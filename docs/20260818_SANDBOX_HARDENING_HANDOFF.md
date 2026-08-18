# Sandbox hardening — session handoff & IT-migration design (2026-08-18)

**One-sentence resume for a new session:**
> Continue the sandbox host-escape hardening on branch `feat/compute-platform-v2`
> per `docs/20260818_SANDBOX_HARDENING_HANDOFF.md` — do Stage 3 (migrate Galaxy
> interactive tools onto the narrow launcher so the backend raw socket can be
> removed), then Stage 4 (4-domain regression + remove socket).

Everything needed to pick up is in this file + the deep-dive
`docs/20260818_SANDBOX_SOCKET_PROXY_HARDENING.md` + memory
`compute-platform-v2.md`.

---

## 1. Where things stand (DONE + verified on test)

Branch `feat/compute-platform-v2`, latest commit `ec8d5c613` (pushed). NOT merged.

Sandbox (feature ①) — three execution surfaces, layered defense:

| Surface | State | Evidence (test) |
|---|---|---|
| **run_code** (frontend) | ✅ host-escape CLOSED — frontend has **zero docker** (no socket, no DOCKER_HOST); dispatched to the narrow launcher over HTTP (`RUN_CODE_BACKEND_URL`) | `uid=1000` + `4.19.0-gvisor` + hash-match; launcher rejects baseDir=/etc, non-allowlist image, scriptPath traversal (400) |
| **local .nf head** (backend) | ✅ migrated to launcher (`NF_HEAD_LAUNCHER_URL`, flag on) — backend runs no docker for the head; launcher validates the argv | `.head_argv.json` shows runsc/net-none argv; head ran `uid=1000`+gvisor+`NET=BLOCKED`; succeeded; rejects `-v /:/host`/`--privileged`/root (400) |
| **interactive tools** (backend) | ⚠️ still on the **raw socket** (works) — the Stage-3 blocker | IT URL registers, JupyterLab opens |

Layers: app container → **narrow launcher** (enforces safe envelope) →
**docker-socket-proxy** (endpoint allowlist) → daemon → **gVisor** (runsc) +
cap-drop/non-root/net-none/read-only.

### Commits this effort
- `e6bc7bb27` narrow launcher (run_code, frontend zero docker)
- `426a5b8d8` docker-socket-proxy hardening
- `c6792a3db` launcher `/run_head` + backend `LauncherClientHeadLauncher` (flag-gated)
- `78a7ff8d8` Stage 2 verified doc
- `ec8d5c613` overlay reflects .nf-via-launcher

### Source of truth (repo)
- `deploy/sandbox-launcher/launcher.py` — the narrow launcher (pure stdlib + docker CLI). Endpoints: `POST /run` (run_code), `POST /run_head` (nf head, validate-argv + stream), `GET /health`.
- `deploy/sandbox-launcher/Dockerfile` — production image form (`docker:27-cli` + `apk add python3`).
- `deploy/docker-compose.sandbox.yml` — canonical overlay (proxy + launcher + frontend/backend wiring + why backend keeps the socket).
- `backend/lib/galaxy/ai/compute/sandbox/head_client.py` — head subprocess client.
- `backend/lib/galaxy/ai/compute/sandbox/launcher.py` — `SandboxedHeadLauncher` + `LauncherClientHeadLauncher`.
- `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` — `_maybe_sandboxed_launch` flag-gated wiring (~L4773).

## 2. Test deployment (how it's actually running)

- Instance: **i-0482a6fa98c6f301a** only (test, `biomate-deploy-test`). t3.medium **4GB RAM + 4GB swap** (added 2026-08-18 after an OOM — do NOT run big image builds here; launcher/proxy pulls are fine).
- SSH egress blocked → **all ops via SSM** `AWS-RunShellScript` (base64 the script to dodge dash/quoting; poll `get-command-invocation`).
- Containers: `biomate-frontend-deploy` (`db7c4b22`, zero docker), `biomate-galaxy-deploy` (`sandbox-test`, raw socket for IT + `.nf` via launcher), `sandbox-launcher`, `docker-socket-proxy`, `biomate-gxit`, `biomate-caddy`. All on `biomate-deploy-net`.
- **Launcher runs no-build** on test: `docker run --name sandbox-launcher … docker:27-cli sh -c "apk add --no-cache python3 && exec python3 /launcher.py"` with `-v /opt/biomate/launcher.py:/launcher.py:ro` + `DOCKER_HOST=tcp://docker-socket-proxy:2375` + `-v /tmp/biomate_code`,`/tmp/nextflow_runs`,`/tmp/biomate_user_nf`. Env: `LAUNCHER_WORKDIR_PREFIX`, `LAUNCHER_HEAD_PREFIXES`, `LAUNCHER_ALLOWED_IMAGES`, `LAUNCHER_RUNTIME=runsc`, `LAUNCHER_UID/GID=1000`.
- **Backend .nf patch is bind-mounted** (not baked): `/opt/biomate/patched/{nextflow_executor.py,head_client.py,launcher.py}` → mounted over the image paths + `NF_HEAD_LAUNCHER_URL` env in the override. (Production TODO: bake the branch code into the backend image instead.)
- **Override backups** (revert points): `/opt/biomate/docker-compose.sandbox.yml.bak.*` (socketproxy, launcher, headlauncher, beproxy, revBE2, …).
- Verify env: `E2E` login uses `lifeifei163361@163.com`? No — this effort used a throwaway account saved in `/tmp/pw-smoke/{email,pass,token}.txt`; `x-e2e-test-token: biomate-e2e-bypass-token-dev-only`; base `https://test.stage-public.biomate.ai`.
- Verify launcher from a peer (frontend/backend have no curl): use host `curl http://<launcher-ip>:8899/...` or `docker exec sandbox-launcher wget`.

