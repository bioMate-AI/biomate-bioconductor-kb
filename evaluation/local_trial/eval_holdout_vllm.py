import argparse, json, re, time, urllib.request
def norm(s): return re.sub(r"[^a-z0-9]+"," ",str(s).lower()).strip()
def score(bench,it,gold,out):
    o=norm(out)
    if bench=="cross_domain_routing":
        raw=gold.get("correct_workflow",it.get("correct_workflow","")); cw=norm(raw)
        core=norm(str(raw).split("/")[-1])  # e.g. nf-core/rnaseq -> rnaseq
        alts=[norm(a) for a in (it.get("acceptable_alts") or [])]
        if not cw: return None
        if cw in o or (core and core in o): return 1.0
        return 0.5 if any(a and (a in o or norm(a.split("/")[-1]) in o) for a in alts) else 0.0
    if bench=="autofix_benchmark":
        cat=norm(gold.get("category",it.get("category",""))); return None if not cat else (1.0 if cat in o else 0.0)
    if bench=="param_prefill":
        exp=gold.get("expected_params",it.get("expected_params",{})) or {}; 
        return None if not exp else sum(1 for v in exp.values() if norm(v) and norm(v) in o)/len(exp)
    return None
P={"cross_domain_routing":lambda it:"Name the single correct bioinformatics WORKFLOW (nf-core pipeline name) for this request. Reply with only the name.\n\nRequest: "+str(it.get("query","")),
"autofix_benchmark":lambda it:"A pipeline failed. Classify the failure into one fix category (e.g. genome_mismatch, missing_input, resource_limit, container_error). Reply with only the category.\n\nWorkflow: "+str(it.get("workflow",""))+"\nError:\n"+str(it.get("error_log",""))[:1200],
"param_prefill":lambda it:"Extract workflow parameters explicitly implied by this request as key: value lines; do not invent unspecified params.\n\nRequest: "+str(it.get("user_query",it.get("query","")))}
def call(url,model,prompt):
    body=json.dumps({"model":model,"messages":[{"role":"user","content":prompt}],"max_tokens":80,"temperature":0,"chat_template_kwargs":{"enable_thinking":False}}).encode()
    r=urllib.request.urlopen(urllib.request.Request(url,data=body,headers={"Content-Type":"application/json"}),timeout=120)
    return json.load(r)["choices"][0]["message"]["content"]
def main():
    ap=argparse.ArgumentParser(); ap.add_argument("--url",default="http://127.0.0.1:8000/v1/chat/completions")
    ap.add_argument("--holdout",required=True); ap.add_argument("--limit-per",type=int,default=40); ap.add_argument("--out",default="vllm_eval.json")
    ap.add_argument("--base-model",default="base"); ap.add_argument("--sft-model",default="sft")
    a=ap.parse_args()
    rows=[json.loads(l) for l in open(a.holdout) if l.strip()]; by={}
    for r in rows: by.setdefault(r["benchmark"],[]).append(r)
    rep={"per_benchmark":{}}
    for b in ["cross_domain_routing","autofix_benchmark","param_prefill"]:
        items=by.get(b,[])[:a.limit_per]; 
        if not items: continue
        bs=ss=n=0.0
        for r in items:
            it=r["input_item"]; gold=r.get("ground_truth",{}); pr=P[b](it)
            try: bo=call(a.url,a.base_model,pr); so=call(a.url,a.sft_model,pr)
            except Exception as e: continue
            x=score(b,it,gold,bo); y=score(b,it,gold,so)
            if x is None or y is None: continue
            bs+=x; ss+=y; n+=1
        if n: rep["per_benchmark"][b]={"n":int(n),"base":round(bs/n,4),"sft":round(ss/n,4),"delta":round((ss-bs)/n,4)}; print(b,"n=%d base=%.3f sft=%.3f delta=%+.3f"%(n,bs/n,ss/n,(ss-bs)/n))
    json.dump(rep,open(a.out,"w"),indent=2); print("WROTE",a.out)
main()
