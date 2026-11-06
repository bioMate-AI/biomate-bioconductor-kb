"""Phase-1.1: the NEURAL proposer — replaces the enumeration stand-in in rule_conditioned_generator.

What the neural model contributes (honest scope):
  - The unified v4 cyclic-peptide LLM (unified_cyclic_llm.py / design.py, ckpt runs_helm/unified_cyclic_llm_v4.pt)
    is a monomer-level macrocycle generator trained on CycPeptMPDB (ncAA + measured permeability) + a display
    pool (binding). Here it PROPOSES the free-position chemistry of the αvβ6 pharmacophore scaffold
    cyclo(p1 - R-G-D-L - p6 - p7 - [dP] - [NMeK]) by scoring each candidate macrocycle's likelihood under
    null-target + HIGH-permeability conditioning, then SAMPLING free-position triples in proportion to that
    likelihood. So the free positions are now chosen by a learned, permeability-biased density instead of a
    fixed enumeration order.
  - The RGD pharmacophore scaffold + the induced rule + FTO stay SYMBOLIC hard constraints (SNG pattern): the
    neural model proposes inside the constrained free space; rule / FTO / developability reject + rank.

Honest limitations (NOT hidden):
  - The v4 model is NOT trained on αvβ6 — conditioning here is null-target + permeability, so the neural signal
    is "developable / permeable macrocycle chemistry," not avb6 affinity. Affinity is the expensive tier (score
    full) / wet-lab.
  - Neural palette = monomers the model knows AND the symbolic gate already classifies correctly
    (aromatic flanks F/Y/W/Nal; small knob A/G/S/Aib/Abu). The model's OOV handle [NMeK] is represented as K
    for the model's context only. Expanding the palette to exotic aromatic ncAA (3Pal, Bal, Bn_Gly, ...) needs a
    VETTED monomer-property table (aromaticity + hydrophobicity + FTO homolog) first — a data task, not a guess.
  - Falls back to the enumeration proposer (rule_conditioned_generator.gen_avb6) if torch / the checkpoint is
    unavailable, with backend="enumeration(fallback)" so the loop never silently degrades.
"""
import json, os, sys, random
sys.path.insert(0, os.path.dirname(__file__))
from rule_induction import predicates
from acceptance_gate import avb6_gate
from fto_score import fto_score

HERE = os.path.dirname(__file__)
ROOT = os.path.dirname(HERE)
CKPT = os.path.join(ROOT, "runs_helm", "unified_cyclic_llm_v4.pt")
TARGETS_JSON = os.path.join(ROOT, "data", "display", "target_proteins.json")

# free-position palette: model-known (CycPeptMPDB vocab) AND symbolic-gate-known-correct
FLANK = ["F", "Y", "W", "Nal"]          # aromatic; model knows all; Nal -> scaffold symbol 2Nal
P6 = ["A", "G", "S", "Aib", "Abu"]      # small specificity knob; model knows all
MODEL2SCAFFOLD = {"Nal": "2Nal"}        # CycPeptMPDB symbol -> acceptance_gate/fto symbol
# the model's context tokens for the fixed scaffold (handle NMeK -> K: OOV-free context, documented)
FIXED_CTX = ["R", "G", "D", "L"]        # between p1 and p6
TAIL_CTX = ["dP", "K"]                  # [dP] known; [NMeK] -> K for the model only


def _sym(m):
    return MODEL2SCAFFOLD.get(m, m)


def _scaffold_helm(p1, p6, p7):
    toks = [_sym(p1), "R", "G", "D", "L", _sym(p6), _sym(p7), "dP", "NMeK"]
    return "cyclo(" + "-".join(t if len(t) == 1 else f"[{t}]" for t in toks) + ")"


def _constrain_reject(p1, p6, p7):
    """Reuse the exact symbolic constrain+reject from the enumeration generator. Returns the candidate record
    or None (rule-violator or patent-infringing rejected by construction)."""
    helm = _scaffold_helm(p1, p6, p7)
    pr = predicates(helm)
    if not (pr["has_rgd"] and pr["has_rgdl"] and pr["flank_aromatic_p1"] and pr["flank_aromatic_p7"]):
        return None
    if not avb6_gate(helm)["PASS_H1_H5"]:
        return None
    fto = fto_score(helm, "avb6")
    if fto["claim"]["verdict"].startswith("INSIDE"):
        return None
    ncaa = [x for x in (_sym(p1), _sym(p6), _sym(p7)) if len(x) > 1]
    return {"helm": helm, "free": {"p1": p1, "p6": p6, "p7": p7}, "ncaa_count": len(ncaa),
            "fto_verdict": fto["claim"]["verdict"], "doe": fto["claim"]["doe"],
            "nearest_patented_id": fto["nearest_patented_identity"]}


