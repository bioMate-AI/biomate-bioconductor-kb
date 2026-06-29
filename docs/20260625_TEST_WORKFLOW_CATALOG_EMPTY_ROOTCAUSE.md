# Test workflow catalog empty → "workflow-engine" error (2026-06-25)

## Symptom (reported via connector on test.stage-public.biomate.ai)

Connector → `POST /api/chat/stream` authenticates 200 (per-user API key works),
Claude correctly routes intent to workflow id `cyp_ddi_panel`, then **stalls
"fetching the catalog"** and the user sees a generic "workflow-engine" error.

## Reporter's fact that is a RED HERRING

> "Postgres `workflows` table exists but is 0 rows on test and prod."

The workflow **catalog** is **NOT** Postgres. Postgres only backs
`workflow_runs` / run-state (which is why `/api/workflows/runs` works). The
catalog/search reads a **SQLite** file.

## Actual data source (code evidence)

- `backend/lib/galaxy/ai/unified_workflow_search.py:113`
  `DB_PATH = Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"`
  → in-container `/app/database/galaxy_ai_tools.db`. Tables: `workflows`,
  `workflows_fts`, `workflow_chains`.
- `_get_connection()` (`unified_workflow_search.py:538`) opens a fresh
  `sqlite3.connect()` per query — so replacing the file is picked up with **no
  restart**.

## Root cause

The test container's `/app/database/galaxy_ai_tools.db` was the **20 KB stub**
baked into the image (only `workflows_fts*` shadow tables, **no `workflows`
table**). Galaxy log:

```
[Pass-0] FTS broad fetch failed: no such table: workflows
FTS search failed: no such table: workflows, falling back to LIKE search
[UnifiedWorkflowGeneration] Chain lookup failed: no such table: workflows
[UnifiedWorkflowGeneration] Error: no such table: workflows
```

→ search returns 0 / raises → frontend marks `workflow_failed`
(`frontend/server/routes.ts` ~5821) → user-facing "workflow-engine" error.

**Why it broke now:** the populated catalog (~2632 workflows, 279 MB) is **not
in the image** and **not in a persistent volume** — it is shipped out-of-band
(`scripts/sync_to_dev.sh` step 3 scp's `backend/database/galaxy_ai_tools.db`
→ host → `docker cp` into the container). **Any container recreate reverts to
the stub.** The 2026-06-25 API-key deploys ran `deploy.sh test` twice, which
recreated the Galaxy container and wiped the previously docker-cp'd catalog.
(dev-public's `/app/database/galaxy_ai_tools.db` is ALSO a 20 KB stub as of
2026-06-24 — same drift; it is not a reliable source.)

## Immediate remediation applied (2026-06-25) — test only

Restored the populated catalog from the S3 sync artifact (NOT from dev-public):

1. Source: `s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db`
   (279 MB / 292,659,200 bytes, 2026-06-22).
2. Presigned GET (bucket is us-east-1; test instance role can't read it →
   presign bypasses IAM) → `curl` on the test host → verify (`workflows`=2632,
   `workflows_fts`=2632, `cyp_ddi_panel` id 12831 present) → `docker cp` into
   `biomate-galaxy-deploy:/app/database/galaxy_ai_tools.db` →
   `chown galaxy:galaxy` + `chmod 664`.

Verified: search now resolves `cyp_ddi_panel`; `no such table` errors gone.
**This is treating the symptom — it is lost again on the next `deploy.sh`.**

## UPDATE 2026-06-26 — durable fix shipped (single-file bind-mount)

Implemented option-2-style persistence, but learned an important lesson:

