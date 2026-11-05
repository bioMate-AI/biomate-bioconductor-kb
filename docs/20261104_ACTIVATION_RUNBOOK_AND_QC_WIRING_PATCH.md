# Activation runbook + QC-engine wiring patch (2026-11-04)

Two next-cycle items for the generalization work (`20261104_GENERALIZATION_SESSION_IMPLEMENTATION.md`):
(A) flip the two routing flags on dev and verify with the smoke harness; (B) a patch wiring the
general QC-gate engine into the live QC path.

> **STATUS UPDATE (2026-11-04, later same day) — both items executed:**
> - **(A) is now automated** by `scripts/enable_generalized_routing_on_dev.sh`
>   (`on`/`off`/`status`). The manual SSM steps below are retained for reference, but the script is
>   the supported path. **Important correction to the original manual plan:** do **NOT** recreate the
>   container from the `biomate-galaxy-dev:rollback` image — verified on 2026-11-04 that the running
>   container's code (docker-cp'd by sync into the writable layer) is **newer than that image**, so
>   recreate-from-image would silently revert dev's backend. The script instead `docker commit`s the
>   live container to a fresh snapshot image and recreates from that, preserving all deployed code
>   with no re-sync / clean-tree / lock required, and verifies a code canary survived.
> - **(B) is APPLIED** — commit `a26e61fcd`, with `backend/tests/test_qc_declared_gates.py` (7 cases).
>   Engine + fallback mapping validated locally (7/7); the handler itself imports only in the dev
>   runtime (pulsar/boltons/scipy), so the test runs on dev, not the laptop.

---

## A. Activation runbook — flip the flags, run the smoke

The generalized code is deployed (commit `001f735e6`+) but the two chat-routing paths are gated by
env flags (default OFF) read at process start: `ML_TRAINING_ROUTING` (`ml_training/routing.py`) and
`MULTIOMICS_ROUTING` (`multiomics/routing.py`). `sync_to_dev.sh` does NOT set env vars, so this is a
one-time ops step on the `biomate-galaxy-dev` container.

### A.1 Open a shell on the dev host (SSM, as the sync script does)
```bash
INSTANCE_ID=i-06696b0d91f4346e0; EC2_USER=ubuntu; AZ=us-west-2a; KEY=/tmp/biomate_ec2_key_sync
# requires the AWS session-manager-plugin installed locally
[ -f "$KEY" ] || ssh-keygen -t ed25519 -f "$KEY" -N "" -q
aws ec2-instance-connect send-ssh-public-key --instance-id "$INSTANCE_ID" --availability-zone "$AZ" \
  --instance-os-user "$EC2_USER" --ssh-public-key "file://$KEY.pub" --region us-west-2 >/dev/null
ssh -i "$KEY" -o ProxyCommand="aws ssm start-session --target $INSTANCE_ID --document-name AWS-StartSSHSession --parameters portNumber=%p --region us-west-2" \
  -o IdentitiesOnly=yes "$EC2_USER@$INSTANCE_ID"
```

### A.2 Set the two flags in the container's env source, then recreate
Env is fixed at container start, so a HUP/`docker restart` is NOT enough — the container must be
**recreated** with the new env (or the env-file edited + `up`). On the dev host:
```bash
# 1) confirm how the galaxy container gets its env (find the compose / env-file):
docker inspect biomate-galaxy-dev --format '{{json .Config.Env}}' | tr ',' '\n' | grep -iE 'ROUTING|STORE' || true
docker inspect biomate-galaxy-dev --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'
# 2) add to that compose/env-file (same place RUN_STATE_STORE/REDIS_URL live):
#      ML_TRAINING_ROUTING=1
#      MULTIOMICS_ROUTING=1
# 3) recreate just the galaxy service:
#      cd <compose dir> && docker compose up -d biomate-galaxy-dev     # or `docker compose up -d` for the stack
# 4) verify the process now sees them:
docker exec biomate-galaxy-dev printenv ML_TRAINING_ROUTING MULTIOMICS_ROUTING   # expect: 1 / 1
# 5) wait for health:
#      curl -fsS http://localhost:8081/api/version >/dev/null && echo galaxy-up
```
If the dev runs gunicorn under a non-compose supervisor, set the two vars wherever
`RUN_STATE_STORE` is set for that unit, then restart the unit.

### A.3 Verify with the smoke harness (from the repo, any machine that can reach dev)
```bash
E2E_FIXTURE_PASSWORD='<fixture pw>' EXPECT_FLAGS_ON=1 bash scripts/smoke_generalized_routing.sh
```
Expected after activation: **both cases PASS** — the stream now carries `sklearn_tabular` /
`"source":"ml_training"` (model-training) and `"method":"SNF"` / `"source":"multiomics"` (multi-omics),
instead of today's fall-through to DaMiRseq / individual proteomics workflows. `EXPECT_FLAGS_ON=1`
makes a fall-through a hard failure, so this is a real activation gate.

