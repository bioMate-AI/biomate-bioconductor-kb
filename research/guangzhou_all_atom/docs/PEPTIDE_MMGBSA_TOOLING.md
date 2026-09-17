# Protein–(cyclic)peptide binding free energy — what the field does, and our adopt-vs-build decision

Cited survey (2026-09-17) triggered by the finding that BioMate's MM-GBSA workflows are small-molecule-
ligand-only (GAFF2/antechamber), which is wrong for a peptide binder. Question: adopt an existing tool or
hand-roll? Answer: **adopt `gmx_MMPBSA` for scoring; use a validated builder for the macrocycle; tier
MM-GBSA→FEP.** My hand-rolled `amber_peptide_mmgbsa` tleap+`:LIG` draft is **superseded** by this.

## 1. Scoring engine → adopt `gmx_MMPBSA` (do NOT hand-roll)
`gmx_MMPBSA` (Valdés-Tresanco et al., *JCTC* 2021, 17:6281; DOI 10.1021/acs.jctc.1c00645):
- Receptor/ligand are **GROMACS index (`.ndx`) groups** — chains/residue selections; the peptide is just
  "a second protein treated as the ligand," inheriting the **protein force field** (ff14SB/ff19SB/CHARMM36).
  **No GAFF2.** This is exactly the peptide case, already solved by a maintained tool.
- **Single-trajectory (ST)** default (intramolecular terms cancel; snapshots from the complex traj).
- GB model: **`igb=8` (GB-Neck2 + mbondi3)** preferred for protein–protein/peptide interfaces (igb=2/5 also fine).
- **Entropy: drop for ranking** (expensive/noisy, cancels across similar designs); Interaction Entropy is the
  cheap add-on if a pseudo-absolute value is wanted.

## 2. System building (the macrocycle) → CHARMM-GUI (robust) vs validated tleap (automatable)
- **CHARMM-GUI** (Lee et al., *JCTC* 2016; PDB Manipulator, *JMB* 2023) applies patches for **head-to-tail
  cyclization, N-methylation, D-AA** and exports matched AMBER/GROMACS inputs — the low-risk builder.
  **Caveat for us: it's an interactive web service — not headless-scriptable in a Nextflow container.**
- **Hand-written tleap `bond` recipe** is automatable but error-prone: loading a cyclic peptide makes tleap
  treat the ends as terminal residues and auto-add **OXT + extra terminal H** that must not exist once
  head↔tail are bonded (AMBER mailing-list consensus). Correct recipe: strip OXT/terminal H → force
  *internal* residue templates for first/last → explicit `bond mol.1.N mol.last.C`. Non-natural residues
  additionally need custom `.prep`/`frcmod`.
- **Implication:** for an automated pipeline over standard-AA cyclics, a *validated* tleap recipe is the
  scriptable path; CHARMM-GUI is the manual pre-step for non-natural/complex cases. (My earlier draft's
  naive `bond` without terminal-atom handling was exactly the documented trap.)

## 3. MM-GBSA accuracy for peptides (ranking, not absolute)
Sun et al., *PCCP* 2019 ("MM/PBSA … part 9", 53 protein–peptide complexes): size-dependent — short peptides
(5–12 res) best via MM/PBSA on minimized structures (rₚ≈0.748); medium (20–25) via MM/GBSA on MD (rₚ≈0.735).
*(rₚ from a search snippet — confirm against the primary article before formal quoting.)* Use MM-GBSA to
**rank/triage only**; charged interfaces and flexible/macrocyclic ligands (conformational entropy) are the
weak spots.

## 4. FEP for cyclic peptides (finalist tier)
- **Schrödinger FEP+**: macrocycle/cyclic-peptide RMSE_ΔΔG **1.06 kcal/mol** (5-target retrospective, >230
  analogues, PubMed 42396675); cyclophilin macrocycles MUE≈1.1 (*JCIM* 2020). FEP+ Biologics branch for peptides.
