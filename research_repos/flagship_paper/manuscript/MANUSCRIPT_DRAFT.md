# An Orchestrated Biological Agent System with Evidence-Graded Quality-Control Governance, Evaluated Against Frontier Baselines on Public Bioinformatics Benchmarks

**Status:** Draft — rebuilt 2026-06-29 as a systems paper (supersedes the 2026-05-27 auto-loop-convergence draft)
**Target venue:** Nature Methods (Article) — primary; Nature Communications — secondary
**Companion paper:** *BioMate-Cryo* (Zhang & Zhang, manuscript in preparation)

---

## Authors

Yaoyun Zhang¹\*, Yuhan Zhang²\* *(placeholder — confirm with corresponding author)*

¹ BioMate AI
² Department of Structural Biology, St. Jude Children's Research Hospital, Memphis, TN, USA
\*Equal contribution

---

## Abstract

Autonomous agents are increasingly used to drive end-to-end biomedical computation, but two requirements have been under-served: governing the hundreds of threshold-dependent quality-control (QC) decisions an agent makes per run with an auditable, evidence-graded rationale, and evaluating agent competence honestly against the published frontier rather than on a single inflated score. We present BioMate, a biological agent system that interprets a natural-language request, routes it across 2,455 Nextflow workflows spanning 34 domains, extracts parameters, recovers missing prerequisites, executes the workflow on AWS Batch, and governs every QC decision through a single architecture in which each of 57 gates across 25 domains is annotated GOLD (citation-anchored consensus), SILVER (method-specific convention), or BRONZE (operational heuristic), with a portable JSONL audit trail aligned to 21 CFR Part 11. On the open-answer BixBench agentic benchmark — where the agent must *execute* the analysis rather than select a multiple-choice option — BioMate's execution path scores ≈48% (n = 50), exceeding the published open-answer state of the art (K-Dense Analyst 29.2%) and the latest frontier models (GPT-5 22.9%, Gemini 2.5 Pro 18.3%); we report this as **SOTA-competitive pending a full-benchmark confirmation run**, because our measurement is on the 50-question Verified subset rather than the full 296-question set. On BiomniEval1, BioMate scores 71.3% (n = 223), above the fine-tuned Biomni-R0-32B-Preview baseline (≈65%). Governance is deployed at scale: a 659-workflow Bioconductor QC harness (658/658 dynamic checks passing; 4/4 round-trip and 7/7 audit-trail unit tests passing) and 20/20 protocol-threshold gates verified end-to-end on live audit-logged runs (each scored 1.0). Protocol-aware profiles eliminated 100% of false-rejections of biology-valid marginal samples observed under default thresholds (HTS, LNP, cryo-EM), and the orchestrated pipeline reconstructs *E. coli* β-galactosidase (EMPIAR-10028) to FSC 0.143 = 1.78 Å as a methods validation. Autonomous closed-loop parameter remediation is implemented but **advisory by default**, pending validation of an efficient parameter search. BioMate shows that evidence-graded governance and honest, frontier-referenced evaluation can be unified in one regulatory-traceable agent.

---

## 1. Introduction

### 1.1 Two under-served requirements for biological agent systems

Computational biology has acquired capable autonomous agents faster than it has acquired the means to govern or evaluate them. A modern agent must interpret a heterogeneous natural-language request, select the correct computational tool from thousands, extract structured parameters from prose, satisfy upstream data prerequisites, execute a workflow, and interpret the output with appropriate caveats — and at every stage it applies quantitative QC thresholds that decide which compounds proceed, which model parameters are accepted, and ultimately which assertions reach a regulatory filing. These thresholds are not detail; they are decisive.

Two requirements follow, and the literature has under-served both. The first is **governance**: across workflow systems (Nextflow, Snakemake, KNIME, Galaxy) and orchestration platforms (Nextflow Tower, AWS HealthOmics, Terra), the layer that *evaluates* whether a stage's output is fit for the next stage has been left almost entirely to convention — threshold values buried in process scripts, copied between projects, or hard-coded into vendor tools without citation. When a threshold is exceeded, the dominant pattern is to silently filter the failing item and continue. The second is **honest evaluation**: agent capability is too often reported as a single, favourable end-to-end number, when the meaningful question is how the system performs against the *current published frontier* on a public benchmark, measured under the same protocol the frontier was measured under. This paper argues that both requirements are architectural rather than domain-specific, that a single system can satisfy both, and that doing so honestly produces results that are strong without being inflated.

