# Multi-Modality Drug Development AI — What Becomes Possible (2026-05-09)

## The Premise

Until now, drug development AI tools have been **modality-siloed**: Schrödinger does small molecules, Genentech tools do antibodies, Moderna's stack does mRNA, Beam does base editing. Each company picks one modality and builds a tool stack around it.

**BioMate is the first platform with all major modalities under one AI orchestration layer.** This unlocks classes of work that no siloed tool can do, because the new things require *comparing across modalities* or *chaining between modalities* in ways that are economically impossible when each tool is at a different vendor.

This document proposes 8 concrete features that become possible only because all modalities live in one platform.

---

## Feature 1: Modality Recommender

**The problem**: A scientist has a target. They don't know which modality will work best. Today they pick based on their team's expertise, not based on what the science says.

**What BioMate can do**: Given a target protein or disease, run a *modality scoring pass* that evaluates every modality option:

> Target: KRAS G12C in NSCLC
>
> | Modality | Feasibility | Estimated time-to-clinic | Score |
> |---|---|---|---|
> | Small molecule | High (sotorasib precedent) | 5-7 yr | 9/10 |
> | PROTAC | Medium (KRAS is hard to degrade — flat surface) | 7-10 yr | 6/10 |
> | siRNA | High (LNP delivery to lung tumors) | 6-8 yr | 7/10 |
> | mRNA vaccine (neoantigen) | Medium (KRAS G12C peptide is HLA-restricted) | 8-12 yr | 5/10 |
> | CAR-T (KRAS G12C TCR-mimetic) | Low (intracellular target) | 10+ yr | 3/10 |
> | ASO | Medium (allele-specific) | 5-7 yr | 7/10 |
>
> **Recommendation**: Small molecule (proven) + ASO as differentiated backup. PROTAC if hard-to-drug confirms.

**Why this matters**: This is a $50M decision. Today, it's made in conference rooms based on intuition. With BioMate's modality coverage, it becomes a 10-minute analysis with reproducible reasoning.

**Implementation**: Workflow `modality_recommender` that calls each modality's design workflow with conservative defaults, scores feasibility based on workflow output (e.g., PROTAC ternary cooperativity α, ADC payload-target match, AAV serotype availability), and ranks. Already buildable from existing pieces.

---

## Feature 2: Cross-Modality IP Landscape

**The problem**: Before committing to a modality, every pharma asks "what is the IP whitespace?" Today this requires an external IP attorney plus modality-specific search vendors, weeks per query.

**What BioMate can do**: Cross-reference each modality's design output against patent databases:

> Target: BCMA in multiple myeloma
> - **CAR-T**: Crowded — 14 active patents on bb2121 derivatives, 8 on P5A3 derivatives. Whitespace: cycle-control engineering.
> - **ADC**: Open whitespace — only 2 active BCMA-ADC patents (Belantamab mafodotin clusters). MMAF derivatives largely unclaimed.
> - **Bispecific antibody**: Moderately crowded — 22 BCMA-bispecific patents (Teclistamab and successor IP).
> - **PROTAC**: Open — no published BCMA-PROTAC patents (BCMA is membrane protein, hard to degrade).
>
> Recommendation: BCMA-ADC has the cleanest IP path; PROTAC is a research bet.

**Implementation**: Add patent database integration (USPTO, EPO, WIPO PatentScope) to BioMate workflow output. Already 80% built — would need PatentScope API key.

---

## Feature 3: Multi-Modality Combination Studies

**The problem**: The next era of oncology is combination therapy across modalities — small molecule + ADC, CAR-T + PROTAC, mRNA vaccine + ICI. Computational design of these combinations does not exist anywhere because each tool vendor handles one modality.

**What BioMate can do**: Combination workflow that:
1. Models each agent's PK/PD individually (existing workflows)
2. Predicts pharmacokinetic interaction (CYP DDI for small molecules + ADC payload + immunomodulator)
3. Models pharmacodynamic synergy (existing `cpa_drug_combination_synergy`)
4. Designs a Phase Ib combination trial with appropriate dose-finding (existing `clinical_trial_simulation` with extensions)

**Example**: KRAS G12C inhibitor (sotorasib) + anti-PD1 mRNA vaccine + KRAS-degrading PROTAC.

> Today: requires 3 separate vendors + 6 months coordination.
> BioMate: one conversation, full simulation, predicted synergy + safety + trial design.

**Implementation**: Workflow `multimodality_combination` that orchestrates per-modality workflows + DDI + clinical trial design. New routing layer in `galaxy-assistant.ts`.

---

## Feature 4: Modality Pivot Analysis (when a program fails)