## 3. Stage 3 — interactive tools → launcher (THE design)

**Goal:** get IT off the raw socket so the backend becomes zero-docker (like the
frontend). Then Stage 4 removes the socket.

**Why it's hard (root-caused 2026-08-18):** routing the backend through the
docker-socket-proxy breaks IT (job exit 125, empty stderr/ec, no session URL) —
but the IT `docker run` command ITSELF works through the proxy (manual repro
with the full IT flag-set + `-v /app:/app:ro` = REPRO_OK). So the failure is NOT
the run; it's Galaxy's **job wrapper**: `(python container_monitor/monitor.py &);
sleep 1; cd working; docker run … -p 8888 --name <hex> …` then Galaxy inspects the
container for the mapped port to register the InteractiveToolEntryPoint (→ the
session URL). `monitor.py` has NO docker refs (it talks the Galaxy API). A
recurring `sqlite3 OperationalError: no such table: galaxy_user` ASGI error
appears in the same window and may be entangled. IT containers are long-lived +
port-published + inspected — a richer lifecycle than the fire-and-forget head.

**Design options (pick after a short spike):**

- **A. Launcher gains a detached-container API + Galaxy IT runner calls it.**
  Add `POST /run_detached` (validate argv like `/run_head`, run `docker run -d`,
  return container id/name), `GET /inspect/<id>` (return published port /
  NetworkSettings — read-only, safe), `POST /stop/<id>`. Then point Galaxy's IT
  docker operations at the launcher. Cleanest long-term (single choke point) but
  requires changing Galaxy's `DockerContainerInterface` / job_conf docker runner
  to use the launcher instead of the `docker` CLI — Galaxy-internals work.

- **B. `docker` CLI shim in the backend.** Put a wrapper `docker` earlier in PATH
  that translates `run`/`inspect`/`ps`/`rm` → launcher API (A's endpoints), and
  remove the raw socket + DOCKER_HOST. Least Galaxy code change, but the shim must
  faithfully emulate the docker CLI subset Galaxy uses (output formats too) — fiddly.

- **C. First: fix IT-under-proxy directly.** Since the docker run works via proxy,
  the break is in monitor.py/entry-point registration under `DOCKER_HOST≠socket`.
  Spike: run one IT launch with the backend on the proxy and `strace`/verbose the
  monitor + capture the `docker` calls Galaxy makes AFTER the run (inspect/port).
  Also resolve the `galaxy_user` table error (which DB is that ASGI handler hitting
  — the sqlite fallback vs the real Postgres? IT may register via a path that hits
  the wrong DB). If the break is a single missing proxy endpoint or the DB error,
  C is far cheaper than A/B. **Recommend starting with C** (a ~1-2h spike) before
  committing to A.

**Enforcement to preserve (whatever option):** the launcher/shim must validate the
IT argv the same way `/run_head` does — mounts under an IT-specific prefix
allowlist (job dirs under `/app/database/jobs_directory`, `/app/database/files`,
`/app/tools/interactive`, `/app:ro`), forced non-root/no-new-priv, no
`--privileged`/host, and image allowlist (the IT images:
`quay.io/bgruening/docker-jupyter-notebook…`, rstudio, cellxgene). Note IT needs
`-p` (publish) and `--net biomate-deploy-net` — allow those (not host net).

## 4. Stage 4 — after IT is on the launcher

1. Remove the backend raw socket + `DOCKER_HOST` (backend → launcher only).
2. Re-verify all three surfaces (run_code, .nf, IT) end-to-end.
3. **4-domain regression** (ADMET / RNA-seq / WGS / CryoEM) with
   `NF_HEAD_LAUNCHER_URL` on — personal .nf is verified, but bioc/domain runs via
   the launcher are NOT yet exercised. Watch for mount paths outside
   `LAUNCHER_HEAD_PREFIXES` (would 400) and network needs (myvariant/WGS wants
   internet; the sandbox net mode is unchanged by the launcher, so no new regression
   expected, but confirm).
4. Bake into CI: `biomate-sandbox-launcher` image + backend branch code (replace
   the bind-mount patches) + the overlay + the IT-proxy infra (currently test-host
   hand-applied).
5. Optional: custom seccomp profile (`SANDBOX_SECCOMP_PROFILE`).

## 5. Guardrails (from CLAUDE.md, learned this effort)
- Review the diff + trace gating before any expensive deploy; predict the outcome.
- After ANY backend Python change: `docker exec … PYTHONPATH=lib python3 -c "import galaxy.webapps.galaxy.api.nextflow_executor"` **before** trusting it (crash-loop gate).
- Read the FULL error (job tool_stderr, docker logs, proxy logs) — an exit code is not a diagnosis.
- Don't run memory-heavy image builds on the 4GB test box (OOM'd once; swap added).
- Fail-closed sandbox: never silently fall back to unsandboxed on error.
