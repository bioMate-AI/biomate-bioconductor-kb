"""Fetch + verbalize EDAM ontology (data types/formats/operations/topics) into mid-training text.
Run: curl -sL https://edamontology.org/EDAM.csv -o /tmp/EDAM.csv; python3 verbalize_ontology_edam.py"""
import csv,json,re,sys
SRC=sys.argv[1] if len(sys.argv)>1 else "/tmp/EDAM.csv"
OUT="/Users/kky/biomate-review/docs/20260912_onprem_llm/midtrain_corpus/edam_corpus.jsonl"
rows=list(csv.DictReader(open(SRC))); lbl={r["Class ID"]:r["Preferred Label"] for r in rows}
def branch(cid):
    m=re.search(r"/(data|format|operation|topic|identifier)_\d+",cid); return m.group(1) if m else "concept"
n=0
with open(OUT,"w") as f:
    for r in rows:
        if (r.get("Obsolete") or "").lower()=="true": continue
        label=r.get("Preferred Label") or ""; defn=(r.get("Definitions") or "").strip()
        if not label or len(defn)<15: continue
        parents=[lbl.get(p.strip(),"") for p in (r.get("Parents") or "").split("|") if p.strip() in lbl]
        syn=(r.get("Synonyms") or "").replace("|",", ")
        t=f"EDAM {branch(r['Class ID'])}: {label} — {defn}"
        if syn: t+=f" Synonyms: {syn}."
        if parents: t+=f" It is a kind of {', '.join(p for p in parents if p)}."
        f.write(json.dumps({"text":t,"source":"edam","id":r["Class ID"]})+"\n"); n+=1
print(f"EDAM: {n} terms")
