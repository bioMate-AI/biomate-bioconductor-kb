"""Phase-0.6: auto-dispatch the expensive GPU physics tier into score().

score() has four expensive hooks (binding_dG, selectivity_gap, groove, geometry) that default to 'pending'.
This module FILLS them from the program's already-computed GPU results — it READS result artifacts, it does
NOT run GPU jobs. The join is HELM -> design-ID -> result (IDs live only in the candidate map files), GATED on
A2 control-anchoring: a receptor's MM-GBSA ΔG scale is admissible only if a control/reference compound ranks
strong in a run on that receptor (else the absolute numbers are void).

A2 model (matches the program's reasoning, docs/20261013_PDL1_PRIORITIZATION_RUN.md / acceptance_gate A2):
  - A receptor is ANCHORED if any MM-GBSA file on it has a control row (id starts with CTRL) that ranks in the
    top tier (<= max(3, 25%)). The anchor can be inherited by a sibling run on the SAME receptor+protocol
    (e.g. PD-L1 G2 inherits the 5o45 anchor from G1); provenance records direct-vs-inherited.
  - VOIDED files are never emitted (αvβ6 MM-GBSA: metal (MIDAS Mn) dropped -> unphysical positive ΔG AND no
    control -> A2 FAIL). This is the honest state: no admissible αvβ6 ΔG exists yet (metal-aware MM-GBSA is TODO).
  - groove occupancy is a structural overlap (control-independent) -> admissible whenever present.
  - geometry has no machine-readable result artifact yet -> stays pending (cofold ipTM saturates, not a
    discriminator) — flagged, not faked.
"""
import json, os, math, functools
from acceptance_gate import raw_tokens
from scorer_config import mechanism_compliant, config_for

HERE = os.path.dirname(__file__)
RESULTS = os.path.join(os.path.dirname(HERE), "results")

# which result artifacts back each target; receptor code is read from each file's "target" field
REG = {
    "pdl1": {"mmgbsa": ["pdl1_mmgbsa_results.json", "pdl1_g2_mmgbsa.json"],
             "counter": ["pdl1_pdl2_counter_mmgbsa.json", "pdl1_g2_pdl2_counter.json"],
             "groove": ["pdl1_g2_groove.json"],
             "fep": ["pdl1_fep_ddg.json"],
             "candidates": ["pdl1_g1_candidates.json", "pdl1_g2_candidates.json"]},
    "avb6": {"mmgbsa": ["avb6_r3_mmgbsa.json", "mmgbsa_avb6_v2.json"],
             "counter": [], "groove": [],
             "fep": ["avb6_fep_ddg.json"],
             "candidates": ["knowledge_grounded_candidates_v1.json", "knowledge_grounded_candidates_v2.json"]},
}
# Admissibility of a MM-GBSA file is decided per TARGET MECHANISM (scorer_config.mechanism_compliant), not a
# hard-coded filename list: e.g. αvβ6 requires Mn@β6-MIDAS, so a metal-free run is non-compliant -> void for the
# right reason, and a future metal-aware run becomes admissible automatically. A2 control-anchoring is enforced
# on top of mechanism compliance below.


@functools.lru_cache(maxsize=None)
def _load(fname):
    p = os.path.join(RESULTS, fname)
    return json.load(open(p)) if os.path.exists(p) else None


def _key(helm):
    """Robust join key: canonical token-core tuple (bracket/spacing-insensitive)."""
    try:
        return tuple(raw_tokens(helm))
    except Exception:
        return None


@functools.lru_cache(maxsize=None)
def _helm_index(target):
    """{token-tuple: design-id} from every dict with id+helm anywhere in the target's candidate files
    (recursive: handles both top-level lists and nested {avb6:{candidates:[...]}} layouts)."""
    idx = {}

    def walk(o):
        if isinstance(o, dict):
            if "id" in o and "helm" in o:
                k = _key(o["helm"])
                if k:
                    idx.setdefault(k, o["id"])
            for v in o.values():
                walk(v)
        elif isinstance(o, list):
            for x in o:
                walk(x)

    for f in REG.get(target, {}).get("candidates", []):
        walk(_load(f))
    return idx


def _control_status(fj):
    """Locate a control row in within_target_ranking and decide whether it anchors the scale (top tier)."""
    wr = fj.get("within_target_ranking", [])
    n = len(wr)
    for rank, row in enumerate(wr, 1):
        if str(row.get("design", "")).upper().startswith("CTRL"):
            thresh = max(3, math.ceil(0.25 * n))
            return {"present": True, "control_id": row["design"], "rank": rank, "n": n,
                    "pass": rank <= thresh, "threshold": thresh}
    return {"present": False, "pass": False, "n": n}


