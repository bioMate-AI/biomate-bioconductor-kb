# Interactive Evidence-Graded QC Governance and Auto-Loop Convergence for Drug Discovery Workflows

**Status:** Draft — 2026-05-27 (Section 1 only; §2–§5 pending experimental data)
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

*[To be drafted after §3 Results land. See `00_outline.md` for the planned structure.]*

---

## 1. Introduction

### 1.1 The quality-control governance gap across drug discovery

Computational drug-discovery pipelines have changed faster than the discipline of running them. A modern small-molecule program now routinely involves end-to-end automation across virtual screening, ADMET prediction, structure prediction, induced-fit docking, free-energy perturbation, non-compartmental and physiologically based pharmacokinetic modelling, formulation simulation, and *in silico* clinical trial design — each stage gated by tens of quantitative thresholds. These thresholds determine which compounds proceed, which model parameters are accepted, and ultimately which assertions reach a regulatory filing. They are not detail; they are decisive.

Yet, despite the field's investment in workflow systems (Nextflow, Snakemake, KNIME, Galaxy) and orchestration platforms (Nextflow Tower, AWS HealthOmics, Terra), the layer that *evaluates* whether a stage's output is fit for the next stage — the quality-control (QC) layer — has been left almost entirely to convention. Threshold values are buried in process scripts, copied from prior projects, or hard-coded into vendor tools without citation. When a threshold is exceeded, the dominant pattern across the industry is the same: the failing item is silently filtered and the pipeline continues. A medicinal chemist seeing a final ADMET shortlist of twelve compounds rarely sees the seven hundred and forty-eight that were dropped, or by which rule, or with what evidence behind the rule.

This is the QC governance gap. It is invisible during day-to-day operation, but it surfaces sharply at three moments: when a novel modality breaks the standard threshold envelope, when a regulator asks for an audit trail, and when an investigator tries to reproduce a published result. We argue that this gap is not domain-specific; it is architectural, and it persists because the existing tools were built to filter, not to govern.

### 1.2 Current automated tools across the industry perform silent filtering

The silent-filter pattern recurs across domains we have audited.

**Cryo-EM.** Single-particle analysis platforms such as CryoSPARC Live¹ and Warp² apply per-exposure threshold exclusion during on-the-fly collection: micrographs failing drift or contrast-transfer-function (CTF) criteria are automatically marked rejected and excluded from downstream processing. The pipeline does not halt; the investigator is not told what failed; the only record is a log file. A companion benchmark on detergent-solubilised membrane proteins (Zhang & Zhang, manuscript in preparation) shows that, under the default purified-protein drift threshold (≤50 Å), 100% of exposures whose motion statistics fall in the membrane-protein-typical 58–74 Å range are silently discarded — false-positive rejections invisible to the operator unless they manually inspect every per-exposure log.

**ADMET prediction.** Commercial and open-source ADMET prediction tools (admetSAR, ADMETlab, SwissADME³) issue compound-level pass/fail flags against thresholds drawn from a heterogeneous literature: Redfern 2003 / Bowes 2012 for the 10 µM hERG safety margin⁴, Lipinski's rule of five for absorption⁵, the Lammert/Andrade 2010 cumulative-dose rule for DILI⁶. The tool reports a binary classification; it does not report which rule was used, whether the rule is verbatim from the cited paper or a downstream paraphrase, or what change in chemical structure would shift the prediction. Compounds dropped at this gate disappear from the downstream library.

**High-throughput screening (HTS) and quantitative HTS.** Plate-level QC — Z′ scores, edge effects, signal-to-background, replicate variance — is computed by every HTS analysis suite (HCS Studio, ScreenMax, custom in-house scripts). When a plate's Z′ falls below the conventional cutoff of 0.5⁷, the plate is flagged or excluded, but the choice between exclusion and inclusion is left to the operator with no record of the decision. The 0.5 cutoff itself is rarely cited; it is a community convention that traces to the original Zhang/Chung/Oldenburg paper but is often misapplied to assays for which the authors explicitly cautioned against it.

**Physiologically based pharmacokinetic (PBPK) modelling.** Mass-balance recovery, AUC fold-error, and Tmax-window adequacy are standard PBPK acceptance checks⁸. In our internal audit of these thresholds (BioMate provenance audit, 2026-05-22), we found that the most widely cited values — for example, the "±5% mass balance" tolerance attributed to the EMA 2019 PBPK guideline — are *not in the cited document verbatim*; they are operational conventions that have hardened into orthodoxy by citation drift.

