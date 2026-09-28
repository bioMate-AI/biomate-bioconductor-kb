"""OBJECTIVE per-task eval for ALL tasks (no LLM judge). Clean gold where available (routing accept-set,
QA MCQA exact-match); deterministic CONTENT-OVERLAP for the rest (fraction of the gold's salient tokens
present in the model output) + clarification=asked?. Per-task grader tag. Usage:
  python build_objective_evals.py --out objective_eval.jsonl --per 100
"""
import argparse, json, os, re, time, urllib.parse, urllib.request, collections
P = "/Users/kky/biomate-review/docs/20260912_onprem_llm/data_pool_v2"
R = "/Users/kky/biomate-review/docs/20260912_onprem_llm/routing_data_v1"
API = "https://datasets-server.huggingface.co/rows"
CLEAN = {"workflow_routing", "knowledge_recall", "scientific_qa"}  # get clean gold; others use overlap


def hf(ds, cfg, split, offset, n):
    out = []
    while len(out) < n:
        q = urllib.parse.urlencode({"dataset": ds, "config": cfg, "split": split, "offset": offset + len(out), "length": min(100, n - len(out))})
        d = {"rows": []}
        for a in range(6):
            try: d = json.load(urllib.request.urlopen(f"{API}?{q}", timeout=60)); break
            except Exception: time.sleep(2 * (a + 1))
        rs = d.get("rows", [])
        if not rs: break
        out += [r["row"] for r in rs]
    return out[:n]


def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--out", required=True); ap.add_argument("--per", type=int, default=100)
    a = ap.parse_args(); items = []
    # 1) routing accept-set (clean)
    for r in [json.loads(l) for l in open(f"{P}/gold_routing_eval.jsonl")][:150]:
        items.append({"task": "workflow_routing", "grader": "accept_set", "accept": r["accept"],
                      "prompt": "You are BioMate. Choose the single best workflow from the candidates. Reply ONLY the exact name.\n\n"
                                f"Request: {r['query']}\n\nCandidates:\n" + "\n".join(f"- {c}" for c in r["candidates"])})
    # 2) QA MCQA (clean, held-out)
    L = "ABCDE"
    for r in hf("openlifescienceai/medmcqa", "default", "train", 150000, 150):
        o = [r.get("opa"), r.get("opb"), r.get("opc"), r.get("opd")]; ci = int(r.get("cop", 0)) if str(r.get("cop", "")).isdigit() else 0
        items.append({"task": "knowledge_recall", "grader": "mcqa", "gold": L[ci],
                      "prompt": f"{r['question']}\n" + "\n".join(f"{L[i]}) {x}" for i, x in enumerate(o) if x) + "\nAnswer with the letter only."})
    for r in hf("bigbio/med_qa", "med_qa_en_source", "train", 8000, 150):
        op = r.get("options") or []
        items.append({"task": "scientific_qa", "grader": "mcqa", "gold": r.get("answer_idx", ""),
                      "prompt": f"{r['question']}\n" + "\n".join(f"{x.get('key')}) {x.get('value')}" for x in op if isinstance(x, dict)) + "\nAnswer with the letter only."})
    # 3) all other tasks from corpus_eval_big -> content-overlap grader (clarification -> asked?)
    rows = [json.loads(l) for l in open(f"{P}/corpus_eval_big.jsonl")]
    seen = collections.Counter()
    SYS = "You are BioMate, an agentic bioinformatics assistant."
    for r in rows:
        t = r.get("task", "?")
        if t in CLEAN or seen[t] >= a.per: continue
        m = {x["role"]: x["content"] for x in r.get("messages", [])}
        u, g = m.get("user", ""), m.get("assistant", "")
        if not (u and g): continue
        seen[t] += 1
        grader = "clarify_ask" if t == "clarification_request" else "content_overlap"
        items.append({"task": t, "grader": grader, "gold": g, "prompt": f"{SYS}\n\n{u}"})
    # 4) N1 out_of_catalog_composition from removal_eval (step overlap + abstention)
    for r in [json.loads(l) for l in open(f"{R}/removal_eval.jsonl")][:100]:
        gt = r.get("ground_truth_steps", "")
        items.append({"task": "out_of_catalog_composition", "grader": "content_overlap", "gold": str(gt),
                      "prompt": "You are BioMate. No single workflow fits. Decompose into an ordered plan; name a "
                                f"candidate workflow per step or GENERATE.\n\nCandidates: {r['candidates']}\n\nRequest: {r['query']}"})
    with open(a.out, "w") as fo:
        for it in items: fo.write(json.dumps(it) + "\n")
    print("OBJECTIVE EVAL (all tasks):", dict(collections.Counter(i["task"] for i in items)))


if __name__ == "__main__":
    raise SystemExit(main())
