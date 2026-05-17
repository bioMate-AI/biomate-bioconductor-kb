# BioMate capability alignment — ANDV campaign vs platform reality

**Purpose**: Connect `MASTER_ANDV_CAMPAIGN_GUIDE.md` and the three `*_IMPLEMENTATION.md` tracks to how BioMate actually delivers drug-development steps **without** treating Claude-authored pseudocode as literal Python imports.

**Authoritative platform map**: `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` (updated through **2026-05-01**) — pipeline stages, ✅ internal vs 🔌 external tooling, workflow IDs, and coverage scorecard (**~79%** overall at last revision).

**Last reviewed**: 2026-05-07

---

## 0. Indexed workflows and tools (canonical inventory)

BioMate does **not** require guessing tool names: workflows and Galaxy-scale tools are stored and full-text indexed in SQLite.

| Artifact | Location | Count (verified 2026-05-07) |
|----------|----------|-------------------------------|
| **Unified DB** | `backend/database/galaxy_ai_tools.db` | ~271 MB |
| **Workflow index** | `workflows` table + `workflows_fts` (FTS5) | **2494** rows |
| **Tool index** | `tools` table + `tools_fts` | **12 274** rows |
| **Curated chains** | `workflow_chains` | **13** rows |
| **Workflow JSON on disk** | `backend/lib/galaxy/ai/data/workflows/*.json` | **951** files (export/subset; search uses DB) |

**Workflows by `source`** (top entries): `bioconductor` ~1818, `biomni_nextflow` ~259, `nfcore` ~230, `nfcore_subwf` ~93, `nextflow` ~56, `biomate` ~32, …

**Routing code**: `backend/lib/galaxy/ai/unified_workflow_search.py` — `UnifiedWorkflowSearch`, `DB_PATH`, `get_stats()`, FTS + optional **BGE** embeddings (`workflow_embeddings`). The AI assistant refers to **950+ / 2400+** indexed workflows depending on context; the DB is the source of truth.

**ANDV-relevant examples** (`domain='drug_discovery'` or name match), by **numeric `id` in DB**:

| id | name | source |
|----|------|--------|
| 10787 | Run Autosite | biomni_nextflow |
| 12824 | Docking Autodock Vina | biomni_nextflow |
| 10788 | Run Diffdock With Smiles | biomni_nextflow |
| 12801 | Schrodinger Glide Docking | biomni_nextflow |
| 10644 | Structure Prediction Docking | biomni_nextflow |
| 12805 | Pocket Detection Druggability | biomni_nextflow |
| 12700 | nf-core/epitopeprediction | nfcore |
| 12819 | P0 Mrna Validation | biomni_nextflow |
| 12799 | GROMACS Protein-Ligand MD + MM-GBSA | biomate |
| 12800 | REINVENT4 Generative Lead Design | biomate |

**Ad hoc queries** (run from repo root):

```bash
sqlite3 backend/database/galaxy_ai_tools.db \
  "SELECT id, name, source FROM workflows WHERE domain='drug_discovery' ORDER BY name LIMIT 50;"
```

So: campaign pseudocode maps to **workflow IDs and routed Galaxy/Biomni/nf-core pipelines** in this index — not to nonexistent `import biomate.*` packages.

---

## 1. Semantic pseudocode (Claude-authored plans)

The inhibitor and vaccine implementation markdown files contain blocks that **look like** `from biomate.structural import …` or `biomate.docking`. Those fragments are **semantic instructions**: they name *intent* (pocket search, dock a library, rank by ADMET, optimize batches) in a familiar programming shape. They are **not** guaranteed to match a single import path in this repository.

**How to read them**

| Pseudocode intent | Practical BioMate realization |
|-------------------|-------------------------------|
| Pocket / AutoSite | Route **AutoSite pocket detection** via Biomni/Galaxy/Nextflow (`run_autosite`, pharmacology toolstack) — see coverage map **Stage 0**. |
| Docking (Vina / Glide / DiffDock) | Route **structure-based docking** workflows (e.g. AutoDock Vina, GlideScore in auto-loop QC per coverage doc) — **Stage 1**. |
| ADMET triage / panels | Route **Predict ADMET** and related QC gates (benchmarked ADMET profiling ~89.3% in doc) — **Stages 1–2**; results can attach to **campaigns** (CRO workspace). |
| Bayesian / DMTA | **`backend/lib/galaxy/ai/drug_discovery/`** + `/api/drug-discovery/.../propose`, assay ingestion, CRO export — **Stage 4 DMTA loop** in coverage diagram. |
| Generative / MD / RBFE | Platform lists **REINVENT4, GROMACS, OpenFE RBFE** etc. — **Stage 3**; invoke via **validated workflows**, not a flat `biomate.*` SDK. |
| Vaccine: epitope / MHC | **nf-core/epitopeprediction** — coverage doc notes wrapper **workflow id=12700** (immunogenicity / T-cell epitope gap section). |
| mRNA / LNP | **LNP formulation optimisation**, **NP PK** — **Specialty: Nucleic Acid / LNP** section of coverage doc (**~76%** LNP/NP track); not a literal `LNPSimulator` class in-repo. |

So: **gap vs plans is mostly notation**, not absence of capability — provided teams **route through BioMate workflows and backends** named in the coverage analysis.

---

## 2. What is *not* the same as the pseudocode

- There is **no** checked-in Python package tree `biomate.structural`, `biomate.docking`, `biomate.immunology`, `biomate.synthetic_biology` as shown in campaign markdown.
- **`backend/lib/galaxy/ai/drug_discovery/`** implements **campaigns, Bayesian proposals, assay ingestion, regulatory/CRO exports** — not a replacement for standalone PyMOL or Schrödinger GUIs.
- **Syncraft** synthesizability remains **stub / external API** per coverage doc — CONNECT gap.
- **Benchling**, **in vivo** uploads, **patient data**: external boundaries unchanged from coverage analysis.

