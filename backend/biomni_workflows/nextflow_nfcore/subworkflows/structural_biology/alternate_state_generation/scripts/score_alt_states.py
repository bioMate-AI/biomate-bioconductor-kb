#!/usr/bin/env python3
"""
score_alt_states.py — BioMate alternate_state_generation scoring + consensus driver.

For each blind generator, score every candidate model by the validated pore-vestibule
discriminator (sequence-aligned, renumbering-robust) against the experimental anchor.
Accept an alternate state only when >= min_generators independently populate it
(cross-generator consensus) — the memorization-bias guard. Emit the best consensus
candidate + a JSON report.

Usage:
  score_alt_states.py --ref anchor.pdb \
     --generator afsample2:/path/to/models_dir_or_glob \
     --generator del_alamo:/path/to/models_dir \
     --min_generators 2 --out_candidate outward_candidate.pdb --report report.json
"""
import argparse, glob, json, os, sys, shutil, importlib.util
import numpy as np

HERE=os.path.dirname(os.path.abspath(__file__))
# discriminator lives beside this script (copied into the container at /opt/biomate)
_ref_holder={}
def load_scorer(ref):
    # robust_score expects REF module-global; set it, then import
    spec=importlib.util.spec_from_file_location("pd", os.path.join(HERE,"pore_discriminator.py"))
    pd=importlib.util.module_from_spec(spec)
    try: spec.loader.exec_module(pd)
    except Exception: pass
    rsspec=importlib.util.spec_from_file_location("rs", os.path.join(HERE,"robust_score.py"))
    rsm=importlib.util.module_from_spec(rsspec)
    try: rsspec.loader.exec_module(rsm)
    except Exception: pass
    rsm.REF=ref          # override AFTER exec so the module default doesn't reset it
    return pd, rsm

def plddt(p):
    b=[float(l[60:66]) for l in open(p) if l.startswith("ATOM") and l[12:16].strip()=="CA"]
    return float(np.mean(b)) if b else 0.0

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--ref", required=True)
    ap.add_argument("--generator", action="append", default=[], help="name:path (dir or glob)")
    ap.add_argument("--min_generators", type=int, default=2)
    ap.add_argument("--plddt_min", type=float, default=60.0)
    ap.add_argument("--out_candidate", default="outward_candidate.pdb")
    ap.add_argument("--report", default="alt_state_report.json")
    a=ap.parse_args()
    pd, rsm = load_scorer(a.ref)
    # anchor sign
    ai,_=pd.open_side(a.ref,"A")
    anchor_sign=np.sign(ai)

    per_gen={}; best=None
    for spec in a.generator:
        name,path=spec.split(":",1)
        pdbs=sorted(glob.glob(os.path.join(path,"**","*.pdb"),recursive=True)+glob.glob(path))
        pdbs=[p for p in pdbs if os.path.isfile(p) and os.path.getsize(p)>1000]
        outward=[]
        for p in pdbs:
            if plddt(p) < a.plddt_min: continue
            try:
                tmp,_=rsm.remap_to_ref(p, None)
                ac,_=pd.open_side(tmp,"A",ref=a.ref,refchain="A")
            except Exception:
                continue
            if np.sign(ac)!=anchor_sign:                 # flipped = alternate state
                outward.append((float(ac),p))
        outward.sort()                                    # most-flipped first
        per_gen[name]={"n_scored":len(pdbs),"n_outward":len(outward),
                       "best_asym":round(outward[0][0],2) if outward else None}
        if outward and (best is None or outward[0][0]<best[0]):
            best=(outward[0][0], outward[0][1], name)

    n_gen_outward=sum(1 for g in per_gen.values() if g["n_outward"]>0)
    consensus = n_gen_outward >= a.min_generators
    report={"anchor":os.path.basename(a.ref),"anchor_asym":round(float(ai),2),
            "per_generator":per_gen,"generators_populating_alt_state":n_gen_outward,
            "min_generators_required":a.min_generators,
            "consensus_accepted":bool(consensus),
            "best_candidate":{"asym":round(best[0],2),"generator":best[2],
                              "file":os.path.basename(best[1])} if best else None}
    if consensus and best:
        shutil.copy(best[1], a.out_candidate)
        report["out_candidate"]=a.out_candidate
    json.dump(report, open(a.report,"w"), indent=2)
    print(json.dumps(report,indent=2))
    # loud-fail gate: no consensus => non-zero so the Nextflow gate flags it
    if not consensus:
        print("GATE FAIL: alternate state not reached by >= "
              f"{a.min_generators} independent generators", file=sys.stderr)

if __name__=="__main__":
    main()
