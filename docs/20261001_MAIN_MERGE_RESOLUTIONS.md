# Main-merge conflict resolutions (integration/next-phase → consolidated)

**Date:** 2026-10-01
**Merge branch:** `integration/mergemain-20261001` (in worktree `/Users/kky/biomate-consolidated`, **mid-merge**)
**Status:** 10 of 11 conflict files resolved + verified (no markers; 4 backend `.py` pass `py_compile`). **`frontend/server/routes.ts` is NOT applied** — the auto-mode classifier blocked editing it. Its 5 resolutions are specified below, ready to apply.

> To finish: apply the routes.ts resolutions below, then `git diff --name-only --diff-filter=U` must be empty and `grep -rn '^<<<<<<<\|^>>>>>>>\|^=======$' frontend backend` must be clean; run `cd frontend && npx tsc --noEmit -p . && npx vitest run`; `cd backend && PYTHONPATH=lib python3.9 -m py_compile` the 4 files; then `git commit` the merge and open a PR into `integration/next-phase`. Do NOT push directly to the shared branch.

## Resolved (10/11) — decisions

1. **billing_router.py** — kept **ours** (fork): the master-key-exclusion query (`:mk != "key"` + `ORDER BY id DESC`), the "only real users" fix. Main's side was a subset.
2. **llm_client.py** — **kept both**: `if local_only(): return generate_local(...)` (fork, global on-prem override) THEN main's `_DIRECT_PROVIDERS` → `_generate_openai_compatible`. Both helpers verified to exist.
3. **qc_trace_monitor.py** — main's `s3 = make_s3_client()` (the `_boto3` import is gone) + **kept** the fork's `_report_names = ("qc_metrics.json","toxicity_report.json")` (toxicity support).
4. **nextflow_executor.py** (2 hunks) — took **main's** `_list_local_output_files(path, run_id)` for both (richer: S3-shaped, skips NF internals, returns `[]` for missing dir — covers the fork's "unavailable" case). `_local_files` left unused.
5. **chat-input.tsx** — kept the fork's superset of lucide icons + added main's `import { filesFromDataTransfer } from "@/lib/folder-drop"`.
6. **project-detail.tsx** — kept the fork's `setMyRole("editor")` (owner-transfer demotion; `myRole` state exists, matches the code comment).
7. **s3-client.ts** (2 hunks) — **merged**: kept the fork's `createClient()` architecture + null-credential guard (IAM-role default chain; used by `ensureBucketRegion`) AND folded main's `S3_ENDPOINT_URL`/MinIO (`endpoint`+`forcePathStyle`) INTO `createClient`; kept main's `configuredEndpoint` field.
8. **i18n.ts** (add/add) — **merged**: took the fork's full API (bundles + `tStatus`/`setLanguagePreference`/`locale`/`SUPPORTED_LOCALES`, which callers import), inserted main's inline `ZH` dict + `isOnPrem` + `onPrem` export, and extended `t()` to try the JSON bundle (dotted keys) then the `ZH` dict (English-string keys) when `locale==='zh'`. Supports BOTH call styles used across the app.
9. **galaxy-assistant.ts** (4 hunks) — took **main's** (theirs) for all: newer GEO/transcriptomics routing prompts with `S3_ENDPOINT_URL` on-prem conditionals, and the richer OpenRouter/custom-provider path (supersedes the fork's simpler OpenRouter block). On-prem local routing is handled by `llm_client.py local_only()` (resolved above).
10. **app-sidebar.tsx** (5 hunks) — kept **both** icon sets (`Database,Layers,CreditCard,Wrench` + `Server`; `noUnusedLocals:false`); took **main's** English-string `t()` calls for the 4 text hunks (all keys verified present in the merged `ZH` dict).

## NOT applied — routes.ts (5 hunks), EXACT resolutions to apply

- **C1 (~line 2889):** HEAD empty, theirs = MinIO multipart-upload block (`if (process.env.S3_ENDPOINT_URL) { CreateMultipartUpload … proxy URLs … }`). **Take theirs** (keep main's block; remove the three markers).
- **C2 (~line 6510):** **KEEP BOTH** (independent features, do not pick one): the fork's `const _sessionDatasetsResolved = await (async () => { … resolveProjectFileReferences … })()` dataset-reference/project-file-staging block (HEAD) AND main's system-level `openai_compatible` key fallback (`if (!_openrouterKey && process.env.LLM_API_URL) { … }`). Resolve by deleting only the 3 marker lines, keeping all content from both sides.
- **C3 (~line 13426):** Take **theirs**: `const match = allFiles.find(... (f?.s3_uri || f?.path || f?.local_path))` (adds `local_path`; `match` is not reassigned, so `const` is safe).
- **C4 (~line 14235):** Take **theirs** (empty): remove the `const apiKey = process.env.ANTHROPIC_API_KEY; if (!apiKey && !localOnly()) return 503` guard. `apiKey` is not used below, so removing it is safe; on-prem providers are handled by the C2 fallback.
- **C5 (~line 14885):** **Merge** — the shared tail after the conflict uses HEAD's vars (`_s3i`, `_GI`, `_nfKeyI`, `canonical`). Keep HEAD's structure (`runsOutputsService.list` + `_S3I/_GI/_nfKeyI`) and fold main's MinIO endpoint into the client construction:
  ```ts
              const { runsOutputsService } = await import('./services/runs-outputs-service');
              const canonical = await runsOutputsService.list(runId);
              const { S3Client: _S3I, GetObjectCommand: _GI } = await import('@aws-sdk/client-s3');
              const _nfKeyI = process.env.AWS_NF_ACCESS_KEY_ID;
              const _nfSecI = process.env.AWS_NF_SECRET_ACCESS_KEY;
              const _s3iEp = process.env.S3_ENDPOINT_URL;
              const _s3i = new _S3I(_s3iEp ? {
                endpoint: _s3iEp, region: 'us-east-1', forcePathStyle: true,
                credentials: { accessKeyId: _nfKeyI || process.env.AWS_ACCESS_KEY_ID || '', secretAccessKey: _nfSecI || process.env.AWS_SECRET_ACCESS_KEY || '' },
              } : {
  ```
  (This ends with `} : {` so the existing shared lines `region: 'us-east-1', followRegionRedirects: true, ...(creds) });` become the else-branch — no other change needed.)

## If abandoning instead
`cd /Users/kky/biomate-consolidated && git merge --abort && git switch integration/consolidated-20261001` restores a clean, deployed-on-dev state; the consolidated branch (without the main merge) remains what dev serves.
