# Survey: how generative models for molecules and peptides are evaluated, and which practices are valid versus gameable

Date: 2026-10-31 (read-only literature survey; nothing committed, no compute, no paid APIs).

Method note. For each item below I opened the primary source (arXiv/bioRxiv PDF downloaded and text-extracted, or a publisher/Crossref record) in this session. Numbers are copied from the table or sentence named next to them. Anything I could not open is listed under UNVERIFIED (section 8) and is not used as evidence in sections 1-7. Where I only saw a preprint, I say so; I did not open published versions unless stated.

---

## 1. Distribution-learning and goal-directed benchmarks

### 1.1 GuacaMol
- Brown N, Fiscato M, Segler MHS, Vaucher AC. "GuacaMol: Benchmarking Models for De Novo Molecular Design." arXiv:1811.09621v2 (26 Feb 2019). https://arxiv.org/abs/1811.09621 . (The opened PDF is the arXiv version; the J. Chem. Inf. Model. 2019, 59(3):1096-1108 citation is taken from the reference lists of Tripp & Hernandez-Lobato and of MOSES, both opened.)
- Distribution-learning metrics (Sec. 3.1, Appendix): validity, uniqueness, novelty (each over 10,000 molecules), KL divergence over physchem descriptors, and FCD, reported as S = exp(-0.2 * FCD).
- Goal-directed: 20 tasks (rediscovery, similarity, isomers, median molecules, MPO, SMARTS, scaffold/Deco hop); score is mean of top-1 / top-10 / top-100 averages (Eq. 4). Plus a compound-quality filter metric. Paper states "5 benchmarks for ... learn distributions ... 20 optimization benchmarks ... and a metric for compound quality."
- Baselines: random sampler, SMILES LSTM, Graph MCTS, AAE, ORGAN, VAE; goal-directed: Best-of-dataset (virtual-screening baseline), SMILES LSTM, SMILES GA, Graph GA, Graph MCTS.
- Table 1 (distribution learning), Validity/Uniqueness/Novelty/KL/FCD: Random sampler 1.000/0.997/0.000/0.998/0.929; SMILES LSTM 0.959/1.000/0.912/0.991/0.913; Graph MCTS 1.000/1.000/0.994/0.522/0.015; AAE 0.822/1.000/0.998/0.886/0.529; ORGAN 0.379/0.841/0.687/0.267/0.000; VAE 0.870/0.999/0.974/0.982/0.863. The random sampler (which just copies the training set) scores about 1.0 on everything except novelty.
- Table 2 (goal-directed), totals over 20 tasks: Best of dataset 12.144; SMILES LSTM 17.340; SMILES GA 14.396; Graph GA 17.983; Graph MCTS 9.009.
- Headline findings (quoted from text): "the best model is a genetic algorithm based on a graph representation"; SMILES LSTM second; "simpler generative models (VAE, LSTM) are more powerful than more complex models"; GAs "provide molecules of inconsistent quality" while the pretrained LSTM has compound quality "on the same level as the virtual screening baseline". The authors report that simple logP/QED tasks "were not very well suited to differentiate between different models when appropriate baselines are employed" and that some tasks "can be too easily solved by most of the models".
- Controls that can fail: yes. Random sampler and Best-of-dataset are built-in baselines that expose metric weakness. Budget: not constrained (no oracle-call limit), which PMO later criticises.

### 1.2 MOSES
- Polykovskiy D, et al. "Molecular Sets (MOSES): A Benchmarking Platform for Molecular Generation Models." arXiv:1811.12823v5 (28 Oct 2020). https://arxiv.org/abs/1811.12823 . (Published Front. Pharmacol. 11:565644 per the Tripp & Hernandez-Lobato reference list; that record not opened separately.)
- Dataset: 1,936,963 molecules, IntDiv1 = 0.857; random test split plus scaffold-split test set (TestSF, 176,226 molecules; scaffolds disjoint from train).
- Metrics: validity, unique@1k/10k, novelty, filters (MCF/PAINS/etc.), IntDiv1/2, FCD (Test and TestSF), SNN, fragment similarity (Frag), scaffold similarity (Scaf), 1-D Wasserstein on MW/logP/QED/SA.
- Selected numbers (Tables 1-3, mean over 3 inits): CharRNN valid 0.975, unique@10k 0.999, filters 0.994, novelty 0.842, IntDiv1 0.856, FCD/Test 0.073, SNN/Test 0.601. VAE valid 0.977, novelty 0.695, FCD/Test 0.099, SNN/Test 0.626. Combinatorial (BRICS fragment recombination, no neural net) valid 1.0, unique@10k 0.9909, novelty 0.9878, IntDiv1 0.8732, FCD/Test 4.2375. "Train" row: FCD/Test 0.008, SNN 0.642.
- Headline: "a simple language model, character level RNN, shows the best results in terms of the FCD measure"; "From a wide range of presented models, CharRNN currently performs the best in terms of the key metrics." The authors note autoencoder models have low novelty, "indicating that these models overfit". They suggest FCD/Test as the single general number.
- Controls that can fail: the Train row and a non-neural Combinatorial baseline exist. Note a high-novelty fragment recombiner has the worst FCD, i.e., the metric set does separate it from a distribution learner; but see Renz (1.5) for why exact-match novelty is weak.

