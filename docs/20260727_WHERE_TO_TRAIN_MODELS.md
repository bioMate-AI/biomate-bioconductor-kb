# Where BioMate Should (and Shouldn't) Train Its Own Models

**Date:** 2026-07-27
**Context:** The target-discovery scorecard, the gate-3 interaction harness, and the autoimmune-stratification thesis are all built. This doc answers two questions: *what resources is that work using?* and *where — if anywhere — do we train our own model to create a defensible improvement (a moat)?*
**Companion docs:** `20260727_AUTOIMMUNE_STRATIFICATION_STRATEGY_v2.md` (§4b LLM plan), `20260726_TARGET_DISCOVERY_BUILD_FINDINGS_AND_PLAN.md`.

---

## 1. Resources currently used — and the uncomfortable truth

Everything built to date runs on **public resources + published methods + our own infra**. Almost none of it is proprietary.

**Data / live APIs (all public):**
- **Open Targets Platform** (live GraphQL) — target–disease evidence + prioritisation panel.
- **gnomAD / LOEUF** — genetic-constraint safety.
- **Stratification substrate:** AMP AIM, 3TR / ADEx, ImmPort/ImmuneSpace, HLA Ligand Atlas, IEDB, VDJdb, DICE / OneK1K.

**Methods (algorithms, not data — all published):**
- Open Targets harmonic-sum association aggregation (Ochoa 2021/2023; Buniello 2025).
- Genetic-support-of-success (Nelson 2015; Minikel 2024).
- Target Development Level (Oprea 2018).
- FDA–NIH BEST interaction-testing framework (the gate-3 test).

**Compute / infra (ours):**
- Hand-rolled statistics — the gate-3 interaction harness uses *no external data at all*, only the client's trial CSV.
- BioMate's 4,000+ workflow catalog (orchestration).
- **Ludwig (LoRA/QLoRA) training module** (`backend/lib/galaxy/ai/ml_training/`) + **vLLM adapter serving** (`infra/vllm`).

**Key point.** Rules + public data are **trustworthy and citable** — which is exactly why they belong at the decision layer. But they are **not a moat**: any competitor can hit the same Open Targets endpoint and read the same papers. This is the "software-only players are commoditized by shared public data" objection (the reason Immunai built a wet lab). A model retrained to reproduce what Open Targets already computes buys us nothing.

---

## 2. Where NOT to train a model

Two components must stay **transparent, not learned** — because for them, *the transparency is the value*:

- **The gate-3 interaction test.** It is a regulatory-grade statistic (biomarker × treatment interaction, per FDA–NIH BEST). A black-box "gate-3 predictor" is worthless to FDA, to a pharma biostatistician, and to a trial design. Its credibility comes from being a citable, reproducible test — not from accuracy on a training set.
- **The primary Open Targets target ranking.** UCB (and every pharma translational team) explicitly want a closed, auditable, human-in-the-loop ranker — *not* a model that ranks targets for reasons you can't see. Train here and you destroy the exact trust that makes it sellable. (A *learned second opinion* is fine — see §3.3 — as long as the decision-of-record stays transparent.)

Rule: **do not train a model where a human is signing off on a regulated decision and needs to see why.**

---

## 3. Where to train models for a defensible moat (ranked)

### #1 — Per-client models / adapters (Ludwig L1–L4) — *the moat is the data, not the algorithm*
The defensible asset is the **data nobody else has**: a client's cohorts, their past stratification/target decisions, their assay quirks, their report house-style. A model fine-tuned on *their* private data cannot be reproduced from public sources — and it never leaves their trust boundary.

