# Few-evidence adaptation to a new target: literature and code survey (2026-10-30)

Scope: read-only survey. Web pages were opened with WebFetch or seen in WebSearch result snippets. Each entry is tagged `[opened]` (fetched, content read) or `[snippet]` (seen only in a search-result summary, not fetched). Several fetches returned only abstract-level text or hit rate limits, so many protocol details below are marked unverified. "Reported" means the authors' own claim as relayed by the page. "Assessment" means my interpretation.

Our scenario: a held-out target family, k = 0, 5, 10, 25 revealed labelled compounds, iterated. Baselines: nearest-neighbour-to-revealed AUROC 0.75-0.87, plus a physchem prior. Model: a hybrid knowledge + neural cyclic-peptide LM in a feedback loop.

---

## 1. Identifying the "digital drug / learn from a little evidence for a new target" work

I cannot identify a single definitive match. The owner's recollection ("digital drug" in the sense of 数字药物/数智药研, a Chinese team, recent, learning iteratively from little evidence on a new target) fits several things equally well. Ranked candidates:

| Rank | Candidate | Team | Confidence | Why |
|---|---|---|---|---|
| 1 | **LigUnity**, "Hierarchical affinity landscape navigation through learning a shared pocket-ligand space", Patterns, Sept 2025 [opened, PMC12546767] | IDEA (International Digital Economy Academy, Shenzhen), XtalPi, Univ. of Washington; first author Bin Feng, senior Sheng Wang | Medium (about 40%) | Chinese institute plus XtalPi. It has an explicit few-shot fine-tuning mode for a new target and an active-learning loop (TYK2, "within four iterations"). "Digital economy" in IDEA's name could also explain a "digital"-flavoured memory. |
| 2 | **DrugCLIP**, Science, Jan 2026, Tsinghua AIR (Lan Yanyan) with Life Sciences and Chemistry [opened sciencenet article; arXiv 2310.06367 seen as snippet] | Tsinghua AIR / BAAI | Low-medium (about 20%) | Very recent and widely covered in Chinese media. Its strength is zero-shot genome-scale screening. The sciencenet article explicitly does not describe iterative learning from experimental feedback. Likely recalled for its wet-lab hit rates (15% NET, 17.5% TRIP12), not for iteration. |
| 3 | **Tsinghua EE (Yao Quanming) few-shot DDI work** (KnowDDI, Nature Computational Science 2023; EmerGNN, Nature Communications Medicine 2024) [opened, tsinghua.edu.cn/info/1175/110719.htm] | Tsinghua Electronic Engineering | Low (about 10%) | The page is titled around few-shot learning to help drug development, but the task is drug-drug interaction on biomedical graphs, not target activity. |
| 4 | **Insilico Medicine's dry-wet closed loop** (Rentosertib, "design-synthesis-test-optimise" cycles) [snippet, Chinese news aggregation] | Insilico (Shanghai Zhangjiang) | Low (about 10%) | Matches "closed-loop with iteration" and "Chinese team". It is an industrial pipeline narrative, not a few-shot method paper. |
| 5 | **ActFound**, Nature Machine Intelligence (pairwise meta-learning, 35,644 ChEMBL assays) [snippet; the SCMP headline reads "Chinese and US scientists"] | Chinese-US collaboration (Peking Univ. involvement not verified by me) | Low (about 10%) | Direct few-shot-on-a-new-assay design. Not framed as "digital drug". |

Other possibilities I did not rule out: a Chinese-language survey or talk on 数字药物 that was not indexed; a DP Technology (Uni-Mol/Hermite/Bohrium) or Shanghai AI Lab work I could not surface. My searches for DP Technology, XtalPi (other than LigUnity), Zhejiang University, Baidu, Tencent, ByteDance and Alibaba returned nothing relevant on few-shot new-target adaptation. I could not search WeChat/Zhihu content directly. Recommended action: ask the owner for any remembered venue, month, or a keyword (e.g. "test-time", "few-shot fine-tune", "TYK2") and re-search. If the memory is of a talk rather than a paper, LigUnity is the closest fit I found.

---

## 2. Works surveyed

### 2.1 Few-shot and meta-learning benchmarks and methods

