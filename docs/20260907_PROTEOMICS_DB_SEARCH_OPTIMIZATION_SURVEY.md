# Optimizing Proteomics Database Search: Faster Matching, More Identifications — A Survey and a Proposal

**Date:** 2026-09-07
**Scope:** Optimization methods for MS/MS (shotgun) peptide-spectrum matching that improve **speed** and **sensitivity** (number of confident matches at a fixed FDR) — and where a new approach could improve both at once.
**Evidence basis:** Three deep-research fan-outs (foundational methods; 2023–2026 latest works; cross-domain fast-retrieval inspiration), each with adversarial 3-vote claim verification. All primary sources peer-reviewed (Nature Methods / Nat Commun / Nat Biotechnol / Nat Comput Sci / MCP / JASMS / Proteomics / JPR) except where explicitly marked preprint or company-authored. Quantitative figures are, where noted, author-reported self-benchmarks on favorable datasets/hardware — read them as illustrative maxima, not universal expectations. **§12 (2023–2026 update) and §13 (cross-domain inspiration) carry the most current material; §11 is the proposal.**

---

## 0. The problem, precisely stated

A shotgun proteomics run produces 10⁴–10⁶ MS/MS spectra. Each spectrum must be matched against a **theoretical search space** of candidate peptides. Two axes govern the outcome:

- **Speed** — wall-clock time to score all spectra against the candidate set. The candidate set explodes with (a) larger databases (metaproteomics, proteogenomics, six-frame translation), (b) more variable modifications, and (c) mass-tolerant / "open" search (±500 Da precursor windows to catch all PTMs), which enlarges the per-spectrum candidate list by orders of magnitude.
- **Sensitivity / match count** — number of peptide-spectrum matches (PSMs), peptides, and proteins accepted at a controlled false-discovery rate (typically 1% FDR via target-decoy). The bottleneck here is not raw scoring but **discrimination**: separating correct matches from the growing cloud of random high-scoring decoys that a large search space produces.

The central tension: **making the search space bigger (to find more) makes it both slower and less specific.** The methods below attack one or both axes. The literature has converged on a **layered stack** — fast indexing for the search itself, then machine-learning rescoring for the discrimination — and the clearest open opportunity is to *fuse* these two currently-separate stages.

---

## 1. Classic database search engines — the scoring foundation

**Input data:** centroided MS/MS peak lists (mzML/mgf/RAW) + a protein FASTA (in-silico digested to peptides with enzyme rules, fixed/variable PTMs).
**Preprocessing:** deisotoping, charge-state deconvolution, peak filtering/normalization, precursor-mass calibration; theoretical fragment (b/y ion) generation per candidate.
**Method:** score observed vs theoretical fragments; assign a statistical confidence; FDR-filter via target-decoy.

| Engine | Scoring core | Optimization contribution | Notes |
|---|---|---|---|
| **SEQUEST** (1994) | XCorr cross-correlation | The foundational algorithm; everything downstream is a lineage from it | Commercial |
| **Comet** | XCorr (SEQUEST successor) | Open-source, actively maintained; **fragment-ion indexing added 2024 (Comet-FI)** cuts search time up to **94%** | UW academic SEQUEST; part of OpenMS/Galaxy/quantms [S9, S-fetch] |
| **Mascot** | Probability-based MOWSE | Long the commercial default; now mostly a comparator/baseline | — |
| **X!Tandem** | Hyperscore + refinement (iterative expansion) | "Refinement" cascade: cheap first pass, then targeted second pass for PTMs/point mutations | Open-source |
| **MS-GF+** | Dot-product on spectral vectors + **generating-function E-values** | **Rigorous statistics → more PSMs.** Exact per-PSM E-value from the full score distribution; auto-derives scoring params from ~1,000 PSMs; works across fragmentation/enzyme/PTM without retuning | **17–38% more PSMs (human), 34–168% (yeast), 37% (phospho) vs Mascot+Percolator** [S1] |
| **Andromeda / MaxQuant** | Binomial peak-probability score | Integrated with MaxQuant quant; handles many PTMs and high peptide-mass accuracy | Free, closed-source |
| **MSFragger** | Hyperscore + **fragment-ion index** | **The dominant algorithmic speedup** — see §2 | [S5] |
| **Sage** (2023) | XCorr-like + fragment index | Rust reimplementation of the index idea; very fast, cloud-friendly | Adopted MSFragger's strategy [S5] |

**Takeaway:** The two things a classic engine can do to help are (a) a **better statistical score** (MS-GF+ shows rigorous E-values alone buy 17–168% more IDs vs Mascot+Percolator) and (b) a **faster candidate lookup** (fragment indexing, §2). These are orthogonal and stackable.

---

## 2. Fragment-ion indexing — the dominant speed lever

**The single most important "faster AND more" result in the survey.**

- **Method (MSFragger, Kong et al., Nat Methods 2017):** invert the problem. Instead of, per spectrum, generating theoretical fragments for every candidate peptide and scoring one at a time, **pre-build an inverted index** of theoretical fragment ions (fragments → the peptides that contain them), organized into mass bins with binary search. An experimental spectrum's peaks then look up all candidate peptides sharing those fragments **simultaneously**, filtering the candidate set before full scoring. [S5]
- **Result:** >100× speedup over conventional engines; **a 500 Da open (mass-tolerant) search becomes feasible in <10 min per LC-MS/MS run.** This is what makes large-space search tractable at all. [S5]
- **Adoption:** the inverted-index idea was subsequently adopted by **Comet-FI** (JPR 2024, up to 94% faster) and **Sage**. It is now the de-facto standard for fast/open search. [S5, S9]

**Why it helps sensitivity, not just speed:** open search recovers PTM-bearing and semi-tryptic peptides that a narrow search never even considers as candidates — so indexing *simultaneously* raises speed and the ceiling on discoverable matches. Speed and open-search sensitivity are coupled.

**Benchmarks used:** HeLa tryptic digests, human/yeast datasets; open-search PTM-discovery on ProteomeXchange sets.

---

## 3. HPC / parallelization — brute-force scale

