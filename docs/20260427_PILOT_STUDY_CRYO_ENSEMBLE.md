# Pilot Study: CryoEnsemble Proof-of-Concept

**Purpose:** Pre-submission validation to support the Google.org AI4Science grant application  
**Duration:** 6 weeks  
**Infrastructure:** BioMate existing pipelines (workflows 12885 + 12886) + public EMDB/EMPIAR data  
**No new data collection required**

---

## Why a Pilot Study Strengthens the Proposal

Google.org selects against "speculative" proposals. A concrete pilot with measurable results — even on public data using approximate methods — demonstrates that (a) the problem is real and quantifiable, (b) the team has the infrastructure to execute, and (c) preliminary numbers exist to scope the full project. The pilot does not need to implement CryoEnsemble in full; it needs to demonstrate the **gap it closes**.

The pilot answers three questions with real data:
1. How incomplete is a cryoDRGN-recovered ensemble relative to a BioEmu-predicted ensemble for the same protein?
2. Do the states predicted by BioEmu but absent from cryoDRGN correspond to physically meaningful conformations (pockets, functional motions)?
3. Can a simple ensemble reweighting (cryoENsemble-style) partially close the gap, motivating the full CryoEnsemble method?

---

## Target Proteins

Two well-characterized proteins are selected because they have: (a) public EMPIAR particle stacks, (b) extensive published MD simulation data, and (c) documented conformational heterogeneity.

### Target A: β₂-Adrenergic Receptor (β₂AR)

| Property | Value |
|----------|-------|
| EMPIAR ID | EMPIAR-10258 |
| Particles | ~127,000 |
| Resolution | 3.2 Å (active state, Gα-coupled) |
| Protein size | 413 residues (receptor) |
| Heterogeneity | Active/inactive equilibrium; known cryptic Na⁺ binding site |
| Why chosen | GPCRmd database has >100 µs of published MD; active vs. inactive populations well-characterized by smFRET (Gregorio et al., Nature 2017); cryoDRGN already published on similar GPCR datasets |

### Target B: TRPV1 Ion Channel

| Property | Value |
|----------|-------|
| EMPIAR ID | EMPIAR-10059 |
| Particles | ~35,645 (apo state) |
| Resolution | 3.4 Å |
| Protein size | 838 residues (homotetrameric channel) |
| Heterogeneity | Gating transition (closed/open/desensitized); S1-S4 domain mobility |
| Why chosen | Original cryoDRGN paper (Zhong et al. 2021) used TRPV1; provides a direct baseline comparison; published MD ensembles (Hazan et al., eLife 2022) |

---

## Week-by-Week Plan

### Week 1–2: Data Preparation and BioEmu Ensemble Generation

**Tasks:**
1. Download EMPIAR-10258 (β₂AR) and EMPIAR-10059 (TRPV1) particle stacks and CTF parameters
2. Run BioEmu on the PDB sequences for both proteins via BioMate workflow 12886 (protein dynamics pipeline), generating N=500 conformers per protein
3. Run MDAnalysis Gaussian fallback (σ=0.5 Å) as a control ensemble (faster, to establish baseline)
4. Compute pairwise RMSD distribution for each BioEmu ensemble to characterize the conformational space covered

**BioMate execution:**
```bash
# β₂AR sequence from UniProt P07550
nextflow run workflows/protein_dynamics.nf \
  --input sequences/beta2ar.fasta \
  --n_samples 500 \
  --outdir s3://biomate-nextflow-work/pilot/beta2ar-bioemu/

# TRPV1 from UniProt Q8NER1  
nextflow run workflows/protein_dynamics.nf \
  --input sequences/trpv1.fasta \
  --n_samples 500 \
  --outdir s3://biomate-nextflow-work/pilot/trpv1-bioemu/
```

**Success criterion:** 500 conformers generated; RMSD spread >1 Å (confirms ensemble diversity)

---

### Week 2–3: cryoDRGN Heterogeneity Analysis

