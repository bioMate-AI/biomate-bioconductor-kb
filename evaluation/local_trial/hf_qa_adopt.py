"""Adopt public GOLD biomedical QA datasets -> SFT (replaces teacher-distilled doc-summaries for the
knowledge/scientific-QA tasks). Uses the HF datasets-server rows API (JSON, no datasets/pyarrow lib).
Gold answers => no teacher hallucination. Usage: python hf_qa_adopt.py --out qa_gold.jsonl [--cap 8000]
"""
import argparse, json, time, urllib.parse, urllib.request

SYS = "You are BioMate, an agentic bioinformatics assistant. Answer accurately and concisely."
API = "https://datasets-server.huggingface.co/rows"


def rows(dataset, config, split, cap):
    off = 0
    while off < cap:
        length = min(100, cap - off)
        q = urllib.parse.urlencode({"dataset": dataset, "config": config, "split": split,
                                    "offset": off, "length": length})
        d = {"rows": []}
        for a in range(8):
            try:
                d = json.load(urllib.request.urlopen(f"{API}?{q}", timeout=90)); break
            except Exception:
                time.sleep(3 * (a + 1))
        rs = d.get("rows", [])
        if not rs: return
        for r in rs: yield r["row"]
        off += len(rs)
        if len(rs) < length: return


def ex(task, source, user, assistant):
    return {"messages": [{"role": "system", "content": SYS},
                         {"role": "user", "content": user}, {"role": "assistant", "content": assistant}],
            "task": task, "source": source}


def conv_pubmedqa(r):
    ctx = r.get("context")
    if isinstance(ctx, dict): ctx = " ".join(ctx.get("contexts", []) or [])
    u = f"Question: {r['question']}\n\nContext: {str(ctx)[:1800]}"
    a = f"{r.get('final_decision','').capitalize()}. {r.get('long_answer','')}"
    return ex("scientific_qa", "pubmedqa", u, a.strip())


def conv_medmcqa(r):
    opts = [r.get("opa"), r.get("opb"), r.get("opc"), r.get("opd")]
    letters = "ABCD"
    ci = int(r.get("cop", 0)) if str(r.get("cop", "")).isdigit() else 0
    u = f"{r['question']}\n" + "\n".join(f"{letters[i]}) {o}" for i, o in enumerate(opts) if o)
    a = f"{letters[ci]}) {opts[ci]}." + (f" {r['exp']}" if r.get("exp") else "")
    return ex("knowledge_recall", "medmcqa", u, a.strip())


def conv_medqa(r):
    opts = r.get("options") or []
    u = f"{r['question']}\n" + "\n".join(f"{o.get('key')}) {o.get('value')}" for o in opts if isinstance(o, dict))
    a = f"{r.get('answer_idx','')}) {r.get('answer','')}."
    return ex("scientific_qa", "medqa", u, a.strip())


def conv_sciq(r):
    u = r["question"]
    a = r.get("correct_answer", "")
    if r.get("support"): a += f" ({r['support'][:400]})"
    return ex("knowledge_recall", "sciq", u, a.strip())


DATASETS = [
    ("qiaojin/PubMedQA", "pqa_labeled", "train", conv_pubmedqa, 1000),
    ("openlifescienceai/medmcqa", "default", "train", conv_medmcqa, None),
    ("bigbio/med_qa", "med_qa_en_source", "train", conv_medqa, None),
    ("allenai/sciq", "default", "train", conv_sciq, None),
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True); ap.add_argument("--cap", type=int, default=8000)
    a = ap.parse_args()
    n = 0
    counts = {}
    with open(a.out, "w") as fo:
        for ds, cfg, split, conv, cap in DATASETS:
            cap = cap or a.cap; c = 0
            for r in rows(ds, cfg, split, cap):
                try:
                    e = conv(r)
                    if e["messages"][1]["content"] and e["messages"][2]["content"]:
                        fo.write(json.dumps(e) + "\n"); n += 1; c += 1
                except Exception:
                    continue
            counts[ds] = c
            print(f"  {ds}: {c}", flush=True)
    print(f"QA GOLD DONE: {n} examples {counts} -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
