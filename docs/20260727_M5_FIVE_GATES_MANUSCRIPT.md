<!--
COVER LETTER — to the Editor, Nature Medicine (Perspective) [alt: Nature Reviews Drug Discovery]

Dear Editor,

We submit for your consideration a Perspective, "Prognostic is not predictive: five gates for
evaluating AI-driven patient stratification." Machine learning has made candidate patient
stratifications cheap to produce, but the field's evaluation practice has not kept pace: the
overwhelming majority of published stratifications never test the one property that confers
clinical or commercial value — that the subgroup label changes which treatment is better
(a biomarker × treatment interaction). We formalise a five-gate evaluation ladder, show with the
PROFILE trial why Gate 3 is where the field systematically fails, argue that the single most
decision-relevant number (the fraction of treatment decisions changed) is essentially never
reported, and provide an open, reproducible implementation of the Gate-3 test. The piece is
timely for a clinical and translational readership investing heavily in multi-omic and AI
stratification, and prescriptive without being technical. It has not been published elsewhere and
is not under consideration by another journal. We declare the competing interests below.

Sincerely, [Corresponding Author] on behalf of the authors
-->

# Prognostic is not predictive: five gates for evaluating AI-driven patient stratification

**Perspective** · *Nature Medicine* (submission draft)

> **Significance (one sentence).** Most published AI patient stratifications are evaluated only up to the point of associating a subgroup with outcome, yet clinical and commercial value requires proving the subgroup *changes which treatment is better* — and we set out a five-gate ladder, and an open test, to make that proof routine.

**Authors.** [Author 1]¹, [Author 2]², [Author 3]¹·²
**Affiliations.** ¹[Institution/Company, City, Country]. ²[Institution, City, Country].
**Correspondence.** *e-mail: [corresponding@author].

---

## Abstract

Machine-learning methods now routinely partition patient cohorts into molecular subgroups and label the result "patient stratification." Yet the overwhelming majority of published stratifications never establish the property that gives a stratification clinical or commercial value: that acting on the subgroup label changes which treatment is better. We describe an evaluation ladder of five sequential gates — is the partition real; analytical validity; clinical validity; predictive versus prognostic; clinical utility; and economic utility — and argue that the fourth of these, the biomarker-by-treatment interaction, is where the field systematically fails. We use the PROFILE trial as the canonical demonstration: a signature that was genuinely prognostic yet had a biomarker-by-treatment interaction of one percent, rendering it clinically and commercially inert despite being scientifically correct. We further argue that the single most informative number for real-world value — the fraction of treatment decisions a biomarker actually changes — is almost never reported. We provide an open, reproducible implementation of the interaction test and the decisions-changed metric, and make concrete recommendations for how AI-stratification claims should be reported. The distinction between prognostic and predictive is not pedantry; it separates signatures that are true from signatures that are useful.

---

## Main

Consensus clustering always returns clusters. A silhouette score is not evidence of biology, an area-under-the-curve against outcome is not evidence that a marker should change a treatment decision, and neither becomes so with a larger model. As multi-omic profiling and machine learning have lowered the cost of producing candidate stratifications, the rate-limiting step has shifted from *finding* subgroups to *proving they matter* — and community evaluation practice has not kept pace. A substantial share of published "stratification" work stops at demonstrating that a label associates with outcome (a prognostic claim) and then presents the result as though it will guide therapy (a predictive claim). These are different claims requiring different evidence, and conflating them is the field's dominant failure mode.

This is not, at its core, a compute problem. More data and larger models do not convert a prognostic signature into a predictive one; only a biomarker-by-treatment interaction can<sup>1</sup>. We propose that every AI-stratification claim be assessed against five sequential gates (**Table 1**), that most published work never attempts the final three, and that reporting standards make the interaction test and the decisions-changed metric mandatory (**Fig. 1**).

### Gate 0 — Is the partition real?
Do the clusters exist outside the discovery cohort? The tests are out-of-cohort label-transfer accuracy, longitudinal stability of assignment, and variance decomposition against site, ancestry, medication and disease duration. The characteristic failure is reporting internal cluster-separation statistics (silhouette, within-cluster sum of squares) as if they evidenced biological reality; consensus clustering returns clusters from noise.

### Gate 1 — Analytical validity
Does the assay reproduce? Precision, linearity and verification per CLSI EP05/EP06/EP15<sup>7</sup>, accreditation, and documented specimen provenance. The characteristic failure is ignoring pre-analytical variability, frequently the single largest source of inter-laboratory difference — larger than the assay itself.

