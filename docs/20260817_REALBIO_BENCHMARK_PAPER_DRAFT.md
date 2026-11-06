# RealBio: an open, objectively-scored benchmark for real-world bioinformatics workflow automation

**Target venue:** NeurIPS Datasets & Benchmarks / *Bioinformatics* (Application Note) / GigaScience
**Prepared:** 2026-08-17

## Authors

**Yaoyun Zhang**¹, **Andrew Dike**¹,²

¹ BioMate AI
² BizBildr

**Corresponding author: Andrew Dike — a.dike@bizbildr.com** (BizBildr). BioMate-AI correspondence for Yaoyun Zhang: **yaoyun.zhang@biomate.ai**.

---

## Abstract

Benchmarks for AI agents in bioinformatics are typically **scored by each system's own judge on its own private task set**, making cross-system numbers non-comparable and inviting (often unintentional) self-grading. We present **RealBio**, an open, objectively-scored, cross-system benchmark that is anti-self-grading by construction: **610 real-world bioinformatics-automation items across 5 RealBio-native objective-ground-truth tasks** (cross-domain workflow routing, parameter pre-fill, protocol thresholds, execution auto-repair, workflow generation), together with **~50 items from three drug-development benchmarks (BOIN dose-escalation, PBPK, end-to-end drug-discovery) cross-published here from the companion DrugDev suite** (§3) because they share the same export and scorer, each with **published ground truth graded by a single shared open scorer** (`score.py`, CC-BY-4.0) — no LLM judge for the objective tasks. RealBio is fair by design: a frozen prompt template per task, an identical candidate set, and one scorer applied identically to every system, so any team can run its own system on the fixed items and land directly on the leaderboard. Our cross-system sweep of eight frontier and open-weight LLMs, a domain agent, and a workflow product finds that **no single system dominates**: LLMs used the way they are actually deployed fail simulation tasks (PBPK: mean 0.075 within-2-fold) and are only mediocre at deterministic dose-finding (BOIN: mean 0.271 exact-MTD), yet do well at knowledge tasks (ligand ranking: mean 0.696 Spearman). The largest cross-system spread is on curated-domain routing, where — under the disclosed product-vs-deployment-default scoping (§4) — one entrant (the BioMate platform, described in a companion systems paper by the same authors) routes at 0.965 [0.930, 0.983] with no LLM in the loop, versus 0.345–0.615 for the same LLMs used directly. RealBio's contribution is the open, objectively-scored, anti-self-grading protocol and dataset on which any team can place its own system — not a ranking of any single one.

> **Honesty contract (kept in the paper).** Every reported number traces to committed `score.py` output on committed `predictions.jsonl`. No number is asserted from memory. Abstention (no grounded answer) is scored as not-correct but is never counted as correct — precision is protected. Systems are credited where they genuinely lead.

---

## 1. Introduction

Large-model "agents" now claim strong performance on biomedical research tasks, but the evidence base has a structural flaw: **the benchmark, the ground truth, and the judge are frequently owned by the same group that owns the system under test**, and results are reported on private or subsetted task sets. A score produced by a system's own judge on its own private set cannot be compared across systems and cannot be independently checked — which is precisely the question a reader asks first ("did you just grade yourself?").

RealBio inverts this. It fixes the items, publishes the ground truth, and ships one open scorer that anyone runs identically on any system. Its tasks are **real-world bioinformatics automation** — the operations a working analyst actually needs (route a plain-English request to the right pipeline, fill its parameters, set protocol thresholds, repair a failed run, generate a workflow, run a dose-escalation / PK / end-to-end design) — not multiple-choice trivia. And it is paired with a **pre-registered ablation** so that a system-level result is never mis-read as a claim about a model's raw intelligence.

**Contributions.** (1) A public, objectively-scored, 8-task / 660-item benchmark of real bioinformatics automation. (2) A pre-registered, fairness-by-construction evaluation protocol with a capability-vs-product ablation. (3) A cross-system leaderboard over current frontier and open-weight models plus a domain agent (Biomni). (4) An open scorer + dataset (CC-BY-4.0) that makes every number reproducible and refutable.

## 2. Related work and how RealBio differs

