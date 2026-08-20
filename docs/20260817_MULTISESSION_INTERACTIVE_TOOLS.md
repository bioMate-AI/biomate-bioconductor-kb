# Multi-Session Interactive Tools — Per-Token Routing (dev)

**Date:** 2026-08-17 (WS execution verified 2026-08-19)
**Status:** ✅ DONE — implemented, deployed, and verified end-to-end on dev **including live code execution**
**Scope:** Concurrent Galaxy Interactive Tool (Jupyter) sessions each route to their own container
**Continues:** `docs/20260811_INTERACTIVE_TOOLS_DEV_ENABLEMENT.md` (single-session enablement, 2026-08-11→13)

---

## 0. Test → audit → test: three bugs the HTTP-200 checks missed (2026-08-19)

A deeper E2E pass (start a kernel, run `print(6*7)` over the kernel WebSocket, assert `42` comes
back) proved the notebook could **load but never execute code** — three stacked defects, each
invisible to a "does /ipython/lab return 200" check. All three are fixed and verified (both
concurrent sessions now execute over WS; distinct kernels).

1. **Kernel POST hung** — `frontend/server/index.ts`. The global `express.json()` body parser
   drained the POST stream for every path except MCP + the Stripe webhook, so the `/interactive`
   raw-stream proxy piped an empty body and Jupyter hung starting a kernel (`POST /api/kernels` →
   000/timeout; every GET worked). This is the *exact* failure already documented in that file for
   `/mcp`. Fix: add `/interactive/` to `_needsRawBody`.
2. **nginx dropped the WS upgrade** — `scripts/sync_to_dev.sh :: enable_interactive_tools`. The host
   nginx `location /` had `proxy_http_version 1.1` but **no `Upgrade`/`Connection` headers and no
   `$connection_upgrade` map**, so WS handshakes arrived at Node as plain GETs and Jupyter 400'd
   them. WS was never functional through nginx. Fix: idempotently add the `map` (conf.d) + the two
   `proxy_set_header` lines to the **active** config (`sites-enabled/biomate-dev.conf` — a real file
   here, *not* a symlink to `sites-available`, which was the first wrong target) and reload nginx
   under an `nginx -t` guard.
3. **WS frames forwarded as binary** — `frontend/server/routes.ts` upgrade handler. The proxy did
   `.send(data)`, which `ws` emits as a **binary** frame; Jupyter's default kernel protocol sends
   JSON as **text** frames, so the kernel silently dropped the proxied `execute_request` (WS
   connected, code never ran → reply timeout). Fix: forward with `{ binary: isBinary }` in both
   directions and in the pre-open flush buffer.

**Lesson:** an HTTP-200 on the app shell says nothing about the WS/kernel path. The meaningful IT
test is *execute code over the kernel WebSocket*, not *load the page*.

---

## 1. Goal

The IT enablement work (2026-08-11→13) got a single Jupyter session serving end-to-end through the
public URL, but with a shared `/ipython` path — only **one** active session at a time. This session
implements the future-enhancement that was deferred there: **per-session (per-token) routing**, so
multiple concurrent Jupyter sessions each resolve to their own container, base path, assets, API, and
kernel WebSocket.

The user's ask, verbatim: *"concurrent sessions would need per-session routing (Galaxy's token/base_url
scheme) — a future enhancement, not required for the dev — **do this**"*.

---

## 2. Result (verified on dev)

Two **simultaneous** launches as the E2E fixture user (`lifeifei163361@163.com`) against
`https://dev-public.biomate.ai`:

| Session | Token | Job (internal) | Container | Host port | `/ipython/lab` | `/ipython/api/status` | baseUrl |
|---|---|---|---|---|---|---|---|
| A | `mujbhx12hqqg` | 2 | `1da8cc8c…` | 32783 | 200 | 200 | `/interactive/mujbhx12hqqg/ipython/` |
| B | `2mw0j3sh2rhr3` | 1 | `bf790972…` | 32782 | 200 | 200 | `/interactive/2mw0j3sh2rhr3/ipython/` |

Two launches → **distinct tokens → distinct jobs → distinct containers → distinct ports**, each serving
its own JupyterLab under its own base path. Re-verified with a second pair of fresh launches after a full
`enable_interactive_tools` + reap cycle (`32laijd6s3ay1` / `2lfonroi2ct04` → 200 each).

---

## 3. Design

Everything lives in `frontend/server/routes.ts` (the Node/Express ingress) — no Galaxy code changes.

### 3.1 Per-token reverse proxy (`targetForToken`)

