"""Per-task scorecard for the on-prem model across ALL LLM-scorable BioMate tasks (not just removal).

Loads base(4-bit)+adapter once, runs each RealBio public-export task, scores with a task-appropriate
deterministic scorer (decomposition uses the removal judge). boin/pbpk/drug_discovery_e2e are EXECUTION
tasks (need the real tools), not pure-LLM, so they're excluded here. litqa2 is scoped out.

  routing (cross_domain_routing) : names correct_workflow (acceptable_alt -> 0.5)
  accession_routing              : names the correct method
  param_prefill                  : recall of expected_params values, minus must_not_fill restraint viol
  autofix_benchmark              : names the gold fix category
  intent_interpretation          : outputs the gold intent label (label set given)
  protocol_thresholds            : chooses the CORRECT action (not the naive one)
  workflow_generation            : names the expected category
  task_decomposition             : judge coverage of gold sub-tasks

Usage: python eval_alltasks.py --base <path> --adapter <path> --model qwen-small-full_mix --out out.json
"""
import argparse, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import judge, direct_load, call_direct  # reuse model load + judge

REPO = "/Users/kky/biomate-review"
PX = f"{REPO}/evaluation/datasets/public_export"
LIM = int(os.environ.get("LIMIT_PER", "60"))


def norm(s): return re.sub(r"[^a-z0-9]+", " ", str(s).lower()).strip()


def load(task):
    p = f"{PX}/{task}/data.jsonl"
    return [json.loads(l) for l in open(p)][:LIM] if os.path.exists(p) else []


def vocab(task, key):
    return sorted({str(r.get(key, "")) for r in load(task) if r.get(key)})


def build():
    intents = vocab("intent_interpretation", "intent")
    afcats = vocab("autofix_benchmark", "category")
    return {
        "cross_domain_routing": (lambda it: "You are BioMate. Name the single correct bioinformatics WORKFLOW (e.g. an nf-core pipeline) for this request. Reply ONLY the workflow name.\n\nRequest: " + it.get("query", ""),
                                 lambda it, o: 1.0 if norm(it["correct_workflow"]) in o else (0.5 if any(norm(a) in o for a in it.get("acceptable_alts") or []) else 0.0)),
        "accession_routing": (lambda it: f"You are BioMate. Given this dataset accession + metadata, name the correct analysis METHOD/tool. Reply ONLY the method name.\n\nAccession: {it.get('accession')}\nMetadata: {it.get('metadata','')}",
                              lambda it, o: 1.0 if norm(it.get("method", "")) and norm(it["method"]) in o else 0.0),
        "param_prefill": (lambda it: "You are BioMate. Extract ONLY the workflow parameters explicitly implied by this request as key: value lines. Do not invent unspecified params.\n\nRequest: " + it.get("user_query", it.get("query", "")),
                          lambda it, o: max(0.0, (sum(1 for v in (it.get("expected_params") or {}).values() if norm(v) and norm(v) in o) / max(len(it.get("expected_params") or {}), 1))
                                          - 0.5 * (sum(1 for k in (it.get("must_not_fill") or []) if norm(k) in o) / max(len(it.get("must_not_fill") or []), 1)))),
        "autofix_benchmark": (lambda it: f"You are BioMate. A pipeline failed. Classify the failure into ONE fix category from: {', '.join(afcats)}. Reply ONLY the category.\n\nWorkflow: {it.get('workflow','')}\nError log:\n{str(it.get('error_log',''))[:1200]}",
                              lambda it, o: 1.0 if norm(it.get("category", "")) in o else 0.0),
        "intent_interpretation": (lambda it: f"You are BioMate. Classify this request into ONE intent from: {', '.join(intents)}. Reply ONLY the intent label.\n\nRequest: " + it.get("query", ""),
                                  lambda it, o: 1.0 if norm(it.get("intent", "")) in o else 0.0),
        "protocol_thresholds": (lambda it: f"You are BioMate reviewing a QC result. A universal threshold flags this run. Decide whether the run is genuinely PASS/VALID or a true FAIL, accounting for the protocol. Reply ONLY one of: PASS, FAIL, VALID.\n\nProtocol: {it.get('protocol')}\nSituation: {it.get('universal_threshold_problem','')}",
                                lambda it, o: (1.0 if norm(it.get("expected_correct_action", "")) in o and norm(it.get("expected_naive_action", "")) not in o
                                               else (0.5 if norm(it.get("expected_correct_action", "")) in o or norm(it.get("ground_truth", "")) in o else 0.0))),
        "workflow_generation": (lambda it: "You are BioMate. Name the workflow CATEGORY (e.g. rnaseq, sarek, atacseq, chipseq, scrnaseq) for this intent. Reply ONLY the category.\n\nIntent: " + it.get("intent", ""),
                                lambda it, o: 1.0 if norm(it.get("expected_category", "")) in o else 0.0),
        "task_decomposition": (lambda it: it.get("instr", "Decompose into an ordered sub-task plan.") + "\n\nRequest: " + it.get("query", ""),
                               lambda it, o: judge([{"step": s.get("sub_task", "")} for s in it.get("gold_subtasks", [])], o)),
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", required=True); ap.add_argument("--adapter", default="")
    ap.add_argument("--model", default="model"); ap.add_argument("--out", required=True)
    a = ap.parse_args()
    direct_load(a.base, a.adapter or None)
    tasks = build()
    per = {}
    for t, (mk, sc) in tasks.items():
        items = load(t)
        if not items:
            continue
        tot = 0.0; n = 0
        for it in items:
            out = call_direct(mk(it), 220)
            if out is None:
                continue
            tot += float(sc(it, norm(out))); n += 1
        per[t] = {"score": round(tot / max(n, 1), 3), "n": n}
        print(f"  {t:24s} {per[t]['score']:.3f}  (n={n})")
    macro = round(sum(v["score"] for v in per.values()) / max(len(per), 1), 3)
    res = {"model": a.model, "macro_over_tasks": macro, "per_task": per}
    json.dump(res, open(a.out, "w"), indent=2)
    print("ALLTASKS:", json.dumps(res))


if __name__ == "__main__":
    raise SystemExit(main())
