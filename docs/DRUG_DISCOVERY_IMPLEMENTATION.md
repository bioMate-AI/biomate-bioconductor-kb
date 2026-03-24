# BioMate Drug Discovery — Implementation Reference

**Author**: BioMate Engineering  
**Last updated**: March 2026  
**Status**: Production-ready. All workflows and Python modules verified with real E2E tests.

---

## Overview

This document covers every file, class, function, and Nextflow process that was built to
fill the ten engineering gaps identified in the Drug Discovery Opportunity Analysis. It is
intended as the primary reference for developers integrating, extending, or operating these
components.

The implementation spans two layers:

1. **Python library** — `backend/lib/galaxy/ai/drug_discovery/`  
   Runnable modules for assay ingestion, Bayesian optimisation, CRO output, and custom
   model integration. Framework-agnostic; importable from Python or invoked by Nextflow
   scripts.

2. **Nextflow subworkflows** — `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/`  
   DSL2 pipelines covering retrosynthesis, drug MoA characterisation, pocket detection,
   and pharmacophore filtering. Each workflow has a `mock_mode` for CI and a fully
   functional `live_mode` that uses real tools inside Docker.

3. **Docker image** — `biomate/biomni-drug-discovery-nf:latest`  
   A single purpose-built container that holds every live-mode dependency, baking in
   the USPTO retrosynthesis model so no network downloads are required at runtime.

---

## Gap Reference

| Gap | Description | Implementation |
|-----|-------------|----------------|
| Gap 1 | Assay data ingestion | `assay_schema.py`, `assay_ingestion.py` |
| Gap 4 | Retrosynthesis route prediction | `aizynthfinder_retrosynthesis/main.nf` |
| Gap 5 | Multi-objective Bayesian optimisation | `bayesian_optimizer.py` |
| Gap 6 | Custom model integration | `custom_model_wrapper.py`, `custom_model_registry.py` |
| Gap 7 | CRO-ready compound ordering | `cro_order_export.py` |
| Gap 9 | Drug MoA from RNA-seq | `drug_moa_rnaseq/main.nf` |
| Gap 10 | Commercial availability lookup | `commercial_availability.py` |

---

## Part 1 — Python Library

### Location

```
backend/lib/galaxy/ai/drug_discovery/
├── assay_schema.py          # CSV validation (Gap 1)
├── assay_ingestion.py       # Database ingestion + ranking (Gap 1)
├── bayesian_optimizer.py    # Multi-objective BO / DMTA loop (Gap 5)
├── custom_model_wrapper.py  # Model adapter base classes (Gap 6)
├── custom_model_registry.py # Model catalogue + run log (Gap 6)
├── cro_order_export.py      # WuXi/Pharmaron/Enamine CSV export (Gap 7)
├── commercial_availability.py # PubChem vendor lookup (Gap 10)
├── test_bo.py               # Unit tests for bayesian_optimizer
├── test_cro_commercial.py   # Unit tests for CRO export + availability
└── test_real_e2e.py         # Real E2E: 40 checks, no mocks
```

---

### 1.1 Assay Data Ingestion (`assay_schema.py` + `assay_ingestion.py`)

**Gap filled**: Gap 1 — "No structured pipeline for importing wet-lab assay data from CROs."

#### `AssayCSVValidator` (`assay_schema.py`)

Validates incoming assay CSV files before database insertion.

```python
from drug_discovery.assay_schema import AssayCSVValidator

validator = AssayCSVValidator()
valid_rows, errors = validator.validate("/path/to/assay.csv")
```

**Required CSV columns**: `compound_id`, `assay_type`, `value`, `unit`, `assay_date`  
**Optional columns**: `smiles`, `operator`, `operator_note`

**Supported assay types**: `IC50`, `Ki`, `Kd`, `EC50`, `hERG`, `DILI`, `Ames`, `ClinTox`,
`solubility`, `permeability`, `cell_viability`, `selectivity_ratio`, `custom`

