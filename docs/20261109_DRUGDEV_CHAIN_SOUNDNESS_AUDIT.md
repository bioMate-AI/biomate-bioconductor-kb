# Drug-development multi-phase chains — deployment & soundness audit

**Date:** 2026-11-09
**Scope:** verify the multi-step/phase drug-development chain capability is deployed on dev and sound (runs steps, passes data between phases, produces correct results).
**Method:** read the engine, submit real chains to the live dev engine (`/api/workflows/chain`) as the E2E fixture, poll to completion, inspect per-step state and the inter-phase data handoff; plus an offline audit of all drug-dev/pharmacology chain-template connections against the real workflow param schemas.

## Verdict

| Layer | State |
|---|---|
| **Deployment** | ✅ sound — engine (`workflow_chain.py`), DAG engine (`galaxy/chain/dag.py`), `chain_planner.py`, orphan reconciler, `_PARAM_TRANSFORMS`, and all **70 chain templates** are on dev. |
| **Engine mechanics** | ✅ sound — resolves workflow name → nextflow_path, runs steps sequentially (and DAG), **pre-validates each connection's `to_input` against the target workflow's declared params and fails fast** with a precise error. A valid 2-step chain (ADMET→CiPA) ran both steps to `succeeded`. |
| **Inter-phase data handoff** | ❌ **largely non-functional for drug-dev chains** — the actual value of a multi-phase chain. Two independent defects below. |

## Defect 1 — 11/24 template connections reference non-existent target params (hard fail)

Audit of every output→input connection in the 19 drug_discovery + 3 pharmacology chain templates: **11 of 24 connections** name a `to_input` that the target workflow does not declare or reference anywhere in its `.nf`. Confirmed live: the `admet_to_cipa_cardiac` chain ran step 1 (ADMET) to success, then the engine rejected the connection — `admet_results → admet_context`, and `cipa_cardiac_safety_ode` declares no `admet_context`. 7 templates affected:

| Template | Broken `to_input` |
|---|---|
| `target_to_lead_full` (6-step flagship) | GROMACS MD ← `docked_poses` |
| `admet_to_cipa_cardiac` | CiPA ← `admet_context` |
| `rnaseq_to_lincs_moa` | differentialabundance ← `counts` |
| `pbpk_renal_impairment_chain` | ← `pk_parameters`, `pk_model` |
| `phase2_dose_justification_chain` | ← `er_model`, `phase3_predictions` |
| `target_tractability_assessment` | AlphaFold ← `candidate_targets` |
| `mrna_codon_optimization_chain` | ← `candidate_constructs` |
| `cyp450_ddi_chain` | ← `in_vitro_ddi`, `human_pk` |

These chains run their first step and then hard-fail at the wiring to the next step — as stored they cannot complete end-to-end.

## Defect 2 — valid connections silently no-op; chain still reports `succeeded`

A corrected 2-step chain (ADMET → CiPA, wiring only the valid `herg_ic50_nM`) reported **`succeeded`** — but step 2's `handoff_warnings` held `"No artifact 'herg_ic50_nM' found from step 1"`, step 1's `artifacts` was `{}`, and CiPA ran on its **default** `herg_ic50_nM` (1000 nM), not the ADMET prediction.

Root cause: `_apply_connection_handoffs` matches `from_output` against the upstream's published **filenames** (`pick_artifact_file`). The templates author connections semantically (`from_output: herg_ic50_nM`), but ADMET publishes `admet_results.json`, not a `herg_ic50_nM` file — so no match, soft warning, fall back to default. A scalar handoff needs the real upstream output filename **plus a transform** to extract the scalar; the templates have neither.

So a multi-phase chain can report `succeeded` while **no data actually passed between phases** — a silent false success. The `handoff_warnings` are not surfaced to the user and do not gate success.

## What a fix requires (per template, not mechanical)