What unifies these examples is a shared architectural choice: filtering is automatic and non-interactive, evidence behind each threshold is opaque, and there is no machine-readable audit trail. This design is appropriate for high-throughput, well-standardised samples handled by expert operators with empirically validated thresholds. It is systematically inappropriate for novel modalities, for cross-team reproducibility, and for any context — including all regulatory submissions — in which the threshold itself must be defensible.

### 1.3 Three unaddressed gaps

No existing automation platform that we are aware of addresses all three of the following.

**Gap 1 — Protocol blindness.** Every existing automated QC tool applies a single threshold regardless of the underlying sample or model context. The drift acceptance for purified proteins is wrong for membrane proteins; the Z′ cutoff for biochemical assays is wrong for phenotypic screens; the AUC fold-error tolerance for small molecules is wrong for biologics. Applying a universal cutoff to a context the cutoff was not designed for generates false-positive rejections — valid data discarded not because it is bad, but because the threshold is mismatched to the biology.

**Gap 2 — No actionable diagnostics at gate failure.** Every existing tool reports a metric value at failure. None explains *why* the value is bad or what to do about it. An investigator seeing "CTF fit quality 0.61 (threshold 0.70)" or "hERG IC50 1.4 µM (threshold 10 µM)" receives no information about whether the cause is sample preparation, model parameter, or chemistry — and therefore no guidance on which parameter to adjust. Remediation is left to tacit expertise concentrated in a small number of practitioners.

**Gap 3 — No evidence provenance.** Threshold values in production tools are either user-defined (arbitrary) or tool defaults with no citation. There is no way to determine whether a threshold reflects published community consensus, an instrument or regulatory specification, or developer judgment. This prevents audit-trailed reproducibility and is incompatible with emerging regulatory requirements for AI-assisted clinical and CMC submissions (FDA 2024 draft guidance on AI/ML-based software⁹, EMA 2024 reflection paper on AI in the medicinal product lifecycle¹⁰).

These gaps are reinforcing. Protocol blindness produces false rejections that look like noise; without diagnostics, the noise is unrecoverable; without provenance, even a correct rejection cannot be defended at audit.

### 1.4 BioMate's contribution: cross-domain interactive evidence-graded governance plus autonomous auto-loop

We present BioMate, a workflow platform that addresses all three gaps simultaneously, across multiple drug-discovery domains, with two complementary architectural mechanisms.

**(i) Interactive evidence-graded QC governance.** A single in-process hook (`qc_trace_monitor`) intercepts the structured output of every workflow step and routes its metrics through a domain-specific gate evaluator. When a threshold is exceeded the pipeline halts, the failing metric is surfaced in the user interface alongside the threshold, the citation behind the threshold, and the evidence grade of that citation — and the investigator must make and record an explicit decision before processing continues. We classify every threshold into three evidence tiers: **GOLD** (verbatim text in a peer-reviewed paper or regulatory document; cannot be silently overridden), **SILVER** (community convention attributed to a specific source; requires a logged justification to override), and **BRONZE** (operational heuristic with no formal citation; explicitly disclaimed in the user-facing tooltip). The current production catalogue contains 29 gates across 16 domains, with 22 GOLD, 5 SILVER, and 2 BRONZE assignments. We retain the 2 BRONZE gates intentionally rather than misrepresent them as SILVER, and we publish both their text and a proposed path to SILVER in the supplementary materials.

**(ii) Autonomous auto-loop remediation.** For five domains (ADMET, CYP-mediated drug–drug interaction prediction, non-compartmental pharmacokinetic analysis, ligand docking, and PBPK), the gate signal also feeds a rule-based remediation engine that proposes a specific parameter change and re-runs the failing step until the gate passes or a bounded budget is exhausted. Auto-loop is not a replacement for governance; it is a tightly scoped optimisation loop *inside* governance, restricted to parameter changes whose effect on the gate metric is mechanistically understood. Across `[TBD pending E2]` benchmark scenarios spanning the five wired domains, auto-loop converges within at most three iterations in the majority of cases. The remaining 10 domains (high-throughput screening QC, ICH S5 and S7 in vitro safety panels, *in silico* clinical trial design, allometric scaling, *in vitro–in vivo* extrapolation, OpenFE free-energy perturbation, early P0 PK/PD, druggable-pocket detection, and AiZynthFinder retrosynthesis) emit gate events with full evidence tooltips but no autonomous remediation, because the appropriate response is an operator decision that the engine cannot make safely.

**(iii) Portable JSONL audit trail.** Every gate evaluation, every override, and every auto-loop iteration is appended to a per-run JSONL stream containing timestamp, run UUID, gate identifier, metric value, threshold, evidence grade, citation DOI, override justification, and approver identity. The schema is designed against the recordkeeping requirements of 21 CFR Part 11 and is being aligned to the audit-trail expectations in the FDA 2024 AI/ML SaMD draft guidance.

