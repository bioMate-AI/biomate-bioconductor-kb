# Interactive Tools — ship to next-phase, E2E root-cause, and the auth stale-key fix

**Date:** 2026-08-26
**Branches/PRs:** #162, #166, #172, #181 (all merged to `integration/next-phase`)
**Related:** `docs/20260822_RSTUDIO_INTERACTIVE_TOOL_WORKING.md`, `docs/20260823_INTERACTIVE_TOOLS_FULL_TEST_PLAN.md`, `docs/20260610_STALE_GALAXY_USER_DRIFT.md`

## What changed

### 1. Interactive tools landed on origin (5 PRs total)
| PR | Content |
|----|---------|
| #139 | Multi-session per-token interactive-tool routing |
| #150 | Kernel POST hang + WebSocket frame-type fixes (notebook executes) |
| #162 | RStudio + CellxGene working, generalized (port-agnostic) routing, auto-select viewer by dataset format |
| #166 | Reference docs (RStudio-working + full test plan) |
| #172 | Reproducible enablement in `sync_to_dev.sh` (`enable_interactive_tools`, gated behind `BIOMATE_ENABLE_IT=1`) |
| #181 | `auth-service` stale-key downgrade fix (below) |

Architecture recap:
- Custom `/interactive/<token>` reverse proxy (`routes.ts` `targetForToken`), port-agnostic via `docker inspect`.
- `job_conf.yml`: one `interactive_tool_.*` rule → root destination (`docker_set_user: ''`).
- Auto-select registry `frontend/client/src/lib/interactive-viewers.ts` (h5ad→CellxGene, vcf→vcf.iobio, bam→bam.iobio, cool/bigwig→HiGlass, rds→iSEE; unknown→Jupyter).
- Enablement (gx-it-proxy sidecar, docker socket, nginx WS upgrade forwarding, reaper) runs only when `BIOMATE_ENABLE_IT=1`.

### 2. E2E attempt + root-cause (the real finding)
Ran the true serve-path E2E (`interactive-autoselect-serve.e2e.ts`: upload → auto-select → launch → **serves**) against dev, plus manual `curl` reproduction.

**Result: env-blocked, not code-blocked.** The fixture user's `galaxyApiKey` is **null** on dev → `userProxy(req)` = `forUser(undefined)` → Galaxy 400s **every** per-user op (`createHistory`, interactive launch — even Jupyter which ignores inputs, since launch still needs a history).

Chain (`auth-service.ts` `verifyCredentials`, lines ~441–506):
1. A `sync_to_dev` DB swap reset Galaxy's `universe.sqlite` → the stored key went stale (drift; see `20260610_STALE_GALAXY_USER_DRIFT.md`).
2. Login's stale-check **cleared** the key to null, **then** called `provisionGalaxyUser`.
3. `provisionGalaxyUser` POSTs `/internal/users/provision` — **failing on dev** — and never throws (returns `false` + background retries).
4. Login still 200s, but the user is left with a **null** key → all Galaxy ops 400.

**Failing component: `POST /internal/users/provision` on dev's Galaxy backend** (internal-only, not publicly reachable). Dev IS running the merged frontend build (upload response key-set matches `routes.ts` exactly), so this is not a stale-build issue. RunCommand SSM is denied for `biomate-admin` (empty-message `InvalidDocument`) and the dev frontend has no CloudWatch log group, so the live provision error could not be read from outside the host.

The E2E harness itself is correct (reads `galaxy_dataset_id`, fails loudly when no HDA is provisioned — test integrity intact).

### 3. Auth stale-key downgrade fix (#181)
`verifyCredentials` now re-provisions **first** and only overwrites credentials when it succeeds; it keeps the existing (possibly stale) key on failure. A stale key and a null key fail the same way, but the stale key preserves `galaxyUserId` for the next drift check and lets background retries recover the session instead of stranding it. Also immunizes against a transient `/api/users/current` probe blip falsely nulling a good key.

Regression test: `frontend/server/auth-stale-key-downgrade-20260826.test.ts` (4/4). Existing auth suites 22/22, tsc clean.

## What was tested
- Unit: interactive-viewers registry + launcher (15/15, from #162); auth stale-key (4/4); auth-fixes + auth-service (22/22). tsc clean on all merged branches.
- E2E (dev): serve-path attempted — blocked upstream (see §2). Not a false pass; the test correctly failed at the un-provisioned input step.

## Known open issues
1. **`/internal/users/provision` is down on dev** — the actual blocker for the interactive-tools E2E *and* all Galaxy-input flows (uploads-as-HDA, history creation). Needs dev-host diagnosis; not reachable/fixable from outside the host.
2. **Dev not re-synced with the merged code** — needs `BIOMATE_ENABLE_IT=1 bash scripts/sync_to_dev.sh` from a **clean** `next-phase`. Blocked while the main repo is on a concurrent session's dirty branch (syncing from a worktree is prohibited).
3. **Deferred:** `project-file-tree.tsx` input-surface launcher wiring depends on the data-UI foundation (`galaxyDatasetId`/`launcherOpen`) not yet on origin.

## Next steps
1. Bring `/internal/users/provision` back up on dev (or restore the fixture's Galaxy key), then re-sync with `BIOMATE_ENABLE_IT=1` and re-run the serve-path E2E.
2. When the main repo frees up, land the deferred file-tree input wiring together with the data-UI foundation.
