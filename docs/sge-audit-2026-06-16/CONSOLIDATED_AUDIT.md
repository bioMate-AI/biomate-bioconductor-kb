# Consolidated Audit — 2026-06-16 → 2026-06-17 (dev)

Three concurrent investigations against `https://dev-public.biomate.ai`:

1. **After-run audit** — 3 of 5 tier-0 workflows (T02, T03, T05) executed to completion; all 7 after-run tabs walked
2. **ParamClarificationCard E2E** — schema-grounded extraction's clarification card proven in browser
3. **P0 root-cause fix** — wired `s3_output_files` through to AfterRunReport (was undefined → empty)

## Headline

| | |
|---|---|
| Workflows executed end-to-end on dev | 3 (T02, T03, T05) |
| ParamClarificationCard render on dev | ✅ confirmed (enum-violation path) |
| **Bug fixed** | P0: Outputs tab forever empty (1-line fix; verified root cause via direct Galaxy API call) |
| Bugs still open (P1, P2) | 2 |

## What completed

### After-run runs

| Workflow | Status | Wallclock | Tabs visible | Params canonical | Outputs registered |
|---|---|---|---|---|---|
| T02 `in_vivo_cart_codesign` | ✅ completed | 12.7 min | 3 / 7 | ✅ 5 keys | ❌ none (P0) |
| T03 `in_vivo_base_edit_design` | ✅ completed | 27.0 min | 3 / 7 | ✅ 5 keys | ❌ none (P0) |
| T05 `modality_triage` | ✅ completed | 4.8 min | 3 / 7 | ✅ 4 keys | ❌ none (P0) |
| T01 `bispecific_format_triage` | ❌ workflow gen refused | n/a | n/a | n/a | n/a |

**T01 separately blocked** — even with `intentOverride='workflow_generation'`, the downstream workflow generator returns *"Workflow generation is currently unavailable for this request"* and asks for reference antibody sequences. Different issue; bispecific generation has its own input gate.

### Schema-grounded extraction across workflows

Confirmed canonical-keyed params in Parameters tab for all 3 successful runs:

```
T02 in_vivo_cart_codesign:
   indication=DLBCL, persistence=transient, car_target=CD19,
   delivery_cell=T_cell, lnp_targeting=auto

T03 in_vivo_base_edit_design:
   target_gene=PCSK9, edit_goal=loss_of_function,
   indication=hypercholesterolemia, delivery=auto,
   editor_preference=auto

T05 modality_triage:
   target_gene=BCMA, indication=oncology, modalities=all,
   atlas_expression=null
```

Same systemic issues affect every run, so they're **module-wide, not T02-specific**.

## P0 root cause + fix (shipped)

Galaxy backend correctly populates `s3_output_files`. Direct probe on the most recently completed dev run returned:

```json
{
  "status": "succeeded",
  "s3_output_files": [
    {"s3_uri": "s3://biomate-nextflow-work/.../ivive_output.txt",
     "name": "ivive_output.txt", "size": 811, "extension": "txt"},
    ...
  ],
  "outdir": "s3://biomate-nextflow-work/..."
}
```

4 files registered backend-side. But UI shows "No output files registered yet" because **`nextflow-workflow-viewer.tsx` rendered `<AfterRunReport>` without forwarding the `outputs` prop**. Inside the component, `outputs = outputsProp ?? []` → always empty.

Compare: `chat-with-artifacts.tsx` (the *other* AfterRunReport callsite) does pass `outputs`, derived from the same `nextflowStatus.s3_output_files`. The viewer just never did.

**Fix:** mirrored the chat-with-artifacts derivation in the viewer. 1-line prop pass-through, ~20 lines of mapping. Committed in `9b342f1ff`.

## ParamClarificationCard browser proof

Test: `frontend/e2e/param-clarification.e2e.ts` — passes on dev in 57s.

**Scene:** send T02 query but with the user saying "B cells" instead of "T cells" (out of the enum `T_cell | NK_cell | macrophage`). Schema-grounded extractor catches the enum-violation and emits `paramClarifications`. The chat-interface metadata-whitelist fix (shipped in PR #10) forwards it. `chat-message.tsx` renders the card.

**Result** (`docs/sge-audit-2026-06-16/param-clarification/01-card-rendered.png`):

> *"A few details for in_vivo_cart_codesign before we run:*
> *You mentioned `B cells` for delivery_cell, but this workflow supports:*
> [T_cell] [NK_cell] [macrophage] · *Skip — I'll fill it in the panel"*

**This is the complete schema-grounded extraction value-prop proven in a real browser on dev.** Card renders, allowed-value chips are clickable, skip link is present, click on T_cell hides the card and the workflow panel stays mounted with the params.

## Open bugs

### P1 — Phases B/C/D never render `running`

Confirmed across all 3 successful runs (T02, T03, T05): Phase A correctly transitions `pending → running → completed`. B/C/D jump straight from `pending → completed`. The "watch each phase work" tutorial-demo value-prop fails.

Next: verify whether the backend SSE actually emits per-phase `running` events for B/C/D, or only A. If yes, throttle bug in `nextflow-workflow-viewer.tsx`. If no, the workflow definition chains phases too fast or the executor doesn't emit explicit running events for chained processes.

### P2 — Methods tab hidden

Direct probe of `/api/invocations/<id>/methods-report` on dev returns **HTTP 502** with body `{"error":"Methods report generation failed","details":"fetch failed"}`. The local-generation fallback in `routes.ts:4455` is throwing. Methods report should be writable from workflow definition + params alone — should not depend on outputs being registered.

Next: trace the local generation path. Likely an unmocked LLM call failing or a missing run-data lookup.

### Aside: T01 bispecific generation gate

Even with intent forced to `workflow_generation`, the bispecific workflow generator refuses with *"Workflow generation is currently unavailable for this request"*. Specific to `bispecific_format_triage`; doesn't affect T02/T03/T05.

## Artifacts in this PR

```
docs/sge-audit-2026-06-16/CONSOLIDATED_AUDIT.md       (this file)
docs/sge-audit-2026-06-16/after-run/                  (T02 — original)
docs/sge-audit-2026-06-16/after-run-T03/              (T03 evidence)
docs/sge-audit-2026-06-16/after-run-T05/              (T05 evidence)
docs/sge-audit-2026-06-16/param-clarification/        (card render proof)
frontend/e2e/after-run-audit.e2e.ts                   (parameterized by env)
frontend/e2e/param-clarification.e2e.ts               (enum-violation scene)
```

## What's still untested

- WorkflowDisambiguationCard render (needs a test hook to force `workflow_type='disambiguation'`)
- ParamClarificationCard `missing_required` path (only `enum_violation` proven)
- "Run again with edits" CTA round-trip
- Per-step output file preview tile (image / table / FASTA / VCF / text variants)
- Methods report DOCX content (blocked on P2)
- Download-all zip contents (blocked on P0 until fix syncs)
