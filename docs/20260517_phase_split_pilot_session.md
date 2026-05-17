# Phase-Split Pilot Session — Scope B in flight (2026-05-17)

Multi-day session executing Scope B from `docs/20260515_workflow_phase_split_audit.md`:
refactor every single-process biomate-ai-tools workflow into a multi-phase pipeline
so the BioMate panel UI can render per-phase cards with real-time `data-status`
transitions. Started after the Tier 0 demo recordings were found to be running
with default parameters (`docs/20260514_demos_broken_audit.md`).

## Completed

### Tier 0 demo workflows (5 + 1) — all refactored, DB-synced, pushed

| Commit       | Workflow                          | Phases | Phase labels                                                                                                  |
|--------------|-----------------------------------|--------|---------------------------------------------------------------------------------------------------------------|
| `409844dae`  | T01 bispecific_format_triage      | 4      | Mechanism Inference / Format Scoring / Composite Ranking / Report Synthesis                                   |
| `b9255f490`  | T02 in_vivo_cart_codesign         | 4      | Atlas Safety / LNP Tropism / Fratricide Check / CAR Construct                                                 |
| `a75ee1fd7`  | T03 in_vivo_base_edit_design      | 4      | Atlas Tissue / Editor Selection / Guide RNA Design / CMC Flag Emission                                        |
| `751b1338e`  | T04 glp1_modality_bakeoff         | 4      | Receptor Atlas Profile / Modality Scoring / Indication Weighting / Top Recommendation                         |
| `ebdaa8ade`  | T05 modality_triage               | 4      | Atlas Profile / CAR-T Viability / ADC + Bispecific Eval / Modality Ranking                                    |
| `ebdaa8ade`  | atlas_expression_query (chained)  | 3      | Data Fetch / Tissue Tabulation / Critical-Tissue Check                                                        |

Each refactor: split monolithic Python heredoc into N sequential Nextflow processes
with intermediate JSON outputs, channel-wired `tuple val(meta), path(intermediate)`
between phases, `// [Phase X] Label` comment immediately above each `process`,
module-level `CONTAINER_IMAGE` constant (function-style breaks Nextflow directive
parsing), Bug 2 null-string fallthrough fix in every Python heredoc, original output
filenames preserved by the final phase. All pass `nextflow inspect`. DB
`workflow_json` re-synced.

### Multi-proc annotation pass (8 workflows) — `a444f2f3b`

Comment-only `// [Phase X] Label` additions to already-multi-process workflows.
No logic changes. Cheap pass.

| Workflow            | Phases | Labels                                                                                          |
|---------------------|--------|-------------------------------------------------------------------------------------------------|
| cryo_heterogeneity  | 4      | cryoDRGN VAE / Latent + Volume / Pocket Scan / Summary                                          |
| drugclip            | 2      | Local VS / API DB Screen                                                                        |
| profam              | 2      | Variant Fitness / Novel Sequence Gen                                                            |
| protein_dynamics    | 3      | Ensemble Sampling / Cryptic Pocket / Summary + UMAP                                             |
| protrek             | 2      | Trimodal Search / Custom DB Embedding                                                           |
| scfv-pmpnn          | 2      | Antibody Seq Design / Structure + Confidence                                                    |
| state               | 2      | Perturbation Response / Cell Embedding Transform                                                |
| syncraft            | 2      | Single Mol Retrosyn / Batch Retrosyn Planning                                                   |

### Step parser path fix — pending commit

`backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py:_parse_nextflow_steps()`
did not include `backend/nf-core-workflows/modules/biomate-ai-tools/` in its
path-resolution candidates. The lazy step fetch
(`GET /api/nextflow/steps?nextflow_path=…`) returned `{"steps":{},"count":0}` for
every biomate-ai-tools workflow — so the UI rendered zero phase cards regardless
of how many processes the `.nf` actually defined.

Fix: added two candidates in the candidate list near line ~515:
```python
biomate_tools_root = backend_root / "nf-core-workflows" / "modules" / "biomate-ai-tools"
candidates += [
    biomate_tools_root / nf_filename,
    biomate_tools_root / nf_filename.split('/')[0] / "main.nf" if '/' in nf_filename
        else biomate_tools_root / nf_filename / "main.nf",
]
```

After HUP'ing gunicorn, all 6 Tier 0 workflows return correct step counts and
phase letters via the steps endpoint:

```
=== bispecific_format_triage ===     step_count: 4  (A/B/C/D)
=== in_vivo_cart_codesign ===        step_count: 4  (A/B/C/D)
=== in_vivo_base_edit_design ===     step_count: 4  (A/B/C/D)
=== glp1_modality_bakeoff ===        step_count: 4  (A/B/C/D)
=== modality_triage ===              step_count: 4  (A/B/C/D)
=== atlas_expression_query ===       step_count: 3  (A/B/C)
```

**This was the blocker** that would have made the audit harness fail with
"0 phase cards rendered" for every Tier 0 demo. Without this fix, the workflow
panel UI cannot show per-phase cards for any biomate-ai-tools workflow.

### Tier 0 audit harness — `edf41fa19`

`frontend/e2e/tier0-audit.e2e.ts` — 735 lines, ~115 assertions across 5 demos.
Per-demo coverage:
- Chat-stream emits `workflow_ready` with **remapped** inline params (catches Bug 1 regression)
- Form prefilled with LLM-extracted values **before Run** (catches the original demo bug)
- Expected number of `phase-group-` cards render with `data-status` attributes
- Click Run → first phase transitions `pending → running` (via `page.waitForFunction`)
- Any phase reaches `completed`
- Per-phase output file chips (`phase-card-preview-btn-*`) render after completion
- Inline `StepOutputPreview` opens on click (text/JSON/CSV)
- `/api/workflows/runs/:id/findings` returns real content (not just `pending`)
- `/api/invocations/:id/methods-report` returns content > 500 chars
- `button-analyze-results` + `button-download-methods-report` render after completion

