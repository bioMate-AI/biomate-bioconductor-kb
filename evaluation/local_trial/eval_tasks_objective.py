"""Objective per-task eval (no LLM judge): accept_set (routing), mcqa exact-match (knowledge/sci-QA).
Per-task small token budget, thinking stripped. Usage:
  python eval_tasks_objective.py --base <p> --adapter <p> --model <name> --evalfile objective_eval.jsonl --out o.json
"""
import argparse, json, os, re, sys, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from eval_removal import direct_load, call_direct_batch
def norm(s): return re.sub(r"[^a-z0-9]+"," ",str(s).lower()).strip()
def ans_of(o): return o.rsplit("</think>",1)[1].strip() if "</think>" in o else o.strip()
def first_letter(o):
    m=re.search(r"\b([ABCDE])\b", ans_of(o).upper()); return m.group(1) if m else ""
def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--base",required=True); ap.add_argument("--adapter",default="")
    ap.add_argument("--model",default="m"); ap.add_argument("--evalfile",required=True); ap.add_argument("--out",required=True)
    a=ap.parse_args(); os.environ["EVAL_DTYPE"]="bf16"
    direct_load(a.base, a.adapter or None)
    rows=[json.loads(l) for l in open(a.evalfile)]
    BS=int(os.environ.get("GEN_BATCH","24")); outs=[]
    for i in range(0,len(rows),BS):
        outs.extend(call_direct_batch([r["prompt"] for r in rows[i:i+BS]], 256))
        print(f"[obj] {min(i+BS,len(rows))}/{len(rows)}",flush=True)
    agg=collections.defaultdict(lambda:[0,0])
    for r,o in zip(rows,outs):
        t=r["task"]; ok=0
        if r["grader"]=="accept_set": ok=int(any(norm(x) in norm(ans_of(o)) for x in r["accept"]))
        elif r["grader"]=="mcqa": ok=int(first_letter(o)==str(r["gold"]).strip().upper())
        agg[t][0]+=ok; agg[t][1]+=1
    per={t:{"acc":round(v[0]/max(v[1],1),3),"n":v[1]} for t,v in agg.items()}
    macro=round(sum(p["acc"] for p in per.values())/max(len(per),1),3)
    json.dump({"model":a.model,"macro":macro,"per_task":per},open(a.out,"w"),indent=2)
    print("OBJ EVAL:",json.dumps({"model":a.model,"macro":macro,"per_task":per}))
if __name__=="__main__": raise SystemExit(main())
