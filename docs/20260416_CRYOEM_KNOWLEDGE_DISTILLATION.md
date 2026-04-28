# CryoEM Knowledge Distillation
**Date:** 2026-04-16  
**Sources:** 00_GENERAL_FRAMEWORK.md, 01_MFSD2B_preprint.md, 02_VMAT2_nature2023.md, 20260225_1138_CRYOEM_PAPER_PLAN.md  
**Purpose:** Condensed reference for implementing QC gate output parser wiring, sample-type parameters, benchmark experiments, and paper writing

---

## 1. CryoSPARC Output Field Names (for output parser wiring)

These are the Python attribute names accessible via `cryosparc-tools` `job.load_output()`.

### Motion correction job (type: `patch_motion_correction`)
```python
micrographs = job.load_output("micrographs")
# Fields on each entry:
#   micrographs.ctf/path              — path to aligned MRC
#   micrographs.total_motion          — total drift in pixels (multiply by pixel_size to get Å)
#   micrographs.average_motion        — per-frame average drift in pixels
# Gate input:
total_drift_A = micrographs["total_motion"] * pixel_size_angstrom
per_frame_A   = micrographs["average_motion"] * pixel_size_angstrom
```

### CTF estimation job (type: `patch_ctf_estimation`)
```python
micrographs_ctf = job.load_output("micrographs")
# Fields:
#   micrographs_ctf.ctf/path          — CTF-corrected MRC path
#   micrographs_ctf.ctf/df1_A         — defocus value 1 (Angstroms, positive = underfocus)
#   micrographs_ctf.ctf/df2_A         — defocus value 2
#   micrographs_ctf.ctf/exp_group_id  — optics group
#   micrographs_ctf.ctf/accel_kv      — voltage
#   micrographs_ctf.ctf/cs_mm         — Cs
#   micrographs_ctf.ctf/amp_contrast  — amplitude contrast
#   micrographs_ctf.ctf/ctf_fit_to_A  — estimated resolution of CTF fit (Å) — lower is better
#   micrographs_ctf.ctf/cross_corr_ctffind  — cross-correlation score (FOM) — higher is better
# Gate inputs:
fit_resolution_A = micrographs_ctf["ctf/ctf_fit_to_A"]   # gate: must be < 4.5 Å
fit_quality      = micrographs_ctf["ctf/cross_corr_ctffind"]  # gate: must be > 0.1
defocus_A        = (micrographs_ctf["ctf/df1_A"] + micrographs_ctf["ctf/df2_A"]) / 2
```

### 2D classification job (type: `class_2D`)
```python
class_averages = job.load_output("class_averages")
particles      = job.load_output("particles")
# Fields on class_averages:
#   class_averages.class_ess           — effective sample size per class (float)
#   class_averages.class_num_particles — particle count assigned to this class (int)
#   class_averages.class_posterior_min — minimum posterior probability
# Gate inputs:
num_particles_per_class = class_averages["class_num_particles"]  # array, len = num_classes
total_particles = num_particles_per_class.sum()
# Junk definition: a class with < 5% of expected even distribution
expected_per_class = total_particles / len(num_particles_per_class)
junk_threshold = 0.05 * expected_per_class
junk_count = (num_particles_per_class < junk_threshold).sum()
junk_fraction = junk_count / len(num_particles_per_class)
```

### Homogeneous / non-uniform refinement job (type: `homogeneous_refinement`, `nonuniform_refinement`)
```python
particles = job.load_output("particles")
# Fields:
#   particles.alignments3D/pose        — Euler angles (N, 3), rotation matrix format
#   particles.alignments3D/shift       — 2D shift (N, 2) in pixels
#   particles.alignments3D/cross_corr  — per-particle cross-correlation score
#   particles.alignments3D/error       — per-particle alignment error
# Gate inputs:
poses = particles["alignments3D/pose"]   # shape (N, 3), rotation vectors
# Convert to viewing directions for orientation anisotropy computation
```

