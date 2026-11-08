# 2026-10-31 BD use-case test log

Scope: BioMate **system functions** claimed in `docs/20261030_SYSUCC_BD_CAPABILITY_AND_USE_CASES_ZH.md` §§5–8.  
Runner: `scripts/test_sysucc_usecases.py`  
Raw results: `docs/qa/20261031-bd-usecases.json`  
Code under test: `/Users/kky/biomate-review` (local services + RDKit/scikit-learn). No LLM, Batch, GPU, or hospital data.

**Result: 51 passed, 0 failed, 0 errors.** Two layers remain blocked (not counted as failures).

These are software-contract checks. A catalogue hit is not a live workflow run.

## Map from BD brief to checks

| BD section | Claimed function | How it was tested | Result |
| --- | --- | --- | --- |
| 5.1 Search | Find a method in the indexed catalogue | `query_knowledge` for 12 hospital-relevant intents | 12/12 catalogue hits; all marked `execution_verified: false` |
| 5.2 Analysis | RNA-seq / DESeq2, single-cell / Seurat, proteomics, flow, clinical survival | Same catalogue queries | Hits include `deseq2_de_from_transcript_abundance`, `nf-core/scrnaseq`, `Analyze Flow Cytometry Immunophenotyping`, `survival_cox_proportional_hazards_regression` |
| 5.3 Design | ADMET, docking, cyclic peptide, antibody / nanobody / scFv | Catalogue queries | Hits include `Predict ADMET Properties (AI)`, `Docking Autodock Vina`, `cyclic_peptide_design`, `bispecific_antibody_design`, `Scfv Antibody Design` |
| 5.4 / 7.2 Models | Versioned train → review → promote / reject → rollback; hash check after “restart” | `CustomModelRegistry` on a temp DB | Failed gate stays rejected; blank reviewer blocked; rollback restores v1; tampered artifact refused |
| 6 Instruments | Workflows exist for the instrument classes we tell BD about | Catalogue queries (scRNA, proteomics, flow, cryo-EM, WGS) | Hits include `CryoSPARC Standard Single-Particle Analysis`, `nf-core/sarek` |
| 7.1 I 期 / BOIN | Dose-escalation support | Catalogue + description search | `clinical_trial_simulation` / `Adaptive Trial Design` (BOIN is in the registered description, not a separate workflow name) |
| 7.2 Assay ingest | Compare potency + safety files; reject bad rows | Existing Case 1 | nM→µM, B leads after safety, incomplete D does not become an unqualified #1 |
| 7.2 Learning loop | New assay batch changes the next proposal; do not fake rank | Existing Case 3 + `can_discriminate` | Scores change with labels; `can_discriminate=False` on this 3-compound fixture (honest) |
| 7.2 Evidence / PK | Extract study numbers without relabelling | Existing Case 4 | t½ 8 h, hERG 5 µM, rat, Cmax/AUC present, prediction not stored as measured, GLP not invented |
| 8.4 #10 salts / bounds | Salt vs parent; censored `<` | New `bd_assay_fidelity` | `CCO.Cl` and `CCO` share parent; compound Y flagged censored |

## Issues already fixed (this run is the regression check)

Logged earlier; **all green on this run**.

| Issue | Fix | Evidence on this run |
| --- | --- | --- |
| Incomplete compound (no safety) ranked #1 with score 1.0 | Coverage-aware rank (`COVERAGE_INCOMPLETE` behind complete) | `incomplete_safety_not_unqualified_best` passed |
| Negative IC50 / bad units accepted | Per-endpoint physical rules in `assay_schema` | `negative_potency`, `unsupported_unit`, `nonfinite` passed |
| Same compound ID, two structures ingested | Structure-identity clash | `conflicting_structure_identity` passed |
| Campaign adapter read `composite_score` (always 0.5) | Shared `RANKED_SCORE_KEY` | `campaign_uses_measured_labels` passed |
| Proposal rounds stuck at 1 | Adapter persists optimizer round | `campaign_round_identity` passed |
| AUC gate accepted missing / `inf` | Fail-closed `_evaluate_gate` | `missing_metric_gate`, `infinite_metric_gate` passed |
| Rat PK labelled human; Cmax/AUC dropped; “prediction only” stored as measured; GLP default true | Wet-lab ingester fidelity | four evidence checks passed |
| Every candidate got the same GP score | Morgan + Tanimoto GP; `can_discriminate` | Flag present and **False** here (best pairwise P = 0.597 < 0.95) |

## Issues found this run (not failures)

| # | Issue | Severity | Action |
| --- | --- | --- | --- |
| 1 | Catalogue search for “BOIN” returns `clinical_trial_simulation`, not a workflow named BOIN. Routing already maps `boin` → that workflow. Easy to over-claim “we have a BOIN workflow” from a loose token match. | Low | Keep BD wording: “dose-escalation / BOIN via clinical trial simulation.” Do not invent a separate product name. |
| 2 | Indexed **PKNCA workflow was not executed**. Generic R sandbox still may lack PKNCA. | Open | Blocked until authenticated project + indexed R-NCA container. Do not substitute local Python NCA. |
| 3 | **Chat / UI / uploaded-file journey not run.** `E2E_FIXTURE_PASSWORD` unset. | Open | Need fixture password; then one login, one project, chain: search → analysis card → assay ingest → model promote. |
| 4 | Catalogue hits are **not** live AWS Batch runs. Single-cell, cryo-EM, WGS, docking remain unexecuted in this log. | Expected | Next expensive tests only after a code review of the exact path; do not speculative-deploy. |
| 5 | `sqlalchemy` missing in this laptop Python; knowledge/literature extras warned and were not used. | Env | Does not affect the 51 checks. |

## What was not tested (on purpose)

- IND assembly (commented out).
- Hospital or patient data.
- Live literature / PubMed (BD §5.1 external search) — needs network policy from the hospital.
- GPU structure prediction, full nf-core/rnaseq, cryoSPARC.
- Connector / HIPAA MCP (separate repo).

## How to re-run

```sh
cd /Users/kky/biomate-review
python3 scripts/test_sysucc_usecases.py --output docs/qa/20261031-bd-usecases.json
# optional live sandbox only:
# python3 scripts/test_sysucc_usecases.py --live --output docs/qa/20261031-bd-usecases-live.json
```

## Next function work (priority)

1. Authenticated PKNCA indexed-workflow run (strongest open BD claim in §7.1 PK).
2. One real analysis workflow from §5.2 that does **not** need GPU (survival or DESeq2 on the prepared airway demo), after reviewing the path.
3. Keep extending this harness when a new BD claim is added — do not add a second SYSUCC runner.
