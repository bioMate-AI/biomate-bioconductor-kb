# Google.org Impact Challenge: AI for Science — Research Proposal

**Project Title:** CryoEnsemble: A Conditional Generative Framework for Complete Conformational Landscape Determination from Cryo-EM Data

**Submitting Institution:** [Institution name — requires nonprofit / academic affiliation for Google.org eligibility]

**Principal Investigators:**
- [Sister's name], [Title], [Department], [Institution] — Cryo-EM structural biology, experimental design, data acquisition
- Yaoyun Zhang, BioMate AI Platform — AI systems, generative modeling, computational infrastructure

**Requested Amount:** $2,800,000 over 3 years

**Program:** Google.org Impact Challenge: AI for Science (2026 cycle, deadline May 1 2026)

---

## Abstract

Proteins are not static machines — they exist as dynamic ensembles of conformations that underlie virtually every biological function. Cryo-electron microscopy (cryo-EM) has transformed structural biology by resolving protein structures at near-atomic resolution, yet a fundamental paradox remains: the technique systematically captures only a fraction of the conformational states that a protein populates under physiological conditions. Physical biases introduced by sample preparation, vitrification, and preferred adsorption to the air-water interface narrow the observable ensemble to the most-populated, most-stable conformations, leaving functionally critical rare states — often the very states responsible for drug binding, allosteric signaling, and catalytic transitions — invisible to the experimenter.

Concurrently, generative AI models such as BioEmu-1 (Science 2025) can predict full equilibrium conformational ensembles from protein sequence alone, but these predictions are unconditioned on experimental evidence and cannot distinguish which predicted states are actually populated in a given experimental dataset.

We propose **CryoEnsemble**: a conditional generative framework that bridges these two worlds. CryoEnsemble jointly refines a generative ensemble model (trained on large-scale MD data) against the full particle image dataset from cryo-EM — not just the reconstructed map, but every raw particle image — to recover a posterior conformational ensemble that is simultaneously (1) physically plausible, (2) anchored to experimental density evidence, and (3) complete with respect to low-population states that classical reconstruction methods discard. The framework will be deployed on BioMate, an open AI-driven bioinformatics platform, enabling any structural biologist worldwide to apply CryoEnsemble to their cryo-EM datasets without custom software installation or computational expertise.

---

## 1. Significance and Motivation

### 1.1 The Conformational Completeness Problem

Protein function is inseparable from protein dynamics. Enzyme catalysis depends on transient active-site geometries; ion channels gate through conformational transitions; allosteric drugs act by shifting population from one state to another. The experimentally observable conformational ensemble — what cryo-EM sees — is therefore not a curiosity but a direct determinant of biological understanding and drug discovery success.

Cryo-EM has become the dominant method for high-resolution structural biology, with over 60,000 structures deposited in the EMDB. Yet three systematic mechanisms ensure that the conformational ensemble recovered by cryo-EM is incomplete:

**Vitrification trapping.** Plunge-freezing occurs in milliseconds, but conformational transitions with free-energy barriers >10 kJ/mol are not equilibrated within the cooling timescale. As demonstrated by Bock & Grubmüller (Nature Communications 2022, doi:10.1038/s41467-022-29332-2), the vitrified ensemble is systematically narrower than the physiological ensemble — higher-energy functional states are depopulated before the sample is frozen.

**Air-water interface adsorption.** Hydrophobic and charged surface patches drive preferential particle adsorption to the air-water interface during blotting. This creates severe orientation bias: certain particle views are overrepresented, others absent. Since different conformations present different surfaces, some conformational states are geometrically inaccessible to reconstruction (Liu et al., Nature Methods 2024, doi:10.1038/s41592-024-02505-1; Zhu et al., Science Advances 2024, doi:10.1126/sciadv.adn0092).

**The rare-state resolution floor.** Classical 3D classification and modern heterogeneity methods (3DVA, cryoDRGN, 3DFlex) require sufficient particle SNR per conformation to produce a meaningful reconstruction. Conformational states present at <2–5% population — perhaps a hundred particles in a typical dataset of ten thousand — fall below this floor and are treated as noise (Fan et al., Communications Biology 2024, doi:10.1038/s42003-024-06739-9).

The consequence is scientifically severe. Cryptic allosteric binding sites that open transiently; the pre-open state of a voltage-gated channel; the transition state of a kinase DFG-flip — these states are precisely what drug discovery most needs, and precisely what cryo-EM currently cannot see.

### 1.2 The Generative AI Gap

Generative models trained on molecular dynamics data offer a complementary view. BioEmu-1 (Noé et al., Science 2025, doi:10.1126/science.adv9817) generates equilibrium conformational ensembles from protein sequence with speed 10,000–100,000× faster than MD simulation, recovering domain motions (83%), local unfolding (70–82%), and cryptic pocket openings (55–88%) that are invisible in single-structure predictions. AlphaFold3 multi-conformation sampling and ESMFold-based approaches similarly explore the conformational landscape beyond the ground state.

However, these models are **unconditioned on experimental evidence**. They cannot accept a cryo-EM density map as input. They cannot distinguish which of their predicted states are populated in a specific biological context (e.g., membrane-embedded vs. solubilized protein; particular lipid composition; post-translational modification state). The BioEmu authors themselves identify "integrating multimodal experimental data, such as cryo-EM or single-molecule fluorescence" as a critical open challenge (Science 2025).

### 1.3 The Opportunity: Conditional Posterior Ensemble Determination

The fundamental opportunity is to combine what each approach does best: cryo-EM provides experimental evidence that anchors the ensemble to physical reality; generative AI provides a learned prior that covers the full thermodynamically accessible landscape including states the cryo-EM dataset was too sparse or biased to reconstruct independently.

This Bayesian framing — cryo-EM data as likelihood, generative ensemble as prior, posterior as the output — is the conceptual foundation of CryoEnsemble. Critically, it can recover low-population states: if BioEmu predicts a state that is present in the cryo-EM particle images at low frequency, the Bayesian posterior will assign it non-zero weight even when classical reconstruction would discard those particles as noise (Tang, Cossio et al., J. Phys. Chem. B 2023, doi:10.1021/acs.jpcb.3c01087; Hoff, Bonomi et al., PLOS Comp. Biol. 2024, doi:10.1371/journal.pcbi.1012180).

---

## 2. Limitations of Current Approaches

### 2.1 Heterogeneity Analysis Methods (cryoDRGN, 3DVA, 3DFlex, DynaMight)

All current cryo-EM heterogeneity analysis methods share a fundamental architectural limitation: they are **purely data-driven with no physical prior**. They can only reconstruct conformational states that are sufficiently represented in the particle dataset. They cannot extrapolate to physically plausible states absent from the data.

Specific documented failures:

| Method | Limitation |
|--------|-----------|
| **3DVA** (Punjani & Fleet, JSB 2021) | Linear PCA model; cannot represent nonlinear conformational manifolds; does not improve local resolution in flexible regions |
| **cryoDRGN** (Zhong et al., NM 2021) | Gaussian latent prior incompatible with multi-modal distributions; latent space density "bears no relation to the true underlying probability distribution" (Gilles & Singer, PNAS 2025, doi:10.1073/pnas.2419140122); conflates pose and conformation |
| **3DFlex** (Punjani & Fleet, NM 2023) | Assumes volume-preserving deformation fields; cannot model compositional heterogeneity; BETA status; requires >100 GB RAM for large datasets |
| **DynaMight** (Schwab et al., NM 2024) | Nonlinear VAE but still purely data-driven; computationally expensive; not suitable for strongly disordered proteins |
| **All methods** | Require sufficient particles per state; fail below ~2–5% population threshold |

The CryoBench evaluation (Jeon, Zhong et al., NeurIPS 2024, doi:10.48550/arXiv.2408.05526) — the first systematic benchmark with ground-truth conformational states from MD simulation — confirmed that all current methods, including cryoDRGN, fail to faithfully reconstruct the true conformational density present in the input data.

### 2.2 Generative Ensemble Models (BioEmu, AF2 Subsampling, ESMFold)

Generative models predict physically plausible conformational diversity but:

- Are **sequence-conditioned only** — no mechanism to incorporate experimental density evidence
- Cannot distinguish which states are populated in a specific experimental context (lipid composition, post-translational modifications, binding partners)
- Produce ensembles that may include thermodynamically accessible states that are **functionally absent** in the specific protein form of interest
- Cannot provide the per-state population fractions that quantify drug target accessibility

### 2.3 Hybrid Fitting and Reweighting Methods (MDFF, CryoFold, cryoENsemble, EMMIVox)

Existing hybrid approaches partially address the problem but have critical gaps:

- **MDFF variants** (including MDFF_NM, J. Chem. Inf. Model. 2024, doi:10.1021/acs.jcim.3c02007): treat the density map as a potential energy surface for fitting single structures or small ensembles; scale poorly to millions of conformations; require explicit MD integration at inference time
- **cryoENsemble** (Scientific Reports 2024, doi:10.1038/s41598-024-68468-7): Bayesian reweighting of MD-generated ensembles against 3D maps; operates on reconstructed maps, not raw particle images, losing per-particle signal; limited to ~10²–10³ conformers
- **EMMIVox** (PLOS Comp. Biol. 2024, doi:10.1371/journal.pcbi.1012180): Bayesian single-structure and ensemble refinement; requires explicit MD force field; computationally prohibitive for full equilibrium ensembles
- **CryoFold 2.0** (J. Phys. Chem. A 2023, doi:10.1021/acs.jpca.3c01731): MELD-based probabilistic restraints; requires running MD simulations at inference time; not practical for routine experimental use

**The critical gap none of these close**: no method jointly trains a generative ensemble model end-to-end against raw cryo-EM particle images, allowing the model to (1) be conditioned on experimental density evidence at the single-particle level, (2) maintain a physically calibrated conformational prior, and (3) recover low-population states by leveraging the generative prior to regularize sparse particle subsets.

---

## 3. Proposed Research: CryoEnsemble

### 3.1 Core Hypothesis

A conditional generative model trained to predict protein conformational ensembles can be made **experimental evidence-aware** by formulating inference as Bayesian posterior estimation over the per-particle cryo-EM image likelihood. The resulting posterior ensemble will (1) be anchored to experimental data, (2) be regularized by a physically learned prior, and (3) recover low-population states invisible to data-only methods.

### 3.2 System Architecture

CryoEnsemble operates as a two-module system:

```
INPUT
 ├─ Protein sequence (FASTA)
 └─ Cryo-EM particle stack + CTF parameters (particles.mrcs + ctf.pkl)

MODULE A: GENERATIVE PRIOR  (BioEmu-2 / DiG backbone)
  Sequence → conformational prior distribution P(x | sequence)
  Output: N conformers {x₁...xN} + latent manifold Z_prior

MODULE B: EXPERIMENTAL POSTERIOR  (CryoEnsemble posterior network)
  For each particle image y_i with CTF φ_i and estimated pose Ω_i:
    Compute image likelihood: L(y_i | x, φ_i, Ω_i) = p(y_i | proj(x, Ω_i), φ_i)
  
  Joint optimization:
    log P(x | Y) ∝ Σ_i log L(y_i | x, φ_i, Ω_i) + log P(x | sequence)
  
  Implemented as: VAE with learned amortized posterior q(z | Y, sequence)
    trained end-to-end with ELBO objective
  
OUTPUT
 ├─ Posterior ensemble {x̃₁...x̃M} — states consistent with BOTH data and prior
 ├─ Per-state population weights w_i (calibrated free-energy differences)
 ├─ Per-state pocket detection map (fpocket / PocketMiner)
 └─ Comparison: prior ensemble vs. posterior ensemble (gap analysis)
```

### 3.3 Key Technical Innovations

**Innovation 1: Per-particle image likelihood conditioning (not map-level)**

Existing hybrid methods (cryoENsemble, EMMIVox) condition on 3D reconstructed maps, which are average representations that discard per-particle conformational signal. CryoEnsemble conditions on the full particle image set Y = {y₁,...,y_N} through an amortized inference network, preserving single-particle information and enabling recovery of low-population states even when their individual maps cannot be reconstructed.

**Innovation 2: Score-based latent prior with physical calibration**

The Gaussian latent prior in cryoDRGN produces uncalibrated latent densities (Gilles & Singer, PNAS 2025). CryoEnsemble replaces it with a score-based diffusion prior trained on BioEmu's MD-derived ensemble data, providing a physically calibrated probability density over conformational space that corresponds to a Boltzmann-weighted equilibrium distribution. This is conceptually related to the latent diffusion extension proposed by Kreis & Dockhorn (arXiv:2211.14169, 2022) but trained with experimental MD-derived ground truth rather than a parametric Gaussian.

**Innovation 3: Pose-conformation disentanglement**

cryoDRGN's known failure to disentangle pose and conformation (Edelberg & Lederman 2023) is addressed by separating the conformational latent variable from the orientation estimation pathway — building on the architectural advances in cryoDRGN-AI (Zhong et al., Nature Methods 2025, doi:10.1038/s41592-025-02720-4) while adding the experimental posterior conditioning module.

**Innovation 4: BioMate deployment for accessibility**

CryoEnsemble will be deployed as a BioMate workflow, making the method accessible to any structural biologist without GPU infrastructure or deep learning expertise. Input: particle stack + sequence. Output: interactive conformational ensemble explorer, pocket landscape, and free-energy profile.

### 3.4 Research Objectives

| Objective | Description | Timeline |
|-----------|-------------|----------|
| **Obj. 1** | Develop and validate CryoEnsemble posterior network architecture | Year 1 |
| **Obj. 2** | Benchmark against cryoDRGN, 3DVA, 3DFlex, cryoENsemble using CryoBench synthetic datasets with MD ground truth | Year 1–2 |
| **Obj. 3** | Apply to 10 experimental cryo-EM datasets spanning distinct protein classes (GPCRs, ion channels, kinases, chaperones) | Year 2 |
| **Obj. 4** | Validate recovered low-population states against independent experimental evidence (HDX-MS, FRET, biochemical assays) | Year 2–3 |
| **Obj. 5** | Deploy CryoEnsemble on BioMate platform; process 100+ public EMDB datasets; establish conformational completeness benchmark | Year 3 |
| **Obj. 6** | Demonstrate drug discovery application: cryptic pocket identification in 3 disease-relevant targets | Year 3 |

---

## 4. Methods

### 4.1 Training Data

**Ensemble prior training:**
- BioEmu's released training data (MD simulations, ~200 ms aggregate, ~1,100 CATH domains)
- Supplemented with publicly available MD trajectories from MoDEL, GPCRmd, and MDAnalysis community datasets
- Target: ~500 diverse protein families with full equilibrium ensemble coverage

**Cryo-EM particle image training:**
- EMPIAR (Electron Microscopy Public Image Archive): >500 publicly deposited raw particle datasets
- Focus on well-characterized proteins with multi-state heterogeneity: TRPV1, β₂-adrenergic receptor (with and without Gα), HIV-1 reverse transcriptase, GroEL, spliceosome datasets
- CryoBench synthetic datasets (Jeon et al., NeurIPS 2024) for benchmarking where MD ground truth is available

### 4.2 Architecture Details

The CryoEnsemble posterior network is a transformer-based architecture with three coupled modules:

**Sequence encoder:** ESM-2 protein language model (3B parameters) for rich sequence representations, as in BioEmu.

**Particle image encoder:** Convolutional encoder operating on 2D particle images after CTF correction and normalization. Encodes each image y_i into a per-particle embedding e_i ∈ ℝ^256.

**Conformational posterior:**
- Aggregates {e_i} via attention over the full particle set
- Conditions the diffusion process on the aggregated experimental signal
- Outputs: per-particle conformational soft-assignments + posterior ensemble samples x̃_k ~ q(x | Y, sequence)

**Training objective:**
```
ELBO = E_q[log p(Y | x, Ω)] - KL(q(z|Y,seq) || p_diffusion(z|seq))
```
where p_diffusion is the BioEmu-derived score-based prior.

### 4.3 Experimental Validation Plan (Sister's Laboratory)

The experimental component, led by [Sister's name], will provide ground-truth validation using three complementary techniques:

**HDX-MS (Hydrogen-Deuterium Exchange Mass Spectrometry):** Measures backbone amide exchange rates as a proxy for conformational flexibility and solvent exposure. Regions of high exchange correspond to conformations predicted to sample disordered or open states in the CryoEnsemble posterior. This provides residue-level validation of the recovered ensemble without requiring atomic structures of rare states.

**Single-molecule FRET (smFRET):** For proteins with defined distance-reporting conformational changes (e.g., kinase open/closed, GPCR active/inactive), smFRET provides direct population fractions of distinct states in solution. CryoEnsemble's predicted population weights w_i will be validated against smFRET-derived state populations.

**Cryo-EM sample preparation optimization:** Systematic comparison of grid preparation conditions (detergent concentrations, buffer pH, temperature, addition of crosslinkers) to experimentally reduce the air-water interface adsorption bias, creating paired datasets with high and low conformational sampling bias for controlled validation of CryoEnsemble's bias correction.

### 4.4 BioMate Platform Integration

BioMate (biomate.ai) provides the computational infrastructure for deploying CryoEnsemble at scale:

- **Cryo-EM heterogeneity pipeline** (workflow 12885, already deployed on AWS Batch): cryoDRGN training and analysis, pocket scan ensemble, heterogeneity report — provides the base reconstruction layer that CryoEnsemble extends
- **Protein dynamics pipeline** (workflow 12886): BioEmu ensemble generation, conformational UMAP, fpocket pocket scan — provides the generative prior layer
- **Knowledge DB**: 181 RAG chunks, 7 cryo-EM sample class protocols, 22 tool entries — provides context-aware parameter guidance to users
- **AWS Batch infrastructure**: GPU execution on `galaxy-cloud-queue-gpu`; Nextflow orchestration
- Target: CryoEnsemble deployed as workflow 12887, callable from BioMate chat interface

---

## 5. Expected Outcomes and Impact

### 5.1 Scientific Outcomes

1. **CryoEnsemble method**: A validated computational framework for posterior conformational ensemble determination from cryo-EM data, with open-source code and pre-trained weights.

2. **Conformational completeness benchmark**: The first systematic comparison of cryo-EM-recovered conformational landscapes against MD ground truth for >100 EMDB datasets, establishing a public leaderboard.

3. **Recovered rare states**: Experimentally validated low-population (<5%) conformational states for at least 5 proteins, with structural characterization of cryptic binding sites and functional annotation.

4. **Population-weighted free-energy estimates**: Posterior ensemble population fractions validated against smFRET and HDX-MS for 5 protein systems, demonstrating calibrated thermodynamic predictions.

### 5.2 Drug Discovery Impact

CryoEnsemble directly addresses the cryptic binding site problem in drug discovery. Approximately 70% of human disease-relevant proteins are currently considered "undruggable" because their ground-state structures lack accessible ligand-binding pockets. Many of these proteins are believed to sample druggable conformations transiently. CryoEnsemble, by recovering low-population states from existing cryo-EM datasets, could unlock these cryptic pockets without requiring new experimental infrastructure or additional data collection.

Three disease-relevant targets will be prioritized for demonstration:
- A G-protein-coupled receptor in an underexplored allosteric state
- A protein-protein interaction interface relevant to oncology
- A kinase DFG-out conformation absent from available crystal structures

### 5.3 Platform Impact via BioMate

Deployment on BioMate means the method becomes accessible to structural biology laboratories globally without GPU expertise. Conservative estimate: 200+ research groups could apply CryoEnsemble to existing EMPIAR datasets in Year 3, producing conformational completeness assessments for well-studied targets (ribosome, proteasome, GPCR family) without any new data collection.

---

## 6. Timeline

| Quarter | Milestone |
|---------|-----------|
| Y1 Q1–Q2 | Architecture design; training data curation; baseline benchmarks on CryoBench |
| Y1 Q3–Q4 | CryoEnsemble v1.0 training; comparison against cryoDRGN / cryoENsemble; first publication submission |
| Y2 Q1–Q2 | Experimental validation begins (HDX-MS, smFRET); 10 EMDB dataset applications |
| Y2 Q3–Q4 | Low-population state recovery demonstrated; pose-conformation disentanglement ablation |
| Y3 Q1–Q2 | BioMate workflow deployment; 100 EMDB dataset processing; conformational completeness benchmark released |
| Y3 Q3–Q4 | Drug discovery application (3 targets); CryoEnsemble v2.0; final publication; open-source release |

---

## 7. Team and Collaboration

### Principal Investigators

**[Sister's name], Ph.D., [Institution]**
Role: Experimental lead; cryo-EM data collection and optimization; HDX-MS and smFRET validation; biological target selection.
Expertise: Single-particle cryo-EM, membrane protein biochemistry, conformational dynamics.

**Yaoyun Zhang, BioMate AI Platform**
Role: Computational lead; CryoEnsemble model architecture and training; BioMate deployment; infrastructure.
Expertise: AI systems, generative models, Nextflow bioinformatics pipelines, AWS cloud infrastructure, structural bioinformatics knowledge systems.

### Collaboration Rationale

This project requires an unusually tight coupling between experimental structural biology and deep generative modeling. The experimental partner provides:
- Access to controlled cryo-EM datasets with paired biochemical validation
- Domain expertise to select biologically meaningful protein targets
- Ground-truth validation through HDX-MS and smFRET

The computational partner provides:
- Pre-built cryoDRGN and BioEmu pipelines (workflows 12885, 12886) already running on AWS Batch
- BioMate deployment platform with GPU-accelerated Nextflow execution
- Structural bioinformatics knowledge DB with curated cryo-EM protocols and tool parameters
- End-to-end AI infrastructure to go from research prototype to accessible tool

### Advisory Expertise (to be recruited)
- Expert in Bayesian inference for structural biology (e.g., contributors to EMMIVox or cryoENsemble)
- Expert in score-based generative models (diffusion model architecture)

---

## 8. Potential Risks and Mitigations

### Risk 1: Pose estimation accuracy limits posterior quality

**Description:** CryoEnsemble conditions on per-particle image likelihoods, which require accurate particle orientations. For highly flexible proteins where the consensus reconstruction is poor, pose estimates may be systematically wrong, corrupting the posterior.

**Likelihood:** Medium — affects ~20% of challenging targets (IDPs, strongly flexible assemblies).

**Mitigation:**
- Implement iterative pose refinement within the CryoEnsemble inference loop (building on cryoDRGN-AI's joint pose-conformation refinement, Nature Methods 2025)
- Evaluate pose uncertainty — particles with high orientation entropy (ambiguous poses) are down-weighted in the likelihood term
- Fallback: for targets with poor consensus maps, use the generative prior ensemble alone (BioEmu) as a starting point and apply cryo-EM density as a soft constraint rather than a hard likelihood

### Risk 2: BioEmu prior is too biased toward training distribution

**Description:** BioEmu was trained on ~1,100 CATH domain proteins from AFDB. Proteins far outside this distribution (novel folds, heavily modified proteins, very large multi-domain proteins) may produce poor priors that misguide the posterior.

**Likelihood:** Medium-low — affects targets with unusual folds or >500 residues.

**Mitigation:**
- Monitor prior quality via latent space divergence metrics during training
- For out-of-distribution proteins, weight the prior term down (temperature scaling of the KL term in the ELBO) and rely more heavily on the cryo-EM particle image likelihood
- Expand training data with GPCRmd and MDAnalysis community MD trajectories to improve coverage of membrane protein folds — the most common cryo-EM target class

### Risk 3: Scalability — training on full particle sets is computationally prohibitive

**Description:** Encoding all N particles (typically 50,000–2,000,000) for amortized posterior estimation requires O(N) forward passes per training step. At N = 500,000 this is computationally expensive.

**Likelihood:** High — this is a known challenge in heterogeneity methods.

**Mitigation:**
- Mini-batch particle sampling during training (standard in cryoDRGN; applicable here)
- Pre-compute and cache particle image embeddings after the first encoder pass
- Hierarchical aggregation: summarize particles into conformation-space clusters using a fast k-means pass before full posterior inference
- If necessary, implement streaming training with gradient checkpointing to reduce peak memory

### Risk 4: Validation gap — no ground-truth conformational ensemble for real proteins

**Description:** For real experimental protein targets, there is no gold-standard ensemble to validate against. CryoBench provides synthetic benchmarks but these may not capture the full complexity of experimental noise.

**Likelihood:** High — this is the fundamental limitation of the field.

**Mitigation:**
- Use CryoBench as the primary quantitative benchmark during development
- For experimental proteins, use three indirect validation strategies: (a) HDX-MS correlation for residue-level flexibility, (b) smFRET population fractions for distance reporters, (c) cross-validation using held-out particle images not seen during training
- Additionally: demonstrate that CryoEnsemble-predicted pocket populations are statistically correlated with competitive binding assay IC₅₀ values for known cryptic-site ligands

### Risk 5: Computational cost limits BioMate deployment accessibility

**Description:** CryoEnsemble inference for a large cryo-EM dataset (500K particles, 300-residue protein) may require 24–72 GPU-hours, making routine use expensive.

**Likelihood:** Medium.

**Mitigation:**
- Develop a fast "CryoEnsemble-Lite" mode that operates on a random subsample of 10,000 particles to produce a draft ensemble in <2 GPU-hours
- Implement AWS Spot Instance optimization in BioMate to reduce per-run cost by ~70%
- Cache results: for public EMDB datasets, precompute and store the posterior ensemble permanently, making repeated queries free

### Risk 6: Google.org institutional eligibility

**Description:** Google.org Impact Challenge requires a nonprofit or academic institution. If the BioMate entity is commercial, it may be ineligible as the lead applicant.

**Likelihood:** Medium — depends on institutional structure.

**Mitigation:**
- Submit with [Sister's university] as the lead institution and fiscal agent; BioMate contributes as a technology partner / subcontractor
- Alternatively: apply to Google DeepMind AI4Science research partnerships (separate program with different eligibility criteria)
- Backup: NIH R01 mechanism with AI-assisted structural biology scope (PA-24-056), or Chan Zuckerberg Initiative Science program, both open to this problem domain

---

## 9. Budget Justification (3-Year, $2.8M)

| Category | Year 1 | Year 2 | Year 3 | Total |
|----------|--------|--------|--------|-------|
| Personnel — computational (2 FTE, includes PI time) | $320K | $330K | $340K | $990K |
| Personnel — experimental (1.5 FTE postdoc + 0.5 FTE technician) | $210K | $220K | $230K | $660K |
| GPU compute (AWS A100 instances, training + inference) | $250K | $200K | $150K | $600K |
| Experimental materials (HDX-MS, smFRET reagents, grid prep) | $80K | $100K | $80K | $260K |
| Subcontract — advisory expertise (Bayesian inference / diffusion models) | $60K | $40K | $20K | $120K |
| Travel, conference dissemination | $20K | $25K | $25K | $70K |
| Indirect costs (negotiated rate) | — | — | — | $100K |
| **Total** | **$940K** | **$915K** | **$845K** | **$2,800K** |

---

## 10. Alignment with Google.org AI4Science Criteria

| Criterion | How CryoEnsemble Addresses It |
|-----------|-------------------------------|
| **AI as core solution** | The posterior network, score-based prior, and per-particle image encoder are novel AI contributions; AI is not ancillary but the scientific mechanism |
| **Quantifiable impact metrics** | State recovery rate vs. CryoBench ground truth; smFRET population fraction correlation; cryptic pocket prediction recall; number of EMDB datasets processed |
| **Scaled impact** | BioMate deployment enables 200+ research groups globally to apply the method without infrastructure investment; public EMDB processing creates a lasting resource |
| **Responsible AI** | Open-source code, pre-trained weights under permissive license; no patient data; uncertainty quantification built into the posterior framework |
| **Scientific ambition** | Addresses a long-standing fundamental limitation of the most widely used structural biology technique; bridges generative AI and experimental physical science |
| **Demonstrated expertise** | Pre-built cryoDRGN + BioEmu pipelines running on AWS Batch; cryo-EM knowledge DB with 181 verified RAG chunks; BioMate platform with 2,457 bioinformatics workflows |

---

## 11. Pilot Study (Pre-Submission Validation)

To strengthen this proposal, a 6-week pilot study is proposed using existing BioMate infrastructure and publicly available data. See companion document: `docs/20260427_PILOT_STUDY_CRYO_ENSEMBLE.md`.

Pilot targets: β₂-adrenergic receptor (EMPIAR-10258, 127,000 particles) and TRPV1 (EMPIAR-10059, 35,645 particles). These have both high-quality cryo-EM data and extensive MD simulation benchmarks in the literature.

---

## References (Selected; All DOIs Verified)

1. Bock LV, Grubmüller H. Effects of cryo-EM cooling on structural ensembles. *Nat Commun* 2022; 10.1038/s41467-022-29332-2
2. Liu Y-T et al. Overcoming the preferred-orientation problem with self-supervised deep learning. *Nat Methods* 2024; 10.1038/s41592-024-02505-1
3. Zhu D et al. Correction of preferred orientation-induced distortion in cryo-EM maps. *Sci Adv* 2024; 10.1126/sciadv.adn0092
4. Jeon M, Zhong ED et al. CryoBench: Diverse and challenging datasets for the heterogeneity problem in cryo-EM. *NeurIPS* 2024; 10.48550/arXiv.2408.05526
5. Gilles MA, Singer A. Cryo-EM heterogeneity analysis using regularized covariance estimation and kernel regression. *PNAS* 2025; 10.1073/pnas.2419140122
6. Zhong ED et al. CryoDRGN: reconstruction of heterogeneous cryo-EM structures using neural networks. *Nat Methods* 2021; 10.1038/s41592-020-01049-4
7. Zhong ED et al. CryoDRGN-AI: neural ab initio reconstruction of challenging cryo-EM and cryo-ET datasets. *Nat Methods* 2025; 10.1038/s41592-025-02720-4
8. Fan X et al. CryoTRANS: predicting high-resolution maps of rare conformations. *Commun Biol* 2024; 10.1038/s42003-024-06739-9
9. Tang WS, Cossio P et al. Ensemble Reweighting Using Cryo-EM Particle Images. *J Phys Chem B* 2023; 10.1021/acs.jpcb.3c01087
10. Hoff SE, Bonomi M et al. Accurate model and ensemble refinement using cryo-EM maps and Bayesian inference. *PLOS Comp Biol* 2024; 10.1371/journal.pcbi.1012180
11. Schwab J et al. DynaMight: estimating molecular motions with improved reconstruction from cryo-EM images. *Nat Methods* 2024; 10.1038/s41592-024-02377-5
12. Punjani A, Fleet DJ. 3DFlex: determining structure and motion of flexible proteins from cryo-EM. *Nat Methods* 2023; 10.1038/s41592-023-01853-8
13. Noé F et al. Scalable emulation of protein equilibrium ensembles with generative deep learning. *Science* 2025; 10.1126/science.adv9817
14. Wang X et al. DiffModeler: large macromolecular structure modeling for cryo-EM maps using a diffusion model. *Nat Methods* 2024; 10.1038/s41592-024-02479-0
15. Shugaeva T, Lindahl E et al. Modeling cryo-EM structures in alternative states with AF2-based models and density-guided simulations. *Commun Chem* 2025; 10.1038/s42004-025-01751-4
16. Beton J et al. Integrating model simulation tools and cryo-electron microscopy. *WIREs Comput Mol Sci* 2023; 10.1002/wcms.1642

---

*Proposal prepared: 2026-04-27. Program: Google.org Impact Challenge AI for Science (deadline May 1, 2026).*
