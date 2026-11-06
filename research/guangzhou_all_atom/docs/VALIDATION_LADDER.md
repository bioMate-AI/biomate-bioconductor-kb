# Validation ladder — exhaust computation before wet lab

Correcting a real gap: I had been jumping from ML generation to "needs wet lab", skipping two
computational tiers (rigorous automated metrics AND physics/MD). Wet lab is the LAST rung, not the
next one. Only designs that survive the cheaper computational rungs earn synthesis.

## Rung 1 — automated de-novo metrics (cheap, no simulation)
- PepGLAD `cal_metrics`: DockQ, Consistency, Diversity (seq/struct/codesign), Cα-RMSD, Slide AAR.
- Self-consistency / designability: fold designs (ESMFold/AF) → scRMSD to the designed structure.
- Structural validity: clash score, bond/angle geometry, Ramachandran.
- Status: running the cyclic-model `cal_metrics` (`cyclic_official_eval.sh`); self-consistency +
  validity still TODO.

## Rung 2 — PHYSICS / MD (computational, previously skipped)
- **Force-field relaxation + energy + clash** — PepGLAD ships `evaluation/dG/openmm_relaxer.py`
  (OpenMM + CHARMM36, no license). Basis of the paper's "Success" metric. Run first — cheapest.
- **MD stability** — short MD (e.g. 1–5 ns) of the peptide–pocket complex; RMSD/RMSF stability
  tells us if a geometrically-plausible design is actually stable (catches false positives).
- **MM-GBSA / MM-PBSA ΔG** — physics-based binding free energy; far better than docking/ML proxy.
  (Full FEP is the gold standard but expensive — reserve for finalists.)
- **Conformational validation** — cyclic-peptide conformers vs **MacroConf NMR constraints**
  (collected) and MD ensembles.
- **MD-based permeability** — the RIGHT tool for our permeability wall: cyclic-peptide permeability
  is conformational ("chameleon" H-bond shielding), which a static ECFP model cannot capture but
  MD / implicit-solvent PMF / the **CycPeptMPDB-4D solvent sims** (collected) can. This likely
  explains why our ML permeability predictor is weak (R²0.23) — the signal is dynamical.

## Rung 3 — wet lab (last, only for survivors)
Synthesis (SPPS + cyclization), LC-MS/HPLC identity/purity, PAMPA/Caco-2 permeability, plasma
stability, solubility, and — with a chosen target — a binding assay. Seeds the DMTA loop.

## Assets we already have
PepGLAD OpenMM relaxer; MacroConf NMR (`datasets/macroconf/`); CycPeptMPDB-4D solvent sims;
BioMate's MD / docking / accelerated-stability / PK-PD workflows.

## Sequencing
Rung-1 metrics establish geometric quality → Rung-2 physics (relax → clash/energy → MD stability
→ MM-GBSA → conformational/NMR → permeability-MD) filters to physically-real, stable, plausibly-
permeable designs → only those go to Rung-3 wet lab. Physics is where our permeability question is
most honestly answered, and it costs GPU-hours, not months and CRO fees.


## Physics-relaxer note (2026-09-15) — root cause + redirect
Two physics runs failed: `evaluation/dG/openmm_relaxer.py:_minimize` HARD-CODES
`getPlatformByName("CUDA")` (ignores the constructor `platform` arg), and pip-installed OpenMM
lacks the CUDA platform plugin. Fix when we run it: `sed -i 's/getPlatformByName("CUDA")/
getPlatformByName(self.platform)/' evaluation/dG/openmm_relaxer.py` and use `platform='CPU'` (or
install a CUDA-enabled OpenMM). DECISION: do NOT re-run physics on the PepGLAD structures — they
are superseded by BoltzGen. Apply the physics/MD verify (relax→MD stability→MM-GBSA) to
**BoltzGen's** designs, where it is the non-circular oracle for BoltzGen's ML-predicted iptm/pae.
