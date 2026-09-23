# Pharmacology & clinical

> One-line promise: go from a concentration–time table or a clinical-trial design question to a
> **population-PK model with a VPC**, a **non-compartmental PK summary**, a **BOIN Phase-I dose-finding
> boundary table with operating characteristics**, or a **CPIC pharmacogenomics report** — each ending
> on a decision artifact, not a process tree.
> For: **clinical pharmacologists / pharmacometricians**, **early-phase clinical-trial statisticians**,
> and **translational / precision-medicine teams**. No coding required.

<!--
Every "supported" claim below is green in coverage-ledger.md § "Pharmacology & clinical".
Honesty rules applied here:
- Code-verified (C) = the .nf/endpoint exists and behaves as described (source read). Live-Batch
  numeric re-runs are marked L / ⏳ and were NOT fired (Batch costs real money — CLAUDE.md).
- FAERS is WIRED + indexed (id 11363) but its .nf is demo-shaped (hardwired 2004 Q1 + insulin) and
  E2E-UNVERIFIED. Presented as such, not as a general pharmacovigilance service.
- The PGx workflow maps PRE-CALLED diplotypes → CPIC; it does NOT call star alleles from a raw VCF.
  That distinction is load-bearing and is stated plainly.
- Anything not built is in "What's not covered" → Appendix E. Never over-promise.
-->

## What this is for

This chapter covers the **quantitative-pharmacology and early-clinical** side of a drug program — the
work that happens *around* first-in-human dosing rather than at the chemistry bench. It is the natural
next step after the ADMET / PBPK / allometric package in the flagship
[Drug discovery → IND](drug-discovery-ind.md) chapter: once you have a candidate and a projected human
dose, these workflows help you **model the clinical PK**, **design the dose-escalation trial**, and
**stratify patients by metabolizer genotype**.

Four families of task live here, each backed by a real indexed workflow:

1. **Non-compartmental analysis (NCA)** — the model-free "first look" at a concentration–time dataset:
   Cmax, Tmax, AUC, half-life, apparent clearance and volume, per subject, using the **PKNCA** R
   package.
2. **Population PK (PopPK)** — a mixed-effects compartmental model (**NONMEM** when licensed, **nlmixr2**
   open-source otherwise) with a **Visual Predictive Check** to qualify the fit.
3. **Phase-I dose-finding** — a **BOIN** (Bayesian Optimal Interval) dose-escalation design that emits a
   decision boundary table and the operating characteristics from a 1,000-trial simulation.
4. **Pharmacogenomics (PGx)** — mapping **pre-called** CYP2D6 / CYP2C19 (+9 more) star-allele
   diplotypes to **CPIC** metabolizer phenotypes and drug-dosing recommendations.

> **Tip** — For the *predicted human PK from structure* (PBPK, 8-compartment Rodgers–Rowland) and the
> *first-in-human dose from animal data* (allometric scaling, exponent 0.33, MRSD/MABEL), see the
> [Drug discovery → IND](drug-discovery-ind.md) chapter — those are documented there and are not
> repeated here. This chapter picks up once you have **clinical or per-subject PK data** in hand.

## Use cases

