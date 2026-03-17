# BioMate Workflow Sources — Inventory, Locations & Overlap Analysis

*Last updated: 2026-03-10*

---

## 1. Directory Map

```
backend/
├── nf-core-modules/                       ← Community nf-core library (git clone)
│   ├── modules/nf-core/                   │  1,651 individual tool modules
│   │   └── <tool>/[<subcommand>/]main.nf  │  (samtools/sort, star/align, …)
│   └── subworkflows/nf-core/              │  94 composite subworkflows
│       └── <name>/main.nf                 │  (bam_sort_stats_samtools, …)
│
├── nf-core-workflows/                     ← Full nf-core pipelines (git clone)
│   ├── rnaseq/                            │  STAR/Salmon RNA-seq
│   ├── sarek/                             │  germline/somatic variant calling
│   ├── chipseq/                           │  ChIP-seq peak calling
│   ├── methylseq/                         │  bisulfite methylation
│   ├── diaproteomics/                     │  DIA proteomics
│   ├── proteomicslfq/                     │  LFQ proteomics
│   └── differentialabundance/             │  differential abundance
│
├── biomni_workflows/
│   ├── nextflow_nfcore/
│   │   └── subworkflows/                  ← PRIMARY BioMate analysis workflows
│   │       ├── biochemistry/   (9)
│   │       ├── bioconductor/   (1818)     ← Bioconductor R-package modules
│   │       ├── bioengineering/ (13)
│   │       ├── bioimaging/     (22)       ← NF-only (no Galaxy predecessor)
│   │       ├── biophysics/     (2)
│   │       ├── cancer_biology/ (7)
│   │       ├── cell_biology/   (5)
│   │       ├── cryo_em/        (15)       ← NF-only
│   │       ├── cryo_et/        (5)        ← NF-only
│   │       ├── database/       (5)
│   │       ├── drug_discovery/ (3)        ← NF-only
│   │       ├── genetics/       (11)
│   │       ├── genomics/       (30)
│   │       ├── glycoengineering/(3)
│   │       ├── immunology/     (13)
│   │       ├── lab_automation/ (6)
│   │       ├── literature/     (4)
│   │       ├── microbiology/   (16)
│   │       ├── molecular_biology/(26)
│   │       ├── pathology/      (7)
│   │       ├── pharmacology/   (29)
│   │       ├── physiology/     (14)
│   │       ├── proteomics/     (1)        ← NF-only
│   │       ├── synthetic_biology/(10)
│   │       └── systems_biology/(12)
│   │
│   └── galaxy/
│       ├── workflows/          (122 .ga)  ← Original Galaxy conversion set
│       └── subworkflows/       (227 .ga)  ← Expanded Galaxy set
│           ← NOTE: NOT indexed — superseded by nextflow_nfcore/ above
│           ← EXCEPT: 2 unique items with no NF equivalent (see §4)
```

---

## 2. Workflow Index — Current State

The search index (`backend/database/galaxy_ai_tools.db`) holds **3,923 workflows**:

| Source | Format | Count | Search Priority | What it is |
|--------|--------|------:|:---:|---|
| `nfcore` | nextflow | 100 | **100** | Full nf-core pipelines (rnaseq, sarek, chipseq, …) |
| `nfcore_subwf` | nextflow | 93 | **95** | nf-core composite subworkflows (`nf-core-modules/subworkflows/`) |
| `nfcore_module` | nextflow | 1,645 | **90** | nf-core individual tool modules (`nf-core-modules/modules/`) |
| `biomni_nextflow` | nextflow | 268 | **85** | BioMate domain analysis workflows (Python, Docker-native) |
| `bioconductor` | nextflow | 1,812 | **75** | Bioconductor R-package nf-core process wrappers |
| `galaxy_biomni` | galaxy_ga | **2** | **35** | Unique BioMate Galaxy workflows — **no NF equivalent yet** |
| ~~`galaxy_local`~~ | — | 0 | — | **Removed** — were Galaxy-format copies of `nfcore_subwf` (redundant) |
| ~~`biomni`~~ | — | 0 | — | **Removed** — legacy Galaxy BioMate, superseded by `biomni_nextflow` |
| **Total** | | **3,923** | | |

---

## 3. Where the Galaxy Files Fit

### `galaxy_workflows/` (94 `.ga` files, formerly `galaxy_local`)

These are **Galaxy-format conversions of the 94 nf-core community subworkflows**.
The names are identical to those in `nf-core-modules/subworkflows/nf-core/`.
They are **no longer indexed** — the authoritative Nextflow originals from
`nf-core-modules/subworkflows/nf-core/` are indexed as `nfcore_subwf` instead.

### `galaxy/subworkflows/` (227 `.ga`) and `galaxy/workflows/` (122 `.ga`)

These are the BioMate-authored Galaxy workflows. **Not indexed** — their
Nextflow equivalents in `nextflow_nfcore/subworkflows/` are indexed as
`biomni_nextflow`. Only the 2 with no Nextflow equivalent are retained.

---

## 4. BioMate Galaxy Workflows Without a Nextflow Equivalent

Two BioMate-authored Galaxy workflows have not yet been converted to Nextflow.
They are indexed as `galaxy_biomni` (priority 35) as a fallback:

