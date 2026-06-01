# 2026-06-01 — React #310 Fix, Missing Plot Fix, and Build Repair

## Summary

Three bugs were found and fixed in this session. A fourth root cause (broken Vite build on EC2) was discovered and repaired, which had been silently preventing all previous deploys from taking effect.

---

## Bug 1 — React Error #310 (full-page crash on workflow panel open)

**Symptom:** Opening the workflow panel (after AI returns a workflow) crashed the entire app with `Minified React error #310` (Invalid hook call).

**Root cause:** `useAfterRunFlavor()` was called inside a JSX conditional expression:
```tsx
// WRONG — inside {isPanelOpen && (...)}
{useAfterRunFlavor() === 'v2' && <AfterRunReport ... />}
```
When `isPanelOpen` was `false` (page load), the hook was skipped. When it became `true` (panel opens), the hook ran for the first time — React saw a different hook count between renders and threw #310.

**Fix:** Moved the hook to the top level of `ChatWithArtifacts` (line 89), before any JSX:
```tsx
const afterRunFlavor = useAfterRunFlavor()
// ... later in JSX:
{afterRunFlavor === 'v2' && <AfterRunReport ... />}
```

**File:** `frontend/client/src/components/chat-with-artifacts.tsx`  
**Commit:** `9ff7bf7d3`

---

## Bug 2 — Gray box / missing plot in AI responses

**Symptom:** AI text responses occasionally showed a gray empty box where a plot/image should be, particularly in the "Example of what I can generate" section.

**Root cause:** The AI (Claude) hallucinated a markdown image reference `![example]()` with an empty `src`. Since `rehypeRaw` is enabled in `ReactMarkdown`, this rendered as a real `<img src="">` — browsers display this as a gray box.

**Fix:** Added a custom `img` component override in `ReactMarkdown`:
- Returns `null` for empty/missing `src` (gray box never appears)
- Adds `onError` handler to hide images that fail to load (404s)

**File:** `frontend/client/src/components/chat-message.tsx`  
**Commit:** `5656500af`

---

## Bug 3 — "BioMate is generating workflow…" cue never showed

**Symptom:** After an AI text response, the "BioMate is generating the workflow for you…" typing indicator (below the text) never appeared before the workflow panel loaded.

**Root cause:** The `workflow_ready` SSE event and `final` SSE event are sent back-to-back in the same TCP flush from the server. React batches both the `setWorkflowGeneratingPhase('workflow')` call (from `workflow_ready`) and the `setIsTypingLocal(false)` call (from `onSuccess`) together — the intermediate "workflow" state never paints to the DOM.

**Fix:** Added an independent `showWorkflowCue` state flag that is set to `true` in `onSuccess` when a workflow was successfully generated, and self-clears after 1.5 seconds. This decouples the cue from `isTypingLocal` entirely.

**File:** `frontend/client/src/components/chat-interface.tsx`  
**Commit:** `23fe1973f`

---

## Root Cause — Vite Build Broken on EC2 (all deploys silent no-ops)

**Symptom:** `sync_to_dev.sh` reported "OK" after every run but the live bundle hash never changed (`index-C-2_rZw4.js` persisted across 4+ deploys).

**Root cause (build failure):** `chat-with-artifacts.tsx` imported two files that were never created:
```ts
import { submitWorkflowFromArtifact, ... } from "@/lib/chain-execution"
import { fetchChainStatus, ... } from "@/lib/chain-pipeline-sync"
```
Vite errored with `ENOENT: no such file or directory` and the Docker build exited with code 1. Because the `docker build ... | tail -5` pipe in the deploy script causes `tail`'s exit code (always 0) to mask `docker build`'s exit code (1), the swap continued using the old `:latest` image.

**Root cause (silent failure in sync script):** `do_sync` is called inside `if do_sync ...; then` in bash. When a function is used as an `if` condition, bash disables `set -e` for the entire call tree inside that function. SSH failures and build failures therefore never abort the script — it always exits 0.

**Fix:** Created the two missing files as API-backed stubs:
- `frontend/client/src/lib/chain-execution.ts` — `submitWorkflowFromArtifact`, `resumeWorkflowChain`, `buildChainSubmitSteps`, `buildChainConnections`
- `frontend/client/src/lib/chain-pipeline-sync.ts` — `fetchChainStatus`, `syncPipelineStepsFromChain`

**Commit:** `945673f29`

**Additional root cause (AWS credentials):** EC2 Instance Connect requires valid AWS IAM credentials. The credentials had expired, causing all `send-ssh-public-key` calls to fail silently (stderr suppressed by `2>/dev/null`), which meant SSH keys were never pushed and all SSH commands returned `Permission denied`. Re-running `aws configure` with fresh credentials restored connectivity.

---

## Verification

After commit `945673f29` was deployed, the live bundle hash changed from `index-C-2_rZw4.js` → `index-T_77COXT.js`, confirming the build succeeded and all three fixes are now live on `https://dev-public.biomate.ai`.

---

## Known Issues / Follow-up

- `Dockerfile.biotools` is not included in the `sync_to_dev.sh` archive (the `tar` command only includes `frontend/Dockerfile`, not `frontend/Dockerfile.biotools`). The biotools base image build fails every deploy but is not fatal since the image is cached from a previous run. Add `frontend/Dockerfile.biotools` to the tar command to fix properly.
- The `do_sync` / `set -e` interaction in `sync_to_dev.sh` means build failures are silent. Consider wrapping `do_sync` call in a subshell or adding explicit exit code checks.
- The chain API endpoints (`/api/chain/submit`, `/api/chain/resume`, `/api/chain/:id/status`) referenced by the new stubs need backend implementation if chain/pipeline workflows are to be used.
