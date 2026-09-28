"""Assemble an OBJECTIVE per-task eval set (no LLM judge). v1 tasks with clean (query -> objective gold):
- workflow_routing: accept-set membership (gold_routing_eval)
- knowledge_recall: MedMCQA held-out, multiple-choice EXACT-MATCH (options + correct letter)
- scientific_qa: MedQA held-out, multiple-choice EXACT-MATCH
Held-out = high offset (avoid the training slice). Extensible to param/tool/etc. as gold lands.
Usage: python build_objective_evals.py --out objective_eval.jsonl --n 300
"""
import argparse, json, os, time, urllib.parse, urllib.request
P = "/Users/kky/biomate-review/docs/20260912_onprem_llm/data_pool_v2"
API = "https://datasets-server.huggingface.co/rows"


def rows(ds, cfg, split, offset, n):
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
    ap = argparse.ArgumentParser(); ap.add_argument("--out", required=True); ap.add_argument("--n", type=int, default=300)
    a = ap.parse_args()
    items = []
    # routing (accept-set)
    for r in [json.loads(l) for l in open(f"{P}/gold_routing_eval.jsonl")]:
        items.append({"task": "workflow_routing", "grader": "accept_set", "candidates": r["candidates"],
                      "prompt": "You are BioMate. Choose the single best workflow for this request from the candidates. "
                                f"Reply ONLY the exact workflow name.\n\nRequest: {r['query']}\n\nCandidates:\n" +
                                "\n".join(f"- {c}" for c in r["candidates"]), "accept": r["accept"]})
    # knowledge_recall: MedMCQA held-out (offset 150000 to avoid the trained slice)
    L = "ABCD"
    for r in rows("openlifescienceai/medmcqa", "default", "train", 150000, a.n):
        opts = [r.get("opa"), r.get("opb"), r.get("opc"), r.get("opd")]; ci = int(r.get("cop", 0)) if str(r.get("cop", "")).isdigit() else 0
        items.append({"task": "knowledge_recall", "grader": "mcqa",
                      "prompt": f"{r['question']}\n" + "\n".join(f"{L[i]}) {o}" for i, o in enumerate(opts) if o) +
                                "\nAnswer with the letter only.", "gold": L[ci]})
    # scientific_qa: MedQA held-out (offset 8000)
    for r in rows("bigbio/med_qa", "med_qa_en_source", "train", 8000, a.n):
        opts = r.get("options") or []
        items.append({"task": "scientific_qa", "grader": "mcqa",
                      "prompt": f"{r['question']}\n" + "\n".join(f"{o.get('key')}) {o.get('value')}" for o in opts if isinstance(o, dict)) +
                                "\nAnswer with the letter only.", "gold": r.get("answer_idx", "")})
    with open(a.out, "w") as fo:
        for it in items: fo.write(json.dumps(it) + "\n")
    import collections
    print("OBJECTIVE EVAL:", dict(collections.Counter(i["task"] for i in items)), "->", a.out)


if __name__ == "__main__":
    raise SystemExit(main())