### Validation FSC job (type: `validation_fsc`)
```python
fsc = job.load_output("fsc")
# Fields:
#   fsc.freq_A_inv      — spatial frequency in 1/Å (float array, len ~200)
#   fsc.fsc_nomask      — FSC without mask
#   fsc.fsc_loosemask   — FSC with loose (soft) mask
#   fsc.fsc_tightmask   — FSC with tight mask
#   fsc.fsc_noisesub    — noise-subtracted FSC
# Gate inputs:
freq    = fsc["freq_A_inv"]       # 1/Å
fsc_val = fsc["fsc_nomask"]       # primary criterion (gold-standard half-map FSC)
# Resolution at FSC=0.143: interpolate where fsc_val first crosses below 0.143
```

### Ice thickness proxy (type: `select_2D` or from raw micrographs)
```python
micrographs = job.load_output("micrographs")
# No direct ice thickness field in standard CryoSPARC output
# Proxy: mean micrograph intensity from MRC header stats
#   micrographs.micrograph_blob/path → load MRC, compute mean pixel intensity
# Alternative proxy: ctf/cross_corr_ctffind — low FOM often indicates thick ice
# Gate: mean_intensity < 0.3 (very bright = too thick) OR > 0.9 (too thin / empty)
```

---

## 2. Sample-Type Parameter Table

Derived from 00_GENERAL_FRAMEWORK.md, 01_MFSD2B_preprint.md, 02_VMAT2_nature2023.md.

| Sample class | pixel_size (Å/pix) | defocus range (μm) | total_dose (e⁻/Å²) | num_2d_classes | picker_strategy | qc_profile |
|---|---|---|---|---|---|---|
| soluble (<100 kDa) | 0.649 | -0.8 to -2.0 | 40–50 | 200 | TOPAZ (mandatory) | cryoem_spa_purified |
| membrane_small (<60 kDa TM, saposin) | 0.649 | -0.8 to -2.0 | 60 | 200 | blob + template + TOPAZ (3-picker) | cryoem_spa_membrane |
| membrane_large (>60 kDa, MSP or detergent) | 0.83 | -1.0 to -2.5 | 50 | 200 | crYOLO general model | cryoem_spa_membrane |
| gpcr (GPCR + G protein complex) | 0.83 | -0.8 to -2.0 | 50 | 200 | crYOLO + template | cryoem_spa_membrane |
| large_rnp (spliceosome, ribosome, >500 kDa) | 1.06–1.30 | -1.5 to -3.0 | 45 | 100–200 | blob + template | cryoem_spa_purified |
| symmetric (virus capsid, ring ATPase) | 0.83 | -1.0 to -2.0 | 50–60 | 100 | blob + symmetry-aware template | cryoem_spa_purified |

### Notes
- **Three-picker strategy** (blob + template + TOPAZ) is mandatory for saposin nanodisc samples (MFSD2B study: 6.6M → 146K = 2.2% yield is normal)
- **γ-cyclodextrin lipid delivery**: For saposin reconstitution, resuspend dried lipid film in 0.5% γ-cyclodextrin (w/v); no Bio-Beads needed; faster detergent removal
- **Box size formula**: `box_px = 2^ceil(log2((13.3 × MW_kDa^(1/3) × 1.5) / pixel_size))`
- **Particle count targets**: soluble <100 kDa: 500K for <3 Å; membrane 55 kDa: 200K for <3 Å; large complex >500 kDa: 20K for 3–5 Å

### QC profile threshold differences

| Metric | cryoem_spa_purified | cryoem_spa_membrane | cryoem_tomo_in_situ |
|---|---|---|---|
| total_drift_angstrom | < 50 | < 80 | < 150 |
| fit_quality (CTF FOM) | > 0.1 | > 0.1 | > 0.05 |
| ctf_fit_to_A | < 4.5 | < 5.0 | < 6.0 |
| junk_fraction (2D) | > 0.70 halts | > 0.70 halts | > 0.85 halts |
| orientation_anisotropy | > 10.0 halts | > 15.0 halts | N/A |

