# BioMate Workflow Sources — Inventory, Locations & Overlap Analysis

*Last updated: 2026-03-10*

---

## 1. Architecture: Two Tables, Two Roles

`galaxy_ai_tools.db` has two distinct collections:

| Table | Role | Searched by |
|-------|------|-------------|
| **`workflows`** | Complete analysis pipelines and multi-step subworkflows | `UnifiedWorkflowSearch` |
| **`tools`** | Individual tool/package executors | `UnifiedToolSearch` |

The AI engine uses both: it finds the best **workflow** for the user's task,
and uses **tools** to understand what executors are available when composing
a new Galaxy workflow on the fly.

---

## 2. Directory Map

```
backend/
├── nf-core-modules/                         ← Community nf-core library (git clone)
│   ├── modules/nf-core/                     │  1,651 individual tool modules → tools table
│   │   └── <tool>/[<subcmd>/]
│   │       ├── main.nf                      │  process wrapper
│   │       └── meta.yml                     │  name, description, keywords, container
│   └── subworkflows/nf-core/                │  94 composite subworkflows → workflows table
│       └── <name>/
│           ├── main.nf
│           └── meta.yml
│
├── nf-core-workflows/                       ← Full nf-core pipelines → workflows table
│   ├── rnaseq/   chipseq/   sarek/
│   ├── methylseq/  diaproteomics/  ...
│
├── biomni_workflows/
│   ├── nextflow_nfcore/
│   │   └── subworkflows/                    ← BioMate analysis workflows → workflows table
│   │       ├── biochemistry/   (9)
│   │       ├── bioconductor/   (1818)       ← Bioconductor R modules (NOT indexed here;
│   │       │                                    2241 entries already in tools table)
│   │       ├── bioimaging/     (22)
│   │       ├── cancer_biology/ (7)
│   │       ├── cryo_em/        (15)  NF-only
│   │       ├── cryo_et/        (5)   NF-only
│   │       ├── drug_discovery/ (3)   NF-only
│   │       ├── genomics/       (30)
│   │       ├── pharmacology/   (29)
│   │       └── ... (24 domains total)
│   │
│   └── galaxy/
│       ├── subworkflows/   (227 .ga)        ← Galaxy source files; NOT indexed
│       └── workflows/      (122 .ga)        ← NOT indexed (superseded by NF equivalents)
│           2 unique items (no NF equiv) → galaxy_biomni in workflows table
```

---

## 3. Current Index State

### `workflows` table — 466 total

| Source | Count | Priority | What |
|--------|------:|:---:|---|
| `nfcore` | 100 | **100** | Full nf-core pipelines (rnaseq, sarek, chipseq, …) |
| `nfcore_subwf` | 93 | **95** | nf-core composite subworkflows (multi-tool analysis steps) |
| `biomni_nextflow` | 268 | **85** | BioMate domain analysis workflows (Python, Docker-native) |
| `galaxy_biomni` | 2 | **35** | Unique BioMate Galaxy workflows — **no NF equivalent yet** |

### `tools` table — 12,514 total

| Type | Count | `wrapper_path` set | Description |
|------|------:|:---:|---|
| Galaxy ToolShed | ~10,821 | — | Community Galaxy tools (CLI, R, Python) |
| nf-core modules | 1,645 | ✅ all | Individual tool wrappers (`star/align`, `samtools/sort`, …) |
| Bioconductor | 2,273 | ✅ 1,818 | R package entries; 1,818 linked to `.nf` file on disk; 455 have embedded `nextflow_process_template` in `nfcore_metadata` JSON instead |

**Bioconductor NF wrapper files on disk:**
`backend/biomni_workflows/nextflow_nfcore/subworkflows/bioconductor/<pkg>/main.nf` (1,818 files)
→ linked via `tools.wrapper_path = "nextflow_nfcore/bioconductor/<pkg>/main.nf"` for 1,818 entries.
The 455 tools entries with no `.nf` file on disk still contain an equivalent `nextflow_process_template`
embedded in their `nfcore_metadata` JSON column, generated from the Bioconductor vignette scrape.

---

## 4. Why This Split

**`nf-core modules`** (1,651 `main.nf` files under `nf-core-modules/modules/`) are
single-process wrappers for individual bioinformatics tools — exactly analogous to
the 10,000+ Galaxy ToolShed entries. They belong in the `tools` table, not `workflows`.

