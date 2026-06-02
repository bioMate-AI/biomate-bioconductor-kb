# Parallel session 2026-06-03

## Completed

| Track | Action | Result |
|-------|--------|--------|
| **Manuscripts** | Plan A v1.1 multitool (604 binders), conservation overlap (18) | `MANUSCRIPT_PLAN_A_VACCINE_v1_1.md` |
| **Manuscripts** | Inhibitor v1.1 addendum (ZINC150 + MM-GBSA) | `MANUSCRIPT_ANDV_INHIBITOR_v1_1.md` |
| **Plan B** | Human-codon optimized CDS FASTA | `plan_b_codon/andv_gp_optimized_cds.fasta` via `fetch_plan_b_optimized_cds.py` |
| **Nextflow** | Fixed `MM_GBSA` Groovy parse errors (f-strings, `\d` regex) | `gromacs_protein_md/main.nf` validates with `nextflow -preview` |
| **Pipeline** | CPU profile when `--no-gromacs-gpu` | `run_andv_inhibitor_pipeline_nextflow.py` |
| **Infra** | Parallel MD launcher | `scripts/run_inhibitor_md_parallel.sh` |

## In progress / blocked

| Track | Action | Status |
|-------|--------|--------|
| **INH-02–05 MD** | `run_inhibitor_md_parallel.sh` (500k steps) | Batch Nextflow driver fails in ~0–30s (empty log_tail); parse fix verified locally — **backend may need HUP reload** to pick up `main.nf` on Batch head node |
| **Aspirin MD** | Same script, `--force-rerun` | Resubmit after driver fix |
| **INH-02–05 MM-GBSA** | Blocked on MD completion | Use `run_mmgbsa_standalone_batch.sh` per outdir after MD |

## Next commands

```bash
# Reload backend (if MD still instant-fails)
cd backend && pkill -HUP -f 'gunicorn.*galaxy'

# Retry parallel MD (clean bash)
env -i HOME="$HOME" PATH="/usr/bin:/bin" FORCE_RERUN=1 \
  /bin/bash --noprofile --norc research/anti-virus/scripts/run_inhibitor_md_parallel.sh

# After each MD outdir exists on S3:
research/anti-virus/scripts/run_mmgbsa_standalone_batch.sh \
  s3://biomate-nextflow-work/nextflow/outputs/parallel-inhibitor-20260513T032000Z/<hash> \
  MM_GBSA_inh02_standalone
```
