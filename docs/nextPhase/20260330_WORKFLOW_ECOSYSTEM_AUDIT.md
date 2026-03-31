# BioMate Workflow Ecosystem Audit
**Date:** 2026-03-30  
**Purpose:** Pre-release organization of workflow inventory, overlap analysis, QC integration, chain mechanism, and visualization

---

## A. Workflow Inventory by Source

From the live database (`backend/galaxy_ai_tools.db`) after 2026-03-30 cleanup:

| Source | Format | Count | Description |
|--------|--------|-------|-------------|
| `bioconductor` | bioconductor_nf | 1,818 | R package Nextflow wrappers — each is a runnable `.nf` file wrapping an R/Bioconductor package |
| `biomni_nextflow` | nextflow | 289 | BioMate-authored domain workflows under `nextflow_nfcore/subworkflows/` |
| `nfcore` | nextflow | 230 | Full published nf-core pipelines (rnaseq, sarek, chipseq, etc.) |
| `nfcore_subwf` | nextflow | 93 | nf-core library subworkflows from `nf-core-modules/subworkflows/nf-core/` |
| `biomate` | nextflow | 2 | Special BioMate-specific Nextflow workflows |
| `biomni` | nextflow | 1 | Legacy BioMate workflow (retained for backwards compat) |
| `galaxy_biomni` | galaxy_ga | 2 | Galaxy JSON workflow files (no Nextflow equivalent) |

**Total: 2,435 workflows** (10 stale/duplicate entries removed 2026-03-30)

### Domain Breakdown (biomni_nextflow) — After 2026-03-30 Merger
BioMate workflows are organized by domain folder. **`pharmacology/` and `drug_discovery/` are now a single DB domain (`drug_discovery`) per user feedback:**

- `drug_discovery/` — pocket detection, pharmacophore filtering, REINVENT4, MOE, Schrödinger, MD simulation (GROMACS, AMBER)
- `pharmacology/` (folder kept, DB domain = `drug_discovery`) — ADMET, docking, drug combinations, FDA labels, PK/PD (NCA, IVIVE, PopPK), radiotherapy dosimetry
- `genomics/` — germline, somatic, WGS, panel
- `single_cell/` — scRNA-seq, trajectory, CITE-seq
- `cryo_em/` — motion correction, CTF estimation, particle picking, 3D reconstruction
- `bioconductor/` — R-based analysis (sub-categorized by domain, see §A.1)
- `physiology/` — PK/PD models
- `bioengineering/` — stability assays, formulation analysis
- `imaging/` — microscopy analysis

### A.1 Bioconductor Sub-categorization (2026-03-30 update)

The 1,818 bioconductor wrappers are categorized in the DB by domain inference from their package descriptions. After adding expanded keyword rules (`microarray`, `affy`, `nmr`, `metabolom`, `single cell`, `scrna`, `copy number`, `docking`, `pharmacokin`, etc.) the domain distribution improved:

| Domain | Count | Notes |
|--------|-------|-------|
| `transcriptomics` | 828 | bulk RNA-seq, microarray, Affymetrix, differential expression |
| `general` | 389 | Infrastructure/annotation packages (alabaster, BiocManager, etc.) — intentionally broad |
| `genomics` | 209 | Variant annotation, genome browsers, CNV, assemblies |
| `epigenomics` | 126 | ATAC-seq, ChIP-seq, bisulfite, Hi-C |
| `proteomics` | 99 | Mass spec, phosphoproteomics, protein interaction |
| `variant_calling` | 59 | SNP/indel callers, VCF manipulation |
| `imaging` | 39 | Fluorescence microscopy, flow cytometry, spatial |
| `metagenomics` | 27 | Amplicon, 16S, binning |
| `single_cell` | 21 | scRNA-seq QC, trajectory, cell typing |
| `metabolomics` | 21 | LC-MS, NMR, MassBank, lipidomics |

The `general` bucket (389) contains legitimate cross-domain packages (data containers, cloud infra, utility packages like `alabaster_*`, `AnVILBase`, `GenomicRanges`) that cannot be classified more specifically without per-package manual tagging. This is expected and acceptable.

