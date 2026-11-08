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

## Final deployment verification

Pending completion of the combined checks and supported sync script.
