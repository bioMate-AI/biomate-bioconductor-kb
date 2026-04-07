# Pilot Study Proposal
## Evaluating AI-Native Computational Drug Discovery in a Clinical Medicine Setting

**Proposing parties:** BioMate AI · Department of Medicine, Zhejiang People's Hospital  
**Pilot duration:** 10 days (range 7–14) from agreed start date  
**Scope:** 10–20 compounds, one active therapeutic target  
**Compute cost to partner:** $0  
*April 2026 · Draft for discussion*

---

## Executive Summary

BioMate is an AI-native drug discovery platform. A researcher describes a task — screen this compound set against a target, evaluate cardiac and liver safety, propose optimised analogues — and BioMate runs the full computational pipeline and returns results with a complete quality audit trail, in a single session.

This pilot evaluates whether BioMate can operate as a reliable computational research partner for a clinical medicine department: delivering correct, well-documented results without requiring bioinformatics expertise from the research team, and doing so fast enough to fit into a clinician-researcher's working day.

The pilot runs for 10 days (range 7–14) on 10–20 real compounds from an active or recently completed project at the Department of Medicine. Three hypotheses are tested. The deliverable is a QC audit log and an exportable methods report — ready for inclusion in a research record or manuscript.

---

## Background

Computational drug discovery has become essential to translational medicine. ADMET profiling, virtual screening, and lead optimisation can now be run on commodity cloud infrastructure using open-source tools. The remaining barrier for clinical research departments is not capability — it is access: the workflows require bioinformatics expertise and pipeline infrastructure that most medical departments do not have in-house.

BioMate removes that barrier. The platform orchestrates the computational pipeline automatically — tool selection, parameter configuration, quality gating, and result formatting — in response to plain language from the researcher. A physician-scientist can describe a therapeutic question and receive a structured, auditable computational result without writing a line of code.

This pilot tests whether that promise holds in practice for a real Department of Medicine use case.

---

## Hypotheses

The pilot is designed to produce a clear answer on three falsifiable claims:

**H1 — Workflow quality.** At least 80% of the compound analysis queries submitted during the pilot produce a complete, correct result without requiring manual parameter correction or re-submission.

*Measurement:* Platform telemetry tracking queries that complete without intervention versus queries that require correction. Denominator is all queries submitted during the pilot window.

**H2 — Time-to-result.** The average time from query submission to a complete, review-ready result is 30 minutes or less for a 10–20 compound ADMET + docking screen.

*Measurement:* Backend timestamp from query submission to result delivery. Compared against the department's estimate of how long the equivalent analysis currently takes by any existing method.

**H3 — QC defensibility.** At least 70% of results returned during the pilot are rated by the research team as scientifically defensible — meaning the quality thresholds applied are appropriate for a research manuscript and the audit trail is sufficient for a methods section.

*Measurement:* Researcher rating on a structured exit form completed at the end of the pilot. Five-point scale per session; defensible is defined as rating 4 or 5 ("publication-ready" or "publication-ready with minor edits").

---

## Pilot Scope and Dataset

**Target:** One protein with a published structure or high-confidence AlphaFold model from a current or recently active project at the Department. A defined binding site and one reference compound for docking validation are sufficient to begin.

**Compound library:** 10–20 small molecules. These can be:
- Compounds the department has previously tested, with known activity or toxicity data available as a ground truth
- Approved drugs being evaluated for repurposing against the target
- Candidate compounds from an ongoing discovery programme

**Reference data:** If available, any existing docking, ADMET, or assay results for these compounds — used to compare BioMate's output against the department's existing analysis, not as a requirement to participate.

---

## Study Design

The pilot runs across three structured arms over 10 days. Arms 1 and 2 run concurrently from Day 1; Arm 3 overlaps from Day 4 as results become available — eliminating the serial wait that inflates conventional pilot timelines. Each arm maps directly to one hypothesis and one KPI in the evaluation framework.

---

### Arm 1 — Workflow Quality (Phase 2, Days 3–7)

**What happens.** The research team submits queries covering the full pipeline: ADMET profiling of the compound set, docking against the target, and integrated ranking. Target: 5–8 sessions across Days 3–7 (one or two sessions per day, each taking ≤ 30 minutes). Sessions are conducted by the researchers themselves — not by BioMate engineers — to test real-world usability.

**What is measured.** For each query: did it complete without manual correction? If not, what type of correction was required (parameter error, tool failure, format issue, or ambiguous input)? Results are logged automatically.

**Success criterion.** ≥ 80% of queries complete without manual correction (H1 threshold).

**Zero hallucination standard.** BioMate must not issue commands for non-existent tools or use parameters with no valid values. This is a hard gate: any hallucinated command counts as a failure regardless of whether it was caught before execution. Target: 0 incidents.

---

### Arm 2 — Time-to-Result (Phase 2, Days 3–7, concurrent with Arm 1)

**What happens.** Every Arm 1 session automatically generates an Arm 2 data point — no separate sessions required. The time from query submission to result delivery is recorded for each run. At the end of Day 6, the research team provides a single estimate of how long the equivalent analysis would have taken by their existing process (manual search, outsourced core facility, or no prior process).

**What is measured.** Backend timestamp delta per session; self-reported baseline time from the research team.

**Success criterion.** Average time-to-result ≤ 30 minutes for a 10–20 compound ADMET + docking screen (H2 threshold).

---

### Arm 3 — QC Defensibility (Phase 3, Days 7–9)

