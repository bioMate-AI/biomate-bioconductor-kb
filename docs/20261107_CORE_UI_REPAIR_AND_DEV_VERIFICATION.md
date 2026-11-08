# Core UI repair and dev verification — 2026-11-07

## Scope and deployment state

Work is isolated on `codex/zh-en-ui-parity`, PR #328. The original worktree's unrelated changes and live workflow database are preserved. This document records code changes and evidence separately from deployment verification. Until the final verification section is filled, these repairs are not claimed deployed.

## Repairs in this batch

- Chat clarification responses no longer become executable workflow cards. The server blocks typed unresolved choices before creating a run; ordinary proposal review still reaches the existing input/confidence gates. Chat progress retains producer event and invocation identity through both chat hosts. Replayed event identity cannot create a second copy. Historical dates include the date and full timezone tooltip.
- After Run avoids a repeated section heading; failed runs do not present a diagnostic sentence as scientific findings or claim unproven automatic recovery.
- Citation retrieval is folded, source metadata uses supplied values, abstracts/excerpts appear when supplied, and missing source text has a compact explicit state. This does not invent abstracts or add search-provider coverage.
- Connectors has persistent close/navigation, bounded scrolling and Markdown skill import through the existing validated endpoint. Existing connections/skills are retained.
- Hospital synthetic multi-omics inputs were recovered from the actual earlier validation fixture, with provenance/checksums. Integration and subtype examples prepare reviewable project-linked drafts; evaluation truth is explicitly excluded from predictor features. Existing example assets remain available. Data presence is not proof of a successful new analysis.
- Models now offers explicit Train/Rounds setup with real project/file choices and confirmation drafts, preserving multiple exact file references. Selected training settings survive config → workflow → staged launch snapshot, including task, model name, metric, gate and cross-validation folds.
- Central training artifact registration binds the authenticated owner to an exact run's canonical S3 outputs. It validates artifact hashes and recorded gate evidence, persists immutable versions idempotently, and never auto-promotes or advertises inference serving. Historical settings are never guessed. Registry UI exposes actual versions, source run and gate evidence.
- Central registry default is `/app/database/model_registry`. Read-only dev inspection verified `/opt/biomate/galaxy_db` is mounted read/write at `/app/database`, writable by Galaxy UID 1000.
- Legacy Models/adaptation reads and inference results now require verified ownership through a privileged server bridge. Adaptation compilers receive exact owner/project feedback rather than a shared global input. Unbound historical ownership never becomes global visibility.
- New controls have both English and Chinese labels in the same application. No alternate `?ui=v2` application is introduced.

Earlier commits in this PR also repair private dataset access, sandboxed report previews, JSON/YAML type handling, notebook launch identity/URLs, unified Settings navigation, format editing and save errors, metadata-only outputs and backend Markdown sync verification.

## Evidence before final deployment

- Final integrated run: 222 suites / 2,388 tests passed; 3 suites / 42 tests skipped. Production client/server build passed. A literal retired-panel guard exposed a TypeScript unreachable-branch narrowing error; the retired duplicate render block was removed. Final typecheck passed, with 12 focused UI tests passing after that removal.
- New registration/config/staging/backend focused checks: 74 Python tests passed. Narrator: 21 Python tests passed. Models/worker ownership: 30 Python tests passed; Node ownership bridge: 15 tests passed. Registry/shared execution boundary: 11 tests passed.
- Exact changed backend modules imported in dev's Python 3.9.25 using a temporary overlay, without overwriting live source or restarting services. Final overlay imported all ten changed runtime modules under Python 3.9.25; each checked source hash matches the current worktree.
- Nextflow inspection parsed the changed training process with zero tasks submitted.
- Workflow guards: all three required chains passed; fabrication audit scanned 3,729 executable workflow files and passed. Both used the existing main database read-only with the isolated workflow tree; no database replacement is planned. Other chain audit findings remain separate open work.
- The legacy After Run audit initially failed because it queried anonymously and checked obsolete bundle wording/feature flags. Replaced with authenticated, read-only saved-run/export contracts. Live old dev: 48 passed, zero failed, four explicit chat-link coverage skips. Component tests cover rendering; API checks do not claim visual equivalence.

## Required final smoke prediction and review

The deployment must ship frontend, backend Python and changed workflow files together from the reviewed commit. It must not replace the live workflow database. Anonymous private-file/profile/model access should be denied; the existing fixture should still reopen saved runs and reproducibility records. Settings should expose Import Workflow/Connectors with one settings entry. Retired project Runs deep links should open Files with project context rather than the duplicate run panel. New hospital examples should attach the preserved inputs to a project draft without starting compute. Train setup should retain exact project/file/task/gate values. Historical runs lacking a launch snapshot must report that limitation, not create a guessed model version. Registry reads should use persisted owner namespaces. Jupyter must return an actual interactive URL or a truthful start failure, never a fabricated job URL.

