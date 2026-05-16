# Workflow Phase-Split Audit — biomate-ai-tools (2026-05-15)

## Context

The Tier 0 demo recordings (T01–T05) were broken because the underlying workflows
ran with default parameters instead of the LLM-extracted values from the user's
natural-language query. Three root-cause bugs were identified and fixed:

1. **Bug 1 — LLM→workflow param key remap** — `WORKFLOW_PARAM_ALIASES` +
   `remapInlineParametersForWorkflow()` added in `frontend/server/galaxy-assistant.ts`
2. **Bug 2 — null-string fallthrough** — `params.X = 'null'` no longer survives
   `.upper() or 'DEFAULT'`; 4 `.nf` files patched
3. **Bug 3 — silent Run dispatch** — `clickRunOnly` in `frontend/e2e/demo-helpers.ts`
   now throws on no-visible / disabled / no-execute-POST / no-runId

While preparing the demo re-record and the cryo-style audit harness
(modeled on `frontend/e2e/cryoem-stepwise-and-output.e2e.ts:997` — the CS-3+4+5+10+12+13+14
super-merged test), a **deeper structural gap** surfaced:

**None of the Tier 0 workflows produce per-phase UI cards with real-time
`data-status` transitions, because they are all single-process `.nf` files.**

The workflow-panel UI keys off the step parser in
`backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:691–763`:
phase_group is assigned **per process block**, not per `// [Phase X]` comment.
A 1-process workflow always renders as exactly 1 phase card, no matter how
many `// [Phase A] … // [Phase B]` comments precede it.

## Audit results

Scanned every `main.nf` under `backend/nf-core-workflows/modules/biomate-ai-tools/`
and `backend/nf-core-workflows/subworkflows/`.

### biomate-ai-tools custom workflows (19 total)

| Category | Count | UI behavior today | Workflows |
|---|---|---|---|
| Single-proc, no phase comments | **11** | 1 generic phase card | af3, alphafold, atlas_expression_query, **bispecific_format_triage (T01)**, boltz, chai1, esmfold, **glp1_modality_bakeoff (T04)**, **in_vivo_base_edit_design (T03)**, **in_vivo_cart_codesign (T02)**, **modality_triage (T05)** |
| Single-proc, has phase comments | **6** | Still 1 card (decorative comments) | aav_serotype_selection, adc_design (4 fake phases), aso_gapmer_design, cart_construct_design, protac_design (5 fake phases), sirna_design |
| Multi-proc, no phase annotation | **8** | N cards under generic phase groups (keyword fallback) | cryo_heterogeneity (4 proc), drugclip (2), profam (2), protein_dynamics (3), protrek (2), scfv-pmpnn (2), state (2), syncraft (2) |
| Properly multi-proc + phased | **1** | Real per-phase cards | mrna_therapeutic_design (2 proc, 2 phases) |

### Upstream nf-core workflows (~150)

`backend/nf-core-workflows/<pipeline>/` are vendored nf-core projects
(sarek, rnaseq, scrnaseq, atacseq, chipseq, differentialabundance, methylseq,
proteinfold, raredisease, etc.). These are already decomposed into proper
modules/subworkflows and use the generic keyword phase rules
(`_GENERIC_PHASE_RULES` in `ai_assistant.py`). **No annotation work needed.**

### Tier 0 demo set (T01–T05) — worst case

All 5 Tier 0 demo workflows are in the "single-proc, no phase comments" group.
This is why the cryo-style audit checklist (per-phase `data-status` transitions,
per-phase output file chips, per-phase Skip / Pause-After / Run-Step controls)
**literally cannot apply** to these workflows in their current form.

## Implication for the cryo-style audit pattern

The cryo super-merged test (`cryoem-stepwise-and-output.e2e.ts:997`,
CS-3+4+5+10+12+13+14) asserts:

- `data-testid^="phase-group-"` cards exist and transition idle → running → completed
- Each card has output-file chips (`phase-card-preview-btn-*`, `phase-card-download-btn-*`)
- Inline `StepOutputPreview` opens per-phase for `.star` / `.png` / `.log` / `.mrc`
- Per-phase Skip / Pause-After / Run-Step / param-override buttons render
  on `pending` cards only
- `findings-card` polls the `/api/workflows/runs/:id/findings` endpoint
- `button-analyze-results` and `button-download-methods-report` render after completion

For T01–T05 in their current single-process form, **only the last two
(findings + methods-report) can be asserted**. Everything else requires
multi-process decomposition first.

## Refactor scope

| Scope | Workflows | Estimated effort | Demo impact |
|---|---|---|---|
| **A — Tier 0 only** | T01–T05 (5 workflows) | ~15 hrs (3 hrs/wf) | Demos can claim per-phase real-time UI |
| **B — All single-proc** | 17 single-proc biomate-ai-tools | ~50+ hrs | All custom workflows render consistently |
| **C — Tier 0 + cheap multi-proc annotation** | 5 refactor + 8 annotation-only | ~20 hrs | Tier 0 + all currently-multi-proc workflows consistent |

Each Tier 0 refactor requires:

1. Identify logical phases (3–4 per workflow)
2. Split monolithic Python heredoc into N sequential process blocks
3. Define intermediate output files (so per-phase UI shows artifacts)
4. Wire Nextflow channels between processes
5. Add `// [Phase X] Label` comment before each process
6. Re-sync `workflow_json` in `backend/database/galaxy_ai_tools.db`
7. Test locally + AWS Batch + verify UI renders N phase cards

## Recommended sequencing

1. Pilot T01 (bispecific_format_triage) — establish the pattern with a real refactor
2. Audit harness — write the T01-version of the cryo super-merged test
3. Run audit, fix root-cause failures (per CLAUDE.md "Review Code Before Testing")
4. Replicate pattern to T02–T05 in parallel once T01 passes
5. Re-record demos with form-fill pre-assertions (Bug 3 fix already in place)
6. Defer Scope B/C until Tier 0 ships

## Why this wasn't caught earlier

The demo videos rendered (Playwright wrote the .webm files), the "tests passed"
(`clickRunOnly` swallowed dispatch failures — Bug 3), and the AWS Batch jobs
ran (with NULL/default params — Bug 2 + Bug 1). Nothing in the existing test
suite asserted that:

- The form had the LLM-extracted values populated **before Run**
- The workflow output reflected the user's actual targets (not workflow defaults)
- The UI exposed per-phase progress (because phase decomposition was never required)

The fixed audit harness must assert all three.

## Files / locations referenced

- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:691–763` — step parser, phase_group assignment
- `frontend/e2e/cryoem-stepwise-and-output.e2e.ts:997` — gold-standard audit pattern
- `frontend/server/galaxy-assistant.ts:650,725,2422,3112` — Bug 1 fix (param remap)
- `frontend/e2e/demo-helpers.ts` — Bug 3 fix (hard-fail clickRunOnly)
- `backend/nf-core-workflows/modules/biomate-ai-tools/{modality_triage,bispecific_format_triage,in_vivo_cart_codesign,in_vivo_base_edit_design}/main.nf` — Bug 2 fix
- `docs/20260514_demos_broken_audit.md` — prior root-cause analysis

## Open question for product direction

Should the demo set demonstrate per-phase real-time UI (requires refactor) or
accept a single-status "running → completed" badge for now and ship simpler
demos sooner? This is a product decision, not a technical one — both paths
are deliverable; the refactor path is 15+ hours of work that improves not
just the demos but the day-to-day BioMate UX for every Tier 0 use case.