- **HiCOPS (Haseeb & Saeed, Nat Comput Sci 2021):** an HPC framework for distributed database search. **>100× over most existing HPC proteome-search tools**; completes **tera-scale** search (GBs of MS data against TBs of theoretical DB) in **~100 min on 72 nodes / 1,728 cores vs ~5 weeks on a single 24-core node** (~500×). [S3]
- **Honest caveat (from adversarial verification):** the ~500× figure bakes in a ~72× hardware scale-up. The architecture-level algorithmic gain is the "**>100× over existing HPC tools**" number. GPU scoring specifically is *not* what HiCOPS does — it is CPU-cluster parallelism.

**Takeaway:** HPC buys wall-clock at the cost of hardware; it does not improve *specificity* (match count at fixed FDR). It's the right lever for tera-scale metaproteomics/proteogenomics, not for a single-run sensitivity problem.

---

## 4. FDR control + semi-supervised ML rescoring — the workhorse for match count

**This is where most of the identification gains come from.** Given raw PSMs from any engine, a machine-learning post-processor re-ranks them to sharpen the target/decoy boundary.

- **Percolator (Käll et al., 2007; Percolator 3.0, The et al., JASMS 2016):** train a **semi-supervised SVM** to discriminate correct PSMs from decoys using a feature vector (score, mass error, charge, peptide length, enzyme termini, …). Re-rank by the learned score, then apply target-decoy FDR. [S2]
  - **Scalability:** Percolator 3.0 downsamples the SVM training set to **500,000 PSMs**, cutting peptide-level runtime from ~a full day to **<10 min** and memory from ~100 GB → 30 GB on the **73-million-PSM Kim draft human proteome**; full PSM→protein FDR in **10–15 min** on commodity hardware. Protein-level FDR is handled by grouping proteins by their theoretical-peptide sets and taking the best-scoring peptide per protein. [S2]
- **Mokapot:** Python reimplementation of Percolator; scriptable, integrates DL features easily.
- **Input data:** PSM tables (target + decoy) with per-PSM features. **Preprocessing:** decoy generation (reversed/shuffled DB), feature extraction. **Evaluation:** #PSMs/peptides/proteins at 1% FDR; runtime; memory.

**Takeaway:** semi-supervised rescoring is a "free" sensitivity boost — it adds no new spectra, just better discrimination — and it is the *insertion point* for deep-learning features (§5). Its effectiveness scales with how many informative features you can feed it.

---

## 5. Deep-learning property predictors — the largest recent sensitivity lever

**Mechanism:** for each candidate peptide, a neural network **predicts** its expected fragment-ion intensity pattern, retention time (RT), and ion-mobility/CCS. The **predicted-vs-observed agreement** becomes powerful new features for Percolator/Mokapot, dramatically sharpening target/decoy separation — decoys are random peptides whose predicted spectra *won't* match, so the discrimination improves most where the search space is largest. [S6]

**The predictor ecosystem:**

| Predictor | Predicts | Model | Notable property |
|---|---|---|---|
| **Prosit** (Nat Methods 2019) | fragment intensity + RT | DNN | Trained on **ProteomeTools**: 550,000 tryptic peptides / **21M synthetic spectra**. Integration into search → **more IDs at >10× lower FDR** [S7] |
| **MS2PIP** | fragment intensity | XGBoost gradient boosting | Fast, CPU-only; powers MS2Rescore [S-fetch] |
| **pDeep** | fragment intensity | LSTM/DNN | Early DL MS2 predictor |
| **DeepLC / AutoRT** | retention time | DL | RT prediction for modified/unseen peptides |
| **AlphaPeptDeep** (Nat Commun 2022) | MS2 + RT + CCS | 4-layer transformer (~4M params) + CNN/biLSTM | **40× faster fragment-intensity prediction than Prosit-Transformer** (35 s vs 24 min on 1.4M peptides, same GPU), accuracy at least on par [S8] |
| **DIA-NN predictor** | MS2 + RT + IM | DNN | Powers MSBooster's rescoring features [S6] |

**Rescoring pipelines that package this:**

| Pipeline | Predictor used | Reported gain at 1% FDR |
|---|---|---|
| **MSBooster** (FragPipe) | DIA-NN (RT/IM/MS2) | **+183%** IDs vs MSFragger+Percolator [S6] |
| **Oktoberfest** | Prosit | **+296% PSMs** vs MaxQuant+Percolator on HLA-I [S6] |
| **INFERYS** (Proteome Discoverer) | INFERYS/Prosit | **+50% peptides** on HLA [S6] |
| **MS2Rescore** | MS2PIP + DeepLC | **+46% PSM rate / +36% unique peptides** vs standard Percolator on HLA-I at 1% FDR; **~+300% at 0.1% FDR** [S6, S-fetch] |

**Where the gains are biggest:** immunopeptidomics (non-tryptic MHC peptides), metaproteomics, proteogenomics, single-cell — precisely the **large-search-space** cases where a plain engine's target/decoy separation degrades. **AlphaPeptDeep** on HLA more than **doubled DDA** identifications and nearly **tripled DIA** unique sequences (36,947 vs ~30,000) at 1% FDR — the clearest single-tool demonstration that speed *and* match count improve together. [S8]

**Critical caveat (time-sensitive):** 2025 entrapment / FDR-calibration studies (Nat Methods) raise legitimate concern that DL-rescoring pipelines (and DIA tools) can **underestimate FDR** — so some fraction of the headline 46–296% "more IDs" may reflect FDR inflation rather than true additional correct matches. This qualifies the magnitude; it does not overturn the relative improvement. **Any new method must be validated with entrapment, not just target-decoy.**

---

## 6. DIA (data-independent acquisition) search

**Input data:** DIA runs fragment *all* precursors in wide isolation windows → highly multiplexed, chimeric MS/MS. Cannot be searched like DDA.
**Method:** peptide-centric scoring against a (real or predicted) spectral library, extracting fragment chromatograms and scoring co-elution.

