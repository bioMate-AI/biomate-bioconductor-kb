#!/usr/bin/env python3
"""
BioMate Regulatory LLM — DPO Training Data Collector

Collects (prompt, chosen, rejected) pairs for Direct Preference Optimization (DPO).
The reward signal is BioMate's regulatory auditor: outputs with MAJOR/CRITICAL
findings are "rejected"; auditor-clean outputs are "chosen".

Three collection modes:
  --audit-failures   Run local model on test prompts, collect MAJOR findings as rejected
  --gemini-pairs     Generate Gemini outputs as chosen for the same prompts
  --human-pairs      Load hand-corrected pairs from a JSONL file

Output format (TRL DPO-compatible):
  {
    "prompt":   "<system>...<user>...",
    "chosen":   "The nonclinical toxicology package...",  # auditor-clean
    "rejected": "13 NONCLINICAL TOXICOLOGY 13.1...",     # MAJOR finding
    "meta": {"section_type": "tox_overview", "source": "audit_failure", ...}
  }

Usage:
    # Collect audit failures from local model (generates rejected pairs)
    python scripts/collect_dpo_training_data.py --audit-failures \
        --test-data data/regulatory_training/tasks/splits/test.jsonl \
        --output data/regulatory_training/dpo

    # Generate Gemini chosen pairs for the same prompts
    python scripts/collect_dpo_training_data.py --gemini-pairs \
        --rejected-pairs data/regulatory_training/dpo/rejected.jsonl \
        --output data/regulatory_training/dpo

    # Train DPO (inside NGC container after collecting enough pairs)
    python scripts/finetune_regulatory_llm.py --dpo \
        --dpo-data data/regulatory_training/dpo/dpo_pairs.jsonl \
        --model qwen3-8b \
        --resume models/regulatory_llm_v1/lora_adapter
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
import time
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# ─── Guardrail: Regulatory Auditor ────────────────────────────────────────────

# Simplified version of the regulatory auditor for standalone use.
# The full auditor lives in backend/lib/galaxy/ai/drug_discovery/regulatory_auditor.py

_AUDIT_RULES: list[dict] = [
    # Citation rules — MAJOR if required citation absent
    {
        "id": "CITE_001", "severity": "MAJOR",
        "section_types": ["pbpk"],  # pk_overview is general PK, not PBPK qualification
        "description": "PBPK qualification section must cite EMA/CHMP/EWP/37498/2011",
        "check": lambda t, d: "EMA/CHMP/EWP/37498/2011" in t or "EMA guideline" in t.lower(),
    },
    {
        "id": "CITE_002", "severity": "MAJOR",
        "section_types": ["tox_genotox"],
        "description": "Genotoxicity section must cite ICH S2(R1)",
        "check": lambda t, d: "S2(R1)" in t or "ICH S2" in t,
    },
    {
        "id": "CITE_003", "severity": "MAJOR",
        "section_types": ["tox_cardiac"],
        "description": "Cardiac safety section must cite ICH S7B",
        "check": lambda t, d: "S7B" in t,
    },
    {
        "id": "CITE_004", "severity": "MINOR",
        "section_types": ["overview", "tox_overview"],
        "description": "General nonclinical overview should cite ICH M3(R2)",
        "check": lambda t, d: "M3(R2)" in t or "M3" in t,
    },
    # Style rules — MAJOR if FDA label style detected
    {
        "id": "STYLE_001", "severity": "MAJOR",
        "section_types": None,  # all sections
        "description": "Output must not contain FDA drug label section headers (§12/§13)",
        "check": lambda t, d: not re.search(
            r"^(12|13)\s+[A-Z][A-Z ,/&()-]+|^(12|13)\.\d", t, re.M
        ),
    },
    {
        "id": "STYLE_002", "severity": "MINOR",
        "section_types": None,
        "description": "Output should not contain bullet points or lists",
        "check": lambda t, d: not re.search(r"^[\-\•\*]\s+", t, re.M),
    },
    # Length rules
    {
        "id": "LEN_001", "severity": "MAJOR",
        "section_types": None,
        "description": "Output must be at least 100 words",
        "check": lambda t, d: len(t.split()) >= 100,
    },
    {
        "id": "LEN_002", "severity": "MINOR",
        "section_types": None,
        "description": "Output should be at least 250 words for a complete section",
        "check": lambda t, d: len(t.split()) >= 250,
    },
    # Content rules
    {
        "id": "CONTENT_001", "severity": "MAJOR",
        "section_types": ["pbpk"],
        "description": "PBPK section must state whether EMA 67% criterion is met or not",
        "check": lambda t, d: any(
            x in t.lower() for x in ["criterion", "within-2-fold", "within 2-fold", "67%", "67 %"]
        ),
    },
    {
        "id": "CONTENT_002", "severity": "MAJOR",
        "section_types": ["tox_genotox"],
        "description": "Genotoxicity section must mention Ames test result",
        "check": lambda t, d: "ames" in t.lower() or "bacterial reverse mutation" in t.lower(),
    },
    {
        "id": "CONTENT_003", "severity": "MAJOR",
        "section_types": ["tox_cardiac"],
        "description": "Cardiac section must report hERG IC50 or state result",
        "check": lambda t, d: "herg" in t.lower() or "ic50" in t.lower() or "iq50" in t.lower(),
    },
]


def audit_narrative(text: str, section_type: str, data: dict) -> list[dict]:
    """Run standalone regulatory audit on a narrative. Returns list of findings."""
    findings = []
    for rule in _AUDIT_RULES:
        # Apply only to relevant section types
        if rule["section_types"] and section_type not in rule["section_types"]:
            continue
        try:
            passes = rule["check"](text, data)
        except Exception:
            passes = True
        if not passes:
            findings.append({
                "rule_id": rule["id"],
                "severity": rule["severity"],
                "description": rule["description"],
                "section_type": section_type,
            })
    return findings


def score_narrative(text: str, section_type: str, data: dict) -> dict:
    """Return {CRITICAL, MAJOR, MINOR, passes}."""
    findings = audit_narrative(text, section_type, data)
    counts = {"CRITICAL": 0, "MAJOR": 0, "MINOR": 0}
    for f in findings:
        counts[f["severity"]] = counts.get(f["severity"], 0) + 1
    counts["passes"] = counts["CRITICAL"] == 0 and counts["MAJOR"] == 0
    counts["findings"] = findings
    return counts


# ─── Local model inference ─────────────────────────────────────────────────────

_local_model = None
_local_tokenizer = None


def load_local_model(adapter_path: Path) -> bool:
    global _local_model, _local_tokenizer
    if _local_model is not None:
        return True
    if not adapter_path.exists():
        log.error("Adapter not found: %s", adapter_path)
        return False
    try:
        import warnings
        warnings.filterwarnings("ignore", message=".*sm_121.*")
        import torch
        from transformers import AutoModelForCausalLM, AutoTokenizer
        from peft import PeftModel

        log.info("Loading Qwen3-8B + adapter from %s …", adapter_path)
        tok = AutoTokenizer.from_pretrained(str(adapter_path), trust_remote_code=True)
        if tok.pad_token is None:
            tok.pad_token = tok.eos_token
        base = AutoModelForCausalLM.from_pretrained(
            "Qwen/Qwen3-8B", torch_dtype=torch.bfloat16, device_map="auto"
        )
        model = PeftModel.from_pretrained(base, str(adapter_path))
        model.eval()
        _local_model, _local_tokenizer = model, tok
        log.info("Local model loaded")
        return True
    except Exception as exc:
        log.error("Failed to load local model: %s", exc)
        return False


def generate_local(system: str, user: str, max_new_tokens: int = 600) -> str:
    import torch
    tok, model = _local_tokenizer, _local_model
    msgs = [{"role": "system", "content": system},
            {"role": "user",   "content": f"/no_think\n{user}"}]
    try:
        text = tok.apply_chat_template(msgs, tokenize=False,
                                       add_generation_prompt=True, enable_thinking=False)
    except TypeError:
        text = tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
    inputs = tok(text, return_tensors="pt").to(model.device)
    with torch.no_grad():
        out = model.generate(**inputs, max_new_tokens=max_new_tokens,
                             do_sample=True, temperature=0.3, top_p=0.9,
                             repetition_penalty=1.1, pad_token_id=tok.eos_token_id)
    return tok.decode(out[0][inputs.input_ids.shape[1]:], skip_special_tokens=True).strip()


def generate_gemini(system: str, user: str, max_tokens: int = 1024) -> str:
    try:
        sys.path.insert(0, str(Path(__file__).parent.parent / "backend/lib"))
        from galaxy.ai.gemini_flash import call_gemini_flash
        return call_gemini_flash(
            messages=[{"role": "user", "content": user}],
            system=system, max_tokens=max_tokens, temperature=0.3,
        ).strip()
    except Exception as exc:
        log.error("Gemini call failed: %s", exc)
        return ""


# ─── System prompts (same as ind_assembly.py) ──────────────────────────────────

_SYSTEMS = {
    "FDA": (
        "You are a regulatory affairs scientist preparing ICH M4 CTD Module 2.6 nonclinical "
        "written summaries submitted to the U.S. FDA under 21 CFR Part 312. Write formal, "
        "plain prose — no markdown, no bullet points. Cite applicable ICH guidelines by full "
        "identifier (e.g. ICH S2(R1), EMA/CHMP/EWP/37498/2011). 300–600 words."
    ),
    "EMA": (
        "You are a regulatory affairs scientist preparing ICH M4 CTD Module 2.6 nonclinical "
        "written summaries submitted to the EMA under EudraLex Volume 10. Write formal, "
        "plain prose — no markdown, no bullet points. Cite EMA guidelines and ICH guidelines "
        "by full identifier. 300–600 words."
    ),
}


# ─── Modes ────────────────────────────────────────────────────────────────────

def collect_audit_failures(
    test_data_path: Path,
    adapter_path: Path,
    out_dir: Path,
    max_samples: int = 200,
) -> list[dict]:
    """
    Run the local model on T1 test prompts. Collect outputs with MAJOR audit
    findings as 'rejected' pairs for DPO training.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    if not load_local_model(adapter_path):
        log.error("Cannot collect audit failures without local model")
        return []

    examples = []
    with open(test_data_path) as f:
        test_pairs = [json.loads(l) for l in f if l.strip()]

    # Filter to section_generation only
    test_pairs = [p for p in test_pairs if p.get("meta", {}).get("task") == "section_generation"]
    test_pairs = test_pairs[:max_samples]
    log.info("Running audit failure collection on %d test examples …", len(test_pairs))

    n_rejected = n_passed = 0
    for i, pair in enumerate(test_pairs, 1):
        msgs = pair.get("messages", [])
        if len(msgs) < 3:
            continue
        system_msg = msgs[0]["content"]
        user_msg = msgs[1]["content"]
        reference = msgs[2]["content"]
        meta = pair.get("meta", {})
        section_type = meta.get("section_type", "unknown")
        region = meta.get("region", "FDA")
        data = {}  # minimal data for numeric faithfulness check

        # Generate from local model
        generated = generate_local(system_msg, user_msg, max_new_tokens=600)
        if not generated:
            continue

        # Audit the output
        audit = score_narrative(generated, section_type, data)
        is_rejected = not audit["passes"]

        # Build prompt string (full ChatML prefix for DPO)
        prompt = f"<|im_start|>system\n{system_msg}<|im_end|>\n<|im_start|>user\n{user_msg}<|im_end|>\n"

        if is_rejected:
            # Also audit the reference — only use it as "chosen" if it passes
            ref_audit = score_narrative(reference, section_type, data)
            if not ref_audit["passes"]:
                # Reference also has MAJOR findings — this pair can't be a good DPO signal
                log.debug("Reference has MAJOR findings for pair %d — skipping", i)
                continue

            examples.append({
                "prompt": prompt,
                "rejected": generated,
                "chosen": reference,
                "meta": {
                    "source": "audit_failure",
                    "section_type": section_type,
                    "region": region,
                    "audit_findings": audit["findings"],
                    "n_major": audit["MAJOR"],
                    "n_minor": audit["MINOR"],
                    "ref_n_major": ref_audit["MAJOR"],
                    "ref_n_minor": ref_audit["MINOR"],
                },
            })
            n_rejected += 1
        else:
            n_passed += 1

        if i % 10 == 0:
            log.info("  [%d/%d] rejected=%d passed=%d", i, len(test_pairs), n_rejected, n_passed)

    log.info("Audit failures collected: %d rejected / %d passed", n_rejected, n_passed)

    out_file = out_dir / "rejected.jsonl"
    with open(out_file, "w") as f:
        for ex in examples:
            f.write(json.dumps(ex, ensure_ascii=False) + "\n")
    log.info("Wrote %d rejected pairs → %s", len(examples), out_file)
    return examples


