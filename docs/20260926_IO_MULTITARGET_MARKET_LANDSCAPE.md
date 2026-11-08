# Multi-Target Immuno-Oncology — Market & White-Space Landscape

**Date:** 2026-09-26
**Purpose:** A verified landscape of the *multi-target immuno-oncology* market — combinations, bispecifics, deal flow, target-pair-selection methods, and the cyclic/macrocyclic-peptide sub-field — to ground the direction of (a) our multi-omic multi-task immune LLM's target-pair nomination and (b) the separate cyclic-peptide therapy program (ACT / cancer, immuno-oncology only).
**Method:** 8 parallel research agents + sub-agents, each under strict anti-fabrication rules (real trials, real deals, verified PMIDs/DOIs/URLs, explicit "reasoned-not-computed" labels). Failures/discontinuations flagged by trial name. Items that could not be verified are listed as such and are **not** cited as fact.
**Honesty contract:** This doc distinguishes what is *demonstrated* (approved/failed trials, filed deals) from what is *reasoned* (mechanistic/topological argument) from what is *our forward capability claim* (not yet built/validated). Do not upgrade a reasoned or forward claim to a fact when reusing this.

Supersedes nothing; extends `biomate-immune-llm/docs/program_control/20260908_MULTITARGET_IMMUNE_THERAPY_SURVEY.md` with the cancer/IO market + competitive + white-space view.

---

## 0 · Executive summary (the honest headline)

1. **The money is in cross-*modality* single molecules, not cross-checkpoint pairs.** PD-(L)1 × VEGF bispecifics are *the* IO deal theme of 2024–2026 (>$20B in upfronts+milestones across Merck, BMS/BioNTech, Pfizer). T-cell engagers in solid tumors are #2, de-risked by tarlatamab's full approval.
2. **Same-axis checkpoint stacking is a graveyard.** Anti-TIGIT + PD-(L)1 failed across **three sponsors** (SKYSCRAPER, KeyVibe, STAR). CD47/magrolimab died on **futility + a mortality signal** ($4.9B write-off). Even the "textbook" adaptive+innate pair (PD-L1+CD47) is the one the market already tried and buried — mechanistic complementarity was necessary but not sufficient; the molecule/tox killed it.
3. **What wins is non-redundancy across *different jobs*** — different phase (CTLA-4 priming + PD-1 effector) or different modality (immune + anti-angiogenic). Live emerging non-redundant bets: CCR8 Treg-depletion, PD-1×IL-2, CD73/adenosine — none Phase-3-proven yet.
4. **Cyclic-peptide IO is NOT empty (correction to an earlier over-claim).** ~35–45 single-target macrocyclic checkpoint binders exist (PD-L1-heavy; BMS-986189 reached the clinic, then **suspended for PK**; several AI-designed). But **zero macrocyclic-peptide checkpoint *therapeutic* has reached market or Ph2+.**
5. **Multi-target cyclic-peptide IO is a single-incumbent frontier — Bicycle Therapeutics.** The only clinical multi-target cyclic-peptide IO asset is **BT7480** (Nectin-4×CD137, Ph1/2). Genuinely *empty* sub-niches: **dual-checkpoint × checkpoint macrocycles (never built)** and **cyclic-peptide CD3 T-cell engagers**.
6. **Immune-mechanism-aware target-*pair* nomination is near-white-space as a capability** — no vendor sells it as a product; AION Labs (AZ/Merck/Pfizer/Teva) is *founding a company* to do it (validates the gap). This is where our immune LLM is differentiated.

**Net strategic read:** First-in-class here is NOT "our version of PD-1×VEGF" (VEGF is now brutally crowded/expensive) and NOT another checkpoint-checkpoint pair (dead). It is a **novel, LLM-nominated cross-modality immune axis, delivered as a tumor-conditional multi-target macrocycle** — a format/axis combination that only Bicycle occupies (and only for tumor-antigen×costim), solving the PK/tox failure mode that sank the incumbents.

---

## 1 · Where the money is going (deal flow, 2024–2026)

### #1 — PD-(L)1 × VEGF bispecifics — dominant theme (cross-modality, single molecule)

