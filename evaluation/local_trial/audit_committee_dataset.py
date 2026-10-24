#!/usr/bin/env python3
"""Row-level dataset quality audit by a committee of TOP LLMs (via OpenRouter).

Unlike the BRIEF-based committee (which reviews a prose description), this samples ACTUAL rows from
each generated set and has each committee model judge each row against a strict rubric, so it catches
real defects: hallucinated/implausible queries, wrong gold, invalid/too-easy or accidentally-correct
negatives, leakage, degeneracy. Aggregates per-dataset pass-rate + consensus issues.

Committee: claude-opus-5.5, gpt-6.1-sol, deepseek-v4-pro, gemini-3.1-pro (strongest available).
Run:  OPENROUTER_API_KEY=... python3 audit_committee_dataset.py --n 20
"""
from __future__ import annotations
import argparse, json, os, random, re, urllib.request
from collections import defaultdict
from pathlib import Path

KEY = os.environ.get("OPENROUTER_API_KEY") or open(os.path.expanduser("~/.config/biomate/openrouter.key")).read().strip()
MODELS = ["anthropic/claude-opus-5.5", "openai/gpt-6.1-sol", "deepseek/deepseek-v4-pro", "google/gemini-3.1-pro-preview"]
POOL = Path(__file__).resolve().parents[1].parent / "docs" / "20260912_onprem_llm" / "data_pool_v2"
OUT = Path(__file__).resolve().parents[1].parent / "docs" / "20260912_onprem_llm" / "committee_reviews"

RUBRIC_ROUTING = (
    "You are auditing SYNTHETIC training data for a bioinformatics workflow-routing LLM. Each example is "
    "a user `query` and the `gold` workflow filename it should route to. For EACH example judge strictly:\n"
    "- query_realistic: 1 if a real bioinformatician could plausibly type this, else 0 (flag templated/"
    "awkward/hallucinated-specifics).\n"
    "- gold_plausible: 1 if `gold` is a reasonable correct target for the query, else 0 (flag mismatch).\n"
    "- issue: one short phrase, or \"\".\n"
    "Return ONLY a JSON list: [{\"idx\":int,\"query_realistic\":0|1,\"gold_plausible\":0|1,"
    "\"verdict\":\"PASS|WARN|FAIL\",\"issue\":\"...\"}]."
)
RUBRIC_PAIR = (
    "You are auditing SYNTHETIC preference pairs for DPO of a bioinformatics workflow-router. Each has a "
    "`query`, a `chosen` workflow and a `rejected` workflow. For EACH judge strictly:\n"
    "- chosen_correct: 1 if `chosen` is a good target for the query, else 0.\n"
    "- negative_valid: 1 if `rejected` is genuinely WORSE for this query yet plausibly confusable "
    "(same area) — 0 if it is obviously unrelated (too easy) OR could ALSO be correct (mislabeled).\n"
    "- issue: one short phrase, or \"\".\n"
    "Return ONLY a JSON list: [{\"idx\":int,\"chosen_correct\":0|1,\"negative_valid\":0|1,"
    "\"verdict\":\"PASS|WARN|FAIL\",\"issue\":\"...\"}]."
)
RUBRIC_PARAM = (
    "You are auditing SYNTHETIC param-selection training data. Each has a `query`+workflow and `gold` = "
    "the required parameter NAMES to fill (+ `must_not_fill` names that must NOT be filled). For EACH judge:\n"
    "- gold_sensible: 1 if the required names are plausible inputs for that workflow, else 0.\n"
    "- restraint_valid: 1 if the must_not_fill names are plausibly from OTHER workflows (good distractors), else 0.\n"
    "- issue: one short phrase, or \"\".\n"
    "Return ONLY a JSON list: [{\"idx\":int,\"gold_sensible\":0|1,\"restraint_valid\":0|1,"
    "\"verdict\":\"PASS|WARN|FAIL\",\"issue\":\"...\"}]."
)


def _call(model, prompt):
    body = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": 4000, "temperature": 0}
    req = urllib.request.Request("https://openrouter.ai/api/v1/chat/completions",
                                 data=json.dumps(body).encode(),
                                 headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    r = json.load(urllib.request.urlopen(req, timeout=180))
    return r["choices"][0]["message"]["content"] or ""


def _parse(txt):
    m = re.search(r"\[.*\]", txt, re.S)
    if not m:
        return []
    try:
        return json.loads(m.group())
    except Exception:
        return []


def _load(fname, n, kind, rng):
    rows = [json.loads(l) for l in (POOL / fname).open() if l.strip()]
    rng.shuffle(rows)
    rows = rows[:n]
    items = []
    for i, r in enumerate(rows):
        if kind == "routing":
            q = r.get("prompt", "").split("\n\n", 1)[-1]
            items.append({"idx": i, "query": q, "gold": r.get("gold")})
        elif kind == "pair":
            q = r.get("prompt", "").split("\n\n", 1)[-1]
            items.append({"idx": i, "query": q, "chosen": r.get("chosen"), "rejected": r.get("rejected")})
        elif kind == "param":
            q = r.get("prompt", "").split("\n\n", 1)[-1]
            g = r.get("gold"); g = json.loads(g) if isinstance(g, str) else g
            items.append({"idx": i, "query": q, "gold": g})
    return items


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    rng = random.Random(a.seed)
    SETS = [
        ("routing", "db_generated_routing_grpo.jsonl", RUBRIC_ROUTING, "routing"),
        ("dpo_routing_confusable", "db_generated_routing_dpo_pairs.jsonl", RUBRIC_PAIR, "pair"),
        ("dpo_exec_grounded", "db_generated_exec_dpo_pairs.jsonl", RUBRIC_PAIR, "pair"),
        ("param", "db_generated_param_grpo.jsonl", RUBRIC_PARAM, "param"),
    ]
    report = {"n_per_set": a.n, "committee": MODELS, "sets": {}}
    for name, fname, rubric, kind in SETS:
        if not (POOL / fname).exists():
            continue
        items = _load(fname, a.n, kind, random.Random(a.seed))
        prompt = rubric + "\n\nEXAMPLES:\n" + json.dumps(items, indent=0)
        per_model = {}
        for model in MODELS:
            try:
                verdicts = _parse(_call(model, prompt))
            except Exception as e:
                per_model[model] = {"error": str(e)[:120]}; continue
            if not verdicts:
                per_model[model] = {"error": "no JSON parsed"}; continue
            agg = defaultdict(float); fails = []
            for v in verdicts:
                for k in ("query_realistic", "gold_plausible", "chosen_correct", "negative_valid",
                          "gold_sensible", "restraint_valid"):
                    if k in v:
                        agg[k] += float(v[k])
                if str(v.get("verdict", "")).upper() == "FAIL":
                    fails.append(v.get("issue", ""))
            nv = len(verdicts)
            per_model[model] = {"n": nv, **{k: round(agg[k] / nv, 3) for k in agg},
                                "fail_rate": round(len(fails) / nv, 3), "fail_issues": fails[:6]}
        report["sets"][name] = per_model
        print(f"=== {name} (n={a.n}) ===")
        for m, r in per_model.items():
            print(f"  {m:34} {json.dumps(r)[:240]}")
    (OUT / "audit_dataset_committee.json").write_text(json.dumps(report, indent=2))
    print(f"\nwrote {OUT / 'audit_dataset_committee.json'}")


if __name__ == "__main__":
    main()
