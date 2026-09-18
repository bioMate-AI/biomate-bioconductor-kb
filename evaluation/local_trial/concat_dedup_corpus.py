"""Concat all mid-training corpus shards (internal + code + gtn + external) -> one deduped text file."""
import json, glob, hashlib, sys, os
D=sys.argv[1] if len(sys.argv)>1 else "/opt/dlami/nvme/midtrain_corpus"
out=os.path.join(D,"midtrain_all.jsonl"); seen=set(); n=0; toks=0
with open(out,"w") as f:
    for p in sorted(glob.glob(os.path.join(D,"*.jsonl"))):
        if p.endswith("midtrain_all.jsonl"): continue
        for l in open(p):
            try: r=json.loads(l)
            except: continue
            t=r.get("text","")
            if len(t)<80: continue
            h=hashlib.sha256(t.encode()).hexdigest()[:16]
            if h in seen: continue
            seen.add(h); f.write(json.dumps({"text":t})+"\n"); n+=1; toks+=len(t)//4
print(f"midtrain_all.jsonl: {n} docs, ~{toks/1e6:.1f}M tokens -> {out}")