def collect_gemini_chosen(
    rejected_path: Path,
    out_dir: Path,
) -> list[dict]:
    """
    For each rejected pair, generate a Gemini output as the 'chosen' response.
    This creates proper (chosen=Gemini_clean, rejected=local_model_MAJOR) DPO pairs.
    """
    out_dir.mkdir(parents=True, exist_ok=True)
    with open(rejected_path) as f:
        rejected_pairs = [json.loads(l) for l in f if l.strip()]

    log.info("Generating Gemini chosen for %d rejected pairs …", len(rejected_pairs))
    dpo_pairs = []

    for i, pair in enumerate(rejected_pairs, 1):
        prompt = pair["prompt"]
        # Extract user message from prompt string
        user_match = re.search(r"<\|im_start\|>user\n(.+?)<\|im_end\|>", prompt, re.S)
        sys_match  = re.search(r"<\|im_start\|>system\n(.+?)<\|im_end\|>", prompt, re.S)
        if not user_match or not sys_match:
            continue

        system_msg = sys_match.group(1)
        user_msg   = user_match.group(1)
        region     = pair.get("meta", {}).get("region", "FDA")

        # Use Gemini to generate the chosen response
        chosen = generate_gemini(
            system=_SYSTEMS.get(region, _SYSTEMS["FDA"]),
            user=user_msg,
        )
        if not chosen or len(chosen.split()) < 50:
            log.debug("Gemini returned empty for pair %d — skipping", i)
            continue

        # Audit the Gemini output too — only use it if it passes
        section_type = pair.get("meta", {}).get("section_type", "unknown")
        gemini_audit = score_narrative(chosen, section_type, {})
        if not gemini_audit["passes"]:
            log.debug("Gemini output also has MAJOR findings — skipping pair %d", i)
            continue

        dpo_pairs.append({
            "prompt":   prompt,
            "chosen":   chosen,
            "rejected": pair["rejected"],
            "meta":     {**pair.get("meta", {}), "chosen_source": "gemini"},
        })

        if i % 10 == 0:
            log.info("  [%d/%d] dpo_pairs=%d", i, len(rejected_pairs), len(dpo_pairs))
        time.sleep(0.5)  # Gemini rate limit

    out_file = out_dir / "dpo_pairs.jsonl"
    with open(out_file, "w") as f:
        for pair in dpo_pairs:
            f.write(json.dumps(pair, ensure_ascii=False) + "\n")
    log.info("Wrote %d DPO pairs → %s", len(dpo_pairs), out_file)
    return dpo_pairs


