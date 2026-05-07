# BioMate Workflow Storage Cost Model
# Date: 2026-05-07 | Real measurements from AWS Batch validation runs

---

## S3 Pricing (us-west-2)

| Component | Rate |
|---|---|
| Standard storage | $0.023 / GB-month |
| PUT requests | $0.005 / 1,000 |
| GET requests | $0.0004 / 1,000 |
| Data egress (internet) | $0.090 / GB |
| Data egress (to EC2 same region) | $0.000 / GB (free) |

---

## Key Finding: Nextflow Report HTML is the Dominant Fixed Cost

Every run publishes two Nextflow-generated files regardless of workflow:

| File | Size (measured) | Monthly storage | Notes |
|---|---|---|---|
| `pipeline_info/report.html` | **2.82 MB** | $0.000065 | Full execution report with task metrics |
| `pipeline_info/timeline.html` | **0.24 MB** | $0.0000055 | Interactive Gantt chart |
| `pipeline_info/dag.dot` | ~4 KB | negligible | DAG definition |
| **Fixed overhead per run** | **~3.07 MB** | **~$0.000071** | Constant regardless of workflow size |

**Recommendation:** In production, consider disabling `timeline.html` and `dag.dot` for standard runs (save 0.25 MB/run). Keep `report.html` — it's valuable for debugging and customer support.

---

## Actual Measured Output Sizes (Validation Runs)

| Workflow | Input | Scientific output | Report HTML | Total | Work dir |
|---|---|---|---|---|---|
| predict_admet | 10 SMILES (372 B) | **14 KB** (3 JSONs + txt) | 2.82 MB | **3.09 MB** | 64 KB |
| clinical_trial | params JSON | **3 KB** (JSON + CSV) | 2.81 MB | **3.05 MB** | 32 KB |
| nca_pknca (step 1) | 18-row CSV | **1 KB** (validation JSON) | 2.81 MB | **3.05 MB** | 32 KB |
| gromacs (20ps mini) | PDB + SDF | **9.7 MB** (GRO + logs + XVG) | 2.83 MB | **12.54 MB** | 11.34 MB |

**Insight:** For CPU workflows, the scientific output is **10–100 KB**. The 3 MB report HTML is 99% of stored data. For GPU/MD workflows, trajectory and structure files dominate.

---

## Storage Cost Model — All Workflow Categories

### Assumptions
- Output retention: **30 days** (default; user can extend)
- Work dir retention: **7 days** (auto-deleted by Nextflow cleanup)
- Downloads: 1–4× depending on workflow type (scientist + PI + CRO partner)
- Egress = internet download (worst case; EC2 analysis is free)

### CPU Workflows (actual output ~10 KB–20 MB)

| Workflow | Output (real) | 30-day storage | Egress (1 dl) | Total S3 | % of price |
|---|---|---|---|---|---|
| predict_admet (10 cpds) | **3.09 MB** | $0.000071 | $0.000278 | **$0.00035** | 0.35% of $0.10 |
| predict_admet (100 cpds) | ~5 MB | $0.000115 | $0.000450 | **$0.00057** | 0.57% of $0.10 |
| clinical_trial_simulation | **3.05 MB** | $0.000070 | $0.000275 | **$0.00034** | 0.34% of $0.10 |
| nca_pknca (full run) | ~6 MB | $0.000138 | $0.000540 | **$0.00068** | 0.68% of $0.10 |
| pbpk_simulation | ~5 MB | $0.000115 | $0.000450 | **$0.00057** | 0.57% of $0.25 |
| cyp_ddi_panel | ~4 MB | $0.000092 | $0.000360 | **$0.00045** | 0.45% of $0.25 |
| scaffold_hopping | ~4 MB | $0.000092 | $0.000360 | **$0.00045** | 0.45% of $0.25 |
| drug_moa_rnaseq | ~500 MB | $0.01150 | $0.04500 | **$0.057** | 11% of $0.50 |
| nonmem_poppk | ~20 MB | $0.000460 | $0.005400 | **$0.006** | 2.4% of $0.25 |
| hts_plate_qc | ~15 MB | $0.000345 | $0.001350 | **$0.002** | 2% of $0.10 |
| docking_vina (100 cpds) | ~50 MB | $0.00115 | $0.00450 | **$0.006** | 1.2% of $0.50 |
| schrodinger_glide | ~200 MB | $0.00460 | $0.01800 | **$0.023** | 4.6% of $0.50 |

