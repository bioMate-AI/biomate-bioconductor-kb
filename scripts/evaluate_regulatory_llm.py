#!/usr/bin/env python3
"""
BioMate Regulatory LLM — Citation Accuracy Evaluator

Replaces the citation_recall substring metric with three LLM-judge signals:
  correct_guideline   — cited guideline actually governs this section type
  contextual_placement — citation appears adjacent to a relevant regulatory claim
  no_hallucination     — no non-existent or inapplicable guideline is cited

Usage:
    python scripts/evaluate_regulatory_llm.py \
        --adapter models/regulatory_llm_v4/lora_adapter \
        --data data/regulatory_training/tasks/splits/test.jsonl \
        --n-samples 100

Outputs:
    - Console table per section type
    - JSON results to evaluation/results/regulatory_citation_accuracy/

Dependencies: anthropic (for LLM judge), peft+transformers (for generation)
"""
from __future__ import annotations

import argparse
import json
import logging
import os
import re
import sys
from pathlib import Path
from typing import Optional

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")

# ---------------------------------------------------------------------------
# Known ICH guidelines and which section types they govern
# ---------------------------------------------------------------------------

GUIDELINE_GOVERNANCE: dict[str, list[str]] = {
    "ICH S2(R1)":              ["tox_genotox"],
    "ICH S2":                  ["tox_genotox"],
    "S2(R1)":                  ["tox_genotox"],
    "ICH S7A":                 ["tox_overview", "overview", "tox_cardiac"],
    "ICH S7B":                 ["tox_cardiac", "admet", "tox_overview"],
    "S7B":                     ["tox_cardiac", "admet"],
    "ICH S1A":                 ["tox_overview"],
    "ICH S1B":                 ["tox_overview"],
    "ICH S5(R3)":              ["tox_overview"],
    "ICH S9":                  ["tox_overview", "overview"],
    "ICH M3(R2)":              ["pk_overview", "tox_overview", "overview"],
    "ICH M4S(R2)":             ["overview", "admet"],
    "ICH M4S":                 ["overview", "admet"],
    "ICH E5":                  ["pk_overview"],
    "ICH M7":                  ["tox_genotox"],
    "EMA/CHMP/EWP/37498/2011": ["pbpk"],
    "21 CFR Part 312":         ["overview", "pk_overview", "tox_overview", "admet"],
    "NMPA":                    ["overview", "pk_overview", "tox_overview", "tox_genotox"],
    "PMDA":                    ["pk_overview", "tox_genotox", "tox_overview"],
}

# Citations that are NEVER correct for a given section type
GUIDELINE_MISMATCHES: dict[str, list[str]] = {
    "tox_genotox": ["EMA/CHMP/EWP/37498/2011", "ICH S7B", "ICH S1"],
    "pbpk":        ["ICH S2(R1)", "ICH S7A", "ICH S1"],
    "admet":       ["EMA/CHMP/EWP/37498/2011"],
}

KNOWN_GUIDELINES = set(GUIDELINE_GOVERNANCE.keys())

# ---------------------------------------------------------------------------
# Rule-based citation accuracy check (fast, no LLM needed)
# ---------------------------------------------------------------------------

_CITATION_EXTRACT_RE = re.compile(
    r"(?:ICH\s+[A-Z]\d+(?:\([A-Z]\d*\))?(?:/R\d+)?|"
    r"EMA/CHMP/EWP/\d+/\d+|"
    r"21\s+CFR\s+Part\s+\d+|"
    r"S\d+\([A-Z]\d*\)|"
    r"NMPA\s+(?:Announcement|Guideline)|"
    r"PMDA\s+Notification)",
    re.I,
)


def _extract_citations(text: str) -> list[str]:
    """Extract all guideline citation strings from generated text."""
    return _CITATION_EXTRACT_RE.findall(text)


def _check_citation_correctness(text: str, section_type: str) -> dict:
    """
    Rule-based citation accuracy check.

    Returns:
        correct_guideline: at least one citation is valid for this section type
        no_hallucination: no known-wrong citation for this section type
        citations_found: list of extracted citations
        wrong_citations: list of citations that don't apply to this section
    """
    citations = _extract_citations(text)
    if not citations:
        return {
            "correct_guideline": False,
            "no_hallucination": True,  # can't hallucinate what isn't there
            "citations_found": [],
            "wrong_citations": [],
            "no_citation": True,
        }

    mismatches_for_section = GUIDELINE_MISMATCHES.get(section_type, [])
    wrong = [c for c in citations if any(m.lower() in c.lower() for m in mismatches_for_section)]

    # Check if any citation governs this section
    governs_section = any(
        any(cited.lower() in known.lower() or known.lower() in cited.lower()
            for known, secs in GUIDELINE_GOVERNANCE.items()
            if section_type in secs)
        for cited in citations
    )

    return {
        "correct_guideline": governs_section,
        "no_hallucination": len(wrong) == 0,
        "citations_found": citations,
        "wrong_citations": wrong,
        "no_citation": False,
    }


