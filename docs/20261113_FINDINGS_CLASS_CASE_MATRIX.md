# 2026-11-13 — Findings/report class case matrix (close-out)

Live tip at close-out verification: see `build-info.json` on DEV after sync.
Worktree branch: `sync/pr398-onto-dev`.

## Pipeline (every domain)

```
Outputs (S3 / Galaxy)
  → scoreFindingsSampleName (metrics / vina / boltz / DE / ADMET ↑)
  → preProcessForFindings (ADMET / DESeq2 / enrichGO / raredisease / ml_training)
  → matchDescriptor → buildFindingsDocument → documentToLegacy  (skip LLM)
  → else LLM last resort
  → persist findings_data.json (S3)
  → GET /findings + /findings/report refuse looksLikeHollowFindings
  → FindingsCard (score-preferring chips + Key Results table)
```

## Case matrix

| Domain | Issue | Fix | Test | Verified |
|--------|-------|-----|------|----------|
| **ml_training** | LLM narrated Ludwig hyperparams; ignored `metrics.json` MAE | `parseMlTrainingFindings`; fluff refuse; sample rank | `ml-training-findings.test.ts`, `findings-quality.test.ts` | Live S3 sidecar `727de1b4` MAE-first (`evidence_version=ml-training-metrics-v1`) |
| **ADMET** | Dual flat vs document liability mismatch | Descriptor merge + `reconcileFindingsDocument` (prior) | `findings-extract.test.ts` | Prior live; class refuse still on |
| **DESeq2 / RNA-seq** | Generic “Assessment completed…” buried top genes; LLM when descriptor miss | Domain summary + Key Results; documentToLegacy cutover | `findings-extract.test.ts` (DESeq2 summary) | Unit |
| **enrichGO** | TSV enrichment tables failed comma-only split → LLM | Autodelim in `_parseEnrichGoOutput` | Covered by descriptor autodelim + quality rank | Unit |
| **variant / WGS** | HIGH impact buried; hollow LLM | Descriptor → documentToLegacy; summary counts HIGH/MODERATE | `findings-extract` variant path | Unit |
| **docking / Vina** | No deterministic affinity parser | `vina_docking` descriptor + score-first summary | `findings-extract.test.ts` Vina | Unit (sample JSON from research runs) |
| **Boltz / structure** | pLDDT only in `qc_metrics.json`; LLM fluff risk | `boltz_qc` content-gated on `mean_plddt` | `findings-extract.test.ts` Boltz | Unit |
| **sampling (all)** | Bookkeeping crowded score cards | `scoreFindingsSampleName` +8 vina/boltz | `findings-quality.test.ts` | Unit |
| **hollow sidecar (all)** | Poison cache re-served | `looksLikeHollowFindings` expanded (docking/structure empty+admit) | `findings-quality.test.ts` | Unit + prior live heal |
| **report download** | Empty / fluff vs Findings | Same refuse + Key Results table from cache\|S3 | prior `ml-training` report tests | Prior live report MD |
| **Findings UX** | Gate chips buried scores | Chip rank prefers affinity/plddt/padj/MAE | `findings-card.test.tsx` | Unit |
| **download_all_zip** | “No outputs found” while Outputs tab full (`727de1b4`) | Prefer `runsOutputsService.list` before empty Galaxy rows | `download-all-handler.test.ts` canonical case | Unit; needs sync for live ZIP |
| **integration / scdownstream** | Unverified scores | Prior verified Integration path | prior | Prior |
| **cryoEM SPA** | LLM ignored FSC / particle counts across step reports | `parseCryoEmFindings` from fsc/picking/extract/motion/workflow_summary | `cryo-em-findings.test.ts` | Unit |
| **MultiQC (RNA/WGS QC)** | No DE table → LLM narrated MultiQC HTML | `parseMultiqcFindings` from `multiqc_data.json` general stats | `multiqc-findings.test.ts` | Unit |
| **QC gates / auto-loop** | Live panel events, not Findings sidecar | Out of Findings class (panel SSE) | — | N/A |
| **Chat stream prose** | Original assistant turn not rewritten | Intentional — After-run Findings/report are source of truth | — | Documented |

## Leftover (honest)

1. **Retroactive chat prose** — not rewritten for old turns; Findings tab + report are authoritative.
2. **Owner ≠ E2E fixture** — authenticated UI screenshot for potency session still needs `drugtest@biomate.dev` (S3 + unit cover the data path).

## Deploy

Class follow-ups in this worktree need `BIOMATE_SYNC_DB=0` sync after commit to land ZIP + docking/Boltz/DESeq2 summary on DEV. ML training heal already on S3 without sync.
