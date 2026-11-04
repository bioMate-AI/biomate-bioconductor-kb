# H9/H10 — Galaxy histories & datasets: surface failures instead of fake-empty

Date: 2026-11-04
Scope: exception-handling audit items H9 and H10 (`docs/20261104_EXCEPTION_HANDLING_AUDIT.md`).

## Problem

Two read endpoints masked a backend/DB/auth failure as an empty result (HTTP
200 with an empty list), so a Galaxy outage, a rejected per-user key, a DB
error, or an S3 access failure looked identical to "you have no data":

- `GET /api/galaxy/histories` — `proxy.getHistories().catch(() => [])` on the
  Galaxy call, `storage.getExecutionRuns(...).catch(() => [])` on the DB call,
  and an outer catch returning `res.json({ histories: [] })`.
- `GET /api/galaxy/histories/:historyId/datasets` — outer catch returned
  `{ datasets: [] }`; the `run:`-prefixed S3 path swallowed `aws s3 ls`
  failures and returned `''` (→ empty datasets).

## Root-cause fix (not a workaround)

A genuinely empty account still returns **200 + `[]`**. A real
upstream/DB/S3 failure now returns a **non-2xx** with an `error` field, a
human message, and the upstream status/body where available. The real cause
is logged server-side at error level.

### Server — `frontend/server/routes.ts`

`GET /api/galaxy/histories` (was ~3572):
- Galaxy call wrapped in its own try. A thrown error (the proxy's axios
  interceptor raises `{ error, message, status_code, detail }`) → **502**
  `GalaxyUpstreamError` with `upstreamStatus` + `upstreamBody` (truncated 500
  chars). A successful-but-empty Galaxy response still yields `[]`.
- DB `getExecutionRuns` call wrapped in its own try. A thrown error → **500**
  `DatabaseError`. (Note: `storage.getExecutionRuns` already falls back to
  MemStorage internally on a query error and logs a warning, so a throw past
  that is genuinely unexpected — but it is no longer swallowed to `[]`.)

`GET /api/galaxy/histories/:historyId/datasets` (was ~3613):
- `run:` S3 path: `aws s3 ls --recursive` exits non-zero both for a genuinely
  empty prefix (no stderr) and for a real failure (AccessDenied, NoSuchBucket,
  bad/expired creds — stderr set). Only a real failure (stderr matches an AWS
  error signature) now returns **502** `S3ListError`; an empty prefix is still
  a valid empty listing.
- Outer catch (non-run Galaxy path): a Galaxy upstream throw (`status_code`
  present) → **502** `GalaxyUpstreamError`; anything else → **500**
  `HistoryDatasetsError`. Both include message + upstream status/body.

The `run:` DB lookup (`storage.getExecutionRun`) is left as-is: it already
catches DB errors internally, logs a warning, and returns `undefined` (→
legit "no outputs yet" for a run still producing files). Not a silent mask.

### Client — `frontend/client/src/components/galaxy-dataset-browser.tsx`

Only consumer of both endpoints (`HistoryTab`).
- Histories fetch already checked `r.ok` and had an error + Retry state;
  improved it to read the server's `message`/`error` body instead of a
  generic "Could not load histories".
- Datasets fetch (`openHistory`) previously did `fetch().then(r => r.json())`
  with `.catch(() => setDatasets([]))` — it did **not** check `r.ok`, so a
  502/500 rendered an empty list that read as "No datasets in this history".
  Extracted into `loadDatasets(history)`, which now checks `r.ok`, throws the
  server message on non-2xx, and sets a new `datasetsError` state. Added an
  inline error + **Retry** branch in the dataset list view, matching the
  existing histories error UI (centered muted text + ghost Retry button).

## Callers checked

Every reference to these endpoints / proxy methods:

| Caller | Location | Handling |
|---|---|---|
| `GalaxyDatasetBrowser` histories fetch | `galaxy-dataset-browser.tsx:258` | **Primary user path** — already `r.ok`-aware + Retry; improved to show server message. |
| `GalaxyDatasetBrowser` datasets fetch | `galaxy-dataset-browser.tsx:272` | **Primary user path** — added `r.ok` check + `datasetsError` + Retry. |
| `getHistories` (interactive-tool history pick) | `routes.ts:~10074` | Separate handler, own try/catch — unaffected by endpoint change. |
| `getHistoryDatasets` (paired-collection) | `routes.ts:~14971` | Separate handler, own try/catch — unaffected. |
| `galaxy-assistant.ts` `getHistories().catch(() => [])` | `galaxy-assistant.ts:3683` | Different call site (assistant context build); intentionally best-effort — left unchanged. |
| `workflow-prerequisites-validator.ts` | `:265`, `:281` | Internal validator, own error handling — not a consumer of these HTTP routes. |

No background poller or unrelated flow consumes these two HTTP endpoints, so
the non-2xx cannot crash an unrelated path.

## Gate results (local, this worktree)

- `npx tsc --noEmit -p .` — **clean, exit 0** (run via sibling checkout's
  `node_modules` symlinked in then removed; worktree has no `node_modules`).
- `vitest run client/src/components/parameter-dialog.test.tsx` — **4/4 pass**
  (only vitest file touching this component; it stubs `GalaxyDatasetBrowser`).
- No server vitest imports `routes.ts` for these endpoints; tsc covers compile.

## Needs live verification (NOT done here — no deploy per instructions)

- Confirm a real Galaxy outage / rejected per-user key yields 502 with body,
  and the UI shows "couldn't load — retry" (not empty).
- Confirm a genuinely empty account still shows 200 + the empty-state copy.
- Confirm an S3 AccessDenied on a `run:` history yields 502 + retry, while a
  still-running run (empty prefix) shows the empty state.
