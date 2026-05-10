# ANDV Pocket Druggability: UI Blocker and Direct Nextflow Plan

## Findings

- The ANDV chat UI E2E test reached `/login`, but the page stayed blank because React never mounted.
- Browser diagnostics showed the initial HTML loaded, while Vite module assets such as `/@vite/client`, `/src/main.tsx`, and `/@react-refresh` failed in Chromium when using `http://127.0.0.1:5000`.
- Playwright API/curl requests for the same assets returned `200`, but browser module requests included `Origin: http://127.0.0.1:5000` and received server-side CORS failures surfaced as `500`.
- The security defaults allowed `http://localhost:*` in development but not `http://127.0.0.1:*`, so Docker Playwright with `--network host` and `BIOMATE_URL=http://127.0.0.1:5000` was blocked at the asset-loading layer.
- A local patch was made to include loopback `127.0.0.1` origins and connect-src entries in `frontend/server/security-config.ts`, but the user asked to pause system-level UI work and validate the scientific workflow directly first.

## Direct Validation Plan

Use BioMate's direct Nextflow execution path for workflow `12805`, `Pocket Detection Druggability`:

- Workflow: `nextflow_nfcore/subworkflows/drug_discovery/pocket_detection_druggability/main.nf`
- Executor: AWS Batch via the BioMate Nextflow API
- Work bucket: `s3://biomate-nextflow-work`
- Container evidence expected in Nextflow trace: ECR image `biomate/biomni-structure-to-drug:x86`

Run the planned structural validation set in parallel:

- ANDV production structure: `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb`
- Stable end-to-end control: `1IEP`

Validation criteria:

- Run reaches `completed` or `succeeded`.
- Output files include `*_pockets.json`, `*_qc_result.json`, and `*_druggability_report.tsv`.
- `num_pockets >= 1`.
- QC status and top pocket metrics are recorded.
- Artifacts are saved under `research/anti-virus/runs/`.

## Direct Validation Results

Artifacts:

- Run bundle: `research/anti-virus/runs/parallel_pocket_20260509T190432Z/`
- Machine-readable summary: `research/anti-virus/runs/parallel_pocket_20260509T190432Z/parallel_summary.json`

Results:

- `andv_9p3i`
  - Run ID: `49b55a19-4b90-41d9-bc58-0cf3597e9896`
  - Input: `s3://biomate-nextflow-work/inputs/andv_campaign/20260507/9P3I.pdb`
  - Output prefix: `s3://biomate-nextflow-work/nextflow/outputs/direct-andv-9p3i/ad44b098`
  - Status: `succeeded`
  - Validation: 10 pockets, QC `PASS`, top druggability score `0.563`, top volume `562.2 A3`

- `control_1iep`
  - Run ID: `0e25b255-3d9e-4197-9b50-ef9381f5a404`
  - Input: `1IEP`
  - Output prefix: `s3://biomate-nextflow-work/nextflow/outputs/direct-control-1iep/bdcbaa36`
  - Status: `succeeded`
  - Validation: 10 pockets, QC `PASS`, top druggability score `0.567`, top volume `879.2 A3`

Execution evidence:

- Both status payloads record `is_batch: true`.
- Both Nextflow logs record `executor > awsbatch (2)`.
- The ANDV `report.html` records workflow container `399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest`.

Helper added for repeatability:

```bash
python3 -u research/anti-virus/scripts/run_parallel_pocket_nextflow.py
```

## UI E2E Follow-up

The system-level UI blocker was fixed and validated after the direct workflow runs.

Fixes:

- `frontend/server/security-config.ts` now allows loopback `127.0.0.1` origins and websocket/connect-src entries in development, matching Docker Playwright `--network host` usage.
- `frontend/server/vite.ts` now ignores generated artifact directories (`dist`, E2E screenshots, test results, reports, and Playwright reports) so long-running workflow tests are not interrupted by full page reloads from generated files.

Validation:

- Docker Playwright verified `/login` renders at `http://127.0.0.1:5000/login`; Vite client connected and the email field was visible.
- Full UI path passed:

```bash
docker run --rm --network host \
  -v /home/yzhang/biomate/frontend:/work -w /work \
  -e BIOMATE_URL=http://127.0.0.1:5000 \
  -e E2E_TEST_TOKEN=biomate-e2e-bypass-token-dev-only \
  mcr.microsoft.com/playwright:v1.57.0-jammy \
  bash -lc 'npx playwright test e2e/andv-pocket-druggability-ui.e2e.ts --project chromium --reporter=line'
```

Result: `1 passed (6.1m)`.

UI-triggered workflow evidence:

- UI workflow run ID: `b1bfb63e-1801-419d-80f9-a620f5edd2ed`
- Nextflow run ID: `66300377-7923-42ec-a02e-723a5415b94a`
- Nextflow status: `succeeded`
- Output prefix: `s3://biomate-nextflow-work/nextflow/outputs/79659428-ce25-413a-9195-c911b9e87ace/fb093254`
- Status payload recorded `is_batch: true` and logs showed `executor > awsbatch (2)`.
- Completion screenshots: `frontend/e2e/screenshots/andv-pocket-ui/05_terminal_or_timeout.png` and `frontend/e2e/screenshots/andv-pocket-ui/06_completed.png`.

## Audit After Screenshot Review

This work proves only the first tractability step, not the full intended ANDV drug-discovery objective.

Critical gaps:

- The completed UI scenario is **Pocket Detection Druggability** only. It does not generate candidate molecules, screen compounds, dock ligands, predict ADMET/toxicity, rank leads, estimate DDI/CYP liabilities, run RBFE, or plan synthesis.
- The original scenario wording says "before we order compounds," but the broader product aim is to **generate candidate drugs and run necessary predictions**. The E2E query and test are therefore under-scoped.
- The final screenshot shows the right workflow panel completed, but the left chat card still says **"No outputs generated yet"** and **"Analysis in progress..."**. That is a UI synchronization issue: completion is not reflected consistently in the conversation artifact.
- The screenshot shows unrelated QC gate labels for this drug-discovery workflow, including examples like reads, CTF, mitochondrial reads, alignment rate, and CiPA thresholds. Those are not pocket-detection-specific metrics and should not appear in a pocket/drug-candidate workflow panel.
- The feedback modal covers the lower-right output/download area in the completion screenshot, making visual audit of output files and the Download All control weaker than it should be.
- The Playwright test currently accepts terminal status and a completion banner, but does not assert that specific files are visible in the panel, that `*_pockets.json` / `*_druggability_report.tsv` / `*_qc_result.json` are user-accessible, or that any candidate-generation/prediction outputs exist.

BioMate workflows found for the full intended program:

- Candidate generation: `drug_discovery/reinvent4_lead_design`, `drug_discovery/scaffold_hopping`
- Virtual screening: `drug_discovery/drugclip_virtual_screening`, `drug_discovery/pharmacophore_filtering`
- Docking: `pharmacology/run_diffdock_with_smiles`, `pharmacology/docking_autodock_vina`, `drug_discovery/schrodinger_glide_docking`, `drug_discovery/moe_covalent_docking`
- Safety/ADMET: `pharmacology/predict_admet_properties`, `pharmacology/ADMET_pred`, `drug_discovery/cyp_ddi_panel`, `drug_discovery/transporter_ddi_pgp_bcrp`, `pharmacology/herg_cardiac_safety_qsar`, `pharmacology/genotoxicity_ames_prediction`
- Affinity/refinement: `drug_discovery/openfe_rbfe`, `drug_discovery/amber_pmemd_md`, `drug_discovery/gromacs_protein_md`
- Developability/translation: `drug_discovery/aizynthfinder_retrosynthesis`, `drug_discovery/syncraft_synthesizability`, `drug_discovery/cro_submission_export`

Correct next validation scope:

1. Pocket tractability from ANDV/9P3I structure.
2. Candidate generation or screening against the tractable pocket.
3. Docking or structure-based ranking of generated/screened candidates.
4. ADMET + hERG/DILI/Ames + CYP/DDI prediction on ranked candidates.
5. Optional higher-cost refinement for top pairs: RBFE/MD and retrosynthesis.
6. Final report/download package containing ranked candidates, SMILES/SDF, docking/affinity evidence, safety flags, and synthesis/CRO readiness.