### 1.3 PMO ("Sample Efficiency Matters")
- Gao W, Fu T, Sun J, Coley CW. "Sample Efficiency Matters: A Benchmark for Practical Molecular Optimization." NeurIPS 2022 Datasets and Benchmarks Track. arXiv:2206.12411v2. https://arxiv.org/abs/2206.12411 ; code https://github.com/wenhao-gao/mol_opt (URL from the paper's abstract).
- Design: 25 methods, 23 oracle tasks (GuacaMol-derived, plus others e.g. drd2, gsk3b, jnk3, qed), oracle budget 10,000 calls, primary metric AUC of top-10 average versus oracle calls (min-max scaled to [0,1]); also AUC top-1/top-100 and raw top-k; 5 independent runs; ZINC 250K only for any database. Docking oracles explicitly left to future work.
- The paper names three problems in prior evaluation: no consideration of oracle budget, trivial oracles (QED, penalized logP), and run-to-run randomness.
- Table 2 (mean AUC Top-10 sum over 23 tasks): 1 REINVENT (SMILES) 14.196; 2 Graph GA 13.751; 3 SELFIES-REINVENT 13.471; 4 GP BO 13.156; 5 STONED 13.024; 6 SMILES LSTM HC; 7 SMILES GA; then SynNet, DoG-Gen, DST. Per-task examples: qed 0.941; valsartan_smarts 0.178 +/- 0.358 (REINVENT) and 0.000 for the other four top methods.
- Headline text: "none of the methods ... can optimize the simple toy objectives within hundreds of oracle calls" (except trivial ones like QED, DRD2, osimertinib_mpo); "several older methods, like REINVENT and Graph GA, outperform more recent ones"; "SELFIES does not seem to offer an immediate benefit ... except in GA"; methods that build "token-by-token or atom-by-atom from a single start point" are most data-inefficient. Authors' own limitation: conclusions "might be biased toward similarity-based oracles".
- Method-family result: an RL language model (REINVENT) and a graph GA won; newer deep generative models did not beat them. This is the strongest primary evidence in this survey that GA/RL baselines must be in any comparison.
- Controls that can fail: yes (replicates, hyperparameter tuning per method, budget counted from scratch including surrogate-training data).

### 1.4 Follow-ups on PMO that change its conclusions
- Tripp A, Hernandez-Lobato JM. "Genetic algorithms are strong baselines for molecule generation." arXiv:2310.09267v1 (Oct 2023, preprint, "Under review"). https://arxiv.org/abs/2310.09267 . Table 2: with a population step of 5 molecules, MOL_GA sums to 14.708 on PMO versus REINVENT 14.196 and Graph GA 13.751 (the authors "believe this result is likely an artifact of the tuning of the baselines in PMO"). Table 1: on unconditional ZINC250k generation, nearly every method is about 100% valid/novel/unique, including MOL_GA (99.76% / 99.94% / 98.60%) and Renz's "AddCarbon" (100% / 99.94% / 99.86%). They propose the "GA criterion": new methods should show a clear advantage over GAs, empirical or conceptual.
- Thomas M, O'Boyle NM, Bender A, de Graaf C. "Re-evaluating sample efficiency in de novo molecule generation." arXiv:2212.01385v1 (Dec 2022). https://arxiv.org/abs/2212.01385 . They re-run PMO adding property filters (MW and logP relative to training data) and a diversity filter; the abstract states this "re-orders the ranking of generative models"; Augmented Hill-Climb ranks top under the combined criterion. The body notes REINVENT still ranks first under property filters, diversity, or both (text near Fig. 3). Lesson: AUC top-10 rewards degenerate or repetitive high-scorers unless diversity and property constraints are part of the metric.

### 1.5 DOCKSTRING
- Garcia-Ortegon M, Simm GNC, Tripp AJ, Hernandez-Lobato JM, Bender A, Bacallado S. "DOCKSTRING: easy molecular docking yields better benchmarks for ligand design." arXiv:2110.15486v1; J. Chem. Inf. Model. 62 (2022), doi 10.1021/acs.jcim.1c01334 (Crossref record). https://arxiv.org/abs/2110.15486 ; https://github.com/dockstring/dockstring
- Content: AutoDock Vina pipeline; >260K molecules docked to 58 targets (>15M scores and poses); three tasks: regression (R2), virtual screening (enrichment factor), de novo design (minimize docking-based objective with 5000 function evaluations and access to the whole dataset).
- Baselines in de novo tasks: SELFIES GA, Graph GA, GP-BO (UCB, EI), and a random ZINC20 baseline.
- Critical finding: "Docking scores are biased towards high molecular weight and lipophilicity. Therefore, optimizing docking scores alone can lead to large and hydrophobic molecules, as we observed in our initial experiments." The unpenalized tasks were "easily solved"; they added a weighted QED penalty, e.g., F2: f = s(l, F2) + 10(1 - QED(l)). They also state logP and QED "are not appropriate objectives for model evaluation" (logP "promoted molecules that were highly unrealistic"; QED "could not be improved further than 0.948").
- This is direct evidence of docking-score hacking by optimizers and of the need for an orthogonal property constraint.

### 1.6 Other oracle-budget work (opened only as citations inside opened papers)
- Tripp et al. 2021 "A fresh look at de novo molecular design benchmarks" is cited by PMO as its reference [15] (surrogate-model-based generation); I did not open it. Listed under UNVERIFIED.

---

## 2. Critiques of generative-model evaluation

