# Approved Cyclic-Peptide Drug Co-Crystals for the M2c Bound-Complex Training Set

**Date:** 2026-10-01
**Purpose:** Curate experimental co-crystal / cryo-EM structures (PDB) of **approved** protein-targeting cyclic-peptide drugs bound to their protein target, for folding into a target-conditioned cyclic-peptide generator's **bound-complex (receptor + cyclic peptide)** training corpus (M2c). These are premium, real-drug complexes.
**Verification:** Every PDB ID below was verified live against the RCSB data / GraphQL API (`https://data.rcsb.org`). No IDs are fabricated; drugs with no structure are marked "no co-crystal found." Resolutions in Å; chains are RCSB `auth_asym_id`s.
**Structured records:** `research/guangzhou_all_atom/data/approved_cocrystals.json`

---

## Honest count (of 34 drugs)

- **18 / 34** have a **direct co-crystal of the exact drug molecule** bound to its real target, with the peptide modeled as a polymer chain in the pocket.
- **+3 / 34** are covered by a **direct peptide-pharmacophore analog** (same active peptide moiety): Lu-177-dotatate and Ga-68-dotatate (→ octreotide/SSTR2) and pegcetacoplan (→ compstatin/C3b).
- **= 21 / 34 usable** for a receptor+cyclic-peptide bound-complex corpus.
- **13 / 34** have **no usable structure**: micafungin, anidulafungin, rezafungin, carbetocin, desmopressin, terlipressin, felypressin, vapreotide, linaclotide, plecanatide, romidepsin, motixafortide, rusfertide (most have a nearby pharmacophore precedent, noted below).

---

## (1) Master table

