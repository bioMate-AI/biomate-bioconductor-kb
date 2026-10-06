# BioMate Manuscript & Publication Plan

> Publication strategy synthesized from `internal/marketing-research/internal_evidence_and_manuscripts.md`,
> the fresh on-prem results (`docs/20260912_onprem_llm/20261004_CLOSE_THE_GAP_ROUTING.md`,
> `docs/20260912_onprem_llm/20261004_REALBIO_LLM_VS_HARNESS.md`), and the external reference notes on
> Biomni (`reference/20261004_REF_biomni_science.md`) and the LongevityBench *Cell* paper
> (`reference/20261004_REF_longevity_benchmark_and_model.md`). Internal claims cite repo paths;
> external facts cite the links captured in the reference notes. Evidence strength is graded
> **Evidenced** / **Partial** / **Aspirational** as in the source notes. No citations are fabricated.

---

## 1. Inventory of current manuscripts and drafts

| Title (working) | Repo path | Target venue (if stated) | Status | Core claim | Evidence strength |
|---|---|---|---|---|---|
| **RealBio: an open, objectively-scored benchmark for real-world bioinformatics workflow automation** | `docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md` | NeurIPS D&B / Bioinformatics App Note / GigaScience | Manuscript-complete; 8 tasks (660 items); CC-BY-4.0 scorer | Open anti-self-grading cross-system benchmark; no single system dominates; BioMate routing 0.965 engine-free | **Evidenced** (committed `score.py` on committed predictions); self-grading COI disclosed |
| **C1 flagship systems paper** — "a curated, executable, governed catalog for trustworthy biomedical workflow automation" | `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` (text as Drive docx `C1_Flagship_…docx`) | Nature Methods form | "Structurally submission-ready"; 17 refs; Figs 1–5; ~6,861 words | Orchestrated agent + QC governance + curated catalog | **Evidenced** (BixBench Phylo-Verified-50 92.0% vs Biomni 88.7%; BiomniEval1 71.1% vs 66.9%); autofix/wf_gen/dd cells still "—" |
| **On-prem domain LLM — draft 1** "Building a Private, On-Premise Domain LLM…" | `docs/20260918_ONPREM_DOMAIN_LLM_MANUSCRIPT.md` | not finalized | Working manuscript; retriever has final numbers | Grounded SFT + paraphrase diversity (3,969→17,291) + contrastive retriever (recall@5 0.915) | **Partial** (retriever Evidenced; training/RL deferred to GPU) |
| **On-prem domain LLM — draft 2** "Grounded, Leakage-Controlled Fine-Tuning of an On-Premises Multimodal LLM…" | `docs/20260912_onprem_llm/MANUSCRIPT.md` | authors TBD | Living draft; round-2 joint training "built but not trained" (GPU-host failure) | Transfer-failure is the central result; format-matched joint training recovers gains; 27B on par with Qwen3.8-Max | **Partial** (central numbers incomplete) |
| **On-prem domain LLM — fresh analyses** (feed the above) | `docs/20260912_onprem_llm/20261004_REALBIO_LLM_VS_HARNESS.md`, `…/20261004_CLOSE_THE_GAP_ROUTING.md` | feeds drafts 1–2 | Fresh (2026-10-04) | "Harness ≫ LLM"; described-menu +20.5pp routing fix; task-split thesis; decomposition the one LLM-bound task | **Evidenced (fresh)**; full-corpus CPT decision row pending |
| **Bioconductor-KB Paper 1** "BioMate-KB: A Structure-Validated, Executable Workflow Knowledge Base…" | `docs/papers/bioconductor_kb_paper/20260601_PAPER1_NAR_DATABASE.md` | NAR Database Issue | Submission draft; top-100 bundle on GitHub CC-BY-4.0 | 15,641 validated steps; NAMESPACE ~96%; dual-agent κ=0.96; 90% step correctness | **Evidenced** (strongest real-data numbers in the inventory) |
| **Bioconductor-KB Paper 2** "Structure-Grounded LLM Extraction Suppresses Hallucination…" | `docs/papers/bioconductor_kb_paper/20260601_PAPER2_METHODS_AI.md` | Nature Methods / Bioinformatics / PLOS CB | Draft; 20-task benchmark across 7 domains | Function-citation accuracy 71.4%→88.2% (+16.8pp); wrong-package 14.3%→2.1%; κ→0.96 | **Evidenced** |
| **Autoimmune M1** "A reproducible pipeline for multi-omic endotyping of autoimmune disease" | `docs/20260727_M1_MULTIOMIC_ENDOTYPING_MANUSCRIPT.md` | Nature Methods (Analysis) | Framework; cover letter embedded | Reproducibility-by-construction pipeline | **Aspirational** ("full pipeline not yet run end-to-end on a real cohort") |
| **Autoimmune M2** "Reproducibility is the missing endotype…" | `docs/20260727_M2_ENDOTYPE_REPRODUCIBILITY_MANUSCRIPT.md` | Perspective | Framework | Reproducibility as endotype concept | **Aspirational** (no new clinical data) |
| **Autoimmune M3** isotype FcRn vs BAFF/APRIL predictive-biomarker framework (myasthenia gravis) | `docs/20260727_M3_ISOTYPE_GATE3_MANUSCRIPT.md` | Analysis | Framework | Predictive-biomarker framework | **Aspirational** ("framework and validation design, not a validated biomarker") |
| **Autoimmune M4** TCR–HLA–peptide antigen resolution (HLA-DP/DQ) | `docs/20260727_M4_ANTIGEN_RESOLUTION_MANUSCRIPT.md` | Methods | Framework | Antigen prioritisation | **Aspirational** (prioritisation, not experimentally validated antigens) |
| **Autoimmune M5** "Prognostic is not predictive: five gates…" | `docs/20260727_M5_FIVE_GATES_MANUSCRIPT.md` | Nature Medicine (Perspective) | Framework | Five-gates prognostic-vs-predictive framework | **Aspirational** (open Gate-3 test implementation) |
| **Cryo-EM benchmark paper** | `research_repos/cryo_em_benchmark_paper/` (plan: `docs/20260428_CRYO_PILOT_AND_MANUSCRIPT_PLAN.md`) | not finalized | ~70% ready; "strongest — REAL benchmark results" | Real cryo-EM benchmark (EMPIAR-10028 3.98 Å; P52 1.78 Å) | **Evidenced** (real runs); missing protocol-discrimination + CryoSPARC/RELION/Warp comparison |
| **CryoEnsemble paper** | `research_repos/cryoensemble_paper/` | not finalized | Flagged for reframe | Ensemble modeling proof-of-concept | **Partial/Aspirational** ("ALL results use a Gaussian perturbation model, NOT actual BioEmu/cryoDRGN") |
| **App note — anti-TNF IBD** "Calibrated, cross-cohort… infliximab response in IBD" | `docs/20260728_MANUSCRIPT_antitnf_ibd.md` | bioRxiv / clinical informatics | Draft; most rigorously caveated | Cross-cohort calibration on real GEO data; honest negatives | **Evidenced** (real GEO GSE12251/14580/16879; AUROC 0.833); deliberately not a novelty claim |
| **App note — preprocessing QC** "Verify, don't just clean…" over-correction QC gate | `docs/20260812_PREPROCESSING_QC_PAPER_SKELETON.md` | Applications Note | Skeleton; Gates 1–2 done on sim + real scIB pancreas | Automated cross-modality over-correction detection | **Partial** ("do NOT claim first"; RBET 2025 is prior art; delta = automation) |

