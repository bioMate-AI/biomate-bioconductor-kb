# BioMate — Large-scale, multi-specialty chained workflows: significant use cases + validation

**Date:** 2026-10-05 · Owner: biomate-review-14
Grounded in a read-only capability inventory (chain engine, 69 chain templates, team RBAC) + a live validation run on dev. Honesty contract: real vs code-real-but-unrun is flagged on every claim.

---

## The capability (what is actually true)

- **Chain-execution engine is real and fully wired** — `backend/lib/galaxy/webapps/galaxy/api/workflow_chain.py` (`POST /api/workflows/chain` → `_run_chain` daemon thread). It runs Nextflow steps **sequentially on AWS Batch**, auto-wires each step's output artifact to the next step's input (declared `connections` + artifact contracts, with extension/type-compat fallback), propagates context params (e.g. genome `GRCh38` → organism `hsa`), and supports **resume** and **per-step approval-gating**. Frontend is wired end-to-end (plan card → "Run Pipeline").
- **Honest launch boundary:** the assistant returns a chain **plan** (`workflow_type:"chain"`); a human clicks **Run Pipeline once** to launch; thereafter steps run and hand off automatically. (Not "zero-click autonomous"; one launch click, optional per-step approval.)
- **69 chain templates** in `workflow_chains` (DB), spanning transcriptomics, single-cell, genomics/variant, epigenomics, proteomics, metabolomics, drug discovery, structural biology, cryo-EM, immunology, pop-gen, multi-omics. Catalog: **4,210 workflows, 4,155 executable**.
- **Team space is real at the project level** — `frontend/server/project-routes.ts`: owner/editor/viewer RBAC (server-enforced), member management, ownership transfer, revocable share links, shared project files + runs + provenance (Team plan). **NOT** an org workspace: no shared real-time chats, no email/pending invitations, no activity feed — do not claim those.
- **Execution-evidence status (critical honesty):** individual chain STEPS are run-proven on Batch (e.g. airway/GSE52778 DESeq2, rc=0, 1,242 sig genes). A **6-step** drug-discovery pipeline (pocket→pharmacophore→ADMET→docking→MD→REINVENT4) is run-proven on Batch for the **ANDV** campaign — but via a bespoke CLI, not the chain API. As of this doc, **no full chain had completed end-to-end through the chain engine itself**; the validation run below is the first such test.

---

## Selected significant use cases (publication-anchored, multi-specialty, chained)

Each maps to a real chain template; "status" states how run-proven it is. Specialties in brackets.

1. **Bulk RNA-seq DE → pathway enrichment** [transcriptomics → systems biology].
   Chain: `bulk_rnaseq_de_analysis` (nf-core/rnaseq → nf-core/differentialabundance → gene_set_enrichment_analysis).
   Anchor: **airway / GSE52778** (Himes et al., *PLoS ONE* 2014 — dexamethasone in airway smooth-muscle cells).
   Status: **DE step run-proven** (Batch, 1,242 sig genes, SPARCL1 top); DE→enrichment link is the subject of the validation run below.

2. **Target structure → ADMET-gated virtual screen → lead** [structural biology → drug discovery → ADMET → MD].
   Chain: `target_to_lead_full` / `andv_inhibitor_track_v1` (pocket_detection → pharmacophore → ADMET → docking → GROMACS MD+MM-GBSA → REINVENT4).
   Anchor: **ANDV glycoprotein** campaign on RCSB **9P3I** with a ZINC subset.
   Status: **run-proven — 6 real Batch steps, all succeeded** (`research/anti-virus/runs/andv_nf_pipeline_…/pipeline_manifest.json`), via the CLI that the template mirrors. Strongest cross-specialty, multi-step, real-execution anchor.

3. **Rare-disease WGS + RNA-seq multimodal workup** [genomics/variant → transcriptomics → clinical].
   Chain: `rare_disease_multimodal_workup` (nf-core/sarek → VEP → nf-core/rnaseq → nf-core/DROP → case-report aggregation).
   Anchor: Mendelian trio WGS+RNA; DROP/OUTRIDER–FRASER is the canonical RNA-outlier method (Kremer et al. *Nat Commun* 2017; Yépez et al. 2021).
   Status: code-real (all 5 step names resolve); end-to-end not yet run.

4. **Transcriptomic signature → drug mechanism-of-action** [transcriptomics → pharmacology].
   Chain: `rnaseq_to_lincs_moa` (nf-core/rnaseq → differentialabundance → transcriptomic_moa_lincs, LINCS/CMap connectivity).
   Anchor: LINCS L1000 / CMap (Subramanian et al., *Cell* 2017); the airway DE table feeds the MoA step.
   Status: code-real (3 steps resolve).

5. **ADMET → cardiac-safety pharmacology** [drug discovery → safety pharmacology].
   Chain: `admet_to_cipa_cardiac` (Predict ADMET (AI) → cipa_cardiac_safety_ode).
   Anchor: CiPA initiative / hERG–ODE proarrhythmia modeling (Li et al., *Circ Arrhythm Electrophysiol* 2017).
   Status: code-real (both steps resolve); pairs with the run-proven hERG/ADMET terfenadine demo (d2).

6. **Single-cell multi-sample analysis** [single-cell → transcriptomics → systems biology].
   Chain: `single_cell_multimodal_analysis` (scrna_qc_normalization → Harmony integration → cell-type annotation → trajectory → differential-abundance).
   Anchor: Harmony (Korsunsky et al., *Nat Methods* 2019); a multi-sample scRNA cohort.
   Status: code-real (5 steps).

