# IH-LM: a knowledge-augmented all-atom language model for cyclic-peptide design, trained with rule-compiled decoding, verifier feedback and held-out-verifier stopping

## Abstract

Cyclic peptides bind extended protein surfaces and a subset is orally available, but generative models for them are usually judged by distribution metrics, by a predictor that is also the reward, or by docking-style scores, and rarely against tuned search baselines at an equal oracle budget. We introduce IH-LM, a knowledge-augmented, decoder-only, atom-level language model for cyclic-peptide design. IH-LM generates SMILES with explicit chirality and ring-closure tokens, and we introduce two contributions. (1) We compile design rules for macrocyclic peptides with non-canonical residues, stereochemistry and ring closure (macrocycle closure, ring size, N-methyl count, molecular-weight bound, structural alerts) into a token-level decoding automaton with prefix look-ahead, and we fine-tune the model with the mask applied so that its learned distribution is conditional on the rules. (2) We build a provenance-linked knowledge layer from literature, patents and structures, in which every statement carries a source and a machine-verified quotation, and we use it as retrieval context (known series, rule snippets, target cards) and as soft priors. Training uses graded verifier-feedback preference tuning and a gap-based stopping monitor under a three-way train, stop and held-out verifier split. The hypothesis under test (H-AA) is that, at a fixed budget of train-verifier calls, IH-LM attains a higher AUC-top-10 (in generation-space standard-deviation units) on held-out verifiers than the best tuned simple optimiser (edit-operator and SELFIES genetic algorithms, Tanimoto-kernel Bayesian optimisation, REINVENT-style reinforcement learning, library enumeration with a surrogate, and a language-model-as-operator search) by at least a pre-registered relative margin (a tenth of the gap that the best baseline closes over random library sampling), and that it recovers more held-out known binders in a blind retrospective arm. We test both contributions with an oracle-budget evaluation on independent held-out verifiers (protocol and calibrated validity gate: companion paper) and with ablations: without rule compilation, without knowledge augmentation, hard rules only against literature priors against data-descriptive priors, and the unaugmented backbone.

---

## 1. Introduction

Cyclic peptides occupy a chemical space between small molecules and biologics. Design is difficult for reasons specific to the space: non-canonical residues, N-methylation and D-residues change conformation and permeability in context-dependent ways; macrocyclisation imposes topological constraints on any generator; and the measured property data that exist are small, assay-heterogeneous and dominated by a few laboratories. The companion paper quantifies the last point: held-out-laboratory skill of fitted models on the largest public cyclic-peptide permeability collection is a fraction of random-split skill, and public lab-shift tests contain too few independent laboratories to detect effects of the size usually reported.

We present IH-LM, a language model built for this setting. It is a decoder-only transformer over atom-level SMILES in which chirality and ring closures are explicit tokens, so that stereocentres, N-methylation, D-residues and macrocycle topology are represented directly. Its design follows from a diagnosis. In a pre-registered pilot, unconditioned language models used as seeded generators, including the unaugmented base model, produced fewer constraint-satisfying unique novel molecules than a monomer-library enumerator (704.6 per 1,000 samples for the enumerator against 237.2 to 294.3 for three language models), because the constraints (macrocycle, N-methyl count, molecular weight, polar surface area, PAINS) are satisfied almost by construction when molecules are assembled from monomers. A language model validated only on constraint yield cannot win; the rules must be removed from the model's burden and the comparison moved to objectives that the rules do not determine. Two earlier feedback runs also barely moved their policies, which pointed to a defect in how the learning signal was constructed. IH-LM is built around these two findings.

**Contributions.** We introduce IH-LM and make two contributions.

1. *Rule-compiled decoding with fine-tuning under the mask* (Section 3.2). We compile peptide design rules into a token-level decoding automaton with prefix look-ahead for macrocyclic peptides with non-canonical residues, stereochemistry and ring closure, and we fine-tune the model with the mask applied so that its learned distribution is conditional on the rules.
2. *Knowledge augmentation* (Section 3.3). We condition IH-LM on a provenance-linked knowledge layer built from literature, patents and structures, in which every statement is tied to a source and a machine-verified quotation. The layer enters the model as retrieval context (known series, rule snippets, target cards) and as soft priors on the logits.

The training procedure (Section 3.4) also uses a graded preference stage that avoids zero-variance reward groups and a gap-based stopping monitor under a three-way train, stop and held-out verifier split; these are components of the procedure and are described in Methods. We test the two contributions in Section 4 with an oracle-budget evaluation on independent held-out verifiers, a blind retrospective recovery arm and ablations (without rule compilation; without knowledge augmentation; hard rules only against literature priors against data-descriptive priors). The evaluation protocol and the calibrated validity gate are those of the companion paper, summarised in Section 4, and the construction of the knowledge layer is described in the knowledge-base paper and summarised in Section 3.3.

---

## 2. Related work

**Chemical and peptide language models.** ChemFM-1B is a general chemistry causal language model (Llama architecture, about 970 million parameters; arXiv:2410.21422). It provides fluent SMILES generation but no peptide-specific design knowledge; its content of N-methylated, D-configured and macrocyclic molecules is not documented, and we measure it. PeptideCLM-2 is a family of masked language models over SMILES pretrained on peptides and small molecules (Feller et al., J. Chem. Inf. Model. 2026); its model cards describe property prediction and document no generation procedure. Both leave open how rule satisfaction, retrieved series and verifier feedback should enter a peptide generator. IH-LM compiles the rules into decoding and conditions on a provenance-linked knowledge layer (Sections 3.2 and 3.3), and uses the PeptideCLM-2 encoder for retrieval and diversity.

**Peptide generators and design tools.** PepINVENT extends REINVENT with non-natural amino acids by reinforcement learning (Geylan et al., arXiv:2409.14040); PepGLAD designs full-atom peptides by geometric latent diffusion (Kong et al., arXiv:2402.13555); PepTune guides discrete diffusion with multiple objectives (Tang et al., arXiv:2412.17780); PepMLM generates binders by span masked language modelling (Chen et al., arXiv:2310.03842); AfCycDesign and RFpeptides use structure-prediction networks for cyclic-peptide and macrocycle design, and RFpeptides reports wet-lab outcomes including designs that failed (Rettie et al., bioRxiv 10.1101/2023.02.25.529956, 10.1101/2024.11.18.622547); BindCraft provides filters that are reused in peptide work (Pacesa et al., bioRxiv 10.1101/2024.09.30.615802); EvoBind searches peptide space by mutation with an AlphaFold-based loss (Bryant and Elofsson, bioRxiv 10.1101/2022.07.23.501214). These works demonstrate that cyclic and non-canonical peptides can be designed computationally and sometimes experimentally. In the sources we read, however, success is often defined by a threshold that most designs pass (a Rosetta ΔG below zero in PepGLAD), the optimised predictor is also the reported metric (PepINVENT, PepTune), and no generator is compared with a mutation or genetic-algorithm baseline at an equal oracle budget. IH-LM is therefore evaluated against tuned search baselines at a fixed budget, on verifiers it did not optimise (Section 4).

**Benchmarks and search baselines.** GuacaMol and MOSES standardised distribution-learning and goal-directed evaluation for small molecules (Brown et al., arXiv:1811.09621; Polykovskiy et al., arXiv:1811.12823). Their distribution metrics can be gamed: a random sampler scores close to the ceiling on KL divergence and Fréchet ChemNet distance, and a trivial "add a carbon" perturbation scores near 100% on validity, novelty and uniqueness (Tripp and Hernández-Lobato, arXiv:2310.09267, Table 1). The PMO benchmark fixes the oracle budget at 10,000 calls, scores the area under the top-10 mean curve and finds that older methods outperform newer ones (Gao et al., arXiv:2206.12411; REINVENT 14.196, Graph GA 13.751, Gaussian-process Bayesian optimisation 13.156). A tuned genetic algorithm later summed to 14.708 on the same suite (Tripp and Hernández-Lobato, Table 2), and adding property and diversity filters re-orders the ranking (Thomas et al., arXiv:2212.01385). DOCKSTRING reports that optimisers drift toward large lipophilic molecules when docking score is the objective (Garcia-Ortegon et al., arXiv:2110.15486). MolLEO uses chemistry-aware language models as crossover and mutation operators in evolutionary search (Wang et al., arXiv:2406.16976), and Saturn reports sample-efficient reinforcement learning with a Mamba model and experience replay (Guo and Schwaller, arXiv:2405.17066). These establish the protocol and the strength of the baselines; none addresses peptides with non-canonical residues or held-out verifiers fitted on disjoint sources. We adopt the protocol and include a language-model-as-operator arm because "a language model helps a genetic algorithm" is already established.