| # | Drug | PDB | Method | Res (Å) | Target (receptor) | Rec chain | Pep chain | Pep len | Suitable |
|---|------|-----|--------|---------|-------------------|-----------|-----------|---------|----------|
| 1 | Caspofungin | **9PE1** | cryo-EM | 3.09 | β-1,3-glucan synthase FKS1 (fungal) + Rho1 | A | H | 6 | ✅ (fungal target) |
| 2 | Micafungin | — | — | — | glucan synthase FKS1 | — | — | — | ❌ none |
| 3 | Anidulafungin | — | — | — | glucan synthase FKS1 | — | — | — | ❌ none |
| 4 | Rezafungin | — | — | — | glucan synthase FKS1 | — | — | — | ❌ none |
| 5 | Oxytocin | **7RYC** | cryo-EM | 2.9 | Oxytocin receptor (OXTR) + Gq | O | L | 10 | ✅ premium |
| 6 | Carbetocin | — | — | — | OXTR | — | — | — | ❌ none (7RYC analog) |
| 7 | Vasopressin | **7KH0** | cryo-EM | 2.8 | V2 receptor + Gs | R | L | 10 | ✅ premium |
| 8 | Desmopressin | — | — | — | V2 receptor | — | — | — | ❌ none (7KH0 analog) |
| 9 | Terlipressin | — | — | — | V1 receptors | — | — | — | ❌ none |
| 10 | Felypressin | — | — | — | V1a receptor | — | — | — | ❌ none |
| 11 | Atosiban | **9UWI** | cryo-EM | 2.8 | V1a receptor (V1aR) | A,B | C,D | 10 | ✅ premium (antagonist) |
| 12 | Somatostatin-14 | **7T10** | cryo-EM | 2.5 | SSTR2 + Gi3 | R | P | 14 | ✅ premium |
| 13 | Octreotide | **7T11** | cryo-EM | 2.7 | SSTR2 + Gi3 | R | P | 8 | ✅ premium |
| 14 | Lanreotide | **7XAV** | cryo-EM | 2.87 | SSTR2 + Gi | A | F | 9 | ✅ premium |
| 15 | Pasireotide | **8ZCJ** | cryo-EM | 3.09 | SSTR5 + Gi | G | A | 6 | ✅ |
| 16 | Vapreotide | — | — | — | SSTRs | — | — | — | ❌ none |
| 17 | Calcitonin (salmon) | **5II0** | X-ray | 2.1 | CTR ectodomain | A,B,C | D,E,F | 25 | ✅ (ECD; 7TYW full-TM alt) |
| 18 | Linaclotide | — | — | — | GC-C ectodomain | — | — | — | ❌ none |
| 19 | Plecanatide | — | — | — | GC-C ectodomain | — | — | — | ❌ none |
| 20 | Ziconotide | **7MIX** | cryo-EM | 3.0 | Cav2.2 (α1B) + α2δ1 + β3 | A | B | 25 | ✅ (= ω-conotoxin MVIIA) |
| 21 | Bremelanotide | **7F55** | cryo-EM | 3.1 | MC4R + Gs | R | L | 7 | ✅ premium |
| 22 | Setmelanotide | **7PIU** | cryo-EM | 2.58 | MC4R + Gs | R | P | 8 | ✅ premium |
| 23 | Ciclosporin (CsA) | **1CWA** | X-ray | 2.1 | Cyclophilin A (PPIA) | A | C | 11 | ✅ ideal (clean, small) |
| 24 | Voclosporin | **3ODI** | X-ray | 2.2 | Cyclophilin A (PPIA) | A | B | 11 | ✅ ideal |
| 25 | Romidepsin | — | — | — | HDAC1/2 | — | — | — | ❌ none (3RQD largazole precedent) |
| 26 | Motixafortide | — | — | — | CXCR4 | — | — | — | ❌ none (3OE0 CVX15 precedent) |
| 27 | Lu-177 dotatate | **7T11** | cryo-EM | 2.7 | SSTR2 | R | P | 8 | ✅ via pharmacophore (octreotate≈octreotide) |
| 28 | Ga-68 dotatate | **7T11** | cryo-EM | 2.7 | SSTR2 | R | P | 8 | ✅ via pharmacophore |
| 29 | **Eptifibatide** | **2VDN / 8T2U** | X-ray / cryo-EM | 2.9 / 3.1 | Integrin αIIbβ3 (GPIIb/IIIa) | A,B | C | 8 | ✅ **αvβ6 RGD precedent** |
| 30 | Zilucoplan | **9Y6C** | X-ray | 2.0 | Complement C5 (TE domain) | A | B | 17 | ✅ clean macrocycle |
| 31 | Pegcetacoplan | **7BAG** | X-ray | 2.0 | Complement C3 / C3b | A,B | C | 14 | ✅ via pharmacophore (compstatin CP40) |
| 32 | Rusfertide | — | — | — | Ferroportin (SLC40A1) | — | — | — | ❌ none (6WBV hepcidin precedent) |
| 33 | Thiostrepton | **2JQ7** | NMR (model) | — | L11 + 23S rRNA (bacterial) | A | C | 19 | ⚠️ direct but NMR model / protein+RNA |
| 34 | Nosiheptide | **2ZJP** | X-ray | 3.7 | 50S ribosome (L11/23S rRNA) | F(L11)+X(rRNA) | 5 | 13 | ⚠️ direct but 3.7 Å giant assembly |

**Key alternates** (better/secondary structures):
- Eptifibatide: **8T2U** (full-length αIIbβ3 in native lipids + eptifibatide, cryo-EM 3.1 Å) is *cleaner* than 2VDN (only chains A=αIIb, B=β3, C=eptifibatide; no Fab). 2VDM is the original; 2VDN is its re-refinement.
- Vasopressin: 7DW9 (V2R+AVP 2.6 Å), 7R0C (AVP-V2R-arrestin2).
- Octreotide: 8ZBE (SSTR5+octreotide 3.24 Å).
- Calcitonin: 7TYW / 7TYY (full-TM calcitonin-receptor core as amylin AMY1/AMY2 + full salmon calcitonin, len 33, cryo-EM 3.0 Å); 6PFO (CTR ECD + sCT 16–32).
- Ciclosporin: 2X2C and many others; calcineurin–CypA–CsA ternary complexes also exist.
- Ziconotide: 7MIY, 7VFU.
- Setmelanotide: 7PIV.
- Zilucoplan: 9Y6C primary citation is literally *"Discovery of Zilucoplan: A Complement C5 Inhibitor…"* — confirming the macrocycle (RCSB label "Ra30303") is the zilucoplan series.