No mocking — all calls hit the live backend. Auth: register a test user via
`POST /api/auth/register` with `termsAccepted: true, privacyAccepted: true`,
JWT injected as both `biomate_token` cookie and `Authorization: Bearer`.

**Not yet executed** — that's the next step.

## Blocked

### Subagent permissions on `backend/nf-core-workflows/modules/biomate-ai-tools/**`

Three parallel subagents (Scope B remainder) were spawned with explicit
instructions for the refactor work:

1. #7 — 6 decoratively-phased workflows (aav, adc, aso, cart_construct, protac, sirna)
2. #8 — 6 protein-modeling workflows (af3, alphafold, boltz, chai1, esmfold, mrna)
3. #9 — 8 multi-proc annotation pass

All three reported **Edit, Write, AND Bash all denied** for these paths. Only #9
was small enough to be completed by me directly. #7 and #8 remain undone — each
needs full Python-heredoc refactor across 6 workflows.

Drafts produced by subagents (before being blocked):

- **#7 phase plans**: aav (4: Capsid Scoring / Tropism / Capacity / Ranking),
  adc (4: Payload / Linker / DAR / ADMET+PK), aso (4: Validation / Design /
  Off-target / Ranking), cart_construct (4: scFv / Hinge+TM / Costim+CD3z / FASTA),
  protac (5: E3 / POI / Linker / bRo5 ADMET / Ternary), sirna (4: Validation / Design /
  Off-target / Ranking)
- **#8 phase plans**: af3 + chai1 (build from stub), alphafold + boltz + esmfold
  (split existing single-process), mrna (expand 2 → 4)

Both subagents read the T01 template and drafted complete content; only the
write step was blocked. Plans documented in subagent transcripts.

## Remaining Scope B work (12 workflows)

Tasks #7 + #8 — needs ~30 hrs of direct refactor since subagent automation is
blocked for these paths. Not demo-critical (none of T01–T05 use these
workflows), so deferrable.

## Remaining audit + demo work

- **Run audit harness** — currently the Galaxy backend on port 8081 has the
  path fix loaded (post-HUP), 5/5 Tier 0 demos return correct phase steps via
  curl. Frontend is on port 5000 with Bug 1 remap live. Workflows have been
  DB-synced. Ready to run: `cd frontend && npx playwright test tier0-audit.e2e.ts`
  but this triggers AWS Batch runs (~$1.50 + ~30 min per demo × 5 = ~$8 + 2.5 hrs).
  Per CLAUDE.md "Review Code Before Testing", review the audit file end-to-end
  before kicking off the full run; consider running just T01 first.
- **Fix root-cause failures** the audit surfaces.
- **Re-record T01–T05 demos** with form-fill pre-Run assertions; supersede
  the misleading 20260514 S3 videos with correction notices.

## Files changed this session

```
backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py             [step parser path fix — pending commit]
backend/nf-core-workflows/modules/biomate-ai-tools/
  ├── bispecific_format_triage/main.nf                            (T01: 4 phases)
  ├── in_vivo_cart_codesign/main.nf                               (T02: 4 phases)
  ├── in_vivo_base_edit_design/main.nf                            (T03: 4 phases)
  ├── glp1_modality_bakeoff/main.nf                               (T04: 4 phases)
  ├── modality_triage/main.nf                                     (T05: 4 phases)
  ├── atlas_expression_query/main.nf                              (T05 chain: 3 phases)
  ├── cryo_heterogeneity/main.nf                                  (annotated)
  ├── drugclip/main.nf                                            (annotated)
  ├── profam/main.nf                                              (annotated)
  ├── protein_dynamics/main.nf                                    (annotated)
  ├── protrek/main.nf                                             (annotated)
  ├── scfv-pmpnn/main.nf                                          (annotated)
  ├── state/main.nf                                               (annotated)
  └── syncraft/main.nf                                            (annotated)
backend/database/galaxy_ai_tools.db                                [DB synced — gitignored]
frontend/e2e/tier0-audit.e2e.ts                                    (new audit harness, 735 lines)
```

## Lessons that should outlive this session

- **The step parser only looks where it knows to look.** When adding a new
  workflow location, audit `_parse_nextflow_steps` candidate paths AND
  `_resolve_nextflow_path` AND any other path-resolution helpers in
  `ai_assistant.py` / `nextflow_executor.py`. The parser failing silently
  (returning empty steps) is the worst-case failure mode — no error, no log,
  just a blank UI.
- **Phase comments require multiple processes.** A `// [Phase A]` comment
  above a single-process workflow is decorative; the UI still renders 1 card.
  The step parser keys `phase_group` off the `process` block, not the comment.
- **Subagent permissions on `backend/nf-core-workflows/modules/biomate-ai-tools/`
  are tight.** All write tools (Edit, Write, Bash heredoc) were denied for
  parallel subagents but allowed for the main session. If parallelizing
  refactor work in this tree, do it from the foreground or grant explicit
  permission in advance.
- **Nextflow directive syntax: `container CONTAINER_IMAGE` (constant), not
  `container container_image()` (function-call).** The function-style is parsed
  as an unknown directive name. Caught at `nextflow inspect` time, before any
  Batch submission.