**Build sketch (assembly, not greenfield — the engine exists):**
- **Reuse:** `backend/lib/galaxy/ai/ml_training/` (`ludwig_llm`, LoRA/QLoRA, MLflow tracking, AWS-Batch-validated) + `infra/vllm` (`sync-adapters.sh`, per-adapter serving).
- **Phases & data contract:**

  | Phase | What | Data contract (per client) | Reused vs new | IP / isolation |
  |---|---|---|---|---|
  | **L1 RAG** | Index client docs / cohort metadata; LLM answers + drafts reports grounded in their corpus | Their documents + metadata; no training | RAG layer over existing serving; **new (thin)** | Nothing leaves; closed retrieval |
  | **L2 per-client LoRA** | Fine-tune a LoRA adapter on their instruction/decision data (past calls, report style) | `{instruction, output}` pairs from their history | **Exists** (`ludwig_llm`); wire to stratification use case | Data in a closed Batch run; adapter is the only artifact |
  | **L3 multimodal** | Ludwig multimodal model over their omics → endotype/biomarker/responder predictions | Their tabular omics + labels | Ludwig declarative multimodal config (**new config, existing engine**) | Closed |
  | **L4 federated** | Adapters trained **client-side**; only weights/deltas shared | Data never exported | Federated wrapper around L2 | Data never leaves client (IRB-locked case) |

- **Serving:** vLLM multiplexes **many client adapters over one shared base** → cost-efficient; each client gets a private model without a dedicated GPU per tenant.
- **Evaluation:** held-out **client-specific** tasks (their stratification/report tasks), **MLflow-tracked** (already in the module), same gate discipline as the transparent layer.
- **Why it wins:** IP-safe (matches UCB's closed-system requirement and the federated-tensor precedent), domain-adapted, and **impossible to clone from public data**. Lowest build cost (engine is done), highest defensibility.

### #2 — HLA-DP/DQ immunopeptidome antigen-prediction model — *the one genuine DL bottleneck*
This is the single place the field itself names deep learning as the answer, not rules: the autoantigen/neoantigen **search problem** — no-enzyme search space, PTM combinatorics, FDR control at scale — and **public class-II coverage is thin exactly for HLA-DP/DQ**, the alleles carrying autoimmune genetic risk. DL has already expanded HLA Ligand Atlas coverage **46–100%** `[UNVERIFIED — the exact "46–100%" figure could not be traced to a source; DL-driven immunopeptidomics gains are real and documented (CAPTAn HLA-II DL, Immunity 2023; Prosit ~7× ID boost), but soften or re-source this specific number before external use]`, so the value is demonstrated, not speculative.

**Build sketch:**
- **Data:** HLA Ligand Atlas + IEDB + public MHC-II eluted-ligand datasets (semi-public), augmented with **client immunopeptidome** runs. Deliberately over-weight **DP/DQ** to fill the gap.
- **Model approach:** fine-tune / train an **HLA-II binding predictor + a de-novo search rescoring model**, focused on DP/DQ; use it to (a) prioritise candidate antigens and (b) rescore spectra to lift sensitivity/FDR.
- **Integration:** plugs directly into BioMate's **existing antigen-resolution chain** — `airrflow` (TCR/BCR) + `hlatyping` + `epitopeprediction` + LC-MS immunopeptidomics — as the improved prediction/rescoring step.
- **Who it serves now:** **Mongoose Bio** (MD Anderson TCR-T spinout built on an Immunopeptidome Discovery Platform) is the immediate, local customer; tolerance developers (Repertoire-class) are the broader market.
- **Why it wins:** semi-public data **+ real DL improvement** = the highest *technical* moat, and it is the "atlas thesis" lane the strategy doc flagged.

### #3 — Learned advisory ranker / responder-predictor — *the flywheel*
As BioMate runs pilots it accumulates **private outcome data across engagements** (which targets/biomarkers actually panned out). A model trained on that **compounding, cross-engagement** data — federated and IP-respecting — becomes the software analog of a wet-lab flywheel: it improves with every client. **Keep it strictly advisory** (a second opinion alongside the transparent ranker / the gate-3 test), so the decision-of-record stays auditable. Value compounds over time; not a day-one build.

---

## 4. The principle

**Train where the data is proprietary (per-client, or the accumulating cross-engagement outcome record) or where deep learning genuinely beats rules (immunopeptidome / antigen prediction). Keep the public-data and decision-layer work — Open Targets ranking, the gate-3 interaction test — transparent, citable, and un-trained, because there the trust *is* the product.** Retraining a model to redo what Open Targets already does on public data is not a moat; a per-client adapter on data no one else holds, or a DP/DQ antigen model on a bottleneck the field can't crack, is.