`app.use("/interactive")` matches `/interactive/<token>/<sub>` and resolves the token to a live
container via a **direct DB→container linkage** that bypasses Galaxy's gx-it-proxy entirely (whose
container-monitor writes an unusable address under docker-out-of-docker):

```
token
  → interactivetool_entry_point.job_id           (sqlite, via `docker exec biomate-galaxy-dev`)
  → job_container_association.container_name       (sqlite)
  → docker inspect <container> .NetworkSettings.Ports["8888/tcp"][0].HostPort
  → proxy HTTP + WebSocket to  172.19.0.1:<hostPort>   (host gateway from the frontend container)
```

- 15-second port cache per token.
- For HTML responses it rewrites `/ipython/` → `/interactive/<token>/ipython/` so **every** asset, API,
  and kernel-WS request the page emits stays under the per-session path (JupyterLab's `base_url` is
  `/ipython`, referenced absolutely).
- The WebSocket `upgrade` handler mirrors the same per-token resolution and pipes frames both ways.

### 3.2 Correct token at launch (`tokenForJob`) — the hard part

The obvious approach — read the token from Galaxy's `/api/entry_points?job_id=<encoded>` `target` — is
**dead under docker-out-of-docker (DooD)**, and the naive stop-gap is **racy**. Both were tried and
rejected:

1. **`target` is null forever in DooD.** `target_if_active` only returns a URL when
   `entry_point.active == True`, and `active` is a *computed property*:
   `configured AND not deleted AND job.running`. In DooD the container-monitor can't resolve the child
   container's address, so it **never sets `configured`** — verified in the DB: post-launch the row has
   `token` set but `configured=0, host=None, port=None`, while the container is up and `job.state='running'`.
   So `active`/`target` stay null indefinitely even though the session is fully usable.
2. **"Newest entry point" is racy.** Returning the most-recent entry-point token means two
   near-simultaneous launches both resolve to the *same* stale token (observed live: both returned
   `2oeibuxpni6zg`).

**Fix:** correlate the token to *this* launched job. `POST /api/tools` returns the **encoded** job id;
decode it (Galaxy's default `id_secret = "USING THE DEFAULT IS NOT SECURE!"`, the same value
`workflow_restarter.py` uses) **inside the galaxy container**, then read the token straight from the
entry-point row keyed by that internal `job_id`:

```python
# executed via: docker exec -e PYTHONPATH=/app/lib biomate-galaxy-dev python3 -c "…"
from galaxy.security.idencoding import IdEncodingHelper
h   = IdEncodingHelper(id_secret="USING THE DEFAULT IS NOT SECURE!")
jid = h.decode_id(encoded_job_id)                      # encoded → internal int
row = sqlite("select token, entry_url from interactivetool_entry_point where job_id=? …", jid)
```

Job-correlated ⇒ **race-free** under concurrent launches, and it needs neither the `active`/`configured`
flag nor any id_secret reconstruction in Node. The launch endpoint returns
`entry_point_url = /interactive/<token>/<entry_url>` (e.g. `…/ipython/lab`), polling briefly because the
entry-point row is written a moment after job creation.

### 3.3 Orphan reaper

`scripts/sync_to_dev.sh :: enable_interactive_tools` now reaps stale
`quay.io/bgruening/docker-jupyter-notebook` containers whose token no longer exists in the current
`universe.sqlite` (a `universe.sqlite` reset on a prior sync wipes entry points but leaves the child
containers running). Delivered base64-encoded (the enclosing ssh block is single-quoted, so apostrophes
in the Python would break it) and dot-sourced so it inherits `$GC`. First run **reaped 12 orphans, kept
2 live**.

---

## 4. DooD facts worth remembering (verified in the dev DB)

- `interactivetool_entry_point` has **no `active` column** — `active` is a Python `@property`
  (`configured AND not deleted AND job.running`). Columns are: `id, job_id, name, token, tool_port, host,
  port, protocol, entry_url, requires_domain, …, configured, deleted, created_time, modified_time, label`.
- Post-launch a row has `token` set but `configured=0, host=None, port=None`; the container-monitor never
  confirms in DooD, so those never populate. `job.state='running'`; `job_container_association` has the
  real `container_name`. **The token + container are usable immediately; the `active` flag never flips.**
- `id_secret` is not set in env or `galaxy.yml` on dev → Galaxy uses its default, so the decode is
  deterministic and stable across restarts.
- The child `docker run` uses `-p 8888` (random host port) under **bridge** networking; Jupyter listens
  on its image default **8888** (an earlier `--net host` era wrongly used 8889 — already reverted).
- Galaxy logs `ERROR … Did not find port to assign to InteractiveToolEntryPoint by tool port: 8888` — this
  is Galaxy's *own* port-assignment failing (the DooD address problem); it does **not** affect our proxy,
  which reads the port from `docker inspect`.