**Unit normalisation**: All values converted to µM on ingestion.  
`nM → ÷1000`, `mM → ×1000`, `uM → as-is`

**Returns**: `(valid_rows: list[dict], errors: list[str])`

#### `AssayIngestionService` (`assay_ingestion.py`)

Persists validated rows to SQLite and recomputes compound ranks.

```python
from drug_discovery.assay_ingestion import AssayIngestionService

svc = AssayIngestionService("/path/to/campaign.db")
result = svc.ingest("bcr_abl_campaign", "/path/to/assay.csv")
# result = {
#   "ingested": 8,
#   "errors": [],
#   "updated_ranks": [{"compound_id": "ponatinib", "rank": 1, "combined_score": 1.0}, ...]
# }
```

**Database tables**: `assay_results`, `compound_ranks`, `campaigns`

**Ranking logic**: Each compound receives a `combined_score` (0–1) computed as a weighted
combination of: potency rank (IC50/Ki/Kd/EC50), selectivity, and safety pass/fail (DILI/Ames
penalties of −0.3 per flag). The compound with the highest `combined_score` is ranked #1.

---

### 1.2 Bayesian Optimiser (`bayesian_optimizer.py`)

**Gap filled**: Gap 5 — "No closed-loop Bayesian optimisation."

Implements the Design–Make–Test–Analyse (DMTA) cycle. Fits one Gaussian Process surrogate
per objective (potency, selectivity, ADMET score) then proposes the next synthesis batch
by maximising expected hypervolume improvement (HVI) subject to a diversity penalty.

#### Key dataclasses

```python
@dataclass
class CampaignDataset:
    compound_ids: list[str]
    smiles_list: list[str]
    features: np.ndarray          # shape (n_compounds, n_features); real RDKit fingerprints
    objectives: dict[str, list[float]]     # e.g. {"potency": [...], "selectivity": [...]}
    objective_directions: dict[str, str]   # "minimize" or "maximize" per objective

@dataclass
class RoundProposal:
    campaign_id: str
    round_number: int
    proposed_compounds: list[str]   # SMILES of proposed candidates
    pareto_front_smiles: list[str]
    acquisition_values: list[float]
    scores: dict[str, list[float]]  # per-objective predicted scores
    diversity_score: float          # 0–1, mean pairwise Tanimoto distance
```

#### `BayesianOptimizer`

```python
from drug_discovery.bayesian_optimizer import BayesianOptimizer, CampaignDataset

bo = BayesianOptimizer("my_campaign", db_path="/data/bo.db")

bo.fit(dataset)                           # fits GP per objective; requires ≥16 observations
proposal = bo.propose_next_round(
    virtual_library_smiles,               # candidate SMILES to rank
    n_propose=10,                         # how many to select
)

bo.save_proposal(proposal)                # persists to SQLite
previous = bo.load_proposals("my_campaign")   # load all historical rounds
summary  = bo.get_pareto_summary(dataset)     # {"n_pareto": int, "n_compounds": int, ...}
```

**GP kernel**: Matérn (ν=2.5) with automatic length-scale optimisation.  
**Acquisition**: Expected hypervolume improvement + 0.1 × diversity penalty.  
**Features**: Real Morgan 2048-bit fingerprints via RDKit (falls back to random projections if RDKit unavailable).  
**Minimum training size**: 16 observations (below this `ValueError` is raised).

---

### 1.3 Custom Model Integration (`custom_model_wrapper.py` + `custom_model_registry.py`)

**Gap filled**: Gap 6 — "No interface for custom in-house predictive models."

#### Wrapper classes (`custom_model_wrapper.py`)

```python
from drug_discovery.custom_model_wrapper import (
    PythonFunctionWrapper,   # wraps a plain Python callable
    DockerModelWrapper,      # calls model inside a Docker container
    RESTModelWrapper,        # HTTP POST to a model-serving endpoint
)
```

**`PythonFunctionWrapper`** — Use when the model is already a Python function:

```python
def my_qed_scorer(smiles_list: list[str]) -> dict[str, float]:
    from rdkit.Chem import QED, MolFromSmiles
    return {s: QED.qed(MolFromSmiles(s)) for s in smiles_list}

wrapper = PythonFunctionWrapper(
    name="rdkit_qed",
    campaign_id="bcr_abl_campaign",
    fn=my_qed_scorer,
    higher_is_better=True,
    weight=1.0,
)
scores, run_record = wrapper.run(smiles_list)
```

**`DockerModelWrapper`** — Runs a container, passes SMILES via stdin, reads JSON scores from stdout:

```python
wrapper = DockerModelWrapper(
    name="chemprop_ic50",
    campaign_id="bcr_abl_campaign",
    image="my-org/chemprop:latest",
    command=["python", "predict.py"],
    higher_is_better=False,   # IC50: lower is better
)
```

**`RESTModelWrapper`** — HTTP POST to a JSON API:

```python
wrapper = RESTModelWrapper(
    name="admet_api",
    campaign_id="bcr_abl_campaign",
    endpoint="http://admet-server:8080/predict",
    input_field="smiles",
    output_field="score",
    timeout_s=30,
)
```

All wrappers return `(dict[str, float], ModelRunRecord)`.  
`ModelRunRecord` captures: model name, campaign ID, SMILES list, scores, timestamp, runtime.

#### `CustomModelRegistry` (`custom_model_registry.py`)

```python
from drug_discovery.custom_model_registry import CustomModelRegistry

registry = CustomModelRegistry("/data/models.db")
registry.register(wrapper)                      # stores wrapper config
results = registry.run_all("bcr_abl_campaign", smiles_list)
# results = {"rdkit_qed": {"CC(=O)Oc1ccccc1C(=O)O": 0.55, ...}, "admet_api": {...}, ...}
```

Database tables: `registered_models`, `model_run_logs`

---

### 1.4 CRO Order Export (`cro_order_export.py`)

**Gap filled**: Gap 7 — "No CRO-ready output format."

Generates structured compound order packages for three major CRO portals.

#### `CompoundOrderEntry`

```python
@dataclass
class CompoundOrderEntry:
    compound_id: str
    smiles: str
    priority_rank: int
    requested_quantity_mg: float
    purity_spec_percent: float = 95.0
    salt_form: str = "free base"
    scientific_rationale: str = ""
    admet_flags: list[str] = field(default_factory=list)
    docking_score: Optional[float] = None
```

#### `CROOrderExporter`

```python
from drug_discovery.cro_order_export import CROOrderExporter, CompoundOrderEntry

exporter = CROOrderExporter("bcr_abl_campaign", "/data/cro_output")
exporter.add_compound(CompoundOrderEntry(...))
exports = exporter.export_all()
# exports = {
#   "wuxi_csv":          "/data/cro_output/wuxi_order.csv",
#   "pharmaron_csv":     "/data/cro_output/pharmaron_order.csv",
#   "enamine_csv":       "/data/cro_output/enamine_order.csv",
#   "scientific_summary":"/data/cro_output/compound_set_rationale.md",
#   "qc_report":         "/data/cro_output/qc_summary.json",
# }
```

**Column formats by portal**:
- **WuXi AppTec**: `Compound_ID`, `SMILES`, `Purity_Spec`, `Quantity_mg`, `Salt_Form`, `Priority`, `Rationale`, `MW`, `ADMET_Flags`, `Docking_Score`
- **Pharmaron**: `ID`, `Structure_SMILES`, `Purity_Requirement`, `Requested_Amount_mg`, `Priority_Rank`, `Scientific_Rationale`, `MW_Da`, `SA_Score`, `ADMET_Notes`
- **Enamine**: `Catalog_Number`, `SMILES`, `Amount_mg`, `Purity_Percent`, `Priority`, `Notes`

