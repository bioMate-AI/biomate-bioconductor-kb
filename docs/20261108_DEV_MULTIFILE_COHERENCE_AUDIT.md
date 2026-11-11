# Dev multi-file coherence audit — November 8, 2026

## Scope and acceptance standard

Continue the online/dev readiness work with a real user journey: upload two assay result files, select both in chat, join by compound identity rather than row order, execute the calculation against the actual selected bytes, and present consistent results. A third deliberately conflicting file must not participate. No hospital data, API interception, synthetic success responses, new accounts, predictive accuracy claims, or GPU jobs are involved.

The test uses the existing fixture account and creates only its own temporary project, three CSVs and a chat session. Cleanup is asserted and recorded. Authentication traces and presigned URLs are excluded. Original failures are retained; a numerically correct answer alone is not sufficient evidence of actual input provenance.

## Observed results before the fix

Initial deployed application: `e06ade54e1bc8cae058fcd52c8895cc946e1b45c`.

| Attempt | Evidence directory under `docs/qa/20261108-dev-coherence/` | Verdict |
| --- | --- | --- |
| Fresh chat link | `run-1794121878660` | Failed: the project query did not activate project context, leaving the chat Unfiled with no attachment chip. All uploaded files and the test project were removed. |
| Normal Data Hub → Use in chat → add second project file | `run-1794121988743` | Both exact references reached the real chat request and the numerical answer was correct. The test failed because its final calculation result reported no staged inputs. Tool events were not retained in this initial attempt, so the ledger does not establish how that result consumed its data; do not label it a verified file-execution pass. Cleanup succeeded. |
| Explicit staged-file execution | `run-1794122168758` | Actual tool events prove both exact selected IDs were staged and read by pandas, returning the correct identity join and differences. The distractor was excluded. The test then failed its answer-text assertion: capture showed mojibake and the assertion accepted ASCII minus only. Browser DOM and screenshot show correct scientific symbols and values. Cleanup succeeded. |

Fixtures: A contains CMP_A=12, CMP_B=3, CMP_C=7 µM. B has reordered rows CMP_C=6, CMP_A=4, CMP_D=8 µM. The expected common-compound B−A differences are −8 and −1 µM; CMP_B and CMP_D are unique to A and B respectively. The unused CSV contains conflicting values 9999 and 9998. File hashes and exact IDs are in each ledger.

## Root causes and narrowly scoped corrections

1. `RootRoute` did not consume the project context carried by a file-to-chat URL. `ChatInput` correctly refused to attach a file unless its URL project matched the active project; a fresh browser had no active project. Add `useChatProjectLink` to select the linked project after authentication, only when a non-empty project and file reference are present. Keep all file parameters intact so the existing composer resolves exact IDs. This is UI context selection, not an authorization bypass; the existing server authorizes project/file access. Ordinary unfiled chats are unchanged.
2. Chat SSE responses omitted an explicit UTF-8 charset. A local real HTTP/Chrome reproduction returned `âˆ’8 ÂµM ä¸­æ–‡` through Playwright response capture for a bare `text/event-stream` header and `−8 µM 中文` with `charset=utf-8`, with identical response bytes. Add the explicit charset to both normal chat and safety-refusal stream headers. Do not repair already-corrupted text with heuristics or change the model's scientific answer.
3. The harness incorrectly treated a Unicode mathematical minus as a failed numeric assertion. Accept ASCII hyphen or Unicode minus, while still rejecting observed mojibake and requiring exact structured numeric outputs. Keep the staged-file assertions. Capture the actual tool calls/results for audit. Opening a copied two-file link must also restore project context, attach both files and not auto-submit a chat request.

## Verification and deployment discipline

The first focused run passed 37 tests across exact file selection, server authorization, sandbox attachment handling, composer references and the new project-link hook (9 behavioral cases). The initial isolated candidate TypeScript check passed.

The first full-suite attempt was NOT a passing run: the sandbox denied local HTTP listeners, the frontend-only export omitted non-frontend fixtures, and transform writes reported ENOSPC. Its complete log is retained at `/private/tmp/biomate-20261108-coherence-release-vitest.log`. These are diagnosed test-environment failures, not permission to skip checks. The two omitted fixtures were exported from the exact Git revision, further source dependencies were included, and the repeat allows the tests' local HTTP servers. Workstation free disk was approximately 360 MiB; no unrelated files were deleted.

PR 335 was merged into `codex/zh-en-ui-parity` while this audit was running. Another chat is actively syncing revision `e8f6f78a2a72572395b26701af1a9d7b042fa39c`; the public build changed to `voice-20261108-700803a2d456` in the interim. Do not overwrite either release with the older audit baseline. Prepare the narrow patch on the updated `e8f6f78` source, preserve the new workflow/PDF/findings changes, leave the active sync lock intact, and recheck the actual dev build before any later deployment or live acceptance run.

Current status: fixes are local; updated exact-source full-suite testing is in progress. No post-fix dev PASS or deployment is claimed. Broader report/scientific qualification remains governed by `20261107_DEV_VALIDATION_AND_TEAM_ACCEPTANCE_HANDOFF.md` and is not implied by this synthetic comparison.
