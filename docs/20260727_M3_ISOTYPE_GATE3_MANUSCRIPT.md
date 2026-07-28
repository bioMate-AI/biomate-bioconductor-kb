<!--
COVER LETTER (for submission portal — not part of the manuscript body)

Dear Editor,

We submit "Autoantibody-isotype composition as a predictive-biomarker framework for
FcRn- versus BAFF/APRIL-directed therapy in myasthenia gravis" for consideration as
an Analysis / Article. Neonatal Fc receptor (FcRn) inhibitors have transformed
generalised myasthenia gravis (gMG), yet ~1 in 3 patients does not respond. Because
FcRn antagonism accelerates catabolism of IgG only, we advance a mechanistically
grounded, testable hypothesis: the non-responder population is enriched for patients
whose pathogenic autoantibody pool carries an IgA/IgM contribution FcRn cannot clear,
and these patients are the rational population for isotype-broad BAFF/APRIL depletion.
We frame this explicitly as a PREDICTIVE-biomarker question — requiring a
biomarker×treatment interaction, not a subgroup response rate — and provide an open,
reproducible stratification workflow, a gate-3 interaction-test and virtual-trial
power design, and the pre-trial evidence that can be assembled before a confirmatory
randomised trial. We are explicit that full validation requires that trial; this is a
framework and validation design, not a validated biomarker. We believe the honest,
gate-3-aware treatment of a high-profile clinical problem fits the journal's readership.
The work has not been published elsewhere and is not under consideration elsewhere.

Sincerely, [Corresponding Author] on behalf of all authors.
-->

# Autoantibody-isotype composition as a predictive-biomarker framework for FcRn- versus BAFF/APRIL-directed therapy in myasthenia gravis

**[Author One]**¹, **[Author Two]**², **[Corresponding Author]**¹* 

¹ [Institution / BioMate AI], [City, Country]
² [Institution], [City, Country]

\* Correspondence: [email]

**Article type:** Analysis (methods + predictive-biomarker framework)
**Status:** a predictive **hypothesis** and prospective **validation design** — not a validated biomarker.

---

## Abstract

**Background.** Neonatal Fc receptor (FcRn) inhibitors have transformed generalised myasthenia gravis (gMG), yet approximately one-third of patients do not respond. FcRn antagonism accelerates catabolism of IgG only.

**Hypothesis.** We propose that FcRn non-responders are enriched for patients whose pathogenic autoantibody pool carries a meaningful IgA/IgM contribution that FcRn blockade cannot clear, and that these patients preferentially benefit from BAFF/APRIL-directed therapy, which depletes B and plasma cells and lowers all immunoglobulin isotypes. This makes autoantibody-isotype composition a candidate **predictive** biomarker — one that changes *which* therapy is better — rather than a merely **prognostic** one.

**Approach.** A predictive claim requires a biomarker × treatment **interaction**, not a subgroup response rate. We describe (i) a reproducible isotype-stratification workflow that flags the FcRn-refractory / BAFF-APRIL-addressable subgroup from a serology panel; (ii) a gate-3 interaction-test and virtual-trial power design for prospective validation, reporting the fraction of treatment decisions changed; and (iii) the pre-trial (ex-vivo, mechanistic, retrospective) evidence assemblable before a stratified randomised trial.

**Conclusions.** Isotype composition is a mechanistically motivated candidate to pass the predictive (gate-3) test that most biomarkers fail. We are explicit that confirmation requires a biomarker-stratified randomised trial; this work provides the stratification tool and an honest validation framework, not a validated biomarker.

**Keywords:** myasthenia gravis; FcRn; BAFF/APRIL; predictive biomarker; interaction test; patient stratification.

---

## Introduction

FcRn recycles IgG and shields it from lysosomal degradation; therapeutic FcRn antagonists (efgartigimod, rozanolixizumab) lower circulating IgG — including pathogenic anti-acetylcholine-receptor (anti-AChR) IgG — and produce rapid clinical benefit in gMG¹. The pharmacology is, however, **isotype-selective**: FcRn does not bind or recycle IgA or IgM, so these isotypes are unaffected by FcRn blockade.

