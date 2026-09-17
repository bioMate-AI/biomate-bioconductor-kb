"""protocol_thresholds data: (sequencing protocol + QC situation) -> PASS/FAIL/WARN, grounded in
QC knowledge; auditor-verified separately (here: generate action + short justification)."""
import json,os,re,random,sys,time,urllib.request
from concurrent.futures import ThreadPoolExecutor
random.seed(53); REPO="/Users/kky/biomate-review"; KEY=os.environ["OPENAI_API_KEY"]; GEN="gpt-5-mini"
PROTOCOLS=["bulk RNA-seq (Illumina, paired-end)","single-cell RNA-seq (10x)","WGS germline (30x)","WES tumor/normal",
 "ChIP-seq (TF)","ATAC-seq","16S amplicon metagenomics","whole-genome bisulfite","nanopore long-read WGS","cut&run"]
QC=["per-base Phred drops below 20 in the last 20% of reads","duplication rate 65%","only 42% reads map to reference",
 "GC content bimodal / adapter contamination flagged","mean coverage 8x for a germline caller","rRNA fraction 45%",
 "ambient RNA / high mito% in 30% of cells","insert-size distribution shows adapter dimers","Q30 = 78% overall",
 "10% of samples fail library-complexity threshold","Q30 = 94% and >90% reads map, all metrics within spec","duplication 12%, insert sizes clean, per-base quality >30 throughout","mean coverage 35x, uniform, no adapter contamination","all FastQC modules pass, GC unimodal, adapters trimmed cleanly","per-base quality dips slightly at read ends but trimming recovers it","3% mito in single-cell, doublet rate low, ambient RNA minimal"]
def _call(p):
    body=json.dumps({"model":GEN,"messages":[{"role":"user","content":p}],"max_completion_tokens":120,"reasoning_effort":"low"}).encode()
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request("https://api.openai.com/v1/chat/completions",data=body,headers={"Authorization":f"Bearer {KEY}","Content-Type":"application/json"}),timeout=60))
            return d["choices"][0]["message"]["content"].strip()
        except Exception: time.sleep(1.5*(a+1))
    return None
def gen(args):
    proto,qc=args
    p=(f"A {proto} run has this QC situation: {qc}. As a QC gate, the correct action is one of PASS, FAIL, WARN. "
       f"Reply with ONLY one token: PASS, FAIL, or WARN.")
    out=_call(p)
    act=next((x for x in ["FAIL","WARN","PASS"] if out and x in out.upper()), None)
    return {"protocol":proto,"universal_threshold_problem":qc,"expected_correct_action":act} if act else None
N=int(sys.argv[1]) if len(sys.argv)>1 else 200
jobs=[(random.choice(PROTOCOLS),random.choice(QC)) for _ in range(N)]
out=[]
with ThreadPoolExecutor(max_workers=8) as ex:
    for e in ex.map(gen, jobs):
        if e: out.append(e)
# dedup
seen=set();u=[]
for e in out:
    k=(e["protocol"],e["universal_threshold_problem"])
    if k not in seen: seen.add(k); u.append(e)
import collections
open(f"{REPO}/docs/20260912_onprem_llm/routing_data_v1/protocol_raw.jsonl","w").write("\n".join(json.dumps(e) for e in u))
print(f"GENERATED {len(u)} protocol | {dict(collections.Counter(e['expected_correct_action'] for e in u))}")
