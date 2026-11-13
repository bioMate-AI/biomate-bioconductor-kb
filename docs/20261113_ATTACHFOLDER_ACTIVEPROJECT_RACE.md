# attachFolder → 0 composer chips (activeProjectId race)

**Date:** 2026-11-13  
**Live at failure:** `429c3dbc` (`build-info.json`)  
**Earlier green:** tip `562908a3` with 3 chips for `pairs/` (no nested files in that run)

## Symptom

`frontend/e2e/folder-attach-all-files.e2e.ts` — after Analysis `?attachFolder=pairs`, expected N `[data-testid="composer-dataset-ref"]` chips, got **0** (45s timeout). API `GET …/folders/files` still returned all files; Models picker showed `pairs/ (5 files)`. testid / URL param unchanged.

## Root cause

Product race in `chat-input.tsx` deep-link attach effect:

```ts
if ((!fileIds.length && !hasFolder) || !activeProjectId || query.get("project") !== activeProjectId) return
```

`?project=` + `attachFolder` are present on first paint, but `activeProjectId` often is still `null` (or a stale localStorage id) until `useChatProjectLink` → ActiveProject context → `chat-interface` local-state sync catches up. The effect bailed and never expanded the folder. Not a flaky wait; not deploy tip drift of the attach API itself (same gate was on `562908a3` — the deepened E2E + cold localStorage made the race reliable).

`b9f468b` seeded `biomate-active-project-id` before navigation (test workaround). That masked the race; it did not fix the composer.

## Fix

Composer deep-link attach is keyed by **`?project=` in the URL**:

- Proceed when `linkProjectId` is present even if `activeProjectId` is still null.
- If `activeProjectId` is set to a *different* project, wait for the link hook (do not attach the wrong home’s files).

Unit coverage: `chat-input.dataset-references.test.tsx` — null `activeProjectId` expands; mismatched id waits.

E2E now **clears** localStorage before attach navigations so live proves the product path, not the seed workaround.

## Deploy note

Frontend-only. Sync required before the live E2E can pass without seeding.