### 1.2 Current automated tools across the industry perform silent filtering

The silent-filter pattern recurs across the domains we have audited.

**Cryo-EM.** Single-particle platforms such as CryoSPARC Live¹ and Warp² apply per-exposure threshold exclusion during on-the-fly collection: micrographs failing drift or contrast-transfer-function (CTF) criteria are automatically marked rejected and excluded. The pipeline does not halt; the investigator is not told what failed; the only record is a log file. A companion benchmark on detergent-solubilised membrane proteins (Zhang & Zhang, in preparation) shows that, under the default purified-protein drift threshold (≤50 Å), exposures whose motion statistics fall in the membrane-protein-typical 58–74 Å range are silently discarded.

**ADMET prediction.** Commercial and open-source tools (admetSAR, ADMETlab, SwissADME³) issue compound-level pass/fail flags against thresholds drawn from a heterogeneous literature: Redfern 2003 / Bowes 2012 for the 10 µM hERG safety margin⁴, Lipinski's rule of five for absorption⁵, the Lammert/Andrade 2010 cumulative-dose rule for DILI⁶. The tool reports a binary classification; it does not report which rule was used, whether it is verbatim from the cited paper or a downstream paraphrase, or what structural change would shift the prediction.

**High-throughput screening (HTS).** Plate-level QC — Z′ scores, edge effects, signal-to-background, replicate variance — is computed by every HTS suite. When a plate's Z′ falls below the conventional cutoff of 0.5⁷, the plate is flagged or excluded, but the choice is left to the operator with no record. The 0.5 cutoff traces to the Zhang/Chung/Oldenburg paper but is routinely misapplied to assays for which the authors explicitly cautioned against it.

**Physiologically based pharmacokinetic (PBPK) modelling.** Mass-balance recovery, AUC fold-error, and Tmax-window adequacy are standard acceptance checks⁸. Our internal audit found that the most widely cited values — for example the "±5% mass balance" tolerance attributed to the EMA 2019 PBPK guideline — are *not in the cited document verbatim*; they are operational conventions hardened into orthodoxy by citation drift.

What unifies these examples is a shared architectural choice: filtering is automatic and non-interactive, the evidence behind each threshold is opaque, and there is no machine-readable audit trail. This is appropriate for high-throughput, well-standardised samples handled by expert operators. It is systematically inappropriate for novel modalities, cross-team reproducibility, and any regulatory context in which the threshold itself must be defensible.

### 1.3 Three unaddressed governance gaps

**Gap 1 — Protocol blindness.** Every existing automated QC tool applies a single threshold regardless of sample or model context. The drift acceptance for purified proteins is wrong for membrane proteins; the Z′ cutoff for biochemical assays is wrong for phenotypic screens; the AUC fold-error tolerance for small molecules is wrong for biologics. A universal cutoff applied to a context it was not designed for generates false-positive rejections — valid data discarded because the threshold is mismatched to the biology.

**Gap 2 — No actionable diagnostics at gate failure.** Existing tools report a metric value at failure. None explains *why* the value is bad or what to do about it. An investigator seeing "CTF fit quality 0.61 (threshold 0.70)" or "hERG IC50 1.4 µM (threshold 10 µM)" receives no guidance on which parameter to adjust; remediation is left to tacit expertise concentrated in a small number of practitioners.

**Gap 3 — No evidence provenance.** Threshold values in production tools are either user-defined (arbitrary) or tool defaults with no citation. There is no way to determine whether a threshold reflects published consensus, an instrument or regulatory specification, or developer judgment. This blocks audit-trailed reproducibility and is incompatible with emerging regulatory requirements for AI-assisted submissions (FDA 2024 draft guidance on AI/ML-based software⁹, EMA 2024 reflection paper on AI in the medicinal product lifecycle¹⁰).

These gaps are reinforcing: protocol blindness produces false rejections that look like noise; without diagnostics the noise is unrecoverable; without provenance even a correct rejection cannot be defended at audit.

### 1.4 BioMate's contribution: an orchestrated agent with evidence-graded governance

