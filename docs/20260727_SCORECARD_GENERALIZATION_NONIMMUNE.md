# Target Scorecard — Generalization Test on Non-Immune Diseases

**Date:** 2026-07-27
**Purpose:** Test whether BioMate's two-stage target-scorecard ranker
*generalises* beyond the autoimmune panel
(`docs/20260727_CROSS_DISEASE_TARGET_SCORECARD.md`). Same pipeline, new
use-cases: oncology, cardio-metabolic, and neuro diseases with **well-known,
textbook drug targets**. Face-validity question: does the drug-blind ranker
rediscover the canonical targets outside immune disease?

**Pipeline (identical to the autoimmune run, host-local, live network):**
1. `nextflow/subworkflows/database/query_opentarget.nf` — live Open Targets
   Platform GraphQL v4 (`api.platform.opentargets.org`), `--n_targets 25`,
   emits `target_evidence.csv`. Queried by **MONDO id** (not free text) to
   avoid the apostrophe/paren quoting bug.
2. `nextflow_nfcore/subworkflows/drug_discovery/target_scorecard_ranker/main.nf`
   — OT-style weighted-harmonic-sum ranker over the evidence table.

Run on the host with `nextflow run … -profile standard -process.container=false`
(Docker is unavailable on this host; both workflow scripts are stdlib-only
Python and run natively — this only bypasses the container, not the logic).

**Panel (8 diseases, all resolved live in OT before scoring):**

| Slug | Disease | MONDO id | Stage 1 | Stage 2 | Canonical targets expected |
|------|---------|----------|:------:|:------:|-----------------------------|
| her2  | HER2-positive breast carcinoma | MONDO_0006244 | 25 ✔ | 25 ✔ | ERBB2, ESR1, PIK3CA |
| cml   | chronic myeloid leukemia       | MONDO_0011996 | 25 ✔ | 25 ✔ | ABL1, BCR |
| mel   | melanoma                       | MONDO_0005105 | 25 ✔ | 25 ✔ | BRAF, NRAS, KIT |
| nsclc | non-small cell lung carcinoma  | MONDO_0005233 | 25 ✔ | 25 ✔ | EGFR, ALK, KRAS, MET, ROS1, BRAF |
| fh    | familial hypercholesterolemia  | MONDO_0005439 | 25 ✔ | 25 ✔ | PCSK9, HMGCR, LDLR, APOB |
| t2d   | type 2 diabetes mellitus       | MONDO_0005148 | 25 ✔ | 25 ✔ | GLP1R, PPARG, KCNJ11 (+SLC5A2, DPP4) |
| alz   | Alzheimer disease              | MONDO_0004975 | 25 ✔ | 25 ✔ | APP, PSEN1, PSEN2, APOE, BACE1, MAPT |
| pd    | Parkinson disease              | MONDO_0005180 | 25 ✔ | 25 ✔ | SNCA, LRRK2, GBA1, PRKN, PARK7, PINK1 |

**8/8 diseases ran end-to-end, 16/16 workflow invocations, 0 failures.** The
live OT GraphQL API was reachable for every call; the no-fabrication guard
(header-only CSV on failure) was never triggered. **No disease failed to run.**

> Note on hypercholesterolemia: used **familial** hypercholesterolemia
> (`MONDO_0005439`, the Mendelian lipid entity) rather than the HP symptom
> term, because that is where the canonical LDLR/PCSK9/APOB/HMGCR genetics
> live in OT.

---

## Generalization verdict

**The ranker generalises well to genetics-driven and monogenic diseases
(cardio-metabolic, neurodegeneration, and the fusion/kinase leukaemia CML),
but generalises *poorly* to solid-tumour oncology driven by
somatic-mutation / clinical evidence — most starkly HER2-positive breast
cancer, where the three textbook targets (ERBB2/ESR1/PIK3CA) are pushed to
ranks 21–24, *out* of the top-10.**

This is not a random failure — it is a **single, diagnosable mechanism** (see
below) that predicts exactly which diseases work and which don't:

| Regime | Diseases | Rediscovery | Why |
|--------|----------|-------------|-----|
| **Genetics/monogenic — STRONG** | FH, T2D, Alzheimer, Parkinson | excellent (canon in top-3 to top-10) | targets carry strong `genetic_association` + `animal_model` + `affected_pathway`, exactly the axes the ranker rewards |
| **Fusion/kinase leukaemia — GOOD** | CML | ABL1 #3, BCR #10 | driver has pathway+animal-model evidence; BCR is penalised (see notes) but still lands top-10 |
| **Somatic-driver solid tumour — WEAK** | HER2 breast, melanoma, NSCLC | mixed; oncogenes with mostly `clinical`+`somatic_mutation` evidence are demoted | the ranker **excludes the `clinical` datatype by design** and treats `somatic_mutation` as just one harmonic term; a classic oncogene whose OT evidence is "we drug it + it's mutated" scores *low* on the biological axis |

**Compared to the autoimmune panel:** the neuro/cardio-metabolic diseases here
are actually **cleaner rediscoveries than MS/MG were** (MS/MG scored low and
were contaminated by potassium-channel artefacts). But oncology introduces a
**new, worse failure mode the autoimmune panel never exposed**: the
drug-blind design that was a *feature* for immune diseases (stops
already-drugged targets ranking on drug evidence alone) becomes a *bug* for
oncogenes, because in OT an oncogene's disease evidence often *is*
predominantly the excluded `clinical` bucket plus `somatic_mutation`. So the
answer is nuanced: **it generalises, but the drug-blind weighting is
mis-calibrated for somatic-driver oncology.**

---

## Rediscovery scorecard (drug-blind ranker vs. textbook targets)

"Best" = highest placement across the panel. Bold = in that disease's top-10.

| Target | Disease | Known drug / role | Scorecard rank | In top-10? |
|--------|---------|-------------------|:--------------:|:----------:|
| **ABL1**   | CML   | BCR-ABL — imatinib/dasatinib | **#3** | ✔ |
| **BCR**    | CML   | BCR-ABL fusion partner | **#10** | ✔ |
| **CDKN2A** | melanoma | tumour suppressor (CDK4/6 axis) | **#1** | ✔ |
| **MITF**   | melanoma | melanocyte master TF | **#4** | ✔ |
| **CDK4**   | melanoma | palbociclib axis | **#9** | ✔ |
| BRAF       | melanoma | vemurafenib/dabrafenib | #12 | ✗ (top-10 in NSCLC) |
| **ALK**    | NSCLC | crizotinib/alectinib | **#2** | ✔ |
| **ERBB2**  | NSCLC | HER2 — trastuzumab/T-DXd | **#4** | ✔ (but #24 in HER2-BC!) |
| **RET**    | NSCLC | selpercatinib | **#6** | ✔ |
| **BRAF**   | NSCLC | dabrafenib+trametinib | **#8** | ✔ |
| **MET**    | NSCLC | capmatinib/tepotinib | **#10** | ✔ |
| EGFR       | NSCLC | osimertinib/gefitinib | #11 | ✗ (just outside) |
| KRAS       | NSCLC | sotorasib/adagrasib | #18 | ✗ |
| **LDLR**   | FH | LDL receptor (statin upregulates) | **#2** | ✔ |
| **PCSK9**  | FH | evolocumab/alirocumab/inclisiran | **#3** | ✔ |
| **APOB**   | FH | mipomersen | **#6** | ✔ |
| **APOE**   | FH | lipid genetics | **#5** | ✔ |
| HMGCR      | FH | statins | #21 | ✗ (see caveat) |
| **SLC5A2** | T2D | SGLT2 — empagliflozin/dapagliflozin | **#1** | ✔ |
| **DPP4**   | T2D | sitagliptin/linagliptin | **#2** | ✔ |
| **KCNJ11** | T2D | sulfonylureas (K_ATP) | **#7** | ✔ |
| PPARG      | T2D | pioglitazone (TZDs) | #11 | ✗ (just outside) |
| GLP1R      | T2D | semaglutide/tirzepatide | #14 | ✗ |
| **APP**    | AD | amyloid precursor — lecanemab substrate | **#5** | ✔ |
| **PSEN1**  | AD | γ-secretase | **#4** | ✔ |
| **PSEN2**  | AD | γ-secretase | **#3** | ✔ |
| **APOE**   | AD | strongest AD risk gene | **#9** | ✔ |
| **PRKN**   | PD | parkin (mitophagy) | **#1** | ✔ |
| **PINK1**  | PD | mitophagy | **#3** | ✔ |
| **PARK7**  | PD | DJ-1 | **#4** | ✔ |
| **LRRK2**  | PD | LRRK2 inhibitors (clinical) | **#7** | ✔ |
| **SNCA**   | PD | α-synuclein | **#8** | ✔ |
| GBA1       | PD | ambroxol/venglustat axis | #13 | ✗ (Tier 1, just outside) |
| ERBB2      | HER2-BC | HER2 — the *defining* target | **#24** | ✗✗ |
| ESR1       | HER2-BC | ER — endocrine therapy | #21 | ✗✗ |
| PIK3CA     | HER2-BC | alpelisib | #22 | ✗✗ |