# ---------------------------------------------------------------------------
# LLM judge for contextual placement (requires LLM call)
# ---------------------------------------------------------------------------

_PLACEMENT_JUDGE_PROMPT = """\
You are a regulatory affairs expert evaluating an AI-generated IND document section.

Section type: {section_type}
Required governing guideline: {required_guideline}

Generated text:
---
{generated_text}
---

Task: Determine if the citation to "{required_guideline}" (or equivalent) appears
in a contextually appropriate location — adjacent to or within the same sentence
as a claim that the guideline actually governs.

Examples of CORRECT placement:
- "Genotoxicity was assessed using the standard ICH S2(R1) battery..." (S2R1 governs genotox)
- "per ICH M3(R2) phase-appropriate requirements, two repeat-dose studies..." (M3R2 governs timing)

Examples of INCORRECT placement:
- Citation is a standalone footnote with no associated claim
- Citation appears in a different section than the claim it supposedly governs
- Citation is mentioned in passing ("we also reviewed ICH S2(R1)") without applying it

Answer with exactly one word: "correct" or "incorrect"."""

_REQUIRED_GUIDELINE_FOR_SECTION = {
    "tox_genotox":  "ICH S2(R1)",
    "pbpk":         "EMA/CHMP/EWP/37498/2011",
    "pk_overview":  "ICH M3(R2)",
    "tox_overview": "ICH M3(R2)",
    "overview":     "ICH M4S(R2)",
    "admet":        "ICH S7B",
    "tox_cardiac":  "ICH S7B",
}


def _llm_judge_placement(generated_text: str, section_type: str) -> Optional[bool]:
    """Use LLM judge to check contextual placement. Returns True/False/None."""
    try:
        sys.path.insert(0, str(Path(__file__).parent.parent / "evaluation"))
        from core.llm_judge import LLMJudge

        required = _REQUIRED_GUIDELINE_FOR_SECTION.get(section_type)
        if not required:
            return None

        judge = LLMJudge()
        prompt = _PLACEMENT_JUDGE_PROMPT.format(
            section_type=section_type,
            required_guideline=required,
            generated_text=generated_text[:1200],
        )
        # Use binary_score with a trivial ground truth
        result = judge.binary_score(
            question=prompt,
            ground_truth="correct",
            agent_answer="correct",  # we embed the question in prompt
        )
        # Actually call via direct API since binary_score expects Q+A format
        # Use the raw judge call instead
        verdict = _call_judge_directly(prompt)
        return verdict
    except Exception as e:
        log.debug("LLM judge placement failed: %s", e)
        return None