The supervised test mode in sync_to_dev.sh retains all health and generation gates but does not auto-launch the legacy background browser suites; explicit browser checks use the working in-app browser and authenticated API checks. This is logged as pending verification, never a test pass.

No new expensive scientific workflow will be launched merely to discover a setup bug. A reviewed lightweight synthetic run may follow successful setup checks. Deployment identity, backend source hashes, API results and browser observations must be recorded after sync.

## Boundaries still requiring evidence

SSE identity repair does not add an offline replay archive: events emitted with no connected clients are not retrospectively reconstructed. Direct executor runs without a saved chat cannot establish old-chat restoration. Training artifact registration does not implement promotion or numeric model inference serving. Complete hospital workflows, GPU sessions, second-user sharing and mainland-China latency require explicit end-to-end evidence; passing source/unit checks alone does not certify hospital pilot readiness.

## First deployed verification and follow-up findings

`6c5a7eddd4cc5c2c6ec43e9699a7f8fa1bb7b082` was pushed to PR #328 and deployed with `scripts/sync_to_dev.sh`. The script completed successfully; public build identity matched that exact commit. All 488 audited runtime Python/skill Markdown files matched the reviewed source. The live workflow database was not replaced. PostgreSQL audit found 29/29 migration ledger hashes matching and all 43 required columns present.

Authenticated post-sync checks: 32 passed, zero failed, including Models boundaries, retained run inventory, private file access, JSON/YAML/CSV profiles and exact hospital demo bytes. The read-only saved-run audit passed 48 checks with four explicit original-chat coverage skips. Two completed records retain 197 and 77 output entries. A saved synthetic Chinese chat retains its two messages. Historical records without `chatSessionId` cannot prove restoration of an original conversation.

Browser checks confirmed the consolidated Settings entries, Nextflow/Galaxy import controls, connector catalogue and Markdown skill import, project format editor and skills, actual YAML preview text, and file-to-chat attachment without auto-send. A cold-start assay example prepared real CSV/README attachments and an editable draft. Models setup carried the selected project/file/task/metric/gate into a review draft without starting training.

These checks also found additional defects; the first deployment is not a complete acceptance pass:

- URL staging for Jupyter still used Galaxy's obsolete history-copy payload. The follow-up uses the supported `upload1` URL-paste contract; a real interactive session must be verified after deployment.
- The Files workspace squeezed the detail pane at narrow widths. Follow-up layout uses workspace container queries, wrapping tabs and intrinsically sized metadata cards.
- Skills used a clipped absolute-positioned menu. The follow-up uses a collision-aware portal with bounded scrolling and keyboard dismissal.
- Research's “Check against our data” action forced a workflow request. The replacement prepares a clearly labelled analysis draft with the original question and evidence; it sends nothing.
- Run Manager consumed almost the entire available height, and historical panels inherited the composer's project label. Follow-up restores the selected record's identity and gives the workflow panel its space.
- Chinese switching loaded the same application but left hardcoded Instructions labels in English. Follow-up translates those controls while retaining user-authored content.
- The Instructions Memory card was backed by human-only notes, with a nonpersistent toggle/removal. It now states that these are Notes not read by the assistant, supports role-checked persistent deletion, and copies a note to a rule only after a successful save. Automatic assistant memory remains a design gap, not a completed feature.
- Canonical saved-run endpoints rejected anonymous reads, but older proxy aliases did not. Follow-up must enforce authentication and record ownership on every affected alias, including both comparison operands.

The sync audit found a destructive age-based cleanup of local run directories. It was removed. The two directories deleted by the first sync were restored append-only from the pre-sync snapshot: 22 files, 99,930 bytes, all SHA-256 verified. No existing files, database records or S3 objects were overwritten. The snapshot now has a stable preservation tag. See `20261107_LOCAL_RUN_HISTORY_RECOVERY.md`. This does not recover unspecified older missing data or add durable storage across future container replacement.

## Follow-up deployment verification

Final combined suite: **228 suites / 2,434 tests passed**, three suites / 42 tests skipped. TypeScript and production client/server build passed. Shell syntax, backend archive-layout guard and five preflight cases passed. One simultaneous build/test invocation ended without a test summary; it was not counted as a pass. The complete suite was then run alone with four workers and passed. No backend Python/workflow/database files changed after the first deployment's verified source/import checks.