@functools.lru_cache(maxsize=None)
def _receptor_anchor(target):
    """{receptor_code: {anchored, via_file, control}} — a receptor is anchored if any of its (non-void) MM-GBSA
    files has a passing control row."""
    anc = {}
    for f in REG.get(target, {}).get("mmgbsa", []):
        fj = _load(f)
        if not fj:
            continue
        rec = fj.get("target", "?")
        cs = _control_status(fj)
        compliant, _ = mechanism_compliant(target, fj)
        cur = anc.get(rec)
        if cs["pass"] and compliant and (cur is None or not cur["anchored"]):
            anc[rec] = {"anchored": True, "via_file": f, "control": cs}
        elif cur is None:
            anc[rec] = {"anchored": False, "via_file": None, "control": cs}
    return anc


def _mmgbsa_record(target, design_id):
    """Find a design's MM-GBSA record + its source file (prefer ok+ring, non-void)."""
    for f in REG.get(target, {}).get("mmgbsa", []):
        fj = _load(f)
        if not fj:
            continue
        for r in fj.get("all", []):
            if r.get("design") == design_id:
                return r, f, fj.get("target", "?")
    return None, None, None


def _counter_dG(target, design_id):
    for f in REG.get(target, {}).get("counter", []):
        fj = _load(f)
        if not fj:
            continue
        for r in fj.get("all", []):
            if r.get("design") == design_id:
                return r.get("dG_bind_kcal_mol"), fj.get("target", "?"), f
    return None, None, None


def _groove(target, design_id):
    for f in REG.get(target, {}).get("groove", []):
        fj = _load(f)
        if fj and design_id in fj:
            return round(float(fj[design_id]), 3), f
    return None, None


def _fep_ddg(target, design_id):
    """Relative FEP ΔΔG for this design, admissible ONLY if the run's CONTROL EDGE validated — i.e. the
    known-affinity control edge was recovered within tolerance (fep_batch.py: 'MUST recover the small known
    affinity gap'). This is the FEP analogue of A2 control-anchoring: without a validated control edge the
    ΔΔG scale is void. Artifact schema (what fep_batch.py writes): {control_edge:{recovered, abs_err_kcal,
    tol_kcal}, edges:[{design, ddG_kcal_mol, ref}]}. Returns (ddG, file, provenance) or (None, None, reason)."""
    for f in REG.get(target, {}).get("fep", []):
        fj = _load(f)
        if not fj:
            continue
        ce = fj.get("control_edge", {})
        validated = bool(ce.get("recovered")) and (
            ce.get("abs_err_kcal") is None or ce.get("tol_kcal") is None
            or ce["abs_err_kcal"] <= ce["tol_kcal"])
        for e in fj.get("edges", []):
            if e.get("design") == design_id and e.get("ddG_kcal_mol") is not None:
                if not validated:
                    return None, f, "FEP control edge NOT validated (ΔΔG scale void) — see control_edge"
                return round(float(e["ddG_kcal_mol"]), 3), f, {
                    "file": f, "ref": e.get("ref"), "control_edge": ce,
                    "sign": "negative = tighter than reference edge"}
    return None, None, "no validated FEP ΔΔG edge for this ID (FEP control edge is gated/not run)"


