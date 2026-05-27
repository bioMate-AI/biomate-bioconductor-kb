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

**ADMET prediction.** Commercial and open-source ADMET prediction tools (admetSAR, ADMETlab, SwissADME³) issue compound-level pass/fail flags against thresholds drawn from a heterogeneous literature: Aronov 2008 for hERG inhibition⁴, Lipinski's rule of five for absorption⁵, the Lammert/Andrade 2010 cumulative-dose rule for DILI⁶. The tool reports a binary classification; it does not report which rule was used, whether the rule is verbatim from the cited paper or a downstream paraphrase, or what change in chemical structure would shift the prediction. Compounds dropped at this gate disappear from the downstream library.

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

*[To be drafted after the user confirms domain reconciliation and E1/E2 data lands. See `00_outline.md`.]*

## 3. Results

*[Pending E1, E2, E3, E4.]*

## 4. Discussion

*[Pending §3.]*

---

## References (placeholder — to be expanded)

1. CryoSPARC Live (Punjani et al., *Nature Methods* 2017; Live release notes).
2. Warp (Tegunov & Cramer, *Nature Methods* 2019).
3. SwissADME, admetSAR, ADMETlab platform references.
4. Aronov AM. *Drug Discov Today* 2008.
5. Lipinski CA et al. *Adv Drug Deliv Rev* 2001.
6. Lammert et al. 2010; Andrade et al. — DILI cumulative-dose rule.
7. Zhang J-H, Chung TDY, Oldenburg KR. *J Biomol Screen* 1999 — Z′ factor.
8. EMA Guideline EMA/CHMP/458101/2016 (2019); FDA 2018 PBPK Guidance for Industry.
9. FDA 2024 draft guidance: AI/ML-based software as a medical device — lifecycle management considerations.
10. EMA 2024 reflection paper on AI in the medicinal product lifecycle.