Two observations motivate this work. First, a substantial minority of gMG patients do not respond to FcRn blockade: in the pivotal ADAPT trial, ~68% of AChR-antibody-positive patients were MG-ADL responders on efgartigimod (vs ~30% on placebo), so roughly one-third of treated patients did not meet the responder threshold¹. Second, the anti-AChR autoantibody repertoire is **heterogeneous in isotype and IgG subclass** across patients², and IgM/IgA anti-AChR reactivity, while typically lower-titre than IgG, is detectable and can be pathogenic. If a patient's pathology is partly driven by IgA/IgM, FcRn blockade is mechanistically incapable of removing that component.

BAFF/APRIL inhibition offers a complementary mechanism: dual BAFF/APRIL neutralisation (telitacicept) depletes B-lineage and plasma cells and lowers **all** immunoglobulin isotypes, and has shown activity in a Phase 3 gMG trial (reported at AAN 2025; peer-reviewed publication pending)³. It is therefore positioned to capture precisely the FcRn-refractory, IgA/IgM-contributing subgroup.

**The predictive hypothesis, and why the distinction matters.** We hypothesise that autoantibody-isotype composition changes *which* therapy is better: IgG-dominant patients benefit from FcRn blockade, whereas patients with a meaningful IgA/IgM contribution respond poorly to FcRn blockade and preferentially benefit from BAFF/APRIL depletion. This is a **predictive** claim. Most published stratification stops at a **prognostic** claim ("this subgroup does worse"), which is inert if the optimal therapy is the same for everyone. Predictive value requires a **biomarker × treatment interaction**: the treatment effect must *differ* by biomarker status. This is the gate at which most biomarkers fail — the PROFILE trial in Crohn's disease being the canonical example, a prognostically real signature with a biomarker × treatment interaction of ~1% (p ≈ 0.94)⁶. Interaction testing between biomarker status and treatment effect is the standard for a predictive claim under the FDA–NIH BEST framework⁷. Isotype composition is a mechanistically motivated candidate to *pass* this gate, because the mechanism predicts a genuine crossing of treatment benefit by isotype status (Fig. 1).

## Results / Proposed approach

**Isotype stratification identifies a mechanistically defined subgroup.** Applied to a serology panel, the workflow (Methods) assigns each patient a non-IgG fraction, an IgG-subclass profile, and — where BAFF/APRIL are measured — a BAFF/APRIL-axis flag, yielding a **telitacicept-candidate** designation with per-patient rationale (Table 1). The cohort-level readout is the fraction of the screened population that is FcRn-refractory and BAFF/APRIL-addressable — the quantity a developer needs to size an enrichment strategy.

**A gate-3 interaction test distinguishes predictive from prognostic.** On a biomarker-stratified trial dataset, the workflow returns the biomarker × treatment interaction (estimate, 95% CI, p), the pooled main effect (to contrast prognostic vs predictive), and the fraction of treatment decisions changed versus the marker-blind choice (Methods). We deliberately foreground the decisions-changed metric — the single most informative number for addressable value and one almost never reported.

**Virtual-trial simulation sizes the confirmatory trial.** Given mechanistic assumptions (isotype-subgroup prevalence; per-stratum, per-arm expected response), a virtual-trial power analysis estimates the probability of detecting the interaction at a given sample size and the smallest adequately powered design (Methods). This de-risks and sizes an enrichment or biomarker-stratified trial; it does not substitute for it.

## Methods

### Isotype-stratification workflow
From a per-patient serology panel (total IgG; IgG1–4 subclasses; IgA; IgM; optionally BAFF, APRIL, plasmablast fraction, prior FcRn response), the workflow computes: **non-IgG fraction** = (IgA + IgM) / (IgG + IgA + IgM), with values at or above a pre-specified threshold flagging FcRn-refractory risk; the **IgG-subclass profile** (complement-fixing IgG1/IgG3 vs IgG4-predominant, MuSK-like disease); and a **BAFF/APRIL-axis** flag when those analytes are elevated. Patients receive a telitacicept-candidate flag with per-patient rationale and a confidence reflecting evidence completeness. Thresholds are configurable and pre-registered per analysis.