1. **Correct each connection to the real schema:** set `to_input` to a param the target workflow actually declares, and `from_output` to a filename the upstream actually publishes.
2. **Add scalar-extraction transforms** where the handoff is a number inside a results file (e.g. `admet_results.json` → `herg_ic50_nM`) — extend `_PARAM_TRANSFORMS` (today it has file-level transforms like `smiles_file_to_json_list`).
3. **Add a transform where shapes differ** (e.g. docking `vina_poses` → a best-pose ligand file for GROMACS's `ligand`).
4. **Engine hardening (recommended):** a chain with an unresolved declared handoff should not silently report `succeeded` — surface `handoff_warnings` and/or gate success, so Defect 2 cannot hide.
5. **Guardrail:** a template-connection validator (the offline audit here) wired into CI/registration so a connection naming a non-existent param is rejected at authoring time.

## Evidence
- Live runs (dev): `chain_1794261172_f64373` (admet_context rejected), `chain_1794261408_d60f70` (succeeded with silent default).
- Audit: 11/24 drug-dev/pharma connections reference params absent from the target `.nf` (verified against `params.<name>` references, not just declarations).

Related: [[project_composer_execution_bottleneck]] · [[project_drugdev_capability]] · workflow_chains (70 templates).

---

## Update (same day) — engine guard shipped, authoring guardrail shipped, and the deeper scope of the template problem

**Shipped (commit `48c03e35f8`):**
- **Engine guard against silent no-op handoffs.** A declared connection that resolves to no wiring (upstream output not found even after fallback) now **fails the step before launch** instead of running it on defaults and reporting `succeeded`. Mirrors the existing `transform_error` / binding-problem fail paths. py_compile + the 25+4 chain unit tests pass.
- **Authoring-time validator** `scripts/validation/validate_chain_templates.py` — runs `galaxy.chain.binding_check.check_connections` (already enforced per-step at runtime, `workflow_chain.py:663`) over **every** registered template, so a template whose connection binds to an undeclared param is caught at CI/authoring instead of at execution.

**The template problem is bigger than "7 drug-dev chains" and not mechanically fixable.** The validator flags **33 of 70 templates** (8 drug/pharma). The flagged connections fall into three classes, only the first of which is a simple rename:

1. **Wrong scalar param name** — e.g. `admet_to_cipa_cardiac` wiring `admet_context` (CiPA declares no such param). Fixable by correcting the name, *if* the data also matches (see 3).
2. **Model mismatch — HDA-staged Bioconductor workflows.** Many downstream R workflows (`deseq2_multi_factor_analysis`, `drimseq`, `FlowSOM`, `geomxtools`, …) declare only `outdir` / `none`: they consume their input via Galaxy dataset (HDA) staging, **not** via a `params.<name>` scalar. The params-based connection model (`counts`, `dds`, `rse` → `params.counts` …) does not reach them, so the binding check correctly rejects the connection. Fixing these requires reconciling the chain handoff model with HDA-staged inputs, not a rename.
3. **Semantic / unit mismatch.** `admet_to_cipa_cardiac` wires ADMET `herg` → CiPA `herg_ic50_nM`, but ADMET-AI emits **hERG inhibition probability** (0–1, e.g. 0.003), while CiPA needs **hERG IC50 in nM**. No clean extraction exists — it needs a defensible probability→IC50 conversion. Likewise `target_to_lead_full` wires docking `vina_poses` → GROMACS `docked_poses`, but GROMACS takes a `ligand` SDF; a best-pose-to-ligand transform must be written. Only 2 transforms exist today (`smiles_file_to_json_list`, `pocket_json_to_box_center`).

**Conclusion.** Deployment ✓, engine ✓ (and now hardened against silent false success + guarded at authoring time). But making the multi-phase drug-dev chains actually pass correct data between phases is **per-chain design work** — correct param names, new transforms (incl. unit conversions that must be scientifically defensible), and a handoff path for HDA-staged workflows. It should not be done by fabricating transforms. Recommend scoping it per chain, starting from the chains whose steps already emit the right data shape.

---

## Correction — this re-derives the authoritative 2026-10-05 audit; its fixes are mostly UNAPPLIED

A prior, more rigorous audit already exists: **`docs/20261005_CHAIN_CONNECTION_AUDIT.md`** (2026-10-05), covering every connection in all chains against the live resolver and each `.nf`'s real outputs. My investigation re-derived its headline (same ~33 chains broken) but with a cruder lens — and I must correct two things:

1. **My authoring validator over-reports.** It uses `check_connections` (is `to_input` a declared param). The Oct-5 audit explicitly flags this as a **secondary** signal: only **5 of 137** `to_input` names are literal downstream params — most wrappers ingest via `params.input`/`params.matrix` + S3, so a `to_input`-not-a-param is **not** proof of breakage. The **authoritative** signal is **`from_output` resolvability** (does the label match a published output FILENAME), which the Oct-5 audit measured: 23 OK, 12 FALLBACK, **56 BROKEN**, 46 uncertain. Use that, not my `to_input` count.

2. **The engine-level fixes were already shipped; the connection renames were not.** `binding_check.py` fail-before-launch (`0ad80b0278`), the transforms infra + real fpocket/box transforms (`8f1f32b748`, `da60cb5503`), and the Oct-6 name-binding/no-hang/chain-aware-status/reconciler fixes (`docs/20261006_CHAIN_FIX_LIVE_VALIDATION.md`, PR #274) are **prior work**. But the Oct-5 audit's **`from_output` rename table (Tiers 1–3) is largely NOT applied** — spot-check of the current DB still shows `top_up_genes`, `de_table`, `salmon_quants`, the `count_matrix` typo, `GenomicMethylSet`, `effect_sizes_and_se`, `ddi_predictions`, `xcms_set`, etc.

**So the real state:** diagnosis + exact fixes already exist (Oct-5); the renameable **(A)** fixes were never written into the catalog, and the design-gap **(B)** ones still need workflow/transform changes. The actionable next step is to **apply the Oct-5 audit's (A) `from_output` renames to `workflow_chains.connections`** (low-risk, pre-diagnosed), then re-validate, and only then tackle the (B) gaps.

**What from today still stands as net-new/complementary:** the **silent-no-op runtime guard** (`48c03e35f8`) — it makes an unresolvable declared `from_output` **fail the step** instead of running on defaults (the Oct-5 "silently dropped" behavior). It fires only on genuine non-resolution (not on OK/FALLBACK), so it surfaces exactly the (B) gaps and any unapplied (A) rename at runtime. My `to_input` authoring validator should be re-based on the `from_output` method (or retired in favor of the Oct-5 approach) before it's trusted as a count.

---

## Applied — 16 Oct-5 (A) `from_output` renames written to the catalog (2026-11-09)

Applied the pre-diagnosed renameable fixes from `20261005_CHAIN_CONNECTION_AUDIT.md`, each **verified**
against the upstream workflow's real declared output filename (resolver rules: exact / substring /
extension, case-insensitive). Reproducible script: `scripts/validation/apply_oct5_chain_connection_fixes.py`
(dry-run by default, `--apply` writes; backs up `workflow_chains.connections` first).

| Chain | Connection | from_output: was → now | resolves to |
|---|---|---|---|
| multiomic_differential_expression_exphunter | s1→s2 | count_matrix → **counts_matrix** | counts_matrix.tsv |
| bp4_rnaseq_best_practices_pipeline | s1→s2 | salmon_quants → **counts_matrix** | counts_matrix.tsv |
| rnaseq_differential_transcript_usage | s1→s2 | salmon_quants → **counts_matrix** | counts_matrix.tsv |
| rnaseq_differential_transcript_usage | s2→s4 | drim_results → **dtu_gene_results** | dtu_gene_results.csv |
| cytof_mass_cytometry_analysis | s2→s3, s2→s4 | cluster_assignments → **flowsom_assignments** | flowsom_assignments.csv |
| geomx_spatial_transcriptomics | s2→s3 | norm_set → **normalized_target** | normalized_target_demodata_geomxset.rds |
| cnv_consensus_pipeline | s2→s3 | cnv_segments → **copy_number_estimates** | copy_number_estimates.csv |
| lcms_metabolomics_consensus | s1→s2 | xcms_set → **xcms_preprocessed** | xcms_preprocessed_object.rds |
| lcms_metabolomics_consensus | s2→s3 | annotated_features → **xsannotated** | xsannotated.rds |
| cyp450_ddi_chain | s1→s2 | ddi_predictions → **ddi_risk_assessment** | ddi_risk_assessment.json |
| bioc_bulk_rnaseq_de_v2 | s2→s3 | enrichment → **enrichgo_results** | enrichGO_results_full.csv |
| methylation_450k_array_analysis | s1→s2, s1→s3 | GenomicMethylSet → **gmsetex** | GMsetEx.rds |
| target_to_lead_full | s5→s6 | mmgbsa_scores → **mmgbsa_results** | mmgbsa_results.csv |
| andv_inhibitor_track_v1 | s5→s6 | mmgbsa_scores → **mmgbsa_results** | mmgbsa_results.csv |

The catalog DB is gitignored; these rows deploy to dev on the next DB sync (md5 → upload + embeddings).

**Still NOT fixed (need workflow/transform changes, per the Oct-5 (B)/Tier-4 tables, not renames):**
- ADMET passed-compounds handoff (`passed_compounds`/`filtered_compounds`) — `predict_admet_properties` emits only a results JSON, no filtered SDF/SMI. Wrapper must emit one.
- docking → GROMACS (`vina_poses` → `ligand`) — needs a best-pose-to-ligand transform.
- scalar-field PK/ADMET handoffs (`herg_ic50_nM`, `bioavailability`, `cl_L_h`, …) — file resolver cannot address a field inside JSON; use the `context_params`/`resolve_context_params` path (none of these connections set it).
- single-cell `.rds`-not-emitted gaps (scater/scran chains) — wrappers must `saveRDS` the SCE.

---

## Design-gap fixes (the "still open" items) — 2026-11-09

Fixed the gaps that needed workflow/transform changes (not renames), at the source:

**1. ADMET → CiPA scalar handoff (`c86b6797a2`).** New transform `admet_toxicity_to_herg_ic50_nM`
reads `toxicity_report.json` `toxicity.herg_ic50_uM` and returns **nM** (×1000 unit conversion — the
ADMET workflow already computes an IC50, so this is NOT a probability→IC50 guess). `admet_to_cipa_cardiac`
rewired: `toxicity_report → herg_ic50_nM` via that transform; the spurious `admet_context` connection
removed. Verified on a real `toxicity_report.json` (432.4 µM → 432424.6 nM).

**2. ADMET passed-compounds (`c86b6797a2`).** `predict_admet_properties` now emits `passed_compounds.smi`
— SMILES clearing ADMET-AI hERG/DILI gates (`params.herg_pass_prob=0.5`, `dili_pass_prob=0.9`; DILI
lenient since the model's baseline is high, hERG is the cardio gate). Previously it emitted no filtered
set, so ADMET→docking chains had nothing to hand off. Chains rewired to route docking through it:
`drug_discovery_admet_gated_screening` (s2→s3 `passed_compounds → smiles_list` + `smiles_file_to_json_list`,
replacing the s1→s3 that bypassed ADMET) and `andv_inhibitor_track_v1` (s3→s4 `passed_compounds → smiles_list`,
was the wrong `ligand_sdf`).

**3. docking → GROMACS best pose.** `structure_prediction_docking` already emits the top pose as
`rank1_*.sdf`; `target_to_lead_full` s4→s5 rewired `vina_poses → docked_poses` ⇒ `rank1 → ligand`
(SDF→SDF, no transform; GROMACS declares `ligand`).

**Still genuinely open (need a conversion STEP, not a rename/transform — in-process transforms lack RDKit/obabel):**
- `target_to_lead_full` s3→s4: ADMET `passed_compounds.smi` (SMILES) → DiffDock `ligand_sdf` (SDF) — needs a SMILES→SDF embed step.
- `andv_inhibitor_track_v1` s4→s5: Vina `*.pdbqt` poses → GROMACS `ligand` (SDF) — needs a pdbqt→SDF convert step (and best-pose selection by score).
- Single-cell `.rds`-not-emitted gaps (`scrna_pseudobulk_de_bioc`, `scrna_consensus_de_bioc`): scater/scran wrappers emit only plots; must `saveRDS` the (normalised/clustered) SCE. Separate (single-cell) domain; not done here.

Net: the drug-dev multi-phase chains now hand off real data at the ADMET→CiPA, ADMET→docking, and DiffDock→GROMACS steps; the two SMILES/SDF/pdbqt format conversions and the single-cell `.rds` gap remain as scoped convert-step work.