**Duplicate R wrapper vs existing workflow check:**
- No BioMate `biomni_nextflow` workflow duplicates a bioconductor wrapper directly — bioconductor wraps single R packages, biomni_nextflow workflows compose multi-step analyses.
- The `nca_pknca` duplicate was across `pharmacology/` and `drug_discovery/` folders (both Nextflow, not R vs Nextflow). **Fixed 2026-03-30:** removed the shorter pharmacology version (256 lines), kept the expanded drug_discovery version (1,044 lines, 3-step pipeline + HTML report).
- nf-core/differentialabundance uses DESeq2 internally — it is a superset of the bioconductor/deseq2 wrapper, not a duplicate (different abstraction level).

---

## B. Full Workflow vs Subworkflow: Definitions and Differences

### Conceptual Distinction

The terms are used inconsistently in BioMate, but here is what each actually means in the codebase:

**Full Pipeline** (`nfcore` source, `backend/nf-core-workflows/<name>/main.nf`):
- Has a complete `workflow { ... }` block with a named entry point
- Has its own `nextflow.config` with profiles (test, docker, singularity)
- Has published nf-core documentation and test datasets
- Example: `nf-core/rnaseq`, `nf-core/sarek`, `nf-core/chipseq`
- Can be run as: `nextflow run nf-core/rnaseq -r 3.14.0 -profile test,docker`

**BioMate Domain Subworkflow** (`biomni_nextflow` source, `nextflow_nfcore/subworkflows/<domain>/<name>/main.nf`):
- Also has a `workflow { ... }` block and is runnable directly
- BUT: typically a single-domain analysis step, not a complete pipeline
- No nf-core-style test profiles; relies on BioMate parameter injection
- Example: `ADMET_pred/main.nf` — takes SMILES, returns toxicity predictions
- Run as: `nextflow run backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/ADMET_pred/main.nf --smiles ...`

**nf-core Subworkflow** (`nfcore_subwf` source, `nf-core-modules/subworkflows/nf-core/`):
- Library-style: designed to be `include`d by a full pipeline
- Has a `workflow` block but no standalone entry point
- Example: `bam_sort_stats_samtools` — takes a BAM, sorts it, runs flagstat
- NOT typically run standalone; used as a building block in generation

**Bioconductor Wrapper** (`bioconductor` source):
- Simple Nextflow wrapper around an R script calling one Bioconductor package
- Runnable standalone: `nextflow run .../deseq2/main.nf --quant_dir ... --metadata ...`
- 1,818 of these — one per R package
- High recall when user asks for a specific R analysis method

### How the System Decides What to Show Users

The search scoring (`unified_workflow_search.py`) applies priority so that:
1. For "run a pipeline on my FASTQ data" → nf-core full pipelines appear first (score +8 + source priority 100)
2. For "ADMET screening of SMILES" → BioMate `drug_discovery` domain subworkflows appear first (domain match; `pharmacology/` folder now maps to `drug_discovery` DB domain)
3. For "DESeq2 differential expression analysis" → Bioconductor DESeq2 wrapper surfaces (exact name match +15)
4. nf-core library subworkflows typically do NOT appear as primary results — they're used in generation

### Leveraging Existing Workflows to Build New Ones

**How the code actually works — 4-level pipeline in `nextflow_composer.py`:**

```
L0: SubworkflowLibrary cache lookup (subworkflow_library/ JSON database)
    → Jaccard similarity ≥ 0.75 on tool IDs, quality ≥ 70 → return cached .nf (0 LLM calls)
    ↓ miss
L1: Tool retrieval from SQLite FTS + category matching (~20 ms)
    ↓
L2: Wrapper path validation + substitution
    - NF-WRAPPER: wrapper_path file exists on disk → use include{} directive
    - BAD-PATH: file missing → substitute same-category tool from good list
    - GENERATE: no wrapper_path → LLM writes minimal process block
    ↓
L3: Single LLM call — generates full DSL2 .nf with 6 core rules injected:
    1. Use exact include{} statements for NF-WRAPPER tools
    2. Write minimal process blocks for GENERATE tools
    3. Chain tools in biologically correct order
    4. Select only relevant tools (discard irrelevant candidates)
    5. Follow nf-core DSL2 conventions (tuple channels, named outputs, versions.yml)
    6. Include file header: intent, tool rationale, expected inputs/outputs
    ↓
L4: Syntax validation (DSL2 marker, include paths, brace balance) + write to disk
    Background thread: cache in SubworkflowLibrary for future L0 hits
```