| Claim | Source (opened) | Evidence |
|---|---|---|
| Distribution metrics are gameable by copy-and-perturb | Tripp & H-L Table 1 (AddCarbon row, citing Renz et al. 2019); GuacaMol Table 1 (random sampler); MOSES (Combinatorial) | AddCarbon: add one carbon atom to random training molecules; scores 100% validity, 99.94% novelty, 99.86% uniqueness on ZINC250k. The random sampler gets ~1.0 on GuacaMol KL and FCD score. |
| Trivial baselines (GA) match or beat deep generators under oracle budget | PMO Table 2; Tripp & H-L Table 2 | Graph GA 2nd in PMO; tuned MOL_GA 14.708 beats everything in PMO. |
| Oracle-budget and replicates must be reported | PMO intro | Three listed failings of prior work. |
| Property-hacking of optimizers | DOCKSTRING Sec. 2.3.3; ether0 SI (see 5.2) | Docking optimizers drift to large lipophilic molecules; LLM RL finds peroxide/hydrazine hacks. |
| Goodhart: optimizing a proxy too far reduces gold reward | Gao L, Schulman J, Hilton J. "Scaling Laws for Reward Model Overoptimization", arXiv:2210.10760, https://arxiv.org/abs/2210.10760 (abstract and intro opened; RLHF setting, not chemistry) | Abstract: optimizing a proxy reward model "too much can hinder ground truth performance, in accordance with Goodhart's law"; they use a fixed gold reward model to measure the gap. The design (proxy vs held-out gold) is the template for held-out-oracle evaluation. |
| Held-out control scorers detect oracle overfitting | Renz et al. 2019 (see UNVERIFIED for what I could and could not confirm) | Existence and bibliographic data confirmed via Crossref (Drug Discov Today Technol. 32-33:55-63, doi 10.1016/j.ddtec.2020.09.003); the paper itself was not openable. The control-score design (optimization score vs model-control vs data-control) is reported by a secondary note only. |
| Physical validity is not captured by pose RMSD | PoseBusters (3.1) | see below |

Items you asked me to verify exist, with what I could and could not read:
- Walters WP, Murcko M. "Assessing the impact of generative AI on medicinal chemistry." Nat Biotechnol 38:143-145 (2020), doi 10.1038/s41587-020-0418-2. Existence verified via Crossref and the Nature page redirect; full text paywalled, so no content claims are made here.
- Bender A, Cortes-Ciriano I. "Artificial intelligence in drug discovery: what is realistic, what are illusions? Part 1: Ways to make an impact, and why we are not there yet." Drug Discov Today 26:511-524 (2021), doi 10.1016/j.drudis.2020.12.009; Part 2 (chemical and biological data), 26:1040-1052, doi 10.1016/j.drudis.2020.11.037. Existence verified via Crossref only; content not opened.
- Renz P, Van Rompaey D, Wegner JK, Hochreiter S, Klambauer G. "On failure modes in molecule generation and optimization." Drug Discov Today Technol 32-33:55-63 (2019/2020). Existence verified (Crossref) and independently via its use in the opened Tripp & H-L paper.

---

## 3. Structure-based generation evaluation

