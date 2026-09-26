# On-Prem Simulation Test Results — 2026-09-26

## Context

Simulated a real customer on-prem single-node BioMate deployment on:
- Instance: `i-0d39e0fe269a69864` (`biomate-onprem-sim`, `35.92.8.10`, t3.xlarge, Ubuntu 22.04)
- LLM: Qianwen/DashScope (`GALAXY_AI_LLM_PROVIDER=openai_compatible`, model `qwen-max`)
- Branch tested: `fix/onprem-llm-compatibility`

## Full 9-Step Journey Test Results

All 9 steps GREEN on final run with image `sha-97f38f24b169`:

| Step | Description | Status |
|------|-------------|--------|
| 1 | Login (register + auth token) | ✅ |
| 2 | Create project | ✅ |
| 3 | Qianwen tool call (research_query fires) | ✅ |
| 4 | Qianwen → ADMET workflow routing (`workflow_ready`) | ✅ |
| 5 | Workflow search + execute accepted | ✅ |
| 6 | Workflow completed (~10s) | ✅ |
| 7 | Output files listed (5 files from local filesystem) | ✅ |
| 8 | MinIO bucket verified | ✅ |
| 9 | AI findings generated via Qianwen | ✅ |

## Security Verification Results (sha-85728dc568b3)

| Check | Expected | Actual | Pass |
|-------|----------|--------|------|
| Cancel without token | 401 | 401 | ✅ |
| Cancel with token, bad ID | 404 | 404 | ✅ |
| Execute without token | 401 | 401 | ✅ |
| Rerun without token | 401 | 401 | ✅ |
| Chat sessions API (`/api/sessions`) | 200 | 200 (4 sessions) | ✅ |
| License status (demo key) | valid=true | valid=false (Galaxy not restarted) | ⚠️ config |

## Bugs Found and Fixed

### Bug 1 — Output files returning 0 for local (non-S3) runs
- **Root cause**: `integration/next-phase` routes.ts only called Galaxy's `/api/nextflow/status/{id}` which returns `s3_output_files` (empty for local runs). Missing second call to `/api/nextflow/runs/{id}/output_files`.
- **Fix**: Added fallback in `routes.ts` `/api/workflows/runs/:id/output_files` handler to call `GET /api/nextflow/runs/{id}/output_files` from Galaxy when S3 files are empty. Added `/api/galaxy-proxy/…` route to proxy local file downloads through the Node server.
- **Commit**: `64765fb44`

### Bug 2 — Fresh-install crash: Docker CLI not installed in backend image
- **Root cause**: Backend Docker image (`biomate-galaxy`) didn't have Docker CLI installed.
- **Fix**: Added `docker-ce-cli` installation to backend Dockerfile.
- **Commit**: `64765fb44`

### Bug 3 — Fresh-install crash: `nf-work` dir missing permissions
- **Root cause**: `install.sh` never created `/app/nf-work`. Docker creates bind-mount dirs as root; Galaxy (uid=1000) can't write.
- **Fix**: Added step to `install.sh`: `mkdir -p $NEXTFLOW_WORK_DIR && chmod 777 $NEXTFLOW_WORK_DIR` before `docker compose up`.
- **Commit**: `fda22c82f`

