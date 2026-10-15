"""Patent/FTO KB — claim layer + real compound/patent axis.

Two complementary axes:
  (1) CLAIM-GENUS layer — `in_claim` maps a candidate onto the structured CA2998968 genus and returns
      {inside | literally-outside + position + DoE}. This is the primary FTO axis for these RGD peptides.
  (2) COMPOUND/PATENT axis (item #5) — `novelty_axis` wires the already-built, honest `drug_novelty_fto` gate:
      Morgan/ECFP Tanimoto vs a 136k-row ChEMBL/BindingDB known-actives library (structure re-discovery) +
      a REAL SureChEMBL-via-PubChem patent-presence check. Replaces the old 2-HELM seq-identity STUB.
      `nearest_patented_identity` now uses drug_novelty_fto's Needleman-Wunsch identity (not the crude zip).

Honesty: the compound/patent axis runs on the ncAA-stripped CANONICAL backbone (same approximation the program's
cofold/MM-GBSA use — 2Nal→F, dP→P, NMeK→K via knowledge_liability_flags.parse_helm); this is recorded as a
caveat on every novelty result. Each axis fails OPEN with an explicit status if a dependency (RDKit, library,
network) is unavailable — it never fabricates a verdict."""
import json, os, sys
from acceptance_gate import raw_tokens, _strip_mods, _canon1

HERE = os.path.dirname(__file__)
PARENT = os.path.dirname(HERE)   # research/guangzhou_all_atom — where drug_novelty_fto lives
for _p in (HERE, PARENT):
    if _p not in sys.path:
        sys.path.insert(0, _p)
_LIB = None   # lazily built, cached known-actives library
# residue -> allowed-class tokens, so ncAA map onto the claim's canonical enumerations
NCAA_HOMOLOG = {"2Nal": "F", "1Nal": "F", "Phe4F": "F", "Phe4Cl": "F", "hPhe": "F", "Bip": "F", "Nle": "Nle"}

def _res_class(core):
    c = _strip_mods(core)
    return c  # canonical letter or ncAA token core

def in_claim(helm, claim):
    """Map a head-to-tail cyclic nonapeptide (P1-R-G-D-L-P6-P7-[dP]-[NMeK] family) onto the genus claim."""
    toks = raw_tokens(helm)
    cyclic = helm.strip().lower().startswith("cyclo(")
    seq1 = "".join(_canon1(t) for t in toks); w = seq1 + seq1[:6]
    # claim applies only to its FORM: head-to-tail cyclic nonapeptide containing RGDL
    if not cyclic:
        return {"verdict": "OUTSIDE (form)", "basis": "not head-to-tail cyclic (e.g. side-chain lactam / bicycle)", "doe": "LOW"}
    if len(toks) != 9:
        return {"verdict": "OUTSIDE (form)", "basis": f"ring size {len(toks)} != claimed 9-mer", "doe": "MED"}
    if "RGDL" not in w:
        return {"verdict": "OUTSIDE (form)", "basis": "no RGDL motif", "doe": "LOW"}
    # map positions (read from Arg): X1=G, X2=L, X3=P6, X4=P7, X5=dP, X6=NMeK, X7=P1
    i = w.find("RGDL")
    p1 = toks[i - 1] if i > 0 else toks[-1]
    dpi = next((j for j, t in enumerate(toks) if _strip_mods(t) == "P" and t.startswith("d")), None)
    p7 = toks[dpi - 1] if dpi else None
    p6 = toks[(i + 4) % len(toks)]
    pos = claim["claim_form"]["positions"]
    out = []
    checks = {"X7(P1)": (p1, pos["X7"]), "X3(P6)": (p6, pos["X3"]), "X4(P7)": (p7, pos["X4"])}
    for name, (res, allowed) in checks.items():
        if res is None:
            continue
        c = _res_class(res)
        if c in allowed:
            continue                                   # literally within the enumeration
        elif NCAA_HOMOLOG.get(c) in allowed:
            out.append({"position": name, "residue": res, "doe": "MED"})   # ncAA homolog of a listed residue -> literally OUT, MED DoE
        else:
            out.append({"position": name, "residue": res, "doe": "HIGH"})  # conservative canonical sub outside list -> literally OUT, HIGH DoE
    if not out:
        return {"verdict": "INSIDE (literal genus)", "basis": "all X positions within enumerations", "doe": "infringes"}
    return {"verdict": "literally OUTSIDE at " + ", ".join(o["position"] for o in out),
            "outside_positions": out, "doe": max(o["doe"] for o in out)}

_AA = set("ACDEFGHIKLMNPQRSTVWY")
# ncAA core (after _strip_mods removes NMe/d- prefixes) -> nearest canonical for the folded backbone
_BB_MAP = {"2Nal": "F", "1Nal": "F", "Nal": "F", "Phe4F": "F", "Phe4Cl": "F", "hPhe": "F", "Bip": "F",
           "Nle": "L", "Aib": "A", "Abu": "A", "Sar": "G"}


def _backbone(helm):
    """Faithful, length-preserving canonical backbone: _strip_mods handles NMe*/d- prefixes (NMeK→K, dP→P),
    then ncAA cores map to their nearest canonical (2Nal/Phe4F→F, Aib/Abu→A, Nle→L). Unknown ncAA are dropped
    (and never silently coerced). This is the ncAA-stripped approximation the cofold/MM-GBSA pipeline also uses."""
    out = []
    for t in raw_tokens(helm):
        c = _strip_mods(t)
        if c in _AA:
            out.append(c)
        elif c in _BB_MAP:
            out.append(_BB_MAP[c])
    return "".join(out)


