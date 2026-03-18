# Execution Environment Switching Guide

This guide explains how to switch BioMate workflow execution between AWS Batch, local, and HPC environments.

---

## Default Behavior

- For Nextflow workflows, BioMate now defaults to `awsbatch` execution unless you explicitly override it.
- For Galaxy workflows, execution follows the Galaxy backend path.
- Hardware hints from the AI tool database (GPU and memory) are propagated into workflow metadata and used during execution setup.

---

## Environment Options

| Environment | Executor value | Typical use case |
|---|---|---|
| AWS Batch | `awsbatch` | Production workloads, scalable cloud execution |
| Local | `local` | Development, debugging, small test runs |
| SLURM | `slurm` | Institutional HPC clusters |

### About "other" environments

BioMate currently has first-class executor handling for `awsbatch`, `local`, and `slurm`.  
If you need another backend, route through Nextflow's custom executor configuration in backend deployment code, then pass matching `compute_config` fields.

---

## Switching from the UI

1. Open **Settings** -> **Compute**.
2. Select your target executor profile.
3. Run the workflow as usual from the workflow card.

If your deployment sets AWS Batch as default, no extra action is needed for standard cloud runs.

---

## Switching via API

Send executor overrides in `executionConfig.computeConfig` on workflow execution.

### AWS Batch (explicit)

```json
{
  "workflowDefinition": { "...": "..." },
  "executionConfig": {
    "executionEngine": "nextflow",
    "computeConfig": {
      "executor": "awsbatch",
      "aws_batch_queue": "biomate-cloud-queue",
      "aws_region": "us-west-2",
      "s3_bucket": "biomate-nextflow-work"
    }
  }
}
```

### Local override

```json
{
  "workflowDefinition": { "...": "..." },
  "executionConfig": {
    "executionEngine": "nextflow",
    "computeConfig": {
      "executor": "local"
    }
  }
}
```

### SLURM override

```json
{
  "workflowDefinition": { "...": "..." },
  "executionConfig": {
    "executionEngine": "nextflow",
    "computeConfig": {
      "executor": "slurm",
      "slurm_partition": "compute",
      "slurm_qos": "normal"
    }
  }
}
```

---

## Hardware Requirement Handling

BioMate uses tool runtime hints from `galaxy_ai_tools.db` to derive:

- `gpu_required`
- `min_memory_gb`

Execution behavior:

- On AWS Batch default path, BioMate auto-fills missing compute values for Nextflow runs:
  - sets `gpu_count=1` when GPU is required and not provided
  - sets `memory_gb=min_memory_gb` when memory is required and not provided
- If you explicitly provide contradictory non-AWS settings (for example `gpu_count=0` for a GPU-required workflow), confidence gating can block execution unless override is enabled.

---

## Operator Checklist

Before switching environments, confirm:

- Nextflow can access required paths (`nextflow_path`, input data, output location).
- AWS Batch settings are valid (`aws_batch_queue`, region, S3 bucket).
- Local/SLURM hosts have required runtime/container access.
- Chosen executor matches data size and turnaround expectations.

---

## Troubleshooting

- `confidence_gate_blocked`: Check domain confidence, tool installation readiness, and hardware readiness fields in the response.
- Nextflow launch errors on cloud: verify queue name, IAM permissions, and S3 bucket access.
- Slow local runs: switch executor to `awsbatch` or `slurm` for production-scale workloads.

---

## AWS Release Reference

For release-grade operator guidance (preflight, validation evidence, and go/no-go checklist), see:

- `docs/QC/20260311_AWS_RELEASE_EXECUTION_GATE_AND_VALIDATION_RUNBOOK.md`