| Deal | Date | Asset / targets | Upfront | Total | 
|---|---|---|---|---|
| Summit ← Akeso | Dec 2022 (expansions since) | Ivonescimab (AK112), PD-1×VEGF | $500M | up to ~$5B |
| Merck ← LaNova | Nov 2024 | LM-299 (→MK-2010), PD-1×VEGF | $588M | ~$3.3B |
| BioNTech ⟵ Biotheus (acq.) | Nov 2024 | BNT327/PM8002, PD-L1×VEGF | $800M | +$150M contingent |
| BMS ↔ BioNTech (co-dev) | Jun 2025 | BNT327 (pumitamig), PD-L1×VEGF | $1.5B | ~$11.1B, 50/50 profit share |
| Pfizer ← 3SBio | May 2025 | SSGJ-707, PD-1×VEGF | $1.25B | ~$6B |

Clinical driver: ivonescimab beat pembrolizumab head-to-head in China (HARMONi-2, **PFS HR 0.51**, later an OS win). **But** global HARMONi hit PFS (HR 0.52) and **missed OS significance (HR 0.79, p=0.057)** — US PDUFA Nov 14, 2026. The "does it work outside China" question is genuinely open; part of the wave is FOMO. (A rumored ~$15B AstraZeneca–Summit deal is **press rumor, not filed** — do not cite as fact.)

### #2 — T-cell engagers (CD3) in solid tumors — de-risked by approval
**Tarlatamab (IMDELLTRA, DLL3×CD3)**: FDA accelerated May 2024 → **full approval Nov 2025** (DeLLphi-304 OS HR 0.60). **Tebentafusp (KIMMTRAK, gp100×CD3 ImmTAC)**: first/only OS win in metastatic uveal melanoma. First solid-tumor TCEs — validating redirected-T-cell bispecifics beyond heme.

### #3–#6 — emerging (no megadeals yet) and cooling
- **CCR8 Treg-depletion** — BMS-986340 furthest (Ph1/2, no data disclosed); LaNova, Roche, Amgen, Bayer active. Non-redundant mechanism (subtract suppression).
- **PD-1 × IL-2 (engineered/"not-alpha")** — Synthekine↔Merck (STK-012), Roche RO7284755; collaboration-stage, modest $.
- **CD73/adenosine** — oleclumab+durvalumab (COAST Ph2 positive; **PACIFIC-9 Ph3 pending**); repositioned as combo.
- **4-1BB (CD137) bispecifics — cooling.** Genmab **halted acasunlimab (PD-L1×4-1BB)** Dec 2025 after portfolio review.

### Graveyards
- **TIGIT:** Roche tiragolumab — whole SKYSCRAPER program scrapped (Jul 2025, >5,000 pts); Merck vibostolimab KeyVibe-003/007/008 discontinued; Gilead/Arcus domvanalimab STAR-221 (Dec 2025) and STAR-121 (~Apr 2026) discontinued. Only PD-1×TIGIT *bispecific* rilvegostomig (AZ) keeps a flicker.
- **CD47/SIRPα:** Gilead magrolimab — ENHANCE-1/2/3 all stopped (ENHANCE-3 for **increased death risk**), FDA hold, **~$4.9B write-off**. Only biomarker-selected **evorpacept** (ALX, ASPEN-06 gastric) survives.

### Market size (wide analyst dispersion — directional only)
IO/immunotherapy market: ~$55–153B (2024/25) → $250–440B by 2032–35 (CAGR ~9–23% depending on definition). Bispecific antibody segment is the fastest-growing sub-market (~30–44% CAGR in aggressive estimates; BCC a conservative ~10% outlier).

---

## 2 · What wins vs fails — the mechanism rule

**Validated winners (cross-modality / phase-complementary / non-redundant):**
- **PD-1 + CTLA-4** (nivo+ipi) — different *phases* (priming + effector, + Treg depletion). Archetype, broadest label, >$11B franchise.
- **Checkpoint + anti-angiogenic** — atezo+bev (HCC, IMbrave150 OS 19.2 vs 13.4 mo), pembro+lenva (RCC/endometrial). Different *modality*.
- **PD-1 + LAG-3** (Opdualag, RELATIVITY-047) — the one same-axis exception that worked, but **modest** and melanoma-only.

