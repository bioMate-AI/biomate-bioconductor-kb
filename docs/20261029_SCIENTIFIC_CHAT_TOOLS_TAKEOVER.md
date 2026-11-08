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

TypeScript passed. The full frontend suite passed with 1,977 tests and 31 pre-existing skips across 172 files. The initial restricted run exposed localhost socket-denial errors; rerunning with localhost access resolved those errors without changing the tests. Ten pure scientific boundary/dispatch tests and six research-context/reference tests cover invalid inputs, failed/malformed responses, complete citation propagation, uncited fallbacks, target evidence and provider parity. Five target contract tests plus the existing real orchestrator smoke test pass locally; the target-ID pytest collection also passes all six collected tests.

The exact final backend modules imported in an isolated process under dev's Python 3.9.25 without replacing deployed files. A real orchestrator check in that process also passed the explicit-candidate filter and ranking metadata assertions. SSM preflight command `1f575b73-1409-4eb9-9d89-1c736fa29343` returned `PY39_CONTRACT_PASS`.

The full suite also caught stale catalog documentation: SQLite reports 4,223 workflows, 42 domains and 69 chains. The October 20 indexing report documents that growth. `CLAUDE.md` and the equality guard were reconciled with those facts; the historical validated subset remains explicitly dated, not conflated with catalog size.

## Deployment review

The change adds two read-oriented chat tools and corrects the existing target route's ranking policy. It does not enable external tool ingestion, create accounts, change credentials or launch Batch jobs. Target ranking requires available evidence channels; OpenTargets ordering is conditional on that channel succeeding. Research success requires the backend's actual prose and references, not HTTP status alone. Expected smoke results are: target identification returns an explicit ranking mode, source provenance and only requested genes; a review returns grounded prose with unchanged references, or an honest error/uncited fallback. A passing engine smoke is not proof that a user-facing model selected the tool.

Before sync: finish exact-source Python 3.9 preflight, inspect the complete diff, commit only this work and run the standard sync. After sync: verify source hashes in running containers, run the target backend smoke without LLM/Batch expenditure, then exercise both tools through one authenticated fixture chat session. Do not register a replacement user, reset a password or use an admin fallback to call the chat path.

## Remaining acceptance checks

- Actual chat tool selection, output rendering and survey quality through the shared fixture account.
- Citation metadata/source verification on the live generated review; reference existence alone does not establish claim support.
- A bounded docking run after code review, including real receptor self-fetch and output registration. The prior handoff established deployment and unit checks, not successful docking computation.
- The full small-molecule chain's ranking turn and output registration, and the peptide multi-phase execution.
- The wider world-model audit: project/session instructions and datasets, cross-project isolation, module/domain knowledge and tool/source selection. Catalog search and two new tool definitions do not establish complete awareness of every context channel.

Neither this shell nor the dev frontend has a fixture-password environment variable configured. The existing fallback in `frontend/e2e/project-workspace.e2e.ts` was subsequently found and accepted by the fixture login. It is loaded into the child test process without displaying or committing its value; no credential was generated or reset.

The live API journey is `node scripts/verify_scientific_chat_tools.cjs`. It requires `E2E_FIXTURE_PASSWORD`, logs in once, creates one disposable project, runs the target and review turns, and deletes that exact project afterward. Target acceptance requires a real tool call and non-error, OpenTargets-backed result. Review acceptance requires either a real `write_review` result or the existing research path's successful cited `researchResponse` artifact; fluent prose alone is insufficient, and explicit tool errors cannot be hidden by a fallback. The execution path is recorded separately, so automatic research does not count as exercising the explicit tool. Six offline parser/assertion tests pass. Running without the password exits 2 before any network call, not a skipped/pass result. Visual rendering and independent scientific assessment remain separate.

The first live attempt authenticated but failed in harness setup because project creation returns `{project: ...}`, not a root `id`. The wrapper handling was fixed and regression-tested. The one project created during that attempt was resolved by its exact creation window and name and reused, rather than creating another. Both reports are retained under `docs/qa/`. That disposable project was deleted afterward; the QA chat record remained available for auditing.

