"""Build the decontamination index from our holdout + SFT files and pickle it, so every fetcher can
drop corpus docs that leak eval/train text. Run FIRST, before the fetchers."""
import argparse, os, sys, pickle
sys.path.insert(0, os.path.dirname(__file__)); import common as C

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--sft", nargs="*", default=[]); ap.add_argument("--holdout", nargs="*", default=[])
    ap.add_argument("--out", required=True); ap.add_argument("--n", type=int, default=13)
    a=ap.parse_args()
    dec=C.Decontaminator(n=a.n)
    for p in list(a.sft)+list(a.holdout):
        before=len(dec.grams); dec.load_jsonl(p); print(f"{p}: +{len(dec.grams)-before} n-grams")
    pickle.dump(dec, open(a.out,"wb"))
    print(f"decontam index: {len(dec.grams)} {a.n}-grams -> {a.out}")

if __name__=="__main__": raise SystemExit(main())
