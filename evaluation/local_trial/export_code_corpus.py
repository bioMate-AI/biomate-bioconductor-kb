"""Export workflow CODE into the mid-training corpus: Nextflow (.nf, nextflow.config), Bioconductor/R
(.R), and DB workflow_json definitions. Deduped by content hash, size-capped. Code helps param/
workflow-gen/decomposition tasks (code domains benefit most from mid-training)."""
import os, re, json, hashlib, sqlite3, glob
REPO="/Users/kky/biomate-review"; OUT=f"{REPO}/docs/20260912_onprem_llm/midtrain_corpus"
os.makedirs(OUT, exist_ok=True)
CAP=8000  # chars per doc
CODE_DIRS=["backend/biomni_workflows","Biomni/biomni_nextflow","backend/nf-core-workflows",
           "backend/nf-core-modules","nextflow_nfcore","docs/20260912_onprem_llm/official_nextflow_docs"]
seen=set(); counts={}
def emit(f,text,source,idv):
    text=text.strip()
    if len(text)<80: return 0
    if len(text)>CAP: text=text[:CAP]
    h=hashlib.sha256(text.encode()).hexdigest()[:16]
    if h in seen: return 0
    seen.add(h); f.write(json.dumps({"text":text,"source":source,"id":idv})+"\n")
    counts[source]=counts.get(source,0)+1; return 1
with open(f"{OUT}/code_corpus.jsonl","w") as f:
    # 1) code files on disk
    for d in CODE_DIRS:
        base=os.path.join(REPO,d)
        if not os.path.isdir(base): continue
        for ext,src in [("*.nf","nextflow"),("*.R","bioconductor_r"),("nextflow.config","nf_config")]:
            for p in glob.glob(f"{base}/**/{ext}",recursive=True):
                try: txt=open(p,errors="ignore").read()
                except Exception: continue
                lang={"nextflow":"nextflow","bioconductor_r":"R","nf_config":"nextflow-config"}[src]
                rel=os.path.relpath(p,REPO)
                emit(f,f"# {lang} file: {os.path.basename(p)}\n{txt}",src,rel)
    # 2) DB workflow_json (workflow structure definitions)
    c=sqlite3.connect(f"file:{REPO}/backend/database/galaxy_ai_tools.db?mode=ro",uri=True); c.row_factory=sqlite3.Row
    for r in c.execute("select name,domain,workflow_json from workflows where workflow_json is not null and length(workflow_json)>80"):
        d=dict(r); emit(f,f"# Workflow definition (JSON): {d['name']} (domain {d.get('domain')})\n{str(d['workflow_json'])[:CAP]}","workflow_json",d['name'])
    # 3) tool wrappers / raw text (tool definitions with code/params)
    for r in c.execute("select tool_id,name,rawText from tools where rawText is not null and length(rawText)>80"):
        d=dict(r); emit(f,f"# Tool wrapper: {d['name']}\n{str(d['rawText'])[:CAP]}","tool_wrapper",str(d['tool_id']))
tot=sum(counts.values())
print(f"code corpus: {counts} | total={tot} unique docs")
chars=sum(len(json.loads(l)['text']) for l in open(f"{OUT}/code_corpus.jsonl"))
print(f"~{chars//4/1e6:.1f}M tokens, {chars/1e6:.1f}M chars, {os.path.getsize(f'{OUT}/code_corpus.jsonl')/1e6:.1f} MB")
