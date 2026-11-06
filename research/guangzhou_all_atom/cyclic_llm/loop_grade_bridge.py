#!/usr/bin/env python3
"""loop_grade_bridge.py — connect the closed loop's scored runs to the execution-graded reward store.

The convergence seam: when a candidate's physics/assay run completes (cofold -> complex.cif, MM-GBSA ->
mmgbsa_result.json with dG_bind_kcal_mol, or a wet-lab assay-ingest), hand it to the execution grader
(grade_detailed over the cyclic_peptide_* CONTRACTS) and persist the objective verdict + scalar reward in
graded_run_store. The RLVR reward for the peptide/HELM generator then reads back by run_id / campaign.

Reuses (audit-first): evaluation/local_trial/{graded_run_store.py, execution_grader.py} and this package's
score()/loop_batch.run_round. Pure execution facts — no similarity, no LLM. BUILT-NOT-FED: it records real
rewards the moment real runs flow; nothing is fabricated here.

CLI:  python loop_grade_bridge.py --selftest        # CPU end-to-end: synthetic scored run -> store -> reward
"""
import sys, os, json

_HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(_HERE, "..", "..", "..", "evaluation", "local_trial"))
import graded_run_store as S  # noqa: E402

# score()/loop physics run-kind -> execution_grader CONTRACT workflow name. A small registry (not a
# frozen dict): a new run-kind (e.g. a gromacs_pmx_fep edge) is added via register_run_kind(...) + its
# contract via graded_run_store.G.register_contract(...), without editing this module — mirroring the
# generic contract registry in execution_grader (Layer C of the physics-in-loop framework).
WORKFLOW = {"cofold": "cyclic_peptide_cofold", "mmgbsa": "cyclic_peptide_mmgbsa", "assay": "cyclic_peptide_assay"}


def register_run_kind(run_kind, workflow_name):
    """Map a closed-loop physics run-kind to its execution_grader contract workflow name (idempotent).
    The contract itself is registered separately via execution_grader.register_contract(workflow_name, ...)."""
    WORKFLOW[run_kind] = workflow_name
    return workflow_name


def workflow_for(run_kind):
    """The contract workflow name for a run-kind, with an actionable error if it is unregistered."""
    try:
        return WORKFLOW[run_kind]
    except KeyError:
        raise KeyError(f"unknown run_kind {run_kind!r}; register it via "
                       f"register_run_kind({run_kind!r}, '<workflow_name>') and "
                       f"execution_grader.register_contract('<workflow_name>', ...)")


def _run_id(scored):
    return str((scored.get("physics") or {}).get("design_id") or scored.get("design_id")
               or scored.get("id") or scored.get("helm"))


def record_scored_run(db_path, scored, physics_outputs, *, run_kind="mmgbsa", campaign=None,
                      status="succeeded", returncode=0, deep=False):
    """Record ONE completed, scored peptide candidate into the graded-run store.

    scored          : a score() record (helm, target, hard_gate_pass, binding_dG, physics.design_id, rank_key).
    physics_outputs : list of {name,size,s3_uri} from the completed cofold/MM-GBSA/assay Batch job
                      (canonical names: complex.cif / mmgbsa_result.json / assay_result.json).
    Returns the grade dict {run_id, verdict, tier, reward, ...}.
    """
    wf = workflow_for(run_kind)
    prov = {"helm": scored.get("helm"), "target": scored.get("target"),
            "hard_gate_pass": scored.get("hard_gate_pass"),
            "binding_dG": scored.get("binding_dG"), "rank_key": scored.get("rank_key")}
    run = S.run_from_outputs(_run_id(scored), wf, physics_outputs,
                             status=status, returncode=returncode, provenance=prov)
    return S.record(db_path, run, deep=deep, campaign=campaign)


def record_round(db_path, scored_list, physics_by_id, *, run_kind="mmgbsa", campaign=None, deep=False):
    """Record every scored candidate that has a COMPLETED physics run (physics_by_id keyed by run_id).

    scored_list    : list of score() records (e.g. the per-candidate `scored` inside loop_batch.run_round).
    physics_by_id  : {run_id: {status, returncode, outputs:[{name,size,s3_uri}]}} for completed jobs.
    Pending (not-yet-finished) candidates are skipped — they get recorded in a later round when they land.
    """
    out = []
    for sc in scored_list:
        pr = physics_by_id.get(_run_id(sc))
        if not pr:
            continue
        out.append(record_scored_run(db_path, sc, pr.get("outputs", []), run_kind=run_kind, campaign=campaign,
                                     status=pr.get("status", "succeeded"), returncode=pr.get("returncode", 0),
                                     deep=deep))
    return out


