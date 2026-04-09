# Spot Instances + GPU Backup Plan — 2026-04-09

Status: **Near-future optimization** (not yet implemented)

---

## Problem: g4dn capacity constraints

`g4dn.xlarge` (NVIDIA T4) instances in `us-west-2` are frequently capacity-constrained,
especially for on-demand. BioMate's `galaxy-cloud-queue-gpu` only has g4dn instances.
When no g4dn is available, GPU jobs sit in RUNNABLE for hours.

## Problem: GPU cost

On-demand GPU pricing is high:
- `g4dn.xlarge` (T4, 16 GB VRAM): $0.526/hr
- A 10 ns GROMACS MD run takes ~4–8 hrs GPU time: $2–4 per run
- Spot pricing: 60–70% cheaper → $0.16–0.21/hr

---

## Plan A: GPU instance family diversification

Add backup GPU instance types to `galaxy-cloud-compute-gpu-industrial`:

| Instance | GPU | VRAM | vCPU | $/hr (on-demand) | Best for |
|---|---|---|---|---|---|
| g4dn.xlarge | T4 | 16 GB | 4 | $0.526 | GROMACS MD, AMBER MD |
| g5.xlarge | A10G | 24 GB | 4 | $1.006 | Larger models, more VRAM |
| p3.2xlarge | V100 | 16 GB | 8 | $3.060 | High-performance fallback |

Proposed CE update (BFS order: cheapest first, fallback to more expensive):
```python
instanceTypes = ['g4dn.xlarge', 'g4dn.2xlarge', 'g5.xlarge', 'g5.2xlarge']
```

Note: `p3.2xlarge` excluded from default pool (expensive, use only if needed).
`g5` (A10G) is faster than g4dn T4 for FP32 and supports bfloat16 — good for
DiffDock and AlphaFold3 which benefit from larger VRAM and newer tensor cores.

**Status:** Requires checking g5 quota in us-west-2. Default g5 On-Demand quota is
often 0 for new accounts — may need quota increase request.

---

## Plan B: Spot instances with checkpoint/resume

### Why spot is viable for GROMACS/AMBER MD

Both GROMACS and AMBER write native checkpoint files:
- GROMACS: `.cpt` (checkpoint) file written every `nstcheckpoint` steps (default 1000)
- AMBER: `restrt` file written at configurable intervals

On spot interruption (2-min warning), the instance saves state and terminates.
On resume, GROMACS supports `-cpi nvt.cpt` to continue from the last checkpoint.

### Implementation approach

1. **Add `nstcheckpoint = 5000` to NVT/NPT/Production MDP files**
   Saves checkpoint every 5 ps (5000 × 0.001 ps). Minimal I/O overhead.
   Upload `.cpt` to S3 alongside outputs via publishDir.

2. **Enable spot instances on the GPU CE with retry logic:**
   ```
   allocationStrategy = SPOT_CAPACITY_OPTIMIZED
   bidPercentage = 100  (up to on-demand price)
   spotIamFleetRole = arn:aws:iam::ACCOUNT:role/AmazonEC2SpotFleetRole
   ```

3. **Add `-cpi` restart in Nextflow process script:**
   ```bash
   # Resume from checkpoint if available (spot restart)
   CPT_FILE="${work_dir}/nvt.cpt"
   if [ -f "$CPT_FILE" ]; then
     gmx mdrun -v -deffnm nvt -cpi "$CPT_FILE" -ntmpi 1 -ntomp ${task.cpus}
   else
     gmx mdrun -v -deffnm nvt -ntmpi 1 -ntomp ${task.cpus}
   fi
   ```

4. **Nextflow retry policy:** `errorStrategy = 'retry'; maxRetries = 3`
   With `-resume`, Nextflow re-submits the failed task and GROMACS picks up from `.cpt`.

### Colleague's prior work
A team member has implemented spot-safe checkpoint handling for the AMBER pipeline.
Reference their implementation before building this for GROMACS. Key questions:
- Where are `.cpt` files stored between retries (S3 vs EFS)?
- How is the spot interruption 2-min warning handled (graceful checkpoint flush)?
- Is the retry triggered by Nextflow's `errorStrategy` or a custom handler?

### Estimated savings

For a typical drug discovery pilot with 5 GROMACS/AMBER runs/month:
- On-demand: 5 × 6 hrs × $0.526 = $15.78/month GPU cost
- Spot (70% discount): 5 × 6 hrs × $0.158 = $4.74/month GPU cost
- Savings: ~$11/month at pilot scale; scales linearly with usage

---

## Implementation priority

1. **Week 1 (quick win):** Add `g5.xlarge` to GPU CE instance types — no code change,
   just a 5-min AWS Batch CE update. Reduces capacity wait times immediately.

2. **Week 2–3:** Implement `nstcheckpoint` in GROMACS MDP files + test spot retry locally
   with a short MD run. Reference colleague's AMBER implementation.

3. **Week 4:** Enable spot CE profile (`gpu_batch_spot`) as opt-in workflow profile.
   Default stays on-demand for reliability; power users can use `gpu_batch_spot`.