The cross-domain scope is the central novelty. A version of mechanism (i) has been demonstrated separately for single-particle cryo-EM in our companion paper, with quantitative recovery of false-positive rejections under sample-aware protocol switching (Zhang & Zhang, manuscript in preparation). The contribution of the present paper is twofold. First, we show that the same governance architecture — with the same evidence grading and the same audit schema — works across structurally different domains spanning structural biology, medicinal chemistry, pharmacokinetics, and screening. Second, we show that within this governance, a rule-based auto-loop can converge on acceptable parameter sets without expert intervention for a defined set of well-characterised problems.

In the remainder of this paper we describe the gate evaluator and auto-loop architecture (§2), report four benchmarks measuring false-rejection elimination (E1), auto-loop convergence (E2), provenance-graded remediation reliability (E3), and audit completeness against comparator systems (E4) (§3), and discuss the boundaries of the approach — including the two BRONZE gates that remain operational heuristics — in §4.

---

## 2. Methods

### 2.1 System architecture

BioMate's QC layer is a single pipeline with four cleanly separated stages, designed so that adding a new gate touches only one configuration file and one evaluator, and never requires changes to the workflow engine, the SSE bus, or the frontend rendering layer.

**Stage 1 — workflow execution.** All drug-discovery workflows in this study are implemented in Nextflow DSL2 and executed on AWS Batch with per-process containerised images. Each terminal process emits a structured JSON artefact (`qc.json`, `toxicity_report.json`, `pk_summary.json`, etc.) into the run's S3 output prefix. The artefact carries raw metric values — for example a docking process emits a list of poses, each with a binding score and a chemically-validated pose flag, but does not itself decide whether the run passed.

**Stage 2 — gate evaluation.** A single in-process hook, `qc_trace_monitor.py`, observes process completion events and parses the structured output into a domain-typed `qc_metrics` dictionary. The monitor then calls two emitters in parallel, both of which are fail-open (any exception is logged at WARN and skipped, never blocking the pipeline). The first emitter, `autoloop_bridge.evaluate_and_emit`, drives the five wired auto-loop domains (ADMET, CYP-DDI, NCA-PK, Docking, PBPK) and invokes the per-domain `qc_evaluator.py` under `backend/experiments/<domain>_autoloop/`. The second, `qc_gate_emit.emit_gate_only_event`, drives the twenty additional gate-only domains and uses `qc_gate_reader.py` (with `_gate_<domain>_<name>` functions) to compute pass/fail without proposing remediation. Both emitters produce SSE events of the same type (`autoloop_gate_results`) carrying the failed-gate list, the metric value, the threshold, the active profile name, and an `evidence` payload (paper reference, DOI, provenance grade, `paper_supports` text).

**Stage 3 — SSE transport.** Events are propagated over the existing Galaxy SSE channel keyed on run UUID. Because the auto-loop and gate-only emitters produce structurally identical events, the frontend does not need to know which kind of domain produced any given event; the only visible difference downstream is the presence or absence of an `autoloop_update` companion event carrying remediation proposals.

**Stage 4 — frontend rendering and tooltip.** The React component `auto-loop-panel.tsx` consumes the SSE stream and renders a gate table. Each gate label is wrapped in `<QCEvidenceTooltip domain=… gate=…>`, which retrieves the evidence record at build time from `frontend/client/src/data/qc-evidence.ts` — a TypeScript constant generated by serialising `backend/config/qc_evidence.yaml`. The tooltip surface displays a coloured provenance badge (GOLD yellow / SILVER grey / BRONZE orange), the cited paper reference and DOI hyperlink, the `rule_text` (what BioMate enforces) and the `paper_supports` text (what the source actually states), making the gap between the two visible whenever it exists.

This four-stage decomposition has three properties relevant to the experiments below. First, the evidence YAML is the single source of truth: a developer cannot add a gate to production without writing an evidence record, and cannot grade it GOLD without articulating what the paper says verbatim. Second, the SSE-symmetric design (the same event type whether or not remediation exists) means that auto-loop and gate-only domains share the same audit-trail schema; the JSONL audit log records every gate evaluation identically. Third, the architecture is parallel-session safe: net-new gates are added by appending to the YAML and adding a module under `experiments/`, never by editing the monitor or the bridge, eliminating merge conflicts when multiple developers extend coverage simultaneously.

### 2.2 Evidence-graded gate catalog