Existing agentic-bio benchmarks (BixBench, LAB-Bench, ScienceAgentBench, BioAgentBench, and system-specific evaluations) advanced the field but commonly (a) rely on an LLM judge, (b) report on private or subsetted items, (c) conflate "the model reasoned well" with "the product added value," and (d) are frequently run only by the system's authors. RealBio's design targets each: objective scoring where the task admits it, published fixed items, direct-use conditions that match how the systems are actually deployed, and a released scorer others run.

**Table 1 | RealBio versus existing agentic-bio benchmarks.**

| Benchmark | Open items | Open scorer | Cross-system | Objective scoring | Ablation |
|---|---|---|---|---|---|
| BixBench (FutureHouse, 2025) | Yes | Yes | Partial (2 models) | No (LLM judge) | Yes |
| LAB-Bench (FutureHouse, 2024) | Partial (80% public) | Yes | Yes (8 models) | Yes (multiple-choice) | Partial |
| ScienceAgentBench (2024) | Partial (gated full set) | Yes | Yes (5 LLMs × 3 frameworks) | Partial (exec + visual LLM judge) | Yes |
| BioAgentBench (2026) | Yes | Partial (LLM-graded) | Yes (10 models × 3 harnesses) | No (LLM judge) | Yes (perturbations) |
| BiomniBench (2026) | Partial (50% public) | Partial (rubrics only) | Yes (3 agents + 9 models) | No (LLM judge) | Partial |
| **RealBio (this paper)** | **Yes** | **Yes (score.py, CC-BY-4.0)** | **Yes (8 LLMs + BioMate + Biomni)** | **Yes (exact-match where the task admits)** | **Yes (engine-free direct-LLM)** |

Across the five agentic-bio benchmarks we verified, each opens some axes but none opens all of them together as RealBio does: LAB-Bench, ScienceAgentBench, and BiomniBench each withhold a private or gated portion of their items for contamination control, and BixBench, BioAgentBench, and BiomniBench each depend on an LLM judge (Claude 3.5 Sonnet, GPT-5.1, and Gemini 3.1 Pro respectively) rather than deterministic scoring. RealBio is distinctive in combining fully open fixed items, a released deterministic scorer (`score.py`, CC-BY-4.0), objective exact-match scoring where the task admits it, and an explicit engine-free direct-LLM ablation. We claim this combination only for the specific benchmarks verified here, not as a universal first; several match RealBio on individual axes (e.g. LAB-Bench and BioAgentBench on cross-system breadth). **Systems not yet on the board.** The AI co-scientist class — Google's AI co-scientist, FutureHouse's Robin, and Edison Scientific's Kosmos — are capable LLM-agent systems that can attempt these tasks; as agents they would place on RealBio at their own capability level, and we make no claim that they cannot. We did not sweep them here for a practical reason only: they are closed products without a public API we could drive under the identical frozen-prompt protocol. RealBio is released precisely to remove that barrier — with the open fixed items and shared `score.py`, any team can run their own system (co-scientist systems included) and land directly on this leaderboard. We report the systems we could run under one identical protocol — eight frontier LLMs used directly, a Biomni agent scaffold, and BioMate — and invite the rest.

## 3. The RealBio benchmark

**Tasks — 5 RealBio-native + 3 cross-published DrugDev (all reported; none dropped or highlighted selectively).** The upper block is the RealBio-native agent-capability surface (n = 610); the lower block are three drug-development benchmarks (B2/B3/B4 of the companion **DrugDev** suite) cross-published here because both suites export to the same `score.py` — they are reported for cross-system continuity, not claimed as RealBio-native capability tasks.

| Task | What it tests | Ground-truth source | Suite |
|---|---|---|---|
| `cross_domain_routing` | plain-English request → correct pipeline/workflow | curated workflow catalog + acceptable-alternatives set | RealBio |
| `param_prefill` | fill a workflow's parameters from context | schema-validated expected values | RealBio |
| `protocol_thresholds` | set QC/protocol thresholds correctly | published protocol references (per-item) | RealBio |
| `autofix` | classify + repair a failed run | fixed failure categories | RealBio |
| `workflow_generation` | produce a runnable workflow for a stated goal | structural/valid-target check | RealBio |
| `boin` | BOIN dose-escalation decisions | Liu & Yuan, *JRSS-C* 2015 | DrugDev B4 |
| `pbpk` | PBPK exposure predictions | published clinical-pharmacology references | DrugDev B3 |
| `drug_discovery_e2e` | end-to-end design (docking) task | RCSB PDB structures, experimental Kd, published PK | DrugDev B2 |