**FS-Mol: A Few-Shot Learning Dataset of Molecules** [opened abstract page only]
- Authors: Stanley, Bronskill, Maziarz, Misztela, Lanini, Segler, Schneider, Brockschmidt (Microsoft Research / Novartis). NeurIPS 2021 Datasets and Benchmarks.
- Regime: tens to hundreds of labelled compounds per task. The search snippet says 5,120 tasks, 233,786 molecules, 157 test targets [snippet].
- Method: dataset plus benchmarking procedure. Baselines are single-task, multi-task and meta-learning approaches.
- Protocol: separate pre-training and evaluation task sets. I could not extract the support-size sweep, the exact split definition, results, or licence; the PDF fetch returned binary. Those are unverified.
- Reusable: the evaluation protocol (task-level splits, support-size sweep, delta-AUPRC against a per-task baseline) is the closest public template to ours. Maps to our k = 0/5/10/25 sweep. Data are ChEMBL small molecules, not cyclic peptides.

**CAMP, "In-Context Learning for Few-Shot Molecular Property Prediction"** [opened arXiv abs 2310.08863]
- Authors: Fifty, Leskovec, Thrun. arXiv Oct 2023.
- Regime: context of (molecule, measurement) pairs, small support sizes.
- Method: transformer-style in-context learner. Predicts a query from the labelled context without fine-tuning.
- Protocol: FS-Mol and BACE. Details of the split were not on the page.
- Reported: surpasses recent meta-learning methods at small support sizes, competitive at large ones.
- Code: not stated on the page.
- Reusable: the "dual-memory loop" could use revealed compounds as in-context memory. Idea only.

**ActFound**, "A foundation model for bioactivity prediction using pairwise meta-learning" [snippet; the bioRxiv PDF fetch returned HTTP 429]
- Reported (snippet): trained on 1.6M bioactivities over 35,644 ChEMBL assays; pairwise prediction of activity difference within an assay, which makes it unit-agnostic; beat nine competitors on ChEMBL, BindingDB, FS-Mol, pQSAR-ChEMBL; published in Nature Machine Intelligence.
- Independent test: **Reusability Report** (Walker and Butt, Vanderbilt) [opened, PMC12363932]. On antibacterial natural products (472 compounds, 14 strains, 8-128 fine-tuning compounds, 40 random splits), ActFound/ActFound-Transfer beat MAML, ProtoNet and TransferQSAR mainly at the fewest shots. Absolute r2 was only 0.01-0.12, "substantially lower than the original publication". Their stated reason: the pairwise function assumes similar compounds have similar activity, and fails when the assay lacks close analogs.
- Reusable: the pairwise-difference idea is a direct template for our assay/lab offset (differences cancel the offset). The reusability report is also direct evidence for risk (c) below.

**Embracing assay heterogeneity with neural processes** [opened arXiv abs 2308.09086]
- Authors: Chan, Verdonk, Poelking (Astex-affiliated, as I recall; not verified on the page).
- Method: hierarchical meta-learning with neural processes that separate between-assay variability from within-assay variance.
- Reported: "drastic improvement" in affinity prediction across targets and assay types, and fast adaptation to new target contexts from very few observations. Splits, k, and code are not on the abstract page; unverified.
- Reusable: closest published match to our lab/assay offset concept as a latent, hierarchical variable. We use anchor compounds to estimate it explicitly; they learn it.

**Attribute-guided Prototype Network (APN)** [opened, Uni-Mol blog page]
- Authors: Hou, Xiang, Zeng (Hunan University) with Li Zeng (Shanghai Institute of Materia Medica). Briefings in Bioinformatics, Aug 2024.
- Regime: 5-shot and 10-shot on Tox21, SIDER, MUV. Method: prototype network with fingerprint and Uni-Mol attributes.
- Reported: Tox21 10-shot ROC-AUC 84.54%. Code: none stated.
- Note: these are property endpoints (toxicity), not new-target activity.

**Tabular in-context learners (TabPFN, TabICL) for biomolecular property prediction** [opened arXiv abs 2606.31126]
- Authors: Guan, Zhang, Wijesinghe, Zhu, Zhao, Power, Ahmed, Warden, Ong, Steinberg (2026).
- Datasets: ProteinGym, TDC ADMET, MoleculeNet, FS-Mol, DrugOOD. Reported: tabular foundation models are strong "only when coupled with expressive representations"; SOTA on ProteinGym with ESM Cambrian encoders. Code not stated.
- Reusable: a cheap strong baseline for k = 5-25 (TabPFN on our LM embeddings plus physchem features). Worth adding to our baseline panel.