**The problem**: Most drug programs fail at Phase II — typically because of efficacy, not safety. When a target is validated but the small molecule fails, today you start over with a different team for a different modality. The institutional knowledge is lost.

**What BioMate can do**: When a program fails, BioMate can run a *modality pivot analysis*: take everything learned about the target (binding site, expression, toxicity ceiling, biomarker response) and recommend the next modality to try.

> Failed: Sotorasib in pancreatic cancer (efficacy too low, KRAS amplification at recurrence)
>
> Pivot recommendation:
> - **PROTAC** (degrade KRAS, overcome amplification by lowering protein levels rather than competing for binding)
> - **mRNA vaccine** with KRAS G12C neoantigen (immunological mechanism, orthogonal to drug resistance)
> - **CAR-T (TCR-mimetic)** if neoantigen is HLA-presented
>
> Each modality scored against the failure mechanism: amplification → PROTAC wins; mutation drift → vaccine wins; HLA loss → not vaccine.

**Implementation**: Add a `modality_pivot` analysis mode to existing modality workflows. Combines failure-mechanism inference (LLM over clinical readouts) + modality recommender.

---

## Feature 5: Single-Cell Validated Modality Selection

**The problem**: Modality choice today is made at the *protein* level — what does the target look like, what's its location, etc. But the real biology is at the *cellular* level — which cell types express the target, how does expression vary, what's the on-target/off-target tissue distribution.

**What BioMate can do**: Connect single-cell atlas data (Tabula Sapiens, Human Cell Atlas — both queryable today) to modality design:

