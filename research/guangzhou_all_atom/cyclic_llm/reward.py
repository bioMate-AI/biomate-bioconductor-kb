"""Phase-1.3 / own-LLM item #8: the RLVR reward + loop→DPO bridge.

Turns the consolidated verifier `score()` into the two signals an own-LLM generator trains against:
  (1) reward(score_record) -> scalar  — the verifiable reward for RL (RLVR). It encodes the direction doc's
      key lesson (docs/20261015_OWN_LLM_OPTIMIZATION_DIRECTION.md §2C): reward passing ALL the hard gates, not
      just binding — the exact failure of this program's G2 round (24 binders, 0 selective). So the hard gate
      (rule ∧ not-infringing ∧ developability) dominates, and selectivity is a first-class SOFT term alongside
      binding, novelty, FTO-DoE and groove (each only when admissible / present).
      BINDING term = the TRUSTWORTHY arbiter when present: relative FEP ΔΔG (`ddg_fep`). MM-GBSA (`binding_dG`)
      is a weak feasibility PROXY, used only as a fallback when no FEP ΔΔG exists (the "SMILES->GAFF MM-GBSA?"
      critique). Making the RL reward's physics = FEP ΔΔG, distinct from any MM-GBSA/display held-out evaluator,
      also directly mitigates circularity threat #4 in the innovation-thesis doc.
  (2) build_preference_pairs(scored) -> dpo_pairs.PairSet — ranks the loop's scored candidates by reward and
      emits chosen≻rejected pairs in the EXISTING dpo_pairs schema (STREAM_VERIFY_SELECT), ready for the
      existing dpo_peptide_trainer.py / TRL DPOTrainer. The loop is the data factory; this is the tap.

HONEST SCOPE — this does NOT train. Per the direction doc §5 (volume gate) + the no-tiny-dataset rule, gradient
RLVR waits until the closed loop produces scored candidates at volume (and, later, assay outcomes as the ground-
truth reward). This module is the reward function + preference-data emitter + a best-of-N DEMONSTRATION that the
reward ranks correctly. Early reward is the verifier (relative, feasibility-level); assay outcome replaces it
later. No GPU, no training, CPU only.
"""
import json, os, sys

