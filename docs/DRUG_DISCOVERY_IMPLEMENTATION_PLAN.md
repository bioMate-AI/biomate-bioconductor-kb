# Drug Discovery Gap Implementation Plan

**Date:** 2026-03-10
**Status:** In Progress
**Source:** `BioMate_DrugDiscovery_Opportunity_Analysis.md`

---

## Overview

Six gaps have been confirmed against the drug discovery introduction and study proposal. All six are committed as pre-study or near-term builds. Implementation runs in four parallel tracks.

| Track | What | Effort | Owner | Status |
|---|---|---|---|---|
| A | Pocket detection + druggability workflow | 3 days | Engineering | Building |
| B | Pharmacophore filtering workflow | 1 week | Engineering | Building |
| C | Assay data ingestion endpoint | 1–2 weeks | Engineering | Building |
| D | Custom model wrapper interface | 2–3 weeks | Engineering | Building |
| E | CRO compound order output | 1 week | Engineering | Queued |
| F | Drug MoA characterisation pipeline | 1 week | Engineering | Queued |

Tracks A–D start in parallel immediately. E–F start after A–D complete.

---

## Track A — Pocket Detection and Druggability Workflow

**Output file:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf`

**What it does:**
1. Accept a PDB or AlphaFold-output PDB as input
2. Run fpocket to detect all cavities
3. Score each pocket: volume (Å³), druggability score (0–1), hydrophobicity, polarity, fraction of pocket lined by aliphatic/aromatic residues
4. Return ranked JSON of pocket sites with visualisable coordinates
5. QC gate: flag as non-druggable if best pocket volume < 300 Å³ or druggability score < 0.5 (BRONZE tier; adjustable)

**Mock mode:** Synthetic pocket JSON with realistic values for a kinase-like protein.
**Live mode:** fpocket Docker container (`docker.io/fpocket/fpocket:latest`).

**Inputs:**
```
tuple val(meta), path(protein_pdb)
```
**Outputs:**
```
pocket_json     — ranked list of pockets with all scores
top_pocket_pdb  — PDB with pocket alpha-spheres for visualisation
druggability_qc — PASS/WARN/FAIL gate result
versions.yml
```

**Index update:** Add to `galaxy_ai_tools.db` workflow table under `drug_discovery` domain, source `biomni_nextflow`.

---

## Track B — Pharmacophore Filtering Workflow

**Output file:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/pharmacophore_filtering/main.nf`

**What it does:**
1. Accept a set of reference active compounds (SMILES) and a screening library (SMILES/SDF)
2. Generate a consensus pharmacophore model: identify shared Donor, Acceptor, Aromatic, Hydrophobic, PosIonizable features using RDKit
3. Screen the library: score each compound by number of features matched and 3D feature distance (if 3D conformers generated)
4. Return filtered library ranked by pharmacophore match score; flag compounds matching ≥ N features (configurable, default 3)
5. Output SMILES of passing compounds for downstream docking

**Mock mode:** Synthetic pharmacophore scores from random uniform distribution with seeded random.
**Live mode:** RDKit MolChemicalFeatures + feature matching in Python; optional ConfGen for 3D conformers.

**Inputs:**
```
path reference_smiles   // file of known active SMILES (one per line)
path library_smiles     // library to screen
val  min_features       // minimum features to match (default 3)
```
**Outputs:**
```
filtered_smiles   — passing compounds with scores
pharmacophore_json — feature model with coordinates
match_report      — per-compound breakdown
versions.yml
```

---

## Track C — Assay Data Ingestion Endpoint

**Output files:**
- `backend/lib/galaxy/ai/drug_discovery/assay_ingestion.py` — core parser + memory updater
- `backend/lib/galaxy/webapps/galaxy/api/drug_discovery_assay.py` — FastAPI route
- `backend/lib/galaxy/ai/drug_discovery/assay_schema.py` — CSV schema definition + validator

**CSV template (standardised):**
```
compound_id, smiles, assay_type, value, unit, operator, assay_date, operator_note
CMPD-001, CC(=O)Oc1ccccc1C(=O)O, IC50, 0.45, uM, <, 2026-03-10, "replicate mean of 3"
CMPD-002, CC(=O)Oc1ccccc1C(=O)O, hERG, 12.3, uM, =, 2026-03-10, ""
CMPD-003, ..., DILI, 0, flag, =, 2026-03-10, "no signal at 50 uM"
```

**Supported assay types:** `IC50`, `Ki`, `Kd`, `EC50`, `hERG`, `DILI`, `Ames`, `ClinTox`, `solubility`, `permeability`, `cell_viability`, `selectivity_ratio`, `custom`

**Logic:**
1. Validate CSV against schema (required columns, type checks, unit normalisation)
2. Map each row to the `compound_id` that BioMate designed or screened in the current campaign
3. Append to campaign memory: `{compound_id, assay_type, value, unit, date, note, source: "wet_lab"}`
4. Recompute compound priority rank across all available evidence (in silico + experimental)
5. Return: updated ranked compound list + any compounds that newly pass/fail ADMET gates after experimental confirmation