**Proven losers (same-axis redundancy):** anti-TIGIT + PD-(L)1 (definitive, 3 sponsors). Relieving the *same* bottleneck (already-primed T cell) adds toxicity, not benefit.

**Three forces that decide (review literature):** (1) mechanistic non-redundancy (different node/phase/modality); (2) the toxicity ceiling (redundant combos pay full irAE cost for little gain — the TIGIT/IL-2/CD47 pattern); (3) tumor context dominates (same combo wins RCC, fails HCC — LEAP-002).

---

## 3 · Target-pair nomination — methods + competitive platforms

**Methods landscape:** network/complementary-exposure (Cheng–Barabási *Nat Commun* 2019; Menche *Science* 2015), SyndrumNET, SynGeNet; ML synergy predictors (DeepSynergy, AZ–Sanger DREAM); experimental (dual-Cas9 GI maps; in-vivo immunocompetent CRISPR screens — Manguso 2017 / Dong 2019 / Lawson 2020). **Critical gap:** nearly all computational methods are validated on **tumor-cell-intrinsic** synergy with **no immune compartment**; only in-vivo immune CRISPR screens capture immune mechanism, and those nominate *target + PD-1 backbone*, not de-novo pairs.

**How industry actually does it:** mechanistic-narrative + PD-1-backbone empiricism (the "combination explosion" — 1,716 anti-PD-1 combinations by 2018), coarsely biomarker-informed. Big rational failure = TIGIT.

**Competitive AI-platform map (verified):** No vendor commercially sells *in-silico IO target-pair nomination* as a product.
- Single-target discovery: Insilico (PandaOmics), Recursion/Exscientia, BenevolentAI, Owkin TargetMATCH, Valo.
- IO immune-target discovery + stratification: **Immunai/AMICA**, **CytoReason**, Owkin BiomarkerPlus, Tempus.
- Drug-synergy prediction: **Turbine.ai** (oncology synergy + anchored co-target; **IO-specific unverified** — nearest competitor).
- **AION Labs** (AZ/Merck/Pfizer/Teva/AWS studio) — **March 2025 global call to *found a startup* for "AI for Novel Target Combinations"** in oncology/immune. Validates the white space as an unsolved, fundable problem.

**Verdict:** immune-mechanism-aware target-*pair* nomination = **white-space verging on emerging niche**, not commodity. Honest hedges: Turbine.ai (nearest) + AION Labs (door opening).

---

## 4 · Cyclic/macrocyclic-peptide IO — full enumeration

**Correction to prior over-claim:** "macrocycle IO is near-empty white space" is **wrong as stated**. The single-target + imaging field is populated; the *multi-target* sub-field is a *single-incumbent frontier*, not empty.

### Single-target macrocyclic checkpoint peptides (~35–45 named; PD-L1-heavy; mostly preclinical/imaging)
- **BMS-986189** (PD-L1, macrocyclic peptide) — Phase 1 → **SUSPENDED (poor PK/half-life)**. **BMS-986238** — 2nd-gen (albumin-binding tail, oral), early clinical (stage sources disagree; a cited NCT is malformed — do not cite). **[¹⁸F]BMS-986229** — PD-L1 PET tracer (imaging, not therapeutic).
- **WL12** (Johns Hopkins) — PD-L1 macrocycle, reached first-in-human NSCLC imaging. Literature: CLP001-003, pAC65 (co-crystal), C-series; **CD47:** D4-2 (mRNA-display macrocycle, PDB 6LYC), pep-20-D12; **VISTA:** AP1049 + tracer; **TIGIT:** DTBP-3/68Ga-GP12 (human imaging); **CTLA-4/LAG-3/TIM-3:** single lineages each; **OX40:** essentially empty.
- **AI-designed:** Baker-lab de novo mini-proteins to CTLA-4 + PD-L1 (co-crystal, functional); AlphaProteo PD-L1 (0.18 nM, **binding-only**); PD-L1-3 mini-protein (first-in-human PET). *Note: strongest AI work is mini-proteins (50–140 aa), not short macrocycles.*
- **Zero macrocyclic-peptide checkpoint therapeutic has reached market or Ph2+.** Field's problem = **drug-like PK + monetization, not chemistry.**