Items are **original tasks** (not scraped from the systems' training corpora), each carrying a machine-checkable answer and, where relevant, an `acceptable_alts` set so a correct-but-differently-named answer receives credit. **RealBio-native total n = 610** (routing 200, param_prefill 170, protocol_thresholds 100, autofix 100, workflow_generation 40); the three cross-published DrugDev tasks add ~50 items (pbpk 15, boin 18 scorable of 20, dd 15).

**Scoring.** One committed `score.py`. For objective tasks the metric is exact/threshold match against published ground truth (no LLM judge). The scoring rule — including `acceptable_alts` credit — is fixed and applied identically to BioMate and every baseline; any asymmetry is a fairness bug, not a result.

**Five evaluation dimensions (Evaluation Framework v1).** Accuracy is one of five dimensions RealBio scores (`five_dimension_reporter.py`): **D1 Performance** (accuracy, CI, pass-rate — the leaderboard, §5.2); **D2 Stability** (cross-run consistency — consistency-rate, Cohen's κ, flip-rate over N repeats, `stability_runner.py`; design target ≥ 0.90); **D3 Time** (per-query latency, p50/p95); **D4 Cost** (input/output tokens per query, the model-agnostic cost proxy; a per-model price map gives $); and **D5 Hallucination** (grounded / hallucinated / unverifiable at important steps, via an LLM-judge `hallucination_detector.py` plus citation-veracity on `litqa2`). D3 and D4 are now reported per model in `leaderboard_5d.csv` (20 systems); **D2 and D5 are implemented but not yet swept per model across the roster** (a gated multi-run / judged pass), and are listed as future work in §6 rather than reported here. This frames the headline accuracy leaderboard explicitly as D1 of five, not the whole evaluation.

## 4. Evaluation protocol (fairness by construction)

Frozen 2026-08-05, **before** the full model roster was run, to prevent post-hoc metric/condition selection.

![Figure 1. RealBio study design: the same 660 items pass through a frozen per-task prompt to each system and are graded by one open objective scorer; the two headline conditions are LLM direct use (the real scenario) and BioMate.](figures/realbio/fig1_design.png)

**Two conditions:**

| Condition | Definition | Isolates |
|---|---|---|
| **C0 — model, direct use** | model + task instruction scoped to the real sources; **no candidate list** (the way an LLM is actually used) | the model's parametric knowledge |
| **C2 — full system** | the product with its curated/enriched DB + orchestration, no LLM in the loop | the *product* contribution |

The **C0 (LLM as actually used) vs C2 (a product with a curated catalog)** contrast is one disclosed product-vs-default comparison the benchmark supports; it is never presented as an RQ1 model-intelligence claim, and no single system is the benchmark's subject.

**On the C0 baseline-fairness objection.** A referee may object that C0 gives the LLMs no candidate list while BioMate (C2) queries its curated catalog, so the comparison is not model-vs-model. This is deliberate and disclosed. C0 is defined as the **deployment default** — the way practitioners actually call an LLM, with no injected catalog — because the paper's question is "the product versus the deployment default," not "catalog-versus-model." The latter question (a catalog-equipped-LLM condition) is technically constructible, and its prediction files exist in the released export, so any reader can build and score it; we **exclude it from the headline by design**, treating the catalog's sufficiency as a product result rather than a raw-capability comparison. We name this scoping choice explicitly so the leaderboard is read as a disclosed product-vs-default comparison, not a rigged model-vs-model one; consequently we do **not** add a catalog-equipped-LLM row to the results tables.

**Open framing decision — the catalog-equipped-LLM (LLM+harness) condition (authors' call).** Since the freeze, a catalog-equipped condition (`routing_harness`: each model given the RAG-fair candidate list) has been scored from the committed files for 17 systems, and it yields the benchmark's most striking cross-system regularity: an **inverse-scaling harness dividend** — bare→catalog routing lifts weak/small open models by **+0.58–0.71** (Qwen3.5-9B 0.120→0.815, Qwen2.5-7B 0.140→0.725, on-prem 9B 0.180→0.885) versus only **+0.35–0.40** for the frontier (Claude 0.615→0.980, Gemini 0.580→0.950), with **every system converging to ~0.80–0.98** regardless of bare ability — i.e. a 9B + catalog ≈ a frontier model + catalog. Two defensible framings, and this is an **authors' editorial decision, not a settled result**:
- **Option A (original scoping):** keep the headline strictly product-vs-deployment-default and relegate the catalog-equipped condition to the supplement, treating catalog-sufficiency as a product property. Cleanest anti-"rigged model-vs-model" stance.
- **Option B (promote):** present the bare-vs-catalog dividend as a first-class, disclosed **secondary** analysis (its own table + the inverse-scaling finding), because it is cross-system, reproducible from the released files, and scientifically interesting in its own right.
- **Recommendation (hybrid):** adopt B *as a labelled secondary analysis* while keeping A's product-vs-default framing as the headline — i.e. add a clearly-marked catalog-equipped table in §5.x and the inverse-scaling figure, explicitly not the headline comparison. This surfaces the dividend honestly without re-opening the "catalog-vs-model" question as the paper's thesis. Final inclusion is the authors' choice.

**Controls.** Frozen per-task prompt template identical across models (committed in `run_baseline.py`); low/zero temperature, with N=3 seeds and mean±SD where a model is non-deterministic; capped retries on transient API errors (a permanent failure is a scored miss, not a drop); models never see ground truth or `acceptable_alts`; one scorer for all.

## 5. Results

### 5.1 Overview

All results below come from the committed `score.py` on committed `predictions.jsonl`. The core cross-system view is the leaderboard in §5.2; §5.3 analyses where each system leads and where the newly-added tasks split by task type.

### 5.2 Leaderboard — LLMs as actually used vs BioMate (8 columns: 5 RealBio-native + 3 cross-published DrugDev; from committed `score.py`)

Each LLM is evaluated **the way it is actually used** — the model with its own knowledge and the task, no candidate list injected. n per cell: routing 200 · autofix 100 · param_prefill 170 · workflow_gen 40 · protocol 100 · pbpk 15 · boin 18 · dd 15. `gpt-5.3-chat-latest` is excluded (routing scored 0.000 — a failed run, not a valid measurement).

![Figure 2. Cross-domain routing: LLMs as actually used vs BioMate.](figures/realbio/fig2_leaderboard.png)

| Model | routing (direct use) | autofix | param_prefill (F1) | workflow_gen | protocol_QC | pbpk (2-fold) | boin (MTD-mg) | dd (Spearman) |
|---|---|---|---|---|---|---|---|---|
| **BioMate** (engine-free curated retrieval) | **0.965** [0.930, 0.983] | — | — | — | — | 0.200◊ | —★ | — |
| Claude Opus 5 | 0.615 | 0.870 | **0.757** | 0.500 | 0.330 | 0.133 | 0.444 | 0.700 |
| Gemini 3.1 Pro | 0.580 | **0.880** | 0.693 | 0.500 | **0.630** | 0.000 | 0.278 | 0.700 |
| GPT-5.6 | 0.530 | 0.860 | 0.671 | 0.500 | 0.460 | **0.200** | **0.500** | 0.700 |
| Kimi K3 | 0.450 | 0.770 | 0.628 | 0.450 | 0.360 | 0.000 | 0.167 | 0.700 |
| DeepSeek V4-pro | 0.415 | 0.800 | 0.621 | 0.500 | 0.420 | 0.067 | 0.167 | 0.667 |
| GLM-5.2 | 0.400 | 0.830 | 0.641 | 0.500 | 0.440 | 0.000 | 0.111 | 0.700 |
| GPT-5.6-luna | 0.355 | 0.830 | 0.624 | 0.500 | 0.340 | **0.200** | 0.389 | 0.700 |
| Qwen3.8-Max | 0.345 | 0.860 | 0.692 | 0.500 | 0.460 | 0.000 | 0.111 | 0.700 |
| Biomni (Stanford A1)¶ | 0.950 | 0.950 | 0.708 | 0.500 | 0.500 | 0.000 ¶¹ | 0.500 | 1.0 (n=4) ¶² |

*Metric definitions (three newly-added tasks).* **pbpk** = fraction of PK predictions within 2-fold of the published reference, scored over all 15 items; a non-parseable / no-final-number answer counts as a miss (Kimi and Qwen produced ~30k-token reasoning with no usable number, hence 0.00). **boin** = exact match of the recommended MTD dose in mg to `reference.true_MTD_mg`, over 18 scorable items (2 of 20 excluded: null true_MTD_mg). **dd** = mean Spearman rank correlation between the model's strongest-first ligand ranking and `ligand_rank_order`, over 15 items. Task means across the 8 LLMs: pbpk **0.075**, boin **0.271**, dd **0.696**.

*Reading (honest).* LLMs used directly are **near-useless at PBPK simulation** (mean 0.075 within-2-fold), **mediocre at BOIN dose-finding** (mean 0.271 exact-MTD), but **good at ligand ranking** (mean 0.696 Spearman) — a knowledge task rather than a simulation task. We report `dd` deliberately as a case where direct LLMs already do well: RealBio is **not rigged to only surface LLM failures**; it surfaces the tasks LLMs cannot do (simulation, deterministic dose-finding) *and* the ones they can (ranking from pharmacological knowledge).

◊ *BioMate's pbpk = 0.200* (3/15 within-2-fold) is a **genuine same-item** run of BioMate's pbpk workflow on the identical 15 RealBio compounds (committed `results/biomate_product/pbpk_benchmark_sameitem.jsonl`, graded by the same `score.py`; 95% CI [0.071, 0.452]). On these items BioMate **ties** GPT-5.6 and GPT-5.6-luna (both 0.200) and beats the LLM field mean (0.075), but does **not** lead. An earlier leaderboard figure of **pbpk = 100% (18/18)** was a *cross-harness artifact* — a different, easier disease-state (impaired/normal) ratio task on a different, favorable compound set — and is **withdrawn**; see §6 and `docs/20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`. ★ *BioMate's boin* was only ever measured **cross-harness** (a claimed 0.80 on a different item set) and has **not** been re-run same-item on the RealBio boin items, so it is shown as not-yet-reported ("—") rather than as a result; a same-item boin run is pending.

¶ *Biomni engine.* The 5 pilot tasks used Opus-5 (n = 40). The 3 computation tasks used **Claude Sonnet 4.5** (Biomni's default Claude tier), because Opus-5's API rejects Biomni's assistant-prefill agent loop (prefill was removed across Claude ≥ 4.6) and so cannot drive the code-executing tasks; byte-identical prompts and the same `score.py`. ¶¹ *Biomni pbpk = 0.000 (0/15) is a format artifact, not an inability* — the agent computes mechanistic PK values (clearance/AUC) that do not match the reference Cmax within 2-fold when reduced to a single number, the same underspecified prompt the LLMs faced. ¶² *Biomni dd = 1.0 on the 4 of 15 items that completed* (the other 11 dropped to API credit-throttling on the large-context task) — a small partial cell, not comparable to the LLMs' 0.696 (n = 15).

*Scope of BioMate's cells:* BioMate is reported only on the tasks with a committed **same-item** RealBio prediction file — routing (`results/biomate_dev/cross_domain_routing_c2ir.jsonl`) and pbpk (`results/biomate_product/pbpk_benchmark_sameitem.jsonl`, ◊). Its autofix, param-prefill, protocol-QC, workflow-generation, boin, and `dd` cells have **no committed same-item RealBio predictions** and are shown as not-yet-reported ("—") rather than zero; none is fabricated. (A convenience `leaderboard.csv` in the export lists BioMate param-prefill/protocol/pbpk/boin values carried over from *non-RealBio* harnesses; those are not same-item head-to-heads and are deliberately excluded from this table — `leaderboard.csv` needs regeneration to match.)

*Coverage note:* the sweep covers all 8 tasks (5 RealBio-native + the 3 cross-published DrugDev tasks `pbpk`/`boin`/`drug_discovery_e2e`); `litqa2` is a defined-but-unswept task not counted in the 8 and is a planned addition in a follow-up sweep.

*Models added since the 2026-08-05 freeze (post-freeze, disclosed as such).* The frozen headline sweep is the eight systems above. Since the freeze the committed board has grown to **17 systems** by adding open/small models from committed result files: **GLM-5.3-prime** (the latest GLM flagship), **Qwen 2.5-7B / 3.5-9B / 3.5-27B / 3.8-27B**, and the **on-prem 9B (base and gold-SFT)**. These are reported as post-freeze additions, not part of the pre-registered frozen comparison. Two honest observations: (i) **newer ≠ better** — GLM-5.3-prime does not uniformly beat GLM-5.2 (direct routing 0.375 vs 0.400; it is higher on protocol-QC), consistent with the plateau seen across model generations; (ii) the small open models are the backbone of the inverse-scaling harness dividend above. `DeepSeek V4-pro` (large) is distinguished from `DeepSeek V4.1-flash` (small); the flash variant, GLM-5.3-prime's DrugDev columns, and `gemma-4-31b` are **not yet swept** (gated) and are listed in §6.

### 5.3 Analysis

- **On curated-domain routing, one entrant's engine-free retrieval (BioMate, 0.965) sits far above the same frontier LLMs used directly** (0.345–0.615) — for example, holding the model fixed, GPT-5.6 routes at 0.530 [0.46, 0.60] directly versus 0.965 [0.93, 0.98] on the same n=200 items — delivered with no LLM in the loop. We report this spread descriptively; the interpretation of *why* a curated catalog is sufficient for reliable routing is developed in the companion systems paper, not here.
- **No single system dominates every task:** Gemini 3.1 leads protocol-QC (0.630) and ties autofix (0.880); Claude Opus 5 leads param-prefill (0.757); Biomni's agent scaffold leads autofix (0.950, n=40 pilot). `workflow_gen` is ~0.500 for almost everyone — a hard, discriminating task and a target for all systems.
- **The three newly-added tasks split cleanly by task type.** Direct LLMs are near-useless at PBPK simulation (mean 0.075 within-2-fold; two models scored 0.00 by emitting long reasoning with no parseable number) and only mediocre at BOIN dose-finding (mean 0.271 exact-MTD). But they are **good at ligand ranking** (mean 0.696 Spearman) — a pharmacological-knowledge task. This is deliberate counter-evidence to the objection that RealBio only measures things LLMs fail at: on `drug_discovery_e2e` the direct LLM does well, and we report it.

Figure 3 summarises the routing spread: BioMate's curated-retrieval routing sits far above the same frontier LLMs used directly. RealBio *measures* this spread; the companion systems paper *argues its cause*.

![Figure 3. Cross-domain routing: BioMate (engine-free) vs the same frontier LLMs used directly.](figures/realbio/fig3_ablation.png)

### 5.4 Failure-mode analysis — what the scores hide

A per-system failure-mode taxonomy over the committed predictions (Suppl. *Error-mode taxonomy*) decomposes each score into five modes — *hallucinated-selection*, *discrimination-error*, *verbose-no-answer*, *wrong-endpoint (under-specification)*, and *overthinking/wrong-scale* — and surfaces three findings the headline accuracies mask. First, direct-LLM routing errors are dominated by **hallucinated workflow names** (targets absent from any catalog: 37–116 of 200 across models), whereas the engine-free entrant's few misses are **discrimination errors** (a real catalog workflow, the wrong one; 8 of 200) — a categorical difference for a system that *executes* its selection, since a fabricated target is not runnable. Second, the low PBPK scores are substantially a **task under-specification artefact**: the stronger reasoners' modal miss is a valid PK value for the *wrong endpoint* (within 2-fold of AUC/t½ rather than the scored Cmax; e.g. 9 of 15 for Gemini 3.1 Pro), which motivates a dataset fix — the prompt should name the target endpoint — rather than a capability verdict; the committed numbers are left unchanged and the defect is flagged. Third, a **verbose-no-answer** mode — extended reasoning with no parseable answer — is negligible for closed frontier models but dominant for several open-weight models on both PBPK and BOIN (up to 15/15 and 16/20), a real output-discipline gap for deployment. Full per-task tables and same-prompt case sketches are in the supplement.

## 6. Limitations

- **The leaderboard in §5.2 covers all 8 tasks** (5 core + the newly-added `pbpk`/`boin`/`drug_discovery_e2e`); `litqa2` is a defined-but-unswept task not counted in the 8 and is a planned addition. BioMate is reported only where a committed **same-item** RealBio prediction exists (routing; pbpk same-item = 0.200, n = 15); all its other cells — autofix, param-prefill, protocol-QC, workflow-generation, **boin**, and `dd` — are shown as not-yet-reported rather than zero.
- Objective scoring covers the 8 tasks by design; open-ended scientific reasoning is out of scope (and is where LLM-judge benchmarks, with their caveats, still apply).
- **Self-grading conflict of interest — the paper's central caveat.** BioMate is one of the authors' own systems (full description in a **companion systems paper by the same authors** [11]), *and the open scorer (`score.py`) was also written by the authors* — so the system under test and the grader share an origin, and BioMate's RealBio numbers are **not** independent third-party validation. We take two concrete honesty measures rather than merely asserting neutrality. First, the items, ground truth, and scorer are public and independently re-runnable by anyone, which is the strongest available answer to self-grading (a mitigation, not an elimination of the conflict). Second, we **actively withdrew an over-favorable artifact**: an earlier BioMate headline of **pbpk = 100% (18/18 within-2-fold)** was a *cross-harness* result on a different, easier task and compound set; the genuine same-item run on the identical RealBio compounds scores **0.200 (3/15)**, and we report that instead (`docs/20260827_BIOMATE_PBPK_SAME_ITEM_RESULT.md`). The benchmark's contribution — open items, open ground truth, and one shared objective scorer — stands independent of any BioMate result.
- Per-item ground truth for `pbpk`/`boin`/`drug_discovery_e2e` derives from published references; any reference error is a data bug fixable in the open dataset.
- **Dimensions not yet swept per model (future work, not reported as results).** D2 Stability and D5 Hallucination are implemented (`stability_runner.py`, `hallucination_detector.py`) but not yet run per model across the roster — they require a gated multi-run / judged pass; we report D1/D3/D4 and list D2/D5 as pending rather than fabricate them.
- **Coverage still gated.** `DeepSeek V4.1-flash` (full suite), `GLM-5.3-prime`'s three DrugDev columns, and `gemma-4-31b` are not yet swept; a staged runbook exists and these are explicitly blank, not zero.
- **The catalog-equipped-LLM (LLM+harness) condition** is an open framing decision (§4): the inverse-scaling dividend is computed from committed files for 17 systems but its placement (supplement vs first-class secondary analysis) is deliberately left to the authors.

## 7. Data & code availability

The full benchmark — the dataset and per-item ground truth and references, the open scorer (`score.py`), the model manifest (`models.yaml`), the committed per-system predictions (`results/`), and the run/aggregation scripts — is packaged in `evaluation/datasets/public_export/` and released under **CC-BY-4.0**:

- **Code & scorer (CC-BY-4.0):** GitHub — `[REPO URL TBD — to be provided by the authors]`
- **Dataset & predictions (CC-BY-4.0):** Hugging Face — `realbio_benchmark`
- **Archival DOI:** `[DOI TBD — assigned on publication (Zenodo)]`

To place a new system on the leaderboard, run it on the fixed items, write predictions as JSONL, score with the shared `score.py`, and the result is directly comparable to the numbers above. Every number in this paper is reproducible by running `score.py` on the committed predictions.

## Competing interests
Y.Z. and A.D. are affiliated with BioMate AI, which develops the BioMate platform evaluated in this study; A.D. is additionally affiliated with BizBildr. The authors declare these competing financial interests.

## Author contributions
Y.Z. designed and implemented RealBio and its evaluation harness, ran the cross-system sweep, and drafted the manuscript. A.D. contributed to benchmark design and manuscript revision. **[Author contributions to be confirmed by the authors.]**

## Acknowledgements
We thank the BioMate AI team for infrastructure and testing support. **[Funding sources to be added by the authors.]**

---

## Supplement

### S1. Worked examples (one real item per task; item · published ground truth · a scored prediction)

Examples are shown *as scored* — including misses — not cherry-picked wins.

| Task | Item (input) | Ground truth | Example prediction | Scored |
|---|---|---|---|---|
| cross_domain_routing | "Run standard RNA-seq analysis on my paired-end FASTQ files from a mouse experiment" | `nf-core/rnaseq` | **BioMate:** `nf-core/rnaseq` | ✅ |
| autofix_benchmark | "hg19 genome specified but annotations require hg38 … ERROR LOG: …" | `genome_mismatch` | Claude Opus 5: `genome_mismatch` | ✅ |
| protocol_thresholds | "Protocol: 10x_genomics_flex_low_input · QC situation: …" | `PASS` | Claude Opus 5: `WARN` | ❌ (a real miss) |
| param_prefill | "RNA-seq differential expression on human lung adenocarcinoma samples" | `{genome: GRCh38}` | Claude Opus 5: `{}` (failed to infer the assembly) | ❌ (a real miss) |

### S2. Frozen prompt templates (verbatim, identical across all systems)

- **routing (direct use):** *"Bioinformatics workflows come primarily from three sources: Nextflow/nf-core, Galaxy, and Bioconductor. … Respond with ONLY the single canonical workflow name (e.g. 'nf-core/rnaseq') and nothing else. INPUT: {query}"*
- **autofix:** *"Classify this pipeline failure into exactly one fix CATEGORY. INPUT: {description}\nERROR LOG:\n{error_log}"*
- **protocol_thresholds:** *"Given the sequencing protocol and the QC situation, decide the correct action: PASS, FAIL, or WARN. INPUT: Protocol: {protocol}\nQC situation: {problem}"*
- **param_prefill:** *"Extract values for the specified parameters as a flat JSON object {name: value}. Include a parameter ONLY if its value is clearly stated in the request. Use canonical/standard values (e.g. official reference-genome assembly identifiers, not organism common names). Respond with JSON only. … Candidate parameters: {names}\nRequest: {user_query}"*
- **pbpk:** *"Predict the requested pharmacokinetic value. Respond with a single number only (no units)."*

The identical prompt across systems is the fairness control; any per-system prompt tuning would be a fairness bug, not a result.

### S3. Uncertainty
All scores are accompanied by their n (per cell) and a 95% Wilson interval from `score.py`. Headline example: BioMate routing 0.965 (n=200), 95% CI **[0.930, 0.983]**; GPT-5.6 direct-use routing 0.530 (n=200), 95% CI **[0.461, 0.598]**. Small-n cells (Biomni pilot n=40; workflow_gen n=40) carry wide intervals and are marked as such; no claim rests on a cell whose CI overlaps a competitor's unless stated.

### S4. Systems & versions
Exact live model slugs (from `models.yaml`, access-dated): `gpt-5.6`, `anthropic/claude-opus-5`, `google/gemini-3.1-pro-preview`, `moonshotai/kimi-k3`, `qwen/qwen3.8-max`, `deepseek/deepseek-v4-pro`, `z-ai/glm-5.2`; open models served via one OpenAI-compatible endpoint (OpenRouter) so the harness is identical across systems. BioMate: engine-free retrieval; platform build at the submission commit. Biomni: 0.0.8 `A1` agent (engine = Opus-5), n=40 pilot.

### S5. Failure analysis
`workflow_generation` sits at ≈0.50 for nearly every system, including BioMate — a discriminating task where no current system is strong. Manual inspection: the failures cluster on intents that map to a *composed* pipeline (multiple sub-workflows) rather than a single named category; a category-only answer under-specifies them. This is a target for all systems and is reported, not hidden.

---

## References

1. BixBench (FutureHouse, 2025). arXiv:2503.00096.
2. LAB-Bench (FutureHouse, 2024). arXiv:2407.10362.
3. ScienceAgentBench (2024). arXiv:2410.05080.
4. BioAgentBench (2026). arXiv:2601.21800.
5. BiomniBench (2026). bioRxiv DOI 10.64898/2026.05.12.724604.
6. Liu S, Yuan Y. Bayesian optimal interval designs for phase I clinical trials. *Journal of the Royal Statistical Society: Series C (Applied Statistics)* 2015;64(3):507–523. (BOIN ground truth for the `boin` task, §3.)
7. RCSB Protein Data Bank. Berman HM, et al. The Protein Data Bank. *Nucleic Acids Research* 2000;28(1):235–242. rcsb.org. (Structure ground truth for `drug_discovery_e2e`, §3.)
8. FDA Guidance for Industry — Pharmacokinetics in Patients with Impaired Renal Function and in Patients with Impaired Hepatic Function (clinical-pharmacology references used for the `pbpk` task ground truth, §3). Cited by source name; no per-item DOI is asserted.
9. Huang K, et al. Biomni: a general-purpose biomedical AI agent. *Science* 2025. DOI 10.1126/science.adz4351. (The `A1` agent scaffold evaluated as a baseline, §5.2, S4.)
10. The eight evaluated LLM slugs, versions, and access dates are listed in Supplement S4 and in the released `models.yaml` (`evaluation/datasets/public_export/`).
11. Zhang Y, Dike A, et al. BioMate: a curated, executable, governed catalog for trustworthy biomedical workflow automation. Companion systems paper by the same authors (in preparation). Describes the BioMate platform whose C2 results are reported here; cited so BioMate's system, its governance layer, and its validated pharmacology benchmarks are documented outside this benchmark paper.