A binary status tracker `docs/20260819_MANUSCRIPT_STATUS_FOR_TEAM.xlsx` was not parsed and may hold a
canonical cross-manuscript table ([internal_evidence_and_manuscripts.md §B](../../internal/marketing-research/internal_evidence_and_manuscripts.md)).

---

## 2. Recommended papers to prepare, with target venues and the single core claim each must defend

The inventory splits into two tiers that marketing and submission strategy must keep separate:
**methods/benchmark/KB papers with committed real numbers** (RealBio, C1, Bioconductor-KB ×2,
cryo-EM benchmark, anti-TNF, preprocessing-QC) and **translational framework papers** (M1–M5) that
are deliberately pre-validation. The four recommended priorities below are drawn from the first tier
plus the fresh on-prem result.

### 2.1 Paper A — RealBio / flagship SYSTEM paper

**Target venue:** Nature Methods form for the flagship system paper (C1), with the companion RealBio
benchmark at NeurIPS Datasets & Benchmarks / Bioinformatics / GigaScience.
**Single core claim it must defend:** *A curated, executable, governed workflow catalog with an
orchestration harness and a QC auto-loop produces trustworthy, reproducible biomedical workflow
automation that general LLMs and code-sandbox agents do not — measured by production execution
grading, not Q&A.*
**Structure.** Model the arc on Biomni's **three-tier evidence ladder** — established benchmarks →
novel held-out tasks → real-world case studies, each with explicit baselines and ablations
([reference/20261004_REF_biomni_science.md](../../reference/20261004_REF_biomni_science.md); Biomni,
*Science* 2025, [10.1126/science.adz4351](https://www.science.org/doi/10.1126/science.adz4351)) —
and **lead with the environment (catalog + tools + QC loop) before the agent**, as Biomni sells E1
before A1. The decisive differentiation from Biomni is that Biomni's real-world execution is
largely **Python-in-sandbox with full system privileges**, whereas BioMate's evaluation is
**production execution grading** — terminal success plus S3 output-content checks on real Nextflow/
nf-core pipelines on AWS Batch (live run `fb3440ec-…`, `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md`
§3c) — a harder, more real evaluation than Q&A-heavy benchmarks. Baselines must include a bare base
LLM and a generic coding agent, mirroring Biomni's persuasive +402% / +43% framing.

### 2.2 Paper B — harness-vs-LLM / task-split paper
**Draft:** `docs/20261004_PAPER_B_HARNESS_VS_LLM_DRAFT.md` (2026-10-04) — abstract, task-split framework, KB-dividend unified figure, bioc 4-arm, decomposition open-problem.

**Target venue:** a benchmarking/ML-for-science venue (NeurIPS D&B or a bioinformatics methods
journal), positioned as the analysis companion to RealBio.
**Single core claim it must defend:** *On a production bioinformatics system, the retrieval/
extraction harness — not the LLM — carries almost all end-to-end performance; the one capability that
is genuinely LLM-bound is multi-task decomposition / dependency-graph orchestration.*
**Evidence spine (fresh, Evidenced).** The harness lifts routing from base 9B **0.18 → 0.815**
(+63pp) and frontier Opus **0.615 → 0.960** (+35pp); bounded SFT gives **no end-to-end advantage over
base** (routing 0.805 vs 0.815) (`docs/20260912_onprem_llm/20261004_REALBIO_LLM_VS_HARNESS.md`). The
routing gap is a **harness-context artifact**: describing candidate workflows (not just bare names)
lifts base 9B routing **0.68 → 0.885** (+20.5pp), to **0.915** at a widened description window, and
to **0.920** on paraphrased queries — model-invariant and semantic, not lexical
(`docs/20260912_onprem_llm/20261004_CLOSE_THE_GAP_ROUTING.md`). The **open research hook** is
multi-task **decomposition**: the model must reason about sub-task dependencies (parallel vs
sequential vs mixed) — the one place where model training, not harness engineering, is the
lever, and where even frontier is far from solved (same doc). *(A preliminary small-vs-frontier
signal exists but is a **coarse 4-class binning artifact** and is deliberately NOT cited as a result
here; a proper node/edge-F1 dependency-graph metric is pending before any figure is published — see §3.2.)* This "benchmark as a *development
target*, not a scoreboard" framing is exactly CLAUDE.md's benchmark-driven-development philosophy and
has top-venue precedent in the LongevityBench *Cell* paper ([reference/20261004_REF_longevity_benchmark_and_model.md](../../reference/20261004_REF_longevity_benchmark_and_model.md)).

### 2.3 Paper C — Bioconductor-KB (strongest data)

**Target venue:** NAR Database Issue (Paper 1); Nature Methods / Bioinformatics / PLOS CB (Paper 2).
**Single core claim each must defend:** Paper 1 — *A structure-validated, executable workflow
knowledge base of 15,641 steps from ~1,970 Bioconductor packages, with NAMESPACE validation ~96% and
dual-agent agreement κ=0.96, is a reusable community resource* (`docs/papers/bioconductor_kb_paper/20260601_PAPER1_NAR_DATABASE.md`).
Paper 2 — *Structure-grounded LLM extraction suppresses hallucination*, improving function-citation
accuracy 71.4%→88.2% and cutting wrong-package errors 14.3%→2.1% (`…/20260601_PAPER2_METHODS_AI.md`).
This is the inventory's strongest committed real data and should anchor the Phase-A credibility push.

### 2.4 Paper D — on-prem domain LLM, reframed as cost/compliance

**Target venue:** a systems/ML-for-science or infrastructure venue; consolidate the three overlapping
drafts first (§4).
**Single core claim it must defend:** *An on-premise domain LLM is a cost and compliance enabler, not
a capability win — bounded domain-adaptation does not move the end-to-end system bar, and the correct
lever is the best base the hardware allows plus the harness.* This is the honest reframe the fresh
results force (`docs/20260912_onprem_llm/20261004_REALBIO_LLM_VS_HARNESS.md`). External validation
that **compact domain LLMs can match frontier models** comes from the LongevityBench *Cell* cover
study: a family of 5 compact Longevity-LLMs (0.6B–9B, built on Liquid AI LFM2 and Alibaba Qwen3/
Qwen3.5 — the same base family as BioMate's L-Qwen3.5-9B) **matched or exceeded all 16 frontier
systems evaluated**, with L-Qwen3.5-9B the highest-scoring of 26 systems and 0.868 vs 0.685
concordance on DNA-methylation age prediction ([reference/20261004_REF_longevity_benchmark_and_model.md](../../reference/20261004_REF_longevity_benchmark_and_model.md); Cell 189(19):5980–5994.e8, [publisher](https://www.cell.com/cell/fulltext/S0092-8674(26)00999-2)).
Cite it as precedent that *curated domain training + domain optimization matter more than raw size*,
and to justify the small-model / on-prem positioning — while being explicit that BioMate's own result
shows the *system/harness*, not the fine-tune, is what moves the bar.

---

## 3. Gaps and concrete next work, per recommended paper

### 3.1 Paper A (RealBio / flagship)

**Gaps.** (a) BioMate is the authors' own system — "not independent third-party validation" (paper
§6); the C0 condition gives direct LLMs no candidate list while BioMate uses its catalog, and an
earlier pbpk "100%" headline was withdrawn as a cross-harness artifact (`docs/20260817_REALBIO_BENCHMARK_PAPER_DRAFT.md`
§4/§6; `docs/20260822_FLAGSHIP_REALBIO_STATUS_AND_PLAN.md` §2). (b) Missing baselines directly against
Biomni across the full task surface (autofix/wf_gen/dd cells are "—"). (c) No wet-lab validation or
user study. (d) No committed artifact proving the QC auto-loop gate fired and auto-remediated on a
live run (`internal_evidence_and_manuscripts.md` §A1/§Gaps).
**Next work.** Add an **independent-grading track** — a non-self grader (held-out human or a
third-party scorer) on the execution-grading metric, decoupling the scorer from the system under
test. Run **Biomni as an explicit baseline** on the same tasks (a bare base LLM and a generic coding
agent as the two reference points). Ship a **QC-loop on/off ablation** and a **rule+LLM vs LLM-only
extraction ablation** so reviewers see *why* it wins. Capture and commit a **live QC-gate-fires-and-
remediates run** (log + output diff) as the Tier-3 case study. Terminate the arc on a concrete,
independently checkable biological output, mirroring the LongevityBench KDM1A-style
enrichment-plus-one-validated-hit closure.

### 3.2 Paper B (harness-vs-LLM / task-split)

**Gaps.** (a) Results are measured on one catalog and one query distribution; absolute magnitudes may
differ on a new catalog/user distribution (the two overfitting mechanisms — phrasing echo and
hand-tuned-workflow concentration — are empirically ruled out, but distribution-shift is not). (b) The
decomposition signal is a **coarse 4-class binning artifact** — the 0.40/0.60 figure must NOT be
published as a capability result; it needs a proper **node/edge-F1 dependency-graph metric** on a
larger, held-out decomposition test set plus an error taxonomy of dependency-graph mis-wirings
before any number is cited. (c) Reproducibility: the served-model + scorer pipeline
must be packaged for independent replay.
**CPT decision row — ANSWERED (2026-10-06, `docs/20260912_onprem_llm/20261006_LLM_HARNESS_DOMAINPRO_EVAL.md`).**
The concept-CPT+SFT "domainpro" was run base-vs-domainpro through the RealBio LLM+harness: knowledge lifts
(**litqa2 +6.0pp, coverage +21pp**) but the harness-assisted tasks **regress** (**routing −16pp, McNemar
p=7.7e-6; param_prefill −6pp F1**) — the SFT traded format/instruction discipline for knowledge (238 vs 9
output tokens on routing). So domain CPT is **not a free end-to-end scaling lever**: it helps the
knowledge-bound slice and hurts the LLM-selection/extraction heads, confirming the task-split thesis. Caveat:
the described-menu routing is an *LLM-menu-pick* instrument; the production dense-cosine retriever (model-
invariant) was not exercised and is likely unaffected. The paper reports this honestly (knowledge↑/harness↓
tradeoff) rather than a clean "CPT wins." (The companion knowledge-MCQA proxy — `20261006_FULLER_CPT_EVAL_RESULTS.md`
— shows +5.4pp raw / **+3.8pp dedup-controlled**, peaking at ~800 CPT steps; cite the dedup figure externally.)
**Next work.** Isolate the production dense-retriever routing path (base vs domainpro downstream only,
expected ≈0 Δ) to separate the retriever from the LLM-selection head; re-mix the SFT with terseness/format
discipline and re-run the harness; rebuild domainpro on the CPT-800 peak. Build a **held-out decomposition benchmark** (beyond the 9,717 training
instances in `train_task_decomposition`) with explicit parallel/sequential/mixed dependency labels,
and report **structure accuracy with coverage held at 1.0** to isolate dependency reasoning. Publish
the **described-menu prompt + scorer + served-base checkpoint** for replay.

### 3.3 Paper C (Bioconductor-KB)

**Gaps.** Already the strongest data; principal gaps are (a) end-to-end *executable* verification of a
sampled subset of the 15,641 steps beyond structural validation, and (b) data+code availability /
DOI. **Next work.** Publish the full KB (not just the top-100 bundle) under CC-BY-4.0 with a minted
DOI; add an **executable-smoke-test** of a stratified sample of steps on real inputs to upgrade
"90% step correctness" from structural to runtime evidence; report inter-annotator κ provenance.

### 3.4 Paper D (on-prem, cost/compliance reframe)

**Gaps.** (a) "27B on par with Qwen3.8-Max" and round-2 joint training are incomplete (GPU-host
failure); a prior zero-delta was an eval artifact (adapter no-op) caught by a logit probe
(`docs/20260912_onprem_llm/MANUSCRIPT.md` §5/§7). (b) Three overlapping drafts disagree on catalog
size (4,017 vs 4,200). (c) Contrastive-retriever gains differ sharply between random split (recall@5
0.915, leaks) and honest family-holdout (0.694) — only the holdout number is defensible.
**Next work.** Complete the **full-corpus CPT + SFT run** and add the LLM+harness catalog score as
the decision row; consolidate the three drafts into one manuscript with a single reconciled catalog
count; report **only the family-holdout retriever numbers** in the headline with the random-split
number explicitly labeled as leakage-inflated; frame the entire paper as cost/compliance with the
LongevityBench *Cell* result as the external "small-can-match-frontier" precedent.

### 3.5 Translational framework papers (M1–M5)

**Gaps.** All five are frameworks/perspectives with **no real-cohort end-to-end validation**, and
author lists are placeholders (`internal_evidence_and_manuscripts.md` §B). **Next work.** Hold M1/M3/
M4 (the Analysis/Methods papers that imply results) until at least one is run end-to-end on a real
cohort; M2/M5 (Perspectives) can proceed as explicitly non-empirical. Marketing must not present any
M-series claim as a validated BioMate result.

---

## 4. Cross-cutting gaps to close before any submission or external use

**Catalog size — RECONCILED 2026-10-04.** Ground truth from the catalog DB: **4,209 workflows across ~36
curated domains (42 raw tags) / 12,312 tools**, with a **validated subset of 1,092 workflows** (clean
real-execution evidence). The prior 2,455/4,017/4,200 figures were a stale count plus two snapshots; see
[`../20261004_CATALOG_COUNT_RECONCILIATION.md`](../20261004_CATALOG_COUNT_RECONCILIATION.md). Every paper
must cite 4,209 (breadth) and 1,092 (validated) separately. CLAUDE.md is corrected; the on-prem drafts
(4,017/4,200) and the MCP live-count string still need updating to match.

**Prove a QC auto-loop gate fired live — DONE 2026-10-04.** Live AWS Batch run `d0ff684b` tripped the
ADMET **GOLD hERG gate at `herg_ic50=0.012 µM`** (+ DILI high); the safe-compound control run `46953d98`
had empty gates, proving the gate discriminates. Captured in `docs/20261004_AUTOLOOP_LIVE_PROOF.md` with
the run-record `qc_gates`, raw S3 metrics, and the deterministic remediation diff (`logp_max 5.0→≤4.0,
mw 500→400`). Caveat for Paper A: the remediation is **reactive/advisory** (suggestion + SSE param diff),
not an autonomous closed-loop re-run — present it as a governed gate + recommended remediation. The live
SSE param-diff capture (vs the code-deterministic reconstruction) is the one remaining nicety.

**Independent (non-self) grading.** The flagship and RealBio depend on BioMate grading itself. A
non-self grading track — human-verified held-out grading or a third-party scorer on the execution-
grading metric — is required to answer the self-grading COI that every reviewer and every external
benchmark claim will raise.

**Consolidate the three on-prem drafts** into one manuscript with reconciled numbers, honest
family-holdout retriever results, and the completed full-corpus CPT decision row, before that arc is
submitted anywhere.

---

## 5. Paper F (NEW, SEPARATE) — heterogeneous-source → Nextflow conversion & execution-graded benchmark

**Plan:** `docs/20261005_PAPER_F_CODE_CONVERSION_PLAN.md`. **Status:** forward-looking (benchmark built +
grader validated; converters + local-9B eval + SFT pending). **Core claim:** one capability — *implicit-DAG
recovery* — turns Snakemake/WDL/CWL/Galaxy/notebooks/Python-R scripts into reproducible, QC-gated Nextflow
pipelines via a stub-run verify-fix loop, measured by an **execution** grader (parse→stub-run→run), not
similarity. **Venue:** Bioinformatics / GigaScience or a benchmark track; decide after the local-9B result.

**RULE (per user, 2026-10-05):** the WDL/CWL/notebook/script-conversion & implicit-DAG-recovery work and its
benchmark (`evaluation/datasets/nextflow_coding/`) are **Paper F ONLY** — do **not** fold them into A–E
(RealBio, Bioc-KB ×2, Paper B, Paper D, Paper E). Note: Paper B/D's "task/request decomposition"
(orchestration planning over existing workflows) is a *distinct* topic and stays in those papers.
