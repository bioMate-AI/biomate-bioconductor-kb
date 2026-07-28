# BioMate Internal Model — Feasible Build Plan (data · base model · evaluation · phasing)

**Date:** 2026-07-27
**Purpose:** turn the strategic "where to train" decision into an operational plan — for each model track, exactly *what data*, *which base model*, *how we evaluate*, *what runs today vs needs GPU/real client data*, and *the phased milestones*.
**Companion docs:** `20260727_WHERE_TO_TRAIN_MODELS.md` (strategy — which tracks are a moat), `20260727_HARMONIZATION_SURVEY.md` (why grounded + OOD eval), `20260727_VIRTUAL_TRIALS_SURVEY.md`, `20260727_RESOURCE_REGISTRY.md` §9, `20260727_INTERNAL_MODEL_EXPERIMENT1.md` (Track A, first runnable experiment).

---

## 0. The design decision up front (the "100M vs 15–40M" question)

The external note asked *why a 100M-param model would be worse than a 15–40M one.* Resolved position:

**Parameter count is the wrong axis. The axes that matter are (a) grounding and (b) data-fit.** For BioMate's actual tasks — ontology mapping, per-client report/decision style, DP/DQ binding — a **small model that is retrieval-grounded and constrained** beats a larger free-generation model, because:

1. **Hallucination scales with free generation, not with being small.** A 100M model asked to *emit* an ontology ID free-form will invent plausible-but-wrong IDs (~17% out-of-dictionary `[UNVERIFIED — the specific 17% figure is not traced to a primary source; the ID-hallucination failure itself is well-documented]`). A 15–40M model that can only *select among retrieved candidates or abstain* cannot hallucinate an ID **by construction**. Constrained decoding, not scale, is what buys correctness here.
2. **The data is small and narrow.** Per-client decision histories and DP/DQ eluted-ligand sets are thousands–tens-of-thousands of examples, not billions of tokens. A larger base overfits or needs data we don't have; a small base + LoRA on the narrow signal generalizes better and trains on CPU/one GPU.
3. **Serving economics.** vLLM multiplexes many small per-client adapters over one shared base. Bigger base = fewer tenants per GPU = worse unit economics for a per-client product.

**Conclusion:** pick the *smallest base that fluently follows instructions*, then get accuracy from **retrieval-grounding + constrained decoding + LoRA on proprietary data**, not from parameter count. "Latest SOTA" here means the current best *small* open instruction model at build time, not the biggest.

---

## 1. Tracks (in priority order) with concrete build specs

### Track A — Metadata-mapping PROPOSER (grounded, constrained, OOD-aware) ✅ *first experiment in flight*
The lowest-cost, highest-certainty build; it also de-risks the whole "LLM in a regulated pipeline" thesis by proving zero-hallucination is achievable.

| Spec | Choice |
|---|---|
| **Task** | free-text clinical/sample metadata → canonical ontology term (EFO/Mondo/HPO/Cell Ontology) **or ABSTAIN** |
| **Data (bootstrap, public)** | ontology labels + synonyms (EFO, Mondo, HPO, CL) via **text2term**; construct `{free_text → canonical_id}` pairs from synonym tables + realistic messy variants; **explicit out-of-dictionary negatives** that must map to ABSTAIN |
| **Data (moat, private)** | each client's historical metadata→term decisions (their vocabulary quirks) |
| **Base model** | smallest fluent open instruction model; **run as a candidate-selector, not a generator** |
| **Method** | deterministic retriever (string/synonym match over the ontology dict) → model **selects one retrieved candidate or abstains**; can never emit an ID outside the retrieved set |
| **Evaluation** | in-dictionary accuracy · **out-of-dictionary abstention rate** · **hallucinated-ID rate (must be 0 by construction)** · human-review load |
| **Runs today?** | **Yes, CPU** — the retriever+ranker harness runs stdlib-only; the LoRA is a drop-in upgrade. This is `20260727_INTERNAL_MODEL_EXPERIMENT1.md`. |
| **Moat** | per-client adapter learns *their* mapping conventions; grounding keeps it audit-safe |

### Track B — Per-client stratification / report LoRA (Ludwig L2) — *the primary commercial moat*
| Spec | Choice |
|---|---|
| **Task** | draft stratification rationales / methods sections / decision memos in the client's house style, grounded in their corpus |
| **Data** | `{instruction, output}` pairs from the client's past calls + report history (never leaves their trust boundary) |
| **Base model** | shared open base; **one LoRA adapter per client** |
| **Method** | `backend/lib/galaxy/ai/ml_training/` `ludwig_llm` (LoRA/QLoRA, MLflow-tracked, AWS-Batch-validated) → adapter artifact only; **vLLM `sync-adapters.sh`** multiplexes adapters over the shared base |
| **Evaluation** | held-out **client-specific** tasks; style/faithfulness rubric; **RAG-grounding faithfulness** (no ungrounded claims); MLflow per-client dashboards |
| **Runs today?** | **Engine exists**; needs *real client instruction data* to be meaningful. The demo (`ml_training_examples/stratification_adapter/`) validates the config path without a GPU. |
| **Moat** | trained on data no competitor holds; IP-isolated (closed Batch run; data never pooled) |

