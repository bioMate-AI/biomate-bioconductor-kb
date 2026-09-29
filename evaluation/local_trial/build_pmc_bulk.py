import argparse, json, os, re, glob
ap=argparse.ArgumentParser(); ap.add_argument("--dir",required=True); ap.add_argument("--out",required=True)
ap.add_argument("--max-tokens",type=int,default=3_000_000_000); a=ap.parse_args()
n=toks=0
with open(a.out,"w") as fo:
    for p in glob.iglob(os.path.join(a.dir,"**","*.txt"),recursive=True):
        try: t=open(p,encoding="utf-8",errors="ignore").read()
        except Exception: continue
        t=re.sub(r"\s+"," ",t).strip()
        if len(t)>500:
            fo.write(json.dumps({"text":t[:20000],"source":"pmc_fulltext_bulk"})+"\n"); n+=1; toks+=len(t)//4
        if toks>=a.max_tokens: break
print(f"PMC BULK: {n} articles ~{toks:,} tok -> {a.out}",flush=True)