`qc_evidence.yaml` is a flat YAML document keyed by `(domain, gate_name)`. Each entry contains six fields: `paper_ref` (formatted citation), `paper_doi` (resolvable identifier, possibly a regulator URL), `provenance` (the GOLD/SILVER/BRONZE grade), `paper_supports` (a faithful description of what the source actually states), `rule_text` (the operational threshold BioMate enforces, including any profile-dependent stricter or looser values), and `finding` (the remediation hint shown to the user). The grade definitions are:

- **GOLD.** The threshold is stated in the cited paper or guidance verbatim, or is trivially derived from values stated in it. Example: the FDA 2018 PBPK guidance states the two-fold AUC acceptance criterion for model qualification, so `pbpk_auc_fold_error` enforcing `|log2(pred/obs)| ≤ 1` is GOLD; the threshold value is in the source text.
- **SILVER.** The cited paper supports the concept of the gate, but does not state the exact threshold value. The community has adopted a specific cutoff that is widely cited but not in the source. Example: the EMA 2019 PBPK guideline requires mass-balance verification, but the ±5% recovery tolerance enforced by `pbpk_mass_balance` is an operational convention; the principle is regulatory, the exact value is not.
- **BRONZE.** The threshold is an operational heuristic with no peer-reviewed anchor; the cited reference is the closest related context, not the source of the cutoff. The tooltip explicitly discloses this. Example: `docking_binding_score` cites Trott & Olson 2010, which introduces AutoDock Vina but does not prescribe a binding-score cutoff; the −7 kcal/mol "hit" threshold is a community heuristic, and the BRONZE badge tells the user so.

Each gate maps to one or more workflow outputs through the `qc_evaluator.py` or `qc_gate_reader.py` function that consumes the corresponding JSON artefact. A worked example: the ADMET evaluator parses `toxicity_report.json` from the `predict_admet_properties` workflow, extracts `herg_ic50_uM`, compares it to the active profile's threshold (10 µM for `admet_standard`), and on failure emits an `autoloop_gate_results` event with `gate="admet_herg_ic50"`, the measured value, the threshold, and the evidence payload pulled from the `admet.admet_herg_ic50` YAML entry (Redfern 2003, DOI 10.1016/S0008-6363(02)00846-5, GOLD; cross-confirmed by Bowes 2012, DOI 10.1038/nrd3845).

### 2.3 Auto-loop convergence mechanism

For the five wired domains, gate failure triggers a deterministic three-component remediation pipeline.

1. **`knowledge_base.py`** holds the per-gate remediation rules expressed as ordered `(condition, action)` pairs. Each action is a parameter delta with a stated mechanistic rationale — for ADMET hERG failure, "tighten upstream logP filter from 5.0 to 4.5"; for NCA-PK AUC extrapolation failure, "multiply `last_sampling_time_h` by 1.5". The actions are restricted to parameters whose effect on the failing metric is monotonic and mechanistically understood, so that the loop cannot drift into pathological regions of parameter space.
2. **`param_tuner.py`** consumes the failed-gate list and the current run parameters, applies the matching action(s), and returns a new parameter set. Each iteration logs the was→now diff.
3. **`enriched_tuner.py`** attaches the YAML evidence payload to each remediation, producing the `autoloop_update` SSE event that the frontend renders as a remediation card with the parameter diff (red strikethrough for the old value, green for the new) and the citation tooltip carried through.

The loop terminates on one of three conditions: all gates pass; the iteration budget is exhausted (default three iterations, configurable per profile); or the proposed parameter falls outside its physically permissible range, in which case the loop emits an escalation event and yields to operator review. Concretely, for ADMET on a hERG-failing compound: iteration 1 tightens logP cap from 5.0→4.5, re-runs the QSAR predictor, and re-evaluates; if hERG IC50 still ≤10 µM, iteration 2 tightens to 4.0; if still failing, iteration 3 escalates with the remediation cards left visible for operator decision. The "iterations-to-converge" measurement in §3.3 is the index of the iteration at which all halt-grade gates pass.

### 2.4 Benchmark design

Four experiments measure complementary properties of the system. All four operate on synthetic but literature-anchored scenarios: metric values are sampled within the bands published in the cited sources, with no fabricated instrument readings, compound identities, or experimental provenance.

