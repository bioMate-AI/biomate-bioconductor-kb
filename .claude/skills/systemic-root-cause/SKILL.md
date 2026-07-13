---
name: systemic-root-cause
description: >-
  Debugging playbook for when you're patching bug after bug in the same area and it feels
  like whack-a-mole. Use it the moment a subsystem produces a SECOND related failure, or an
  error changes shape after each "fix" (e.g. one crash becomes a different crash), or the same
  input passes in CI/local but fails in prod/Batch. It stops instance-patching, forces you to
  the ONE upstream source N things funnel through, gets ground truth from the real runtime, and
  closes the whole CLASS with a guard so it can't silently come back. BioMate-grounded (AWS
  Batch, SSM, gunicorn/gravity, the Nextflow executor) but the method is general.
---

# Systemic root-cause hunt (stop the whack-a-mole)

You reach for this when fixing one bug just spawns the next in the same neighborhood. The goal
is not another patch — it's to find the single upstream cause the symptoms funnel through, fix
it there, and add a guard that kills the whole class.

## 1. Recognize you're whack-a-moling (the trigger signals)

Escalate from instance-fixing to upstream-hunting the moment you see ANY of these:

- **Same subsystem, second related bug.** Two failures from the same component/data path in a row.
- **The error changes shape after each fix.** e.g. `cat() got NoneType` → `too many indices` →
  next thing. A moving symptom on a fixed input almost always means the *input/precondition* is
  wrong, not the code that trips over it. (Real case: both were "0 valid molecules reached the
  model", surfacing differently across chemprop versions — pinning versions never fixed it.)
- **Same input: CI/local passes, prod/Batch fails.** The bug is in the *environment or data path*,
  not the logic. Do NOT keep editing the logic.
- **You're pinning versions / adding try/except / special-casing** to make a symptom go away.
- **N similar files each need the same tweak.** If a fix wants to be applied to 50/272/... places,
  the real fix is upstream (the source they share), not the 272 edits.

## 2. Find the single upstream source

Ask: *where do all these symptoms funnel through?* Concretely:

- **Trace the data/param backwards** from the crash to where the value was produced. The crash
  site is rarely the bug. (Real case: `admet_model.py preds[:, i]` crashed, but the bug was 6
  hops upstream — the executor serialized a list param with `str()` → Python repr → the workflow
  parsed it as ONE string → 0 molecules.)
- **Count the blast radius.** `grep -rl` the pattern. If one change at the source fixes 272 files
  vs 272 edits, that's your answer and your proof it's systemic.
- **Diff the passing vs failing path.** CI passes, Batch fails → enumerate every difference
  (image, python, cpu, HOME, env vars, how the input is marshalled) and rule them out one by one
  with evidence, not guesses.

## 3. Get GROUND TRUTH from the real runtime (don't theorize)

You cannot out-think a shape mismatch — instrument it. The moves that actually crack it:

- **Read the real stderr, not the summary.** For AWS Batch: `aws batch describe-jobs --jobs <id>
  --query 'jobs[0].container.logStreamName'` then `aws logs get-log-events --log-group-name
  /aws/batch/job --log-stream-name <it>`. This showed the RDKit "Failed parsing SMILES
  '['CC(=O)...']'" that output files hid.
- **Plant a diagnostic in the failing path.** In the `except`, add `traceback.print_exc()` +
  `print(f"[DIAG] numpy={np.__version__} py={sys.version}")`. One run tells you the exact line +
  the actual runtime versions (killed the "it's a numpy 2.x issue" theory: it was 1.26.4).
- **Snapshot a hung/forked process.** `py-spy dump --pid <pid> --nonblocking` FROM THE HOST
  (container seccomp usually blocks ptrace); or `faulthandler.dump_traceback_later(N)` inside an
  in-container `python3 -c` repro. This is how the fork-after-threads deadlock was located.
- **Reproduce in isolation with the exact runtime knobs.** Pin cpus (`docker run --cpuset-cpus=0`),
  env, single vs batch input — a passing isolated repro is itself evidence ("not the code").
- **Verify the fix ALONE.** Revert every other patch, apply only the upstream fix, re-run. If it's
  green with everything else reverted, you fixed the real thing (not a pile of confounders).

## 4. Close the CLASS, not the instance

A fix that isn't guarded regresses. After the upstream fix:

- **Add a hard-gated CI test** that fails if someone reverts it. Cheapest form: read the source and
  assert the invariant (no heavy imports, runs in plain CI) — e.g. "both param paths json.dumps
  lists". Wire it as a *hard* gate, not the best-effort `pytest tests/ || true` step.
- **Make builds reproducible** if dep drift was involved: full lockfile (`pip freeze` →
  constraints) + a CI smoke that exercises the REAL artifact before it ships. Note the smoke only
  guards the path it exercises — if it calls `predict()` with a clean list it will NOT catch a
  param-serialization bug. Make the smoke walk the real prod path.
- **Split the upstream fix into its own small PR.** Decouple it from the big feature branch so it
  merges fast and low-risk (see PRs #96/#97: one focused root-cause fix each).

## 5. Be honest about scope

"One and done" is true for the CLASS you just closed (upstream fix + guard), never for "all bugs".
Say which class is now closed and what's still open (e.g. merged to branch ≠ deployed to prod).

## BioMate diagnostic map (where to look)

- **dev backend** = instance `i-06696b0d91f4346e0` (Name tag says "BioMate-Production" but runs the
  DEV stack). SSM-only: `aws ssm send-command ... AWS-RunShellScript`. See memory
  `dev-search-fork-deadlock` for the gravity/gunicorn env-injection gotcha (`gravity.environment`
  in galaxy.yml needs `galaxyctl update`, not just a restart).
- **Batch** compute env `biomate-nextflow-ce-v2`; job logs in CloudWatch `/aws/batch/job`; managed
  CE can't be manually scaled to 0; ECS default image-pull-behavior CACHES mutable tags → to force
  a fresh image use an immutable `:x86-<sha>` tag or terminate the warm instance.
- **Nextflow executor**: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` marshals
  params (list/dict must be `json.dumps`, guarded by
  `backend/tests/test_nextflow_executor_list_param_json.py`).
- **Container images**: `backend/docker/biomni-*/Dockerfile` + `requirements.lock`; built/verified
  by the reusable `.github/workflows/build-biomni-image.yml` (build → smoke inside image → push).
