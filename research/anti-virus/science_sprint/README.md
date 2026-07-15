# ANDV Publication-Positive Science Sprint (6-week plan)

Implements **parallel compute tracks** from `feedback_review/COMPUTATIONAL_EXPERIMENTAL_PLAN_POSITIVE_RESULTS.md` using existing BioMate Nextflow workflows and local analysis scripts.

**Success criteria (publication):**
- ≥3 inhibitor scaffolds with ensemble-best affinity materially better than rigid baseline (target narrative: Kd &lt; 5 µM after refinement)
- ≥5 conformational / structural epitope patches with cross-species support
- Manuscript sections replace `[planned computational expansion]` placeholders

---

## Tracks (run in parallel)

| Track | Script | Compute | Output |
|-------|--------|---------|--------|
| **INH-MD** | `track_inh_md.py` | AWS Batch (GROMACS) | `science_sprint/runs/*/track_inh_md/` |
| **INH-ENSEMBLE** | `track_inh_ensemble_docking.py` | Batch × N conformers | `ensemble_results.json`, `ensemble_summary.md` |
| **A-MULTITOOL** | `track_plan_a_multitool.py` | Batch (epitopeprediction ×2) | MHCnuggets + NetMHCpan S3 outdirs |
| **A-STRUCTURAL** | `track_plan_a_structural_epitopes.py` | Local (~minutes) | `structural_epitope_patches.json` |
| **A-CROSS** | `track_plan_a_cross_species.py` | Local + UniProt | `cross_species_conservation.json` |

---

## Prerequisites

```bash
# Galaxy with full workflow registry (NOT start_backend.sh formal DB)
cd /home/yzhang/biomate/backend && ./start_andv_backend.sh

# AWS credentials for Batch / S3
export AWS_DEFAULT_REGION=us-west-2
export GALAXY_API_KEY=$(grep bootstrap_admin_api_key config/galaxy.yml | awk '{print $2}')
export BIOMATE_API_URL=http://127.0.0.1:8081
```

Baseline inhibitor artifacts: `research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z/`  
Guo structures: `research/anti-virus/structures/{9P3I,9P3Y,9P3X,...}.cif`

---

## Launch all tracks

```bash
bash research/anti-virus/science_sprint/run_sprint_parallel.sh
```

Logs: `research/anti-virus/science_sprint/logs/`

---

## Single-track commands

```bash
# Local (fast) — no API
python3 research/anti-virus/science_sprint/track_plan_a_structural_epitopes.py
python3 research/anti-virus/science_sprint/track_plan_a_cross_species.py

# API / Batch (slow)
python3 research/anti-virus/science_sprint/track_inh_ensemble_docking.py --dry-run
python3 research/anti-virus/science_sprint/track_inh_ensemble_docking.py

python3 research/anti-virus/science_sprint/track_plan_a_multitool.py --ensure-worktree

NetMHCpan requires the licensed DTU tarball on S3 (not in git):

```bash
# After academic download of netMHCpan-4.1b.Linux.tar.gz
aws s3 cp netMHCpan-4.1b.Linux.tar.gz \\
  s3://biomate-nextflow-work/inputs/andv_campaign/netmhcpan/netMHCpan-4.1b.Linux.tar.gz
```

python3 research/anti-virus/science_sprint/track_inh_md.py --gromacs-n-steps 250000  # smoke
python3 research/anti-virus/science_sprint/track_inh_md.py --gromacs-n-steps 5000000 # production
```

---

## Week mapping

| Week | Inhibitor | Vaccine |
|------|-----------|---------|
| 1–2 | MD trajectories (`track_inh_md.py`) | Structural epitopes + cross-species |
| 2–3 | Ensemble docking (`track_inh_ensemble_docking.py`) | Multi-tool epitope (`track_plan_a_multitool.py`) |
| 4–6 | HTS / REINVENT follow-up (existing `run_parallel_library_vs_generative.py`) | Immunogen design (manuscript sections) |

---

## Integrating results into manuscripts

1. Copy `ensemble_summary.md` → inhibitor Results (ensemble vs rigid table)
2. Copy `structural_epitope_patches.json` → Plan A conformational epitope subsection
3. Copy `cross_species_conservation.json` → Plan A conservation figure/table
4. Update `docs/MANUSCRIPT_*_v1_0.md` — remove `[planned expansion]` where data exists

See also: `docs/ANDV_MILESTONE_CHECKLIST.md` (Week 4–6 science rows).
