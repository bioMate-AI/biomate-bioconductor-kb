# Data Scarcity & Novel-Target Generalization in Binder / Peptide / Macrocycle Design — Sourced Survey

**Date:** 2026-10-04
**Scope:** Literature survey (2022–2026) of methods proposed to overcome *training-data scarcity* and to *generalize to novel targets* in protein-binder, peptide, and cyclic-peptide/macrocycle design (with molecular-design context). Recommends honestly-assessed path(s) for our cyclic-peptide program.
**Discipline:** Every claim below is sourced to a real paper with a URL/DOI. Where an approach is only validated in silico, or only on targets with pre-existing data, that limit is stated. **No approach here is claimed to "solve" generalization — I lead with the gaps.**

---

## 0. Our situation (the premise this survey answers)

- **Modality:** cyclic peptides / macrocycles.
- **The wall:** only ~hundreds to low-thousands of *bound* peptide–protein complex structures exist, and far fewer are macrocyclic. PepBDB collects all PDB peptide–protein complexes (peptide ≤ 50 aa) — order ~10³–10⁴ entries, heavily redundant ([PepBDB, *Bioinformatics* 2019](https://academic.oup.com/bioinformatics/article/35/1/175/5050021); [PMID 29982280](https://pubmed.ncbi.nlm.nih.gov/29982280/)). The curated PepBench/PepGLAD split used by recent generative models has **4,157 train + 114 val complexes** total across *all* targets and *all* peptide types ([PepPCBench / PepGLAD context](https://www.biorxiv.org/content/10.1101/2025.04.08.647699.full.pdf)). That is the binding-structure data wall.
- **Targets:** novel / hard (PD-L1, αvβ6) — surfaces with little or no cyclic-peptide binding data.
- **Data we already hold:** permeability (CycPeptMPDB — experimental passive permeability, no structures, [JCIM 2023](https://pubs.acs.org/doi/abs/10.1021/acs.jcim.2c01573)); conformers (CREMP — 36,198 macrocycles / 31.3M conformers, [*Sci Data* 2024](https://www.nature.com/articles/s41597-024-03698-y); permeability-annotated subset CREMP-CycPeptMPDB, 3,258 peptides, [Zenodo 10798262](https://zenodo.org/records/10798262)); structures (PepBDB/PepBench above); **binding affinity being collected** (this is the actual bottleneck — see §4).

The key distinction throughout: *predicting permeability/structure/conformers* is comparatively data-rich; *predicting/designing binding to a novel target* is data-poor. Most "foundation model" wins reported below are on the former, not the latter.

---

## 1. Sourced landscape table

| # | Approach | Overcomes data scarcity? | Generalizes to NEW targets? | Evidence / benchmark | Key ref (URL/DOI) |
|---|---|---|---|---|---|
| a | **Cross-domain generative FM** (UniMoMo: peptides+antibodies+small-mol in one model) | Partially — multi-domain co-training reported to beat single-domain models **in silico** | **Unproven in vitro.** Benchmark wins are docking/geometry metrics, not wet-lab affinity on held-out targets | In-silico binder benchmarks across 3 domains; GPCR case study (computational) | [UniMoMo, arXiv 2503.19300, ICML 2025](https://arxiv.org/abs/2503.19300) |
| a | **Molecular/protein pretraining, transfer to low-data** | Helps **in-distribution** low-data; **does NOT reliably help OOD** | **No** for OOD/new chemotypes — this is the critical honest finding | BOOM: foundation models SOTA on ID, fail OOD; PLMFit mixed | [BOOM, arXiv 2505.01912](https://arxiv.org/pdf/2505.01912); [PLMFit, PMC12309243](https://pmc.ncbi.nlm.nih.gov/articles/PMC12309243/); [TL small datasets, AIP Adv 2024](https://pubs.aip.org/aip/adv/article/14/10/105119/3316780) |
| b | **Meta-learning / few-shot QSAR** (ADKF-IFT, FS-Mol, prototypical/MAML) | Yes — SOTA few-shot regression/classification with 16–256 support points | **Only with a few labeled points from the new target** (not zero-shot); gains shrink vs. simple baselines | FS-Mol benchmark; *but* simple fine-tuning matches/beats meta-learning | [ADKF-IFT, arXiv 2205.02708](https://arxiv.org/abs/2205.02708); [FS-Mol](https://github.com/microsoft/FS-Mol); [**"Is Meta-training Really Necessary?" arXiv 2404.02314**](https://arxiv.org/abs/2404.02314) |
| c | **Active learning / closed-loop BO** (design-make-test) | Yes — reduces experiments needed to converge | **Yes, conditionally** — still needs an initial labeled seed on the target; cold-start unsolved by the loop alone | Iterative peptide design; BO materials loops converge in ~20–44 iterations | [AL/meta for peptides, arXiv 1911.09103](https://arxiv.org/html/1911.09103); [Closed-loop BO, npj/PMC7686338](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7686338/) |
| d | **Physics / structure priors** (RFdiffusion→RFpeptides, AfCycDesign, HighFold, CyclicBoltz, BindCraft, AlphaProteo) | **Yes — the strongest substitute for data today**; priors are target-agnostic | **Yes — demonstrated wet-lab on novel targets**, but with caveats (low raw hit rate, needs in-silico filtering + synthesis) | RFpeptides: 12/39 tested → binders incl. 9.4 nM, <20 designs/target; AlphaProteo 9–88% incl. PD-L1 | [RFpeptides, *Nat Chem Biol* 2025](https://www.nature.com/articles/s41589-025-01929-w); [AfCycDesign, *Nat Commun* 2025](https://www.nature.com/articles/s41467-025-59940-7); [CyclicBoltz1](https://www.biorxiv.org/content/10.1101/2025.02.11.637752v1.full); [AlphaProteo, DeepMind 2024](https://deepmind.google/blog/alphaproteo-generates-novel-proteins-for-biology-and-health-research/) |
| e | **Data augmentation / self-distillation** (from structure predictors) | Partially — scales *structural* training data | **Risk: circularity/bias** — amplifies PDB's well-folded bias; no new binding signal | AF2 noisy-student self-distillation (~300k Uniclust); distillation for inverse folding | [AF2, *Nature* 2021](https://www.nature.com/articles/s41586-021-03819-2); [AF Distillation, arXiv 2210.03488](https://arxiv.org/pdf/2210.03488); [bias probe, PMC13504272](https://pmc.ncbi.nlm.nih.gov/articles/PMC13504272/) |
| f | **Retrieval-augmentation** (RADiAnce) | Yes — reuses known interfaces as templates for low-data sites | **In-silico only so far** — cross-domain interface transfer improves metrics; no wet-lab on novel targets yet | Latent RAG; outperforms baselines on affinity/geometry recovery metrics | [RADiAnce, arXiv 2510.10480, NeurIPS 2025](https://arxiv.org/abs/2510.10480) |
| g | **High-throughput experimental data** (mRNA/phage display + NGS) | **Yes — the real fix.** Generates 10⁶–10¹³ sequence–label pairs *on your target* | **Yes — but target-by-target** (each campaign is one target); then ML generalizes within that target's sequence space | mRNA display up to ~10¹²–10¹⁴; NGS→ML (LSTM/diffusion) correlates with affinity | [mRNA display, PNAS 2001](https://www.pnas.org/doi/10.1073/pnas.061028198); [diffusion on mRNA-display libs, PMC12582155](https://pmc.ncbi.nlm.nih.gov/articles/PMC12582155/); [LSTM from phage display, *Sci Rep* 2021](https://www.nature.com/articles/s41598-021-85274-7) |

---

## 2. Approach-by-approach assessment (what genuinely works vs. hype)

### (a) Cross-domain / transfer pretraining & foundation models
**Claim.** A single model trained jointly across peptides, antibodies, and small molecules transfers interaction knowledge to the data-poor class. UniMoMo (ICML 2025) is the flagship: unified "Graph of Blocks" representation + all-atom autoencoder + E(3)-equivariant diffusion; authors report multi-domain training beats domain-specific models and a GPCR case study generating all three modalities to one site ([arXiv 2503.19300](https://arxiv.org/abs/2503.19300)).

**Honest assessment.** The multi-domain *superiority* is measured on **in-silico docking/geometry benchmarks**, not wet-lab affinity on held-out targets. More damning for the "transfer rescues data scarcity" thesis is the **BOOM** benchmark: current molecular pretraining improves *in-distribution* property prediction but **does not improve out-of-distribution** performance ([arXiv 2505.01912](https://arxiv.org/pdf/2505.01912)). PLMFit similarly finds transfer benefit is task- and split-dependent ([PMC12309243](https://pmc.ncbi.nlm.nih.gov/articles/PMC12309243/)), and transfer only helps "when distribution shifts between upstream and downstream are minimized" — i.e., *not* for a genuinely novel target/chemotype. **Verdict: real for representation reuse and ID low-data; HYPE as a standalone fix for novel-target generalization.**

### (b) Meta-learning / few-shot QSAR
**Claim.** Learn-to-learn across many assays so a new target needs only a handful of labels. ADKF-IFT (deep-kernel GP with implicit-function-theorem bilevel optimization) is SOTA on **FS-Mol** across support sizes 16–256 ([arXiv 2205.02708](https://arxiv.org/abs/2205.02708); [FS-Mol](https://github.com/microsoft/FS-Mol)).

**Honest assessment.** Two hard caveats. (1) **Not zero-shot** — you still need a labeled support set *from the new target* (16+ points); meta-learning reduces, it does not eliminate, the cold-start. (2) The method edge is fragile: **"Is Meta-training Really Necessary for Molecular Few-Shot Learning?" ([arXiv 2404.02314](https://arxiv.org/abs/2404.02314))** shows a plain fine-tuning + Mahalanobis "quadratic-probe" baseline **matches or beats** the elaborate meta-learners on FS-Mol and OOD setups. So the *value* is the few-shot framing (small support → usable model), not any particular meta-architecture. **Verdict: genuinely useful once you have a small target-specific label set; the meta-learning machinery itself is partly HYPE — simple fine-tuning is competitive.**

### (c) Active learning / closed-loop design-make-test
**Claim.** Bayesian optimization over a design→synthesize→assay loop finds binders in far fewer experiments. Demonstrated for iterative peptide design ([arXiv 1911.09103](https://arxiv.org/html/1911.09103)) and across closed-loop materials/chemistry (convergence in ~20–44 iterations vs. random) ([npj/PMC7686338](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7686338/)).

**Honest assessment.** The loop is **sample-efficient but not cold-start-free** — BO needs an initial seed (random or physics-proposed) on the target before its surrogate is informative; the literature quantifies *convergence* iterations, not *cold-start from zero* on a novel protein surface. Its real power is **compounding**: it converts each wet-lab round into a better surrogate, and it is the natural consumer of (d) physics proposals and (g) HT data. **Verdict: genuinely works as the integrating framework; does not by itself overcome cold-start — it must be seeded.**

### (d) Physics / structure priors — *the strongest data substitute today*
**Claim.** Encode cyclic geometry + folding/energy into the prior so little or no target-specific binding data is needed. Evidence is now **wet-lab, not just in-silico**:
- **RFpeptides** (RFdiffusion + cyclic positional encoding): synthesized 77 designs, tested 39, obtained **12 binders including 9.4 nM**, with **<20 designs/target** and X-ray Cα RMSD <1.5 Å to design models ([*Nat Chem Biol* 2025](https://www.nature.com/articles/s41589-025-01929-w)).
- **AlphaProteo** (mini-protein binders, not cyclic): **9–88% experimental success**, 3–300× better affinity than prior methods, **on PD-L1 among 7 targets** ([DeepMind 2024](https://deepmind.google/blog/alphaproteo-generates-novel-proteins-for-biology-and-health-research/)).
- **BindCraft**: one-shot functional binder design with high reported in-vitro success ([biorxiv 2024.09.30.615802](https://www.biorxiv.org/content/10.1101/2024.09.30.615802.full.pdf)).
- Cyclic-aware folding to *score/filter* designs: **AfCycDesign** ([*Nat Commun* 2025](https://www.nature.com/articles/s41467-025-59940-7)), **HighFold/HighFold2/HighFold3** ([BiB 2024, bbae215](https://academic.oup.com/bib/article/25/3/bbae215/7665139)), **CyclicBoltz1** (AF3-framework, non-canonical AAs, median/avg RMSD competitive) ([biorxiv 2025.02.11.637752](https://www.biorxiv.org/content/10.1101/2025.02.11.637752v1.full)); **CycleDesigner** couples RFdiffusion + HighFold for cyclic binders ([biorxiv 2024.11.27.625581](https://www.biorxiv.org/content/10.1101/2024.11.27.625581v1.full)).

**Honest assessment.** This is the only family with **experimental success on novel targets without target-specific training data** — because the prior is physics/structure, which is target-agnostic. Caveats, stated plainly: (1) **raw hit rates are modest and target-dependent** (AlphaProteo's 9% floor; a separate study reports RFdiffusion's low success for *functional* detection binders, [biorxiv 2025.02.07.636769](https://www.biorxiv.org/content/10.1101/2025.02.07.636769.full.pdf)) — you still synthesize and screen tens of designs. (2) Published cyclic wet-lab wins (RFpeptides' RbtA) are **not yet PD-L1/αvβ6 cyclic peptides** — AlphaProteo's PD-L1 result is a *mini-protein*, not a macrocycle. (3) Folding tools (HighFold/CyclicBoltz) are *scorers/filters*, not affinity predictors. **Verdict: genuinely works and is the best current substitute for binding data — but it is a hit-generator requiring a synthesis+assay backend, not an in-silico oracle.**

### (e) Data augmentation / synthetic data (self-distillation)
**Claim.** Predict structures for unlabeled sequences and train on them. AF2 itself used noisy-student self-distillation (~300k Uniclust predictions) to boost accuracy ([*Nature* 2021](https://www.nature.com/articles/s41586-021-03819-2)); distillation of AF confidence improves inverse folding/design ([arXiv 2210.03488](https://arxiv.org/pdf/2210.03488)).

**Honest assessment.** For *structure* this is proven. For *binding/novel targets* it is **circular**: synthetic structures carry no new binding-affinity signal and **amplify the PDB's bias toward compact, well-folded, crystallizable conformers** ([bias probe, PMC13504272](https://pmc.ncbi.nlm.nih.gov/articles/PMC13504272/); [OpenFold generalization, biorxiv 2022.11.20.517210](https://www.biorxiv.org/content/10.1101/2022.11.20.517210v1.full)). Using predictor outputs to train the next predictor risks a self-reinforcing loop that *looks* like more data but adds no ground truth. **Verdict: useful for structural pretraining/conformer coverage (where we already have CREMP); HYPE/dangerous as a substitute for real binding labels.**

### (f) Retrieval-augmentation (RADiAnce)
**Claim.** For a low-data binding site, retrieve known interfaces from a cross-domain database (peptides/antibodies/fragments) and condition generation on them. RADiAnce unifies retrieval + generation in a contrastive latent space + latent diffusion, reporting gains on affinity/geometry/interaction-recovery metrics ([arXiv 2510.10480, NeurIPS 2025](https://arxiv.org/abs/2510.10480)).

**Honest assessment.** Conceptually the best-matched idea to "novel target, few examples" — it explicitly transfers *interface motifs* rather than whole models. But it is **brand-new (Oct 2025) and in-silico only**; the metrics are computational recovery, not wet-lab affinity on held-out novel targets, and retrieval quality is bounded by how similar any catalogued interface is to PD-L1/αvβ6 pockets. **Verdict: promising, worth tracking/piloting; unproven in vitro — do not bank on it.**

### (g) High-throughput experimental data — *the real fix for the wall*
**Claim.** Don't fight scarcity algorithmically — generate 10⁶–10¹³ sequence→binding labels directly on your target via mRNA display (libraries ~10¹²–10¹⁴, [PNAS 2001](https://www.pnas.org/doi/10.1073/pnas.061028198)) or phage display + deep NGS, then train ML within that space. ML on display-derived NGS works: LSTM generative models whose likelihood correlates with affinity ([*Sci Rep* 2021](https://www.nature.com/articles/s41598-021-85274-7)); diffusion models trained on mRNA-display selections produce novel high-affinity binders ([PMC12582155](https://pmc.ncbi.nlm.nih.gov/articles/PMC12582155/)); sequencing depth materially changes conclusions ([IJMS 2023](https://doi.org/10.3390/ijms24065396)). Million-scale experimental screening now drives de novo antibody design too ([mBER, biorxiv 2025.09.26.678877](https://www.biorxiv.org/content/10.1101/2025.09.26.678877.full.pdf)).

**Honest assessment.** This is the one route that **actually removes the data wall** — it manufactures the missing binding labels. Limits: (1) it is **per-target** (each campaign buys one target's landscape; generalization is *within* that target's sequence neighborhood, not automatically to the next novel target); (2) display biases (amplification, composition) must be controlled; (3) it requires wet-lab capability/cost. **Verdict: genuinely breaks scarcity; it is a data-generation program, not a shortcut — and it is the ideal fuel for (b)/(c).**

---

## 3. Synthesis — what genuinely works vs. hype

**Genuinely works (evidence-backed):**
1. **Physics/structure priors (d)** — the only family with *wet-lab* success on novel targets with *zero target-specific binding data* (RFpeptides 9.4 nM in <20 designs; AlphaProteo on PD-L1). This is the real near-term lever for cyclic peptides, via RFpeptides/CycleDesigner proposal + HighFold/CyclicBoltz/AfCycDesign filtering.
2. **High-throughput display + NGS (g)** — the only route that *removes* the binding-data wall rather than working around it; directly produces the labels our program is "collecting."
3. **Active-learning closed loop (c)** — the proven framework to spend wet-lab budget efficiently, *once seeded* by (d) and/or (g).
4. **Few-shot modeling (b)** — real value for turning a small target-specific label set into a usable surrogate; just use simple fine-tuning, not elaborate meta-learning.

**Partly hype / over-claimed:**
- **"Foundation-model transfer solves generalization" (a):** false for OOD/novel targets — BOOM shows pretraining helps ID, not OOD. Transfer is representation reuse, not a generalization guarantee.
- **"Self-distillation = more data" (e):** circular for binding; amplifies PDB bias; no new ground truth.
- **Cross-domain generative & retrieval models (a, f):** architecturally elegant and the right *direction*, but current evidence is **in-silico metrics only** — none has demonstrated wet-lab affinity on a held-out novel target. Treat as pilots, not deliverables.

**The through-line:** nothing overcomes scarcity by algorithm alone. Every method that *demonstrably* reaches a novel target either (i) imports a **physics/structure prior** that needs no binding data, or (ii) **generates the binding data experimentally**. The purely-computational "transfer/retrieval/distillation" stories improve benchmark numbers but have **no wet-lab generalization evidence** on new targets — so do not report them as solved.

---

## 4. Recommended path(s) for our cyclic-peptide case (PD-L1, αvβ6)

We already hold permeability (CycPeptMPDB), conformers (CREMP), and structures (PepBDB/PepBench); binding affinity is the missing axis. Recommended **two-track, loop-coupled** program:

**Track 1 — Physics-prior hit generation (fast, no new binding data needed) → (d).**
- Generate cyclic-peptide backbones for PD-L1 and αvβ6 with **RFpeptides / CycleDesigner** (RFdiffusion + cyclic offset) seeded from the target structures (PD-L1 has abundant structures; αvβ6 has cryo-EM/crystal structures).
- **Filter in silico** with cyclic-aware folding — **HighFold3** and **CyclicBoltz1** (handle head-to-tail cyclization + non-canonical AAs) — plus interface/pLDDT-style confidence and our **CREMP conformer/strain** and **CycPeptMPDB permeability** models as developability gates.
- Synthesize the top tens (RFpeptides-style <20–40/target) and assay. This yields first real binders *and* the seed labels Track 2 needs. **This is the primary near-term recommendation** — it is the only evidence-backed route to novel-target hits without pre-existing binding data.

**Track 2 — Experimental data engine to break the wall (the durable fix) → (g).**
- Run **mRNA/phage display + deep NGS** against PD-L1 and αvβ6 to manufacture 10⁶⁺ target-specific sequence→enrichment labels — the binding data we lack. This is the single investment that most moves our data position, and it directly populates the "binding affinity being collected" axis.

**Loop — couple them with sample-efficient AL → (b)+(c).**
- Feed Track-1 + Track-2 labels into a **few-shot surrogate** (plain fine-tuning per "Is Meta-training Really Necessary?", not heavy meta-learning) and drive an **active-learning / Bayesian-optimization** design→make→test loop. Each round improves the surrogate and the next design batch — this is where sample efficiency compounds.

**Watch, pilot, don't bank on (a, e, f).**
- **RADiAnce (f)** is the most on-point new idea for low-data novel targets (retrieve PD-L1/αvβ6-adjacent interface motifs) — pilot it in silico and validate *only* via Track-1 synthesis; do not treat its metrics as results.
- Use **self-distillation/synthetic structures (e)** *only* for conformer/structure pretraining (where CREMP already helps), never as a binding-label substitute.
- Treat **cross-domain FMs (a)** as representation backbones, with the explicit expectation (BOOM) that they will *not* generalize OOD to our novel targets on their own.

**Honest bottom line.** There is **no published method that provably generalizes to a novel cyclic-peptide target from data alone.** The defensible plan is: physics priors to get first hits now (Track 1), a display+NGS data engine to kill the wall (Track 2), and a sample-efficient AL loop to compound both — with FM/retrieval/distillation as pilots, not promises. Our moat is the **closed experimental loop + proprietary binding data**, not any single model.

---

## Sources (primary)

- UniMoMo — https://arxiv.org/abs/2503.19300 (ICML 2025)
- BOOM (OOD benchmark) — https://arxiv.org/pdf/2505.01912
- PLMFit — https://pmc.ncbi.nlm.nih.gov/articles/PMC12309243/
- Transfer learning, small datasets — https://pubs.aip.org/aip/adv/article/14/10/105119/3316780
- ADKF-IFT — https://arxiv.org/abs/2205.02708 ; FS-Mol — https://github.com/microsoft/FS-Mol
- Is Meta-training Really Necessary? — https://arxiv.org/abs/2404.02314
- Active/meta learning for iterative peptide design — https://arxiv.org/html/1911.09103
- Closed-loop Bayesian active learning — https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7686338/
- RFpeptides — https://www.nature.com/articles/s41589-025-01929-w
- AlphaProteo — https://deepmind.google/blog/alphaproteo-generates-novel-proteins-for-biology-and-health-research/
- BindCraft — https://www.biorxiv.org/content/10.1101/2024.09.30.615802.full.pdf
- AfCycDesign — https://www.nature.com/articles/s41467-025-59940-7
- HighFold — https://academic.oup.com/bib/article/25/3/bbae215/7665139
- CyclicBoltz1 — https://www.biorxiv.org/content/10.1101/2025.02.11.637752v1.full
- CycleDesigner — https://www.biorxiv.org/content/10.1101/2024.11.27.625581v1.full
- RFdiffusion low success for functional detection binders — https://www.biorxiv.org/content/10.1101/2025.02.07.636769.full.pdf
- AlphaFold2 (self-distillation) — https://www.nature.com/articles/s41586-021-03819-2
- AlphaFold Distillation for design — https://arxiv.org/pdf/2210.03488
- Synthetic-alignment bias probe — https://pmc.ncbi.nlm.nih.gov/articles/PMC13504272/
- OpenFold generalization — https://www.biorxiv.org/content/10.1101/2022.11.20.517210v1.full
- RADiAnce — https://arxiv.org/abs/2510.10480 (NeurIPS 2025)
- mRNA display (foundational) — https://www.pnas.org/doi/10.1073/pnas.061028198
- Diffusion on mRNA-display libraries — https://pmc.ncbi.nlm.nih.gov/articles/PMC12582155/
- LSTM from phage-display NGS — https://www.nature.com/articles/s41598-021-85274-7
- NGS sequencing depth, phage display — https://doi.org/10.3390/ijms24065396
- mBER (million-scale screening) — https://www.biorxiv.org/content/10.1101/2025.09.26.678877.full.pdf
- CREMP — https://www.nature.com/articles/s41597-024-03698-y ; CREMP-CycPeptMPDB — https://zenodo.org/records/10798262
- CycPeptMPDB — https://pubs.acs.org/doi/abs/10.1021/acs.jcim.2c01573
- PepBDB — https://academic.oup.com/bioinformatics/article/35/1/175/5050021 (PMID 29982280)
- PepPCBench / PepGLAD splits — https://www.biorxiv.org/content/10.1101/2025.04.08.647699.full.pdf
