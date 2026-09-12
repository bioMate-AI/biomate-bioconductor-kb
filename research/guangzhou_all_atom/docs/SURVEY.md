# Peptide-first generative drug design for the Guangzhou program

## Decision

A peptide-first program can use an all-atom generative foundation model, but neither the representation nor a shared transformer is by itself a new contribution. The most defensible starting point is a peptide design and optimization system with explicit covalent topology, stereochemistry, target context and measured developability objectives. Reuse a strong published generator initially, qualify it on the intended peptide chemistry, and introduce new modeling only against a frozen baseline.

A conventional conversational LLM can serve every modality as the planning and evidence interface. It should call scientific generators and evaluators. A molecular language model is a different component: it can generate residue, SMILES or monomer sequences, but valid text does not establish a correct bound conformation. An all-atom diffusion/flow model is another component again. These distinctions matter when describing the proposed model to the Guangzhou partner.

The recommended immediate comparison is BoltzGen for supported peptide binder topologies, PepGLAD/PepFlow for full-atom sequence–structure design, and a peptide chemistry generator such as PepTune for broader chemical optimization. Include RFpeptides for macrocyclic binders. Treat UniMoMo as evidence that sharing a backbone across modalities is possible, not as proof that a single checkpoint will meet all therapeutic requirements. [^1][^2][^3][^4][^5][^6]

The opportunity is technically advanced, but there is no evidence here that our own model is already state of the art. That claim requires reproducible comparisons and, for drug-discovery utility, prospective measured results. A useful proposed research question is: **can chemistry-aware peptide adaptation improve the number of distinct, synthesis-feasible candidates meeting target and developability constraints per fixed experimental budget on unseen target/series combinations?** This is a hypothesis, not an established novelty claim.

## Scope and recovered project records

This assessment covers public evidence retrieved through September 12, 2026, emphasizing original papers, official code and dataset records. It prioritizes peptides following the clarified project direction; small molecules and other modalities are assessed as extensions. Newly retrieved preprints are identified separately from published work. Computational comparisons are not pooled into a universal ranking because tasks, training data, postprocessing and denominators differ.

The original Guangzhou requirements ask for molecular generation and optimization across synthetic accessibility, affinity and safety, integrated with prediction and ranking. The internal English reference records a RMB 70 million listing and December 31, 2026 deadline; these are transcribed project details, not independently verified procurement terms. The questionnaire leaves modality, target, assays, deployment and IP to be agreed. [L1–L3]

The recovered August survey and closed-loop test plan are in the `biomate-audit-fix` worktree. They describe REINVENT/3D-generation integration, scoring, Bayesian selection and wet-lab feedback. They are evidence of an integrated discovery proposal, not a specification of a new all-atom peptide foundation model. The September capability audit explicitly distinguishes a BRICS enumeration workflow from learned generation and identifies wider model-adapter and campaign capabilities. Current source confirms the BRICS implementation and the presence of model-registry and Bayesian-optimizer modules; historical test claims were not rerun as part of this survey. [L2, L4, L5]

## Can the same model serve different drug modalities?

| Modality | What can be shared | What must be specialized | Initial position |
|---|---|---|---|
| Linear canonical peptides | Target encoder, atom/residue geometry, sequence prior, campaign interface | Sequence/structure decoding, proteolysis, solubility and target assays | Primary baseline track |
| Cyclic/disulfide/stapled peptides | Much of the peptide backbone model and atomic context | Closure bonds, crosslink identities, geometry, chemical synthesis and topology validation | Primary extension; qualify each topology |
| D-residue, N-methylated, other noncanonical peptides | Atomistic graph features and some learned interactions | Monomer chemistry, stereochemistry, tokenizer/decoder coverage, permeability and conformational sampling | Dedicated chemistry track |
| Small molecules | Atom/bond geometry, pocket encoding and multi-objective orchestration | Variable graph generation, medicinal-chemistry training distribution and property models | Separate specialist baseline |
| Peptidomimetics/nonpeptidic macrocycles | Graph and conformer machinery | Mixed monomers, backbone replacements, macrocycle conformations and synthesis | Bridge track after peptide baseline |
| PROTACs | Chemistry encoders, linker generators and ranking infrastructure | Two binders, exit vectors, linker geometry, ternary complexes and degradation readouts | Separate task and benchmark |
| Molecular glues | Interaction encoders and chemistry representation | Composite interfaces, cooperative ternary stabilization and functional mechanism | Research extension |
| Antibodies/nanobodies | Some protein/peptide generative and target representations | Framework/CDR constraints, developability and immunological/functional assessment | Separate supported protein-design branch |
| Conjugates, including peptide–drug or antibody–drug conjugates | Component inventory and workflow platform | Payload, linker, attachment site, release, exposure and combined pharmacology | Modular system, not one free-form generator |

