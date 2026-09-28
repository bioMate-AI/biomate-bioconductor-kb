# Removal of `scrnaseq_standard_endtoend` (broken unimplemented stub)

Date: 2026-09-28

## Decision

`scrnaseq_standard_endtoend` (workflow id 14435) was an **unimplemented stub**.
Its ECR image `biomate/scrnaseq-standard:v1` and the `/opt/biomate/scrnaseq/*`
scripts it invoked never existed, so every run failed at the alignment step.
Decision (user): **remove it, do not build it.** All live references removed;
historical benchmark result snapshots left untouched.

## Files changed

1. **Workflow file** — `git rm` of
   `backend/biomni_workflows/nextflow_nfcore/subworkflows/single_cell/scrnaseq_standard_endtoend/main.nf`
   (only tracked file). The untracked `.nextflow/` cache + `work/` dir under that
   folder were deleted from disk.

2. **Local workflow DB** — `backend/database/galaxy_ai_tools.db` (full 306 MB DB,
   verified not a stub before editing). In one transaction:
   - `DELETE FROM workflows WHERE id=14435` (name/filename `scrnaseq_standard_endtoend`).
   - FTS kept consistent: `workflows_fts` is an external-content FTS5 table with
     INSERT/UPDATE triggers but **no DELETE trigger**, so a plain base-row delete
     would have orphaned the FTS row. Issued the FTS5 `'delete'` command with the
     OLD indexed column values *before* deleting the base row. `integrity-check`
     passes afterward. (The term `scrnaseq_standard_endtoend` still MATCHes rows
     14436/14437 — that is correct; it appears in their annotation text.)
   - Removed workflow chain id 66 `scrnaseq_standard_to_isee` — its step 1 was the
     removed workflow, so the chain was broken/unusable.
   - Defensive deletes of `workflow_embeddings` / `workflow_phase_rationale` for
     14435 (both already 0 rows).
   - Result: workflow count 4202 → 4201.

3. **`frontend/server/galaxy-assistant.ts` (LIVE LLM routing prompt)** — delicate:
   - `DOMAIN_CATALOGS.single_cell` catalog: removed the `scrnaseq_standard_endtoend`
     bullet; added a note that BioMate has no raw-FASTQ → annotated-cell-types
     end-to-end pipeline. The trajectory bullet no longer says "from id 14435".
   - Routing-rules `single_cell` block: reworded the SCRNA-DEMO GUARD so it no
     longer names the workflow; added an SCRNA-FASTQ CAPABILITY NOTE that (a) tells
     the model **not** to promise raw-FASTQ → cell-types, and (b) redirects
     matrix-based scRNA-seq to the **working** workflows only:
     the Bioconductor single-cell chain (`scran`, `scater`, `scuttle`,
     `scdblfinder`), `Create Harmony Embeddings Scrna` / `Create Scvi Embeddings Scrna`,
     `Annotate Celltype Scrna`, and `geo_scrna_pseudobulk` (id 14485) for GEO
     accessions. DATA-FIRST guard kept intact. Also fixed the trajectory rule's
     "from id 14435" reference.
   - `npx tsc --noEmit -p tsconfig.json` → clean (exit 0).

4. **`evaluation/datasets/cross_domain_routing/queries.yaml`** — retargeted/cleaned
   the 7 references:
   - `sc2_001` and `sc2_012` (raw-FASTQ → annotated-cell-types, had
     `correct_workflow: scrnaseq_standard_endtoend`): retargeted `correct_workflow`
     to `nf-core/scrnaseq` (which does the real FASTQ → count-matrix step); notes
     document the retarget and the downstream matrix-based annotation path.
   - `sc_006`, `sc2_005`, `sc2_008`: removed the `scrnaseq_standard_endtoend`
     `acceptable_alts` entry.
   - `sc2_011`: removed the `scrnaseq_standard_endtoend` acceptable alt (kept
     `Map To Ima Interpret Scrna`).
   - YAML re-validated with `yaml.safe_load` (valid). Only remaining string hits are
     the explanatory notes documenting the retarget.

5. **`scripts/run_workflow_output_audit.py`** — `TUTORIAL_CASES["T2_single_cell"]`
   mapping repointed from the removed workflow to the real
   `scrnaseq_trajectory_pseudotime/main.nf`.

6. **`.../scrnaseq_trajectory_pseudotime/main.nf`** — header comment no longer names
   the removed workflow ("Takes any clustered + annotated h5ad" instead of "output
   of scrnaseq_standard_endtoend").

## Left untouched (intentional)

- `evaluation/datasets/public_export/results/**/*.jsonl` — historical result
  snapshots, not live config.
- `docs/20260912_onprem_llm/**` training-data JSON snapshots (untracked data
  artifacts, not live routing config).

## Routing gap resolution

There is no working FASTQ → annotation end-to-end scRNA workflow after removal.
scRNA-seq requests now:
- If raw FASTQ: the prompt asks the user for a counts matrix / `.h5ad` / GEO-SRA
  accession instead of promising raw-read processing; alignment-only FASTQ →
  count-matrix is `nf-core/scrnaseq`.
- Matrix-based analysis routes to the existing, working workflows: Bioconductor
  chain (scran/scater/scuttle/scdblfinder), Harmony/scVI embeddings, Annotate
  Celltype Scrna, `scrnaseq_trajectory_pseudotime` (counts/annotated h5ad),
  `geo_scrna_pseudobulk` for GEO accessions.
No replacement workflow name was invented — only DB-present workflows are referenced.

## Deploy

Committed to working tree and synced to dev via `scripts/sync_to_dev.sh`
(health-gated). Dev verification: DB count for `scrnaseq_standard_endtoend` = 0;
scRNA-seq routing no longer names it.