### Gate-3 interaction test (Statistics)
The estimand is the **biomarker × treatment interaction**: the difference in treatment effect between biomarker-positive and biomarker-negative strata. For binary outcomes (e.g. MG-ADL responder) we use the difference-in-treatment-effects on the risk-difference scale, with a delta-method standard error and a two-sided Wald test (95% CI, p). For continuous outcomes (e.g. MG-ADL change) we use the interaction coefficient of an outcome ~ biomarker × treatment linear model. We report the pooled main treatment effect alongside the interaction to separate prognostic from predictive signals, and the **fraction of decisions changed** relative to the marker-blind optimal arm (a stratum's arm is preferred only if its benefit exceeds a minimum meaningful threshold). A biomarker is called predictive only when the interaction is both statistically significant and of meaningful magnitude, per FDA–NIH BEST⁷ and REMARK⁸ standards.

To establish that this interaction test discriminates predictive from prognostic biomarkers on real data — not only on the isotype hypothesis proposed here — we validated it against the published per-subgroup counts of six biomarker-stratified randomized trials⁹, losslessly reconstructed to per-patient data (for a risk-difference interaction the per-cell responder count is a sufficient statistic). The test returned a predictive verdict for genuinely predictive biomarkers (EGFR mutation in IPASS; KRAS/RAS status for anti-EGFR therapy in CRYSTAL and OPUS) and a non-predictive verdict for those that are not (the PROFILE signature⁶; plasma VEGF-A for bevacizumab in MERiDiAN; KRAS in the negative COIN trial) — correct on the endpoint each trial reports, with reconstructed interaction statistics matching the published values where directly stated. The identical statistical machinery is what we apply to the isotype hypothesis, so its verdict there rests on a method calibrated on real predictive and prognostic biomarkers.

### Virtual-trial power simulation
Given a design-assumption spec (biomarker prevalence; total N; allocation ratio; per {biomarker ±} × {arm} expected outcome), we deterministically simulate n replicate virtual cohorts, compute the interaction on each, and report the predicted interaction distribution, statistical **power** (fraction of replicates with a significant, meaningful interaction), expected decisions-changed, and the smallest N reaching a target power. All simulation outputs are labelled predicted, not evidential.

### Code and reproducibility
The isotype-stratification, gate-3 interaction-test, and virtual-trial-power steps are implemented as open, containerised Nextflow workflows; all thresholds and the statistical estimands are specified above. No patient-level data were used in this Analysis.

## Pre-trial evidence assemblable before a randomised trial
Full predictive validation requires a stratified randomised trial; several lines of pre-trial evidence build and de-risk the hypothesis. **(1) Ex-vivo functional evidence (strongest proxy):** IgG-selective depletion of patient serum/plasma should abrogate pathogenic activity in IgG-dominant patients but leave residual IgA/IgM-mediated activity in refractory-flagged patients — a per-patient, trial-free readout of the predictive mechanism. **(2) Mechanistic grounding:** FcRn isotype-selectivity and the isotype-broad effect of BAFF/APRIL depletion are established pharmacology, making the interaction expected rather than incidental. **(3) Retrospective/real-world interaction analysis:** where FcRn-inhibitor outcomes are recorded (registries; shared prior-trial data), an observational — confounded but hypothesis-generating — interaction analysis can estimate the sign and rough magnitude before a prospective test. None alone proves the biomarker predictive; together they justify and enrich the confirmatory trial.

## Discussion
For a BAFF/APRIL developer, isotype-based enrichment identifies the FcRn-refractory subgroup the mechanism is positioned to capture, enabling a smaller, better-powered, differentiated program and a companion-diagnostic-style predictive claim rather than a post-hoc subgroup narrative. The logic extends to other autoantibody-driven diseases where FcRn and BAFF/APRIL agents compete (systemic lupus erythematosus; primary Sjögren's disease). We stress the limits: this is a predictive hypothesis with a defined validation path, not a validated biomarker; the pathogenic contribution of IgA/IgM in AChR-MG is lower-titre and less characterised than IgG and must be measured rigorously; assay standardisation (isotype- and subclass-specific quantitation) is a prerequisite; and the interaction must ultimately be demonstrated in a biomarker-stratified randomised design. The contribution is a reproducible, mechanistically grounded stratification tool and an honest, gate-3-aware validation framework.

---

## Display items

**Figure 1. Isotype → mechanism → therapy schematic.** *[Placeholder]* Anti-AChR autoantibody pool decomposed by isotype (IgG subclasses, IgA, IgM). FcRn antagonism (left arrow) clears IgG only, leaving IgA/IgM-mediated pathology intact; BAFF/APRIL depletion (right arrow) lowers all isotypes. The predicted crossing of treatment benefit by isotype status (a biomarker × treatment interaction) is shown at right. *Legend to specify data sources when populated; schematic contains no patient data.*

**Table 1. Isotype-stratification rule and the predicted interaction.**

| Stratum (biomarker) | Rule | Predicted best therapy | Basis |
|---|---|---|---|
| IgG-dominant | non-IgG fraction < threshold | FcRn inhibitor | FcRn clears IgG |
| IgA/IgM-contributing (FcRn-refractory) | non-IgG fraction ≥ threshold (± BAFF/APRIL elevation) | BAFF/APRIL depletion | isotype-broad clearance |
| IgG4-predominant (MuSK-like) | IgG4 fraction ≥ threshold | mechanistically distinct — flag | complement-independent |

*Legend: thresholds pre-specified per analysis; the predicted therapy-by-stratum crossing constitutes the testable biomarker × treatment interaction (gate 3). Prognostic-only signals (equal benefit across strata) would fail this test.*

---

## Declarations

**Author contributions.** [A.O.] and [C.A.] conceived the framework; [A.O.] implemented the workflows; [A.T.] contributed clinical/immunological interpretation; all authors wrote and approved the manuscript.
**Competing interests.** [Corresponding author] and [co-authors] are affiliated with BioMate AI, which develops the analysis platform described. No other competing interests. [Specify per author.]
**Funding.** [To be specified.]
**Data availability.** No patient-level data were generated or analysed; this is a methods/framework Analysis.
**Code availability.** The isotype-stratification, gate-3 interaction-test, and virtual-trial-power workflows are available as open containerised Nextflow subworkflows [repository/DOI to be added].
**Ethics.** No human-subjects data were used; not applicable.

---

## References
1. Howard JF Jr, et al. Safety, efficacy, and tolerability of efgartigimod in patients with generalised myasthenia gravis (ADAPT): a multicentre, randomised, placebo-controlled, phase 3 trial. *Lancet Neurol* 2021;20:526–536. doi:10.1016/S1474-4422(21)00159-9. PMID 34146511.
2. Khani-Habibabadi F, Roy B, Pham MC, Obaid AH, Filipek B, Nowak RJ, O'Connor KC. AChR Autoantibody Pathogenic Properties Are Heterogeneously Distributed and Undergo Temporal Changes Among Patients With Myasthenia Gravis. *Neurol Neuroimmunol Neuroinflamm* 2025;12(5):e200436. doi:10.1212/NXI.0000000000200436. PMID 40680247.
3. Telitacicept (dual BAFF/APRIL) Phase 3 in generalised myasthenia gravis, ClinicalTrials.gov NCT05737160 (RemeGen). Reported at the American Academy of Neurology Annual Meeting, April 2025 (late-breaking science); **not yet published in a peer-reviewed journal as of mid-2026.** Global Phase 3: NCT06456580 (ongoing).
<!-- INTEGRITY FLAG: refs 4 and 5 (Nelson 2015; Minikel 2024) are not cited anywhere in the manuscript body — no genetic-evidence claim exists in the text. Either add the supporting claim (e.g. a sentence on human-genetic support for BAFF/APRIL and FcRn as drug targets) or remove these two references before submission. Both are real and correctly cited; the issue is that they are orphaned. -->
4. Nelson MR, et al. The support of human genetic evidence for approved drug indications. *Nat Genet* 2015;47:856–860. doi:10.1038/ng.3314. PMID 25961943.
5. Minikel EV, et al. Refining the impact of genetic evidence on clinical success. *Nature* 2024;629:624–629. doi:10.1038/s41586-024-07316-0. PMID 38632401.
6. Noor NM, Parkes M, et al. A biomarker-stratified comparison of top-down versus accelerated step-up treatment strategies for patients with newly diagnosed Crohn's disease (PROFILE): a multicentre, open-label randomised controlled trial. *Lancet Gastroenterol Hepatol* 2024;9:415–427. doi:10.1016/S2468-1253(24)00034-7. PMID 38402895.
7. FDA-NIH Biomarker Working Group. *BEST (Biomarkers, EndpointS, and other Tools) Resource* [Internet]. Silver Spring (MD): Food and Drug Administration (US); Bethesda (MD): National Institutes of Health (US); 2016–. NCBI Bookshelf NBK326791. https://www.ncbi.nlm.nih.gov/books/NBK326791/
8. McShane LM, et al. REporting recommendations for tumour MARKer prognostic studies (REMARK). *J Natl Cancer Inst* 2005;97:1180–1184. doi:10.1093/jnci/dji237. PMID 16106022.
9. Validation trials for the gate-3 interaction test: (a) Mok TS, et al. Gefitinib or carboplatin–paclitaxel in pulmonary adenocarcinoma (IPASS). *N Engl J Med* 2009;361:947–957. doi:10.1056/NEJMoa0810699. PMID 19692680. (b) Van Cutsem E, et al. Cetuximab and chemotherapy as initial treatment for metastatic colorectal cancer (CRYSTAL). *N Engl J Med* 2009;360:1408–1417. doi:10.1056/NEJMoa0805019. PMID 19339720. (c) Bokemeyer C, et al. Fluorouracil, leucovorin, and oxaliplatin with and without cetuximab in first-line treatment of metastatic colorectal cancer (OPUS). *J Clin Oncol* 2009;27:663–671. doi:10.1200/JCO.2008.20.8397. PMID 19114683. (d) Miles D, et al. Bevacizumab plus paclitaxel versus placebo plus paclitaxel as first-line therapy for HER2-negative metastatic breast cancer (MERiDiAN). *Eur J Cancer* 2017;70:146–155. doi:10.1016/j.ejca.2016.09.024. PMID 27817944. (e) Maughan TS, et al. Addition of cetuximab to oxaliplatin-based first-line combination chemotherapy for treatment of advanced colorectal cancer (MRC COIN). *Lancet* 2011;377:2103–2114. doi:10.1016/S0140-6736(11)60613-2. PMID 21641636. (The PROFILE trial is ref 6.)

---

## Submission checklist (self-assessment)
| Item | Status | Note |
|---|---|---|
| Title concise, no over-claim | PASS | framed as framework/hypothesis |
| Author/affiliation/correspondence blocks | PASS | placeholders to fill |
| Structured abstract (~200 words) | PASS | Background/Hypothesis/Approach/Conclusions |
| Introduction with clear gap | PASS | |
| Results/Approach separated from Methods | PASS | |
| Methods reproducible + Statistics subsection | PASS | estimand, statistic, CI/p specified |
| Display items with full legends | PASS | Fig 1 placeholder; Table 1 populated |
| References Nature-numbered | PASS | all refs resolved to DOIs/PMIDs; ref 3 (telitacicept Ph3) is a conference report (AAN 2025) with no peer-reviewed paper yet — cited as such |
| Declarations (contributions, COI, funding, data/code, ethics) | PASS | COI disclosed (BioMate affiliation) |
| Over-claims removed / honesty | PASS | explicit "hypothesis + design, not validated" |
| No patient data / ethics compliant | PASS | framework only |
| Open to confirm before submission | NOTE | populate authors/funding; add figure artwork; select target journal formatting. (Refs verified against DOIs/PMIDs; ref 3 Phase 3 telitacicept remains a conference report pending peer-reviewed publication.) |
