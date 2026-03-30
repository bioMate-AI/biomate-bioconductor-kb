# BioMate for Cryo-EM and Structural Biology
### A Platform Overview for Research Collaboration

---

## What BioMate Does

BioMate is an AI-native research platform that turns a plain-language description of an experiment into a fully configured, automatically quality-checked computational pipeline — and runs it. The scientist describes what they want to do; BioMate builds the workflow, checks whether the results meet scientific standards at each step, flags problems in real time with an explanation and a suggested fix, and records every decision in an audit trail.

For structural biology, this means: describe your dataset — the microscope, voltage, pixel size, what the sample is, and what you are trying to learn — and BioMate configures the full processing pipeline from raw movie stacks to sharpened reconstruction. It monitors data quality automatically at every stage: motion correction, CTF estimation, particle picking, 2D classification, 3D refinement, and final model validation. When something goes wrong — preferential orientation, too many junk classes, a CTF fit that dropped below acceptable quality — the platform tells you what happened, what it means for resolution, and what to try next.

The platform also integrates structure prediction (AlphaFold3) and molecular docking directly into the same environment, so structural biologists working in drug discovery or chemical biology can move from a solved map to a docked compound without changing platforms.

---

## Capabilities by Project Stage

### Stage 1 — Data Collection Quality Assessment

- **Movie stack import** — file integrity check, format detection (MRC, TIFF, EER), and early rejection of corrupted acquisitions before any GPU compute is consumed
- **Pre-screening run** — rapid pass through the first micrographs to assess CTF quality and motion before committing the full dataset to processing
- **Volta Phase Plate (VPP) detection** — automatic recognition of phase plate datasets from acquisition metadata; switches CTF estimation and QC thresholds to the appropriate phase contrast mode
- **Per-session statistics** — motion drift distribution, CTF fit quality histogram, and acceptance rate summary across all micrographs in a collection session

### Stage 2 — Preprocessing

- **Motion correction** — GPU-accelerated patch-based motion correction with dose weighting; total drift and per-frame drift both monitored with automatic micrograph rejection if motion exceeds accepted limits
- **CTF estimation** — CTFFIND4-based CTF parameter estimation (defocus, astigmatism, phase shift); Thon ring fit quality monitored per micrograph; micrographs failing CTF quality automatically excluded
- **Ice thickness assessment** — fraction of thick-ice micrographs estimated from CTF diagnostics; flagged before picking
- **Micrograph curation** — automated selection of micrographs passing both motion and CTF thresholds; rejection audit log records the reason for each excluded micrograph

### Stage 3 — Particle Analysis

- **Particle picking** — two-round strategy: blob-based picking in round 1 to generate a clean reference set; template-based picking in round 2 using 2D class average templates for higher sensitivity; junk particle detection between rounds
- **Particle extraction** — configurable box size; generates particle stacks for classification
- **2D classification — two rounds** — 2D classification on round 1 and round 2 particle sets; junk fraction monitored automatically; runs halted and flagged if junk class content exceeds safe levels; automated class selection based on quality scores

### Stage 4 — 3D Reconstruction

- **Ab initio volume generation** — stochastic gradient descent 3D volume initialisation; supports 1 to 4 simultaneous classes for heterogeneous samples
- **Homogeneous refinement** — gold-standard FSC-regularised single-class refinement; orientation anisotropy (preferred orientation) detected automatically; hard stop if the anisotropy ratio exceeds the accepted community limit
- **Heterogeneous refinement** — multi-class 3D classification for conformationally variable samples; class population fractions and per-class FSC reported
- **Validation FSC** — independent half-map FSC for resolution reporting
- **Local CTF refinement** — per-particle CTF parameter refinement and beam tilt estimation to push toward high resolution
- **Non-uniform refinement** — adaptive regularisation for improved map quality in flexible or disordered regions
- **Local resolution estimation** — per-voxel resolution estimation; large spread across the map flagged as advisory

### Stage 5 — Post-Processing and Map Quality

- **Map sharpening** — B-factor sharpening with advisory gates on over-sharpening (B-factor > 0 Å²) and over-blurring (B-factor < −300 Å²)

### Stage 6 — Atomic Model Quality

- **AlphaFold3 structure prediction** — predict an atomic model from sequence to use as a fitting template; supports proteins, nucleic acids, and multi-chain complexes; outputs per-residue confidence (pLDDT), predicted aligned error (PAE), and a CIF file ready for real-space refinement
- **Real-space model refinement** — Phenix real_space_refine for fitting the predicted or deposited model into the EM map
- **MolProbity stereochemistry validation** — Ramachandran outlier fraction, rotamer outlier fraction, and all-atom clashscore; all three metrics reported with automatic flagging
- **EMRinger map-model cross-validation** — side-chain dihedral peak correlation against local electron density; independent check on model accuracy orthogonal to MolProbity

