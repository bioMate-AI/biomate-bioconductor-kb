# China (Alibaba Cloud) Deployment Skill

**One-click stable deploy harness for mainland China ECS.**
GHA workflow: `.github/workflows/sync-to-acr.yml` on branch `feat/aliyun-demo-deploy`.

---

## Quick start

```bash
# Normal deploy (DB + nfcore already in volumes from last time):
# trigger sync-to-acr.yml with defaults (skip_assets=true, all others false)

# First-time or after volume wipe:
# trigger with skip_assets=false

# Enable real ADMET-AI (one-time):
# 1. Add ACR_USERNAME + ACR_PASSWORD to repo secrets (Settings → Secrets → Actions)
# 2. Trigger with mirror_admet_to_acr=true
# All subsequent deploys will auto-pull from ACR
```

---

## Architecture (China ECS)

| Component | Value |
|---|---|
| ECS IP | `101.201.107.126` (cn-beijing) |
| Demo URL | `http://101.201.107.126` |
| Demo account | `demo@biomate-demo.com / BioMate2026!` |
| LLM | Qwen-max via DashScope (`DASHSCOPE_API_KEY` in ECS `.env`) |
| ADMET image | `registry.cn-beijing.aliyuncs.com/biomate/biomni-admet:x86` (ACR) |
| ADMET fallback | `biomate/biomni-tools:latest` (RDKit only, pre-loaded on ECS) |

---

## Pitfall catalogue

Every item below caused a hard failure during the initial China deploy. Each is now mitigated in `sync-to-acr.yml`.

---

### P1 — DaoCloud registry mirror intercepts ALL docker pull

**Symptom:** Nextflow workflow fails with `Unable to find image 'X' locally` even though `docker images` shows the image. Exit code 1.

**Root cause:** ECS `daemon.json` has a DaoCloud mirror configured as a registry mirror. Docker intercepts EVERY pull request — including images already loaded locally — and routes it through the mirror. The mirror cannot find a private image → connection error.

**Fix:** Inject `--pull never` into Nextflow's Docker `runOptions` in `nextflow_executor.py`:
```python
# before fix
"--user root --network host ..."
# after fix  
"--user root --pull never --network host ..."
```
`--pull never` tells the Nextflow Docker executor: use the local cache only, never attempt a remote pull. Verified working.

**Mitigation in workflow:** "Patch nextflow_executor.py" step (one-time sed, idempotent).

**Why `kill -HUP` won't work here:** Galaxy gunicorn runs with `--preload`. HUP recycles workers but they inherit the master's preloaded code — the sed-patched file on disk is NOT re-read. Must use `docker restart`.

---

### P2 — AWS ECR inaccessible from mainland China

**Symptom:** `docker pull 399683337364.dkr.ecr.us-west-2.amazonaws.com/...` times out or gets connection refused. ECS has no route to AWS us-west-2.

**Root cause:** AWS ECR is a US-region service. Mainland China has no direct connectivity to it (GFW + no AWS China ECR for this account).

**Fix:** Use Alibaba Cloud ACR as a relay:
1. GHA runner (US network) pulls from ECR and pushes to `registry.cn-beijing.aliyuncs.com/biomate/biomni-admet:x86`
2. ECS (cn-beijing) pulls from ACR — same-region traffic, free and fast

**Trigger (one-time):** `sync-to-acr.yml` with `mirror_admet_to_acr=true`. Requires `ACR_USERNAME` + `ACR_PASSWORD` GHA secrets.

**Ongoing:** Every deploy, the "Set BIOMATE_ADMET_CONTAINER" step checks if the image is cached or tries to pull from ACR. Falls back to `biomni-tools:latest` if ACR is unavailable.

**`BIOMATE_ADMET_CONTAINER` env var:** `main.nf` now uses an Elvis operator:
```groovy
container System.getenv('BIOMATE_ADMET_CONTAINER') ?: (... ECR or Docker Hub ...)
```
Set in ECS `.env` by the workflow. No sed patching of `.nf` files needed.

---

### P3 — galaxy_ai_tools.db bandwidth bottleneck (303 MB, US→China ~50 KB/s)

**Symptom:** DB file arrives at 98 MB (corrupted), Galaxy AI assistant returns errors, workflow search fails.

**Root cause:** GHA → ECS SSH pipe routes through US→China public internet at ~50 KB/s. A 303 MB file takes ~100 minutes — far beyond the 30-minute GHA job timeout. Partial write = corrupted SQLite file.

