"""Export BioMate's internal, license-clean domain text into a mid-training corpus.
Sources: tools (description/scientific_context/usage_guide/best_practices/help/examples/citations),
workflows (description/annotation/IO/tools/params), and skills/*.md (Bioconductor + expert).
Writes one JSONL of {text, source, id}; deduped by text hash. Highest-value, on-domain, ours."""
import sqlite3, json, os, re, hashlib, glob
REPO="/Users/kky/biomate-review"; OUT=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus"
os.makedirs(OUT, exist_ok=True)
c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
def clip(x,n): return (str(x) or "")[:n] if x else ""
def emit(f,text,source,idv,seen):
    text=re.sub(r"\n{3,}","\n\n",text).strip()
    if len(text)<80: return 0
    h=hashlib.sha256(text.encode()).hexdigest()[:16]
    if h in seen: return 0
    seen.add(h); f.write(json.dumps({"text":text,"source":source,"id":idv})+"\n"); return 1
seen=set(); n_t=n_w=n_s=0
with open(f"{OUT}/internal_corpus.jsonl","w") as f:
    # tools
    for r in c.execute("select tool_id,name,category,description,scientific_context,usage_guide,best_practice_functions,help_text,examples,edam_operations,edam_topics,citations from tools"):
        d=dict(r); parts=[f"# Bioinformatics tool: {d.get('name')}"]
        if d.get('category'): parts.append(f"Category: {d['category']}")
        for lbl,col,ln in [("Description","description",800),("Scientific context","scientific_context",1500),
                           ("When/how to use","usage_guide",1200),("Best practices","best_practice_functions",1000),
                           ("EDAM operations","edam_operations",300),("EDAM topics","edam_topics",300),
                           ("Help","help_text",1500),("Examples","examples",1000)]:
            v=clip(d.get(col),ln)
            if v and len(v)>10: parts.append(f"{lbl}: {v}")
        n_t+=emit(f,"\n".join(parts),"tool",str(d.get('tool_id')),seen)
    # workflows
    for r in c.execute("select name,domain,category,description,annotation,tags,input_types,output_types,tools_used,params_schema from workflows"):
        d=dict(r); parts=[f"# Bioinformatics workflow: {d.get('name')}"]
        for lbl,col,ln in [("Domain","domain",60),("Category","category",60),("Description","description",1200),
                           ("Annotation","annotation",800),("Tags","tags",200),("Input types","input_types",400),
                           ("Output types","output_types",400),("Tools used","tools_used",400),("Parameters","params_schema",1200)]:
            v=clip(d.get(col),ln)
            if v and len(v)>2: parts.append(f"{lbl}: {v}")
        n_w+=emit(f,"\n".join(parts),"workflow",d.get('name'),seen)
    # skills (markdown)
    for p in glob.glob(f"{REPO}/backend/lib/galaxy/ai/skills/*.md")+glob.glob(f"{REPO}/backend/lib/galaxy/ai/skills/**/*.md",recursive=True):
        try: n_s+=emit(f,open(p).read(),"skill",os.path.basename(p),seen)
        except Exception: pass
print(f"corpus written: tools={n_t} workflows={n_w} skills={n_s} total={n_t+n_w+n_s} unique docs")
import subprocess
sz=os.path.getsize(f"{OUT}/internal_corpus.jsonl"); print(f"size: {sz/1e6:.1f} MB")