**What happens.** From Day 7, results from Arms 1 and 2 are available for review as they are completed — no waiting for all sessions to finish. The research team reviews QC audit logs, quality gate decisions, and auto-generated methods reports as they accumulate, rating each on a five-point scale. The exit survey is completed on Day 9 to capture overall ratings across all sessions.

Where existing results are available for the same compounds, the research team compares BioMate's rankings against them and identifies where they agree, diverge, and whether any divergence would have changed an advancement decision.

**What is measured.** Exit survey ratings (five-point scale, per session reviewed). Concordance between BioMate rankings and existing results where ground truth is available.

**Success criterion.** ≥ 70% of sessions rated 4 or 5 on defensibility (H3 threshold).

---

## Division of Labor

| Task | Department | BioMate |
|---|---|---|
| Target structure and compound set (10–20 compounds) | ✓ | |
| Existing results for comparison (optional) | ✓ | |
| Researcher time for query submission (≤ 2 hrs/week) | ✓ | |
| Exit form completion at pilot end | ✓ | |
| Platform execution and cloud infrastructure | | ✓ |
| QC audit log and methods report generation | | ✓ |
| Compute costs | | ✓ |
| Data governance (platform Terms of Service via registration) | | ✓ |

**Pre-pilot commitments (BioMate, by Day 0 — agreed date before pilot begins):**
- Platform configured with the department's target and compound set
- ADMET profile set for the relevant disease area
- QC audit log export and methods report format confirmed with the research team

**Pre-pilot commitments (Department, by Day 0 — agreed date before pilot begins):**
- Pilot account registered on BioMate platform (user agreement completed at registration)
- Target structure and compound SMILES (10–20 compounds) shared via secure upload
- Designated point of contact for query submission and exit survey

---

## Timeline

The pilot runs for 10 days across three phases. Phase 1 is entirely internal — the partner invests no time until Phase 1 passes.

| Phase | Days | Activities | Partner Time |
|---|---|---|---|
| **Phase 1 — Internal Validation** | Days 1–2 | BioMate runs gold-standard validation checks on public data: docking RMSD vs PDB 7RFS (nirmatrelvir), pharmacophore AUC-ROC vs PDB 7KI0 (GLP-1R), mRNA CAI vs mRNA-1273, PKPD body weight vs SUSTAIN-1. Pass/fail report delivered to partner by end of Day 2. | 0 hrs |
| **Phase 2 — Workflow Quality + Time-to-Result** | Days 3–7 | Partner submits 5–8 ADMET + docking sessions on their compound set. Arms 1 and 2 run concurrently — every session simultaneously logs a workflow quality data point and a time-to-result data point. BioMate team available for onboarding questions on Day 3. | ~1 hr/day |
| **Phase 3 — QC Defensibility Review** | Days 7–9 | Partner reviews completed results from Phase 2. Rates each session on a five-point defensibility scale. Completes exit survey on Day 9. Concordance analysis against any existing results. | ~2 hrs total |
| **Debrief** | Day 10 | Results summary across all three hypotheses (H1/H2/H3); go/no-go for full collaboration; next steps agreed. | 1 hr |

**Phase 1 gate:** If Phase 1 validation fails on any check, BioMate fixes the issue before Phase 2 begins — the partner's time is never spent on a workflow BioMate cannot validate internally. This is the key risk control: the partner cannot be exposed to a broken pipeline.

**Critical path:** Phase 2 is the bottleneck. Five sessions across five days requires roughly one session per working day, each taking ≤ 30 minutes. The debrief occurs on Day 10 regardless of whether optional sessions 6–8 were completed.

---

## Deliverables

At the end of the 10-day pilot, the Department of Medicine receives:

1. **QC audit log** — a complete record of every query, every tool run, every quality gate outcome, and every analyst decision across all pilot sessions. Formatted for inclusion in a research record or regulatory submission.

2. **Exportable methods report** — a structured methods section for the computational analysis, ready to include in a manuscript without manual write-up. Tool versions, parameters, and evidence citations for each quality threshold included.

3. **Pilot evaluation summary** — H1, H2, and H3 outcomes against targets; concordance analysis against any existing results; comparison of time-to-result versus current department baseline. Delivered on Day 10.

4. **Go/no-go recommendation** — a joint assessment of whether BioMate is ready to support a full research collaboration, and what (if anything) would need to change before the full study begins.

---

## Data and Confidentiality

Compound structures and target identifiers shared for the pilot remain under the Department's governance at all times. BioMate processes data only within the agreed computational environment. No proprietary compound data is retained by BioMate after the pilot window closes. All session memory is exportable and deletable.

Data governance is covered by BioMate's Terms of Service, which researchers accept at platform registration. The Terms explicitly prohibit BioMate from using research data for model training or retaining compound data beyond the pilot window, and guarantee deletion within 14 days of pilot completion upon request.

---

## Path to Full Collaboration

A successful pilot is the entry point to a deeper research collaboration. The full study — which this pilot de-risks — would evaluate BioMate across a complete DMTA (Design-Make-Test-Analyse) campaign cycle, including CRO assay data integration, multi-objective Bayesian optimisation for next-round compound design, and drug MoA characterisation from patient RNA-seq. The outcome would be a jointly authored methods evaluation paper, with the Department's clinical context as the scientific anchor.

The full study design, timeline, and authorship arrangement will be agreed after the pilot debrief.

---

*April 2026 · BioMate AI · Draft for discussion with Zhejiang People's Hospital, Department of Medicine*
