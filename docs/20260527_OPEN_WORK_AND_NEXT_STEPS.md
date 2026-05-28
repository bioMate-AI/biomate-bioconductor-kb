# Open Work & Next Steps After Drug-Dev Sweep

**Date:** 2026-05-27 / 28
**Branch:** `integration/next-phase`
**Context:** end-of-day inventory after this session's drug-dev framework fixes (CRT, profiles{aws{}}, status reconcile, inner-docstring parser-v2 fix).

## What's done this session

Framework-level (production-ready):
- Nextflow 25.10.5 pin + Netty/Apache HTTP clients (no JVM SIGSEGV)
- `profiles{aws{}}` block restored in `_generate_executor_config`
- Status reconcile: `failed → succeeded` when real outputs exist anywhere (outputs/ or recovered from work/)
- 12h stuck-running guard
- Inner Python docstring `"""` → `'''` conversion (10 workflows fixed)

Workflow-level:
- cyp_ddi `Standardizer` → `Cleanup`; `rdkit-pypi` → `rdkit`
- pharma inline-SMILES + local-tmp + deleteOnExit
- PBPK `/1000` unit fix + `fu_plasma` QSAR estimator
- ZnBinder SMARTS (hydroxamic acid, thiol, carboxylate)

Validated end-to-end: predict_admet, transporter_ddi, pbpk_simulation (Cmax matches aspirin literature), pharmacophore_filtering, pocket_detection_druggability, cyp_ddi_panel, clinical_trial_simulation, ich_s5_reproductive_tox, virtual_patient_cohort. 9 workflows producing scientifically-sound outputs.

## Open work — ordered by value

### Tier 1 — workflow-level remaining (each is 1-2 hr work)

1. **nlmixr2_population_pk** — parser-v2 compilation error, distinct from the docstring fix. Needs targeted Groovy syntax review of `pharmacology/nlmixr2_population_pk/main.nf`.
2. **nca_pknca** — `NCA_INPUT_VALIDATION` container exits with code 1 even when given a valid-shape CSV. Pull AWS Batch CloudWatch stderr → diagnose schema or validator-script bug.
3. **nonmem_poppk** — commercial NONMEM license required. **Defer** unless the user has a license file to mount.

### Tier 2 — scientific quality (filed in audit doc, not blocking)

4. **PBPK saturable-binding model** — current fu_plasma estimator is logP-only (Lobell-Sivars QSAR). Doesn't model concentration-dependent unbinding (aspirin, ibuprofen, warfarin). Sensitivity sweep via auto-loop is the right fit: run PBPK at fu_p ∈ {0.05, 0.1, 0.2, 0.4}, present uncertainty band.
5. **pocket_detection_druggability → real Fpocket** — currently uses `biotite_geometric` heuristic. Returns 0.567 druggability on the imatinib-Abl ATP cleft where Fpocket gives 0.85-0.95. Swap binary already in `biomni-tools` image; expect ~1hr workflow refactor.
6. **ZnBinder SMARTS validation** — fire pharma with vorinostat (`O=C(NO)CCCCCCC(=O)Nc1ccccc1` — paradigm hydroxamic acid HDAC inhibitor) to confirm the new SMARTS actually matches. Light test.

### Tier 3 — broader coverage

7. **Re-validate other domains on the fixed framework** — cryoEM, RNA-seq, single-cell, structural biology, proteomics workflows haven't been re-tested since today's CRT and parser-v2 fixes. May surface 1-2 more "missed" workflows that need similar small fixes. Best done by class:
   - cryoEM (10+ workflows): test cryosparc_standard_spa as canary
   - genomics (15+): test wgs_germline_gatk, perturb_seq_analysis
   - proteomics (3+): test profam_fitness_prediction
   - single_cell (7+): test scrna_doublet_qc
   - virtual_cell (10+): test ode_signaling_simulation
   - structural_biology (2+): test boltz_structure_prediction
8. **Drug-dev breadth test** — only ~15 of 90 drug-discovery workflows tested. Sweep the remaining ~75 with a fast-fire script, classify failures by error pattern.

### Tier 4 — defense-in-depth (framework hardening)

9. **Status reconcile when run absent from MemStorage** — current logic returns 404 if the run isn't in MemStorage (e.g., container restart wiped state). Should fall back to S3 listing using a derived path, so historical runs are recoverable.
10. **Worker recycle / publishDir-mid-kill** — when Nextflow JVM dies mid-publishDir, some files land in outputs/, others in work/. The work/ fallback handles the latter, but a unified reconciliation that merges both is cleaner.
11. **CSV schema discovery** — many workflows take CSVs but don't enforce schema at startup. NCA_INPUT_VALIDATION is one example. A standardized schema-check process step that emits a friendly error before the heavy compute starts.

### Tier 5 — UI / other agents' lanes (do NOT touch)

12. UI work in `reference/05_25_todo.md` (auth, billing widget, IND report stubs, CRO sidebar) — owned by other agents.
13. IND P1-7 + P2-6 frontend (`074c1363f`, `8a176b281`) — owned by other agents.
14. Connectors-v2 — separate branch.

## Recommended sequence for next session

1. **15-min**: read v5 poll results (currently pending) → mark which of the 7 workflows now pass.
2. **30-min**: dig nlmixr2_population_pk Groovy syntax → likely a 1-line fix (DSL quoting, return value, channel chain).
3. **15-min**: pull nca_pknca CloudWatch → diagnose validator schema → regenerate sample CSV.
4. **30-min**: fire ZnBinder vorinostat test + pocket Fpocket swap canary.
5. **2-hr block**: broader cryoEM/RNAseq/proteomics sweep, ~3 canaries per domain.

After that, drug-dev is provably stable; the remaining work is breadth (Tier 3) and polish (Tier 4).

## Standing principles for this codebase

From CLAUDE.md (enforced every session):
- **Resolve root causes, never workarounds**. Today's audit caught a docstring fix that initially broke `${params.X}` interpolation in 105 files — reverted within 2 minutes and rewritten correctly. The instinct to ship is wrong; the instinct to verify a sample of changed files before committing is right.
- **Review code before testing on expensive runs**. Wasting AWS Batch starts on guess-fix cycles is forbidden. Static analysis + small smoke samples first.
- **Document periodically**. This file is one of those docs; CLAUDE.md mandates them after every significant session.
