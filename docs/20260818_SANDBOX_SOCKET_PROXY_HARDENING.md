# Sandbox docker-socket hardening (2026-08-18)

Feature ① (execution isolation) hardening: remove the raw `/var/run/docker.sock`
mount from the app containers so an RCE in the app process can no longer make
arbitrary Docker API calls (which is root-equivalent on the host).

## What shipped

A `tecnativa/docker-socket-proxy:0.3.0` sidecar (`deploy/docker-compose.sandbox.yml`)
now sits in front of the Docker daemon. It is the ONLY container holding the
socket (read-only). App containers reach the daemon over the internal network
via `DOCKER_HOST=tcp://docker-socket-proxy:2375`.

Allowlist (minimal set `docker run` needs): `CONTAINERS, IMAGES, NETWORKS, EXEC,
POST, INFO, VERSION, PING`. Everything else is denied: `BUILD, COMMIT, CONFIGS,
SECRETS, SWARM, SERVICES, TASKS, NODES, PLUGINS, VOLUMES, SYSTEM, DISTRIBUTION,
AUTH, SESSION`.

## Verified on test (i-0482)

| Surface | Path | Result |
|---|---|---|
| run_code (frontend) | frontend → proxy | ✅ still sandboxed: `uid=1000`, `/proc/version = 4.19.0-gvisor`, network blocked, hash-verified real exec — through the proxy, no raw socket on the frontend |
| dangerous endpoints | frontend → proxy | ✅ `docker volume ls`, `swarm init`, `build` all return **403**; `docker images` (read) works |
| local .nf sandbox | backend → proxy | ✅ ran + `succeeded` through the proxy (uid 1000 + gVisor) |
| interactive tools | backend → proxy | ❌ **breaks** — see below |

## Interactive-tools incompatibility (why the backend stays on the raw socket)

Routing the **backend** through the proxy breaks Galaxy interactive tools:
launch returns `queued`, the IT job exits **125**, and no session URL is ever
registered. On the raw socket the same launch works in ~6 s.

Diagnosis (isolated by reverting only the backend to the raw socket → IT works
again, so the proxy is implicated):

- It is **not** a simple allowlist gap. Every manual `docker run` reproduction
  through the proxy — including the full IT flag-set (`-p 8888`,
  `--net biomate-deploy-net`, `--security-opt no-new-privileges`,
  `--user 1000:1000`, `--pids-limit`, `--memory`, `--cpus`, `-v /app:/app:ro`)
  — **succeeds**.
- `galaxy_ext/container_monitor/monitor.py` does not talk to Docker directly.
- The failure is in Galaxy's IT container port-discovery / entry-point
  registration path, which reaches the daemon in a way the allowlist proxy
  doesn't satisfy (a Galaxy-IT-specific access pattern). A `sqlite3
  OperationalError: no such table: galaxy_user` also appears in that window and
  may be entangled.

Decision: **frontend → proxy (run_code hardened), backend → raw socket** so IT
and the .nf sandbox both keep working. run_code is the most direct
arbitrary-code-execution surface, so hardening it is the biggest single win.
Full backend hardening is a follow-up (make Galaxy's IT docker interface
`DOCKER_HOST`-aware, or move IT off the local-docker runner).

## Residual threat (applies even where the proxy is in front)

`tecnativa/docker-socket-proxy` is **endpoint-level**, not body-level. It blocks
whole API paths but cannot inspect a `POST /containers/create` body — so an
RCE'd app that retains create+start could still create a container with a
malicious host bind mount (`-v /:/host`) or a privileged flag and escape.

In BioMate's current design the docker command is always constructed
server-side with fixed safe flags (the chat user supplies *code*, never docker
flags), so this only matters under an app-process RCE. Still, endpoint-level
filtering does not fully close host-escape.

## True closure — narrow launcher (IMPLEMENTED for run_code, 2026-08-18)

The create+bind residual is now closed for run_code by a small trusted
**launcher microservice** (`deploy/sandbox-launcher/`, image
`biomate-sandbox-launcher:1`):

- it is the only app-side holder of docker access (talks to the daemon via the
  socket-proxy — launcher → proxy → daemon, two layers);
- it implements the existing code-runner sidecar contract (`POST /run`) but
  ENFORCES the safe envelope — the workdir bind must resolve under
  `/tmp/biomate_code`, the image must be allowlisted, and
  runtime(gVisor)/user(non-root)/network(none)/caps/no-new-privileges are forced
  by the launcher, never taken from the caller;
- the **frontend now has NO docker access at all** (no socket, no `DOCKER_HOST`);
  run_code is dispatched to the launcher via `RUN_CODE_BACKEND_URL`.

Verified on test (i-0482):

| Check | Result |
|---|---|
| run_code via public API | ✅ `uid=1000`, `4.19.0-gvisor`, **hash-match** — real sandboxed exec through frontend → launcher → proxy → daemon |
| frontend docker access | ✅ none (`DOCKER_HOST` unset, no socket mount) |
| malicious `baseDir=/etc` | ✅ rejected 400 `baseDir not under /tmp/biomate_code` |
| non-allowlist image | ✅ rejected 400 |
| `scriptPath` traversal | ✅ rejected 400 |

So even a fully RCE'd frontend can only ask the launcher to run a validated
RunSpec — it cannot bind-mount host paths or pick a privileged runtime/image.

### Remaining

- **Backend / .nf head** still launches sandboxes directly (raw socket). Migrate
  it onto the launcher next (extend the allowlist prefix to
  `/tmp/biomate_user_nf` + `/tmp/nextflow_runs` and add an `nf_head` RunSpec kind).
- **Interactive tools** can then also be moved onto the launcher as the single
  docker choke point, which resolves the backend/IT proxy incompatibility above.
- Bake `biomate-sandbox-launcher` into CI (currently the test host runs it from
  `docker:27-cli` + `apk add python3` + bind-mounted `launcher.py`; the repo
  Dockerfile is the production form).

## Rollback

Backups on test: `/opt/biomate/docker-compose.sandbox.yml.bak.socketproxy.*`,
`.bak.socketproxyC.*`, `.bak.revBE.*`. To fully revert: restore a pre-proxy
backup, `docker rm -f docker-socket-proxy`, and
`docker compose -f docker-compose.deploy.yml -f docker-compose.sandbox.yml up -d
--force-recreate frontend-deploy galaxy-backend-deploy`.