---

## 3. Recommended integration map — ANDV inhibitor track

1. **Structures** — RCSB downloads (**9P3I**, **9P3Y**, optional **9P3X/M/L**); script: `research/anti-virus/scripts/fetch_guo_structures.sh`. Details: `GUO_ET_AL_CELL2026_READING_NOTES.md`.
2. **Target / pocket** — Align with **Stage 0** coverage: AutoSite + druggability workflows; optional **tractability scorer** (workflow **id=12879** per coverage doc).
3. **Hit discovery** — Align with **Stage 1**: DrugCLIP / Vina / DiffDock / pharmacophore / ADMET triage as **routed workflows**, then export ranked SMILES + scores for campaigns.
4. **H2L / LO** — Use **Stage 2–3** tools as needed (ADMET suite, MD/RBFE, etc.) per coverage doc scorecard.
5. **DMTA** — Drug-discovery **campaign + propose + ingest assays**; wire Benchling/CRO CSV when available.

---

## 4. Recommended integration map — vaccine tracks A / B

1. **Epitopes / MHC** — Use **nf-core/epitopeprediction** (workflow **id=12700** reference in coverage doc) or equivalent external NetMHC; store outputs under campaign data — not `from biomate.immunology import MHCPredictor`.
2. **Protein / VLP (Plan A)** — Expression + analytics are **CRO / lab**; structural layers align with **Biologics** coverage (Boltz/Chai, ScFv tools where relevant).
3. **mRNA-LNP (Plan B)** — Align with **Nucleic Acid / LNP** section: **LNP formulation**, **P0 mRNA validation**, **NP PK** workflows — manufacturing and stability remain **CRO + real-time studies**, matching CONNECT/DATA boundaries in the coverage doc.

---

## 5. Documentation conventions for campaign markdown

- Keep pseudocode as **readable intent**; add a one-line comment where helpful: *“Semantic — route via BioMate Stage N workflows (see coverage analysis).”*
- Prefer linking **`docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`** over inventing new package names.
- When a step is 🔌 or 🔌🔌 in the coverage doc, the plan should say **external API**, **CRO upload**, or **patient data** — not “missing BioMate feature.”

---

## 6. File index (implementation shortcuts)

| Capability area | Where to start in-repo |
|-----------------|-------------------------|
| **Workflow / tool search** | `backend/database/galaxy_ai_tools.db`, `unified_workflow_search.py` |
| Campaign / BO / propose | `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py`, `api_router.py` |
| DMTA demo script | `scripts/run_dmta_simulation.py` |
| AutoSite (Biomni) | `Biomni/biomni/tool/pharmacology.py` → `run_autosite`; workflow id **10787** |
| Galaxy AutoSite | `backend/biomni_workflows/galaxy/tools/biomni/pharmacology/run_autosite.xml` |
| Example Vina | Workflow **12824**, `backend/tools/biomni_generated/pharmacology_docking_autodock_vina/` |
| Full pipeline legend | `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` (mermaid + tables) |

---

## 7. Running AutoSite (workflow **10787**)

The indexed workflow maps to `backend/biomni_workflows/nextflow_nfcore/subworkflows/pharmacology/run_autosite/main.nf`.

### 7a. BioMate default: AWS Batch (`POST /api/nextflow/execute`)

With `NEXTFLOW_USE_AWS=true` in backend `.env`, the executor defaults to **awsbatch** and `profile` resolves to **`aws`**. Upload the receptor to the deployment bucket (default **`biomate-nextflow-work`**), then call the API with **`pdb_file`** set to **`s3://…`** and `"compute_config": {"executor": "awsbatch"}`. The Nextflow process stages **`s3://` inputs** to a local path before the embedded Biomni Python runs (see `main.nf`). Example batch submissions and S3 output prefixes: `research/anti-virus/runs/20260508_batch_autosite/AWS_BATCH_RUNS.json`.

**End-to-end monitored test (real pockets + QC, no ADFR binary):** workflow **12805** pocket detection + druggability — run `research/anti-virus/scripts/e2e_biomate_batch_monitor.py` with `--pdb-input s3://…/your.pdb`. Recorded run: `research/anti-virus/runs/e2e_batch_latest/E2E_RUN_RECORD.json`. RCSB **mmCIF-only** entries (no `.pdb` at `files.rcsb.org`) need a converted PDB (e.g. `research/anti-virus/scripts/cif_to_pdb.py`) uploaded to S3 first.

### 7b. Local Nextflow + Docker (`biomate/biomni-tools`)

```bash
nextflow run . -profile docker \
  --pdb_file /absolute/path/to/receptor.pdb \
  --output_dir ./autosite_work \
  --outdir /absolute/path/to/results_outdir
```

**Containers are linux/amd64 only** (`docker inspect` shows `Architecture=amd64`). On **aarch64** hosts (many Grace/ARM dev boxes), Docker may fail before Python runs with errors such as `exec /bin/bash: no such file or directory` when amd64 emulation is missing or broken. Alternatives: **x86_64 Linux**, working **binfmt/QEMU** for amd64 images, or **§7a** Batch.

**Structure prep for Guo deposits**: mmCIF from RCSB can be converted to PDB (first model) with `research/anti-virus/scripts/cif_to_pdb.py` so `params.pdb_file` matches what `prepare_receptor` expects.

---

**Version**: 1.5 — §7a E2E monitor script + mmCIF-only RCSB caveat.