### Track C — HLA-DP/DQ immunopeptidome model — *the one genuine deep-learning bottleneck*
| Spec | Choice |
|---|---|
| **Task** | HLA-II (esp. **DP/DQ**) binding/presentation prediction + de-novo spectrum rescoring, to lift antigen-candidate sensitivity/FDR |
| **Data** | HLA Ligand Atlas + IEDB + public MHC-II eluted-ligand sets (semi-public); **over-weight DP/DQ** to fill the known coverage gap; augment with client immunopeptidome runs |
| **Base model** | fine-tune an HLA-II binding predictor family (NetMHCIIpan-class architecture) + a rescoring head; **not** a general LLM |
| **Method** | train DP/DQ-focused predictor; plug into the existing `antigen_resolution` chain (airrflow + hlatyping + epitopeprediction + LC-MS) as the improved prediction/rescoring step |
| **Evaluation** | held-out eluted-ligand AUC/PPV **stratified by DP/DQ allele**; retrospective recovery of known autoantigens (e.g. celiac DQ2.5 gluten epitopes — see `20260727_ANTIGEN_CELIAC_VALIDATION.md`) |
| **Runs today?** | **No** — needs GPU + curated eluted-ligand data. This is a scoped R&D build, not an assembly. |
| **Moat** | semi-public data **+ real DL improvement** on a bottleneck the field itself names; serves Mongoose Bio / tolerance developers |

### Track D — Learned advisory ranker (flywheel) — *later, strictly advisory*
Trained on **accumulating cross-engagement outcome data** (which targets/biomarkers actually panned out). Kept as a *second opinion* beside the transparent OT ranker and the gate-3 test — never the decision-of-record. Value compounds with each pilot; **not a day-one build** and needs outcomes we don't yet have.

**Where we deliberately do NOT train:** the gate-3 interaction test and the primary OT target ranking stay **transparent, citable, un-trained** — there the auditability *is* the product (see WHERE doc §2).

---

## 2. Cross-cutting evaluation standard (applies to every learned component)

1. **Hallucination rate** — for any component that emits a grounded entity (ID, gene, allele), measure ungrounded-output rate; **design for 0 via constrained decoding**, then verify.
2. **Out-of-distribution / out-of-dictionary slice** — always hold out inputs with *no valid answer*; reward **abstention**, penalize confident wrong answers. (Survey lesson: the failure mode is confident hallucination on OOD inputs.)
3. **Calibration & abstention** — the model must know when it doesn't know; report abstention precision/recall.
4. **Human-review load** — % of outputs a human must correct; the product metric.
5. **Per-client held-out tasks** — Track B/D evaluated on *that client's* tasks, MLflow-tracked.
6. **Gate discipline** — a learned component only enters the pipeline if it beats the transparent baseline on a held-out set *and* stays advisory where a regulated decision is signed off.
7. **Framing** — every model output is **hypothesis-generating**, not confirmatory (virtual-trials survey): a predicted antigen/endotype/mapping is a candidate for confirmation, labeled as such.

---

## 3. Feasibility ladder — what runs now vs what's gated

| | Runs on CPU now | Needs 1 GPU + LoRA | Needs curated data + GPU R&D |
|---|:--:|:--:|:--:|
| **Track A** proposer (retriever+ranker) | ✅ (exp-1) | LoRA upgrade | — |
| **Track B** per-client LoRA | config-validated | ✅ (needs client data) | — |
| **Track C** DP/DQ model | — | — | ✅ |
| **Track D** flywheel ranker | — | needs outcome data | ✅ (accumulates) |

**Honest read:** Track A is demonstrable today end-to-end (and is being demonstrated in exp-1). Track B's *engine* is done and its config path is validated; it becomes real only with a client's private instruction data. Tracks C and D are genuine R&D/flywheel builds — correctly *not* claimed as done.

---

## 4. Phased milestones

- **Phase 1 (now):** Track A exp-1 — bootstrap dataset + constrained-decoding harness + OOD eval, **0 hallucinated IDs verified** on CPU. Deliverable: `20260727_INTERNAL_MODEL_EXPERIMENT1.md` + `ml_training_examples/metadata_proposer/`.
- **Phase 2:** Track A LoRA upgrade — swap the ranker for a small LoRA (Ludwig), re-run the *same* OOD eval, show human-review-load reduction. First real per-client adaptation path.
- **Phase 3:** Track B pilot — with a design partner's (redacted) instruction data, train one client adapter, serve via vLLM, evaluate on their held-out report tasks. Proves data-isolation + house-style adaptation.
- **Phase 4:** Track C scoping — assemble DP/DQ eluted-ligand corpus, baseline NetMHCIIpan on the DP/DQ slice, define the improvement target before training.
- **Phase 5:** Track D — begin logging cross-engagement outcomes behind an advisory ranker; train once enough pilots have closed.

---

## 5. Bottom line

**Feasible, and already started.** The plan is *not* "train one big model" — it's a portfolio of small, grounded, data-isolated components, each with a concrete data source, an honest feasibility tier, and an OOD-first eval. Track A is running on CPU today; Track B's engine exists and waits on client data; Track C is the one true DL R&D bet on the DP/DQ bottleneck; Track D compounds with pilots. Every learned piece stays **hypothesis-generating and advisory** where a regulated decision is on the line — which is exactly what keeps it sellable to translational teams like UCB.