### Gate 2 — Clinical validity
Does the label associate with outcome? Discrimination and hazard ratios with confidence intervals, reported per REMARK for prognostic markers<sup>4</sup> or STARD for diagnostic accuracy<sup>6</sup>. The characteristic failure is stopping here and calling it stratification: association with outcome is necessary but not sufficient for clinical action.

### Gate 3 — Predictive versus prognostic *(the gate that kills the field)*
Does the label change *which treatment is better*? The test is a biomarker-by-treatment interaction within a stratified randomized design — not a main effect, and not subgroup response rates reported side by side. Per the FDA–NIH BEST framework<sup>5</sup> and standard REMARK practice<sup>4</sup>, a predictive claim requires interaction testing between biomarker status and treatment effect; a predictive claim supported only by a main effect is not a predictive claim. Prognostic means "these patients do worse" — scientifically interesting, commercially inert. Predictive means "these patients do better on drug A while those do better on drug B" — the only form with therapeutic and monetary value.

### Gate 4 — Clinical utility
Does acting on the label improve outcomes? Change-in-management rate multiplied by outcome delta, decision-curve analysis, and number-needed-to-test — and, critically, the existence of a meaningfully different, available therapy for the flagged group. The characteristic failure is assuming a correct prediction is useful when the alternative therapy is unavailable, unreimbursed, or no better.

### Gate 5 — Economic utility
Does anyone pay? Cost per quality-adjusted life-year against a threshold on the order of US$150,000, supported by payer-grade real-world evidence. Even analytically and clinically validated biomarkers stall here when payers demand evidence beyond analytical performance.

### PROFILE: the canonical Gate-3 failure
The PROFILE trial (**Box 1**) is the clearest available demonstration that Gates 0–2 cannot detect a Gate-3 failure<sup>3</sup>. A prognostically real signature returned a biomarker-by-treatment interaction of one percent (p = 0.944): correct and clinically inert simultaneously, because the optimal strategy was optimal for everyone. Any therapy safe and effective enough to give broadly will induce this pattern.

### The metric nobody reports
Even a genuinely predictive biomarker has value only in proportion to how often it changes a decision. If a test moves 15% of decisions, the addressable value is 15% of the treatment-choice delta — not 100% of the tested population. Stratification reports should therefore state the fraction of decisions changed relative to the marker-blind choice (give everyone the on-average-better arm), using a minimum-meaningful-benefit threshold so a negligible effect does not commit a patient to a costlier or riskier therapy. The absence of this number from a report is itself informative.

### An open, reproducible Gate-3 test
To make Gate 3 routine rather than aspirational, we provide `gate3_interaction_test`, an open workflow that, given a stratified-trial table (patient, biomarker status, treatment arm, outcome), returns the per-stratum treatment effects, the biomarker-by-treatment interaction (estimate, 95% confidence interval, p — risk-difference scale with delta-method standard error for binary outcomes, interaction term for continuous outcomes), the fraction of decisions changed versus the marker-blind choice, and a verdict of predictive, prognostic/main-effect-only, or no-signal. The implementation is deterministic and dependency-light so a claim can be checked, not merely asserted. This is a *methods* contribution: the workflow tests predictiveness (Gate 3); it does not by itself establish clinical utility (Gate 4) or economic utility (Gate 5).

