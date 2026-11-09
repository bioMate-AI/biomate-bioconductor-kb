# Paper 1 citation verification (2026-10-31)

Scope: every literature statement in `docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md` (line 14 = Introduction, line 16 = Related work, line 5 = tag legend) and in `docs/20261030_PRIOR_ART_PEPBENCHMARK_PROTAC_CEILING.md`. The three 20261031 survey docs were used only as leads; each primary source below was re-opened in this session.

Method and limits. arXiv items: PDF downloaded and read as `pdftotext` text. PLOS / PMC / JCIM items: abstract and (where stated) full text via Europe PMC REST (search record or `fullTextXML`) or the PLOS page; the publisher pages for JCIM (Sieg) are paywalled, so for Sieg only the abstract was read. Venue/DOI checked with Crossref where stated. Numbers below are copied from the named table or sentence. Verdict scale: SUPPORTED / PARTIALLY / NOT SUPPORTED / COULD NOT OPEN. Nothing here was run; no paid API.

## 0. Headline problems in the draft (fix before submission)

1. **Line 16 mis-describes arXiv 2605.11764.** The draft says "an inter-laboratory ceiling in PROTAC *permeability*". The paper is about PROTAC *degradation activity* (DC50 / Dmax labels); the text contains no occurrence of "permeab". Replace "permeability" with "degradation-activity prediction".
2. **Line 16 groups Sieg 2019, Kalliokoski 2013, Landrum and Riniker 2024, GAUCHE and Graff 2021 under "kNN-style baselines versus learned models in molecular property and few-shot settings".** None of the five is about that. Sieg = bias in structure-based virtual-screening benchmarks; Kalliokoski and Landrum = noise from mixing IC50/Ki across assays; GAUCHE = a Gaussian-process library; Graff = active-learning surrogate models for docking screens. Split them by what each actually shows (wording in section 2).
3. **Line 14 Amirahmadi numbers are correct but need three qualifiers:** the 5,826 are *samples* (5,758 peptides + 68 duplicate measurements; 6/7/10-mers only); the AttentiveFP and MPNN rows are copied from Liu et al.'s protocol, not re-run by Amirahmadi; and the Tanimoto GP is tied for highest with a convex kernel mixture (identical values in Table 6). Numbers come from arXiv v1; the journal version exists (J Cheminform 18, article 108, Crossref issued 2026-08-04) and was not opened.
4. The legend (line 5) and the "[LIT-SUMMARY]" tags on Li, Praski, Chen, Huang can all become `[LIT-VERIFIED]` (section 1), except that the Chen sentence should say DUD-E.

## 1. Citation-by-citation

### 1.1 Amirahmadi et al. (draft line 14, tagged LIT-VERIFIED)
- Ref: Amirahmadi A, Geylan G, De Maria L, Etminani F, Ohlsson M, Tibo A. "A decoupled alignment kernel for peptide membrane permeability predictions." arXiv:2511.21566 (26 Nov 2025); Journal of Cheminformatics 18, article 108 (2026) [Crossref, DOI 10.1186/s13321-026-01276-5; Springer page not opened, redirected to login].
- Draft claim (line 14): "in one benchmark every method lost discrimination moving from random to scaffold splits (AttentiveFP 86.2 -> 66.1 ROC-AUC on 5,826 PAMPA peptides) and a Tanimoto-kernel Gaussian process on fingerprints scored highest on both splits [Tables 3 and 6]".
- Verdict: **SUPPORTED with qualifiers.**
- Checked (arXiv v1 PDF text): Table 3 (ROC-AUC x100, random / scaffold): GP MD-GAK 88.8 +/- 0.2 / 79.8 +/- 0.0; RF 65.1 / 55.3; SVM 59.6 / 53.9; AttentiveFP (best random) 86.2 +/- 1.8 / 66.1 +/- 5.4; DMPNN 84.8 / 71.6; GAT 83.9 / 65.9; GCN 77.2 / 66.9; MPNN (best scaffold) 77.2 / 73.4; PAGTN 78.0 / 68.2; RNN 55.2 / 52.5; LSTM 56.8 / 53.1; GRU 73.1 / 61.7; ChemCeption 46.6 / 40.3; ImageMol 80.4 / 66.1. Every row falls, so "every method lost discrimination" holds for Table 3. Table 6 (raw values): GP TAN sim 89.7 +/- 0.2 / 80.4 +/- 0.0; GP convex (MD-GAK + Tanimoto) 89.7 +/- 0.2 / 80.4 +/- 0.0; GP MD-GAK 88.8 / 79.8. Text (section 3.3): "TAN sim achieves the highest ROC-AUC on both splits (random: 0.897 +/- 0.002; scaffold: 0.804 +/- 0.000), narrowly ahead of the MD-GAK GP. The convex mixture ... matches the top ROC-AUC."
- Dataset sentence (section 2.5): "This yields 5,758 peptides plus 68 peptides with duplicate PAMPA measurements; these duplicates are retained as independent samples ... giving a working subset of 5,826 samples". Splits: random 8:1:1 repeated 10 times; scaffold split via Murcko scaffolds. The paper says the baseline numbers are "the best reported graph models under the same protocols" (Liu et al. [3]).
- Caveats: scaffold-split s.e.m. for the GP is 0.0 (single deterministic split); labels are binarised at P >= -6.
- Recommended wording: "In one published benchmark on 5,826 PAMPA samples (6-, 7- and 10-mers), every method in the comparison lost ROC-AUC from random to scaffold splits (e.g. AttentiveFP 86.2 -> 66.1, baseline values taken from Liu et al.), and a Gaussian process with a Tanimoto fingerprint kernel had the highest ROC-AUC on both splits (89.7 / 80.4, tied with a kernel mixture) [Amirahmadi et al., Tables 3 and 6, arXiv v1]." Tag `[LIT-VERIFIED]`.

