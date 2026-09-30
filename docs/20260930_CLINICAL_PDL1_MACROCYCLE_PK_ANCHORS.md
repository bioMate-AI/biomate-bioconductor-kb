# Clinical & Clinical-Stage Macrocyclic / Cyclic-Peptide PD-L1 Therapeutics — PK & Developability Anchors

**Date:** 2026-09-30
**Purpose:** Curated, citation-verified dataset of clinical (and closely adjacent) macrocyclic / cyclic-peptide PD-1/PD-L1 therapeutics, focused on **pharmacokinetics (PK) and developability outcomes — especially failures**. Built for a cyclic-peptide drug-design program to learn from *why* clinical macrocyclic PD-L1 peptides failed. The thesis being tested: the niche is open because **PK / half-life / oral developability is hard**, not because of efficacy or crowding.
**Machine-readable companion:** `research/guangzhou_all_atom/data/raw/clinical_pdl1_macrocycle_pk.json`

---

## Provenance & confidence contract

> **Every experimental value in this document is an EVAL-ONLY anchor. None of it — no sequence, structure, or PK number — may be used as model TRAINING data. Experimental measurements are held-out validation only.**

Each value carries a confidence tag:

| Tag | Meaning |
|---|---|
| **reported** | Directly stated with a primary source (peer-reviewed paper, PDB, ClinicalTrials.gov, ISRCTN, company disclosure) |
| **widely_stated** | Repeated across secondary sources; no clean primary source located |
| **inferred** | Reasoned from adjacent facts, not directly stated |
| **not_disclosed** | Not publicly available / not found |

**No DOI, PMID, NCT, or PK number in this document is fabricated.** All identifiers were checked against the live source (PMC, ClinicalTrials.gov API v2, ISRCTN, RCSB PDB). Where a value is unavailable it is written "not disclosed" / "not found". The **PAMPA / in-vitro vs in-vivo PK distinction is called out explicitly** wherever a permeability or half-life number appears.

---

## Headline finding (the "failure" story)

**The macrocyclic / cyclic-peptide route to PD-L1 has produced zero approved or late-stage clinical successes, and — critically — there is no public HUMAN in-vivo PK for any clinical peptide PD-L1 antagonist.**

- The lead peptide program (**BMS-986189 → BMS-986238**) required engineering an **albumin-binding fatty-acid tail** just to reach a viable half-life. Even the 2nd-gen compound's **first-in-human trial was terminated/suspended early with no human PK disclosed**.
- The "oral PD-L1" space that *did* generate clean human PK is dominated by **small molecules / peptidomimetics** (Incyte, Gilead, CA-170), **not true peptides** — and those largely failed on **safety (neuropathy)**, **strategic deprioritization**, or **disputed target engagement**.
- The only reported peptide half-lives are **preclinical animal** (BMS-986238 >19 h in rat/cyno) — the human number was never disclosed.

This is precisely the developability gap the program is targeting.

---

## 1. Summary table

