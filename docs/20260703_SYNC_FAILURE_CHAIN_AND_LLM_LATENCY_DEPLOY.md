# 2026-07-03: Sync Failure Chain Resolution + LLM Latency Fixes Deployed

## Goal

Deploy LLM latency fixes from commits `eb961610f` through `8ce677b1a` to dev (https://dev-public.biomate.ai).
Core fixes: single retry per LLM provider (was 2), 30s fast-fail timeout for Gemini, orphan-completion poller,
`load_dotenv(override=False)` so container env vars win over .env file.

## What Happened — Four Consecutive Bugs

### Sync 7 (previous session) — ordering bug

`deploy_databases()` ran AFTER `restart_galaxy()` in `do_sync()`. Galaxy cold-boots in ~3.5 min.
With a warm Docker build cache (~14s), the 4-minute health gate started before `deploy_databases`
triggered another Galaxy restart → all probes exhausted → rollback.

**Fix (commit `397e12b2f`):** Moved `deploy_databases` before `restart_galaxy`. Extended health gate
from 48→120 probes (4 min → 10 min).

### Sync 8 — macOS Apple Double crash-loop

`deploy_backend_python()` used `tar -czf` without `COPYFILE_DISABLE=1`. macOS tar bundles a binary
`._<name>.py` Apple Double resource-fork file alongside every `.py` file in the archive. On Linux,
these extract as real files named `._*.py`. The `find -name "*.py"` loop then copies them into the
Galaxy container, including into alembic's `versions_gxy/` directory.

When gunicorn `--preload` boots, alembic iterates all `*.py` files in `versions_gxy/` to build
its revision map. The binary `._*.py` files contain null bytes → `ValueError: source code string
cannot contain null bytes` → crash loop → all 120 health probes fail → rollback.

Evidence: `extracted 580 python files` (290 real + 290 resource forks). The frontend tar had
`COPYFILE_DISABLE=1` from a prior session; the backend tar did not.

**Fix (commit `0cde1fa57`):**
- `COPYFILE_DISABLE=1 tar -czf ... --exclude='._*'` on the backend tar creation
- `find ... ! -name "._*"` on both EC2 find calls (count check + copy loop)

### Sync 9 — apostrophe breaks ec2_ssh block

The fix commit added a comment inside the `ec2_ssh '...'` single-quoted block containing `alembic's`.
Bash terminates single-quoted strings at the first `'`, so everything after `alembic` was parsed as
local bash code instead of being sent to SSH. The file-copy loop never ran on EC2.

Result: only the partial ec2_ssh block (up to the apostrophe) executed remotely — extracting the tar
but NOT copying files. Galaxy reloaded with unchanged old code. The sync reported `result=healthy`
because Galaxy was healthy (just running old code). Local bash tried to execute `docker exec ...`
at lines 415+, got `docker: command not found`.

**Fix (commit `a36e9fb61`):** Changed `alembic's` → `the alembic` in the comment.
Rule: **never use apostrophes in `ec2_ssh '...'` single-quoted blocks.**

### Sync 10 — diff gap

After sync 9 "succeeded", commit `a36e9fb61` became the new diff base. The only change since it was
`scripts/sync_to_dev.sh` itself → `do_backend=false` → Python files still not deployed. DB sync only.

**Fix (commit `8ce677b1a`):** Added a trailing newline to `nextflow_executor.py` to force a diff
in `backend/lib/` → `do_backend=true` on the next sync.

### Sync 11 — success

- `backend=true` confirmed
- 290 python files extracted (NOT 580 — no resource forks)
- 290 `cp:` lines, all real `.py` files, zero `._*.py`
- No `docker: command not found` (apostrophe fix confirmed)
- `nextflow_executor.py`, `bootstrap.py`, `completion_poller.py`, `run_state_store.py` all copied
- Galaxy healthy at attempt 11/24 (~50s after HUP)
- `result=healthy`

## What's Now Live on Dev

| Commit | Change |
|--------|--------|
| `eb961610f` | LLM retry_attempts: 2→1, 30s fast-fail for Gemini models |
| `6e552328e` | Orphan poller bootstrapped at module load; `load_dotenv(override=False)` |
| `0cde1fa57` | `._*` exclusion from backend tar (sync 8 root cause) |
| `a36e9fb61` | Apostrophe fix in ec2_ssh comment (sync 9 root cause) |
| `8ce677b1a` | Force-deploy touch commit |

## Lessons / Rules Added to Memory

1. **`ec2_ssh '...'` blocks must not contain apostrophes.** Use `the X` instead of `X's`.
2. **Check extracted count.** If `extracted N python files` shows 2× expected, `._*` resource forks got in.
3. **Successful health gate ≠ files deployed.** If `do_backend` was false or ec2_ssh broke, old code runs.
4. **Pre-sync compile check:** `python3.9 -c "compile(open(f).read(), f, 'exec')"` catches syntax errors
   without needing Galaxy's full dependency stack.

## Known Open Issues

- `stat: illegal option -- c` in DB sync (macOS stat called where Linux stat expected) — benign warning, DB does sync correctly
- `deploy_databases: command not found` at line 1082 in some sync runs — investigate; may be a heredoc quoting issue in a different ec2_ssh block
- `find: /tmp/backend_py_extract/backend: No such file or directory` sometimes appears but files still copy — investigate ordering

## Next Steps

- Verify LLM response times on dev are now <30s (original goal)
- Run E2E tests PH-2 through PH-5 on dev to confirm workflow execution still works