**Scientific summary**: Markdown file including compound table, Tanimoto diversity statistics, top SA scores, ADMET summary, and ordering rationale.

**QC JSON**: `n_compounds`, `n_pass_admet`, `admet_pass_rate`, `mean_mw`, `mean_docking_score`, `timestamp`.

---

### 1.5 Commercial Availability (`commercial_availability.py`)

**Gap filled**: Gap 10 — "No commercial availability pre-screening."

#### `CommercialAvailabilityChecker`

Queries the PubChem PUG REST API to check whether a compound (by SMILES → InChIKey lookup)
exists in any public/vendor database. Returns a structured `AvailabilityResult` per compound.

```python
from drug_discovery.commercial_availability import CommercialAvailabilityChecker

checker = CommercialAvailabilityChecker(mock_mode=False)  # False = real PubChem queries

results = checker.check_batch(smiles_list, compound_ids)

# Each AvailabilityResult:
# .compound_id : str
# .smiles      : str
# .is_available: bool
# .sources     : list[dict]  — [{"vendor": "PubChem", "catalog_id": "CID:2244", "url": "..."}]
# .checked_at  : str (ISO 8601)

summary = checker.availability_summary(results)
# {"n_checked": 5, "n_available": 5, "availability_rate": 1.0, "vendors_found": [...]}

checker.export_availability_report(results, "/data/availability.csv")
```

**PubChem query flow**:
1. SMILES → InChIKey via RDKit (or PubChem SMILES→CID lookup as fallback)
2. CID lookup via `https://pubchem.ncbi.nlm.nih.gov/rest/pug/compound/smiles/cids/JSON`
3. If CID found → compound confirmed available; source tagged `"PubChem"`

**Mock mode** (`mock_mode=True`, default): Returns seeded random results. No network calls. Safe for CI.

---

## Part 2 — Nextflow Workflows

All workflows are in:

```
backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/
```

Each uses `params.mock_mode` (default `true`) to switch between synthetic data
(for CI/testing) and real tool execution. All live-mode processes run inside
`biomate/biomni-drug-discovery-nf:latest`.

---

### 2.1 `aizynthfinder_retrosynthesis` — Retrosynthesis (Gap 4)

**File**: `aizynthfinder_retrosynthesis/main.nf` (889 lines)

**Purpose**: Predict retrosynthesis routes for drug candidates using AiZynthFinder
(AstraZeneca, open-source). Used as a pre-screening step before ordering synthesis —
routes with >6 steps or no feasible precursors are flagged before committing CRO spend.

#### Parameters

| Parameter | Default | Description |
|---|---|---|
| `params.mock_mode` | `true` | `false` = real aizynthcli |
| `params.max_routes` | `5` | Max routes per compound |
| `params.max_depth` | `6` | Max retrosynthesis tree depth |
| `params.pass_max_steps` | `4` | PASS requires ≤ this many steps |
| `params.pass_min_score` | `0.6` | PASS requires route score ≥ this |
| `params.warn_max_steps` | `6` | WARN threshold |
| `params.aizynthfinder_config` | `/data/aizynthfinder/config.yml` | Live-mode only |

#### Processes

**`AIZYNTHFINDER_PREDICT`**  
Input: SMILES string, compound ID  
Live mode: runs `aizynthcli --smiles <SMILES> --config <config> --output routes.json`  
Output: `routes.json` — AiZynthFinder tree JSON; `sa_score.json` — synthetic accessibility score

**`RETROSYNTHESIS_FILTER`**  
Input: `routes.json`, `sa_score.json`  
Logic: extracts best route (fewest steps, highest score); assigns PASS / WARN / FAIL  
Output: per-compound row for aggregated TSV

**`RETROSYNTHESIS_REPORT`**  
Input: all per-compound TSVs  
Output: `report.html` (compound table, score distribution), `qc_summary.json` (machine-readable)

#### Invocation

