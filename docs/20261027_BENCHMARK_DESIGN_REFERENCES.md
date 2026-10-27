# Public benchmark design references — what the best AI-scientist / LLM-provider benchmarks do, and what we borrow

**2026-10-27.** The task-design committee's unanimous #1 upgrade was "score a hidden, independently-verifiable
outcome from an artifact-backed task, not the naming of a method." This survey confirms that the strongest
public benchmarks — from LLM providers (OpenAI) and AI-scientist groups (Princeton, FutureHouse, Valence) —
have already converged on that exact pattern. We should borrow their designs rather than reinvent.

## A. Execution-grounded verification (the pattern to adopt)

| Reference | Who / when | Design pattern worth borrowing | Result (hardness) |
|---|---|---|---|
| **SWE-bench / SWE-bench Verified** | Princeton 2023 (arXiv:2310.06770); OpenAI Verified 2024 | Agent works in a **per-instance Docker container** (bash, edit files, submit a patch); scored by **hidden tests** — `FAIL_TO_PASS` (the bug is fixed) **plus** `PASS_TO_PASS` (nothing else broke). 500-item expert-curated subset. | frontier agents solve a minority; even "verified" tests miss coverage on 26/500 (UTBoost) — a caution on hidden-test completeness |
| **MLE-bench** | OpenAI, Oct 2024 (arXiv:2410.07095) | 75 real Kaggle competitions; **held-out test via preparation scripts**; graded by the **competition's own metric**; **human leaderboard** medal thresholds as the baseline | best setup reaches bronze-medal level in ~17% |
| **ScienceAgentBench** | ICLR 2025 (arXiv:2410.05080) | Output is a **self-contained Python program**; graded on the **program + its execution results + cost**; explicit **contamination mitigation**; tasks drawn from 44 peer-reviewed papers | best agent 32.4% (34.3% with expert knowledge) |
| **CORE-Bench** | Princeton, Sep 2024 (arXiv:2409.11363) | **Reproduce published results**; 3 **difficulty tiers defined by how much reproduction info is given** (not by vocabulary); agent sets up code and answers questions about the outputs | hardest tier 21% |
| **PaperBench** | OpenAI, Apr 2025 (arXiv:2504.01848) | Replicate 20 ICML papers; **hierarchical rubrics co-developed with the original authors** (8,316 gradable sub-tasks); an **LLM judge that is itself validated** against a separate judge benchmark | best 21% vs. human 41% |

**Takeaway:** the headline score is always a *hidden, executed outcome* (tests pass / metric on held-out data /
program runs and reproduces), never "did the agent name the right method." Difficulty is set by information
availability, and contamination/leakage is controlled explicitly. Where a judge is unavoidable, it is validated.

## B. Leakage-aware splits and anti-gaming metrics (for any prediction task)

| Reference | Design pattern worth borrowing |
|---|---|
| **PLINDER / PINDER** (bioRxiv 2024.07.17.603955 / .603980) | **Task-specific leakage-aware splits** — leakage is defined per task (protein-sequence + pocket + interaction + ligand similarity); what counts as leakage for docking differs from co-folding |
| **PoseBusters** (Chem Sci 2024) | **Physical-validity checks** (RDKit: geometry, clashes, planarity) beyond a single accuracy number, so a method can't game the metric with invalid outputs; and the finding that **classical/mechanistic tools beat deep learning** on validity + generalization |
| **Therapeutics Data Commons (PyTDC)** | Standard **scaffold / cold-start splits** — with the honest caveat that scaffold splitting does **not** remove analog, duplicate, label, temporal, or provenance leakage |
| **Polaris** (Valence, industry-led, 2024–2025) | **Blind community challenges** + **meta-analysis of common pitfalls**; an antidote to leaderboard-chasing; a credible model for *releasing* a benchmark |
| **Tox21 reproducible leaderboard** (Nov 2025, arXiv:2511.14744) | Reproducibility-first ADMET leaderboard |

**Takeaway:** PoseBusters directly mirrors our own finding (mechanistic dose-selection rule 0.85 vs. chat LLMs
0.11–0.50) — the mechanistic baseline beating the learned one is a recognized, publishable design, not a weakness.

## C. Domain anchors for DrugDev (our weakest external reference)

- **TrialBench** (arXiv:2407.00631, 2024): 23 AI-ready clinical-trial datasets across 8 prediction tasks,
  **including drug dose-finding** — and dose-finding is explicitly one of its **weakest** tasks (F1 < 0.50).
  This is the nearest public anchor for our Phase-I dose task; it is *predictive-dataset* in form, so our
  **execution-grounded, decision-and-simulation** framing is the complement, not a duplicate. Cite it directly.
- **BixBench** (FutureHouse, arXiv:2503.00096, Mar 2025): expert "capsules" = **real dataset + notebook +
  hypothesis + results**, with open-answer + MCQ questions. Borrow the *attach-real-data, open-ended-analysis*
  form; **avoid** its scoring weakness (open/MCQ grading that leans on an LLM) in favor of deterministic /
  execution grading.

## D. Concrete adoption plan mapped to our three benchmarks

- **RealBio → adopt the SWE-bench pattern.** Convert failure-repair and workflow-generation into
  **container-grounded** items: a failed workspace + raw logs (no diagnosis), the agent submits a config/code
  patch, and scoring is a **hidden pass/fail** on a resumed run plus a "nothing-else-broke" check and a
  safety check (no dropped samples / changed reference build). Keep label-match only as a cheap diagnostic.
  Borrow ScienceAgentBench's program + execution-result + cost scoring for workflow generation.
- **Channel routing → adopt MLE-bench/CORE-Bench outcome scoring.** Replace single-label classification with
  **multi-step resource plans** scored by downstream success (correct record retrieved / compatible accession /
  workflow actually initiated), plus abstention cases; keep route-label accuracy as a diagnostic only.
  Calibrate difficulty by information availability, CORE-Bench-style.
- **DrugDev → adopt PoseBusters + MLE-bench + the modeling-contract idea.** Publish a **reproducible modeling
  contract** (physiology, formulation, clearance scaling, analyte, molecular weight, tolerances); **blind the
  compounds** (structures + measured properties, not names) to kill recall; score **operating characteristics**
  from a **hidden** toxicity curve (MTD-selection frequency, overdose allocation) with Monte-Carlo uncertainty;
  keep the **mechanistic baseline** as the PoseBusters-style "classical beats learned" anchor. Cite TrialBench.

## E. One cross-cutting rule we already satisfy, and one we must add

- **Already satisfied:** a non-model baseline (our keyword 0.80 on routing, mechanistic 0.85 on dose) — the
  field expects this (MLE-bench human baseline, PoseBusters classical baseline).
- **Must add:** **hidden, executed verification** as the primary score, and **leakage-aware / contamination
  controls** with empirically-calibrated difficulty — the common denominator of every top benchmark above.
