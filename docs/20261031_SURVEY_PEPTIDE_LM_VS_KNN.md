# Survey: pretrained peptide / cyclic-peptide LMs vs simple fingerprint baselines (few-label and shifted splits)

Date: 2026-10-31 (read-only literature survey; not committed). Method: every cited item below was opened (arXiv / PMC / publisher / bioRxiv / HF page or downloaded PDF) via a page-fetch tool that returns a model-generated extract of the page. Numbers marked [pdf-text] were read from the actual extracted PDF text; numbers marked [extract] came from the fetch tool's extract of the HTML/PMC page and were NOT cross-checked against the original table (re-verify before external use). No search snippet is used as a citation.

Question: have pretrained peptide/cyclic-peptide LMs been compared against simple baselines (fingerprint + kNN / kernel / RF / GBM / Tanimoto-GP), especially under (a) few labels, (b) scaffold/cluster/source-disjoint or otherwise shifted splits?

---

## 1. Papers that DO contain a direct LM-vs-simple-baseline comparison

### 1.1 Feller & Wilke, PeptideCLM-2 (Scaling SMILES-based chemical LMs for therapeutic peptide engineering)
- Authors: Feller et al. (Aaron L. Feller, Claus O. Wilke group). Year 2026. PMC page labels it a bioRxiv preprint/author manuscript; the DOI 10.1021/acs.jcim.6c00652 redirects to a J. Chem. Inf. Model. 66(14) page (publisher page itself not read). https://pmc.ncbi.nlm.nih.gov/articles/PMC12803269/ ; HF collection https://huggingface.co/collections/aaronfeller/peptideclm-2 (9 models: MLM/Hybrid/MTR x 31.7M/0.1B/0.3B; 118M pretraining set).
- Splits: CycPeptMPDB "robust evaluation splits" taken from prior benchmarks (exact split type not stated in the extract); THPep random 5-fold CV; others replicated from literature. No systematic scaffold/cluster/source-disjoint protocol across tasks. No few-shot experiment found in the extract.
- Baselines: RDKit99 descriptors, Morgan FP 2048/r2, with ElasticNet+ExtraTrees, XGBoost, RF; ChemBERTa-2 77M MTR; ChemProp. Triplicate seeds; "standardized" tuning (details not extracted).
- Numbers [extract] (summary table, CycPeptMPDB permeability AUROC): PeptideCLM-2 best 0.836 +/- 0.011; prior SOTA 0.781; RDKit99 baseline 0.800 +/- 0.003; Morgan FP 0.792 +/- 0.001. So the LM margin over the best simple baseline is +0.036 AUROC (about 3.6 points). Cell penetration (MCC): PeptideCLM-2 0.875 vs Morgan FP 0.891 (asterisked; Morgan baseline is higher) and CheMeleon 0.892. Antimicrobial MCC 0.884 vs 0.836; tumor homing 0.756 vs 0.673 (RDKit99).
- Paper's own statement: descriptor-only approaches "remained competitive on simpler tasks"; Morgan FP beats the LM on cell penetration. So partial tie/loss reported by the authors.
- Fair tuning: unclear; the "0.781 prior SOTA" is the original PeptideCLM (v1) cluster-split number below.

### 1.2 Feller & Wilke, PeptideCLM v1 (bioRxiv 2024; JCIM version referenced)
- Peptide-aware chemical language model successfully predicts membrane diffusion of cyclic peptides. bioRxiv 10.1101/2024.08.09.607221 (v2, Nov 2024). https://pmc.ncbi.nlm.nih.gov/articles/PMC11326283/
- Splits: k-means clusters on peptide embeddings, leave-one-cluster-out, 6 clusters (explicitly to avoid leakage / test OOD). This is the best-designed shifted split among LM papers.
- Baselines: only other LMs (ChemBERTa, ChemBERTa-2 variants, random-init). NO fingerprint/RF/kNN baseline run; the text only cites Tan et al. R2 0.658 for RF/GBM from other work.
- Numbers [extract] (CycPeptMPDB): PeptideCLM 23M ROC-AUC 0.781 +/- 0.067, PR-AUC 0.738 +/- 0.161, RMSE 0.742 +/- 0.214; ChemBERTa-2 MTR 77M 0.743 +/- 0.063 / 0.696 +/- 0.171 / 0.724 +/- 0.134; ChemBERTa-1 MLM 10M 0.701 +/- 0.081 / 0.670 +/- 0.187 / 0.714 +/- 0.147. Note: LM beats ChemBERTa by ~4-8 AUC points but the fold SDs (0.06-0.08) are the same size as the gap, and the RMSE of the "best" model is not best.
- Key point: the later 1.1 paper's Morgan FP (0.792) and RDKit99 (0.800) AUROC exceed this v1 number (0.781), although the splits may not be identical (unverified).

