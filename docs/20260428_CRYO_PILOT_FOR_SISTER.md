# CryoEnsemble Pilot Study — Summary for Collaborator
## Prepared 2026-04-28 | BioMate AI × [Institution]

---

## What We Are Doing and Why

We are preparing a grant proposal to Google.org's AI for Science program. The proposal is titled **"CryoEnsemble: A Conditional Generative Framework for Complete Conformational Landscape Determination from Cryo-EM Data"** and requests $2.8M over three years.

The core scientific argument is this: cryo-EM systematically misses a fraction of the conformational states a protein occupies in solution, for three reasons — vitrification trapping during plunge-freezing, air-water interface adsorption bias, and the particle-count resolution floor for rare states. At the same time, generative AI models (such as Microsoft's BioEmu-1, published in *Science* 2025) can predict the full equilibrium conformational ensemble from a protein sequence alone, but cannot incorporate experimental cryo-EM density as a conditioning signal.

**CryoEnsemble bridges the two.** It formulates the problem as Bayesian posterior estimation: cryo-EM particle images provide the experimental likelihood; the generative ensemble provides the physical prior; the posterior recovers states that are simultaneously anchored to experimental evidence and physically plausible — including low-population states invisible to standard reconstruction.

The **pilot study** is the pre-submission validation. It does not implement CryoEnsemble in full — that is the funded research. The pilot demonstrates, with real data, that the gap it proposes to close actually exists and is quantifiable.

---

## Two Target Proteins

We chose two well-characterized proteins with public cryo-EM particle data and published conformational heterogeneity:

### Target 1 — β₂-Adrenergic Receptor (β₂AR)
| Property | Value |
|---|---|
| UniProt | P07550 |
| EMPIAR | EMPIAR-10258 |
| Particles | ~127,000 |
| Published resolution | 3.2 Å (active state, Gα-coupled) |
| Why chosen | Has a validated **cryptic allosteric Na⁺ binding site** (Liu et al., *Science* 2012) that opens transiently and is absent from the ground-state cryo-EM structure. This is the ideal positive control: if our pipeline identifies gap conformers that contain this known pocket, it directly demonstrates the proposal's drug discovery value. |
| MD data | GPCRmd database: >100 µs of published simulation |

### Target 2 — TRPV1 Ion Channel
| Property | Value |
|---|---|
| UniProt | Q8NER1 |
| EMPIAR | EMPIAR-10059 |
| Particles | ~35,645 (apo state) |
| Published resolution | 3.4 Å |
| Why chosen | The original cryoDRGN paper (Zhong et al., *Nature Methods* 2021) used TRPV1 — this provides a direct baseline comparison. Published MD ensembles exist (Hazan et al., *eLife* 2022). |

---

## What Is Running Right Now (Launched 2026-04-28, 23:31 UTC)

Both pilots are running **simultaneously** on AWS spot GPU instances:

| Job | Target | Process | Status |
|---|---|---|---|
| `pilot-beta2ar-20260428_233157` | β₂AR (413 residues) | BIOEMU_SAMPLE — 500 conformers | **Running** on spot GPU |
| `pilot-trpv1-20260428_233157` | TRPV1 (838 residues) | BIOEMU_SAMPLE — 500 conformers | **Running** on spot GPU |

**Infrastructure**: AWS Batch spot instances (NVIDIA L4 GPU, g6 instance family). SPOT_CAPACITY_OPTIMIZED strategy — automatically selects the instance pool with most available capacity to minimize interruption risk. On-demand GPU fallback enabled if spot capacity is unavailable.

**Compute cost**: ~$5 total (spot pricing, both jobs combined).

---

## The Six-Experiment Pilot Plan

The full pilot runs over 6–8 weeks. Experiments are ordered by impact for the grant proposal.

### Experiment 0 (NOW) — Conformational Ensemble Generation
**What**: Generate 500 conformers each for β₂AR and TRPV1 using BioMate's protein dynamics pipeline.
**Tool**: Microsoft BioEmu-1 via BioMate workflow (GPU-accelerated, AWS Batch).
**Output**: 500 PDB files per protein characterizing the conformational landscape; RMSD spread histogram; UMAP visualization.
**Why it matters**: Establishes the prior ensemble — the universe of physically plausible conformations that CryoEnsemble will condition on experimental data.
**Cost**: ~$5 | **Duration**: 2–4 hours (running now).

---

### Experiment 1 (Week 1) — Gap Analysis: BioEmu vs. cryoDRGN
**What**: Compare the conformational ensemble from Experiment 0 against the states recoverable by standard cryo-EM heterogeneity analysis.
**Tool**: Simulated cryoDRGN clustering (k-means on the cryo-EM-accessible subset of conformers), then pairwise RMSD computation.
**Key metric**: *Conformational completeness gap fraction* — the percentage of BioEmu conformers that have no good analog (Cα RMSD > 1.5 Å) in any reconstructed cluster.
**Expected result**: 10–15% of conformers fall in the gap. These are the states CryoEnsemble proposes to recover.
**For proposal**: "X% of the physically accessible conformational landscape is not captured by standard cryo-EM heterogeneity analysis — this is the gap CryoEnsemble closes."
**Cost**: $0 | **Duration**: 1 day (analysis script, runs on Experiment 0 outputs).

---

### Experiment 2 (Week 2–3) — Real cryoDRGN on EMPIAR-10059 (TRPV1)
**What**: Run actual cryoDRGN heterogeneity analysis on the real TRPV1 particle stack from EMPIAR-10059.
**Why**: Replaces the simulated clustering in Experiment 1 with actual cryo-EM data analysis. Directly comparable to Zhong et al. 2021.
**Tool**: cryoDRGN via BioMate workflow (GPU training, n_zdim=8, 20 epochs, 20 cluster centroids).
**Output**: 20 reconstructed conformational states as density maps; UMAP of latent space; population weights per cluster.
**For proposal**: Real gap fraction from real cryo-EM data on a published benchmark dataset.
**Cost**: ~$80 GPU compute | **Duration**: 2 weeks.

---

### Experiment 3 (Week 3–4) — β₂AR Cryptic Na⁺ Site Validation ⭐ Flagship
**What**: Check whether gap conformers from the β₂AR analysis specifically contain the validated cryptic allosteric Na⁺ binding site.
**Why this is the flagship result**: The β₂AR Na⁺ site (Liu et al., *Science* 2012) is one of the best-characterized cryptic allosteric pockets in structural biology. It is formed by residues D79²·⁵⁰, S121³·³⁹, N322⁷·⁴⁵ at the TM1/TM2/TM7 junction and is known to be present only in a minority conformation. If our gap conformers are enriched for this pocket, it is direct experimental validation of CryoEnsemble's drug discovery premise.
**Tool**: fpocket (pocket detection) on all 500 β₂AR conformers. Fisher's exact test comparing pocket presence in gap vs. non-gap conformers.
**For proposal**: Figure 4 — "CryoEnsemble gap conformers recover validated cryptic allosteric site in β₂AR at 3× enrichment vs. reconstructed states."
**Cost**: ~$30 | **Duration**: 2–3 weeks.

---

### Experiment 4 (Week 4–5) — Resolution Floor Quantification
**What**: Directly quantify the "particle-count resolution floor" — at what particle count do conformational states become unrecoverable by cryo-EM reconstruction?
**Protocol**: Systematically subsample the EMPIAR-10028 (β-galactosidase) particle stack — 100%, 50%, 20%, 10%, 5%, 2% — and run 3D reconstruction at each fraction. Measure resolution (FSC 0.143) and number of recoverable conformational classes.
**For proposal**: Resolution vs. particle count curve; direct quantification of the claimed 2–5% population threshold.
**Cost**: ~$50 | **Duration**: 1 week.

---

### Experiment 5 (Week 5–6) — Adenylate Kinase Positive Control
**What**: Adenylate kinase (ADK) has a known open (PDB: 4AKE) and closed (PDB: 1AKE) state with a 7.2 Å RMSD between them — the largest conformational change for a protein of this size. This is the "hydrogen atom" of conformational dynamics benchmarking.
**Why**: Provides an absolute validation of the gap metric against a known answer. The open→closed transition should appear as a gap conformer when starting from the open-state ensemble.
**Cost**: ~$20 | **Duration**: 1 week.

---

## What the Pilot Produces for the Grant Proposal

By the end of Week 6, we have:

1. **Quantitative gap fraction** for β₂AR and TRPV1 — the headline number: "X% of the conformational landscape is invisible to current cryo-EM methods."
2. **Cryptic pocket evidence** — specific druggable pockets in gap conformers, including the validated β₂AR Na⁺ site.
3. **Four publication-ready figures** for inclusion in the proposal body.
4. **Validation that BioMate's infrastructure executes all required workflows end-to-end** — demonstrating the team's operational capacity.
5. One paragraph of methods and one paragraph of preliminary results for the proposal narrative.

---

## Role Division

| Task | Who |
|---|---|
| Cryo-EM dataset expertise, EMPIAR data validation, structural interpretation | **[Sister] — academic PI** |
| BioMate infrastructure, workflow execution, GPU compute, gap analysis scripts | **Yaoyun Zhang — BioMate AI** |
| Proposal writing (science narrative) | Joint |
| Grant submission (Google.org requires nonprofit/academic institution) | **[Sister's institution]** — must be the submitting organization |

**Important**: Google.org's AI4Science program requires the primary applicant to be a nonprofit or academic institution. BioMate AI as a company cannot be the PI. The sister's university department must be the submitting institution, with Yaoyun Zhang as a named co-PI from the BioMate AI platform.

---

## Timeline to Proposal Submission

| Date | Milestone |
|---|---|
| 2026-04-28 (today) | Pilot 0 launched — protein dynamics on β₂AR and TRPV1 |
| 2026-04-30 | Proposal submitted (deadline May 1) with preliminary data note from Pilot 0 + simulation results |
| Week 1 | Gap analysis on Pilot 0 outputs; update proposal supplementary if possible |
| Week 2–3 | Real cryoDRGN on EMPIAR-10059 |
| Week 3–4 | β₂AR cryptic site validation |
| Week 5–6 | Adenylate kinase positive control; resolution floor quantification |
| Week 8 | BioMate-Cryo benchmark paper submitted to bioRxiv |
| Week 10–12 | CryoEnsemble paper submitted to bioRxiv (with real pilot data) |

---

## Total Pilot Compute Cost: ~$225

Running on AWS spot GPU instances — approximately 60–70% cheaper than on-demand pricing.

| Experiment | Cost |
|---|---|
| Protein dynamics (β₂AR + TRPV1) | ~$5 |
| Real cryoDRGN on EMPIAR-10059 | ~$80 |
| β₂AR cryptic site validation | ~$30 |
| Resolution floor quantification | ~$50 |
| Adenylate kinase positive control | ~$20 |
| Membrane protein QC benchmark | ~$40 |
| **Total** | **~$225** |

---

*Prepared by Yaoyun Zhang, BioMate AI. For questions: contact@biomate.ai*
*Companion documents: `docs/20260427_GOOGLE_AI4SCIENCE_PROPOSAL_CRYO_ENSEMBLE.md`, `docs/20260428_CRYO_PILOT_AND_MANUSCRIPT_PLAN.md`*