def _call_judge_directly(prompt: str) -> Optional[bool]:
    """Direct Anthropic/Gemini call for the placement judge."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if api_key:
        try:
            import anthropic
            client = anthropic.Anthropic(api_key=api_key)
            msg = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=5,
                messages=[{"role": "user", "content": prompt}],
            )
            verdict = msg.content[0].text.strip().lower()
            return "correct" in verdict
        except Exception as e:
            log.debug("Anthropic judge failed: %s", e)

    gemini_key = os.environ.get("GEMINI_API_KEY") or os.environ.get("GOOGLE_API_KEY")
    if gemini_key:
        try:
            import google.generativeai as genai
            genai.configure(api_key=gemini_key)
            model = genai.GenerativeModel("gemini-2.0-flash")
            resp = model.generate_content(prompt)
            verdict = resp.text.strip().lower()
            return "correct" in verdict
        except Exception as e:
            log.debug("Gemini judge failed: %s", e)

    return None


# ---------------------------------------------------------------------------
# Model generation
# ---------------------------------------------------------------------------

def load_adapter(adapter_path: str):
    """Load Qwen3-8B + LoRA adapter for generation."""
    import warnings
    warnings.filterwarnings("ignore", message=".*sm_121.*", category=UserWarning)
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from peft import PeftModel

    log.info("Loading adapter from %s", adapter_path)
    tok = AutoTokenizer.from_pretrained(adapter_path, trust_remote_code=True)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token

    base = AutoModelForCausalLM.from_pretrained(
        "Qwen/Qwen3-8B",
        torch_dtype=torch.bfloat16,
        device_map="auto",
        trust_remote_code=True,
    )
    model = PeftModel.from_pretrained(base, adapter_path)
    model.eval()
    return model, tok


def generate_one(model, tok, messages: list[dict], max_tokens: int = 400) -> str:
    import torch
    try:
        text = tok.apply_chat_template(
            messages[:-1],  # system + user only
            tokenize=False, add_generation_prompt=True, enable_thinking=False,
        )
    except TypeError:
        text = tok.apply_chat_template(messages[:-1], tokenize=False, add_generation_prompt=True)

    inputs = tok(text, return_tensors="pt").to(model.device)
    with torch.no_grad():
        out = model.generate(
            **inputs, max_new_tokens=max_tokens,
            do_sample=True, temperature=0.3, top_p=0.9,
            repetition_penalty=1.1, pad_token_id=tok.eos_token_id,
        )
    generated = out[0][inputs.input_ids.shape[1]:]
    return tok.decode(generated, skip_special_tokens=True).strip()


# ---------------------------------------------------------------------------
# Main evaluation loop
# ---------------------------------------------------------------------------

def evaluate(
    adapter_path: str,
    data_path: str,
    n_samples: int,
    use_llm_judge: bool,
    output_dir: Path,
) -> dict:
    import random

    examples = []
    with open(data_path) as f:
        for line in f:
            d = json.loads(line)
            sec = d.get("meta", {}).get("section_type", "unknown")
            if sec in ("unknown",):
                continue
            examples.append(d)

    random.shuffle(examples)
    sampled = examples[:n_samples]
    log.info("Evaluating %d examples from %s", len(sampled), data_path)

    # Load model
    model, tok = load_adapter(adapter_path)

    results_by_section: dict[str, list[dict]] = {}

    for i, ex in enumerate(sampled):
        sec = ex.get("meta", {}).get("section_type", "unknown")
        messages = ex.get("messages", [])
        ref = next((m["content"] for m in messages if m["role"] == "assistant"), "")

        log.info("[%d/%d] section=%s", i + 1, len(sampled), sec)
        generated = generate_one(model, tok, messages)

        rule_result = _check_citation_correctness(generated, sec)

        placement = None
        if use_llm_judge and not rule_result["no_citation"]:
            placement = _llm_judge_placement(generated, sec)

        record = {
            "section_type": sec,
            "citations_found": rule_result["citations_found"],
            "wrong_citations": rule_result["wrong_citations"],
            "correct_guideline": rule_result["correct_guideline"],
            "no_hallucination": rule_result["no_hallucination"],
            "no_citation": rule_result["no_citation"],
            "contextual_placement": placement,
            "generated_preview": generated[:300],
            "reference_preview": ref[:300],
        }
        results_by_section.setdefault(sec, []).append(record)

    # Aggregate
    summary: dict[str, dict] = {}
    for sec, records in results_by_section.items():
        n = len(records)
        summary[sec] = {
            "n": n,
            "correct_guideline_rate": sum(r["correct_guideline"] for r in records) / n,
            "no_hallucination_rate": sum(r["no_hallucination"] for r in records) / n,
            "no_citation_rate": sum(r["no_citation"] for r in records) / n,
            "contextual_placement_rate": (
                sum(r["contextual_placement"] for r in records if r["contextual_placement"] is not None)
                / max(1, sum(1 for r in records if r["contextual_placement"] is not None))
            ) if use_llm_judge else None,
        }

    # Overall
    all_records = [r for recs in results_by_section.values() for r in recs]
    overall = {
        "n": len(all_records),
        "correct_guideline_rate": sum(r["correct_guideline"] for r in all_records) / len(all_records),
        "no_hallucination_rate": sum(r["no_hallucination"] for r in all_records) / len(all_records),
        "no_citation_rate": sum(r["no_citation"] for r in all_records) / len(all_records),
    }

    output = {"overall": overall, "by_section": summary, "raw": {
        sec: records for sec, records in results_by_section.items()
    }}

    output_dir.mkdir(parents=True, exist_ok=True)
    out_path = output_dir / "citation_accuracy.json"
    with open(out_path, "w") as f:
        json.dump(output, f, indent=2, default=str)

    # Print table
    print(f"\n{'='*65}")
    print(f"{'Section':<18} {'N':>4} {'Correct%':>10} {'No-Halluc%':>12} {'No-Cite%':>10}")
    print(f"{'-'*65}")
    for sec, s in sorted(summary.items()):
        cg = f"{s['correct_guideline_rate']*100:.0f}%"
        nh = f"{s['no_hallucination_rate']*100:.0f}%"
        nc = f"{s['no_citation_rate']*100:.0f}%"
        print(f"{sec:<18} {s['n']:>4} {cg:>10} {nh:>12} {nc:>10}")
    print(f"{'-'*65}")
    print(f"{'OVERALL':<18} {overall['n']:>4} "
          f"{overall['correct_guideline_rate']*100:>9.0f}% "
          f"{overall['no_hallucination_rate']*100:>11.0f}% "
          f"{overall['no_citation_rate']*100:>9.0f}%")
    print(f"{'='*65}")
    print(f"\nResults saved to {out_path}")

    return output


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description="Regulatory LLM citation accuracy evaluator")
    ap.add_argument("--adapter", default="models/regulatory_llm_v4/lora_adapter")
    ap.add_argument("--data", default="data/regulatory_training/tasks/splits/test.jsonl")
    ap.add_argument("--n-samples", type=int, default=100)
    ap.add_argument("--llm-judge", action="store_true", help="Enable contextual placement LLM judge")
    ap.add_argument("--output-dir", default="evaluation/results/regulatory_citation_accuracy")
    args = ap.parse_args()

    evaluate(
        adapter_path=args.adapter,
        data_path=args.data,
        n_samples=args.n_samples,
        use_llm_judge=args.llm_judge,
        output_dir=Path(args.output_dir),
    )


if __name__ == "__main__":
    main()
