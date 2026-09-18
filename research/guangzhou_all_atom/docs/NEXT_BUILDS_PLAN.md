# Next big builds — concrete plan (2026-09-18)

The three deliberate builds after cheap work was exhausted. Executed in parallel where resources allow
(A/B = AWS compute; C = codebase). Honest risk flags included.

## A. Conformation-aware permeability (2-environment) — the differentiator
**Goal:** beat the 2D permeability ceiling (R²0.45) and make N-methylation visible, via the chameleon signal
that single-environment/2D cannot capture.
**Method:** for a CycPeptMPDB subsample — generate conformers (ETKDG-macrocycle) → for the low-energy
conformer, build an OpenMM system (GAFF via openmmforcefields SystemGenerator) → **minimize in GBn2
implicit water (polar) AND in vacuum (apolar)** → compute 3D-PSA (rdFreeSASA polar-SASA) in each → features
= polar_3DPSA, apolar_3DPSA, and **polar−apolar Δ (the chameleon term)** → fuse with 2D → 5-fold shuffled CV
vs 2D-only. **The new thing vs the failed single-env test: the polar-vs-apolar Δ** (prior test lacked the
polar/GB state).
**Risk:** new toolchain (OpenFF/GAFF per peptide, GB minimize) — antechamber/param flakiness on macrocycles;
per-peptide try/except + small subsample + timeout + progress. Uncertain payoff (survey <2%-variance caveat).
**Success:** 2D+2env R² materially > 0.45 AND N-methylation Δ becomes positive on our designs.

## B. FEP finalist tier — rigorous binding arbiter
**Goal:** correct MM-GBSA's size bias and arbitrate the top designs before wet lab, at ~1 kcal/mol.
**Method:** ATM (Alchemical Transfer Method, OpenMM-based; the best-validated open peptide-RBFE per the
survey) relative binding between the MM-GBSA Pareto picks for one target (e.g. 1yf4: FSRNVGDPY vs SFEASGFAPM
vs GSGLLKS), on the CHARMM/psfgen-built cyclic complexes we already produce. Absolute-BFE (decoupling) as
the alt.
**Risk:** HIGHEST setup complexity/new toolchain (alchemical schedule, lambda windows, mapping) — like the
MM-GBSA saga but harder. **Staged, not blind-launched:** first a single-edge proof-of-concept on 1yf4, cheap
smoke of the ATM setup before scaling. GPU-heavy.
**Success:** ΔΔG on the Pareto edge with a sane error bar; ranking consistent-or-corrected vs MM-GBSA.

## C. Productionize MM-GBSA on BioMate — consolidation (low risk)
**Goal:** make the validated cyclic-peptide MM-GBSA a reusable BioMate capability (per
BIOMATE_CLOSED_LOOP_INTEGRATION.md).
**Method:** register the workflow in the workflow DB (`backend/database/galaxy_ai_tools.db`) following the
`amber_pmemd_md` entry pattern — name, domain=drug_discovery, params (receptor/peptide, pep range, igb),
steps, tags, container; add the nextflow files under `biomni_workflows/.../drug_discovery/amber_peptide_mmgbsa/`
(already written). Verify it surfaces via `search_workflow`.
**Risk:** low — codebase/DB work, no new science, no GPU. Main effort = matching the DB insertion schema.
**Success:** `search_workflow('protein peptide MM-GBSA')` returns it with correct params.

## Parallelization
- **A** launches now (AWS compute, differentiator).
- **C** proceeds as codebase in parallel (no compute conflict).
- **B** is planned + staged (single-edge ATM smoke first) — not blind-launched given its risk profile.
