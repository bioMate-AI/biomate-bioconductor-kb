# How a Target Is Acknowledged & Validated — the DETAILED paths

*Companion to `20260911_TARGET_LIFECYCLE_HOW_A_TARGET_BECOMES_ACKNOWLEDGED.md` (the 6-stage
ladder). This doc drills into each rung: the exact claim being validated, the methods/experiments
that credential it, the quantitative gate, the failure mode that kills it, and worked traversals of
real targets across mechanism channels. 2026-09-11.*

---

## 0 · The one idea that makes the whole path rigorous

Every rung is answering **one probabilistic question**: *what is the probability this gene is a
causal, directionally-correct, druggable driver of the disease?* Each validation step is an
**update** on that probability, and the ladder is ordered by **how much each step moves it** and
**how expensive it is**. You spend cheap in-silico causal evidence first (it moves the probability
the most per dollar), and only pay for CRISPR/animal/clinical once the causal prior is high enough.

Two things must become true, and every method below serves one of them:
1. **Identity** — *which gene* (not which locus). ~90% of GWAS hits are non-coding, so the SNP ≠ the gene.
2. **Direction** — *inhibit, activate, or replace* (from the sign of the human genetic effect).

---

## 1 · T0 → T1 — the causal jump (where most targets die; where most detail lives)

**Claim to validate:** "this gene *causes* the disease (driver), in a known direction — it is not a
passenger, a consequence, or a bystander in an associated locus."

The credentialing methods, in increasing strength, with their gates:

| Method | What it shows | Quantitative gate | Kills it if… |
|---|---|---|---|
| **Fine-mapping → credible set** | narrows an associated locus to the few variants likely causal | 95% credible set small; posterior inclusion prob (PIP) high on a variant | credible set is large / spans many genes → identity unresolved |
| **Locus-to-gene (L2G / OpenTargets)** | maps the causal variant to the causal *gene* (distance, QTL, chromatin) | L2G score high (≈≥0.5) and separable from neighbours | top gene ambiguous vs neighbour → stay T0 |
| **Colocalization (coloc)** | the disease signal and a molecular QTL (eQTL/pQTL/sQTL) share the **same** causal variant | **PP.H4 ≥ 0.8** (shared) and PP.H4 ≫ PP.H3 (distinct) | PP.H3 dominates → disease and expression are *different* signals; not the gene |
| **cis-Mendelian randomization** | lifelong genetically-proxied perturbation of the gene → disease (a natural RCT); gives **direction + magnitude** | significant cis-MR effect; robust to MR-Egger / weighted-median (no horizontal pleiotropy) | pleiotropy or null cis-MR → association is confounded/non-causal |
| **Rare-variant / LoF burden ("human knockouts")** | protective LoF → inhibiting is safe+efficacious; disease LoF → activate/replace | exome-wide-significant burden; consistent direction | no rare-variant signal (weakens, doesn't kill) |
| **OMIM / monogenic** | the gene causes a Mendelian form of the disease | established Mendelian gene | — (strongest single causal proof when present) |

**Direction-of-effect logic (the output of this rung):**
- gain-of-function *causes* disease → **inhibit** (e.g. most cytokines)
- loss-of-function *protects* → **inhibit** (PCSK9, IL23R R381Q, SLC30A8)
- loss-of-function *causes* disease → **activate / replace** (enzyme-replacement logic)

**Promotion rule to T1:** a named gene (L2G/fine-map) **+** a coloc PP.H4 ≥ 0.8 with a disease-relevant
QTL **+** a direction from cis-MR or LoF. Genetics that names gene *and* direction *before any drug*
is the strongest possible T1 (this is why genetically-supported targets approve at ~2–2.6× base rate,
and the multiplier rises with causal-gene confidence).

**Honest failure modes at T0→T1:** wrong gene in the locus; a reverse-causation biomarker (disease
raises the protein, not vice-versa — MR direction test catches this); context — the causal QTL may
only exist in the disease-driving cell state, so a bulk eQTL misses it (needs cell-type/context QTL).

---

## 2 · T1 → T2 — functional / mechanistic validation

**Claim:** "deliberately perturbing this gene changes the disease phenotype, and the entity is
physically druggable."

- **Perturbation (the core test):** CRISPR **knockout / knockdown / activation (CRISPRa)** in the
  disease-relevant cell type or organoid → does the disease signature move in the direction genetics
  predicted? **Rescue** (re-express → reverse) closes the causal loop. Arrayed or pooled screens with
  a defined disease-signature readout.
- **Model systems, with their validity limits:** primary human immune cells / patient-derived
  organoids > immortalized lines; animal models credential in-vivo relevance but carry species-mismatch
  risk (murine immunology ≠ human — a documented translation gap).
- **Druggability / tractability (the "can a molecule engage it" test):** structure or high-quality
  homology model; a **ligandable pocket** (for small molecules) or a surface epitope (for antibodies);
  **modality fit** — extracellular/secreted → antibody; intracellular enzyme/pocket → small molecule;
  "undruggable" interface/scaffold → degrader / PROTAC / molecular glue / ASO. A target with no
  modality path stalls here regardless of causal strength.

**Promotion rule to T2:** perturbation moves the phenotype in the genetics-predicted direction (with
rescue) **and** a credible modality engages the target.

---

## 3 · T2 → T3 — translational / preclinical proof

**Claim:** "a real tool molecule/antibody engages the target and shows efficacy in a disease model,
and on-target safety is scoped."

- **Target engagement** — a PD biomarker proving the molecule hits the target in vivo (not just binds
  in vitro).
- **In-vivo efficacy** in a disease model at engaging exposures.
- **On-target safety, predicted from human genetics (the cheap safety oracle):** **PheWAS** on the
  target's variants (what else does perturbing this gene do across the phenome?) + **cis-MR on safety
  endpoints** — flags on-target adverse effects *before* the tox study (e.g. an inhibitor's predicted
  side-effects = the phenotypes of the LoF human knockout). Plus tissue-expression breadth.
- Standard tox / PK-PD.

**Promotion rule to T3:** engagement + in-vivo efficacy + an acceptable on-target safety profile.

---

## 4 · T3 → T4 → T5 — clinical, where "acknowledged" is earned

- **T4 · Proof-of-mechanism (Ph1/2):** biomarker-confirmed **engagement in patients** + an efficacy
  **signal** on a disease endpoint. This is the first *human efficacy* read — the moment the target
  thesis meets reality.
- **T5 · Acknowledged / validated:** a **Ph3-confirmed, approved** drug whose mechanism *is* that
  target. Only human efficacy credentials a target; ~90% of drugs that enter clinical trials fail, and
  **efficacy (the target being wrong or insufficient) is the single largest cause** — which is exactly
  why the genetic/causal front-loading in §1 matters.
- **What T5 changes:** the target becomes a **credentialing anchor** — the positive control every new
  nomination in that mechanism channel is scored against (see the channel map in the ladder doc).

---

## 5 · Worked traversals — the detailed life cycle of real targets, by channel

**PCSK9 — the gold-standard genetics-first traversal (lipid channel).**
T0: LDL correlates with CHD. **T1: rare LoF variants → lifelong low LDL and ~88% CHD reduction; GoF →
familial hypercholesterolaemia → direction = INHIBIT, named gene + direction before any drug**
(Cohen 2006, [10.1056/NEJMoa054013](https://doi.org/10.1056/NEJMoa054013)). T2/T3: antibody engages
secreted PCSK9. T5: evolocumab/alirocumab approved. *Lesson: genetics did the T0→T1 work; the clinic
mostly confirmed it — the fast, low-attrition path.*

**IL6R — cis-MR that mimics the drug (IL-6 channel).**
T0: IL-6 elevated in inflammation. **T1: cis variant Asp358Ala proxies IL6R inhibition → lowers CRP /
downstream signaling, mirroring tocilizumab's biology** (IL6R MR Consortium 2012,
[10.1016/S0140-6736(12)60110-X](https://doi.org/10.1016/S0140-6736(12)60110-X)). T5: tocilizumab
approved (RA). *Lesson: cis-MR is a pre-clinical readout of what the drug will do.*

**IL23R / TYK2 — protective LoF fixes the direction (IL-12/23 channel).**
T0: IL-23 pathway associated with psoriasis/IBD. **T1: IL23R R381Q is a protective LoF → inhibiting the
axis is protective** (Di Meglio 2011, [10.1371/journal.pone.0017160](https://doi.org/10.1371/journal.pone.0017160)).
T2–T5: ustekinumab/risankizumab (IL-12/23), and **deucravacitinib** (allosteric TYK2 inhibitor) — the
same axis drugged at a downstream node. *Lesson: one protective allele credentials a whole channel and
multiple nodes within it.*

**ALCAM — where Dr. Mohan's target actually sits (adhesion / ALCAM–CD6 channel).**
**T0 (strong):** urinary ALCAM discriminates active lupus nephritis across three ethnicities, AUC
0.84–0.93 (Stanley/Mohan 2020, *Nat Commun* 11:2197,
[10.1038/s41467-020-15986-3](https://doi.org/10.1038/s41467-020-15986-3)) — a well-validated
**association/biomarker**. **The T0→T1 gate it still owes:** is ALCAM a **causal driver** of renal
inflammation or a **passenger/consequence**? Concretely — coloc of an ALCAM pQTL/eQTL with LN genetics,
a direction from cis-MR or LoF, and CRISPR perturbation in the disease-relevant renal/immune context.
The **CD6 side** (itolizumab) is clinically further along, which credentials the *channel* but does not
by itself credential *ALCAM* as the drug target. *This is exactly the rung a computational
causal-confidence pass is built to address.*

---

## 6 · Where BioMate credentials the ladder (and the honest boundary)

| Rung | Automatable in-silico (BioMate) | Requires wet-lab / clinic |
|---|---|---|
| **T0→T1** | fine-map/L2G, **coloc PP.H4**, **cis-MR** (direction+magnitude), rare-variant/PheWAS lookups, **multi-channel causal-confidence each vs a matched null**, interpretable per-target breakdown | — |
| **T1→T2** | virtual-KO / perturbation-signature screen (over *measured* perturbation data), druggability/pocket + modality fit | the actual CRISPR / rescue / animal experiment |
| **T2→T3** | on-target safety prediction (PheWAS + cis-MR safety), expression-breadth flags | engagement PD, in-vivo efficacy, tox |
| **T3→T5** | responder / mechanism **stratification** (which patient fits which acknowledged channel) | the trial itself |

**Honest scope:** BioMate automates the **T0→T1→T2 credentialing** — the hardest, highest-value,
cheapest-to-front-load part — and the downstream **responder-stratification** once a channel is
acknowledged. Its **face validity is the drug-blind scorecard** (rediscovered the canonical channel
anchors — C5, FcRn, IL-23/TYK2, IL-6R, CD20, BAFF, IFNAR1, S1P, CTLA-4 — from biology alone, no drug
data). What it does **not** do: replace the CRISPR/animal/clinical rungs, or claim a T0 biomarker is a
T1 target without running the causal gate. Turning a specific T0 (e.g. ALCAM) into a credentialed
T1/T2 is a pilot on real cohort data, not a settled result.

---

## 7 · The path in one line

**Associate (T0) → prove causal + direction (T1: fine-map/coloc/MR/LoF) → perturb + confirm druggable
(T2: CRISPR/rescue + modality) → engage + show efficacy in models with safety scoped (T3:
PD/in-vivo/PheWAS) → human proof-of-mechanism (T4: Ph1/2) → approved (T5: Ph3) = acknowledged, and now
the channel's anchor.** Each rung is a probability update; genetics front-loads the two that matter
most — *which gene* and *which direction* — which is why it predicts approval.

---

## 8 · Sources

**Example / anchor targets** (inherited from the ladder doc): Nelson 2015, *Nat Genet* —
[10.1038/ng.3314](https://doi.org/10.1038/ng.3314); Minikel 2024, *Nature* —
[10.1038/s41586-024-07316-0](https://doi.org/10.1038/s41586-024-07316-0); IL6R-MR Consortium 2012,
*Lancet* — [10.1016/S0140-6736(12)60110-X](https://doi.org/10.1016/S0140-6736(12)60110-X); IL23R R381Q,
Di Meglio 2011 — [10.1371/journal.pone.0017160](https://doi.org/10.1371/journal.pone.0017160); PCSK9,
Cohen 2006 — [10.1056/NEJMoa054013](https://doi.org/10.1056/NEJMoa054013); ALCAM, Stanley/Mohan 2020,
*Nat Commun* 11:2197 — [10.1038/s41467-020-15986-3](https://doi.org/10.1038/s41467-020-15986-3).

**Method papers (verified this pass):**
- **Colocalization** (coloc / PP.H4) — Giambartolomei et al. 2014, *PLoS Genetics* 10(5):e1004383 —
  [10.1371/journal.pgen.1004383](https://doi.org/10.1371/journal.pgen.1004383) (PMID 24830394).
- **Locus-to-gene (L2G)** / Open Targets Genetics — Mountjoy et al. 2021, *Nature Genetics* 53:1527 —
  [10.1038/s41588-021-00945-5](https://doi.org/10.1038/s41588-021-00945-5).
- **MR-Egger** (pleiotropy-robust MR) — Bowden, Davey Smith & Burgess 2015, *Int J Epidemiol* 44(2):512 —
  [10.1093/ije/dyv080](https://doi.org/10.1093/ije/dyv080) (PMID 26050253).
- **Weighted-median MR** — Bowden, Davey Smith, Haycock & Burgess 2016, *Genetic Epidemiology* 40:304 —
  [10.1002/gepi.21965](https://doi.org/10.1002/gepi.21965) (PMID 27061298).
- **PheWAS** — Denny et al. 2010, *Bioinformatics* 26(9):1205 —
  [10.1093/bioinformatics/btq126](https://doi.org/10.1093/bioinformatics/btq126) (PMID 20335276).

*Fine-mapping / credible sets* is described by standard concept and is integrated within the L2G pipeline
above; *cis-MR* foundational framing follows Davey Smith & Ebrahim — left un-DOI'd here rather than cite an
unverified identifier.