**Fix:** Have ECS download from S3 DIRECTLY using `curl` over SSH:
```bash
ssh root@ECS "curl -fL 'https://biomate-onprem-assets.s3.amazonaws.com/onprem/galaxy_ai_tools.db' \
  -o $VOLPATH/galaxy_ai_tools.db.new && mv ... galaxy_ai_tools.db"
```
Only control commands flow over SSH (tiny). S3 → ECS uses Alibaba Cloud's S3 gateway (faster than US→China public internet). Atomically renamed to avoid partial reads.

**Threshold check:** Step downloads only if current size < 250 MB (262 MB threshold) to skip if already complete.

---

### P4 — Broad `sed` pattern destroying Python string literals

**Symptom:** ADMET workflow fails with `SyntaxError: perhaps you forgot a comma?` at line ~369 of the rendered Python script inside Nextflow.

**Root cause:** The original sed pattern `.*biomni-admet.*` matched too broadly. Line 501 of `main.nf` is a Python string:
```python
"Container: ensure biomni-admet:x86 is used for Chemprop-backed predictions.\\n"
```
The pattern matched it and replaced it with Groovy `container 'biomate/biomni-tools:latest'`. Python saw this as an unquoted identifier in a tuple context → `SyntaxError`.

**Fix:** Narrow the pattern to only match Groovy process `container` declarations:
```bash
# Wrong (matches Python strings too):
s|.*biomni-admet.*|    container 'biomate/biomni-tools:latest'|g

# Correct (matches only Groovy `container` declarations, 4-space indent):
s|^    container .*biomni-admet.*|    container 'biomate/biomni-tools:latest'|g
```
Old pattern matched 4 lines (34, 96, 99, 501). New pattern matches only 2 (34, 99 — the actual Groovy declarations). Line 96 is a comment; line 501 is Python.

**Current status:** Not needed anymore — BIOMATE_ADMET_CONTAINER env var handles it (P2 fix). Documented here because this class of bug (too-broad sed) recurs.

---

### P5 — Wrong polling endpoint: `/api/runs/:id/meta` vs `/api/workflows/runs/:id/status`

**Symptom:** After workflow completes, status stays `running` for all 8+ minutes of polling. Test times out.

**Root cause:** `/api/runs/:id/meta` reads the stale DB value — it does NOT reconcile with Galaxy's live Nextflow state. The DB is only updated when the `/status` endpoint is called.

**Fix:** Poll `/api/workflows/runs/:id/status` instead. This endpoint calls `galaxyAPIProxy.getNextflowStatus()`, reconciles with Galaxy, and updates the DB atomically on terminal state. First poll (10 s after launch) returned `status=completed`.

---

### P6 — Google CDN links block page load in China

**Symptom:** Browser shows blank white page. Network tab shows `fonts.googleapis.com` and `googletagmanager.com` requests hanging/failing.

**Root cause:** Google services are blocked in mainland China. The built `index.html` includes `<link href="https://fonts.googleapis.com/...">` and GTM script tags. Browsers block page render while waiting for these resources.

**Fix:** Sed-patch the built `index.html` in-place (Express reads from disk, no restart needed):
```bash
sed -i "/fonts.googleapis.com/d; /fonts.gstatic.com/d; /googletagmanager.com/d" \
  /app/dist/public/index.html
```
**Mitigation:** "Patch index.html" step in `restart-stack`. Also committed as `fix(aliyun): strip Google CDN links from index.html` on this branch.

---

### P7 — CORS_ORIGINS blocks IP-based access

**Symptom:** Browser console shows `CORS error` or API calls return 403 when accessing via `http://101.201.107.126`.

**Root cause:** `CORS_ORIGINS` defaults to `https://biomate.ai` (production domain only). IP-based access is rejected.

**Fix:** Add to ECS `.env`:
```
CORS_ORIGINS=http://101.201.107.126:5000
```
Or for multiple origins: comma-separated.

---

### P8 — Involucro stale lock causes infinite restart loop

**Symptom:** Galaxy container restarts every ~60 s, ExitCode=0, logs show `Acquiring lock on involucro`.

**Root cause:** Galaxy acquires `/app/database/dependencies/involucro.lock` at startup. If a previous run crashed mid-lock, the file persists in the Docker volume (survives container restart). Every new startup tries to acquire → waits 300 s → exits cleanly → Docker restarts → repeat.

**Fix:** Remove the stale lock before starting:
```bash
rm -f $VOLPATH/dependencies/involucro.lock
```
**Mitigation:** "Remove stale involucro.lock" step in `restart-stack`.

---

### P9 — gunicorn `--preload` + `kill -HUP` limitation