- **Open-source**: **ATM/ATM-RBFE + ATS extension** (Gallicchio; *JCIM* 2022 10.1021/acs.jcim.1c01129; ATS
  *JCIM* 2025) — OpenMM-based, validated on protein–peptide RBFE, **the most peptide-relevant open method**.
  OpenFE/perses exist but peptide-macrocycle accuracy is **less validated** (verify on our own set).

## Validated verify stack (funnel)
1. **Build** each design — validated tleap cyclic recipe (standard-AA, automatable) or CHARMM-GUI (non-natural, manual).
2. **Triage** — short explicit-solvent single-traj MD + **`gmx_MMPBSA` (igb=8, entropy off)** → *relative ranking*.
3. **Finalists** — **FEP+ or ATM/ATS** at ~1 kcal/mol RMSE.

## Revised BioMate contribution (supersedes the hand-rolled draft)
- **Discard** the `MMPBSA.py`+`:LIG` masking in the parked `amber_peptide_mmgbsa/main.nf`.
- **New workflow = wrap `gmx_MMPBSA`**: run short AMBER/GROMACS MD of the complex (reuse the amber min/equil/
  production stages) → `gmx_MMPBSA` with peptide as a chain group (igb=8, ST, entropy off). System build via a
  validated cyclic-tleap step (standard-AA) with a documented CHARMM-GUI fallback for non-natural.
- FEP tier (ATM open-source) is a separate, later workflow for finalists — not v1.

## DECISION (2026-09-17) — build via CHARMM-GUI mechanism; smoke test confirmed the tleap trap
Cheap CPU smoke test (`build-smoke-20260917T203824Z`, ~$0.05) on a real design (1yf4 `GSGLLKS`):
the naive automated tleap recipe (`remove` OXT/terminal-H + `bond N.1 C.last`) **FAILED to build** —
`Could not find bond parameter for atom types: N3 - C` (+ CX-N3-C, H-N3-C angles) for BOTH peptide
and complex. `N3` = tleap's charged N-terminal ammonium type; tleap always applies terminal patches,
so the head-to-tail `N3–C` bond is unparametrized in ff19SB. This empirically confirms the survey:
**do not hand-roll tleap cyclization.**

Chosen path = **CHARMM-GUI-mechanism build**. Two realizations:
- **(A) Manual CHARMM-GUI pre-step** (robust, immediate): a human runs CHARMM-GUI Solution Builder on
  the receptor–cyclic-peptide complex (it applies the head-to-tail patch + N-methyl/D-AA patches and
  exports AMBER/GROMACS inputs), uploads the bundle to S3; the BioMate workflow consumes it and
  automates minimize→equilibrate→production MD→gmx_MMPBSA. Not batch-friendly (manual per complex).
- **(B) Headless psfgen equivalent** (automatable): CHARMM-GUI is a front-end to CHARMM/psfgen. psfgen
  can build the peptide segment with **`first NONE last NONE`** (NO terminal patches → internal `N`/`C`
  types, avoiding the `N3` trap) then apply a **head-to-tail patch** (delete terminal O/H, form the C–N
  amide, `regenerate angles dihedrals`). This reproduces CHARMM-GUI's mechanism scriptably (CHARMM36m).
  gmx_MMPBSA accepts CHARMM psf inputs. Needs its own cheap smoke test (like the tleap one) to validate.

Recommended: pursue (B) for an automatable BioMate workflow, validated by a psfgen smoke test; fall
back to (A) manual CHARMM-GUI for non-natural chemistry until (B) is proven. Downstream MD + gmx_MMPBSA
(igb=8, single-traj, entropy off) is unchanged either way.

## Honest flags
- rₚ correlation numbers are from a snippet — confirm before formal use.
- OpenFE/perses peptide accuracy unverified — ATM/ATS is the better-validated open FEP for peptides.
- CHARMM-GUI is not headless-automatable — the automated pipeline needs the validated tleap recipe; this is
  the real open decision for the workflow build.
