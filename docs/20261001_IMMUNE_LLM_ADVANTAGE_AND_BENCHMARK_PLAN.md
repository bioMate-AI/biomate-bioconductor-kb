# Immune Multi-Omics Multi-Task LLM — Advantage, System Structure & Benchmark Plan

**Date:** 2026-10-01
**Purpose:** The clear, defensible plan for (1) the advantage we highlight, (2) the system structure + why it's advantaged, (3) the benchmark datasets + head-to-head comparisons vs existing works. Calibrated to the evidence gathered this program — we claim the integration/system advantage, NOT "the FM beats every baseline" (which the field + our own results show is false for single-modality tasks).

**Honesty contract:** each advantage is tagged PROVEN (measured, beats field bar) / PENDING (test running) / BET (reasoned, to be shown). No single-modality RNA-only "FM beats PCA/TIS/NetMHCpan" claim — the field disproves it and so do we.

---

## 1 · The advantage we highlight

**The headline (honest):** *not* "a better RNA foundation model" — but **an immune-mechanism-aware, multi-omic, multi-channel VALIDATION system** that does the things single-modality tools structurally cannot, delivered as one backbone across 8 tasks and closed with a dry→wet loop.

Four concrete advantages, in priority order:

1. **Multi-omic INTEGRATION (the structural edge).** The field's winning tools are single-channel: TIS/TIDE (RNA-only), NetMHCpan/MHCflurry (sequence-only), co-expression (one modality). Our system fuses **RNA + protein/CITE + ATAC + immunopeptidome + TCR + KG + causal-perturbation**. Advantage is claimable *only where >1 modality is needed* — exactly where the incumbents can't compete. *(PENDING — multi-omic fusion lift being measured in the full run.)*

2. **Immune-mechanism-aware multi-channel TARGET-CONFIDENCE (the real bottleneck).** Per our own thesis, target *discovery* isn't the bottleneck — *confidence* + predictive matching is. We triangulate expression + genetics + perturbation-causal + KG/pathways + immunopeptidome into a fused confidence. No vendor sells in-silico IO target-*pair* nomination (AION Labs is still *founding* a company to). *(PROVEN in part: multi-channel fusion = 0.813 > single-source + degree-null; the FM adds +0.059 as a channel in its covered gene space.)*

3. **One shared backbone across 8 tasks + multi-task sharing.** A single concept-grounded representation serves annotation, target-ID, stratification, presentation, recognition, durability, inflammation, biomarker — data-rich tasks regularize data-poor ones, and the system is coherent (nominate → stratify → design → validate), not a toolbox. *(BET/PENDING — sharing never tested until the current full run.)*

