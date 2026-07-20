# Layer-4 Orchestration LLM — Execution-Trace Corpus Build Spec

**Date:** 2026-07-18 · **Owner:** LLM training · **Base model:** Qwen3-14B (Apache-2.0) + LoRA — 7–14B target for serving speed (8B latency drop-down)
**Why this first:** the trace corpus is BioMate's one genuinely defensible moat (per `20260718_LLM_TRAINING_DEEP_SURVEY.md`). Every competitor is prompt/RAG over a frontier base; none fine-tunes on real workflow execution traces. This spec builds that corpus and starts from data BioMate **already generated**.

---

## 1. Objective

Produce a supervised + preference training corpus that teaches an open base model BioMate's five orchestration skills:
1. **Routing** — user intent → correct workflow(s) from the 2,455-workflow catalog, in correct translational order.
2. **Parameter extraction** — scientific prose → structured workflow config (rule-first, LLM-fallback, schema-validated).
3. **Cross-domain synthesis** — pass results between domains with biological context (GWAS→scRNA→ADMET→PBPK→IND).
4. **QC judgment** — detect a QC failure, select a remediation, re-run, report as a QC event.
5. **IND assembly** — author §2.6 narrative from combined workflow outputs.

**Differentiation target:** the **long tail** (rare modalities, multi-domain chains, corrupted/edge-case inputs) where frontier zero-shot fails (BioAgent Bench, arXiv:2601.21800) — *not* RNA-seq/variant-calling, which open models already do zero-shot.

---

## 2. Training-example schema

One canonical JSONL record (both SFT and DPO derive from it):

```json
{
  "id": "trace_<source>_<n>",
  "task": "routing | param_extraction | synthesis | qc_judgment | ind_assembly",
  "domain": ["genomics","single_cell","drug_discovery",...],
  "input": {
    "user_intent": "<NL request or prose>",
    "context": {"data_characteristics": "...", "prior_step_outputs": {...}}
  },
  "target": {                       // the accepted / ground-truthed answer
    "workflow_path": "nextflow_nfcore/.../main.nf",
    "params": {"genome":"GRCh38","strandedness":"reverse", ...},
    "reasoning": "why this workflow / these params / this remediation",
    "output_summary": "biological interpretation"
  },
  "provenance": {"source":"validation_session|audit_log|geo_mined|self_generated|metadata_card",
                 "verified_against":"published finding | AWS Batch job id | schema",
                 "grade":"GOLD|SILVER|BRONZE"},
  "rejected": {"...optional, for DPO — the modified/failed alternative..."}
}
```

---

## 3. Data sources (in priority order)

| # | Source | Location | Yields | Est. volume | Grade |
|---|---|---|---|---|---|
| S0 | **In-house validation traces (2026-07 sessions)** | `data/validation/results/test{1a,1b,1f,1h,3c,4a,4b,5a,7a,8a,8b}/` | Real routing→param→exec→QC→interpretation, **ground-truthed vs published values + AWS Batch job ids** | ~50–200 high-grade examples (seed) | GOLD |
| S1 | **Session audit logs** | `*_audit.jsonl` + `*_summary.txt` (repo root); run-state store | Real user/agent decisions: intent→workflow→params→outcome | 100s–1000s | SILVER |
| S2 | **Workflow metadata cards** | `backend/database/galaxy_ai_tools.db` (name, domain, description, required/optional params, steps, nextflow_path) | Instruction-tuning on "what each workflow does / needs / chains with" — all 2,455 | 2,455 | GOLD (curated) |
| S3 | **Auto-loop / AutoFix remediation records** | QC logs; `backend/experiments/*_autoloop/`; `workflow_ops/autofix/` | **Negative→fix examples** for QC-judgment task (what failed, what fixed it) | 100s | GOLD |
| S4 | **Self-generated traces (Strategy B)** | Run BioMate on ~500 autoimmune GEO datasets × relevant workflows | Real execution records, ground-truthed vs linked GEO paper | ~2,500; ~$1–5K compute | SILVER |
| S5 | **GEO-mined traces (Strategy A/C)** | GEO series + linked PubMed methods sections (extract-then-verify) | (data context)→(workflow steps)→(interpretation) triples | ~100K after filtering | BRONZE |

**Start with S0 + S2 + S3 (all in-house, GOLD, zero new compute), add S1, then scale with S4/S5.**

---

## 4. Pipeline

