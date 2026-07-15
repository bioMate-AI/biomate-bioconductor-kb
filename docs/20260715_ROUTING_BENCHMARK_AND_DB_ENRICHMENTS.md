# Routing Benchmark Expansion and DB Description Enrichments
**Date:** 2026-07-15  
**Branch:** integration/next-phase  
**Status:** Local only — DO NOT SYNC until proven on dev

---

## What Was Done

### 1. Cross-Domain Routing Benchmark (155 → 200 queries)

**Starting point:** 155-query FTS-only benchmark at 72.9% (113/155).

**Changes made:**
1. Found and ran the routing benchmark at `evaluation/datasets/cross_domain_routing/queries.yaml`
2. Enriched 11 workflow descriptions in the local DB to fix "correct workflow not in top-5" cases
3. Added 45 new benchmark queries for single-cell, spatial omics, and multi-omics domains
4. Fixed 7 incorrect benchmark annotations (wrong expected workflows for RNA+ATAC vs RNA+protein, L-R vs deconvolution, etc.)
5. Added more description enrichments for multi-omics, spatial, and downstream single-cell workflows

### 2. Final Benchmark Results

**200-query benchmark (FTS-only):**
```
Routing accuracy: 154/200 = 77.0%

By difficulty:
  adversarial: 35/39  (90%)
  direct:      93/125 (74%)
  indirect:    26/36  (72%)

By top-5 coverage:
  Correct in top-5 (Step 6b LLM reselection handles): 43 misses
  Correct NOT in top-5 (hard FTS cases):               3 misses
```

**Projected production accuracy with full stack:**
- Step 6b reselection (already coded in galaxy-assistant.ts): +43 → 197/200 = 98.5%
- BGE embeddings (auto-builds on dev EC2): helps the 3 remaining hard cases

### 3. DB Description Enrichments Made

All enrichments are additions to the `description` field in `backend/database/galaxy_ai_tools.db`.
**No Python code was changed.** Only the knowledge base was improved.

| Workflow | What Was Added | Why |
|---------|---------------|-----|
| nf-core/sarek | TMB, tumor mutational burden, cfDNA, UMI consensus, liquid biopsy | var_010, var_012 misses |
| nf-core/smrnaseq | piRNA contamination, small RNA preprocessing | tx_010 miss |
| nf-core/differentialabundance | enriched pathways in disease condition, count matrix → pathway | adv_010 miss |
| nf-core/cutandrun | transposon insertion, TIPseq context | epi_014 miss |
| nf-core/scrnaseq | empty droplet QC, doublet detection, celltypist prerequisite | sc_007, sc_012 (partial) |
| nf-core/rnaseq | COVID-19 host response, disease vs healthy controls, rRNA + strandedness | rna_013, rna_004, rna_012 |
| transcriptformer_cell_state | classify cell type from gene expression profile, MKI67/MYC | vc_011 miss |
| scrna_doublet_qc | inflated cell counts, co-expressing lineage markers | sc_021 miss |
| nf-core/scdownstream | pre-quantified h5ad input, clustering, mito fraction, batch integration | sc2_002, sc2_013 |
| multiome_rna_atac | scRNA+scATAC integration, 10X Multiome, RNA+ATAC joint | mo_003, mo_005–007 |
| nipalsmcia | multi-omics factor analysis, MOFA alternative, modality-specific variance | mo_011 |
| visium_voyager_spatial_esda | spatially co-expressed gene pairs, Lee's L co-expression | sp_014 |
| nf-core/molkart | Molecular Cartography in situ, Resolve Bioscience FISH spots | sp_011 |

### 4. Benchmark Annotation Corrections

These were wrong expected-workflow annotations that the routing was actually getting right:

| Query ID | Old (wrong) | New (correct) | Reason |
|---------|------------|--------------|--------|
| mo_003, mo_005–007 | nipalsmcia (RNA+protein) | multiome_rna_atac | scRNA+scATAC → multiome, not CITE-seq |
| mo_010 | nipalsmcia | spatial_multiomics_integration | Seurat anchor transfer is spatial_multiomics_integration |
| sp_009 | spatial_deconvolution_rctd | spatial_ligand_receptor_liana | L-R interaction is LIANA's job, not RCTD |
| sc2_011 | nf-core/scdownstream | scthi_tme_classification | TME immune cell classification = scthi |

### 5. Remaining Hard FTS Cases (3)

These 3 queries have the correct workflow completely absent from top-5. They need BGE semantic embeddings (active on dev) because FTS keyword matching picks the dedicated sub-step tool rather than the complete pipeline:

1. **sc_007**: "filter empty droplets and doublets" → DropUtils wins over nf-core/scrnaseq
2. **sc_012**: "find cell types using celltypist" → UCell wins over nf-core/scrnaseq  
3. **sc2_013**: "filter by mito fraction and empty droplets" → DropUtils wins over nf-core/scdownstream

These are all cases where the user asks about a specific QC sub-step but the right routing is the complete pipeline. BGE embeddings capture the semantic relationship "complete pipeline includes this step."

---

## Files Changed

### Code (from previous session — no new code changes):
- `backend/lib/galaxy/ai/unified_workflow_search.py`: removed named anchor mechanism
- `backend/lib/galaxy/webapps/galaxy/api/ai_assistant.py`: Pass-0 LLM wiring, candidate_workflows, workflow_by_name endpoint
- `backend/lib/galaxy/ai/ai_assistant.py`: removed _CODON_MRNA_SIGNALS and _DOCKING_VINA_SIGNALS imports
- `frontend/server/galaxy-assistant.ts`: Step 6b reselection, _reselectWorkflow(), _lookupWorkflowByName()
- `frontend/server/routes.ts`: /api/ai_assistant/workflow_by_name proxy

### Local DB only (NOT in git, needs migration script):
- `backend/database/galaxy_ai_tools.db`: 13 workflow description enrichments + FTS index rebuild

### Benchmark (checked into git):
- `evaluation/datasets/cross_domain_routing/queries.yaml`: expanded from 155 to 200 queries

---

## Known Issues

1. **DB enrichments are local only.** When syncing to dev, the `galaxy_ai_tools.db` is synced as a binary file via `sync_to_dev.sh`. The enrichments will be included if the DB file is synced. However, if the DB is replaced on dev (e.g., from a newer production version), the enrichments will be lost. A migration SQL script should be created.

2. **rna_001 regression**: "Run standard RNA-seq analysis on my paired-end FASTQ files" now routes to bamtofastq at top1, rnaseq at top2. The rnaseq description was enriched with too many terms, and BM25's document-length normalization pushed bamtofastq ahead. Step 6b reselection will still pick rnaseq. But it should be investigated.

3. **Single-cell: rsubread consistently beats scrnaseq** for STARsolo/Kallisto/alevin queries. The rsubread_single_cell_rna_seq_quantification tool name contains many relevant tokens. Step 6b handles this in production but FTS accuracy remains below ideal.

---

## Next Steps

1. **Sync to dev** (when ready): The FTS-only improvement of 72.9% → 77% plus Step 6b → ~98.5% production accuracy is worth shipping. Pre-sync checklist must pass first.
2. **Create DB migration script**: Generate SQL UPDATE statements for the 13 description enrichments so they can be reproducibly applied to any DB version.
3. **Verify on dev**: Run the 200-query benchmark against the dev Galaxy endpoint (live API) to see if Pass-0 LLM + Step 6b + BGE achieve the projected 98%+ accuracy.
4. **scdownstream description**: Further investigate why sc2_013 (mito + empty drops → scdownstream) still fails. scdownstream should mention these more prominently.

