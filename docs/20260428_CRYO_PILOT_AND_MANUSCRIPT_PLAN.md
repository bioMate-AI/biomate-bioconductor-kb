# CryoEM Pilot Work & Manuscript Plan — 2026-04-28

## Current State Assessment

### What actually exists (honest audit)

#### Google.org Proposal (`docs/20260427_GOOGLE_AI4SCIENCE_PROPOSAL_CRYO_ENSEMBLE.md`)
- Complete, well-written, scientifically compelling
- $2.8M over 3 years; deadline **May 1, 2026** (3 days)
- **Critical gap**: Requires academic/nonprofit PI affiliation. BioMate alone is ineligible.
- Sister (structural biologist) must be named PI from an academic institution
- Status: ready to submit once institutional affiliation is confirmed

#### CryoEnsemble Manuscript (`research_repos/cryoensemble_paper/`)
- Well-framed paper, good literature positioning, formal proof of BME insufficiency
- **Critical weakness: ALL results use a Gaussian perturbation model, NOT actual BioEmu or cryoDRGN**
  - Section 2.2 explicitly states: "three-tier Gaussian perturbation model... approximates BioEmu-1's multi-scale ensemble sampling while being computable without ML inference"
  - Section 2.3: "simulated cryoDRGN clustering" — not actual cryoDRGN on real particle data
  - The 10-protein results (Table 2: 10.0% gap, Table 3: +16.1% pockets, Table 4: BME→0) are all simulation artifacts
- Must be submitted to bioRxiv EITHER as a "proof-of-concept with surrogate model" (honest framing) OR after replacing with actual BioEmu + cryoDRGN data (the right scientific standard)

#### BioMate-Cryo Benchmark Paper (`research_repos/cryo_em_benchmark_paper/`)
- **Strongest paper** — has REAL benchmark results:
  - P36: EMPIAR-10028, 3.98 Å FSC, 7.4h wall, $6.29, 24 CryoSPARC jobs
  - P52: 1.78 Å FSC (Nyquist-limited), 4-GPU parallel, 3.4× speedup, $0.75
- Missing: protocol discrimination experiment (membrane protein profile vs. purified protein)
- Missing: comparison table vs. CryoSPARC Live, RELION, Warp
- **This paper is ~70% ready for submission. Highest priority.**

#### Pilot Study Plan (`docs/20260427_PILOT_STUDY_CRYO_ENSEMBLE.md`)
- Well-designed 6-week plan (β₂AR + TRPV1, $100 compute cost)
- **Not yet executed** — this is a plan, not results
- Scripts written, EMPIAR targets identified, compute cost estimated

---

## Priority Matrix

| Work Item | Impact | Urgency | Effort | Priority |
|---|---|---|---|---|
| Submit BioMate-Cryo to bioRxiv | High (real data) | High (1 week) | Low | **1st** |
| Execute pilot study (workflow 12886 + 12885) | High (proposal proof) | High (before May 1) | Medium | **2nd** |
| BioMate-Cryo: protocol discrimination experiment | High (key missing result) | Medium | Medium | **3rd** |
| CryoEnsemble: replace Gaussian model with actual BioEmu | Critical for publication | Medium | High | **4th** |
| Submit revised CryoEnsemble to bioRxiv (honest framing) | Medium | Low | Low | **5th** |

---

## Immediate Pilot Work (Before May 1 Deadline)

### Pilot 0 — Protein Dynamics on β₂AR and TRPV1 (2 days, ~$5 compute)

Run BioMate workflow 12886 (protein dynamics pipeline) on the two pilot targets. This gives actual ensemble data (even with MDAnalysis fallback if full BioEmu not available) to insert as real preliminary data into the proposal.

```bash
# β₂AR: UniProt P07550, PDB 2RH1 chain A
nextflow run workflows/protein_dynamics.nf \
  --input sequences/beta2ar.fasta \
  --n_samples 500 \
  --outdir s3://biomate-nextflow-work/pilot/beta2ar/

# TRPV1: UniProt Q8NER1, PDB 3J5P chain A
nextflow run workflows/protein_dynamics.nf \
  --input sequences/trpv1.fasta \
  --n_samples 500 \
  --outdir s3://biomate-nextflow-work/pilot/trpv1/
```

**Output for proposal**: RMSD spread histogram showing ensemble diversity (>1 Å confirms multi-conformation sampling). One figure, one paragraph of preliminary results.

### Pilot 1 — Gap Analysis Script on β₂AR + TRPV1 (1 day, $0 compute after Pilot 0)