We present BioMate, a biological agent system whose contribution is the **system-building approach** rather than any single predictive model. BioMate interprets a natural-language request, routes it across 2,455 Nextflow workflows spanning 34 domains, extracts the required parameters from the prose, recovers missing upstream prerequisites, executes the selected workflow on AWS Batch, governs every QC decision through an evidence-graded gate layer, and records a portable audit trail. Three properties distinguish it:

**(i) Interactive evidence-graded QC governance.** A single in-process hook (`qc_trace_monitor`) intercepts the structured output of every workflow step and routes its metrics through a domain-specific gate evaluator. When a threshold is exceeded the pipeline halts and the failing metric is surfaced alongside the threshold, the citation behind it, and the evidence grade of that citation: **GOLD** (verbatim in a peer-reviewed paper or regulatory document; cannot be silently overridden), **SILVER** (community convention attributed to a source; override requires a logged justification), or **BRONZE** (operational heuristic with no formal citation; explicitly disclaimed in the tooltip). The production catalogue contains 57 gates across 25 domains (26 GOLD, 26 SILVER, 5 BRONZE; recomputed from `backend/config/qc_evidence.yaml`).

**(ii) Advisory closed-loop remediation.** For five domains (ADMET, CYP-DDI, NCA-PK, docking, PBPK) the gate signal also feeds a rule-based engine that *proposes* a parameter change. In production this engine is **advisory by default** — it emits gate-aware remediation suggestions but does not autonomously re-run the workflow (`autoloop_bridge.py`). We discuss the engineering of an efficient autonomous variant as future work (§4); the present paper makes no autonomous-convergence performance claim.

**(iii) Portable JSONL audit trail.** Every gate evaluation and override is appended to a per-run JSONL stream carrying timestamp, run UUID, gate identifier, metric value, threshold, evidence grade, citation DOI, override justification, and approver identity — designed against 21 CFR Part 11 and aligned to the FDA 2024 AI/ML SaMD draft guidance.

The contribution of the present paper is to (a) demonstrate that this governance architecture operates at scale across structurally different domains, and (b) evaluate the orchestration system honestly against the *current published frontier* on two public benchmarks, where it matches or exceeds the state of the art under the same protocol. In the remainder we describe the architecture (§2), report the evaluation (§3), and discuss boundaries and limitations (§4).

---

## 2. Methods

### 2.1 System architecture

BioMate's orchestration and QC layers form a pipeline with cleanly separated stages, designed so that adding a new workflow or gate touches only configuration and an evaluator, never the engine, the event bus, or the frontend.

**Routing and parameter extraction.** A natural-language request is embedded and matched against an index of 2,455 Nextflow workflows; the top candidate is selected, required parameters are extracted from the prose with a hybrid rule-plus-LLM layer, and missing prerequisites (reference genomes, indices, upstream artefacts) are recovered before submission.

**Execution.** Selected workflows are implemented in Nextflow DSL2 and executed on AWS Batch with per-process containerised images. Each terminal process emits a structured JSON artefact (`qc.json`, `toxicity_report.json`, `pk_summary.json`, …) into the run's S3 output prefix, carrying raw metric values without itself deciding pass/fail.

**Gate evaluation.** `qc_trace_monitor.py` observes process completion, parses output into a domain-typed `qc_metrics` dictionary, and calls two fail-open emitters in parallel. `autoloop_bridge.evaluate_and_emit` drives the five remediation-wired domains via per-domain `qc_evaluator.py`; `qc_gate_emit.emit_gate_only_event` drives the twenty gate-only domains via `qc_gate_reader.py`. Both produce SSE events of the same type (`autoloop_gate_results`) carrying the failed-gate list, metric, threshold, active profile, and an `evidence` payload (reference, DOI, provenance grade, `paper_supports` text).

**Frontend and audit.** `auto-loop-panel.tsx` renders a gate table; each gate label is wrapped in `<QCEvidenceTooltip>`, displaying a coloured provenance badge (GOLD/SILVER/BRONZE), the cited reference and DOI, and both `rule_text` (what BioMate enforces) and `paper_supports` (what the source states), making any gap between them visible. Every gate evaluation is appended identically to the JSONL audit stream.