### Multi-target cyclic-peptide IO — 8 verified programs, 5 are Bicycle
- **BT7480** (Nectin-4 × CD137) — **Ph1/2, NCT05163041, ± nivolumab** — the *only* clinical-stage multi-target cyclic-peptide IO asset. (Confirmed via ClinicalTrials.gov API; a "BT7480 = CD3" claim seen in one search is **FALSE**.)
- BT7455 / BCY12491 (EphA2 × CD137, preclinical), NK-TICA (EphA2 × NKp46), OX40×tumor-antigen TICAs (discovery). Bicycle "TICA" = tumor antigen × immune costimulatory receptor, one synthetic multi-bicyclic molecule.
- Non-Bicycle (3, academic, borderline chemotype): CSBP (CD24/Siglec-10 × PD-1, D-peptide), Pal-DMPOP (CD47×PD-L1 self-assembling), antiCD3-G7-RGD (CD3×αvβ3 self-assembling).
- **Genuinely empty:** dual-**checkpoint** × checkpoint macrocycles (never built), cyclic-peptide CD3 TCEs (no clinical/IND).
- **Graveyard signal:** BMS-986189 suspended for PK; Bicycle **deprioritized/partnered-out BT7480** in its 2026 restructuring (~30% cut). The incumbent is retrenching.

**Who we'd compete with directly:** Bicycle (tumor-antigen×immune-agonist bicyclics), decisively; secondarily PeptiDream/BMS (single-target checkpoint macrocycles) and de-novo mini-protein groups (Baker, DeepMind).

---

## 5 · The candidate pair analyses (for reference; both completed 2026-09-26)

### Peptide-druggability of three checkpoints
- **PD-L1 — STRONG:** WL12, CLP002, **BMS-986189** (clinical, sub-nM), extracellular IgV domain, PET + Ph1/2 precedent.
- **CD47/SIRPα — MODERATE–STRONG:** macrocyclic SIRPα blocker (Cell Chem Biol 2020, PMID 32640189) + pep-20/pep-20-D12; but **µM affinity, preclinical-only**.
- **TIGIT — WEAK/NONE:** antibody-only; **no validated cyclic peptide exists** → de-novo research risk.
- Functional 9-mo proof credible for all (Promega blockade reporter bioassays exist, incl. PD-1+TIGIT combo).

### Network-separation (complementary-exposure) — PD-L1+CD47 vs PD-L1+TIGIT
- **Method: COMPUTED** on STRING v12.0 high-confidence human PPI (16,201 nodes / 236,930 edges); `sAB = dAB − (dAA+dBB)/2`. Reproducible: `scratchpad/compute_sab.py`.
- **Robust signal (both neighbor-expanded module defs):** PD-L1+CD47 more separated (more complementary) than PD-L1+TIGIT. Seed-only definition inverts as a STRING co-annotation **artifact** (all checkpoints co-annotated at distance 1) — do not quote a single sAB.
- **Qualitative + clinical (more decisive):** PD-L1/TIGIT = same adaptive T-cell exhaustion axis (redundant "boost" → SKYSCRAPER-01 failed); PD-L1/CD47 = adaptive + innate (complementary). **But** PD-L1+CD47 is exactly the axis magrolimab failed on tox/futility — so "better complement" is a *mechanistic/topological* verdict, **not** proven clinical superiority.

**Implication:** the "safe" complementary pair (PD-L1+CD47) is a buried graveyard; the druggable-but-redundant pair (PD-L1+TIGIT) is dead. Neither is a first-in-class play — which is the whole point.

---

## 6 · Strategic synthesis — the first-in-class thesis

**What NOT to do:** a checkpoint × checkpoint pair (dead/redundant), a re-tread of PD-L1+CD47 (buried), or "our PD-1×VEGF" (crowded, $20B already committed).

