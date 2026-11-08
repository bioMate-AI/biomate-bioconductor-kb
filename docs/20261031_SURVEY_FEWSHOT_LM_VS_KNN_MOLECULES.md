# Survey: when do language-model / pretrained-embedding approaches beat nearest-neighbour, similarity-lookup or kernel baselines in few-label molecular prediction?

Date: 2026-10-28 (file dated 20261031 per request). Read-only literature survey; not committed.
Method: every item below was opened as a primary source (arXiv PDF, ACL Anthology PDF, PMC full text, PLOS full text, publisher abstract via Europe PMC). Numbers are copied from the named table or text passage. Where a number was read from a PDF-to-text layout that mangled columns, that is stated. Nothing here is cited from search-result snippets alone. Items I could not fully open are under UNVERIFIED at the end.

Terminology note: "LM" in this literature covers three different things that should not be conflated: (a) instruction-tuned general LLMs prompted with SMILES (MolecularGPT, MolRAG, LLMNN); (b) SMILES/text-pretrained encoders (ChemBERTa, MolBERT, MoLFormer, CDDD) used as frozen embeddings; (c) task-conditioned "in-context" transformers trained from scratch on molecule+label tokens (CAMP, MHNfs), which are not language models.

---

## 1. LLM + nearest-neighbour hybrids

### 1.1 LLMNN (Gupta, Hartford, Liu) - exists; it is about experimental design / Bayesian optimisation, not property prediction

Citation: Rushil Gupta, Jason Hartford, Bang Liu. "LLMs for Bayesian Optimization in Scientific Domains: Are We There Yet?" Findings of the Association for Computational Linguistics: EMNLP 2025, pp. 15482-15510. https://aclanthology.org/2025.findings-emnlp.838.pdf (opened and read in full text).

What it actually claims (abstract and Sec. 1/8): (i) off-the-shelf instruction-tuned LLMs (Llama-3.1-8B, Qwen-2-7B, Qwen-2.5-14B, Claude 4 Sonnet, GPT-4o-mini) used as BioDiscoveryAgent-style experiment designers are insensitive to experimental feedback: replacing true outcomes with permuted labels does not change performance; (ii) classical Linear UCB and GP-based BO beat the LLM agent; (iii) a hybrid, LLM-guided Nearest Neighbour (LLMNN), where the LLM proposes seed candidates and the batch is filled by nearest-neighbour expansion in an embedding space (MoLFormer-XL-10pct embeddings for molecules), is "competitive or superior" to the LLM agent and "performs at par with the classical baselines, except on some molecular datasets" (Conclusion).

Task and data: closed-loop selection of hits, N = 5 rounds, batch B = 128/64/32, hit = top 10% (90th percentile). Molecular sets: ESOL (|C| = 1128), FreeSolv (642), Ion. E. (11,565). These are physicochemical regression sets, not target-specific bioactivity ranking. The 5 gene-perturbation sets are not molecular. Splits: none (pool-based simulation; every candidate is in the pool). Averages over 5 runs.

Table 4 (cumulative hits, molecular sets; columns Ion. E. / ESOL / FreeSolv; column order inferred from |C| and the 90th-percentile threshold because the PDF text layout was garbled, row values copied as printed):
- Ground truth hits: 1156 / 112 / 64
- Random: 77.8 / 29 / 14.4
- Coreset: 151.6 / 57.6 / 20.4
- Linear UCB: 283 / 76 / 39
- GP: 151.39 / 35 / 16.8
- LLMNN NoExp, Claude 4 Sonnet: 173.3 / 60.6 / 43.6
- LLMNN, Claude 4 Sonnet (Table 7, MoLFormer embeddings): 189.6 / 63.8 / 38
- Llama-3.1-8B LLMNN NoExp: 152.8 / 23.4 / 12.2; Qwen-2.5-14B NoExp: 185.6 / 33.6 / 17.2
Reading: Linear UCB beats every LLMNN variant on Ion. E. (283 vs best 200.2) and ESOL (76 vs best 75.4 with OpenAI embeddings); only FreeSolv (64 hits possible) shows LLMNN above Linear UCB (43.6 vs 39). The text itself says "the traditional baselines still perform really well" and "the inductive bias that similar candidates have similar properties is clearly not the best bias on molecular domains" (Limitations). With open 7-14B backbones the molecular LLMNN is at or below the classical GP/Coreset rows on ESOL.
Ablation (Table 6): replacing the LLM's centroid choice by random centroids drops hits (Ion. E./ESOL/FreeSolv): 83.2 / 24 / 16 versus 173.3 / 60.6 / 43.6, so the nearest-neighbour step alone (random seeds) is weak; LLM seed choice matters. Table 7: OpenAI text-embedding-3-large embeddings (200.2 / 75.4 / 39.6) were not worse than MoLFormer (189.6 / 63.8 / 38) for Claude 4 Sonnet.
Baseline fairness: classical methods were given "the same candidate embeddings" as the LLM (stated for the gene tables, Table 2 caption); I did not find a statement about how GP/LinUCB hyperparameters were tuned, and I could not confirm from the text which embedding the GP/LinUCB used on the molecular sets. A plain Tanimoto-fingerprint GP (GAUCHE-style) or fingerprint kNN was not included.
Take-away: it is evidence that LLM priors help only as a seed generator, and that a classical GP/linear model over embeddings is at least as good on small physchem sets. It says nothing about FS-Mol-style bioactivity transfer.

### 1.2 MolRAG (retrieval of analogues + LLM reasoning), with its own kNN control

