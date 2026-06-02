# Nextflow runtime version drift on dev — actually running 26.04.2, not pinned 25.10.5

**Date:** 2026-06-01
**Branch:** `integration/next-phase`
**Verified on:** dev EC2 `biomate-galaxy-dev` container

## Finding

Dev is running **Nextflow framework 26.04.2**, not the pinned **25.10.5**.

```
$ docker exec biomate-galaxy-dev ls /tmp/nextflow_runs/<recent-run>/.nextflow/framework/
26.04.2

$ docker exec biomate-galaxy-dev printenv NXF_VER
(empty)
```

## Root cause

Three layers were *supposed* to enforce 25.10.5, but only the launcher install survives:

| Layer | Intended pin | Actual state |
|---|---|---|
| `scripts/sync_to_dev.sh` line 244 (`EXPECTED_NF_VER=25.10.5`) | Installs the **launcher script** at 25.10.5 | ✅ launcher script installed |
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` `env["NXF_VER"] = "25.10.5"` from commit `32aab65bd` | Sets `NXF_VER` env var when spawning Nextflow subprocess | ❌ **reverted** — line no longer in code (local or deployed) |
| Galaxy container env | Persistent `NXF_VER=25.10.5` | ❌ not set |

Without `NXF_VER` in the env, the Nextflow launcher script downloads the **latest** framework jar from JFrog on each first invocation. As of 2026-06-01 that's `26.04.2`.

## How the bug appeared

1. Commit `32aab65bd` (2026-05-25) bumped the pin from 25.10.0 → 25.10.5 and added `env["NXF_VER"]` in `nextflow_executor.py:_run_nextflow_command()`.
2. Between 2026-05-28 and 2026-06-01 the `nextflow_executor.py` file was rewritten multiple times by parallel sessions (parser-v2 sweep, `from __future__` fix, FD-decoupling work). The `env["NXF_VER"] = ...` line was dropped in one of those rewrites — neither local HEAD nor deployed `/app/lib/.../nextflow_executor.py` contains it now.
3. `sync_to_dev.sh` still reinstalls the launcher with `NXF_VER=25.10.5 curl get.nextflow.io | bash`, which **only** controls which launcher script gets written. The launcher's runtime decision about which framework jar to pull is governed by the live `$NXF_VER` env at invocation time, not by what was set during install.

## Impact

All tier 0 workflows actually executed on 26.04.2 today. Two of the fixes in this thread were specifically for 26.04 strict-DSL2 behaviour:

- `5b7888216` — inline `container System.getenv(...)` ternary because 26.04 strict DSL2 rejects top-level `def CONTAINER_IMAGE = ...` script statements.
- `5de908f0d` — `-profile aws` because the workflows' nextflow.config only define `aws` / `spot_gpu` / `local` / `test` (no `docker`), and 26.04 is stricter about validating profile names.

Both fixes are still correct under 26.04 and also harmless under 25.10. Reverting to 25.10.5 is therefore optional, not blocking.

## Decision needed

Pick one of:

1. **Stay on 26.04.2** — accept the drift. Update `sync_to_dev.sh` to set `EXPECTED_NF_VER=26.04.2` and refresh the comment. The two 26.04-specific fixes (`5b7888216`, `5de908f0d`) are already in tree and validated end-to-end on all five tier 0 demos.
2. **Re-pin to 25.10.5** — restore the `env["NXF_VER"] = "25.10.5"` line in `nextflow_executor.py` so every subprocess invocation gets the pin in its environment. The two 26.04 fixes stay in tree (they're correct for both versions). Add a test that asserts the framework directory name matches the pin.

Recommendation: **option 2** for reproducibility — runtime version drift on dev makes it hard to reproduce issues offline. The work-around fixes in tree are general enough to survive either version.

## Reproduction

```bash
# On dev
ssh ubuntu@dev "docker exec biomate-galaxy-dev bash -c '
  printenv NXF_VER
  ls /tmp/nextflow_runs/*/​.nextflow/framework 2>/dev/null | sort -u
'"
# Empty NXF_VER, framework=26.04.2 confirms drift.
```

## Fix-up snippet (option 2)

```python
# backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py
# Restore in the function that builds the Nextflow subprocess env:
env["NXF_VER"] = os.environ.get("NXF_VER", "25.10.5")
```

Add a startup assertion so the next sweep that drops this line trips the check:

```python
_NF_PIN = "25.10.5"
def _enforce_nextflow_version_pin(env: Dict[str, str]) -> None:
    if env.get("NXF_VER") != _NF_PIN:
        log.warning("NXF_VER=%r, expected %r — pinning", env.get("NXF_VER"), _NF_PIN)
        env["NXF_VER"] = _NF_PIN
```

## Related artefacts to look at

- `git show 32aab65bd:backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py | grep NXF_VER` — original line that got dropped
- `scripts/sync_to_dev.sh:244-248` — launcher-only pin (works as intended for the launcher script, but doesn't reach the runtime jar download)
- `docs/20260528_GALAXY_BACKEND_FIX_AND_PARSER_V2_V2.md` — same parallel-session sweep that introduced the `from __future__` regression also likely dropped this line