**Symptom:** After editing Python code and sending HUP to gunicorn master, changes don't take effect. Workers continue using old code.

**Root cause:** With `--preload`, gunicorn loads the application module once in the master process, then forks workers that inherit the master's memory. HUP reloads configuration and recycles workers, but the new workers still inherit the MASTER's already-loaded (pre-patch) code. The edited file on disk is irrelevant.

**Fix:** `docker restart biomate-galaxy` — forces gunicorn to re-preload from disk on fresh start.

**Never do:** `kill -HUP $(pgrep gunicorn)` after patching Python files when gunicorn uses `--preload`.

---

## GHA secrets required

| Secret | Description | Example |
|---|---|---|
| `ECS_ROOT_PASS` | SSH root password for `101.201.107.126` | Already set |
| `ACR_USERNAME` | ACR Personal Access Token name or RAM user | `cruser@1234567890` |
| `ACR_PASSWORD` | ACR Personal Access Token password | (set in ACR console) |

### How to get ACR credentials

1. Log in to [Alibaba Cloud Console → Container Registry (ACR)](https://cr.console.aliyun.com)
2. Create a personal access token (推荐) or use a RAM sub-user
3. Create namespace `biomate` in the `cn-beijing` registry if not exists
4. Set `ACR_USERNAME` and `ACR_PASSWORD` in GitHub → Settings → Secrets → Actions

---

## E2E test coverage

Every deploy runs 3 workflow tests automatically (login once, fire sequentially):

| Case | Workflow | Container | Input |
|---|---|---|---|
| ADMET | `predict_admet_properties` | biomni-tools | aspirin SMILES |
| PBPK | `pbpk_disease_state` | biomni-tools | renal/hepatic impairment params |
| hERG | `herg_cardiac_safety_qsar` | biomni-tools | aspirin SMILES, 500mg oral |

All 3 use `biomni-tools:latest` (pre-loaded on ECS) — no ECR access required.

**Coverage map — what the harness intentionally skips:**
- RNA-seq / WGS / CryoEM: ECR-only images not yet mirrored to ACR (see Phase 2 below)
- Cross-user isolation: enforced by Postgres row-level checks, not needed in e2e
- Registration flow: tested in server-side unit tests, not here (registration is rate-limited)

### Phase 2: broader case support (when needed)

To add RNA-seq (DESeq2), WGS (myvariant), CryoEM:
1. Mirror domain images ECR → ACR (one-time, ~2 GB each):
   - `bioc-domain-transcriptomics:3.20-slim`
   - `bioc-domain-variant_calling:3.20-slim`
   - `cryosparc-nf:latest`
2. Add a `mirror_domain_images` GHA input (same pattern as `mirror_admet_to_acr`)
3. In deploy step: global sed on nfcore volume — replace ECR prefix with ACR prefix
4. Pre-pull images on ECS (with `--pull never` active, images must be local)
5. Add corresponding e2e cases

---

## Workflow inputs reference

| Input | Default | Description |
|---|---|---|
| `skip_assets` | `true` | Skip DB + nfcore volume transfer (already populated) |
| `check_only` | `false` | Only run `check-status`, skip deploy |
| `pull_biomni_tools` | `false` | Pull biomni-tools from GHCR to ECS (~800 MB, once) |
| `mirror_admet_to_acr` | `false` | Mirror biomni-admet:x86 ECR→ACR (~4 GB, once) |

---

## Standard deploy checklist

```
□ Code pushed to feat/aliyun-demo-deploy
□ sync-to-acr.yml triggered (push or dispatch)
□ transfer-assets: skipped (assets already in volumes) or completed
□ mirror-admet-image: skipped (already mirrored) or completed
□ restart-stack: completed — check BIOMATE_ADMET_CONTAINER value in logs
□ check-status: ADMET e2e test COMPLETED
□ Browser: http://101.201.107.126 loads without blank page
□ Demo login: demo@biomate-demo.com / BioMate2026!
```

---

## First-time deploy checklist (new ECS instance)

```
□ 1. SSH to ECS; run: mkdir -p /app/biomate && cd /app && git clone <repo>
□ 2. Copy .env to /app/biomate/.env (set DASHSCOPE_API_KEY, POSTGRES_PASSWORD, etc.)
□ 3. Trigger sync-to-acr.yml with skip_assets=false, pull_biomni_tools=true
□ 4. (optional) Trigger with mirror_admet_to_acr=true for real ADMET-AI
□ 5. Verify at http://<ECS_IP> — ADMET demo should work
```