Reviewed smoke prediction: this is a frontend/server/script follow-up; no workflow database replacement, Python reload, nf-core mutation or Galaxy recreation is required. Startup should skip the 29 verified migrations through its canonical runner. The history cleanup is absent and the preserved two run trees must remain. Anonymous legacy read aliases must return 401, owner and invocation-alias exports must still work, and project members must retain authorized reads. Jupyter should stage through upload1 and only succeed when an actual correlated interactive URL exists. Files should stack at the observed 810px viewport, menus fit the viewport, and saved run panels must use recorded identity without relaunching. These predictions require post-sync evidence.

The follow-up was committed as `16a4446031239cf021e27c46cdf9717b250501cd`, pushed to PR #328, and deployed through `scripts/sync_to_dev.sh` successfully. Public build identity matched. The workflow database and Galaxy container were not replaced. Authenticated post-deploy checks passed 42/42; saved-run AfterRun checks passed 48/48 with four original-chat-link coverage skips. All 22 recovered local run files still match their preservation hashes. The 29 migration ledger entries remain valid.

Browser verification confirmed a bounded, scrollable Skills portal and Escape dismissal, narrow-width file list/detail stacking, exact file-to-chat draft attachment without auto-send, and persisted output-format edits through reload. The synthetic QA format was restored to its original value. Chinese Instructions use the same deployed layout with translated controls; the check found remaining hardcoded project/membership/example labels, now corrected locally. This is not full translation coverage of server-supplied content.

A real Jupyter attempt still failed. Launch registration returned a correlated URL, but the actual job exited 127 (`docker: command not found`), and the browser displayed Interactive session not ready. A registered URL is therefore explicitly not counted as successful notebook acceptance. Dev Galaxy lacks the Docker CLI/socket capability required by its configured interactive runner. See the recovery plan; no socket grant or container recreation has yet occurred.

The Files page also still clipped the lower detail content because its parent did not own vertical scrolling. Settings reproduces the same class of failure: its dialog is 648px high while its grid content grows to 1,759px; the inner Radix viewport grows to its full 1,616px content height and has nothing to scroll. Local fixes give each surface a bounded flex/scroll chain; post-deployment browser acceptance is pending.

## Third repair batch — local, not deployed

- Reviewed source-adjacent contracts reconnect five self-contained demo workflows to their real defaults while preserving conservative gates for unreviewed schemas and genuinely required files. ChIP/control inputs are a pair; class labels without a peak table are rejected. These are metadata/wiring defects; the eight audited deployed workflow sources matched the repository.
- Missing supplied chemoproteomics files and unknown explicitly selected sample columns now fail instead of silently replacing user data or choosing a different comparison.
- The catalog-selected flow workflow now stages its actual FCS file into the worker, removes synthetic population fallback, rejects unsupported compensation/unknown gate markers, and labels its bundled H2O blank as a measured scatter/file-format demonstration rather than immune-subset or clinical evidence.
- Notebook launch responses require a running job, job-correlated entry point and responsive target, then recheck the job. Failure/timeout does not return an unusable URL. Synchronous existing Docker lookup calls can exceed the nominal 30-second polling budget; pending launches are not auto-cancelled, and their response warns against starting a duplicate.
- Connector setup gains persistent Back to connector kinds and Cancel restores the originating connector tab. Models detail gains Back while loading. Settings now uses a bounded, keyboard-focusable native scroll region. The navigation matrix distinguishes tested local transitions from pending deployed checks.
- Recovery tooling replaces the old lossy recreation/chmod666 routine with a review-first, exact-plan-digest path, append-only run-state preservation and rollback. It refuses active jobs and non-bind mounts. Host Docker access is a material new capability, not part of ordinary cosmetic sync; approval remains pending.

The actual Galaxy Python3.9 import check for the three modified backend modules remains pending. Automatic approval review rejected their temporary upload to the existing private dev instance for insufficient source-export authorization; user approval was requested. No alternate upload path was used. Local Python3.14 tests and syntax checks do not replace that required target-runtime check. Do not deploy this backend batch until it passes.

## UI-only release boundary and smoke prediction

The pending backend batch is preserved byte-for-byte in a named local Git stash and excluded from this deployment commit; no modified Galaxy Python or scientific workflow is being uploaded. This UI/server/script release should update Settings scrolling, connector return controls, translated Instructions examples and notebook response readiness. It must leave Galaxy's current code, workflow database, container and 22 preserved run-state files unchanged. The reviewed runtime-recovery helper is inert unless the separate IT-only path is explicitly invoked with approval and a matching plan hash.