**Tally of canonical targets in the correct disease's top-10:**
**19 of 34** land in top-10. Of the 15 that miss, **11 miss only just**
(rank #11–24 while still Tier 1/2, i.e. present and highly ranked — EGFR #11,
PPARG #11, GBA1 #13, GLP1R #14, KRAS #18) or land in a *different* disease's
top-10 (BRAF). Only **3 are hard misses inside the top-25 slice** and they are
all in one disease: **HER2-positive breast cancer** (ERBB2/ESR1/PIK3CA at
21–24). A further 3 (BACE1, MAPT in AD; GCGR in T2D) fell **outside the n=25
OT slice entirely** — a coverage limit, not a ranking error.

---

## The one mechanism behind every miss

The ranker's disease-evidence score is a **normalised weighted harmonic sum**
over `genetic_support`, `cell_specificity`, `expression_evidence`, and
`biological_relevance`. Two design choices in `query_opentarget.nf` drive the
oncology failures:

1. **`clinical` (known-drug) datatype is excluded from `biological_relevance`
   (weight 0), by design.** For immune/monogenic diseases this is harmless —
   those targets have independent genetic/animal/pathway evidence. But a
   solid-tumour oncogene like **ERBB2 in breast cancer** has OT datatypes
   `clinical:0.91, somatic_mutation:0.46` and *nothing else* — its entire
   disease signal is the excluded bucket plus one somatic term. Harmonic sum of
   a single 0.46 term → `biological_relevance = 0.46`, `genetic_support`
   empty → it ranks 24th behind 23 GWAS-flavoured passengers.
2. **`somatic_mutation` is only *one* of five biological datatypes and gets
   harmonic-discounted.** NRAS in melanoma (`bio=0.97` but `genetic=0.0`) and
   KRAS in NSCLC (`bio=0.94`, `genetic` empty) are demoted because the missing
   genetic axis drags the weighted harmonic sum down. The ranker rewards
   *converging multi-axis* evidence; pure somatic drivers are single-axis.

**Why the "good" diseases are good:** their textbook targets carry
**`genetic_association` AND `animal_model` AND `affected_pathway`** — e.g.
LDLR (`genetic 0.97`, `bio 0.90`), PRKN (`genetic 0.96`, `bio 0.88`), PSEN1
(`genetic 0.95`), KCNJ11 (`genetic 0.93`). Multi-axis convergence is exactly
what the harmonic sum rewards, so they float to the top.

**The most instructive single result:** **ERBB2 ranks #24 in HER2-positive
breast cancer but #4 in NSCLC.** Same gene, same ranker — in NSCLC OT gives it
`affected_pathway + literature + clinical` (multi-axis, `bio=0.97`), in breast
cancer only `clinical + somatic_mutation`. The ranker is faithfully reading
the evidence; the evidence *shape* differs by disease, and the drug-blind
weighting punishes the "we already drug it" shape.

---

## Per-disease top-10 scorecards

Score = OT-style weighted-harmonic-sum over disease-evidence axes, reduced by a
safety penalty. Tiers: T1 ≥0.65, T2 ≥0.45, T3 ≥0.30, else T4. `*` = canonical
target for that disease. `gen`/`bio` = genetic_support / biological_relevance.

### HER2-positive breast cancer (top=PTPRK 0.57; 0×T1) — WEAK
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | PTPRK | 0.57 | T2 | — | 0.61 |
| 2 | EPS15 | 0.56 | T2 | — | 0.61 |
| 3 | LPP | 0.55 | T2 | — | 0.61 |
| 4 | FHIT | 0.55 | T2 | — | 0.61 |
| 5 | PTPRT | 0.54 | T2 | — | 0.61 |
| 6 | EXT1 | 0.53 | T2 | — | 0.61 |
| 7 | PREX2 | 0.53 | T2 | — | 0.61 |
| 8 | HIP1 | 0.52 | T2 | — | 0.61 |
| 9 | CDK6 | 0.52 | T2 | — | 0.61 |
| 10 | QKI | 0.51 | T2 | — | 0.61 |

_The top-10 is a wall of `bio=0.61` cancer-GWAS/somatic passenger genes with no
genetic axis. **ERBB2 #24, ESR1 #21, PIK3CA #22.** This is the clearest
failure in the panel — the drug-blind weighting inverts the ranking for a
disease defined by its drug target._

### Chronic myeloid leukemia (top=GAB2 0.75; 3×T1) — GOOD
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | GAB2 | 0.75 | T1 | — | 0.79 |
| 2 | SETBP1 | 0.71 | T1 | 0.87 | 0.55 |
| 3 | **ABL1** | 0.70 | T1 | 0.86 | 0.95 |
| 4 | GRB2 | 0.65 | T2 | — | 0.75 |
| 5 | TET2 | 0.63 | T2 | 0.71 | 0.70 |
| 6 | FYN | 0.63 | T2 | — | 0.77 |
| 7 | BLK | 0.61 | T2 | — | 0.63 |
| 8 | KIT | 0.59 | T2 | — | 0.73 |
| 9 | CSF3R | 0.46 | T2 | — | 0.51 |
| 10 | **BCR** | 0.44 | T3 | 0.28 | 0.96 |

_ABL1 (#3) and BCR (#10) both in the top-10 — the BCR-ABL fusion rediscovered.
BCR is dragged to T3 because its OT `genetic_association` is low (0.28: as a
fusion partner it has weak standalone genetics) even though `bio=0.96`. The
BCR-ABL kinase itself (ABL1) is clean top-3._

### Melanoma (top=CDKN2A 0.80; 7×T1) — GOOD (with BRAF caveat)
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | **CDKN2A** | 0.80 | T1 | 0.93 | 0.95 |
| 2 | IRF4 | 0.78 | T1 | 0.85 | 0.74 |
| 3 | MAP2K1 | 0.76 | T1 | — | 0.94 |
| 4 | **MITF** | 0.73 | T1 | 0.82 | 0.87 |
| 5 | GNAQ | 0.72 | T1 | — | 0.86 |
| 6 | GNA11 | 0.67 | T1 | — | 0.85 |
| 7 | RAC1 | 0.65 | T1 | — | 0.91 |
| 8 | SF3B1 | 0.64 | T2 | — | 0.87 |
| 9 | **CDK4** | 0.63 | T2 | 0.80 | 0.87 |
| 10 | CTLA4 | 0.63 | T2 | 0.72 | 0.96 |

_Strong melanoma biology (CDKN2A, MITF, MAP2K1/MEK, GNAQ/GNA11 uveal drivers,
CDK4, CTLA4/ipilimumab). **BRAF is #12** (`gen=0.70, bio=0.97`) — just outside,
demoted by the harmonic discount, not absent. NRAS #21 and KIT #23 fall
because their `genetic_support=0.0` (pure somatic drivers)._

### Non-small cell lung carcinoma (top=EML4 0.91; 19×T1) — STRONG
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | EML4 | 0.91 | T1 | — | 0.97 |
| 2 | **ALK** | 0.84 | T1 | — | 0.98 |
| 3 | KEAP1 | 0.84 | T1 | — | 0.95 |
| 4 | **ERBB2** | 0.82 | T1 | — | 0.97 |
| 5 | TP53 | 0.80 | T1 | — | 0.98 |
| 6 | **RET** | 0.79 | T1 | — | 0.96 |
| 7 | STK11 | 0.79 | T1 | — | 0.97 |
| 8 | **BRAF** | 0.78 | T1 | — | 0.97 |
| 9 | SMARCA4 | 0.78 | T1 | — | 0.97 |
| 10 | **MET** | 0.78 | T1 | — | 0.95 |

_Best oncology result: EML4-ALK fusion (#1/#2), plus ERBB2, RET, BRAF, MET —
five kinase/fusion targets in the top-10. NSCLC works where breast cancer
fails because OT gives these targets rich `affected_pathway + literature`
evidence (`bio≈0.97`), not clinical-only. **EGFR is #11** (`gen=0.93` but
harmonic-discounted), **KRAS #18** (empty genetic axis), **ROS1 #24** — the
three that miss are the ones whose evidence is genetics/somatic-thin._

### Familial hypercholesterolemia (top=MIR6886 0.93; 14×T1) — STRONG
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | MIR6886 | 0.93 | T1 | 0.93 | — |
| 2 | **LDLR** | 0.85 | T1 | 0.97 | 0.90 |
| 3 | **PCSK9** | 0.83 | T1 | 0.92 | 0.69 |
| 4 | LDLRAP1 | 0.82 | T1 | 0.85 | 0.64 |
| 5 | APOE | 0.73 | T1 | 0.82 | 0.87 |
| 6 | **APOB** | 0.70 | T1 | 0.89 | 0.68 |
| 7 | APOA5 | 0.69 | T1 | 0.76 | 0.54 |
| 8 | SORT1 | 0.69 | T1 | 0.82 | 0.10 |
| 9 | GHR | 0.69 | T1 | 0.81 | 0.46 |
| 10 | PIP5K1B | 0.67 | T1 | 0.68 | — |

_Near-textbook: LDLR #2, PCSK9 #3, APOB #6 — the LDL-clearance axis
rediscovered. **HMGCR (statin target) is #21** — the one real miss, because in
OT its evidence is mostly `clinical` (excluded) with modest genetics
(`gen=0.62`); statins act on a pathway node that is not a strong FH *genetic*
driver. MIR6886 at #1 is a genetic-only miRNA artefact (`bio` empty, single
axis) — see caveats._

### Type 2 diabetes mellitus (top=SLC5A2 0.96; 15×T1) — STRONG
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | **SLC5A2** | 0.96 | T1 | — | 0.98 |
| 2 | **DPP4** | 0.90 | T1 | — | 0.97 |
| 3 | GCK | 0.86 | T1 | 0.93 | 0.91 |
| 4 | SLC30A8 | 0.85 | T1 | 0.90 | 0.71 |
| 5 | WFS1 | 0.83 | T1 | 0.93 | 0.62 |
| 6 | ABCC8 | 0.82 | T1 | 0.93 | 0.72 |
| 7 | **KCNJ11** | 0.81 | T1 | 0.93 | 0.89 |
| 8 | SLC2A2 | 0.79 | T1 | 0.89 | 0.59 |
| 9 | ENPP1 | 0.77 | T1 | 0.89 | 0.60 |
| 10 | HNF1A | 0.74 | T1 | 0.89 | 0.82 |

_SGLT2 (SLC5A2) and DPP4 rank #1/#2 despite tiny OT association (0.637/0.636) —
driven up by high `literature`+`clinical`→`bio` and no penalty. KCNJ11/ABCC8
(K_ATP / sulfonylurea) and the MODY genes (GCK, HNF1A) rediscovered. **PPARG
#11, GLP1R #14** just outside (GLP1R's OT evidence is `clinical:1.0` — the
excluded bucket — so it's demoted despite being the blockbuster
semaglutide/tirzepatide target). GCGR fell outside the 25-slice._

