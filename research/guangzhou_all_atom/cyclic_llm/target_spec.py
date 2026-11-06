"""Generic target-spec engine — one data schema, one pipeline, zero per-target code.

A target is DATA (a spec). One generic engine reads it and configures generation / cofold / scoring.
Crucially, **"metal-aware" is NOT special-cased** — the metal is just the `cofactors` field, a free list of
ligand CCD codes:

    cofactors: []                      -> no cofactor (most cytokine/PPI targets)
    cofactors: [{ccd:"MN", n:3}]       -> integrin beta-I domain (MIDAS/ADMIDAS/SyMBS)
    cofactors: [{ccd:"MG", n:1}]       -> I-domain integrin (LFA-1)
    cofactors: [{ccd:"ZN"}] / [{ccd:"HEM"}] / [{ccd:"ATP"}] ...   -> identical code path

The same is true of every other axis: `epitope` drives the pose method from a DATA table (not an if-branch),
`motif` drives scaffold-conditioned vs de-novo generation, `counter_targets`/`controls` come straight from the
spec. **Adding a target = adding a spec row.** This replaces the hard-coded ligands / RGD-scaffold / per-target
registries. It is also the row that belongs in BioMate's workflow DB so the engine runs through the product.
"""
import json, os, functools

HERE = os.path.dirname(__file__)
KB = os.path.join(HERE, "target_kb")
PLAN = os.path.join(os.path.dirname(HERE), "results", "docking", "cofold_mmgbsa_plan_v2.json")

# DATA tables (not code branches). Extend by editing data, not logic.
POSE_BY_EPITOPE = {
    "linear-motif":   {"pose_method": "cofold+mmgbsa", "dock_prepose_ok": True,
                       "why": "clear linear anchor; dock is a valid cheap pre-pose, MM-GBSA decides"},
    "I-domain-MIDAS": {"pose_method": "cofold+mmgbsa", "dock_prepose_ok": True,
                       "why": "metal-anchored I-domain; dock pre-pose acceptable"},
    "discontinuous":  {"pose_method": "cofold+mmgbsa", "dock_prepose_ok": False,
                       "why": "no linear anchor (groove/PPI); cofold required, docking unreliable"},
}
_DEFAULT_POSE = {"pose_method": "cofold+mmgbsa", "dock_prepose_ok": False, "why": "unknown epitope -> cofold"}
# fallback ONLY when a KB row predates the explicit `cofactors` field: derive a sane default from the metal field.
_INTEGRIN_SITES = {"linear-motif": 3, "I-domain-MIDAS": 1}   # beta-I domain has 3 metal sites; I-domain has 1


def _derive_cofactors(mech):
    """Back-compat: if a KB row has no explicit `cofactors`, derive it from mechanism.metal_cofactor.
    This only bootstraps old rows; the authoritative value is the spec's own `cofactors` list."""
    metal = mech.get("metal_cofactor")
    if not metal:
        return []
    n = _INTEGRIN_SITES.get(mech.get("epitope"), 1)
    return [{"ccd": metal.upper()[:3], "n": n, "site": mech.get("site")}]


@functools.lru_cache(maxsize=None)
def _plan():
    try:
        return json.load(open(PLAN))
    except Exception:
        return {"receptors": {}, "peptides": {}}


@functools.lru_cache(maxsize=None)
def load_spec(target):
    """Load + normalize a target into the canonical spec. Pure data in -> pure data out."""
    p = os.path.join(KB, f"{target}.json")
    if not os.path.exists(p):
        return None
    kb = json.load(open(p))
    mech = kb.get("mechanism", {})
    cofactors = kb.get("cofactors")
    if cofactors is None:                      # old row -> bootstrap from metal field (then it's data)
        cofactors = _derive_cofactors(mech)
    pose = POSE_BY_EPITOPE.get(mech.get("epitope"), _DEFAULT_POSE)
    # receptor chains come from the prepped-structure plan when available (else physics is 'needs prep')
    plan_recep = _plan().get("receptors", {})
    pdb = (kb.get("receptor_pdb") or ((kb.get("receptor_structure") or "").split()[0].split("/")[0].lower() or None))
    chains = plan_recep.get(pdb, {}).get("chains") if pdb else None
    motif = mech.get("motif")
    return {
        "target": target, "name": kb.get("name"), "indication": kb.get("indication"),
        "epitope": mech.get("epitope"), "site": mech.get("site"),
        "cofactors": cofactors,                         # <-- METAL IS JUST THIS (any ligand, 0..n)
        "motif": motif,
        "scaffold_mode": (f"scaffold-conditioned:{motif}" if motif else "de-novo"),
        "pose_method": pose["pose_method"], "dock_prepose_ok": pose["dock_prepose_ok"], "pose_why": pose["why"],
        "counter_targets": kb.get("counter_targets", []),
        "controls": kb.get("controls", []),
        "receptor": {"pdb": pdb, "structure": kb.get("receptor_structure"),
                     "chains_available": bool(chains), "chains": chains},
        "source": kb.get("source"),
    }


def cofactor_ccds(spec):
    """Flatten cofactors -> the CCD-code list the cofold input needs. Metal = just these codes."""
    out = []
    for c in spec.get("cofactors", []):
        out += [c["ccd"]] * int(c.get("n", 1))
    return out


def requires_cofactor(spec):
    return bool(spec.get("cofactors"))


def build_cofold_input(spec, candidates):
    """GENERIC cofold input from ANY spec: receptor chains + cofactors (metal or not) + peptides.
    No target-specific code; `cofactors` carries whatever the mechanism needs. Returns None if the
    receptor structure is not prepped yet (honest cold-start for physics)."""
    chains = spec["receptor"]["chains"]
    if not chains:
        return {"error": f"receptor {spec['receptor']['pdb']} not prepped (needs structure)"}
    return {
        "target": spec["receptor"]["pdb"], "spec": spec["target"],
        "receptor_chains": {k: v for k, v in chains.items() if isinstance(v, str) and v and k != "NOTE"},
        "ligands": cofactor_ccds(spec),                 # generic: [] / [MN,MN,MN] / [MG] / [ZN] ...
        "peptides": candidates,
    }


if __name__ == "__main__":
    targets = ["avb6", "pdl1", "a4b7", "a4b1", "lfa1", "c5", "fcrn", "baff", "cd40",
               "il2ra", "tnfa", "il17a", "il17f", "il23", "il6r", "cd20"]
    print("=== generic target_spec engine — all config from DATA (metal = just `cofactors`) ===\n")
    print(f"{'target':7s} {'epitope':14s} {'cofactors (metal=just this)':26s} {'scaffold_mode':24s} dock_prepose")
    for t in targets:
        s = load_spec(t)
        if not s:
            continue
        cof = ",".join(cofactor_ccds(s)) or "—"
        print(f"{t:7s} {str(s['epitope']):14s} {cof:26s} {s['scaffold_mode']:24s} {s['dock_prepose_ok']}")
    print("\nNote: zero per-target code ran. avb6 metal is cofactors=[MN,MN,MN]; pdl1/cytokines are []; "
          "lfa1 is [MG]. A new cofactor type (ZN/HEM/ATP/…) is the same path.")
    # show the avb6 cofold input is now SPEC-DERIVED (not hard-coded ligands)
    s = load_spec("avb6")
    demo = build_cofold_input(s, [{"id": "demo", "pep": "FRGDLAFPK"}])
    print(f"\navb6 cofold input (spec-derived): ligands={demo.get('ligands')} "
          f"chains={list(demo.get('receptor_chains', {}).keys())}")
