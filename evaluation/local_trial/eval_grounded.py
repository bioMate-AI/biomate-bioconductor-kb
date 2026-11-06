"""Rebuild-slice-1: a GROUNDED metric that degenerate baselines cannot pass.

The old removal metric was recall-only over free-text steps, so null-echo (restate the query) and a
fixed generic pipeline BEAT the trained model, and query-only (no candidates) scored highest — the
catalog was irrelevant. Fix: credit a gold milestone ONLY if it is covered by a plan step that grounds
in a REAL candidate tool, and penalize fatal bioinformatic errors.

  grounded_coverage = judge(gold, plan_filtered_to_steps_that_name_a_real_candidate)
  grounded_score    = grounded_coverage * (1 - min(1, 0.25 * fatal_bio_errors))

Validates the metric by re-scoring degenerate + frontier strategies (API-only, no GPU). Pass criterion:
null_echo / generic_template / query_only grounded_score < 0.15; frontier_with_candidates >> query_only
(catalog now matters).
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import judge, call, INSTR

D = os.environ.get("EVAL_DIR", "/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1")
N = int(os.environ.get("N", "80"))
rows = [json.loads(l) for l in open(f"{D}/removal_eval.jsonl")][:N]
URL = "https://api.openai.com/v1/chat/completions"

GENERIC = ["Read and quality-check the input data", "Filter low-quality or low-abundance features",
           "Normalize the data", "Fit an appropriate statistical model",
           "Test for significance and correct for multiple testing",
           "Summarize and visualize the results", "Write output tables and figures"]
generic_plan = json.dumps([{"step": s, "workflow_or_action": "GENERATE"} for s in GENERIC])


def echo_plan(q):
    parts = [p.strip() for p in re.split(r"[.;\n]", q) if len(p.strip()) > 15][:8]
    return json.dumps([{"step": p, "workflow_or_action": "GENERATE"} for p in parts])


def grounded_only(plan_text, cands):
    """Keep only plan steps whose workflow_or_action names a REAL candidate (not GENERATE/RUN_CODE)."""
    try:
        arr = json.loads(re.search(r"\[.*\]", plan_text, re.S).group(0))
    except Exception:
        # regex fallback on step/action pairs
        steps = re.findall(r'"step"\s*:\s*"([^"]+)"', plan_text)
        acts = re.findall(r'"workflow_or_action"\s*:\s*"([^"]+)"', plan_text)
        arr = [{"step": s, "workflow_or_action": a} for s, a in zip(steps, acts)]
    kept = [x for x in arr if isinstance(x, dict) and x.get("workflow_or_action") in cands]
    return json.dumps(kept) if kept else ""


def neg_penalty(plan_text):
    p = ("Below is a proposed bioinformatics analysis plan. Count DISQUALIFYING errors (e.g. "
         "log/CPM-normalizing before a raw-count model like DESeq2/edgeR; batch-correcting normalized "
         "data with a count-based method; wrong data type into a tool; invalid ordering). Reply ONLY an "
         f"integer count.\n\nPlan:\n{plan_text}")
    out = call(URL, "gpt-5-mini", p, mx=1500)
    m = re.search(r"\d+", out or "")
    k = int(m.group(0)) if m else 0
    return min(1.0, 0.25 * k)


STRATS = ["null_echo", "generic_template", "query_only", "frontier_cands"]
agg = {s: {"raw": 0.0, "grounded": 0.0, "gscore": 0.0} for s in STRATS}
n = 0
for r in rows:
    gt, q = r["ground_truth_steps"], r["query"]
    cands = set(r["candidates"])
    plans = {
        "null_echo": echo_plan(q),
        "generic_template": generic_plan,
        "query_only": call(URL, "gpt-5-mini", f"{INSTR}\n\nRequest: {q}"),  # no candidates
        "frontier_cands": call(URL, "gpt-5-mini",
                               f"{INSTR}\n\nCandidates:\n" + "\n".join(f"- {c}" for c in r["candidates"]) + f"\n\nRequest: {q}"),
    }
    for s, pt in plans.items():
        raw = judge(gt, pt)
        gcov = judge(gt, grounded_only(pt, cands)) if grounded_only(pt, cands) else 0.0
        gsc = gcov * (1 - neg_penalty(pt)) if gcov > 0 else 0.0
        agg[s]["raw"] += raw; agg[s]["grounded"] += gcov; agg[s]["gscore"] += gsc
    n += 1
    if n % 20 == 0:
        print(f"  {n}/{len(rows)}", {s: round(agg[s]["gscore"] / n, 3) for s in STRATS})

res = {s: {k: round(v / max(n, 1), 3) for k, v in d.items()} for s, d in agg.items()}
res["n"] = n
json.dump(res, open(f"{D}/eval_grounded_result.json", "w"), indent=2)
print("\nGROUNDED METRIC RESULT:")
for s in STRATS:
    print(f"  {s:18s} raw={res[s]['raw']:.3f}  grounded={res[s]['grounded']:.3f}  gscore={res[s]['gscore']:.3f}")
print("PASS if null_echo/generic_template/query_only gscore <0.15 and frontier_cands >> query_only")