Citation: Ziting Xian, Jiawei Gu, Lingbo Li, Shangsong Liang. "MolRAG: Unlocking the Power of LLMs for Molecular Property Prediction." ACL 2025 (Long Papers), pp. 15513-15531. https://aclanthology.org/2025.acl-long.755.pdf (read).
Setting: MoleculeNet datasets, 1/2/4 retrieved analogues in the prompt, Llama3-8B-Instruct (main), GPT-4o and Qwen2.5-7B-Instruct on a "Test-Mini" subset. Supervised baselines GCN/GAT/GIN/Graphormer(-p) and pretrained GIMLET/KVPLM/MoMu/Galactica are quoted (the regression rows match the numbers in the GIMLET/MolecularGPT papers, i.e. they appear to be copied, not re-run; I did not verify this against a repro statement).
Key control (Sec. 4.4, Table 4, ROC-AUC): "KNN-Based" majority vote over retrieved neighbours vs MolRAG 4-shot Sim-CoT:
- BACE: kNN 0.7628; Llama3-8b 0.7225; Qwen2.5-7b 0.7560
- HIV: kNN 0.5786; Llama3-8b 0.6436; Qwen2.5-7b 0.6680
- MUV: kNN 0.5099; 0.5616; 0.5441
- Tox21: kNN 0.6095; 0.6393; 0.6602
- ToxCast: kNN 0.5894; 0.6408; 0.6624
- BBBP: kNN 0.5972; 0.5411; 0.6042
- CYP450: kNN 0.7503; 0.7229; 0.7229
The paper text says MolRAG "consistently outperforms KNN". Its own Table 4 does not support "consistently": kNN is higher than at least one MolRAG model on BACE, BBBP and CYP450 (kNN beats both models on BACE-vs-Llama, BBBP-vs-Llama, and both models on CYP450). The kNN is a plain majority vote with unspecified k and no tuning description that I found; kNN was not tuned or run with a Tanimoto-weighted score.
Regression (Table 3, RMSE, Llama3-8b Sim-CoT 4-shot): ESOL 3.2806, Lipo 1.1251, FreeSolv 6.1923, versus GCN 1.331 / 0.760 / 2.119: LLM retrieval is far worse than a GCN on regression.
Splits: standard MoleculeNet splits per its Sec. 4.1 (I did not verify scaffold vs random per dataset).

### 1.3 MolecularGPT (instruction-tuned LLM with similarity-retrieved demonstrations)

Citation: Yuyan Liu, Sirui Ding, Sheng Zhou, Wenqi Fan, Qiaoyu Tan. "MolecularGPT: Open Large Language Model (LLM) for Few-Shot Molecular Property Prediction." arXiv:2406.12950v2 (18 Oct 2024). https://arxiv.org/abs/2406.12950 (PDF read). I did not confirm a final venue.
Setup: LLaMA2-7B-chat fine-tuned (QLoRA) on instructions from >1000 property tasks; at inference k nearest neighbours of the query (ECFP/MACCS similarity) are put in the prompt as labelled demonstrations. Evaluated on MoleculeNet + CYP450 (657 tasks per its Sec. 4.1).
Table 1 (ROC-AUC, 2-shot rows as printed): MolecularGPT BACE 0.7218, HIV 0.7204, MUV 0.6338; MHNfs 0.5939, 0.5835, 0.5566; Pre-GS-Meta 0.5213, 0.5702, 0.5507; GIMLET 0.7141, 0.6794, 0.6420. Avg rank (last column) 1.1 (2-shot) / 2.1 (8-shot) for MolecularGPT, as read from the layout (row-to-rank alignment from a garbled text layout; treat as approximate).
Table 2 (zero-shot, plus fully supervised GNNs for reference): fine-tuned Graphormer-p BACE 0.8575, HIV 0.7788, MUV 0.7480, ESOL RMSE 0.804; MolecularGPT 0-shot 0.6212 / 0.7128 / 0.6253, ESOL 1.471. So few-shot LLM is below fully supervised GNNs on most columns.
No kNN, RF or Tanimoto-GP baseline is reported, even though the method's few-shot mechanism is similarity retrieval. The paper's own ablation (Sec. 4.3) finds that performance improves up to 2 retrieved demonstrations and does not improve beyond, and that similarity-based retrieval beats diversity-based by 2.7% (8-shot). Whether the >1000 training tasks overlap the MoleculeNet test tasks was not checked here. Tuning of the MHNfs / Pre-GS-Meta baselines is not described in the passages I read.

### 1.4 Benchmark of prompting LLMs on molecule tasks

Citation: Zhiqiang Zhong, Kuangyu Zhou, Davide Mottin. "Benchmarking Large Language Models for Molecule Prediction Tasks." arXiv:2403.05075v1 (8 Mar 2024). https://arxiv.org/abs/2403.05075 (abstract and header read; tables not extracted). Claim (abstract): "LLMs generally lag behind ML models in achieving competitive performance on molecule tasks, particularly ... models adept at capturing the geometric structure", and LLMs can help ML models when used collaboratively. Six standard molecule datasets. I did not extract numbers.

---

## 2. Pretrained molecular embeddings vs ECFP

### 2.1 Praski, Adamczyk, Czech (2025/2026) - the main benchmark