- **DIA-NN (Demichev et al., Nat Methods 2020):** integrated suite using **deep neural networks + interference/signal correction**. Improves both identification and quantification over conventional DIA processing; optimized for **high-throughput, short-gradient** work (deep proteome coverage at 0.5–4 h HeLa gradients vs OpenSWATH/Skyline/Spectronaut). Independent 2023 benchmarks rank it among the highest-sensitivity workflows. [S4]
- **Predicted (in-silico) spectral libraries** — from Prosit/AlphaPeptDeep — remove the need for costly experimental library acquisition and enable **library-free DIA**.
- **Caveat:** the same 2025 FDR-calibration critiques apply to DIA-NN/Spectronaut/EncyclopeDIA at fine FDR granularity.

**Benchmarks used:** HeLa dilution series; immunopeptidomics DIA head-to-heads (Skyline vs Spectronaut vs DIA-NN vs PEAKS, MCP 2023).

---

## 7. Embedding / ANN / clustering — the under-exploited retrieval frontier

These treat spectra as **vectors** and use approximate-nearest-neighbor (ANN) retrieval instead of exhaustive scoring. This is the category most directly relevant to a new "faster + more" method — and, per the research caveats, the one **least benchmarked head-to-head against fragment indexing.**

- **ANN-SoLo (Bittremieux et al., JPR 2018):** open-modification **spectral library** search via ANN. Converts high-resolution sparse spectra to low-dimensional vectors by **feature hashing**, indexes with **random-projection trees (Annoy)** and/or **GPU-powered Faiss** for candidate retrieval, then cascades to exact scoring. Makes open-modification library search fast without a mass-tolerant brute-force scan. [S-fetch]
- **GLEAMS (Bittremieux et al.):** a **Siamese neural network** trained with **contrastive loss** encodes each spectrum into a fixed **32-dimensional embedding**. Enables embedding-based joint analysis / nearest-neighbor clustering of **billions** of spectra across repositories — a learned metric where "same peptide" spectra are neighbors regardless of charge/PTM/instrument. [S-fetch]
- **Spectral clustering (MS-Cluster, MaRaCluster, falcon):** cluster near-identical spectra first, search only cluster representatives → fewer searches, and consensus spectra are cleaner (more sensitive).
- **Casanovo (Yilmaz et al.):** transformer **de novo** sequencing — translates spectrum peaks directly to sequence with **no database**. Relevant as the database-free extreme; useful for novel/variant peptides but not yet a speed/sensitivity replacement for database search on known proteomes. [S-fetch]

**Why this is the frontier:** embeddings turn PSM matching into **vector retrieval**, which has a mature, GPU-accelerated ANN toolchain (Faiss, HNSW, ScaNN) capable of billion-scale search in milliseconds. The open question the research explicitly flagged: *embeddings' speed/sensitivity trade-off has not been rigorously compared to fragment indexing on the same benchmark.*

---

## 8. Immunopeptidomics / large-search-space — the stress test

Non-tryptic MHC peptides mean **no enzyme constraint** → the candidate space is enormous and a plain engine's specificity collapses. This is where every optimization above shows its **largest** effect:
- Fragment indexing makes the wide unconstrained search feasible;
- DL rescoring restores discrimination (Oktoberfest +296%, INFERYS +50%, MS2Rescore +46%/+300%, AlphaPeptDeep 2–3×);
- It is also where **FDR calibration is most fragile** — so it doubles as the best validation battleground.

---

## 9. Benchmark datasets referenced across the field

| Dataset / resource | Use |
|---|---|
| **ProteomeTools** (PXD004732 etc.) | 550k synthetic peptides / 21M spectra — trains/validates Prosit, AlphaPeptDeep, MS2PIP |
| **Kim draft human proteome** (PXD000561) | 73M-PSM scale test (Percolator 3.0 scalability) |
| **HeLa tryptic digest** (standard) | Speed/depth benchmark for engines and DIA gradients |
| **iPRG studies (ABRF)** | Community search-engine comparisons |
| **Human / yeast standard mixes** | MS-GF+ sensitivity benchmarks (5 human, 10 yeast sets) |
| **HLA / immunopeptidome sets** | Large-search-space rescoring benchmarks |
| **ProteomeXchange / PRIDE (PXD…)** | Repository substrate for all of the above + GLEAMS-scale clustering |

**Gap flagged by the research:** there is **no single unified cross-tool benchmark** (fixed accessions + protocol) spanning speed AND sensitivity across engine + rescoring + embedding methods. Each tool self-benchmarks on favorable data. This is itself an opportunity (§11).

---

## 10. Open gaps (the wedge)

The verification surfaced four concrete gaps:

1. **Two-stage architecture is not jointly optimized.** Today: fast index-based candidate search → *then* a separate DL-rescoring pass. The retrieval stage is blind to the rescoring model's notion of similarity, and the rescoring stage can only re-rank what the fast filter already surfaced. Anything the filter drops is unrecoverable.
2. **Embedding-based retrieval is unquantified vs fragment indexing** on the joint speed/sensitivity frontier — named in every review, benchmarked head-to-head in none.
3. **FDR under large-space + DL rescoring is fragile.** 2025 entrapment studies show some of the 46–296% gains may be FDR inflation. Any new method must ship with entrapment validation.
4. **No unified benchmark** ties speed and match count together across method classes.

---

## 11. Proposal: a predictor-informed embedding index that fuses retrieval and rescoring

**Thesis:** the biggest unclaimed win is to **collapse the two stages into one** — make the fast candidate-retrieval step already use the *same* learned similarity that the rescorer uses, so speed and match count are optimized *jointly* instead of sequentially. Concretely:

### 11.0 Framing — acquisition-agnostic, not "DDA search" (addressing "DIA killed DDA")
DIA has won *quantitative profiling of known proteomes* — but that does not retire this problem, it **relocates** it. DIA analysis is *itself* a database/library search + rescore problem (DIA-NN, CHIMERYS, DIA-BERT, DIA-CLIP are all search engines), and the "search a huge space fast with more matches" bottleneck is now **most acute in the large-search-space regimes that span both acquisition modes**:
- **Library-free DIA** must score each spectrum against a **predicted library of the entire proteome** (or, for immunopeptidomics/metaproteomics, far larger) — a **billion-scale ANN retrieval** problem par excellence.
- **Immunopeptidomics** (no enzyme constraint), **open/PTM discovery**, **metaproteomics/proteogenomics** (giant DBs), and **cross-linking MS** (quadratic peptide-pair space) are where every current tool's speed *and* specificity break down — and where ML rescoring already shows the biggest gains (Oktoberfest +296%, AlphaPeptDeep 2–3×).

