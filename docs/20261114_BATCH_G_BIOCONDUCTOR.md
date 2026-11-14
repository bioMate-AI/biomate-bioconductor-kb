# Batch G — Bioconductor R container-exit coldstarts

**Timestamp:** 2026-11-14  
**Evidence:** `docs/20261114_COLDSTART_FAILED_WORKFLOWS_INVENTORY.md` §5; execshots  
`analysis-domain-fgen-1` (mageckflute), `analysis-domain-prot-0` (deqms),  
`analysis-domain-prot-1` (multigsea), `analysis-try-sample-data-7` (survival cox).

## Verdict

Four related failures: Style-A Bioconductor workflows hard-read fixed basenames / column
schemas, while cold-start attachments arrive under demo names (or MaxQuant’s real column
vocabulary). Staging + R scripts now normalize paths and schemas at the root — no local R
installs, no pydeseq substitutes.

## Per-workflow root cause

| Workflow | Cold-start case | Observed error | Root cause | Fix |
|----------|-----------------|----------------|------------|-----|
| **survival cox** | `analysis-try-sample-data-7` | `Time variable is not numeric` / `Surv` traceback | CSV found (`patient_clinical_data.csv` with `time_months`), but Cox script called `Surv(time, status)` with no alias/coercion (KM `main.nf` already mapped columns) | Port KM column-alias + numeric/status mapping into `cox_proportional_hazards_regression.nf`; drop ID columns from `~ .` |
| **deqms** | `analysis-domain-prot-0` | `'x' must be an array of at least two dimensions` | Real LFQ-Analyst `proteinGroups.txt` uses `Potential.contaminant` (not vignette `Contaminant`). `$Contaminant` → `NULL` → 0-row filter → empty LFQ matrix → `rowMins`/limma crash. Also 3 groups H/L/N when prompt wants H vs L | Accept `Potential.contaminant`; robust LFQ/peptide column detection; prefer H+L two-group contrast when N present |
| **multigsea** | `analysis-domain-prot-1` | `Could not find transcriptome.csv … in cwd` | `// Input: transcriptome, proteome, metabolome` (3 tokens). Freestyle file collection was gated on `len(names)==1` → only placeholder `.dat`. Attachments are `tcga_mrna.csv` / `tcga_protein.csv` (abundance), not ranked DE tables; metabolome often absent | Executor: freestyle + `_ROLE_HINTS` stage under declared names; no blind-zip of metadata→metabolome. Script: discover by role; abundance+metadata → ranks; metabolome optional |
| **mageckflute** | `analysis-domain-fgen-1` | `FluteRRA → ReadRRA → [.data.frame` | Cold-start attaches `crispr_counts.tsv` (sgRNA counts). Bound/staged as `gene_summary.txt`. `ReadRRA` hard-indexes 14 MAGeCK-RRA columns → crash on 6-col counts | Detect counts vs RRA; convert counts→MAGeCK-shaped gene/sgRNA summaries; `incorporateDepmap=FALSE`; package testdata only as last resort |

## Files changed

| File | Change |
|------|--------|
| `backend/lib/galaxy/webapps/galaxy/api/nextflow_executor.py` | Style-A freestyle pool for multi-token `Input:`; role/basename hints; no metadata→metabolome blind zip |
| `backend/lib/galaxy/ai/ai_assistant.py` | Exact-stem bind + bioc Style-A cues (`patient_clinical_data`, `proteinGroups`, omics layers, RRA names) |
| `…/survival/cox_proportional_hazards_regression.nf` | Column alias + numeric coercion (parity with KM) |
| `…/deqms/maxquant_lfq.nf` | Contaminant/LFQ/peptide robustness; H vs L when 3 groups |
| `…/multigsea/main.nf` | Flexible layer discovery; abundance→ranks; optional metabolome |
| `…/mageckflute/main.nf` | Counts→RRA bridge before `FluteRRA` |
| `backend/tests/test_coldstart_batch_g_bioconductor.py` | Import-light contract tests (6 passed) |
| `docs/20261114_BATCH_G_BIOCONDUCTOR.md` | This note |

**Not touched (per batch rules):** reinvent4\*, soft-pass harness, structure-set (Batch F), sarek samplesheet helper, `_PER_PROCESS_CONTAINER_WORKFLOWS`, `PRODUCTION_MD` gate.

## Local verification

```bash
cd backend && PYTHONPATH=lib python3.9 -m pytest tests/test_coldstart_batch_g_bioconductor.py -q
# 6 passed
```

Full Galaxy import of `nextflow_executor` still needs the Galaxy venv (`beaker`, etc.) — same as PRE_SYNC Galaxy module-load check on a machine with that env.

## Blockers / residual risk

1. **DEV sync** — code not live until PRE_SYNC + one-writer `scripts/sync_to_dev.sh`.
2. **multigsea pathway download** — `getMultiOmicsFeatures(useLocal=FALSE)` needs Batch egress to pathway DBs; if blocked, enrichment fails after ranks succeed.
3. **mageckflute counts→RRA** — in-script Wilcoxon/LFC bridge is not full `mageck test`; sufficient for FluteRRA/ReadRRA column contract and cold-start hit lists, not a substitute for production MAGeCK CLI when available in-image.
4. **DepMap** — disabled (`incorporateDepmap=FALSE`) so Batch nodes without egress do not hang; enrichment still uses organism annotation packages in the bioc image.
5. **Re-run evidence** — need post-sync coldstart regrade of the four case IDs above to close the class on DEV.

## Expected smoke outcome (after sync)

| Case | Expect |
|------|--------|
| try-sample-data-7 | Cox completes; `cox_coefficients.csv` / HR tables; no “Time variable is not numeric” |
| domain-prot-0 | DEqMS completes on LFQ-Analyst proteinGroups; H-L contrast results |
| domain-prot-1 | multiGSEA finds mrna+protein, optional metabolome skipped; enrichment CSV |
| domain-fgen-1 | Counts converted → FluteRRA finishes without ReadRRA column crash |
