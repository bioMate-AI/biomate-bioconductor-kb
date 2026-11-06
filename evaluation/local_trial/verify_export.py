#!/usr/bin/env python3
"""Export-and-verify gate — reload an exported adapter in a FRESH process, prove it
is non-degenerate, and BLOCK promotion (nonzero exit) on failure.

Why this exists
---------------
A successful training *exit* is NOT proof that the serialized adapter reloads and
generates real text. BioMate shipped a silently-broken adapter on 2026-10-07; the
training job exited 0 and the artifact was promoted anyway. Three partial guards
already existed but none BLOCKS promotion automatically right after export:

  * pre-save degeneracy heuristic         — train_qlora_pilot.py (train-metric only, pre-save)
  * adapter-changes-logits sanity          — eval_holdout.py (eval-time, not a deploy gate)
  * served non-degenerate smoke            — smoke_sft_gold.py (MANUAL, endpoint-based, post-deploy)

This consolidates them into ONE automatic step (modeled on ScienceBuddy
coevolve/worker.py's load-check): reload the exported checkpoint, assert the adapter
changes behavior, assert every probe generation is non-degenerate, else exit nonzero
so the caller never uploads/serves the artifact.

Usage
-----
  CPU self-test of the degeneracy contract (no model load, no GPU):
      python3 verify_export.py --selftest
  Gate in the promote path (GPU), BEFORE `aws s3 cp` of the adapter:
      python3 verify_export.py --base "$BASE" --adapter "$OUT" || exit 1

Exit codes: 0 = PASS (safe to promote); 31 = BLOCKED (degenerate / no-effect adapter);
2 = usage error.
"""
import argparse
import json
import sys
from collections import Counter

# Default probes mirror smoke_sft_gold.py (a terse decomposition list + a bounded
# findings narration) so "verified before deploy" matches "smoke-tested after deploy".
PROBES = [
    ("decomposition",
     "Decompose this bioinformatics request into an ordered list of subtasks "
     "(one per line, terse): 'Call somatic variants from matched tumor/normal "
     "WGS FASTQs and annotate functional impact.'"),
    ("findings",
     "You are a bioinformatics scientist. In 3-5 sentences, summarize the key "
     "findings from this RNA-seq result: 1,284 genes differentially expressed "
     "(FDR<0.05), 812 up / 472 down; top enriched pathway: oxidative "
     "phosphorylation (padj=3e-7); PCA separates treated vs control on PC1 (61% var)."),
    ("routing",
     "Name the single most appropriate workflow for: 'align paired-end bulk RNA-seq "
     "reads to GRCh38 and quantify gene expression'. Answer with the workflow name only."),
]


def classify_generation(text, *, min_chars=12, min_unique_chars=4,
                        max_token_repeat_ratio=0.5, min_tokens_for_repeat=6):
    """The non-degenerate contract for ONE generation. Pure + CPU-only so it is unit
    testable without loading a model. Returns (ok: bool, reasons: list[str])."""
    reasons = []
    s = (text or "").strip()
    if not s:
        return False, ["empty"]
    if len(s) < min_chars:
        reasons.append(f"too_short(<{min_chars}c)")
    if len(set(s)) < min_unique_chars:
        reasons.append(f"low_char_diversity(<{min_unique_chars})")  # "aaaa", "....."
    if not any(c.isalnum() for c in s):
        reasons.append("no_alphanumeric")
    toks = s.split()
    if len(toks) >= min_tokens_for_repeat:
        top = Counter(toks).most_common(1)[0][1]
        if top / len(toks) > max_token_repeat_ratio:
            reasons.append(f"token_repetition(>{max_token_repeat_ratio:.0%})")
    return (len(reasons) == 0), reasons


def _selftest():
    """Assert the contract flags degenerate text and passes real text. CPU-only."""
    good = [
        "1. Align tumor/normal FASTQs\n2. Call somatic variants (Mutect2)\n3. Annotate (VEP)",
        "Expression is dominated by oxidative phosphorylation (padj=3e-7); 812 genes up and 472 "
        "down separate treated from control on PC1.",
        "nf-core/rnaseq",
    ]
    bad = {
        "empty": "   ",
        "single_char": "aaaaaaaaaaaaaaaaaaaa",
        "punct_only": "......................",
        "repetition": "the the the the the the the the the the the the",
        "too_short": "ok",
    }
    failures = []
    for i, g in enumerate(good):
        ok, reasons = classify_generation(g)
        if not ok:
            failures.append(f"good[{i}] wrongly flagged: {reasons} :: {g[:50]!r}")
    for name, b in bad.items():
        ok, reasons = classify_generation(b)
        if ok:
            failures.append(f"bad[{name}] not flagged: {b[:40]!r}")
    if failures:
        print("SELFTEST FAIL")
        for f in failures:
            print("  -", f)
        return 1
    print(f"SELFTEST PASS ({len(good)} good accepted, {len(bad)} degenerate rejected)")
    return 0