### Stage 6 — Advanced Single-Particle Workflows

These workflows go beyond the standard linear SPA pipeline and are invoked when the dataset or scientific question requires it. Each is an independent Nextflow module that can be chained onto any prior stage.

- **Particle subtraction** — removes signal outside a 3D mask from all particle images, leaving only the region of interest (e.g., one lobe of a multi-domain complex, one subunit of a homo-oligomer). Essential when preferred orientation, conformational heterogeneity, or micelle signal prevents a specific domain from refining cleanly in the global reconstruction. Combined with local refinement as the *focused refinement pipeline*.
- **Local (focused) refinement** — refines the alignment of subtracted particles against a focused map, typically pushing resolution 0.5–2 Å better than the global refinement for the sub-region of interest. Used for large, flexible, or asymmetric complexes where global alignment is dominated by one domain.
- **3D Variability Analysis (3DVA)** — CryoSPARC's principal-component decomposition of conformational heterogeneity. Decomposes the particle set into continuous variability modes (eigenvectors of the conformational space) rather than discrete classes. Used to visualise breathing motions, domain rotations, and ligand-induced conformational changes. Output: per-particle latent coordinates + variability component maps for movie generation.
- **3D Variability Display** — clusters the 3DVA latent space into discrete conformational snapshots (default: 20 frames) and generates a conformational trajectory for visualisation. The standard follow-on to 3DVA when a movie or discrete state separation is needed.
- **Symmetry expansion** — expands a particle set by all symmetry operators of the assembly (C4 → 4× particles; O → 24× particles), placing each copy in the asymmetric unit. Used to break the symmetry constraint and focus on one protomer, one active site, or a symmetry-broken ligand binding event. Standard workflow before asymmetric local refinement of a symmetric assembly.
- **Global CTF refinement** — estimates and corrects global optical aberrations (beam tilt, anisotropic magnification, trefoil) from the full particle population after a high-resolution refinement. These aberrations accumulate across a session and are not corrected by per-particle CTF refinement. Typically applied as the final CTF correction step before sharpening in near-atomic resolution projects.
- **Helical SPA pipeline** — complete 11-step pipeline for filamentous specimens: motion correction → CTF estimation → filament tracing → particle extraction → 2D classification → helical refinement. Applies helical symmetry (rise + twist) during reconstruction. Supports microtubules, actin filaments, amyloid fibres (α-synuclein, tau), and intermediate filaments. CryoSPARC refines the helical parameters (rise and twist) iteratively.
- **Filament tracer** — picks filamentous particles along traced filament axes, applying a configurable overlap fraction and minimum filament length threshold. Generates coordinate sets for extraction in helical box sizes.
- **Topaz train** — trains a custom ResNet neural network picker on your own micrographs using positive examples from a prior picking round. Produces a dataset-specific model with substantially higher sensitivity and lower false-positive rate than a generic blob picker. Used when the particle is small (< 100 kDa), low-contrast, or has an unusual shape.
- **Topaz extract** — applies a trained Topaz model to the full micrograph set, with a configurable log-likelihood threshold. Used as the picking step when a custom-trained model is available.
- **Import micrographs** — starts a processing project from pre-corrected micrographs (MRC/TIFF) rather than raw movies. Used when motion correction was already performed externally (CryoSPARC Live on-the-fly, MotionCor2 standalone, or a collaborator-provided dataset).
- **Import particles** — imports an existing particle stack from RELION (STAR format) or CryoSPARC (.cs format) directly into the BioMate pipeline. Used to resume processing from a collaborator's dataset, or to apply BioMate's QC governance and downstream modules to particles already picked and extracted elsewhere.

### Stage 7 — Cryo-Electron Tomography

- **Tilt series import** — MDOC metadata parsing; per-tilt dose, stage position, and defocus target extracted automatically
- **Tilt alignment** — AreTomo2 (GPU-accelerated, fiducial-less, default) and IMOD (gold fiducial, classic reference); alignment residual statistics reported
- **Tomogram reconstruction** — weighted back-projection (WBP) and SIRT; all tilt series in the dataset are reconstructed simultaneously (approximately 4× the throughput of IMOD serial processing)
- **Subtomogram averaging (STA)** — RELION 4 STA pipeline; template matching for picking, iterative alignment and averaging, gold-standard FSC per STA round