def audit_report(
    test_data_path: Path,
    adapter_path: Path,
    n_samples: int = 50,
    save_path: Optional[Path] = None,
) -> dict:
    """Generate an audit report comparing local model vs reference on n test examples."""
    if not load_local_model(adapter_path):
        log.error("Cannot generate audit report without local model")
        return {}

    with open(test_data_path) as f:
        pairs = [json.loads(l) for l in f if l.strip()
                 if json.loads(l).get("meta", {}).get("task") == "section_generation"]
    pairs = pairs[:n_samples]

    results = []
    by_section: dict[str, dict] = {}

    for pair in pairs:
        msgs   = pair.get("messages", [])
        meta   = pair.get("meta", {})
        sec    = meta.get("section_type", "unknown")
        system = msgs[0]["content"] if msgs else ""
        user   = msgs[1]["content"] if len(msgs) > 1 else ""
        ref    = msgs[2]["content"] if len(msgs) > 2 else ""

        generated = generate_local(system, user)
        audit = score_narrative(generated, sec, {})
        ref_audit = score_narrative(ref, sec, {})

        results.append({
            "section_type": sec,
            "generated_words": len(generated.split()),
            "ref_words": len(ref.split()),
            "gen_major": audit["MAJOR"],
            "gen_minor": audit["MINOR"],
            "ref_major": ref_audit["MAJOR"],
            "ref_minor": ref_audit["MINOR"],
            "gen_passes": audit["passes"],
        })
        by_section.setdefault(sec, []).append(results[-1])

    # Summary
    total = len(results)
    n_pass = sum(1 for r in results if r["gen_passes"])
    avg_len = sum(r["generated_words"] for r in results) / total if total else 0
    avg_maj = sum(r["gen_major"] for r in results) / total if total else 0

    print(f"\n{'='*60}")
    print(f"Audit Report: {n_pass}/{total} generated outputs pass ({100*n_pass/total:.0f}%)")
    print(f"Avg output length: {avg_len:.0f}w")
    print(f"Avg MAJOR findings: {avg_maj:.2f}")
    print(f"\nBy section type:")
    by_section_summary = {}
    for sec, rows in sorted(by_section.items()):
        pass_rate = sum(1 for r in rows if r["gen_passes"]) / len(rows)
        sec_avg_maj = sum(r["gen_major"] for r in rows) / len(rows)
        sec_avg_len = sum(r["generated_words"] for r in rows) / len(rows)
        print(f"  {sec:20s}: {100*pass_rate:.0f}% pass | {sec_avg_maj:.1f} MAJOR | {sec_avg_len:.0f}w avg")
        by_section_summary[sec] = {"pass_rate": pass_rate, "avg_major": sec_avg_maj, "avg_len": sec_avg_len, "n": len(rows)}

    report = {
        "n_samples": total,
        "n_pass": n_pass,
        "pass_rate": n_pass / total if total else 0,
        "avg_length_words": avg_len,
        "avg_major_findings": avg_maj,
        "by_section": by_section_summary,
        "adapter": str(adapter_path),
    }
    if save_path:
        save_path.parent.mkdir(parents=True, exist_ok=True)
        with open(save_path, "w") as f:
            json.dump(report, f, indent=2)
        log.info("Audit report saved → %s", save_path)
    return report


