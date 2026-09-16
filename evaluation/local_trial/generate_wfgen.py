"""workflow_generation data: research intent -> expected_category (harness 17-label space)."""
import json,os,re,random,sys,time,urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(51); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
CATS=['admet','alphafold','atac_seq','bisulfite_seq','chip_seq','crispr_screen','cryo_em','generative_design',
 'gwas','metagenomics','molecular_docking','molecular_dynamics','rna_seq','scrna_seq','spatial_transcriptomics',
 'variant_calling','wgs']  # 17 (from harness label set)
def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":120,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None
def gen(args):
    cat,i=args
    p=(f"Write ONE realistic 1-2 sentence research request whose correct analysis category is '{cat}'. "
       f"Describe the biology/data/goal in a researcher's words. Do NOT name the category or analysis method. Reply with only the request.")
    q=_call(p)
    return {"intent":q,"expected_category":cat} if q and len(q)>15 else None
PER=int(sys.argv[1]) if len(sys.argv)>1 else 22
jobs=[(c,i) for c in CATS for i in range(PER)]
out=[]
with ThreadPoolExecutor(max_workers=10) as ex:
    for e in ex.map(gen, jobs):
        if e: out.append(e)
import collections
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/wfgen_raw.jsonl","w").write("\n".join(json.dumps(e) for e in out))
print(f"GENERATED {len(out)} wfgen | {dict(collections.Counter(e['expected_category'] for e in out))}")
