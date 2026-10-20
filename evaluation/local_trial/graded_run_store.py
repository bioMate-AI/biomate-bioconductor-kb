"""Graded-run store + execution-graded RL reward wiring.

The missing infrastructure that makes execution_grader.grade_run usable as a real RLVR reward:
  (a) a PERSISTED store (SQLite) that records the objective PASS/FAIL verdict + execution tier per
      candidate run, keyed by run_id, with provenance (the raw run dict), so verdicts accumulate as
      the closed loop produces runs; and
  (b) the VERDICT -> SCALAR-REWARD wiring: a dense, monotone reward over the execution ladder
      (execution_grader.TIERS) — NO string similarity, NO LLM, purely from what the run DID.

This is the reward source for the peptide/HELM generator's RLVR once the sibling closed loop streams
real (synthesize -> assay -> execute) runs: each run is graded + stored here, and training reads the
reward by run_id / campaign. Workflow-specific correctness is enforced by execution_grader.CONTRACTS.

CLI:
  python graded_run_store.py --selftest                 # CPU dry-run: tiers -> monotone reward ordering
  python graded_run_store.py --runs runs.json --db grades.db [--deep] [--campaign C]   # grade + persist
  python graded_run_store.py --db grades.db --report    # show stored verdicts/rewards
"""
import argparse, json, os, sqlite3, time

import execution_grader as G

# ---- (b) verdict -> scalar reward: dense, monotone over the execution ladder (G.TIERS) ----
# PASS == top tier. FAIL runs still get partial credit for HOW FAR they executed, so RL has a gradient
# instead of an all-or-nothing signal. Values are objective (no similarity / LLM).
TIER_REWARD = {
    "crashed":          0.00,   # never reached terminal success
    "no_outputs":       0.20,   # ran, produced no result outputs
    "empty_outputs":    0.30,   # outputs exist but all empty
    "missing_required": 0.45,   # non-empty, but a contract-required output is missing
    "content_invalid":  0.65,   # outputs present but a content / type / identity check failed (deep)
    "pass":             1.00,   # all objective checks pass
}
assert [TIER_REWARD[t] for t in G.TIERS] == sorted(TIER_REWARD[t] for t in G.TIERS), \
    "TIER_REWARD must be monotone along execution_grader.TIERS"


def reward_for_tier(tier):
    """Map an execution-ladder tier to a scalar RL reward in [0, 1]."""
    return TIER_REWARD[tier]


def run_from_outputs(run_id, workflow, outputs, status="succeeded", returncode=0, provenance=None):
    """Build a grade_detailed-compatible run dict from a completed job's S3 outputs.
    outputs: list of {name, size, s3_uri}. `provenance` fields are carried into run_json for traceability.
    This is the generic seam the closed loop uses to hand a finished (cofold/MM-GBSA/assay) run to grading."""
    run = {
        "id": str(run_id), "workflowName": workflow,
        "execution": {
            "status": "completed" if status == "succeeded" else (status or "failed"),
            "nextflowStatus": {"status": status, "returncode": returncode, "s3_output_files": outputs or []},
        },
    }
    if provenance:
        run.update(provenance)
    return run


def grade_and_reward(run, deep=False):
    """Objective grade of one run -> {run_id, workflow, verdict, tier, reward, reason, deep}."""
    verdict, reason, tier = G.grade_detailed(run, deep=deep)
    return {
        "run_id": str(run.get("id", run.get("run_id", "?"))),
        "workflow": run.get("workflowName", "?"),
        "verdict": verdict, "tier": tier, "reward": reward_for_tier(tier),
        "reason": reason, "deep": int(bool(deep)),
    }


# ---- (a) persisted graded-run store (SQLite) ----
SCHEMA = """
CREATE TABLE IF NOT EXISTS graded_runs (
    run_id    TEXT PRIMARY KEY,
    campaign  TEXT,
    workflow  TEXT,
    verdict   TEXT NOT NULL,          -- PASS | FAIL
    tier      TEXT NOT NULL,          -- execution_grader.TIERS
    reward    REAL NOT NULL,          -- scalar RL reward in [0,1]
    reason    TEXT,
    deep      INTEGER DEFAULT 0,      -- 1 if content was graded from S3
    graded_at TEXT NOT NULL,          -- ISO-8601 UTC
    run_json  TEXT                    -- raw run dict, for provenance / re-grade
);
CREATE INDEX IF NOT EXISTS idx_graded_runs_campaign ON graded_runs(campaign);
"""


def connect(db_path):
    con = sqlite3.connect(db_path)
    con.executescript(SCHEMA)
    return con


def record(db_path, run, deep=False, campaign=None):
    """Grade a run and persist its verdict+reward (upsert by run_id). Returns the grade dict."""
    g = grade_and_reward(run, deep=deep)
    con = connect(db_path)
    with con:
        con.execute(
            """INSERT INTO graded_runs (run_id, campaign, workflow, verdict, tier, reward, reason, deep, graded_at, run_json)
               VALUES (?,?,?,?,?,?,?,?,?,?)
               ON CONFLICT(run_id) DO UPDATE SET
                 campaign=excluded.campaign, workflow=excluded.workflow, verdict=excluded.verdict,
                 tier=excluded.tier, reward=excluded.reward, reason=excluded.reason, deep=excluded.deep,
                 graded_at=excluded.graded_at, run_json=excluded.run_json""",
            (g["run_id"], campaign, g["workflow"], g["verdict"], g["tier"], g["reward"],
             g["reason"], g["deep"], time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
             json.dumps(run)),
        )
    con.close()
    return g