The evidence YAML is the single source of truth — a developer cannot add a production gate without writing an evidence record, nor grade it GOLD without quoting the source verbatim — and the architecture is parallel-session safe (additive YAML plus net-new evaluator modules, never edits to the shared monitor).

### 2.2 Evidence-graded gate catalog

`qc_evidence.yaml` is keyed by `(domain, gate_name)`; each entry carries `paper_ref`, `paper_doi`, `provenance`, `paper_supports`, `rule_text`, and `finding`. The grade definitions:

- **GOLD.** The threshold is stated verbatim in the cited source or trivially derived from it. Example: the FDA 2018 PBPK guidance states the two-fold AUC acceptance criterion, so `pbpk_auc_fold_error` (`|log2(pred/obs)| ≤ 1`) is GOLD.
- **SILVER.** The source supports the gate concept but not the exact threshold. Example: the EMA 2019 PBPK guideline requires mass-balance verification, but the ±5% tolerance is an operational convention.
- **BRONZE.** The threshold is a heuristic with no peer-reviewed anchor; the tooltip says so. Example: `docking_binding_score` cites Trott & Olson 2010, which introduces AutoDock Vina but prescribes no binding-score cutoff; the −7 kcal/mol "hit" threshold is a community heuristic.

A worked example: the ADMET evaluator parses `toxicity_report.json`, extracts `herg_ic50_uM`, compares it to the active profile's 10 µM `admet_standard` threshold, and on failure emits an event with the evidence payload from `admet.admet_herg_ic50` (Redfern 2003, DOI 10.1016/S0008-6363(02)00846-5, GOLD; cross-confirmed by Bowes 2012, DOI 10.1038/nrd3845).

### 2.3 Advisory remediation engine

For the five wired domains, gate failure invokes a rule-based remediation engine (`knowledge_base.py` → `param_tuner.py` → `enriched_tuner.py`) that maps each failed gate to a parameter delta with a stated mechanistic rationale (for ADMET hERG failure, "tighten the upstream logP filter"; for NCA-PK AUC-extrapolation failure, "extend `last_sampling_time_h`"). In production the engine runs **advisory-only**: it emits the proposed change and its evidence payload as an `autoloop_update` SSE event rendered as a remediation card (was→now parameter diff with the citation carried through), and does **not** autonomously re-execute the workflow (`autoloop_bridge.py`). Whether to apply a suggestion is an operator decision recorded in the audit trail. An autonomous closed-loop variant exists in the offline benchmark harness but is disabled by default pending validation of an efficient parameter search (§4); we therefore report no autonomous-convergence rate in this paper.

### 2.4 Evaluation design

We evaluate BioMate along two axes: (a) **public agentic benchmarks** measured under the benchmark's own published protocol, for direct comparison to the frontier; and (b) **governance at scale and validation experiments** measuring the QC layer's coverage and behaviour.

**Public benchmarks.** *BixBench*¹¹ is an open-answer agentic benchmark: the agent receives a capsule's raw data files and must perform the analysis to answer each question (the pre-executed reference notebook is the held-out answer key, not provided to the agent). We run BioMate in execution mode (`biomate_exec`): capsule data are uploaded to a BioMate session, each question is posed through the chat-stream interface, and BioMate's `run_code` tool computes the answer, which is then graded. *BiomniEval1*¹² is a biomedical-reasoning benchmark of 223 tasks across five subtasks (patient-gene, rare-disease, GWAS-causal, GWAS-variant, screen-gene). Both are scored with the benchmark's own answer keys.

**Governance and validation.** *Governance-at-scale* counts deployed gates and verifies they fire on real runs (§3.1). *E1 (false-rejection)* generates literature-anchored scenarios for HTS and LNP under default, relaxed, and strict profiles and measures the false-rejection rate on biology-valid marginal samples. *E4 (audit completeness)* scores per-event field coverage of BioMate's JSONL stream against Nextflow Tower, Galaxy, and KNIME Server on the ten 21 CFR Part 11 / FDA-2024 fields. *Cryo validation* runs the orchestrated single-particle pipeline on a public dataset and compares the reconstruction to the published structure.

### 2.5 Implementation and reproducibility