**Constrained decoding and validity by construction.** The Grammar VAE guarantees syntactically valid output through a grammar (Kusner et al., arXiv:1703.01925); SELFIES guarantees validity at the string level (Krenn et al., arXiv:1905.13741), with no consistent advantage over SMILES outside genetic algorithms in PMO; finite-state and context-free-grammar guided decoding is established for language models (Willard and Louf, arXiv:2307.09702; Mündler et al., arXiv:2508.10111). Validity is cheap to guarantee and cannot distinguish generators, and these methods target syntax, not the chemical property windows and macrocycle topology that define cyclic-peptide design. IH-LM compiles property-level and topology-level rules into the decoder with prefix look-ahead and then trains under the mask (Section 3.2).

**Preference optimisation, verifiable rewards and over-optimisation.** Direct preference optimisation (Rafailov et al., arXiv:2305.18290) is the objective we use for the update. Reinforcement learning with verifiable rewards has been applied to chemistry language models, for example ether0 (a 24-billion-parameter model trained on 640,730 experimentally grounded problems, with documented reward-hacking patterns and plausibility filters against them; Narayanan et al., arXiv:2506.17238), LLMol (arXiv:2607.19044) and RePO (arXiv:2603.05900); these report the sparse-feedback problem under similarity constraints but not peptide generation with independent held-out verifiers. The divergence between a proxy and a gold reward during optimisation is measured for language-model reinforcement learning (Gao, Schulman and Hilton, arXiv:2210.10760), and constrained formulations address it with composite rewards (Moskovitz et al., arXiv:2310.04373). Stopping on an independent validation signal is therefore an established idea; IH-LM's training procedure applies it with a stop verifier that is independent of the training verifier by fitting laboratory (Section 3.4.4).

**Knowledge and retrieval.** Curated collections cover structure-property data (CycPeptMPDB, CREMP, CyclicPepedia, Macrocycle-DB, SweMacrocycleDB) and peptide-protein complexes (PepBDB, Propedia, BioLiP2); they do not provide structured design rules with provenance, a campaign ledger, or a cyclic-annotated complex set. In our own data nearest-neighbour lookup was the strongest few-label baseline and analog retrieval the only module of an earlier model ladder with a consistent effect (companion paper), which is why retrieval is a component with an ablation arm and not a claimed contribution. The knowledge layer builds on the existing collections by identifier and adds the missing layers (Section 3.3).

**Simple baselines for peptide properties and evaluation practice.** In cyclic-peptide permeability prediction a Tanimoto-kernel Gaussian process outperformed fine-tuned ChemBERTa, random forest and XGBoost on a near-duplicate-removed split (ROC-AUC 86.7 against 80.0 to 83.9; Amirahmadi et al., arXiv:2511.21566), and PepBenchmark reports random forest on ECFP6 leading on non-canonical peptide tasks and small sets (Zhang et al., ICLR 2026). Requiring physical validity changes the ranking of docking methods (Buttenschoen et al., arXiv:2308.05777) and generated poses show related failures (Harris et al., arXiv:2308.07413). We therefore include a kernel-based optimiser among the baselines and apply orthogonal physical checks to final candidates (Section 4.10).

---

## 3. IH-LM

### 3.1 Architecture

**Backbone.** IH-LM is a decoder-only transformer of about 970 million parameters with 22 layers, hidden size 2,048, rotary position embeddings, a vocabulary of 320 atom-level tokens and 512 positions. The vocabulary is a SMILES atom tokenisation in which bracket atoms carry chirality (`@`, `@@`), charge and explicit hydrogens, ring closures are digit tokens and branches are parenthesis tokens, so stereochemistry, N-methylation, D-residues and macrocycle topology are explicit in the token stream.

**Adapters and conditioning.** Peptide-specific behaviour is learned by low-rank adapters (rank 16 to 32) on the attention projections. The adapters condition generation on a text prefix that contains, in order, (i) an optional retrieved context (the k nearest known peptides in stereo-aware similarity with their verified values, provenance-tagged rule snippets, and for targets with a card its pharmacophore text), and (ii) an optional seed prefix of a SMILES string to be completed or edited (Section 3.3). Sampling uses a temperature parameter under a logit processor that applies the decoding automaton.

**Decoding automaton.** A token-level parser over the 320-token vocabulary tracks ring closures, atom counts and weights, N-methyl amide counts and branch depth, and masks logits so that only tokens with a feasible completion are sampled (Section 3.2).

**Encoder.** A frozen PeptideCLM-2 encoder (31.7 million and 114 million parameter models; weights loaded into our own implementation with strict key and shape matching, zero missing and zero unexpected keys) provides embeddings for the retrieval index and for novelty and diversity measures. Frozen embeddings were not detectably different from fingerprints for ranking in our pilot analyses, so no claim rests on them.

**Structure tier.** Candidate peptides are scored against targets by Boltz-2 and BoltzGen cofolding and UniMoMo, used for verification only, and by our molecular-mechanics and free-energy pipelines. A cyclic fine-tune of BoltzGen that we tried lost to the base model on three of three comparisons, and UniMoMo's cyclic DockQ (0.759) exceeded that fine-tune's (0.506), so the structure tier is used unmodified.

### 3.2 Rule-compiled decoding

**Rule set.** The hard constraint set C is: a single connected sanitisable molecule; largest ring of at least 12 atoms; between 2 and 6 N-methyl amides (SMARTS `[CX3](=O)[NX3;!H1]([CH3])`); molecular weight in [600, 1,400]; topological polar surface area at most 300; no PAINS match (RDKit catalogue). The set is identical to the one used in the pilot of Section 5.1, and a test asserts equality with the pilot checker on a large string set.

**Compilation.** The tracker maintains ring-closure bookkeeping (open labels and ring sizes), a running molecular-weight sum, and lower bounds on the number of N-methyl amides still required and on the tokens needed to finish. A token is admitted if some completion can still satisfy C, using conservative bounds: an additive molecular-weight bound that uses the remaining-token minimum, the N-methyl window, and feasibility of closing a macrocycle of at least 12 atoms. Inadmissible tokens receive −∞ logits. The prefix look-ahead is the property that matters: a mask without it can steer decoding into a prefix with no rule-satisfying completion. Soundness (no rule-satisfying string is ever pruned) is tested on a golden set of enumerated satisfying, violating and invalid strings with a required false-prune rate of zero; completeness (completions of masked prefixes satisfy C) is tested separately; a reference implementation and a vectorised one must agree on all test strings. Results are in Table 5.

**Soft rules.** Optional log-linear potentials add to the logits (a product of experts). Their weights have three possible sources, treated as an experimental factor: none (hard rules only; the primary configuration), literature priors from the knowledge layer (Section 3.3.5), and the per-laboratory directions measured on the two training laboratories (data-descriptive priors). Mining validated rules on the training laboratories alone yielded none: the unmodified criteria require at least three sources (and half-split agreement for pair rules) and the training group has two. The per-source directions nevertheless agree between the two laboratories and with textbook directions (TPSA −0.470 and −0.485, HBD −0.439 and −0.527, logP +0.287 and +0.488 within-source Spearman; N-methylation mean within-source z-effect +0.623 and +0.483, pooled +0.554 [0.373, 0.735], I² = 0.95). A leak guard rejects any rule file mined from laboratories that fit a stop or held-out verifier.

