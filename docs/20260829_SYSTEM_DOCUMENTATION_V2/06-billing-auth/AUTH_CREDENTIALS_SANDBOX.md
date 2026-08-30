# 06b · Auth, Credentials, Sandbox & Interactive Tools

**Verified 2026-08-29.**

---

## 1. Authentication

### JWT / cookies / sessions
- **Frontend mint** — `frontend/server/auth-service.ts:808`: `jwt.sign()` HS256, issuer `biomate.com`, expiry `24h` (default) / `30d` (rememberMe); verify L568; secret `JWT_SECRET`.
- **Cookie** — **`biomate_token`** (`auth-middleware.ts:76,244`), httpOnly, `secure` in prod, `sameSite:'lax'`.
- **Backend Galaxy JWT** — `webapps/.../auth.py:102` `_create_jwt_token` (`{user_id,email,exp,iat}`), verify L423, `jwt_expiry_days=30`, HS256. **Billing decodes the same token.**

### Passwords
- BioMate users: **bcrypt, 12 rounds** (`auth-service.ts:120/401`; `auth.py:120/124`).
- Galaxy-provisioned users: **PBKDF2-SHA256, 100000 iterations** (`billing_router.py:708`, format `PBKDF2$sha256$100000$<salt>$<hash>`).

### OAuth & MFA
- **OAuth login (frontend)** — `oauth-service.ts`: passport Google (L40) + GitHub (L73); `findOrCreateOAuthUser` (L128) links by email, 7-day trial, tier `academic`, `emailVerified: true`. (Backend `oauth2_callback.py` is for **file-source** S3/cloud OAuth, not user login.)
- **MFA** — `mfa-service.ts`: speakeasy TOTP, one-time recovery codes, JTI replay-prevention. `POST /api/auth/mfa/challenge` issues the full session token after TOTP.

### E2E bypass
`auth-middleware.ts:114` — header `X-E2E-Test-Token` = `E2E_TEST_TOKEN || 'biomate-e2e-bypass-token-dev-only'`, guarded `NODE_ENV !== 'production'`. **Grants only a subscription-check waiver — it does NOT bypass identity auth** (JWT/API-key still required).

## 2. User provisioning (BioMate → Galaxy account + per-user API key)

1. Registration (`auth-service.ts:69`): bcrypt-hash → insert `users` row → **synchronously** call `provisionGalaxyUser(id, email)` (L199) → reload user to capture `galaxyUserId`/`galaxyApiKey`/`galaxyUsername`; async exponential-backoff retry on failure.
2. `POST /internal/users/provision` (`billing_router.py:684`): derive username `bm_<16hex>`, PBKDF2 password (never used for login), write directly to Galaxy SQLite `galaxy_user` via raw SQLAlchemy (bypassing the broken admin API), then generate/reuse an API key `secrets.token_hex(16)` into `api_keys`. Returns `{galaxy_user_id, galaxy_api_key, galaxy_username}`.
3. Frontend stores the Galaxy API key **encrypted** into `users`; on login, stale-key detection re-provisions.

## 3. Credential stores

| Store | Tech | Where |
|-------|------|-------|
| **BYOK LLM keys** | `users.llm_api_keys` JSONB `{anthropic?, openrouter?, selected_model?}`, **AES-256-GCM** (`field-encrypt.ts:43`, `FIELD_ENCRYPTION_SECRET`, `iv:tag:ciphertext`) | endpoints `routes.ts:6867` (GET returns existence flags only; POST encrypts); per-request decrypt + inject into `GalaxyAssistant`, ephemeral, falls back to system keys |
| **Connector / headless keys** | `bm_live_<24B>` stored as **SHA-256 hash only** | `api-key-service.ts`, `api_keys` table |
| **Galaxy-native tool credentials** | Galaxy Vault `biomate/credentials/<tool_id>` with `user.preferences` fallback | `credentials_api.py` — `get_effective_credential` resolves user → master env-var (e.g. `SIMCYP_LICENSE_KEY`, `ALPHAFOLD3_DOCKER_TOKEN`) via `LICENSE_REGISTRY`, source `user`/`biomate`/`none`; endpoints `GET/POST/DELETE /api/users/credentials`, `GET /api/nextflow/license-requirements` |

## 4. Sandbox mode (default OFF, gVisor isolation)