All BioMate code is open source (release tag to follow acceptance). The QC layer is in `backend/config/qc_evidence.yaml`, `backend/lib/galaxy/.../qc_gate_*.py`, `backend/lib/galaxy/jobs/qc_trace_monitor.py`, and `backend/experiments/*_autoloop/`; the BixBench adapter is `evaluation/adapters/bixbench_adapter.py`. The architecture is fail-open: any failure in an emitter, the SSE bus, or the tooltip degrades to a logged skip, never a halted pipeline.

---

## 3. Results

### 3.1 Evidence-graded governance at scale

BioMate's production QC layer comprises **57 gates across 25 domains** (26 GOLD, 26 SILVER, 5 BRONZE; recomputed from `qc_evidence.yaml`). The grades carry concrete textual differences in their `paper_supports` fields, and the five BRONZE gates are retained frankly rather than promoted to inflate the GOLD/SILVER count (e.g. `docking_binding_score`: "Trott & Olson 2010 … does NOT prescribe a binding-score cutoff. The −7 kcal/mol 'hit' threshold is community heuristic.").

Beyond the curated catalogue, the same governance layer is deployed at scale and verified to fire on real runs. A code-generation **Bioconductor QC harness** instruments analysis workflows with domain-appropriate QC gates and re-executes each under R to confirm the injected gate fires: as of the 2026-06 backfill it covers **659 workflows across 13 multi-omics domain groups**, with **658/658** dynamic Rscript checks passing (one hand-written canonical skipped), **4/4** round-trip and **7/7** audit-trail unit tests green, and **7/7** audit dimensions clean. Separately, a **protocol-threshold benchmark** ran 20 workflows (HTS plate QC, allometric scaling, ICH S5/S7 toxicology, druggability, PK/PD, BOIN dose-finding, LNP, antibody developability, siRNA off-target, biomarker enrichment, IVIVE, ADMET, CYP-DDI, NCA-PK, PBPK, Ames, retrosynthesis, structure prediction, population PK) end-to-end with live `[QC-S3]` + `[QC Gate]` logging; **20/20 gates fired correctly and scored 1.0** against their citation-graded thresholds, each with a recorded run ID and timestamp (Supplementary Table S1). Together these establish that the governance architecture is not a curated demonstration but a deployed, verified layer.

### 3.2 Public benchmarks: matching or exceeding the frontier (headline)

We evaluate the orchestration system against the *current published frontier* on two public benchmarks, under each benchmark's own protocol.

**BixBench (open-answer, execution).** BixBench is an agentic benchmark in which the agent must execute the analysis on raw data; the pre-executed reference notebook is the held-out answer key. We stress that this is distinct from the *multiple-choice* variant of the benchmark, on which frontier models score much higher (e.g. GPT-5.5 ≈ 80.5% MC) precisely because selecting an option is far easier than computing the answer. On the **open-answer** task — the one that measures analytical capability — the published state of the art is modest, reflecting how hard the task is: the multi-agent K-Dense Analyst reports 29.2%, GPT-5 22.9%, and Gemini 2.5 Pro 18.3%¹¹.

BioMate, run in execution mode (`biomate_exec`), scores **≈48% (n = 50)** on the Phylo Verified-50 subset — its `run_code` tool computing each answer from the capsule data. This **exceeds the published open-answer state of the art** (K-Dense 29.2%) and the latest frontier model (GPT-5 22.9%) by a substantial margin. We report this result with one mandatory caveat: BioMate's 48% is measured on the 50-question Verified subset, whereas the leaderboard figures are on the full 296-question benchmark, and the Verified subset may differ in difficulty. We therefore frame the result as **SOTA-competitive on open-answer BixBench, pending a full-296 confirmation run** (see §4). We additionally note a known harness limitation — a fraction of failures arise when BioMate computes a correct answer that the automated judge cannot extract from verbose output — meaning the true execution score is a floor, not a ceiling.

**BiomniEval1.** On the 223-task biomedical-reasoning benchmark, BioMate scores **71.3%**, above the fine-tuned Biomni-R0-32B-Preview baseline (≈65%)¹². The subtask breakdown is reported in full, including the weak one: patient-gene 86%, rare-disease 83%, GWAS-causal 70%, GWAS-variant 74%, and screen-gene 42% (the last is ceiling-limited without access to the specific CRISPR-screen publications); these subtask scores average to the 71.3% overall. (An earlier v17 run scored 65.9%; the 71.3% figure reflects the current system and is to be re-confirmed against the append-only ledger before final submission.)