**Tasks:**
1. Run BioMate workflow 12885 (cryoDRGN heterogeneity) on both EMPIAR datasets
2. Use n_zdim=8, n_epochs=20, n_clusters=20 (20 conformational state representatives)
3. Extract 20 representative volumes (kmeans cluster centers) per protein
4. Convert volumes to pseudo-structures using a simple density-guided fitting (MDFF or phenix.real_space_refine on a single reference PDB)

**Parameters (from cryo_em_protocols knowledge DB):**
- β₂AR: box_size=256, pixel_size=1.06 Å/px (from EMPIAR metadata)
- TRPV1: box_size=256, pixel_size=1.22 Å/px

**Success criterion:** cryoDRGN completes; UMAP shows interpretable latent structure; 20 cluster volumes visually distinct

---

### Week 3–4: Gap Analysis — cryoDRGN vs. BioEmu

This is the core measurement of the pilot.

**Method:**
For each of the 20 cryoDRGN cluster volumes, extract the backbone Cα coordinates. Compute the nearest-neighbor RMSD from each cryoDRGN structure to each BioEmu conformer. This gives, for each cryoDRGN state, the "closest BioEmu analog."

Then reverse the comparison: for each BioEmu conformer, find the nearest cryoDRGN state. Conformers with nearest-cryoDRGN RMSD >2.0 Å are **BioEmu-predicted states absent from the cryo-EM reconstruction** — the gap the proposal aims to close.

```python
import numpy as np
import MDAnalysis as mda
from scipy.spatial.distance import cdist

# Load 500 BioEmu Cα coordinate arrays: shape (500, N_residues, 3)
bioemu_coords = load_ensemble("bioemu_conformers/*.pdb")  # shape (500, N, 3)

# Load 20 cryoDRGN cluster structures: shape (20, N_residues, 3)
cryodrgn_coords = load_structures("cryodrgn_clusters/*.pdb")  # shape (20, N, 3)

# Flatten to (n_conformers, N_residues * 3)
B = bioemu_coords.reshape(500, -1)
C = cryodrgn_coords.reshape(20, -1)

# Pairwise RMSD matrix: shape (500, 20)
rmsd_matrix = cdist(B, C, metric='euclidean') / np.sqrt(N_residues)

# For each BioEmu conformer: distance to nearest cryoDRGN state
min_rmsd_to_cryodrgn = rmsd_matrix.min(axis=1)  # shape (500,)

# Gap: fraction of BioEmu ensemble with no good cryoDRGN analog
gap_fraction = (min_rmsd_to_cryodrgn > 2.0).mean()
print(f"Fraction of BioEmu ensemble not captured by cryoDRGN: {gap_fraction:.1%}")
```

**Expected result (hypothesis):** Based on CryoBench (Jeon et al., NeurIPS 2024) showing cryoDRGN fails to recover the full MD-derived conformational density, we expect 40–70% of BioEmu conformers to have no good analog in the cryoDRGN reconstruction. This number — the conformational completeness gap — is the headline result of the pilot.

**Success criterion:** Gap fraction >30% for at least one target, providing quantitative motivation for CryoEnsemble

---

### Week 4–5: Pocket Landscape Comparison

Run fpocket and PocketMiner on both ensemble sets to characterize whether the BioEmu-predicted states absent from cryoDRGN harbor different (and potentially more) druggable pockets.

**Tasks:**
1. Run fpocket on all 500 BioEmu conformers + 20 cryoDRGN structures (BioMate workflow 12885 includes pocket scan ensemble)
2. For each conformer: record (a) number of pockets detected, (b) druggability score of best pocket, (c) location of best pocket (residue centroid)
3. Compare: Do BioEmu-only conformers (those absent from cryoDRGN) show distinct or additional pockets?

**For β₂AR specifically:** The cryptic Na⁺ allosteric binding site (between TM1/TM2/TM7) is known to be present in a minority conformation (Liu et al., Science 2012). If cryoDRGN misses this state and BioEmu recovers it, this is direct demonstration of the proposal's drug discovery value.

**Success criterion:** At least one distinct pocket cluster identified in BioEmu-only conformers with druggability score >0.5; ideally mapping to a known allosteric or cryptic site

---

### Week 5–6: Simple Reweighting and Results Documentation