---

## 3. QC Threshold Evidence Table

| Gate | Metric | Threshold | Evidence level | Citation | Rationale |
|---|---|---|---|---|---|
| Motion correction | total_drift_angstrom | < 50 Å | BRONZE | Community practice (VMAT2 paper: "< 50 Å" in micrograph QC section) | Stage drift causes blurring; > 50 Å unrecoverable even with motion correction |
| Motion correction | per_frame_drift_angstrom | < 5 Å | BRONZE | Community practice | Individual frame usability threshold |
| CTF estimation | ctf_fit_to_A | < 4.5 Å | SILVER | CTFFIND4 documentation; Rohou & Grigorieff 2015 | CTF fit quality directly limits achievable resolution |
| CTF estimation | cross_corr_fom | > 0.1 | SILVER | CTFFIND4 output documentation | FOM < 0.1 = CTF fit failed; micrograph discarded |
| CTF estimation | defocus range | 1,000–100,000 Å | GOLD | Physical constraint (effective CTF correction range) | Outside range = CTF correction invalid |
| Particle picking | particles_picked | > 1,000 | BRONZE | Community minimum for 2D classification to converge | < 1,000 particles → 2D classification meaningless |
| 2D classification | junk_fraction | > 0.70 halts | BRONZE | Derived from community practice; MFSD2B: 2.2% yield considered normal | > 70% junk indicates picking failure, not biology |
| 2D classification | junk_fraction | > 0.50 advisory | BRONZE | Community heuristic | Advisory to check picker parameters |
| Orientation distribution | anisotropy_ratio | > 10.0 halts | BRONZE | Rosenthal & Henderson 2003 (orientation uniformity requirement for high-resolution reconstruction) | > 10x anisotropy = reconstruction will be anisotropic; high-res in preferred view direction only |
| FSC resolution | fsc_0143_resolution_A | not None and < 20 Å | GOLD | Henderson et al. 2012 (FSC 0.143 gold-standard criterion) | FSC never crossing 0.143 = reconstruction did not converge; reporting any resolution claim is invalid |
| Ice quality | mean_micrograph_intensity | 0.3–0.9 (normalized) | BRONZE | Community practice | Outside range = too thick (bright) or too thin/empty (dark) |

### Evidence level definitions
- **GOLD**: Published consensus (Henderson et al. 2012 FSC 0.143); cannot be silently overridden; override requires written justification logged in audit trail
- **SILVER**: Method-specific best practice (CTFFIND4 documentation); requires logged justification to override
- **BRONZE**: Community heuristic (drift < 50 Å, junk fraction); can be overridden silently; override logged automatically

---

## 4. Benchmark Experiment Specs

### Dataset 1: β-galactosidase (EMPIAR-10061) — gold standard true negative
- **EMPIAR ID**: 10061
- **Expected resolution**: 2.2 Å (published; Bartesaghi et al. 2015, Science)
- **Pixel size**: 0.885 Å/pix
- **Voltage**: 300 kV
- **Symmetry**: D2
- **QC profile**: `cryoem_spa_purified`
- **Success criteria**:
  - All QC gates pass (zero false positives)
  - Final FSC 0.143 resolution within 0.2 Å of published (i.e., < 2.4 Å)
  - Full 23-step pipeline completes without halt
  - Audit JSONL contains events for all 23 steps
- **Metrics to record**:
  - `fsc_0143_resolution_A`: target < 2.4
  - `total_wall_time_min`: target < 480 (8 hr)
  - `micrographs_accepted` / `micrographs_total`
  - `particles_final`
  - `gpu_hours`
  - `estimated_cost_usd`
  - `qc_gates_fired` / `qc_gates_passed`