**Fine-tuning under the mask.** Masked decoding changes the sampling distribution relative to the unmasked model. To keep the learned distribution conditional on the rules, the adapter is trained with the same mask applied to the logits, so that the likelihood is computed under the constrained softmax. Before any feedback is applied we report the divergence between the masked and unmasked models, the validity, uniqueness and diversity of 5,000 masked samples, and the effect of 200 adapter steps (Table 5). A post-hoc-filter arm (no mask; rule failures discarded after generation) is retained as an ablation that also reports the oracle calls wasted on rule failures.

### 3.3 Knowledge augmentation

IH-LM is conditioned on a knowledge layer. This subsection describes what the layer contains, how every statement is verified, how it is kept leak-safe, and how it enters the model. The construction pipeline, coverage analysis and measured extraction quality are given in full in the knowledge-base paper; what is needed to replicate this study is stated here.

**3.3.1 Contents.** The layer holds four kinds of statements about cyclic peptides. (i) *Rules and fundamentals*: directional relations, windows and mechanisms with effect sizes where the source states them (beyond-rule-of-5 windows, intramolecular hydrogen bonding, N-methylation, ring size, lipophilicity and polarity effects, solubility and aggregation, permeability mechanisms). (ii) *Cautions*: limits, data-bias and counter-evidence statements. (iii) *Cards* for design campaigns and methods: what was designed, hit rates, failure modes and lessons, including our own earlier campaigns. (iv) *Structure-derived knowledge*: a library of validated protein-cyclic-peptide complexes, bound-conformation priors computed from it, and target cards for 17 targets (the 16 of our target base and GRPR), each with an explicit flag where the library holds no cyclic complex (Section 3.3.6). Statements derived from patents form a separate tier P (Section 3.3.3(d)).

