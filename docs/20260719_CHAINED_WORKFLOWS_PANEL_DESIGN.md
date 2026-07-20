# Chained Workflows — Panel Design & Chat Flow
**Date:** 2026-07-19 | Conference prep: July 21–23, 2026 Boston

---

## Overview

BioMate supports two types of workflow chains relevant for the conference demos:

1. **Single-workflow chains** — one Nextflow job internally executing multiple stages  
2. **Conversation chains** — multiple separate workflows run in sequence through the chat

---

## Type 1: Single-Workflow Chains (Built for Conference)

These are self-contained Nextflow workflows that run as one AWS Batch job with multiple internal evidence layers. Each layer runs sequentially inside the same process.

### Workflows built

| Workflow name | Stages | Contact served |
|---------------|--------|----------------|
| `gwas_scrna_eqtl_target_chain` | GWAS loci → eQTL colocalization → scRNA cell-type specificity → ranked target report | Tarek Samad / Lundbeck (CD40L) |
| `pbpk_peripheral_nerve` | 10-compartment ODE (blood, liver, kidney, fat, muscle, peripheral nerve, spinal, DRG, NMJ, CSF) | David Ngai / Alnylam (GalNAc-siRNA) |
| `macrophage_metabolic_state_scrna` | scRNA normalization → Leiden clustering → metabolic program scoring → pseudotime → differential abundance | David Ngai / Alnylam (CIDP macrophage biology) |
| `rnaseq_proteomics_multiomics_integration` | Per-modality normalization → MOFA2 factor decomposition → pathway enrichment → responder AUROC | Ruchi Gupta / Gilead, Beatrix Bartok / Biogen |

### Chat flow for a single-workflow chain

**Example: Tarek Samad query**

The user must phrase the request as a workflow execution, not a research question:

> **Works** (routes to `gwas_scrna_eqtl_target_chain`):  
> "Run the GWAS-to-scRNA target prioritization workflow for CD40L across MG, CIDP, and GBS"  
> "Analyze CD40L genetic evidence and cell-type expression across myasthenia gravis and CIDP using the target chain"

> **Does NOT work** (classified as research question, returns text):  
> "I need to map CD40L's genetic evidence across MG, CIDP, and GBS. Pull GWAS hits near CD40LG…"  
> — BioMate answers with a literature-style explanation instead of routing to a workflow

**Chat panel sequence:**

1. User types the request → presses Enter
2. AI response streams with text explanation of the 3-layer approach
3. `wf-chip` appears below the AI text:
   ```
   ┌──────────────────────────────────┐
   │ gwas_scrna_eqtl_target_chain     │
   │ drug_discovery   [Open in panel] │
   └──────────────────────────────────┘
   ```
4. User clicks "Open in panel" → right panel opens

### Workflow panel states

**Pre-run (idle):**
```
Panel name:  gwas_scrna_eqtl_target_chain
Domain:      drug_discovery
Parameters:
  target_gene  = CD40LG
  diseases     = Myasthenia Gravis, CIDP, GBS
  min_gwas_pvalue = 5e-8

[ Confirm & Run ]
```
- `data-testid="workflow-overall-status-badge"` has `data-status="idle"`
- Tabs: Settings | Phases | After Run

**Running (AWS Batch):**
```
Overall status: [⟳ RUNNING]

Phase cards:
  GWAS Layer    [✓] completed
  eQTL Layer    [⟳] running       ← spinner, SSE updates this live
  scRNA Layer   [·] pending

Footer: [ Running… ]
```
- Phase cards use `data-status="running"` → `data-status="completed"` as each stage finishes
- SSE progress pills appear in chat: `WF`, `QC`, `LOOP` speaker labels
- Action bar (`[data-testid="panel-action-bar"]`) shows while running

**Completed:**
```
Overall status: [✓ COMPLETED]

After Run tab:
  Outputs:     gwas_loci.csv, candidate_genes.csv, target_priority_report.json, chain_output.txt
  Findings:    Ranked CD40LG evidence across MG/CIDP/GBS — complement loci at 5p13.1, eQTL in PBMC, high B-cell expression
  Parameters:  [what was used]

[ Run again ]   [ Download report ]   [ Analyze results ]
```

---

## Type 2: Conversation Chains (Multi-Step Sessions)

Multiple separate workflows run in sequence through the chat. Each step opens a new workflow in the right panel.

### Demo A — "MG Immune Profiling" (9 contacts)

**Step 1: scRNA-seq clustering**
```
User:    "Run single-cell RNA-seq clustering on PBMC data from MG patients vs healthy controls"
BioMate: Routes to nf-core/scrnaseq
Panel:   Pre-run → Running → Completed
         Outputs: UMAP, cluster labels, marker genes, FcRn expression overlay
```

**Step 2: DESeq2 responder DE**
```
User:    "Now run differential expression comparing responders vs non-responders using the cluster labels"
BioMate: Routes to DESeq2 (parameter prefill: condition=responder, from prior run context)
Panel:   New workflow in panel — DESeq2
         Outputs: ranked DE gene list, volcano plot
```

**Step 3: Complement pathway enrichment**
```
User:    "Enrich the top differentially expressed genes for complement pathway"
BioMate: Routes to clusterProfiler / pathlinkr
Panel:   New workflow — pathway enrichment
         Outputs: bar chart of enriched GO terms, complement gene hits
```

**Each wf-chip in the chat shows the state of that step** — users can see the full session history by scrolling the chat. The panel always shows the most recent (or user-clicked) workflow.

### Demo C — "IND-Ready Evidence Package" (Cartesian + Hesperos)