Two internal routing and parameter metrics support the orchestration claim but are not headlined because they are self-reported and not yet independently re-audited: cross-domain routing 94.6% (v11, n = 120) and parameter prefill 84.8% (v10, n = 115). A later routing run (v13) scored 61.9% (n = 155); we flag this as unresolved — it confounds genuine drift with test-set staleness and an index change — and defer it to an offline per-query analysis (§4).

### 3.3 Default-profile QC silently rejects biology-valid samples (E1, Figure 1)

Across both tested domains, default-profile QC rejects 100% of biology-valid `marginal` samples. For HTS, 20 marginal plates from live-cell, low-signal assays (Z′ in [0.40, 0.49]) are all rejected by the default profile (Z′ ≥ 0.50) and all recovered by the `screening_grade` profile (Z′ ≥ 0.40) without changing rejection on `truly_bad` plates (10/10 still rejected). For LNP, 20 marginal batches (large-particle, small-particle, and elevated-PDI sub-populations within Akinc 2019 / ISO 22412 non-clinical ranges) are all rejected by the `clinical` profile and all recovered by `research_grade` while still rejecting 10/10 `truly_bad` batches. The cryo-EM analogue (companion paper) shows the same structural result on membrane proteins.

These domains exhibit the same architectural failure mode under fixed-threshold QC: 100% false-positive rejection of valid data when sample biology deviates from the default, and 0% recovery without an explicit profile switch. We note the caveat that the E1 metric values are **synthetic but literature-anchored** (sampled within published bands), not re-analysed raw instrument data; the result is a stress-test of the architectural failure mode rather than a population estimate.

### 3.4 Audit-trail completeness against comparator systems (E4, Figure 2)

We scored BioMate's per-event JSONL audit stream against Nextflow Tower, Galaxy, and KNIME Server across ten run logs each (n = 10 per group, across ADMET, BOIN, cryo-EM, HTS, PBPK), on the ten 21 CFR Part 11 / FDA-2024 fields. BioMate achieved per-run completeness of 1.0 on all 10 runs (IQR [1.0, 1.0]); the baselines achieved 0.0 on all 10 (IQR [0.0, 0.0]); Mann–Whitney U = 0.00, p = 1.57 × 10⁻⁴. We state plainly that this is a **structural** result, not a close contest: comparator logs carry run UUID and timestamp but none records threshold value, evidence DOI, evidence grade, override justification, or approver identity within the gate event, because those fields are absent from their data models. BioMate's audit schema is a structural superset of comparator surfaces; the p-value reflects perfect separation at n = 10 and the finding is qualitative more than statistical.

### 3.5 Cryo-EM validation: known-structure reproduction (Figure 3)

Run through the orchestrated single-particle pipeline, BioMate reconstructs *E. coli* β-galactosidase (EMPIAR-10028) to FSC 0.143 = **1.78 Å** (Nyquist-limited at the native 0.885 Å/px sampling, four-GPU parallel), with a complete gate-by-gate audit trail. We frame this explicitly as a **methods validation** — a reproduction of a known structure demonstrating that the orchestration and governance layers do not degrade a standard pipeline — not as a structural discovery. The companion cryo-EM paper reports the protocol-discrimination result in full.

---

## 4. Discussion

BioMate shows that the orchestration of routing, parameter extraction, execution, and evidence-graded QC governance can be unified in a single regulatory-traceable system, and that when this system is evaluated honestly against the *current* published frontier it is competitive or better: on open-answer BixBench its executing path exceeds the published state of the art, and on BiomniEval1 it edges a fine-tuned domain baseline. These are deliberately the numbers measured under each benchmark's own protocol — not a more flattering protocol — because the value of the comparison depends entirely on protocol parity.

The governance layer is the system's most mature contribution: 57 evidence-graded gates, a 659-workflow harness that verifies gates fire on real runs, and an audit trail that is a structural superset of established platforms. The advisory remediation engine is a deliberate scope boundary: in offline analysis a naïve fixed-step parameter search does not reliably converge, whereas a gate-aware analytic or bisection search converges in one to three steps when the gate metric is a known monotonic function of the parameter. We therefore ship remediation as advisory and defer the autonomous variant — and any convergence-rate claim — to a future study that validates the search efficiency directly.