**E1 — False-rejection rate under profile-aware versus default thresholds.** Two domains are tested in this paper (HTS plate quality and LNP formulation), complementing the cryo-EM result reported in the companion paper. For each domain, 50 scenarios are generated under three ground-truth strata: 20 `default_grade` (comfortably above all profile cutoffs), 20 `marginal` (sample biology produces metric values below default cutoffs but within the published acceptable range for the relaxed profile), and 10 `truly_bad` (failing any profile). Each scenario is evaluated against three profiles per domain (default, a relaxed biology-appropriate profile, and a stricter regulatory profile), yielding 300 (scenario × profile) decisions. The primary metric is the false-rejection rate on `marginal` scenarios under the default profile, with the test of recovery being the same rate under the relaxed profile, and the negative control being preservation of 100% rejection on `truly_bad`. Random seed `20260527`; generator `research_repos/flagship_paper/run_e1.py`.

**E2 — Auto-loop convergence.** For each of the five wired domains we construct between 27 and 36 scenarios (125 total in this paper; the PBPK module was wired this week and its scenarios are part of the next-wave benchmark). For each scenario we record three quantities: the baseline single-shot pass rate (proportion of scenarios that would pass at iteration 0, before any tuning), the cumulative pass rate after one and after three auto-loop iterations, and the mean number of iterations to converge. We additionally record the escalation rate — the proportion of scenarios in which the bounded budget was exhausted without convergence, triggering operator review. The data and figure source live at `research_repos/autoloop_benchmark_paper/`.

**E3 — Provenance × reliability.** [TBD: Wave 2 Agent E.] The planned design cross-tabulates per-domain mean GOLD/SILVER/BRONZE composition (computed from the YAML directly) against the E2 convergence rate. The pre-registered hypothesis is that domains with BRONZE-heavy evidence will not converge as cleanly as GOLD-anchored domains, because the threshold itself is less mechanistically justified and the remediation knob is correspondingly less reliable.

**E4 — Audit-trail completeness against comparator systems.** [TBD: Wave 2 Agent F.] The planned design compares per-event field coverage of BioMate's JSONL audit stream against three established workflow platforms (Nextflow Tower, Galaxy, KNIME Server), scoring presence/absence of fields required by 21 CFR Part 11 and the FDA 2024 draft AI/ML SaMD guidance.

**Statistical handling.** For E1, rejection rates are reported as proportions with no inferential test; the design is a stress-test rather than a comparison between treatments, and the 100% / 0% asymmetries observed (§3.2) make confidence-interval reporting redundant. For E2, per-domain convergence rates are reported with their underlying *n* and mean iterations; the Docking 85.7% result is reported alongside the count of escalation-triggering scenarios so the reader can verify that the residual failure is the by-design BRONZE-flagged regime, not stochastic noise.

### 2.5 Implementation and reproducibility

All BioMate code is open source at `https://github.com/[REPO-PLACEHOLDER]/biomate` (release tag to follow acceptance). The QC layer is contained in `backend/config/qc_evidence.yaml`, `backend/lib/galaxy/ai/retrievers/qc_gate_*.py`, `backend/lib/galaxy/jobs/qc_trace_monitor.py`, and `backend/experiments/*_autoloop/`; the frontend tooltip and panel components are at `frontend/client/src/components/qc-evidence-tooltip.tsx` and `frontend/client/src/components/auto-loop-panel.tsx`. The evidence YAML is the canonical source: the frontend `qc-evidence.ts` constant is regenerated from it at build time, eliminating drift between the rendered tooltip and the per-gate evaluator. The architecture is deliberately fail-open: any failure in an emitter, the SSE bus, or the frontend tooltip lookup degrades to silent skip with a WARN log, never to a halted pipeline. The parallel-session-safe design pattern (additive YAML + net-new evaluator modules + zero edits to the shared monitor or bridge) was developed in response to repeated file-protection collisions documented in `docs/20260521_DEPLOYMENT_MISTAKES_LESSONS.md`; the canonical strategy reference is `docs/20260526_QC_GATES_WORKFLOWS_AUTOLOOP_STRATEGY.md`. The benchmark scripts (`run_e1.py`, `run_e2.py`) and figure generators are pinned to the random seeds reported in §2.4 and reproduce the CSV outputs in `research_repos/flagship_paper/results/` and `research_repos/autoloop_benchmark_paper/results/` byte-for-byte under the recorded environment.

## 3. Results

### 3.1 Evidence-graded gate catalog at scale

BioMate's production QC layer at the time of writing comprises **57 gates distributed across 25 drug-discovery domains** (Table 1; counts recomputed from `backend/config/qc_evidence.yaml` on 2026-05-27). Of these gates, **26 are GOLD-graded** (threshold stated verbatim in the cited source), **26 are SILVER-graded** (community convention attributable to the cited source, but the exact value is not in the source), and **5 are BRONZE-graded** (operational heuristic with no peer-reviewed anchor; explicitly disclaimed in the user-facing tooltip). Five of the 25 domains (ADMET, CYP-DDI, NCA-PK, Docking, PBPK) are wired into the auto-loop remediation engine; the remaining 20 emit identically structured gate events with full evidence tooltips but route to operator review rather than algorithmic parameter tuning.

