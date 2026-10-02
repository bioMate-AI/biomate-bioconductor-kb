"""Verbalize the FULL BioMate catalog DB into rich, VARIED natural-language text for mid-training so the
model KNOWS the catalog (every workflow/tool + fields). Multiple views/record (catalog-entry, prose,
and description->name QA that teaches recall) to avoid the degenerate-repetition that hurt the KG run.
Deterministic (real DB fields only — zero hallucination). Usage:
  python build_db_corpus.py --db galaxy_ai_tools.db --out db_catalog_corpus.jsonl --repeat 3
"""
import argparse, json, re, sqlite3


def clean(s, n=600):
    s = re.sub(r"<[^>]+>", " ", str(s or "")); s = re.sub(r"\s+", " ", s).strip()
    return s[:n]


def wf_views(r):
    name, dom, desc = r["name"], r.get("domain") or "general", clean(r.get("description"), 500)
    inp, out, tools = clean(r.get("input_types"), 200), clean(r.get("output_types"), 200), clean(r.get("tools_used"), 300)
    cat = r.get("category") or dom
    v = []
    v.append(f"BioMate workflow catalog entry.\nName: {name}\nDomain: {dom}\nCategory: {cat}\n"
             f"Description: {desc}\nInputs: {inp}\nOutputs: {out}\nTools used: {tools}")
    if desc:
        v.append(f"The `{name}` workflow ({dom}) {desc} It accepts {inp or 'the required inputs'} and "
                 f"produces {out or 'its outputs'}" + (f", using {tools}." if tools else "."))
        v.append(f"Q: Which BioMate workflow should I use to {desc[:180].rstrip('.')}?\n"
                 f"A: Use the `{name}` workflow ({dom}).")
    return [x for x in v if x]


def tool_views(r):
    name, cat = r["name"], r.get("category") or "general"
    desc = clean(r.get("help_text") or r.get("rawText"), 500)
    params, inp, out = clean(r.get("parameters"), 300), clean(r.get("inputs"), 200), clean(r.get("outputs"), 200)
    v = [f"BioMate tool catalog entry.\nTool: {name}\nCategory: {cat}\nDescription: {desc}\n"
         f"Parameters: {params}\nInputs: {inp}\nOutputs: {out}"]
    if desc:
        v.append(f"The `{name}` tool ({cat}) {desc}" + (f" Parameters: {params}." if params else ""))
    return [x for x in v if x]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True); ap.add_argument("--out", required=True)
    ap.add_argument("--repeat", type=int, default=3, help="repeat the catalog N times (memorization)")
    a = ap.parse_args()
    c = sqlite3.connect(f"file:{a.db}?mode=ro", uri=True); c.row_factory = sqlite3.Row
    wfs = [dict(r) for r in c.execute("select * from workflows")]
    tools = [dict(r) for r in c.execute("select * from tools")]
    docs = []
    for r in wfs:
        if r.get("name"): docs += [{"text": t, "source": "db_workflow"} for t in wf_views(r)]
    for r in tools:
        if r.get("name"): docs += [{"text": t, "source": "db_tool"} for t in tool_views(r)]
    import random; random.seed(7)
    toks = 0
    with open(a.out, "w") as fo:
        for _ in range(a.repeat):
            random.shuffle(docs)
            for d in docs:
                fo.write(json.dumps(d) + "\n"); toks += len(d["text"]) // 4
    print(f"DB CATALOG DONE: {len(wfs)} wf + {len(tools)} tools -> {len(docs)} views x{a.repeat} = "
          f"{len(docs)*a.repeat} docs, ~{toks:,} tokens -> {a.out}", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