### Stage 8 — Structure-Based Drug Design

For structural biologists whose work feeds into a drug discovery programme:

- **Molecular docking** — DiffDock (diffusion-based blind docking; no grid box required; generates a pose ensemble ranked by confidence) and AutoDock Vina (grid-based, classical reference method); both run on the same compound list with a comparison report
- **Virtual screening pre-filter** — DrugCLIP contrastive learning scoring ranks large compound libraries against a target structure approximately 10 million times faster than Vina; used to shortlist compounds before full docking
- **Compound structure validation** — SMILES validity and chemical standardisation enforced before any docking compute runs; invalid structures blocked outright, salts stripped and logged

---

## QC Governance — What Makes BioMate Different

Every pipeline step is monitored against evidence-based quality thresholds. When a step produces results below threshold, the scientist sees:

1. The exact metric that failed and by how much
2. A plain-language explanation of what the failure means for data quality and resolution
3. Domain-specific troubleshooting guidance — for example, for a preferred orientation failure: which sample preparation strategies (detergent titration, tilted data collection, cryo-additive screening) address the root cause and why
4. The choice to apply AI-suggested corrections and re-run, or to override and proceed with a recorded justification

Three severity tiers are applied:
- **Blocking** — the result is not scientifically valid; the workflow pauses for a decision
- **Advisory** — the result is acceptable but warrants attention; the workflow continues with a flagged warning
- **Near-threshold** — the metric is within 10% of a threshold; an early warning before it becomes a problem

**Examples of automatic gates that fire without any configuration:**
- Motion correction: total drift > 50 Å → micrograph rejected; per-frame drift > 3 Å/frame → advisory
- CTF estimation: Thon ring fit quality < 0.7 → micrograph rejected; astigmatism > 1000 Å → advisory
- Phase plate: phase shift < 0.2 rad (plate depleted) or > 1.5 rad (over-charged) → advisory
- 2D classification: > 70% of classes are junk → run halted; 50–70% junk → advisory
- Refinement: orientation anisotropy ratio > 10× → run halted (preferred orientation problem); 5–10× → advisory
- Sharpening: B-factor outside −300 to 0 Å² → advisory; local resolution spread σ > 3.0 Å → advisory
- MolProbity: Ramachandran outliers > 2%, rotamer outliers > 5%, clashscore > 20 → advisory
- EMRinger score < 1.0 → advisory

All decisions — including overrides — are written to an audit log that travels with the result.

**Named QC profiles** adapt the threshold set to the experimental context without bypassing governance. Current cryo-EM profiles:

- `cryoem_spa_standard` — standard SPA of soluble, purified complexes; all default thresholds
- `cryoem_spa_lowdose` — low-dose acquisitions (< 40 e⁻/Å²) or EMPIAR benchmark mode; CTF and motion thresholds relaxed for the intentionally low-SNR conditions
- `cryoem_spa_phase_plate` — Volta Phase Plate datasets; CTF fit quality threshold relaxed to 0.65; phase shift gate activated
- `cryoem_spa_membrane` — membrane proteins in detergent micelles or nanodiscs; motion and CTF thresholds adjusted for lower inherent signal-to-noise

---

## Research Intelligence — Hypothesis, Protocol, and Literature

Before running a single analysis, BioMate can help think through the experiment. The platform's research agent is available throughout the conversation — not just at the workflow generation step.

**Literature-backed answers to scientific questions.** Ask anything: "Which particle picker performs best on membrane proteins with preferred orientation?", "What CTF estimation method is most reliable below 2 Å resolution?", "What resolution is typically achievable for a 150 kDa soluble complex on a 200 kV instrument?", "What are the known failure modes of DiffDock for covalent binders?" The research agent searches PubMed in real time and returns a synthesised answer with citations. Responses include a confidence indicator and follow-up questions for deeper exploration.

**Hypothesis generation for structural biology questions.** Describe a processing result — "my 2D classes look blurry but my CTF quality scores are fine" or "I'm stuck at 4.5 Å despite 300,000 particles" — and ask what hypotheses it suggests. The agent proposes testable explanations (sample flexibility, preferred orientation, ice quality, heterogeneity masked by single-class refinement), identifies which hypothesis is most consistent with the observed QC metrics, and recommends which BioMate workflow would test it next.

**Protocol and methodology guidance.** Ask how to solve a preparation or collection problem — sample concentration for cryo-EM grids, detergent type and concentration for membrane proteins, optimal tilt range for a tomography session — and the agent returns step-by-step guidance drawn from published methods and benchmark comparisons.