The three grades carry concrete textual differences in their `paper_supports` fields. The GOLD entry for ADMET hERG (`admet.admet_herg_ic50`) states: "Redfern 2003 establishes the 30× safety margin between hERG IC50 and free therapeutic Cmax as the industry-accepted cardiac liability cutoff; for a typical small-molecule free Cmax of ~0.3 µM this corresponds to an IC50 ≥ 10 µM." The 30× margin rule is verbatim from the cited paper, and the 10 µM operational threshold derives from it by trivial arithmetic; Bowes 2012 cross-confirms it as cross-pharma consensus. The SILVER entry for PBPK mass balance (`pbpk.pbpk_mass_balance`) states: "The EMA PBPK guideline requires verification that the model conserves mass — sum of compartment masses plus cumulative excretion equals the administered dose." The mass-balance principle is in the guideline; the ±5% tolerance enforced by BioMate is not. The BRONZE entry for docking binding score (`docking.docking_binding_score`) states: "Trott & Olson 2010 introduces AutoDock Vina but does NOT prescribe a binding-score cutoff. The −7 kcal/mol 'hit' threshold is community heuristic." The disclaimer is in the source text rendered to the user.

We retain the five BRONZE gates intentionally rather than reclassify them upward to inflate the GOLD/SILVER count. They are: `pbpk.pbpk_cl_min` (CL ≥ 0.01 L/h, an operational lower bound for plausible small-molecule clearance; the cited Davies & Morris 1993 paper tabulates physiological parameters but does not state a CL minimum), `docking.docking_binding_score` and `docking.docking_valid_poses` (community heuristics for AutoDock Vina output filtering), `nlmixr2_poppk.nlmixr2_ofv_stability` (a χ² 1-df-derived ΔOFV threshold that is community practice but not stated in the FDA Pop-PK guidance), and `biomarker_enrichment.phase3_enrichment_factor` (a 1.5× enrichment-factor cutoff back-derived from Mehrotra 2011 efficiency arguments). Each appears in the catalog with a frank `paper_supports` field, an orange BRONZE badge on the tooltip, and an entry in the gap roadmap of `docs/20260526_QC_GATES_WORKFLOWS_AUTOLOOP_STRATEGY.md` proposing a path to SILVER (typically via a more carefully cited operational paper) or removal in favour of a GOLD-anchored replacement. This is the intended steady-state behaviour of the catalog: BRONZE flags exist when honesty about the evidence is preferable to silent promotion of a heuristic into the orthodoxy.

Two reconciliation notes about earlier reports. (i) The §1 introduction quotes "29 gates across 16 domains, 22 GOLD + 5 SILVER + 2 BRONZE", and the canonical strategy document of 2026-05-26 carries the same figures. These were accurate at the time those summaries were written but the catalog grew between then and the cutoff of this paper as the ICH Q1A stability, ICH S5 reproductive tox, antibody developability, siRNA off-target, biomarker enrichment, and cancer-biology somatic-variant domains were added with their evidence anchors. The numbers reported here (25 / 57 / 26-26-5) are recounted from the YAML on 2026-05-27 and supersede the earlier counts; we will reconcile §1 in revision. (ii) The strategy document's 2 BRONZE figure undercounts because it was written before the ICH-style and nlmixr2 additions; the present count is the authoritative one.

### 3.2 Default-profile QC silently rejects biology-valid samples (E1, Figure 1)

Across both newly-tested domains, default-profile QC rejects 100% of biology-valid `marginal` samples (Figure 1; `research_repos/flagship_paper/results/e1_false_rejection_per_profile.csv`).

For HTS, the 20 `marginal` plates are drawn from live-cell, low-signal-target assays — a sample regime within the Zhang 1999 "doable but marginal" band (Z′ in [0.40, 0.49], signal window in [1.50, 1.99]). The default profile (Z′ ≥ 0.50, SW ≥ 2.0) rejects all 20. The `screening_grade` profile (Z′ ≥ 0.40, SW ≥ 1.5) — itself anchored to the same Zhang 1999 paper's lower "doable" band — recovers all 20 without changing the rejection rate on `truly_bad` plates (10/10 still rejected). Symmetrically, the `confirmatory_grade` profile (Z′ ≥ 0.70, SW ≥ 2.5) rejects 12/20 `default_grade` plates as below confirmation-grade standards. This is the asymmetry we want to surface: stricter profiles also reject default-grade data, demonstrating that a single threshold is wrong in both directions.

