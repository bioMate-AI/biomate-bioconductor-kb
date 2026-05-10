# BioMate multi-workflow planning and resource alignment

**Purpose**: Document how BioMate plans and executes multi-step drug-discovery and vaccine-style campaigns, and how that aligns with the ANDV inhibitor and vaccine implementation tracks.

**Related (split deliberately)**:

- **Execute ANDV stages via Nextflow / API today**: `docs/20260509_ANDV_NEXTFLOW_PIPELINE_EXECUTION.md`
- **Backlog — registry, gap protocol, DAG orchestration**: `docs/FUTURE_WORK_BIOMATE_ORCHESTRATION.md`

**Audience**: Product and engineering decisions around assistant behavior and resource alignment (not step-by-step Batch execution).

**Last updated**: 2026-05-09

---

## 1. How BioMate builds multi-step plans today

The chat assistant (`frontend/server/galaxy-assistant.ts`) resolves sequential pipelines in **three tiers**:

| Tier | Behavior |
|------|------------|
| **1 — Single-workflow collapse** | Attempts to map the full user message to **one** indexed workflow via `generateWorkflow`, then calls `_checkWorkflowCoverage` (LLM) to ask whether that workflow **internally** covers all decomposed biological steps. High confidence → **one workflow card** instead of a chain. |
| **2 — Curated chain** | If intent decomposition sets `chain_hint` to a known chain name, loads the definition from `GET ${GALAXY_URL}/api/workflow-chains`, resolves each step’s Nextflow path via `processSubIntent`, and returns `workflow_type: 'pipeline'` with `source: 'biomate_curated_chain'`. |
| **3 — Greedy sequential** | Walks remaining intents **one cluster at a time**, optionally merging consecutive steps when `_checkWorkflowCoverage` says one workflow covers multiple intents. Produces `pipeline_steps` with dependency metadata (`input_from`, descriptions). |

**Implication**: “Planning” is **heuristic**, not a formal planner that proves coverage against the entire workflow database. It combines LLM judgment, a **small curated chain catalog**, and greedy workflow search.

---

## 2. Curated chains (authoritative seed)

Curated chains are defined in `backend/scripts/index_all_workflows.py` (`CURATED_CHAINS`) and seeded into the `workflow_chains` table.

**Drug-discovery examples** (relevant to inhibitor campaigns):

- **`target_to_lead_full`** — pocket detection → pharmacophore → ADMET → docking → GROMACS/MM-GBSA → REINVENT4 (semantic match to “target to ranked leads”).
- **`drug_discovery_screening`** — ADMET → structure/docking → binding affinity.
- **`drug_discovery_admet_gated_screening`** — pharmacophore → ADMET → docking.

**Omics-heavy chains** (bulk RNA-seq, scRNA, CUT&Tag, APA, rare disease, etc.) dominate the rest of the list.

**Vaccine-specific curated chains** (e.g. epitope → immunogen → mRNA → LNP as one named chain) are **not** present in `CURATED_CHAINS` at the time of this document; those tracks rely on **per-step workflow search** (Tier 3) and indexed workflows such as nf-core/epitopeprediction and nucleic-acid/LNP-related pipelines (see `research/anti-virus/BIOMATE_CAPABILITY_GAP.md` and `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md`).

---

## 3. Alignment with ANDV campaign documents

- **Inhibitor pseudocode** in `*_IMPLEMENTATION.md` files should be read as **semantic intent**, not literal Python imports (`BIOMATE_CAPABILITY_GAP.md`).
- **Platform map**: Indexed workflows and tools live in `backend/database/galaxy_ai_tools.db`; routing uses `backend/lib/galaxy/ai/unified_workflow_search.py`.
- **Overlap**: The **`target_to_lead_full`** chain closely mirrors a large slice of the inhibitor track (pockets → screen/triage → docking → refinement/generation).

---

## 4. Limits of “follow the plan to completion”

1. **Planning ≠ automatic artifact plumbing**  
   Chains declare logical `connections` (outputs → inputs). The UI models step dependencies (`PipelineListView`, `input_from`). **Automatic, typed handoff of outputs between arbitrary Nextflow jobs** as one compiled DAG is **not** guaranteed; users often bridge steps via **S3 paths**, **campaign artifacts**, and **step-by-step approval** (`approvalGate`).

2. **Classifier vs chain catalog**  
   The intent-decomposition prompt lists a fixed set of **known `chain_hint` names**. That list should stay **synchronized** with `CURATED_CHAINS`. If drug-discovery chains (e.g. `drug_discovery_admet_gated_screening`) are absent from the prompt while present in the DB, Tier 2 may **under-trigger** for queries that should map to those chains.

3. **External boundaries**  
   CRO, Benchling, in vivo, proprietary GUIs, and some APIs remain outside indexed execution (see coverage analysis doc).

---

## 5. Product architecture backlog (not required to run ANDV Nextflow today)

Improvements for **chat-native chaining**, **gap handling**, and **typed artifact DAGs** are tracked as **future work** so execution can proceed via direct API/Batch scripts.

See **`docs/FUTURE_WORK_BIOMATE_ORCHESTRATION.md`**.

---

## 6. Related files

| Topic | Location |
|-------|----------|
| Campaign ↔ platform mapping | `research/anti-virus/BIOMATE_CAPABILITY_GAP.md` |
| ANDV campaign overview | `research/anti-virus/MASTER_ANDV_CAMPAIGN_GUIDE.md` |
| Chain seed data | `backend/scripts/index_all_workflows.py` (`CURATED_CHAINS`) |
| Assistant tiers | `frontend/server/galaxy-assistant.ts` (`processSequentialPipeline`, `_checkWorkflowCoverage`, `_fetchCuratedChain`) |
| Drug development coverage scorecard | `docs/20260417_DRUG_DEVELOPMENT_COVERAGE_ANALYSIS.md` |
| ANDV Nextflow step runner + manifest | `docs/20260509_ANDV_NEXTFLOW_PIPELINE_EXECUTION.md`, `research/anti-virus/scripts/run_andv_inhibitor_pipeline_nextflow.py` |

---

**Version**: 1.1
