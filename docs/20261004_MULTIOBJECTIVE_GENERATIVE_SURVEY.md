# Multi-Objective Generative Models for Molecular + Peptide/Macrocycle Design — Sourced Survey & BioMate Design Recommendation

**Date:** 2026-10-04
**Author:** Yaoyun Zhang (xiaoni5122@gmail.com)
**Status:** Literature survey + design proposal. Forward-looking recommendation — the recommended generator is work to be *built*, not a finished/validated system.

---

## 0. Honest gaps, stated first

This survey is grounded in real papers (URLs/DOIs inline). Before the landscape, the load-bearing caveats:

1. **Peptide/macrocycle multi-objective (MO) generation is immature.** The mature MO-generation literature (REINVENT, GFlowNets, qNEHVI BO, MODPO) is overwhelmingly **small-molecule**. Cyclic-peptide generative work exists (GeoCycler, PepALD, FAR-DPO, CP-Composer, HFGuidedDesign) but is **mostly 2025–2026, mostly single- or dual-objective (binding/structure-feasibility), and mostly not yet peer-reviewed** (arXiv preprints). There is **no published, validated 5-objective cyclic-peptide Pareto generator**. We would be building near the frontier, not reproducing a known recipe.
2. **"Recovers the TRUE Pareto front" is almost never *proven*** for real chemical objectives — the true front is unknown. Papers report *relative* hypervolume/front-coverage vs baselines on benchmark oracles (PMO, QM9, DRD2). Treat every "Pareto-true?" cell below as "designed to target the full front" vs "known to collapse to one trade-off," not as a proof.
3. **Our binding-affinity data is "being collected."** Every MO method here needs a usable signal (oracle or preference labels) per objective. With 4 objectives well-covered (permeability = CycPeptMPDB; conformers/stability-proxy = CREMP; structure/synthesizability = PepBDB/RDKit) and **binding thin/absent**, the honest near-term design must degrade gracefully when an objective's signal is weak (e.g. a cheap docking/structure proxy + explicit uncertainty), not pretend to optimize a value it cannot score.
4. **Dataset-count check.** The CycPeptMPDB *paper* reports **7,334** cyclic peptides ([Li et al. 2023, JCIM, 10.1021/acs.jcim.2c01573](https://pubs.acs.org/doi/10.1021/acs.jcim.2c01573)); the live DB has grown since. The brief's "8,466" is plausibly the current web count but is **not the published figure** — verify against the current download before quoting it externally.
5. **Sample-efficiency numbers are benchmark-specific.** "Most sample-efficient" claims (REINVENT, Augmented Memory) come from the PMO benchmark's 10k-oracle-call budget on small molecules ([Gao et al. 2022](https://proceedings.neurips.cc/paper_files/paper/2022/file/8644353f7d307baaf29bc1e56fe8e0ec-Paper-Datasets_and_Benchmarks.pdf)); they do **not** transfer automatically to peptide oracles.

---

## 1. Method families — what the SOTA actually is

### 1.1 Multi-objective RL for generation

**REINVENT4 + MPO (scalarization-in-RL).** REINVENT is an RNN/Transformer SMILES generator steered by RL toward a **Multi-Parameter Optimization (MPO)** score that aggregates per-property components (each mapped to [0,1] via transforms) into a single scalar reward. It is the de-facto industrial baseline and was the **most sample-efficient** model on PMO. *MO mechanism = (weighted) scalarization*: it returns a region of chemical space for one weighting, **not the full Pareto front** in one run. ([Loeffler et al. 2024, J. Cheminformatics 16:20, 10.1186/s13321-024-00812-5](https://jcheminf.biomedcentral.com/articles/10.1186/s13321-024-00812-5))

**Augmented Memory + Beam Enumeration (sample efficiency, same scalarized-RL family).** Augmented Memory adds experience replay + SMILES augmentation on top of REINVENT-style RL and set SOTA sample efficiency on PMO; Beam Enumeration adds self-conditioning via probable substructures. Still **scalarized** MO. ([Guo & Schwaller 2024, JACS Au, 10.1021/jacsau.4c00066](https://pubs.acs.org/doi/10.1021/jacsau.4c00066); [Beam Enumeration, ICLR 2024, arXiv:2309.13957](https://arxiv.org/abs/2309.13957))

**GFlowNets — multi-objective & preference-conditioned (MOGFN).** GFlowNets sample objects with probability ∝ reward, so they natively produce **diverse** candidates (not just the single mode RL collapses to). Two MO variants:
- **MOGFN-PC (preference-conditioned):** condition the policy on a preference vector *w* sampled from a Dirichlet during training; scalarize per-*w* but learn **one model covering all weightings**, sampling diverse Pareto-set members per preference. ([Jain et al. 2023, "Multi-Objective GFlowNets," ICML/PMLR v202](https://proceedings.mlr.press/v202/jain23a/jain23a.pdf))
- **HN-GFN / sample-efficient MOGFN:** hypernetwork-conditioned GFlowNet for sample-efficient MO molecular optimization. ([Zhu et al. 2023, NeurIPS, arXiv:2302.04040](https://arxiv.org/abs/2302.04040))
- **Goal-conditioned GFlowNets** for controllable MO molecular design. ([arXiv:2306.04620](https://arxiv.org/pdf/2306.04620))
GFlowNets' selling point vs RL = **front coverage + candidate diversity**; cost = harder training (flow-matching/trajectory-balance stability) and still oracle-hungry unless combined with a surrogate (genetic-guided GFlowNets, [arXiv:2402.05961](https://arxiv.org/html/2402.05961v1)).

### 1.2 Pareto-based / Bayesian optimization (true-front, sample-efficient, low-throughput)

**qNEHVI (q-Noisy Expected Hypervolume Improvement).** The SOTA MO Bayesian-optimization acquisition: batch, noise-robust, one-step Bayes-optimal for hypervolume, polynomial (not exponential) in batch size. Directly targets **hypervolume of the Pareto front** → recovers the full front (including non-convex regions) far better than scalarized EI. Extremely **sample-efficient** but assumes a **small number of expensive evaluations** over a **fixed/surrogate-modeled search space** — it is an *optimizer/selector*, not a *de-novo generator*. ([Daulton et al. 2021, NeurIPS, arXiv:2105.08195](https://arxiv.org/pdf/2105.08195); chemistry use: [Schotten–Baumann, RSC React. Chem. Eng. 2024, 10.1039/D3RE00502J](https://pubs.rsc.org/en/content/articlelanding/2024/re/d3re00502j))

**Pareto MOEA / Pareto virtual screening.** Classical multi-objective evolutionary algorithms + explicit non-dominated sorting. Demonstrated **superior to scalarization across 3 drug-design case studies** for multi-objective virtual screening. ([Fromer & Coley 2024, RSC Digital Discovery, 10.1039/D3DD00227F](https://pubs.rsc.org/en/content/articlehtml/2024/dd/d3dd00227f))

**Scalarization theory (why it matters).** Linear scalarization **provably cannot reach the non-convex part of a Pareto front**; Chebyshev/Tchebycheff and hypervolume scalarizations can reach all Pareto points. A small set of well-chosen Tchebycheff scalarizations approximates the whole front with high fidelity — the practical bridge between cheap scalarization and true-front methods. ([Smooth Tchebycheff, arXiv:2402.19078](https://arxiv.org/html/2402.19078v1); [Optimal Scalarizations for Sublinear Hypervolume Regret, NeurIPS 2024](https://proceedings.neurips.cc/paper_files/paper/2024/file/4685275b9a6a2c55d78135563dfd50bb-Paper-Conference.pdf); direct molecule comparison: [EHVI vs fixed scalarization, arXiv:2507.13704](https://arxiv.org/pdf/2507.13704))

### 1.3 Preference / RLHF-based alignment (apply RLHF ideas to generators)

**MODPO (multi-objective DPO).** Extends DPO to multiple objectives with an implicit *collective reward model*; produces a **Pareto front of models** for diverse preferences at ~3× less compute than multi-objective RLHF, RL-free and more stable. Proven on LM alignment (safety, long-form QA) — **not yet on molecules**, but directly portable to a molecular/peptide language model. ([Zhou et al. 2024, ACL Findings, arXiv:2310.03708](https://arxiv.org/abs/2310.03708))

**Rewards-in-Context (RiC).** Condition a foundation model on a **reward/objective vector in-context**, then SFT; supports **dynamic preference adjustment at inference** with a single model and only SFT (cheap, stable). The cleanest "condition-the-generator-on-an-objective-vector" recipe. ([Yang et al. 2024, ICML, arXiv:2402.10207](https://arxiv.org/abs/2402.10207))

**DPO on molecular language models (single-objective, proven on molecules).** DPO fine-tuning raised filter-pass rates (52→79%, 53→65%) and increased predicted-active fractions — evidence preference optimization works on *molecular* generators. ([Preference Optimization for Molecular Language Models, arXiv:2310.12304](https://arxiv.org/html/2310.12304))

**DecompDPO (structure-based drug design).** DPO with multi-granularity preference pairs to align *diffusion* models to pharmaceutical needs — bridges RLHF-style alignment and structure-based generation. ([arXiv:2407.13981](https://arxiv.org/abs/2407.13981))

### 1.4 Constrained/guided diffusion & objective-vector conditioning

**PILOT** — equivariant diffusion, pocket-conditioned, **multi-objective guidance via importance sampling** (~4.3× faster than classifier guidance). Strong template for property-steered 3D generation. ([Cremer et al. 2024, Chem. Sci., 10.1039/D4SC03523B](https://pubs.rsc.org/en/content/articlehtml/2024/sc/d4sc03523b))

**Training-free / classifier-guided MO diffusion.** Several 2024–2025 methods steer off-the-shelf diffusion models with multiple property predictors (MUDM, [ICLR 2024](https://openreview.net/pdf?id=X41c4uB4k0); Graph Diffusion Transformers predictor-free guidance, [NeurIPS 2024](https://papers.nips.cc/paper_files/paper/2024/file/0f6931a9e339a012a9909306d7c758b4-Paper-Conference.pdf); DiffMC-Gen, [Adv. Sci. 2025, 10.1002/advs.202417726](https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/advs.202417726); evolutionary training-free guidance, [arXiv:2505.11037](https://arxiv.org/html/2505.11037v1)). Trade-off: training-free guidance is flexible but can **collapse generative paths / go off-manifold** when stacking many gradients ([arXiv:2512.10339](https://arxiv.org/pdf/2512.10339)).

### 1.5 Synthesizability as a first-class objective

**Directly optimizing synthesizability via retrosynthesis** (reward = retrosynthetic route found), and **synthesis-space generation** (generate the *synthetic route*, so every molecule is synthesizable by construction). Strongest guarantee for the "synthesizability" objective. ([Directly Optimizing Synthesizability, arXiv:2407.12186](https://arxiv.org/pdf/2407.12186); [Generative AI for navigating synthesizable chemical space, arXiv:2410.03494](https://arxiv.org/html/2410.03494v1)). Cheap proxies: SA score, RAscore ([PMC8179384](https://pmc.ncbi.nlm.nih.gov/articles/PMC8179384/)). **Caveat:** SA/RAscore are calibrated on small molecules; synthesizability of macrocyclic peptides (coupling, cyclization, non-natural residues) needs a peptide-specific notion — thin evidence here.

### 1.6 Peptide / macrocycle-specific generation (the frontier for us)

| Work | What it does | Objective(s) | Status |
|---|---|---|---|
| **PepALD** ([arXiv:2606.14510](https://arxiv.org/html/2606.14510)) | Autoregressive latent diffusion over HELM monomers; R-group-aware ring closure | De-novo macrocycle generation (distribution) | 2026 preprint |
| **GeoCycler** ([arXiv:2605.23407](https://arxiv.org/pdf/2605.23407)) | Reward-aligned 3D diffusion, constraint-conditioned | Structure/closure + binding, reward-aligned | 2026 preprint |
| **FAR-DPO** ([arXiv:2608.19808](https://arxiv.org/pdf/2608.19808)) | Feasibility-aware robust **DPO for cyclic peptides** | Preference alignment w/ feasibility | 2026 preprint |
| **CP-Composer** ([arXiv:2507.04225](https://arxiv.org/pdf/2507.04225)) | Zero-shot design via composable geometric constraints | Multi-constraint structure | 2025 preprint |
| **HFGuidedDesign** ([PMC13334703](https://pmc.ncbi.nlm.nih.gov/articles/PMC13334703/)) | Discrete diffusion + real-time structure guidance | Structure plausibility + binding | 2025 |
| **DiffPepBuilder** ([arXiv:2405.00128](https://arxiv.org/pdf/2405.00128)) | Target-specific de-novo peptide binder design | Binding/structure | 2024 |
| **MOFormer** ([arXiv:2406.02610](https://arxiv.org/pdf/2406.02610), [PMC12596111](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12596111/)) | **Pareto-based** conditional Transformer for AMPs | Activity + toxicity (true MO) | 2024 |
| **M3-CAD** ([bioRxiv 2024.01.02.573846](https://www.biorxiv.org/content/10.1101/2024.01.02.573846v1.full)) | Multimodal multitask AMP pipeline | Activity + mechanism + low toxicity | 2024 |

**Read:** for *linear* peptides (AMPs), true Pareto MO generation exists (MOFormer). For *cyclic/macrocyclic* peptides, generation is real but the MO story is still binding+feasibility; permeability/synthesizability/selectivity as *simultaneous* generator objectives is largely **unoccupied space** — which is exactly where our CycPeptMPDB + CREMP data give an edge.

**Supporting data assets** (real, verified):
- **CycPeptMPDB** — membrane permeability of cyclic peptides, 7,334 in paper / larger live ([10.1021/acs.jcim.2c01573](https://pubs.acs.org/doi/10.1021/acs.jcim.2c01573)); predictor baseline **CycPeptMP** ([Bib 2024, bbae417](https://academic.oup.com/bib/article/25/5/bbae417/7743192)).
- **CREMP** — 36,198 macrocyclic peptides, ~31.3M xTB conformers; **CREMP-CycPeptMPDB** adds 3,258 peptides with permeability labels ([Sci. Data 2024, 10.1038/s41597-024-03698-y](https://www.nature.com/articles/s41597-024-03698-y); [Zenodo 13334335](https://zenodo.org/records/13334335)).
- **PepBDB** — ~13,489 curated peptide–protein complexes ([Bioinformatics 2019, 35:175](https://academic.oup.com/bioinformatics/article/35/1/175/5050021)); **PepBench** — de-novo binder backbone benchmark, 12 targets ([ProteinQure/pepbench](https://github.com/ProteinQure/pepbench)).

---

## 2. Landscape table (sourced)

Legend — **Pareto-true?**: Full = targets whole front (incl. non-convex) in one model/run; Pref = one model covers front via preference-conditioning; Scalar = one weighting per run (non-convex gaps). **Sample-eff**: relative, benchmark-specific. **Peptide-proven?**: Y small-mol only unless noted.

| Method (family) | What it optimizes | Pareto-true? | Sample-eff | Peptide-proven? | Key ref (URL) |
|---|---|---|---|---|---|
| **REINVENT4 + MPO** (scalarized RL) | Weighted sum of per-property scores | Scalar (single weighting/run) | High (PMO SOTA baseline) | Small-mol; no cyclic-peptide MO | [10.1186/s13321-024-00812-5](https://jcheminf.biomedcentral.com/articles/10.1186/s13321-024-00812-5) |
| **Augmented Memory + Beam Enum.** (RL) | Scalarized MPO, replay-accelerated | Scalar | **Very high (PMO SOTA)** | Small-mol | [10.1021/jacsau.4c00066](https://pubs.acs.org/doi/10.1021/jacsau.4c00066) · [arXiv:2309.13957](https://arxiv.org/abs/2309.13957) |
| **MOGFN-PC** (preference GFlowNet) | Dirichlet-sampled scalarizations, diverse | **Pref (front via w)** | Medium (oracle-hungry unless surrogate) | QM9/small-mol | [PMLR v202 Jain 2023](https://proceedings.mlr.press/v202/jain23a/jain23a.pdf) |
| **HN-GFN / sample-eff MOGFN** | Hypernet-conditioned MO | Pref | Higher (surrogate-based) | Small-mol | [arXiv:2302.04040](https://arxiv.org/abs/2302.04040) |
| **qNEHVI** (MO Bayesian opt) | **Hypervolume** of front, noise-robust, batch | **Full (hypervolume)** | **Very high (few evals)** | Not a de-novo generator; reaction/mol opt | [arXiv:2105.08195](https://arxiv.org/pdf/2105.08195) |
| **Pareto MOEA / Pareto screening** | Non-dominated sorting | Full | Medium | Small-mol virtual screen | [10.1039/D3DD00227F](https://pubs.rsc.org/en/content/articlehtml/2024/dd/d3dd00227f) |
| **Tchebycheff scalarization set** | Minimax scalarizations reaching all points | **Full (non-convex OK)** | High (few scalarizations) | Theory/general | [arXiv:2402.19078](https://arxiv.org/html/2402.19078v1) |
| **MODPO** (multi-obj DPO) | Implicit collective reward, front of models | **Pref (front of models)** | High (RL-free, ~3× < MORLHF) | LMs only (portable) | [arXiv:2310.03708](https://arxiv.org/abs/2310.03708) |
| **Rewards-in-Context (RiC)** | Condition on reward vector, SFT | Pref (inference-time) | **High (SFT-only)** | FMs (portable) | [arXiv:2402.10207](https://arxiv.org/abs/2402.10207) |
| **DPO on molecular LM** | Single-objective chemist preference | Scalar | High | **Molecules (proven)** | [arXiv:2310.12304](https://arxiv.org/html/2310.12304) |
| **DecompDPO** (SBDD) | Multi-granularity prefs on diffusion | Pref-ish | Medium | SBDD molecules | [arXiv:2407.13981](https://arxiv.org/abs/2407.13981) |
| **PILOT** (MO guided diffusion) | Pocket + multi-property importance-sampling guidance | Guidance (not front) | Medium | 3D small-mol ligands | [10.1039/D4SC03523B](https://pubs.rsc.org/en/content/articlehtml/2024/sc/d4sc03523b) |
| **Synthesis-space generation** | Synthesizable-by-construction | n/a (constraint) | High | Small-mol | [arXiv:2410.03494](https://arxiv.org/html/2410.03494v1) |
| **MOFormer** (Pareto Transformer) | Activity + toxicity | **Full (Pareto)** | Medium | **Peptides (AMPs) ✓** | [arXiv:2406.02610](https://arxiv.org/pdf/2406.02610) |
| **PepALD / GeoCycler / FAR-DPO** | Macrocycle gen; binding/feasibility; DPO | Mostly single/dual | Medium | **Cyclic peptides ✓ (early)** | [2606.14510](https://arxiv.org/html/2606.14510) · [2605.23407](https://arxiv.org/pdf/2605.23407) · [2608.19808](https://arxiv.org/pdf/2608.19808) |

---

## 3. Synthesis — what makes the best multi-objective generator

Reading across the families, four findings are robust enough to design on:

1. **Scalarization ≠ the Pareto front.** Linear scalarization provably misses non-convex front regions and needs many runs to sweep trade-offs. A single-weighting REINVENT run is a point tool, not a front tool. If users must *explore trade-offs* (binding vs permeability is a classic peptide tension), the generator must be **preference-conditioned or hypervolume-driven**, not a fixed weighted sum. ([2402.19078](https://arxiv.org/html/2402.19078v1), [D3DD00227F](https://pubs.rsc.org/en/content/articlehtml/2024/dd/d3dd00227f))

2. **One model that covers the whole front beats N retrained models.** Preference-conditioning (MOGFN-PC, RiC) and front-of-models (MODPO) all deliver *inference-time* trade-off control from a single training run — the right ergonomics for a platform where users dial in priorities. RiC/MODPO add **training stability** (SFT/RL-free) that online MO-RL and GFlowNet flow-matching lack.

3. **Oracle cost dominates; separate the expensive objective.** The decisive axis in practice is *how many true evaluations* each objective costs. Permeability and synthesizability we can score cheaply/offline (CycPeptMPDB-trained surrogate; SA/RAscore/retro). Binding is expensive and **data-thin for us**. The best systems **do not treat all objectives symmetrically**: cheap objectives go in the inner generative loop; the expensive/uncertain objective gets a **surrogate + Pareto-BO (qNEHVI) outer loop** that spends real evaluations where they most grow hypervolume. This hybrid (cheap-in-loop generation + qNEHVI selection) is more sample-efficient than making the generator query an expensive oracle directly.

4. **Guarantee what you can; optimize the rest.** Synthesizability and cyclization-feasibility are best handled as **constraints/construction** (synthesis-space generation; CP-Composer-style geometric constraints), not soft rewards — removing them from the objective vector shrinks the front dimensionality and stabilizes training. Diffusion guidance is flexible but **stacking many gradients goes off-manifold** ([2512.10339](https://arxiv.org/pdf/2512.10339)); keep guided objectives few.

**The honest tradeoff triangle:** *Pareto-front coverage* (GFlowNet/qNEHVI/MOEA) ↔ *sample efficiency* (qNEHVI, Augmented Memory, RiC/SFT) ↔ *training stability* (RiC/MODPO SFT >> online MO-RL / flow-matching). No single method maxes all three. The best real system **composes** them.

---

## 4. Recommended design for BioMate's multi-objective peptide/molecule generator

**Objectives:** {binding affinity, membrane permeability, synthesizability, selectivity, stability}.

### 4.1 Architecture — two-tier, "cheap-in-loop generator + Pareto-BO outer loop"

**Backbone generator (modality-split, shared interface).**
- *Cyclic peptides:* an **autoregressive/latent-diffusion generator over HELM monomers** (PepALD-style, [2606.14510](https://arxiv.org/html/2606.14510)) so non-natural residues and ring closures are first-class. Cyclization + geometric feasibility enforced as **hard constraints at decode time** (CP-Composer-style, [2507.04225](https://arxiv.org/pdf/2507.04225)) — removes "feasibility/synthesizability" from the soft-objective set.
- *Small molecules:* reuse a **SMILES language model** (REINVENT-compatible) or a **synthesis-space generator** ([2410.03494](https://arxiv.org/html/2410.03494v1)) so synthesizability is by-construction.
- Shared **preference-vector conditioning input** so both modalities expose the same MO control surface.

**MO mechanism — preference-conditioned generation + hypervolume outer loop (hybrid, not a single trick):**
1. **Inner loop (cheap objectives, high throughput):** condition the generator on a **preference/objective vector** à la **Rewards-in-Context** ([2402.10207](https://arxiv.org/abs/2402.10207)) and/or align it with **MODPO** ([2310.03708](https://arxiv.org/abs/2310.03708)) using preference pairs built from our labeled data. Objectives scored *in-loop* by fast surrogates: **permeability** (CycPeptMPDB/CREMP-trained, CycPeptMP-grade, [bbae417](https://academic.oup.com/bib/article/25/5/bbae417/7743192)), **stability** (CREMP conformer-ensemble features as proxy), **selectivity** (off-target surrogate where data allow). Train preference-conditioned so **one model spans the front** and users dial trade-offs at inference.
2. **Outer loop (expensive/uncertain objective = binding):** a **qNEHVI Bayesian-optimization layer** ([2105.08195](https://arxiv.org/pdf/2105.08195)) over the generator's proposals, with a **GP/uncertainty surrogate for binding** (docking/structure proxy now; wet-lab/assay labels as they arrive). qNEHVI selects the batch that maximally grows **true-front hypervolume**, spending scarce binding evaluations efficiently and **recovering non-convex front regions** that scalarization misses.
3. **Guardrail/validation** (per CLAUDE.md hybrid rule): every generated candidate passes a schema/validity + constraint check (valid HELM, ring closure, allowed monomers, SA/RAscore band) before scoring — invalid drops don't consume binding budget.

### 4.2 Why this composition (grounded in §3)

- **Preference-conditioning (RiC/MODPO)** gives single-model, inference-time front control with **SFT/RL-free training stability** — avoids the flow-matching/online-RL instability of pure MOGFN/MO-RL while still covering the front via preferences.
- **qNEHVI outer loop** supplies the **true-front, non-convex, sample-efficient** optimization that scalarized RL cannot, and spends the expensive binding budget optimally — directly addressing our thin binding data.
- **Constraints over soft rewards** for synthesizability/cyclization shrinks the objective vector from 5 → effectively 3–4 soft objectives (binding, permeability, selectivity, stability), stabilizing training and avoiding off-manifold diffusion-guidance collapse.
- **Data fit:** permeability (CycPeptMPDB) and conformer/stability (CREMP) are exactly the cheap-in-loop signals this design assumes; PepBDB/PepBench seed the binding surrogate and the de-novo backbone prior.

### 4.3 Honest tradeoffs of the recommendation

- **Complexity:** a two-tier hybrid is more moving parts than one REINVENT MPO run. Justified only because (a) binding is expensive/thin and (b) users need trade-off exploration. If a program only needs "optimize one weighting, cheaply," **REINVENT4/Augmented Memory MPO is the correct, simpler baseline** — ship that first as the v0 and the comparison point.
- **Binding is the bottleneck, not the generator.** With binding data "being collected," the qNEHVI layer runs on a *proxy* surrogate initially; front quality on the binding axis is only as good as that proxy. Report binding-axis results with explicit uncertainty; do **not** claim validated multi-objective optimization of binding until real assay labels close the loop.
- **Cyclic-peptide MO generation is unproven at 4–5 objectives.** We are extending PepALD/MOFormer ideas into unoccupied space; expect iteration. Validate incrementally: 2-objective (permeability+feasibility, where we have data) → add stability → add binding last.
- **Evaluation:** there is **no standard 5-objective cyclic-peptide Pareto benchmark**. Build an internal one from CREMP-CycPeptMPDB held-out + a small docking oracle; report **dominated hypervolume and front coverage vs a REINVENT-MPO scalarized baseline** (the Fromer–Coley protocol, [D3DD00227F](https://pubs.rsc.org/en/content/articlehtml/2024/dd/d3dd00227f)), not a single scalar score.

### 4.4 Staged build (matches BioMate's benchmark-driven, verify-each-step discipline)

1. **v0 baseline:** REINVENT4-MPO (small-mol) + a HELM generator with cyclization constraints (cyclic). Scalarized. Establishes the comparison front.
2. **v1:** add preference-conditioning (RiC/MODPO) on cheap objectives (permeability, stability, selectivity) → single model, inference-time trade-offs. Benchmark hypervolume vs v0.
3. **v2:** add qNEHVI outer loop with a binding surrogate. Benchmark non-convex front recovery + sample efficiency on binding evaluations.
4. **v3:** close the loop with real binding/assay data as collected; re-benchmark. Only here claim "multi-objective binding optimization."

---

## 5. References (consolidated)

**MO-RL / generators:** REINVENT4 [10.1186/s13321-024-00812-5](https://jcheminf.biomedcentral.com/articles/10.1186/s13321-024-00812-5) · Augmented Memory [10.1021/jacsau.4c00066](https://pubs.acs.org/doi/10.1021/jacsau.4c00066) · Beam Enumeration [arXiv:2309.13957](https://arxiv.org/abs/2309.13957) · PMO benchmark [NeurIPS 2022](https://proceedings.neurips.cc/paper_files/paper/2022/file/8644353f7d307baaf29bc1e56fe8e0ec-Paper-Datasets_and_Benchmarks.pdf)
**GFlowNets:** MOGFN-PC [PMLR v202](https://proceedings.mlr.press/v202/jain23a/jain23a.pdf) · HN-GFN [arXiv:2302.04040](https://arxiv.org/abs/2302.04040) · goal-conditioned [arXiv:2306.04620](https://arxiv.org/pdf/2306.04620) · genetic-guided [arXiv:2402.05961](https://arxiv.org/html/2402.05961v1)
**Pareto/BO & scalarization:** qNEHVI [arXiv:2105.08195](https://arxiv.org/pdf/2105.08195) · Pareto virtual screening [10.1039/D3DD00227F](https://pubs.rsc.org/en/content/articlehtml/2024/dd/d3dd00227f) · Smooth Tchebycheff [arXiv:2402.19078](https://arxiv.org/html/2402.19078v1) · Optimal scalarizations [NeurIPS 2024](https://proceedings.neurips.cc/paper_files/paper/2024/file/4685275b9a6a2c55d78135563dfd50bb-Paper-Conference.pdf) · EHVI vs scalarization (molecules) [arXiv:2507.13704](https://arxiv.org/pdf/2507.13704)
**Preference/RLHF:** MODPO [arXiv:2310.03708](https://arxiv.org/abs/2310.03708) · RiC [arXiv:2402.10207](https://arxiv.org/abs/2402.10207) · DPO molecular LM [arXiv:2310.12304](https://arxiv.org/html/2310.12304) · DecompDPO [arXiv:2407.13981](https://arxiv.org/abs/2407.13981)
**Diffusion guidance:** PILOT [10.1039/D4SC03523B](https://pubs.rsc.org/en/content/articlehtml/2024/sc/d4sc03523b) · MUDM [ICLR 2024](https://openreview.net/pdf?id=X41c4uB4k0) · DiffMC-Gen [10.1002/advs.202417726](https://advanced.onlinelibrary.wiley.com/doi/full/10.1002/advs.202417726) · path collapse [arXiv:2512.10339](https://arxiv.org/pdf/2512.10339)
**Synthesizability:** directly optimizing [arXiv:2407.12186](https://arxiv.org/pdf/2407.12186) · synthesizable space [arXiv:2410.03494](https://arxiv.org/html/2410.03494v1) · RAscore [PMC8179384](https://pmc.ncbi.nlm.nih.gov/articles/PMC8179384/)
**Peptide/macrocycle:** PepALD [arXiv:2606.14510](https://arxiv.org/html/2606.14510) · GeoCycler [arXiv:2605.23407](https://arxiv.org/pdf/2605.23407) · FAR-DPO [arXiv:2608.19808](https://arxiv.org/pdf/2608.19808) · CP-Composer [arXiv:2507.04225](https://arxiv.org/pdf/2507.04225) · HFGuidedDesign [PMC13334703](https://pmc.ncbi.nlm.nih.gov/articles/PMC13334703/) · DiffPepBuilder [arXiv:2405.00128](https://arxiv.org/pdf/2405.00128) · MOFormer [arXiv:2406.02610](https://arxiv.org/pdf/2406.02610) · M3-CAD [bioRxiv](https://www.biorxiv.org/content/10.1101/2024.01.02.573846v1.full) · MOLLM [arXiv:2502.12845](https://www.arxiv.org/pdf/2502.12845v2) · MolLEO [molleo.github.io](https://molleo.github.io/)
**Data:** CycPeptMPDB [10.1021/acs.jcim.2c01573](https://pubs.acs.org/doi/10.1021/acs.jcim.2c01573) · CycPeptMP [bbae417](https://academic.oup.com/bib/article/25/5/bbae417/7743192) · CREMP [10.1038/s41597-024-03698-y](https://www.nature.com/articles/s41597-024-03698-y) · CREMP-CycPeptMPDB [Zenodo 13334335](https://zenodo.org/records/13334335) · PepBDB [Bioinformatics 35:175](https://academic.oup.com/bioinformatics/article/35/1/175/5050021) · PepBench [ProteinQure/pepbench](https://github.com/ProteinQure/pepbench)