These are architectural recommendations. Shared input representation is weaker evidence than joint generation, and joint generation is weaker than validated performance in every modality. In particular, a model accepting a small molecule as a **target/context** does not necessarily generate new small-molecule chemistry. BoltzGen's protein-small_molecule protocol designs proteins binding small molecules; it is not a replacement for a ligand generator. [^1][^2]

A practical system therefore has one project interface and candidate contract, a small portfolio of generators, and modality-specific evaluators. A later unified backbone can be tested with task identifiers, balanced sampling, chemistry-specific adapters and decoders. It must beat independent specialists at equal data and compute. Negative transfer is plausible: abundant canonical-protein examples can dominate scarce macrocycle or noncanonical-peptide data.

## Peptide model landscape

**BoltzGen.** The 2025 preprint presents an all-atom model combining design and structure prediction with covalent and structural design specifications. It reports experimental campaigns across multiple binder classes and targets. This gives it stronger practical evidence than a model supported only by docking scores, but does not establish universal performance on modified therapeutic peptides. Official code is MIT-licensed and includes a peptide protocol. Verify the exact supported designed-residue vocabulary and topology rather than inferring arbitrary noncanonical generation from the ability to supply modified context. [^1][^2]

**PepGLAD.** The NeurIPS 2024 work uses a geometric latent diffusion model for target-conditioned full-atom peptide design. A residue autoencoder compresses variable atomic detail; receptor-dependent coordinate normalization addresses binding-site geometry. It is a focused and useful scientific comparator for peptide sequence–structure co-design. A repository note that pocket detection accepts noncanonical residues is not evidence that the designed peptide decoder generates arbitrary noncanonical monomers. [^3]

**PepFlow.** The 2024 work jointly models peptide sequence and structural degrees of freedom using multimodal flow matching. It offers a relevant comparator for co-design and side-chain tasks. Its existence rules out treating joint peptide sequence/structure flow matching as a new idea. Check the deployed model's supported residue vocabulary, length range and topology against the planned chemistry. [^4]

**RFpeptides and AfCycDesign.** Published macrocycle design work adapts structure-generation/prediction machinery to cyclic connectivity and reports high-affinity protein-binding macrocycles. These are important controls when the deliverable is a cyclic peptide binder. Canonical macrocycle design success does not automatically transfer to arbitrary D-residues, crosslinkers or N-methylation; those modifications change chemistry and conformational preferences. [^7][^8]

**PepTune.** The ICML 2025 work uses guided discrete diffusion over peptide SMILES for multi-objective optimization. It is relevant when chemical diversity and nonstandard peptide chemistry matter. It should be paired with an independent structural workflow for a project claiming target-conditioned all-atom design. Optimizing learned property scores does not establish measured permeability, safety or potency. [^5]

**PepALD.** A June 2026 preprint proposes autoregressive latent diffusion for macrocyclic peptides with chemical grounding of monomers. It is a closely relevant emerging comparator for non-natural macrocycles. Its publication recency and preprint status require checking code, checkpoint and data availability before making it an execution dependency. [^9]

**CycDiff-DPO.** The 2026 Chemical Science article studies preference-based optimization of target-binding macrocycles for permeability. This materially narrows the novelty space: adding a permeability predictor and preference optimization to a peptide generator is already represented in the literature. A new contribution needs a stronger generalization, calibration, chemistry or prospective-validation result. [^10]

**Additional watchlist.** SurfFlow proposes surface-aware peptide co-design, PepBFN uses Bayesian flow networks, and APCyc explicitly addresses cyclization and properties. These recent preprints deserve reproduction if their chemistry and benchmark overlap ours, but are not treated here as experimentally established replacements for the initial baselines. [^11][^12][^13]

## Unified and small-molecule models

**UniMoMo** jointly represents molecular fragments and amino-acid blocks, using a full-atom autoencoder with geometric latent diffusion across small molecules, peptides and antibodies. It directly supports the scientific plausibility of cross-modality training. The official repository calls it a computational proof of concept; antibody design also has framework requirements. Use it to test whether shared training helps peptide performance, with each modality reported separately. [^6]