### 3.1 PoseBusters
- Buttenschoen M, Morris GM, Deane CM. "PoseBusters: AI-based docking methods fail to generate physically valid poses or generalise to novel sequences." arXiv:2308.05777v3 (28 Nov 2023). https://arxiv.org/abs/2308.05777 . (RSC Chem. Sci. version exists, DOI prefix 10.1039/d3sc04185a seen in Crossref review records; not opened.)
- Tests: chemical consistency and geometric/physical plausibility (bond lengths/angles, stereo, aromatic ring planarity, internal clashes, protein-ligand clashes, energy ratio threshold); a pose passing all is "PB-valid". Benchmarks: Astex Diverse (85 complexes, mostly seen in DL training) and the new PoseBusters Benchmark set (308 complexes not in any compared method's training data).
- Numbers (Astex, text under Fig. 1): RMSD <= 2 A alone: DiffDock 72%, Gold 67%, TankBind 59%, Vina 58%, Uni-Mol 45%. RMSD <= 2 A AND PB-valid: Gold 64%, Vina 56%, DiffDock 47%, Uni-Mol 12%, DeepDock 11%, TankBind 5.9%. On the PoseBusters Benchmark set the text gives Gold 55% and Vina 58% as the best, and "the best performing DL method, DiffDock (12%), does not compete".
- Takeaway: RMSD-only success hid physically invalid poses for DL docking; a physical-validity gate re-ranked methods. Abstract also says the tool can "assess docking and molecular generation methods".

### 3.2 PoseCheck
- Harris C, Didi K, Jamasb AR, Joshi CK, Mathis SV, Lio P, Blundell TL. "Benchmarking Generated Poses: How Rational is Structure-based Drug Design with Generative Models?" arXiv:2308.07413v1. https://arxiv.org/abs/2308.07413
- Abstract-level findings (opened): generated molecules from SBDD models "have significantly more physical violations and fewer key interactions compared to baselines"; and redocking "masks many of these failure modes" (generated vs Vina-redocked poses often differ significantly, Fig. 2). Metrics: steric clashes, strain energy, interaction fingerprints. Numerical tables not extracted here.

### 3.3 AF2 / Boltz confidence as a filter (ipTM, ipAE, pLDDT)
- Overath MD, Rygaard (et al.), Jenkins TP. "Predicting Experimental Success in De Novo Binder Design: A Meta-Analysis of 3,766 Experimentally Characterised Binders." bioRxiv doi 10.1101/2025.08.14.670059. https://www.biorxiv.org/content/10.1101/2025.08.14.670059 . Reads via a fetch tool summary (the PDF itself was not downloadable): 3,766 designs, 15 targets, 436 confirmed binders (11.6%); AF3-derived ipSAE_min gives a 1.4-fold gain in average precision over AF2 ipAE; ipTM "performed well at low recall thresholds but underperformed"; per-target AP ranged 0.1-1.0; some datasets were pre-filtered by ipAE, which biases comparison. Preprint, not peer-reviewed as opened. Treat the numbers as secondary because the fetch tool summarised the page.
- Liu C, et al. "ProtDBench: A Unified Benchmark of Protein Binder Design and Evaluation." arXiv:2605.04118v2 (22 May 2026). https://arxiv.org/abs/2605.04118 . Uses the Cao et al. 2022 wet-lab dataset (designs tested without prior AlphaFold filtering) to assess verifiers (AF2-IG, ColabFold, Boltz-1/2, Chai-1, Protenix). Statements opened: "substantial verifier-dependent bias and limited agreement under identical filtering protocols"; "no single metric or verifier dominates uniformly across all targets"; union recall under top-1% ipTM filtering shows recall falls quickly as the number of verifiers that must agree rises. Protein binders, not peptides.
- BindCraft authors' own caution (BindCraft preprint, Discussion): ipTM is "a powerful binary predictor of binding activity" but they flag it, and AF2 single-sequence filtering, as limitations, and recommend an orthogonal Rosetta-type physics score.
- ApexGen authors state circularity: Boltz-2 is "trained on PDB-derived data overlapping with our training distribution ... high scores may reflect 'native-like appearance' to a model with shared training priors rather than true binding affinity" (see 4.7).
- Peptide-specific calibration: AfCycDesign benchmarked its own confidence metric on 80 NMR cyclic-peptide structures: of 49 predictions with pLDDT > 0.85, 73% (n=36) had backbone RMSD < 1.5 A to native; overall 50 of 80 had pLDDT > 0.7 and RMSD < 1.5 A (see 4.3). This is a structure-recovery calibration, not a binding calibration.

### 3.4 DockQ / RMSD
- PepGLAD (4.2) reports RMSD(C-alpha), RMSD(all-atom) and DockQ for conformation generation against crystal references; that is reference recovery, a retrospective test. DockQ originates in Basu & Wallner (cited in PepGLAD; not opened separately).

---

## 4. Peptide-specific works: how each evaluates

Legend: "In silico" = purely computational; "Wet lab" = experimental data in the opened version.

### 4.1 PepINVENT (non-canonical peptides, SMILES, RL)
- Geylan G, et al. (AstraZeneca). arXiv:2409.14040v1, https://arxiv.org/abs/2409.14040 ; published Chem. Sci. 16 (2025), doi 10.1039/d4sc07642g (Crossref; published version not opened).
- Evaluated: validity (syntactic + chemical), peptide-level and amino-acid-level uniqueness (string, isomeric SMILES, canonical SMILES), novelty of generated amino acids (natural / known NNAA / novel), topology-aware validity per topology over 400 test peptides, 1000 samples each. Quote: ">99% unique" for beam search; multinomial sampling gives >1,400 unique amino acids versus ~200 for beam search (Fig. 5), described as 70-fold vs 10-fold expansion over 20 amino acids.
- Goal-directed RL (REINVENT infrastructure, triplicate runs, diversity filter with penalty): scoring components are a ring-size topological constraint, CamSol-PTM solubility, a custom-alert substructure penalty, and an XGBoost permeability classifier trained on CycPeptMPDB PAMPA data (balanced accuracy 0.78, MCC 0.59 on a 10% stratified test set). Result reported: 6318, 922 and 10 soluble macrocyclic peptides without undesirable substructures with permeability scores above 0.6, 0.7, 0.8 (Fig. 10).
- Controls that can fail: none that I found. The same permeability predictor serves as the RL reward and as the reported success measure; no held-out oracle, no GA/enumeration baseline, no wet lab.

### 4.2 PepGLAD
- Kong X, Jia Y, Huang W, Liu Y. "Full-Atom Peptide Design with Geometric Latent Diffusion." NeurIPS 2024; arXiv:2402.13555v4. https://arxiv.org/abs/2402.13555
- Benchmark PepBench (PDB + literature, 1D and 3D) and ProtFrag (70K protein fragments for VAE pretraining). 40 candidates per receptor.
- Metrics: diversity (cluster counts for sequence and structure), consistency (Cramer's V), Rosetta DeltaG, and "Success": "the proportion of successful designs (i.e. DeltaG < 0, indicating no severe atomic clashes or twisted conformations)". That threshold is very permissive.
- Table 2 (versus two non-diffusion-model systems; Div / Con / DeltaG / Success / time per candidate): AnchorExtension 0.245 / 0.423 / -26.80 / 84.30% / 735 s (only 10 candidates per receptor affordable); RFDiffusion 0.259 / 0.696 / -33.82 / 79.68% / 61 s; PepGLAD 0.506 / 0.789 / -29.36 / 92.82%. RFDiffusion has the better DeltaG, PepGLAD the better success rate under the DeltaG < 0 definition. AnchorExtension (dock a scaffold then mutate with energy-guided cycles) is the closest thing to a search baseline in the paper.
- Own limitation: "the binding affinity assessment relies on the Rosetta scoring function as a proxy for wetlab experiments." No wet lab. Conformation generation is scored against reference structures (RMSD, DockQ).
- Controls that can fail: weak (DeltaG < 0 passes most things, including a 84.3% physics-based search baseline); no scrambled-peptide control.

### 4.3 AfCycDesign
- Rettie SA, Campbell KV, Bera AK, Kang A, Kozlov S, De La Cruz J, Adebomi V, Zhou G, DiMaio F, Ovchinnikov S, Bhardwaj G. "Cyclic peptide structure prediction and design using AlphaFold." bioRxiv doi 10.1101/2023.02.25.529956 (posted 26 Feb 2023; preprint opened). https://www.biorxiv.org/content/10.1101/2023.02.25.529956 . (Published version not opened.)
- Structure prediction: 80 NMR cyclic peptide structures from the PDB; median pLDDT 0.88 and RMSD 1.13 A; 50/80 with pLDDT > 0.7 and RMSD < 1.5 A; 73% (36/49) correct at pLDDT > 0.85.
- Design: backbone redesign and hallucination; 10,681 unique structural clusters predicted with pLDDT > 0.9; compared with Rosetta sequence design on the same backbones (63 clusters with pLDDT > 0.9 for Rosetta versus 1,145 for AfCycDesign, but Rosetta restricted to canonical 20 amino acids and scored by the same AF metric, a circularity caveat). Wet lab: synthesis of selected peptides; all seven X-ray structures (one redesigned, six hallucinated) within RMSD < 1.0 A of design models (Ca RMSD values such as 0.2, 0.3, 0.4, 0.8 A reported for individual peptides; RH8.1 deviated at 1.0 A); RH9.1 did not crystallize, 1D NMR consistent with folded.
- Controls that can fail: yes, in a limited sense: selection used pLDDT and Rosetta Pnear, then structures were solved, so the in-silico filter was tested against X-ray; only designs passing the filter were solved (no negative-filter designs tested).

### 4.4 RFpeptides
- Rettie S, Juergens D, Adebomi V, et al. "Accurate de novo design of high-affinity protein binding macrocycles using deep learning." bioRxiv doi 10.1101/2024.11.18.622547 (18 Nov 2024; preprint opened); published Nat. Chem. Biol. 21 (2025), doi 10.1038/s41589-025-01929-w (Crossref; not opened).
- Pipeline: RFdiffusion + RoseTTAFold2 extended to macrocycles, ProteinMPNN + Rosetta Relax, filtered by AfCycDesign iPAE, AF2/RF2 agreement, Rosetta ddG, spatial aggregation propensity, contact molecular surface.
- Wet-lab results (SPR), counts copied from text: MCL1: 27 selected, 13 failed synthesis/cyclisation, 14 tested, 3 binders, best KD 2 uM, X-ray Ca RMSD 0.7 A; MDM2: 11 selected, 3 low yield, 8 tested, 3 binders showing signal at 100 uM; GABARAP: 13 selected, 6 synthesised at > 90% purity, 2 binders (6 nM and 36 nM), IC50 0.7 and 2.5 nM in AlphaScreen; RbtA (no experimental target structure): 26 selected, 11 synthesised, 4 binding at 100 uM, best KD 9.4 nM. Abstract: three of four X-ray structures with Ca RMSD < 1.5 A to design.
- Controls that can fail: yes, wet lab with failures (many designs bound nothing; the paper counts them). No GA/enumeration baseline, no scrambled-sequence negative control seen in my search of the text. The filter thresholds were tuned per target (e.g., iPAE < 0.3 for MDM2, 0.13 for GABARAP, 0.28 for RbtA), so thresholds are not fixed in advance.

### 4.5 BindCraft (protein binders; included because its filters are copied into peptide work)
- Pacesa M, Nickel L, et al., Correia BE, Ovchinnikov S. "BindCraft: one-shot design of functional protein binders." bioRxiv doi 10.1101/2024.09.30.615802 (preprint opened). https://www.biorxiv.org/content/10.1101/2024.09.30.615802
- Abstract: "experimental success rates of 10-100%". Discussion: across 10 targets success rates "range from 24.5 to 100%, with an average success rate of 49.5%". Filters (Methods): AF2 complex pLDDT > 0.8, i_pTM > 0.5, shape complementarity > 0.55, plus i_pAE criterion and Rosetta checks; tested designs were picked from the top 20 by i_pTM. Compared in text, not in a controlled head-to-head, with RFdiffusion and AlphaProteo. The authors acknowledge AF2 monomer filtering may reject real binders and that i_pTM does not correlate with affinity.
- Not a peptide generator; success there is binder presence by SPR/BLI, not affinity ranking.

### 4.6 PepTune (and PeptideCLM)
- Tang S, Zhang Y, Chatterjee P. "PepTune: De Novo Generation of Therapeutic Peptides with Multi-Objective-Guided Discrete Diffusion." arXiv:2412.17780v4 (2 Jun 2025). https://arxiv.org/abs/2412.17780
- Peptide SMILES (including non-natural and cyclic), masked discrete diffusion, Monte Carlo Tree Guidance over a Pareto set of classifier rewards (binding affinity regressor, permeability regressor, solubility / hemolysis / non-fouling classifiers).
- Table 1 (generative quality, max token length 200): Data validity 1.000, uniqueness 1.000, diversity 0.885; PepMDLM (unguided) validity 0.450, uniqueness 1.000, diversity 0.705, SNN 0.513, KL 0.174; PepTune validity 1.000, uniqueness 1.000, diversity 0.677, SNN 0.486, KL 0.173. Guidance raises validity from 45% to 100% by search against the validity filter.
- "External validation" = AutoDock Vina docking of selected Pareto-front peptides with RDKit ETKDG conformers (e.g., GLP-1R candidates -7.4 and -7.0 kcal/mol versus semaglutide -5.7 and liraglutide -5.1). The reward for binding is a learned affinity predictor, and the selected candidates are those with the highest predicted affinity, so docking is a post-hoc plausibility view, not an independent test. No wet lab in this version. Comparison to prior generators is limited (HELM-GPT mentioned in Table 7 text for validity). No GA baseline.
- PeptideCLM: I did not obtain a primary source for a PeptideCLM generator. The record I found (Feller & Wilke, "Peptide-aware chemical language model successfully predicts membrane diffusion of cyclic peptides", bioRxiv 10.1101/2024.08.09.607221; J. Chem. Inf. Model. supporting-info DOI seen) is a property predictor. PepTune uses PeptideCLM embeddings for its solubility / hemolysis / non-fouling classifiers (Table 2 text in PepTune). I did not open Feller & Wilke, so its content is UNVERIFIED.

### 4.7 PepMLM
- Chen T, et al., Chatterjee P. "PepMLM: Target Sequence-Conditioned Generation of Therapeutic Peptide Binders via Span Masked Language Modeling." arXiv:2310.03842v3. https://arxiv.org/abs/2310.03842
- In silico: pseudo-perplexity of the binder region; AlphaFold-Multimer pLDDT and ipTM; "hit rate" defined as the fraction of generated binders whose ipTM exceeds that of the paired test-set known binder: PepMLM "exceeding 38%", RFdiffusion "below 30%". Classes: both ipTM >= 0.7, generated >= 0.7 but test < 0.7, both <= 0.7. Authors note it "remains challenging to definitively ascertain whether our binders exhibit unique binding modes or ... limitations in AlphaFold2-Multimer modeling".
- Wet lab: NCAM1 ECD sandwich ELISA, 4 PepMLM and 4 RFdiffusion linear peptides, PBS negative control, top PepMLM peptide binds more strongly than all four RFdiffusion peptides at 1.37 uM target; MSH3 degradation in HEK293T versus non-targeting poly-Q uAb control; mutant-HTT degradation in TruHD: 3 of 5 peptides; viral phosphoproteins: 60 uAbs screened, 16 with 25-49% reduction and 8 with > 50%, "overall hit-rate of around 40%, in strong agreement with our in silico hit rate".
- Controls that can fail: partly (RFdiffusion comparator, PBS and non-targeting controls). Weaknesses: tiny n (4 versus 4), "hit rate" is relative to a reference peptide's predicted ipTM rather than a threshold, the cell assay measures degradation by a fused construct, not binding per se, and there is no scrambled-peptide control in the text I searched.

### 4.8 Other peptide works opened
- ApexGen: Xia X, de la Fuente-Nunez C. arXiv:2511.14663. https://arxiv.org/abs/2511.14663 . Compared against PepFlow; reports RMSD <= 2 A success rate rising from 17.0% (pocket-only) to 31.5% (full-receptor), Boltz-2 ipTM and PyRosetta DeltaG/dSASA; explicitly cautions that Boltz-2 training overlap creates circularity and that scores are "geometric plausibility ... complementing but not replacing experimental validation". No wet lab.
- CP-Composer: Jiang D, et al. arXiv:2507.04225v2 (ICML 2025 per the PDF header). https://arxiv.org/abs/2507.04225 . "Success Rate" = proportion of target proteins for which at least one of five generated peptides satisfies the specified cyclisation geometric constraints (so it measures constraint satisfaction, not binding), reported 38% to 84%; baseline is PepGLAD without guidance and an energy-guidance variant.
- EvoBind (a GA-like search baseline): Bryant P, Elofsson A. bioRxiv doi 10.1101/2022.07.23.501214. https://www.biorxiv.org/content/10.1101/2022.07.23.501214 . Starts from a random peptide, mutates one residue at a time and accepts if an AlphaFold-based loss improves (1000 iterations, 8 recycles); AF peptide pLDDT discriminates correct (RMSD < 2 A) from incorrect predictions with ROC AUC 0.94 (n = 12 positives, 84 negatives, so small). This is evidence that random-mutation hill climbing with a structure-predictor oracle is itself an established peptide-design method; I found no work in the opened set that uses it as the explicit baseline against which a learned generator must win.
- CPSea (NeurIPS 2025 Datasets and Benchmarks): 2.71 million cyclic peptide-receptor complexes mined from AlphaFold DB (from a search snippet only; not opened, UNVERIFIED).

### 4.9 Does any peptide work compare against simple GA / enumeration baselines?
In the opened set: no peptide generator paper uses a mutation/GA baseline with an equal oracle budget. PepGLAD's AnchorExtension (energy-guided mutation) is the closest, and it achieved 84.30% "success" against PepGLAD's 92.82%, under a threshold (DeltaG < 0) that most designs pass. EvoBind is itself a mutation/hill-climb method, but it is presented as a method, not as the baseline. PMO and Tripp & H-L make the GA comparison for small molecules only.

---

## 5. LLM-specific: constrained decoding and RL with verifiable rewards

### 5.1 Constrained / grammar decoding for molecules
- Kusner MJ, Paige B, Hernandez-Lobato JM. "Grammar Variational Autoencoder." arXiv:1703.01925. https://arxiv.org/abs/1703.01925 . Encodes and decodes parse trees of a context-free grammar so outputs "are always valid"; they claim a more coherent latent space and better Bayesian optimization. Validity here is syntactic/grammar-level.
- Krenn M, et al. "Self-Referencing Embedded Strings (SELFIES): A 100% robust molecular string representation." arXiv:1905.13741v2. https://arxiv.org/abs/1905.13741 . Every string decodes to a valid molecule. PMO then found SELFIES gives no clear advantage over SMILES except in GA.
- Tao W, et al. "How to Make Large Language Models Generate 100% Valid Molecules?" arXiv:2509.23099v1 (Sep 2025). https://arxiv.org/abs/2509.23099 . Abstract opened: LLMs perform worse with SELFIES than SMILES in few-shot settings, their ability to correct invalid SMILES is limited, and SmiSelf (SMILES-to-SELFIES conversion by grammar rules) gives "100% validity while preserving molecular characteristics".
- Mundler N, Dekoninck J, Vechev M. "Constrained Decoding of Diffusion LLMs with Context-Free Grammars." arXiv:2508.10111v1. https://arxiv.org/abs/2508.10111 . General CFG-constrained decoding for diffusion LLMs; includes a SMILES task (167 instances) generated by a Gemini model with verification and scored against a golden solution. Syntax only.
- Evaluation lesson: validity is cheap to guarantee by construction (grammar, SELFIES, a post-hoc validity filter as in PepTune's invalid-peptide loss and MCTS), so validity cannot differentiate generators. Guaranteed validity says nothing about property satisfaction or utility.

### 5.2 RL with verifiable rewards and reward hacking
- Narayanan SM, et al. (FutureHouse). "Training a Scientific Reasoning Model for Chemistry" (ether0). arXiv:2506.17238v2 (2 Dec 2025). https://arxiv.org/abs/2506.17238 . A 24B LLM trained with RL on 640,730 experimentally grounded problems across 375 tasks. Held-out test set; outperforms a dedicated Molecular Transformer on the reaction task given less data (ether0 70% after 46,000 examples vs MT 64.1% on the full USPTO dataset; MT retrained on the same small data failed to exceed 30%). Anti-hacking design documented in the SI: an extra plausibility check on open-answer molecule tasks using Bloom filters of rings and radius-2 fragments harvested from ChEMBL/COCONUT molecules with reported assays. Quote: hand-constructed rules, ML models and QED "found them susceptible to reward hacks such as inserting peroxides to satisfy oxygen counts, or hydrazines to increase solubility. We found this check to be essential." Also notes contamination filtering (ORD vs USPTO overlap). Reward verifier for some tasks is a trained ML model (Table 1 flags "ML model verifier"), which brings Goodhart exposure back for those tasks.
- Ouyang M, Lan H, Lin W. "Adopting Reinforcement Learning with Verifiable Rewards for Molecular Generation" (LLMol). arXiv:2607.19044v1 (21 Jul 2026). https://arxiv.org/abs/2607.19044 . SFT then GRPO with property rewards. Evaluated on penalized logP, QED and structure-constrained optimization, and ZINC distribution metrics. The paper itself notes "penalized logP increases with molecule length" and separates baselines by length limit. Baselines listed: JT-VAE, LIMO, GCPN, MolDQN-type, GraphDF, GraphAF, Chemformer, RT, MolGen, RetMol, MARS; a GA baseline is not in the list I read (cites Tripp & H-L only in related work). These oracles are the ones PMO and DOCKSTRING call trivial. As far as I could read, no held-out oracle and no oracle-call budget.
- Li X, Zhou Z, Zhang L, Han B, et al. "Reference-guided Policy Optimization for Molecular Optimization via LLM Reasoning" (RePO), ICLR 2026, arXiv:2603.05900. https://arxiv.org/abs/2603.05900 . Reports that answer-only SFT collapses reasoning and RLVR gives sparse feedback under similarity constraints; metric SR x Similarity on TOMG-Bench and MuMOInstruct; includes Graph-GA and REINVENT among compared methods in a multi-objective table (text lines near "methods (Graph-GA (Jensen, 2019), REINVENT ...)"). I did not extract its numeric tables.
- What these show about reward hacking guards: only ether0 documents concrete hacks and a countermeasure; the other two rely on the reward being rule-based ("verifiable"), which prevents label noise but does not prevent exploitation of the rule (length for penalized logP).

---

## 6. Evaluation layers ranked by credibility

| Rank | Layer | What it tells you | Main failure mode (evidence) | Credibility as sole evidence |
|---|---|---|---|---|
| 1 | Wet-lab, prospective, with negative/random controls and fixed pre-registered thresholds | Real hit rate | Small n; selection by the same filters; thresholds tuned per target (RFpeptides) | High if controls and counts reported (RFpeptides reports failures) |
| 2 | Retrospective recovery on experimentally determined data (X-ray/NMR structures, wet-labelled binder/non-binder sets not pre-filtered by the predictor) | Whether in-silico verifier tracks reality | Training-set leakage (PoseBusters Astex vs Benchmark gap); circularity (ApexGen caveat) | Medium-high if split by time/scaffold/sequence |
| 3 | Orthogonal physics / independent predictor not used in generation (PB-valid checks, clash/strain, Rosetta or MD not used as reward, different structure predictor) | Whether the optimum is an exploit | Different-but-correlated models share biases (ProtDBench verifier disagreement; Boltz-2 overlap) | Medium; best as a gate, not a score |
| 4 | Held-out oracle (second predictor trained on different data/seed, Goodhart-style gold vs proxy) | Whether reward overfitting occurred | Needs genuinely independent data; Renz-style control scores (secondary evidence only) | Medium |
| 5 | Oracle-budget benchmark with strong tuned baselines (PMO AUC top-10, 10K calls, replicates) | Sample efficiency against GA/REINVENT | Oracle is a proxy; GAs can beat sophisticated models when tuned (Tripp & H-L) | Medium for ranking methods, low for utility |
| 6 | Distribution-learning metrics (validity, uniqueness, novelty, IntDiv, FCD, KL) | Resemblance to training set | Copy-and-perturb (AddCarbon), random-sampler scoring about 1.0, validity by construction | Low; necessary sanity floor only |
| 7 | Predicted-property or docking-score "success" with permissive thresholds (DeltaG < 0, Vina score, own-classifier hits) | Little | Used as reward and as metric (PepINVENT, PepTune); DOCKSTRING docking-score bias | Very low |

---

## 7. Minimum evaluation package a referee would likely accept for an LLM peptide generator when no wet-lab data exist

This is my synthesis from the opened literature, not a published standard; each item names the evidence it rests on.

1. Floors and nulls: report validity, uniqueness, novelty, and diversity, but also run a trivial-modification control (AddCarbon-style perturbation of training peptides) and a random-sampler control through the identical pipeline, and show the metric set separates them from the model (GuacaMol Table 1; Tripp & H-L Table 1).
2. Equal-budget search baselines: a mutation/GA baseline (Graph-GA-style on the representation used, or EvoBind-style hill-climb for sequences) and a REINVENT-style RL baseline, tuned, with the same oracle-call budget, replicates (5 or more), and AUC-style budget curves (PMO; Tripp & H-L's GA criterion). Also a best-of-dataset / library-screen baseline (GuacaMol).
3. Held-out oracle: the optimization oracle and the reporting oracle must differ (different model family or training data, or a physics method never used as reward); report the gap between optimization score and held-out score over training steps (Goodhart: Gao-Schulman-Hilton design; Renz control-score idea, secondary).
4. Orthogonal physical gates: for structure-based claims, PB-valid-style validity checks (clashes, strain, geometry) applied to the final poses, and more than one structure predictor with agreement reported (PoseBusters; PoseCheck; ProtDBench verifier disagreement). Do not use a verifier trained on data overlapping the test set as the only judge (ApexGen caveat). For cyclic peptides, add stereochemistry, ring-closure and nonstandard-residue validity checks the predictor was not optimised against.
5. Retrospective recovery with held-out splits: remove by sequence/scaffold cluster, report recovery of known binders or experimentally characterised structures not seen in training or reward (AfCycDesign 80-NMR benchmark; Cao dataset approach in ProtDBench).
6. Threshold pre-registration and honesty about success definitions: fix thresholds before generation (RFpeptides tuned them per target; PepGLAD's DeltaG < 0 is non-discriminating); report enrichment relative to a decoy/random peptide set evaluated with the same verifier (the missing control in most papers).
7. Diversity and property constraints inside the headline metric (Thomas et al. re-ranking; DOCKSTRING QED penalty), plus an explicit check for known hacking signatures (size/lipophilicity drift, unusual substructures; ether0 plausibility filter).
8. Reward-hacking audit for RL: list the reward components, show the reward-vs-held-out curve, inspect top-k outputs by hand, report fraction failing an independent plausibility filter (ether0 SI as template).
9. Leakage and contamination statement: test set and reference peptides excluded from SFT and RL data (ether0 contamination filtering of ORD vs USPTO).
10. Calibrated claim language: "in-silico plausibility under verifier X", never "binders" or "hit rate" without experimental data.

---

## 8. UNVERIFIED (not opened, or content not confirmed)

- Walters & Murcko 2020 (Nat Biotechnol 38:143): existence confirmed via Crossref, full text paywalled and not read; no claim about its content is used above.
- Bender & Cortes-Ciriano 2021 Parts 1 and 2 (Drug Discov Today): existence confirmed via Crossref only; content not read.
- Renz et al. 2019/2020 (Drug Discov Today Technol 32-33:55-63): Crossref confirms authors, journal, pages. ChemRxiv API returned 403/404; the control-score framework (optimization score, model control score, data control score) and the "OS outpaced both control scores" sentence come from a secondary web note (hunterheidenreich.pages.dev) and a search snippet, not from the paper. Only the AddCarbon numbers in Tripp & H-L Table 1 were verified from an opened source.
- Overath et al. bioRxiv 2025 meta-analysis: numbers come from a fetch-tool summary of the bioRxiv page (PDF not downloadable here); treat as secondary.
- CPSea (NeurIPS 2025 D&B): known only from search-result snippets.
- Feller & Wilke PeptideCLM: record seen (bioRxiv 10.1101/2024.08.09.607221), not opened; I could not confirm any peptide-generation capability for "PeptideCLM".
- Published versions of preprints (PepMLM, PepTune, BindCraft, AfCycDesign, RFpeptides [Nat Chem Biol DOI seen], PoseBusters [Chem Sci DOI prefix seen], PepINVENT [Chem Sci DOI seen]): not opened; numbers above are from the preprint/arXiv versions and may differ in the final papers (for example, later versions of PepTune or PepMLM might include more wet-lab data).
- Tripp et al. 2021 "A fresh look at de novo molecular design benchmarks": referenced in PMO only, not opened.
- PepFlow, DiffPepBuilder, HELM-GPT, TDC oracle suite, and RFdiffusion peptide benchmarks: not opened.
- RePO numeric tables and the LLMol per-task numbers: not extracted.

---

## 9. What the literature (as opened) does NOT contain

- No peptide-generator paper that compares against a tuned GA / mutation-hill-climb baseline at equal oracle budget with replicates (the small-molecule PMO/GA-criterion practice has not been carried over).
- No peptide benchmark of the PMO type (fixed oracle budget, AUC-top-k, multi-method, replicates) that includes non-canonical or cyclic peptides with a physics-grade or experimental oracle.
- No randomised/scrambled-peptide negative-control reported in the wet-lab sections I searched (PepMLM, RFpeptides); controls are PBS, non-targeting constructs, or none.
- No quantitative calibration of AF/Boltz ipTM for non-canonical, D-amino-acid, N-methylated or cyclic peptide binding (AfCycDesign calibrates structure recovery for cyclic peptides; the ipTM-vs-binding meta-analyses cover protein binders).
- No held-out-oracle evaluation (second independent predictor) in PepINVENT or PepTune; the optimisation predictor and the reported metric coincide.
- No prospective, pre-registered comparison of an LLM peptide generator versus GA/enumeration baselines with synthesised peptides.
- No reward-hacking audit for peptide RL comparable to ether0's; peptide-specific exploits (e.g., sequence-length, hydrophobicity, repeated motifs, unusual NNAA that fool permeability classifiers) are not documented in any opened paper.
- No agreed definition of "success rate" across peptide papers (DeltaG < 0; ipTM above a paired reference; constraint satisfaction; SPR hit fraction), so published rates are not comparable.
- A settled external reference for the "Goodhart in molecule generation" quantitative gap: the Goodhart scaling-law paper is from RLHF, not chemistry; I found no chemistry paper in the opened set that measures proxy-vs-gold divergence curves directly (Renz is the likely candidate but could not be read).