HERE = os.path.dirname(__file__)
PARENT = os.path.dirname(HERE)
for _p in (HERE, PARENT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

# reward weights (explicit + documented; gate dominates, selectivity is first-class)
DEFAULT_WEIGHTS = {
    "gate_pass": 1.0,          # base reward for passing ALL hard gates
    "gate_fail_base": -1.0,    # base for a gate failure
    "gate_fail_per": -0.25,    # extra penalty per failed hard gate
    "doe": 0.30,               # FTO doctrine-of-equivalents RISK (lower risk better) -> scaled
    "novelty": 0.30,           # 1 - nearest_patented_identity (more novel better)
    "developability": 0.20,    # liability-free + mid hydrophobicity
    "ddg_fep": 0.90,           # TRUSTWORTHY ARBITER: relative FEP ΔΔG (more negative better); preferred binding term
    "binding": 0.45,           # MM-GBSA ΔG — FEASIBILITY-LEVEL FALLBACK only, used iff no FEP ΔΔG (weak proxy)
    "selectivity": 0.60,       # admissible on-target selectivity gap (more negative better); 0 if pending
    "groove": 0.20,            # admissible groove occupancy (higher better); 0 if pending
    "known_active_penalty": -0.5,  # structure Tanimoto re-discovery (fto.novelty verdict == known_active)
}
_DOE_RISK = {"LOW": 0.0, "MED": 0.5, "HIGH": 1.0, "infringes": 1.0}   # risk fraction (lower is better)


def _num(x):
    return x if isinstance(x, (int, float)) else None


def reward(rec, weights=None):
    """Scalar reward from a score() record. Returns {reward, gated, terms}. Only admissible/present objectives
    contribute (pending physics contributes 0 — feasibility-level reward, honestly)."""
    w = {**DEFAULT_WEIGHTS, **(weights or {})}
    terms = {}
    gated = bool(rec.get("hard_gate_pass"))
    if gated:
        terms["gate"] = w["gate_pass"]
    else:
        n_fail = sum(1 for v in rec.get("hard_gate_reasons", {}).values() if not v)
        terms["gate"] = w["gate_fail_base"] + w["gate_fail_per"] * max(0, n_fail - 1)

    fto = rec.get("fto", {})
    # FTO DoE risk (lower risk -> higher reward)
    terms["doe"] = w["doe"] * (1.0 - _DOE_RISK.get(fto.get("doe"), 0.5))
    # novelty vs known patented compounds (lower identity -> more novel)
    pid = _num(fto.get("patent_id"))
    if pid is not None:
        terms["novelty"] = w["novelty"] * (1.0 - pid)
    # structure re-discovery penalty (real Tanimoto axis, when the full-tier novelty ran)
    nov = fto.get("novelty") or {}
    if nov.get("verdict") == "known_active":
        terms["known_active"] = w["known_active_penalty"]

    # developability (liability count + hydrophobicity band)
    dev = rec.get("developability", {})
    if dev:
        liab = len(dev.get("liabilities", []))
        meanH = _num(dev.get("meanH"))
        band = 1.0 if (meanH is not None and -0.2 <= meanH <= 0.7) else 0.4
        terms["developability"] = w["developability"] * max(0.0, (1.0 - 0.25 * liab)) * band

    # expensive tier — only when admissible (numeric, not "pending")
    # BINDING: prefer the trustworthy FEP ΔΔG arbiter; MM-GBSA is a weak feasibility proxy used ONLY as a
    # fallback when no FEP ΔΔG is present (the "SMILES→GAFF MM-GBSA?" critique + circularity-threat #4: the
    # RLVR training reward should be FEP ΔΔG, distinct from any MM-GBSA/display held-out evaluator).
    ddg = _num(rec.get("ddg_fep"))
    b = _num(rec.get("binding_dG"))
    if ddg is not None:
        terms["ddg_fep"] = w["ddg_fep"] * max(0.0, min(1.0, -ddg / 3.0))      # relative ΔΔG; ~-3 kcal/mol saturates
    elif b is not None:
        terms["binding_mmgbsa_proxy"] = w["binding"] * max(0.0, min(1.0, -b / 40.0))   # fallback; ~-40 kcal/mol saturates
    s = _num(rec.get("selectivity_gap"))
    if s is not None:
        terms["selectivity"] = w["selectivity"] * max(0.0, min(1.0, -s / 15.0))   # negative gap = selective
    g = _num(rec.get("groove_occupancy"))
    if g is not None:
        terms["groove"] = w["groove"] * max(0.0, min(1.0, g))

    return {"reward": round(sum(terms.values()), 4), "gated": gated,
            "terms": {k: round(v, 4) for k, v in terms.items()}}


def rank_by_reward(scored, weights=None):
    """Attach reward to each score() record and return sorted (best first)."""
    out = [{**rec, "_reward": reward(rec, weights)} for rec in scored]
    out.sort(key=lambda r: -r["_reward"]["reward"])
    return out


def build_preference_pairs(scored, *, prompt="", weights=None, max_pairs=None):
    """Rank the loop's scored candidates by reward and emit chosen≻rejected pairs in the EXISTING dpo_pairs
    schema (STREAM_VERIFY_SELECT). chosen = gate-passing; rejected = gate-failing (cleanest negatives) then
    lower-reward gated; margin = reward gap. Representation = HELM (the peptide generator is HELM-native).
    Returns a dpo_pairs.PairSet (its .to_trl_records() feeds the DPO trainer)."""
    from dpo_pairs import PreferencePair, PairSet, STREAM_VERIFY_SELECT
    ranked = rank_by_reward(scored, weights)
    gated = [r for r in ranked if r["_reward"]["gated"]]
    failed = [r for r in ranked if not r["_reward"]["gated"]]
    pairs, seen = [], set()
    # strongest signal: every gated candidate ≻ every gate-failing candidate
    for pos in gated:
        for neg in failed + [g for g in gated if g["_reward"]["reward"] < pos["_reward"]["reward"]]:
            if pos["helm"] == neg["helm"]:
                continue
            key = (prompt, pos["helm"], neg["helm"])
            if key in seen or (prompt, neg["helm"], pos["helm"]) in seen:
                continue
            seen.add(key)
            margin = round(pos["_reward"]["reward"] - neg["_reward"]["reward"], 4)
            clean = not neg["_reward"]["gated"]
            pairs.append(PreferencePair(
                prompt=prompt, chosen=pos["helm"], rejected=neg["helm"],
                stream=STREAM_VERIFY_SELECT, chosen_id=pos["helm"], rejected_id=neg["helm"],
                margin=margin, weak=not clean,
                reason=("gated ≻ gate-failed" if clean else "gated higher-reward ≻ gated lower-reward"),
                provenance={"stream": STREAM_VERIFY_SELECT, "reward_source": "score() verifier (feasibility-level)"}))
            if max_pairs and len(pairs) >= max_pairs:
                return PairSet(pairs=pairs, notes=["reward-ranked verify_select pairs (capped)"])
    return PairSet(pairs=pairs, notes=["reward-ranked verify_select pairs from score()"])


if __name__ == "__main__":
    from score import score
    from rule_conditioned_generator import gen_avb6
    # demo pool: gated by-construction survivors + deliberately gate-FAILING candidates (reward spread)
    _H, clean = gen_avb6(6)
    failing = ["cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])",          # INFRINGING
               "cyclo([2Nal]-R-G-D-L-A-[2Nal]-[dP]-[NMeK])",  # greasy
               "cyclo(A-R-G-D-L-G-A-[dP]-[NMeK])"]           # rule fail
    pool = [c["helm"] for c in clean] + failing
    scored = [score(h, "avb6") for h in pool]
    ranked = rank_by_reward(scored)

    print("=== reward ranking (score() verifier as RLVR reward) ===")
    for r in ranked:
        rw = r["_reward"]
        print(f"  reward={rw['reward']:+.3f} gated={rw['gated']}  {r['helm']}")
        print(f"      terms={rw['terms']}")
    ps = build_preference_pairs(scored, prompt="avb6", max_pairs=40)
    print(f"\n=== DPO preference pairs (verify_select, reward-ranked) ===")
    print(f"  emitted {len(ps.pairs)} pairs  stream_counts={ps.stream_counts()}")
    for p in ps.pairs[:4]:
        print(f"    chosen≻rejected (margin {p.margin}, {'clean' if not p.weak else 'weak'}): {p.reason}")
    out = os.path.join(HERE, "target_kb", "avb6_dpo_pairs.jsonl")
    ps.write_jsonl(out)
    print(f"\n  wrote {os.path.relpath(out, HERE)} ({len(ps.pairs)} pairs, full provenance)  -> dpo_peptide_trainer.py / TRL")

    # the G2 lesson, encoded: selectivity is a first-class reward term (admissible physics, PD-L1 round)
    try:
        import physics_dispatch as pd
        g1 = pd._load("pdl1_g1_candidates.json"); g2 = pd._load("pdl1_g2_candidates.json")
        k05 = next(r["helm"] for r in g1["prior_round3"] if r["id"] == "PDL1-K-05")
        a02 = next(r["helm"] for r in g2["candidates"] if r["id"] == "PDL1-G2-A02")
        print("\n=== selectivity reward (the G2 lesson: reward ALL gates, not just binding) ===")
        for lbl, h in [("K-05  selective (gap −15.27)", k05), ("G2-A02 NOT selective (gap +14.11)", a02)]:
            t = reward(score(h, "pdl1", tier="full"))["terms"]
            print(f"  {lbl}: binding_term={t.get('binding')}  selectivity_term={t.get('selectivity')}")
    except Exception as e:
        print(f"\n(selectivity demo skipped: {e})")
    print("\n  NOTE: reward + pairs only; gradient RLVR is gated on loop volume + GPU (OWN_LLM doc §5).")