**Scientific rationale embedded in every workflow.** When BioMate generates or recommends a workflow, the response includes a structured rationale panel:
- *When to use this workflow* — the sample types and scientific questions it is designed for
- *When not to use it* — limitations; for example, when a sample is too small or too flexible for SPA and cryo-ET would be more appropriate
- *Data requirements* — microscope type, voltage, pixel size range, expected particle density, minimum micrograph count
- *Key assumptions* — what the analysis implicitly assumes about sample homogeneity
- *Common pitfalls* — documented failure modes with root cause and fix
- *Parameter recommendations* — specific values with scientific justification for the sample class

---

## AI Assistance

- Describe any structural biology analysis in plain English and the platform generates the full pipeline, drawing on over 950 indexed workflows across structural biology, genomics, proteomics, drug discovery, and microbiology
- The AI explains which tools it selected and why — for example, why two-round template picking is recommended, or why non-uniform refinement is offered after homogeneous refinement plateaus
- Clarifying questions are offered non-blocking — the pipeline starts while the dialogue continues
- A pilot run feature automatically tests preprocessing parameters on a small subset of micrographs before committing the full dataset

---

## Results, Visualisation, and Download

After a workflow completes, BioMate organises outputs by scientific content type — maps, models, plots, particle stacks, quality reports, and data tables — each shown with a count badge so the scientist can navigate directly to what matters.

**In-browser viewers — no downloads required for inspection.**

- *Image and plot viewer* — CTF power spectra, 2D class average grids, FSC curves, orientation distribution plots, and local resolution heat maps render directly in the browser; zoom, pan, and export to PNG or SVG
- *Data table viewer* — per-micrograph QC tables, per-particle statistics, MolProbity residue-level outputs, and docking score rankings open in a sortable, filterable grid
- *Structure viewer* — atomic models (PDB/CIF) rendered in an interactive 3D molecular viewer with surface, ribbon, and stick representations; colour by chain, B-factor, or pLDDT (for AlphaFold3 models); overlay multiple models for comparison
- *Density map viewer* — MRC density maps displayed as orthogonal slices (XY/XZ/YZ) with adjustable Z position; contour level control; fitted model overlay
- *Sequence viewer* — protein sequences (FASTA) with amino acid colouring, for AlphaFold3 input review

**Download options.**

- Individual files download in their native format (MRC maps, PDB/CIF models, STAR files, CSV tables)
- *Download All* creates a ZIP archive of every workflow output
- Citation export produces a BibTeX file from every tool reference embedded in the workflow report — ready for a manuscript methods section or EMDB deposition

**Auto-generated processing report.** After any workflow, a report button produces a structured document covering the pipeline name and parameters, methods (tool names, versions, and settings actually used), QC results (which checks passed, which triggered warnings, any override decisions and justifications), and output file descriptions. Available as Markdown for editing or HTML for sharing.

**Interactive post-run environment.** A Jupyter notebook session can be launched directly from a completed workflow, with all output files pre-loaded into the kernel, for custom analysis, additional plots, or statistical tests.

---

## Compute

Runs on a local GPU workstation (minimum 24 GB VRAM for CryoSPARC-based SPA), a university HPC cluster with a GPU partition (SLURM), or AWS GPU instances. Singularity is supported for institutions where Docker is not permitted on the cluster. CryoSPARC itself runs on-premise; the licence is free for academic use. The scientist selects the compute environment once in settings; all subsequent runs use it without further configuration.

---

## Roadmap (Next 6–12 Months)

| Capability | Status |
|---|---|
| On-the-fly preprocessing — QC feedback while data collection is still running | In development |
| Continuous heterogeneity analysis (cryoDRGN integration) | In development |
| Automated EMDB/PDB deposition wizard — pre-filled metadata from processing report | Planned |
| Interactive model building (Coot session launch from completed map) | Planned |
| AlphaFold3 local server deployment (for institutions with data privacy requirements) | Planned |
| EMPIAR public dataset browser — search, download, and benchmark against published resolutions | Planned |
| Facility multi-user project management — shared queue, per-group storage quotas, job priority | Planned |
| In-situ cryo-ET + proteomics integration — link subtomogram averages to proteomics identifications from the same lamella | Planned |

---

## What We Would Like to Understand From You

We would value your perspective on the following questions. There are no right answers — the goal is to understand whether the platform as described maps to how cryo-EM work actually runs in your lab or facility.

**On coverage and fit:**

1. Looking at the stage-by-stage breakdown above — where does your current work sit, and does the coverage feel complete for those stages? What step is conspicuously absent?