**AssayMatch** [opened arXiv 2511.16087]
- Authors: Fan and Barzilay. Method: learns which source-assay data to include for a target assay. Reported: selective inclusion beats pooling all data, especially for moderately similar assays. Code: github.com/Ozymandias314/AssayMatch (stated on the page). Protocol details were not extractable; unverified.
- Reusable: pre-training/transfer data selection for peptide targets (select source families by assay similarity, not pooling).

### 2.2 Pocket-ligand models adapted to a new target

**LigUnity** [opened, PMC12546767] (also candidate #1 above)
- Authors: Feng, Liu, Li, Yang, Zou, Cao, Li, Zhang, Wang; IDEA, XtalPi, UW. Patterns, Sept 2025.
- Regime: hit-to-lead fine-tuning with 20-80% of the measured compounds per target. On the Merck FEP benchmark, about 23 ligands (80% of an average of 29) gave r2 = 0.472. TYK2 active learning on 10,000 FEP-labelled ligands, reported to find highly active compounds within four iterations and to beat other methods by over 40% in r2.
- Method: Uni-Mol-based shared pocket-ligand embedding with scaffold discrimination (contrastive) and pharmacophore ranking (Plackett-Luce listwise); H-GNN pocket refinement at inference.
- Protocol (reported): virtual screening on DUD-E (102 targets), DEKOIS 2.0 (81), LIT-PCBA (15); hit-to-lead on JACS and Merck FEP; time/scaffold/unit splits. Leakage controls reported: training proteins with more than 30% sequence similarity to test proteins removed in stringent evaluations; assays similar to the FEP benchmarks removed and test ligands excluded from pre-training.
- Code: github.com/IDEA-XL/LigUnity. Data: PocketAffDB (about 800k points) on Figshare. Licence: CC BY 4.0 (paper). Model/code licence not verified.
- Assessment: the fine-tune-fraction protocol (20-80%) is far more evidence than our k = 5-25; FEP series are congeneric, so analog lookup is a strong shortcut there. The TYK2 active-learning set is a computed (FEP) oracle, not wet lab. DUD-E has known decoy and analog bias.

**DrugCLIP** [opened sciencenet and Tsinghua pages; arXiv 2310.06367 snippet]
- Team: Tsinghua AIR (Lan Yanyan) + life sciences + chemistry; Science, Jan 2026. Contrastive pocket-molecule retrieval, zero-shot. Reported wet-lab: 15% hit rate on NET (100 picked from 1.6M); 10 of 50 binders for a target without known ligands; genome-scale screen over about 10,000 targets with 500M compounds [snippets].
- Regime: k = 0. No feedback loop described.
- Reusable: the "fake ligand" pretraining idea (protein fragments as pseudo-ligands, ProFSA [snippet]) as a way to obtain pretraining signal for peptide-pocket pairs. Small-molecule pockets; peptide transfer is untested.

**PETA** [opened, papers.cool abstract of arXiv 2608.19906]
- Authors: Lin, Yao, Wang, Ong, Pan. Test-time adaptation updating only LayerNorm parameters (about 0.03%) with pocket-specific generated negatives and mixup. Reported: beats pretrained and fully retrained baselines. Splits, k, code unverified.
- Reusable: a parameter-efficient per-target adaptation for our LM (LayerNorm/adapter only) to avoid overfitting at k = 5-10.

**Adapting Boltz-2 with limited experimental activity data** [opened but PDF unreadable]
- Authors: Furui and Ohue (arXiv 2609.24302). Title claims improved early enrichment from limited labelled actives. Number of actives, splits, decoys and leakage controls could not be extracted; all unverified.

### 2.3 Retrieval, in-context, and LLM-agent works

**MolRAG** (ACL 2025, long.755) [snippet]. Retrieves structurally analogous molecules as context for LLM chain-of-thought. Reported 1.1-45.7% gains over direct prediction. Assessment: this is explicitly analog lookup plus an LLM, so it is the prior art for the "analog retrieval" half of our fusion. It can also be the shortcut in its own results.

**MOLE-RAG** [opened, alphaxiv 2606.05693]. Chan, Kweon, Shin, Bhattacharjee, Jiang, Guo, Han (UIUC, UCSD). Training-free; BM25 literature retrieval, RDKit context, fingerprint-retrieved similar training molecules as few-shot examples. Nine MoleculeNet tasks, scaffold split 8:1:1, three seeds. Reported: e.g. BBBP +28.5 AUROC for Mistral-7B; GNNs still better on some tasks. A snippet says structure-based retrieval is the "most potent single augmentation", up to 20 AUROC points over random few-shot. Assessment: scaffold split is weaker than family-disjoint; retrieval gain supports our NN baseline being hard to beat.

**LLMs for Bayesian Optimization in Scientific Domains: Are We There Yet?** [opened, arXiv 2509.21403]
- Authors: Gupta, Hartford, Liu. Findings of EMNLP 2025.
- Reported: LLM agents showed no sensitivity to experimental feedback (randomly permuted labels had no effect); classical linear bandits and GP optimisation beat them; hybrid **LLMNN** (LLM prior knowledge plus nearest-neighbour sampling) is competitive or better. They advocate separating prior reasoning from posterior-informed batch acquisition.
- Reusable: very high. The permuted-label control should be a mandatory arm in our loop evaluation. The architectural conclusion matches ours: prior knowledge + data-driven posterior.

**ExLLM** [opened, arXiv 2502.12845v5]. Ran et al. Experience-snippet memory, k-offspring, feedback adapter; reported SOTA on PMO; under review. Oracle is a computed property, not a new-target assay. Reusable as a memory-management idea for the dual-memory loop.

**MDForge** [snippet]. Agentic MD pipeline design under sparse reward. Low relevance (pipeline design, not activity).

### 2.4 Active learning and closed loops

- **Active learning in drug discovery reviews/benchmarks** [snippets: Deep Batch Active Learning (eLife reviewed preprint), "Traversing Chemical Space with Active Deep Learning" (ChemRxiv), practical considerations for active ML in drug discovery]. I did not open these; claims such as "up to six-fold improvement in hit discovery" are unverified.
- **Insilico dry-wet closed loop** [snippet]: Rentosertib in Phase III, 18 months and $2.6M preclinical (reported by press, unverified).
- **RFpeptides** [opened, RosettaCommons post]: Nature Chemical Biology, June 20 2025; diffusion design of macrocycles; about 20 macrocycles synthesised per target (MCL1, MDM2, GABARAP, RbtA); MCL1/MDM2 1-10 uM, GABARAP and RbtA sub-10 nM; code integrated into RFdiffusion on GitHub (RosettaCommons). Evidence regime: zero labels, structure-only. Not a feedback loop.
- **HighPlay** (MCTS + HighFold, TEAD4 micromolar) [snippet]; **PepEvolve** [snippet]. Cyclic peptide design with RL; not opened.

### 2.5 Assay heterogeneity

**Kalliokoski, Kramer, Vulpetti, Gedeck, "Comparability of Mixed IC50 Data - A Statistical Analysis"**, PLoS ONE 2013 [opened, PMC3628986]. Reported: independent IC50 measurements of the same protein-ligand pair across sources have sigma(pIC50) = 0.68 (factor 4.8), MUE 0.55; ChEMBL pKi averages 0.35 log units above pIC50 (recommend factor 2.0); filtering removed more than 93% of 616,555 IC50 entries because of unit, subtype and assay-type errors. Reusable: the quantitative noise ceiling and sanity range for our lab offset (an offset estimate far above about 0.7 log units should trigger a check).

### 2.6 Cyclic peptides and macrocycles

**Monomer-aware decoupled global alignment kernels (MD-GAK, PMD-GAK) with Gaussian Processes** [opened, Chalmers page]
- Authors: Amirahmadi, Geylan, De Maria, Etminani, Ohlsson, Tibo; Journal of Cheminformatics 18:108 (2026).
- Data: CycPeptMPDB membrane permeability. Reported: beats graph and language-model baselines across discrimination, calibration, robustness, including scaffold-level robustness. Reproducibility statement present; code details not verified.
- Reusable: GP with a monomer-alignment kernel is an obvious calibrated few-label posterior for cyclic peptides, and a strong baseline at k = 5-25 (property prediction, not target activity).

**Multi_CycGT** (permeability, bioRxiv 2023) [snippet]; **JAMUN**, **RINGER** (conformer generation) [snippet]. Not opened; permeability and conformation, not target activity transfer.

**Gap finding**: I found no published work on cross-target transfer of cyclic-peptide binding activity with k = 5-25 labels, family-disjoint splits and matched decoys. Absence in my searches is not proof of absence (see unverified list).

---

## 3. Mapping to our modules

| Our module | Closest prior art | Note |
|---|---|---|
| Knowledge prior with n0/(n0+k) shrinkage | LLMNN (prior + NN posterior) [opened]; GP/hierarchical Bayes (neural processes) [opened]; MolRAG/MOLE-RAG as unweighted combination [snippet/opened] | None of those that I opened uses an explicit evidence-count-weighted shrinkage of a prior toward data. Gap or my search missed it. |
| Lab/assay offset with anchor compounds | ActFound pairwise differences [snippet+opened reusability]; neural-process assay latent [opened]; Kalliokoski 2013 noise numbers [opened] | Anchor compounds measured in both labs as an explicit calibration set: not seen in what I opened. |
| Stereo-aware analog retrieval | MolRAG, MOLE-RAG, CAMP-style context [snippet/opened] | Retrieval by fingerprint similarity; stereo-awareness not discussed in what I read. |
| Edit-space head | LigUnity pharmacophore ranking (pairwise/listwise) [opened]; ActFound pairwise [snippet] | Pairwise delta heads exist; edit-conditioned prediction on peptides not found. |
| Dual-memory loop | ExLLM experience memory [opened]; CAMP context [opened] | |
| Provenance-aware acquisition | LigUnity TYK2 greedy and explore-exploit [opened]; LLMNN batch acquisition [opened] | No provenance weighting seen. |

---

## 4. Conclusions

### (a) Components worth borrowing (adaptation notes for cyclic peptides)

1. **Permuted-label and no-feedback control arms** (Gupta et al.). Add to every loop evaluation: shuffle the revealed labels, or reveal random compounds, and report how much of the gain survives. Cheap, and it protects the headline from "the model ignored the feedback" and "NN lookup did it all".
2. **FS-Mol-style protocol with a per-target baseline delta** (Stanley et al.). Report delta-AUROC over the best of NN-to-revealed and physchem prior at each k, with confidence intervals across target families. For peptides, task = one target family; support set sizes 0/5/10/25 already match.
3. **Parameter-efficient per-target adaptation** (PETA; LigUnity fine-tuning). At k = 5-10, update only LayerNorm/adapters or a low-dimensional head on the LM, not the backbone. Pair with the n0/(n0+k) shrinkage so the prior dominates at small k.
4. **Calibrated GP head with a monomer-alignment kernel** (Amirahmadi et al.). Use as a strong, uncertainty-aware baseline and as a possible replacement for the edit-space head at small k. Evaluate on CycPeptMPDB-style data for permeability; for binding we need our own data.
5. **Pairwise-difference training for lab offset** (ActFound; neural processes). Training on within-assay differences removes the offset by construction; our anchor-based estimate can then be tested against it as an ablation. Use Kalliokoski's 0.68 log-unit scatter as the expected noise floor. Heed the reusability report: pairwise methods fail without close analogs, which is typical for diverse peptide libraries.

Also cheap: TabPFN/TabICL on LM embeddings as an additional k-shot baseline (arXiv 2606.31126).

### (b) Prior-art risk for our claims (my assessment, from the sources I opened)

- **Evidence-weighted fusion of knowledge priors and analog lookup**: moderate risk. LLMNN (EMNLP 2025) combines an LLM prior with nearest-neighbour sampling and argues for prior/posterior separation; MolRAG-type systems combine retrieval with a knowledge model. An explicit n0/(n0+k) shrinkage was not seen in what I opened, but Bayesian shrinkage is textbook, so the novelty claim should rest on the empirical result and on the controls, not on the form of the fusion. Cite Gupta et al. as closest.
- **Anchor-based lab-offset calibration**: low-moderate. Hierarchical assay models (neural processes) and pairwise approaches (ActFound) handle assay shifts, and Kalliokoski quantifies the problem. Explicit anchor compounds are not in what I opened, so a narrowly worded claim ("anchor-based, explicit, small number of anchors") looks defensible, pending a wider search.
- **Small in-house hybrid vs larger pretrained peptide LMs in a loop**: I found no head-to-head in this survey, and found no large pretrained peptide LM benchmarked in a loop. The nearest comparison class is LLM-agent BO, where larger LMs did not use feedback (Gupta et al.), which supports the framing. Not searched deeply (peptide-specific LMs such as PepLand, PepMLM etc. were not examined); unverified.
- **Family-disjoint, matched-decoy cyclic-peptide benchmark**: low risk of prior art as far as my searches go. CycPeptMPDB is permeability; RFpeptides reports about 20 designs per target, not a benchmark. LigUnity uses a 30% sequence-identity filter and DUD-E/DEKOIS decoys on small molecules. Our novelty would be peptide-specific family-disjoint splits and matched decoys; confirm with a targeted search of macrocycle benchmarks (DEL, MaP, PDB macrocycle sets) before claiming "first".

### (c) Evaluations likely affected by analog lookup or leakage (assessment, tagged)

- **LigUnity hit-to-lead on JACS/Merck FEP** [assessment]: congeneric series with 10-30 ligands per target and 20-80% of compounds used for fine-tuning make nearest-neighbour or Free-Wilson-style interpolation very strong. The paper reports a 30% sequence filter for pre-training, which does not address ligand-level analog overlap within a target. The TYK2 loop uses an FEP oracle (computed), so it shows search efficiency, not wet-lab transfer. Its NN-only baseline, if reported, should be checked.
- **DUD-E / DEKOIS / LIT-PCBA virtual screening used by DrugCLIP and LigUnity** [assessment]: DUD-E is known in the literature for decoy and analog bias; I did not open a source in this session to cite for that, so treat it as a general-knowledge caveat. Their stated mitigation is a sequence-similarity filter, which is protein-level only.
- **MolRAG / MOLE-RAG** [assessment]: retrieval of structurally similar training molecules is the method, and the evaluation is MoleculeNet with scaffold split. Scaffold splits still leave close analogs across the boundary, so reported retrieval gains partly measure analog lookup.
- **ActFound original claims** [assessment]: the reusability report found r2 of 0.01-0.12 on a diverse natural-product set versus higher originally reported values, consistent with performance depending on analog presence in the assay. I did not read the original paper's split details (fetch failed).
- **APN few-shot on Tox21/SIDER/MUV** [assessment]: endpoint property tasks with task-level splits; MUV is built to reduce analog bias, Tox21 is not. No analog control mentioned on the page.
- **RFpeptides** [assessment]: no label-transfer claim, so analog leakage is not the concern; the risk is selection bias (a small number of targets, about 20 designs each, best binders highlighted).
- **ExLLM** [assessment]: PMO-style oracle optimisation with computed properties; says nothing about new-target wet-lab feedback.

---

## 5. Unverified or not done

- Could not identify the "digital drug" work definitively (section 1).
- Not opened (snippet only): ActFound bioRxiv (HTTP 429), DrugCLIP arXiv, MolRAG ACL page, HighPlay, PepEvolve, Multi_CycGT, JAMUN, RINGER, ProFSA, eLife deep batch active learning, ChemRxiv active deep learning, Insilico news items.
- Opened but content too thin to extract protocol: FS-Mol (support-size sweep, results, licence), Boltz-2 adaptation (everything beyond title), neural processes (splits, k), PETA (benchmarks), CAMP (splits), AssayMatch (metrics, splits), tabular ICL (split specifics).
- Not searched: peptide-specific pretrained LMs and their few-shot behaviour; macrocycle binding benchmarks beyond CycPeptMPDB; DEL-based macrocycle ML; FS-Mol successors beyond CAMP (e.g. other FS-Mol-based methods, Meta-MGNN, MHNfs); Bayesian shrinkage priors in pQSAR (Novartis/Merck-style profile-QSAR); stereochemistry-aware retrieval work. Absence in this survey is not evidence of absence.
- DUD-E decoy bias statement is general knowledge, not from a page I opened.
- Chinese-language sources (WeChat, Zhihu) were reachable only through search snippets.
