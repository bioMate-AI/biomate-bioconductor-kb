# Researcher-Outreach Session — Summary

**Date:** 2026-06-17
**Branch:** `qc/coverage-and-rebuilds`
**Commits added today:** 11 (`64c3228be9` → `9d5b11cd6`)
**Status:** All deliverables verified live; no destructive operations; held per "do not sync."

## What was built (all verified live against Galaxy :8081 + Node :5000)

### Tier-0 drug-design metadata fixes (continuation of 2026-06-16 work)

| Layer | Before | After |
|---|---|---|
| `workflow_chains` rows for T01–T05 | ❌ none | ✅ ids 61–65 (T05 = 2-step atlas→triage to match `tier0-audit expectedPhaseCount=7`) |
| `qc_evidence.yaml` Citations tab | ❌ empty | ✅ 12 gates with verbatim DOIs from `Tier-0 Demo Requirement.md` §"Scientific-accuracy corrections" |
| `rationale_registry` (why?) anchor | ❌ no rows | ✅ 23 rows (4×4 + 7) all `confirmed: true` |
| Node proxy `/api/rationale/*` | ❌ 401 | ✅ added `routes.ts:4426` |
| `tier0-audit.e2e.ts` assertions | 9 per demo | +3 (citations, rationale, chain row) |

### Researcher chains — Dr. Degui Zhi (UTHealth, ZhiGroup org)

| Demo | Chain id | Workflow(s) | Real data path |
|---|---|---|---|
| **Z01** TorchGWAS on UDIP brain phenotypes | 69 | `torchgwas_udip_phenotype_scan` (4-phase) | shipped `examples/toy/` (64×12×3) + 1000G for realistic scale |
| ~~Z02 FDA~~ | ~~70~~ DEPRECATED | — | Upstream is paper-reproduction recipe, not inference; revisit only if lab provides `predict()` |

### Researcher chains — Dr. Zhongming Zhao (UTHealth, bsml320 org)

| Demo | Chain id | Workflow(s) | Real data path |
|---|---|---|---|
| **ZZ01** Tumor-reactive T-cell pipeline | 71 | 3-step (9 phases): `turep` → `scupa_polarization` → `immuneapp_hla_screen` | Sade-Feldman GSE120575 melanoma TILs for turep; Scupa blocked on license |
| **ZZ02** Single-cell GWAS for immune cell types | 72 | `scgwas_immune_cell` (3-phase) | **Repo `example/` ships Schizophrenia Pardinas 2018 + DER22 panel — zero data wrangling** |

### Chain narrator (closes 2026-06-16 handoff item)

- `NextflowExecuteRequest` accepts optional `chain_meta` dict
- `execute_nextflow` drops `chain_meta.json` in `work_dir` (local mode)
- `workflow_chain._run_chain` auto-computes `chain_meta` by parsing `.nf` header `// [Phase X]` markers + the next `process <NAME>` line
- `_resolve_rationale_id` in `nextflow_executor.py` now finds a sidecar on every chain-dispatched run → (why?) anchor lights up on each phase SSE event without any per-chain hand-wiring

Smoke-tested in dev shell:
```
torchgwas_udip_chain → 4 phase patterns extracted (TORCHGWAS_PHENOTYPE_QC, _KERNEL, _SCAN, _REPORT)
```

## Claude design handoffs