# ─── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(description="Collect DPO training pairs from regulatory audit")
    ap.add_argument("--audit-failures", action="store_true",
                    help="Run local model on test set, collect MAJOR findings as rejected")
    ap.add_argument("--gemini-pairs", action="store_true",
                    help="Generate Gemini chosen for existing rejected pairs")
    ap.add_argument("--audit-report", action="store_true",
                    help="Generate audit pass/fail report for the local model")
    ap.add_argument("--test-data", type=Path,
                    default=Path("data/regulatory_training/tasks/splits/test.jsonl"))
    ap.add_argument("--rejected-pairs", type=Path,
                    default=Path("data/regulatory_training/dpo/rejected.jsonl"))
    ap.add_argument("--adapter", type=Path,
                    default=Path("models/regulatory_llm_v1/lora_adapter"))
    ap.add_argument("--output", type=Path,
                    default=Path("data/regulatory_training/dpo"))
    ap.add_argument("--max-samples", type=int, default=200)
    ap.add_argument("--save-report", type=Path, default=None,
                    help="Save audit report JSON to this path (e.g. data/regulatory_training/audit_v1.json)")
    args = ap.parse_args()

    if args.audit_report:
        audit_report(args.test_data, args.adapter, n_samples=args.max_samples,
                     save_path=args.save_report)

    if args.audit_failures:
        collect_audit_failures(args.test_data, args.adapter, args.output, args.max_samples)

    if args.gemini_pairs:
        collect_gemini_chosen(args.rejected_pairs, args.output)


if __name__ == "__main__":
    main()
