# Autoimmune Model Training — Strategy Decision & DGX Spark Execution Plan

**Date:** 2026-07-19 · **Decision owner:** you · **Hardware:** NVIDIA DGX Spark (GB10, 128 GB LPDDR5X unified, ~273 GB/s, ~1 PFLOP FP8)
**Inputs:** Direction 1 = `20260701_BIOMATE_AUTOIMMUNE_STRATEGY_AND_LLM_TRAINING.md` (broad 4-layer stack). Direction 2 = `20260706_SLE_FOUNDATION_MODEL_SURVEY_AND_PROPOSAL.md` + `20260706_SLE_GENEFORMER_ADAPTATION_SURVEY.md` + `20260706_SLE_BANCHEREAU_PILOT_ELABORATION.md` (narrow SLE single-cell FM adaptation). Also `20260718_LLM_TRAINING_DEEP_SURVEY.md`.

---

## 1. The two directions, side by side

| | Direction 1 — Broad autoimmune foundation | Direction 2 — Narrow SLE (tailored) |
|---|---|---|
| Scope | 4 models (virtual cell, target-ID, trial-design, orchestration) across all autoimmune | One immune single-cell FM adapted to SLE patient stratification |
| Base | Geneformer v2 / STRING-GNN / Llama-70B (all found stale/behind in the deep survey) | Adopt existing immune FM (scGPT-blood / CellFM / RegFormer) + novel A+B FT |
| Novelty | Integration; but 3 of 5 moat claims eroded/contradicted | **A+B multi-task hierarchical supervision** — confirmed novel (cross-disease categorical + pathway-score regression) |
| Evidence risk | Virtual-cell perturbation is scientifically **contested** (FMs don't beat linear baselines) | Same risk, but **explicitly gated** (mean-expression baseline must be beaten) + a real target (Perez 2022 R=0.66) |
| Time / cost | Months, multi-GPU, high | **3–5 days on the DGX Spark**, ~$0 marginal |
| Defensibility | Public-data foundation = **least defensible** (competitors have more data/compute) | Public data too — but depth + curation + novel method can differentiate |
| DGX Spark fit | ❌ mostly needs cloud/multi-GPU | ✅ designed for it |

---

## 2. My recommendation (you asked "what do you think?")

**Do not build a broad foundation from public data first. That is the weakest, most expensive, least defensible move — and you already sensed why ("if public data is available, everyone else can do exactly what we are planning").** A seed-stage effort on one 128 GB personal GPU cannot out-foundation CZI, Arc, or Immunai on public single-cell data. Whoever has more cells and more H100s wins that race, and it isn't us.

**Instead: narrow-first, then broaden, and adopt (don't build) the public foundation.**

The key reframe: **"build the foundation with public data first" should be "*adopt* an existing public foundation, and spend our scarce effort on the tailored, novel adaptation + proprietary curation."** Someone already paid to pretrain scGPT-blood / CellFM on 10–100M cells. Re-pretraining a foundation is redundant *and* undifferentiated. Our differentiation budget should go where competitors won't bother: **one disorder, deeper than anyone, with a novel supervision method and a curated corpus.**

Concretely, my answer to "both, or foundation-first":
- **Not both in parallel now** — you have one GPU and limited attention; parallel dilutes the fast win.
- **Not foundation-first** (in the "pretrain broadly" sense) — that's the trap.
- **Narrow-first (Direction 2), sequenced**, is the right call — because it is *fast, cheap, gated, publishable, and de-risks the entire FM-adaptation thesis before you spend a dollar on the broad plan.* If the narrow SLE probe can't beat a linear baseline, the broad plan would have failed too — you just found out in a week instead of a quarter.

**Where the moat actually is** (from the deep survey): not the model weights, but (a) BioMate's **execution-trace flywheel** (the orchestration LLM — different resources, run in the background), (b) the **closed DBTL / instrument loop** already built in the connector work, and (c) **curated-corpus depth** — the "text-mining the dataset first" instinct is right, *if* it produces a deeper, better-labeled SLE corpus (transcriptome ↔ SLEDAI / anti-dsDNA / complement) than the public GEO series everyone downloads. The dataset preparation *is* the differentiator — more than the base model.

**One-line verdict:** Start Direction 2 on the Spark this week, gated by the linear baseline. Treat the "foundation" as *adopted*, not built. Let the moat come from curation depth + the orchestration flywheel, not from a bigger public-data model. Broaden to RA/IBD by replicating the recipe only after the SLE win clears its gate.

---

## 3. DGX Spark execution plan (start ASAP)

**Feasibility on GB10 / 128 GB unified (from the SLE docs):** fine-tuning an immune single-cell FM at 1–5M cells across ~5 conditions ≈ **3–5 days**; unified memory is ~2–3× slower than datacenter HBM but the model + batches fit comfortably. This is the right machine for Direction 2 and for periodic Qwen3-14B LoRA (orchestration) — no cloud needed to start.

### Phase A — Dataset preparation (the real differentiator) · Spark CPU + storage · ~1 week
The point of difference. Go beyond downloading known GEO series:
1. **Text-mine + assemble the SLE single-cell corpus.** Systematically mine GEO + CELLxGENE + literature for SLE/RA/IBD PBMC & tissue scRNA-seq with **linked clinical labels** (SLEDAI, anti-dsDNA, complement C3/C4, treatment, flare). Confirmed cores: Nehar-Belaid 2020 (GSE135779, eval), CELLxGENE RA, IBDverse (1.1M Crohn's cells, *Nat Genet* 2026), plus Banchereau 2016 (GSE65391). The curation — harmonized cell-type + disease-activity + lab-value labels — is what others don't build.
2. **Normalize to a single schema** (cell × gene + per-cell metadata + per-patient clinical vector). QC, batch keys, train/val/test split **by patient** (no leakage).
3. **Deliverable:** a curated, versioned SLE-centric immune corpus (~1–5M cells) + a clinical-label table. This asset is reusable across every downstream model and is the thing to keep proprietary/deepen.

### Phase B — Baseline gate (do this BEFORE any FM training) · Spark · ~1 day
Non-negotiable, per the docs' own warning (mean-expression can beat scFMs):
- Run **PCA + logistic regression** and **mean-cell-type-expression centroid** on raw expression for LDA/HDA/healthy stratification.
- **Gate:** if a linear baseline already separates disease activity at ~Perez-2022 level (R≈0.66), *stop and pivot* — a fine-tuned FM adds nothing here, and so would the broad plan.

### Phase C — Novel A+B adaptation (if Phase B clears) · Spark · ~3–5 days
1. **Base model priority:** RegFormer (Mamba+GRN, if weights public) → **CellFM** (800M, 19.2M T cells, Zenodo weights now) → **scGPT-blood** (confirmed available). Adopt, don't pretrain.
2. **Method:** A+B multi-task hierarchical supervision — cross-disease categorical head + continuous pathway-score (IFN/M1.2) regression head, joint fine-tune. **Required:** layer sweep (0/25/50/75/100% depth — intermediate layers often win) + full ablation table incl. the linear baseline.
3. **Eval:** ASW of the 3 patient clusters on held-out SLE; **beat Perez 2022 (R=0.66)**; cite/baseline TEDDY, EVA, UCE-zero-shot, Immunai.
4. **Deliverable:** a de-risked, publishable SLE stratification result — and proof the adaptation thesis works before broadening.

### Phase D — Broaden + wrap in the moat (only after C clears)
- Replicate the recipe to RA and IBD (same corpus, same A+B method) → the "autoimmune" breadth, earned by replication not by a bigger foundation.
- **In parallel, on the same Spark (different workload):** start the **orchestration LLM (Qwen3-14B LoRA)** on the already-executed validation traces (see `20260718_LAYER4_TRACE_CORPUS_BUILD_SPEC.md`). This is the actual moat and doesn't compete with Phase A–C for wall-clock (different data/skills; run when the cell-FM job is idle).

---

## 4. When you need a bigger GPU than the Spark

The Spark covers Phases A–D above. Burst to cloud **only** for:

| Trigger | Why Spark isn't enough | Recommended | Est. cost |
|---|---|---|---|
| **Pretraining a novel FM from scratch at >10M cells** (the "3 architecturally novel designs": disentangled dual encoder, ClinCLIP, Mamba 20k-gene context) | ~273 GB/s bandwidth → pretraining throughput too slow | 4–8× H100 (cloud, 2–5 days) | ~$1–4K/run |
| **Full fine-tune (not LoRA) of a >14B LLM**, or fast multi-run LLM iteration | unified-memory throughput | 8× A100/H100 spot | ~$0.6–1.2K/run |
| **Self-generated trace corpus at scale** (run BioMate on 500 GEO datasets) | this is *workflow execution*, not GPU training | AWS Batch (existing) | ~$1–5K total |
| **Direction 1 broad program**, if ever pursued | multi-model, multi-week | multi-GPU cloud | budget separately |

**Recommendation: do not buy or rent a bigger GPU yet.** Everything needed to start — dataset prep, the baseline gate, the novel A+B SLE model, and the orchestration LoRA — runs on the Spark. Keep a **~$1–2K cloud-burst contingency** for one scenario only: if Phase C clears the gate *and* you decide to pretrain a novel architecture from scratch (vs. keep adapting an existing FM). Adopt-and-adapt should be the default; from-scratch pretraining is the exception that justifies renting H100s.

---

## 5. Immediate next steps (this week, on the Spark)

1. **Phase A kickoff:** stand up the corpus-curation pipeline; pull Nehar-Belaid GSE135779 + CELLxGENE RA + IBDverse + Banchereau GSE65391; harmonize to the cell×gene + clinical-label schema; split by patient.
2. **Phase B:** run the PCA+LR and mean-expression baselines → the go/no-go gate.
3. Confirm base-model weights in priority order (RegFormer → CellFM → scGPT-blood); set up the FT env on the Spark (bf16/tf32, batch 64, per the SLE doc's config).
4. Keep the orchestration LoRA (Direction-1 Layer 4) queued as the background job — it's the moat, and its data already exists.

**RL note (per your steer):** RL comes after the corpus. Once you share the two reference resources, we construct the RL/preference corpus on top of the curated dataset + the execution traces — not before.