Citation: Mateusz Praski, Jakub Adamczyk, Wojciech Czech. "Benchmarking Pretrained Molecular Embedding Models For Molecular Representation Learning." arXiv:2508.06199 (v1 8 Aug 2025; v4 23 Feb 2026, read). https://arxiv.org/abs/2508.06199
Design: 25 models x 25 datasets (7 MoleculeNet + 18 TDC, e.g. AMES n = 7278, Bioavailability_Ma n = 640, CYP1A2_Veith n = 12579 from its dataset appendix); fixed scaffold split (Appendix: "a fixed training-test split (scaffold split)"); frozen embeddings fed to Random Forest, logistic regression and kNN; hyperparameter grids identical across all models and datasets (RF min_samples_split in {2,4,6,8,10}, 500 trees; LR regularisation 1e-2 to 1e3; kNN k in {1,3,5,7,9}); the best of the three heads is selected per dataset and embedder; kNN on MUV omitted (did not finish in 24 h). Statistics: hierarchical Bayesian Bradley-Terry with ROPE. Baseline = ECFP count fingerprint (and Atom Pair, Topological Torsion).
Table 1 (mean rank / mean AUROC; selected rows copied): CLAMP 5.40 / 82.55%; R-MAT 6.08 / 80.83%; MolBERT 6.92 / 80.51%; ChemBERTa 7.32 / 79.99%; ECFP 7.52 / 79.89%; CDDD 7.64 / 80.60%; Atom Pair 7.88 / 79.48%; MAT 8.02 / 80.18%; MoLFormer 9.50 / 79.80%; Mol2Vec 10.36 / 79.55%; ChemFM 12.60 / 78.25%; Uni-Mol2 13.32 / 78.11%; MolR 13.80 / 77.84%; GraphMVP 14.64 / 77.18%; Uni-Mol 16.64 / 76.85%; GROVER 17.08 / 75.68%.
Headline: "nearly all neural models show negligible or no improvement over the baseline ECFP"; only CLAMP (itself a fingerprint-based, CLIP-style text-molecule model) is significantly better (Bayesian test). The text/SMILES transformers (ChemBERTa, MolBERT, MoLFormer, CDDD) are within the ROPE or equal to ECFP; the graph-pretrained models (GROVER, Uni-Mol, GraphMVP) are worse.
Fairness: the strongest point of the paper is that the baseline and all embedders get identical downstream tuning. Caveats: frozen-embedding probing (no fine-tuning); full-training-set regime (hundreds to ~10^4 labelled compounds), not few-shot; ADMET-type endpoints, not target-specific potency; ECFP count vs binary not an ablation I read.
Why it matters here: the best published evidence that pretrained SMILES/graph embeddings do not beat a fingerprint under a scaffold split when downstream tuning is matched. It contains no support-set-size sweep, so it cannot speak to n = 8-64 labels.

### 2.2 MoleculeACE (activity cliffs, 24 methods incl. pretrained SMILES transformers)

Citation: Derek van Tilborg, Alisa Alenicheva, Francesca Grisoni. "Exposing the Limitations of Molecular Machine Learning with Activity Cliffs." J. Chem. Inf. Model. 2022, 62, 5938-5951. https://pmc.ncbi.nlm.nih.gov/articles/PMC9749029/ . Correction: J. Chem. Inf. Model. 2024, 64(24), 9643-9648, https://pmc.ncbi.nlm.nih.gov/articles/PMC11683855/ (a software bug mislabelled some activity-cliff pairs and affected the train/test split; the correction reports updated Table 1 and Figs 3-5 and states conclusions are unchanged. The sentence was truncated in my fetch after "The same findings and conclusions as the o...", so "unchanged" is read from that fragment). I read the original-article text; numbers below are from the original and may differ slightly in the corrected figures.
Data and split: 30 ChEMBL v29 targets, 615 (JAK1) to 3,657 (DRD3) molecules, 48,707 entries (35,632 unique). Spectral clustering on ECFP, then stratified random 80/20 split per cluster by activity-cliff label. Consequence stated by the authors: even when all cliff partners fall in the test set, highly similar molecules remain in training (substructure 0.80 +/- 0.03, scaffold 0.93 +/- 0.02, SMILES 0.95 +/- 0.01 similarity). This is a similarity-rich split: it favours lookup-style models.
Result (text): SVM + ECFP best on cliff compounds on average; no statistically significant difference between SVM, GBM or RF with ECFP; RMSE_cliff ranged 0.62-1.60 (traditional) and 0.68-1.44 (deep) log units; "the multilayer perceptron coupled with ECFPs outperformed all other neural networks based on SMILES or graphs"; "despite transformers being pretrained on a larger corpus of SMILES strings (10M compounds), they did not perform better than LSTMs, which were pretrained on 36,281 molecules only"; self-supervised pretraining for GNNs gave no notable gain (preliminary analysis). kNN is in the 24 methods and had "the highest dependency on the chosen target"; I did not extract a kNN RMSE number.
Fairness: hyperparameters for every method tuned by Bayesian optimisation (GP-based, 50 combinations, 5-fold CV) - the most uniform tuning of any paper here. Data-size finding: for training sets > 1000 molecules RMSE and RMSE_cliff correlate (r > 0.80); difficulty is worst in small-data regimes.
Limits: regression of pEC50/pKi, 80% of 600-3,600 molecules as training, so not few-shot; no LLM; no Tanimoto GP.

### 2.3 Fingerprint hash collisions with GP (adjacent)

Walter Virany, Austin Tripp. "Hash Collisions in Molecular Fingerprints: Effects on Property Prediction and Bayesian Optimization." arXiv:2511.17078v1 (21 Nov 2025). https://arxiv.org/abs/2511.17078 . Opened intro/abstract only: exact (uncompressed) fingerprints give a small, consistent gain for a GP on five DOCKSTRING benchmarks, with no significant BO gain. Its introduction states that neural representations "have not been shown to robustly outperform fingerprints ... particularly given limited training data", citing Green et al. 2023 and Praski et al. 2025 (I did not open Green et al.).