Run the gap analysis script from `docs/20260427_PILOT_STUDY_CRYO_ENSEMBLE.md` against the Gaussian-simulated cryoDRGN centroids (using existing simulation), but applied to the REAL protein dynamics output from Pilot 0. This converts the simulated paper results to partially-real results.

**Expected output**: Gap fraction for both proteins. If consistent with simulated 10%, that validates the simulation model. If different, it updates the claim with real data.

---

## Further Pilot Works (Post-Submission, 1–8 Weeks)

### Pilot 2 — Real cryoDRGN on EMPIAR-10059 TRPV1 (2 weeks, ~$80 GPU compute)

**Purpose**: Replace the simulated cryoDRGN clustering with actual heterogeneity analysis on real cryo-EM data. This is the single most important experiment for the CryoEnsemble paper's credibility.

```bash
# Run BioMate workflow 12885 (cryo-het / cryoDRGN)
nextflow run workflows/cryo_heterogeneity.nf \
  --particles s3://biomate-nextflow-work/pilot/empiar/10059/particles.mrcs \
  --ctf s3://biomate-nextflow-work/pilot/empiar/10059/ctf.pkl \
  --n_zdim 8 \
  --n_epochs 20 \
  --n_clusters 20 \
  --outdir s3://biomate-nextflow-work/pilot/trpv1-cryodrgn/
```

**Why TRPV1 first**: Smaller dataset (35,645 particles vs. 127,000 for β₂AR); cryoDRGN already published on TRPV1 (Zhong et al. 2021) providing a direct reference comparison; lower compute cost.

**Expected output**: 20 cluster volumes as CryoSPARC .mrc files. Comparison of real cryoDRGN clusters vs. the simulated k-means clusters. Does the real gap fraction match ~10%?

### Pilot 3 — Cryptic Site Validation on β₂AR (2–3 weeks, ~$30 compute)

**This is the highest-impact experiment for the Google proposal.**

β₂AR has a validated cryptic allosteric Na⁺ binding site between TM1/TM2/TM7 (Liu et al., Science 2012, doi:10.1126/science.1215142). This site opens transiently and is not present in the ground-state Gs-coupled structure (EMPIAR-10258). If our gap analysis identifies conformers with this pocket, it directly proves the proposal's drug discovery value with experimental precedent.