---

## (2) Ranked shortlist — BEST co-crystals to add to the M2c bound-complex corpus

Ranking favors: (a) drug (or exact pharmacophore) modeled as a **polymer peptide chain** in the pocket, (b) clean receptor + peptide (minimal irrelevant chains), (c) good resolution, (d) manageable size.

**Tier 1 — add first (clean, high-res, peptide-as-polymer):**
1. **1CWA** — Ciclosporin / Cyclophilin A, X-ray 2.1 Å. The gold-standard small clean cyclic-peptide complex; CsA modeled as an 11-res polymer chain, single receptor domain.
2. **3ODI** — Voclosporin / Cyclophilin A, X-ray 2.2 Å. Same clean scaffold, second data point for the cyclosporin macrocycle class.
3. **9Y6C** — Zilucoplan / Complement C5 TE domain, X-ray 2.0 Å. Clean single receptor domain + 17-mer macrocycle; a large synthetic macrocycle class under-represented elsewhere.
4. **8T2U** — Eptifibatide / integrin αIIbβ3 (full-length, native lipids), cryo-EM 3.1 Å. Clean receptor (αIIb+β3) + cyclic KGD/RGD-mimetic octapeptide; RGD-integrin geometry. (See §3.)
5. **7PIU** — Setmelanotide / MC4R + Gs, cryo-EM 2.58 Å. Best-resolution GPCR–cyclic-peptide complex; cyclic 8-mer in a 7TM pocket.

**Tier 2 — premium GPCR–peptide complexes (strip Gα/Gβ/Gγ/scFv, keep receptor+peptide):**
6. **7T10** — Somatostatin-14 / SSTR2, 2.5 Å.
7. **7T11** — Octreotide / SSTR2, 2.7 Å (also covers Lu-177-/Ga-68-dotatate pharmacophore).
8. **7RYC** — Oxytocin / OXTR, 2.9 Å.
9. **7KH0** — Vasopressin / V2R, 2.8 Å.
10. **9UWI** — Atosiban / V1aR, 2.8 Å (antagonist-bound; adds an inactive-state exemplar).
11. **7F55** — Bremelanotide / MC4R, 3.1 Å.
12. **7XAV** — Lanreotide / SSTR2, 2.87 Å.
13. **8ZCJ** — Pasireotide / SSTR5, 3.09 Å.
14. **7BAG** — Compstatin CP40 / C3b, 2.0 Å (pegcetacoplan pharmacophore; clean receptor+peptide).

**Tier 3 — usable with caveats:**
15. **7MIX** — Ziconotide / Cav2.2, 3.0 Å (large channel; one clean disulfide-knotted peptide chain).
16. **5II0** — Salmon calcitonin / CTR ectodomain, 2.1 Å (ECD only; pair with 7TYW for the TM pocket).
17. **9PE1** — Caspofungin / FKS1, 3.09 Å (fungal enzyme target; giant membrane complex, extract pocket).
18. **2ZJP / 2JQ7** — Nosiheptide / Thiostrepton on the bacterial ribosome (3.7 Å X-ray / NMR model; protein+RNA receptor). Lowest priority; include only if ribosomal-RNA pockets are in scope.