2. The platform covers the computational processing pipeline from raw movies to a sharpened map and validated model. The steps it does not yet cover interactively are manual model building in Coot and structure deposition. How critical are those two gaps for your current workflow?

3. Do you primarily run SPA on purified complexes, in-situ cryo-ET, or both? If cryo-ET, how central is subtomogram averaging to your projects versus visual inspection of tomograms?

4. For groups whose structural work feeds into a drug discovery programme: is the path from a solved EM structure to a docked compound currently handled within your lab, passed to a separate computational chemistry team, or outsourced? Would having the docking step in the same platform as the structure determination change how you hand that off?

**On software and tooling:**

5. What do you currently use for SPA processing — CryoSPARC, RELION, or a mix? If both, is there a clear rule for which one you reach for first?

6. How is your CryoSPARC access managed — site licence, per-lab licence, facility-managed instance, or do you rely on RELION precisely because it avoids the licence question?

7. How do you currently manage the bookkeeping of a processing project — which software version, which micrograph subset was used, which parameters were tried and discarded? Is there a system, or is it tracked informally?

**On quality governance:**

8. When a dataset has borderline data quality — a CTF fit quality that is acceptable but not great, or a 2D classification where 40% of classes look like junk — how does your team decide whether to proceed to refinement or re-collect? Is that decision made by one person, reviewed by a senior researcher, or documented anywhere?

9. Preferred orientation is one of the most common failure modes in cryo-EM. When you encounter it, what is your current workflow for detecting it, quantifying it, and deciding what to do next? Would having that automatically flagged mid-pipeline change how quickly you respond?

10. Would an automatically generated processing audit log — recording every QC decision, every parameter choice, every override, and the tool version used — be useful to you for internal documentation, facility records, or EMDB deposition? Or would it create overhead that outweighs the benefit?

**On the facility context:**

11. Is cryo-EM in your setting primarily a single-lab resource, a shared core facility serving multiple PIs, or a large national facility? How does that context affect what you would need from a platform like this — for example, multi-user project separation or per-group storage quotas?

12. Data volumes in cryo-EM are large — a single Krios session can produce 1–3 TB. Where does your data currently live after collection, and who is responsible for running the first preprocessing pass before the data expires from the acquisition machine? Is there a bottleneck there?

**On integration and compute:**

13. What is your typical GPU setup — local workstation, institutional cluster, or cloud on demand? Do GPU hours feel like a scarce resource, and if so, at which processing stage is the bottleneck worst?

14. Is your institution comfortable with cloud compute for cryo-EM data, or are there data governance or cost concerns that make on-premise execution the only realistic option?

**On research intelligence:**

15. The cryo-EM methods landscape changes quickly — new refinement algorithms and CTF estimators appear every year. How does your team currently track which tools to use for a given sample type? Would a literature-aware assistant embedded in the analysis environment change that?

16. When a processing run produces an unexpected result — a resolution plateau, or 2D classes that do not match what you see in the raw micrographs — where do you currently go first for diagnostic guidance?

**On results and output:**

17. After a reconstruction completes, what is the first thing you do with the map — open it in UCSF ChimeraX, send it to a collaborator, start fitting a model, or compare FSC curves to a previous run? Which of those steps is most friction-prone today?

18. The platform generates a structured processing report covering the full pipeline, all QC outcomes, and tool versions. If this report were formatted to align with what EMDB requires for deposition, would that reduce your deposition effort — or is deposition metadata not currently the main bottleneck?

**On what is missing:**

19. What capability — if BioMate had it — would make the strongest case for adoption in your lab or facility?

20. Is there a category of analysis you run routinely in structural biology that is not represented anywhere in this document?

---

## What Can Be Built on Top of BioMate

The platform is designed to be extended. Groups who collaborate with us get direct access to:

- **Custom workflow integration** — if your lab has an in-house processing script or a custom picker, it can be wrapped as a BioMate workflow and receive the same QC governance and AI assistance as everything else on the platform
- **Custom QC profiles** — threshold sets tailored to your sample type (membrane proteins, small complexes, phase plate datasets, low-dose collections); versioned, auditable, and portable across projects
- **API access** — programmatic pipeline submission, result retrieval, and QC event streams; suitable for integration with a facility LIMS or an automated data mover running alongside the acquisition computer
- **AI assistant fine-tuning** — the workflow generation model can be primed with your lab's standard data collection protocols and historically successful parameter sets, so recommendations draw on your own institutional knowledge
- **Co-development** — capabilities on the roadmap (on-the-fly QC, EMDB deposition wizard, Coot integration, facility multi-user management) can be prioritised and co-designed around your specific use cases

---

*Document version: March 2026*
