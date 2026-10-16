"""Phase-0.7: mechanism-matched scorer config.

Reads a Target KB `mechanism` tag and derives how that target must be scored by the expensive physics tier:
  - METAL: integrin MIDAS targets (metal_cofactor set, e.g. αvβ6 → Mn at β6 MIDAS) REQUIRE the metal retained
    and parameterized in cofold + MM-GBSA. A metal-free run is mechanism-NON-COMPLIANT → its ΔG is void
    (this is exactly why the αvβ6 round-3 numbers are positive/unphysical). PPI groove targets (pdl1,
    metal_cofactor null) require NO metal.
  - POSE METHOD by epitope: a linear-motif epitope (RGD.L) has a clear anchor → docking is an acceptable cheap
    pre-pose, but the trusted discriminator is still cofold+MM-GBSA; a discontinuous epitope (PD-1 groove) has no
    linear anchor → cofold is REQUIRED (docking unreliable).
  - COUNTER-TARGETS for selectivity come from the KB (αvβ6 → other integrins; pdl1 → pdl2).
  - RECEPTOR asset + CONTROLS (for A2) come from the KB.

This replaces hard-coded constants in physics_dispatch with a per-target config derived from the mechanism, and
makes αvβ6 physics admissible precisely WHEN a metal-aware, control-anchored run exists — not before.
"""
import json, os, functools

HERE = os.path.dirname(__file__)
KB = os.path.join(HERE, "target_kb")

# NOTE: the epitope->pose table now lives once in target_spec.POSE_BY_EPITOPE (this module is a view over it).
# KB counter-target label -> the receptor code that appears in result files' "target" field (where known)
_OFFTARGET_RECEPTOR = {"pdl2": "pdl2"}   # integrin off-targets have no result-file code yet (runs not produced)


@functools.lru_cache(maxsize=None)
def load_kb(target):
    p = os.path.join(KB, f"{target}.json")
    if not os.path.exists(p):
        return None
    return json.load(open(p))


@functools.lru_cache(maxsize=None)
def config_for(target):
    """Mechanism-matched scorer config — now a thin VIEW over the one generic engine (target_spec.load_spec).
    Metal/pose/counter all come from the spec (metal = the spec's `cofactors`); this keeps the back-compat
    output keys physics_dispatch depends on, with no second copy of the mechanism logic."""
    from target_spec import load_spec, cofactor_ccds
    s = load_spec(target)
    if s is None:
        return {"target": target, "known": False,
                "reason": f"no Target KB entry (target_kb/{target}.json)"}
    cof = s.get("cofactors", [])
    metal = cof[0]["ccd"] if cof else None          # primary cofactor (back-compat 'metal' field)
    site = cof[0].get("site") if cof else None
    return {
        "target": target, "known": True, "name": s.get("name"),
        "epitope": s.get("epitope"), "motif": s.get("motif"),
        "cofactors": cof,                            # the general field (metal = just this)
        "requires_metal": bool(cof),
        "metal": metal, "metal_site": site,
        "pose_method": s["pose_method"], "dock_acceptable_prepose": s["dock_prepose_ok"],
        "pose_rationale": s["pose_why"],
        "counter_targets": s["counter_targets"],
        "counter_receptor_codes": {ct: _OFFTARGET_RECEPTOR.get(ct) for ct in s["counter_targets"]},
        "receptor_asset": s["receptor"]["structure"],
        "controls": [{"id": c.get("id"), "helm": c.get("helm")} for c in s.get("controls", [])],
        "result_requirements": (
            [f"cofactor(s) {','.join(cofactor_ccds(s))} present at {site} "
             f"(prepared receptor {s['receptor']['structure']})"] if cof else [])
            + ["A2 control row anchors the receptor ΔG scale"],
    }


def _file_declares_metal(fj, metal):
    """True if a result file records that `metal` was retained in the run (top-level or per-record or protocol)."""
    if not metal:
        return True
    m = metal.lower()
    # top-level metal/ions provenance
    for k in ("metal", "metals", "ions", "metal_cofactor", "cofactor"):
        v = fj.get(k)
        if v and m in str(v).lower():
            return True
    # per-record provenance (protocol string or a metal field)
    for r in fj.get("all", []) or fj.get("results", []):
        if not isinstance(r, dict):
            continue
        for k in ("metal", "ions", "has_metal", "protocol"):
            v = r.get(k)
            if v and m in str(v).lower():
                return True
        break   # protocol is uniform across records; one check suffices
    return False


def mechanism_compliant(target, fj):
    """Is a MM-GBSA result file admissible under the target's mechanism? Returns (bool, reason).
    Metal gate only (A2 control-anchoring is enforced separately in physics_dispatch)."""
    cfg = config_for(target)
    if not cfg.get("known"):
        return False, cfg.get("reason", "unknown target")
    if cfg["requires_metal"] and not _file_declares_metal(fj, cfg["metal"]):
        return (False, f"mechanism-noncompliant: requires {cfg['metal']} at {cfg['metal_site']}; run does not "
                       f"record the metal (metal-complete receptor {cfg['receptor_asset']} required)")
    return True, "mechanism-compliant"


if __name__ == "__main__":
    import sys
    for t in (sys.argv[1:] or ["avb6", "pdl1"]):
        c = config_for(t)
        print(f"\n=== scorer config: {t} ({c.get('name')}) ===")
        if not c.get("known"):
            print("  ", c.get("reason")); continue
        print(f"  epitope={c['epitope']} motif={c['motif']}")
        print(f"  requires_metal={c['requires_metal']} metal={c['metal']} site={c['metal_site']}")
        print(f"  pose_method={c['pose_method']} dock_prepose_ok={c['dock_acceptable_prepose']}  ({c['pose_rationale']})")
        print(f"  counter_targets={c['counter_targets']} -> receptor codes {c['counter_receptor_codes']}")
        print(f"  receptor_asset={c['receptor_asset']}")
        print(f"  controls={[cc['id'] for cc in c['controls']]}")
        print(f"  result_requirements:")
        for r in c["result_requirements"]:
            print(f"    - {r}")