Stretch (flag as partially-grounded): `multi_omics_mofa_chain` [transcriptomics + proteomics + metabolomics → MOFA+] — most ambitious cross-specialty chain, but several step names did not resolve on a strict check; verify before claiming runnable.

---

## Validation walkthrough (live on dev)

**Goal:** prove the chain ENGINE runs a multi-step pipeline end-to-end (not just individual steps). First end-to-end run through `POST /api/workflows/chain`.

**Chain:** `nf-core/differentialabundance` (DESeq2 on airway/GSE52778) → `gene_set_enrichment_analysis` (GO/KEGG/Reactome), connection `de_results → gene_list`, context-param `genome → organism`.
**chain_run_id:** `chain_1791260333_5f39f9` (submitted 2026-10-05, status accepted → running).

**Result (honest, two runs):**
- ✅ **Sequential multi-step execution works.** The chain engine launched step 1 (DESeq2) on AWS Batch, polled it to `succeeded`, and **auto-advanced to step 2 with no manual action** — the first time multi-step chaining is run-proven through the chain API itself (previously only single steps + a CLI pipeline were proven). Run `chain_1791260333_5f39f9` step0 run `57b00ece` succeeded; re-run `chain_1791262269_8fa689` step0 run `244bf06e` succeeded.
- ❌ **Automatic artifact handoff is BROKEN (root-caused).** Both runs stalled at step 2 with `handoff_warnings: ["No artifact '<name>' found from step 1"]` — v1 with `from_output:"de_results"`, v2 with `from_output:"DESeq2_results"` (which *is* a substring of the published `dex_vs_untreated_DESeq2_results.csv`). So the failure is **not** the connection name. Root cause is in `workflow_chain.py::_list_run_output_files(run_id)`: it collects a completed step's outputs only from (a) the in-process `_runs` dict, (b) `get_nextflow_status`, and (c) a **local** `outdir` via `Path(outdir).exists()`. For an AWS-Batch step the outputs are on **S3** (`s3://…`), so the local-path branch never fires, and for a cross-worker/poller-finalized chain-launched run the in-memory sources carry no `s3_output_files` → the function returns an **empty list** → `pick_artifact_file` matches nothing → every connection fails regardless of name → the next step never launches (run_id stays null, stuck "running"). This explains why **no chain has ever completed end-to-end through the engine**.
- **Fix (recommended, not yet applied):** `_list_run_output_files` must retrieve a Batch step's published outputs from the authoritative source — list the S3 `outdir` (the step's `nextflowOutputDir`, e.g. via the same S3 listing `/api/s3/browse` / the run record's `output_files`) — instead of (or in addition to) the local-path check. Once outputs are retrievable, the connection-name audit below determines which `from_output`/`to_input` names also need aligning.

## Change log
- 2026-10-05 — created: capability framing (honest), 6 publication-anchored multi-specialty chained use cases, and the first end-to-end chain-engine validation run (DE→enrichment on airway/GSE52778).

## Connection audit across ALL chains (static, 69 chains / 137 connections)
Full report: `docs/20261005_CHAIN_CONNECTION_AUDIT.md`. Totals: **OK 23 · FALLBACK(brittle) 12 · BROKEN 56 · UNCERTAIN 46**; **33 of 69 chains have ≥1 broken connection**, 9 fully clean (entirely OK: alternative_polyadenylation_analysis, bioc_proteomics_de_v2, bioc_scrna_cluster_v2, cellcell_communication_with_viz, time_series_de_with_edge).

**Two independent layers break the handoff (both must be fixed for end-to-end chaining):**
1. **Runtime (enabling bug):** `_list_run_output_files` doesn't retrieve a Batch step's S3 outputs → empty file list → every connection fails regardless of name (my live finding; blocks ALL chains today).
2. **Static (naming/contract):** even with outputs available, 56/137 `from_output` labels don't match the published filename. Three sub-classes: (a) **renameable** (~34 — upstream emits it, label just mismatches: e.g. `de_results`→`results`, `count_matrix`→`counts_matrix` typo, `de_table`→`results`); (b) **design gaps** (~15 — upstream wrapper emits no such artifact: scater QC persists no `.rds` SCE → scrna_pseudobulk/consensus can't hand off; variant_burden no `.gds`; recount3 no RSE; annotate step no `.h5ad`; predict_admet no filtered SDF); (c) **scalar PK/ADMET fields** (`herg_ic50_nM`, `bioavailability`, …) the file-resolver can't address — need the existing `context_params` mechanism, which those chains don't set.
3. **Fallback mis-gating:** the `_EXT_TO_PARAM` heuristic runs ONLY for chains with NO connections (gated `elif idx>0`), so connection-based chains get no safety net when a name misses — it should also apply as a fallback.

**Prioritized fix plan:** (F1) fix `_list_run_output_files` to list the S3 outdir — single enabling fix for all chaining; (F2) rename the ~34 mismatched connection labels in the chain templates/DB (low-risk data fix); (F3) enable the ext fallback for connection-based chains; (F4) per-workflow wrapper fixes for the ~15 design gaps (emit the missing artifact) + wire `context_params` for the scalar PK/ADMET chains. Re-validate each fixed chain end-to-end on Batch.