- **First attempt (WRONG): named volume over the whole `/app/database`.** It
  persisted the catalog AND Galaxy's `gravity/` process-manager runtime state
  (supervisor sockets/pids). The first recreate worked (fresh volume), but the
  next `deploy.sh` down/up reused the volume with **stale gravity state** →
  Galaxy went **unhealthy** → frontend (depends_on healthy) never started →
  **test outage**. (PR #51 shipped this; corrected by the follow-up.)
- **Correct fix: single-file bind-mount** of just the catalog:
  `/opt/biomate/data/galaxy_ai_tools.db:/app/database/galaxy_ai_tools.db`.
  `/app/database` (gravity, cache, tmp) stays ephemeral image content → clean
  boots; only the catalog persists on the host. Verified: full down/up cycle →
  Galaxy healthy in ~120s, catalog persists (2632 rows).

Seed the host file once per host:
`mkdir -p /opt/biomate/data && curl <presigned s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db> -o /opt/biomate/data/galaxy_ai_tools.db && chmod 644`.
If the host file is absent, Docker creates an empty dir at the mount target →
sqlite can't open it → search degrades to no-results, **but Galaxy still boots
healthy** (safe). deploy.sh `down` (no -v) doesn't touch the host file.

## UPDATE 2026-06-26 (2) — workflow definition files also missing on test

Separate but related gap found while checking the container for workflow files:

- The catalog lists ~2632 workflows, but the container had only 764 `.nf` files;
  `cyp_ddi_panel`'s `.nf` was absent. Cause: `backend/.dockerignore` excludes
  `biomni_workflows/nextflow_nfcore/` ("indexed separately"), and dev seeds those
  files into the container via `sync_to_dev.sh` **step 4** (`docker cp` of
  `backend/biomni_workflows/`). deploy.sh-based envs (test/prod) never run that.
- Effect: generation still SUCCEEDS (card from catalog) but `workflow_ga.steps`
  comes back `0` — the steps parser (`_parse_nextflow_steps`) reads the `.nf`
  from disk, and the lazy `/api/nextflow/steps` fallback only covers
  `bioconductor` paths. So drug_discovery / nf-core workflows showed a card with
  no phase steps.
- Fix (def-only, mirrors the catalog): seed the `.nf`/`.config` definitions
  (~5MB bundle of `nextflow_nfcore`, 3734 files) onto the host at
  `/opt/biomate/data/nextflow_nfcore` and **additively** bind-mount it at
  `/app/biomni_workflows/nextflow_nfcore` (the image has no such subdir → no
  shadowing of `nextflow/`, `nextflow_generated/`). Verified:
  `/api/nextflow/steps` for cyp_ddi_panel returns 5 steps; `generate_workflow`
  returns `steps: 5`. NOTE: this seeds DEFINITIONS only — workflows whose
  EXECUTION needs bundled reference data (e.g. drug_discovery, 216MB of data)
  are not fully execution-ready on test; seed the full tree for that.

## UPDATE 2026-06-26 (3) — execute → 422 "Access denied to S3" = INVALID creds, not a bucket-permission gap

After steps resolved, `POST /api/nextflow/execute` returned 422
`{"error":"Access denied to S3 bucket 'biomate-nextflow-work'"}`. The reporter
read this as "the IAM role lacks bucket permission" — that is the WRONG fix.

Diagnosed on the test host:
- The preflight ([nextflow_executor.py:1976-2004]) does `boto3 s3.head_bucket()`
  with the default credential chain.
- The galaxy container has **explicit `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY`
  in its env** (so boto3 uses those, NOT the EC2 instance role).
- `boto3 sts get_caller_identity` in the container →
  **`InvalidClientTokenId: The security token included in the request is
  invalid`**. The embedded keys are **stale/deleted/invalid** → EVERY S3 call
  fails 403 (not just this bucket). Granting the bucket to any role/key does
  nothing while the dead embedded keys are present and used.
- EC2 instance role is `BioMateEc2DeployRole` (inline policies: dev/test
  secrets-read, ECR push/pull, `S3ReadDevSync`, `v6-eval-s3-and-terminate`) —
  it has SOME S3 but the backend isn't using it (embedded keys win), and it
  likely lacks WRITE to `nextflow/outputs/*`.

Fix (account-level; the deploy user `galaxy-dev` can't read/write the secret or
IAM, so this needs an admin):
- **Option A (matches current design):** in Secrets Manager
  `test/biomate/galaxy-env`, replace the invalid `AWS_ACCESS_KEY_ID`/
  `AWS_SECRET_ACCESS_KEY` with VALID keys whose identity has
  `s3:GetObject`/`PutObject`/`ListBucket` on `biomate-nextflow-work`, then
  `deploy.sh test <tag>` (re-materializes env).
- **Option B (cleaner, recommended):** remove the embedded keys from the secret
  so boto3 uses `BioMateEc2DeployRole`, and attach this inline policy to that
  role:
  ```json
  {"Version":"2012-10-17","Statement":[
    {"Sid":"NfWorkRW","Effect":"Allow",
     "Action":["s3:GetObject","s3:PutObject","s3:DeleteObject"],
     "Resource":"arn:aws:s3:::biomate-nextflow-work/*"},
    {"Sid":"NfWorkList","Effect":"Allow",
     "Action":["s3:ListBucket","s3:GetBucketLocation"],
     "Resource":"arn:aws:s3:::biomate-nextflow-work"}]}
  ```

### RESOLVED 2026-06-26 (admin SSO) — reused dev's key

The orphaned key `AKIAV2DX3XSKGYVKVDET` was a deleted key of the **`biomate-admin`**
IAM user (AdministratorAccess) — the identity dev's backend also uses. dev runs
on a valid `biomate-admin` key `AKIA…LG5H4HQ6` (last used today). Fix applied:
copied dev's working key into `test/biomate/galaxy-env`
(`PutSecretValue`, only `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` changed, the
other 19 keys preserved) → `deploy.sh test` re-materialized env. Verified in the
container: `sts get_caller_identity` → `user/biomate-admin`; `head_bucket` OK;
`put+delete` to `biomate-nextflow-work/nextflow/outputs/` OK. (No IAM key
created/deleted — `biomate-admin` was already at the 2-key limit; test now shares
dev's key. Proper long-term fix: dedicated least-priv backend identity / instance
role with S3-write + Batch, not an admin key embedded in the secret.)

### Next blocker (separate): execute sends `parameters: undefined`

`frontend/server/routes.ts:9543` logs `request.workflowDefinition.parameters`
and it's undefined → the SMILES never reaches Nextflow. The execute body is built
from `request.workflowDefinition.parameters` (routes.ts:9557/9581); whoever calls
`POST /api/workflows/execute` (the connector / chat execute path) isn't populating
it. Needs the actual re-run request payload to pin where the SMILES drops.

### UPDATE 2026-06-27 — params chain: fix A done; next blocker = Gemini dep missing

- **Fix A (merged, PR #61):** `workflow_ga.parameters` now flattens the
  rule/LLM-extracted values (not just `.nf` schema defaults), so headless
  consumers carry them to execute. Deployed to test via a fast backend OVERLAY
  (`FROM <deployed-backend> + COPY ai_assistant.py`) — no 15-min full Galaxy
  rebuild. Correct + necessary.
- **But the value still isn't extracted on test.** Logs:
  `[ParamSuggest] LLM inference failed: No module named 'google'`.
  `_infer_params_from_intent_llm` (ai_assistant.py:1834) is hardcoded to Gemini
  (`from galaxy.ai.gemini_flash import call_gemini_flash` →
  `import google.generativeai`). `google-generativeai` is **NOT in
  `backend/requirements.txt`** → not in the image. dev installs it at runtime
  (sync_to_dev pip layer); deploy.sh test/prod don't → extraction throws → every
  free-text param (SMILES, gene, PDB id) comes back `None` → fix A has nothing
  to flatten. GEMINI_API_KEY/GOOGLE_API_KEY ARE set on test, so the code tries
  Gemini and fails (the routing LLM works only because it uses the resilient
  fallback client that falls back to Anthropic).
- **Fix options for the Gemini gap:**
  - (b, recommended) make `_infer_params_from_intent_llm` use the same resilient
    fallback LLM client as routing (falls back to Anthropic) instead of the
    hardcoded `call_gemini_flash`. No new dep; fixes all envs; Anthropic already
    works on test.
  - (a) add `google-generativeai` to `backend/requirements.txt` + full backend
    rebuild. Keeps Gemini as primary but makes the image self-contained.

## Root-cause fix — for backend (pick one)

1. **Bake `galaxy_ai_tools.db` into the backend image (recommended).** The
   image build pulls the catalog artifact from
   `s3://biomate-nextflow-work/dev-sync/galaxy_ai_tools.db` and `COPY`s it to
   `/app/database/`. Catalog becomes part of the immutable artifact; deploys are
   reproducible; docker-cp drift is eliminated. Cost: ~279 MB image size; the
   reindex pipeline must publish a new artifact + trigger a rebuild on catalog
   change.
2. **Persistent volume / host bind-mount** for `/app/database/galaxy_ai_tools.db`
   that `deploy.sh` does not recreate. Restore once into the volume; container
   mounts it. Survives recreate.
3. **Restore-on-boot** entrypoint that fetches the catalog from S3 if the local
   file is missing/stub. Needs the instance role to have S3 read on the bucket
   (currently 403) — add a bucket policy or use a dedicated artifacts bucket.

## Secondary bug found (same logs) — please also fix

```
[UnifiedWorkflowGeneration] LTM correction fetch failed:
  (psycopg2.OperationalError) invalid sslmode value: "no-verify"
```

A Postgres connection string on test uses `sslmode=no-verify`, which is **not a
valid libpq value** (valid: disable/allow/prefer/require/verify-ca/verify-full).
The LTM (long-term-memory) correction path is broken until this env/DSN is
corrected (likely intended `require` or `prefer`). Non-fatal for routing but
silently disables LTM corrections.