### Bug 4 — AI findings returning 503 with non-Anthropic LLMs
- **Root cause**: `/api/workflows/runs/:id/ai/analyze` checked `process.env.ANTHROPIC_API_KEY` at entry and returned 503 if missing.
- **Fix**: Removed the ANTHROPIC_API_KEY early guard. `llmGenerate()` routes to any provider.
- **Commit**: `be742fab0` (PR #247)

### Bug 5 — Background findings task hardcoded to Gemini
- **Root cause**: Background findings analysis task called `callGeminiFlash()` unconditionally.
- **Fix**: Detect configured provider; use `llmGenerate()` when Gemini is not the sole configured LLM.
- **Commit**: `be742fab0` (PR #247)

### Bug 6 — Status endpoint missing auth (`authenticateToken`)
- **Root cause**: `GET /api/workflows/runs/:id/status` used no auth middleware — anyone could poll any run.
- **Fix**: Added `authenticateToken` middleware.
- **Commit**: `9dd864818`

### Bug 7 — Failed-run findings stuck in "pending" forever
- **Root cause 1**: No status check before triggering background analysis.
- **Root cause 2**: Checked `run.status` (undefined) instead of `run.execution?.status`.
- **Fix**: Added status guard; return static `{status:'error'}` response immediately for failed runs.
- **Commit**: `97f38f24b`

### Bug 8 — Cancel/rerun/execute endpoints missing auth (SECURITY)
- **Root cause**: All three used `optionalAuth` — unauthenticated users could cancel any run, rerun any workflow, and execute arbitrary workflows.
- **Fix**: Changed to `authenticateToken` + added userId ownership check on cancel/rerun.
- **Commit**: `77e0de074`
- **Verified**: All three return 401 without token on deployed instance.

### Bug 9 — Browser-uploaded files not staged for Nextflow on on-prem
- **Root cause**: `stageLocalFilesForBatch()` returned early when `NEXTFLOW_USE_AWS=false`, leaving uploaded files inaccessible to Galaxy.
- **Fix (frontend)**: Detect `S3_ENDPOINT_URL` (MinIO); create path-style MinIO client and upload files to `biomate-data` bucket.
- **Fix (backend)**: `_generate_executor_config()` now generates a minimal nextflow.config with MinIO aws.client settings when local executor + S3_ENDPOINT_URL is set, so Nextflow can stage `s3://` inputs.
- **Commit**: `112ba23c3`

### Bug 10 — `.env.onprem.example` duplicate `NEXTFLOW_WORK_DIR` and wrong default license key
- **Root cause 1**: Two `NEXTFLOW_WORK_DIR` entries (line 106: `/tmp/biomate-nf-work`, line 121: `/app/nf-work`).
- **Root cause 2**: `BIOMATE_LICENSE_KEY` set to placeholder `BMOP-XXXX-...` causing fresh installs to show `valid:false`.
- **Fix**: Removed duplicate entry; set `BMOP-DEMO-DEMO-DEMO-DEMO` as default.
- **Commit**: `85728dc56`

### Bug 11 — `install.sh` admin creation uses `require('./server/db.ts')` (broken in production)
- **Root cause**: Production image has no `.ts` files — TypeScript is compiled to `/app/dist/`. The admin creation silently failed for all users.
- **Fix**: Replaced with API-based flow: `POST /api/auth/register` → `POST /api/auth/verify-email` → psql UPDATE to `subscription_tier='admin'`.
- **Commit**: `15c3237d1`

### Bug 12 — `install.sh` calls `_wizard()` before defining it
- **Root cause**: `_wizard()` function was defined at line ~131, but called at line ~119 inside the `if [[ ! -f ".env" ]]` block. With `set -euo pipefail`, bash exits with "command not found" on first-time installs without an existing `.env`.
- **Fix**: Moved `_wizard()` definition before the `if` block that calls it.
- **Commit**: `d545a57e0`

### Bug 13 — `DOCKER_GID` not auto-detected; GALAXY_API_KEY not auto-generated
- **Root cause 1**: install.sh wizard auto-generated JWT/Session secrets but not `GALAXY_API_KEY` (shared key for frontend↔Galaxy auth). The `.env` comment said "auto-generate" but nothing was implemented — both containers run with empty key.
- **Root cause 2**: `DOCKER_GID` defaults to 999 but actual Docker socket GID varies by distro. Wrong GID → galaxy user can't access docker.sock → Nextflow task containers can't launch.
- **Fix**: Wizard now generates GALAXY_API_KEY alongside JWT/Session. Added step 4b to auto-detect Docker socket GID via `stat -c %g /var/run/docker.sock` and update `.env`.
- **Commit**: `d545a57e0`

### Bug 14 — Local file download proxy missing authentication (SECURITY)
- **Root cause**: `/api/galaxy-proxy/api/nextflow/outputs/local-download` used `optionalAuth` — any caller who guessed a run_id UUID could download output files without logging in.
- **Fix**: Changed to `authenticateToken` + user ownership check (run.userId must match req.user.id).
- **Commit**: `d545a57e0`

### Bug 15 — `backend/config/galaxy.yml` tracked in git with real credentials + broken paths
- **Root cause (security)**: The dev `galaxy.yml` (containing Anthropic/OpenAI API keys and a `/Users/kky/...` absolute path) was tracked in git despite `.gitignore`, due to `git add -f` at some earlier point.
- **Root cause (functionality)**: On a fresh git clone, `backend/config/galaxy.yml` doesn't exist (now removed). The bind mount `./backend/config:/app/config` hides the image-baked `galaxy.yml`, causing Galaxy to fail to start.
- **Fix**: Removed `galaxy.yml` and `galaxy.yml.docker` from git tracking. Added install.sh step 4a to copy `galaxy.yml.template → galaxy.yml` if missing before `docker compose up`.
- **Commit**: `c2ca6b39f`

### Bug 16 — `galaxy.yml.template` LLM provider/model/key override env vars (CRITICAL)
- **Root cause**: The template contained `ai_llm_provider: anthropic`, `ai_llm_model: claude-sonnet-4-5`, and `ai_llm_api_key: ${ANTHROPIC_API_KEY}`. Galaxy reads galaxy.yml with a raw YAML parser — `${ANTHROPIC_API_KEY}` is NOT substituted; it's treated as the literal string `"${ANTHROPIC_API_KEY}"`. Galaxy's config system calls `setattr(self, 'ai_llm_api_key', '${ANTHROPIC_API_KEY}')` for every key in the YAML. When `configure_ai_assistant(dict(app.config.__dict__), ...)` runs, `raw_config.get('ai_llm_api_key')` returns the truthy literal, short-circuiting the env-var fallback chain. Similarly, `raw_config.get('ai_llm_provider')` returns `'anthropic'`, overriding `GALAXY_AI_LLM_PROVIDER` from .env.
- **Impact**: All non-Anthropic customers on fresh install get `provider=anthropic` with `api_key="${ANTHROPIC_API_KEY}"` (literal) → every LLM call fails with API authentication error.
- **Fix**: Removed all three LLM keys from `galaxy.yml.template`. LLM config comes exclusively from env vars via `configure_ai_assistant()`'s fallback chain.
- **Commit**: see below

### Bug 17 — `install.sh` `_wizard()` sed injection via user-supplied values
- **Root cause**: All password/key writes used `sed -i.bak "s|^KEY=.*|KEY=$val|"`. If the value contains `|` (a valid password character, common in password-manager-generated passwords), the sed delimiter is broken — the command either fails or corrupts the .env file line.
- **Impact**: Passwords or API keys containing `|` are silently not written to `.env`, leaving the field empty and causing startup failures that are hard to diagnose.
- **Fix**: Added a `_setenv KEY VALUE` helper function using pure bash line-by-line rewrite (no delimiters) — handles any value including `|`, `\`, `&`, and `/`.
- **Commit**: see below

### Bug 18 — `install.sh` missing `_check_required GALAXY_API_KEY`
- **Root cause**: `_check_required` was called for POSTGRES_PASSWORD, JWT_SECRET, SESSION_SECRET, MINIO_ROOT_PASSWORD — but not GALAXY_API_KEY. In `--non-interactive` mode, if the user's pre-filled `.env` has empty GALAXY_API_KEY, the install proceeds without complaint.
- **Impact**: Both frontend and Galaxy start with empty bootstrap API key → internal auth uses empty == empty (matches), but Galaxy's port 8081 is effectively unauthenticated.
- **Fix**: Added `_check_required GALAXY_API_KEY` to the validation block.
- **Commit**: see below

### Bug 19 — `onprem-update.sh` health check always passes (NDJSON vs single-JSON parse)
- **Root cause**: `docker compose ps --format json` (Docker Compose v2) emits NDJSON — one JSON object per line. The check used `python3 -c "import sys,json; d=json.load(sys.stdin)"` which expects a single JSON value and raises `json.JSONDecodeError: Extra data` on NDJSON. The error was suppressed by `2>/dev/null`, `|| echo ""` returned an empty string, and the condition `"" != "healthy" && "" != ""` is `False` → service counted as healthy immediately.
- **Impact**: `bash onprem-update.sh` exits the health-check loop without waiting for services to actually be ready, causing the verification step to run against containers still starting up.
- **Fix**: Replaced JSON-parsing approach with `docker inspect --format '{{.State.Health.Status}}'` using the known container names (`biomate-postgres`, `biomate-redis`, `biomate-galaxy`, `biomate-frontend`) — matches the approach in `install.sh`.
- **Commit**: see below

### Bug 20 — `onprem-update.sh` never sources `.env` — POSTGRES_USER/DB always use hardcoded defaults
- **Root cause**: `backup_data()` references `${POSTGRES_USER:-biomate}` and `${POSTGRES_DB:-biomate}`. The script never sources `.env`, so these always fall back to the hardcoded `biomate` defaults, even if the customer configured different values.
- **Impact**: If POSTGRES_USER != "biomate" in .env, `pg_dump -U biomate` fails with authentication error and backup is skipped (silently, since the outer `||` swallows the failure).
- **Fix**: Added `set -a; source "$REPO_DIR/.env"; set +a` in `main()` immediately after `check_prerequisites`.
- **Commit**: see below

### Bug 21 — `scripts/biomate create-admin` shell/SQL injection + wrong Postgres defaults
- **Root cause 1**: Password was interpolated directly into a Node.js `-e` string: `b.hash('$_admin_pass',12)`. A password containing `'` breaks JavaScript syntax; one containing `$HOME` would be expanded by the shell before reaching Node.js.
- **Root cause 2**: Email was interpolated directly into raw SQL: `VALUES ('$ADMIN_EMAIL', ...)`. An email with `'` causes a SQL syntax error.
- **Root cause 3**: `scripts/biomate` only called `_load_env` in the `status` case. Other commands like `create-admin` used `${POSTGRES_USER:-biomate}` from an unsourced shell, always falling back to `biomate` even if the customer set a different user.
- **Fix**: Replaced the Node.js+SQL approach with the same API-based flow used in `install.sh` (register → auto-verify → `psql UPDATE` with single-quote escaping via `sed "s/'/''/g"`). Moved `_load_env` to run unconditionally at the top-level before the `case` dispatch.
- **Commit**: see below

### Bug 23 — `configure_ai_assistant` LLM_API_KEY=none masks DeepSeek/Zhipu real API keys
- **Root cause**: `.env.onprem.example` sets `LLM_API_KEY=none` (for local vLLM that needs no auth). `configure_ai_assistant` included `os.getenv('LLM_API_KEY')` in the generic API key fallback chain — BEFORE provider-specific env vars like `DEEPSEEK_API_KEY`. A customer who copies the example and switches to DeepSeek (Option B) would still have `LLM_API_KEY=none` set, so `_api_key = "none"`. The DeepSeek LLM client then sends `Authorization: Bearer none` → 401 Unauthorized on every LLM call.
- **Additional issue**: Provider was determined AFTER the key lookup (using `raw_config.get('ai_llm_provider')` which could contain stale YAML values), so the generic chain was further polluted by wrong ordering.
- **Fix**: Restructured `configure_ai_assistant`: (1) determine provider first — env var `GALAXY_AI_LLM_PROVIDER` wins over YAML `ai_llm_provider` (not the reverse); (2) look up API key based on resolved provider; (3) added explicit per-provider key map (DEEPSEEK_API_KEY, ZHIPU_API_KEY, OPENROUTER_API_KEY, etc.); (4) added `${...}` literal guard to reject un-expanded YAML placeholders.
- **Commit**: see below

### Bug 24 — `scripts/create-first-admin.sh` missing `"acceptTerms":true` in register request
- **Root cause**: The `/api/auth/register` endpoint requires `acceptTerms: true` in the request body. The script's curl call omitted this field.
- **Impact**: Registration fails with 400; user not created; `UPDATE users SET subscription_tier='admin'` matches 0 rows; script prints "Done!" but no admin exists in the database.
- **Fix**: Added `"acceptTerms":true` to the JSON body.
- **Commit**: see below

## Known Issues (Not Blocking)

- **Workflow search routing**: Searching for "ADMET prediction small molecule toxicity" returns wrong workflow via search API. Chat routing (via `workflow_ready`) works correctly. DB scoring fix is a separate issue.
- **File upload test**: MinIO staging fix (Bug 9) not yet E2E-verified — needs a workflow that accepts a file input to confirm staging → Nextflow read → success.
- **License on sim instance**: Galaxy container needs restart with `BIOMATE_LICENSE_KEY=BMOP-DEMO-DEMO-DEMO-DEMO` to verify the license fix. This requires updating the `.env` on the instance.

## Deployment Artifacts

| Artifact | Value |
|----------|-------|
| Frontend image (security + MinIO) | `sha-85728dc568b3` |
| Branch | `fix/onprem-llm-compatibility` |
| PR open | #248 → `integration/next-phase` (waiting for merge) |

## Commits in this PR

| SHA | Change |
|-----|--------|
| `64765fb44` | Fresh-install bugs: output files, Docker CLI, compose volumes |
| `be742fab0` | LLM provider: remove Anthropic guard, replace Gemini hardcode |
| `9dd864818` | Auth on status endpoint |
| `97f38f24b` | Failed-run findings: execution.status fix |
| `77e0de074` | Security: auth on cancel/rerun/execute |
| `112ba23c3` | MinIO file staging for on-prem |
| `85728dc56` | Env example: demo license key, remove duplicate NEXTFLOW_WORK_DIR |
| `fda22c82f` | install.sh: create nf-work dir before docker compose up |
| `15c3237d1` | install.sh: fix admin creation (API-based, not require .ts) |
| `d545a57e0` | install.sh: wizard order fix, DOCKER_GID detection, GALAXY_API_KEY generation |
| `d545a57e0` | routes.ts: authenticateToken + ownership on local file download proxy |
| `c2ca6b39f` | Remove credentials from git; install.sh auto-generates galaxy.yml from template |
| TBD | galaxy.yml.template: remove hardcoded LLM config (Bug 16) |
| TBD | install.sh: _setenv helper + GALAXY_API_KEY check (Bugs 17-18) |
| TBD | onprem-update.sh: .env sourcing + docker inspect health check (Bugs 19-20) |
| TBD | scripts/biomate: API-based create-admin + top-level _load_env (Bug 21) |
| TBD | scripts/create-first-admin.sh: add acceptTerms to register request (Bug 24) |
| TBD | ai_config.py configure_ai_assistant: provider-aware API key lookup (Bug 23) |
