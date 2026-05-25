## Plan B execution report

In silico workflows submitted via `POST http://127.0.0.1:8081/api/nextflow/execute` with `profile: aws` and `compute_config: {"executor":"awsbatch","s3_bucket":"biomate-nextflow-work"}`.

### API preflight

- HTTP 200 on `/api/version` during orchestration (see `api_preflight.json`).

### Runs

#### 10813_codon

- **run_id:** `e3f044d5-37c5-447d-8941-89fce0ef67e7`
- **final status:** `succeeded`
- **S3 outdir (from status):** `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/10813_codon/`
- **last status HTTP:** `200`
- **proof copy:** `GET /api/nextflow/status/{run_id}` returned `s3_output_files: []` while the run was still terminal with `succeeded`. A post-hoc object list under the outdir prefix showed published outputs under `run/`. Proof file (local):

  - Source URI: `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/10813_codon/run/versions.yml`
  - Command: `aws s3 cp s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/10813_codon/run/versions.yml research/anti-virus/runs/plan_b_exec_20260512T184230Z/proof_10813_codon_versions.yml`
  - Local path: `proof_10813_codon_versions.yml`

#### 10721_rna2d

- **run_id:** `9f04fe9a-958a-44b7-8573-ac836d982eb2`
- **final status:** `succeeded`
- **S3 outdir (from status):** `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/10721_rna2d/`
- **last status HTTP:** `200`
- **proof copy:** Same `s3_output_files` gap as 10813; proof via `aws s3 ls` on outdir then:

  - Source URI: `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/10721_rna2d/run/versions.yml`
  - Command: `aws s3 cp s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/10721_rna2d/run/versions.yml research/anti-virus/runs/plan_b_exec_20260512T184230Z/proof_10721_rna2d_versions.yml`
  - Local path: `proof_10721_rna2d_versions.yml`

#### 12869_lnp (optional third; executed after 10813 and 10721 both succeeded)

- **run_id:** `8c29fa67-2d5d-4021-8510-70c0069dd5ed`
- **final status:** `succeeded`
- **S3 outdir (from status):** `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/12869_lnp/`
- **last status HTTP:** `200`
- **proof copy:**

  - Source URI: `s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/12869_lnp/lnp_opt_run/versions.yml`
  - Command: `aws s3 cp s3://biomate-nextflow-work/nextflow/outputs/plan_b_exec_20260512T184230Z/12869_lnp/lnp_opt_run/versions.yml research/anti-virus/runs/plan_b_exec_20260512T184230Z/proof_12869_lnp_versions.yml`
  - Local path: `proof_12869_lnp_versions.yml`

### Supplementary machine-readable records

- `submissions.json` — execute responses for 10813 and 10721.
- `submission_12869.json` — execute response for 12869.
- `poll_results.json` — last status payload per run after polling to a terminal state.