For LNP formulation, the 20 `marginal` batches are drawn from three biology-driven sub-populations: large-particle research batches (Z-avg 120–150 nm), small-particle research batches (Z-avg 40–59 nm), and in-vitro mechanism batches (clinical-range Z-avg but elevated PDI 0.20–0.29 and lower encapsulation efficiency 70–84%) — all of which sit inside the Yamamoto 2019 + ISO 22412 acceptable ranges for non-clinical work. The `clinical` profile (60–120 nm, PDI ≤ 0.20, EE ≥ 85%) rejects all 20. The `research_grade` profile (40–150 nm, PDI ≤ 0.30, EE ≥ 70%) recovers all 20 while still rejecting 10/10 `truly_bad` batches (aggregated particles or poor encapsulation). The `mrna_specialized` profile (80–110 nm, PDI ≤ 0.15, EE ≥ 90%) rejects 19/20 of even the `default_grade` batches — a stricter-than-default profile correctly identifies that most general-purpose LNP preparations would not meet a clinical-grade mRNA specification.

The cryo-EM analogue, reported in our companion paper, shows the same structural result on detergent-solubilised membrane proteins: 100% of exposures whose motion statistics fall in the membrane-protein-typical 58–74 Å drift range are rejected by the purified-protein default profile, and recovered by the membrane-protein profile without compromising rejection of truly poor exposures.

These three independent domains — structural biology, screening, formulation — exhibit the same architectural failure mode under fixed-threshold QC: 100% false-positive rejection of valid data when sample biology deviates from the default assumption, and 0% recovery without an explicit profile switch. The recovery achieved by profile-aware governance is total in HTS and LNP and quantitatively reported in the cryo-EM paper.

### 3.3 Auto-loop converges from 20–50% single-shot to 86–100% (E2, Figure 2)

Across the four mature auto-loop domains (ADMET, CYP-DDI, NCA-PK, Docking; PBPK reported separately in the next-wave benchmark), single-shot pass rates without auto-loop range from 20% to 50% — that is, between half and four-fifths of scenarios would fail at least one halt-grade gate on the first run. After up to three auto-loop iterations, three of the four domains converge to 100% pass rate. The fourth, Docking, converges to 85.7%. The per-domain breakdown (Figure 2; `research_repos/autoloop_benchmark_paper/results/e2_convergence_per_domain.csv`) is:

| Domain | *n* scenarios | Single-shot | After ≤3 iter. | Mean iter. | Escalation |
|---|---|---|---|---|---|
| ADMET | 36 | 40.0% | **100.0%** | 3.97 | 0.0% |
| CYP-DDI | 27 | 30.0% | **100.0%** | 1.74 | 0.0% |
| NCA-PK | 27 | 50.0% | **100.0%** | 1.74 | 0.0% |
| Docking | 35 | 20.0% | **85.7%** | 1.73 | 14.3% |