def physics_for(helm, target):
    """Join HELM -> design-ID -> admissible physics. Returns a record with values (or None=pending) + an
    admissibility flag + reasons + provenance. Does NOT run GPU."""
    out = {"helm": helm, "target": target, "design_id": None,
           "binding_dG": None, "selectivity_gap": None, "groove": None, "geometry": None, "ddg_fep": None,
           "admissible": {}, "reasons": {}, "provenance": {}}
    did = _helm_index(target).get(_key(helm))
    out["design_id"] = did
    if did is None:
        out["reasons"]["all"] = "no candidate-ID mapping for this HELM (not run through the GPU pipeline)"
        return out
    anchor = _receptor_anchor(target)

    # binding_dG
    rec, fname, receptor = _mmgbsa_record(target, did)
    compliant, creason = (mechanism_compliant(target, _load(fname)) if fname else (False, "no file"))
    if rec is None:
        out["reasons"]["binding_dG"] = "no MM-GBSA record for this ID"
    elif not compliant:
        out["reasons"]["binding_dG"] = creason
    elif not (rec.get("ok") and rec.get("ligand_ring_closed")):
        out["reasons"]["binding_dG"] = f"run not ok/ring-closed (ok={rec.get('ok')}, ring={rec.get('ligand_ring_closed')})"
    else:
        a = anchor.get(receptor, {"anchored": False})
        if a["anchored"]:
            out["binding_dG"] = rec["dG_bind_kcal_mol"]
            out["admissible"]["binding_dG"] = True
            direct = a["via_file"] == fname
            out["provenance"]["binding_dG"] = {"file": fname, "receptor": receptor,
                                               "a2": "direct" if direct else "inherited",
                                               "anchor_file": a["via_file"], "control": a["control"]}
        else:
            out["reasons"]["binding_dG"] = f"A2 FAIL: receptor {receptor} not control-anchored"

    # selectivity_gap = ΔG(on-target) - ΔG(off-target); admissible only if on-target receptor anchored
    if out["binding_dG"] is not None:
        off, off_rec, off_f = _counter_dG(target, did)
        if off is not None:
            out["selectivity_gap"] = round(out["binding_dG"] - off, 2)
            out["admissible"]["selectivity_gap"] = True
            out["provenance"]["selectivity_gap"] = {"on": out["binding_dG"], "off": off,
                                                     "off_receptor": off_rec, "file": off_f,
                                                     "sign": "negative = on-target-selective"}
        else:
            out["reasons"]["selectivity_gap"] = "no counter-target (off-target) MM-GBSA for this ID"
    else:
        out["reasons"]["selectivity_gap"] = "requires an admissible on-target binding_dG"

    # groove (structural overlap, control-independent)
    gv, gf = _groove(target, did)
    if gv is not None:
        out["groove"] = gv
        out["admissible"]["groove"] = True
        out["provenance"]["groove"] = {"file": gf}
    else:
        out["reasons"]["groove"] = "no machine-readable groove artifact for this ID (G1 groove is doc-only)"

    # ddg_fep (relative FEP ΔΔG — the trustworthy binding arbiter; control-edge validated)
    dd, fep_f, fep_info = _fep_ddg(target, did)
    if dd is not None:
        out["ddg_fep"] = dd
        out["admissible"]["ddg_fep"] = True
        out["provenance"]["ddg_fep"] = fep_info
    else:
        out["reasons"]["ddg_fep"] = fep_info if isinstance(fep_info, str) else "pending"

    # geometry
    out["reasons"]["geometry"] = "no geometry result artifact (cofold ipTM saturates, not a discriminator)"
    return out


if __name__ == "__main__":
    import sys
    sys.path.insert(0, HERE)
    # demo: the fully-gated PD-L1 lead, a G2 candidate (inherited/unanchored), and a novel generator HELM
    g1 = _load("pdl1_g1_candidates.json")
    k05 = next(r["helm"] for r in g1["prior_round3"] if r["id"] == "PDL1-K-05")
    g2 = _load("pdl1_g2_candidates.json")
    a02 = next(r["helm"] for r in g2["candidates"] if r["id"] == "PDL1-G2-A02")
    novel = "cyclo(W-R-G-D-L-G-[2Nal]-[dP]-[NMeK])"   # from our avb6 generator -> never folded
    avb6_mapped = "cyclo(F-R-G-D-L-S-W-[dP]-[NMeA])"  # AVB6-K-01: HAS a MM-GBSA record, but metal-free run
    for label, helm, tgt in [("PD-L1 lead K-05", k05, "pdl1"),
                             ("PD-L1 G2 A02 (no in-file ctrl)", a02, "pdl1"),
                             ("avb6 AVB6-K-01 (mapped, metal-free run)", avb6_mapped, "avb6"),
                             ("novel avb6 generator HELM", novel, "avb6")]:
        p = physics_for(helm, tgt)
        print(f"\n=== {label} ===\n  {helm}  -> id={p['design_id']}")
        for fld in ("binding_dG", "selectivity_gap", "groove", "geometry"):
            adm = p["admissible"].get(fld)
            val = p[fld] if p[fld] is not None else f"pending ({p['reasons'].get(fld) or p['reasons'].get('all','')})"
            prov = p["provenance"].get(fld)
            tag = f"  [admissible, {prov.get('a2','')}]" if adm and prov and 'a2' in prov else ("  [admissible]" if adm else "")
            print(f"    {fld:16s}= {val}{tag}")
