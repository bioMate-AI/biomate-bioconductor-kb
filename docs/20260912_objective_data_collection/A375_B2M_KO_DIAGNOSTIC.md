# A375 B2M-KO Immunopeptidome Diagnostic (PXD065279)

**Date:** 2026-09-13 · **training_eligible:** false (diagnostic/decision artifact)

## Question
The leave-HLA-out H4 gate FAILED largely because **one** point contradicted biology: A375 B2M-KO
immunopeptidome retained **88%** of presentation, while HAP1 B2M-KO collapsed to **3%**. B2M is
obligate for surface HLA-I, so a clean B2M-KO should collapse the HLA-I immunopeptidome. Is A375's
88% a technical artifact or genuine B2M-independent biology?

## VERDICT: **METHOD ARTIFACT** (not leaky-KO, not genuine biology)

The 88% is a **mild-acid-elution (MHC1-TIP) enrichment artifact**. The B2M knockout is **clean**
(zero residual B2M). The **true HLA-I ligand signal DID collapse** — genuine-ligand retention is
**~12%**, agreeing with HAP1's 3% and with H4. The apparent 88% is a large **B2M-independent
intracellular / non-HLA peptide background** that mild acid elution co-releases and that persists
when surface HLA-I is gone.

| Measure | Value | Meaning |
|---|---|---|
| HAP1 B2M-KO retention (W6/32 **IP**) | **0.028** | H4 PASS reference |
| A375 B2M-KO naive **total-peptide** retention (**MAE**) | **0.894** | the anomaly — *wrong measure* |
| A375 B2M-KO **genuine HLA-I ligand** retention | **0.119** | *true* signal — **collapses**, matches HAP1 |
| A375 B2M-KO **non-ligand background** retention | **0.676** | B2M-independent background that inflates the 88% |

## Evidence by check

### 1. KO completeness — CLEAN, not leaky
B2M protein is detected as 2 peptides in WT (`IQRTPKIQVYS`, `IQRTPKIQVYSRHPAEN`; spectral counts 2/1,
MS/MS). **Both are 0 spectral counts / 0 intensity / unmatched in the KO.** B2M is genuinely
eliminated → the 88% cannot be residual-B2M leakage.

### 2. Are the retained peptides genuine HLA-I ligands? — NO
- **Length:** WT peaks sharply at 9mers (30% 9mer, median 9) = canonical HLA-I. KO 9mer fraction
  **halves (30%→16%)**, median shifts 9→10 — degrading away from the HLA-I signature.
- **Motif / anchor match:** exact overlap of 8–11mers with mono-allelic ligands of A375's *own*
  alleles (A\*01:01, A\*02:01, B\*44:03, B\*57:01, C\*06:02, C\*16:01; 135,859 anchor ligands):
  WT **48.8%** → KO **12.0%**, a **4-fold** collapse in ligand quality.
- **A\*02:01 anchor:** pos-2 hydrophobic enrichment drops 49%→35%.
- **C-terminus:** WT dominated by Y/L/F anchors (12% K/R); KO loses the Y-anchor peak and enriches
  tryptic K/R and acidic D/S → shift toward non-HLA background.

### 3. Prep / metadata — ROOT CAUSE
PXD065279 = **MHC1-TIP**, enrichment by **mild acid elution** (131 mM citric acid / 66 mM Na₂HPO₄ /
150 mM NaCl / 25 mM iodoacetamide, pH 3.3; 10 kDa ultrafilter + C18). **No W6/32, no antibody IP**
for this A375 WT/B2M-KO pair (FragPipe DDA, Orbitrap Astral/Exploris). PRIDE metadata itself notes
**"identification of intracellular peptides post-mild acid elution"** and an MHC1-TIP-vs-IP
comparison. MAE co-releases a B2M-independent intracellular/membrane background that antibody-IP
excludes. HAP1 (the PASS set) used antibody pan-HLA-I capture → ~pure surface ligand → collapses to
3%. **Comparing MAE total-peptide retention to IP total-peptide retention is method-confounded.**

### 4. Recompute the 88% — robust for the WRONG measure; inverts when stratified
- Naive total: detection-count 0.894, spectral-sum 0.878, intensity 0.752 → the prior ~0.88 reproduces.
- **Stratified:** genuine-ligand retention **0.119** (868 WT ligands → 103 kept); non-ligand
  background **0.676**; 9mer-only 0.256. The "robust 88%" is robust only for total-peptide count;
  controlling for HLA-I ligand identity **flips the sign from "retained" to "collapsed."**

## Should this point be excluded from the gate? — YES (as scored)
- **Exclude** the A375 B2M-KO point **as it was scored** (naive total-peptide retention). It does not
  contradict H4; it is an apples-to-oranges enrichment method whose readout is dominated by non-HLA
  background.
- **Better fix:** re-score all deposits on **genuine-HLA-ligand retention** (anchor-matched 8–11mers)
  so MAE and IP become comparable — then A375 B2M-KO = 0.119, which **supports** H4.
- The load-bearing held-out HAP1 anti-correlation (transfer ρ = −0.92) in `LEAVE_HLA_OUT_RESULT.json`
  was **driven by this mis-measured point.** Removing it removes the *active contradiction*.
- **Caveat:** this does NOT by itself PASS the gate. After correction, H4 is **UNPROVEN /
  under-powered** (only HAP1 + this one re-scored A375 point carry a hard-essential collapse; still
  <3 independent hard-essential-KO backgrounds), not **CONTRADICTED**. Reclassify accordingly and
  still acquire ≥3 distinct HLA backgrounds × hard-essential KO panel (B2M/TAP1/TAP2/TAPBP) with a
  **consistent enrichment method** before claiming cross-HLA generalization.

## Limitations
Genuine-ligand set = exact-match to a finite mono-allelic anchor (conservative lower bound; applied
symmetrically to WT and KO). No NetMHCpan/MHCflurry affinity run (not installed) — used
anchor-overlap + anchor-residue heuristics; a 4-fold anchor-hit drop + halved 9mer fraction is very
unlikely to reverse under affinity prediction. Single WT/KO condition columns in the combined_peptide
table; cross-checked across count/spectral-sum/intensity.
