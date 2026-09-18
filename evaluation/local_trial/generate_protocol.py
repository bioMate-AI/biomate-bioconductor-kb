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
# COHERENT: map each protocol to QC issues that actually apply to it
PMAP={
 "bulk RNA-seq (Illumina, paired-end)":["per-base Phred drops below 20 in the last 20% of reads","duplication rate 65%","only 42% reads map to reference","rRNA fraction 45%","Q30 = 94% and >90% reads map, all metrics within spec","per-base quality dips slightly at read ends but trimming recovers it"],
 "single-cell RNA-seq (10x)":["ambient RNA / high mito% in 30% of cells","only 42% reads map to reference","3% mito in single-cell, doublet rate low, ambient RNA minimal","10% of samples fail library-complexity threshold"],
 "WGS germline (30x)":["mean coverage 8x for a germline caller","GC content bimodal / adapter contamination flagged","mean coverage 35x, uniform, no adapter contamination","Q30 = 78% overall"],
 "WES tumor/normal":["mean coverage 8x for a germline caller","only 42% reads map to reference","Q30 = 94% and >90% reads map, all metrics within spec"],
 "ChIP-seq (TF)":["duplication rate 65%","only 42% reads map to reference","all FastQC modules pass, GC unimodal, adapters trimmed cleanly"],
 "ATAC-seq":["duplication rate 65%","insert-size distribution shows adapter dimers","mean coverage 35x, uniform, no adapter contamination"],
 "16S amplicon metagenomics":["GC content bimodal / adapter contamination flagged","per-base Phred drops below 20 in the last 20% of reads","all FastQC modules pass, GC unimodal, adapters trimmed cleanly"],
 "whole-genome bisulfite":["per-base Phred drops below 20 in the last 20% of reads","Q30 = 78% overall","mean coverage 35x, uniform, no adapter contamination"],
 "nanopore long-read WGS":["Q30 = 78% overall","mean coverage 8x for a germline caller","insert-size distribution shows adapter dimers"],
 "CITE-seq (10x)":["ambient RNA / high mito% in 30% of cells","only 42% reads map to reference","3% mito in single-cell, doublet rate low, ambient RNA minimal"],
 "spatial transcriptomics (Visium)":["only 42% reads map to reference","GC content bimodal / adapter contamination flagged","all FastQC modules pass, GC unimodal, adapters trimmed cleanly"],
 "RRBS":["per-base Phred drops below 20 in the last 20% of reads","Q30 = 78% overall","duplication rate 65%"],
 "Ribo-seq":["rRNA fraction 45%","duplication rate 65%","per-base quality dips slightly at read ends but trimming recovers it"],
 "small RNA-seq":["insert-size distribution shows adapter dimers","duplication rate 65%","all FastQC modules pass, GC unimodal, adapters trimmed cleanly"],
 "cut&run":["duplication rate 65%","insert-size distribution shows adapter dimers","all FastQC modules pass, GC unimodal, adapters trimmed cleanly"],
}
jobs=[]
for _ in range(N):
    p=random.choice([k for k in PMAP]); jobs.append((p,random.choice(PMAP[p])))
# COHERENT
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