**Skill files used to avoid common errors:**

The LLM is augmented by two error-avoidance layers:

1. **`skill_loader.py`** (`backend/lib/galaxy/ai/agents/skill_loader.py`): Loads domain-specific skill prompts from `claude-scientific-skills-biomate` repository. Maps workflow intent/domain to prebuilt skill YAML files (e.g., pharmacology skill, genomics skill) and injects them into the LLM context. Includes reference subdirectories for extended scientific knowledge.

2. **The 6 core DSL2 rules** injected in the `NextflowComposer` prompt (lines 450-494 of `nextflow_composer.py`): These rules have been tuned to prevent the most common LLM Nextflow errors: missing `dsl = 2` header, wrong include path format, unbalanced workflow blocks, and non-DSL2 process syntax.

**Chain workflow composition (workflow_chain.py):**
- Curated 8-step chains defined in the DB use semantic wiring JSON (`from_output → to_input`)
- At runtime, `_resolve_outputs_for_run()` uses **extension-based matching** (`_EXT_TO_PARAM` dict) not the semantic labels
- The semantic labels are display-only in the UI (`PipelineListView`)
- New chains can reference any existing workflow by ID — the executor resolves file paths from the DB

**Remaining gap:** The system still generates fresh Nextflow process code for non-wrapper tools rather than `include`-ing a matched nf-core subworkflow. The `nf-core-modules/subworkflows/nf-core/` library (93 entries) is available but not automatically searched during composition. Adding a "find matching nf-core subworkflow → include it" step between L2 and L3 would improve reuse of tested modules.

---

## C. QC in Workflows vs the BioMate QC Gate

### Two Separate QC Systems

**System 1: Pipeline-embedded QC (e.g., FastQC, MultiQC)**
- Part of the scientific workflow — nf-core/rnaseq always runs FastQC and MultiQC
- Purpose: generate human-readable QC reports for the scientist to interpret
- Output: HTML reports in `results/multiqc/`, PNG plots, per-sample stats
- Triggered by: the Nextflow process graph — always runs if wired
- No enforcement: does not stop execution if samples fail

**System 2: BioMate QC Gate (`NextflowQCGateHandler` in `qc_trace_monitor.py`)**
- Platform governance layer — monitors the Nextflow trace file in real time
- Purpose: enforce QC thresholds according to named profiles and red lines
- Output: SSE events to the UI (PASS / ADVISORY / BLOCKING), audit log entries
- Triggered by: "process completed" events in the Nextflow trace file
- Enforcement: can emit BLOCKING gates that surface prominently in the UI (but does not currently abort the Nextflow run itself)

### How They Relate

```
Nextflow run starts
    │
    ├─ FastQC runs (pipeline QC)
    │   └─ Produces: multiqc_report.html, per-sample stats
    │
    ├─ BioMate QC Gate reads trace file
    │   └─ On "FASTQC COMPLETED":
    │       ├─ Parses: duplication rate, total sequences, per-base quality
    │       ├─ Compares to: rnaseq_default profile thresholds
    │       └─ Emits: SSE event to UI (PASS / ADVISORY / BLOCKING)
    │
    ├─ STAR_ALIGN runs
    │   └─ Produces: alignment BAM files
    │
    └─ BioMate QC Gate reads trace
        └─ On "STAR_ALIGN COMPLETED":
            ├─ Parses: uniquely mapped %, multi-mapped %
            ├─ Checks: mapped_pct >= 70 (GOLD, non-overridable)
            └─ Emits: SSE event
```

**Design coherence:** The two systems are complementary. FastQC generates the data; the QC Gate enforces policy. There is **no conflict** — they operate at different levels. The pipeline's MultiQC HTML is preserved for researcher review; the Gate provides machine-readable enforcement.

### QC Gate Consistency with nf-core Pipelines (2026-03-30 audit)

