"""LITERATURE source: fetch real PubMed abstracts per method/assay bucket and reverse-generate
grounded user query scenarios (workflow-routing + research/methods/experiment intents).
Grounded in the paper's described analysis/goal — NOT copying the abstract. Auditor-validated
downstream. Complements GEO (study records) + DB reverse-gen (workflows)."""
import json, os, re, time, random, urllib.parse, urllib.request, sys
from concurrent.futures import ThreadPoolExecutor
random.seed(53); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
EUT="https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
def get(url,p):
    for _ in range(4):
        try: return urllib.request.urlopen(url+"?"+urllib.parse.urlencode(p),timeout=40).read().decode()
        except Exception: time.sleep(1)
    return ""
# method term -> (candidate workflow if clearly assay-mappable else None, default intent)
BUCKETS=[
 ("bulk RNA-seq differential expression STAR salmon","nf-core/rnaseq","workflow_generation"),
 ("single-cell RNA-seq clustering Seurat","nf-core/scrnaseq","workflow_generation"),
 ("ChIP-seq peak calling MACS2","nf-core/chipseq","workflow_generation"),
 ("ATAC-seq chromatin accessibility","nf-core/atacseq","workflow_generation"),
 ("whole genome sequencing somatic variant calling GATK","nf-core/sarek","workflow_generation"),
 ("16S rRNA microbiome amplicon","nf-core/ampliseq","workflow_generation"),
 ("experimental design power analysis sequencing study",None,"experiment_design"),
 ("bioinformatics methods comparison benchmarking review",None,"comparative_methodology"),
 ("statistical method explanation tutorial genomics",None,"teaching_explanation"),
]
def abstracts(term,n=25):
    r=get(EUT+"/esearch.fcgi",{"db":"pubmed","term":term,"retmax":n,"retmode":"json","sort":"relevance"})
    try: ids=json.loads(r)["esearchresult"].get("idlist",[])
    except Exception: return []
    time.sleep(0.4)
    txt=get(EUT+"/efetch.fcgi",{"db":"pubmed","id":",".join(ids),"rettype":"abstract","retmode":"text"})
    return [a.strip() for a in re.split(r"\n\n\d+\.\s",txt) if len(a.strip())>200][:n]
def gen(abst,wf,intent):
    tgt = f"They want to run the analysis (candidate workflow context: {wf})." if wf else f"Their need is a {intent} (no pipeline to run)."
    q=call(f"Based on this real paper, write ONE realistic user request/question a researcher would send to a bioinformatics assistant, in their own words describing their DATA/GOAL. {tgt} Do NOT copy the abstract or name the workflow. Paper:\n{abst[:900]}\nReply with only the request.")
    if not q or len(q)<20: return None
    e={"query":q,"intent":intent,"source":"pubmed"}
    if wf: e["correct_workflow"]=wf
    return e
def call(prompt):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":500,"reasoning_effort":"low"}).encode()
    try:
        d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
        return d["choices"][0]["message"]["content"].strip().strip('"')
    except Exception: return None
PER=int(sys.argv[1]) if len(sys.argv)>1 else 20
jobs=[]
for term,wf,intent in BUCKETS:
    for a in abstracts(term,PER): jobs.append((a,wf,intent))
print("fetched",len(jobs),"abstracts; generating scenarios...")
out=[]
with ThreadPoolExecutor(max_workers=12) as ex:
    for e in ex.map(lambda j: gen(*j), jobs):
        if e: out.append(e)
from collections import Counter
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/literature_raw.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print("GENERATED",len(out),"literature scenarios:",dict(Counter(e["intent"] for e in out)))