---

## 3. Tanimoto-kernel GPs and active-learning baselines

### 3.1 Amirahmadi et al. (J. Cheminformatics 2026) - not a general Tanimoto-GP-vs-deep paper

Citation: Ali Amirahmadi, Gokce Geylan, Leonardo De Maria, Farzaneh Etminani, Mattias Ohlsson, Alessandro Tibo. "A decoupled alignment kernel for peptide membrane permeability predictions." J. Cheminformatics 2026, https://link.springer.com/article/10.1186/s13321-026-01276-5 (the journal page was only seen as a search hit; I read the arXiv version arXiv:2511.21566v1, 26 Nov 2025, https://arxiv.org/abs/2511.21566). Reconcile: I confirmed the arXiv text; I did not open the Springer page, so the final published numbers could differ.
This is a cyclic-peptide membrane-permeability (CycPeptMPDB, ~7.3k peptides) paper whose contribution is a monomer-aware alignment kernel (MD-GAK/PMD-GAK) for GPs. The Tanimoto GP is an added comparator. It is not few-shot.
Setting A (label- and canonical-group-stratified nested 5-fold CV; hyperparameters "tuned in inner loops validation"; ROC-AUC x100):
- Table 4 (label-stratified): GP Tanimoto 89.0 +/- 0.8; GP MD-GAK 87.8 +/- 0.7; GP PMD-GAK 87.6 +/- 0.5 (Tables 1: XGBoost 86.3 +/- 0.6, RF 85.7 +/- 0.8, ChemBERTa 84.4 +/- 0.9).
- Table 5 (group-stratified, harder): GP Tanimoto 86.7 +/- 0.5; PMD-GAK 84.8 +/- 1.4; (Table 2: XGBoost 83.9 +/- 1.7, RF 81.8 +/- 2.4, ChemBERTa 80.0 +/- 0.9).
So a Tanimoto-kernel GP on Morgan counts beat fine-tuned ChemBERTa by 4.6 (label split) and 6.7 (group split) AUC points and beat RF/XGBoost too. Their stated limitation: "we deliberately avoided heavy hyperparameter search" for the GP.
Setting B (length-focused PAMPA, 6/7/10-mers, random vs scaffold; Table 6): GP Tanimoto 89.7 +/- 0.2 / 80.4 +/- 0.0; AttentiveFP 86.2 +/- 1.8 / 66.1 +/- 5.4; MPNN 77.2 +/- 5.5 / 73.4 +/- 8.7; RF 65.1 +/- 4.1 / 55.3 +/- 3.4 (Table 3); SVM 59.6 +/- 1.8 / 53.9 +/- 0.1. Important caveat: for Setting B the paper says it "compared the results on pre-specified benchmarks in [3]", i.e. the graph/string/image baselines are numbers taken from a prior benchmark rather than re-run with the authors' tuning, while RF/SVM and the GPs are theirs; the RF/SVM numbers are much weaker than their own Setting-A RF, which suggests different featurisation/tuning between the two settings. Std of "0.0" for the scaffold GP indicates a deterministic split and no seed variation. Treat Setting B as suggestive only.

### 3.2 GAUCHE (Griffiths et al.)

Citation: Ryan-Rhys Griffiths, Leo Klarner, Henry Moss, Aditya Ravuri, Sang Truong, Samuel Stanton, Gary Tom, Bojana Rankovic, Yuanqi Du, Arian Jamasb, Aryan Deshwal, Julius Schwartz, Austin Tripp, Gregory Kell, Simon Frieder, Anthony Bourached, Alex J. Chan, Jacob Moss, Chengzhi Guo, Johannes Durholt, Saudamini Chaurasia, Felix Strieth-Kalthoff, Alpha A. Lee, Bingqing Cheng, Alan Aspuru-Guzik, Philippe Schwaller, Jian Tang. "GAUCHE: A Library for Gaussian Processes in Chemistry." arXiv:2212.04450v2 (21 Feb 2023). https://arxiv.org/abs/2212.04450 (PDF read). I did not verify a final venue.
Setup: Photoswitch (392), ESOL, FreeSolv, Lipophilicity; 80/20 random splits over 20 trials (no scaffold split); regression RMSE.
Table 1 (GP kernels; Photoswitch RMSE in nm; ESOL; FreeSolv; Lipophilicity): Tanimoto on fragprints 20.9 +/- 0.7 / 0.71 +/- 0.01 / 1.31 +/- 0.06 / 0.67 +/- 0.01; SMILES string kernel 24.8 +/- 0.7 / 0.66 +/- 0.01 / 1.31 +/- 0.01 / 0.68 +/- 0.01; WL graph kernel 22.4 +/- 1.4 / 1.04 +/- 0.02 / 1.47 +/- 0.06 / 0.74 +/- 0.05.
Table 3 (deep Bayesian models, same splits): FC-BNN fragprints 20.9 +/- 0.6 / 0.88 +/- 0.01 / 1.39 +/- 0.03 / 0.75 +/- 0.01; GNN-BNN 28.5 +/- 1.2 / 0.88 +/- 0.01 / 0.96 +/- 0.01 / 0.73 +/- 0.02; CNN ensemble (SELFIES) 26.4 +/- 1.0 / 0.67 +/- 0.01 / 1.29 +/- 0.04 / 0.75 +/- 0.01. So Tanimoto-GP is best or tied on 3 of 4 sets, with the GNN-BNN better only on FreeSolv (0.96 vs 1.31). Pretrained-GNN embeddings are described as a possible GP input; I did not find a quantitative LM-embedding row in the tables I read.
Fairness: the paper frames GPs as needing no per-problem tuning; the deep baselines' tuning is described in its appendix, which I did not audit. BO result: on Photoswitch and ESOL the Tanimoto and string GPs outperform random search (Fig. 3) in an ultra-low-data setting (their words); no LLM baseline.

