"""Pre-training validation + cleaning gate for the SFT set (committee-audit driven). Rule-based
(CLAUDE.md: rules first). Fixes/drops the CONFIRMED defects:
  1. param type violations: integer/count params with fractional values (nPerm=0.01) -> drop that key
  2. genome enum normalization in gold values: hg38->GRCh38, mm10->GRCm38, hg19->GRCh37, mm9->GRCm37
  3. FDR/p-value scale sanity: a param named *fdr*/*pval*/*qval* with value >1 -> likely percent -> /100
  4. structural: exactly 2 msgs, non-empty; rag_routing gold MUST be in the candidate block
  5. truncation: user request ending mid-sentence -> trim to last sentence boundary; drop if unrecoverable
Writes a cleaned file + a report. Does NOT fabricate content (per committee: never repair by generating)."""
import json, re, sys, collections
IN=sys.argv[1] if len(sys.argv)>1 else "docs/20260912_onprem_llm/routing_data_v1/multitask_sft_paraphrased.jsonl"
OUT=IN.replace(".jsonl","_clean.jsonl")

INTPARAM=re.compile(r"(?i)(iter|nperm|n_?perm|nboot|nrep|threads|cpus|ncore|nreads|readlen|read_length|"
                    r"kmer|k_?mer|nfeatures|n_?features|mincount|min_count|maxcount|topgenes|topsamples|"
                    r"num[_a-z]*|nsection|ntissue|nprofile|_count\b|count$|_n$|size$|nclust|n_clust|epochs?)")
FDRP=re.compile(r"(?i)(fdr|pval|p_?value|qval|q_?value|alpha|significance)")
GENOME={r"\bhg38\b":"GRCh38", r"\bhg19\b":"GRCh37", r"\bmm10\b":"GRCm38", r"\bmm9\b":"GRCm37",
        r"\bhg18\b":"NCBI36"}

def norm_genome(s):
    for k,v in GENOME.items(): s=re.sub(k, v, s, flags=re.I)
    return s

def clean_param_gold(g):
    """g is a JSON object string of params. Returns (cleaned_json_or_None, changes)."""
    try: d=json.loads(g)
    except Exception: return g, []
    if not isinstance(d, dict): return g, []
    changes=[]; out={}
    for k,v in d.items():
        # type violation: int-named param with fractional value in (0,1)
        if isinstance(v,(int,float)) and INTPARAM.search(k) and 0<float(v)<1:
            changes.append(f"drop_int_frac:{k}={v}"); continue
        # FDR/p scale: value >1 on a probability param -> percent -> /100
        if isinstance(v,(int,float)) and FDRP.search(k) and float(v)>1:
            out[k]=round(float(v)/100,6); changes.append(f"fdr_scale:{k} {v}->{out[k]}"); continue
        # genome enum in string values
        if isinstance(v,str):
            nv=norm_genome(v)
            if nv!=v: changes.append(f"genome:{v}->{nv}")
            out[k]=nv; continue
        out[k]=v
    return (json.dumps(out) if out else None), changes

def last_sentence_trim(s):
    """trim a mid-sentence-truncated request to the last complete sentence; None if unrecoverable."""
    s=s.rstrip()
    if re.search(r'[.!?)\]"]$', s): return s          # already clean
    m=list(re.finditer(r'[.!?]["\')\]]?\s', s))
    if m and m[-1].end()>len(s)*0.5:                   # keep if >=half survives
        return s[:m[-1].end()].rstrip()
    return None                                        # too little left -> drop

def main():
    rows=[json.loads(l) for l in open(IN) if l.strip()]
    rep=collections.Counter(); out=[]; param_changes=collections.Counter()
    for r in rows:
        m=r.get("messages",[])
        if len(m)!=2 or not str(m[0].get("content","")).strip() or not str(m[1].get("content","")).strip():
            rep["drop_structural"]+=1; continue
        u=m[0]["content"]; a=m[1]["content"]
        # rag_routing: gold must be in candidates
        if "Retrieved candidates:" in u:
            block=u.split("Retrieved candidates:")[1].split("Request:")[0]
            cands=[l.strip("- ").strip() for l in block.split("\n") if l.strip().startswith("-")]
            if a.strip() not in cands: rep["drop_rag_gold_missing"]+=1; continue
        # param gold cleaning (only when gold looks like a param JSON object)
        if a.strip().startswith("{") and '"' in a and "clarify_needed" not in a and "root_cause" not in a:
            cleaned,ch=clean_param_gold(a)
            for c in ch: param_changes[c.split(":")[0]]+=1
            if ch:
                if cleaned is None: rep["drop_param_emptied"]+=1; continue
                a=cleaned; m[1]["content"]=a; rep["param_fixed"]+=1
        # truncation: trim the request span (skip diag_fix/autofix where error logs are inherently clipped)
        if "ERROR LOG" not in u and "Error log" not in u:
            for mark in ["Request: ","Request:\n","INPUT:\n","User query:\n"]:
                if mark in u:
                    pre,req=u.rsplit(mark,1)
                    if req and req.rstrip()[-1:].isalnum() and not re.search(r'[.!?)\]"]$', req.rstrip()):
                        t=last_sentence_trim(req)
                        if t is None: rep["drop_truncated_query"]+=1; req=None
                        elif t!=req.rstrip(): rep["trimmed_query"]+=1; m[0]["content"]=pre+mark+t
                    break
            else: req="ok"
            if req is None: continue
        out.append({"messages":m})
    open(OUT,"w").write("\n".join(json.dumps(r) for r in out))
    print(f"VALIDATE_SFT: {len(rows)} -> {len(out)} kept")
    print("actions:", dict(rep))
    print("param changes by type:", dict(param_changes))

if __name__=="__main__": raise SystemExit(main())
