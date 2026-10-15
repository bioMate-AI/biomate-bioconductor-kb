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

# epitope -> pose-method policy
_POSE = {
    "linear-motif": {"pose_method": "cofold+mmgbsa", "dock_acceptable_prepose": True,
                     "rationale": "clear linear anchor (RGD.L); dock is a valid cheap pre-pose, MM-GBSA decides"},
    "discontinuous": {"pose_method": "cofold+mmgbsa", "dock_acceptable_prepose": False,
                      "rationale": "no linear anchor (groove PPI); cofold required, docking unreliable"},
}
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
    """Derive the mechanism-matched scorer config for a target from its KB mechanism tag."""
    kb = load_kb(target)
    if kb is None:
        return {"target": target, "known": False,
                "reason": f"no Target KB entry (target_kb/{target}.json)"}
    mech = kb.get("mechanism", {})
    metal = mech.get("metal_cofactor")
    epitope = mech.get("epitope", "unknown")
    pose = _POSE.get(epitope, {"pose_method": "cofold+mmgbsa", "dock_acceptable_prepose": False,
                               "rationale": f"unknown epitope '{epitope}' -> default to cofold+MM-GBSA"})
    counter = kb.get("counter_targets", [])
    controls = [{"id": c.get("id"), "helm": c.get("helm")} for c in kb.get("controls", [])]
    return {
        "target": target, "known": True, "name": kb.get("name"),
        "epitope": epitope, "motif": mech.get("motif"),
        "requires_metal": metal is not None,
        "metal": metal, "metal_site": mech.get("site") if metal else None,
        "pose_method": pose["pose_method"], "dock_acceptable_prepose": pose["dock_acceptable_prepose"],
        "pose_rationale": pose["rationale"],
        "counter_targets": counter,
        "counter_receptor_codes": {ct: _OFFTARGET_RECEPTOR.get(ct) for ct in counter},
        "receptor_asset": kb.get("receptor_structure"),
        "controls": controls,
        # what a MM-GBSA result file must declare to be mechanism-compliant for this target:
        "result_requirements": (
            [f"metal '{metal}' present at {mech.get('site')} (metal-complete receptor {kb.get('receptor_structure')})"]
            if metal else []) + ["A2 control row anchors the receptor ΔG scale"],
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