**3.3.2 Schema, tiers and verification.** Each entry has a statement; a direction (plus, minus, multi, window, context, caution, conflict); a scope; the outcome concerned; an effect size and units where given; an evidence tier (T1: the quoted statement reports a result or method from the source's own experiment, simulation or data analysis; T2: a review's summary of others' work, a restatement of a result cited to another paper, a textbook rule, the authors' background or a project goal, which is also the default when the stored text cannot show that the number is the source's own; T3 secondary source; T-internal our own campaign documents; P patent-derived); a source (PMCID or arXiv identifier, DOI, journal, year); a verbatim quotation of at most 30 words; a confidence level; an access date; and the extractor. Verification is deterministic: after whitespace normalisation the quotation must be an exact substring of the stored full text of the cited paper, and an entry that fails is discarded, never repaired. This guarantees attribution of the sentence, not correct reading; correctness is measured by judged precision on an audit sample (Section 3.3.3(c)). An entry may carry a weight only if its tier is T1 or T2, its kind is rule or fundamental, its quotation is verified, its direction is weighted, and it maps to a feature computable from the two-dimensional structure (TPSA, hydrogen-bond donors and acceptors, molecular weight, cLogP, rotatable bonds, heavy atoms, N-methyl count, D-residue count, cyclic flag). All other entries have weight zero and serve as retrieval context only.

**3.3.3 Sources and counts.** Five sources feed the layer. (a) *Imports of existing curated collections* (CycPeptMPDB, CREMP, CyclicPepedia, Macrocycle-DB and SweMacrocycleDB for structure-property data; PepBDB, Propedia and BioLiP2 for complexes), joined on stereo-aware InChIKey or PDB identifier, with parse and join rates recorded. (b) *The hand-verified set*: 107 entries (44 rules, 24 fundamentals, 11 cautions, 28 cards) in tiers T1 (60), T2 (36) and T-internal (11), from 45 external sources (41 open-access articles and 4 preprints) and 5 internal documents; all 107 quotations are machine-verified against stored full text, and 32 entries are weight-eligible (14 T1 and 18 T2; 28 permeability, 1 stability, 1 solubility, 2 other). The file's SHA-256 is `293688072468…`. (c) *Literature mining at scale*: an eight-billion-parameter open-weight instruction model run over open-access full text, with 40 queries over four topics (structure-property rules, fundamentals, prior-work statements, target-structure statements); every surviving entry passes the exact-quotation check; acceptance thresholds were fixed before extraction (judged precision at least 0.80 on a 100-entry audit sample drawn with a fixed seed; scaling only if the pilot projects at least 60% of the property-by-substructure coverage cells filled, a cell being filled with at least three verified entries from at least three papers), and planted-quote and altered-quote controls must all be rejected. (d) *Patent mining*, extraction only and without any freedom-to-operate analysis: candidate patents are selected from the SureChEMBL snapshot by a peptide-macrocycle filter (molecular weight 500 to 2,600, a ring of at least 12 atoms, at least three amide bonds in or attached to the ring), full texts are retrieved from public patent pages with a fixed delay and an identifying user agent, statements are extracted with the same schema and the same exact-quotation check against the retrieved text, and the resulting entries form the separate tier P. (e) *Structure mining*: BioLiP2 peptide-ligand entries and our earlier coordinate-based miner give 30,773 candidate complexes, of which 28,789 parse. Cyclisation (disulfide, head-to-tail, amide-like, thioether, ester-like, carbon-carbon link; ring size in residues) is re-detected from the deposited coordinates by distance tests, independently of any resource label; D residues and N-methylation are detected geometrically; backbone dihedral windows give descriptive turn classes (types I, I′, II, II′); interface contacts, hydrogen bonds, buried surface and hotspots are computed from coordinates. Of the parsed peptide-ligand rows 90% are linear peptides and are removed. After quality control and removal of duplicates (best resolution per target, sequence and closure class) the library holds 888 cyclic-peptide complexes over 451 targets, 802 of them with non-antibody receptors (closure: 366 disulfide, 187 head-to-tail, 140 amide-like, 78 carbon-carbon link, 69 thioether, 48 ester-like; 765 X-ray, 110 cryo-EM and 13 NMR structures; median resolution 2.2 Å; 527 with non-standard residues, 226 with at least one D residue, 118 with at least one N-methyl and 134 with a cis amide). Propedia and PepBDB were not imported: they derive from the same deposited structures and carry no cyclic-specific annotation, which is a scoping decision and not a verified equivalence.

**3.3.4 Leak safety and direction check.** Knowledge derived from labelled evaluation data must not enter a prior that is evaluated with that data. Data-derived priors are mined from the train group only (Section 4.2); the guard `assert_priors_clean` refuses a prior mined from any source that fits a stop or held-out verifier, and the earlier rule file mined from all laboratories fails it. Literature priors use no labels in their creation or weights. The scaled extraction flags an entry as a possible benchmark source when the first author and year of its paper match a CycPeptMPDB source, and flagged entries are excluded from priors used with held-out verifiers. Priors computed from a target's structures or ligands are excluded for that target in the retrospective arm; structure-derived priors are recomputed without the matching targets by accession (Section 3.3.6). As a consistency check, the direction of each literature rule was compared with the train laboratories only (2020_Townsend, 2,881 peptides; 2021_Kelly, 1,518; within-source Spearman against the raw PAMPA label, cluster bootstrap over stereoisomer groups, descriptive, no multiplicity correction). Of the 107 entries, 17 agree, 7 are mixed, none disagrees and 83 cannot be tested (cards, cautions and context entries make no directional claim, and non-permeability rules cannot be tested against a permeability label). N-methyl count (+0.50 and +0.53), HBD (−0.44 and −0.53), TPSA (−0.47 and −0.49) and cLogP (+0.29 and +0.49) agree in both laboratories; molecular weight and heavy-atom count change sign between them (−0.12 and +0.48), and D-residue count shows no signal at the count level (−0.04 and +0.02). Size and D-residue rules are therefore not weighted.

**3.3.5 Use in the model.** *Soft potentials in the decoder:* a weight-eligible directional rule contributes weight × sign × the standardised feature of the partial molecule to the logits, and a window rule contributes a hinge penalty on its stated thresholds, as a product of experts. Weights are a uniform prior (0.10 scaled by the entry's confidence level; zero for conflicts, cautions and context entries) and are not tuned. Three prior configurations form an experimental factor, and the structure-derived potentials of Section 3.3.6 are a separate ablation: hard rules only (the primary configuration); literature priors, which use the weight-eligible rules whose direction agreed in both train laboratories (15 rules; size and D-residue terms receive weight zero); and data-descriptive priors, the per-laboratory directions of Section 3.2. *Retrieval context in the prompt:* the store holds known peptides with measured or verifier-assigned values; a stereo-aware index (Morgan radius 2, 2,048 bits, chirality on) returns the k nearest neighbours with deterministic tie-breaking, and an embedding index over the frozen encoder supports novelty and diversity. The prompt builder places the retrieved peptides, their scores, provenance-tagged rule snippets and, for targets with a card, its pharmacophore text in the context, with a token-budget guard that drops the farthest hits first and raises an error rather than truncating silently. A blind-rule hook for the retrospective arm rejects, by document identifier, answer-set structure key and year cut-off, any retrieval that could leak held-out information; four violation types raise errors in tests, and on the arm-G store (4,634 exact rows from 230 documents spanning 1991 to 2025 and eight integrin targets) the newest held-out document was excluded in five of five queries. A wider store of 21,575 rows over 724 targets carries no document identifiers and cannot support the blind arm.

**3.3.6 Structure-derived priors and target cards.** From the library of Section 3.3.3(e) we compute bound-conformation priors on the primary set of 802 complexes with non-antibody receptors over 378 targets (a target is the UniProt set of the receptor chains). Each prior is tested for stability by leave-one-target-out: the total-variation distance (categorical priors) or the largest absolute change (rates) when one target is removed, with thresholds fixed before the run (at least 20 targets, median deviation at most 0.05, maximum at most 0.25). Stable priors are ring spans by closure type (disulfide median 10 residues, interquartile range 8 to 13, n = 301; head-to-tail 8, 7 to 11, n = 174; amide-like 7, 5 to 10, n = 137; thioether 12, 9 to 12, n = 67); the frequency of beta-turn types (a type I turn in 56.5% of disulfide-closed complexes, type I′ 9.0%, II 6.3%, II′ 7.3%); the position rates of N-methylation (4.7% at positions in contact with the target against 2.2% elsewhere) and D residues (5.3% against 6.9%, not enriched); and the fate of backbone NH groups (47% intramolecularly hydrogen-bonded, 10% bonded to the receptor only, 43% free). Interface-residue enrichment (isoleucine, tryptophan, phenylalanine enriched; glutamine, alanine, cysteine depleted) is not stable under leave-one-target-out (maximum deviation 0.50 in log2 units) and is exported with weight zero. Every prior carries the SHA-256 of the target set it was computed from (`419f8bf3d8dc…` for the primary set), and the computation accepts a list of accessions to exclude: for the retrospective arm the αvβ6 and PD-L1 accessions are removed, which also removes the αvβ3 targets that share the αV accession. The priors enter IH-LM as prompt snippets with provenance (ring spans, turn frequencies, N-methylation positions) and as ring-size soft potentials, log-probability tables per closure class with default weight 0.5 where stable and not tuned. They are population statistics that no single target changes, and they use no labels or affinities.

The 17 target cards report, for each target, the reference structure, the number of cyclic-peptide complexes in the library and the best template. Five targets have cyclic-peptide complexes (BAFF 5, FcRn 5, IL-17A 1, PD-L1 9, TNF-α 1). CD20's single complex is an antibody-epitope complex and the card says so. The library holds no cyclic-peptide complex for α4β1, α4β7, αvβ6, C5, CD40, IL-17F, IL-23, IL-2Rα, IL-6R, LFA-1 or GRPR; their cards carry an explicit no-structure flag, and any prior for them is transferred from other targets. For αvβ6 this does not prove that no such complex exists in the PDB, because complexes in which the macrocycle is deposited as a hetero-ligand fall outside both resources.

### 3.4 Training IH-LM

#### 3.4.1 Initialisation and data

IH-LM is initialised from the ChemFM-1B checkpoint (about 970 million parameters; arXiv:2410.21422). Adapter fine-tuning uses public peptide and macrocycle SMILES drawn from CREMP, NPAtlas, COCONUT, a capped generated-peptide pool and ChEMBL (at most 10% of tokens), with every CycPeptMPDB structure (7,334 peptides in its publication) and every compound of the frozen binding benchmark excluded by flat-structure key and Tanimoto ≥ 0.9 (the corresponding union filter removed 8,983 molecules, 0.312%, from the ChEMBL corpus used for earlier work). Composition and counts are in Table 6. The verifiers of Section 4.2 are fitted on CycPeptMPDB labels, but the language model never trains on those structures. The need for this stage is measured: an earlier 25.5-million-parameter atom-level model trained mostly on ChEMBL (1.7% macrocycles) generated molecules that were 66.4% valid, 10.2% macrocycles, with a mean of 0.078 N-methyl amides per molecule against 2.67 in real peptides; the corresponding content of the initialisation checkpoint is reported in Table 5.

#### 3.4.2 Fine-tuning under the mask

The adapter is trained with the decoding mask applied (Section 3.2) on the corpus of Table 6; the diagnostics are reported in Table 5.

#### 3.4.3 Preference stage

*Diagnosis.* Two earlier feedback runs barely moved their policies. A group-relative policy-gradient run had a fraction of zero-standard-deviation reward groups of about 0.95 to 1.0 and a KL divergence from the reference of about 0.001: a binary reward combined with a start policy that is consistent per prompt gives no within-group variance, so the update learns from roughly 5% of the batch. In a direct-preference run the relative weight change was 0.00096 and 0.0017 for two variants, and 70.8% of the valid samples of the unified peptide model were memorised training peptides. The cause lay in the study design, not in the capability of the method.

*Update.* The preference updater (i) computes graded rewards from continuous train-verifier scores; (ii) forms rank-based group advantages (ties averaged, no division by the group standard deviation); (iii) requires a minimum number of valid members per group and a non-trivial score spread and reports dropped groups; (iv) forms pairs of the i-th best against the i-th worst with a score margin and applies a DPO loss with a KL penalty to the reference; and (v) applies a gate from round 3: if KL to the reference is below 0.01 or the relative adapter weight change is below 0.005, the learning rate or rank is raised once and the run then stops. A control that can fail is built in: on a tabular toy policy with a concentrated start, the legacy binary recipe has more than 90% zero-variance groups, a gain near zero and KL near zero, whereas the graded updater has a gain above 0.10 and KL above 0.01; on a broad start the legacy recipe learns, so the stall comes from the variance structure and not from a defective legacy implementation. Both directions are asserted in tests. The group-size parameter counts valid members: with an unconstrained model at validity 0.67 to 0.75 a nominal group of 32 holds fewer than 16 valid members in most groups; the rule automaton removes this waste because every sample is valid by construction.

#### 3.4.4 Goodhart-gap stopping

The monitor tracks the best-so-far set by train score (size set from the first batch) and the independent stop-verifier score of that set, smooths both, and stops when the gap, in units of the round-0 standard deviation, exceeds a threshold for consecutive rounds; the restore point is the maximum of the stop-verifier gain. The held-out verifier does not appear in its signature. Parameters were fixed on development simulations before test seeds were run: top fraction q = 0.10, threshold τ = 1.0, patience 4, tolerance 0.05, warm-up 2, smoothing 3.

*Operating characteristics on planted environments* (simulations; 400 test seeds per environment; evolution-strategy optimisation in ten dimensions with a hackable proxy). In the hackable environment the monitor retained 0.794 [0.776, 0.811] of the peak held-out gain against 0.560 [0.556, 0.563] without a monitor, stopping a median of 3 rounds before the held-out peak, with a missed-hack rate (retained fraction below 0.75) of 0.273. In the benign environment it retained 0.999 with a false-stop rate of 0.000 (Wilson 95% upper bound 0.010). A simpler monitor retained 0.447 in the hackable environment. When the stop verifier shares the train verifier's exploit the monitor behaves like no monitor (0.560). The pre-registered verdict was INCONCLUSIVE: the missed-hack rate exceeded the 0.20 criterion and the median delay of −3 rounds fell outside the [−2, +4] window; criteria were not changed after test results. A documented limitation is the winner's curse: best-so-far statistics grow by selection alone when the train score is noisy, so a plateau can look like a widening gap, and the monitor assumes the train and stop verifiers measure related quantities. Its effect in the peptide loop is reported in Table 8.

### 3.5 Verifiers and source groups

The verifier ladder, the three roles (train, stop, held-out), the source-group definition and the verifier-quality floors define both the training signal and the evaluation, and are specified once in Section 4.2.

### 3.6 Loop orchestration

A round consists of sampling N = 100 to 200 molecules from the compiled decoder, querying the train verifiers within the remaining budget (duplicates, invalid molecules and rule failures are not charged), forming preference pairs, updating the adapter, adding scored molecules to the retrieval store, and updating the monitor. Checkpoints are atomic and a resumed run reproduces the uninterrupted oracle log exactly (tested). Logs contain hashes of molecules, never structures, and are uploaded every 60 seconds. On a planted-optimum test problem (ten seeds, 300-call budget) the loop found the optimum in 7 of 10 seeds against 1 of 10 for random search, and a shuffled-reward control gave no gain (−0.0015, t-interval [−0.020, 0.017]); this verifies the harness, not anything about peptides.

---

## 4. Evaluation

This section specifies the study completely enough to replicate it. The protocol is pre-registered, with amendments dated and committed before the data they affect was read, and applies the decision rules of the companion paper, which we summarise because they govern every choice below: (1) state the minimal detectable difference first, with its standard-deviation source and real cluster count; (2) set margins from decisions, never after seeing intervals; (3) report the interval against the margin; (4) use the independent cluster as the unit of inference; (5) every control must be able to fail and to pass; (6) every instrument, including the validity gate, needs a positive control; (7) amend only for errors, before the data an amendment affects is read, and count the versions; (8) one multiplicity family with a fixed denominator; (9) run data-quality gates before any model; (10) word claims by evidence tier.

### 4.1 Oracle-budget protocol

*Budget and metric.* Each optimiser interacts with a train verifier (the oracle) for at most B calls; the pilot uses B = 1,000 and the primary study B = 3,000. *Scale.* Every verifier returns a z-score against the generation space, z = (raw − μ_ref)/σ_ref, where μ_ref and σ_ref are computed from 1,500 random rule-satisfying draws of the library sampler under the hard rules C; scores are not clipped. Stop and held-out verifiers use the same construction with their own raw scores. The score of a run is the AUC-top-10 in these reference standard-deviation units (SD-AUC): the area under the curve of the mean of the ten best oracle scores seen so far against the number of oracle calls, divided by B (a run that finds its best molecules early scores higher). A percentile scale against natural peptides saturates: on tuning seeds, tuned baselines reached top-10 mean percentiles of 0.979 to 0.986 at B = 1,000 and random library sampling 0.886 to 0.944, which leaves no room for a margin of practical size; the generation-space scale does not saturate. SD-AUC measures improvement over blind sampling from our own library sampler, not an absolute chemical quality. *Charging rules.* A call is charged only for a valid, rule-satisfying, previously unseen molecule; invalid molecules, duplicates (by canonical isomeric SMILES) and proposals that fail the hard rules are not charged but are counted, and the number of proposals is capped at 20 × B. All methods apply the same hard-rule filter C (Section 3.2). *Starting set.* Seed molecules are 300 rule-satisfying peptides from the train group, drawn deterministically. *Outputs per run.* The oracle log (hashes only), the final top-10, the held-out verifier's score of the final top-10 (applied once, after the run) and the stop verifier's score of the same set (the Goodhart-gap diagnostic).

### 4.2 Verifier ladder, source groups and verifier quality

Each objective family has a *train* verifier (the budgeted oracle), a *stop* verifier (used only by the stopping monitor, never as an oracle) and a *held-out* verifier (applied only to the final top-10). A consistency check enforces distinct names, correct roles and disjoint fitting-source sets across the three, and the harness refuses to use a held-out verifier as an oracle.

**Table 1. Pilot-stage verifier families.**

| family | train (oracle) | stop | held-out |
|---|---|---|---|
| F1 physicochemical rule | fixed formula: −0.01·TPSA − 0.15·HBD + 0.20·logP − 0.10·max(0, rotatable bonds − 10), no fitting | random forest fitted on group S | minimum polar SASA over four ETKDG and MMFF conformers |
| F2 permeability model | gradient-boosted trees fitted on group A (within-source z-scored PAMPA; Morgan counts and descriptors) | random forest fitted on group S | Tanimoto-kernel ridge fitted on group B |

A structure family (Boltz confidence against a target) and a free-energy audit are stage 3 and outside the pilot.

**Source groups (version 2).** Sources are the laboratory or paper identifiers of CycPeptMPDB with at least 20 labelled PAMPA peptides after correction of source assignments (20 sources, 6,784 peptides). The two largest, 2020_Townsend (2,881 peptides, 42.5%) and 2021_Kelly (1,518, 22.4%), form the train group A (4,399 peptides, 64.8%); under the first grouping the train, stop and held-out verifiers were each effectively a single-laboratory model (Townsend 90% of train, Kelly 80% of stop, two papers 91% of held-out). The remaining 18 sources are assigned by a snake draft on size to the stop group S (nine sources, 1,269 peptides, 18.7%; 2013_CHUGAI is 69.2% of it) and the held-out group B (nine sources, 1,116 peptides, 16.5%; 2016_Furukawa is 59.3% of it). Membership has SHA-256 `be8a9945f504…`. A laboratory is a paper identifier here, so two papers from one laboratory can fall in different groups. A robustness arm re-runs the baselines on the first grouping with the same tuned configurations and evaluation seeds only; nothing is selected on it (Table 12).

**Verifier-quality floors.** Floors were fixed before any baseline ran: the stop and held-out permeability verifiers must reach a mean leave-one-source-out Spearman of at least 0.15 over at least five evaluable sources, and the physics held-out at least +0.10 against measured z-scores on a fixed 120-peptide sample. They derive from the leave-labs-out skill measured earlier for gradient-boosted models (about 0.22 to 0.25), discounted for smaller fitting groups. A verifier below its floor is declared too weak to rank and its family contributes no stop or held-out evidence. For the physics held-out, which did not reach its floor, one replacement attempt was registered before it ran: a Boltzmann-weighted polar solvent-accessible surface area over 60 ETKDG conformers per peptide (298.15 K), evaluated on all group-B peptides within a fixed time box with a per-molecule limit of 120 s. It passes if the pooled Spearman against the within-source z-score is at least +0.10 and the lower bound of a 95% source-cluster bootstrap interval exceeds 0; it is evaluable only if at least 600 peptides covering at least 7 of the 9 sources complete, and otherwise the test is VOID. Its stated consequence for a failed or void test is that the family has no admissible held-out verifier and the pilot gate is INCONCLUSIVE by design. No further replacement was allowed. The measured outcomes are in Section 5.2.

### 4.3 Baselines and fair tuning

The other generators and optimisers are baselines: a random library-sampling floor; library enumeration with a gradient-boosted surrogate ranking; an edit-operator genetic algorithm (N-methyl add and remove, D-flip, residue swap, ring change) with the same filter; a SELFIES genetic algorithm; and Tanimoto-kernel Gaussian-process Bayesian optimisation with an upper-confidence acquisition (kappa 1). A REINVENT-style reinforcement-learning arm and a language-model-as-operator arm (an unfine-tuned model proposing crossover and mutation) are part of the required set. A Graph-GA is replaced by the SELFIES GA plus the edit-operator GA (declared deviation). *Tuning protocol.* Every method is tuned on the other family's train objective (configurations for F1 are chosen on F2's train objective and vice versa) on seeds 100 to 102 with grids of three to eight configurations; the best mean SD-AUC wins; the chosen configurations are frozen in a file before any evaluation seed runs. The design had called for disjoint development objectives with 20 configurations; with two families, cross-family tuning keeps tuning and test objectives disjoint at a smaller grid, and this is declared. IH-LM's own hyperparameters are tuned the same way, on development objectives and never on a held-out verifier.

### 4.4 Controls and what each can detect

**Table 2. Controls.**

| control | construction | detects | pass rule |
|---|---|---|---|
| shuffled reward | hash-noise verifier | a method that "improves" without a signal; harness bias | every method's SD-AUC inside the random-library floor interval |
| planted optimum | its own [0, 1] score = max(0, 1 − (\|N-Me − 4\| + \|ring − 20\|/4)/4) | an optimiser or decoder that cannot find a known optimum | every non-floor method reaches at least 0.9 of the optimum top-10 mean within B |
| copy-seed | the oracle sees only the seeds | counting errors in the budget curve | plateau at the best seed score |
| randomly initialised model | same architecture, no pretrained weights | value of the initialisation | reported with the verdict |
| no rule compilation | post-hoc filtering; wasted oracle calls counted | the effect of the mask | reported |
| no knowledge augmentation | no retrieval context, no soft priors | the effect of the knowledge layer | reported |
| no preference stage | frozen adapters, best-of-B | the effect of feedback | reported |
| no stopping monitor | training to the end | the effect of the monitor | reported |
| unaugmented backbone | initialisation checkpoint, no adapter, mask, retrieval or feedback | total gain over the base model | reported |

A control that fails is reported with the verdict. A control fixed at zero by construction, or with a threshold below the null standard error, is not a control (companion paper).

### 4.5 Seeds, unit of inference and intervals

Evaluation uses seeds 0 to 9 per method per family (20 for the primary contrast if the pilot variance requires it). The unit of inference is the objective family; with two families in the pilot, family-cluster inference is not available (n = 2) and conclusions are conditional on those constructions; the primary study uses three families (physicochemical rule, permeability model, structure) and an objective-cluster bootstrap. Within a family, paired contrasts (same seed) use the wider of two intervals: the percentile bootstrap interval of the mean over seeds (5,000 resamples) and the t-interval on n − 1 degrees of freedom. Interval types are labelled everywhere. The primary contrast is IH-LM minus the best baseline on the held-out verifier, with the best baseline selected on the evaluation seeds (conservative for IH-LM), and the train-verifier contrast reported beside it.

### 4.6 Margin, minimal detectable difference and pass probability

*Margin.* In each family the margin is m_f = 0.10 × (SD-AUC of the best baseline − SD-AUC of random library sampling), computed from the baseline evaluation seeds and committed before any IH-LM run: a method that closes less than a tenth of the gap that the best baseline closes over random search would not change which method we recommend. *Detectable difference.* With n paired seeds and a paired standard deviation SD of the method differences, SE = SD/√n and the minimal detectable difference at 80% power and two-sided α = 0.05 is MDE80 ≈ 2.8·SE. The pass rule of Section 4.7 requires the mean to be at least m_f and the lower bound of the interval to exceed 0, so its effective margin is max(m_f, t·SE) with t ≈ 2.26 for n = 10 (about 0.7 to 0.8 × MDE80). *Pass probability.* If a true gain δ (in SD-AUC units) appears on a verifier of reliability λ_H (its leave-one-source-out Spearman against the real label) attenuated to about λ_H·δ, the probability of passing is P(Z > (max(m_f, t·SE) − λ_H·δ)/SE) for a standard normal Z. An amendment committed before any IH-LM number is read states SD from the baselines, m_f, MDE80 for ten seeds, the effective margin, and this probability for δ equal to one and two margins and λ_H in {0.229, 0.10, 0} (Table 7); at λ_H = 0 the probability of a held-out pass equals the false-positive probability whatever the true gain. If MDE80 exceeds twice the margin, the screen is declared low-power in advance and a miss is worded "no gain detectable above the minimal detectable difference", never "no gain".

### 4.7 Gate and frozen vocabulary

The margin m_f of Section 4.6 is the smallest improvement that would change which method we recommend. **GO**: in every family the mean difference is at least m_f and the lower bound of the wide interval is above 0, on held-out verifiers, with the controls that can fail having passed. **NO-GO-detectable**: in at least one family the upper bound of the wide interval is below m_f. **INCONCLUSIVE**: otherwise; a compute decision taken from an INCONCLUSIVE screen is called a judgement call. The full claim H-AA additionally requires a win in at least two of three families and a win in the retrospective arm. The stage-1 stop rule is pre-registered: if IH-LM's point estimate of SD-AUC is not above the best baseline's at the pilot budget, on both train and held-out verifiers, the study stops there and reports NO-GO-detectable or INCONCLUSIVE according to the interval against the margin. If a family has no admissible held-out verifier, that family cannot support a GO and the registered ceiling is INCONCLUSIVE. This applies to family F1 (Section 5.2): the pilot gate cannot exceed INCONCLUSIVE, and the held-out evidence rests on family F2. Every held-out claim is worded with the verifier attenuation of Section 4.6, and the F2 held-out is used as an independent model check (does a gain transfer to a differently fitted model), not as a measure of real permeability.

### 4.8 Arm G: blind retrospective recovery

Arm G needs no verifier. For each target with enough exact potency measurements, the top-quartile binders by potency form the answer set and are held out; the context contains a few non-answer binders; the metric is the fraction of answer-set compounds with a generated stereo-aware near neighbour (Tanimoto ≥ 0.5) among N = 1,000 samples, plus scaffold-level recovery. Baselines are seeded identically. Retrieval stores and knowledge priors are rebuilt without the held-out documents under the blind rule of Section 3.3.5, and any prior computed from a target is excluded for that target. Models pretrained on large chemistry corpora may have seen most ChEMBL binders (the cut-off is unverified), so arm G uses post-cutoff documents only (the data carry document years to 2025) or is reported as contaminated.

### 4.9 The calibrated validity gate

The companion paper's validity gate tests whether the labels of a binding benchmark can be predicted from compound-only features (no-target, typicality, censoring and assay-source controls, about 24 per benchmark) and returns BIASED, UNVERIFIABLE, NOT_EQUIVALENT or VALID. Its positive control measured that, on truly clean planted benchmarks, the registered gate flags 24.5% (26 families) and 32.5% (14 families) as biased, certifies 61% and 2.5% as valid, and detects planted shortcuts of AUROC 0.60 to 0.65 with probability about 1.00. The calibrated gate replaces the percentile bootstrap by a null-calibrated maximum statistic: each control's departure from 0.5 is standardised by its interval, its dispersion is calibrated on permutation-null records of the same benchmark type, the verdict statistic is the maximum standardised departure, and its critical value is the 0.95 empirical quantile of that maximum under the null; the equivalence margin is derived from the design's own power as half the minimal detectable difference at F families (0.0553 at F = 26) in place of the registered ±0.05 chosen post hoc. Acceptance criteria were fixed before any validation run, on fresh seeds and constructions separate from the calibration data: a false-alarm rate on planted-valid benchmarks of at most 0.10 (exact 95% upper bound at most 0.15) at 20, 26 and 47 families; detection of at least 0.80 at planted AUROC 0.65 and at least 0.90 at 0.70; and P(VALID | shortcut at 0.65) at most 0.05. Measured values are in Table 13.

### 4.10 Audits of final candidates and staging

Stage 3 applies orthogonal checks never used as rewards: conformer-ensemble 3D polar surface area on the top-10 of each run; Boltz confidence on the final top-5 against a target; and a free-energy audit of the best arm against the best baseline on one target, only if the primary study passes. These are reported with the caveat that confidence scores saturate (cofold confidence against physics correlated at −0.04 in our earlier work) and share biases with their training data. Stage 0 measures timing, the backbone's own content, mask correctness and baselines; stage 1 is the pilot (B = 1,000, two families, ablations first for no-rules and no-feedback); stage 2 is the primary study (B = 3,000, three families, ten seeds); stage 3 is the audits.

---

## 5. Results

### 5.1 Unconditioned language models against simple generators (pilot)

In a pre-registered pilot, three language models, none trained for this constraint set, were used as seeded generators and compared with tuned simple generators on the number of constraint-satisfying, unique, novel molecules per 1,000 samples (Y) under the constraint set C.

**Table 3. Constraint yield of seeded generators.**

| generator | seeds | Y per 1,000 | t-interval | validity |
|---|---|---|---|---|
| monomer-library enumeration | 5 | 704.6 | 681.8 to 727.4 | 1.000 |
| edit-operator GA | 5 | 414.2 | 396.4 to 432.0 | 1.000 |
| ChemFM-1B, unaugmented (reduced allocation) | 3 | 294.3 | 281.8 to 306.8 | 0.980 |
| earlier in-house 25.5 M atom-level model | 3 of 5 | 284.0 | 232.7 to 335.3 | 0.775 |
| PeptideCLM-2 (masked infilling) | 5 | 237.2 | 226.9 to 247.5 | 0.847 |

Each language model differs from the enumerator by −408 to −467 per 1,000, with intervals far below zero (paired by run seed). Controls behaved as registered (copy-seed Y = 0; randomly initialised models validity 0). The result is a property of the metric as much as of the models, and it motivates the rule-compiled decoder and the choice of objectives that the rules do not determine.

### 5.2 Verifier quality

The stop verifier met its floor (mean leave-one-source-out Spearman 0.363 over nine sources). The held-out permeability verifier met the registered mean-based floor (mean 0.229 over nine sources) only through small sources and ranks its largest laboratory essentially not at all (sample-size-weighted Spearman −0.005). The physics held-out verifier did not reach its floor (−0.008 against +0.10 on a 120-peptide sample). The train verifier ranks the held-out sources better (mean Spearman 0.302) than the held-out verifier ranks its own.

The registered replacement test for the physics held-out (Section 4.2) was VOID: 528 of the 1,116 group-B peptides completed (588 failed or reached the per-molecule limit) and they covered 5 of the 9 sources, against the required 600 peptides and 7 sources. The failures are systematic, not random: the peptides that could not be embedded are larger (median 67 heavy atoms against 51 for those that completed), and no peptide completed for four sources. Consequently the physics family has no admissible held-out verifier, the pilot gate is INCONCLUSIVE by design (Section 4.7), and the held-out evidence rests on the permeability family, a weak ranker. On the completed subset the pooled Spearman between the score and the label is 0.225 (95% source-cluster bootstrap 0.163 to 0.418); this number is descriptive, is biased by the selection of smaller peptides from five sources, and is not a pass. It differs markedly from the −0.008 of the random 120-peptide sample, so the relation of the physics score to the label depends on which peptides can be embedded at all; this reflects coverage and selection and is not a verified property of the verifier.

**Table 4. Verifier quality (leave-one-source-out Spearman).**

| verifier | mean | sample-size-weighted | sources | floor | met |
|---|---|---|---|---|---|
| stop (random forest, group S) | 0.363 | 0.357 | 9 | 0.15 | yes |
| held-out F2 (kernel ridge, group B) | 0.229 | −0.005 | 9 | 0.15 | yes (mean-based) |
| held-out F1 physics (120-peptide sample) | −0.008 | — | — | 0.10 | no |
| held-out F1 physics, Boltzmann-weighted replacement (528 of 1,116 peptides, 5 of 9 sources; descriptive, selection-biased) | 0.225 | — | 5 | 0.10 | void |
| train F2 on group B sources | 0.302 | — | — | — | — |
| train F2 on group S sources | 0.298 | — | — | — | — |

### 5.3 Rule-compiled decoding and fine-tuning under the mask

Fifteen retrieval tests and thirty-eight orchestrator and harness tests pass, including blind-rule controls that raise on violation; the preference-updater controls pass in both directions; the monitor's simulated operating characteristics are in Section 3.4.4.

**Table 5. Decoding automaton and fine-tuning.**

| quantity | value |
|---|---|
| false-prune rate on the golden set (required 0) | — |
| agreement of reference and vectorised implementations | — |
| mask overhead per decoding step | — |
| rule satisfaction of 5,000 masked samples (required 1.0) | — |
| validity / uniqueness / diversity of masked samples | — |
| KL divergence, masked to unmasked model | — |
| initialisation checkpoint: mean N-methyl amides, D-residue fraction, macrocycle fraction | — |
| after 200 adapter steps under the mask: validity, diversity, KL | — |

**Table 6. Fine-tuning corpus.**

| source | structures | real fraction | after exclusions |
|---|---|---|---|
| CREMP (without CycPeptMPDB-linked entries) | — | — | — |
| NPAtlas | — | — | — |
| COCONUT macrocycle subset | — | — | — |
| generated-peptide pool (capped) | — | — | — |
| ChEMBL (at most 10% of tokens) | — | — | — |

### 5.4 Comparison with baselines

**Table 7. Stage-0 baselines, margin and detectable difference.**

| family | method | SD-AUC train (mean, wide interval) | SD-AUC held-out (mean, wide interval) | paired SD | margin m_f | MDE80 (10 seeds) | P(pass) at δ = m_f / 2 m_f for λ_H = 0.229 / 0.10 / 0 |
|---|---|---|---|---|---|---|---|
| F1 | each baseline | — | — | — | — | — | — |
| F2 | each baseline | — | — | — | — | — | — |

**Table 8. Stage-1 comparison, IH-LM minus best baseline.**

| family | held-out verifier (wide interval) | train verifier (wide interval) | Goodhart gap | verdict |
|---|---|---|---|---|
| F1 | — | — | — | — |
| F2 | — | — | — | — |

Figure 1 shows the top-10 mean against oracle calls for all methods, in train and held-out panels, per family.

**Figure 1.** Budget curves: top-10 mean against oracle calls, train and held-out panels, per family (—).

### 5.5 Ablations

**Table 9. Ablations (held-out SD-AUC, difference from full IH-LM).**

| variant | F1 | F2 |
|---|---|---|
| full IH-LM | — | — |
| without knowledge augmentation | — | — |
| without rule compilation (post-hoc filter) | — | — |
| without the preference stage | — | — |
| without the stopping monitor | — | — |
| hard rules only | — | — |
| literature priors (15 rules) | — | — |
| structure-derived ring-size potentials | — | — |
| data-descriptive priors | — | — |
| unaugmented backbone | — | — |
| randomly initialised model | — | — |

### 5.6 Retrospective recovery

**Table 10. Arm G.**

| target | method | recovery fraction | scaffold recovery | contamination flag |
|---|---|---|---|---|
| each target | IH-LM and baselines | — | — | — |

### 5.7 Audits and robustness

**Table 11. Audits of final candidates.**

| audit | IH-LM | best baseline |
|---|---|---|
| 3D polar surface area, top-10 | — | — |
| Boltz confidence, final top-5 | — | — |
| free-energy audit | — | — |

**Table 12. Robustness on source-group version 1.**

| family | IH-LM minus best baseline (held-out) | verdict |
|---|---|---|
| F1 | — | — |
| F2 | — | — |

**Table 13. Calibrated validity gate.**

| quantity | registered gate | calibrated gate | criterion |
|---|---|---|---|
| false-alarm rate, 20 / 26 / 47 families | 0.245 at 26; 0.325 at 14 | — | ≤ 0.10 (upper 95% ≤ 0.15) |
| detection at planted AUROC 0.65 / 0.70 | ≈ 1.00 at 0.60 to 0.65 | — | ≥ 0.80 / ≥ 0.90 |
| P(VALID) on clean benchmarks | 0.61 at 26; 0.025 at 14 | — | reported |
| P(VALID \| shortcut at 0.65) | — | — | ≤ 0.05 |

---

## 6. Discussion

**Rule-compiled decoding.** The pilot showed that a metric on which constraints hold by construction favours library enumeration. We compile the same constraints into IH-LM's decoder, so that the model carries the same guarantee, and we fine-tune under the mask so that the learned distribution is conditional on the rules. The comparison then turns on what the rules do not determine, which is what the held-out-verifier objectives measure. The ablation without rule compilation (post-hoc filtering) quantifies both the effect on the objective and the oracle calls wasted on rule failures.

**Knowledge augmentation.** Knowledge enters IH-LM by two routes whose effects can be separated: as retrieved context in the prompt and as soft priors on the logits. The ablations without knowledge augmentation, the three prior configurations (hard rules only, literature, data-descriptive) and the structure-derived potentials isolate each route. Priors enter with provenance, so a change in held-out performance can be traced to rules whose sources are known and whose quotations are machine-verified. The knowledge layer is also reusable outside this model.

**Reporting.** The outcome is reported in the frozen vocabulary of Section 4.7, together with the ablations, the training diagnostics (zero-variance fraction, KL to the reference, adapter weight change), the monitor's operating characteristics and the measured verifier quality, whichever way the pre-registered rule falls. A GO supports the claim that IH-LM uses a fixed oracle budget more efficiently than the tuned simple optimisers on independent held-out verifiers; a NO-GO-detectable excludes the margin in at least one family; an INCONCLUSIVE states that the screen cannot distinguish a gain of the target size from none, as the amendment on the minimal detectable difference records in advance.

---

## 7. Limitations

**Scope of verifier-based evidence.** All verifiers are computational. The laboratory-fitted ones inherit the structure of one public database in which two laboratories dominate, and the physics verifier is correlated with the train formula by construction since both reward low polarity. A GO would not show that the designs are active, permeable or synthesisable, and the paper does not claim wet-lab validation. The monitor's operating characteristics (Section 3.4.4) come from simulations and do not describe real verifiers.

**Verifier quality limits held-out claims.** The held-out physics verifier did not reach its pre-registered floor, and its single registered replacement test was void because only 528 of 1,116 peptides (5 of 9 sources) could be embedded, with the failures concentrated on larger molecules. The physics family therefore has no admissible held-out verifier, the pilot gate cannot exceed INCONCLUSIVE, and the held-out evidence rests on the permeability family, whose held-out verifier ranks its largest laboratory essentially not at all while the train verifier ranks the held-out sources better than it does (Section 5.2). A gain on the permeability held-out verifier is attenuated by its reliability, and held-out claims are worded accordingly. This is a property of the available public data, stated before the comparison.

**The enumeration advantage.** The constraint-yield metric favours library enumeration because the constraints are satisfied almost by construction. Rule compilation and the choice of objectives address this, but enumerators remain strong on any objective that rewards the property classes they build in, so enumeration baselines (with and without a surrogate) appear in every comparison.

**Group structure.** The train verifiers are fitted on two laboratories, which makes the train objective laboratory-specific. The stop and held-out groups are each dominated by one laboratory (CHUGAI about 69% of stop; 2016_Furukawa about 59% of held-out). With two objective families the primary inference is conditional on those constructions, public permeability lab-shift tests are power-limited (companion paper), and a gain smaller than the minimal detectable difference cannot be excluded.

**Pretraining overlap.** The initialisation checkpoint and the encoder were pretrained on large chemistry corpora whose overlap with CycPeptMPDB and with the binding benchmark has not been checked (no corpus snapshot was available to us). Novelty against those corpora is not checked. Arm G mitigates this with post-cutoff documents; IH-LM does not train on labelled structures, but the verifiers' fitting sets overlap with public sources the models may have seen.

**Soft rules.** No mined soft rule met the validation criteria on the two training laboratories, so the primary configuration uses hard rules only. The literature priors are checked for direction against the same two laboratories, which are laboratories known for heavily N-methylated series; agreement is evidence of consistency, not of causation. Whether the priors help is answered by the ablation of Table 9.

**Structure-derived knowledge.** The library has no binding-affinity annotation (0 of 818 distinct entries carry one in the structure database), so no ligand-efficiency proxy could be built. The binding-mode numbers on the cards are medians computed from the deposited structures; no paper was opened for any card, and the cited DOIs are the structure database's primary-citation metadata. The library is dominated by crystallisable, soluble, disulfide-rich binders (765 of 888 complexes are X-ray structures), its coverage is bounded by the peptide class of BioLiP2 and our earlier miner, cyclisation and D-residue and N-methyl calls are geometric and depend on model quality, and the priors describe what is deposited, not what binds best; they are not validated as design aids except through the ablation of Table 9.

**Knowledge-layer quality.** Exact quotations guarantee fidelity of the source sentence, not correct interpretation. The statements of the hand-verified set were drafted with an AI assistant from opened sources and have not been independently judged against their quotations, and its 36 tier-T2 entries (reviews' summaries, restated results, textbook rules, background statements) rest on underlying primary sources that were not re-opened. The scaled extraction uses an eight-billion-parameter open-weight model, and its precision is measured on an audit sample. Rules from papers whose data are in CycPeptMPDB are flagged and excluded from priors used with held-out verifiers.

---

## 8. Data and code availability

Pre-registrations, dated amendments, code, tuned configurations, per-run oracle logs (molecule hashes) and result files for every number in this paper are archived with the paper. Source-group membership has SHA-256 `be8a9945f5042b97afa177d85c23f80b9343c933722c54f02188bd75b276db1c`; the knowledge file used in this paper has SHA-256 `29368807246824222aa8ea860ff69adce1393ef9976a5c8fbb6091c5d0fe6951`. All experiments ran on rented cloud instances with a single-writer storage prefix per run, a wall-clock cap and a cost log per instance.

---

## References

Brown N, Fiscato M, Segler MHS, Vaucher AC. GuacaMol: benchmarking models for de novo molecular design. arXiv:1811.09621 (J Chem Inf Model 2019). Polykovskiy D, et al. Molecular Sets (MOSES). arXiv:1811.12823 (Front Pharmacol 2020). Gao W, Fu T, Sun J, Coley CW. Sample efficiency matters: a benchmark for practical molecular optimization. arXiv:2206.12411 (NeurIPS 2022 Datasets and Benchmarks). Tripp A, Hernández-Lobato JM. Genetic algorithms are strong baselines for molecule generation. arXiv:2310.09267. Thomas M, O'Boyle NM, Bender A, de Graaf C. Re-evaluating sample efficiency in de novo molecule generation. arXiv:2212.01385. Garcia-Ortegon M, et al. DOCKSTRING. arXiv:2110.15486 (J Chem Inf Model 2022). Buttenschoen M, Morris GM, Deane CM. PoseBusters. arXiv:2308.05777. Harris C, et al. PoseCheck. arXiv:2308.07413. Gao L, Schulman J, Hilton J. Scaling laws for reward model overoptimization. arXiv:2210.10760. Moskovitz T, et al. Confronting reward model overoptimization with constrained RLHF. arXiv:2310.04373. Rafailov R, et al. Direct preference optimization. arXiv:2305.18290. Geylan G, et al. PepINVENT. arXiv:2409.14040 (Chem Sci 2025). Kong X, et al. Full-atom peptide design with geometric latent diffusion (PepGLAD). arXiv:2402.13555. Tang S, Zhang Y, Chatterjee P. PepTune. arXiv:2412.17780. Chen T, et al. PepMLM. arXiv:2310.03842. Rettie SA, et al. Cyclic peptide structure prediction and design using AlphaFold. bioRxiv 10.1101/2023.02.25.529956. Rettie S, et al. Accurate de novo design of high-affinity protein binding macrocycles using deep learning. bioRxiv 10.1101/2024.11.18.622547 (Nat Chem Biol 2025). Pacesa M, et al. BindCraft. bioRxiv 10.1101/2024.09.30.615802. Bryant P, Elofsson A. EvoBind. bioRxiv 10.1101/2022.07.23.501214. Wang H, et al. MolLEO. arXiv:2406.16976. Guo J, Schwaller P. Saturn. arXiv:2405.17066. Kusner MJ, Paige B, Hernández-Lobato JM. Grammar variational autoencoder. arXiv:1703.01925. Krenn M, et al. SELFIES. arXiv:1905.13741. Willard BT, Louf R. Efficient guided generation for large language models. arXiv:2307.09702. Mündler N, Dekoninck J, Vechev M. Constrained decoding of diffusion LLMs with context-free grammars. arXiv:2508.10111. Narayanan SM, et al. Training a scientific reasoning model for chemistry (ether0). arXiv:2506.17238. Ouyang M, et al. LLMol. arXiv:2607.19044. Li X, et al. RePO. arXiv:2603.05900. Amirahmadi A, et al. A decoupled alignment kernel for peptide membrane permeability predictions. arXiv:2511.21566. Zhang et al. PepBenchmark. ICLR 2026. Feller AL, Wilke CO, et al. PeptideCLM-2. J Chem Inf Model 2026. ChemFM-1B. arXiv:2410.21422.