**Protocol**:
1. Run cryoDRGN on EMPIAR-10258 (β₂AR, 127,000 particles, ~$80 GPU compute)
2. Run protein dynamics on β₂AR (Pilot 0 outputs)
3. Run fpocket on all conformers — identify clusters with Na⁺ site geometry (residues D792.50, S1213.39, N3227.45)
4. Check: are gap conformers enriched for Na⁺ site openness? (Fisher's exact test, p-value)

**Expected outcome**: Gap conformers show 2–4× enrichment for Na⁺ site openness vs. cryoDRGN-captured conformers. This is a landmark result.

**In manuscript**: Figure 4 — "CryoEnsemble gap conformers recover validated cryptic allosteric site in β₂AR"

### Pilot 4 — Resolution Floor Quantification (1 week, ~$50 compute)

**Purpose**: Directly quantify the "particle-count resolution floor" claim — at what particle count do conformational states become unrecoverable?

**Protocol**:
1. Take EMPIAR-10028 β-galactosidase (known homogeneous — good control)
2. Systematically subsample: 100%, 50%, 20%, 10%, 5%, 2%, 1% of particles
3. Run 3D reconstruction at each fraction via BioMate-Cryo pipeline
4. Measure: FSC resolution, number of visible conformational classes, Euler angle distribution

**Expected output**: Resolution vs. particle count curve. Shows that below ~2–5% of total particles (typically 500–2,000 particles for a 10,000-particle dataset), reconstruction degrades — directly quantifying the floor claimed in the proposal.

**In manuscript**: Figure 2 (BioMate-Cryo paper) or supplementary figure (CryoEnsemble paper)

### Pilot 5 — Membrane Protein Protocol Discrimination (2 weeks, ~$40 compute)

**Purpose**: Complete the missing BioMate-Cryo benchmark — quantify how many micrographs the `membrane_protein` QC profile saves vs. the default `purified_protein` profile on a membrane protein dataset.

**Dataset**: EMPIAR-10005 (TRPV1 in nanodisc, 2.9 Å, 34,967 particles) — this is a membrane protein that exhibits elevated beam-induced motion.

**Protocol**:
1. Process EMPIAR-10005 twice through BioMate-Cryo:
   - Run A: `--profile purified_protein` (strict drift ≤50 Å, CTF ≥0.70)
   - Run B: `--profile membrane_protein` (relaxed drift ≤80 Å, CTF ≥0.65)
2. Compare: micrographs accepted/rejected, final particle count, FSC resolution
3. Compute: false-positive rejection rate = micrographs discarded by Run A but recovered by Run B that produce good particle picks

**Expected output**:
- Run A rejects ~20–35% more micrographs than Run B (based on published literature)
- Run B achieves higher final particle count and equal or better FSC
- Key metric: false-positive micrograph rejection rate quantified for the first time

**In BioMate-Cryo manuscript**: Table 2 (protocol discrimination benchmark). This is the paper's second key result after the P36/P52 benchmarks.

### Pilot 6 — Adenylate Kinase as Open/Closed Benchmark (1 week, ~$20 compute)

**Purpose**: Adenylate kinase (ADK) is the "hydrogen atom" of conformational dynamics — it has a known open (4AKE) and closed (1AKE) state with a 7.2 Å RMSD between them, well-characterized by MD and experiment. Adding it as a positive control to the CryoEnsemble paper provides the strongest validation.

**Why it's ideal**:
- Two crystal structures (open + closed) are the ground truth for the gap
- The open→closed transition is exactly a "domain motion" (Tier 2 in the Gaussian model)
- MDAnalysis + DESRES MD data is publicly available
- EMPIAR-10544 has the ADK particle stack
- Reviewers know this protein — it's a benchmark benchmark

**Protocol**:
1. Run protein dynamics on 4AKE and 1AKE sequences separately (500 conformers each)
2. Run gap analysis: does the 4AKE ensemble (open-biased) capture the closed state (1AKE) and vice versa?
3. Compute gap fraction using 1AKE as "ground truth gap target"
4. This gives an absolute validation of the gap metric against a known answer

**Expected result**: ADK gap fraction is dominated by the open↔closed transition (~7 Å RMSD), providing a positive control where the "correct answer" is known from crystallography.

**In CryoEnsemble manuscript**: Section 3.1 — positive control validation of the gap metric.

---

## Manuscript Improvements

### BioMate-Cryo Paper — Missing Experiments & Additions

**Status**: 70% ready. Missing:

1. **Protocol discrimination table** (Pilot 5 above) — adds Table 2
2. **Comparison table vs. existing tools**: what CryoSPARC Live, RELION, Warp, and TranSPHIRE each audit vs. what BioMate-Cryo audits. Makes the "three gaps" framing concrete.

   | Feature | CryoSPARC Live | RELION | Warp | BioMate-Cryo |
   |---|---|---|---|---|
   | Automatic filtering | ✓ | ✓ | ✓ | ✗ (interactive gates) |
   | Sample-specific profiles | ✗ | ✗ | ✗ | ✓ (4 profiles) |
   | Evidence-graded thresholds | ✗ | ✗ | ✗ | ✓ (GOLD/SILVER/BRONZE) |
   | Actionable diagnostics | ✗ | ✗ | partial | ✓ |
   | Portable audit trail (JSONL) | ✗ | ✗ | ✗ | ✓ |
   | Multi-GPU parallel execution | ✗ | ✓ | ✓ | ✓ (3.4× speedup) |

3. **Time savings calculation**: estimated hours saved per typical dataset by catching QC failures at gate time vs. discovering them after 2D classification fails. Use the P36 run as a worked example.

4. **Submission checklist**: What does BioMate-Cryo's audit trail satisfy from the EMDB/WWPDB structure deposition requirements? This ties the paper to an immediate practical need every structural biologist faces.

5. **An additional EMPIAR dataset**: EMPIAR-10258 (β₂AR, membrane protein) — process with `membrane_protein` profile and report FSC. Adds scientific diversity and links to the CryoEnsemble story.

### CryoEnsemble Paper — Critical Fixes Before Submission

**The paper's current Gaussian model results are scientifically honest (clearly disclosed in methods) but will attract reviewer skepticism. Two paths:**

**Path A — Submit with current simulation, commit to actual BioEmu in revision** (faster, gets priority date):
- Revise abstract to say "surrogate multi-scale model approximating BioEmu-1" — don't call it BioEmu
- Add a dedicated limitations section: "All results presented use a Gaussian perturbation surrogate... Year 1 of the funded CryoEnsemble project will replace these with actual BioEmu-1 inference and cryoDRGN analysis on real particle data"
- The BME proof (Section 3.3) is mathematically rigorous and does not depend on the model — this holds regardless
- Submit to bioRxiv as a "framework paper" not an "empirical results paper"

**Path B — Execute Pilot 2 + 3, replace with real data first** (stronger, takes 4–6 weeks):
- Requires actual cryoDRGN on EMPIAR-10059 and EMPIAR-10258
- Requires actual BioEmu ensemble from workflow 12886
- Results in a paper reviewers at Nature Methods will take seriously
- Recommended path for journal submission

**Minimum additions for Path A (bioRxiv only)**:
1. Add ADK positive control (Pilot 6) — 1 week, confirms gap metric works on known answer
2. Revise framing throughout: "Gaussian perturbation surrogate" not "generative model"
3. Add limitations section with explicit commitment to actual BioEmu data

**For Path B (journal target)**:
1. Replace Section 2.2 with actual BioEmu protocol (via workflow 12886)
2. Replace Section 2.3 with actual cryoDRGN protocol (via workflow 12885)
3. Add Figure 5: Cryptic site validation in β₂AR (Pilot 3)
4. Add Figure 2 panel: Resolution floor quantification (Pilot 4)
5. This is a Nature Methods-caliber paper

---

## Proposed Figure Set for Both Papers

### BioMate-Cryo (target: 5 figures)
- **Figure 1**: Pipeline architecture + QC gate schematic (exists)
- **Figure 2**: P36 benchmark: per-job timing, particle stack, FSC curve at 3.98 Å
- **Figure 3**: P52 multi-GPU: speedup bars (5.7×, 2.8×, 2.5×, 3.4× total); cost comparison ($6.29 vs. $0.75)
- **Figure 4**: Protocol discrimination: EMPIAR-10005 micrograph acceptance rates by profile (Pilot 5)
- **Figure 5**: Tool comparison table + audit trail schema

### CryoEnsemble (target: 6 figures)
- **Figure 1**: Conceptual — three mechanisms of conformational incompleteness (vitrification, AWI, resolution floor) + CryoEnsemble solution schematic
- **Figure 2**: Gap analysis across 10 proteins: min-RMSD histograms, gap fraction bar chart; ADK positive control validation (Pilot 6)
- **Figure 3**: Pocket landscape: pocket score distributions for gap vs. non-gap conformers, Mann-Whitney p-values
- **Figure 4**: BME reweighting proof: posterior gap probability vs. λ curve for all 10 proteins (proof of map-level insufficiency)
- **Figure 5**: β₂AR cryptic Na⁺ site enrichment in gap conformers (Pilot 3) — the drug discovery flagship result
- **Figure 6**: CryoEnsemble architecture and expected workflow (future direction)

---

## Timeline

| Week | Pilot | Manuscript |
|---|---|---|
| Now (Week 0) | Pilot 0: workflow 12886 on β₂AR + TRPV1 (before May 1) | — |
| Week 1 | Pilot 1: gap analysis on Pilot 0 outputs | Submit BioMate-Cryo to bioRxiv |
| Week 2–3 | Pilot 2: cryoDRGN on EMPIAR-10059 | — |
| Week 3–4 | Pilot 5: membrane protein protocol discrimination | Add Table 2 to BioMate-Cryo; revise CryoEnsemble abstract + limitations |
| Week 4–5 | Pilot 3: β₂AR cryptic site validation | — |
| Week 5 | Pilot 6: ADK positive control | Submit CryoEnsemble to bioRxiv (Path A) or continue to journal (Path B) |
| Week 6–8 | Pilot 4: resolution floor quantification | Submit BioMate-Cryo to Nature Methods |
| Week 10–12 | — | Submit CryoEnsemble to Nature Methods (Path B) |

---

## Cost Summary

| Pilot | Compute | Duration |
|---|---|---|
| 0 — Protein dynamics β₂AR + TRPV1 | ~$5 | 1–2 days |
| 1 — Gap analysis script | $0 | 1 day |
| 2 — cryoDRGN on EMPIAR-10059 | ~$80 | 2 weeks |
| 3 — β₂AR cryptic site validation | ~$30 | 2–3 weeks |
| 4 — Resolution floor quantification | ~$50 | 1 week |
| 5 — Membrane protein protocol discrimination | ~$40 | 2 weeks |
| 6 — Adenylate kinase positive control | ~$20 | 1 week |
| **Total** | **~$225** | **8 weeks** |