def _neural_available():
    try:
        import torch  # noqa: F401
    except Exception:
        return False
    return os.path.exists(CKPT)


def _score_triples(temp):
    """Load v4; for every (p1,p6,p7) on the palette, compute the model loglik of the assembled macrocycle under
    null-target + <p_hi>. Returns {triple: loglik} — the neural proposal density over the free space."""
    import numpy as np, torch
    import design
    from train_cyclic_llm_v3 import TFEAT_DIM
    model, toks, stoi, a, dev = design.load(CKPT)
    zero = np.zeros(TFEAT_DIM, "float32")
    out = {}
    for p1 in FLANK:
        for p6 in P6:
            for p7 in FLANK:
                monos = [p1] + FIXED_CTX + [p6, p7] + TAIL_CTX     # model-vocab context (NMeK->K)
                ll = design.loglik(model, stoi, monos, "<e_na>", "<p_hi>", zero, dev)
                out[(p1, p6, p7)] = ll
    return out


def gen_avb6_neural(n=12, temp=2.0, n_sample=800, seed=0):
    """Neural proposer: sample free-position triples in proportion to the model's permeability-conditioned
    macrocycle likelihood, then symbolic constrain+reject. Emits (H, X) + backend metadata.
    Falls back to the enumeration proposer if the neural stack is unavailable."""
    H = json.load(open(os.path.join(HERE, "target_kb", "avb6_induced_rule.json")))["induced_rule"]
    if not _neural_available():
        from rule_conditioned_generator import gen_avb6
        _H, X = gen_avb6(n)
        meta = {"backend": "enumeration(fallback)", "reason": "torch or v4 checkpoint unavailable",
                "ckpt": CKPT}
        return H, X, meta

    import numpy as np
    ll = _score_triples(temp)
    triples = list(ll.keys())
    logits = np.array([ll[t] for t in triples], "float32")
    p = np.exp((logits - logits.max()) / max(temp, 1e-6)); p /= p.sum()
    rng = np.random.default_rng(seed)
    picks = rng.choice(len(triples), size=n_sample, replace=True, p=p)

    seen, X = set(), []
    for idx in picks:
        p1, p6, p7 = triples[idx]
        rec = _constrain_reject(p1, p6, p7)
        if rec is None or rec["helm"] in seen:
            continue
        seen.add(rec["helm"])
        rec["neural_loglik"] = round(float(ll[(p1, p6, p7)]), 3)
        X.append(rec)
    # rank survivors by FTO strength then neural preference (higher loglik first)
    rank = {"LOW": 0, "MED": 1, "HIGH": 2}
    X.sort(key=lambda c: (rank.get(c["doe"], 1), c["nearest_patented_id"], -c["neural_loglik"]))
    X = X[:n]
    meta = {"backend": "neural (unified_cyclic_llm_v4)", "conditioning": "null-target + <p_hi> permeability",
            "palette": {"flank": FLANK, "p6": P6}, "oov_handling": "[NMeK]->K for model context only",
            "target_agnostic": True, "n_sampled": int(len(picks)), "ckpt": os.path.relpath(CKPT, ROOT)}
    return H, X, meta


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=12)
    ap.add_argument("--temp", type=float, default=2.0, help="exploration knob: 1.0 exploits the model's sharp "
                    "preference (~5 survivors), >=2.0 broadens proposals")
    ap.add_argument("--n-sample", type=int, default=800)
    args = ap.parse_args()
    H, X, meta = gen_avb6_neural(args.n, args.temp, args.n_sample)
    print(f"backend: {meta['backend']}")
    for k in ("conditioning", "palette", "oov_handling", "target_agnostic", "n_sampled", "reason"):
        if k in meta:
            print(f"  {k}: {meta[k]}")
    print(f"\nH (induced rule): binder(X) :- {', '.join(H)}.")
    print(f"X ({len(X)} neural-proposed candidates; rule-violators AND patent-INFRINGING rejected by construction):")
    for c in X:
        nl = f" neural_ll={c['neural_loglik']}" if "neural_loglik" in c else ""
        print(f"  {c['helm']}   ncAA={c['ncaa_count']}  FTO: {c['fto_verdict']} (DoE {c['doe']}, patent-id {c['nearest_patented_id']}){nl}")
    out = os.path.join(HERE, "target_kb", "avb6_neural_HX.json")
    json.dump({"H": H, "X": X, "meta": meta}, open(out, "w"), indent=2)
    print(f"\nwrote {os.path.relpath(out, HERE)}  (neural (H,X) artifact)")
