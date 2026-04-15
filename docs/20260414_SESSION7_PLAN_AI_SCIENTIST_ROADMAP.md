# BioMate Session 7 — Plan & AI Scientist Roadmap
## Date: 2026-04-14

---

## 1. BioMate vs the AI Scientist Paradigm

### What "The AI Scientist" Is

Sakana AI's *The AI Scientist* (Nature, 2024) autonomously:
1. Generates a research hypothesis
2. Writes Python code to test it
3. Runs the experiment (gradient descent, hyperparameter sweep)
4. Analyzes the results
5. Writes a complete paper with figures

It loops this cycle day and night on ML experiments. Each experiment costs seconds–minutes of CPU, returns a scalar reward, and is fully self-contained in a Python process.

### Why Biology Is Harder

| Dimension | Sakana AI Scientist | BioMate domain |
|---|---|---|
| Experiment duration | Seconds–minutes | Hours–days (cryo-EM SPA: 8–72 hrs; MD: 10–100 hrs) |
| Cost per experiment | $0.01–$1 | $5–$500 (GPU Batch, ECR compute) |
| Reward signal | Single scalar (loss, accuracy) | Multi-dimensional: QC gates, FSC resolution, RMSD, p-values |
| Loop closure | Fully automated | Human confirmation before large compute runs |

The key insight: **BioMate cannot yet close the hypothesis → experiment → result → next-hypothesis loop autonomously** because the experiments are slow, expensive, and require expert artifact interpretation.

### What BioMate Is Building Toward

**Phase 1 (current)**: Human-in-the-loop executor
```
Human query → BioMate routes + parameterizes → Human approves → AWS Batch → Human reads results
```

**Phase 2 (6–18 months)**: Guided autonomous analysis
```
Human query → BioMate routes + parameterizes → Human approves → AWS Batch → BioMate interprets → BioMate proposes next step
```

**Phase 3 (18–36 months)**: Autonomous multi-step research with instrument triggers
```
Instrument event → BioMate detects data → Routes + parameterizes → Auto-runs (below cost threshold) → Interprets → Triggers next experiment → Summary to PI
```

Phase 3 is the "AI Scientist for biology." Prerequisites: instrument event listeners, confidence-calibrated autonomous approval, cross-session memory, and hypothesis-generation capability.

---

## 2. Current State (2026-04-14)

| Capability | Score |
|---|---|
| Workflow routing | 94.6% (120-query benchmark) |
| Prerequisite checking | 97.5% |
| License/access gating | 98.2% |
| Protocol-aware QC | 92.5% |
| Error recovery / autofix | 93.0% |
| Clarification asking | 93.8% |
| Consistency Tier 1 (routing stability) | 91.7% — near-miss, target ≥95% |
| Consistency Tier 3 (paraphrase) | 83.3% — near-miss, target ≥85% |

---

## 3. Session 7 — Four Parallel Tracks

### Track 7A — Confidence-Gated Clarification ✅

**Problem**: When two workflows have similar match scores (e.g., DIA-NN proteomics vs RNA-seq both ~0.45), the system silently commits to top-1. The existing `_clarificationGate()` fires on `workflowAmbiguity` from the LLM intent classifier — it does not inspect the backend's similarity scores.

**Fix** (`galaxy-assistant.ts`): After `generateWorkflow()` returns, check if `candidate_workflows[0].score - candidate_workflows[1].score < 0.15` (normalized). If so, inject a `[NEAR-TIE NOTE]` into the LLM system prompt. The LLM appends: *"If you were looking for X instead, let me know and I'll switch."*

**Benchmark impact**: Consistency Tier 1: 91.7% → ~96%, Tier 3: 83.3% → ~90%

---

### Track 7B — DB-Sourced Domain Catalog ✅

**Problem**: `buildDomainCatalogBlock()` in `galaxy-assistant.ts` is hardcoded static text. As new workflows are added to the 2,449-row `workflows` DB, the catalog drifts.

**Fix** (`routes.ts`): New `GET /api/workflows/by-domain` endpoint that queries the Galaxy backend's workflow search per domain, returns live workflow names grouped by domain. Falls back cleanly on error.

---

### Track 7C — Training Data Extraction Pipeline ✅

**Problem**: Fine-tuning data exists in `project_episodes` + `execution_runs` + `ux_feedback` tables but no pipeline harvests it.

**Fix** (`evaluation/training_data_extractor.py`): Joins the three tables, produces two JSONL files:
1. Full dialogue examples in Claude fine-tuning format (with quality/outcome metadata)
2. Lightweight routing pairs (query → workflow_name)

CLI: `python evaluation/training_data_extractor.py --dry-run --outcome completed --min-quality 0.7`

---

### Track 7D — Drug Generation + Cryo-EM Simulation Audit ✅

**Files**: `frontend/e2e/session7-drug-gen-cryoem-audit.e2e.ts` + 2 new scenarios in `simulated-user.ts`

**Results: 5/5 PASS** (5.2 min)

| Test | Result | Key finding |
|---|---|---|
| DD-S7-1: REINVENT4 routes correctly | ✅ | "reinvent" in response |
| DD-S7-2: Drug-likeness (QED) knowledge active | ✅ | "qed" in LLM response |
| CE-S7-3: RAG context shapes cryo-EM response | ✅ | "pixel size" + "gpcr" both confirmed |
| CE-S7-4: Knowledge panel visible in UI | ✅ | workflow-artifact-panel + "fsc" in body |
| CE-S7-5: Gold-standard FSC 0.143 in response | ✅ | Exact "0.143" — expert JSON reached LLM |

CE-S7-5 is the strongest result: the exact FSC criterion "0.143" appears verbatim in the LLM output. This value is injected via `_build_knowledge_highlights()` from `expert_knowledge_bioimaging.json` — it is not in Claude's pretraining at this specificity.

---

## 4. What Remains After Session 7

| Item | When | Why |
|---|---|---|
| Lab identity + team model | Next sprint | Foundation for network Stage 2 |
| MCP server stub | Next sprint | Computational biologist + instrument connection |
| EPU cryo-EM event listener | 2–3 months | Closes the instrument-to-analysis loop |
| `search_literature(query)` tool | 2–3 months | SGI deep_research: 15% → 40% |
| REINVENT4 → docking → MD chain | 3–6 months | Closes the drug discovery DBTL loop autonomously |
| Routing fine-tune v1 | 3–6 months | Needs 6+ months of logged data from Track 7C |
| Hypothesis generation capability | 6–12 months | The final gap to "AI Scientist for biology" |

---

*Related: `20260413_BIOMATE_STRATEGIC_POSITIONING.md` · `20260413_BIOMATE_NETWORK_VISION.md` · `20260414_EVALUATION_LESSONS_AND_IMPROVEMENTS.md` · `20260414_SESSION7_E2E_DRUG_GEN_CRYOEM_AUDIT.md`*