### 4.1 Limitations

- **The BixBench result is on the Verified-50 subset.** A full-296 `biomate_exec` run is required before the open-answer SOTA claim can be stated without the "pending confirmation" qualifier, and BioMate's LLM-based answer judge has not yet been cross-validated for strictness against the official BixBench scorer; a lenient judge would inflate the score, while the verbose-output extraction gap would deflate it.
- **Autonomous remediation is advisory.** We make no autonomous-convergence performance claim in this paper; the production engine emits suggestions only, and the efficient autonomous search is unvalidated future work.
- **ADMET/heuristic predictions are not validated on official splits.** BioMate's heuristic ADMET models have not been evaluated on the official TDC ADMET-Group scaffold split, and no leaderboard-comparable ADMET claim is made here.
- **Several internal benchmarks are self-reported.** Routing (94.6%), parameter prefill (84.8%), and the protocol-threshold pass rate are self-reported and await independent audit; the routing v13 = 61.9% result is unresolved pending an offline per-query diff.
- **E1 uses synthetic-but-anchored metrics.** False-rejection rates are computed on literature-anchored synthetic scenarios, not re-analysed raw datasets, and the cryo protocol-discrimination result (companion paper) uses synthetic membrane-protein exposures (small n).
- **E4 separation is structural and small-n.** The 1.0-vs-0.0 audit-completeness gap reflects absent fields in comparator data models, measured on curated (not randomly sampled) runs at n = 10 per group.

---

## 5. Data and code availability

All data underlying this study are publicly available. Raw biological inputs are referenced by their existing public accessions and are **not** re-hosted: BixBench capsules (FutureHouse), BiomniEval1 tasks, GEO/ENCODE accessions, and EMPIAR-10028 (β-galactosidase). BioMate-derived evaluation artefacts — task files, prompts, gate configurations (`qc_evidence.yaml`), per-run JSONL audit logs, and result CSV/JSON — are released as a loadable dataset on Hugging Face Datasets (`huggingface.co/datasets/biomate/biomate-agent-bench`, slug to finalise on release). The evaluation harness, gate evaluators, and BixBench adapter are released on GitHub with a tagged release (`github.com/[REPO-PLACEHOLDER]/biomate`, tag to follow acceptance). No Zenodo deposit is used; all data are public by accession.

---

## References (placeholder — to be expanded)

1. CryoSPARC Live (Punjani et al., *Nature Methods* 2017; Live release notes).
2. Warp (Tegunov & Cramer, *Nature Methods* 2019).
3. SwissADME, admetSAR, ADMETlab platform references.
4. Redfern WS, Carlsson L, Davis AS, et al. *Cardiovasc Res* 2003;58(1):32–45. DOI 10.1016/S0008-6363(02)00846-5. Cross-confirmed by Bowes J et al. *Nat Rev Drug Discov* 2012;11(12):909–922 (DOI 10.1038/nrd3845).
5. Lipinski CA et al. *Adv Drug Deliv Rev* 2001.
6. Lammert et al. 2010; Andrade et al. — DILI cumulative-dose rule.
7. Zhang J-H, Chung TDY, Oldenburg KR. *J Biomol Screen* 1999 — Z′ factor.
8. EMA Guideline EMA/CHMP/458101/2016 (2019); FDA 2018 PBPK Guidance for Industry.
9. FDA 2024 draft guidance: AI/ML-based software as a medical device.
10. EMA 2024 reflection paper on AI in the medicinal product lifecycle.
11. BixBench: a Comprehensive Benchmark for LLM-based Agents in Computational Biology. FutureHouse & ScienceMachine, arXiv:2503.00096 (2025); open-answer leaderboard (llm-stats.com/benchmarks/bixbench, accessed 2026-06). K-Dense Analyst open-answer result reported separately.
12. Huang K et al. Biomni: A General-Purpose Biomedical AI Agent. *bioRxiv* 2025, doi:10.1101/2025.05.30.656746; Biomni-R0 Technical Report, biomni.stanford.edu, 2025.