def record_many(db_path, runs, deep=False, campaign=None):
    return [record(db_path, r, deep=deep, campaign=campaign) for r in runs]


def get_reward(db_path, run_id):
    """Scalar reward for one run_id, or None if not graded yet."""
    con = connect(db_path)
    row = con.execute("SELECT reward FROM graded_runs WHERE run_id=?", (str(run_id),)).fetchone()
    con.close()
    return row[0] if row else None


def rewards(db_path, campaign=None):
    """{run_id: reward} for RL batch sampling (optionally scoped to a campaign)."""
    con = connect(db_path)
    q, args = "SELECT run_id, reward FROM graded_runs", ()
    if campaign is not None:
        q += " WHERE campaign=?"; args = (campaign,)
    rows = con.execute(q, args).fetchall()
    con.close()
    return {r[0]: r[1] for r in rows}


# ---- CPU self-test: synthetic runs at each L1 tier -> correct verdict + monotone reward ordering ----
def _synthetic_runs():
    def done(files):
        return {"nextflowStatus": {"status": "succeeded", "returncode": 0, "s3_output_files": files}}
    return [
        ("crashed",          {"id": "r_crash", "workflowName": "rnaseq", "execution": {"status": "running"}}),
        ("no_outputs",       {"id": "r_noout", "workflowName": "rnaseq",
                              "execution": {"status": "completed", **done([{"name": "versions.yml", "size": 50}])}}),
        ("empty_outputs",    {"id": "r_empty", "workflowName": "rnaseq",
                              "execution": {"status": "completed", **done([{"name": "out.csv", "size": 0, "s3_uri": "s3://x/out.csv"}])}}),
        ("missing_required", {"id": "r_miss", "workflowName": "Predict Admet Properties",
                              "execution": {"status": "completed", **done([{"name": "qc_metrics.json", "size": 120, "s3_uri": "s3://x/qc.json"}])}}),
        ("pass",             {"id": "r_pass", "workflowName": "rnaseq",
                              "execution": {"status": "completed", **done([{"name": "deseq2_results.csv", "size": 4096, "s3_uri": "s3://x/d.csv"}])}}),
    ]


def selftest():
    import tempfile
    cases = _synthetic_runs()
    print("=== grade -> tier -> reward (L1, no S3) ===")
    prev = -1.0
    db = os.path.join(tempfile.mkdtemp(), "grades.db")
    for expect_tier, run in cases:
        g = record(db, run, deep=False, campaign="selftest")
        print(f"  {g['run_id']:9s} tier={g['tier']:16s} verdict={g['verdict']:4s} reward={g['reward']:.2f}  ({g['reason']})")
        assert g["tier"] == expect_tier, f"{g['run_id']}: tier {g['tier']} != expected {expect_tier}"
        assert (g["verdict"] == "PASS") == (expect_tier == "pass"), f"{g['run_id']}: verdict/tier mismatch"
        assert g["reward"] > prev, f"reward not strictly increasing at {expect_tier} ({g['reward']} <= {prev})"
        prev = g["reward"]
    # store round-trips
    back = rewards(db, campaign="selftest")
    assert len(back) == len(cases), "store did not persist every run"
    assert back["r_pass"] == 1.0 and back["r_crash"] == 0.0, "stored rewards wrong"
    assert get_reward(db, "r_pass") == 1.0 and get_reward(db, "nope") is None
    # consistency with the authoritative grade_run verdict
    for _t, run in cases:
        assert G.grade_run(run)[0] == grade_and_reward(run)["verdict"], "grade_run vs store verdict drift"
    print("\nSELFTEST PASS — tiers monotone (crashed<no_outputs<empty<missing_required<pass),"
          " verdicts consistent with grade_run, store round-trips.")
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--runs", help="JSON array of run objects (list_runs/get_run) to grade + persist")
    ap.add_argument("--db", default="graded_runs.db")
    ap.add_argument("--deep", action="store_true", help="validate output CONTENT from S3 (richer tier)")
    ap.add_argument("--campaign", default=None)
    ap.add_argument("--report", action="store_true", help="print stored verdicts/rewards from --db")
    a = ap.parse_args()
    if a.selftest:
        return selftest()
    if a.runs:
        runs = json.load(open(a.runs))
        if isinstance(runs, dict):
            runs = [runs]
        gs = record_many(a.db, runs, deep=a.deep, campaign=a.campaign)
        npass = sum(g["verdict"] == "PASS" for g in gs)
        for g in gs:
            print(f"{g['verdict']:4s} reward={g['reward']:.2f} tier={g['tier']:16s} {g['workflow']:30s} {g['run_id']}  {g['reason']}")
        print(f"\n{npass}/{len(gs)} PASS -> persisted to {a.db}")
        return 0
    if a.report:
        con = connect(a.db)
        for row in con.execute("SELECT verdict, reward, tier, workflow, run_id, reason FROM graded_runs ORDER BY graded_at"):
            print(f"{row[0]:4s} reward={row[1]:.2f} tier={row[2]:16s} {row[3]:30s} {row[4]}  {row[5]}")
        con.close()
        return 0
    ap.error("one of --selftest / --runs / --report is required")


if __name__ == "__main__":
    raise SystemExit(main())