> Target: CLDN18.2 in gastric cancer
>
> Single-cell expression:
> - Tumor cells: high (median 4.2, 87% of cells)
> - Normal gastric epithelium: moderate (median 1.8, 60% of cells) ← off-target risk
> - Other tissues: <0.5 in all
>
> Modality implications:
> - **ADC (zolbetuximab-MMAE)**: high payload load → on-target gastric epithelial toxicity → manage with dose
> - **CAR-T**: catastrophic on-target/off-tumor risk in normal stomach → reject or use logic-gated CAR
> - **Bispecific T-cell engager**: tunable, early stop possible → preferred
> - **siRNA**: ineffective (CLDN18.2 is membrane structural protein, knockdown doesn't reverse phenotype)

**Implementation**: Connect existing `state_perturbation_prediction` and scRNA-seq workflows as inputs to modality design workflows. Use cell-level expression as a feature in modality scoring.

---

## Feature 6: Patient-Stratified Multi-Modality Design

**The problem**: Personalized medicine today means picking the right *small molecule* for a patient based on their mutations. The next step is picking the right *modality* for the patient.

**What BioMate can do**: Given a patient's variant profile + expression + HLA + comorbidities, recommend the modality that fits:

> Patient: BRCA1-mutant ovarian cancer, TP53-WT, HLA-A*02:01 positive, history of cardiomyopathy
>
> Modality fit:
> - **PARP inhibitor (small molecule)**: standard, but low cardiac safety margin given history → flag
> - **PARP-PROTAC**: emerging, no cardiac liability data → research option
> - **BRCA-restored mRNA replacement**: experimental, strong scientific rationale
> - **Neoantigen vaccine** (TP53-WT supports immune response): viable, HLA-A*02:01 supports many predicted epitopes
>
> Recommendation: PARP standard-of-care + neoantigen vaccine combination; avoid anthracycline-class PROTACs.

**Implementation**: Connect patient WGS/EHR (existing `nf-core/raredisease`) → variant + HLA → modality scoring with patient-specific safety filters. New workflow `patient_modality_match`.

---

## Feature 7: Modality Migration for Cost Reduction

**The problem**: An approved biologic ($100K-500K/year per patient) is unaffordable in most of the world. Today, biosimilars take 12+ years to develop and barely lower cost. Cross-modality migration could compress this to 2-3 years.

**What BioMate can do**: Take an approved biologic (e.g., Humira/adalimumab) and design a small molecule or peptide alternative that targets the same pathway:

> Approved: Adalimumab (anti-TNF, $50K/year)
>
> Modality migration analysis:
> - Target: TNF-alpha trimer disruption
> - Small molecule TNF inhibitors: failed historically (PPI hard to drug)
> - **Cyclic peptide** (Zinpentraxin precedent): feasible — design via ProteinMPNN cyclic + AF2 prediction
> - **PROTAC against TNFR1 receptor**: alternative degradation strategy
> - **Anti-TNF mRNA scFv expressed in vivo**: continuous biologic at SC injection cost
>
> Recommendation: Anti-TNF mRNA-encoded scFv via LNP → 100x manufacturing cost reduction vs. recombinant antibody, same mechanism.

**Implementation**: Workflow `modality_migration` that takes an approved drug + mechanism + target → ranks alternative-modality designs by feasibility + projected cost reduction. Has direct economic argument: every dollar of cost reduction is patient-accessible.

---

## Feature 8: AI-Designed Personal Medicine (the YC-2026 vision)

**The problem**: One-to-one personalized therapy (n-of-1 drugs for individual rare disease patients) is the frontier. Today it costs $2-3M per patient (e.g., milasen for Mila Makovec, Batten disease, MIT/Boston Children's). The cost is not in the drug — it's in the multi-modality design team.

**What BioMate can do**: When a rare disease patient's WGS is uploaded, BioMate can in one conversation:

1. **Identify the variant** (existing `nf-core/raredisease`)
2. **Score therapeutic strategies across all modalities**:
   - Splice-modulating ASO if splice variant (milasen pattern)
   - Gene replacement via AAV if loss-of-function (Zolgensma pattern)
   - Base editing if point mutation
   - mRNA replacement therapy if protein lost
   - Drug repurposing via TxGNN if pathway-druggable
   - Neoantigen vaccine if cancer
3. **Design the lead therapeutic for each viable modality** (existing workflows)
4. **Estimate IND cost + timeline per modality** (FDA platform IND for ASO = 6 months; AAV = 24 months; etc.)
5. **Output a ranked therapeutic plan** the patient's clinician can act on

> A patient gets diagnosed Monday. BioMate produces a complete therapeutic strategy by Friday. Today this takes 18 months and a $2M consortium.

**This is the YC AI personalized medicine vision made real.** It's not a chatbot reading lab values. It's a platform that does the actual therapeutic design work, across every modality, for one patient at a time. And because all modalities are in one place, the cost per case drops 100x.

**Implementation**: Workflow `n_of_1_therapeutic_design` chaining all six modality workflows behind a single patient-input front-end. Routing rule: "n-of-1 patient" or "personal medicine for variant X" triggers the chain.

---

## What This Unlocks Strategically

These eight features are not incremental — they create entirely new product surface areas:

1. **Modality Recommender** — sells to executive decision makers (CSO, CMO, BD). Different buyer than the bench scientist.
2. **IP Landscape** — sells to BD/legal teams. Higher ACV, longer sales cycle, but stickier.
3. **Multi-modality combinations** — opens the combination therapy market, projected $40B by 2030.
4. **Modality Pivot** — sells to portfolio rescue teams in pharma. Failed Phase II programs are a $20B/year problem.
5. **Single-cell Validated Modality** — defensible technical moat; requires both single-cell + modality coverage that no competitor has.
6. **Patient-Stratified Modality** — connects BioMate to clinical decision support; entirely new market (clinicians, not researchers).
7. **Modality Migration for Cost** — global health story; unlocks government / NGO buyers (BMGF, Wellcome Trust, CEPI).
8. **n-of-1 Personalized Medicine** — the YC frontier; could be the BioMate IPO story.

Each one is a billion-dollar product line. Each one is impossible without all modalities in one platform.

---

## What to Build Next

Concrete sequence:

**Q1 — Build the modality recommender** (Feature 1). It's the simplest, most demo-able, and proves the multi-modality value to every visitor in 30 seconds. ~2 weeks of work.

**Q1 — Add patent landscape integration** (Feature 2). PatentScope API + workflow output enrichment. ~3 weeks.

**Q2 — Single-cell validated modality** (Feature 5). Connects existing single-cell workflows to modality scoring. ~1 month. Technical moat builder.

**Q2 — n-of-1 patient design** (Feature 8). The flagship. ~2-3 months. Becomes the headline demo.

**Q3 — Multi-modality combinations** (Feature 3). Opens combination therapy market. ~2 months.

**Q4 — IP landscape, modality migration, patient stratification, modality pivot** — sequenced based on early customer signal.

---

## The Pitch Frame

The current BioMate pitch is "one platform, every modality." That's accurate but it's a feature claim.

The real claim is bigger:

> **BioMate is not a tool — it is the first AI scientist that thinks about drug development the way a Chief Scientific Officer does: across modalities, across patients, across the full lifecycle. Every other drug discovery AI is a specialist tool inside one modality. BioMate is the only one that asks the executive question: which modality, which patient, which combination, which cost.**

This is the difference between Stripe (payments tool) and Stripe Atlas + Capital + Tax + Climate — Stripe became infrastructure for entire businesses, not just payments. BioMate's multi-modality coverage is what lets it become the infrastructure for entire drug development programs, not just one workflow.
