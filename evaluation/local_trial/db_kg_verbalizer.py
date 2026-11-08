"""Verbalize the tool AI DB as a KNOWLEDGE GRAPH (relational triples -> sentences) for mid-training.
Relations: tool-performs-EDAMoperation (URI->label via EDAM.csv), tool-in/out-datatype,
workflow-uses-tools, tool-in-category/domain, tool-best-practice-for. Distinct from internal_corpus
(free text) — this captures the ontology STRUCTURE. Dual-use: training text + the RAG knowledge base."""
import sqlite3,json,os,csv,re
REPO="/Users/kky/biomate-review"; OUT=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus/db_kg_corpus.jsonl"
# EDAM URI -> label
edam={}
if os.path.exists("/tmp/EDAM.csv"):
    for r in csv.DictReader(open("/tmp/EDAM.csv")): edam[r["Class ID"]]=r["Preferred Label"]
def labels(field):
    try: uris=json.loads(field) if field else []
    except: uris=[u.strip() for u in str(field).split(",")] if field else []
    return [edam.get(u,"") for u in uris if edam.get(u)]
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
seen=set(); n=0
def emit(f,t):
    global n
    t=t.strip()
    if len(t)<25: return
    h=hash(t)
    if h in seen: return
    seen.add(h); f.write(json.dumps({"text":t,"source":"db_kg","id":str(n)})+"\n"); n+=1
with open(OUT,"w") as f:
    # tools: operations (EDAM-linked), topics, I/O, category, best-practice
    for r in c.execute("select name,category,edam_operations,edam_topics,inputs,outputs,best_practice_domains,best_practice_functions from tools"):
        d=dict(r); nm=d["name"]
        ops=labels(d.get("edam_operations")); tops=labels(d.get("edam_topics"))
        if ops: emit(f,f"The bioinformatics tool {nm} performs the operations: {', '.join(ops)}.")
        if tops: emit(f,f"The tool {nm} is used in the topics: {', '.join(tops)}.")
        if d.get("inputs") and d.get("outputs"): emit(f,f"The tool {nm} consumes {str(d['inputs'])[:150]} and produces {str(d['outputs'])[:150]}.")
        if d.get("category"): emit(f,f"The tool {nm} belongs to the category {d['category']}.")
        bpd=d.get("best_practice_domains")
        if bpd and len(str(bpd))>3: emit(f,f"The tool {nm} is a recommended (best-practice) tool for: {str(bpd)[:150]}.")
    # workflows: uses tools; domain; I/O flow
    for r in c.execute("select name,domain,tools_used,input_types,output_types from workflows where tools_used is not null and length(tools_used)>5"):
        d=dict(r)
        emit(f,f"The {d.get('domain')} workflow {d['name']} is composed of the tools: {str(d['tools_used'])[:250]}.")
        if d.get("input_types") and d.get("output_types"):
            emit(f,f"The workflow {d['name']} takes {str(d['input_types'])[:120]} as input and yields {str(d['output_types'])[:120]}.")
print(f"DB-as-KG corpus: {n} relational sentences")
