"""v3 removal eval — harness. Runs a model on the removal cases (target workflow removed from
candidates) and scores out-of-catalog ability:
  - composed: did it produce a multi-step PLAN (vs pick one workflow as if exact)?
  - validity: named workflows are real & among candidates & not the removed target (no hallucination)?
  - coverage: LLM-judge — does the plan cover the removed workflow's ground-truth steps? (0..1)
Works against a cloud baseline (default gpt-5-mini) or the trained on-prem model served on vLLM
(--url http://127.0.0.1:8000/v1/chat/completions --model <served>). Establishes the bar the on-prem
model must match/beat."""
import json, os, sys, re, urllib.request, time, argparse
REPO=os.environ.get("REPO","/Users/kky/biomate-review"); D=os.environ.get("EVAL_DIR",f"{REPO}/docs/20260912_onprem_llm/routing_data_v1")
KEY=os.environ.get("OPENAI_API_KEY","")

INSTR=("You are BioMate. No single existing workflow may exactly fit this request. Decompose it into an "
       "ordered PLAN of steps; for EACH step name a workflow from the CANDIDATES that realizes it, or "
       "write \"GENERATE\" if no candidate fits, or \"RUN_CODE\" for a small ad-hoc step. "
       "Reply ONLY a JSON list of {\"step\": ..., \"workflow_or_action\": ...}.")

_DIRECT={"model":None,"tok":None}
def direct_load(base, adapter):
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import PeftModel
    tok=AutoTokenizer.from_pretrained(base, trust_remote_code=True)
    if tok.pad_token is None: tok.pad_token=tok.eos_token
    bnb=BitsAndBytesConfig(load_in_4bit=True, bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True, bnb_4bit_compute_dtype=torch.bfloat16)
    m=AutoModelForCausalLM.from_pretrained(base, quantization_config=bnb, device_map="auto",
        torch_dtype=torch.bfloat16, trust_remote_code=True, low_cpu_mem_usage=True)
    if adapter: m=PeftModel.from_pretrained(m, adapter)
    m.eval(); _DIRECT["model"]=m; _DIRECT["tok"]=tok

def call_direct(prompt, mx=400):
    import torch
    m=_DIRECT["model"]; tok=_DIRECT["tok"]
    enc=tok.apply_chat_template([{"role":"user","content":prompt}], add_generation_prompt=True,
        return_tensors="pt", return_dict=True); enc={k:v.to(m.device) for k,v in enc.items()}
    n=enc["input_ids"].shape[1]
    with torch.no_grad():
        out=m.generate(**enc, max_new_tokens=mx, do_sample=False, pad_token_id=tok.pad_token_id)
    return tok.decode(out[0][n:], skip_special_tokens=True)

def call_direct_batch(prompts, mx=300):
    """Batched greedy decode — left-padded for decoder-only. ~Bx faster than one-at-a-time."""
    import torch
    m=_DIRECT["model"]; tok=_DIRECT["tok"]
    tok.padding_side="left"
    strs=[tok.apply_chat_template([{"role":"user","content":p}], add_generation_prompt=True, tokenize=False) for p in prompts]
    enc=tok(strs, return_tensors="pt", padding=True, truncation=True, max_length=1024, add_special_tokens=False)
    enc={k:v.to(m.device) for k,v in enc.items()}
    n=enc["input_ids"].shape[1]
    with torch.no_grad():
        out=m.generate(**enc, max_new_tokens=mx, do_sample=False, pad_token_id=tok.pad_token_id)
    return [tok.decode(o[n:], skip_special_tokens=True) for o in out]

def call(url, model, prompt, mx=1600):   # always the API path (used by the model-under-test AND the judge)
    # gpt-5.x are reasoning models: NO temperature (only default supported) and reasoning eats the
    # token budget -> set reasoning_effort=low + a generous max_completion_tokens (else empty content).
    payload={"model":model,"messages":[{"role":"user","content":prompt}],"max_completion_tokens":mx}
    if model.startswith("gpt-5"): payload["reasoning_effort"]="low"
    else: payload["temperature"]=0
    body=json.dumps(payload).encode()
    h={"Content-Type":"application/json"}
    if "openai.com" in url or (KEY and "127.0.0.1" not in url): h["Authorization"]=f"Bearer {KEY}"
    for a in range(3):
        try:
            d=json.load(urllib.request.urlopen(urllib.request.Request(url,data=body,headers=h),timeout=120))
            return d["choices"][0]["message"]["content"]
        except Exception: time.sleep(1.5*(a+1))
    return ""

def judge(gt_steps, plan_text):
    gt="; ".join(s["step"] for s in gt_steps)
    p=(f"Ground-truth analysis steps: {gt}\n\nProposed plan:\n{plan_text}\n\n"
       "What FRACTION (0.0-1.0) of the ground-truth steps are covered by the proposed plan "
       "(semantically, order-insensitive)? Reply ONLY the number.")
    out=call("https://api.openai.com/v1/chat/completions","gpt-5-mini",p,mx=2000)
    m=re.search(r"[01]?\.\d+|[01]", out or "")
    return float(m.group(0)) if m else 0.0