**API endpoint:** `POST /api/drug-discovery/{campaign_id}/ingest-assay`
- Body: multipart CSV upload
- Returns: `{ingested: N, updated_ranks: [...], newly_failed: [...], newly_passed: [...]}`

---

## Track D — Custom Model Wrapper Interface

**Output files:**
- `backend/lib/galaxy/ai/drug_discovery/custom_model_wrapper.py` — adapter class
- `backend/lib/galaxy/ai/drug_discovery/custom_model_registry.py` — per-campaign registry
- `backend/lib/galaxy/webapps/galaxy/api/drug_discovery_models.py` — registration + invocation route

**Three integration modes:**

**Mode 1 — Python function**
```python
from biomate.drug_discovery import register_model

@register_model(name="my_gnn_affinity", campaign_id="camp-001",
                input_type="smiles_list", output_type="score_dict")
def my_model(smiles_list: list[str]) -> dict[str, float]:
    # user's existing scoring code, unchanged
    scores = gnn_model.predict(smiles_list)
    return {s: float(v) for s, v in zip(smiles_list, scores)}
```

**Mode 2 — Docker container**
```json
{
  "name": "my_affinity_model",
  "image": "myregistry/my-affinity-model:v1.2",
  "input_mount": "/input/smiles.txt",
  "output_mount": "/output/scores.json",
  "input_format": "smiles_one_per_line",
  "output_format": "json_smiles_to_score"
}
```

**Mode 3 — REST endpoint**
```json
{
  "name": "my_affinity_model",
  "endpoint": "http://internal-server:8080/predict",
  "method": "POST",
  "input_format": {"smiles": ["..."]},
  "output_path": "$.scores"
}
```

**What the wrapper does for all modes:**
- Calls the model with the current compound SMILES list
- Validates the output schema (must return {smiles → float} mapping)
- Logs: model name, version/tag, input count, output count, timestamp → audit trail
- Integrates scores into the BioMate integrated ranking: user configures weight and direction (higher = better or lower = better)
- Toggle on/off flag for reproducibility comparison (model disabled → BioMate built-in scores only)

**API endpoints:**
- `POST /api/drug-discovery/{campaign_id}/models/register` — register a model
- `POST /api/drug-discovery/{campaign_id}/models/{model_name}/run` — run on current compound set
- `GET  /api/drug-discovery/{campaign_id}/models` — list registered models + run history

---

## Track E — CRO Compound Order Output (Queued)

**Output file:** `backend/lib/galaxy/ai/drug_discovery/cro_order_export.py`

**What it does:** After BioMate proposes next-round compounds, generate a structured export:
- SMILES + compound ID + priority rank + requested quantity (mg) + purity spec + salt form
- Scientific rationale per compound (BioMate-generated, citing the assay outcomes and in silico scores that motivated the design)
- ADMET pre-filter summary of the proposed set
- Formats: WuXi AppTec CSV template, Pharmaron SDF+metadata, generic CSV

**API endpoint:** `GET /api/drug-discovery/{campaign_id}/export/cro-order?format=wuxi|pharmaron|generic`

---

## Track F — Drug MoA Characterisation Pipeline (Queued)

**Output file:** `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/drug_moa_rnaseq/main.nf`

**What it does:**
1. Accept bulk RNA-seq from drug-treated vs. vehicle-control cells
2. Run nf-core/rnaseq (STAR + salmon) for alignment and quantification
3. Run DESeq2 for differential expression
4. Query LINCS L1000 / CMap for gene signature similarity to known drug treatments
5. Run GSEA against MSigDB Hallmarks + pathway databases
6. Return: MoA hypothesis ranked by signature correlation, DE table, enriched pathways

**Connects to:** assay data ingestion (Track C) — transcriptomic response can be logged as an assay result with `assay_type: "moa_rnaseq"`

---

## Index Update

After each track completes, run:
```bash
cd backend && python scripts/index_all_workflows.py
```

New workflows (A, B, F) and the `pocket_detection_druggability` + `pharmacophore_filtering` chains should appear in the DB under `drug_discovery`.

Also add two new workflow chains to `CURATED_CHAINS` in `index_all_workflows.py`:
- `drug_discovery_admet_gated_screening`: ADMET → pharmacophore filter → Vina docking → ranking
- `target_to_lead_full`: pocket detection → pharmacophore filter → ADMET → docking → MM-GBSA → REINVENT4

---

## Definition of Done

| Track | Done when |
|---|---|
| A | `nextflow run main.nf` in mock mode exits 0; produces pocket JSON with ≥ 1 ranked pocket; added to DB index |
| B | `nextflow run main.nf` in mock mode exits 0; produces filtered SMILES and match report; added to DB index |
| C | `POST /ingest-assay` accepts the CSV template; returns updated ranks; campaign memory contains the ingested assay rows |
| D | All three integration modes (Python function, Docker, REST) callable; scores appear in integrated ranking; audit log written |
| E | `GET /export/cro-order?format=wuxi` returns valid WuXi-format CSV for a 20-compound proposal |
| F | `nextflow run main.nf` in mock mode exits 0; produces DE results + CMap similarity scores; added to DB index |