**Total workflows: 2,435** (not 230 — the 230 figure refers only to `nfcore` full-pipeline source; bioconductor and biomni_nextflow workflows are additional).

The QC gate (`qc_trace_monitor.py`) recognizes **95+ process parsers** covering:
- FastQC, MultiQC, STAR_ALIGN, HISAT2, BOWTIE2, BWA, Salmon, Kallisto
- PICARD MarkDuplicates, samtools flagstat/depth/coverage, featureCounts
- CellRanger, STARsolo, Alevin (single-cell)
- MACS2/3 peak calling, deepTools bamCoverage
- Kraken2, MetaPhlAn (metagenomics)
- RELION, cryoSPARC, MotionCor2, CTFFIND, Gautomatch (cryo-EM)
- DIA-NN, OpenSWATH (proteomics)

Process names are recognized by `process_upper` substring matching — compatible with nf-core trace format since nf-core uses `TOOL_SUBTOOL` naming which the parsers match. The trace file format (`.nextflow/trace.txt`) is standardized across all nf-core pipelines.

**Known gap:** ~35% of nf-core's 230 pipelines use domain-specific processes not yet in the parser registry (e.g., nanoseq, crisprseq, hic). These processes complete without QC gate evaluation (no BLOCKING/ADVISORY emitted). This is safe — the gate only fires when it recognizes a process.

### QC HTML Reports — UI Accessibility

MultiQC and FastQC HTML outputs ARE properly surfaced:
- `classifyFileType()` in `routes.ts` checks `interactiveExts = ['html', 'htm']` **before** `textExts`, so HTML files are classified `'interactive'`
- Interactive outputs render as sandboxed iframes in `chat-output-attachments.tsx` with "Open in New Tab" and "Download" buttons
- File filter at line 6482 in `routes.ts` explicitly allows `'html'` extensions

**Gap still open:** For direct Nextflow runs (not Galaxy-registered), HTML files in `--outdir/multiqc/` are only accessible if the output scanner (`addRuntimeArtifactOutputs`) traverses subdirectories. The scanner does `fs.readdirSync(outdir)` — it may miss deeply nested `multiqc/multiqc_report.html`. A recursive scan or explicit `**/multiqc_report.html` glob would fix this.

### QC Profile Selection — Current Solution

QC profiles are **pre-inferred at workflow generation time** by `_infer_qc_profile()` in `ai_assistant.py`:

| Workflow | Inferred Profile |
|----------|-----------------|
| nf-core/rnaseq (ENCODE samples) | `rnaseq_encode4` |
| nf-core/rnaseq (low input) | `rnaseq_low_input` |
| nf-core/sarek (germline) | `wgs_germline_standard` (auto from domain) |
| nf-core/sarek (tumor-only) | `wgs_somatic_tumor_only` |
| Proteomics + phospho tags | `proteomics_phospho` |
| Cryo-EM + phase plate | `cryoem_spa_phase_plate` |
| Drug discovery compounds | `compound_druglike` |
| PK/PD / pharmacokinetics | `compound_druglike` (merged domain) |

The profile is shown in the workflow viewer header (`workflowDefinition?.qc_profile`) before the user clicks "Run". For common well-characterized workflows (nf-core/rnaseq, nf-core/sarek), the correct profile is always pre-set automatically.

**Gap:** The user cannot manually select a QC profile from a dropdown — the UI exposes only threshold overrides (key-value pairs in `execution-control-panel.tsx`). Adding a profile selector dropdown showing the 30+ named profiles would make QC configuration more transparent, particularly for edge cases where auto-inference returns `None`.

**Profile list (30+ curated):** rnaseq_polya_standard, rnaseq_ribodepleted, rnaseq_ffpe, rnaseq_single_nucleus, rnaseq_nonmodel_organism, rnaseq_encode4, rnaseq_low_input, wgs_germline_standard, wgs_germline_lowpass, wgs_somatic_tumor_only, wgs_ffpe, wes_research, wes_clinical_germline, scrna_standard, scrna_cardiac, scrna_neuronal, scrna_perturbation, metagenomics_human_gut, metagenomics_soil, metagenomics_marine, metagenomics_clinical_pathogen, cryoem_spa_purified, cryoem_spa_membrane, cryoem_spa_phase_plate, cryoem_tomo_in_situ, proteomics_standard, proteomics_phospho, proteomics_plasma_biomarker, proteomics_chemoproteomics, compound_druglike, compound_natural_product, compound_peptidomimetic, pgx_clinical, pgx_research.