**FLOWR / FLOWR.root** are relevant to the small-molecule extension. FLOWR combines continuous and categorical flow modeling with pocket conditioning and introduces SPINDR. Its original repository now points to FLOWR.root for continued development. The latter adds joint affinity/generation capabilities and adaptation, while its authors explicitly warn about incomplete convergence and OOD limitations. These are useful integration candidates, not peptide-first defaults or unbiased affinity judges for their own output. The root repository's core MIT license differs from its UI's source-available terms. [^14][^15]

**FlowMol3** is an unconditional small-molecule generator, including explicit hydrogens, using continuous/discrete flow modeling. Its improvements include self-conditioning, fake atoms and geometry distortion. It is an appropriate atomic-chemistry reference, but lacks the peptide-specific target/topology contract needed for this program. Its reported validity does not imply target affinity or peptide utility. [^16]

**REINVENT4 and joint flow optimization.** REINVENT4 remains a practical sequence-based generation/optimization control for the small-molecule branch. A September 2026 Communications Chemistry paper jointly optimizes continuous and discrete flow-model features using rewards. Together these establish that model adaptation and multi-objective generation are active, populated areas. Scientific novelty must be assessed at the level of a precise method and outcome. [^17][^18]

**Synthesis-aware generation.** SynCoGen models building blocks, reactions and 3D coordinates jointly. It is pertinent to a later synthesis-aware small-molecule branch, but does not eliminate the need for peptide-specific synthesis representations and laboratory feasibility. Peptide design must track complete monomer identities, terminal groups and crosslinks so that a synthesis request denotes a unique compound. [^19]

## Proposed architecture and research contribution

The first version should use a target-conditioned peptide generator behind a stable interface rather than start with expensive general foundation-model pretraining. The input contract includes target structure/sequence, binding region, peptide length range, allowed chemistry and protected motifs. The output must include a complete molecular graph with stereochemistry, residue/monomer mapping, crosslinks, raw coordinates and generation provenance. A one-letter sequence is insufficient for modified peptides.

Use a hierarchical representation: atom/bond graphs for chemical identity; monomer tokens for efficient peptide modeling; explicit attachment atoms and closure edges; and coordinate or internal-coordinate features for 3D geometry. Maintain D/L stereochemistry as chemistry rather than a text annotation. Support for a monomer in the input parser must not silently become a claim that the generator was trained to produce it.

Begin with separate canonical peptide and chemically modified peptide tracks. Reuse the target encoder and campaign logic where justified; freeze unsupported chemistry and report it. Add an adapter or monomer-aware decoder only after a baseline failure demonstrates the need. Compare against retraining a specialist on exactly the same data to isolate the value of shared training.

The most promising project-level differentiation is a **measured-data-guided peptide optimization loop with controlled generalization**: target binding and selectivity, stability, solubility, permeability where relevant, synthesis feasibility, diversity and uncertainty. That combination is a useful product proposal but still not sufficient to claim algorithmic novelty. A publishable contribution would need evidence such as better out-of-series performance, improved calibration under chemistry shifts, or a better prospective success rate at equal experimental cost.

Keep novelty and reliability distinct. Exact training-set overlap can identify rediscovery, and fingerprint/sequence distances can flag related examples. Neither estimates binding reliability by itself. The 2026 molecular-unfamiliarity work relates reconstruction behavior to distribution shift and predictive generalization; its applicability to peptide property endpoints needs testing rather than assumption. Do not maximize novelty indiscriminately: moving farther from measured data can weaken property predictions. [^20]

## Data and evaluation

Use separate data ledgers for peptide–target complexes, unbound peptide conformations, property assays and synthesis outcomes. Preserve publication/source identifiers, molecular graphs, units, assay conditions, censoring and known failure outcomes. Do not merge binding constants, inhibition endpoints and cellular functional responses into one label without an explicit model of their relationship.

CycPeptMPDB's published release aggregates thousands of cyclic peptides and permeability measurements. It is a useful starting source, not a homogeneous set of interchangeable permeability labels. Assay/source differences and chemical-series overlap can create optimistic random-split results. Split by chemical family and source where feasible, preserve a temporal holdout, and validate on the partner's relevant assay. [^21]

For structures, cluster targets and peptide families before splitting. Prevent exact-identity leakage across alternative SMILES, atom orderings, cyclic starting residues and conformers. Check target homology and binding-site similarity separately. Compare checkpoint training cutoffs with test deposition dates. Unknown pretraining manifests must be recorded as unknown; a newly assembled evaluation set can still overlap an old model's training set.

Use four benchmark strata: canonical linear peptides; supported cyclic/disulfide peptides; specified modified/noncanonical peptides; and later cross-modality transfer. Evaluate known-ligand reconstruction separately from de novo generation. Do not provide an experimental ligand's atomic contacts to a de novo model and then call recovery a blind discovery result.

