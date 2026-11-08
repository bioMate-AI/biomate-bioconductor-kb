"""Merge all external corpus shards into one file with CROSS-SOURCE MinHash near-dedup (a vignette
quoted in a paper, a doc mirrored on multiple sites). Keeps provenance; writes a merge manifest."""
import argparse, glob, json, os, sys
sys.path.insert(0, os.path.dirname(__file__)); import common as C

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--dir", required=True); ap.add_argument("--out", required=True)
    a=ap.parse_args()
    dd=C.Deduper(); man=C.Manifest("external_merged"); f=C.open_out(a.out); kept=0
    for p in sorted(glob.glob(os.path.join(a.dir,"*.jsonl"))):
        b=os.path.basename(p)
        if b in ("external_corpus.jsonl",) or "diagfix" in b: continue
        for l in open(p):
            try: r=json.loads(l)
            except: continue
            t=r.get("text","")
            if len(t)<80: continue
            if not dd.add(t): man.bump(f"crossdedup_{r.get('source','?')}"); continue
            f.write(json.dumps(r)+"\n"); kept+=1
            man.bump(f"kept_{r.get('source','?')}", tok=C.tokens(t))
    f.close(); man.dump(a.out.replace(".jsonl","_manifest.json"))
    print(f"external_corpus: {kept} docs -> {a.out}")
    print("by source:", {k:v['n'] for k,v in man.c.items() if k.startswith('kept_')})

if __name__=="__main__": raise SystemExit(main())
