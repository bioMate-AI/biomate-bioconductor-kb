# Advantage Over Published Work — Honest Assessment + Two-Path Plan

**Date:** 2026-07-28
**Question (user):** *"What is the advantage over other published works?"* Answered
without spin, then a plan to pursue BOTH a tool advantage and a science advantage.

---

## 1. The honest answer

Published work we are measured against:
- **Cantini 2021** (Nat Commun) — 9 bulk jDR methods, 10 TCGA cancers + sim + sc; static
  `momix` notebook. Found intNMF best clustering, MCIA most robust.
- **Rappoport & Shamir 2018** (NAR) — 9 methods, cancer benchmark; static.
- **scMultiBench 2025** (Nat Methods) — ~40 single-cell multimodal methods, 64+22
  datasets, 7 tasks; static codebase.
- **OmniBioAI / OmicOS / OmicsNavigator / OMICX** — LLM-agentic omics platforms (no
  method-comparison benchmark).
- **CEPICS 2019** — web platform running 5 integration methods on your cancer data.

| Dimension | vs the above | Real advantage? |
|---|---|---|
| The methods | we re-implement *their* methods | **None** |
| Finding "no universal winner" | Cantini already showed it | **None** |
| Your-own-data + plain-English + cloud + reproducible + LLM | they're frozen codebases; CEPICS old/narrow/unmaintained | **Modest** (engineering/accessibility, not science) |
| Bulk **and** single-cell SOTA under **one** interface | Cantini=bulk only, scMultiBench=sc only, *separate + frozen* | **Potentially real — NOT built yet** (sc track pending) |
| A new method or new regime | — | **None yet** |

**Blunt truth:** as *science*, we currently have **no advantage** — we reproduce
published methods and a published finding. What we have is a *tool* advantage, and by
itself that is "stacked adjectives" a reviewer collapses (CEPICS already did
"platform runs N methods on your cancer data"). To claim more would be dishonest.

---

## 2. Path A — the TOOL advantage (achievable, modest venue)

**Claim:** the first *living, maintained, your-own-data* platform that unifies the SOTA
of BOTH benchmarks — **bulk (Cantini) AND single-cell (scMultiBench)** — under one
plain-English, reproducible, cloud interface. Cantini and scMultiBench are two frozen
codebases in two different worlds; nobody runs *your* mixed cohort through the best of
both, reproducibly, from natural language.

- **Contribution type:** resource / tool (Bioinformatics, GigaScience, Genome Biology
  application note). NOT a science-novelty paper.
- **What it requires:** harden the bulk set (7 methods, matched-k, per-omics SOTA
  normalization, speed-profiled) + build the **single-cell track** (StabMap, totalVI,
  GLUE, Seurat-WNN) under the same interface + reproduce both benchmarks on canonical
  cohorts to prove parity.
- **Status:** 6/7 bulk methods E2E (MOFA2, SNF, intNMF, iClusterPlus, JIVE, MCIA-on-CLL);
  matched-k fair comparison working; sc track = next.

## 3. Path B — the SCIENCE advantage (the real bet, high-end IF it lands)

The published benchmarks left specific regimes open. The one we already have apparatus
for — and which scMultiBench *explicitly names as an open problem* — is
**missing-modality / mosaic robustness at scale.**

**The bet:** systematically characterize how each integration method's subtype recovery
degrades under (a) a *removed* modality, (b) an *added uninformative* modality, (c)
*partial sample overlap* (each omic measured on a different sample subset — the real
mosaic case) — across **7 methods × multiple cohorts**, and identify *which mechanism
family is robust to which perturbation.*

- **Why it could be genuinely new:** Cantini/scMultiBench benchmark *complete-data*
  recovery; they do not systematically map *robustness-to-missingness by method
  mechanism*. Our 2×2 pilot already found the seed result (ARD-sparse methods robust to
  a junk view; equal-weight fusion degraded — even by a label-containing view). Extending
  that to a full method×perturbation×cohort map is a real, non-obvious contribution IF
  the pattern generalizes.
- **Why the platform matters here:** the sample-intersect + universal interface + 7
  methods make this sweep *runnable* — and reproducible on a user's own partial-overlap
  data, which is the practical payoff (real cohorts almost never have all omics on all
  samples).
- **Honest gate:** this is a *bet*. It is high-end only if the robustness pattern is
  clean and generalizes. If it's noisy/cohort-specific (as our predictor experiment
  turned out), it degrades to a supporting result for Path A. We will know only by
  running it — and we will report it honestly either way.

## 4. Decision: pursue BOTH (user directive)
- **Path A** is the safe, real deliverable — the powerful platform + a tool/resource
  paper. Continue hardening bulk + build the sc track.
- **Path B** is the science bet — run the missing-modality robustness sweep across the
  7-method foundation; if it yields a clean, generalizable mechanism→robustness map,
  that is the high-end paper; if not, it strengthens Path A.
- Sequencing: finish the bulk foundation (all 7 methods × 3 cohorts, matched-k) →
  immediately reuse it as the substrate for the Path-B robustness sweep. Same apparatus,
  two outputs.

Related: [[project_multiomics_benchmark]]; `docs/20260728_MULTIOMICS_FOUNDATION_ROADMAP.md`
(the SOTA build plan); `docs/20260728_MULTIOMICS_FINDING_AND_COMPETITIVE_REASSESSMENT.md`
(the 2×2 seed result Path B extends).