---

## D. Workflow Chain Mechanism

### What Exists

**8 curated chains** are defined in the database (seeded from `index_all_workflows.py`):

| Chain Name | Steps | Use Case |
|-----------|-------|----------|
| `rare_disease_multimodal_workup` | 5 | WGS + RNA-seq + clinical integration |
| `bulk_rnaseq_de_analysis` | 3 | FASTQ → alignment → DESeq2 |
| `single_cell_multimodal_analysis` | 5 | scRNA + ATAC + protein |
| `cutandtag_chromatin_analysis` | 3 | CUT&TAG processing to peak calling |
| `alternative_polyadenylation_analysis` | 2 | FASTQ → APA quantification |
| `drug_discovery_screening` | 3 | ADMET → docking → binding affinity |
| `drug_discovery_admet_gated_screening` | 3 | Pharmacophore → ADMET → Vina docking |
| `target_to_lead_full` | 6 | Pocket detection → pharmacophore → ADMET → docking → MD/MM-GBSA → REINVENT4 |

### Chain Execution Architecture

```
User: "Run target-to-lead for EGFR"
         │
         ▼
  AssistantIntent: workflow_generation, type=chain
         │
         ▼
  POST /api/workflows/chain
  { steps: [{nextflow_path, params}, ...] }
         │
         ▼
  workflow_chain.py: _run_chain()
  ┌──────────────────────────────────┐
  │ Step 1: execute_nextflow(step1)  │
  │   → wait for completion          │
  │ Step 2: _resolve_outputs_for_run │
  │   → scan outdir for files        │
  │   → match extensions → params   │
  │   → execute_nextflow(step2,params│
  │ Step 3: same...                  │
  └──────────────────────────────────┘
```

### Output → Input Wiring

The curated chain JSON defines semantic wiring:
```json
{"from_step": 1, "from_output": "filtered_compounds", "to_step": 2, "to_input": "compounds"}
```

But the **runtime executor** does NOT use these labels. It uses extension-based inference:
```python
_EXT_TO_PARAM = {
    "fastq": ["reads", "input", "fastq", "fastq_input"],
    "bam":   ["bam", "input_bam", "alignments", "input"],
    "vcf":   ["vcf", "input_vcf", "variants"],
    "sdf":   ["ligand_sdf", "compounds", "molecules"],
}
```

**Gap:** The semantic connections in the curated JSON (`filtered_compounds → compounds`) are for UI display only. The actual wiring uses file extension matching. If step 1 produces a `.sdf` file of filtered compounds, and step 2 expects `--compounds`, the extension match `sdf → compounds` will correctly wire them. But if naming conventions differ, it silently fails to wire and uses only explicitly-set params.

### Pre-flight Type Compatibility Check

Before running a chain, `check_step_compatibility` validates that the output types of step N match the expected input types of step N+1, using `input_types` and `output_types` columns from the `workflows` table. This is the A1 feature (type-safe pipeline wiring).

### When to Use Chains (and When Not To)

**Use chains when:**
- The analysis is a known, multi-step research pattern (RNA-seq DE, drug discovery)
- The steps have clear data dependencies (output from step 1 is input to step 2)
- The user describes an end-to-end project, not just one analysis

**Do NOT use chains for:**
- One-off analysis: "run nf-core/rnaseq" (single workflow, not a chain)
- Exploratory queries: "what tools exist for ADMET?" (tool search, not execution)
- Independent analyses without data dependencies: "run both DESeq2 and edgeR on the same dataset" (parallel, not sequential)

**Current limitation:** The chain mechanism is sequential only — step N must complete before step N+1 starts. The UI (`PipelineListView`) can display parallel groups but the executor doesn't support them.

---

## E. Visualization Resources

### BioMate Viewer Components