So PredictedSpec-ANN is framed **acquisition-agnostic** (like CHIMERYS), with the **beachhead = immunopeptidomics + library-free DIA** — the largest space, the biggest documented rescoring gains, and directly relevant to neoantigen/immunology work. This positioning survives "DDA is dead" cleanly: the target is *large/novel search space*, which is wide open regardless of acquisition mode.

### 11.1 Core idea — "PredictedSpec-ANN"
Build a **single embedding space** in which an observed spectrum's embedding is nearest to the embedding of the **DL-predicted spectrum** of its true peptide.

- **Offline (index build):** for the target+decoy peptide space, use a fast predictor (**AlphaPeptDeep** — 40× faster than Prosit, so proteome-scale prediction is cheap) to generate predicted MS2 (+RT +CCS). Encode each predicted peptide into a fixed-length embedding via a **contrastively-trained encoder** (à la GLEAMS, but peptide-conditioned). Index all peptide embeddings in a **GPU ANN index (Faiss/HNSW)**.
- **Online (query):** embed each observed spectrum with the *paired* encoder; **ANN-retrieve top-k peptide candidates in milliseconds**. Because the embedding metric is trained to mirror predicted-vs-observed agreement, the retrieved candidates are *already rescoring-quality* — the retrieval and the rescoring feature are the same distance.
- **Confirm:** exact fragment-match + RT/CCS features → Mokapot for calibrated FDR (this stays, for statistical rigor).

### 11.2 Why this improves *both* axes at once
- **Speed:** ANN retrieval is sublinear and GPU-parallel (billion-scale in ms). No per-spectrum exhaustive scoring; no separate rescoring inference pass over a huge candidate list — the retrieval *is* the scoring for the shortlist. Open/large-space search becomes a k-NN lookup, not a mass-window scan.
- **Match count:** the retrieval metric is predictor-informed, so true peptides that a fragment index would rank below the cutoff (low-intensity, PTM-shifted, non-tryptic) surface as near neighbors. This directly attacks the large-search-space specificity collapse where current gains are biggest.

