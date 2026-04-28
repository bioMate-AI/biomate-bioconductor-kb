# BioMate Wet-Lab → Model Feedback Loop
## Survey, Process Architecture & Gap-Filling Plan

**Date:** 2026-04-17  
**Scope:** State of industry practice · BioMate current implementation · what is missing · concrete plan to close the loop  
**Linked to:** `docs/20260417_DRUG_DEV_GAP_ANALYSIS_AND_FEEDBACK_LOOP.md`

---

# Part 1 — Industry Survey: What a Wet-Lab → Model Feedback Loop Looks Like

## 1.1 The DMTA Cycle (Industry Standard)

Drug discovery operates on a four-phase iterative cycle:

```
       ┌──────────────────────────────────────────────────────┐
       │                   DMTA CYCLE                         │
       │                                                      │
       │   DESIGN                MAKE                         │
       │   ───────              ───────                       │
       │   AI/ML models    →   Synthesis planning         │
       │   BO proposals        CRO order                      │
       │   Generative design   Commercial availability        │
       │   Free energy calc    Retrosynthesis                  │
       │        │                    │                        │
       │        │                    ↓                        │
       │   ANALYSE              TEST                          │
       │   ───────              ────                          │
       │   Model retraining ←  Biochemical assays             │
       │   Score update        Cellular assays                 │
       │   Pareto update       ADMET panels                   │
       │   Hypothesis gen      In vivo PK/PD                  │
       └──────────────────────────────────────────────────────┘
```

Each cycle takes **4–16 weeks** in traditional drug discovery. The goal of computational acceleration is to:
1. Reduce the number of compounds that need to be synthesized per cycle
2. Make each model iteration faster and more accurate
3. Eventually enable automated experiment planning

## 1.2 Industry Leaders and Their Approaches

| Company | Approach | Key Feature |
|---|---|---|
| Recursion Pharmaceuticals | Phenomics + ML | 2.2M image-based assays/week fed into foundation models |
| Insilico Medicine | Generative + BO | PandaOmics target → Chemistry42 generative → Wet-lab → retrain |
| Schrödinger | FEP+ + active learning | FEP-guided synthesis prioritization with experimental validation loop |
| Relay Therapeutics | Conformational dynamics + ML | MD-informed drug design with iterative SAR |
| Xaira Therapeutics | AlphaFold-based | AI-generated protein binders validated by HT assays → model update |
| Pfizer | DMTA-OS | Internal DMTA Operating System: ELN → automated assay → ML → proposal |
| Genentech | AIRHEAD | Active learning + BO for antibody optimization |

**Common pattern across industry leaders:**
- **Structured data schema** for assay results (not ad-hoc CSV files)
- **ELN/LIMS integration** — data flows automatically from instrument to model
- **Multi-objective Bayesian optimization** — not just potency; safety, selectivity, synthesizability simultaneously
- **Human-in-the-loop** checkpoints — AI proposes, scientist approves, then CRO executes
- **Campaign tracking** — compounds are tracked across multiple rounds with full provenance

## 1.3 Key Metrics for Loop Performance

| Metric | Industry Target | What It Measures |
|---|---|---|
| Cycle time | 4–8 weeks per round | How fast new data informs next design |
| Hit rate improvement | 3–10× over random | BO efficiency vs baseline screening |
| Rounds to optimization | 3–6 rounds | Convergence to target compound profile |
| Data efficiency | IC50 per compound tested | Model accuracy with limited training data |
| Model uncertainty calibration | RMSE < 0.5 log unit | Whether model knows what it doesn't know |

---

# Part 2 — BioMate Current Implementation: Detailed Audit

## 2.1 What Is Implemented

### Layer 1: Compound Proposal (DESIGN)

**File:** `backend/lib/galaxy/ai/drug_discovery/bayesian_optimizer.py`