Located in `frontend/client/src/components/viewers/`:

| Component | Handles | Display |
|-----------|---------|---------|
| `vcf-viewer.tsx` | VCF variant files | Table with consequence, gene, frequency |
| `sequence-viewer.tsx` | FASTA/FASTQ | Sequence display with annotation |
| `annotation-viewer.tsx` | GFF/GTF annotation | Genome annotation browser |
| `csv-table-viewer.tsx` | CSV/TSV tabular data | Paginated table with sorting |
| `structure-viewer.tsx` | PDB/mmCIF molecular structures | 3D viewer via 3Dmol.js |
| `density-map-viewer.tsx` | MRC/CCP4 cryo-EM density maps | 3D density visualization |
| `interactive-tool-launcher.tsx` | HTML-based tools (IGV, JBrowse, Jupyter) | Galaxy Interactive Tools iframe |

### How Outputs Are Routed to Viewers (`ChatOutputAttachments`)

The output display system fetches `/api/invocations/{id}/outputs` and classifies each file:

```
fileType = "image"       → <img> tag via /api/outputs/{id}/display
fileType = "interactive" → iframe via /api/outputs/{id}/display (for HTML reports)
fileType = "table"       → CSV table preview
fileType = "sequence"    → sequence-viewer
fileType = "variants"    → vcf-viewer
fileType = "structure"   → structure-viewer (PDB)
fileType = "singlecell"  → single-cell visualization
```

### nf-core HTML Reports

nf-core pipelines produce HTML reports as standard output:
- **FastQC**: per-sample HTML with quality metrics
- **MultiQC**: aggregate HTML combining all QC stats
- **nf-core/rnaseq**: produces `multiqc_report.html` in `results/multiqc/`
- **nf-core/sarek**: produces `multiqc_report.html` + variant annotation reports

These HTML files are classified as `fileType: "interactive"` when registered as Galaxy outputs. The UI renders them in a sandboxed iframe with "Open in New Tab" and "Download" options.

### Galaxy Interactive Tools (Parallel Path)

The `InteractiveToolLauncher` suggests launching specific Galaxy Interactive Tools based on output file types:
- `.h5ad` → CellxGene (single-cell)
- Notebook format → JupyterLab
- `.bam` + genome → IGV
- Taxonomy/OTU data → Phinch
- Multiple format → RStudio

This provides a **parallel visualization path** — instead of inline display, the user gets a full interactive environment.

### Potential Conflicts and Resolution

| Scenario | Inline Viewer | Interactive Tool | Which wins? |
|---------|---------------|-----------------|------------|
| MultiQC HTML | iframe in chat | (none) | Inline — HTML is classified `interactive` |
| scRNA `.h5ad` | Single-cell viewer | CellxGene | User choice — both offered |
| Genome alignment `.bam` | (none currently) | IGV | IGV only |
| Structure `.pdb` | 3Dmol.js inline | (none) | Inline |
| Tabular results `.csv` | CSV table preview | RStudio | Both offered |

**Current state:** There is no conflict enforcement — the system may offer both options simultaneously. For `.h5ad`, a user sees both an inline single-cell viewer and a CellxGene launch button. This is additive rather than conflicting.

**Gap:** MultiQC/FastQC HTML reports from Nextflow direct execution (not Galaxy-registered) may not be surfaced automatically. The inline viewer only works for outputs registered in Galaxy's output system. For `nextflow run` direct executions, results are in the filesystem at `--outdir` but not automatically displayed. A file browser or "view results" button for direct Nextflow runs would improve UX significantly.

---

## Recommendations

### Immediate (Pre-release)
1. Add a "View Results" file browser for direct Nextflow execution outputs (the HTML reports are there but not surfaced)
2. Document for users that `workflow_chains` semantic wiring is display-only; actual output→input uses extension matching
3. Test QC gate compatibility with the 5 most common nf-core pipelines explicitly

### Near-term
4. Add a workflow composition feature: when generating a custom workflow, search for existing nf-core subworkflows that match each step and `include` them
5. Add process name registry test so QC gate alerts on unrecognized process names
6. Support parallel chain steps in the executor (currently display-only)
