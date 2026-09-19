"""v3 removal eval — harness. Runs a model on the removal cases (target workflow removed from
candidates) and scores out-of-catalog ability:
  - composed: did it produce a multi-step PLAN (vs pick one workflow as if exact)?
  - validity: named workflows are real & among candidates & not the removed target (no hallucination)?
  - coverage: LLM-judge — does the plan cover the removed workflow's ground-truth steps? (0..1)
Works against a cloud baseline (default gpt-5-mini) or the trained on-prem model served on vLLM
(--url http://127.0.0.1:8000/v1/chat/completions --model <served>). Establishes the bar the on-prem
model must match/beat."""
import json, os, sys, re, urllib.request, time, argparse
REPO="/Users/kky/biomate-review"; D=f"{REPO}/docs/20260912_onprem_llm/routing_data_v1"
KEY=os.environ.get("OPENAI_API_KEY","")

INSTR=("You are BioMate. No single existing workflow may exactly fit this request. Decompose it into an "
       "ordered PLAN of steps; for EACH step name a workflow from the CANDIDATES that realizes it, or "
       "write \"GENERATE\" if no candidate fits, or \"RUN_CODE\" for a small ad-hoc step. "
       "Reply ONLY a JSON list of {\"step\": ..., \"workflow_or_action\": ...}.")

def call(url, model, prompt, mx=600):
    body=json.dumps({"model":model,"messages":[{"role":"user","content":prompt}],
                     "max_completion_tokens":mx,"temperature":0}).encode()
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

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--url",default="https://api.openai.com/v1/chat/completions")
    ap.add_argument("--model",default="gpt-5-mini"); ap.add_argument("--limit",type=int,default=80)
    ap.add_argument("--out",default=f"{D}/removal_eval_result.json")
    a=ap.parse_args()
    rows=[json.loads(l) for l in open(f"{D}/removal_eval.jsonl")][:a.limit]
    composed=valid=n=0; cov=0.0; details=[]
    for r in rows:
        cands=set(r["candidates"]); W=r["removed_workflow"]
        prompt=f"{INSTR}\n\nCandidates:\n"+"\n".join(f"- {c}" for c in r["candidates"])+f"\n\nRequest: {r['query']}"
        resp=call(a.url,a.model,prompt)
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
        details.append({"W":W,"plan":is_plan,"valid":ok_valid,"coverage":round(cv,2)})
    res={"model":a.model,"n":n,"composed_rate":round(composed/max(n,1),3),
         "validity_rate":round(valid/max(n,1),3),"mean_step_coverage":round(cov/max(n,1),3)}
    json.dump({"summary":res,"details":details},open(a.out,"w"),indent=2)
    print("REMOVAL EVAL:",json.dumps(res))

if __name__=="__main__": raise SystemExit(main())