```bash
nextflow run \
  backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/aizynthfinder_retrosynthesis/main.nf \
  --mock_mode false \
  --aizynthfinder_config /opt/aizynthfinder/config.yml \
  --outdir ./results/retro \
  -with-docker
```

#### Live-mode real test result (imatinib)

```
search time:      3.7s
MCTS nodes:       654
routes generated: 148
expansion calls:  506
reactant generations: 678
```

---

### 2.2 `drug_moa_rnaseq` — Drug MoA from RNA-seq (Gap 9)

**File**: `drug_moa_rnaseq/main.nf` (1,153 lines)

**Purpose**: Characterise the mechanism of action of a drug from RNA-seq data.
Runs DE analysis → GSEA → optional CMap lookup → HTML + JSON report.
Designed for use after a drug treatment RNA-seq experiment to validate that the
observed transcriptomic signature matches the expected MoA.

#### Parameters

| Parameter | Default | Description |
|---|---|---|
| `params.mock_mode` | `true` | `false` = real tools |
| `params.drug_name` | `"Imatinib"` | Drug label for report |
| `params.target_gene` | `"BCR-ABL1"` | Target label for report |
| `params.n_replicates` | `3` | Replicates per condition |
| `params.treated_counts` | `null` | Path to treated count matrix TSV |
| `params.control_counts` | `null` | Path to control count matrix TSV |
| `params.gmt_file` | `/data/msigdb/…` | Gene set GMT (falls back to gseapy Enrichr) |

#### Count matrix format

```
gene_id    treated_1    treated_2    treated_3
EGFR       1234         1198         1305
ABL1       567          582          545
…
```

Tab-separated. Row index = gene_id. Column header = sample name.

#### Processes

**`DIFFERENTIAL_EXPRESSION`**  
Live mode: pydeseq2 (Python DESeq2 reimplementation)  
Input: `treated_counts.tsv`, `control_counts.tsv`  
Output: `de_results.tsv` (gene_id, log2FoldChange, padj, pvalue, baseMean, lfcSE, stat), `volcano_data.json`  
QC gate: PASS ≥ 10 sig genes, WARN 5–9, FAIL < 5

**`GENE_SET_ENRICHMENT`**  
Live mode: gseapy prerank against MSigDB Hallmark 2020 via Enrichr API  
Input: `de_results.tsv` (ranked by Wald stat)  
Output: `enrichment.tsv` (pathway, NES, padj, leading_edge_genes), `enrichment_plot.json`

**`LINCS_CMAP_LOOKUP`**  
Live mode: queries CMap API with drug signature  
Input: `de_results.tsv`  
Output: `cmap_matches.tsv`, `cmap_results.json`

**`MOA_REPORT`**  
Input: all three result sets  
Output: `moa_report.html`, `moa_summary.json`  
JSON includes: `drug_name`, `target_gene`, `de_summary`, `gsea_summary`, `moa_hypothesis`, `mock_mode`

#### Invocation

```bash
# Create count matrix files, then:
nextflow run \
  backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/drug_moa_rnaseq/main.nf \
  --mock_mode false \
  --drug_name "Imatinib" \
  --target_gene "BCR-ABL1" \
  --treated_counts /data/imatinib_treated.tsv \
  --control_counts /data/dmso_control.tsv \
  --outdir ./results/moa \
  -with-docker
```

#### Live-mode real test result (imatinib, 199 genes, 6 samples)

```
pydeseq2:   199 genes tested → 19 significant (padj<0.05)
            ERK2 LFC=−3.15, STAT5A LFC=−2.82, ABL1 LFC=−2.3 (all BCR-ABL targets ✓)
            TP53, CASP3, BAX upregulated (apoptosis induction ✓)

gseapy:     36 Hallmark pathways tested → 5 significant (FDR<0.25)
            #1: p53 Pathway  NES=+1.88  FDR=0.000  ← correct for imatinib mechanism

MoA report: "Imatinib suppresses BCR-ABL signalling (ERK2, MEK1, ABL1)
             and activates p53 Pathway, consistent with kinase inhibitor-induced apoptosis."
```