Primary computational reporting should be the fraction of **all attempted samples** passing the predeclared chemistry and geometry contract, followed by unique, route-reviewed candidates passing the project objectives. Report raw and relaxed structures separately, identify duplicate removal and resampling, and record compute per accepted candidate. Chemical sanitization alone does not prove physical validity; structural benchmarks have repeatedly demonstrated this gap. Small-molecule PoseBusters checks are useful, but peptide closure, chirality, backbone torsions and crosslinks require additional validation. [^22][^23]

Peptide-specific evaluation should include sequence/monomer validity, atom connectivity, stereochemistry, covalent closure, target clashes and interface geometry; diversity in sequence, monomer composition and structure; target-family and chemistry-shift generalization; and measured endpoint prediction with calibration. For intracellular projects, include permeability and cellular target engagement; for extracellular projects, use relevant exposure and stability criteria rather than assuming membrane entry is desirable.

Prospective validation should compare against the partner's current method and a published baseline under a fixed synthesis/assay budget. Select candidates before assay unblinding; retain synthesis failures and inactive candidates. Report synthesis success, purity, measured target activity/selectivity, appropriate developability endpoints, and confidence intervals. Select numerical acceptance thresholds after target and assay selection, before evaluating the held-out results.

## Other compound modalities

PROTACs require joint attention to two ligands, their linker and the induced ternary complex. Binary docking scores are insufficient as the sole objective. Recent ternary-complex prediction and linker-driven sampling studies illustrate that this is a distinct modeling task; cellular degradation endpoints are distinct from binding measurements. Molecular glues likewise need interface/cooperativity-aware evaluation, and a newly proposed ternary-generative model is not yet proof of broad prospective discovery. [^24][^25][^26]

Conjugates should be represented compositionally: binder, payload, linker, attachment site and release mechanism. Even perfect generation of each component does not establish the pharmacology of the combined product. The reusable asset is the candidate record and experimental loop; component-specific models remain appropriate.

The recommended expansion order is canonical and supported cyclic peptides first, specified modified macrocycles second, small molecules as an independent branch third, and degraders/conjugates only when the target biology and assays justify them. This order limits simultaneous uncertainties in chemistry, generation and evaluation.

## Limitations and decision gates

Public benchmark claims were examined but not reproduced during the literature survey. Several current papers are preprints; repository support and paper scope can differ. Licensing statements are repository observations, not a completed audit of weights, data or commercial dependencies. No particular partner target, proprietary dataset, peptide chemistry class or assay panel is available in these records.

Proceed now with representation, evaluation and baseline preparation. Before target-specific training, fix the chemistry contract, data rights and evaluation split. Before a partner-facing SOTA claim, reproduce the relevant specialists and run prospective experiments. The research program remains strong without claiming an unverified new universal model.

## Sources

