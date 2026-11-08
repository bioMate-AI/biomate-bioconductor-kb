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

Pending reviewed commit, supported sync and post-deploy API/browser checks. The earlier successful deployment does not establish that these follow-up changes are live.