Docking test review found a silent pass when the workflow file was absent. That condition now fails. A new test extracts and executes the real embedded `fetch_pdb` helper with only the external downloader substituted, checks the canonical RCSB URL, and checks the `receptor_pdb_file` environment binding. Eight docking tests pass. These are still not proof of a successful Batch docking run.

The shared branch was already 607 commits ahead of upstream at takeover; this task does not authorize publishing those unrelated commits.

## Live backend result

After the standard sync restarted Galaxy and its health check passed, SSM command `ebea44bb-d4ad-4cc1-b79f-94a2609dff2b` verified all three deployed backend SHA256 hashes against local sources and called the actual target HTTP endpoint. With disease `MONDO_0005105`, candidates BRAF/NRAS/TP53 and `use_llm:false`, OpenTargets returned BRAF 0.8533, NRAS 0.7794 and TP53 0.7178. All three were `nominated`, with `ranking.mode=primary_channel`, `primary_channel=genetics_ot`, real OpenTargets provenance and no unscored requested genes. These are association scores, not clinical probabilities or proof of superiority over OpenTargets. This probe used no LLM and launched no Batch job.

The main sync completed healthy for `3d6e5c5a5`: public build commit verified, Galaxy workflow-generation smoke passed, intent-driven database-search routing passed, and the connector contract reported zero failed or inconclusive checks. The legacy migration helper emitted `relation users already exists` before printing `Migrations applied`; that message is not evidence that every migration applied. This change introduces no database migration.

## Provider parity follow-up

The new guard enumerates every advertised built-in tool and requires dispatch in both provider loops. It reproduced a missing `query_domain_knowledge` case in the Gemini loop. The missing case now delegates to the same `_toolQueryKnowledge` method used by Anthropic and joins the citation corrections below in a frontend-only sync after the live journey. Expected smoke: Gemini dispatch is present, numbered research sources stay intact, and health checks remain green. No backend, database or workflow change is required for that follow-up.

## Live chat audit and scientific output corrections

The target chat tool ran successfully in 55.8 seconds with OpenTargets and LLM reasoning. Manual review of its user-facing answer nevertheless found two interpretation errors: LLM agreement was described as independent literature corroboration, and 200 retrieved target records were described as a patient cohort. The frontend projection now names that count `n_targets_retrieved` and explains the legacy `genetics_ot` name, channel-agreement tiers and lack of independent experimental evidence. No score was changed to improve the demo.

The review request used the existing research-agent route rather than calling `write_review` again. Logs confirm a successful research response. The chat rewrite then emitted an extra bibliography entry, “Inferred from … consensus,” as though it were a paper. The recovered answer is in `docs/qa/20261029-scientific-review-recovered.json`. The concrete context bug was `answer.slice(0,4000)` and `citations.slice(0,8)`: later numbered references could survive in prose while their source records were hidden from the model.

The fix passes the complete research answer, cited records and returned abstracts into chat, distinguishing clinical, preclinical and cross-disease evidence. Research rewrites are buffered until their reference boundary is checked. The displayed bibliography comes from returned metadata, never invented entries. Invalid markers or unsupported bibliography entries fall back to the original grounded answer. The same guarded text is used for chat persistence; a `write_review` result also updates the structured evidence artifact. This protects reference integrity, not universal claim support.

NCBI metadata checks confirmed all four PMID/title pairs in the recovered answer. Abstract checks established that [PMID 42277540](https://pubmed.ncbi.nlm.nih.gov/42277540/) concerns non-melanomatous tumors, and [PMID 40744388](https://pubmed.ncbi.nlm.nih.gov/40744388/) reports in vitro/in vivo work. Those sources do not independently establish melanoma clinical efficacy for that combination. Source existence and passing software tests do not establish support for every biomedical claim; post-sync review must check that distinction.