[^1]: Stark et al. *BoltzGen: Toward Universal Binder Design*. 2025 preprint. https://pmc.ncbi.nlm.nih.gov/articles/PMC12697729/
[^2]: BoltzGen authors. Official implementation and protocols; accessed September 12, 2026. https://github.com/HannesStark/boltzgen
[^3]: Kong et al. *Full-Atom Peptide Design with Geometric Latent Diffusion*. NeurIPS 2024. https://arxiv.org/abs/2402.13555 ; official code https://github.com/THUNLP-MT/PepGLAD
[^4]: *Full-Atom Peptide Design based on Multi-modal Flow Matching*. 2024. https://arxiv.org/abs/2406.00735
[^5]: Tang et al. *PepTune: De Novo Generation of Therapeutic Peptides with Multi-Objective-Guided Discrete Diffusion*. ICML 2025; preprint 2024. https://arxiv.org/abs/2412.17780
[^6]: Kong et al. *UniMoMo: Unified Generative Modeling of 3D Molecules for De Novo Binder Design*. ICML 2025. https://arxiv.org/abs/2503.19300 ; https://github.com/kxz18/UniMoMo
[^7]: *Accurate de novo design of high-affinity protein-binding macrocycles using deep learning*. Nature Chemical Biology, 2025. https://www.nature.com/articles/s41589-025-01929-w
[^8]: *Cyclic peptide structure prediction and design using AlphaFold2*. Nature Communications, 2025. https://www.nature.com/articles/s41467-025-59940-7
[^9]: *PepALD: Macrocyclic Peptide Generation via Autoregressive Latent Diffusion*. June 2026 preprint. https://arxiv.org/abs/2606.14510
[^10]: *Design of permeability-optimized target-binding macrocycles via direct preference optimization*. Chemical Science, 2026. https://pubs.rsc.org/en/content/articlepdf/2026/sc/d6sc01722c
[^11]: *Surface-based Molecular Design with Multi-modal Flow Matching*. January 2026 preprint. https://arxiv.org/abs/2601.04506
[^12]: *Full Atom Peptide Design via Riemannian Euclidean Bayesian Flow Networks*. November 2025 preprint. https://arxiv.org/abs/2511.14516
[^13]: *APCyc: Property-Informed Design of Cyclic Peptides via Automated Cyclization*. June 2026 preprint. https://arxiv.org/abs/2606.12991
[^14]: Cremer et al. *FLOWR*. Nature Computational Science, 2026. https://www.nature.com/articles/s43588-026-00998-8 ; https://github.com/jule-c/flowr
[^15]: Cremer et al. *FLOWR.root*. 2025 preprint and current official code. https://arxiv.org/abs/2510.02578 ; https://github.com/jule-c/flowr_root
[^16]: Dunn and Koes. *FlowMol3*. Digital Discovery, 2026; preprint 2025. https://pmc.ncbi.nlm.nih.gov/articles/PMC13104864/ ; https://github.com/Dunni3/FlowMol
[^17]: MolecularAI. REINVENT4 official repository and documentation. https://github.com/MolecularAI/REINVENT4
[^18]: Wang, Janet and Tibo. *Controllable molecular generation with fine-tuned flow-matching model*. Communications Chemistry, September 5, 2026. https://www.nature.com/articles/s42004-026-02188-z
[^19]: *SynCoGen: Synthesizable 3D Molecule Generation via Joint Reaction and Coordinate Modeling*. 2025 preprint. https://arxiv.org/abs/2507.11818
[^20]: *Molecular deep learning at the edge of chemical space*. Nature Machine Intelligence, 2026. https://www.nature.com/articles/s42256-026-01216-w
[^21]: *CycPeptMPDB: A Comprehensive Database of Membrane Permeability of Cyclic Peptides*. JCIM, 2023. https://doi.org/10.1021/acs.jcim.2c01573
[^22]: Buttenschoen, Morris and Deane. *PoseBusters: AI-based docking methods fail to generate physically valid poses or generalise to novel sequences*. Chemical Science, 2024. https://pmc.ncbi.nlm.nih.gov/articles/PMC10901501/
[^23]: Sanjrani et al. *Benchmarking 3D Structure-Based Molecule Generators*. JCIM, 2025. https://pubs.acs.org/doi/10.1021/acs.jcim.5c01020
[^24]: *AI-Based Prediction of PROTAC- and Molecular Glue-Mediated Ternary Complexes: A Comparative Evaluation of AlphaFold 3 and Boltz-2*. Archiv der Pharmazie, March 2026. https://onlinelibrary.wiley.com/doi/10.1002/ardp.70225
[^25]: *Linker-Driven Sampling of PROTAC-Induced Ternary Complexes*. Journal of Medicinal Chemistry, June 2026. https://pubmed.ncbi.nlm.nih.gov/42233498/
[^26]: *TriGlue: a Biology-Inspired Generative Model for Generating Molecular Glue-Induced Ternary Complex*. July 2026 preprint. https://arxiv.org/abs/2607.22143

Local records (private workspace access):

- L1. [Guangzhou project English reference](/Users/kky/biomate-review/docs/20260911_GUANGZHOU_AI_DRUG_DESIGN_PROJECT_EN.md), September 11, 2026, requirements and opportunity summary.
- L2. [Full capability audit](/Users/kky/biomate-review/docs/20260911_GUANGZHOU_AI_DRUG_DESIGN_CAPABILITY_AUDIT.md), September 11, 2026, technical precision and verification status.
- L3. [Client questionnaire](/Users/kky/biomate-review/docs/20260911_GUANGZHOU_CLIENT_QUESTIONNAIRE_EN.md), September 11, 2026, modality and acceptance questions.
- L4. [Earlier survey](/Users/kky/biomate-audit-fix/docs/20260811_DRUGDISCOVERY_SOTA_SURVEY_AND_GAP_FIXES.md), August 11, 2026, generation and closed-loop sections.
- L5. [Earlier test plan](/Users/kky/biomate-audit-fix/docs/20260811_DRUGDISCOVERY_CLOSEDLOOP_TEST_PLAN.md), August 11, 2026, computational and wet-lab plan.
