# Target identification and review writing chat tools

Claude Code stopped with uncommitted `identify_targets` and `write_review` definitions and handlers in `frontend/server/galaxy-assistant.ts`. This continuation completes their scientific response contracts and prepares them for dev verification. Docking execution, fine-tuning and tool-discovery activation are separate acceptance tasks, not established by these tests.

## Implementation

- Both model loops dispatch the new tools through the request-scoped Galaxy client. The original raw `fetch` handlers omitted per-user authentication and ignored configured client overrides.
- Research responses require application-level success, nonempty prose and a valid reference list. HTTP 200 with `success:false` is a failure. An uncited benchmark fallback is identified as uncited, not presented as a literature review.
- Citation order, abstracts, confidence, retrieval statistics, source disagreements and methods survive the chat boundary. The tool does not trim references and leave dangling numbered citations. Missing numeric reference markers fail the boundary check.
- The proposed citation-count option was removed from the new tool: the backend does not enforce it as a final reference limit. Returning all grounded references preserves the answer/reference mapping.
- Target responses retain source provenance, conflicts, actual ranking mode and failed channels. Harmonic-sum values stored under the legacy `per_channel_z` name are normalized scores, not statistical z-scores.
- The target HTTP route now uses the orchestrator's documented default instead of overriding it with a fused ranker. OpenTargets supplies the ordering when available. Missing or failed OpenTargets evidence is explicitly reported; no improvement over OpenTargets or clinical validity is claimed.
- Explicit candidate-gene requests constrain returned targets. Unscored requested genes are listed rather than assigned fabricated scores. Optional planner-generated candidates do not constrain the user's search.
- Offline mode does not advertise these two network-backed tools.

## Verification

TypeScript passed. The full frontend suite passed with 1,969 tests and 31 pre-existing skips across 171 files. The initial restricted run exposed localhost socket-denial errors; rerunning with localhost access resolved those errors without changing the tests. New pure boundary tests cover invalid inputs, failed/malformed responses, citation preservation, uncited fallbacks, target evidence and both dispatch sites. Five target contract tests plus the existing real orchestrator smoke test pass locally.

The exact final backend modules imported in an isolated process under dev's Python 3.9.25 without replacing deployed files. A real orchestrator check in that process also passed the explicit-candidate filter and ranking metadata assertions. SSM preflight command `1f575b73-1409-4eb9-9d89-1c736fa29343` returned `PY39_CONTRACT_PASS`.

The full suite also caught stale catalog documentation: SQLite reports 4,223 workflows, 42 domains and 69 chains. The October 20 indexing report documents that growth. `CLAUDE.md` and the equality guard were reconciled with those facts; the historical validated subset remains explicitly dated, not conflated with catalog size.

## Deployment review

The change adds two read-oriented chat tools and corrects the existing target route's ranking policy. It does not enable external tool ingestion, create accounts, change credentials or launch Batch jobs. Target ranking requires available evidence channels; OpenTargets ordering is conditional on that channel succeeding. Research success requires the backend's actual prose and references, not HTTP status alone. Expected smoke results are: target identification returns an explicit ranking mode, source provenance and only requested genes; a review returns grounded prose with unchanged references, or an honest error/uncited fallback. A passing engine smoke is not proof that a user-facing model selected the tool.

Before sync: finish exact-source Python 3.9 preflight, inspect the complete diff, commit only this work and run the standard sync. After sync: verify source hashes in running containers, run the target backend smoke without LLM/Batch expenditure, then exercise both tools through one authenticated fixture chat session. The live fixture password is currently absent from this shell; do not register a replacement user, reset a password or use an admin fallback to call the chat path.

## Remaining acceptance checks

- Actual chat tool selection, output rendering and survey quality through the shared fixture account.
- Citation metadata/source verification on the live generated review; reference existence alone does not establish claim support.
- A bounded docking run after code review, including real receptor self-fetch and output registration. The prior handoff established deployment and unit checks, not successful docking computation.
- The full small-molecule chain's ranking turn and output registration, and the peptide multi-phase execution.
- The wider world-model audit: project/session instructions and datasets, cross-project isolation, module/domain knowledge and tool/source selection. Catalog search and two new tool definitions do not establish complete awareness of every context channel.

The dev frontend also has no `E2E_FIXTURE_PASSWORD` or `E2E_TEST_PASSWORD` configured. Fixture chat verification therefore requires the existing test credential; a new account is not an acceptable substitute.

Deployment and live results will be appended below after verification. The shared branch was already 607 commits ahead of upstream at takeover; this task does not authorize publishing those unrelated commits.