**Verdict:** For CPU workflows, S3 storage is **<5% of price** and can be absorbed into the compute price. No separate storage line item needed below $1/run.

---

### GPU / Hybrid Workflows — Storage is Material

| Workflow | Output size | Storage (30d) | Egress (×dl) | **Total S3** | % of price |
|---|---|---|---|---|---|
| drugclip_screening (1K cpds) | ~20 MB | $0.00046 | $0.0018 | **$0.002** | 0.02% of $12 |
| reinvent4_design | ~50 MB | $0.00115 | $0.0045 | **$0.006** | 0.06% of $8 |
| scfv_antibody_design | ~100 MB | $0.00230 | $0.0090 | **$0.011** | 0.11% of $8 |
| structure_pred + docking | ~1 GB | $0.02300 | $0.0900 | **$0.113** | 0.9% of $12 |
| boltz / chai1 structure | ~200 MB | $0.00460 | $0.0180 | **$0.023** | 0.23% of $12 |
| openfe_rbfe (1 pair, 5ns) | ~2 GB | $0.04600 | $0.1800 | **$0.226** | 1.1% of $20 |
| gromacs_protein_md **10ns** | **~5 GB** | $0.1150 | $0.4500 (×3) | **$1.47** | 10% of $14 |
| gromacs_protein_md **100ns** | **~42 GB** | $0.9660 | $3.7800 (×3) | **$12.11** | 8.6% of $140 |
| amber_pmemd **10ns** | **~4 GB** | $0.0920 | $0.3600 (×3) | **$1.17** | 8.4% of $14 |

### CryoEM — Storage is the Second-Largest Cost

| Workflow | Output size | Storage (30d) | Egress (×dl) | **Total S3** | % of price |
|---|---|---|---|---|---|
| topaz_train | ~50 MB | $0.00115 | $0.0044 | **$0.006** | 0.1% of $5 |
| cryosparc_spa (quick, 1K ptcl) | ~500 MB | $0.01150 | $0.0450 | **$0.057** | 0.8% of $7 |
| cryosparc_spa (full, 500K ptcl) | **~10 GB** | $0.2300 | $0.9000 (×4) | **$4.82** | 6% of $80 |
| cryo_et_full | **~20 GB** | $0.4600 | $1.8000 (×3) | **$7.26** | 10% of $75 |

---

## Storage Tiers — Recommended Policy

| Tier | Retention | Included in price? | Notes |
|---|---|---|---|
| **Hot (30 days)** | 30 days | Yes — absorbed for CPU workflows | Standard for all runs |
| **Warm (90 days)** | 90 days | +$0.01–0.50 add-on | For regulatory submissions, audit trails |
| **Archive (1 year)** | 1 year (S3 Glacier) | +$0.004/GB/month | ~83% cheaper than standard; restore takes hours |
| **Work dir cleanup** | 7 days | Always free | Nextflow work dirs auto-deleted |

**S3 Glacier pricing:** $0.004/GB-month vs $0.023 standard → archive large trajectories after 30 days to cut costs by 83%.

---

## Updated All-In Pricing (Compute + Storage)

### CPU Workflows — Storage negligible, absorb into compute price

| Workflow | Compute (balanced) | Storage overhead | **All-in price** |
|---|---|---|---|
| predict_admet (100 cpds) | $0.25 | <$0.01 | **$0.25** |
| clinical_trial BOIN | $0.25 | <$0.01 | **$0.25** |
| nca_pknca | $0.25 | <$0.01 | **$0.25** |
| pbpk_simulation | $0.50 | <$0.01 | **$0.50** |
| cyp_ddi_panel | $0.50 | <$0.01 | **$0.50** |
| hts_plate_qc | $0.50 | <$0.01 | **$0.50** |
| drug_moa_rnaseq | $2.00 | $0.06 | **$2.10** |
| schrodinger_glide (100 cpds) | $1.00 | $0.02 | **$1.25** |
| nonmem_poppk | $1.00 | <$0.01 | **$1.00** |