### Dataset 2: TRPV1 ion channel (EMPIAR-10005) — membrane protein profile validation
- **EMPIAR ID**: 10005
- **Expected resolution**: 3.4 Å (Liao et al. 2013, Nature)
- **Pixel size**: 1.22 Å/pix
- **Voltage**: 300 kV
- **Symmetry**: C4
- **QC profile**: `cryoem_spa_membrane`
- **Success criteria**:
  - With `cryoem_spa_purified` profile: motion gate FIRES (expected; membrane proteins exhibit 30–60% more beam-induced motion)
  - With `cryoem_spa_membrane` profile: motion gate passes, pipeline completes
  - Demonstrates false-positive elimination by profile switching
  - Final resolution within 0.5 Å of published (i.e., < 3.9 Å)
- **Metrics to record**:
  - `purified_profile_halt_step`: should be `motion_correction`
  - `membrane_profile_resolution_A`
  - Micrographs rejected by default profile vs. membrane profile (show difference)

### Dataset 3: Known-bad dataset for true positive QC gate validation
- **Candidate**: EMPIAR-10017 (β-galactosidase with known stage drift issues)
- **Success criteria**:
  - Motion correction gate fires on at least 20% of micrographs
  - Gate proposes specific remediation text
  - User override (simulated) allows continuation with audit log entry
  - Partial dataset (post-override) still achieves reasonable resolution

### Dataset 4: T20S proteasome (EMPIAR-10028) — scalability at high particle count
- **EMPIAR ID**: 10028
- **Expected resolution**: Sub-3 Å
- **Symmetry**: D7
- **Success criteria**:
  - All gates pass
  - Symmetry applied correctly (D7)
  - > 100,000 particles in final set
  - Parallel phase fan-out active (>1 batch submitted simultaneously)

### Comparison plan
- **Comparator A**: Manual CryoSPARC GUI (expert operator, same datasets) → FSC resolution and wall time recorded
- **Comparator B**: CryoSPARC Live (silent threshold exclusion, no interactive halt) → show what happens on TRPV1: Live silently rejects good micrographs; BioMate halts, user overrides, retains data
- **Comparator C**: RELION 4 on-the-fly + Schemes (single global CTF filter)
- **Key differentiating experiment**: Run difficult dataset (EMPIAR-10005) through BioMate and CryoSPARC Live in parallel. BioMate halts with explanation + suggestion; user overrides with justification recorded in JSONL. CryoSPARC Live continues silently, losing valid micrographs. Compare final resolutions and valid micrograph counts.

---

## 5. Paper Differentiators

### The 6 capabilities only BioMate has (vs. all other tools)

| Capability | CryoSPARC Live | RELION Schemes | Scipion | TranSPHIRE | Warp | cryoAssess | BioMate |
|---|---|---|---|---|---|---|---|
| Real-time monitoring | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ | ✅ |
| Threshold-based data exclusion | ✅ | ✅ | ❌ | ✅ | ✅ | ✅ | ✅ |
| **Interactive halt + human decision** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Protocol-aware biology profiles** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Failure-time actionable suggestions** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Evidence-graded override governance** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Quantified GPU cost savings (pilot-then-full)** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |
| **Portable JSONL audit trail** | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

### Key distinction from CryoSPARC Live (primary competitor — use this in introduction)
> "CryoSPARC Live performs threshold-based exposure exclusion — silently marking bad micrographs as 'rejected' and continuing processing. The 'Auto-Pause' in v5.0 is triggered by absence of new data, not by quality failure. BioMate's differentiator is categorical: it halts downstream job submission at the point of failure, presents the investigator with the failing metric, its evidence level, and specific parameter suggestions, and records their explicit decision before proceeding. This transforms QC from silent data loss into governed human-in-the-loop oversight."

### Key intro/conclusion quotes derived from paper plan