**Preprocessing note for GPCR entries:** for 7T10/7T11/7RYC/7KH0/7F55/7PIU/7XAV/8ZCJ/9UWI, keep only the **receptor chain + peptide chain** (drop Gα/Gβ/Gγ, Nb35/scFv16, and any receptor fusion partners such as the SSTR2-KOR, B2AR-SSTR5, or BRIL/LgBit constructs) before adding to the corpus.

---

## (3) Eptifibatide → αvβ6 RGD cyclic-peptide program note

**Eptifibatide is the single most relevant approved-drug precedent for our αvβ6 RGD cyclic-peptide program.**

- **What it is:** a disulfide-cyclized heptapeptide (Mpr-Har-Gly-Asp-Trp-Pro-Cys-NH₂; modeled as an 8-residue chain in the PDB) carrying a **KGD** motif — a selective mimetic of the **RGD** integrin-recognition motif.
- **Target:** platelet integrin **αIIbβ3** (GPIIb/IIIa), an RGD-family integrin. Verified structures: **2VDN** (X-ray headpiece, 2.9 Å; chains A=αIIb, B=β3, C=eptifibatide, plus Fab 10E5 H/L) and **8T2U** (cryo-EM, full-length receptor in native lipids, 3.1 Å; chains A=αIIb, B=β3, C=eptifibatide — cleaner, no antibody).
- **Relationship to αvβ6:** αvβ6 and αIIbβ3 are both **RGD-binding integrins** sharing the conserved architecture — α-subunit β-propeller + β-subunit βI/βA domain with the **MIDAS / ADMIDAS / SyMBS** metal triad that coordinates the ligand Asp carboxylate. Eptifibatide/αIIbβ3 is the clinical proof that a **small disulfide-cyclized RGD/KGD macrocycle** can be an approved drug occupying an integrin ligand pocket at the MIDAS. The β-subunit differs (β3 vs β6) and αvβ6 is more RGD-selective (its specificity loop / RGD-pocket geometry in **4UM9** — per the ACT program notes — must be preserved, not trimmed), but **2VDN/8T2U give a real integrin + cyclic-RGD-peptide bound complex** from which the generator can learn Asp-to-MIDAS placement and the cyclic backbone pose. **Recommendation: add 8T2U to the corpus as the canonical RGD-integrin exemplar, and use it as a positive control when conditioning generation on αvβ6 (4UM9).**

---

## (4) GPCR–peptide cluster (high-value cryo-EM bound complexes)

The oxytocin/vasopressin family, the somatostatin analogs, and the melanocortins form a dense cluster of **recent cryo-EM GPCR–cyclic-peptide complexes** — exactly the premium bound complexes called for:

- **Oxytocin/vasopressin family:** 7RYC (oxytocin/OXTR), 7KH0 + 7DW9 (vasopressin/V2R), 9UWI (atosiban/V1aR).
- **Somatostatin analogs:** 7T10 (SST-14/SSTR2), 7T11 (octreotide/SSTR2), 7XAV (lanreotide/SSTR2), 8ZCJ (pasireotide/SSTR5), 8ZBE (octreotide/SSTR5).
- **Melanocortins:** 7F55 (bremelanotide/MC4R), 7PIU + 7PIV (setmelanotide/MC4R).

All are human receptors with the cyclic peptide modeled as a polymer chain in the orthosteric pocket; after stripping transducer/fiducial chains they are clean receptor+peptide training pairs.

---

## Method / provenance

- Candidate discovery: RCSB full-text search API (`search.rcsb.org/rcsbsearch/v2/query`) on each drug name + target name.
- Per-entry verification: RCSB GraphQL (`data.rcsb.org/graphql`) for experimental method, resolution, polymer entities (description, length, polymer type, `auth_asym_ids`, source organism) and non-polymer ligands — to confirm the drug is present and whether modeled as a peptide polymer chain vs. HETATM.
- Negative results ("no co-crystal found") reflect zero full-text matches for the drug name and no hit when searching the target class; they are honest absences, not unsearched gaps.
