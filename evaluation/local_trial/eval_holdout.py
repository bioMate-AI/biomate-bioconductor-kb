#!/usr/bin/env python3
"""In-scope eval: base-27B vs SFT-27B on the held-out RealBio benchmarks.

Loads base (4-bit) + the QLoRA adapter ONCE; scores each held-out item twice —
with the adapter (SFT) and with `disable_adapter()` (base) — for a clean delta.
Scored directly against gold labels (no app stack). Regulatory suite is out of scope.

Scorers (categorical, robust):
  routing  : output must name the correct_workflow (or an acceptable_alt)
  autofix  : output must name the gold fix category
  param_prefill: recall of expected_params values appearing in output
"""
from __future__ import annotations
import argparse, json, re
from pathlib import Path


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


def score_item(bench: str, item: dict, gold: dict, out: str) -> float | None:
    o = norm(out)
    if bench == "cross_domain_routing":
        cw = norm(gold.get("correct_workflow", item.get("correct_workflow", "")))
        alts = [norm(a) for a in (item.get("acceptable_alts") or [])]
        if not cw:
            return None
        return 1.0 if cw and cw in o else (0.5 if any(a and a in o for a in alts) else 0.0)
    if bench == "autofix_benchmark":
        cat = norm(gold.get("category", item.get("category", "")))
        return None if not cat else (1.0 if cat in o else 0.0)
    if bench == "param_prefill":
        exp = gold.get("expected_params", item.get("expected_params", {})) or {}
        if not exp:
            return None
        hit = sum(1 for v in exp.values() if norm(v) and norm(v) in o)
        return hit / len(exp)
    return None


PROMPTS = {
    "cross_domain_routing": lambda it: (
        "You are BioMate. Name the single correct bioinformatics WORKFLOW (e.g. an nf-core "
        "pipeline name) that should run this request. Reply with only the workflow name.\n\n"
        f"Request: {it.get('query','')}"),
    "autofix_benchmark": lambda it: (
        "You are BioMate. A pipeline run failed. Classify the failure into one fix category "
        "(e.g. genome_mismatch, missing_input, resource_limit, container_error, ...). Reply "
        f"with only the category.\n\nWorkflow: {it.get('workflow','')}\nError log:\n{str(it.get('error_log',''))[:1200]}"),
    "param_prefill": lambda it: (
        "You are BioMate. Extract the workflow parameters explicitly implied by this request "
        "as key: value lines. Do not invent unspecified params.\n\n"
        f"Request: {it.get('user_query', it.get('query',''))}"),
}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True)
    ap.add_argument("--adapter", required=True)
    ap.add_argument("--holdout", required=True)
    ap.add_argument("--benchmarks", default="cross_domain_routing,autofix_benchmark,param_prefill")
    ap.add_argument("--limit-per", type=int, default=40)
    ap.add_argument("--out", default="holdout_eval_result.json")
    args = ap.parse_args()

    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import PeftModel

    benches = args.benchmarks.split(",")
    rows = [json.loads(l) for l in open(args.holdout) if l.strip()]
    by = {}
    for r in rows:
        by.setdefault(r["benchmark"], []).append(r)

    tok = AutoTokenizer.from_pretrained(args.base, trust_remote_code=True)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    bnb = BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
                             bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=torch.bfloat16)
    model = AutoModelForCausalLM.from_pretrained(args.base, quantization_config=bnb,
                                                 device_map="auto", torch_dtype=torch.bfloat16,
                                                 trust_remote_code=True, low_cpu_mem_usage=True)
    model = PeftModel.from_pretrained(model, args.adapter)
    model.eval()

    # SANITY GUARD (root-cause of the 20260914 "0.0 delta everywhere" run): verify the adapter
    # actually changes the logits. If enabled==disabled the whole eval is meaningless — a silent
    # no-op adapter reports base==sft and looks like "training didn't help" when it's really a load
    # artifact (wrong adapter path, quantization mismatch, or disable_adapter not toggling). Fail LOUD.
    with torch.no_grad():
        probe = tok("BioMate workflow for RNA-seq differential expression:", return_tensors="pt")
        probe = {k: v.to(model.device) for k, v in probe.items()}
        l_sft = model(**probe).logits[0, -1].float()
        with model.disable_adapter():
            l_base = model(**probe).logits[0, -1].float()
    dmax = (l_sft - l_base).abs().max().item()
    if dmax < 1e-4:
        raise SystemExit(
            f"FATAL: adapter has NO effect on logits (max|Δ|={dmax:.2e}, enabled==disabled).\n"
            "The reported 0.0 delta is an EVAL ARTIFACT, not a real result. Fix before trusting:\n"
            "  - confirm --adapter points at a trained adapter (adapter_model.safetensors non-zero)\n"
            "  - confirm --base matches the base the adapter was trained on (same quantization)\n"
            "  - or use the canonical two-server eval: merge_lora.py + eval_holdout_vllm.py")
    print(f"[sanity] adapter changes logits: max|Δ|={dmax:.4f}  (>1e-4 required) OK")
    identical = 0  # per-item guard: count where base_out==sft_out (should be a minority)

    def gen(prompt: str) -> str:
        msgs = [{"role": "user", "content": prompt}]
        enc = tok.apply_chat_template(msgs, add_generation_prompt=True,
                                      return_tensors="pt", return_dict=True)
        enc = {k: v.to(model.device) for k, v in enc.items()}
        in_len = enc["input_ids"].shape[1]
        with torch.no_grad():
            out = model.generate(**enc, max_new_tokens=64, do_sample=False,
                                 pad_token_id=tok.pad_token_id)
        return tok.decode(out[0][in_len:], skip_special_tokens=True)

    report = {"per_benchmark": {}}
    for b in benches:
        items = by.get(b, [])[: args.limit_per]
        if not items:
            continue
        base_s, sft_s, n = 0.0, 0.0, 0
        for r in items:
            it = r["input_item"]; gold = r.get("ground_truth", {})
            prompt = PROMPTS[b](it)
            # SFT (adapter enabled)
            sft_out = gen(prompt)
            # base (adapter disabled)
            with model.disable_adapter():
                base_out = gen(prompt)
            if norm(base_out) == norm(sft_out):
                identical += 1
            bs = score_item(b, it, gold, base_out)
            ss = score_item(b, it, gold, sft_out)
            if bs is None or ss is None:
                continue
            base_s += bs; sft_s += ss; n += 1
        if n:
            report["per_benchmark"][b] = {"n": n, "base": round(base_s/n, 4),
                                          "sft": round(sft_s/n, 4), "delta": round((sft_s-base_s)/n, 4)}
            print(f"{b}: n={n} base={base_s/n:.3f} sft={sft_s/n:.3f} delta={(sft_s-base_s)/n:+.3f}")
    total = sum(v["n"] for v in report["per_benchmark"].values()) or 1
    frac_identical = identical / total
    report["identical_output_frac"] = round(frac_identical, 3)
    if frac_identical > 0.9:
        print(f"WARNING: {frac_identical:.0%} of items had IDENTICAL base/sft output — the adapter "
              "is barely moving greedy predictions; treat deltas as unreliable and inspect training.")
    Path(args.out).write_text(json.dumps(report, indent=2))
    print("WROTE", args.out, "| identical_output_frac=", round(frac_identical, 3))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