**Introduction hook:**
> "In a typical 1,000-micrograph SPA dataset, a motion correction failure caught at step 2 saves approximately 8 GPU-hours of downstream compute — equivalent to the cost of the entire preprocessing phase. Yet every existing cryo-EM automation tool continues silently past such failures, forcing investigators to discover data loss only in post-hoc processing logs."

**Protocol-blindness problem:**
> "Membrane proteins exhibit 30–60% more beam-induced motion than soluble proteins due to lipid bilayer flexibility. Applying purified-protein drift thresholds (< 50 Å) to membrane protein data produces systematic false-positive rejections — silently discarding valid, usable micrographs. No existing automated tool implements biology-aware QC profiles."

**Evidence provenance:**
> "Threshold values in CryoSPARC Live, RELION, and Warp are either user-defined or tool defaults with no citation. There is no mechanism to know whether a threshold reflects published community consensus, instrument specification, or developer intuition. BioMate's GOLD/SILVER/BRONZE evidence tier is the first such classification in any cryo-EM tool."

**Conclusion:**
> "BioMate's interactive QC governance closes the gap between automated monitoring (which all major tools provide) and accountable human oversight (which none provide). The result is a system where every threshold that halts a pipeline is traceable to published evidence, every override is logged with justification, and the full decision history of a structural determination is portable and auditable."

### Target journal decision
- **Nature Methods**: if FSC resolution matches manual processing (within 0.2 Å) AND significant time/cost savings demonstrated
- **Nature Communications**: if FSC matches but methodological advance is primarily automation + governance
- **Journal of Structural Biology**: fallback

---

## 6. Additional Implementation Notes

### MFSD2B-derived parameters (for < 60 kDa TM core in saposin nanodisc)
```python
MFSD2B_PARAMS = {
    "pixel_size": 0.649,               # Å/pix @ 130,000× on K3
    "defocus_range": [1.1, 2.1],       # μm underfocus (positive values in paper)
    "total_dose": 60,                  # e⁻/Å²
    "frames": 60,
    "particle_yield_fraction": 0.022,  # 6.6M → 146K = 2.2% (normal for nanodisc)
    "final_particles": 146629,
    "final_resolution_A": 3.03,        # DDM condition
    "picker_strategy": "blob+template+topaz",  # 3-picker mandatory
    "nanodisc_type": "saposin_A",
    "lipid_delivery": "gamma_cyclodextrin",
    "reconstitution_ratio": "protein:saposin:lipid = 1:15",
}
```

### VMAT2-derived parameters (55 kDa in saposin nanodisc)
```python
VMAT2_PARAMS = {
    "pixel_size": 0.83,
    "defocus_range": [-0.8, -2.5],
    "total_dose": 60,
    "frames": 50,
    "box_size": 256,
    "nanodisc_diameter_nm": 10,
    "particle_count_target": 200000,
    "final_resolution_A": [2.7, 2.9],  # two drug-bound states
    "molprobity_target": 1.5,
    "ramachandran_favored": 0.97,
    "saposin_lipid_mix": "POPC:POPE:POPG = 3:1:1",
    "saposin_molar_ratio": "protein:saposin:lipid = 1:10:200",
    "gamma_cyclodextrin_pct": 0.5,
}
```

### Universal invariant principles (never violate in protocol generation)
1. Gold-standard FSC at 0.143 — always report; never use 0.5 as primary resolution criterion
2. MolProbity < 2.0 for PDB deposition
3. Negative stain BEFORE cryo-EM (confirms complex assembly, particle size, no aggregation)
4. Functional validation before structural study for active/assembled systems
5. Reference dataset mandatory for comparative studies (drug-bound without apo cannot be interpreted)
6. CTF FOM < 0.1 → discard micrograph; no particle count compensates for bad CTF
7. Ligand density at < 4σ is unreliable — annotate as uncertain
8. Never apply symmetry without experimental evidence — start C1, verify from 2D classes
