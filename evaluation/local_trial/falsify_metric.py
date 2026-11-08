"""Committee-v4 P0 falsification: how much of the removal-eval score is query-paraphrase, not
composition? Runs degenerate baselines against the SAME fixed gold + judge as eval_removal.py.

Baselines:
  null_echo        - plan = the query split into imperative bullets (no tool selection, no reasoning)
  generic_template - plan = one fixed 7-step generic pipeline for EVERY case
  query_only       - gpt-5-mini given the query but NO candidates (does the catalog matter at all?)

Committee calibration: null_echo & generic_template must score <0.15; >0.35 => metric uncalibrated
(the ~0.5 on-prem number is then a paraphrase floor, not capability).
"""
import json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import judge, call, INSTR  # reuse the exact judge + API path

D = os.environ.get("EVAL_DIR", "/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1")
N = int(os.environ.get("N", "80"))
rows = [json.loads(l) for l in open(f"{D}/removal_eval.jsonl")][:N]

GENERIC = ["Read and quality-check the input data", "Filter low-quality or low-abundance features",
           "Normalize the data", "Fit an appropriate statistical model",
           "Test for significance and correct for multiple testing",
           "Summarize and visualize the results", "Write output tables and figures"]
generic_plan = json.dumps([{"step": s, "workflow_or_action": "GENERATE"} for s in GENERIC])


def echo_plan(q):
    parts = [p.strip() for p in re.split(r"[.;\n]", q) if len(p.strip()) > 15][:8]
    return json.dumps([{"step": p, "workflow_or_action": "GENERATE"} for p in parts])


tot = {"null_echo": 0.0, "generic_template": 0.0, "query_only": 0.0}
n = 0
for i, r in enumerate(rows):
    gt = r["ground_truth_steps"]; q = r["query"]
    tot["null_echo"] += judge(gt, echo_plan(q))
    tot["generic_template"] += judge(gt, generic_plan)
    resp = call("https://api.openai.com/v1/chat/completions", "gpt-5-mini", f"{INSTR}\n\nRequest: {q}")  # NO candidates
    tot["query_only"] += judge(gt, resp)
    n += 1
    if n % 20 == 0:
        print(f"  {n}/{len(rows)} …", {k: round(v / n, 3) for k, v in tot.items()})

res = {k: round(v / max(n, 1), 3) for k, v in tot.items()}
res["n"] = n
json.dump(res, open(f"{D}/falsify_metric_result.json", "w"), indent=2)
print("\nFALSIFY RESULT:", json.dumps(res))
print("reference: on-prem 4B sft-only 0.483 | full_mix 0.493 | frontier+candidates 0.874")
print("calibration: null_echo & generic_template <0.15 OK; >0.35 => metric measures paraphrase")