```
Step 1: User "Run ADMET screening on these 8 SMILES"
        → predict_admet_properties workflow, panel shows ADMET panel with hERG, Cmax, BBB

Step 2: User "Run PBPK for compound 3 which passed ADMET"
        → pbpk_simulation workflow, panel shows PK curve, AUC, Cmax

Step 3: User "Generate the IND §2.6 pharmacokinetic narrative"
        → BioMate AI generates §2.6 text from PBPK results

Step 4: User "Export the full audit trail"
        → run_audit_export workflow, panel shows SHA256 manifest + claims_index.json
```

---

## Multi-Omics Flexibility Answer

### The problem

A single multi-omics workflow needs to work for any combination:
- RNA-seq + Olink proteomics (Ruchi Gupta / Gilead)
- RNA-seq + metabolomics (Biohaven — metabolic context)
- scRNA-seq + ATAC-seq (joint chromatin + expression)
- RNA-seq + methylation array (epigenomic context)
- RNA-seq + protein + metabolomics (3-way full integration)

### The solution: `modalities` parameter

One workflow (`rnaseq_proteomics_multiomics_integration`) handles all combinations via:

```nextflow
params.modalities = 'rna,protein'   // default
// other valid values:
// 'rna,metabolomics'
// 'scrna,atac'
// 'rna,methylation'
// 'rna,protein,metabolomics'
```

BioMate's AI fills this from user context:
- "RNA-seq and Olink" → `rna,protein`
- "scRNA-seq with ATAC" → `scrna,atac`  
- "RNA plus metabolomics" → `rna,metabolomics`
- "full multi-omics: RNA, protein, metabolomics" → `rna,protein,metabolomics`

### Per-modality normalization (auto-selected)

| Modality | Input format | Normalization applied |
|----------|-------------|----------------------|
| `rna` | Count matrix (gene × sample) | DESeq2 VST (log1p of size-factor normalized) |
| `scrna` | Pseudo-bulk count matrix | Log-CPM per sample |
| `protein` | NPX or log2 abundances (Olink, SomaScan, RPPA) | log2 + quantile normalization |
| `metabolomics` | Intensity matrix (GC-MS, LC-MS, NMR) | log2 + unit-variance scaling |
| `atac` | Peak score matrix | TF-IDF log-transform |
| `methylation` | Beta-value matrix | M-value: log2(β/1−β) |

### MOFA2 integration

After normalization, all active modalities are concatenated and decomposed via SVD (MOFA2 proxy). The workflow outputs:

- **`factor_weights_{modality}.csv`** — feature weights per factor, one file per active modality
- **`factor_variance_explained.csv`** — which factor explains which fraction of variance in each modality
- **`pathway_enrichment.csv`** — GO/KEGG enrichment on RNA modality top-weighted genes
- **`curated_pathway_scores.csv`** — per-sample complement, FcRn, B-cell, inflammatory scores
- **`factor_phenotype_auc.csv`** — AUROC of each factor vs the outcome label (responder/non-responder)
- **`integration_report.html`** — multi-panel HTML report adapting its sections to active modalities

The output schema is **identical regardless of which modality combination is used**, so downstream analysis (responder prediction, pathway enrichment) always works the same way.

---

## Routing Verification (dev-public.biomate.ai, 2026-07-19)

Tested via `/api/ai_assistant/generate_workflow` with professional-user phrasing:

| Contact / Use case | Query phrasing | Workflow routed | Confidence |
|--------------------|---------------|-----------------|------------|
| Tarek / Lundbeck (CD40L) | "CD40L pathway target prioritization using GWAS genetic evidence and scRNA-seq cell type expression across MG CIDP GBS" | `gwas_scrna_eqtl_target_chain` | 137 |
| David Ngai / Alnylam (PBPK) | "GalNAc-siRNA PBPK model with peripheral nerve and spinal cord compartments for CIDP patient dosing" | `pbpk_peripheral_nerve` | 158 |
| David Ngai / Alnylam (macrophage) | "Macrophage metabolic state transitions in CIDP nerve repair. Identify glycolytic vs lipid-associated TREM2 macrophage subtypes from scRNA-seq" | `macrophage_metabolic_state_scrna` | 171 |
| Ruchi / Gilead | "Integrate RNA-seq and Olink proteomics from CIDP patients. MOFA2 factor analysis. Complement pathway enrichment" | `rnaseq_proteomics_multiomics_integration` | 88 |
| Beatrix / Biogen | "We have bulk RNA-seq and plasma cell quantification from MG patients treated with felzartamab. Multi-omics integration to find the responder signature" | `rnaseq_proteomics_multiomics_integration` | 80 |
| Martin / Apellis | "Complement pathway enrichment analysis on PBMC RNA-seq data from MG patients" | `pathlinkr` (pathway tool, acceptable) | 46 |

### Key finding: intent classification threshold

The generate_workflow API correctly routes all 6 BD queries. However, the **chat interface** applies intent classification first. Queries phrased as research questions ("I need to understand...", "Pull GWAS hits...", "Give me a view...") are classified as `research_question` and return text explanations instead of workflow cards.

**For demos: phrase requests as explicit workflow commands:**
- ✅ "Run the GWAS→scRNA→eQTL chain for CD40L across MG, CIDP, and GBS"
- ✅ "Analyze macrophage metabolic states in this CIDP scRNA-seq dataset"  
- ✅ "Integrate these RNA-seq and Olink files using multi-omics analysis"
- ❌ "I need to map CD40L genetic evidence across three indications..."

---

## Open Issue

**Complement pathway enrichment for Martin Kolev (Apellis/Biogen):**  
Routes to `pathlinkr` (confidence 46) rather than `clusterprofiler` (confidence ~40). Both are valid pathway enrichment tools. `pathlinkr` will show complement genes enriched from DE results. This is acceptable for the demo but could be improved by strengthening the `clusterprofiler` annotation to explicitly mention complement cascade, C3, C5, CFH, CFB.