Expected smoke: public build-info equals the new commit; authenticated Models/file/demo and private-route boundary checks remain green; Settings's content scrollTop reaches scrollHeight minus clientHeight while its header/Close remain on screen; Escape dismisses it; Connector Back and Cancel preserve the original tab and Close returns to the exact project Instructions route; the Files detail bottom is reachable; English and Chinese share those paths. A new notebook is not launched while its known Docker capability is absent: readiness now must report failure rather than return an unusable success URL. Notebook usability and the pending backend examples remain open.

Validation before release: full combined frontend/server suite 2,447 pass / 42 skip; the final exact UI-only tree also passed 2,447 tests / 42 skips after preserving backend edits. TypeScript and production build pass. Seventeen sync-helper/health tests plus actual archive-layout check pass. The pending backend separately passed 22 focused Python tests, required three workflow-chain checks and the 3,729-workflow fabrication audit; flow and chemoproteomics parse with zero submitted tasks. Those local checks do not substitute for actual Python3.9 import or end-to-end scientific execution.

## UI-only dev verification: 6bf15d791

The exact reviewed UI-only commit `6bf15d7912226e172247b54b9afce60ee67be11b` was pushed and deployed successfully with `scripts/sync_to_dev.sh`. The log confirms frontend=true, backend=false, workflows=false, db=false. Health, generation, DB-search routing and connector contract gates pass. Public build identity matches. Authenticated checks passed 42/42; saved-run/reproducibility checks passed 48/48 with four explicit original-chat coverage skips. See the redacted postdeploy and AfterRun JSON reports under `qa/20261107-hospital-readiness`.

Actual deployed browser checks:

- Settings content is now 550 px high with 1,661 px of content; wheel reaches scrollTop 1,111, exactly the bottom. Close stays visible; Escape dismisses. The local actual-component harness additionally tested keyboard Home/End with 25 synthetic rows and a 390×650 viewport whose dialog fits within bounds.
- Add connector from Models & LLMs → database setup exposes persistent Back, Cancel and Close. Close stays at y 68.75–100.75 after body scrolling. Back returns to kinds; Cancel restores the original Models & LLMs tab; Close returns to the exact originating project Instructions URL. Existing 64 sources, 11 model references and the existing private connection remain present; no connection was changed.
- Files detail now scrolls: 692 px viewport / 788 px content, scrollTop 95.5 at its browser maximum. The final YAML MIME card ends at y 675.45 within the 722 px viewport. Actual YAML content is readable; unavailable dimensions remain dashes.
- Switching to Chinese uses the same deployed app/layout. Project bar, membership actions, Settings Appearance/Close and new built-in output examples are translated. The original stored user format and skill catalogue remain present. Server-supplied expert names/descriptions remain their original content; this is not a claim of complete translation coverage. The test restores English.
- Run Manager opens the saved completed scdownstream record and collapses its list. The panel shows Completed 100%, actual saved findings/outputs and run actions; it does not relaunch. The previous synthetic chat remains available. The record has no original chat link, so this does not establish recovery of an original conversation.

## Deeper run/navigation follow-up — prepared for next UI sync

The browser found that Back-to-kinds left the previous setup form beneath the picker. The follow-up hides underlying forms/catalogues while choosing a kind; Cancel still restores the original tab.

Source-and-mounted-component checks found and repaired cancellation being coerced to failure in the embedded AfterRun report, loss of actual task error/job/work-directory fields through the step adapter, and failed-run Resume posting no edited parameters. The new report receives cancellation, recorded failure logs, failed step names and autofix history; cancellation suppresses failure diagnosis and cancels its outstanding explanation request. Resume forwards current effective parameters through the verified Node→Galaxy resume contract; API failure retains the draft. No workflow is launched by these regression tests.

Final combined regression suite: 2,452 passed / 42 skipped. TypeScript and production build are passed for this final follow-up. These checks do not close the known notebook runtime or pending demo-backend release.

Known boundaries: offline events not received by a client have no replay archive; older timestamp-less/event-ID-less progress cannot be reconstructed safely; process-level cancelled states still use the older phase-state vocabulary, though the overall cancelled run is now distinguished. Missing source process metadata cannot be manufactured into exact per-phase status. Language changes currently reload the application, so unsaved transient form/selection state is not guaranteed across a switch. These remain explicit follow-ups.

Final pre-sync prediction: this follow-up changes only frontend rendering/requests and QA documents. It must retain Galaxy, database and run files unchanged. Public build identity must equal its pushed commit. Connector kinds must show neither the old database form nor the old provider catalogue, and Cancel must restore the source tab. Existing saved runs must reopen with their recorded status and outputs. Cancellation/edited-resume semantics are covered by mounted regressions; no new expensive run is launched solely to test them. Existing authenticated API and saved-run audits must remain green. No IT-only path, backend upload or Docker-socket grant is invoked.
