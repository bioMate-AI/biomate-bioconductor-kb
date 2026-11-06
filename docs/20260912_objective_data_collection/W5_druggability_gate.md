# W5 — Druggability GATE (modality-fit filter)

Role: **GATE** (modality-fit filter, not a learned score). Intended program modality: **cyclic peptides**. `training_eligible=false`.

Targets: **20**. Sources: BindingDB_All_202409 (S3, streamed single-pass, matched on UniProt accession), ChEMBL tractability, UniProt localization.

## Tallies

- **Small-molecule modality:** 5 — JAK1, JAK2, JAK3, BTK, S1PR1
- **Biologic modality:** 15 — IL6R, TNF, MS4A1, TNFSF13B, IL17A, IL23A, IL4R, IL5, TSLP, IL5RA, CTLA4, IFNAR1, IL1B, IL13, IL12B
- **PPI-interface targets (cyclic-peptide-relevant class):** 14 — IL6R, TNF, TNFSF13B, IL17A, IL23A, IL4R, IL5, TSLP, IL5RA, CTLA4, IFNAR1, IL1B, IL13, IL12B
- **Cyclic-peptide-fit CANDIDATES (heuristic):** 14 — IL6R, TNF, TNFSF13B, IL17A, IL23A, IL4R, IL5, TSLP, IL5RA, CTLA4, IFNAR1, IL1B, IL13, IL12B
- **Cyclic-peptide-fit LOW (heuristic):** 6 — MS4A1, JAK1, JAK2, JAK3, BTK, S1PR1
- **Small-molecule UNTESTED in BindingDB (NOT inactive):** 9 — IL6R, MS4A1, TNFSF13B, IL23A, IL4R, TSLP, IL5RA, IL13, IL12B

## Per-target

| Gene | Family | Modality class | SM ligandability | BindingDB potent<=1uM | Measured weak>=10uM | Distinct ligands | PPI iface | Cyclic-peptide fit |
|---|---|---|---|---|---|---|---|---|
| IL6R | cytokine receptor (IL-6Ra) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |
| TNF | TNF-superfamily ligand (trimer) | biologic-primary; small-molecule/PPI-inhibitor emerging | small-molecule-tractable (validated) | 1690 | 810 | 159 | yes | candidate-strong |
| MS4A1 | 4-TM cell-surface antigen (CD20) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | no | low |
| TNFSF13B | TNF-superfamily ligand (BAFF) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |
| JAK1 | tyrosine kinase (JAK) | small-molecule | small-molecule-tractable (validated) | 17675 | 773 | 943 | no | low |
| JAK2 | tyrosine kinase (JAK) | small-molecule | small-molecule-tractable (validated) | 19510 | 1949 | 1784 | no | low |
| JAK3 | tyrosine kinase (JAK) | small-molecule | small-molecule-tractable (validated) | 9831 | 2231 | 1253 | no | low |
| BTK | tyrosine kinase (TEC/BTK) | small-molecule | small-molecule-tractable (validated) | 20806 | 751 | 693 | no | low |
| IL17A | secreted cytokine (IL-17 homodimer) | biologic-primary; small-molecule/PPI-inhibitor emerging | small-molecule-tractable (validated) | 276 | 29 | 1 | yes | candidate-strong |
| IL23A | secreted cytokine (IL-23 p19/p40) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |
| IL4R | cytokine receptor (IL-4Ra) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |
| IL5 | secreted cytokine (IL-5) | biologic (antibody / Fc-fusion accessible) | small-molecule-weak/limited | 0 | 1 | 0 | yes | candidate |
| TSLP | secreted cytokine (TSLP) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |
| IL5RA | cytokine receptor (IL-5Ra) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |
| CTLA4 | Ig-superfamily costimulatory receptor | biologic (antibody / Fc-fusion accessible) | small-molecule-weak/limited | 1 | 0 | 0 | yes | candidate |
| IFNAR1 | cytokine receptor (IFNAR1) | biologic (antibody / Fc-fusion accessible) | small-molecule-weak/limited | 0 | 0 | 1 | yes | candidate |
| S1PR1 | lipid GPCR (S1P1) | small-molecule | small-molecule-tractable (validated) | 3987 | 2078 | 1515 | no | low |
| IL1B | secreted cytokine (IL-1b) | biologic-primary; small-molecule/PPI-inhibitor emerging | small-molecule-tractable (validated) | 408 | 20 | 7 | yes | candidate-strong |
| IL13 | secreted cytokine (IL-13) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |
| IL12B | secreted cytokine (IL-12/23 p40) | biologic (antibody / Fc-fusion accessible) | small-molecule-untested (no BindingDB small-molecule data) | - | - | - | yes | candidate |

## Discipline

- GATE not training label; training_eligible=false for every record.
- 'untested' != 'inactive': targets with zero BindingDB small-molecule rows are small-molecule-UNTESTED, NOT declared undruggable. Measured inactivity counted only from real weak values (>=10 uM) and '>' censored high values, reported separately per target.
- modality_class and cyclic_peptide_fit_heuristic are HEURISTICS from target class + localization + PPI-interface biology + BindingDB ligandability — NOT measured cyclic-peptide engagement.

## Caveats — what "druggable by cyclic peptide" actually requires that we DON'T have

- NO measured cyclic-peptide binding for any of the 20 targets. BindingDB affinities here are overwhelmingly small molecules; the counts prove the INTERFACE is chemically engageable, not that a cyclic peptide binds it.
- No structural epitope/hotspot analysis (interface area, hotspot residue density, pocket vs flat interface) — a flat interface can still be a poor cyclic-peptide site.
- No membrane-permeability assessment. Intracellular targets (JAK1/2/3, BTK) would require cell-penetrant macrocycles — an unsolved general problem; 'PPI-interface' heuristic does NOT rescue them.
- No selectivity / paralog cross-reactivity data (e.g. JAK1 vs JAK2, IL12B shared p40 with IL23).
- No developability (protease stability, half-life, manufacturability) or PK for a peptide format.
- BindingDB coverage is literature/patent-biased: absence of rows reflects what has been screened, not intrinsic undruggability.
- Target-family / PPI-interface / pocket flags are curated from established biology for these 20 well-characterized proteins; not machine-derived from a structure database.