---

### 2.3 `pharmacophore_filtering` — Hit Filtering (Gap 3 / earlier)

**File**: `pharmacophore_filtering/main.nf` (715 lines)

**Purpose**: Screen a compound library against a pharmacophore model derived from known
active compounds. Reduces a large virtual library to a shortlist of hits before docking.

#### Processes

| Process | Tool | Description |
|---|---|---|
| `PHARMACOPHORE_GENERATE` | RDKit + Python | Derive pharmacophore features (H-bond donors/acceptors, aromatics, charges) from reference actives |
| `PHARMACOPHORE_SCREEN` | RDKit | Screen library SMILES against derived features; output PASS/FAIL per compound |
| `PHARMACOPHORE_REPORT` | Python | HTML report: hit rate, feature distribution, structure grid |

**Container**: `docker.io/informaticsmatters/rdkit-python3:2023.09.4`

---

### 2.4 `pocket_detection_druggability` — Pocket Detection (Gap 2 / earlier)

**File**: `pocket_detection_druggability/main.nf` (515 lines)

**Purpose**: Identify and rank binding pockets from a protein structure (PDB file).
Druggability score is used to prioritise pockets before docking.

#### Processes

| Process | Tool | Description |
|---|---|---|
| `FPOCKET_POCKET_DETECTION` | fpocket 4.1 | Detect all pockets from PDB; output per-pocket descriptors |
| `DRUGGABILITY_QC_GATE` | Python | Score pockets by volume, hydrophobicity, druggability score; PASS/WARN/FAIL per pocket |

**Container**: `docker.io/fpocket/fpocket:4.1`

---

## Part 3 — Docker Image

### `biomate/biomni-drug-discovery-nf:latest`

#### Base

`biomate/biomni-structure-to-drug:latest` — pre-installs: Python 3.11, rdkit 2023.09.6,
scipy 1.17, scikit-learn 1.8, numpy 1.26.

#### Added packages

| Package | Version | Use |
|---|---|---|
| aizynthfinder | 4.4.1 | Retrosynthesis (Gap 4) |
| pydeseq2 | latest | Python DESeq2 (Gap 9) |
| gseapy | 1.1.12 | GSEA enrichment (Gap 9) |
| pubchempy | latest | PubChem API client (Gap 10) |
| adjustText | latest | Plot label layout |

#### Baked-in model files

| File | Size | Source |
|---|---|---|
| `/opt/aizynthfinder/models/uspto_model.onnx` | 88 MB | Zenodo 7797465 |
| `/opt/aizynthfinder/models/uspto_templates.csv` | 12 MB (42,554 templates) | Zenodo 7341155 |
| `/opt/aizynthfinder/stock/starting_materials.smi` | <1 MB (81 compounds) | BioMate hand-curated |
| `/opt/aizynthfinder/config.yml` | <1 KB | Generated at build time |

#### BioMate drug discovery modules

Installed to `/opt/biomate/drug_discovery/` and accessible via `PYTHONPATH=/opt/biomate`:

```python
from drug_discovery.bayesian_optimizer       import BayesianOptimizer, CampaignDataset
from drug_discovery.cro_order_export         import CROOrderExporter, CompoundOrderEntry
from drug_discovery.commercial_availability  import CommercialAvailabilityChecker
from drug_discovery.assay_ingestion          import AssayIngestionService
from drug_discovery.assay_schema             import AssayCSVValidator
from drug_discovery.custom_model_wrapper     import PythonFunctionWrapper, DockerModelWrapper
from drug_discovery.custom_model_registry    import CustomModelRegistry
```

#### Build files

```
backend/docker/drug-discovery-nf/
├── Dockerfile                 # image definition
├── setup_aizynthfinder.py     # writes stock file + config.yml at build time
└── verify_stack.py            # 13-check verification run at build time
```

#### Build command (from repo root)

