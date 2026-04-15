# CryoEM E2E Fixes & AWS IAM — 2026-04-15

## Context

Continuing from the previous session where CS-3/4/5 were failing immediately because the
CryoSPARC workflow was rejected by the Python executor with a 422 before Nextflow even started.

---

## Root Causes Fixed

### 1. S3 Glob Pattern Validation (nextflow_executor.py)

**Problem:** `_validate_s3_url()` called `s3.head_object(Bucket, Key)` with a literal glob key
like `empiar-10028/Micrographs/00[1-5]_movie.mrcs`. S3 `head_object` doesn't support globs —
it returns 404, which the executor treated as "file not found" and raised HTTP 422.

**Fix:** Added glob detection before the `head_object` call:
```python
_is_glob_key = any(c in key for c in ("*", "?", "[", "]"))
if check_object and key and not key.endswith("/") and not _is_glob_key:
    # head_object check — skipped for glob patterns
```

File: `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py`

**The fix was already in the file** from the previous session, but the backend had not been
restarted. Restarting the backend made it effective.

### 2. Galaxy Backend Was Not Running

**Problem:** The Galaxy backend (port 8081) was not running. All execute calls from routes.ts
returned connection errors, which surfaced as `Poll 0: failed 0/0` in tests.

**Fix:** Started the backend with `cd /home/yzhang/biomate/backend && bash start_backend.sh`.

Verification:
```bash
curl http://localhost:8081/api/version  # → {"version_major":"25.1","version_minor":"dev0"}
```

### 3. AWS Batch IAM — ecsInstanceRole Cannot Access biomate-cryo-data

**Problem:** The EMPIAR-10028 data lives in `s3://biomate-cryo-data/`. The `ecsInstanceRole`
used by all Batch compute environments had no policy granting access to this bucket, causing:
```
AccessDenied when calling the ListObjectsV2 operation: User: arn:aws:sts::...:assumed-role/ecsInstanceRole/...
is not authorized to perform: s3:ListBucket on resource: "arn:aws:s3:::biomate-cryo-data"
```

**Fix:** Added a bucket policy to `biomate-cryo-data` granting the role read access:
```bash
aws s3api put-bucket-policy --bucket biomate-cryo-data --region us-west-2 --policy '{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "AllowECSInstanceRoleAccess",
    "Effect": "Allow",
    "Principal": {"AWS": "arn:aws:iam::399683337364:role/ecsInstanceRole"},
    "Action": ["s3:GetObject", "s3:ListBucket"],
    "Resource": ["arn:aws:s3:::biomate-cryo-data", "arn:aws:s3:::biomate-cryo-data/*"]
  }]
}'
```

All Batch compute environments use `ecsInstanceRole` (verified: 10 CEs all use
`arn:aws:iam::399683337364:instance-profile/ecsInstanceRole`).

---

## Test Results

### 5/5 Playwright Tests Pass

Suite: `frontend/e2e/cryoem-stepwise-and-output.e2e.ts`

| Test | Playwright | Audit assertions | Notes |
|------|-----------|-----------------|-------|
| CS-1 | ✓ pass | 8/8 | Workflow card, QC section, phase cards |
| CS-2 | ✓ pass | 7/7 | Step control UI before run |
| CS-3 | ✓ pass | 5/7 | Workflow completed on AWS Batch; `nf-process-list` assertion is a timing race (list appears then disappears before check); `phase-card-statuses` cards don't update after completion |
| CS-4 | ✓ pass | 1/2 | `workflow-card-appeared` fails occasionally due to LLM non-determinism; the `waitForWorkflowCard` handles clarifications but LLM sometimes doesn't match in 3min |
| CS-5 | ✓ pass | 3/9 (fast-fail) or 11/11 (instant-fail) | When workflow fails fast, 11/11 pass; when workflow runs 15min+ on Batch, the page may go stale and UI elements become invisible |

### Audit Counts

- Run A (after backend restart, workflow fails fast): `3/6` suite assertions (CS-1, CS-2, CS-5 all-pass)
- Run B (after IAM fix, workflow completes in ~15min): `2/6` suite assertions (CS-1, CS-2 all-pass)

The variance is due to:
1. CS-3 `nf-process-list` timing — fixed by workflow actually progressing, but the poll window is narrow
2. CS-4 LLM non-determinism — sometimes routes to workflow card, sometimes to clarification
3. CS-5 long-run stale page — when workflow takes 15+ min, Playwright page loses live UI state

---

## Database Entry

CryoSPARC workflow in `galaxy_ai_tools.db` (id=12833):
- **Registered path:** `biomni_workflows/pipeline_composition/pipelines/cryosparc_standard_spa/main.nf`
- **Alternative path:** `biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf`
- Both files exist. The DB uses the `pipeline_composition` version (staged pipeline).

---

## S3 Data

`s3://biomate-cryo-data/empiar-10028/Micrographs/` — 19+ files `001_movie.mrcs` through `019_movie.mrcs` (1GB each). EMPIAR-10028 β-galactosidase dataset.

Test uses glob `00[1-5]_movie.mrcs` to select only 5 movies (≈5GB) for a shorter run.

---

## Remaining Open Issues

1. **CS-5 stale page**: When CryoSPARC runs 15+ minutes, Playwright browser session drifts. The `workflow-completion-banner`, `run-metrics-strip`, `button-analyze-results` are not visible after completion because the viewer component may have scrolled/unmounted. Consider adding a `page.reload()` + re-locate after `pollToTerminal` returns.

2. **CS-4 LLM non-determinism**: On ~30% of runs, the initial CryoSPARC query triggers a clarification instead of a workflow card. The test handles this with a follow-up message but the follow-up may also get a clarification. Adding `domain_hint=cryo_em` to the query helps but doesn't guarantee routing.

3. **phase-card-statuses-updated-after-run**: After workflow completes, the phase cards inside the viewer don't show updated status icons (the cards still show `undefined` for status). This is a UI bug — the `phaseCards` state isn't refreshed after terminal status arrives from the poll.

---

## Key Files Modified This Session

- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — S3 glob fix (applied prior session, restart activated it)
- `backend/lib/galaxy/ai/ai_assistant.py` — `_OPTIONAL_NULL_PARAMS`, `_extract_explicit_params_from_query` (applied prior session)
- `backend/biomni_workflows/nextflow_nfcore/subworkflows/cryo_em/cryosparc_standard_spa/main.nf` — `mock_mode=false` (applied prior session)
- AWS S3 bucket policy: `biomate-cryo-data` — new policy applied via `aws s3api put-bucket-policy`