# ---- CPU end-to-end self-test: synthetic scored peptide runs -> grade -> store -> get_reward ----
def selftest():
    import tempfile, unittest.mock as mock
    db = os.path.join(tempfile.mkdtemp(), "peptide_grades.db")
    # a score()-shaped record for an αvβ6 candidate
    scored = {"helm": "cyclo(F-R-G-D-L-A-F-P-K)", "target": "avb6", "hard_gate_pass": True,
              "binding_dG": -41.2, "rank_key": [0, 0, -41.2, 0], "physics": {"design_id": "avb6_D007"}}
    out = lambda name, size: [{"name": name, "size": size, "s3_uri": f"s3://fixture/{name}"}]

    print("=== L1 (no S3): required-output presence -> tier -> reward ===")
    cases = [
        ("mmgbsa PASS",    dict(physics_outputs=out("mmgbsa_result.json", 420), run_kind="mmgbsa"),                         "pass",             1.00),
        ("cofold PASS",    dict(physics_outputs=out("complex.cif", 90210),      run_kind="cofold"),                         "pass",             1.00),
        ("mmgbsa MISSING", dict(physics_outputs=out("partial_log.txt", 120),    run_kind="mmgbsa"),                         "missing_required", 0.45),
        ("crashed",        dict(physics_outputs=out("mmgbsa_result.json", 420), run_kind="mmgbsa", status="failed"),       "crashed",          0.00),
    ]
    for label, kw, exp_tier, exp_rw in cases:
        g = record_scored_run(db, dict(scored, **{"physics": {"design_id": "avb6_" + label.replace(' ', '_')}}),
                              campaign="avb6_selftest", **kw)
        print(f"  {label:14s} tier={g['tier']:16s} verdict={g['verdict']:4s} reward={g['reward']:.2f}")
        assert g["tier"] == exp_tier and abs(g["reward"] - exp_rw) < 1e-9, f"{label}: {g['tier']}/{g['reward']}"
        assert S.get_reward(db, g["run_id"]) == exp_rw, f"{label}: store reward mismatch"

    print("=== deep (mocked S3): MM-GBSA content/json-keys check ===")
    with mock.patch.object(S.G, "s3_text", return_value=json.dumps({"dG_bind_kcal_mol": -41.2, "target": "avb6"})):
        g = record_scored_run(db, dict(scored, physics={"design_id": "avb6_deep_ok"}),
                              physics_outputs=out("mmgbsa_result.json", 420), run_kind="mmgbsa",
                              campaign="avb6_selftest", deep=True)
        print(f"  deep valid ΔG  tier={g['tier']:16s} reward={g['reward']:.2f}")
        assert g["tier"] == "pass" and g["reward"] == 1.00
    with mock.patch.object(S.G, "s3_text", return_value=json.dumps({"target": "avb6"})):  # no dG_bind
        g = record_scored_run(db, dict(scored, physics={"design_id": "avb6_deep_nodG"}),
                              physics_outputs=out("mmgbsa_result.json", 420), run_kind="mmgbsa",
                              campaign="avb6_selftest", deep=True)
        print(f"  deep missing ΔG tier={g['tier']:16s} reward={g['reward']:.2f}")
        assert g["tier"] == "content_invalid" and g["reward"] == 0.65, f"got {g['tier']}/{g['reward']}"

    # round-level wiring: a scored list + completed-physics map -> records only the finished ones
    scored_list = [dict(scored, physics={"design_id": "avb6_A"}), dict(scored, physics={"design_id": "avb6_B"})]
    physics_by_id = {"avb6_A": {"status": "succeeded", "returncode": 0, "outputs": out("mmgbsa_result.json", 420)}}  # B pending
    gs = record_round(db, scored_list, physics_by_id, run_kind="mmgbsa", campaign="avb6_round")
    assert len(gs) == 1 and gs[0]["run_id"] == "avb6_A", "record_round should skip the pending candidate"
    assert S.get_reward(db, "avb6_A") == 1.00 and S.get_reward(db, "avb6_B") is None

    print("\nSELFTEST PASS — loop scored-run -> peptide CONTRACT -> grade_detailed -> graded_run_store;"
          " get_reward returns the right scalar (L1 + deep + round-level). Pure execution facts.")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        raise SystemExit(selftest())
    print(__doc__)