def grounded_only(plan_text, cands):
    """Keep only plan steps whose workflow_or_action names a REAL candidate (grounded metric v2)."""
    try: arr=json.loads(re.search(r"\[.*\]", plan_text, re.S).group(0))
    except Exception:
        st=re.findall(r'"step"\s*:\s*"([^"]+)"', plan_text); ac=re.findall(r'"workflow_or_action"\s*:\s*"([^"]+)"', plan_text)
        arr=[{"step":s,"workflow_or_action":a} for s,a in zip(st,ac)]
    kept=[x for x in arr if isinstance(x,dict) and x.get("workflow_or_action") in cands]
    return json.dumps(kept) if kept else ""

def neg_penalty(plan_text):
    p=("Below is a proposed bioinformatics analysis plan. Count DISQUALIFYING errors (e.g. log/CPM-"
       "normalizing before a raw-count model like DESeq2/edgeR; batch-correcting normalized data with a "
       "count method; wrong data type into a tool; invalid ordering). Reply ONLY an integer count.\n\n"
       f"Plan:\n{plan_text}")
    out=call("https://api.openai.com/v1/chat/completions","gpt-5-mini",p,mx=1500)
    m=re.search(r"\d+", out or ""); return min(1.0, 0.25*(int(m.group(0)) if m else 0))

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--url",default="https://api.openai.com/v1/chat/completions")
    ap.add_argument("--model",default="gpt-5-mini"); ap.add_argument("--limit",type=int,default=80)
    ap.add_argument("--out",default=f"{D}/removal_eval_result.json")
    ap.add_argument("--direct",action="store_true",help="load base+adapter locally (on the GPU box)")
    ap.add_argument("--base",default=""); ap.add_argument("--adapter",default="")
    a=ap.parse_args()
    if a.direct: direct_load(a.base, a.adapter or None)   # model-under-test = the trained local model
    rows=[json.loads(l) for l in open(f"{D}/removal_eval.jsonl")][:a.limit]
    composed=valid=n=0; cov=0.0; gcov=0.0; gsc=0.0; details=[]
    for r in rows:
        cands=set(r["candidates"]); W=r["removed_workflow"]
        prompt=f"{INSTR}\n\nCandidates:\n"+"\n".join(f"- {c}" for c in r["candidates"])+f"\n\nRequest: {r['query']}"
        resp=call_direct(prompt,400) if a.direct else call(a.url,a.model,prompt)
        if not resp: continue
        n+=1
        named=re.findall(r'"workflow_or_action"\s*:\s*"([^"]+)"', resp)
        steps=re.findall(r'"step"\s*:\s*"[^"]+"', resp)
        is_plan=len(steps)>=2
        composed+=is_plan
        picks=[x for x in named if x not in ("GENERATE","RUN_CODE")]
        ok_valid = all((x in cands) for x in picks) and (W not in picks)   # real, available, not the removed one
        valid+=ok_valid
        cv=judge(r["ground_truth_steps"], resp); cov+=cv
        # grounded metric v2: credit only milestones realized by a real candidate, x (1-neg_penalty)
        gplan=grounded_only(resp, cands)
        gc=judge(r["ground_truth_steps"], gplan) if gplan else 0.0
        gs=gc*(1-neg_penalty(resp)) if gc>0 else 0.0
        gcov+=gc; gsc+=gs
        details.append({"W":W,"domain":r.get("domain",""),"plan":is_plan,"valid":ok_valid,
                        "coverage":round(cv,2),"grounded":round(gc,2),"gscore":round(gs,2)})
    # committee-v3 fix #6: macro-average over domains (not transcriptomics-dominated micro) + nonzero mean
    import collections as _c
    bydom=_c.defaultdict(list)
    for x in details: bydom[x["domain"] or "?"].append(x["coverage"])
    dom_means={d:round(sum(v)/len(v),3) for d,v in bydom.items()}
    macro=round(sum(dom_means.values())/max(len(dom_means),1),3)
    gbydom=_c.defaultdict(list)
    for x in details: gbydom[x["domain"] or "?"].append(x.get("gscore",0.0))
    gmacro=round(sum(sum(v)/len(v) for v in gbydom.values())/max(len(gbydom),1),3)
    nz=[x["coverage"] for x in details if x["coverage"]>0]
    res={"model":a.model,"n":n,"composed_rate":round(composed/max(n,1),3),
         "validity_rate":round(valid/max(n,1),3),
         "micro_step_coverage":round(cov/max(n,1),3),          # OLD (paraphrase-inflated) metric
         "macro_step_coverage":macro,
         "grounded_micro":round(gcov/max(n,1),3),              # NEW grounded metric v2 (non-gameable)
         "gscore_micro":round(gsc/max(n,1),3), "gscore_macro":gmacro,
         "nonzero_mean_coverage":round(sum(nz)/max(len(nz),1),3), "nonzero_frac":round(len(nz)/max(n,1),3),
         "per_domain":dom_means}
    json.dump({"summary":res,"details":details},open(a.out,"w"),indent=2)
    print("REMOVAL EVAL:",json.dumps(res))

if __name__=="__main__": raise SystemExit(main())