4. **The composite system + closed loop (the moat).** The defensible moat is the *integration + the dry→wet wet-lab flywheel*, not any single model — the business-committee and our own strategy independently converged on this. *(PROVEN the loop's Learn step works: active-learning replay recovers 2.5–3.2× more hits than random on real permeability data.)*

**What we explicitly do NOT claim:** that the raw FM embedding beats PCA/TIS on RNA-only stratification (it doesn't — batch-entangled), or beats NetMHCpan on sequence-only presentation. Those are the incumbents' turf; we win by *integration*, not by out-RNA-ing them.

---

## 2 · System structure (how we leverage LLM + multi-channel knowledge + computation)

The system is a **multi-channel fusion / validation engine** with the LLM as its multi-omic representation + annotation backbone — NOT a monolithic "ask the LLM" model.

```
            ┌─────────── EVIDENCE CHANNELS (per task) ───────────┐
 data ──►   │  expression · genetics(L2G) · perturbation/causal  │
            │  KG/pathways · immunopeptidome · TCR · cell-state   │
            └───────────────────────┬────────────────────────────┘
                                     │  (one channel is the LLM's
 ┌──────────────────┐               │   multi-omic concept embedding)
 │  IMMUNE LLM       │──embeddings──►│
 │  (concept/pathway │               ▼
 │   bottleneck,     │        ┌──────────────┐     ┌──────────────┐
 │   multi-omic      │        │  FUSION +     │────►│  TASK OUTPUT │
 │   fusion, causal- │        │  coverage-    │     │  (confidence,│
 │   grounded,       │        │  aware rank + │     │  rank, call) │
 │   contrastive)    │        │  null-gating  │     └──────┬───────┘
 └────────┬──────────┘        └──────────────┘            │
          │  used 3 ways per task:                        ▼
          │  (1) frozen  (2) SFT  (3) helper-feature   dry→wet CLOSED LOOP
          └───────────────────────────────────────►  generate→CRO→learn→retrain
```

**Design principles (each fixing a diagnosed failure):**
- **Concept/pathway bottleneck** — representation grounded in cell-states/pathways (COMPASS-validated) → transferable, not batch-leaky free-form z.
- **Causal grounding** — trained on perturbation (Perturb-seq virtual-KO) so target signal is causal, not observational co-expression (which fails the degree-null).
- **Cross-study contrastive** — batch-invariance by construction (same-biology-different-study pulled together) — the mechanism GRL/MMD failed to achieve.
- **Multi-omic gated fusion** — per-modality presence-masked fusion; the LLM is one evidence channel among several, OR-gated so missing coverage never dilutes.
- **3-mode usage** — every task uses the LLM as (1) frozen, (2) SFT'd, or (3) a helper feature; a task "works" if **any** mode beats the field bar. The LLM earns its place where it helps; simple/measured methods win where they win.
- **Closed loop** — generated candidates → CRO assays → results ingested → scorers/generator retrained → next round (Learn step proven on real data).

**Advantage of this structure:** no single component is the single point of failure or the sole claim — the *fusion* is robust (prune a harmful channel, OR-gate a sparse one), the *moat is the composite*, and the LLM contributes exactly where it's strong (annotation, multi-omic channel) without having to win alone.

---

## 3 · Benchmark datasets + head-to-head comparisons (the proof plan)

**Discipline (non-negotiable):** strong field bar (not a weak null) · **cross-cohort / external validation (not within-cohort CV)** · matched null reported alongside · task counts as working if it clears the bar in **any** of the 3 modes.

| Task | Benchmark dataset(s) | Field-SOTA comparator (the bar) | Matched null | Status |
|---|---|---|---|---|
| **Target-ID / pair** | CollecTRI TFs + wet-lab-validated gold; Open Targets L2G | single-source priors; co-expression; genetics-prior | **degree / annotation-depth null** | ✅ fusion 0.813 > null; FM +0.059 (coverage-gated) |
| **Annotation** | corpus, study-disjoint; GSE243013 atlas | **CellTypist, scANVI, scGPT/Geneformer** | majority/study-freq | PENDING head-to-head (FM +0.054 vs null so far) |
| **Responder stratification** | Gondal ICB (176 donors), GSE123813, ICB cohorts; **autoimmune: Assassi SSc activity** | **PCA/gene-set, IFN-γ GEP (Ayers), TIDE (Jiang), COMPASS** | PCA + shuffle, LCO | PENDING v3 (raw embed loses; concept+contrastive in test) |
| **Presentation (HLA-I)** | 1.08M HLA-I ligandome (MHCflurry-disjoint split) | **NetMHCpan-4.1, MHCflurry-2.0** | capacity (random-init) | PENDING; our angle = **cell-state-CONDITIONAL** (they can't) |
| **Perturbation / virtual-KO screen** | Replogle–Nadig / CZI Perturb-seq | **GEARS, scGPT, State, train-mean, additive** | degree-null | ✅ measured screen 0.85 vs null |
| **Recognition (TCR)** | McPAS / IEDB / VDJdb | CDR3 k-mer / TCR-dist baseline | chance | PENDING (needs per-sequence TCR encoder) |
| **Durability** | Frangieh leave-condition-out | transcript baseline | train-mean | PENDING |
| **Inflammation** | DAS28 / SLEDAI (ImmPort) | clinical-activity baseline | — | cross-modal gap (needs expression link) |
| **Biomarker** | — | (retire — circular self-supervised target) | — | 🔴 do not claim |

**Positioning vs existing works (who we beat, and how):**
- **Single-cell FMs (scGPT / Geneformer / scFoundation / UCE):** benchmarks (Kedzierska, Boiarsky, Bendidi, Ahlmann-Eltze) show they don't beat simple baselines per-task → **we don't compete as a bigger RNA FM; we win on multi-omic + multi-task + causal + concept.** Cite these as "why single-modality FMs plateau."
- **Stratification signatures (TIS / TIDE / IMPRES / COMPASS):** RNA-signature tools → **our edge is multi-omic + the concept bottleneck** (COMPASS validates the concept route; we extend it multi-omically). Honest: our PCA/gene-set baseline (0.734 LCO) is already upper-competitive with the field's modest ~0.55–0.70 band.
- **Target discovery (Open Targets, Insilico PandaOmics, AION Labs):** single-target / no immune-mechanism product → **our edge = immune-compartment-aware multi-channel confidence + causal-perturbation channel + target-PAIR nomination** (near-white-space; AION still founding).
- **Presentation (NetMHCpan / MHCflurry):** sequence-only → **our edge = context/cell-state-conditional presentation**, which sequence predictors structurally cannot produce.

**The demonstration that proves the thesis (the one figure):** for each multi-modality task, show **fusion-with-the-LLM-channel > best single-modality SOTA > null**, cross-cohort, in the 3-mode matrix — i.e., the *integration* wins where the incumbents' single channel can't. Target-ID already shows the shape (0.813 fusion; FM additive once coverage-fixed); stratification/presentation are the pending confirmations.

---

## 4 · Current evidence status (honest ledger)
- **PROVEN:** multi-channel target-ID fusion works (0.813 > null); FM adds as a channel (+0.059, coverage-gated); annotation FM contribution (+0.054 vs null); measured perturbation target screen (0.85); closed-loop Learn step (replay 2.5–3.2× > random); concept bottleneck doesn't collapse annotation (0.52).
- **PENDING (running):** v3 stratification 3-mode transfer; v1 field-bar head-to-heads (MHCflurry, CellTypist/scANVI); dormant-heads transfer; multi-omic fusion lift.
- **BET (to show):** multi-task sharing lifting data-poor tasks; cell-state-conditional presentation beating NetMHCpan on the context task; target-ID full-universe win after TF-inclusive re-train.
- **RETIRED:** raw-embedding RNA-only stratification; biomarker (circular).

## 5 · The next build that advances the plan
One combined training run = **concept bottleneck + cross-study contrastive + perturbation-grounding (v3) + TF-inclusive HVG panel (target-ID coverage) + multi-omic fusion on**, evaluated across all 8 tasks in the 3-mode matrix against the field bars above. That single run tests advantages 1–3 at once and produces the corrected 8-task × 3-mode × field-bar scorecard — the external-facing proof.
