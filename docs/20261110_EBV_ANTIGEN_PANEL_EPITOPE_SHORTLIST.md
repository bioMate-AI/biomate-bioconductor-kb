# EBV antigen panel — B-cell epitope + immunogen shortlist (SYSUCC)

**Date:** 2026-11-10
**Context:** running BioMate's new immunology workflows across SYSUCC's EBV program — the 6 canonical
EBV (B95-8) antigens — to produce a ranked B-cell epitope shortlist and a draft multi-epitope immunogen.
EBV+ nasopharyngeal carcinoma is SYSUCC's signature; the envelope glycoproteins **gp350, gB, gH/gL** are
the principal neutralizing-antibody / vaccine targets.

Workflows: `immunology/bcell_epitope_immunogen` (14667, linear) and `immunology/surface_epitope_mapping`
(14668, structure-based + discontinuous). Sequences are the canonical UniProt entries (verified headers);
structures are real PDBs. Run on real data; identical code to the AWS-Batch container.

## 1. Panel coverage (UniProt, verified)

| Antigen | Acc | Len | Linear B-cell epitopes |
|---|---|---|---|
| gp350/220 (BLLF1) | P03200 | 907 | 25 |
| gB (BALF4) | P03188 | 857 | 16 |
| gH (BXLF2) | P03231 | 706 | 18 |
| gL (BKRF2) | P03212 | 137 | 3 |
| EBNA1 (BKRF1) | P03211 | 641 | 9 |
| LMP2A (LMP2) | P13285 | 497 | 8 |
| **Total** | | | **79** |

## 2. Top panel-ranked linear B-cell epitopes (composite propensity)

| Rank | Antigen | Position | Sequence | Composite |
|---|---|---|---|---|
| 1 | gB | 401–423 | TPTSSPPSSPSPPAPSAARGSTP | 0.721 |
| 2 | EBNA1 | 378–401 | EKRPRSPSSQSSSSGSPPRRPPPG | 0.713 |
| 3 | gH | 211–224 | FSYPSLTSAQSGDY | 0.626 |
| 4 | LMP2A | 339–347 | CSSCSSCPL | 0.587 |
| 5 | gB | 803–812 | EQNQEQKRAA | 0.585 |
| 6 | gL | 63–76 | SLNSPKNGSNQLVI | 0.534 |
| 7 | LMP2A | 94–111 | DGLPPPPYSPRDDSSQHI | 0.533 |
| 8 | gB | 523–534 | ISVSQCVPVNQA | 0.529 |
| 9 | gp350 | 669–684 | PSSNPETLSPSTSDNS | 0.521 |
| 10 | gH | 634–645 | ITSQEVQNSILS | 0.521 |
| 11 | gL | 94–100 | KRSSSAL | 0.517 |
| 12 | gp350 | 714–723 | HVSTSSPAPR | 0.511 |

**Honest triage note:** several top hits are Ser/Pro/Thr-rich low-complexity, hydrophilic stretches (e.g.
gB 401–423, EBNA1 378–401 near the Gly-Ser/Arg repeats, gp350's O-glycosylated membrane-proximal stalk).
These score high on hydrophilicity/flexibility propensity but may be glycan-shielded or poorly immunogenic
in vivo — exactly why they must be triaged against the **structure/surface** map (§3) and confirmed by
ELISA/neutralization. For a neutralizing vaccine, prioritise the folded-domain, surface-exposed epitopes on
gp350/gB/gH/gL over the repeat/stalk regions.

## 3. Structure-based (conformational) epitopes on the key neutralization targets

Real Shrake-Rupley SASA + 3D clustering (`surface_epitope_mapping`, 12 Å CA-CA):

| Target (PDB) | Residues | Exposed | Linear patches | Discontinuous patches (truly disc.) |
|---|---|---|---|---|
| gp350 N-term / CR2 domain (2H6O) | 440 | 198 | 8 | 23 (21) |
| **gH/gL complex (5T1D)** | 1356 | 526 | 16 | **70 (68)** |

The gH/gL discontinuous patches span both chains and multiple sequence segments (e.g. a gH V213-seeded
patch of 9 residues across 6 segments) — genuine conformational epitopes the sequence-only path cannot see.
These are the shortlist to cross-reference with known EBV-neutralizing mAb footprints (AMMO1 on gH/gL;
72A1 on gp350 CR2 site) and to confirm experimentally.

## 4. Draft multi-epitope immunogen

Top 10 distinct panel epitopes (GPGPG-linked) → **198-aa protein + 603-nt codon-optimized mRNA**
(`docs/20261110_ebv_panel/immunogen_construct.json`). A computational starting construct only — no signal
peptide / adjuvant / UTRs / folding / immunogenicity validation; label and validate before use.

## 5. Artifacts
`docs/20261110_ebv_panel/`: per-antigen `*_epitopes.csv`, `bcell_epitopes_ranked.csv`, `immunogen_construct.json`,
and the discontinuous-epitope JSONs for gp350 (2H6O) and gH/gL (5T1D).

**Honest scope (both workflows):** linear = classic sequence propensity (Parker/Emini/Kolaskar/Karplus-Schulz/
Chou-Fasman), NOT a trained predictor; structural = real geometry (Shrake-Rupley SASA + 3D clustering), NOT a
trained conformational predictor (DiscoTope). Both are ranked shortlists to confirm by ELISA / neutralization,
never measured results.

Related: [[project_sysucc_modality_capability]] · docs/20261110_SYSUCC_BCELL_EPITOPE_IMMUNOGEN.md