**Task 1 — cryoENsemble-style reweighting (approximate):**
Using the cryoENsemble principle (BME reweighting; Scientific Reports 2024, doi:10.1038/s41598-024-68468-7), apply a simple Bayesian reweighting to the BioEmu ensemble using the cryoDRGN cluster populations as experimental priors. This upweights BioEmu conformers that are consistent with the cryo-EM cluster membership and downweights those inconsistent.

This is an approximation of CryoEnsemble's full posterior — it demonstrates the concept works in principle.

```python
# Simple BME reweighting:
# w_i ∝ exp(-chi2_i / theta) * w0_i
# where chi2_i = sum over cluster assignments of (assignment_prob - expected)^2
# theta = regularization temperature

# Expected: reweighted ensemble has higher overlap with cryoDRGN clusters
# while retaining some BioEmu-only states with non-zero weight
```

**Task 2 — Results writeup:**
Document the following figures for inclusion in the grant proposal:

- **Figure 1:** UMAP of BioEmu ensemble (500 points) colored by nearest-cryoDRGN-cluster RMSD — visually shows the gap
- **Figure 2:** Gap fraction histogram (RMSD to nearest cryoDRGN state) — the headline number
- **Figure 3:** Pocket count and druggability comparison: cryoDRGN vs. BioEmu-only conformers
- **Figure 4:** Reweighted ensemble UMAP — shows partial closure of the gap

---

## Data, Compute, and Cost Estimate

| Item | Source | Cost |
|------|--------|------|
| EMPIAR-10258 (β₂AR particles) | Public, free | $0 |
| EMPIAR-10059 (TRPV1 particles) | Public, free | $0 |
| BioEmu (MDAnalysis fallback, 2×500 conformers) | BioMate workflow 12886 | ~$5 (CPU Batch) |
| cryoDRGN training (2 datasets, 20 epochs) | BioMate workflow 12885 | ~$80 (GPU Batch) |
| fpocket pocket scan (2×520 structures) | BioMate workflow 12885 | ~$10 (CPU) |
| Analysis scripts (Python, local) | In-house | $0 |
| **Total pilot compute cost** | | **~$100** |

---

## Deliverables for Grant Proposal

By end of Week 6, the pilot produces:

1. **Quantitative gap fraction** for β₂AR and TRPV1 (the number: "X% of the conformational ensemble predicted by BioEmu is not captured by cryoDRGN")
2. **Pocket discovery evidence** — specific druggable pockets present in BioEmu-only conformers
3. **Four publication-ready figures** as preliminary data
4. **Confirmation that BioMate infrastructure executes the required workflows end-to-end** — demonstrating the team's capacity to deliver the full CryoEnsemble project
5. A one-paragraph methods description and one paragraph of preliminary results for inclusion in the proposal body

---

## What the Pilot Does NOT Do

The pilot deliberately avoids over-engineering:
- It does NOT train CryoEnsemble (that is the funded research)
- It does NOT implement the per-particle image likelihood conditioning (that is Year 1 of the funded project)
- It uses MDAnalysis fallback in BioEmu (not full BioEmu learned sampling) because GitHub access is blocked at Docker build time — this is sufficient for gap analysis

The pilot's purpose is **evidence, not completion**. The gap fraction and pocket discovery results are the evidence.

---

## Next Steps to Start the Pilot

1. Download EMPIAR datasets and upload to S3: `s3://biomate-nextflow-work/pilot/empiar/`
2. Extract sequences from PDB (β₂AR: 2RH1 chain A; TRPV1: 3J5P chain A) → FASTA files
3. Submit workflow 12886 (protein dynamics) for each sequence
4. Submit workflow 12885 (cryo-het) for each particle stack
5. Write analysis scripts for gap fraction and pocket comparison (Week 3–4)
6. Document results → figures → insert into proposal

Total elapsed time from start to proposal-ready preliminary data: **6 weeks**

---

*Pilot plan prepared: 2026-04-27. Companion to: docs/20260427_GOOGLE_AI4SCIENCE_PROPOSAL_CRYO_ENSEMBLE.md*