| Goal (researcher's words) | Workflow(s) / chain | Inputs | Outputs (artifact) | Lane |
|---|---|---|---|---|
| "Give me Cmax, AUC and half-life from this concentration–time table" | `nca_pknca` (PKNCA, R) | concentration–time CSV (`subject_id,time,conc,dose,route`) | per-subject NCA table + population summary + HTML report | Cloud (AWS Batch) |
| "Fit a population-PK model to my Phase-I data and check it with a VPC" | `nonmem_poppk` (NONMEM → nlmixr2 fallback) | NONMEM-format CSV (`ID,TIME,DV,AMT,MDV,EVID,CMT[,covariates]`) | parameter table (θ/Ω/Σ) + ETA distribution + VPC bands + report | Cloud |
| "Design a Phase-I dose-escalation trial and tell me how well it finds the MTD" | `clinical_trial_simulation` (design=`BOIN`) | dose levels, target DLT rate φ, PK/ER params | BOIN boundary table + operating characteristics + dose-escalation CSV | Cloud |
| "Translate this patient's CYP2D6 / CYP2C19 diplotypes into a CPIC dosing report" | `pharmacogenomics_pgx_report` | **pre-called** diplotypes JSON (e.g. `{"CYP2D6":"*1/*4"}`) | phenotype + drug-recommendation CSV + actionable-flag summary | Cloud |
| "Explore a pharmacovigilance signal in FAERS" (see honesty note) | `faers` (Bioconductor, id 11363) | FAERS quarterly ASCII zip + standardized RDS | signal tables (ROR/PRR-style), MedDRA hierarchy, dedup object | Cloud — **wired, E2E-unverified** |

> **Pitfall — this is a *modeling and design* toolkit, not a clinical database.** NCA/PopPK/BOIN
> compute on the data (or design) **you** supply; they do not fetch patient records. The PGx workflow
> **starts from diplotypes you already called** (see below). FAERS is wired but demo-shaped. Read each
> section's scope note before you promise a result to a clinical team.

## How to ask

BioMate routes on intent. The disambiguations that matter most in this chapter are **NCA vs. PopPK**
(model-free vs. mixed-effects), **which trial design**, and — critically — **"genotype" vs. "already
have diplotypes"** for PGx.

Non-compartmental (model-free) analysis:

> "Run non-compartmental PK analysis on this concentration–time CSV — I want Cmax, AUC and half-life
> per subject."

Population-PK fit + VPC:

> "Fit a two-compartment population-PK model to my Phase-I data (`ID,TIME,DV,AMT,MDV,EVID,CMT`) with
> FOCE-I and give me a visual predictive check."

BOIN Phase-I design:

> "Design a BOIN dose-escalation trial: dose levels 10, 20, 40, 80, 160 mg, target DLT rate 0.30,
> and simulate the operating characteristics."

Pharmacogenomics (note the wording):

> "I have called diplotypes — CYP2D6 \*1/\*4 and CYP2C19 \*2/\*2 — give me the CPIC phenotypes and
> dosing recommendations for codeine and clopidogrel."

**Disambiguation to avoid:**
- **"PK analysis" is ambiguous.** *"non-compartmental / NCA / model-free"* → `nca_pknca`. *"population
  model / mixed-effects / NONMEM / nlmixr2 / VPC"* → `nonmem_poppk`. *"predict human PK from a SMILES"*
  is neither — that is PBPK in the [IND chapter](drug-discovery-ind.md).
- **PGx starts from diplotypes, not a raw VCF.** If you ask BioMate to "call CYP2D6 star alleles from
  my VCF," the honest answer is that the PGx **report** workflow expects the diplotypes to be **already
  called** (e.g. by PyPGx / PharmCAT / Stargazer upstream) — it maps them to CPIC phenotypes and
  dosing. Star-allele *calling from raw sequence* is not built here (see "What's not covered"). Supply
  diplotypes and the report runs; supply only a VCF and you are past the workflow's contract.
- **"Dose escalation" defaults to BOIN.** Say `3+3` explicitly if you want the classic design; the same
  `clinical_trial_simulation` workflow supports `design=3plus3`.

## Tools & workflows behind this

| Tool / workflow | Role | Where (verified) |
|---|---|---|
| `nca_pknca` | Non-compartmental PK (AUClast/AUCinf/Cmax/Tmax/t½/CL·F/Vz·F) via PKNCA + HTML report | `backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/nca_pknca/main.nf` (DB id 10642) |
| `nonmem_poppk` | Mixed-effects PopPK; NONMEM when licensed, **nlmixr2 auto-fallback**; VPC + covariate/bootstrap steps | `.../drug_discovery/nonmem_poppk/main.nf` (DB id 12918) |
| `nlmixr2_population_pk` | Pure open-source (nlmixr2/SAEM) PopPK variant with GOF + VPC PDFs | `.../pharmacology/nlmixr2_population_pk/main.nf` |
| `clinical_trial_simulation` | **BOIN** (Liu & Yuan 2015) + 3+3 dose escalation; boundary table + operating characteristics | `.../drug_discovery/clinical_trial_simulation/main.nf` (DB id 14511) |
| `adaptive_trial_design` | Beyond 3+3/BOIN: MAMS + response-adaptive randomization, O'Brien-Fleming/Pocock boundaries | `.../drug_discovery/adaptive_trial_design/main.nf` (DB id 14509) |
| `pharmacogenomics_pgx_report` | Maps **pre-called** diplotypes (11 genes) → CPIC/DPWG phenotype + dosing | `.../pharmacology/pharmacogenomics_pgx_report/main.nf` (DB id 12876) |
| `faers` | Bioconductor `faers` pharmacovigilance signal detection — **wired, demo-shaped, E2E-unverified** | `.../bioconductor/faers/main.nf` (DB id 11363) |
| BOIN / NCA / allometric QC gates | Turn pipeline outputs into GOLD/SILVER/FAIL verdicts | `backend/lib/galaxy/ai/retrievers/qc_gate_reader.py:113-139` (boin_dlt_boundary, allometric_r_squared) |

> **License** — **NONMEM requires a commercial license** (ICON plc). BioMate uses a Bring-Your-Own-
> License pattern: it reads `NONMEM_HOME` / `NONMEM_LICENSE_FILE` from your stored credential and runs
> `nmfe75`/`nmfe74` when present; **otherwise it transparently falls back to nlmixr2** (open-source R),
> which the pipeline labels *"FDA Acceptable Open-Source"* rather than *"FDA Submission Grade"*
> (`nonmem_poppk/main.nf:84-104,1482-1492`). The quality tier is stamped into every report so you never
> mistake a fallback fit for a licensed one.

## QC gates & how to read them

Each gate answers one question and reports a **GOLD / SILVER / FAIL** verdict with a cited threshold.

### NCA gates (`nca_pknca/main.nf:298-337`)

| Gate | Threshold | What a fail means | Citation |
|---|---|---|---|
| **AUC extrapolation** | `≤ 20%` of AUCinf extrapolated (per-subject max) | Terminal-phase sampling too short — AUCinf is unreliable | FDA 2003 BA/BE guidance |
| **Terminal-slope coverage** | `≤ 2` subjects with no λz fit | Too few subjects have a valid half-life (need ≥ 3 terminal points each) | Gabrielsson & Weiner PK/PD 5th ed. |

Read AUC-extrapolation as: *if more than 20% of a subject's total exposure had to be extrapolated past
the last measured point, sample longer next time before trusting that subject's AUCinf/CL/Vd.* NCA does
not detect flip-flop kinetics — the workflow's own assumptions section says so
(`nca_pknca/main.nf:505-520`).

### PopPK diagnostics (`nonmem_poppk`)

PopPK does not "halt" on a threshold the way ADMET does; instead it reports the classic model-
qualification diagnostics you interpret yourself:

- **Minimisation status** — did the estimator converge? (`MINIMIZATION SUCCESSFUL`).
- **OFV / AIC / BIC** — objective function and information criteria for model comparison.
- **ETA / EPS shrinkage** — high shrinkage (rule of thumb > 30%) means individual estimates are pulled
  toward the population mean; be cautious reading covariate relationships off shrunken ETAs.
- **The VPC itself** — the single most important qualification: if the **observed** 5th/50th/95th
  percentiles fall inside the **simulated** prediction bands across time, the model reproduces the data
  it was fit to. The VPC step simulates `vpc_n_sim` (default 500) replicate datasets and writes
  per-time-bin observed-vs-simulated percentiles (`nonmem_poppk/main.nf:1234-1365`).

### BOIN operating characteristics (`clinical_trial_simulation`)

The BOIN design is judged not by a single p-value but by **how often the design gets the dose right**
across 1,000 simulated trials:

| Metric (`operating_characteristics.json`) | What it tells you |
|---|---|
| **P(correct MTD selection)** | Probability the design picks the true MTD — the headline "is this design good?" number |
| **P(underdosing)** | Probability it selects a dose below the true MTD (under-treats) |
| **P(overdosing)** | Probability it selects a dose above the true MTD (safety concern) |
| **no_safe_dose_in_range** | Flag: all dose levels exceed the target DLT rate — escalation should not proceed |

The BOIN decision itself is the boundary rule: escalate when the observed DLT rate is `≤ λe`,
de-escalate when `≥ λd`, otherwise stay — with `λe = φ − ε₁·φ` and `λd = φ + ε₂·(1−φ)` (defaults
ε₁ = ε₂ = 0.1), exactly the Liu & Yuan (2015) formulation (`clinical_trial_simulation/main.nf:154-202`).
The **`boin_dlt_boundary` QC gate** then scores the recommended MTD: GOLD if the observed DLT rate is
≤ 0.9·φ, SILVER if ≤ φ, FAIL if the MTD exceeds the target (`qc_gate_reader.py:113-126`).

> **QC gate — read P(overdosing) before you celebrate P(correct MTD).** A design can find the right
> MTD often *and* over-dose too often; both come out of the same simulation. For an oncology Phase-I,
> the overdose probability is frequently the gating safety number.

## Worked example (gold standard)

**Goal.** Design a BOIN Phase-I dose-escalation trial and read the operating characteristics as a
trial statistician.

**Prompt** (services-page use case 2.3):

> "Design a Phase-I dose-escalation oncology trial using BOIN — dose levels 10, 20, 40, 80, 160 mg,
> target DLT rate 0.30, and estimate the probability of correct MTD selection."

**What comes back and how to read it:**

- **The boundary table (`BOIN_decision_table.json`).** For φ = 0.30 the escalation boundary is
  `λe = 0.27` and de-escalation `λd = 0.37` (from the Liu & Yuan formula with ε = 0.1). This is the
  entire "at cohort *k*, do I go up / stay / down?" rulebook a clinical team follows at the bedside — a
  small table, not a black box.
- **The operating characteristics (`operating_characteristics.json`).** Across 1,000 simulated trials
  you get P(correct MTD selection), P(underdosing), P(overdosing) and the true-MTD dose. This is the
  number you take to a DSMB to argue the design is fit for purpose.
- **The dose-escalation table (`dose_escalation_results.csv`).** Per dose level: true DLT rate,
  median Cmax, and how often that dose was selected as MTD — the "where did the trials land" picture.

**The artifact.** You end on a **decision object** — a boundary rule you can execute and an OC summary
that says how well it performs — not a raw simulation dump. That is the gold-standard-comparable
terminus the tutorial-demo plan mandates.

> **Note (verification tier).** The BOIN, NCA and PopPK workflows are **code-verified (C)** end to end
> by reading the source (algorithm, outputs, QC gates all present and coherent). A fresh live AWS-Batch
> run to re-confirm exact numeric outputs is **pending (L / ⏳)** and was **not** fired — Batch runs cost
> real money (CLAUDE.md). No gold-standard pharmacology dataset is registered in
> `evaluation/tutorial_demos/gold_standards.yaml` yet, so the numbers above illustrate the
> *artifact shape*, not a captured run.

## Outputs & visualization

| Output | Where it renders | When to go interactive |
|---|---|---|
| NCA per-subject table (`nca_results.csv`) + population summary | After-run **Outputs** → table viewer | Export CSV for your PK report appendix |
| NCA HTML report (`nca_report.html`, log-linear conc–time + parameter table) | HTML viewer in after-run outputs | Open in browser for the concentration–time figure |
| PopPK parameter table (θ/Ω/Σ, SE, 95% CI) + ETA distribution | Table viewers | Export for the PopPK report §; overlay covariate plots |
| VPC bands (`vpc_summary.csv` / `vpc_plot_data.json`) | Plot/table viewers | Read the observed-in-band check; export for qualification memo |
| BOIN boundary table (`BOIN_decision_table.json`) | Table viewer | This is the bedside rulebook — export to the protocol |
| Operating characteristics (`operating_characteristics.json`) | Table / metric viewers | Take to the DSMB / design justification |
| PGx recommendation CSV + actionable-flag summary | Table + text viewers | Export the actionable rows to the clinical note |
| FAERS signal tables (if run) | Table viewer | See honesty note before relying on these |

## Pitfalls & tips

> **Tip — nlmixr2 fallback is a feature, not a downgrade you should hide.** If you don't have a NONMEM
> license, PopPK still runs (nlmixr2/SAEM) and the report is labelled *"FDA Acceptable Open-Source."*
> That is fine for exploratory and supportive analyses; for a *pivotal* submission, add the NONMEM
> credential so the report is stamped *"FDA Submission Grade."* The tier is in every report — don't
> present a fallback fit as a licensed one.

> **Pitfall — PGx maps diplotypes; it does not call them.** The single most common misuse is expecting
> `pharmacogenomics_pgx_report` to read a raw VCF and produce star alleles. It expects the **diplotypes
> already called** (its input default is a diplotypes JSON like `{"CYP2D6":"*1/*4"}`). Call star alleles
> upstream (PyPGx / PharmCAT / Stargazer), then feed the diplotypes here for the CPIC translation.

> **Pitfall — NCA AUCinf is only as good as your tail.** If the AUC-extrapolation gate fails (> 20%),
> your CL/F and Vz/F are built on an unreliable AUCinf. The fix is experimental — sample the terminal
> phase longer — not a parameter change. NCA also cannot see flip-flop kinetics.

> **Tip — pick φ deliberately for BOIN.** The target DLT rate φ *is* the design. φ = 0.25 vs 0.30
> shifts both boundaries (`λe`, `λd`) and every operating characteristic. Set it from the clinical
> risk tolerance for the indication, not the default.

> **Pitfall — FAERS is wired, not general-purpose (yet).** The indexed `faers` workflow (id 11363) is
> real Bioconductor code, but its `.nf` is **demo-shaped**: it is hardwired to the **2004 Q1** quarterly
> file and an **insulin** filter, and it requires a **pre-standardized RDS** as a second input
> (`faers/main.nf:74-135`). It has **not** been E2E-verified on dev. Treat it as a working starting
> point for a pharmacovigilance analysis, not a "type any drug, get signals" service. See Appendix E.

## What's not covered

Honest scope — these are **not** claimed as present in this chapter; they live in **Appendix E
(Coverage & roadmap)**:

- **Star-allele *calling* from raw VCF / sequence** (PyPGx / PharmCAT / Stargazer as a BioMate step).
  The PGx workflow consumes **pre-called** diplotypes; the calling step upstream of it is not built here
  (`pharmacogenomics_pgx_report/main.nf` input contract).
- **General-purpose FAERS pharmacovigilance.** The `faers` workflow is wired + indexed (id 11363) but is
  hardwired to 2004 Q1 + insulin, needs a pre-standardized RDS, and is **E2E-unverified**. A "query any
  drug over any date range" service, drug-name resolution, and disproportionality (ROR/PRR) presented as
  a general endpoint are **roadmap** (`faers/main.nf`; coverage-ledger II.4 finding).
- **DDI simulation (mechanistic CYP3A4 perpetrator, e.g. + ketoconazole AUC fold-change).** The
  services-page Pop-PK card narrates a DDI step; the `nonmem_poppk` workflow itself estimates PopPK +
  VPC and does **not** include a static/mechanistic DDI module. Not documented as present.
- **MTD from a live dose-escalation *from PopPK exposure* as a single click.** MTD in this chapter comes
  from the **BOIN simulation** (`clinical_trial_simulation`), which is a design tool. A one-shot
  "PopPK → Cmax-threshold MTD" chain like the tester-guide 2.1 narrative is not a single built workflow.
- **A captured gold-standard pharmacology run.** There is no pharmacology dataset in
  `gold_standards.yaml`; all numeric examples here illustrate artifact shape, not a re-run. Live-Batch
  numeric confirmation is tier L / ⏳.
- **Real MFA / production clinical-report signing.** Where these workflows feed the IND dossier,
  the e-signature caveats from the [IND chapter](drug-discovery-ind.md) apply (dev TOTP is weak).

---
_Verification: this page depends on the coverage-ledger rows under **"## Pharmacology & clinical"** —
`nca_pknca` PKNCA NCA params + AUC-extrap/terminal-slope QC gates (C), `nonmem_poppk` NONMEM→nlmixr2
fallback + VPC + quality-tier stamping (C), `clinical_trial_simulation` BOIN (Liu & Yuan 2015) boundary
table + operating characteristics + `boin_dlt_boundary` gate (C), `pharmacogenomics_pgx_report` diplotype→
CPIC mapping with the "pre-called, not VCF-calling" caveat (C), FAERS wired+indexed id 11363 but
demo-shaped / E2E-unverified (C 🔧), cross-refs to IND-chapter PBPK + allometric (link, not re-derived),
and the roadmap/gap rows (🗺️). Live-Batch numeric re-confirmation is tier L / ⏳ (not fired)._