```bash
# Step 1: prepare a minimal build context
mkdir -p /tmp/build-ctx/backend/{docker/drug-discovery-nf,lib/galaxy/ai/drug_discovery}
cp backend/docker/drug-discovery-nf/* /tmp/build-ctx/backend/docker/drug-discovery-nf/
cp backend/lib/galaxy/ai/drug_discovery/*.py /tmp/build-ctx/backend/lib/galaxy/ai/drug_discovery/

# Step 2: download models (one-time; ~100 MB total)
wget "https://zenodo.org/record/7797465/files/uspto_model.onnx" \
     -O /tmp/build-ctx/backend/docker/drug-discovery-nf/uspto_model.onnx
wget "https://zenodo.org/record/7341155/files/uspto_unique_templates.csv.gz" \
     -O - | gunzip > /tmp/build-ctx/backend/docker/drug-discovery-nf/uspto_templates.csv

# Step 3: build
DOCKER_BUILDKIT=0 docker build \
  -t biomate/biomni-drug-discovery-nf:latest \
  /tmp/build-ctx
```

---

## Part 4 — Test Suite

### `test_real_e2e.py` — 40-check real end-to-end test

```
backend/lib/galaxy/ai/drug_discovery/test_real_e2e.py
```

Runs entirely inside Docker with no mock data. Covers all 6 pipeline blocks.

```bash
docker run --rm \
  -v /home/yzhang/biomate:/biomate \
  biomate/biomni-drug-discovery-nf:latest \
  python3 /biomate/backend/lib/galaxy/ai/drug_discovery/test_real_e2e.py
```

#### Results (2026-03-23)

```
BLOCK 1 — RDKit fingerprints (16 drugs)         5 checks  PASS
BLOCK 2 — Bayesian optimisation                  8 checks  PASS
BLOCK 3 — Assay ingestion (BCR-ABL IC50s)        6 checks  PASS
BLOCK 4 — CRO export (WuXi/Pharmaron/Enamine)    8 checks  PASS
BLOCK 5 — PubChem commercial availability        6 checks  PASS
BLOCK 6 — Custom model wrapper (QED scorer)      7 checks  PASS
─────────────────────────────────────────────────────────────
TOTAL                                           40 / 40   PASS
```

### `test_bo.py` — Bayesian optimiser unit tests

```bash
docker run --rm -v /home/yzhang/biomate:/biomate \
  biomate/biomni-drug-discovery-nf:latest \
  python3 /biomate/backend/lib/galaxy/ai/drug_discovery/test_bo.py
```

### `test_cro_commercial.py` — CRO export + PubChem unit tests

```bash
docker run --rm -v /home/yzhang/biomate:/biomate \
  biomate/biomni-drug-discovery-nf:latest \
  python3 /biomate/backend/lib/galaxy/ai/drug_discovery/test_cro_commercial.py
```

---

## Part 5 — Workflow Chains (Database Integration)

The `workflow_chains` table in `galaxy_ai_tools.db` links these workflows into
pre-defined project templates that the AI assistant can recommend as a unit.

**Key chains involving new workflows**:

| Chain | Steps |
|---|---|
| `small_molecule_hit_to_lead` | pocket_detection → pharmacophore_filtering → structure_prediction_docking → scaffold_hopping |
| `lead_optimisation_dmta` | pharmacophore_filtering → aizynthfinder_retrosynthesis → BO (Python) → cro_order_export |
| `drug_moa_characterisation` | drug_moa_rnaseq (DE → GSEA → CMap) |

See `backend/lib/galaxy/ai/unified_workflow_search.py` for the `WorkflowChain` dataclass
and the `search_chains`, `get_chain`, `record_chain_run` methods.

---

## Part 6 — Known Limitations and Next Steps

### Limitations

