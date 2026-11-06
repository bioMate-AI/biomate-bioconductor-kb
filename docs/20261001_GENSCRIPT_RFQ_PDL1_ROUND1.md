# GenScript RFQ — PD-L1 Round-1 Cyclic Peptides: Synthesis + QC + SPR Binding

**Purpose:** detailed request-for-quote covering synthesis → binding proof, with every GenScript deliverable
specified (verified from GenScript's QC and SPR service pages, 2026-10-01). Send Part A to
**peptide@genscript.com**, Part B to **protein@genscript.com** (1-732-885-9188), referencing one project so
they bundle it.

---

## What GenScript returns by default vs on request (verified)

**Peptide synthesis — STANDARD deliverable (included):** lyophilized peptide in vials · **COA** ·
**RP-HPLC chromatogram** (purity) · **MS spectrum** (MW/identity). Triple-QC by MS + HPLC during synthesis.

**Peptide — OPTIONAL add-on QC (request explicitly):** net peptide content (Amino Acid Analysis *or*
nitrogen analysis) · TFA→acetate counter-ion exchange + counter-ion quantification · solubility test
(water/PBS/DMSO free) · moisture / Karl Fischer · endotoxin (≤0.01 EU/µg) · pH · LC-MS/MS · stability.

**SPR/BLI — delivers:** ka (kon), kd (koff), **KD**, affinity ranking, Chi² (fit quality), **sensorgrams**,
kinetic data tables. Instruments: Biacore 8K+ (SPR) / Octet RH16 (BLI). Turnaround from ~8 days.

---

## PART A — Custom cyclic-peptide synthesis (to peptide@genscript.com)

**10 peptides, identical spec:**
- **Cyclization:** head-to-tail backbone amide (C-terminus → N-terminus macrolactam). **No free N/C termini;
  no acetyl or amide cap.** Please flag any sequence you expect low cyclization yield on, and propose a fix
  (e.g. a turn-inducing residue) before synthesis.
- **Residues:** canonical L-amino acids only.
- **Purity:** **≥95%** (RP-HPLC).
- **Amount:** **5 mg** each (net peptide).
- **Counter-ion:** **acetate — please do TFA→acetate exchange + report counter-ion content.**

**QC to return per peptide (standard + these add-ons):**
1. COA · RP-HPLC chromatogram · MS spectrum (standard)
2. **Net peptide content** (AAA or nitrogen analysis) — needed so we can set exact molar concentrations for SPR
3. **Solubility test** (water / PBS / DMSO)
4. **Counter-ion content** (confirm acetate, residual TFA)
5. (nice-to-have) moisture / Karl Fischer

**Sequences (N→C):**
| ID | Sequence | Priority |
|---|---|---|
| P01 | GAYTSKSTGVTF | **RUSH** |
| P02 | SSPFPVFKEFSP | **RUSH** |
| P03 | GGYTSSATGVTF | **RUSH** |
| P04 | ARTPEDLEEAVRTGKP | **RUSH** |
| P05 | LGVETSNPAIAELAKM | **RUSH** |
| P06 | GGSGEGKKLAEELGLK | **RUSH** |
| P07 | SAPEVLRPYSSNPK | standard |
| P08 | AAPEVLRKYTSLP | standard |
| P09 | SNGPAELEEAVGVKI | standard |
| P10 | SSNPAAKHIDPM | standard |

---

## PART B — SPR binding vs human PD-L1 (to protein@genscript.com)

- **Analytes:** the 10 cyclic peptides above (same project).
- **Target/ligand:** recombinant **human PD-L1 extracellular / IgV domain**, His-tagged or biotinylated for
  immobilization. **Please quote supplying SPR-grade PD-L1**; we can also provide it.
- **Assay design:** (1) **affinity ranking** (single concentration) across all 10 to identify binders; then
  (2) **full kinetics** (concentration series) on the binders → ka, kd, **KD**.
- **Return per peptide:** ka, kd, KD, Rmax, Chi², **raw sensorgrams**, and the ranking call — **for ALL 10,
  explicitly including peptides that show no binding** (report them as non-binders with the curves, do not omit).
- **Instrument:** Biacore 8K+ preferred.
- (Optional Part B2) **PD-1/PD-L1 competition assay** (ELISA or HTRF) on binders → % blockade / IC50 — quote
  separately.

---

## PART C — Data-return format (this is what closes our dry→wet loop)

Please return, as **one structured results table (CSV/Excel) + the raw files**:
- **Every peptide, every step, including all failures and non-binders** — do not pre-filter to successful ones.
- Per peptide: synthesis outcome (made / cyclized Y/N) · **failure mode if any** (e.g. poor cyclization yield,
  aggregation, deletion sequence) · final purity % · measured mass · net peptide content · solubility · SPR
  ka/kd/KD/Chi²/binder-call.
- **Raw traces:** HPLC chromatograms, MS spectra, SPR sensorgrams (exportable data, not just images).

We use every outcome as data (negatives and failures included), so the complete set matters more than the hits.

---

## PART D — Commercials / logistics (please quote)

1. Price + lead time for **Part A** (synthesis only, 10 peptides).
2. Price + lead time for **Part A + B bundled** (synthesis → SPR).
3. **Rush/express** option + lead time for **P01–P06** specifically.
4. Door-to-door lead time **including shipping** to our location.
5. Batch/library discount for ordering all 10 together.