### 1.2 Li et al., CycPeptMPDB (draft line 14, tagged LIT-SUMMARY)
- Ref: Li J, Yanagisawa K, Sugita M, Fujie T, Ohue M, Akiyama Y. "CycPeptMPDB: A Comprehensive Database of Membrane Permeability of Cyclic Peptides." J Chem Inf Model 2023, 63(7), 2240-2250. DOI 10.1021/acs.jcim.2c01573; PMC10091415.
- Draft claim: "collects 7,334 peptides from 45 papers and two patents, mostly PAMPA".
- Verdict: **SUPPORTED.**
- Checked (Europe PMC abstract, verbatim): "We collected information on a total of 7334 cyclic peptides, including the structure and experimentally measured membrane permeability, from 45 published papers and 2 patents from pharmaceutical companies." Assay counts (PMC page via summariser, matches survey lead; not re-counted from the paper's table): PAMPA 6,941; Caco-2 649; RRCK 186; MDCK 40 measurements. 6,941 of 7,816 measurements is 89 %, so "mostly PAMPA" is fair; the abstract itself does not state the assay split.
- Wording: keep. Tag `[LIT-VERIFIED]` (abstract) and cite the assay counts to the paper's statistics section only if the table is re-read.

### 1.3 Praski et al. (line 16, LIT-SUMMARY)
- Ref: Praski M, Adamczyk J, Czech W. "Benchmarking Pretrained Molecular Embedding Models For Molecular Representation Learning." arXiv:2508.06199 (v1 8 Aug 2025; v4 23 Feb 2026 read). Venue: none stated on arXiv.
- Draft claim: "Pretrained molecular embeddings often do not beat ECFP".
- Verdict: **SUPPORTED.**
- Checked (v4 abstract, verbatim): "evaluating 25 models across 25 datasets ... nearly all neural models show negligible or no improvement over the baseline ECFP molecular fingerprint. Only the CLAMP model, which is also based on molecular fingerprints, performs statistically significantly better than the alternatives." Results text: "only four models outperformed the ECFP fingerprint. The top-performing model, CLAMP, is a fusion of molecular fingerprints."
- Wording: "In a 25-model, 25-dataset comparison, nearly all pretrained neural embeddings gave negligible or no improvement over ECFP [Praski et al., arXiv 2508.06199v4]." Tag `[LIT-VERIFIED]` (cite as preprint).

### 1.4 Chen et al. (line 16, LIT-SUMMARY)
- Ref: Chen L, Cruz A, Ramsey S, Dickson CJ, Duca JS, Hornak V, Koes DR, Kurtzman T. "Hidden bias in the DUD-E dataset leads to misleading performance of deep learning in structure-based virtual screening." PLoS ONE 2019, 14(8): e0220113. DOI 10.1371/journal.pone.0220113; PMC6701836.
- Draft claim: "hidden bias in ligand benchmarks".
- Verdict: **SUPPORTED** (tighten to DUD-E).
- Checked (abstract and full text via Europe PMC XML): "superior enrichment efficiency in CNN models can be attributed to the analogue and decoy bias hidden in the DUD-E dataset". Full text: "for all 102 targets, the ligand-KNN models achieved AUC values greater than 0.82, 97 of which were greater than 0.90. It is noteworthy that a simple KNN model performed only slightly worse than a ligand CNN model"; "96 (94%) targets have a best K equal to 1 or 2".
- Wording: "analogue and decoy bias in the DUD-E structure-based screening set, where a ligand-only kNN on 2048-bit RDKit fingerprints reached AUC > 0.82 on all 102 targets [Chen et al. 2019]". This is also the strongest published precedent for our no-target-control idea. Tag `[LIT-VERIFIED]`.

### 1.5 Huang et al. (line 16, LIT-SUMMARY)
- Ref: Huang A, Knight IS, Naprienko S. "Data Leakage and Redundancy in the LIT-PCBA Benchmark." arXiv:2507.21404v2 (7 Aug 2025). Preprint.
- Draft claim: "memorisation baselines on LIT-PCBA".
- Verdict: **SUPPORTED.**
- Checked (abstract, verbatim): "In ALDH1 alone ... 323 active training-validation analog pairs occur at ECFP4 Tanimoto >= 0.6; across all targets, 2,491 2D-identical inactives appear in both training and validation"; "a trivial memorization-based baseline with no learnable parameters exploits these artifacts to match or exceed the reported performance of state-of-the-art deep learning and 3D-similarity models." Baseline built from 4096-bit ECFP4 (section 3).
- Wording: keep; cite as preprint (corporate authors, SieveStack). Tag `[LIT-VERIFIED]`.

### 1.6 Sieg, Flachsenberg, Rarey 2019 (line 16, untagged within a LIT-UNVERIFIED group)
- Ref: J Chem Inf Model 2019, 59(3), 947-961. DOI 10.1021/acs.jcim.8b00712 (Crossref confirms authors, journal, volume, pages, date 2019-03-05).
- Draft claim: grouped as "kNN-style baselines versus learned models in molecular property and few-shot settings".
- Verdict: **NOT SUPPORTED as grouped; PARTIALLY for a bias-control statement. Abstract only (paywalled; Europe PMC abstract).**
- Checked (abstract, verbatim): "we re-evaluated three widely used benchmark data sets in the context of ML methods and came to the conclusion that not every benchmark data set is suitable. Moreover, we demonstrate on two examples from current literature that bias is learned implicitly and unnoticed from standard benchmarks." No kNN, no few-shot, no numbers in the abstract. Tables not read.
- Wording: "Benchmark bias in ML-based structure-based virtual screening can be learned implicitly [Sieg et al. 2019, abstract]." Tag `[LIT-SUMMARY]` (abstract only) or drop.

### 1.7 Kalliokoski, Kramer, Vulpetti, Gedeck 2013 (line 16)
- Ref: PLoS ONE 2013, 8(4): e61007. DOI 10.1371/journal.pone.0061007.
- Draft claim: grouped as kNN versus learned models.
- Verdict: **NOT SUPPORTED as grouped; SUPPORTED for the IC50-comparability statement** (the one the task states).
- Checked (PLOS page / Europe PMC abstract, verbatim): "The standard deviation of IC50 data is only 25% larger than the standard deviation of Ki data, suggesting that mixing IC50 data from different assays, even not knowing assay conditions details, only adds a moderate amount of noise to the overall data." Data: "10.895 IC50 values for 3.480 Protein/Ligand systems" giving "20.356 pairs of independent measurements"; "sigma pIC50 = 0.68, MUE pIC50 = 0.55 and MedUE pIC50 = 0.43".
- Wording: "Mixed public IC50 values for identical protein-ligand systems have sigma(pIC50) = 0.68 (20,356 pairs) and the authors judge the added noise 'moderate' [Kalliokoski et al. 2013]; Landrum and Riniker 2024 report larger disagreement under their pairing." Tag `[LIT-VERIFIED]` (abstract level; the sigma figure is also stated in the abstract section of the PLOS page).

### 1.8 Landrum and Riniker 2024 (line 16)
- Ref: Landrum GA, Riniker S. "Combining IC50 or Ki Values from Different Sources Is a Source of Significant Noise." J Chem Inf Model 2024, 64(5), 1560-1567. DOI 10.1021/acs.jcim.4c00049; PMC10934815.
- Draft claim: grouped as kNN versus learned models.
- Verdict: **NOT SUPPORTED as grouped; SUPPORTED for combining-IC50/Ki noise.**
- Checked (abstract, verbatim via Europe PMC): "almost 65% of the points differ by more than 0.3 log units, 27% differ by more than one log unit, and the correlation between the assays, as measured by Kendall's tau, is only 0.51"; maximal curation: "48% of the points differ by more than 0.3 log units, 13% by more than one log unit, and Kendall's tau is 0.71"; "Surprisingly, our analysis shows similar amounts of noise when combining data from different literature Ki assays." (A summariser added "99% data loss"; that figure is NOT in the abstract; do not use it.)
- Wording: use for the sentence on heterogeneity of pooled literature labels (this is the right cite for our "laboratory = source id" caveat). Tag `[LIT-VERIFIED]`.

### 1.9 GAUCHE (line 16)
- Ref: Griffiths R-R, Klarner L, Moss HB, Ravuri A, Truong S, Stanton S, Tom G, Rankovic B, Du Y, Jamasb A, Deshwal A, Schwartz J, Tripp A, Kell G, Frieder S, Bourached A, Chan AJ, Moss J, Guo C, Durholt J, Chaurasia S, Strieth-Kalthoff F, Lee AA, Cheng B, Aspuru-Guzik A, Schwaller P, Tang J. "GAUCHE: A Library for Gaussian Processes in Chemistry." arXiv:2212.04450v2 (21 Feb 2023). A later conference venue was not verified in this session; cite as arXiv.
- Draft claim: grouped as kNN versus learned models.
- Verdict: **NOT SUPPORTED as grouped.** It is a library paper (kernels for fingerprints, strings, graphs; applications to regression, uncertainty and Bayesian optimisation). It does define a Tanimoto kernel and shows Tanimoto-fingerprint GPs performing well in its regression tables, but it does not frame a kNN comparison.
- Wording: "Gaussian-process models with Tanimoto-type kernels over fingerprints are available as a standard tool [GAUCHE, arXiv 2212.04450]" (supports our baseline choice, nothing more). Tag `[LIT-VERIFIED]` for that sentence only.

### 1.10 Graff, Shakhnovich, Coley 2021 (line 16)
- Ref: Chem Sci 2021, 12, 7866-7881. DOI 10.1039/d0sc06805e; PMC8188596.
- Draft claim: grouped as kNN versus learned models.
- Verdict: **NOT SUPPORTED as grouped.**
- Checked (abstract + full text): the paper tests random forest, feed-forward NN and message-passing NN surrogates with greedy/UCB/Thompson/EI acquisition for docking-score screens; e.g. "using a directed-message passing neural network we can identify 94.8% or 89.3% of the top-50 000 ligands in a 100M member library after testing only 2.4% of candidate ligands". No kNN baseline was found (search for "nearest neighbo" in the full text returned nothing). It is relevant to closed-loop selection, not to kNN versus learned.
- Wording: "Model-guided pool-based selection can recover most top-ranked docking hits while evaluating a small fraction of a library [Graff et al. 2021]". Tag `[LIT-VERIFIED]` for that sentence, or drop.

### 1.11 PepBenchmark (line 16 and prior-art note, LIT-SUMMARY)
- Ref: Zhang J, Wang R, Zhou K, Xiao T, Zhu L, Min Y, Wang Y. "PepBenchmark: A Standardized Benchmark for Peptide Machine Learning." arXiv:2604.10531v1 (12 Apr 2026). PDF header: "Published as a conference paper at ICLR 2026". The prior-art note lists "Zhang, Wang, Zhou et al." (correct).
- Draft claim (line 16): "cyclic-peptide benchmarks (PepBenchmark)". Prior-art note claims about cyclic content, splits, BDNegSamp, k-mer leakage, fingerprint baselines.
- Verdict: **SUPPORTED** (with two small number corrections).
- Checked: abstract: "29 canonical-peptide and 6 non-canonical-peptide datasets across 7 groups". Intro: "29 canonical datasets (68,588 sequences) and 6 non-canonical datasets (9,512 sequences)". Section 3: non-canonical = "peptides incorporate cyclic structures or non-canonical amino acid monomers". Table 3: nc-cpp pampa 6970, regression, Hybrid split; ppi 44148 cold-start; nc-PpI ba 277 cold-start. Appendix B.1.3: nc-cpp pampa is "a subset of CycPeptMPDB (Li et al., 2023), including only molecules that are measured using PAMPA". BDNegSamp: 4 steps (pool, task-correlation filter, similarity filter, distribution-controlled sampling); Appendix text: features "discretized into 30 bins and Jensen-Shannon (JS) divergence is constrained below 0.2", stricter thresholds for 1-mer and 2-mer; Table 13 reports JS after sampling. Table 4 (ECFP split, ROC-AUC): avg RF 95.9, XGBoost 96.0, LightGBM 95.7, GradBoost 95.1, GCN 86.9, PeptideCLM 70.3. Table 5 (cold-start): ppi ROC-AUC 51.4-61.3 across models (e.g. ECFP4 54.4, GIN 61.3, PeptideCLM 51.4); nc ppi ba MAE 1.465-1.741 (PepDoRA 1.465, GIN 1.741).
- Corrections to the prior-art note: nc-PpI ba is 277 in the dataset table and appendix but **278 in Table 5**; "MAE 1.47-1.74" is the range over the models listed (PLM columns are blank). Fine to cite as "about 277-278".
- Wording (line 16): "PepBenchmark (ICLR 2026) standardises 35 peptide datasets including a cyclic-peptide PAMPA permeability task derived from CycPeptMPDB (6,970 points)". Tag `[LIT-VERIFIED]`.

### 1.12 Klamt, Nejdl, Tang, arXiv 2605.11764 (line 16 and prior-art note, LIT-SUMMARY)
- Ref: Klamt T, Nejdl W, Tang M. "Decomposing the Generalization Gap in PROTAC Activity Prediction: Variance Attribution and the Inter-Laboratory Ceiling." arXiv:2605.11764v1 (12 May 2026). Page header says "Preprint."
- Draft claim: "an inter-laboratory ceiling in PROTAC permeability".
- Verdict: **NOT SUPPORTED as worded (permeability); SUPPORTED for the inter-laboratory ceiling in PROTAC degradation-activity prediction.**
- Checked (abstract, verbatim): "a within-target cross-laboratory cascade that bounds the inter-laboratory contribution at 0.124 AUROC, substantially above the 0.05 contribution from binarisation-threshold choice"; "Few-shot k=5 stratified per-target retraining combined with ADMET features lifts 65-target LOTO AUROC from 0.668 to 0.7050"; "PROTAC-Bench, ... 10,748 PROTAC degradation measurements across 173 targets and 65 LOTO folds". Cascade (text): "random-CV 0.802, cross-lab 0.678, LOTO 0.653 on the 36-target cohort, paired n = 35"; bootstrap CI "[0.0512, 0.1971]" and leave-one-target-out range "[0.1132, 0.1308] across the 12 replicate-bearing" targets; section 5 text: "the reproducibility floor as the operational ceiling at current dataset scale". Dedup: ceiling about 0.617 (0.668 minus 0.051). LOFO 0.616 +/- 0.024. Search of the text for "permeab", "peptide", "macrocyc", "cyclic": no hit in the sense of the topic (the prior-art note's claim holds).
- Wording: "an inter-laboratory ceiling for PROTAC degradation-activity prediction (cross-lab AUROC drop 0.124; preprint) [Klamt et al., arXiv 2605.11764]". Tag `[LIT-VERIFIED]` with "preprint".

### 1.13 Gupta, Hartford, Liu, LLMNN (task lead; not in draft text)
- Ref: Gupta R, Hartford J, Liu B. "LLMs for Bayesian Optimization in Scientific Domains: Are We There Yet?" Findings of the ACL: EMNLP 2025, pp. 15482-15510. https://aclanthology.org/2025.findings-emnlp.838.pdf
- Verdict: **SUPPORTED** for: LLM agents insensitive to feedback; classical Linear UCB / GP at least as good; hybrid LLMNN "competitive or superior".
- Checked (PDF): abstract: "replacing true outcomes with randomly permuted labels has no impact on performance. Across benchmarks, classical methods such as linear bandits and Gaussian process optimization consistently outperform LLM agents"; LLMNN "achieves competitive or superior performance across domains". Table 4 (cumulative hits, columns Ion. E. / ESOL / FreeSolv): G. truth 1156 / 112 / 64; Random 77.8 / 29 / 14.4; Coreset 151.6 / 57.6 / 20.4; Linear UCB 283 / 76 / 39; GP 151.39 / 35 / 16.8; LLMNN Claude 4 Sonnet NoExp 173.3 / 60.6 / 43.6, with explanations 189.6 / 63.8 / 38. Text: with Qwen2-7B "the latter [traditional baselines] still wins over the LLMNN approach across all the datasets"; "with larger LLMs like Claude 4 Sonnet, the LLMNN method outperforms classical ..." (sentence continues past the excerpt read; the full statement was not re-read here, so quote only the part above).
- Caveat: molecular sets are ESOL / FreeSolv / ion-energy physical-property sets, 5 runs, no split; do not generalise to bioactivity. Column order is as printed in the PDF text.
- Recommendation: if cited, one sentence on feedback-insensitivity and classical baselines; not needed in the draft. Tag `[LIT-VERIFIED]` if used.

### 1.14 MoleculeACE / van Tilborg et al. (task lead; not in draft text)
- Ref: van Tilborg D, Alenicheva A, Grisoni F. "Exposing the Limitations of Molecular Machine Learning with Activity Cliffs." J Chem Inf Model 2022, 62, 5938-5951. DOI 10.1021/acs.jcim.2c01073; PMC9749029 (Crossref confirms).
- Verdict: **SUPPORTED** for "descriptor-based classical ML outperformed deep learning on activity-cliff compounds".
- Checked (Europe PMC full text): "While all methods struggled in the presence of activity cliffs, machine learning approaches based on molecular descriptors outperformed more complex deep learning methods." "SVM coupled with ECFP descriptors ... resulted in the best performance on average"; "no statistical difference was found between SVM, GBM, or RF coupled with ECFPs"; split keeps similar training molecules "(in terms of substructure [0.80 +/- 0.03], ...)"; authors call ECFP superiority "somewhat surprising" given ECFPs define the cliffs.
- Recommendation: usable as a related-work cite alongside Praski. Tag `[LIT-VERIFIED]` if used. The benchmark name MoleculeACE is not in the text I read; refer to the paper by title.

### 1.15 FS-Mol (task lead; not in draft text)
- Ref: Stanley M, Bronskill J, Maziarz K, Misztela H, Lanini J, Segler M, Schneider N, Brockschmidt M. "FS-Mol: A Few-Shot Learning Dataset of Molecules." NeurIPS 2021 Datasets and Benchmarks. https://datasets-benchmarks-proceedings.neurips.cc/paper/2021/hash/8d3bba7425e7c98c50f52ca1b52d3735-Abstract-round2.html (PDF read).
- Verdict: **SUPPORTED** for "RF outperforms kNN in all experiments; meta-learning wins on kinases".
- Checked: "Our best performing single-task method is RF, which outperforms kNN in all of our experiments." Table 2 (support size 16, delta-AUPRC), "all enzymes", 157 tasks: RF 0.093 +/- 0.007; GNN-ST 0.021 +/- 0.005; GNN-MT 0.112 +/- 0.006; MAT 0.052 +/- 0.005; GNN-MAML 0.160 +/- 0.009; PN 0.206 +/- 0.008. Kinases (125 tasks): RF 0.082, PN 0.217.
- Note: this contradicts any framing that kNN is the strongest few-shot baseline; RF > kNN here, and ProtoNet/MAML exceed RF. Tag `[LIT-VERIFIED]` if used.

### 1.16 Items named in the task but not verified further
- DUD-E bias papers beyond Chen 2019 (e.g. other DUD-E/MUV bias studies): not located in the draft or the three surveys' verified lists; nothing cited, so nothing to verify. Huang 2025 itself cites bias literature [5-8] for DUD-E/MUV; do not cite those second-hand.
- ACNet, "Liu et al." (prior-art note, last paragraph, "the synthesis also lists LLMNN, ACNet, Liu et al."): no reference given; not verified; do not cite without full references.
- The draft's other external claims (CycPeptMPDB local file counts, 41 sources, etc.) are `[VERIFIED:...]` data tags, outside this task.

## 2. Suggested replacement for draft line 16

"Related work. Pretrained molecular embeddings seldom beat ECFP [Praski et al., arXiv 2508.06199]; classical descriptor models outperformed deep learning on activity-cliff compounds [van Tilborg et al. 2022]. Benchmark bias and memorisation are documented for DUD-E (a ligand-only kNN reaches AUC > 0.82 on all 102 targets) [Chen et al. 2019] and LIT-PCBA [Huang et al., arXiv 2507.21404]; bias learned from standard benchmarks was also reported by Sieg et al. 2019 [abstract only]. Mixing IC50 or Ki values across assays adds noise [Kalliokoski et al. 2013; Landrum and Riniker 2024]. Cyclic-peptide permeability benchmarks include PepBenchmark [Zhang et al., ICLR 2026] and Amirahmadi et al.; an inter-laboratory ceiling was reported for PROTAC degradation-activity prediction [Klamt et al., arXiv 2605.11764, preprint]. We claim no benchmark or architecture novelty."

## 3. Summary table

| Citation | Verdict | Action |
|---|---|---|
| Amirahmadi et al., arXiv 2511.21566 / J Cheminform 18:108 | SUPPORTED with qualifiers (samples not peptides; baselines from Liu et al.; tie with convex mixture; arXiv v1 numbers) | Tag LIT-VERIFIED after rewording |
| Li et al. 2023 CycPeptMPDB | SUPPORTED (abstract) | Tag LIT-VERIFIED |
| Praski et al., arXiv 2508.06199 | SUPPORTED | Tag LIT-VERIFIED (preprint) |
| Chen et al. 2019 (DUD-E) | SUPPORTED | Tag LIT-VERIFIED; say DUD-E |
| Huang et al., arXiv 2507.21404 | SUPPORTED | Tag LIT-VERIFIED (preprint) |
| Kalliokoski et al. 2013 | SUPPORTED for IC50 noise; not for kNN grouping | Tag LIT-VERIFIED with corrected sentence |
| Landrum and Riniker 2024 | SUPPORTED for IC50/Ki noise; not for kNN grouping | Tag LIT-VERIFIED with corrected sentence |
| PepBenchmark, arXiv 2604.10531 (ICLR 2026) | SUPPORTED | Tag LIT-VERIFIED |
| Klamt et al., arXiv 2605.11764 | SUPPORTED except "permeability" (wrong) | Tag LIT-VERIFIED after fixing to "degradation activity"; label preprint |
| van Tilborg et al. 2022 | SUPPORTED | Optional add; LIT-VERIFIED |
| FS-Mol | SUPPORTED | Optional add; LIT-VERIFIED |
| LLMNN (Gupta et al., EMNLP Findings 2025) | SUPPORTED (physchem sets only) | Optional add; LIT-VERIFIED |
| GAUCHE, arXiv 2212.04450 | NOT SUPPORTED for kNN grouping; only "GP library with Tanimoto kernel" | Use narrow sentence or drop; venue unverified |
| Graff et al. 2021 | NOT SUPPORTED for kNN grouping (no kNN baseline) | Drop from that sentence or narrow to active-learning screening |
| Sieg et al. 2019 | PARTIALLY; abstract only, paywalled; not about kNN | Keep only as "bias learned from benchmarks", tag LIT-SUMMARY (abstract) or drop |
| ACNet / "Liu et al." (prior-art note) | COULD NOT VERIFY: no reference given | Drop until a full reference is supplied |

Ready for `[LIT-VERIFIED]`: Amirahmadi (reworded), Li, Praski, Chen, Huang, Kalliokoski, Landrum, PepBenchmark, Klamt (reworded), plus optional van Tilborg, FS-Mol, LLMNN.
Drop or narrow: GAUCHE, Graff, Sieg (as grouped under "kNN versus learned"), ACNet / Liu et al.