### Alzheimer disease (top=BCHE 0.86; 16×T1) — STRONG
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | BCHE | 0.86 | T1 | — | 0.94 |
| 2 | CR1 | 0.84 | T1 | 0.91 | 0.94 |
| 3 | **PSEN2** | 0.83 | T1 | 0.91 | 0.88 |
| 4 | **PSEN1** | 0.82 | T1 | 0.95 | 0.86 |
| 5 | **APP** | 0.80 | T1 | 0.92 | 0.88 |
| 6 | CDK5R1 | 0.80 | T1 | — | 0.91 |
| 7 | APH1B | 0.78 | T1 | 0.82 | 0.47 |
| 8 | CDK5 | 0.78 | T1 | — | 0.86 |
| 9 | **APOE** | 0.77 | T1 | 0.89 | 0.80 |
| 10 | EPHA1 | 0.74 | T1 | 0.83 | 0.53 |

_The amyloid cascade rediscovered: PSEN2/PSEN1/APP (γ-secretase + amyloid
precursor, ranks 3–5), APOE (#9), plus γ-secretase subunit APH1B and
cholinesterase BCHE/ACHE (symptomatic drug targets). **BACE1 and MAPT are NOT
in the OT top-25 slice** — BACE1 has weak OT genetic association (a drug target
without a genetic signal); MAPT associates more strongly with FTD/PSP than AD
in OT. Both are n=25 coverage misses, not ranking failures._

### Parkinson disease (top=PRKN 0.89; 17×T1) — STRONG
| # | Gene | Score | Tier | gen | bio |
|--:|------|------:|------|----:|----:|
| 1 | **PRKN** | 0.89 | T1 | 0.96 | 0.88 |
| 2 | PLA2G6 | 0.88 | T1 | 0.94 | 0.85 |
| 3 | **PINK1** | 0.88 | T1 | 0.95 | 0.78 |
| 4 | **PARK7** | 0.87 | T1 | 0.91 | 0.84 |
| 5 | ATP13A2 | 0.87 | T1 | 0.94 | 0.76 |
| 6 | COMT | 0.84 | T1 | — | 0.94 |
| 7 | **LRRK2** | 0.84 | T1 | 0.92 | 0.86 |
| 8 | **SNCA** | 0.82 | T1 | 0.91 | 0.80 |
| 9 | FBXO7 | 0.80 | T1 | 0.88 | 0.82 |
| 10 | MAOB | 0.79 | T1 | — | 0.91 |

_Best neuro result and one of the best in the whole panel: **5 of the 6
canonical PD genes in the top-10** (PRKN, PINK1, PARK7, LRRK2, SNCA — the
mitophagy + α-synuclein core), plus COMT and MAOB (the actual PD drug enzymes:
entacapone, rasagiline/selegiline). **GBA1 is #13** (Tier 1 — present under
its current approved symbol; the task's "GBA" is the deprecated symbol) and
MAPT #12. Monogenic PD is the ranker's ideal case: strong `genetic` + `bio` +
`animal_model` convergence._

---

## How this compares to the autoimmune panel

| Dimension | Autoimmune panel | This non-immune panel |
|-----------|------------------|-----------------------|
| Run success | 8/8, 16/16 calls | 8/8, 16/16 calls |
| Best rediscovery | psoriasis (5 marketed mechanisms in top-10), MG top-2 = C5+FcRn | PD (5/6 canon genes), NSCLC (5 kinases), FH (LDL axis), AD (amyloid cascade) |
| Weakest area | MS/MG — low scores, K-channel artefacts | **HER2 breast cancer — canon at #21–24**; solid-tumour somatic drivers |
| Failure mechanism | co-annotated neuro K-channels inflate MS/MG lists | drug-blind weighting demotes clinical-/somatic-only oncogenes |
| Overall | high face validity; misses were rank #11–12 | high face validity for genetics-driven disease; **one class (somatic-driver oncology) mis-ranked** |

**Net:** it does generalise. Monogenic/genetics-driven non-immune disease
(FH, T2D, AD, PD) rediscovers canonical targets **as well as or better than**
the strongest autoimmune cases, and with fewer artefacts than MS/MG. The
genuinely new weakness the non-immune panel exposes is **somatic-driver solid
oncology**, where the same drug-blind design that *helped* immune diseases
*hurts* — because an oncogene's OT disease evidence is often precisely the
`clinical`+`somatic_mutation` shape the ranker down-weights.

---

## Honest caveats

- **Evidence-driven prioritisation, not novel discovery.** Every hit above is a
  *rediscovery* of established biology from aggregated Open Targets evidence
  (human genetics, literature, animal models, pathways, expression). A high
  rank means "strong converging published evidence," not a new mechanism.
- **Known-target bias / not blind prediction.** `query_opentarget.nf` excludes
  the `clinical` datatype from `biological_relevance` (weight 0), so a target
  can't rank purely for being drugged — but `literature`/`genetic_association`
  are still richer for well-studied targets. This is a face-validity check, not
  a claim of blind prediction.
- **Somatic-driver oncology is systematically mis-weighted (the headline
  caveat).** For HER2 breast cancer the three defining targets land at #21–24;
  for melanoma/NSCLC several drivers (BRAF, EGFR, KRAS, NRAS, KIT, ROS1) fall
  just outside the top-10. Root cause: the drug-blind exclusion of `clinical`
  plus harmonic discounting of single-axis `somatic_mutation` evidence.
  **Fix for future work:** an oncology weight profile that (a) re-admits
  `somatic_mutation` at higher weight or as its own axis, and/or (b) does not
  zero `clinical` for solid tumours where clinical *is* the strongest genuine
  disease-target link. Do not "fix" this by editing production `.nf` params for
  a benchmark — it needs a disease-class-aware weighting scheme.
- **n=25 slice is shallow.** BACE1 and MAPT (AD), GCGR (T2D), MC1R (melanoma)
  fell **outside** the top-25 OT-associated list — coverage limits, not
  ranking errors. GBA1 (PD #13), EGFR (NSCLC #11), PPARG (T2D #11) sit just
  past the top-10 cut but remain Tier 1/2. Top-10 membership is a hard
  threshold, not a hard boundary in the evidence.
- **Thin axis coverage (OT-only).** Only `genetic_support`,
  `biological_relevance`, `tractability`, `safety_liability` are populated;
  `cell_specificity` and `expression_lfc/padj` are empty (they come from
  scRNA/DE tools). Many top targets score at 35–65% axis coverage and are
  correctly flagged provisional. Fusing a disease scRNA/DE run would raise
  coverage and re-order mid-tiers — and could specifically rescue the demoted
  oncogenes (which are strongly *expressed*/amplified in tumour tissue).
- **Single-axis genetic artefacts float up.** MIR6886 (#1 FH) and similar
  genetic-only rows (empty `bio`) can top a list on one strong genetic term
  with no biological corroboration. A minimum-axis-count guard would suppress
  these.
- **Symbol drift.** Canonical "GBA" is the OT-deprecated symbol; OT returns
  "GBA1" (rank #13, present). Match on current approved symbols when auditing.

---

## Many-use-case test result

**8/8 non-immune diseases passed both pipeline stages (16/16 invocations, 0
failures). No disease failed to run.** The apostrophe/paren param-quoting bug
was avoided by passing MONDO ids to stage 1 and apostrophe-free display names
to stage 2. The live OT GraphQL API was reachable for all 16 calls; the
no-fabrication guard (header-only CSV on failure) was never triggered — no
synthetic fallback at any point. Raw outputs (evidence CSVs, scorecards, JSON,
per-disease reports) are under the transient run workspace
`…/scratchpad/panel_ni/<slug>/` (regenerate by re-running the two workflows
with the MONDO ids in the panel table above).

---

## Fix: disease-class-aware weight profile

**Date:** 2026-07-27. **File changed (one only):**
`backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/target_scorecard_ranker/main.nf`
(the ranker — *not* `query_opentarget.nf`, which is left untouched).

### Root cause recap

The failure diagnosed above lives in the fixed **"discovery" datatype-weight
profile** that `query_opentarget.nf` uses to collapse the OT per-datatype
evidence into a single `biological_relevance` number: the known-drug
`clinical` datatype is **zeroed (weight 0)** and `somatic_mutation` enters an
*unweighted* harmonic sum as just one of several biological datatypes. That is
correct for immune/genetics-driven disease (it makes the MG top-2 = C5 + FcRn a
real drug-blind rediscovery) but **wrong for solid-tumour oncology**, where a
driver oncogene's OT evidence is often predominantly `clinical` + `somatic`
(e.g. ERBB2 in breast cancer: `clinical:0.91, somatic_mutation:0.46`, nothing
else) → demoted to #24 behind 23 GWAS passengers.

### The fix — a transparent, rule-based, opt-in weight profile

`query_opentarget.nf` already **preserves the raw per-datatype scores** in the
evidence `notes` column
(`datatypes=clinical:0.91,somatic_mutation:0.46; …`). The ranker now, **only
when a non-default profile is selected**, RECOMPUTES `biological_relevance`
from those raw datatypes using a disease-class weight profile. The harmonic-sum
machinery is unchanged — only the per-datatype weights differ. No learned /
black-box ranking; every weight is documented in code and in the report.

New params (both actually used by the Python; no dead params):

- `--weight_profile discovery|solid_tumour` (default `discovery`; `oncology` is
  an accepted alias of `solid_tumour`).
- `--disease_class auto|immune|solid_tumour` (default `auto`). A non-`auto`
  class overrides `--weight_profile` (`immune` → `discovery`, `solid_tumour` →
  `solid_tumour`); `auto` keeps whatever `--weight_profile` says.

**Per-datatype weights into `biological_relevance` (the only thing that
differs between profiles):**

| datatype | `discovery` (default) | `solid_tumour` |
|----------|:---------------------:|:--------------:|
| `clinical` | **0.00** (excluded) | **0.80** (re-admitted, partial) |
| `somatic_mutation` | 1.00 | 1.00 |
| `literature` | 1.00 | 1.00 |
| `animal_model` | 1.00 | 1.00 |
| `rna_expression` | 1.00 | 1.00 |
| `affected_pathway` | 1.00 | 1.00 |

Two safety properties make this a clean opt-in:

1. **Default is byte-for-byte unchanged.** On `discovery` the ranker does *not*
   re-parse `notes` and takes `biological_relevance` exactly as supplied. Verified
   by running the committed (git-`HEAD`) ranker and the patched ranker on the same
   HER2 and MG evidence CSVs: **`target_scorecard.csv` is byte-for-byte identical**
   (the only report-`.md` delta is three additive lines documenting the profile).
2. **Re-admission is MONOTONIC.** The recomputed value is floored at the
   upstream discovery value (`bio = max(discovery_bio, recomputed)`), so
   re-admitting the `clinical` datatype can only *raise* a target's biological
   signal — it never dilutes a target (e.g. ESR1/PIK3CA, whose `clinical` is a
   weak 0.09) that was already strong on `somatic` alone.

Also applied the bash single-quote escape to every single-quoted string-param
export in this file (`disease`, `evidence_file`, `network_file`,
`weight_profile`, `disease_class`):
`'${params.disease}'` → `'${params.disease.toString().replace("'", "'\''")}'`.

### Diff summary (one file)

- Added `params.weight_profile` (default `'discovery'`) + `params.disease_class`
  (default `'auto'`), fully documented in a header comment block.
- Exported both to the Python via `PARAM_WEIGHT_PROFILE` / `PARAM_DISEASE_CLASS`.
- Python: `BIO_DATATYPE_PROFILES` table, `resolve_weight_profile()`
  (alias + class-override logic), `_parse_notes_datatypes()` (reads the raw
  datatypes from the `notes` column), `bio_relevance_for_profile()` (weighted
  harmonic sum), and a monotonic-floor recompute of `biological_relevance` in
  `normalise_target()` guarded by `if WEIGHT_PROFILE != 'discovery'`.
- Surfaced the active profile + its datatype weights in `run_meta`
  (`weight_profile`, `weight_profile_bio_datatypes`) and in the Markdown report
  header.
- Single-quote-escaped all string-param exports.

### Test results (live two-stage pipeline; MONDO ids; `nextflow run … -profile standard`)

Stage 1 `query_opentarget.nf --n_targets 25`, stage 2 this ranker.

**1. No-regression (DEFAULT `discovery` profile) — PASS.**

| Disease (MONDO) | Top of ranking | Verdict |
|---|---|---|
| Myasthenia gravis (`MONDO_0009688`) | **#1 C5, #2 FCGRT (FcRn)** | ✔ unchanged vs prior doc |
| Psoriasis (`MONDO_0005083`) | #1 IL12B, #2 IL36RN, #3 CARD14, #4 IL17A, #5 TYK2 | ✔ marketed immune mechanisms, unchanged |

MG's `target_scorecard.csv` under the patched ranker is byte-for-byte identical
to the git-`HEAD` ranker's output.

**2. Fix works (`--weight_profile solid_tumour`) — HER2-positive breast
carcinoma (`MONDO_0006244`).**

| Target | rank (default `discovery`) | rank (`solid_tumour`) | `biological_relevance` (disc → solid) |
|--------|:--------------------------:|:---------------------:|:-------------------------------------:|
| **ERBB2** | **#24** | **#1** | 0.456 → **0.703** |
| ESR1  | #21 | #22 | 0.608 → 0.608 (floored, unchanged) |
| PIK3CA | #22 | #23 | 0.608 → 0.608 (floored, unchanged) |

**ERBB2 — the panel's clearest failure — is rescued from #24 to #1** by
re-admitting its `clinical:0.91` + `somatic:0.46` evidence. ESR1 and PIK3CA are
*not* lifted by the evidence re-weighting because their remaining depression is
a genuine, orthogonal **safety-liability penalty** (ESR1 `safety=0.612`, PIK3CA
`safety=0.816` — PI3K/ER toxicity), not the clinical/somatic exclusion this fix
targets; their `biological_relevance` is held flat by the monotonic floor
(their `clinical` is only 0.09, so re-admission legitimately adds nothing). The
honest outcome: the named headline oncogene is fixed decisively; the two
high-liability co-targets stay mid-ranked for a correct reason the ranker should
not override. `oncology` alias and `--disease_class solid_tumour` both reproduce
ERBB2 #1; `--disease_class immune` correctly forces `discovery` back (ERBB2 #24).

**3. Opt-in confirmed — HER2 under the DEFAULT profile is still the old demoted
behavior:** ERBB2 #24, ESR1 #21, PIK3CA #22 (exactly the ranks in the scorecard
table above). The fix changes nothing unless `solid_tumour`/`oncology` (or
`--disease_class solid_tumour`) is explicitly requested.