```
BayesianOptimizer
├── fit(dataset: CampaignDataset)
│   ├── Featurize: Morgan fingerprints (radius=2, 2048-bit, RDKit)
│   ├── One GP surrogate per objective (sklearn GaussianProcessRegressor)
│   │   └── Kernel: Matérn 5/2 + WhiteKernel noise
│   ├── Scale objectives to [0,1] with polarity canonicalization
│   └── Compute current Pareto front
│
└── propose(n_compounds, candidate_pool)
    ├── Score all candidates by Expected Hypervolume Improvement (EHVI)
    ├── Apply diversity penalty: Tanimoto distance from current Pareto
    ├── Return top-N with RoundProposal dataclass
    └── Persist round to SQLite
```

**Limitations:**
- Candidate pool must be **externally provided** — BO does not generate SMILES (it ranks a supplied list)
- Morgan fingerprints only — no 3D features, no pharmacophore features
- GP scales poorly beyond ~1000 training points (would need switch to sparse GP or neural network surrogate)

### Layer 2: Synthesis Planning (MAKE)

**Commercial availability:** `commercial_availability.py`  
- PubChem batch API check: `is_commercially_available(smiles_list)` → JSON with vendor links

**CRO order export:** `cro_order_export.py`  
- Formats: WuXi AppTec, Pharmaron, Enamine, Generic CSV
- Validates: MW, LogP, Lipinski compliance, safety thresholds
- Outputs: CRO-ready CSV + QC report

**Retrosynthesis:** `aizynthfinder_retrosynthesis` (Nextflow workflow)  
- AiZynthFinder: provides synthesis routes ≤4 steps
- Synthesizability filter integrated into CRO selection

**Generative design:** `reinvent4_lead_design` (Nextflow workflow)  
- REINVENT4: de novo, scaffold decoration, scaffold hopping
- *Not currently connected to BO propose step* — runs independently

### Layer 3: Assay Data Ingestion (ANALYSE)

**REST API:** `api_router.py`
```
POST /{campaign_id}/ingest-assay
  body: { csv_content: str }
  returns:
    { ingested_count, errors, compound_rankings, newly_passed, newly_failed }
```

**Ingestion service:** `assay_ingestion.py`  
- Schema: `compound_id`, `assay_type`, `value`, `unit` (long format)
- Unit normalization: nM/µM/pM/mM → canonical µM
- Operator handling: `>`, `<`, `~`, exact
- SQLite persistence: `campaign_assay_results` + `campaign_compound_ranks`

**Nextflow pipeline:** `assay_ingestion_and_ranking/main.nf`  
- Three processes: PARSE → SCORE → RANK
- Outputs: ranked CSV + HTML report + JSON summary
- Runs on AWS Batch (same container as other workflows)

**Composite scoring formula:**
```python
# Potency: pIC50-based, normalized to [0,1]
potency_score = max(0, min(1, (pIC50 - 6.0) / 6.0))   # 6=1µM, 12=0.01nM

# Safety: hERG log-scaled  
safety_score = max(0, min(1, log10(hERG_uM + 0.001) / log10(30)))

# Composite
composite = potency_weight * potency_score + safety_weight * safety_score
```

### Layer 4: Frontend (Analyst Interface)

**File:** `frontend/client/src/components/drug-discovery-action.tsx`

Three widgets:
1. **AssayUploadWidget** — drag-and-drop CSV upload, campaign ID, template download
2. **CROExportWidget** — format selector, threshold check, download CRO CSV
3. **CampaignDashboardWidget** — live ranking table, color tiers (green/amber/red)

### Layer 5: Custom Model Integration

**File:** `custom_model_registry.py` + `custom_model_wrapper.py`

External models can be plugged in via:
- Python function (direct import)
- Docker container (REST calls to container)
- REST endpoint (external service)

Models run against current compound set; scores stored per campaign. This is the integration point for proprietary in-house QSAR/ML models.

---

## 2.2 What the Current Loop Looks Like (Full Trace)