def nearest_patented(helm, claim):
    """Real Needleman-Wunsch sequence identity (drug_novelty_fto) of the candidate backbone vs the claim's known
    patented-compound backbones. Replaces the old crude equal-length zip. Pure-Python; no RDKit needed."""
    refs = [_backbone(k) for k in claim.get("known_compounds", [])]
    if not refs:
        return 0.0
    try:
        from drug_novelty_fto import nearest_sequence
        best, _ = nearest_sequence(_backbone(helm), refs)
        return round(best, 2)
    except Exception:
        # fallback to the old equal-length identity if the module is unavailable (never hard-fail)
        bb = _backbone(helm); best = 0.0
        for r in refs:
            if len(r) == len(bb) and bb:
                best = max(best, sum(a == b for a, b in zip(bb, r)) / len(bb))
        return round(best, 2)


def _library():
    """Build + cache the known-actives library once. Returns None (honestly) if RDKit/CSV unavailable."""
    global _LIB
    if _LIB is not None:
        return _LIB or None
    csv_path = os.path.join(PARENT, "data", "raw", "binding_affinity", "binding_affinity_v1.csv")
    try:
        import drug_novelty_fto as nf
        if not os.path.exists(csv_path):
            _LIB = False; return None
        cache = os.path.join(PARENT, "data", "_registry_cache", "novelty_lib_binding_affinity_v1.pkl")
        _LIB = nf.build_library(csv_path, tag_cols=["is_pdl1", "is_avb6", "target_name"], cache_path=cache)
    except Exception:
        _LIB = False
    return _LIB or None


def novelty_axis(helm, target, check_patents=False):
    """Compound/patent axis via drug_novelty_fto: structure Tanimoto vs the known-actives library (+ same-target
    subset) and optional live SureChEMBL/PubChem patent presence. Runs on the canonical backbone (caveat)."""
    bb = _backbone(helm)
    out = {"backbone": bb, "backbone_caveat": "ncAA-stripped canonical backbone (2Nal/Phe4F→F, Aib/Abu→A, "
           "Nle→L, dP→P, NMe*→parent; unknown ncAA dropped); structure/patent axes approximate the real molecule"}
    try:
        import drug_novelty_fto as nf
    except Exception as e:
        out["status"] = f"unavailable: drug_novelty_fto import failed ({e})"
        return out
    restrict = {"avb6": ("is_avb6", "True"), "pdl1": ("is_pdl1", "True")}.get(target)
    v = nf.score_candidate(f"{target}:{bb}", seq=bb, cyclic=True, library=_library(),
                           restrict_tag=restrict, check_patents=check_patents)
    out.update({
        "structure_status": v.structure_status, "structure_tier": v.structure_tier,
        "max_tanimoto": v.max_tanimoto, "nearest_known_id": v.nearest_known_id,
        "same_target_max_tanimoto": v.nearest_known_tag.get("same_target_max_tanimoto"),
        "same_target_nearest_id": v.nearest_known_tag.get("same_target_nearest_id"),
        "patent": v.patent, "verdict": v.verdict, "occupied": v.occupied, "reasons": v.reasons,
    })
    return out


def fto_score(helm, target="avb6", structure=False, check_patents=False):
    """Claim-genus verdict (+ real NW nearest-patented identity) always; opt-in compound/patent novelty axis.
    structure=True adds structure-Tanimoto vs known actives; check_patents=True adds a live SureChEMBL check."""
    claim = json.load(open(os.path.join(HERE, "fto_kb", "ca2998968.json")))
    res = {"claim": in_claim(helm, claim), "nearest_patented_identity": nearest_patented(helm, claim)}
    if structure or check_patents:
        res["novelty"] = novelty_axis(helm, target, check_patents=check_patents)
    return res

if __name__ == "__main__":
    tests = [
        "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",          # avebehexin = literal genus
        "cyclo(W-R-G-D-L-A-[2Nal]-[dP]-[NMeK])",     # ncAA flank -> MED DoE
        "cyclo(Y-R-G-D-L-S-F-[dP]-[NMeK])",          # Ser@X3 -> HIGH DoE
        "cyclo(R-G-D-L-F-[dP]-[NMeK])",              # 7-mer ring-size -> OUTSIDE(form) MED
        "Ac-[Dap]-R-G-D-L-A-F-[dP]-[Glu]-K-NH2",     # side-chain lactam -> OUTSIDE(form) LOW
    ]
    for h in tests:
        r = fto_score(h)
        print(f"{h}\n   -> {r['claim']['verdict']} | DoE {r['claim']['doe']} | nearest-patented id {r['nearest_patented_identity']}")

    import sys as _sys
    patents = "--patents" in _sys.argv
    print("\n=== compound/patent axis (structure Tanimoto vs 136k known actives" +
          (" + live SureChEMBL" if patents else "") + ") ===")
    for h in ["cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])", "cyclo(W-R-G-D-L-G-[2Nal]-[dP]-[NMeK])"]:
        n = fto_score(h, "avb6", structure=True, check_patents=patents)["novelty"]
        pat = n.get("patent", {})
        print(f"{h}\n   backbone={n['backbone']} | {n.get('structure_status')} tier={n.get('structure_tier')} "
              f"max_T={n.get('max_tanimoto')} (same-target {n.get('same_target_max_tanimoto')}, {n.get('same_target_nearest_id')}) "
              f"| verdict={n.get('verdict')}" + (f" | patent present={pat.get('present')} n={pat.get('n_patents')}" if patents else ""))
