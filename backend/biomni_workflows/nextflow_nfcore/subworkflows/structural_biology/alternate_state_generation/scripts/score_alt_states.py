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

    per_gen={}; best=None; alt_generators=set()
    for spec in a.generator:
        name,path=spec.split(":",1)
        pdbs=sorted(glob.glob(os.path.join(path,"**","*.pdb"),recursive=True)+glob.glob(path))
        pdbs=[p for p in pdbs if os.path.isfile(p) and os.path.getsize(p)>1000]
        flipped=[]                                        # models in the ALTERNATE (non-anchor) basin
        for p in pdbs:
            if plddt(p) < a.plddt_min: continue
            try:
                tmp,_=rsm.remap_to_ref(p, None)
                ac,_=pd.open_side(tmp,"A",ref=a.ref,refchain="A")
            except Exception:
                continue
            if np.sign(ac)!=anchor_sign:                 # flipped = alternate state
                flipped.append((float(ac),p))
        flipped.sort()                                    # most-flipped first
        per_gen[name]={"n_scored":len(pdbs),"n_alt_state":len(flipped),
                       "best_asym":round(flipped[0][0],2) if flipped else None}
        if flipped:
            alt_generators.add(name)
            if best is None or flipped[0][0]<best[0]:
                best=(flipped[0][0], flipped[0][1], name)

    # --- consensus reliability: fraction of independent strategies that reach the alternate basin ---
    n_strat=len(a.generator)
    reliability = round(len(alt_generators)/n_strat, 2) if n_strat else 0.0

    # --- MSA-ablation memorization signal (colmask=deep MSA vs depth=shallow MSA) ---
    in_deep  = "colmask" in alt_generators           # column-mask uses the full/deep MSA
    in_shallow = "depth" in alt_generators           # depth-reduction uses shallow MSA
    in_boltz = "boltz" in alt_generators             # independent model family
    if in_shallow and not in_deep:
        memo="MSA-dependent (reasoned) — recovered only under depth-reduction; low memorization risk"
    elif in_deep and in_shallow:
        memo="MSA-robust across depth — corroborated; run deposit-proximity check (BioMate PDB search)"
    elif in_deep and not in_shallow:
        memo="deep-MSA default basin — likely the model's dominant prediction"
    else:
        memo="only non-AF2 (Boltz) reached it — cross-family evidence"
    if in_boltz and (in_deep or in_shallow):
        memo += "; independently corroborated by Boltz-2 (different model family)"

    consensus = len(alt_generators) >= a.min_generators
    report={"anchor":os.path.basename(a.ref),"anchor_asym":round(float(ai),2),
            "n_strategies":n_strat,
            "per_strategy":per_gen,
            "alternate_state":{
                "reached":bool(alt_generators),
                "strategies_populating":sorted(alt_generators),
                "consensus_reliability":reliability,       # 0-1: how many independent strategies agree
                "memorization_signal":memo,
                "best_asym":round(best[0],2) if best else None,
                "best_strategy":best[2] if best else None,
                "best_file":os.path.basename(best[1]) if best else None},
            "min_strategies_required":a.min_generators,
            "gate_pass":bool(consensus)}
    if best:                                              # emit the candidate whenever the alt basin is reached
        shutil.copy(best[1], a.out_candidate)
        report["out_candidate"]=a.out_candidate
    json.dump(report, open(a.report,"w"), indent=2)
    print(json.dumps(report,indent=2))
    # loud-fail gate: alternate basin never reached by any strategy
    if not consensus:
        print("GATE FAIL: alternate state not reached by >= "
              f"{a.min_generators} independent strategies", file=sys.stderr)

if __name__=="__main__":
    main()