### A.4 Rollback
Remove the two env lines + recreate the container. No code change; the generalized paths simply go
dormant again (fall through to normal workflow search).

---

## B. QC-engine wiring patch — APPLIED (commit `a26e61fcd`)

> Applied 2026-11-04 exactly as drafted below, plus `backend/tests/test_qc_declared_gates.py`
> (7 cases: halt blocks, advisory non-blocking, pass → no failure, list- and dict-form declared
> gates, malformed-spec never breaks the path). `py_compile` clean under Python 3.9. The handler
> is only importable inside the Galaxy runtime, so the test is dev-run; the engine + the exact
> fallback-mapping logic were validated in isolation locally (7/7).

Wires `galaxy.ai.qc_gate_engine.evaluate_gates` into `jobs/qc_trace_monitor.py` as a **general
fallback**: when a workflow DECLARES gates in its `qc_metrics.json` (a `gates` / `declared_gates`
list), evaluate them generically and fold the results into the existing `(qc_passed, failures)`
return — so a domain with **no hardcoded branch** still gets real gates from data. Additive: it does
not change any existing hardcoded branch; it only adds declared-gate evaluation.

**Why not applied here:** `qc_trace_monitor.py` is on the live QC path (and is frequently in other
sessions' edit set). This change must land in a dev-validated cycle with a run that declares gates
and asserts pass/advisory/halt. Apply it then, not blind.

### B.1 The patch (against `backend/lib/galaxy/jobs/qc_trace_monitor.py`, `_check_qc_thresholds`, def at line 4438)

At the **top of the method**, capture the declared gates + raw measured values *before* the dict is
wrapped in `_ObservedMetrics`:
```python
    def _check_qc_thresholds(self, process_name: str, qc_metrics: Dict[str, Any]) -> tuple[Optional[bool], list]:
        ...docstring...
        if not qc_metrics:
            return None, []
        _raw_metrics = dict(qc_metrics)                                   # ADD
        _declared_gates = _raw_metrics.get("gates") or _raw_metrics.get("declared_gates")  # ADD
        qc_metrics = _ObservedMetrics(qc_metrics)
        failures = []
        process_upper = process_name.upper()
        ...all existing hardcoded branches unchanged...
```

At the **end of the method**, just before the final `return`, add the general fallback:
```python
        # GENERAL FALLBACK (data-driven): evaluate any workflow-DECLARED gates via the
        # general engine, so a domain with no hardcoded branch above still gets real gates.
        if _declared_gates:                                              # ADD block
            try:
                from galaxy.ai.qc_gate_engine import evaluate_gates
                _measured = {k: v for k, v in _raw_metrics.items()
                             if k not in ("gates", "declared_gates")}
                _rep = evaluate_gates(_declared_gates, _measured)
                _seen = {(f.get("metric"), f.get("threshold")) for f in failures}
                for r in _rep.results:
                    if r.action in ("advisory", "halt") and (r.metric, r.threshold) not in _seen:
                        failures.append({
                            "metric": r.metric, "value": r.measured, "threshold": r.threshold,
                            "operator": r.op,
                            "message": f"{r.name}: {r.measured} {r.op} {r.threshold} (declared gate)",
                            "advisory": (r.action == "advisory"),
                            "evidence": r.evidence, "provenance": r.provenance,
                        })
            except Exception:
                pass   # declared-gate evaluation is best-effort; never break the hardcoded path

        if not qc_metrics.observed and not failures:                     # CHANGED: `and not failures`
            return None, []
        blocking_failures = [f for f in failures if not f.get("advisory", False)]
        return (len(blocking_failures) == 0, failures)
```
(The only change to existing lines is `and not failures` on the `qc_metrics.observed` guard, so a
process whose only gates are declared ones is still reported instead of returning `None, []`.)

### B.2 Validation (in the dev cycle, before trusting it)
1. Unit: the engine itself is covered by `qc_gate_engine_test.py` (7 tests). Add one
   `qc_trace_monitor` test: a process with **no hardcoded branch** + a `gates` block in
   `qc_metrics.json` → `_check_qc_thresholds` returns the declared pass/advisory/halt.
2. Dev run: a workflow emitting `qc_metrics.json` with a `gates` list (one halt, one advisory);
   assert the run's QC report shows them and that a halt gate blocks (SIGTERM path) while an
   advisory does not.
3. Regression: re-run an existing gated domain (e.g. cryo-EM FSC, ADMET hERG) and confirm its
   hardcoded gates still fire unchanged (the fallback must not alter them).

### B.3 Rollback
Revert the three added hunks. The hardcoded branches are untouched, so removal is clean.