| Compound | Sponsor | Modality | ~MW (Da) | PDB | Highest phase | Status | Discontinuation reason | Half-life | %F oral | Route | Key sources |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **BMS-986189** | BMS / PeptiDream | Macrocyclic peptide (1st-gen) | 1887 *(vendor, widely_stated)* | 8ALX (core=pAC65) | Phase 1 | **Suspended** | Short t½ (once-daily) + off-target CYP liabilities → superseded *(widely_stated)* | "short" — **no numeric human value** *(not_disclosed)* | not disclosed | not disclosed (likely IV/SC) | NCT02739373; PMID 37679783; PMID 38123744 |
| **BMS-986238** | BMS / PeptiDream | Oral macrocyclic peptide (2nd-gen); albumin-binding C18 tail | ~2979 *(widely_stated)* | none | Phase 1 (FIH, healthy vols) | **Terminated / suspended early** | Not disclosed (terminated before Parts B/C) | **>19 h in rat AND cyno (PRECLINICAL animal)**; **human not disclosed** | not disclosed (had oral+IV arm) | Oral (+IV comparator) | ISRCTN17572332; ACS Spring 2025 |
| **BMS macrocyclic peptide-57** | BMS (WO2014151634) | Macrocyclic peptide, 15-mer (tool cpd) | not disclosed | **5O4Y** | Preclinical/tool | N/A | N/A | not disclosed (IC₅₀ 9 nM) | — | — | PMID 28881104; PDB 5O4Y |
| **BMS macrocyclic peptide-71** | BMS (WO2014151634) | Macrocyclic peptide, 14-mer (tool cpd) | not disclosed | **5O45** | Preclinical/tool | N/A | N/A | not disclosed (IC₅₀ 7 nM) | — | — | PMID 28881104; PDB 5O45 |
| **BMS-986229** (¹⁸F) | BMS / MSK | ¹⁸F macrocyclic-peptide PD-L1 **PET tracer** (diagnostic) | 2297 | none (from 986189 chemotype) | Clinical imaging pilots | Diagnostic tool | N/A (tracer) | blood t½ **<2 h** (preclinical, in-vivo) | — | IV | PMID 38123744; NCT04161781 |
| **INCB086550** | Incyte | Oral **small molecule** (not peptide) | 694 *(widely_stated)* | none | Phase 1 | **Discontinued** | **Immune-mediated / peripheral neuropathy** *(reported)* | not estimated | not disclosed | Oral | PMID 42580817; NCT03762447 |
| **INCB099280** | Incyte | Oral **small molecule** | not disclosed | none | Phase 2 initiated | **Discontinued** | **Strategic** (not safety) | not estimated | not disclosed | Oral | PMID 42580817; NCT04242199 |
| **INCB099318** | Incyte | Oral **small molecule** | not disclosed | none | Phase 1 | **Discontinued** | **Strategic** (not safety) | **3.87 h QD / 3.92 h BID (human, in-vivo)** | not disclosed | Oral | PMID 42580817; NCT04272034 |
| **CA-170** (AUPM-170) | Aurigene / Curis | Oral **peptidomimetic** (not cyclic peptide); PD-L1 + VISTA | ~360 *(vendor, **suspect**)* | none | Phase 2a; Ph1 complete | **Dormant / deprioritized** *(inferred)* | **Disputed target engagement** (doesn't bind recombinant PD-L1) | preclin 3.4 h (mouse); **human ~4–9.5 h** | 50% *(mouse)*; human not disclosed | Oral | NCT02812875; PMID 31374878; PMID 34103659 |

*Non-qualifying reference compounds (peptide imaging tracers / never-clinical peptides): ⁶⁸Ga-NOTA-WL12, ¹⁸F-NOTA-NF12, AUNP-12, DPPA-1, GS-4224 — see §4.*

---

## 2. Per-compound detail

### 2.1 BMS-986189 — 1st-gen macrocyclic peptide (the anchor failure)

- **Sponsor / modality:** Bristol Myers Squibb (peptide from the BMS–PeptiDream collaboration); synthetic macrocyclic peptide PD-L1 antagonist. *(reported)*
- **MW / structure:** Vendor (MedChemExpress) lists MW **1887.21**, formula C₉₁H₁₃₁N₂₁O₂₁S, CAS 1629665-96-8, IC₅₀ 1.03 nM — all **widely_stated** (vendor, not primary). The related PET-tracer paper describes the chemotype as **~2 kDa** and reports **K_D < 10 pM by SPR** *(reported)*. Full clinical-compound sequence/SMILES **not disclosed**.
- **Structure (binding core):** The 15-residue macrocyclic **binding core, pAC65**, is crystallized with PD-L1 at 1.1 Å — **PDB 8ALX** *(reported)*.
- **Clinical:** Phase 1 single-ascending-dose study in **healthy subjects**, **NCT02739373** (n=76; started 2016-04-18, completed 2016-12-14). **No results posted** (`hasResults: false`). *(reported)*
  - *Note:* the ClinicalTrials.gov condition field reads "Severe sepsis" — almost certainly a registry-category artifact; the compound is an oncology PD-L1 program.
- **Status:** **Suspended at Phase 1** per PatSnap/Synapse R&D status; superseded by 2nd-gen BMS-986238. *(reported)*
- **Discontinuation reason:** **Short half-life** (required once-daily dosing) plus reported **off-target liabilities incl. time-dependent CYP inhibition** — a textbook peptide-developability failure that motivated the albumin-binding redesign. This framing is **widely_stated** (secondary reviews, ACS abstracts); **no numeric human t½ is public**.
- **PK:** Near-complete peripheral PD-L1 occupancy at low plasma concentrations in healthy volunteers *(widely_stated)*. Half-life "short" — **numeric value not disclosed**. Clearance, %F, Cmax, route: **not disclosed**.

> **⚠️ Data conflict (flagged):** A 2026 review ("One Face, Three Solutions", PMC13403227) states BMS-986189 is "currently in **Phase 2**" with "**prolonged half-life** and oral bioavailability" — but provides **no citation** for these claims, and they contradict the primary ClinicalTrials.gov + R&D-status data (Phase 1, suspended, short t½). The review likely conflates 986189 with the 2nd-gen 986238. **Treat the "Phase 2 / prolonged half-life" claim as unsourced; do not cite it as fact.**

**Sources:** [NCT02739373](https://clinicaltrials.gov/study/NCT02739373) · [PDB 8ALX](https://www.rcsb.org/structure/8ALX) · pAC65 paper PMID 37679783, DOI 10.1186/s12943-023-01853-4 (PMC10483858) · PET-tracer paper PMID 38123744, DOI 10.1007/s11307-023-01889-4 (PMC10973053) · review Sui et al. 2024, DOI 10.20892/j.issn.2095-3941.2023.0297 · conflicting review PMC13403227.

---

### 2.2 BMS-986238 — 2nd-gen oral macrocyclic peptide (the "rescue" that also stalled)

**This directly resolves the ~19-hour half-life question: it is ANIMAL PK (rat + cyno), NOT human. No human half-life is public.**

- **Sponsor / modality:** BMS; peptide originated in the BMS–PeptiDream collaboration. **Oral synthetic cyclic (macrocyclic) peptide** PD-L1 inhibitor, 2nd-generation. The ISRCTN registry confirms verbatim: "a synthetic cyclic peptide initially developed by PeptiDream Inc." *(reported)*
- **Design:** Engineered **albumin-binding C18 fatty-diacid tail + PEG linker** → reversible human-serum-albumin binding → extended half-life and oral viability. This is BMS's explicit rescue of the poor-PK first-gen. *(reported)*
- **MW / formula:** ~**2979.5 Da** *(widely_stated)*. Formula sources **conflict**: C₁₄₅H₂₂₈N₂₆O₄₀S (Drug Hunter) vs C₁₄₃H₂₂₄N₂₆O₄₀S (vendors). CAS 2919596-13-5. Sequence/SMILES **not disclosed**. No PDB.
- **Clinical registration — no NCT exists:** The ClinicalTrials.gov API returns **zero** studies for BMS-986238. Any "NCT…" cited elsewhere (including the biochempeg secondary source's "NCT0668458") is erroneous or points to unrelated drugs. The real registration is UK **ISRCTN17572332** (EudraCT 2020-004521-23; HRA ref QSC203717): Phase 1, first-in-human, **healthy volunteers** (up to 136 planned), single ascending dose + food-effect + **absolute-bioavailability (oral + IV) arm**. *(reported)*
- **Status:** **Terminated / suspended early** — "terminated prior to Part B and Part C being initiated"; ISRCTN lists "Suspended". **No human PK disclosed.** *(reported)*
- **Half-life:** **>19 h in BOTH rat AND cynomolgus monkey (PRECLINICAL animal)** — every source attributes the number to rat/cyno; traces to the **ACS Spring 2025** disclosure ("Discovery of BMS-986238…"). **Human t½ = not found** (trial terminated early). *(reported, animal)*
- **%F oral / clearance / Cmax / Tmax:** **not found** (qualitatively "highly protein bound," "lowered renal clearance"). *(not_disclosed)*

**Sources:** [ISRCTN17572332](https://www.isrctn.com/ISRCTN17572332) · HRA QSC203717 · ACS Spring 2025 "Discovery of BMS-986238…" (acs.digitellinc.com) · drughunter.com/molecule/bms-986238 · [biochempeg.com/article/441.html](https://www.biochempeg.com/article/441.html) *(correct on the "rat + cyno >19h" species attribution; **wrong on the NCT**)* · MedChemExpress (CAS/MW).

---

### 2.3 BMS macrocyclic peptide-57 and peptide-71 — the structural/SAR lineage

These are the **research/tool compounds** from BMS patent **WO2014151634A1 / US20140294898A1** (inventors Miller, Mapelli, Allen et al.) that seeded the whole BMS macrocyclic-peptide PD-L1 program. They are **not clinical candidates**, but their **co-crystal structures with disclosed (non-standard) sequences** are the most directly *learnable* structural anchors in this dataset.

| Peptide | Residues | PDB | IC₅₀ (PD-1/PD-L1) | Crystallized residue string |
|---|---|---|---|---|
| **peptide-57** | 15 | **5O4Y** | 9 nM | PHE-MAA-ASN-PRO-HIS-LEU-SER-TRP-SER-TRP-9KK-9KK-ARG-CCS-GLY-NH₂ |
| **peptide-71** | 14 | **5O45** | 7 nM | PHE-MEA-9KK-SAR-ASP-VAL-MEA-TYR-SAR-TRP-TYR-LEU-CCS-GLY-NH₂ |

All *(reported)*. Both deposited via **Magiera-Mularz et al., "Bioactive Macrocyclic Inhibitors of the PD-1/PD-L1 Immune Checkpoint," Angew Chem Int Ed 2017, 56:13732–13735 (DOI 10.1002/anie.201707707, PMID 28881104)**.

> **Correction to the original brief:** PDB **5N2D** and **5N2F** are **NOT** macrocyclic peptides — they are BMS **small-molecule (biphenyl-class)** PD-L1 inhibitors from Guzik/Holak et al., *J Med Chem* 2017, 60:5857–5867 (DOI 10.1021/acs.jmedchem.7b00293, PMID 28613862). Only **5O45** and **5O4Y** are the macrocyclic peptides. Keep them separate when building structural anchors.

**Sources:** [WO2014151634A1](https://patents.google.com/patent/WO2014151634A1/en) · [PDB 5O45](https://www.rcsb.org/structure/5O45) · [PDB 5O4Y](https://www.rcsb.org/structure/5O4Y) · PMID 28881104.

---

### 2.4 BMS-986229 — ¹⁸F PD-L1 PET tracer (diagnostic; same chemotype as 986189)

- **Modality:** ¹⁸F-labeled **macrocyclic peptide** PD-L1 **PET imaging radiotracer** (diagnostic, not therapeutic). **~2296.63 Da**. Derived from **BMS-986189** via propargylglycine + Cu-catalyzed azide-alkyne cycloaddition; paper states "no appreciable difference in binding parameters compared to its unmodified counterpart BMS-986189." *(reported)*
- **PK / biodistribution:** blood half-life **<2 h**, rapid non-target clearance (in-vivo, preclinical); tumor:background 5:1 at 90–100 min; 83–93% specific binding (mouse); effective dose 0.025 mSv/MBq. Human GBM pilot (n=12): tumor-to-normal-brain ratio 18.1 ± 10.1; avid 10/12. *(reported)*
- **Clinical:** imaging pilots only — **NCT04161781** (esophagogastric, MSK) = Completed. A GBM pilot paper cites **NCT02617589**, but that NCT is actually **CheckMate-498** (a Phase 3 nivolumab GBM *therapeutic* trial) — probable mis-cite; the imaging NCT is **unverified**. *(inferred)*

**Sources:** Kim J, Donnelly DJ, Tran T, et al., *Mol Imaging Biol* 2023;26(2):301–309, DOI 10.1007/s11307-023-01889-4, PMID 38123744 (PMC10973053) · PMID 38492018 (PMC11131584) · GBM pilot PMID 41003913 (PMC12474851) · [NCT04161781](https://clinicaltrials.gov/study/NCT04161781).

---

### 2.5 Incyte oral PD-L1 program — INCB086550 / INCB099280 / INCB099318 (small molecules, for contrast)

**Modality clarification (important):** all three are **true oral SMALL MOLECULES**, not macrocycles or peptidomimetics — verbatim in the Phase I paper: "three orally administered small-molecule PD-L1 inhibitors." They bind PD-L1 in 1:2 stoichiometry → dimerization/internalization (biphenyl-class hallmark). Included here because they are the "oral PD-L1" candidates that **did** generate human PK, and their failure modes are instructive contrast. **All three discontinued.**

| Compound | NCT / n | Phase & status | Discontinuation | Human PK (in-vivo) |
|---|---|---|---|---|
| **INCB086550** | NCT03762447, n=138 | Phase 1 — discontinued | **Immune-mediated / peripheral neuropathy** (nervous-system TEAE 10.1%) | Tmax 1–4 h; Cmax dose-proportional 100–800 mg; **t½ not estimated**; %F/CL not disclosed. In-vitro IC₅₀ 3.1/4.9/1.9 nM (human/cyno/rat). MW 693.81 *(widely_stated)* |
| **INCB099280** | NCT04242199, n=182 | Phase 2 initiated — discontinued | **Strategic** (2024 pipeline cut; not safety) | Tmax ~2 h; Cmax dose-dependent; **t½ not estimated**; %F/CL/MW not found |
| **INCB099318** | NCT04272034, n=104 | Phase 1 — discontinued | **Strategic** (explicitly not safety); minimal neuropathy | **t½ 3.87 h QD / 3.92 h BID** (only one with a reported t½); Tmax ~1 h; %F/CL/MW not found |

All Tmax/Cmax/t½ = **human in-vivo** from the Phase I paper. **Oral %F and clearance not disclosed for any of the three.**

**Sources:** Phase I paper *J Immunother Cancer* 2026;14(8):e015334, DOI 10.1136/jitc-2026-015334, PMID 42580817 (PMC13475261) · mechanism/IC₅₀: Koblish et al., *Cancer Discov* 2022;12(6):1482, DOI 10.1158/2159-8290.CD-21-1156 · NCTs above.

---

### 2.6 CA-170 (AUPM-170) — Aurigene / Curis oral peptidomimetic (disputed engagement)

- **Modality:** oral **peptidomimetic / amino-acid-inspired small molecule** (1,2,4-oxadiazole scaffold; L-Ser/D-Asn/L-Thr-derived). **Not a cyclic peptide.** Target: **PD-L1 + VISTA** (PD-L2 also claimed). *(reported)*
- **MW:** **not reliably disclosed.** A vendor lists 360.32 g/mol (C₁₂H₂₀N₆O₇, CAS 1673534-76-3), but this is **flagged suspect** (too light for the described peptidomimetic) — treat MW as **not found**.
- **Clinical:** Phase 1 **NCT02812875** (Curis; n=71; escalated to 2400 mg/day) = Completed; Phase 2a basket in India (cHL ORR ~30%; nsNSCLC signals); Phase 2b/3 nsNSCLC was *planned*. Program now appears **dormant/deprioritized** (no formal discontinuation announcement found — *inferred*).
- **Target-engagement controversy (the real "failure" lesson):** **Musielak et al., Molecules 2019, DOI 10.3390/molecules24152804, PMID 31374878 (PMC6695792)** found CA-170 does **NOT directly bind recombinant human PD-L1** by solution NMR/HTRF/cell assays even at 10× excess. The developer rebuttal (**Sasikumar et al., Commun Biol 2021, DOI 10.1038/s42003-021-02191-1, PMID 34103659, PMC8187357**) **acknowledges the negative solution-NMR data** and confirms CA-170 did **not** prevent PD-1:PD-L1 complex formation even at 100 µM in TR-FRET, proposing a "defective ternary complex" via cellular-context binding. **Net: direct biophysical binding to recombinant PD-L1 was never demonstrated; mechanism remains disputed.** *(reported)*
- **PK (verified against PMC8187357), with tags:**
  - **Mouse (in-vivo, oral):** %F **50%**; clearance 723 mL/hr/kg; Cmax 1723 ng/mL; oral AUC 19,574 hr·ng/mL. *(reported, mouse)*
  - **Preclinical t½ 3.4 h** — attributed to preclinical data, **NOT human**. *(reported, preclinical)*
  - **In-vitro plasma stability:** >95% remaining at 4 h (rat + human plasma). *(reported, in-vitro)*
  - **Human (in-vivo, Phase 1):** **t½ ≈ 4–9.5 h**, generally dose-proportional exposure. *(reported, human)*
  - Human absolute oral %F and human Cmax: **not found** (no IV comparator in Phase 1).

> **Conflict resolved:** the "3.4 h" is **preclinical/mouse**; the **human clinical** half-life is **~4–9.5 h** — both from the same 2021 paper. Do not conflate them.

**Sources:** [NCT02812875](https://clinicaltrials.gov/study/NCT02812875) · Musielak 2019 (PMC6695792) · Sasikumar 2021 (PMC8187357).

---

## 3. What is learnable (eval-only anchors + honest gaps)

### 3.1 Usable NOW as eval-only developability/PK anchors

1. **Co-crystal geometries with disclosed sequences (the strongest anchors):** PDB **5O45** (peptide-71, 14-mer, IC₅₀ 7 nM), **5O4Y** (peptide-57, 15-mer, IC₅₀ 9 nM), and **8ALX** (pAC65, the binding core of clinical BMS-986189). These carry crystallographically resolved sequences (with non-standard residues) and PD-L1 poses — usable for **structure-based binding-pose evaluation** and **CC′FG-face coverage** checks of generated macrocycles. *(These are the only entities in the set with both structure and sequence.)*
2. **Qualitative developability failure labels** (categorical eval labels, not fittable numbers):
   - BMS-986189 → **short-t½ failure** (+ CYP liability)
   - BMS-986238 → **required an albumin-binding lipid tail; human trial terminated**
   - CA-170 → **disputed target engagement** (doesn't bind recombinant PD-L1)
   - INCB086550 → **neuropathy safety failure**
   These are the right labels for a "will this class of design survive development?" eval — not for a regression target.

### 3.2 Honest gaps (do not paper over these)

- **No clinical macrocyclic/cyclic-peptide PD-L1 antagonist has public HUMAN in-vivo PK** (t½, %F, CL, Cmax). BMS-986189 is "short" qualitative only; BMS-986238's human PK was never disclosed (trial terminated).
- **The only reported half-lives are either (a) preclinical animal** (BMS-986238 >19 h rat/cyno; CA-170 3.4 h mouse) **or (b) from small molecules / peptidomimetics, not peptides** (INCB099318 3.87–3.92 h human; CA-170 4–9.5 h human). A peptide-design program cannot calibrate a human-t½ model on these directly.
- **Full covalent structures / SMILES of the CLINICAL peptides (986189, 986238) are NOT disclosed** → you cannot compute descriptors for the actual clinical entities; only the crystallized **binding cores** (pAC65, peptide-57/71) are available. This means "predict the clinical compound's permeability/t½" is not answerable from public data.
- **PAMPA vs in-vivo:** **no PAMPA / Caco-2 permeability data was found for any of the clinical peptides.** Any membrane-permeability modeling must lean on the external **CycPeptMPDB** set (already present at `research/guangzhou_all_atom/data/raw/CycPeptMPDB_Peptide_All.csv`) as a **PAMPA proxy** — and **PAMPA permeability ≠ in-vivo half-life**. Do not equate the two; a good PAMPA number did not save any of these compounds, because in-vivo t½ is driven by proteolysis/renal clearance/albumin binding, not passive permeability alone. That is exactly the developability gap.
- **One 2026 review makes an unsourced "Phase 2 / prolonged half-life / oral bioavailability" claim for BMS-986189** that conflicts with primary registry + R&D-status data (Phase 1, suspended, short t½). Do not treat the Phase 2 claim as fact.
- **Registry coverage is English-language:** Chinese (CDE) / Japanese (JAPIC) registries were not exhaustively crawled; a non-English early-Phase-1 oral PD-L1 macrocyclic peptide could exist and not surface here (*inferred* absence, not confirmed).

---

## 4. Non-qualifying reference compounds (for completeness)

True peptides with human data but as **diagnostic imaging tracers** (not antagonists), or peptides that **never reached clinic**, or small molecules already covered. Listed so the boundary of the dataset is explicit — **none are clinical therapeutic macrocyclic PD-L1 antagonists**.

- **⁶⁸Ga-NOTA-WL12** — PD-L1-binding small peptide PET tracer (cyclization not explicitly stated); first-in-human (9 NSCLC); effective dose 4.1 mSv; tumor SUVmax 1.84–5.47. PMID 34326125, DOI 10.2967/jnumed.121.262045 (PMC8973283).
- **¹⁸F-NOTA-NF12** — D-peptide PET tracer; first-in-human (NSCLC/esophageal). PMID 35831714, DOI 10.1007/s00259-022-05876-9.
- **AUNP-12** — branched 29-mer PD-1-derived peptide (Aurigene/Pierre Fabre); **never entered clinic**; preclinical mouse PK only.
- **DPPA-1** — academic 12-mer D-peptide; preclinical (in-vitro serum stability only). PMC11054459.
- **GS-4224 / evixapodlin** — Gilead oral **small molecule** (not peptide), PD-L1 dimerization; Phase 1 NCT04049617, **globally discontinued**; MW 691.6, IC₅₀ 0.213 nM; human PD reported, numeric human PK not found. PMID 38604815 (PMC11015256).

---

## 5. Provenance note (restated)

Every experimental value in this document and its JSON companion is an **eval-only anchor** — held-out developability/PK validation for the cyclic-peptide design program. **None of these records, sequences, co-crystal structures, or PK numbers may be used as model training data.** Confidence tags (`reported` / `widely_stated` / `inferred` / `not_disclosed`) are attached to every non-trivial value; no DOI, PMID, NCT, or PK number here is fabricated, and unavailable values are explicitly marked "not disclosed" / "not found."