```mermaid
flowchart LR
    S0[Validation traces] --> N[Normalize to schema]
    S1[Audit logs] --> N
    S2[Metadata cards] --> N
    S3[Remediation records] --> N
    S4[Self-generated] --> N
    S5[GEO-mined] --> V
    N --> V[Verify: schema-valid params?\nworkflow_path resolves?\noutput matches ground truth?]
    V --> D[Dedup + decontaminate\nvs eval sets]
    D --> B{Balance by task + domain\n(upweight long tail)}
    B --> SFT[SFT JSONL]
    B --> DPO[DPO pairs: accepted vs modified]
```

- **Verify:** drop any record whose `workflow_path` doesn't resolve in the catalog, whose params fail schema validation, or (for S0/S4) whose output diverges from the ground-truth finding.
- **Decontaminate:** remove anything overlapping the routing/param/QC eval sets (the existing `test_workflow_retrieval_semantic.py`, param-prefill cases, autoloop scenarios) so the gate stays honest.
- **Balance:** upweight rare domains + cross-domain chains; downweight RNA-seq/variant-calling (commoditized).

---

## 5. Training formats

- **SFT (instruction tuning):** all five tasks from `target`. Include the metadata cards (S2) as "workflow knowledge" instructions.
- **DPO (preference):** where `rejected` exists — accepted vs modified/failed alternative. Seed from S3 (remediation: fixed vs original failing params) and S1 (accepted vs user-edited outputs). This is the compounding flywheel: every future accepted session output adds a preference pair.

---

## 6. Bootstrap from already-executed validation traces (week 1)

Convert the 2026-07 validation results directly into the first GOLD examples — no new runs:

| Test | Trace example (task) |
|---|---|
| 1-A | intent "prioritize RA targets from GWAS" → `scgwas_immune_cell` + eQTL + druggability chain; output PTPN22/TYK2 ranking (synthesis) |
| 1-B | prose "responders vs non-responders, GSE89408" → DESeq2 params → 16,261 DEGs, 9/10 RA markers (routing + param + synthesis) |
| 1-F | "tocilizumab IND package" → PBPK + developability + §2.6 chain → Cmax 190 vs 178 (ind_assembly) |
| 3-C | hERG gate fired → param remediation → IC50 recalibrated (qc_judgment; DPO negative→fix) |
| 4-A | drug + indication → §2.6.1 narrative, 5 sections, 4 citations (ind_assembly) |
| 5-A | deucravacitinib SMILES → ADMET-AI → hERG/PPBR/logP vs known (param + synthesis) |
| 7-A | multi-step prompt → scgwas/ADMET/PBPK all rank-1 routing (routing) |

Target: **~150–300 GOLD seed examples** from S0+S3 in week 1; enough to run a first LoRA SFT and validate the pipeline end-to-end before scaling with S4/S5.

---

## 7. Fine-tune config & eval gate

- **Base:** **Qwen3-14B** (dense, Apache-2.0) — 7–14B for serving speed (32B ruled out). **Method:** LoRA/QLoRA (Unsloth or Axolotl); fits a **single 24GB GPU** (even 16GB). LoRA limits catastrophic forgetting of general tool-use. Use thinking-off for routing/tool-calls, thinking-on for §2.6.
- **Drop-down:** **Qwen3-8B** if inference latency is the binding constraint (verified best-small tool-use; fine-tune recovers most of the in-domain gap).
- **A/B hedge:** **GLM-4-9B-0414 (MIT)** — function-calling post-trained; run head-to-head on our tool schemas if Qwen3 underperforms. (Kimi excluded — no dense 7–14B open model. DeepSeek R1-Distill = optional reasoning specialist only.)
- **Note:** no public BFCL row exists for Qwen3-14B / GLM-4-9B-0414; the eval gate below is measured on our own harness.
- **Eval gate (must pass before deploy):**
  - Routing P@1 on held-out intents **> best open-model zero-shot**, especially long-tail/cross-domain.
  - Param-extraction F1 **> rule-only and > frontier-zero-shot**.
  - QC-judgment: correct remediation selection rate vs the autoloop ground-truth scenarios.
  - **Decontamination check:** zero eval-set leakage in training data.

---

## 8. Milestones

1. **Week 1:** S0+S2+S3 normalized → ~150–300 GOLD examples; pipeline verified.
2. **Week 2–3:** first Qwen3-32B LoRA SFT; pass routing gate on held-out intents.
3. **Week 3–4:** add S1 audit logs + start DPO from remediation/accepted-vs-modified pairs.
4. **Month 2:** S4 self-generated traces (~500 GEO datasets); scale corpus; re-train.
5. **Month 3:** S5 GEO-mined (extract-then-verify) for long-tail coverage; robustness eval vs BioAgent-Bench-style perturbed inputs.

**Flywheel:** deploy behind the existing router; every accepted/modified session output becomes a new SFT/DPO example — the corpus (and the moat) compounds with usage.