def _run_gate(args):
    # Heavy imports live here so --selftest needs no torch/transformers/GPU.
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import PeftModel

    tok = AutoTokenizer.from_pretrained(args.base, trust_remote_code=True)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                             bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=torch.bfloat16)
    model = AutoModelForCausalLM.from_pretrained(
        args.base, quantization_config=bnb, device_map="auto", torch_dtype=torch.bfloat16,
        trust_remote_code=True, low_cpu_mem_usage=True)
    model = PeftModel.from_pretrained(model, args.adapter)
    model.eval()

    # Guard 1 (from eval_holdout.py): the adapter must actually change the logits.
    # enabled==disabled means a silent no-op adapter (wrong path, quant mismatch) — the
    # exact failure the 2026-10-07 deploy hit. Block, don't promote.
    with torch.no_grad():
        probe = tok("BioMate workflow for RNA-seq differential expression:", return_tensors="pt")
        probe = {k: v.to(model.device) for k, v in probe.items()}
        l_adp = model(**probe).logits[0, -1].float()
        with model.disable_adapter():
            l_base = model(**probe).logits[0, -1].float()
    dmax = (l_adp - l_base).abs().max().item()

    def gen(prompt, base=False):
        enc = tok.apply_chat_template([{"role": "user", "content": prompt}],
                                      add_generation_prompt=True, return_tensors="pt",
                                      return_dict=True)
        enc = {k: v.to(model.device) for k, v in enc.items()}
        in_len = enc["input_ids"].shape[1]
        ctx = model.disable_adapter() if base else _nullctx()
        with torch.no_grad(), ctx:
            out = model.generate(**enc, max_new_tokens=args.max_new_tokens, do_sample=False,
                                 pad_token_id=tok.pad_token_id)
        return tok.decode(out[0][in_len:], skip_special_tokens=True)

    report = {"base": args.base, "adapter": args.adapter, "logit_delta_max": dmax, "probes": []}
    blocked = []
    if dmax < args.min_logit_delta:
        blocked.append(f"adapter_no_effect(max|Δ|={dmax:.2e}<{args.min_logit_delta:.0e})")

    differs = 0
    for name, prompt in PROBES:
        adp_text = gen(prompt, base=False)
        ok, reasons = classify_generation(adp_text)
        base_text = gen(prompt, base=True)
        changed = adp_text.strip() != base_text.strip()
        differs += int(changed)
        report["probes"].append({"probe": name, "ok": ok, "reasons": reasons,
                                 "changed_vs_base": changed, "len": len(adp_text.strip()),
                                 "text_head": adp_text.strip()[:200]})
        if not ok:
            blocked.append(f"{name}:{','.join(reasons)}")

    # Guard 3: behaviour must change on at least one probe (logits differing but identical
    # greedy text would still be a near-useless promotion).
    if differs == 0:
        blocked.append("no_probe_output_differs_from_base")

    report["blocked_reasons"] = blocked
    report["verdict"] = "PASS" if not blocked else "BLOCKED"
    if args.out:
        with open(args.out, "w") as f:
            json.dump(report, f, indent=2)
    print(json.dumps({k: report[k] for k in ("logit_delta_max", "verdict", "blocked_reasons")}, indent=2))
    if blocked:
        print("EXPORT GATE BLOCKED — not safe to promote:", "; ".join(blocked), file=sys.stderr)
        return 31
    print(f"EXPORT GATE PASS — adapter reloads, changes behaviour, non-degenerate "
          f"(max|Δ|={dmax:.4f}, {differs}/{len(PROBES)} probes differ from base).")
    return 0


class _nullctx:
    def __enter__(self): return None
    def __exit__(self, *a): return False


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true", help="CPU-only contract test; no model load")
    ap.add_argument("--base", help="base model path/id the adapter was trained on")
    ap.add_argument("--adapter", help="exported adapter dir to gate before promotion")
    ap.add_argument("--max-new-tokens", type=int, default=96)
    ap.add_argument("--min-logit-delta", type=float, default=1e-4)
    ap.add_argument("--out", default="", help="optional JSON report path")
    args = ap.parse_args()
    if args.selftest:
        return _selftest()
    if not args.base or not args.adapter:
        ap.error("--base and --adapter are required unless --selftest")
    return _run_gate(args)


if __name__ == "__main__":
    sys.exit(main())