---

## 5. Operational notes / gotchas

- **Server restart ends existing sessions.** Every sync replaces `universe.sqlite` and restarts galaxy;
  Galaxy then garbage-collects entry points for jobs the restarted process no longer tracks. So
  **pre-existing** sessions lose their DB linkage (the containers linger, orphaned, until reaped) — but
  **fresh** launches after a restart work fine. This is expected interactive-tool behaviour.
- **Startup window.** The launch endpoint returns as soon as the entry-point row exists (~1–2 s), but the
  container needs a further ~10–30 s to actually serve. So the returned URL returns **503 briefly, then
  200** once the container + JCA row + Jupyter are all ready. The client should poll the URL (spinner)
  rather than open it once. (This produced a brief false-alarm "it's 503!" during verification — the
  containers were still booting; they served 200 a couple of minutes later.)
- **Security (DEV-ONLY).** The whole IT chain depends on the galaxy container having the host docker
  socket ≈ root on the host. Fine for dev; production needs a real IT job destination (k8s/ECS), not DooD.

---

## 6. Verification method (reproducible)

1. Login the fixture user → JWT; `POST /api/interactive/launch {tool_id:'interactive_tool_jupyter_notebook'}`
   **twice concurrently**; assert the two returned `entry_point_url`s carry **distinct** tokens.
2. `curl https://dev-public.biomate.ai/interactive/<token>/ipython/lab` for each → 200 with
   `<title>JupyterLab</title>` and `baseUrl` rewritten to `/interactive/<token>/ipython/`;
   `…/ipython/api/status` → 200.
3. Read-only SSM diagnostics (instance `i-06696b0d91f4346e0`) to confirm each token maps to a **distinct**
   container + port: `token → entry_point.job_id → job_container_association.container_name → docker inspect`.

---

## 7. Commits

On branch `dev-it-multisession-20260816` (superset of the IT-enablement chain):

| Commit | What |
|---|---|
| `437461a70` | multi-session proxy — per-token routing + baseUrl rewrite (HTTP + WS) |
| `53a7f6726` | galaxy-proxy: widen transient-retry budget to span the gunicorn restart tail |
| `39ec24778` | job-correlated entry-point token (first cut, via `/api/entry_points`) |
| `1001e7426` | **the fix** — resolve launch token by decoding `job_id` in-container (DooD-proof); removes the dead `getEntryPointForJob` |
| `2d7930dfe` | docs (this feature) + reaper in `enable_interactive_tools` |

Two unrelated self-contained commits were also rescued from the working tree during the session (they
would otherwise have been wiped by concurrent-session churn): the galaxy-proxy retry budget above, and a
`connectors-dialog` custom-skill delete UI (`015d70626`). Both tsc-clean.

---

## 8. Landing status — needs merge-ordering, not more code

- **Draft PR #132** tracks the work (kept draft intentionally — no review ping).
- The branch is **~390 commits ahead of `origin/integration/next-phase`** because local `next-phase` runs
  far ahead of origin and carries other sessions' unpushed work. A squash-merge as-is would collapse all
  390 into one unreviewed merge — **not done deliberately.**
- **Isolation was tried and is not possible:** cherry-picking just the multi-session commits onto a fresh
  branch off `origin/integration/next-phase` conflicts immediately on `scripts/sync_to_dev.sh`, because
  origin lacks the entire IT enablement foundation (docker socket, `/app` materialization, gx-it-proxy,
  `job_conf.yml`, galaxy configs — the commits in **PR #119** + the prior enablement session).
- **Therefore the order is: land #119 (enablement) first → this rebases cleanly on top.** They are one
  feature. This finding is recorded as a comment on PR #132.

---

## 9. Next steps

1. Land **PR #119** (IT enablement) once its branch is reconciled with origin, then rebase/merge the
   multi-session commits on top (or fast-forward if origin/next-phase already carries them).
2. **Client polling UX:** have `interactive-launcher.tsx` poll the returned `entry_point_url` until 200
   (spinner during the ~10–30 s container-boot window) instead of opening it immediately.
3. **Production IT destination:** replace DooD (host docker socket) with a real isolated job destination
   (k8s/ECS) before any non-dev use. Once there's a real destination the container-monitor `configured`
   flag works, and the simpler `/api/entry_points` `target` path becomes viable (though the in-container
   decode remains a fine, restart-stable fallback).
4. **Reaper cadence:** the reaper currently runs only during `enable_interactive_tools`; orphaned
   containers accumulate between enables. Consider a periodic reap (or reap-on-launch) if leakage matters.