### 1.3 Amirahmadi, Geylan, De Maria, Etminani, Ohlsson, Tibo (AstraZeneca/Halmstad/Chalmers), "A decoupled alignment kernel for peptide membrane permeability predictions"
- arXiv:2511.21566 (26 Nov 2025, cs.LG). https://arxiv.org/abs/2511.21566 (tables read from PDF text) [pdf-text].
- Splits: Setting A = label-stratified and canonical-group-stratified (near-duplicate-removed) nested CV on 7,221 unique CycPeptMPDB peptides; Setting B = 6/7/10-mers, random vs scaffold split (5,758 peptides), numbers for other methods taken from Liu et al. (1.4).
- Baselines: GP (alignment kernels), XGBoost, RF (2048-bit Morgan count r=3), fine-tuned ChemBERTa; inner-loop hyperparameter tuning stated for all. Tanimoto-kernel GP on whole-peptide fingerprints added in Tables 4-6.
- Table 1 (label-stratified, ROC-AUC x100): XGBoost 86.3 +/- 0.6; RF 85.7 +/- 0.8; ChemBERTa 84.4 +/- 0.9; GP-MD-GAK 87.8 +/- 0.7; GP Tanimoto 89.0 +/- 0.8 (Table 4).
- Table 2 (canonical-group-stratified, harder): XGBoost 83.9 +/- 1.7; RF 81.8 +/- 2.4; ChemBERTa 80.0 +/- 0.9; GP-PMD-GAK 84.8 +/- 1.4; GP Tanimoto 86.7 +/- 0.5 (Table 5). ChemBERTa is the worst of the six in both tables and drops 4.4 AUC from Table 1 to 2 (XGBoost drops 2.4; Tanimoto GP drops 2.3).
- Table 6 (6/7/10-mers ROC-AUC, random / scaffold): Tanimoto GP 89.7 / 80.4; MD-GAK 88.8 / 79.8; AttentiveFP 86.2 / 66.1; MPNN 77.2 / 73.4. (Table 3, citing Liu et al.: RF 65.1 / 55.3; SVM 59.6 / 53.9 - these RF/SVM numbers are very low and come from the other paper's untuned run, see 1.4.)
- Paper's own conclusion: Tanimoto fingerprint GP "consistently maximizes rank discrimination" (ROC-AUC) across all three settings; it beats the fine-tuned ChemBERTa, RF, XGBoost and the GNNs. Pretrained peptide LMs (PeptideCLM etc.) NOT compared. Only an unmodified general SMILES LM (ChemBERTa) is in the comparison. This is the closest published evidence of "kernel baseline >= LM under shifted split", but ChemBERTa is a weak/general LM, and results are classification (binary) only.

### 1.4 Liu, Li, Verma, Lee, "Systematic benchmarking of 13 AI methods for predicting cyclic peptide membrane permeability"
- J. Cheminformatics 2025, DOI 10.1186/s13321-025-01083-4, PMC12392647. https://pmc.ncbi.nlm.nih.gov/articles/PMC12392647/ ; code https://github.com/Gobliu/BenchmarkCycPeptMP
- 5,826 peptides (lengths 6, 7, 10). Random 80:10:10 x10 repeats; one fixed Murcko-scaffold split; external set of 201 peptides (length 8, 9).
- Models: fingerprint (RF, SVM), graph (AttentiveFP, DMPNN, GAT, GCN, MPNN, PAGTN), string (RNN, LSTM, GRU), image (ChemCeption, ImageMol). NO pretrained peptide LM, NO kNN/GP.
- Random-split regression [extract]: DMPNN MAE 0.347 / RMSE 0.512 / R2 0.555 / r 0.750; RF 0.397 / 0.556 / 0.475 / 0.692; SVM 0.383 / 0.566 / 0.456 / 0.683. So the best GNN improves on RF by ~0.044 RMSE and 0.08 R2; the paper says DMPNN is statistically superior (p<0.05). All models degrade strongly on scaffold split.
- Surprising result: models trained on random split generalised better to the external length-8/9 set than scaffold-split-trained models (authors attribute to training-set diversity).
- Tuning: "Hyperparameters for the benchmarked models were not exhaustively tuned due to time constraints" - so RF/SVM baselines are not fairly tuned (Table 3 of 1.3 shows RF at AUC 65 on this subset, versus RF 85.7 in 1.3's own tuned setting - different data subset, but indicates baseline under-tuning is likely).
- Noise ceiling reported by this paper: inter-report variability of repeated measurements 0.867 +/- 0.631 (log Papp units), intra-report 0.206 +/- 0.191; best-model MAE ~0.35 sits between them [extract].

### 1.5 Adamczyk, Ludynia, Czech, "Molecular Fingerprints Are Strong Models for Peptide Function Prediction"
- arXiv:2501.17901 (v3 10 Mar 2026), q-bio.BM. https://arxiv.org/abs/2501.17901
- 132 datasets over LRGB Peptides-func, AutoPeptideML, AMPBenchmark, a BERT-AMP benchmark, PeptideReactor. Splits are the benchmarks' own: CD-HIT-2D 40% leave-one-dataset-out, homology-clustered OOD test sets (AutoPeptideML), 10x5-fold CV.
- Baselines/LMs: ProtBERT, ESM2 (8M-650M), ProtT5/ProtT5-XL, AMP-BERT, LMPred, cAMPs-pred; graph models GCN/GIN/GraphGPS/GRIT etc. Fingerprint+LightGBM (ECFP, Topological Torsion, RDKit counts) with default hyperparameters (only PeptideReactor tuned over radius).
- Numbers [extract]: LRGB Peptides-func ECFP 74.60% AUPRC vs S2GCN 73.11%; AutoPeptideML ECFP 78.1% AUROC vs ProtT5-XL 79.7% (3B params; fingerprint model ~22k params; PLM slightly ahead); AMPBenchmark ECFP 97.37% AUROC; BERT benchmark TT 87.8% avg F1 vs AMP-BERT 75.3%.
- Authors conclude fingerprints match or beat PLMs/GNNs; they report no dataset where a pretrained transformer definitively beats them; fingerprints weaker on the shortest peptides and synthetic long-range tasks. Canonical peptides (FASTA) only; no CycPeptMPDB and no cyclic/non-canonical peptide LMs.

### 1.6 Zhang et al., "PepBenchmark: A Standardized Benchmark for Peptide Machine Learning"
- arXiv:2604.10531 (12 Apr 2026), ICLR 2026. https://arxiv.org/abs/2604.10531 (results from arxiv HTML, extract [extract]).
- 29 canonical + 6 non-canonical datasets. Splits: hybrid (k-mer enrichment + MMseqs2 clustering) for canonical; ECFP-similarity split (0.95 threshold) for non-canonical; cold-start for peptide-protein.
- Models: fingerprint (RF, XGBoost, LightGBM on ECFP6); PLM (ESM2 8M-650M, DPLM, ProtBERT); SMILES (ChemBERTa, PepDoRA, PeptideCLM); GNN (GCN, GAT, GIN, PepLand).
- Reported: on canonical single-input tasks PLMs lead (avg ROC-AUC 80.6, ESM2-150M-Finetune 81.5) with fingerprints second (79.2); SMILES/GNN much worse (73.2 / 69.5). On non-canonical tasks fingerprint models lead (95.9-96.0 AUC), SMILES/GNN (incl. PeptideCLM, PepLand) "remain weak performers". "Random Forest with ECFP6 frequently achieves first or second place on smaller datasets (<1,500 samples)". The similarity-based non-canonical split is a mild shift (0.95 cutoff). Per-dataset numbers for CycPeptMPDB were not retrieved from the extract; consult the paper's leaderboard tables.

### 1.7 Zhang et al., PepLand (Briefings in Bioinformatics 2025, DOI 10.1093/bib/bbaf367; arXiv 2311.04419)
- https://pmc.ncbi.nlm.nih.gov/articles/PMC12315545/
- Five tasks. Numbers [extract]: nc-CPP SCC PepLand 0.628 vs best baseline 0.539 (Uni-Mol); nc-Binding 0.768 vs 0.721 (ChemBERTa2); c-CPP AUC 0.838 vs 0.885 (ESM2, PepLand lower); c-Sol 0.662 vs 0.725 (ESM2, lower); c-Binding 0.503 vs 0.488 (ChemBERTa2).
- Baselines are pretrained models and "chemical fingerprint and small-molecule baseline models" (the extract does not give the fingerprint-model numbers per task, nor the split type). Whether a kNN/RF-on-fingerprint was tuned is not verifiable from what I read. Paper itself reports PepLand losing to ESM2 on canonical tasks. Treat as weak evidence.

### 1.8 HELM-BERT (Lee, Koyama, Maeda, Matsumoto, Okuno; Kyoto Univ.), arXiv:2512.23175 (29 Dec 2025)
- https://arxiv.org/abs/2512.23175 ; numbers from https://arxiv.org/html/2512.23175 [extract].
- CycPeptMPDB regression (outliers log Papp <= -10 removed, 7,715 samples), 10-fold CV with 10% test. Random-style split, no scaffold/cluster/source split.
- Table 3 (full fine-tune): HELM-BERT R2 0.717 +/- 0.035, r 0.849 +/- 0.021, RMSE 0.416 +/- 0.021, MAE 0.295 +/- 0.010; MoLFormer-XL R2 0.578, r 0.767, RMSE 0.509, MAE 0.367; PeptideCLM R2 0.536, r 0.741, RMSE 0.534, MAE 0.385.
- NO ECFP/RF/XGBoost/GNN/kNN baseline and no low-data experiment (confirmed by extract). The only simple context is the other papers' numbers: e.g. CycPeptMP's Morgan-FP RF got r 0.815 on its own (different) split (Sec. 1.9). Not comparable but shows the 0.849 is not obviously beyond what a good RF reaches on a random-like split. Note also that the search-engine blurb I saw (Pearson 0.769, RMSE 0.878) disagrees with the paper's Table 3; I trust the opened page.

### 1.9 Li, Yanagisawa, Akiyama, CycPeptMP (Briefings in Bioinformatics 2024; DOI 10.1093/bib/bbae417)
- bioRxiv 10.1101/2023.12.25.573282; read via the bioRxiv full text [extract]. https://www.biorxiv.org/content/10.1101/2023.12.25.573282v1.full ; https://academic.oup.com/bib/article/25/5/bbae417/7743192
- 6,889 peptides; test set 344 peptides chosen by Kennard-Stone (maximally spread in descriptor space - this is a shifted/"interpolation-hard" test, not random). Not a scaffold/source-disjoint split.
- Table 3 (test RMSE / R): CycPeptMP 0.503 / 0.883; RF (Morgan FP) 0.616 / 0.815; SVM 2D 0.653 / 0.793; SVM 2D+3D 0.594 / 0.833; MAT 0.978 / 0.408; SAT 1.071 / 0.015; PharmHGT 0.698 / 0.771; FinGAT 0.657 / 0.788. RF and SVM tuned by grid search (Suppl. Table S2). Not a pretrained LM (supervised multi-level model with augmentation), but the only fairly tuned RF row; the two pretrained-style transformers (MAT, SAT) lose badly to RF. Best simple baseline is within 0.09 RMSE of the proposed model.
- Authors document label noise: cyclosporin A measured -5.01 to -6.2 across five publications (SD 0.427); 314 values censored at -8; 12 values at -10 excluded.

### 1.10 van Tilborg, Alenicheva, Grisoni, MoleculeACE (J. Chem. Inf. Model. 2022)
- https://pmc.ncbi.nlm.nih.gov/articles/PMC9749029 (not peptide-specific).
- 24 methods on 30 targets; ECFP-clustered 80/20 stratified split. SVM+ECFP was the best method on activity-cliff compounds; MLP on ECFP beat all graph and SMILES-based NNs. Concludes human-engineered features beat learned representations in low-data drug discovery. [extract]

### 1.11 Praski, Adamczyk, Czech, "Benchmarking Pretrained Molecular Embedding Models For Molecular Representation Learning"
- arXiv:2508.06199. https://arxiv.org/abs/2508.06199 ; methods from https://arxiv.org/html/2508.06199v4
- 25 models x 25 datasets, scaffold-based train/test splits, ECFP count baseline with identical hyperparameter tuning as every model (RF / logistic / kNN heads, best of three per dataset), hierarchical Bayesian testing. "Nearly all neural approaches show negligible or no improvement over ECFP"; only CLAMP (itself fingerprint-based) is significantly better. Caveat stated by the authors: reproducibility/code quality correlated with performance. No peptide-specific models and no peptide datasets in the benchmark (small-molecule benchmark only).

### 1.12 Burns et al., CheMeleon (arXiv:2506.15792; revised Feb 2026)
- https://arxiv.org/abs/2506.15792 . Abstract only read. Claims that "classical methods often outperform neural networks on real-world datasets with limited training data"; CheMeleon wins 75% of Polaris tasks vs RF 68%, and 97% of MoleculeACE assays vs RF 50% [extract]. This is a small-molecule paper, included as evidence that RF is a strong low-data reference even for new foundation models, and CheMeleon is the 0.892 CPP number in 1.1.

---

## 2. Data-leakage / split inflation / noise in CycPeptMPDB-style benchmarks

- Liu et al. (1.4): scaffold split drops all models substantially; random split can still generalise better to an external set. Note random-split numbers are therefore not meaningless but overstate performance on new scaffolds.
- Amirahmadi et al. (1.3): moving random -> scaffold costs AttentiveFP 20.1 AUC points (86.2 -> 66.1) and the GP only 9.0 (88.8 -> 79.8); frames near-duplicates as the source of inflation. Tanimoto GP loses 9.3 (89.7 -> 80.4).
- Li et al. CycPeptMPDB (J. Chem. Inf. Model. 2023, 63(7):2240-2250, DOI 10.1021/acs.jcim.2c01573; https://pmc.ncbi.nlm.nih.gov/articles/PMC10091415/): 6,941 PAMPA + 649 Caco-2 + 40 MDCK + 186 RRCK measurements; "measured membrane permeabilities between each source are also different"; 365 peptides measured in two assays; mixed-assay merging by priority PAMPA > Caco-2 > RRCK > MDCK. No leave-source-out ML benchmark in that paper.
- CycPeptMP (1.9): cyclosporin A SD 0.427 across five labs; censoring at -8.
- Noise ceiling (Liu et al., 1.4): inter-report 0.867 +/- 0.631 vs intra-report 0.206 +/- 0.191 log units. Models' MAE of ~0.35 sits well below the inter-report spread, so source-effects (not model capacity) limit cross-source generalisation. I did NOT find a paper that quantifies an R2 / Spearman ceiling for PAMPA across laboratories for peptides specifically. (PMC11278619, a review on Caco-2/MDCK assay variability, could not be opened - captcha - listed under UNVERIFIED.)
- I found no paper that evaluates CycPeptMPDB with a leave-one-source (publication/laboratory) -out split for LM vs baseline. PeptideCLM v1's leave-one-cluster-out is the closest.

---

## 3. UNVERIFIED (could not open primary source; do not cite as evidence)
- Multi_CycGT (bioRxiv 10.1101/2023.06.20.545822): only seen in search listings; split design and baselines unconfirmed. (A search blurb gave accuracy 0.8206 / AUC 0.8650; not verified.)
- PepMSND: a search blurb described it as a peptide blood-stability model (KAN + Transformer + GAT + SE(3)-Transformer; ACC 0.867, AUC 0.912); I did not open the paper, and it is apparently not a permeability model.
- PCPpred (bioRxiv 10.64898/2026.01.19.700485, 2026): two fetches returned HTTP 429; contents unknown. Potentially directly relevant (multi-assay peptide permeability).
- ChemFM (arXiv 2410.21422): only search summaries; no peptide/cyclic-peptide evaluation was confirmed. MolFormer/ChemBERTa appear only as baselines inside papers above (HELM-BERT, PeptideCLM, PeptideCLM-2, PepBenchmark, Amirahmadi).
- Bi-TEAM (arXiv 2603.01873, Gu et al., 2 Mar 2026): abstract read only; claims large gains on scaffold-similarity tasks and hemolysis; baselines/fingerprint comparison not read.
- LengthLogD (arXiv 2505.17198): abstract only; Morgan-FP-based logD model, not an LM comparison.
- CycPeptMPDB-related: ScienceDirect "Unravelling cyclic peptide membrane permeability prediction: a study on data augmentation, architecture choices, and representation schemes" (S2635098X25000610) returned HTTP 403; not read.
- Conformal-prediction RL paper (van Weesep et al., arXiv 2605.05770, May 2026): abstract read only; no baselines extracted.
- ESM-based peptide models other than as baselines in 1.5/1.6/1.7; CycPeptMP/Multi_CycGT/ESM were not found in any head-to-head against a tuned kNN.
- The exact CycPeptMPDB split definition in PeptideCLM-2 and per-task fingerprint numbers in PepLand and PepBenchmark.

---

## 4. What the literature does NOT contain (the gap)
1. No study compares pretrained cyclic-peptide LMs (PeptideCLM v1/v2, HELM-BERT, PepLand) against a *fairly tuned* fingerprint kNN / Tanimoto-GP / RF / GBM on CycPeptMPDB under a source- (laboratory-/publication-) disjoint split.
2. No few-shot / learning-curve study (e.g. N = 50, 100, 500 labels) of peptide LMs vs fingerprint baselines on cyclic-peptide permeability. Only indirect: PepBenchmark says RF-ECFP6 is first or second below ~1,500 samples (canonical and non-canonical sets); MoleculeACE and CheMeleon make the general low-data point for small molecules.
3. HELM-BERT and PeptideCLM v1 have no fingerprint baseline at all; HELM-BERT uses random-style CV.
4. Only Amirahmadi et al. has a Tanimoto-kernel GP on CycPeptMPDB, and it compares to ChemBERTa, not to a peptide LM, and only classification.
5. Solubility, hemolysis, ADMET beyond permeability for cyclic peptides: only PepLand (c-Sol, ESM2 wins) and PepBenchmark (leaderboards) touch them; no cyclic-specific kNN baselines.
6. No quantified cross-laboratory ceiling (R2/Spearman) for CycPeptMPDB PAMPA; only mean absolute spread statistics (Liu et al.) and anecdotes (cyclosporin A).
7. Baseline tuning is uneven: Liu et al. state RF/SVM not exhaustively tuned; Adamczyk et al. use default hyperparameters; only Amirahmadi et al., CycPeptMP (grid search) and Praski et al. tune baselines comparably.

---

## 5. Summary (<=200 words)
Published evidence does not show that large peptide LMs beat nearest-neighbour/fingerprint baselines under few-label or shifted splits; it also does not show the reverse for cyclic peptides specifically, because the decisive experiment has not been published. Where fair comparisons exist, simple baselines tie or win: a Tanimoto-kernel GP beat fine-tuned ChemBERTa, RF and XGBoost under a near-duplicate-removed CycPeptMPDB split (AUC 86.7 vs 80.0-83.9) and on scaffold splits (80.4 vs GNNs 66-73) (arXiv 2511.21566); fingerprint+LightGBM matched or beat ESM2/ProtT5 on canonical peptides (2501.17901); RF-ECFP6 leads on non-canonical peptides and small (<1,500) sets (PepBenchmark). The newest peptide LM (PeptideCLM-2) reports +0.036 AUROC over RDKit-descriptor XGBoost on CycPeptMPDB (0.836 vs 0.800), but under unspecified "benchmark" splits, and loses to Morgan FP on cell penetration. HELM-BERT and PeptideCLM v1 lack fingerprint baselines. Confidence: moderate that LMs offer at most small gains over tuned simple baselines on shifted splits; low on few-shot, where no direct peptide study exists; the extracts were machine summaries, so verify numbers before external use.
