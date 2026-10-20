#!/usr/bin/env python3
"""loop_batch.py — closed-loop driver slice with Batch-routed physics (REINVENT/Saturn-style, first slice).

The system lever: run `propose -> score(tier='full') -> select -> revise` with score()'s PHYSICS TIER
DISPATCHED through AWS Batch (physics_batch) instead of read-only from pre-computed files, with score() as
the verifier/reward. This is the first working slice — one round, wired end-to-end against the real Batch
seam.

What is wired here:
  1. propose          : reuse the spec-driven proposer (propose.propose) — candidates = [{helm, ...}].
  2. physics dispatch : for any candidate whose physics is MISSING (physics_for -> design_id None), dispatch a
                        cofold job via physics_batch.dispatch_cofold (spec-derived input; metal just works).
                        dry_run unless submit=True — one Batch job per missing candidate, NO at-scale sweep.
  3. reward           : score(helm, tier='full') — the multi-objective verifier (rule + FTO + developability +
                        physics when available); ranked by score.rank_key (Pareto: gate, FTO-DoE, binding, ...).
  4. select + revise  : freeze gate-passers; revise the fails (reuse loop.revise — the symbolic stand-in).

What remains (noted, not built here):
  (a) async: wait for the dispatched cofold jobs (physics_batch.fetch_result), run the MM-GBSA Batch job
      (biomate-ambertools-gpu / gromacs job-def) on the metal model from the physics track, and feed the
      results back into physics_dispatch's registry so the NEXT round's score() reads real physics;
  (b) replace loop.revise with the REINVENT4 / Saturn sample-efficient policy (reward = score());
  (c) a reviewed, budgeted at-scale fan-out (this slice stays at one job per candidate, gated).
"""
import sys, os, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import target_spec, physics_batch, physics_dispatch, fto_score
from score import score
import loop as _loop


def _physics_missing(helm, target):
    try:
        return physics_dispatch.physics_for(helm, target).get("design_id") is None
    except Exception:
        return True


def run_round(candidates, target="avb6", submit=False, round_id=None):
    """ONE REINVENT/Saturn-style round. candidates: list of {helm, ...} (or HELM strings).

    round_id scopes the per-candidate Batch run_ids so a multi-candidate submit does NOT collide on one
    S3 prefix (dispatch_cofold's default run_id is a bare timestamp — three jobs in the same second would
    share one prefix and all cofold the last-written peptide). Defaults to a timestamped round tag.
    """
    import time as _time
    round_id = round_id or f"{target}-{int(_time.time())}"
    helms = [c["helm"] if isinstance(c, dict) else c for c in candidates]
    # 2. physics tier routed through Batch: dispatch any candidate lacking physics
    dispatched = []
    for i, helm in enumerate(helms):
        if _physics_missing(helm, target):
            cand = {"id": f"C{i:03d}", "pep": fto_score._backbone(helm)}
            run_id = f"{round_id}-{cand['id']}"  # distinct prefix per candidate -> no overwrite
            d = physics_batch.dispatch_cofold(target, [cand], run_id=run_id, dry_run=not submit)
            dispatched.append({"id": cand["id"], "helm": helm, "pep": cand["pep"], "run_id": run_id,
                               "mode": ("submitted" if d.get("submitted_job_id") else
                                        ("cold_start" if d.get("cold_start") else "dry_run")),
                               "job_id": d.get("submitted_job_id"),
                               "result_prefix": d.get("result_prefix")})
    # 3. reward = score() (reads available physics; pending until the dispatched jobs land + MM-GBSA runs)
    scored = [score(h, target, tier="full") for h in helms]
    scored.sort(key=lambda r: r["rank_key"])
    # 4. select gate-passers; revise the fails
    passes = [r for r in scored if r["hard_gate_pass"]]
    revised = []
    for r in scored:
        if not r["hard_gate_pass"]:
            new, action = _loop.revise(r)
            if new:
                revised.append({"from": r["helm"], "to": new, "action": action})
    return {"target": target, "round_id": round_id, "n_candidates": len(helms),
            "physics_dispatched": len(dispatched),
            "gate_pass": len(passes), "revised": len(revised), "dispatched": dispatched,
            "ranking": [{"helm": r["helm"], "gate": r["hard_gate_pass"], "rank_key": r["rank_key"]} for r in scored]}


if __name__ == "__main__":
    submit = "--submit" in sys.argv
    rid = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--round-id=")), None)
    n = int(next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--n=")), "3"))
    try:
        import propose
        res = propose.propose(target_spec.load_spec("avb6"), n)
        cands = res.get("candidates", res if isinstance(res, list) else [])
    except Exception as e:
        print("proposer unavailable (%s); using backbones" % e, file=sys.stderr)
        cands = [{"helm": "cyclo(F-R-G-D-L-A-F-P-K)"}, {"helm": "cyclo(A-R-G-D-L-A-F-P-K)"}]
    out = run_round(cands, "avb6", submit=submit, round_id=rid)
    print(json.dumps(out, indent=2, default=str))
