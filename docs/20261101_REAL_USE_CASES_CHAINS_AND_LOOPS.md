# Real use cases for BioMate chains, search and loops

Date: 2026-11-01. Each use case follows one format: the person and need, inputs they hold, the steps (workflow or capability), where a person decides, the output, how success is
checked against a known answer, and an honest status. Status words: VERIFIED (run, result recorded), BUILT (code present, not run end to end), PLANNED (design only).
Related: `20261101_ORCHESTRATION_OVERVIEW_AND_UNIFICATION.md`, `20261101_USE_CASE_SURVEY_PROPOSE_MEASURE_PLAN.md`, `20261101_VINA_SCREENING_CHAIN_BENCH_SCENARIO.md`, `20261101_WORKFLOW_CHAIN_AUDIT.md`.

## UC1. Hit finding on a structurally characterised target (EGFR kinase)
- **Person and need.** A medicinal chemist or computational biologist holds a crystal structure and a few known inhibitors and needs a ranked shortlist from a purchasable library before ordering compounds.
- **Inputs.** PDB 1M17 (EGFR kinase with erlotinib); five reference actives; a library of about 300 compounds (actives and property-matched decoys).
- **Steps (chain `vina_virtual_screening_bench`).** Pocket detection and druggability -> pharmacophore filtering against the reference actives -> ADMET triage -> AutoDock Vina docking -> ranked hits.
  Two handoffs need conversions (file to inline SMILES list; pocket JSON to docking box), declared as named transforms.
- **Where a person decides.** Approve the target pocket and the library before spend; review a blocked ADMET gate; approve the shortlist before it enters a campaign.
- **Output.** A ranked list with docking scores, ADMET flags and the pocket used, plus the run's provenance.
- **Success check.** Redocked erlotinib within 2.0 A heavy-atom RMSD of the crystal pose; actives rank above decoys (AUROC and enrichment at 1% and 5%, with a random-baseline p-value; reference actives excluded from scoring).
- **Status.** BUILT in part by parallel workstreams (transforms, chain definition, data and scoring harness); no end-to-end run yet. The earlier audit found that as originally defined this chain family could not pass data between steps.
- **Known limits.** One target and one library; Vina scoring is a coarse filter, not a binding-affinity prediction; decoy bias is possible and is documented in the scenario manifest.

## UC2. Survey a topic, propose a study, use public data to measure and prepare
- **Person and need.** A researcher entering a field needs a cited overview, the open gaps, a proposed study and an early feasibility estimate from data that already exists.
- **Inputs.** A topic and a time window; permission to spend a stated amount.
- **Steps.** Literature search -> per-paper reading with verified quotes (fan-out) -> reviewer gate -> cited survey -> gap and novelty analysis -> *gate: choose the gap* -> study proposal with evidence-linked elements -> public dataset search (fan-out) -> feasibility measurement (counts, covariates, effect sizes, power, pilot) -> analysis plan, data manifest, report.
- **Where a person decides.** Scope; the evidence table; the gap; the proposal's assumptions; data and cost; go, revise or stop after the pilot; final sign-off (H1 to H7 in the plan).
- **Success check.** Time split: restrict the literature to before a cut-off, run the pipeline, and compare the proposed studies with work published afterwards, against a single-agent baseline. Report small samples as small.
- **Status.** PLANNED. Parts exist: federated literature search, grounded review with citation existence check (live 20/20 on real and fake references), ClinicalTrials.gov mirror (609,551 studies), per-document reader with quote verification (12 offline tests). The planner, gap and proposal steps and the gates are not built.

## UC3. Rank candidate targets for a disease with auditable evidence
- **Person and need.** A target-identification scientist needs a ranked list with the source of every claim, not an assertion.
- **Inputs.** A disease (and optionally an ontology id and candidate genes); optionally the group's own analysis tables or a finished analysis run.
- **Steps.** Parallel evidence channels (Open Targets disease association, STRING network, pathway, the group's tables, language-model reasoning) -> arbiter -> ranked targets with per-target source links -> optional validation plan (catalogue workflows that would test the top targets) -> optional drug-type suggestion (guidance only).
- **Where a person decides.** Choose which targets to take forward; approve any follow-on workflow run.
- **Success check.** Open Targets-primary ordering is the audited default; fusion has not been shown to beat Open Targets alone (0 of 17 cancers). The time-split gold set for novel targets was built but is too small to support or reject any novel-target claim (11 novel pairs, one disease with two or more).
- **Status.** VERIFIED for the route, channels and provenance (41 offline tests, live runs against Open Targets and STRING); NOT verified for novel-target discovery.

## UC4. Test whether a target's cell-type specificity predicts clinical progression
- **Person and need.** A portfolio scientist wants to know whether a published prior (switch-like, cell-type-specific target genes advance further in the clinic) holds on public data before using it to triage targets.
- **Inputs.** Full ClinicalTrials.gov registry; Open Targets drug and mechanism tables; Human Protein Atlas single-cell expression.
- **Steps.** Map trial interventions to drugs and targets -> compute specificity per target -> compare progression in the top specificity quartile against the rest, with a shuffled-label control.
- **Output.** Risk ratios with confidence intervals and the stated caveats.
- **Success check.** Pre-specified definitions and outcomes; agreement in direction and strength with the published claim.
- **Status.** VERIFIED as a run (1,884 drugs, 595 targets): risk ratios 1.07 (Phase 2+), 1.18 (Phase 3+), 1.17 (approved, interval 0.98 to 1.37), all in the published direction but smaller than the published effect; survivorship bias in the drug set compresses them. Not a validated triage tool.

## UC5. One campaign round: propose, make, test, learn
- **Person and need.** A project team running a compound series needs the next batch proposed, sent to a CRO, and the results folded back in.
- **Inputs.** The series' assay history and objectives.
- **Steps (a loop over a plan).** Propose a batch (multi-objective Bayesian optimisation) -> export the CRO order -> wait for assay data -> ingest assays -> retrain models.
- **Where a person decides.** Approve the batch before the order leaves; approve anything that is synthesised (always); review returned outliers; approve continue, stop or change objective at the end of each round.
- **Success check.** Held-out prediction error falls round on round; the optimiser states when its surrogate cannot discriminate between candidates.
- **Status.** BUILT (routes and optimiser exist and are live); not re-validated this session. Gates beyond the existing handoffs are PLANNED.

## UC6. Routine analyses as chains (examples)
`bulk_rnaseq_de_analysis` (rnaseq -> differential abundance -> enrichment), `rare_disease_multimodal_workup` (variant branch and expression branch joined in a case report),
`scrna_pseudobulk_de_bioc` (7 steps). **Status: PLANNED for repair.** The audit shows no recorded run for any of the 69 defined chains, and most connections name parameters the
downstream workflows do not declare; the repairs and a run per chain are in `20261101_CHAIN_FIX_PLAN.md`.

## Summary table
| Use case | Status | Evidence |
|---|---|---|
| UC1 Hit finding (EGFR, Vina chain) | BUILT in part | scenario spec; workstreams B1 to B3 |
| UC2 Survey, propose, measure | PLANNED | plan doc; parts built |
| UC3 Target ranking with provenance | VERIFIED (not for novel targets) | 41 tests; live runs; temporal gold too small |
| UC4 Specificity prior | VERIFIED as a run | result JSON and write-up |
| UC5 Campaign round | BUILT | routes live |
| UC6 Routine chains | PLANNED for repair | chain audit |
