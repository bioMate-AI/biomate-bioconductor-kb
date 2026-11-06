# Design handoff execution plan

Date: 2026-10-24. Status: QC fixes published in PR #298; first Problem 1 UI slice implemented.

## Takeover entry points

Start with [Claude Code takeover](20261024_CLAUDE_CODE_TAKEOVER.md) for worktree/transfer instructions or [Claude Design takeover](20261024_CLAUDE_DESIGN_TAKEOVER.md) for accepted decisions and next deliverables. The [portable accepted preview](design/20261024_workflow_response_preview.html) supersedes the earlier paused mockup.

## Scope and governing references

Execute the nine problems in `20261023_UI_DESIGN_PROBLEMS_FOR_CLAUDE_DESIGN.md`, one at a time. Each deliverable is a written component/pattern specification with regions, states, interactions, provenance requirements, existing token references, and acceptance scenarios. Follow with an implementation slice and verification before treating a problem as complete.

Source precedence: `reference/claude_design/data_centroid_design_v2/SIMPLIFICATION_DECISIONS.md` overrides older specs/prototypes. The manifest's Group A describes requirements; Group D supplies visual references; Group B/C supply examples and their evidence limitations. The composition architecture governs harness integration, not new product screens.

Keep four entry points, exactly three after-run tabs, the five user-facing evidence classes, existing file identities/versions, and a single owner for each control. Scientific claims carry entity identity and source; predictions carry context, uncertainty or applicability as available. Missing metadata is explicitly unavailable, never inferred as validation.

## Ordered work

| Order | Problem and deliverable | Implementation focus | Completion evidence |
| --- | --- | --- | --- |
| 1 | One coherent workflow response: intent, run reference, activity, answer | `chat-interface.tsx`, `chat-progress-fold.tsx`, `chat-message.tsx`, `chat-with-artifacts.tsx` | Running → findings pending → ready; gate/failure/cancel; reload; multiple runs; narrow pane; keyboard |
| 2 | Entity-aware findings and shared provenance | `findings-card.tsx`, `AfterRunReport.tsx`, findings generator/parser and server contracts | Real names/SMILES survive end to end; unresolved identity honest; source links resolve; repeated source displayed once |
| 3 | Reproducibility record as one audit document | `AfterRunReport.tsx`; spec 12 | Six expandable sections; immutable original; bundle availability/error; absent sections distinguished from empty results |
| 4 | Neatness specification and surface deviation inventory | Existing tokens, cards, tables, badges, tabs, empty states | Light/dark, narrow/wide, focus and contrast inspection; no duplicate controls |
| 5 | Molecular Table/Figure/Structure variants | `step-output-preview.tsx`, existing viewer registry | Linked structure/confidence/PAE; pose + score; depiction grid; ΔΔG ± SEM/cycles; objective units; censored/OOD/held/missing states |
| 6 | Shared run-step schema with domain examples | Workflow viewer and spec 13 | ADMET/docking/FEP/generative/stability/novelty/training: actual tool/version, two supported parameters, output references and status |
| 7 | QC gate and remediation states | `auto-loop-panel.tsx`, workflow panel | Pass/advisory/halt/regulatory halt; diff; retry count/window; authorized overrides; complete audit; no automatic human approval |
| 8 | Durable campaign in Models → Rounds | `models-panel.tsx`, campaign API/persistence audit | Round timeline; bench waiting without spinner; order/intake; partial/censored/no-data; refit creates model version |
| 9 | Ranked-entity evidence-answer variant | Search answer and evidence contracts | Tier/conflict/veto; channel provenance; OpenTargets ranking boundary; missing/disagreeing evidence |

Problem 4 supplies the comprehensive consistency inventory; earlier slices must already use existing design tokens. Domain rows and exemplars are data fixtures, not per-workflow UI templates.

## Per-problem workflow

1. Read the relevant spec sections, prototype, current code, and real example sources.
2. Record existing behavior and any missing data/API contract. Distinguish verified implementation from a requirement or proposed extension.
3. Write the spec, including accessibility, loading/error/partial states and exact visual-reference mapping. Where the source design lacks a primitive, supply an explicit design reference before coding its visual treatment.
4. Implement the smallest complete reusable slice. Preserve unrelated working-tree changes.
5. Run focused behavior tests and inspect the UI in relevant states. For backend changes, verify identity/source propagation, authorization, and failed-data behavior. Record limitations honestly.
6. Update this tracker with delivered files, checks and remaining dependencies.

## Engineering counterpart and decisions to resolve

- LLM-authored `blocks` require a typed catalog, provenance validation, registered renderers, a feature flag and relevance comparisons. Do not label a visual grouping change as completion of that migration.
- Preserve Summary / Outputs / Reproducibility record navigation: the architecture's reference to replacing fixed tabs must be interpreted as replacing result-body rendering, consistent with the accepted simplification decisions.
- Run ID ↔ invocation ID grouping is implemented with explicit aliases and initiating-message identity; verify full live restore and concurrent runs before considering the lifecycle complete.
- New progress/findings preserve ownership metadata. Unknown legacy records remain unattached; full backend session-restore behavior still requires live verification.
- Existing completion polling is bounded; the UI must distinguish findings still pending from failed/unavailable. No indefinite spinner or false ready state.
- Campaign persistence, order submission, report editing and model registration must be checked against APIs before enabling controls. Peptide research-script loops and synthetic KD demonstrations must remain visibly distinct from platform-native capabilities.
- d5–d7 examples have documented evidence gaps; b1 sources diverge and routing is documented as dormant. Do not invent worked-example values or imply deployed training behavior.

## Tracker

- Cross-workflow gate fixes implemented locally: assessment/execution separation in both workflow UIs, normalized reports/exports, NCA dispatch, truthful unavailable states, recorded/reconstructed QC persistence, confirmed pause responses and removal of CryoSPARC placeholder measurements. See `20261024_CROSS_WORKFLOW_QC_GATE_AUDIT.md` for changes and validation. This does not mark the remaining nine-problem design work complete.

- Accepted completion behavior: a finished standalone ADMET screen reports QC flags as findings, not a pause requiring remediation. Remove completed-run exclusion/threshold suggestions and Resume/Cancel framing. Document compound identities, measurements, thresholds, outcomes and sources in report/output files. The completed-response preview now supersedes the paused mockup.

- Requirements/source review: initial pass complete across the four Group A documents, architecture, simplification decisions, specs 06/07/14 and chat code. Other detailed specs are read at their respective step.
- Problem 1: first production slice implemented. Explicit run ownership groups inline unfolded progress and completion answers; persisted aliases, replay deduplication, stable stream identity and reader-controlled scrolling are covered. The complete plan stays inside the unfolded progress stream and the answer owns response controls. See `20261024_WORKFLOW_RESPONSE_DESIGN_SPEC.md` for exact scope and remaining lifecycle checks.
- Completed-response preview: shows named DILI findings and the batch QC summary, with source/report navigation and no completed-run hold or remediation suggestions. The preview is simulated; production message/stream components are also inspected separately in a local browser harness.
- Problems 2–9: queued in the order above.
- Remaining: live workflow lifecycle verification for Problem 1; entity-aware findings and source propagation next (Problem 2). No claim that all nine problems are complete.