### 3.3 Graff, Shakhnovich, Coley (2021) - pool-based active learning, no Tanimoto-GP in the comparison

Citation: David E. Graff, Eugene I. Shakhnovich, Connor W. Coley. "Accelerating high-throughput virtual screening through molecular pool-based active learning." Chem. Sci. 2021, 12, 7866-7881. https://pmc.ncbi.nlm.nih.gov/articles/PMC8188596/ (read).
Surrogates compared: RF on 2048-bit atom-pair fingerprints, feed-forward NN on the same fingerprints, D-MPNN; acquisition greedy/UCB/TS/EI/PI. Targets are docking scores (Enamine 10k/50k/HTS 2.1M, AmpC 100M, D4 138M) - not experimental potency, and a random initial 0.4-1% batch. Numbers: Enamine 10k greedy: RF 51.6% (+/-5.9), NN 66.8%, MPN 66.2% of top-100 found after 6% of the library; Enamine HTS 0.4% batches: top-1000 found RF 84.3%, NN 95.7%, MPN 97.6% (random 2.6%); AmpC top-50,000: MPN 89.3% greedy / 94.8% UCB after 2.4% of the library. The paper states a GP surrogate "does not scale well to millions of acquired data points" and cites a GP/Thompson-sampling study (Pyzer-Knapp) as suited to thousands of compounds - so it contains no GP-Tanimoto or kNN row; it is not evidence about Tanimoto kernels. Its relevance: with training sets of hundreds to thousands of compounds, learned D-MPNN surrogates beat fingerprint-RF/NN only once the pool/labels are large; "an exhaustive hyperparameter optimization was outside the scope". Docking scores are smooth functions of structure, a very different label than assay potency.

---

## 4. Few-shot learning on FS-Mol and related

### 4.1 FS-Mol benchmark paper

Citation: Megan Stanley, John Bronskill, Krzysztof Maziarz, Hubert Misztela, Jessica Lanini, Marwin Segler, Nadine Schneider, Marc Brockschmidt. "FS-Mol: A Few-Shot Learning Dataset of Molecules." NeurIPS 2021 Datasets and Benchmarks. https://datasets-benchmarks-proceedings.neurips.cc/paper/2021/file/8d3bba7425e7c98c50f52ca1b52d3735-Paper-round2.pdf (read in full; first four authors confirmed from the PDF header, the remaining four as in the dblp listing).
Split: tasks (assays/targets) disjoint between train (4,938), validation (40) and test (157) per the MHNfs paper's description; test tasks use stratified random support/query splits; metric Delta-AUPRC (AUPRC minus positive rate).
Baselines: "RF and kNN on ECFP and phys-chem descriptors" with "hyperparameter choice following a grid-search and validation procedure"; the paper says "Our best performing single-task method is RF, which outperforms kNN in all of our experiments." GNN-ST from scratch is described as "not a promising method".
Table 2 (support size 16, delta-AUPRC, "all enzymes" row, n = 157 tasks): RF 0.093 +/- 0.007; GNN-ST 0.021 +/- 0.005; GNN-MT 0.112 +/- 0.006; MAT 0.052 +/- 0.005; GNN-MAML 0.160 +/- 0.009; ProtoNet (PN) 0.206 +/- 0.008. Kinases (125 tasks): RF 0.082, GNN-MT 0.113, GNN-MAML 0.178, PN 0.217. Mean rank: PN 1.56, GNN-MAML 2.75, GNN-MT 3.17, RF 3.55, MAT 4.74, GNN-ST 5.22. Text: "random forests ... are doing very well for small-to-medium-sized training sets"; PN "provides a significant performance increase over RF methods, in particular on tasks with few datapoints"; GNN-MT and MAT "either perform comparably to the single-task baseline or under-perform it substantially". Per-support-size values for RF/kNN are in Fig. 2 (no numbers in the main text I could read). Transfer is strongest for kinases (1,497 training tasks) and weakest for classes with <40 training tasks (e.g. classes 6-7), where RF is on par (ligases RF 0.027 vs PN 0.058; translocases RF 0.102 vs PN 0.055 - differences well inside the error bars).
Interpretation: on FS-Mol the pretrained models win only where related training tasks exist; RF/kNN on ECFP are strong baselines except at the smallest supports. No pretrained-LM embedding was included.

### 4.2 MHNfs - includes a plain Tanimoto similarity-search baseline