**`nf-core subworkflows`** (94 `main.nf` files under `nf-core-modules/subworkflows/`)
compose multiple modules into a meaningful multi-step operation (e.g.
`bam_sort_stats_samtools` = sort + index + stats + flagstat + idxstats). They are
**composite pipelines** and belong in the `workflows` table.

**Bioconductor modules** are single R-package process wrappers. They were already
correctly indexed in the `tools` table (2,241 entries with `tool_id LIKE 'bioconductor/%'`)
before this work. They are **not** re-added to `workflows`.

---

## 5. BioMate Galaxy Workflows Without a Nextflow Equivalent

Two BioMate-authored Galaxy workflows are indexed as `galaxy_biomni` (priority 35,
fallback only) pending Nextflow conversion:

| Domain | Workflow | Function |
|--------|----------|----------|
| `synthetic_biology` | `identify_fas_functional_domains` | Identifies functional domains in a Fatty Acid Synthase sequence |
| `biophysics` | `predict_protein_disorder_regions` | Predicts intrinsically disordered regions via IUPred2A |

8 `support_tools/` Galaxy utilities (REPL, plot capture, Synapse download) have no
Nextflow equivalent **by design** — internal Galaxy executor helpers only.

---

## 6. NF-Only BioMate Domains (No Galaxy Predecessor)

50 `biomni_nextflow` workflows were written directly in Nextflow for domains added
after the initial Galaxy conversion sprint:

| Domain | Count | Notes |
|--------|------:|---|
| `bioimaging` | 17 | nnUNet segmentation, image registration, NIfTI tools |
| `cryo_em` | 15 | CryoSPARC SPA, helical/filament refinement, Topaz pick/train |
| `cryo_et` | 5 | Full ET pipeline, tiltseries import, subtomogram averaging |
| `drug_discovery` | 3 | Structure + docking, scaffold hopping, PKNCA |
| `genomics` | 5 | GEO connector, Perturb-seq, trajectory inference, GATK germline |
| `pharmacology` | 4 | IVIVE, nlmixr2 PopPK, QSAR RF, NCA |
| `proteomics` | 1 | Chemoproteomics pull-down |

---

## 7. Galaxy Source Files and Conversion Coverage

| Galaxy source | Total `.ga` | With NF equivalent | Missing NF equiv |
|---|---:|---:|---:|
| `galaxy/subworkflows/` | 227 | 217 (96%) | 10 (4%) |
| `galaxy/workflows/` | 122 | 121 (99%) | 1 (1%) |

The 10 missing from `subworkflows/`: 8 are `support_tools` internals; 2 listed in §5.
The `galaxy_workflows/` directory (94 files) contained Galaxy-format copies of
`nf-core-modules/subworkflows/` — **not indexed** (Nextflow originals used instead).

---

## 8. Dispatch Logic

```
WORKFLOW search (UnifiedWorkflowSearch):
  nfcore (100) → nfcore_subwf (95) → biomni_nextflow (85) → galaxy_biomni (35)

TOOL search (UnifiedToolSearch):
  10821 Galaxy ToolShed + 1645 nf-core modules + 2241 Bioconductor = 14707 tools
```

| User request | Result |
|---|---|
| "Run RNA-seq end-to-end" | workflow: `nfcore/rnaseq` |
| "Sort and QC a BAM file" | workflow: `nfcore_subwf/bam_sort_stats_samtools` |
| "Align reads with STAR" | tool: `nfcore/star/align` |
| "Run DESeq2 on my counts" | tool: `bioconductor/deseq2` |
| "Model microbial dynamics" | workflow: `biomni_nextflow/microbiology` |
| "Identify FAS domains" | workflow: `galaxy_biomni/synthetic_biology` (fallback) |

---

## 9. Re-indexing

```bash
# Full rebuild (fast, ~5s)
python3 backend/scripts/index_all_workflows.py --rebuild

# Incremental (add new workflows/tools only)
python3 backend/scripts/index_all_workflows.py
```

---

## 10. Outstanding Gaps

| Item | Priority | Action |
|------|:--------:|--------|
| Convert `synthetic_biology/identify_fas_functional_domains` to NF | High | Add `main.nf` to `nextflow_nfcore/subworkflows/synthetic_biology/` |
| Convert `biophysics/predict_protein_disorder_regions` to NF | Medium | Add `main.nf` to `nextflow_nfcore/subworkflows/biophysics/` |
| Add more nf-core pipelines (atacseq, ampliseq, mag, …) | Low | Clone to `nf-core-workflows/`, add to `NFCORE_PIPELINES` dict |
