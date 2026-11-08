"""Generic spec-driven PROPOSER — not metal/RGD-specific.

One entry point `propose(spec, n)` reads the target spec and picks the generation mode from DATA:
  - `motif` present (+ a scaffold impl for it)  -> SCAFFOLD-CONDITIONED generation (e.g. RGD-family integrins).
  - otherwise (no linear motif: cytokine/complement/FcRn/CD PPIs, metal or not) -> DE-NOVO generation, the v4
    model conditioned on the target's RECEPTOR SEQUENCE (target_feature), proposing free macrocycles for the groove.

So the proposer is NOT tied to metal or to the avb6 RGD scaffold: non-metal PPI targets (our autoimmune portfolio)
flow through the de-novo path. Scaffolds are a registry keyed by motif and extend by data/impl, not by branching.
"""
import os, sys

HERE = os.path.dirname(__file__)
PARENT = os.path.dirname(HERE)
for _p in (HERE, PARENT):
    if _p not in sys.path:
        sys.path.insert(0, _p)
from target_spec import load_spec

CKPT = os.path.join(PARENT, "runs_helm", "unified_cyclic_llm_v4.pt")


def _receptor_seq(spec):
    ch = spec["receptor"].get("chains") or {}
    seqs = [v for k, v in ch.items() if isinstance(v, str) and v and k != "NOTE"]
    return max(seqs, key=len) if seqs else None   # the longest chain = the binding domain


def propose(spec, n=12, temp=1.0, seed=0):
    """Return {target, mode, candidates:[{helm,...}], ...} — generation mode chosen from the spec."""
    from scaffold import canon_motif, scaffold_propose
    if canon_motif(spec.get("motif")):                 # any motif with a scaffold template -> scaffold-conditioned
        return scaffold_propose(spec, n=n)

    # de-novo: condition the v4 generator on the target's receptor sequence
    seq = _receptor_seq(spec)
    if not seq:
        return {"target": spec["target"], "mode": "de-novo", "candidates": [],
                "error": f"no receptor sequence for {spec['receptor'].get('pdb')} (structure needs prep)"}
    import design
    from train_cyclic_llm_v3 import target_feature
    model, toks, stoi, a, dev = design.load(CKPT)
    tf = target_feature(seq).astype("float32")
    gens = design.generate(model, toks, stoi, tf, dev, n * 4, a["block"], a.get("max_len", 16), temp)
    seen, cands = set(), []
    for g in gens:
        key = tuple(g)
        if key in seen:
            continue
        seen.add(key)
        helm = "cyclo(" + "-".join(m if len(m) == 1 else f"[{m}]" for m in g) + ")"
        cands.append({"helm": helm, "monomers": g, "len": len(g),
                      "ncaa": sum(1 for m in g if len(m) > 1)})
        if len(cands) >= n:
            break
    return {"target": spec["target"], "mode": "de-novo",
            "conditioned_on": f"{spec['receptor'].get('pdb')} receptor ({len(seq)} aa)",
            "backend": "neural (unified_cyclic_llm_v4), target-sequence-conditioned", "candidates": cands}


if __name__ == "__main__":
    targets = ["avb6", "pdl1", "a4b7", "a4b1", "lfa1", "c5", "fcrn", "baff", "cd40",
               "il2ra", "tnfa", "il17a", "il17f", "il23", "il6r", "cd20"]
    print("=== proposer mode per target (chosen from spec; metal is irrelevant to the choice) ===")
    from scaffold import canon_motif
    for t in targets:
        s = load_spec(t)
        mode = "scaffold-conditioned" if canon_motif(s.get("motif")) else "de-novo"
        cof = ",".join(c["ccd"] for c in s["cofactors"]) or "—"
        print(f"  {t:7s} cofactors={cof:9s} motif={str(s.get('motif')):16s} -> {mode}")

    # prove the NON-METAL de-novo path end-to-end on PD-L1 (our own target), then general scoring
    print("\n=== de-novo generation for a NON-METAL target (PD-L1), scored generically ===")
    import json
    from score import developability
    from fto_score import fto_score
    res = propose(load_spec("pdl1"), n=6, temp=1.2)
    print(f"mode={res['mode']} conditioned_on={res.get('conditioned_on')} backend={res.get('backend')}")
    for c in res["candidates"][:6]:
        dev = developability(c["helm"])
        nov = fto_score(c["helm"], "pdl1", structure=True).get("novelty", {})
        print(f"  {c['helm'][:52]:52s} len={c['len']} ncaa={c['ncaa']} | dev_pass={dev['pass']} "
              f"meanH={dev['meanH']} | novelty={nov.get('verdict')} T={nov.get('max_tanimoto')}")
    print("\n-> non-metal, de-novo, our-own-target: generation + developability + FTO-novelty all run. "
          "No metal, no RGD scaffold, no avb6 special-case.")