**The defensible first-in-class shape (three levers, mapped to our assets):**
1. **Novel orthogonal axis, LLM-nominated** — an immune axis paired with a *different modality/mechanism* (Treg-depletion / metabolic-adenosine / myeloid-beyond-CD47 / stromal), chosen by our immune-compartment-aware, causal/perturbation-grounded pair nominator — the capability that is itself near-white-space (no vendor sells it).
2. **Multi-target *macrocycle* format** — the sub-niche only Bicycle occupies (and only for tumor-antigen×costim). A **dual-immune-target constrained-peptide** — especially a checkpoint×checkpoint or novel-axis macrocycle — **has never been built.** Macrocycle advantages: solid-tumor penetration, synthetic tunability, cost.
3. **Tumor-conditional activation** — protease-/pH-gated, so it's active only in the TME. Directly solves the **systemic-tox failure mode** that killed magrolimab and the PK problem that suspended BMS-986189.

**The honest capability claim (defensible even pre-generation):**
- *Model:* multi-omic, multi-task immune LLM whose target-ID + pair-nomination heads are immune-compartment-aware and null-disciplined — a capability no competitor productizes (Immunai/CytoReason = single-target+stratification; Turbine = synergy; AION Labs still founding).
- *Data:* full immune scope (infectious + autoimmune + IO, 21.4M cells) + full KG — feeding causal/mechanistic pair rationale, not empirical PD-1-backbone trial-and-error.
- *Therapy:* a differentiated multi-target macrocycle format in a single-incumbent (retrenching) frontier.
- *System:* closed-loop DBTL on the peptide side (the compounding moat).

**Explicit tradeoff (named, not hidden):** this is higher-risk and longer than a validated-target 9-month binding proof. It is the innovation lane the program has chosen.

---

## 7 · Open decisions

1. **Which novel orthogonal axis** — run the immune LLM's pair nominator to produce a *ranked, evidence-broken-down* menu of cross-modality partners (not the failed six). Decision gated on that output.
2. **Format** — combination of two single-target macrocycles (available now, correct for independent-blockade checkpoints) vs a bivalent/tumor-conditional single molecule (the harder, more novel, more defensible build). Rule: single molecule only if simultaneous engagement is required.
3. **Anchor** — if IO-native and peptide-precedented is required, PD-L1 remains the only checkpoint with clinical macrocycle precedent; the *novelty* must then come from the orthogonal partner + conditional format, not the anchor.

---

## 8 · Caveats & flagged-unverifiable (do not cite as fact)
- Rumored AZ–Summit ~$15B ivonescimab deal (press rumor, unfiled).
- BMS-986238 exact stage; its cited NCT is malformed/invalid.
- BT7455 clinical entry (preclinical/IND-enabling only, no NCT).
- Ensemble/Orbit/Pepscan IO programs (unverifiable — flagged, not fabricated).
- Some acasunlimab/tiragolumab discontinuation dates from trade press only.
- Network-separation sAB absolute values are small and module-definition-dependent (STRING distance-floor artifact for co-annotated immune genes) — quote the *ranking with caveat*, never a single number.
- "Better complement (PD-L1+CD47)" is mechanistic/topological, **not** proven clinical superiority (magrolimab failed).

## Key sources
Deals: Akeso/Summit, Merck (MK-2010), BioNTech IR, BMS/BioNTech, Pfizer/3SBio press + SEC filings. Combinations: CheckMate-214/743, RELATIVITY-047 (NEJM), IMbrave150 (J Hepatol), SKYSCRAPER-01 (Roche/PMID 42507968), KeyVibe (Merck), STAR-221/121 (Taiho/Gilead), ENHANCE (Gilead). Bispecifics: KIMMTRAK/IMDELLTRA FDA, cadonilimab/ivonescimab (Lancet/ASCO), Ziihera/Rybrevant FDA. Methods: Cheng–Barabási *Nat Commun* 2019, Menche *Science* 2015; in-vivo IO CRISPR (Manguso/Dong/Lawson). Platforms: Immunai, CytoReason, Turbine.ai, AION Labs (PRNewswire Mar 2025). Peptides: BT7480 (NCT05163041, PMID 34725211), BMS-986189 (AdisInsight/ACS 2025), WL12 (PMID 28025143), CD47 macrocycle (PMID 32640189), Baker/AlphaProteo de-novo binders. (Full URL list in the agent transcripts under `tasks/`.)