| Domain | Workflow | Function | Status |
|--------|----------|----------|--------|
| `synthetic_biology` | `identify_fas_functional_domains` | Identifies functional domains in a Fatty Acid Synthase (FAS) sequence | Pending NF conversion |
| `biophysics` | `predict_protein_disorder_regions` | Predicts intrinsically disordered regions (IDRs) via IUPred2A | Pending NF conversion |

Additionally, 9 `support_tools/` Galaxy utilities (REPL, plot capture, Synapse download)
have no Nextflow equivalent **by design** — they are internal Galaxy executor helpers.

---

## 5. NF-Only BioMate Workflows (No Galaxy Predecessor)

50 workflows in `biomni_nextflow` were written directly in Nextflow for domains
added after the Galaxy conversion sprint:

| Domain | Count | Notable workflows |
|--------|------:|---|
| `bioimaging` | 17 | nnUNet segmentation, image registration, NIfTI tools |
| `cryo_em` | 15 | CryoSPARC SPA, helical/filament refinement, topaz pick/train |
| `cryo_et` | 5 | Full ET pipeline, tiltseries import, subtomogram averaging |
| `drug_discovery` | 3 | Structure prediction + docking, scaffold hopping, PKNCA NCA |
| `genomics` | 5 | GEO data connector, Perturb-seq, trajectory inference, GATK germline WGS |
| `pharmacology` | 4 | IVIVE, nlmixr2 PopPK, QSAR random forest, NCA |
| `proteomics` | 1 | Chemoproteomics pull-down |
| **Total** | **50** | |

---

## 6. Overlap Analysis

### nf-core subworkflows ↔ galaxy_workflows (now removed)

All 93–94 entries in `galaxy_workflows/` were exact Galaxy-format copies of
`nf-core-modules/subworkflows/nf-core/`. The Galaxy versions are no longer needed.

### BioMate Nextflow ↔ Galaxy subworkflows

| Galaxy source | Total | With NF equivalent | Without NF equiv |
|---|---:|---:|---:|
| `galaxy/subworkflows/` | 227 | 217 (96%) | 10 (4%) |
| `galaxy/workflows/` | 122 | 121 (99%) | 1 (1%) |

The 10 missing from `subworkflows/`: 8 are `support_tools` internals; 2 are listed in §4.

### Bioconductor ↔ other sources (6 packages skipped)

Bioconductor packages that overlap with already-indexed nfcore/biomni tools
are **skipped** during indexing to avoid duplicates:

| Package | Overlaps with |
|---------|--------------|
| `cafe` | nfcore_module |
| `muscle` | nfcore_module |
| `mygene` | nfcore_module or nfcore_subwf |
| `scds` | nfcore_module |
| `sparsesignatures` | nfcore_module |
| + 1 more | — |

The 3 key statistical tools (DESeq2, edgeR, limma) are **not** duplicated:
- The `nfcore_module` entries cover them as tool modules
- The `bioconductor` versions provide R-package-level wrappers with upstream/downstream metadata

In practice the nf-core full pipeline (priority 100) or nfcore_module (90) is
served when the user asks for an end-to-end workflow; the Bioconductor module
(75) is served when the user explicitly requests the R package.

---

## 7. Source Priority and Dispatch Logic

```
nfcore (100) → nfcore_subwf (95) → nfcore_module (90) → biomni_nextflow (85)
→ bioconductor (75) → galaxy_biomni (35, fallback only)
```

| User request | Served from | Reason |
|---|---|---|
| "Run RNA-seq on my FASTQs" | `nfcore/rnaseq` | Full pipeline, highest priority |
| "Sort and QC a BAM file" | `nfcore_subwf/bam_sort_stats_samtools` | Composite subworkflow |
| "Align reads with STAR" | `nfcore_module/star/align` | Individual tool module |
| "Model microbial dynamics" | `biomni_nextflow/microbiology` | No nf-core equivalent |
| "Run DESeq2" | `nfcore_module` → `bioconductor/deseq2` | Both exist; nfcore_module wins |
| "CryoSPARC SPA pipeline" | `biomni_nextflow/cryo_em` | NF-only domain |
| "Identify FAS domains" | `galaxy_biomni/synthetic_biology` | No NF equivalent yet |

---

## 8. Re-indexing

```bash
# Standard rebuild (no bioconductor — fast, ~2s)
python3 backend/scripts/index_all_workflows.py --rebuild

# Full rebuild including all Bioconductor modules (~10s)
python3 backend/scripts/index_all_workflows.py --rebuild --include-bioconductor

# Incremental — only add workflows not yet in DB
python3 backend/scripts/index_all_workflows.py
```

---

## 9. Outstanding Gaps

| Item | Priority | Action needed |
|------|:--------:|---|
| Convert `synthetic_biology/identify_fas_functional_domains` to Nextflow | High | Write `main.nf` in `nextflow_nfcore/subworkflows/synthetic_biology/` |
| Convert `biophysics/predict_protein_disorder_regions` to Nextflow | Medium | Write `main.nf` in `nextflow_nfcore/subworkflows/biophysics/` |
| Add more nf-core full pipelines (atac-seq, ampliseq, mag, …) | Low | Clone pipelines to `nf-core-workflows/`, update `NFCORE_PIPELINES` dict |