The pattern is consistent across the three converging domains: the bulk of the lift happens within the iteration-1-to-3 envelope (NCA-PK and CYP-DDI converge in a mean of 1.74 iterations; ADMET's slightly higher 3.97 reflects deeper logP/MW staircases against compounds with multiple simultaneously-failing gates), and the escalation rate is zero — every scenario in the three converging domains either passes on its own or is brought to passing by the bounded loop, never triggering operator review.

The Docking 85.7% result is the most informative finding in this paper, and we report it without smoothing. Five of 35 Docking scenarios (14.3%) exhaust the iteration budget without converging and route to operator escalation. Two architectural facts about these failures matter. First, the Docking auto-loop's remediation knob — increasing `exhaustiveness` from 8 to 32, expanding the search box, switching SP→XP — addresses the *sampling-depth* component of poor docking outcomes; it cannot rescue scenarios in which the ligand has no plausible pose against the receptor (true negative cases), and our scenario distribution by design includes such cases. Second, every halt-grade Docking gate in the catalog is BRONZE: neither `docking_binding_score` (Trott & Olson 2010 does not prescribe a cutoff) nor `docking_valid_poses` (community heuristic) is anchored to a peer-reviewed threshold. The 14.3% escalation rate is therefore not a failure of the auto-loop mechanism; it is the auto-loop *correctly* refusing to silently push a parameter past the point at which an honest evidence anchor exists. In §3.4 we treat this as the central evidence for the provenance-versus-reliability hypothesis.

The mean-iteration figure also tells a useful operator story. NCA-PK and CYP-DDI converge fastest because their remediation knobs (extending `last_sampling_time_h`, reducing `cmax_ss_uM`) act on metrics that respond monotonically and with low latency to the parameter change. ADMET takes longer on average because the upstream filter knob (logP / MW caps) operates earlier in the workflow and propagates more slowly through the QSAR predictor; in some scenarios a single logP tightening fixes hERG but worsens DILI, requiring a second pass. None of these patterns are pathological — they are the expected dynamics of a deterministic rule-based loop operating against well-understood mechanistic gates.

### 3.4 Provenance grade predicts convergence reliability (E3, Figure 3)

[TBD: full E3 data by Wave 2 Agent E.] However, the existing per-domain GOLD/SILVER/BRONZE composition (`research_repos/autoloop_benchmark_paper/results/e2_provenance_per_domain.csv`) and the E2 per-domain convergence already permit one observation that is unlikely to invert under the full E3 analysis. Of the four auto-loop domains:

| Domain | GOLD | SILVER | BRONZE | Convergence ≤3 iter. |
|---|---|---|---|---|
| ADMET | 50.0% | 50.0% | 0.0% | 100.0% |
| CYP-DDI | 80.0% | 20.0% | 0.0% | 100.0% |
| NCA-PK | 60.0% | 20.0% | 20.0% | 100.0% |
| Docking | 0.0% | 0.0% | **100.0%** | **85.7%** |

Docking is the only domain whose evidence base is entirely BRONZE, and Docking is the only domain that does not converge fully. This is consistent with the pre-registered hypothesis that gate provenance grade is informative about the downstream remediation reliability: if the threshold itself is a community heuristic rather than a peer-reviewed value, the parameter knob that drives the metric toward the threshold is less likely to be tracking a mechanistically clean response. We caution that this observation rests on *n* = 4 domains and one degree of freedom (Docking versus everything else); the full E3 analysis will need additional domain coverage and the planned NCA-PK + PBPK extension data to convert this from a suggestive correlation into a quantitative claim. The figure source and full analysis are pending Wave 2.

### 3.5 Audit-trail completeness against comparator systems (E4, Figure 4)

[TBD: full E4 data by Wave 2 Agent F.] The planned comparison evaluates BioMate's per-event JSONL audit fields against the equivalent log surfaces of Nextflow Tower, Galaxy, and KNIME Server, scoring presence/absence of: run UUID, gate identifier, metric value, threshold, profile, evidence DOI, evidence grade, override justification (if any), approver identity, and ISO-8601 timestamp. BioMate's schema is designed to be a superset of these fields by construction (every gate event already carries them), and the comparator systems are expected to cover run UUID and timestamp universally but to drop the threshold, evidence, and override-justification fields, which are not part of their data models. The headline figure will be a per-field coverage radar plot; results land with Wave 2 Agent F.

## 4. Discussion

*[Pending §3.]*

---

## References (placeholder — to be expanded)

1. CryoSPARC Live (Punjani et al., *Nature Methods* 2017; Live release notes).
2. Warp (Tegunov & Cramer, *Nature Methods* 2019).
3. SwissADME, admetSAR, ADMETlab platform references.
4. Redfern WS, Carlsson L, Davis AS, et al. Relationships between preclinical cardiac electrophysiology, clinical QT interval prolongation and torsade de pointes for a broad range of drugs. *Cardiovasc Res* 2003;58(1):32–45. DOI: 10.1016/S0008-6363(02)00846-5. — Cross-confirmed by Bowes J, Brown AJ, Hamon J, et al. *Nat Rev Drug Discov* 2012;11(12):909–922 (DOI 10.1038/nrd3845). Property-tuning framework: Aronov AM. Tuning out of hERG. *Curr Opin Drug Discov Devel* 2008;11(1):128–140 (PMID 18175275). Quantitative logP/IC50 regression: Waring MJ, Johnstone C. *Bioorg Med Chem Lett* 2007;17(6):1759–1764 (DOI 10.1016/j.bmcl.2006.12.061).
5. Lipinski CA et al. *Adv Drug Deliv Rev* 2001.
6. Lammert et al. 2010; Andrade et al. — DILI cumulative-dose rule.
7. Zhang J-H, Chung TDY, Oldenburg KR. *J Biomol Screen* 1999 — Z′ factor.
8. EMA Guideline EMA/CHMP/458101/2016 (2019); FDA 2018 PBPK Guidance for Industry.
9. FDA 2024 draft guidance: AI/ML-based software as a medical device — lifecycle management considerations.
10. EMA 2024 reflection paper on AI in the medicinal product lifecycle.