### 11.3 Validation plan (non-negotiable, per the FDR caveat)
- **Entrapment FDR** (not just target-decoy) on immunopeptidomics + metaproteomics — the fragile cases.
- **Unified benchmark** (fills gap #4): fixed PXD accessions (ProteomeTools, Kim PXD000561, an HLA set, a HeLa gradient), reporting **speed AND #peptides@1% FDR@entrapment** for: Comet-FI, MSFragger+MSBooster, DIA-NN, ANN-SoLo, and PredictedSpec-ANN. Publish the harness.
- **Ablations:** ANN-only (no predictor metric) vs predictor-informed ANN vs full two-stage baseline — isolates the "fusion" contribution.

### 11.4 Staged, de-risked build
- **Phase 0 — reproduce baselines** (no new modeling): stand up MSFragger→MSBooster→Mokapot and DIA-NN on the unified benchmark; establish the speed/sensitivity Pareto front. *This alone delivers a reusable benchmark asset.*
- **Phase 1 — embed & index** existing predicted libraries (AlphaPeptDeep output) with off-the-shelf Faiss; measure ANN-retrieval recall vs fragment index. No training yet.
- **Phase 2 — contrastive encoder** (observed↔predicted pairing, hard negatives from decoys/near-isobaric peptides) — this is the novel core; hard-negative mining is where the sensitivity edge lives.
- **Phase 3 — fuse** retrieval distance into Mokapot features; run entrapment validation; report joint metric.

### 11.5 What already exists — and how §11 must differ (prior-art honesty)
The 2026 literature (§12) shows the fusion idea is **no longer white space** — so the contribution must be sharpened, not claimed as first-of-kind:
- **DIA-CLIP** (Feb 2026 preprint) already builds a contrastive dual-encoder aligning peptides and DIA spectra for zero-shot PSM inference. **Differentiator:** DIA-CLIP is DIA-specific and (as published) a *scoring/inference* model, not a *retrieval index over the peptide search space*. §11's novelty must be the **candidate-retrieval-as-ANN** half — replacing the fragment-index prefilter itself with a predictor-informed embedding index — and demonstrating it on **DDA open/large-space search** where DIA-CLIP does not operate. If DIA-CLIP generalizes first, pivot to the DDA open-search + immunopeptidomics niche and the unified benchmark asset.
- **CHIMERYS** already fuses predicted-spectrum scoring with per-spectrum LASSO deconvolution — but scores per spectrum, it does not *retrieve* candidates by embedding. **Differentiator:** §11 attacks the *candidate-generation* bottleneck (sublinear ANN over the whole peptide space), which CHIMERYS still solves by conventional candidate lookup.
- **GLEAMS/DreaMS** prove spectrum embeddings work at repository scale but embed *spectra for clustering*, not *peptides for database retrieval*. **Differentiator:** §11's index is over **predicted peptide spectra** (the searchable space), with the observed spectrum as the query — a cross-modal retrieval, not spectrum-spectrum clustering.

### 11.6 Concrete design tricks borrowed from §13
- **Hard-negative mining from the live ANN index (ANCE-style):** during contrastive training, mine near-isobaric / same-precursor-mass decoy peptides as hard negatives directly from the current index — the single biggest sensitivity lever in DPR/ANCE, and a natural fit since decoys are already the proteomics hard-negative source.
- **Prefilter cascade (Foldseek/MMseqs2/Sage):** don't discard fragment indexing — use it (or a coarse PQ-quantized embedding pass) as a cheap first stage, then embedding-ANN, then exact fragment-match re-scoring. Each stage cheaper and more permissive than the next.
- **Product quantization / compact vectors (Faiss/DiskANN):** keep the whole human (or metaproteome) peptide index in RAM/SSD at billion scale with millisecond queries.
- **NCE calibration (Oktoberfest):** calibrate predicted spectra to the run's collision energy before embedding, so predicted↔observed alignment isn't degraded by instrument mismatch.

### 11.7 Risks (stated honestly)
- Embedding recall may trail exact fragment indexing on *easy* narrow searches (index is already <10 min/run there) — the win must come on **large/open** spaces; scope the claim accordingly.
- FDR calibration of a learned retrieval metric is exactly the thing 2025 entrapment work flags — **entrapment validation is the make-or-break**, not an afterthought.
- ProteomeTools/AlphaPeptDeep predictor quality bounds the index quality; PTM/charge coverage gaps propagate. Mitigate with transfer-learning fine-tuning on the target instrument class (AlphaPeptDeep supports this).

### 11.8 Fit with BioMate
This is a data-centric retrieval capability: a spectrum/peptide **embedding index** is the same infrastructure pattern as BioMate's existing tool/workflow vector search (UnifiedToolSearch/VectorToolSearch) — build the ANN index once, reuse it for search, clustering, and repository-scale dereplication. A `proteomics_db_search` workflow with a `rescoring: {none|percolator|dl|embedding}` toggle slots into the existing Nextflow/Batch execution model; the benchmark harness (Phase 0) is a natural addition to the benchmark suite (a `proteomics_search` capability with speed + IDs@1%FDR targets).

---

## 12. Latest works (2023–2026 update) — verified current

A dedicated second research pass confirms the state of the art is current and, importantly, that **the field is already moving toward the exact fusion the proposal targets** — a contrastive dual-encoder for PSM assignment now exists as a preprint. This *sharpens* rather than kills the proposal (see §11.7). Three converging waves:

**Wave 1 — fragment-indexed engines matured and went open/cloud.**
- **Sage (Lazear, JPR 2023):** open-source clean-room Rust reimplementation of MSFragger's fragment indexing — a **multi-level index (fragment mass → precursor mass) that skips any candidate sharing no fragments**. Blazing narrow *and* open (>500 Da) search, ~2,500 PSMs/CPU-sec; cloud-friendly, now embedded in many pipelines. **This is the archetypal prefilter cascade a fused index should build on.** [L1]

**Wave 2 — data-driven rescoring (DDR) now *exceeds* traditional database search, with FDR validated.**
- The MCP 2024 review states outright that predictor-based rescoring "**is exceeding the performance of peptide identification from traditional database search engines**." Mature multi-tool ecosystem: **MS2Rescore** (MS2PIP+DeepLC; multi-engine incl. Sage/MS-GF+/Mascot), **Oktoberfest** (Prosit/MS2PIP/AlphaPeptDeep via Koina; adds spectral-library gen, **NCE calibration**, and rescoring; MIT, pip-installable), **MSBooster** (DIA-NN predictions + MSFragger), INFERYS, DeepRescore, inSPIRE. [L2, L3]
- **Head-to-head calibration check (Castaño & Beaudry, Proteomics 2025):** on a standard HeLa DDA digest, DDR added **+40–53% peptides and +64–67% PSMs at 1% FDR** over the MaxQuant baseline, and — crucially — **entrapment false-match rate stayed near the nominal 1%** (Oktoberfest best/most robust at 1.12% FMR), at 50–77% added compute. This is the reassuring counter-point to the FDR-inflation critiques: *properly done*, DDR gains survive entrapment. [L4]

**Wave 3 — transformer / foundation spectrum encoders and contrastive dual-encoders (the frontier the proposal lives in).**
- **DIA-CLIP** (arXiv/bioRxiv **Feb 2026 preprint — architecture verified, metrics self-reported**): a **contrastive dual-encoder + encoder-decoder** that learns a **unified cross-modal latent space aligning peptide sequences with DIA spectral/XIC features**, enabling **zero-shot PSM inference** with *no per-run training* (vs today's per-run semi-supervised rescoring). Author-claimed +45% protein IDs / −12% entrapment IDs. **This is the closest published parallel to §11 — treat it as prior art to differentiate against, not ignore.** [L5]
- **DIA-BERT** (Nat Commun 2025): encoder-only transformer (8 attention blocks after conv layers) learning directly on the **raw peak-group matrix (330×16)**, no handcrafted features; pretrained on **~276M precursors**, per-file fine-tuned; reported +51% proteins / +22% precursors vs DIA-NN while recalling 98%/86% of DIA-NN's IDs (self-reported; benchmark figures 2-1 verified). [L6]
- **Tesorai Search** (bioRxiv 2024 → MCP 2026, **company-authored**): a pretrained PSM model trained on **100M+ *real* peptide-spectrum pairs, never seeing decoys** — directly targeting decoy-based FDR miscalibration. **Cite the design/training regime only; its headline +170% figure was refuted 0-3 and must not be cited.** [L7]
- **Noble-lab foundation model** (arXiv May 2025): pretrains a spectrum encoder with **de novo sequencing as the pretraining task**; representations transfer to spectrum-quality, chimericity, phospho, glyco tasks, **especially in low-data regimes** — the pretraining substrate an embedding index needs. [L8]
- **DreaMS** (Nat Biotechnol 2025): **116M-param transformer, self-supervised (masked-peak + retention-order) on ~700M spectra** (GeMS/GNPS), producing **1024-d embeddings**, SOTA on spectral similarity — proof that self-supervised spectrum embedding scales to repository size. **GLEAMS** (Nat Methods 2022): 32-d **Siamese contrastive** spectrum embedder for similarity search over compact vectors. Together they validate the **embedding + vector-search** half of the proposal at massive scale. [L9]
- **CHIMERYS** (Nat Methods 2025): spectrum-centric, acquisition-agnostic (DDA/DIA/PRM); models chimeric MS2 as a **non-negative L1-regularized (LASSO)** linear combination of pure spectra, driven by **INFERYS predicted fragment intensities + RT** — i.e., it *already fuses predicted-spectrum scoring with per-spectrum deconvolution*. On a 2 h HeLa run: **238,795 PSMs at 1% FDR, >85% of spectra yielding ≥1 PSM, two-thirds multiplexed.** The clearest existing precedent for merging scoring and assignment (though per-spectrum LASSO, not embedding retrieval). [L10]

**Updated FDR caveat (strengthened):** the 2024–2025 entrapment literature (Wen et al., Nat Methods 2025; Freestone/Keich/Noble; Winnow) shows DIA and ML-rescoring tools *can* systematically under-control FDR — so self-reported "+51%/+45%/SOTA" gains may partly reflect FDR inflation. But Castaño & Beaudry 2025 shows entrapment-clean DDR gains are real when calibrated. **Conclusion: entrapment validation is mandatory, and it is achievable — the proposal must include it, not fear it.**

---

## 13. Cross-domain fast-retrieval inspiration (verified)

Every domain that solved "faster **without** losing recall" used the **same recipe**: replace expensive per-pair scoring with a **two-tower / dual-encoder that pre-encodes one side into a compact index**, then **retrieve candidates by cheap similarity** (dot-product or k-mer match) **before any heavy rescoring on the survivors**. The verified evidence:

| Method | Data | Method / architecture | KEY TRICK (fast without losing recall) | Benchmark | Speedup |
|---|---|---|---|---|---|
| **DrugCLIP** [C1] | protein-ligand pairs (PDBBind) | CLIP-style **contrastive dual-encoder** (Uni-Mol pocket + ligand); screening = **dense retrieval**, no binding-affinity labels | **In-batch negatives** (N×N pairs; diagonal=positive, off-diagonal=negative) to manufacture negatives from scarce labels + **HomoAug** (transfer ligand onto homologous pockets) to expand positives | DUD-E, LIT-PCBA; genome-wide AF2 screen | **pre-encode once → dot-product**; ~6B Enamine in <30 h; **up to ~10⁷× vs docking** (Science 2026); trillion-scale screen in ~24 h on 8×A100 |
| **Foldseek** [C2] | protein 3D structures | **3Di structural alphabet** (each residue's nearest spatial neighbor → 20-state code via **VQ-VAE trained for evolutionary conservation**); then sequence-style search | **Quantize a continuous descriptor into a compact discrete vocabulary** so retrieval is cheap token/k-mer matching, not 3D superposition | SCOPe40 all-vs-all; AlphaFoldDB | **4,000×–184,600×** vs DALI/TM-align/CE (942-res query: 6 s vs 33 h vs 10 d) at **86–133% of their sensitivity** |
| **MMseqs2** [C3] | protein/DNA sequences | **3-stage cascade**: k-mer prefilter → SIMD ungapped align → SIMD Smith-Waterman | **Similar-k-mer matching** (600–60k similar k-mers/query k-mer → large k=7 keeps recall) + **double-consecutive-match-on-same-diagonal** + **cache-friendly** binning; stage 1 removes ~99.9%, stage 2 ~99% → full align on ~10⁻⁵ of targets | matched vs BLAST/PSI-BLAST | **36× vs BLAST** (matched sensitivity); **433× vs PSI-BLAST** (higher sensitivity) |
| **knnProtT5** [C4] | ProtT5 per-protein embeddings | mean-pool per-residue PLM embeddings → 1024-d vector; **HNSW ANN** (faiss, M=42, efSearch=256) | **Learned embedding + graph ANN as an alignment-free candidate generator** — finds remote homologs alignment misses | remote-homology detection | dense vector retrieval, complement to MMseqs2 prefilter |
| **DPR / ANCE** *(established practice; not in verified set)* | text passages | two-tower BERT; retrieval as MIPS over Faiss | **in-batch + BM25 hard negatives (DPR); ANCE mines hard negatives from the *live* ANN index during training** | MS-MARCO / open-QA | the canonical hard-negative-mining lever for embedding retrieval |
| **ANN libraries** *(established practice)* | any vectors | Faiss (IVF + **product quantization**, GPU), HNSW (graph, log-time), ScaNN (anisotropic quant.), DiskANN (SSD) | **product quantization / graph indexing** keeps billions of vectors in RAM/SSD at **millisecond query** | ANN-Benchmarks; BigANN | billion-scale, ms latency |

**The four transferable tricks that go straight into §11:**
1. **Pre-encode-once + dot-product retrieval** (DrugCLIP) — the whole reason it beats docking by 10⁷×; the whole reason an embedding index beats per-candidate scoring.
2. **Manufacture negatives when labels are scarce** (DrugCLIP in-batch negatives + HomoAug) — proteomics already *has* the negatives (decoys, near-isobaric peptides); mine them as hard negatives.
3. **Prefilter cascade: cheap discrete/k-mer/coarse-ANN stage → vectorized/exact rescore only on survivors** (Foldseek, MMseqs2) — rescoring runs on ~10⁻⁵ of the space, so it can be as expensive (accurate) as you like.
4. **Discretize + quantize for compactness** (Foldseek 3Di VQ-VAE; Faiss PQ) — keep the whole peptide index in memory at repository scale.

**Synthesis:** the winning recipe everywhere is **(learned embedding) + (cheap prefilter cascade / ANN) + (hard-negative mining) + (exact re-scoring on the shortlist)**. Proteomics has each ingredient *in isolation* (Sage prefilter; GLEAMS/DreaMS embeddings; DL rescoring) but **has not composed them into one cascade for database search**. DrugCLIP is the proof-of-existence that this recipe delivers order-of-magnitude wins in a label-scarce molecular-retrieval problem structurally identical to ours — and DIA-CLIP (§12) is the first proteomics system reaching for it.

---

## 14. How to generate the benchmark (the missing unified asset)

**Core problem:** real proteomics data has **no absolute ground truth** — you never fully know which peptides were truly present. So you cannot benchmark on one dataset. The design triangulates **three complementary ground-truth sources**, each answering a question the others can't, and measures **speed and match-count on the same runs** so the two axes are never decoupled.

### 14.1 Three ground-truth sources (triangulation)

| Source | What it gives | Question it answers | Example data |
|---|---|---|---|
| **A. Entrapment database** | Known-false sequences mixed into the target DB — any match to them is (almost surely) wrong | **Is the claimed 1% FDR real?** (calibration/honesty) | Human SwissProt **+** a controlled ratio of entrapment sequences (shuffled human, or a phylogenetically distant proteome) |
| **B. Synthetic peptide library** | You *know* exactly which peptides were synthesized → any ID outside that set is false | **True precision/recall**, and **retrieval recall@k** for our ANN stage | **ProteomeTools** (PXD004732 / PXD010595): 550k peptides, 21M spectra |
| **C. Defined species mixture** | Known proteomes at known ratios | **Realistic complexity + quant accuracy + foreign-ID rate** | **LFQbench / iPRG** human+yeast+*E. coli* mixes (DDA *and* DIA) |

Plus two **stress-test** sets (no new ground-truth mechanism, they probe scaling):
- **Immunopeptidomics HLA** set — the large-search-space regime (no enzyme rule) where gains and FDR fragility are largest.
- **Kim draft human proteome** (PXD000561) or a metaproteome — sheer-scale stress for speed/memory.

### 14.2 The entrapment mechanism (the calibration innovation)
This is what makes the benchmark *honest* and directly answers the 2025 FDR-inflation critiques:
1. Build `target.fasta` (real proteome) + `entrapment.fasta` at a **fixed known ratio** (e.g., 1:1 or 1:8). Entrapment sequences = shuffled-target or a distant organism that cannot be present.
2. Run each method to its claimed 1% FDR (target-decoy / mokapot).
3. **Estimate the *actual* false-match rate** from entrapment hits: `FMR ≈ (entrapment IDs × 1/ratio) / target IDs` (paired-entrapment estimator, Wen/Freestone/Keich-Noble).
4. **Report the calibration curve:** claimed FDR (x) vs measured FMR (y). A calibrated method sits on the diagonal; an FDR-inflating method bulges above it. *A method that finds "+50% more IDs" but sits above the diagonal is disqualified, not celebrated.*

### 14.3 Metrics (both axes, on the same runs)

**Speed / cost** (from the Nextflow trace, not self-report): wall-clock per run; **PSMs/CPU-sec**; peak RAM; scaling narrow→open (±500 Da); throughput vs DB size. N≥3 replicates for variance.
**Sensitivity:** #PSMs, #peptides, #proteins **at 1% target-decoy FDR**.
**Calibration (the honesty metric):** measured FMR at claimed 1% (source A); precision/recall vs known set (source B); foreign-proteome ID fraction + quant-ratio recovery (source C).
**Retrieval-stage metric (isolates *our* contribution):** **recall@k** — does the true peptide (known from source B) appear in the ANN/index shortlist before rescoring? Compare embedding-ANN vs fragment-index shortlists at matched k. This separates *retrieval quality* from *rescoring quality* — critical for diagnosing where a gain comes from.
**Headline:** a **Pareto frontier of speed vs entrapment-clean IDs** — the single plot the whole survey has been missing.

### 14.4 Fair-comparison controls (avoid the self-benchmark trap the survey flagged)
Every method gets: **identical FASTA** (same target+entrapment), **identical search settings** (enzyme, missed cleavages, variable PTMs, precursor/fragment tolerance), **the same downstream FDR estimator** (mokapot) applied uniformly, the **same EC2 instance type + thread count**, and documented warm/cold cache. Pin every tool version in a container. Publish the harness + accessions so numbers are reproducible — the opposite of the per-tool favorable-dataset self-benchmarks that dominate the literature.

### 14.5 Harness architecture (BioMate-native)
```
proteomics_search_benchmark  (Nextflow → AWS Batch)
  fan-out over (dataset × method):
    method ∈ {Comet-FI, MSFragger→MSBooster, Sage, MS-GF+, DIA-NN, PredictedSpec-ANN}
    each container:  mzML + FASTA(target+entrapment) → normalized PSM table
      columns: spectrum_id, peptide, protein, score, q_value, is_entrapment, is_synthetic_true
  → capture runtime/memory from Nextflow trace/report (speed axis, machine-measured)
  → scoring aggregator (run_code / Python):
      compute IDs@1%FDR, entrapment FMR, precision/recall, recall@k, quant accuracy
      emit Pareto front + calibration curves
  → store results + provenance (data-centric; reproducible)
```
- **Universal PSM-table contract** is the key interface — every engine's native output (pepXML/mzIdentML/parquet) is normalized to one schema so scoring is engine-agnostic.
- Speed is read from the **executor trace**, never from a tool's own log — apples-to-apples.

### 14.6 Phasing (de-risked; Phase 0 is already a shippable deliverable)
- **Phase 0 — baselines only (no new modeling):** run Comet-FI / MSFragger+MSBooster / Sage / DIA-NN across sources A+B+C, produce the Pareto front + calibration curves. **This alone is the unified benchmark asset the field lacks** — publishable and reusable independent of our method.
- **Phase 1 —** add retrieval recall@k measurement on ProteomeTools; drop in embedding-ANN retrieval (off-the-shelf Faiss over AlphaPeptDeep-predicted spectra) and compare recall@k vs fragment index.
- **Phase 2 —** add PredictedSpec-ANN end-to-end; report on the *same* frontier + entrapment curve. A win = **up-and-to-the-right on the Pareto front while staying on the calibration diagonal.**

### 14.7 Phase 0 is scaffolded (2026-09-07)
Phase 0 is built and locally validated — see `docs/20260907_PROTEOMICS_SEARCH_BENCHMARK_PHASE0.md`. Harness at `evaluation/datasets/proteomics_search_benchmark/` (spec + Nextflow `main.nf` + `prepare_search_db.py` + `normalize_psms.py`) and scorer at `scripts/score_proteomics_search_benchmark.py`. Scoring and DB-prep self-tests pass; the stub DAG runs green with correct multi-file fan-out. Uses only engines BioMate already has (Comet, MS-GF+) on registry datasets (PXD000612, PXD001854); a real Batch run is the gated next step (the first run validates `normalize_psms.py` column mapping before any headline number).

### 14.8 Fit with BioMate's benchmark-driven loop
Register as a `proteomics_search` capability alongside the existing suite (targets: e.g. **IDs@1%FDR ≥ MSFragger+MSBooster baseline; measured FMR ≤ 1.3%; ≥5× faster on open search**). Per the CLAUDE.md loop: benchmark reveals a gap → fix via BioMate (workflow/rule/model) → **re-run to verify the gain is real and entrapment-clean**, never tune the benchmark to the method.

---

## Sources (verified, peer-reviewed)

- **[S1]** Kim & Pevzner, *MS-GF+ makes progress towards a universal database search tool for proteomics*, Nat Commun 2014 — nature.com/articles/ncomms6277
- **[S2]** The et al., *Fast and accurate protein FDR estimation (Percolator 3.0)*, JASMS 2016 — link.springer.com/article/10.1007/s13361-016-1460-7
- **[S3]** Haseeb & Saeed, *HiCOPS: high-performance computing framework for tera-scale database search*, Nat Comput Sci 2021 — nature.com/articles/s43588-021-00113-z
- **[S4]** Demichev et al., *DIA-NN: neural networks and interference correction for DIA proteomics*, Nat Methods 2020 — nature.com/articles/s41592-019-0638-x / pubmed 31768060
- **[S5]** Kong et al., *MSFragger: ultrafast peptide identification via fragment-ion indexing*, Nat Methods 2017 — nature.com/articles/nmeth.4256; nesvilab.org/software.html; Comet-FI, JPR 2024 — pubs.acs.org/doi/10.1021/acs.jproteome.4c01094
- **[S6]** Declercq/Bouwmeester et al., *rescoring review*, MCP 2024 — mcponline.org/article/S1535-9476(24)00088-4; MSBooster, Nat Commun 2023 — nature.com/articles/s41467-023-40129-9; MS2Rescore, MCP 2022 — pmc.ncbi.nlm.nih.gov/articles/PMC9411678
- **[S7]** Gessulat et al., *Prosit*, Nat Methods 2019 — nature.com/articles/s41592-019-0426-7
- **[S8]** Zeng et al., *AlphaPeptDeep*, Nat Commun 2022 — nature.com/articles/s41467-022-34904-3
- **[S9]** Eng et al., *Comet*, Proteomics 2013; *A Deeper Look into Comet*, JASMS 2015; github.com/UWPR/Comet
- **[S-fetch]** (extracted, primary, single-source — treat as strong but not triple-verified): ANN-SoLo (JPR 2018, pubs.acs.org/doi/10.1021/acs.jproteome.8b00359); GLEAMS (biorxiv 483263); Casanovo (github.com/Noble-Lab/casanovo); MS2PIP; Comet-FI 94% figure.

**Latest-works sources (§12, 2023–2026 pass; verified except where marked):**
- **[L1]** Lazear, *Sage*, J Proteome Res 2023 22(11):3652–3659 — doi 10.1021/acs.jproteome.3c00486; github.com/lazear/sage
- **[L2]** Declercq/Bouwmeester et al., rescoring review, MCP 2024 — pmc.ncbi.nlm.nih.gov/articles/PMC11269915
- **[L3]** Picciani et al., *Oktoberfest*, Proteomics 2024 — doi 10.1002/pmic.202300112; github.com/wilhelm-lab/oktoberfest
- **[L4]** Castaño & Beaudry, DDR head-to-head + entrapment, Proteomics 2025 — pmc.ncbi.nlm.nih.gov/articles/PMC11962579; doi 10.1002/pmic.202400225
- **[L5]** *DIA-CLIP* — arXiv:2602.01772 / bioRxiv 2026.02.09.704949 (**preprint; architecture verified, metrics self-reported**)
- **[L6]** *DIA-BERT*, Nat Commun 2025 — nature.com/articles/s41467-025-58866-4 (benchmark figures 2-1 verified/self-reported)
- **[L7]** *Tesorai Search*, bioRxiv 2024.08.19.606805 → MCP 2026 (**company-authored; design facts only — +170% figure refuted, do not cite**)
- **[L8]** Sanders et al. (Noble lab), *Foundation model for MS proteomics*, arXiv:2505.10848 (2025)
- **[L9]** Bushuiev et al., *DreaMS*, Nat Biotechnol 2025 — s41587-025-02663-3; PMID 40410407; github.com/pluskal-lab/DreaMS. GLEAMS — Bittremieux et al., **Nat Methods 2022, 19:675–678** (note: a DOI returned by search, 10.1021/acs.analchem.3c00260, is a *misattribution* to a different metabolomics embedder — use the Nat Methods cite)
- **[L10]** *CHIMERYS*, Nat Methods 2025 — s41592-025-02663-w; pmc.ncbi.nlm.nih.gov/articles/PMC12074992
**Cross-domain sources (§13, verified):**
- **[C1]** Gao et al., *DrugCLIP*, NeurIPS 2023 — arXiv:2310.06367; github.com/bowen-gao/DrugCLIP; genome-wide application: *Science* 2026, doi 10.1126/science.ads9530 (speedup/trillion-scale figures are author-reported extrapolations; an independent expert flagged generalization/memorization concerns about the screen, not the speed)
- **[C2]** van Kempen et al., *Foldseek*, Nat Biotechnol 2023 — s41587-023-01773-0; pmc.ncbi.nlm.nih.gov/articles/PMC10869269
- **[C3]** Steinegger & Söding, *MMseqs2*, Nat Biotechnol 2017 — doi 10.1038/nbt.3988
- **[C4]** Schütze et al., *knnProtT5 / nearest-neighbor on embeddings*, Front Bioinform 2022 — doi 10.3389/fbinf.2022.1033775
- **DPR / ANCE / Faiss / HNSW / ScaNN / DiskANN** — cited as established retrieval practice (not part of the verified proteomics claim set; standard references: Karpukhin et al. 2020; Xiong et al. ICLR 2021; Johnson et al. Faiss; Malkov & Yashunin HNSW; Guo et al. ScaNN; Subramanya et al. DiskANN).

**Verification note:** first pass 25/25 verified (0 killed); second pass 24 confirmed with two explicitly-flagged downgrades (DIA-CLIP/Tesorai metrics), one refuted sub-claim (Tesorai +170%), and one source-pointer correction (GLEAMS DOI). §13 cross-domain figures (DrugCLIP/Foldseek/MMseqs2/knnProtT5) verified 3-vote; DPR/ANCE/ANN-library items are established-practice references, not from the verified proteomics claim set. The **[S-fetch]** items (ANN-SoLo, GLEAMS, Casanovo, MS2PIP details) were extracted from primary sources but not part of the final triple-verified set — cited as strong-but-single-source. The cross-cutting **2025 entrapment/FDR-calibration caveat** applies to every DL-rescoring and DIA figure above and is built into the proposal's validation plan.
