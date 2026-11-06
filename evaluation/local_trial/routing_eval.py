"""2x2 routing eval over a vLLM endpoint: {base,sft} x {starved,in-format}.
Scores select-from-candidates top-1 (correct or acceptable_alt), paired bootstrap CI,
saves every raw output. Uses the SHARED routing_prompt so eval == train protocol."""
import argparse, json, re, sys, urllib.request, random
sys.path.insert(0, __file__.rsplit("/",1)[0])
from routing_prompt import build_messages
random.seed(1)
def norm(s): return re.sub(r"[^a-z0-9]+"," ",str(s).lower()).strip()

def select(out, candidates):
    """Which candidate did the model choose? exact/substring match; fallback None."""
    o=norm(out)
    # prefer exact candidate whose normalized form appears
    hits=[c for c in candidates if norm(c) and norm(c) in o]
    if hits: return max(hits,key=lambda c:len(norm(c)))  # longest match wins
    # core-token fallback (last path segment)
    for c in candidates:
        core=norm(str(c).split("/")[-1])
        if core and core in o: return c
    return out.strip()

def is_correct(sel, correct, alts):
    gold={norm(correct)}|{norm(a) for a in (alts or [])}
    s=norm(sel)
    return 1.0 if s in gold or any(g and (g in s or s in g) for g in gold) else 0.0

def call(url, model, messages):
    body=json.dumps({"model":model,"messages":messages,"max_tokens":40,"temperature":0,
                     "chat_template_kwargs":{"enable_thinking":False}}).encode()
    r=urllib.request.urlopen(urllib.request.Request(url,data=body,headers={"Content-Type":"application/json"}),timeout=120)
    return json.load(r)["choices"][0]["message"]["content"]

def boot(pairs, idx_a, idx_b, n=2000):
    import random as R; R.seed(0); N=len(pairs); diffs=[]
    for _ in range(n):
        s=[pairs[R.randrange(N)] for _ in range(N)]
        diffs.append(sum(p[idx_a] for p in s)/N - sum(p[idx_b] for p in s)/N)
    diffs.sort(); return diffs[int(.025*n)], diffs[int(.975*n)]

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--url",default="http://127.0.0.1:8000/v1/chat/completions")
    ap.add_argument("--eval",required=True); ap.add_argument("--out",default="routing_eval_result.json")
    ap.add_argument("--raw",default="routing_eval_raw.jsonl"); ap.add_argument("--limit",type=int,default=0)
    a=ap.parse_args()
    items=[json.loads(l) for l in open(a.eval) if l.strip()]
    if a.limit: items=items[:a.limit]
    conds=[("base","starved"),("base","informat"),("sft","informat"),("sft","starved")]
    scores={c:[] for c in conds}; raw=open(a.raw,"w")
    for it in items:
        row={"id":it.get("id"),"correct":it["correct_workflow"]}
        rec={}
        for model,mode in conds:
            msgs=build_messages(it["query"], it.get("candidates",[]), in_format=(mode=="informat"))
            try: outp=call(a.url,model,msgs)
            except Exception as e: outp=f"__ERR__{e}"
            sel=select(outp, it.get("candidates",[]))
            sc=is_correct(sel, it["correct_workflow"], it.get("acceptable_alts"))
            scores[(model,mode)].append(sc); rec[f"{model}_{mode}"]={"out":outp[:120],"sel":sel,"score":sc}
        row["conds"]=rec; raw.write(json.dumps(row)+"\n")
    raw.close()
    n=len(items)
    res={"n":n,"accuracy":{f"{m}_{md}":round(sum(scores[(m,md)])/n,4) for m,md in conds}}
    # paired diffs
    pairs=list(zip(scores[("base","starved")],scores[("base","informat")],scores[("sft","informat")],scores[("sft","starved")]))
    lo,hi=boot(pairs,2,1); res["sft_lift_over_base_informat"]={"delta":round(res["accuracy"]["sft_informat"]-res["accuracy"]["base_informat"],4),"ci95":[round(lo,4),round(hi,4)]}
    lo2,hi2=boot(pairs,1,0); res["candidate_context_effect"]={"delta":round(res["accuracy"]["base_informat"]-res["accuracy"]["base_starved"],4),"ci95":[round(lo2,4),round(hi2,4)]}
    json.dump(res,open(a.out,"w"),indent=2)
    print(json.dumps(res,indent=2))
main()
