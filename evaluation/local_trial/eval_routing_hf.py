"""2x2 routing eval WITHOUT vLLM: load base 4-bit + LoRA once; toggle disable_adapter()
for base vs sft. Reuses routing_prompt + identical select/is_correct/boot as routing_eval.py."""
import argparse, json, re, sys, random
sys.path.insert(0, __file__.rsplit("/",1)[0])
from routing_prompt import build_messages
random.seed(1)
def norm(s): return re.sub(r"[^a-z0-9]+"," ",str(s).lower()).strip()
def select(out, candidates):
    o=norm(out); hits=[c for c in candidates if norm(c) and norm(c) in o]
    if hits: return max(hits,key=lambda c:len(norm(c)))
    for c in candidates:
        core=norm(str(c).split("/")[-1])
        if core and core in o: return c
    return out.strip()
def is_correct(sel, correct, alts):
    gold={norm(correct)}|{norm(a) for a in (alts or [])}; s=norm(sel)
    return 1.0 if s in gold or any(g and (g in s or s in g) for g in gold) else 0.0
def boot(pairs, ia, ib, n=2000):
    import random as R; R.seed(0); N=len(pairs); d=[]
    for _ in range(n):
        s=[pairs[R.randrange(N)] for _ in range(N)]
        d.append(sum(p[ia] for p in s)/N - sum(p[ib] for p in s)/N)
    d.sort(); return d[int(.025*n)], d[int(.975*n)]
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--base",required=True); ap.add_argument("--adapter",required=True)
    ap.add_argument("--eval",required=True); ap.add_argument("--out",default="routing_eval_result.json")
    ap.add_argument("--raw",default="routing_eval_raw.jsonl"); ap.add_argument("--limit",type=int,default=0)
    a=ap.parse_args()
    import torch
    from transformers import AutoModelForCausalLM, AutoTokenizer, BitsAndBytesConfig
    from peft import PeftModel
    tok=AutoTokenizer.from_pretrained(a.base, trust_remote_code=True)
    if tok.pad_token is None: tok.pad_token=tok.eos_token
    bnb=BitsAndBytesConfig(load_in_4bit=True,bnb_4bit_quant_type="nf4",bnb_4bit_use_double_quant=True,bnb_4bit_compute_dtype=torch.bfloat16)
    model=AutoModelForCausalLM.from_pretrained(a.base,quantization_config=bnb,device_map="auto",torch_dtype=torch.bfloat16,trust_remote_code=True,low_cpu_mem_usage=True)
    model=PeftModel.from_pretrained(model,a.adapter); model.eval()
    def gen(messages):
        try: enc=tok.apply_chat_template(messages,add_generation_prompt=True,return_tensors="pt",return_dict=True,enable_thinking=False)
        except TypeError: enc=tok.apply_chat_template(messages,add_generation_prompt=True,return_tensors="pt",return_dict=True)
        enc={k:v.to(model.device) for k,v in enc.items()}; il=enc["input_ids"].shape[1]
        with torch.no_grad(): o=model.generate(**enc,max_new_tokens=40,do_sample=False,pad_token_id=tok.pad_token_id)
        return tok.decode(o[0][il:],skip_special_tokens=True)
    items=[json.loads(l) for l in open(a.eval) if l.strip()]
    if a.limit: items=items[:a.limit]
    conds=[("base","starved"),("base","informat"),("sft","informat"),("sft","starved")]
    scores={c:[] for c in conds}; raw=open(a.raw,"w")
    for i,it in enumerate(items):
        rec={}
        for mdl,mode in conds:
            msgs=build_messages(it["query"], it.get("candidates",[]), in_format=(mode=="informat"))
            if mdl=="base":
                with model.disable_adapter(): outp=gen(msgs)
            else: outp=gen(msgs)
            sel=select(outp,it.get("candidates",[])); sc=is_correct(sel,it["correct_workflow"],it.get("acceptable_alts"))
            scores[(mdl,mode)].append(sc); rec[f"{mdl}_{mode}"]={"out":outp[:120],"sel":sel,"score":sc}
        raw.write(json.dumps({"id":it.get("id"),"correct":it["correct_workflow"],"conds":rec})+"\n")
        if i%25==0: print(f"  {i}/{len(items)}",flush=True)
    raw.close(); n=len(items)
    res={"n":n,"accuracy":{f"{m}_{md}":round(sum(scores[(m,md)])/n,4) for m,md in conds}}
    pairs=list(zip(scores[("base","starved")],scores[("base","informat")],scores[("sft","informat")],scores[("sft","starved")]))
    lo,hi=boot(pairs,2,1); res["sft_lift_over_base_informat"]={"delta":round(res["accuracy"]["sft_informat"]-res["accuracy"]["base_informat"],4),"ci95":[round(lo,4),round(hi,4)]}
    lo2,hi2=boot(pairs,1,0); res["candidate_context_effect"]={"delta":round(res["accuracy"]["base_informat"]-res["accuracy"]["base_starved"],4),"ci95":[round(lo2,4),round(hi2,4)]}
    json.dump(res,open(a.out,"w"),indent=2); print(json.dumps(res,indent=2))
main()