Citation: Johannes Schimunek et al. "Context-enriched molecule representations improve few-shot drug discovery." ICLR 2023 (preprint version read: arXiv:2305.09481, https://arxiv.org/abs/2305.09481). The full author list was not confirmed from the PDF text I read.
Setting: FS-Mol, support size 16, stratified random support split, all hyperparameters of all methods adjusted on FS-Mol validation tasks; 5 retrains x 10 support-set draws.
Table 1 (delta AUC-PR; All [157] / Kinases [125] / Hydrolases [20] / Oxidoreductases [7]): GNN-ST .029; MAT .052; Random Forest .092/.081/.158/.080; GNN-MT .093; Similarity Search (Tanimoto-weighted mean, no training) .118 / .109 / .166 / .097; GNN-MAML .159; PAR .164; Frequent Hitters .182 / .207 / .098 / .041; ProtoNet .207; Siamese Networks .223; IterRefLSTM .234; ADKF-IFT .234; MHNfs .241 / .259 / .199 / .096.
Observation: a training-free Tanimoto similarity search (.118) beats RF, GNN-MT, MAT and GNN-ST at support 16, and is tied-or-better than the other classical rows on hydrolases (.166 vs RF .158; ProtoNet .209). The task-agnostic "Frequent Hitters" baseline (ignores the support set entirely, predicts molecule promiscuity learned across training assays) scores .182, above GNN-MAML, PAR, RF and Similarity Search - so a substantial part of FS-Mol delta-AUPRC is a prior over compounds, not few-shot transfer. This is a data-distribution effect (see section 6).
Domain shift (Table 2, Tox21, AUC / delta AUC-PR): Similarity Search .629 / .061; IterRefLSTM .664 / .067; MHNfs .679 / .073: the learned models keep a small edge off-distribution.
Notes: it uses the earlier (FS-Mol-style) label noise; MHNfs vs the other embedding methods are close (.241 vs .234).

### 4.3 CAMP: in-context learning for few-shot molecular property prediction

Citation: Christopher Fifty, Jure Leskovec, Sebastian Thrun. "In-Context Learning for Few-Shot Molecular Property Prediction." arXiv:2310.08863v1 (13 Oct 2023, "Under Review"). https://arxiv.org/abs/2310.08863 (read).
Model: a 100.2M-parameter Transformer over (MPNN molecule embedding, label token) context; trained from scratch by meta-learning on FS-Mol train tasks; not a pretrained language model.
Table 1 (FS-Mol, delta-AUPRC +/- s.e., 157 tasks, support 8 / 16 / 32 / 64 / 128), copied: GNN-ST - / .021 / .027 / .031 / .052; MT .088 / .112 / .143 / .176 / .222; MAML .153 / .160 / .166 / .173 / .192; MAT - / .051 / .069 / .092 / .136; CNP .174 / .180 / .186 / .189 / .205; ProtoNet .146 / .185 / .224 / .256 / .290; ADKF-IFT .079 / .093 / .108 / .130 / .177; CAMP .205 / .229 / .246 / .257 / .273.
So CAMP beats all listed methods at 8/16/32, ties ProtoNet at 64 (.257 vs .256) and is below ProtoNet at 128 (.273 vs .290). BACE cross-domain (Table 2, AUPRC): CAMP .651 / .686 / .700 / .728 / .737 vs ProtoNet .564 / .594 / .650 / .690 / .711 (8-128 support); the paper says the margin over the next-best shrinks as support grows (15% at 8, 9% at 128).
Baseline fairness issues: (i) there is no RF, kNN or Tanimoto-similarity row at all in Table 1/2; the authors state they restrict to GNN features and exclude ECFP/PhysChem inputs (justified by fingerprint latency); (ii) ADKF-IFT, which is state of the art with ECFP+PhysChem features, "significantly underperforms" under GNN features, so the comparison to the strongest published baselines is partly an artefact of that choice; (iii) baseline hyperparameters follow the original papers while CAMP got a small search (warm-up steps, dropout), though they report the validation loss gain was 0.588 to 0.575. Cross-check with Table 1 above: FS-Mol RF ~.093 and Similarity Search .118 at support 16, vs CAMP .229 - so on FS-Mol the learned meta-models are about 2x the delta-AUPRC of fingerprint lookup at n = 16 in the published tables (different papers, same benchmark, same metric, but not the same rerun).

### 4.4 LLM / foundation-model few-shot results for context

MolecularGPT (section 1.3) and MolRAG (section 1.2) are the LLM few-shot references. Neither evaluates on FS-Mol, so no number is comparable to the FS-Mol rows above. I found no paper in this review that reports an LLM prompted with SMILES on the FS-Mol test tasks against RF or Tanimoto similarity.

---

## 5. The "Chinese team, learning iteratively with little evidence of a new target" paper

Best match found, with moderate (not certain) confidence: LigUnity.
Citation: Bin Feng, Zijing Liu, Hao Li, Mingjun Yang, Junjie Zou, He Cao, Yu Li, Lei Zhang, Sheng Wang (and further authors listed in the PMC record; the first nine are shown in the page metadata I read). "Hierarchical affinity landscape navigation through learning a shared pocket-ligand space." Patterns 6(10):101371, 17 Sep 2025 (PMC date); DOI 10.1016/j.patter.2025.101371. https://pmc.ncbi.nlm.nih.gov/articles/PMC12546767/ ; preprint https://www.biorxiv.org/content/10.1101/2025.02.17.638554v2 . Affiliations: International Digital Economy Academy (IDEA), Shenzhen; XtalPi, Shenzhen; University of Washington (Sheng Wang). I read the full PMC text.
What it is: a pocket-ligand foundation model (3D pocket structure + ligand, shared embedding; scaffold-discrimination and pharmacophore-ranking objectives; PocketAffDB 0.8M data points, 0.5M ligands, 53,406 pockets, 26,748 assays).
Evaluations: virtual screening (DUD-E, DEKOIS 2.0, LIT-PCBA; claims it beats 24 methods); hit-to-lead (JACS and Merck FEP sets, 16 targets, ~29 ligands/target; zero-shot and fine-tuning on 20-80% of ligands); few-shot fine-tuning with 4/8/12/16 ligands on ChEMBL/BindingDB split-by-time (161 test assays, avg 48.6 ligands), split-by-scaffold, split-by-unit (65 assays, % units); PDE10A (1,162 ligands, Roche time-stamped; fine-tune on first 20% of ligands, Pearson 0.55 vs DrugCLIP 0.37); active learning on TYK2 (10,000 FEP ligands).
Numbers copied from text: split-by-time few-shot: "an average improvement of 8.5% in terms of r2" over ActFound (best competing few-shot method; ActFound is ligand-based) (Fig. 4A, no table numbers in text); split-by-unit: 40.2% improvement over Pocket-DTA (vs 13.8% in split-by-time); Merck set under "no similar ligands and no similar proteins": r2 = 0.472 after fine-tuning on 80% of ligands (23.2/target) vs FEP+(OPLS4) r2 = 0.528.
Baselines: in the active-learning experiment (the "iterate with new labels" part) the competitors are ElasticNet, Gaussian process, GBM, linear regression and random forest, all on 2,048-bit ECFP4 fingerprints; the text says LigUnity achieves "over 40% improvement in terms of r2" under both greedy and exploration-exploitation selection (Fig. 5D; no table numbers). The fingerprint GP is a standard ECFP GP; whether it uses a Tanimoto kernel, and how any baseline was tuned, are not stated in the main text I read. No kNN/Tanimoto-similarity row and no FS-Mol evaluation appear in the structure-free comparison (DeepDTA, BIND, DrugCLIP, Pocket-DTA, Sequence-DTA). It also relies on 3D pocket structure, which kNN/GP-on-ligand baselines do not see, so wins are not "LM vs lookup" but "structure-aware multi-task pretraining vs ligand-only learners".
Caveats on identification: the phrase in the request does not name the paper; LigUnity is the one I could verify matches "Patterns 2025", "Chinese team" and "learning with a few labelled ligands of a new target, with an iterative active-learning loop". I cannot rule out a different paper (e.g. an unrelated Chinese group's iterative few-shot work); confidence ~60%.

---

## 6. Data distribution and why similarity lookup can look strong

- Liu, Wang, Glover, Feasel, Wallqvist. "Dissecting Machine-Learning Prediction of Molecular Activity: Is an Applicability Domain Needed for QSAR Models Based on Deep Neural Networks?" J. Chem. Inf. Model. 2019, 59, 117-126. https://bhsai.org/pubs/Liu_2019_Dissecting_Machine_Learning_Prediction.pdf (abstract and introduction read). Compared DNN, random forest and variable nearest neighbour on 21 in vivo/in vitro datasets: "the overall performance of the three methods was similar"; accuracy is governed by similarity to training molecules; for molecules with little similarity all three return approximately the training mean. Conclusion: model quality depends less on the algorithm and more on structurally diverse training data. I did not extract the per-dataset R2 table.
- Chen, Cruz, Ramsey, Dickson, Duca, Hornak, Koes, Kurtzman. "Hidden bias in the DUD-E dataset leads to misleading performance of deep learning in structure-based virtual screening." PLoS ONE 2019, 14(8): e0220113. https://pmc.ncbi.nlm.nih.gov/articles/PMC6701836/ (read). A receptor-ligand CNN and a ligand-only CNN gave the same average AUC of 0.98 across 102 DUD-E targets (R2 = 0.98 between them); a plain ligand-kNN on 2048-bit RDKit fingerprints (K chosen by internal CV) gets AUC > 0.82 on all 102 targets and > 0.90 on 97 of them, "only slightly worse than a ligand CNN". Cause: analogue bias (actives are congeneric) plus decoy bias. The authors also show ligand-only models trained on one target score highly on distant targets (inter-target analogue bias), so sequence-similarity splits do not remove ligand bias.
- Sieg, Flachsenberg, Rarey. "In Need of Bias Control: Evaluating Chemical Data for Machine Learning in Structure-Based Virtual Screening." J. Chem. Inf. Model. 2019, 59(3), 947-961, DOI 10.1021/acs.jcim.8b00712. Only the abstract was read (via Europe PMC); the publisher page returned HTTP 403 and the figshare PDF was empty. Abstract: re-evaluated three widely used benchmark data sets (the abstract does not name them in the text I read), concluded that "not every benchmark data set is suitable", and shows on two literature examples that "bias is learned implicitly and unnoticed from standard benchmarks"; provides guidelines. Tables, datasets and numbers are NOT verified (see UNVERIFIED).
- van Tilborg et al. 2022 (MoleculeACE, section 2.2): the benchmark's split keeps near-analogues (substructure similarity 0.80 +/- 0.03) in training, and ECFP-based SVM/RF/GBM/MLP win; the authors note ECFP superiority is surprising because ECFP also defines the cliffs.
- Schimunek et al. (section 4.2): the Frequent Hitters baseline (.182) beats RF (.092) and Similarity Search (.118) on FS-Mol; assay-independent compound priors carry much of the score.
- Landrum and Riniker. "Combining IC50 or Ki Values from Different Sources Is a Source of Significant Noise." J. Chem. Inf. Model. 2024. https://pmc.ncbi.nlm.nih.gov/articles/PMC10934815/ (abstract and results read). With minimal curation, ~65% of same-compound IC50 pairs from different assays differ by > 0.3 log units, 27% by > 1 log unit, Kendall tau 0.51; with maximal curation (matching ChEMBL assay metadata) 48% > 0.3, 13% > 1, tau 0.71, at the expense of data set size; Ki-Ki pairs show similar noise (minimal curation: 67% > 0.3 and 30% > 1.0 log units; maximal curation: 69% > 0.3 and 32% > 1.0, i.e. no improvement). This sets a noise floor on any ranking metric computed on pooled ChEMBL data and makes small gains between models hard to resolve; my inference (not stated by the authors) is that on pooled datasets differences between a kNN and a pretrained model of a few AUC points are inside label noise.
- Kalliokoski, Kramer, Vulpetti, Gedeck. "Comparability of Mixed IC50 Data - A Statistical Analysis." PLoS ONE 2013, 8(4): e61007. https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0061007 (read). Note the author list: the initial query wording named other authors; the PLOS page lists Kalliokoski, Kramer, Vulpetti, Gedeck. From ChEMBL: 616,555 IC50 values (confidence >= 4) reduced to 10,895 values for 3,480 protein-ligand systems and 20,356 independent pairs; sigma(pIC50) ~25% larger than sigma(pKi) (fitted Gaussians sigma_pIC50 = 0.87, sigma_pKi = 0.69 in Fig. 5; overall sigma_pIC50 = 0.68, MUE = 0.55); the authors conclude mixing IC50 from different assays "only adds a moderate amount of noise" and a Ki-IC50 factor of 2 is reasonable. Landrum and Riniker's numbers (65% of pairs off by > 0.3 log) read as a more pessimistic view of the same kind of data; the two papers use different pairing/curation, so they are not strictly contradictory.

---

## What the literature (as opened here) does NOT contain

1. No paper in this set compares an LLM or pretrained-LM embedding against a tuned Tanimoto-kernel GP / Tanimoto kNN on the same low-label (n = 8-64 per target) potency-ranking task with a scaffold or temporal split and matched tuning. Praski has matched tuning but full-data ADMET classification; FS-Mol/MHNfs/CAMP have few-shot supports but no pretrained-LM and (CAMP) no fingerprint baseline; MolecularGPT/MolRAG have LLMs but no tuned kNN/RF/GP and use MoleculeNet-style tasks.
2. No FS-Mol result for a prompted LLM or SMILES-LM embedding with a Tanimoto-GP rerun was found.
3. No paper isolates "analog density" as a controlled variable (e.g. performance of LM vs kNN as a function of nearest-neighbour Tanimoto similarity of the query to the support set), apart from Liu 2019's DNN/RF/variable-NN comparison, which is not LLM-based.
4. The only direct kNN-vs-LLM control is MolRAG Table 4, and it is a majority-vote kNN of unspecified k.
5. LLMNN is not a property-prediction method; reading it as "LLM+kNN beats kNN" would be wrong.
6. I did not find any published fair-tuning audit of the FS-Mol RF/kNN baselines beyond the original grid search.

## UNVERIFIED

- Sieg, Flachsenberg, Rarey 2019: full text not opened (HTTP 403 / empty PDF); only the Europe PMC abstract. The datasets re-evaluated, and any numbers, are unconfirmed.
- Amirahmadi et al.: numbers are from the arXiv v1 PDF; the Springer J. Cheminformatics page (DOI 10.1186/s13321-026-01276-5) was not opened.
- FS-Mol: last four authors and order taken from a dblp search listing (first four confirmed in the PDF). Per-support-size values for RF and kNN (Fig. 2) not extracted; kNN has no number in the main text, only the statement that RF outperforms kNN in all experiments.
- MHNfs (ICLR 2023): author list not read from the PDF; table values copied from the arXiv preprint, which could differ from the camera-ready.
- MoleculeACE correction: statement of unchanged conclusions inferred from a truncated sentence; no per-method numbers verified in the corrected figures.
- GAUCHE final venue not confirmed; deep-baseline tuning in its appendix not audited.
- LigUnity: full author list beyond the first nine; the exact Fig. 4/5 numbers (not in text); whether the TYK2 GP baseline uses a Tanimoto kernel; baseline tuning; leakage handling for pretraining overlaps with test assays beyond the statements quoted.
- Zhong et al. 2024 (LLM benchmark): tables not read; only the abstract claim.
- Graff et al.: Tanimoto GP not evaluated; any claim that fingerprint-GP is competitive there is not supported.
- MolecularGPT: overlap between its >1000 instruction-tuning tasks and the MoleculeNet test sets not checked; Table 1 rank column read from a garbled layout.
- "Green et al. 2023" (cited by Virany and Tripp as evidence that neural representations do not robustly beat fingerprints with limited data) was not opened.

## Summary of evidence (<= 200 words)

Published evidence says pretrained LM/SMILES/graph embeddings rarely beat a tuned ECFP baseline: Praski (25 models x 25 datasets, scaffold split, matched tuning) finds only CLAMP, itself fingerprint-based, ahead; MoleculeACE and Tanimoto-GP papers (GAUCHE, Amirahmadi) show fingerprint kernels/SVM/RF matching or beating deep models on small to mid-size sets. General LLMs prompted with retrieved analogues (MolecularGPT, MolRAG, LLMNN) lack tuned kNN/GP controls; MolRAG's own Table 4 shows plain kNN beating its LLM on BACE, BBBP and CYP450. Where learned models do win, they are meta-trained on many related assays (FS-Mol: ProtoNet .206, CAMP .229 vs RF .093, Tanimoto similarity .118 at n=16; LigUnity with pocket structure), mostly at n <= 32, and gains fade or vanish at larger supports or with few related training tasks. Similarity-rich splits, congeneric series (DUD-E kNN AUC > 0.9 on 97 of 102 targets) and IC50 noise inflate lookup baselines and blur small differences. Confidence: high that fingerprint baselines are hard to beat with frozen pretrained embeddings; moderate that meta-learned models beat lookup at n <= 32; low for LLMs, because no fair head-to-head exists.
