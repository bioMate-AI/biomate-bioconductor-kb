# Cryo-EM E2E User Guide — EMPIAR-10028 β-galactosidase

**Persona**: Dr. Sarah Chen, cryo-EM facility scientist
**Dataset**: EMPIAR-10028, *E. coli* β-galactosidase, 7028 EER movies
**Goal**: Run a full SPA pipeline through BioMate, experience pilot run suggestion and QC governance

---

## Dataset Reference

| Parameter | Value | Notes |
|---|---|---|
| **Dataset** | EMPIAR-10028 | Publicly available benchmark |
| **Sample** | *E. coli* β-galactosidase | Tetrameric, D2 symmetry |
| **Movies** | 7028 EER files | Total dataset (EMPIAR) |
| **Pixel size** | 0.885 Å/pixel | Counting mode |
| **Voltage** | 300 kV | Titan Krios |
| **Cs** | 2.7 mm | |
| **Amplitude contrast** | 0.1 | |
| **Particle diameter** | ~180 Å | |
| **Symmetry** | D2 | |
| **Published resolution** | 2.2 Å | EMDB-2984 |

You do **not** need to download the full dataset. BioMate runs in mock processing mode by default; the parameters above are used to generate realistic mock outputs.

---

## Step-by-Step Instructions

### Step 1 — Open BioMate

Navigate to the BioMate chat interface. Sign in with your account.

**Expected**: Chat input box visible at the bottom of the screen.

---

### Step 2 — Send the Cryo-EM Query

Copy and paste the following message into the chat:

```
Run a CryoSPARC single-particle analysis pipeline on my E. coli beta-galactosidase
cryo-EM dataset. Parameters: num_movies=7028, pixel_size=0.885, symmetry=D2,
particle_diameter=180, voltage=300, cs=2.7, amplitude_contrast=0.1
I want to use cryo_em quality control checks during processing.
```

Press Enter or click Send.

**Expected**: BioMate shows "AI is typing..." then a response appears with a Nextflow Workflow card.

---

### Step 3 — Observe the Pilot Run Banner

Because `num_movies=7028` exceeds the 1,000-movie threshold, BioMate recommends a pilot run before committing to full processing.

**Expected**: An amber banner at the top of the workflow card reading:
> **Pilot run recommended** — Large cryo-EM dataset (7,028 movies) — pilot run on ~200 movies recommended before full processing

This banner tells you that running all 7028 movies immediately is risky. A pilot on ~200 movies lets you validate parameters (CTF range, particle diameter, picking settings) before spending compute on the full dataset.

> **What if the banner doesn't appear?**
> The pilot banner fires when BioMate detects `num_movies > 1000` in your query parameters. If the AI extracts parameters differently, try rephrasing as: `"I have 7028 EER movies"`.

---

### Step 4 — Explore QC Settings

Before executing, look at the QC Settings panel below the parameters.

1. Click the **QC Settings** header to expand the section
2. In the **QC Profile** dropdown, select `cryoem_spa_standard`
3. (Optional) Add a threshold override to see how QC gates work:
   - Key: `total_drift_angstrom`
   - Value: `10`
   - Click **Add**

**What this does**: The `cryoem_spa_standard` profile sets baseline thresholds appropriate for purified protein complexes. With the override `total_drift_angstrom=10`, any micrograph with more than 10 Å of total beam-induced motion will fail the QC gate. This is very strict (normal threshold is 50 Å) and will demonstrate the gate mechanism with real data.

> **Note on mock mode**: In mock processing mode, QC gates check for real MotionCor2 log files (`*.log`, `*_motion.txt`) which the mock pipeline does not produce. QC gates fire automatically when running with real CryoSPARC output.

---

### Step 5 — Execute the Workflow

Click **Run Workflow** (or **Confirm & Run**).

