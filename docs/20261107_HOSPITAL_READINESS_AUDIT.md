# Hospital pilot readiness and deployment audit — 2026-11-07

## Verdict

**Do not treat dev as cleared for private hospital uploads yet.** A live access-control failure was reproduced using only this audit's synthetic files. Fixes are prepared for review; the live failure must be retested after deployment. No patient data was used, no users were invited, no account permissions were changed, and no scientific workflow was launched.

Target tested: `https://dev-public.biomate.ai`. The intended hospital-facing address was requested but not confirmed during the audit. This report does not establish the state of another deployment.

## Confirmed findings

1. **Private-file access bypass (release blocker).** The standard project-file URL endpoint correctly returns 401 anonymously. The alternative `/api/workflows/runs/:id/step-file` returned HTTP 200 and the exact CSV, JSON and YAML bytes without login, even with a nonexistent run ID. Bucket membership was treated as authorization. Only the dedicated QA project's synthetic files were requested. Fixed in code by requiring authentication, resolving the original owned/project-member run, binding each storage URI to that run's output records, and checking local path boundaries (including symlinks). On-prem download aliases now resolve Nextflow IDs to the original owned run and reject missing/unknown run IDs rather than skipping ownership checks. This is not yet a live remediation.
2. **Actual deployment omission.** Dev advertises commit `20f159a1cb794b8222ad2f923ae192270d9ee64c`. A read-only SSM hash comparison of 482 sync-managed Galaxy Python/skill files found 481 exact matches, zero differing files, and one missing file: `ai/skills/biomate-universe.md`. The sync script's packaging included Markdown, but its later Python-only layout loop discarded it. Fixed the actual loop and added a post-copy SHA-256 check for skill Markdown. The staging regression test executes that real loop with Python, skill Markdown, unrelated Markdown and AppleDouble fixtures. No backend source was changed on dev by this audit.
3. **PR #328 merge regression.** An extra early empty-output return hid all run metadata when there were no scientific outputs. New tests reproduced this on both failed and completed runs; removing that duplicate return restores the existing metadata section. Red and green test logs are retained locally.
4. **Advisory routing is inconsistent across languages and intents.** The six live English/Chinese advisory classifier responses are recorded in `bilingual-route-checks.json`. The English RNA-seq request was labelled answer-only while the Chinese equivalent was workflow preparation. Literature queries were promoted to the workflow lane; Chinese survival was labelled drug discovery. This is the composer advisory classifier, not proof of what the executor would run. Root-cause investigation is still required; no keyword workaround was added.
5. **AI language changes are not released.** PR #328 remains open. Its Settings selector and explicit reply-language directive are not on the deployed build. A Chinese-language question did receive a Chinese reply and persist, but this verifies question-language mirroring, not the unreleased UI-language directive.
6. **Active report isolation.** HTML report links minted same-origin blob URLs, which discard response security headers; `noopener` alone does not isolate the document's origin. Report navigation now retains the authenticated HTTP endpoint and a CSP sandbox (scripts allowed, same-origin privileges withheld). HTML/SVG response and link-policy regression tests cover this. Live rendering remains unverified. Chrome control failed; the built-in browser later loaded the dev login successfully, but no authenticated visual acceptance run has been completed.

7. **Anonymous profiling leak (release blocker).** POST /api/perception/profile returned sample rows from the private synthetic CSV without login. The local fix requires authentication and authorizes the dataset against the project-file registry, including project membership. Arbitrary server paths and unregistered storage refs are denied; legitimate standalone/unregistered paths need an explicit authorized resolution design before release. No live remediation is claimed.
8. **Health-check false positive.** The old post-sync check accepted HTTP 200 HTML at /galaxy/api/version. The replacement validates JSON and required semantic health fields at /api/galaxy/version and the frontend/assistant health endpoints. Two standard-library tests pass.

## Live checks completed

- 51 checks passed; three checks failed, all three reproducing the same anonymous step-file bypass on different synthetic formats. These are HTTP/API checks, not browser E2E tests. Two harness assumptions were corrected: updates legitimately return HTTP 200, and the live stream terminates with `event: done`; persisted content and version history were independently verified.
- Existing shared fixture login, project/skill/database/MCP/interactive-service/QC endpoints.
- Chinese-named dedicated QA project; CSV, JSON, YAML upload, exact-byte download, hash deduplication, structural/data quality profiles.
- Changed-file upload → v2 → restore v1 as new v3, retaining v1/v2/v3.
- Chinese project settings saved and reread; project-linked Chinese chat and project chat hierarchy; existing saved chats reopened with matching message counts; new assistant reply persisted.
- Two completed fixture runs' reproducibility records returned 200 with 197 and 77 registered outputs. The scientific analyses were not re-executed or independently validated.
- 74 public cold-start/demo assets returned 200 and matched local SHA-256 exactly. This establishes asset deployment, not successful execution of every example.

QA project is synthetic-only and retained for review: `/projects?project=067a17c4-c14a-49d8-a8c8-c41ae49f6807`.

## Git / PR audit

- Dev's build ID and the local last-full-sync marker both identify `20f159a1c`; that does not prove every file shipped, as the missing Markdown demonstrates.
- PR #328 is pushed but open; this is an unreleased change, not a failed sync.
- Reviewed 26 recent client commits outside dev's ancestry. Twelve have identical deployed client patch IDs. Further source inspection confirmed key report, progress grouping, QC wording, feedback and starred-workflow changes already exist through later commits/refactors. Commit ancestry alone must not be used to call those missing.
- Older open PRs include #240 (original Chinese localization), #316 (merge candidate), #324 (explicitly review-only) and #310 (assay/BO/Benchling fixes). Open PRs are not evidence those complete branches are released. No old branch was blindly merged, closed or deleted during this audit.
- The shared checkout has other ongoing edits. Changes here are isolated in `codex/zh-en-ui-parity`; those edits were preserved.

## Validation and limits

- TypeScript, full frontend suite and production build results are recorded with the review update; focused access/preview/metadata tests and Bash syntax/staging test passed.
- Chrome DOM inspection, navigation and screenshot calls failed with the browser-control connection error; native computer access was also unavailable. The built-in browser later loaded the login page successfully. **No completed live visual/mobile/authentication-onboarding audit is claimed.**
- The SSH key-refresh approach was rejected by automatic approval review. The hash audit instead used existing Systems Manager permissions, without injecting keys or changing access control.
- No GPU/Batch pipeline, live interactive session, email verification, second-user sharing flow, mainland-China connectivity/performance, or full scientific-result verification was performed. A new-account pilot rehearsal and representative public oncology datasets remain necessary.

## Required release verification

Deploy the reviewed access and sync fixes from a pinned commit, then require: anonymous synthetic downloads denied; legitimate owner and project-member outputs still load; active HTML reports isolated; all sync-managed source/skill hashes match; Settings language switch works in a real browser; UI language reaches new AI replies. Recheck the intended hospital-facing URL, not just dev. Resolve advisory-routing discrepancies before presenting those labels as reliable. Do not describe this audit as blanket hospital readiness.

## Integrated local repair validation

After parallel repairs: 212 suites passed, 2,315 tests passed; 3 suites / 42 tests skipped. TypeScript and production build passed. Sync staging, health-check unit tests, Bash syntax and diff whitespace checks passed. Local integration also fixes Models error states/navigation/scroll containment, format editing and preview, failure presentation, metadata display and notebook launch identity/URL handling. None establishes deployed acceptance until the pinned patch is synced and UI journeys are tested.