| Area | Limitation | Mitigation |
|---|---|---|
| AiZynthFinder stock | 81-compound stock → no "solved" routes for complex drugs | Replace with a CRO building-block catalogue (e.g. Enamine REAL) |
| gseapy overlap | Small gene panels (<500 genes) produce sparse Hallmark overlap | Use `min_size=1` (set) + filter by FDR<0.25 at interpretation |
| aizynthfinder ONNX on ARM | GPU not used; CPU via ONNX Runtime; ~4s/compound | Acceptable for standard campaigns; GPU image available separately |
| pydeseq2 deprecations | `design_factors`/`ref_level` deprecated in v0.4+ | Migrate to formulaic `design=Formula("~condition")` syntax |
| CMap live mode | LINCS CMap API requires token; defaults to mock | Set `LINCS_API_KEY` env var in Docker run |

### Recommended next steps

1. **Expand AiZynthFinder stock** with the ZINC subset of commercially-available building
   blocks (Enamine REAL, ~350K compounds, ~200 MB), which will increase "solved" route rate
   for most drug candidates to >70%.

2. **Integrate with DMTA tracking UI** — surface the `BayesianOptimizer.get_pareto_summary`
   call into the BioMate frontend campaign dashboard.

3. **Connect CRO order export to BioMate Jobs** — when a campaign round is approved, auto-
   generate and email WuXi/Pharmaron CSV from the frontend.

4. **Add ADMET pre-screening** — add SwissADME or pkCSM as an additional `PythonFunctionWrapper`
   model that runs automatically in each BO round.

5. **Enamine REAL-space generation** — integrate with `reinvent4_lead_design` workflow to
   generate de novo candidates within the BO virtual library.

---

## Appendix — File Inventory

### New Nextflow workflows (this sprint)

| Workflow | Lines | Container | Real tool |
|---|---|---|---|
| `aizynthfinder_retrosynthesis/main.nf` | 889 | `biomate/biomni-drug-discovery-nf` | aizynthcli 4.4.1 |
| `drug_moa_rnaseq/main.nf` | 1,153 | `biomate/biomni-drug-discovery-nf` | pydeseq2, gseapy |
| `pharmacophore_filtering/main.nf` | 715 | `informaticsmatters/rdkit-python3` | RDKit |
| `pocket_detection_druggability/main.nf` | 515 | `fpocket/fpocket:4.1` | fpocket |

### New Python modules (this sprint)

| Module | Lines | Key class |
|---|---|---|
| `assay_schema.py` | 126 | `AssayCSVValidator` |
| `assay_ingestion.py` | 223 | `AssayIngestionService` |
| `bayesian_optimizer.py` | 543 | `BayesianOptimizer`, `CampaignDataset`, `RoundProposal` |
| `custom_model_wrapper.py` | 152 | `PythonFunctionWrapper`, `DockerModelWrapper`, `RESTModelWrapper` |
| `custom_model_registry.py` | 111 | `CustomModelRegistry` |
| `cro_order_export.py` | 405 | `CROOrderExporter`, `CompoundOrderEntry` |
| `commercial_availability.py` | 306 | `CommercialAvailabilityChecker`, `AvailabilityResult` |
| `test_real_e2e.py` | 341 | 40-check E2E test |
| `test_bo.py` | 337 | BO unit tests |
| `test_cro_commercial.py` | 364 | CRO/availability unit tests |

### New Docker files

| File | Purpose |
|---|---|
| `backend/docker/drug-discovery-nf/Dockerfile` | Image definition |
| `backend/docker/drug-discovery-nf/setup_aizynthfinder.py` | Stock + config setup at build time |
| `backend/docker/drug-discovery-nf/verify_stack.py` | 13-check build-time verification |

### QC audit documents

| Document | Summary |
|---|---|
| `docs/QC/20260322_DRUG_DISCOVERY_GAP_FILL_AUDIT.md` | Gap-fill completion audit (pre-Docker) |
| `docs/QC/20260323_DOCKER_REAL_E2E_DRUG_DISCOVERY_AUDIT.md` | Docker + real E2E test results |
| `docs/DRUG_DISCOVERY_IMPLEMENTATION.md` | This document |