**Purpose:** isolate user-supplied code (the Nextflow head's Groovy eval + `run_code` Python/R) from the host in a locked-down gVisor container with zero host access. Doc: `docs/20260819_SANDBOX_MODE_COMPLETE.md`. **Every env var defaults disabled — importing the module changes nothing until an operator opts in.**

**Isolation chain:** app containers (no raw docker socket) → **narrow launcher** (the only app-side docker holder) → `docker-socket-proxy` (endpoint allowlist) → daemon → gVisor `runsc`. Three tiers (`config.py:29`): T1 rootless + cap-drop-ALL + no-new-privs + RO-rootfs + non-root UID; T2 + network none; T3 + gVisor.

**Components** (`backend/lib/galaxy/ai/compute/sandbox/`):
- `config.py` (187) — `SandboxConfig`, per-run UID = hash(run_id) → 20000–29999.
- `command.py` (150) — `build_sandbox_command()` wraps argv in `docker run <iso flags>`; `filter_container_env` drops `AWS_*`/`_KEY`/`_SECRET`/`_TOKEN`/`PASSWORD`/`OPENAI`/`HF_TOKEN`, keeps a `LANG`/`NXF_*` allowlist (prevents secret leakage into container argv).
- `validator.py` (116) — static `.nf` pre-check, **15 block/warn rules** (`--privileged`, host-root mount, docker.sock, nsenter/unshare, `169.254.169.254`, `/etc/shadow`, `~/.aws`, ssh keys, `curl|bash`, `Runtime.exec`, `ProcessBuilder`, `sudo`, …).
- `launcher.py` (100), `head_client.py` (67), and the microservice `deploy/sandbox-launcher/launcher.py` (424, port 8899, endpoints `/run` [run_code], `/run_head` [nextflow], `/run_it` [interactive, Option A]) — `validate_head_argv` forces the safe envelope, image allowlist, runtime `runsc`.

**Socket-proxy hardening (2026-08-18):** `tecnativa/docker-socket-proxy:0.3.0` is the sole raw-socket holder; app containers reach the daemon via `DOCKER_HOST=tcp://docker-socket-proxy:2375`. The residual "create + bind-mount `/`" threat is closed by the narrow launcher.

**Coverage:** `run_code` ✅, personal `.nf` uploads ✅ (`nextflow_executor.py:4960 _maybe_sandboxed_launch`), Interactive Tools ⚠️ (launcher endpoint exists but not yet wired into Galaxy's IT runner — backend still holds a raw socket for IT), AWS Batch not sandboxed (ECS task isolation). Key env gates: `SANDBOX_ENABLED` (default false), `SANDBOX_TIER` (1), `SANDBOX_VALIDATE_UPLOADS`, `SANDBOX_REJECT_ON_VIOLATION` (→ 422), `NF_HEAD_LAUNCHER_URL`, `RUN_CODE_BACKEND_URL`, `LAUNCHER_RUNTIME=runsc`, `LAUNCHER_ALLOWED_IMAGES`.

## 5. Interactive tools (Jupyter / RStudio / CellxGene / …)

**7 tools enabled** (`backend/config/interactivetools_conf.xml`): Jupyter (8888, `ipython/lab`), RStudio (8787, `X-RStudio-Root-Path`), CellxGene (80), VCF-iobio, BAM-iobio, HiGlass, iSEE, Pavian.

> ⚠️ **Correction:** there is **no `BIOMATE_ENABLE_IT` env gate** in current code (zero grep hits — the memory note is stale). Enablement is at the Galaxy tool-XML registration level (`interactivetools_conf.xml`) + job routing (`job_conf.yml:83`, regex `interactive_tool_.*` → `docker_interactive_root`, `DISABLE_AUTH=true` for RStudio).

**`/interactive/<token>` proxy** — implemented in the **frontend Node server** (`routes.ts:16499`, `app.use("/interactive", …)`):
- Token→container (15s cache): Galaxy DB `interactivetool_entry_point.token → job_id → job_container_association → container_name → docker inspect` first published TCP port (port-agnostic). Target = `IT_HOST_GATEWAY:port` (default `172.19.0.1`).
- HTTP rewrite injects `x-rstudio-root-path`, rewrites `/ipython/` → `/interactive/<token>/ipython/` so per-session assets/WS stay scoped.
- WebSocket upgrade proxy with **TEXT/BINARY frame-type preservation** (required by the Jupyter kernel protocol).

**Backend APIs:** `job_ports.py` (`POST /api/jobs/{job_id}/ports` — container registers host/port), `managers/interactivetool.py` (entry-point create/config/auth, `InteractiveToolEntryPoint` ORM with `token = token_hex(8)`, `active = configured & !deleted & job.running`). **Auto-select by format** — `ai/interactive_tool_mapping.py`: h5ad→cellxgene (0.95) + scanpy_qc, kreport→pavian, cool/hic→higlass, rds→isee, csv→openrefine/deseq2. Frontend `POST /api/interactive/launch` auto-maps the first dataset. **Multisession:** per-token isolation, concurrent sessions multiplexed by token, no cross-talk.