**Expected**: The workflow viewer updates to show execution status. If running on AWS Batch:
- After ~5 seconds: A blue **Provisioning compute** banner appears while EC2 instances start
- After ~3–5 minutes: The banner disappears and log output begins to appear
- Progress bar advances through steps: IMPORT → MOTION → CTF → DENOISE → PICK → CLASSIFY → REFINE → FSC → SHARPEN

---

### Step 6 — QC Gate Behaviour (with real data)

When running with real CryoSPARC output (not mock mode), BioMate monitors each processing step:

| Gate | Metric | Default threshold | Profile `cryoem_spa_standard` |
|---|---|---|---|
| Motion correction | `total_drift_angstrom` | 50 Å | 50 Å (same) |
| CTF estimation | `fit_quality` | 0.7 | 0.7 |
| CTF estimation | `astigmatism_angstrom` | 1000 Å (advisory) | 1000 Å |
| Orientation bias | `orientation_anisotropy_ratio` | 5× (SILVER) / 10× (GOLD) | same |

**If a QC gate fires**, a modal appears showing:
- The metric that failed
- The measured value vs. threshold
- Remediation suggestions (e.g., "Consider tilted data collection for preferred orientation")

You can choose to **Proceed Anyway** (requires 2-step confirmation) or **Pause** to adjust parameters.

---

### Step 7 — Review Output

After completion, the workflow viewer shows:
- Per-step status (green = passed, red = failed)
- QC annotations on each step
- Final resolution estimate from FSC analysis
- Orientation anisotropy check from 3DFSC-style analysis

---

## QC Parameter Guide

### `total_drift_angstrom`
Total beam-induced motion across all frames. Values > 50 Å typically indicate:
- Grid was not properly vitrified
- Beam-induced charging on carbon film
- Specimen moved during pre-irradiation

**Remediation**: Pre-irradiate with 5–10 e⁻/Å² before data collection; use gold or graphene support.

### `fit_quality` (CTF)
Cross-correlation of the power spectrum to the theoretical CTF model (0–1 scale).
Values < 0.7 indicate poor Thon ring visibility, often due to:
- Too thick or contaminated ice
- Charging on the grid
- Defocus range outside 0.5–3 μm

**Remediation**: Optimize ice thickness; use wider defocus range during collection.

### `orientation_anisotropy_ratio`
Ratio of best-covered to worst-covered view direction (from 3DFSC analysis).
- **1.0×** = perfectly isotropic orientation distribution
- **> 5×** (SILVER advisory): mild preferred orientation detected
- **> 10×** (GOLD blocking): severe preferred orientation; reconstruction is anisotropic

**Remediation**: Tilted data collection (15–30°); detergent screening; different grid support.

---

## Troubleshooting

| Issue | Likely cause | Fix |
|---|---|---|
| No pilot banner | AI matched a template without the `num_movies` parameter | Include `num_movies=7028` explicitly |
| "Provisioning compute" banner never disappears | AWS Batch cold start can take 5–8 min | Wait; check AWS Batch console if > 10 min |
| QC gate modal does not appear | Running in mock mode (no real log files) | Expected; QC gates require real CryoSPARC output |
| Workflow fails with "permission denied" | S3 bucket policy | Verify `BIOMATE_NEXTFLOW_BUCKET` IAM role has s3:PutObject |
| Progress stuck at 0% for > 10 min | Batch job may have failed to start | Check `GET /api/nextflow/invocations/{id}/status` |

---

## Running the Automated E2E Test

```bash
cd /home/yzhang/biomate/frontend

# Run with headed browser (shows recording)
npx playwright test e2e/cryoem-real-e2e.e2e.ts --headed --reporter=html

# Run headless with video
npx playwright test e2e/cryoem-real-e2e.e2e.ts --reporter=html

# Run only the QC profiles smoke test (fast)
npx playwright test e2e/cryoem-real-e2e.e2e.ts -g "T0 cryoem profiles"
```

Screenshots are saved to: `frontend/e2e/screenshots/cryoem-e2e/`