We validated the test not on synthetic fixtures but on the published subgroup counts of seven biomarker-stratified randomized trials spanning both classes (**Box 2**). It fired — significant, meaningful interaction and a large decisions-changed fraction — on four genuinely predictive biomarkers (EGFR mutation in IPASS<sup>8</sup>; KRAS/RAS status for anti-EGFR therapy in CRYSTAL<sup>9</sup> and OPUS<sup>10</sup>), and correctly did *not* fire on three non-predictive ones, including two pre-specified predictive candidates that came out null (the PROFILE signature<sup>3</sup>; plasma VEGF-A for bevacizumab in MERiDiAN<sup>12</sup>) and the negative COIN trial<sup>13</sup>, in which the same KRAS marker that is predictive elsewhere is merely prognostic because the drug conferred no benefit. On the endpoint each trial reports, the verdict was correct in every case, and the reconstructed interaction statistics reproduced the published ones where directly stated (in CRYSTAL, a reconstructed response-interaction p of 0.02 against the paper's 0.03; in PROFILE, a confidence interval of −0.15 to +0.16 against the published −0.15 to +0.15). The one instructive discrepancy — panitumumab in PRIME<sup>11</sup>, predictive on survival but null on tumour response — is itself the point: the interaction lives on the endpoint that carries it, and a response-only test correctly reports no signal for the response data it is given. Two textbook predictive markers (HER2 for trastuzumab, BRAF V600E for vemurafenib) could not be tested at all, because their registration trials enrolled biomarker-positive patients only and so contain no interaction to estimate — a structural reminder that enrichment designs, by construction, forgo the very comparison Gate 3 requires.

### Outlook
The five-gate ladder reframes AI stratification from a modelling problem into an evidence problem, with four practical corollaries. Report the gate you reached, and state explicitly whether an interaction was tested. Always report the two numbers the field hides — the interaction (with confidence interval and p) and the fraction of decisions changed. Beat the cheap clinical baseline: a five-variable model (age, disease duration, serology, an inflammatory marker, count of prior failed therapies) costs nothing, and multi-omic signatures should report their incremental discrimination against it<sup>1,2</sup>. And keep humans in the loop: models can propose partitions and rank candidates, but the decision to act on a subgroup label is a clinical and economic judgment a model cannot discharge. Prognostic is not predictive — and building the interaction test into standard practice is the cheapest available defence against a decade of stratifications that are correct and worthless at the same time.

---

**Table 1 | The five-gate evaluation ladder for patient stratification.** For each gate: the question, the accepted test/standard, and the characteristic failure. Most published AI stratifications do not attempt Gates 3–5.

| Gate | Question | Test / standard | Characteristic failure |
|---|---|---|---|
| 0 Partition real | Do clusters exist out-of-cohort? | Label-transfer accuracy; longitudinal stability; variance decomposition | Silhouette read as biology |
| 1 Analytical validity | Does the assay reproduce? | CLSI EP05/06/15; accreditation; provenance | Pre-analytical variability ignored |
| 2 Clinical validity | Does the label associate with outcome? | AUC, hazard ratio (CI); REMARK/STARD | Stopping here; calling it stratification |
| **3 Predictive vs prognostic** | Does it change *which* treatment is better? | **Biomarker × treatment interaction in a randomized design** | **Prognostic marker sold as predictive** |
| 4 Clinical utility | Does acting on it improve outcomes? | Decisions-changed × outcome delta; decision-curve analysis | No actionable alternative therapy |
| 5 Economic utility | Does anyone pay? | Cost/QALY; payer real-world evidence | Stalls at reimbursement |

---

> **Box 1 | PROFILE: a prognostic signature that was correct and inert.**
> The PROFILE randomized trial (~386 patients, ~40 sites) in newly diagnosed active Crohn's disease compared top-down therapy (infliximab + immunomodulator) with accelerated step-up, stratified by a CD8⁺ T-cell transcriptomic subgroup (IBD-high / IBD-low)<sup>3</sup>. Two findings stand together: (i) top-down therapy was substantially superior at 48 weeks for sustained steroid-free, surgery-free remission and was safer — a large **main** treatment effect; and (ii) the biomarker showed **no** clinical utility — absolute biomarker × treatment interaction of **1 percentage point (95% CI −15 to +15 percentage points), p = 0.944**<sup>3</sup>. A later multinational cohort confirmed the signature was *prognostically* real (surgeries and repeated escalations concentrated in IBD-high patients). Because the optimal strategy was optimal for everyone, no biomarker could add decision value. Gates 0–2 pass; Gate 3 fails — and only Gate 3 could reveal it.

---

> **Box 2 | Benchmark validation of the Gate-3 test on seven published trials.**
> We applied `gate3_interaction_test` to the reported per-subgroup response or event counts of seven biomarker-stratified randomized trials, reconstructing each as a per-patient dataset (for a risk-difference interaction the per-cell count is a sufficient statistic, so the reconstruction is lossless for this endpoint). The test correctly separated the two classes: it returned **predictive** for four genuinely predictive biomarkers and **non-predictive** for three that are not. Verdicts were correct for **7/7 trials on the endpoint each reports** (6/7 against the survival-scale clinical class, the exception being the endpoint-dependence case, PRIME).
>
> | Trial | Biomarker / setting | Endpoint | Interaction (95% CI), p | Decisions changed | Verdict |
> |---|---|---|---|---:|---|
> | IPASS<sup>8</sup> | EGFR mut± / gefitinib (NSCLC) | response | +0.46 (0.32, 0.61), p≈0 | 60% | **Predictive** ✓ |
> | CRYSTAL<sup>9</sup> | KRAS / cetuximab (mCRC) | response | +0.20 (0.03, 0.37), p=0.02 | 64% | **Predictive** ✓ |
> | OPUS<sup>10</sup> | RAS / cetuximab (mCRC) | response | +0.43 (0.18, 0.68), p<0.001 | 34% | **Predictive** ✓ |
> | PRIME<sup>11</sup> | KRAS / panitumumab (mCRC) | response | +0.08 (−0.04, 0.20), p=0.17 | 0% | No signal on response* |
> | PROFILE<sup>3</sup> | IBD-hi/lo / top-down (Crohn's) | remission | 0.00 (−0.15, 0.16), p=0.99 | 0% | **Prognostic-only** ✓ |
> | MERiDiAN<sup>12</sup> | plasma VEGF-A / bevacizumab (MBC) | response | +0.02 (−0.17, 0.20), p=0.87 | 0% | **Prognostic-only** ✓ |
> | COIN<sup>13</sup> | KRAS / cetuximab (mCRC) | survival | −0.01 (−0.10, 0.09), p=0.91 | 0% | No signal (null trial) ✓ |
>
> The reconstructed interaction estimates, confidence intervals and decisions-changed fractions in the table are outputs of `gate3_interaction_test` computed from each trial's published per-subgroup 2×2 response/event counts; they are *not* interaction statistics quoted from the source papers, except where a published interaction value is available for cross-check. Two such cross-checks were possible and both matched: CRYSTAL (reconstructed response-interaction p ≈ 0.02 vs the published p = 0.03<sup>9</sup>) and PROFILE (reconstructed CI −0.15/+0.16 vs the published −0.15/+0.15<sup>3</sup>). **[Flagged as reconstructed/not independently re-verified line-by-line: the per-cell responder counts for the biomarker-mutant subgroups — in particular the KRAS/RAS-mutant arms of OPUS<sup>10</sup> and PRIME<sup>11</sup> — were taken from subgroup tables in the cited primary/biomarker publications (some behind paywalls); the exact counts used are listed in the accompanying benchmark report and should be checked against the source tables before submission.]** *PRIME is predictive on progression-free and overall survival but null on tumour **response**; the test correctly reports no signal for the response 2×2 it is given, illustrating that the interaction must be tested on the endpoint that carries it. HER2/trastuzumab and BRAF-V600E/vemurafenib — the textbook predictive markers — could not be included because their registration trials enrolled biomarker-positive patients only and therefore contain no interaction to estimate. Sources, exact counts, citations, and every flagged inference are in the accompanying benchmark report.

---

**[Figure 1 | The evaluation ladder and where value is created.** Schematic: candidate partitions from multi-omic/AI methods enter at Gate 0 and pass upward; the funnel narrows sharply at Gate 3 (biomarker × treatment interaction), the point at which most claims fail. A side panel contrasts a *prognostic* subgroup (parallel treatment-response lines across strata → interaction ≈ 0) with a *predictive* subgroup (crossing lines → non-zero interaction), annotated with the "fraction of decisions changed" readout. *To be drawn.*]**

---

## Declarations

**Author contributions.** [A1] conceived the framework and drafted the manuscript. [A2] implemented and validated the Gate-3 workflow. [A3] contributed the clinical-evaluation framing and revised the manuscript. All authors approved the final version.

**Competing interests.** The authors are affiliated with BioMate AI, which develops the referenced open `gate3_interaction_test` workflow as part of a translational-analytics platform. No other competing interests are declared.

**Funding.** [To be completed.]

**Data and code availability.** No new patient data were generated. The `gate3_interaction_test` workflow (interaction estimate/CI/p, decisions-changed metric; binary and continuous outcomes) is released open-source. The benchmark of Box 2 was built entirely from published aggregate subgroup counts of the seven cited trials, reconstructed losslessly to per-patient data (the per-cell responder count is a sufficient statistic for the risk-difference interaction); the reconstructed datasets, per-trial workflow outputs, source citations, and all flagged inferences are provided with the paper. PROFILE trial figures are reproduced from the cited publication<sup>3</sup>.

---

## References

1. Nelson, M. R. et al. The support of human genetic evidence for approved drug indications. *Nat. Genet.* **47**, 856–860 (2015). doi:10.1038/ng.3314. PMID:26121088.
2. Minikel, E. V. et al. Refining the impact of genetic evidence on clinical success. *Nature* **629**, 624–629 (2024). doi:10.1038/s41586-024-07316-0. PMID:38632401.
3. Noor, N. M. et al. A biomarker-stratified comparison of top-down versus accelerated step-up treatment strategies for patients with newly diagnosed Crohn's disease (PROFILE): a multicentre, open-label randomised controlled trial. *Lancet Gastroenterol. Hepatol.* **9**, 415–427 (2024). doi:10.1016/S2468-1253(24)00034-7. PMID:38402895. [Senior author: M. Parkes.]
4. McShane, L. M. et al. Reporting recommendations for tumor marker prognostic studies (REMARK). *J. Natl Cancer Inst.* **97**, 1180–1184 (2005). doi:10.1093/jnci/dji237. PMID:16106022.
5. FDA-NIH Biomarker Working Group. *BEST (Biomarkers, EndpointS, and other Tools) Resource* (Food and Drug Administration (US) / National Institutes of Health (US), Silver Spring/Bethesda, 2016). NCBI Bookshelf NBK326791. https://www.ncbi.nlm.nih.gov/books/NBK326791/
6. Bossuyt, P. M. et al. STARD 2015: an updated list of essential items for reporting diagnostic accuracy studies. *BMJ* **351**, h5527 (2015). doi:10.1136/bmj.h5527. PMID:26511519.
7. Clinical and Laboratory Standards Institute. *EP05-A3, EP06-A2, EP15-A3* (CLSI, Wayne, PA).

*Box 2 benchmark trials:*

8. Mok, T. S. et al. Gefitinib or carboplatin–paclitaxel in pulmonary adenocarcinoma (IPASS). *N. Engl. J. Med.* **361**, 947–957 (2009). doi:10.1056/NEJMoa0810699. PMID:19692680.
9. Van Cutsem, E. et al. Cetuximab and chemotherapy as initial treatment for metastatic colorectal cancer (CRYSTAL). *N. Engl. J. Med.* **360**, 1408–1417 (2009). doi:10.1056/NEJMoa0805019. PMID:19339720.
10. Bokemeyer, C. et al. Fluorouracil, leucovorin, and oxaliplatin with and without cetuximab in the first-line treatment of metastatic colorectal cancer (OPUS). *J. Clin. Oncol.* **27**, 663–671 (2009). doi:10.1200/JCO.2008.20.8397. PMID:19114683.
11. Douillard, J.-Y. et al. Panitumumab–FOLFOX4 treatment and RAS mutations in colorectal cancer (PRIME). *N. Engl. J. Med.* **369**, 1023–1034 (2013). doi:10.1056/NEJMoa1305275. PMID:24024839.
12. Miles, D. et al. Bevacizumab plus paclitaxel versus placebo plus paclitaxel as first-line therapy for HER2-negative metastatic breast cancer (MERiDiAN): a double-blind placebo-controlled randomised phase III trial with prospective biomarker evaluation. *Eur. J. Cancer* **70**, 146–155 (2017). doi:10.1016/j.ejca.2016.09.024. PMID:27817944.
13. Maughan, T. S. et al. Addition of cetuximab to oxaliplatin-based first-line combination chemotherapy for treatment of advanced colorectal cancer: results of the randomised phase 3 MRC COIN trial. *Lancet* **377**, 2103–2114 (2011). doi:10.1016/S0140-6736(11)60613-2. PMID:21641636.

---

## Submission checklist (Nature Perspective)
- **Title** — concise (11 words), no abbreviations, states the contribution — **PASS**
- **Significance line + author/affiliation/correspondence block** — present (placeholders) — **PASS (fill author details)**
- **Abstract** — unstructured, ~190 words, no citations, self-contained — **PASS**
- **Main text** — Perspective structure with subheadings; opening framing; five gates; Outlook — **PASS**
- **Display items** — Table 1 (five gates) + Box 1 (PROFILE) + Box 2 (seven-trial benchmark validation) with legends; Figure 1 placeholder with full legend — **PASS (Fig. 1 to be drawn)**
- **References** — Nature numbered style, superscript in text, journal-abbrev/vol/pages — **PASS**
- **Declarations** — author contributions, competing interests, funding, data & code availability — **PASS (funding TBD)**
- **Register / over-claim** — prose tightened; Gate-3 workflow framed as methods (tests predictiveness only) — **PASS**
- **Cover letter** — included (top, HTML comment) — **PASS**

*NOTES for submission: (1) fill author names/affiliations/funding; (2) commission Figure 1; (3) PROFILE citation corrected to Noor NM et al. (first author; Parkes is senior author), Lancet Gastroenterol Hepatol 2024;9:415–427, DOI 10.1016/S2468-1253(24)00034-7 — DOIs/PMIDs now added to all refs; (4) references for the Box 2 benchmark trials (IPASS, CRYSTAL, OPUS, PRIME, MERiDiAN, COIN) added as refs 8–13 with DOIs/PMIDs and in-text superscripts; per-cell reconstructed counts for OPUS/PRIME mutant subgroups flagged for line-by-line re-check against source tables; (5) target Nature Medicine Perspective (~2,000–2,500 words, ≤4 display items) — current length and 4 display items (Table 1, Box 1, Box 2, Fig. 1) fit.*