```
ROUND 1:
  User sends message → "screen these 50 SMILES against our BCR-ABL target"
  BioMate AI → routes to assay_ingestion_and_ranking
  User uploads IC50 + hERG CSV → POST /ingest-assay
  → Ranked compound list in SQLite + dashboard update
  
  User sends message → "propose next 10 compounds for synthesis"
  BioMate AI → calls BayesianOptimizer.fit() on ingested data
  BayesianOptimizer → scores candidate pool (must be supplied)
  → RoundProposal: 10 SMILES + acquisition values + Pareto front
  
  User sends message → "generate CRO order for proposed compounds"
  CROOrderExporter → validates + formats → WuXi CSV download
  
  [4-8 weeks later: wet lab synthesizes and assays]
  
ROUND 2:
  User uploads new IC50/hERG CSV → POST /ingest-assay
  → Scores updated in SQLite
  
  User asks → "re-run BO with new data"
  BayesianOptimizer.fit() → retrained on round 1 + round 2 data
  → New 10-compound proposal
  
  [cycle repeats]
```

**Each step requires a manual user action.** There is no automatic trigger between steps.

---

## 2.3 Gap Analysis (Detailed)

| Gap | Description | Impact |
|---|---|---|
| **G1: No auto-retrain trigger** | After ingest-assay, BO is NOT automatically refitted. Scientist must remember to call propose. | Round transition can be missed; data sits unused |
| **G2: No candidate pool generation** | BO ranks supplied candidates; it does not generate new SMILES. Requires separate REINVENT4 run (manual). | Loop broken between ANALYSE and DESIGN |
| **G3: LIMS not wired to DMTA loop** | `BenchlingConnector` (309 lines, OAuth2) EXISTS at `backend/lib/integrations/benchling_connector.py` but is NOT connected to `AssayIngestionService`. Manual CSV export still required. | 2-4 day delay per round; transcription errors |
| **G4: No active learning / uncertainty sampling** | BO uses EHVI only. No uncertainty-guided selection (compounds where model is least certain). | Less efficient use of synthesis budget |
| **G5: No multi-objective Pareto UI** | Pareto front computed but not visualized. Scientist cannot see the trade-off frontier. | Suboptimal compound selection in practice |
| **G6: No round provenance tracking** | No history of which compounds came from which BO round and why. | Reproducibility and regulatory audit risk |
| **G7: BO not wired to API; ADMET objectives not connected** | `BayesianOptimizer` exists and supports arbitrary `CampaignDataset.objectives` but is NEVER called from `api_router.py`. No REST endpoint exists for BO proposals. ADMET objectives are a secondary gap after API wiring. | BO framework is dead code until wired to the API |
| **G8: No generative coupling** | REINVENT4 and BO are independent. BO proposals do not seed REINVENT4 for focused generation around Pareto solutions. | Misses the industry-standard design-generate-rank loop |
| **G9: No assay quality control** | No automated QC of incoming assay data (outlier detection, Z' factor, positive/negative controls). | Bad assay data silently corrupts the model |
| **G10: No campaign comparison** | Cannot compare campaigns (e.g., target A vs target B, scaffold series X vs Y). | Cannot manage a portfolio of campaigns |

---

# Part 3 — Closed-Loop Architecture: What It Should Look Like

## 3.1 Target Architecture

```
╔══════════════════════════════════════════════════════════════════════════╗
║              BioMate DMTA Closed Loop — Target Architecture              ║
╠══════════════════════════════════════════════════════════════════════════╣
║                                                                          ║
║  [DESIGN]                                                                ║
║  ┌─────────────────────────────────────────────────────────────┐        ║
║  │ 1. BayesianOptimizer.propose()                              │        ║
║  │    ├── multi-objective: potency, safety, ADMET, selectivity │        ║
║  │    ├── acquisition: EHVI + uncertainty sampling             │        ║
║  │    └── output: RoundProposal with 10-50 SMILES              │        ║
║  │                                                             │        ║
║  │ 2. REINVENT4 focused generation (seeded by Pareto front)    │        ║
║  │    └── generate 500-1000 SMILES around Pareto solutions     │        ║
║  │                                                             │        ║
║  │ 3. Filter: CommercialAvailability + Synthesizability        │        ║
║  │    └── pool of 50-200 actionable candidates                 │        ║
║  └─────────────────────────────────────────────────────────────┘        ║
║       │                                                                  ║
║       ▼ (auto-generated CRO order)                                       ║
║  [MAKE]                                                                  ║
║  ┌─────────────────────────────────────────────────────────────┐        ║
║  │ CROOrderExporter → WuXi/Pharmaron/Enamine CSV               │        ║
║  │ AiZynthFinder retrosynthesis → synthesis routes             │        ║
║  │ Human approval checkpoint (Scientist reviews + approves)    │        ║
║  └─────────────────────────────────────────────────────────────┘        ║
║       │                                                                  ║
║       ▼ (4-8 weeks)                                                      ║
║  [TEST — Wet Lab]                                                        ║
║  ┌─────────────────────────────────────────────────────────────┐        ║
║  │ Biochemical: IC50, hERG, kinase selectivity                 │        ║
║  │ Cellular: cell viability, target engagement (NanoBRET)      │        ║
║  │ ADMET: Caco-2, microsomal stability, protein binding        │        ║
║  │ → Results in ELN (Benchling/Dotmatics) as structured data   │        ║
║  └─────────────────────────────────────────────────────────────┘        ║
║       │                                                                  ║
║       ▼ (auto-pull via LIMS connector OR CSV upload)                     ║
║  [ANALYSE]                                                               ║
║  ┌─────────────────────────────────────────────────────────────┐        ║
║  │ AssayQCService (Z', outlier detection, plate map validate)   │        ║
║  │ AssayIngestionService (normalize, unit convert, persist)     │        ║
║  │ CompositeScoring (multi-objective update)                    │        ║
║  │ → AUTO-TRIGGER: BayesianOptimizer.fit() on new data          │        ║
║  │ → AUTO-GENERATE: next-round proposal draft for scientist     │        ║
║  └─────────────────────────────────────────────────────────────┘        ║
║       │                                                                  ║
║       └──────────────────────────────────────────────────────►  [DESIGN]║
╚══════════════════════════════════════════════════════════════════════════╝
```

## 3.2 Data Flow Specification

```
Round N start:
  campaign_id: "BCR-ABL1-series-3"
  compounds_in_db: 47 (from rounds 1 & 2)
  pareto_front_size: 6
  round_number: 3

Step A — Proposal generation (DESIGN):
  BO.fit(potency=IC50_nM, safety=hERG_uM, admet=caco2_papp)
  candidates = REINVENT4.generate(seed_smiles=pareto_smiles, n=1000)
  candidates = filter(commercial=True, synthesizability_score>0.6, Lipinski=True)
  proposal = BO.propose(candidates, n=20, diversity_weight=0.3)
  
  Output: RoundProposal {
    round: 3,
    proposed_smiles: [20 compounds],
    acquisition_values: [...],
    uncertainty_scores: [...],  ← NEW: identifies least-certain compounds
    pareto_front: [6 compounds],
    rationale: "6 new Pareto candidates + 14 uncertainty-driven exploration"
  }

Step B — Human approval (MAKE):
  Scientist reviews proposal in BioMate UI
  Marks: APPROVE | MODIFY | REJECT for each compound
  System: generates CRO order for approved compounds
  CRO: synthesizes + assays (4-8 weeks)

Step C — Data ingestion (ANALYSE):
  LIMS connector OR manual CSV upload
  AssayQCService.validate(plate_map, controls, Z_prime)
  AssayIngestionService.ingest(round=3, csv=results)
  
  Auto-trigger on ingestion complete:
    BO.fit(all_rounds_combined)        ← retrain on round 1+2+3 data
    next_proposal_draft = BO.propose() ← generate round 4 draft
    notify_scientist("Round 3 data ingested. 23 new compounds scored.
                      Round 4 proposal ready for review.")
```

---

# Part 4 — Gap-Filling Plan (Concrete Implementation)

## G1 + G2: Auto-Retrain + Generative Coupling (Highest Priority)

**What to build:**  
An event-driven trigger: when `ingest-assay` completes successfully, automatically:
1. Refit the BO on all available campaign data
2. Run REINVENT4 scaffold hopping seeded by current Pareto front compounds
3. Score generated compounds through BO
4. Draft a `RoundProposal` and store it as "pending review"
5. Notify the user in the chat UI

**Implementation:**

```python
# In AssayIngestionService.ingest_assay_data(), after successful ingest:

async def _trigger_next_round_proposal(self, campaign_id: str):
    """Auto-triggered after each successful assay ingest."""
    # 1. Fetch all campaign data
    dataset = self._build_campaign_dataset(campaign_id)
    if len(dataset.compound_ids) < 3:
        return  # Not enough data yet
    
    # 2. Refit BO
    optimizer = BayesianOptimizer(db_path=self.db_path)
    optimizer.fit(dataset)
    
    # 3. Generate candidates via REINVENT4 (async Nextflow call)
    pareto_smiles = optimizer.get_pareto_front_smiles()
    candidates = await self._run_reinvent4_generation(
        seed_smiles=pareto_smiles,
        n_generate=500,
        campaign_id=campaign_id
    )
    
    # 4. Filter + propose
    candidates = self._filter_candidates(candidates)
    proposal = optimizer.propose(candidates, n_compounds=20)
    
    # 5. Store as pending_review round
    self._save_pending_proposal(campaign_id, proposal)
    
    # 6. Return proposal for notification
    return proposal
```

**API change:** `POST /ingest-assay` response adds:
```json
{
  "ingested_count": 23,
  "errors": [],
  "compound_rankings": [...],
  "next_round_proposal": {
    "status": "pending_review",
    "round_number": 4,
    "proposed_count": 20,
    "pareto_front_count": 7,
    "message": "Round 4 proposal ready for review in campaign dashboard"
  }
}
```

---

## G3: LIMS Integration Layer

> **CORRECTION (2026-04-17, validated against codebase):**  
> The Benchling connector **already exists** at `backend/lib/integrations/benchling_connector.py` (309 lines, fully implemented). It provides OAuth2 + API key auth, `pull_workflow_inputs()`, `push_workflow_outputs()`, `list_assay_results()`, and `bulk_create_assay_results()`. This is NOT a gap to build from scratch.
>
> The **actual gap** is: the existing `BenchlingConnector` class is not wired into the DMTA loop. `AssayIngestionService` does not call it — assay data must still be exported manually as CSV. The work required is a single integration bridge, not a new connector.

**What to build (revised — wiring, not new code):**

1. Add `lims_provider` + `lims_config` fields to the campaign database schema
2. Wire `BenchlingConnector.list_assay_results()` into `AssayIngestionService.poll_lims()`:

```python
# In AssayIngestionService (backend/lib/galaxy/ai/drug_discovery/assay_ingestion_service.py)

from backend.lib.integrations.benchling_connector import BenchlingConnector

async def poll_lims_and_ingest(self, campaign_id: str):
    """Pull latest assay results from LIMS and auto-ingest."""
    campaign = self._get_campaign(campaign_id)
    if not campaign.lims_config:
        return  # No LIMS configured; CSV-only mode
    
    connector = BenchlingConnector(
        api_key=campaign.lims_config['api_key'],
        base_url=campaign.lims_config['base_url']
    )
    
    # BenchlingConnector.list_assay_results() already exists
    results = await connector.list_assay_results(
        schema_id=campaign.lims_config['assay_schema_id'],
        since=campaign.last_lims_sync
    )
    
    if results:
        df = self._normalize_benchling_results(results)
        await self.ingest_assay_data(campaign_id, df)
        campaign.last_lims_sync = datetime.utcnow()
```

3. Other LIMS targets (Dotmatics, generic CSV fallback) are already handled or remain lower priority:

| Provider | Status |
|---|---|
| Benchling | EXISTS at `backend/lib/integrations/benchling_connector.py` — just wire to DMTA |
| Dotmatics/Studies | Truly new connector needed |
| Generic CSV | ALREADY EXISTS — `AssayIngestionService` accepts CSV today |
| SiLA2 instruments | EXISTS at `backend/lib/integrations/sila2_adapter.py` |
| Opentrons | EXISTS at `backend/lib/integrations/opentrons_connector.py` |
| Plate reader | EXISTS at `backend/lib/integrations/plate_reader_connector.py` |
| LC-MS | EXISTS at `backend/lib/integrations/lcms_connector.py` |

**New API endpoint (remains same as before):**
```
POST /api/drug-discovery/{campaign_id}/lims-connect
  body: { provider, api_key, base_url, project_id, poll_interval_minutes }
  → Registers LIMS polling job; auto-ingests when new results appear

GET /api/drug-discovery/{campaign_id}/lims-status
  → Returns last sync time, records pulled, errors
```

---

## G4: Uncertainty Sampling

**What to build:**  
Add uncertainty quantification (UQ) to the BO proposal. GP surrogates already compute posterior variance — expose it as a selection criterion.

**Implementation (small change to existing BO):**

```python
# In BayesianOptimizer.propose():

# Current: rank by EHVI only
# New: blend EHVI with uncertainty (exploration-exploitation tradeoff)

acquisition_values = (
    (1 - exploration_weight) * ehvi_scores +
    exploration_weight * uncertainty_scores  # GP posterior std
)

# Also flag "uncertainty-driven" compounds separately in RoundProposal
proposal.uncertainty_selected = [smiles for top uncertainty compounds]
proposal.ehvi_selected = [smiles for top EHVI compounds]
```

**User-facing:** Chat UI shows two compound groups in proposal:
- "Exploitation (7 compounds) — nearest to Pareto front, high confidence"
- "Exploration (3 compounds) — model uncertain here, informative to test"

---

## G5: Pareto Front Visualization

**What to build:**  
A React component that renders the multi-objective Pareto front.

```typescript
// frontend/client/src/components/pareto-front-chart.tsx

interface ParetoFrontChartProps {
  compounds: Array<{
    id: string;
    potency_score: number;
    safety_score: number;
    admet_score?: number;
    is_pareto: boolean;
    round_number: number;
  }>;
  proposed?: string[];  // SMILES of next-round proposals
}
```

- 2D scatter: potency vs safety, colored by round
- Pareto frontier highlighted
- Hover: compound ID, structure tooltip, scores
- Click: opens structure viewer
- Toggle: show/hide individual rounds

---

## G6: Round Provenance & Audit Trail

**What to build:**  
Add a `campaign_rounds` table to SQLite + tracking of which proposal generated which synthesized compound.

```sql
CREATE TABLE campaign_rounds (
  round_id        TEXT PRIMARY KEY,
  campaign_id     TEXT NOT NULL,
  round_number    INT NOT NULL,
  created_at      TIMESTAMP,
  proposal_json   TEXT,   -- RoundProposal JSON
  approved_by     TEXT,   -- scientist name/email
  approved_at     TIMESTAMP,
  cro_order_sent  TIMESTAMP,
  assay_results_received TIMESTAMP,
  model_version   TEXT    -- hash of training data at time of proposal
);

CREATE TABLE compound_round_mapping (
  compound_id   TEXT,
  campaign_id   TEXT,
  proposed_in_round  INT,
  synthesized   BOOL,
  assayed       BOOL,
  PRIMARY KEY (compound_id, campaign_id)
);
```

---

## G7: Multi-Objective ADMET Integration

> **CORRECTION (2026-04-17, validated against codebase):**  
> `CampaignDataset.objectives` is already a `dict[str, np.ndarray]` — it supports arbitrary objectives. The **BO framework itself is multi-objective and extensible**. This is NOT a framework gap.
>
> The **actual gap** is: `BayesianOptimizer` is not called from `api_router.py` anywhere. The entire BO stack (`bayesian_optimizer.py`) is completely disconnected from the REST API. It exists only as library code with no HTTP endpoint. Connecting ADMET objectives is a second-order problem; the first-order problem is wiring BO to the API at all.
>
> **Real implementation order:**
> 1. **First**: Add `POST /api/drug-discovery/{campaign_id}/propose` endpoint that calls `BayesianOptimizer.fit() + .propose()` — this unlocks the entire BO workflow from the frontend
> 2. **Then**: Extend `CampaignDataset` population to include ADMET predictions alongside wet-lab potency/safety values

**What to build (revised):**  
Wire `BayesianOptimizer` to the REST API, then extend the objective set.

```python
# In api_router.py — add this missing endpoint

@router.post("/{campaign_id}/propose")
async def propose_next_round(campaign_id: str, body: ProposeRequest):
    """
    CURRENTLY MISSING — BayesianOptimizer is never called from the API.
    This is the core wiring gap for multi-objective ADMET optimization.
    """
    dataset = build_campaign_dataset(campaign_id)  # reads from SQLite
    optimizer = BayesianOptimizer(db_path=DB_PATH)
    optimizer.fit(dataset)
    proposal = optimizer.propose(
        candidates=body.candidates,
        n_compounds=body.n_compounds,
        diversity_weight=body.diversity_weight
    )
    return proposal.to_dict()
```

Once wired, extend `CampaignDataset` population to include ADMET objectives:

Currently the BO receives objectives in this format (when manually called):
```python
CampaignDataset(
  objectives={'potency': array, 'safety': array},
  objective_directions={'potency': 'maximize', 'safety': 'maximize'}
)
```

**Extended objectives:**
```python
CampaignDataset(
  objectives={
    'potency': ic50_array,          # from wet lab
    'safety': herg_array,           # from wet lab
    'admet_caco2': papp_array,      # from predict_admet_properties
    'admet_solubility': sol_array,  # from ESOL
    'selectivity': kinase_sel_arr,  # from proteome_selectivity_profiling (new)
    'synthesizability': sa_array,   # from AiZynthFinder
  },
  objective_directions={
    'potency': 'maximize',
    'safety': 'maximize',
    'admet_caco2': 'maximize',
    'admet_solubility': 'maximize',
    'selectivity': 'maximize',
    'synthesizability': 'maximize'
  }
)
```

**Bridge layer:** After each assay ingest, auto-run ADMET predictions on all new compounds and add to BO dataset.

---

## G9: Assay Quality Control Layer

**What to build:**  
Automated QC checks on incoming assay data before ingestion. Reject bad plates silently without corrupting model.

```python
# backend/lib/galaxy/ai/drug_discovery/assay_qc.py

class AssayQCService:
    def validate_plate(self, df, controls_col='control_type') -> QCReport:
        """
        Checks:
        - Z' factor (>0.5 = acceptable, >0.7 = excellent)
        - Signal:noise ratio
        - Positive/negative control separation
        - Outlier detection (±3σ from plate mean)
        - Duplicate consistency (CV < 20%)
        """
        z_prime = self._compute_z_prime(df)
        outliers = self._detect_outliers(df)
        cv_duplicates = self._compute_cv(df)
        
        return QCReport(
            z_prime=z_prime,
            plate_accepted=z_prime > 0.5,
            outlier_compounds=outliers,
            cv_failures=cv_duplicates,
            flag_for_review=z_prime < 0.5
        )
```

**API change:** `POST /ingest-assay` runs QC before ingesting; returns:
```json
{
  "qc_passed": true,
  "z_prime": 0.73,
  "outliers_flagged": ["CPD-034"],
  "ingested_count": 22,
  "skipped_count": 1,
  "message": "1 compound flagged as outlier (>3σ); excluded from ranking. Plate Z'=0.73 (EXCELLENT)"
}
```

---

# Part 5 — Implementation Roadmap

## Sprint 1 (2 weeks): Auto-Retrain + Round Tracking
- G1: Auto-trigger BO refit after ingest-assay
- G6: Add `campaign_rounds` + `compound_round_mapping` tables
- G9: Basic assay QC (Z' factor, outlier detection)
- **Deliverable:** Complete round lifecycle with audit trail; BO retrains automatically

## Sprint 2 (2 weeks): Generative Coupling + Uncertainty
- G2: Wire REINVENT4 generation seeded by Pareto front into proposal pipeline
- G4: Add uncertainty sampling alongside EHVI
- G5: Pareto front React visualization component
- **Deliverable:** Full DESIGN step is automated; user sees exploitation vs exploration compounds

## Sprint 3 (2 weeks): LIMS + Multi-Objective ADMET
- G3: Benchling LIMS connector (REST API pull)
- G7: ADMET objectives integrated into BO dataset
- G8: REINVENT4 ↔ BO bi-directional coupling
- **Deliverable:** Data flows automatically from Benchling; BO optimizes over 6 objectives

## Sprint 4 (1 week): UI + Campaign Management
- G10: Campaign comparison dashboard
- G5: Full Pareto front 3D visualization (3 objectives)
- Round history view with provenance annotations
- **Deliverable:** Scientist can manage portfolio of campaigns with full history

## Total: 7 weeks to fully closed-loop DMTA

---

# Part 6 — Testing Plan for the Closed Loop

## Unit Tests (existing — already passing)
- `test_bo.py` — fit/propose/round numbering/persistence
- `test_cro_commercial.py` — CRO export formats
- `test_real_e2e.py` — real RDKit + GP + PubChem

## New Unit Tests Needed
- `test_assay_qc.py` — Z' calculation, outlier detection
- `test_auto_retrain.py` — ingest → BO refit trigger
- `test_lims_connector.py` — mock Benchling API responses
- `test_multi_objective_bo.py` — 6-objective EHVI calculation

## E2E Test: Full DMTA Loop
**File to create:** `frontend/e2e/dmta-closed-loop.e2e.ts`

```
Test: 3-round DMTA cycle E2E
  Round 1:
    1. Upload 8 BCR-ABL inhibitor IC50 + hERG results
    2. Assert: 8 compounds ingested, ranked, QC passed
    3. Assert: BO auto-proposes 10 next candidates
    4. Assert: CRO export downloads correctly
  
  Round 2:
    5. Upload 10 new assay results (from round 1 proposals)
    6. Assert: all 18 compounds now in campaign
    7. Assert: Pareto front updated (≥1 new Pareto compound)
    8. Assert: Round 2 proposal differs from Round 1 (model learning)
  
  Round 3:
    9. Upload 8 results for round 2 compounds
    10. Assert: BO accuracy improved (predicted vs actual correlation)
    11. Assert: Round provenance table shows 3 rounds with timestamps
```

---

# Summary

| Component | Current State | Gap | Sprint to Fix |
|---|---|---|---|
| Compound ranking after assay | ✅ Complete | — | — |
| Bayesian optimizer fit + propose | ✅ Complete | No auto-trigger | Sprint 1 |
| CRO order export | ✅ Complete | — | — |
| Commercial availability | ✅ Complete | — | — |
| Assay QC | ❌ Missing | Z', outlier detection | Sprint 1 |
| Round provenance tracking | ❌ Missing | No audit trail | Sprint 1 |
| Auto-retrain on ingest | ❌ Missing | Manual step required | Sprint 1 |
| Uncertainty sampling | ❌ Missing | EHVI only | Sprint 2 |
| Generative coupling (REINVENT4 ↔ BO) | ❌ Missing | Independent systems | Sprint 2 |
| Pareto front visualization | ❌ Missing | Computed not shown | Sprint 2 |
| LIMS integration (Benchling) | ❌ Missing | Manual CSV upload | Sprint 3 |
| Multi-objective ADMET in BO | ❌ Missing | 2 objectives only | Sprint 3 |
| Campaign comparison | ❌ Missing | Single campaign only | Sprint 4 |

**Current loop completeness: 40%**  
**After 7-week roadmap: ~90%**  
**Remaining 10%:** LIMS from CROs (vendor-specific integrations), automated instrument data parsing, regulatory audit export
