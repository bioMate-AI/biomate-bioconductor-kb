# run_code Sandbox: Production Path

**Date:** 2026-05-18
**Branch:** `integration/next-phase`
**Status:** abstraction landed; sidecar service is the next concrete step

## Why

`run_code` (the LLM-callable Python/R/bash tool) spawns ephemeral sandbox containers via `docker run`. The frontend container today mounts `/var/run/docker.sock` to do this, which grants root-on-host through the daemon. Acceptable for dev; **must not ship to production** as-is.

## What changed

`frontend/server/code-runner.ts` now picks the sandbox backend at runtime:

| `RUN_CODE_BACKEND_URL` env | Behavior |
|---|---|
| unset (dev default) | spawn `docker run --rm --network=none ... biomate-biotools:1` against the mounted socket — same as before |
| set (production) | POST script + bind-mount path + image + limits to that URL; the frontend container needs no docker access |

Implementation detail: same `--network=none / --memory=2g / --cpus=2 / --user uid:gid` envelope in both paths; sidecar contract preserves all isolation invariants.

## Sidecar contract

```
POST {RUN_CODE_BACKEND_URL}/run
Authorization: Bearer {RUN_CODE_BACKEND_TOKEN}   (optional)
Content-Type: application/json

{
  "baseDir":        "/tmp/biomate_code/<session>",
  "interpreter":    "python3" | "Rscript" | "bash",
  "scriptPath":     "/work/script.py",
  "image":          "biomate-biotools:1",
  "timeoutSeconds": 300,
  "network":        "none",
  "memory":         "2g",
  "cpus":           2,
  "user":           "1000:1000",
  "env":            { "DATA_DIR": "/work/input", "OUTPUT_DIR": "/work/output", "HOME": "/tmp" }
}

→ 200 { "stdout": "...", "stderr": "...", "exitCode": 0 }
→ non-200 → frontend treats as error, surfaces stderr=[sidecar error: HTTP N]
```

The sidecar is responsible for the actual `docker run` (it has the socket); the frontend has no docker access. Bind-mount path must be accessible to the sidecar (shared volume or NFS); the obvious deployment runs sidecar on the same host as the frontend with `baseDir` on a shared docker volume.

## What's NOT in this commit

A reference sidecar implementation. The contract is small (one endpoint, well-typed JSON) — any of these are acceptable:

1. **Minimal node sidecar** (~50 lines, mirrors the `runViaDocker` block from `code-runner.ts`). Quickest to ship.
2. **rootless-docker variant** — sidecar runs in a user-namespaced container, no host root escalation possible.
3. **firecracker / kata-containers** — full microVM isolation, slower spinup (~125ms) but the strongest boundary.

Recommended for v1: option 1 (node sidecar) deployed via the same image-build pipeline that ships the frontend. Option 2 as v2 hardening.

## Deploy plan

1. Build + ship the sidecar image to ECR (`biomate/run-code-sandbox`).
2. Add to docker-compose for stage/prod (same host as frontend, `/var/run/docker.sock` mounted in **sidecar only**, not frontend).
3. Set `RUN_CODE_BACKEND_URL=http://run-code-sandbox:8090` and `RUN_CODE_BACKEND_TOKEN=<rotating>` in the frontend env.
4. Remove the `-v /var/run/docker.sock:/var/run/docker.sock` line from the frontend container's deploy command.
5. Smoke-test: ask BioMate "run `print(2+2)` in Python" — sidecar should respond with stdout=4.

After step 4 lands, the frontend container has no path to host root via the docker daemon.

## Open questions

- **`baseDir` sharing**: sidecar must read/write the same `/tmp/biomate_code/<session>` paths the frontend wrote scripts to. Simplest: shared docker volume. Alternative: sidecar accepts the script + inputs as multipart upload, runs in its own tmpfs. Multipart is cleaner but doubles wire traffic for large inputs.
- **Resource enforcement**: the contract specifies memory/cpus, but enforcement is the sidecar's responsibility. Should the sidecar accept these as suggestions (and clamp to its config), or reject runs that exceed configured limits? Recommend reject for v1.

## Follow-ups

- File `frontend/server/code-runner.ts` `runViaSidecar` already implements the client side. No more frontend changes needed until the sidecar exists.
- Tracking this work alongside CI/CD P1.3 (`scripts/deploy.sh` SSM rollout) is the right place — both are production-readiness items that ship together.
