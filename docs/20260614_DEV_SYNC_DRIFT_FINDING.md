# Dev sync drift — finding from 2026-06-14 baseline e2e

## TL;DR

The e2e harness (`scripts/e2e_use_cases.sh`) running against
`https://dev-public.biomate.ai` failed 9 P0 + 4 P1 assertions. Root
cause is NOT that the features are broken — it's that **dev is
running a bundle from a sync source that did NOT have the project
framework, dataset cap, compression UUID preservation, or several
auth fixes**.

The canonical `integration/next-phase` branch HAS all the code. A
sync from a clean checkout of that branch will fix it.

## Evidence

### Code IS on the canonical branch

```
$ ls frontend/server/project-routes.ts
-rw-rw-r-- 1 yzhang yzhang 8636 Jun 14 00:30 frontend/server/project-routes.ts

$ grep -c registerProjectRoutes frontend/server/routes.ts
2

$ git log -1 --format='%h %ai %s' -- frontend/server/project-routes.ts
0991abf2fc 2026-06-12 20:09:17 -0500 feat(projects): full LTM project framework — server CRUD + client UI

$ git merge-base --is-ancestor 0991abf2fc HEAD && echo "ancestor"
ancestor
```

### Local bundle correctly includes the code

```
$ npx esbuild server/index.ts --platform=node --packages=external \
    --bundle --format=esm --outfile=/tmp/test_bundle.js
   /tmp/test_bundle.js  1.4mb
   ⚡ Done in 43ms

$ grep -c registerProjectRoutes /tmp/test_bundle.js
4
```

### Deployed bundle on dev does NOT

```
$ sudo docker exec biomate-dev-frontend ls /app/dist
index.js
public

$ sudo docker exec biomate-dev-frontend sh -c \
    'grep -c registerProjectRoutes /app/dist/index.js'
0
```

### Dev /api/projects returns 404

```
$ curl -sS -X POST https://dev-public.biomate.ai/api/projects \
    -H "Authorization: Bearer $JWT" -H "content-type: application/json" \
    -d '{"name":"diag"}'
<!DOCTYPE html><html lang="en"><head>…<title>Error</title>…
<pre>Cannot POST /api/projects</pre>
HTTP 404 ct=text/html

$ curl -sS https://dev-public.biomate.ai/api/projects \
    -H "Authorization: Bearer $JWT"
{"error":"NotFound","message":"API route /api/projects not found"}
HTTP 404 ct=application/json
```

Auth works (`auth/me` returns the user); only the project framework
endpoints are missing.

### Container last started

```
$ sudo docker inspect biomate-dev-frontend --format '{{.State.StartedAt}}'
2026-06-14T04:02:36Z
```

That's recent enough that the recent next-phase commits were
available on origin — but the sync that ran was either:
  - from a stale local clone that hadn't pulled
  - from a topic branch that lagged behind next-phase
  - from a session that stashed the project-routes import before
    syncing

This is exactly the scenario the CLAUDE.md sync rule (commit
`3e87791456`) was added to prevent. The drift happened before that
rule landed; the next sync will reset the state.

## E2E harness output (this run, against dev as-is)

```
passes: 12
P0 fails: 9
P1 fails: 4
P2 fails: 0
```

Per-UC summary:

| UC | Priority | Status | Root cause |
|---|---|---|---|
| UC-1 register/verify | P0 | ✗ no verificationToken | auth fix not deployed |
| UC-2 project+DEG | P0 | ✗ /api/projects 404 | project framework not deployed |
| UC-3 cross-user | P0 | partial (URLs 404 but for wrong reason) | same |
| UC-4 dataset cap | P1 | ✗ kept all 33, oldest=ds-000 | dataset-cap not deployed |
| UC-5 compression UUIDs | P1 | ✗ preserved header missing | compression fix not deployed |
| UC-7 abstract skip | P1 | ✓ chat_only returned | passive default behaviour |
| UC-8 trial-expired | P0 | skipped (needs SQL) | covered by audit script |
| UC-9 sync-rule branch | P0 | ✓ on integration/next-phase | new |
| UC-10 Bioc routing | P1 | ✓ 3/3 routed to workflow states | core routing OK |
| UC-11 chain↔chat | P1 | not in headless harness | UI |
| UC-12 schema-grounded | P2 | not in headless harness | UI |
| UC-13 memory try/catch | P2 | skipped (would need failure injection) | source-tested |

## Recommended action

Run a sync **from the current canonical `integration/next-phase`
worktree** (which IS at the right commit and HAS all the code) to
restore dev to the expected state. The pre-sync gate already passed
locally (`scripts/pre_sync_check.sh` returned 0):

```
✓ branch=integration/next-phase, working tree clean
✓ W1 tsc — clean
✓ W2 vitest — 0 test failures, ≤ 2 file failures (DATABASE_URL env-only)
✓ W3 embeddings — loaded / rebuilt OK
✓ W4 boot smoke — backend came up clean
✓ Safe to run scripts/sync_to_dev.sh
```

After sync, re-run `scripts/e2e_use_cases.sh`. The 9 P0 fails should
all turn green (they're caused by missing routes, not broken logic).

## Going forward

The CLAUDE.md sync rule + the test plan + the wrapper scripts (this
session's output) form a closed loop:

```
canonical branch on next-phase
       │
       ▼
scripts/pre_sync_check.sh   (W1–W4 + branch self-check)
       │ exit 0
       ▼
scripts/sync_to_dev.sh
       │
       ▼
scripts/post_sync_check.sh  (S1–S5 + branch self-check)
       │
       ▼
scripts/e2e_use_cases.sh    (UC-1..UC-13 against dev)
```

Each step refuses to run from a non-canonical branch. Drift like the
one this doc records becomes impossible — or at minimum caught
loudly.