- `reference/claude_design/design_handoff_zhi_lab/Zhi-Lab Demo Requirement.md` — Z01 (4-phase; FA brain phenotypes anchor)
- `reference/claude_design/design_handoff_zhao_lab/Zhao-Lab Demo Requirement.md` — ZZ01 (9-phase multi-tool showcase) + ZZ02 (single tool)
- Both inherit the tier-0 8-beat structure + 480×120 tip-card style
- Methodology-blue (#2563eb) outcome-card band distinguishes researcher-partner demos from BioMate-native modality demos
- UTHealth joint 4-demo playlist plan (Z01 + ZZ02 + Z02 + ZZ01) with cross-references in tip text

## Tests

`frontend/e2e/researcher-chains-audit.e2e.ts`:

- **`@meta` suite — 3/3 PASS** against live stack (`citations` ≥ 1 per workflow + `rationale_text` curated + sanity substring)
- **`@dispatch` suite — scaffolded but `test.describe.skip`** until real-data integration lands

`frontend/e2e/tier0-audit.e2e.ts` extended:
- 5 tier-0 demos × +3 assertions (#10/#11/#12)
- Will pass live on next full run

## Researcher-fit assessments

- `docs/20260617_RESEARCHER_FIT_DEGUI_ZHI.md` — full survey: 5 Tier-A drop-ins (TorchGWAS, RaPID, ~~FDA~~, Med-BERT, UDIP-ViT), 14 Tier-B (no LICENSE), 3 Tier-C (RaPID2, FRAME, RLBWT not found)
- `docs/20260617_RESEARCHER_FIT_ZHONGMING_ZHAO.md` — full survey: 6 Tier-A (turep, NetBCE, ImmuneApp, CytoRescue, fadvi, scGWAS), 11 Tier-B, 4 Tier-C
- Cross-researcher synergy table (GWAS / Alzheimer's / EHR / drug discovery)

## Practical 4-week demo schedule

| Week | Action | Cost |
|---|---|---|
| 1 | Wrap **scGWAS** real-data using shipped `example/`. Record ZZ02 demo. | Dev time only, no GPU |
| 1 | Wrap **TorchGWAS** with shipped `examples/toy/` for smoke + 1000G + simulated phenotypes for realistic scale. Record Z01 demo. | ~30 GPU-min per run |
| 2 | Apply for UKB credential (parallel; ~3 mo cycle) | Free |
| 3 | Wrap **turep alone** with Sade-Feldman GSE120575. Record ZZ01-stub. | ~30 GPU-min |
| 4 | Outreach to both labs with 3 working demos + asks: (a) Scupa MIT license, (b) FDA clean inference entry point, (c) UKB credential sponsorship | — |

## Verified-today open items

- **Scupa license** — needed for ZZ01 Step 2 (NOASSERTION on bsml320/Scupa)
- **FDA inference entry point** — needed before Z02 wrap viable
- **UKB credential** — needed for Z01 paper-faithful demo (3-month cycle)
- **`chain_meta` SSE end-to-end** — auto-write works locally; needs verification on AWS Batch S3 mode (currently sidecar skipped in S3 mode)

## What did NOT happen this session (deferred)

- Cherry-pick to `integration/next-phase` + push to remote (held per "do not sync")
- Real-data wrap of any tool (scaffolding only; .nf files emit placeholder JSON)
- Model-card workflow-type prototype (2-day proposal documented, not built)
- Outreach emails to the labs (drafted in researcher-fit docs as one-paragraph pitches; not sent)

## Files added/changed this session

```
backend/config/qc_evidence.yaml                  (+12 tier-0 + 3 Zhi + 7 Zhao gates)
backend/config/rationale_mapping.yaml             (+5 tier-0 + 2 Zhi + 2 Zhao chains; 23+8+12=43 rows)
backend/scripts/add_tier0_drug_design_chains.py   (new)
backend/scripts/add_zhi_lab_chains.py             (new)
backend/scripts/add_zhao_lab_chains.py            (new)
backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py  (chain_meta hook)
backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py     (_compute_chain_meta + pass-through)
backend/nf-core-workflows/modules/biomate-ai-tools/torchgwas_udip_phenotype_scan/main.nf  (new)
backend/nf-core-workflows/modules/biomate-ai-tools/turep/main.nf                          (new)
backend/nf-core-workflows/modules/biomate-ai-tools/scupa_polarization/main.nf             (new)
backend/nf-core-workflows/modules/biomate-ai-tools/immuneapp_hla_screen/main.nf           (new)
backend/nf-core-workflows/modules/biomate-ai-tools/scgwas_immune_cell/main.nf             (new)
frontend/server/routes.ts                         (+/api/rationale proxy)
frontend/e2e/tier0-audit.e2e.ts                   (+#10/#11/#12)
frontend/e2e/researcher-chains-audit.e2e.ts       (new; 3/3 @meta PASS)
reference/claude_design/design_handoff_zhi_lab/Zhi-Lab Demo Requirement.md      (new)
reference/claude_design/design_handoff_zhao_lab/Zhao-Lab Demo Requirement.md    (new)
docs/20260616_TIER0_DRUG_DESIGN_CITATIONS_FIX.md  (new)
docs/20260616_DEV_vs_CLAUDE_DESIGN_TRUTH_TABLE.md (corrected tier-0 §6)
docs/20260617_RESEARCHER_FIT_DEGUI_ZHI.md         (new)
docs/20260617_RESEARCHER_FIT_ZHONGMING_ZHAO.md    (new)
docs/20260617_RESEARCHER_INTEGRATION_OPEN_ITEMS.md (new; updated 2× with paper-cohort plan + Z02 drop)
docs/20260617_RESEARCHER_OUTREACH_SESSION.md      (this file)
```