### GPU/Hybrid — Storage is a real line item

| Workflow | Compute | Storage + Egress | **All-in price** | Storage % |
|---|---|---|---|---|
| drugclip_screening (1K) | $2.00 | $0.00 | **$2.00** | <0.1% |
| reinvent4 lead design | $4.00 | $0.01 | **$4.00** | <0.1% |
| structure prediction + docking | $12.00 | $0.11 | **$12.25** | <1% |
| gromacs 10ns | $14.00 | **$1.47** | **$16.00** | 9% |
| gromacs 100ns | $140.00 | **$12.11** | **$155.00** | 8% |
| amber 10ns | $14.00 | **$1.17** | **$16.00** | 7% |
| openfe_rbfe (5ns, 1 pair) | $20.00 | **$0.23** | **$20.50** | 1% |

### CryoEM — Storage is ~6–10% of total cost

| Workflow | Compute | Storage + Egress | **All-in price** | Storage % |
|---|---|---|---|---|
| topaz train | $5.00 | $0.01 | **$5.00** | <0.1% |
| cryosparc_spa (quick) | $7.00 | $0.06 | **$7.00** | <1% |
| cryosparc_spa (full) | $80.00 | **$4.82** | **$87.00** | 6% |
| cryo_et_full | $75.00 | **$7.26** | **$85.00** | 9% |

---

## Trajectory Archival Strategy (MD Simulations)

For GROMACS/AMBER users running production campaigns, trajectory storage compounds quickly:

| Scenario | Compute | Hot storage (30d) | Archived (1yr) | Total/campaign |
|---|---|---|---|---|
| 5× 10ns runs (lead opt) | $70 | $7.35 | $0.92 | **$78** |
| 3× 100ns runs (hit validation) | $420 | $36.33 | $4.54 | **$461** |
| 10× 100ns runs (campaign) | $1,400 | $121.10 | $15.12 | **$1,536** |

**Recommendation:** Auto-archive trajectories to S3 Glacier after 30 days. Users can restore on-demand ($0.02/GB restore + $0.003/GB restore fee). This cuts storage costs 83% while keeping trajectories accessible.

---

## Storage Cost by Retention Period

For large outputs (GROMACS 100ns = 42 GB):

| Retention | Standard storage | Glacier (after day 30) | Egress (3 dl) | Total |
|---|---|---|---|---|
| 30 days | $0.97 | — | $11.34 | **$12.31** |
| 90 days | $2.90 | — | $11.34 | **$14.24** |
| 30d hot + 11mo Glacier | $0.97 | $1.76 | $11.34 | **$14.07** |
| 30d hot + keep (1yr) | $11.59 | — | $11.34 | **$22.93** |

Best practice: charge users for 30-day hot storage in compute price, offer optional 1-year Glacier archival as an add-on ($0.10–$0.50/run flat fee).

---

## What This Means for Pricing Strategy

1. **CPU workflows (<10 MB output):** S3 costs are $0.001–$0.06. Absorb entirely into compute price. No storage line item.

2. **Medium GPU workflows (200 MB–2 GB output):** S3 costs $0.02–$0.25. Still <2% of compute price. Absorb.

3. **Large GPU workflows (MD, CryoEM >5 GB output):** S3 costs $1.50–$12. This is **7–10% of the total bill** and must be priced in explicitly.

4. **Action:** For gromacs, amber, cryosparc_spa (full), cryo_et: add a **storage line item** to the displayed price quote before the user runs. Show: "Estimated storage: $X.XX (30-day retention, includes 1 download)."

5. **Work directories:** Never charge for work dirs. Delete after 7 days automatically (already done). Cost is negligible (<$0.01).

6. **The Nextflow report.html (2.82 MB per run):** At scale (10,000 runs/month), this is 28 GB/month = $0.64/month. Negligible but worth noting.
