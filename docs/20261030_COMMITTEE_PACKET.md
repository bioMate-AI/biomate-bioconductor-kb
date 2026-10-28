# BRIEF TO REVIEWERS
You are one of an independent AI review committee (reviewers from different labs). A small team is building a hybrid knowledge+neural cyclic-peptide language model ('IH-LM', in-house, loop-native) and evaluating it in a retrospective closed-loop replay on public data. Everything below is our own material. STATUS: retrospective only on public literature data; NO measured data from our own wet-lab campaigns exists; several experiments are pending (marked [PENDING]). Be demanding, specific and honest; do not be agreeable. Mark anything you are unsure of as [UNVERIFIED]; do NOT invent citations, authors, numbers or venues. Give concrete fixes and rank issues by severity.


===== MASTER PLAN =====
# Master plan and critical path — "loop improves the LLM; small ≈ large" study (2026-10-29)

Single deliverable: one manuscript (docs outline in `20261028_CYCLIC_PROGRAM_MANUSCRIPT_INVENTORY.md` §F) with verified results only. Hypotheses: `20261029_HYPOTHESES_SMALL_LLM_LOOP.md`; comparison dimensions: `20261029_MODEL_COMPARISON_ANALYSIS_SPEC.md`.

## Workstreams, owners, dependencies
| id | workstream | output | depends on | status (2026-10-29) |
|---|---|---|---|---|
| WS2 | loop replay (L5 GBM controlled loop; L7 model comparison: GBM, atom LM, v4-subset, ChemBERTa, larger pretrained peptide/chemistry LMs fine-tuned (not NLP LLMs), 5 controls) | yield curves, controls, cost | adapters (exist: LoopModel/AtomLoopModel); frozen lists only for held-out recovery | L5 running on spot; L7 prereg done, not run — **critical path #1** |
| WS3 | benchmark instrument (analysis I; M2→M3 typicality fix; run_s3 harness) | validity-gated held-out recovery | none | M2 invalid (typicality control 0.665); M3 in progress — critical for the recovery metric |
| WS1 | v5 small model (corpus filter, trainer, staged training, stereo eval, cost meter) | upgraded small model | WS3 folds (done), corpus filter, trainer | not trained; **not on critical path** (atom LM serves as small model if v5 slips) |
| WS4 | stratification and substructure-effect analysis | strata, matched-pair effects, feature families | none | running |
| WS5 | knowledge-base audit and gap prototypes | KB verdicts, mined rules (leak-safe) | WS4 matched pairs (read-only) | running |
| SV | literature survey and prior-art table | related work, novelty risk | none | running |
| WS6 | manuscript writer (non-result sections) | Intro, Related Work, Methods, Hypotheses, Limitations, figure plan, result placeholders | SV (related work), docs | to start |
| S2 | physics-chain pilot on 60 αvβ6 compounds | chain-executed arm | owner approval (cap USD 80) | gated |

## Critical path (what determines finish time)
1. **WS2 runs L7 now with existing models** (GBM, atom LM, ChemBERTa, v4-subset, larger pretrained peptide/chemistry LMs fine-tuned (not NLP LLMs), 5 controls). Yield-based metrics need no frozen lists. This alone yields the central comparison. Do not wait for v5 or M3.
2. **WS3 M3** → validity-gated held-out recovery for the same models (adds the generalisation metric). Runs in parallel with step 1.
3. **Aggregation** (me): L5/L7 aggregates, comparison analysis (13 dimensions), figures.
4. **WS6 assembles** the manuscript; result sections filled only from aggregated, audited numbers.
Off the critical path (upgrade if ready): v5 (WS1), KB-mined rules (WS5), S2 chain arm.

## Gates (nothing proceeds past a gate without it)
- Pre-registration committed before any scored run (dated amendment).
- Planted-signal positive control passes per adapter/scorer before any null is believed.
- Benchmark validity gate: no-target and typicality controls must be CI-compatible with chance before arms are judged.
- Shuffled-label feedback must not improve (leak check); data-matched one-shot control reported.
- Audit-first on every unexpected result (suspect our own code).
- Every number in the manuscript traces to a committed artifact; unverified items tagged.

## Compute and cost caps (spot only; tag project=cyclic-selector)
L5 (running, per-task checkpointed); L7 frontier-LLM in-context estimate-first, stop above USD 25; v5 stage 1 stop above USD 40 against the HIGH end of the spot-price range; S2 USD 80 cap, **not started without owner approval**. Real spot prices (us-west-2, 2026-10-29): g6.xlarge 0.43–0.69, g6.2xlarge 0.45–0.92, g4dn.xlarge 0.25–0.27 USD/h.

## Definition of done (first full draft)
Methods and evaluation design complete; L5 and L7 aggregates with CIs and controls; model comparison on the 13 dimensions where data exist; held-out recovery on analysis I (and M3 if its validity gate passes); related work with verified citations and a prior-art risk table; limitations stated (retrospective only; generation needs wet lab; narrow task); all audits listed in `20261028_CODE_DATA_EVAL_AUDIT_LOG.md` plus workstream audit docs.


## Correction (2026-10-30)
'Large LLM' = large pretrained cyclic-peptide/chemistry LMs, not NLP LLMs. OpenRouter/in-context arms retired from the central comparison (≈USD 4.3 spent on exploratory runs; paid calls off). Model candidates: docs/20261030_PEPTIDE_CHEM_LM_MODEL_SURVEY.md (in progress).


## Definition update (2026-10-30)
The subject model is the in-house hybrid loop-native cyclic LLM (IH-LM), not 'small'. Comparators = external pretrained peptide/chemistry LMs fine-tuned plainly + baselines; required same-base ablation ladder (plain → +K_phys → +lab offset → +retrieval → +edit heads). See HYPOTHESES doc 'Definition update' and HYBRID proposal 'IH-LM definition'.

## Restructure (owner, 2026-10-30): two aims, one paper
[...truncated for packet...]

===== HYPOTHESES =====
# Hypotheses: a small LLM with a feedback-and-knowledge loop versus baseline and large LLMs (2026-10-29)

Status: **hypotheses only, written before the L7 replay or any v5 run; not yet registered as a formal amendment.** Each hypothesis states its prediction, the measurement that tests it, and what would falsify it. Registration (dated amendment in `PREREG_LOOP.md` and the v5 prereg) must precede any scored run. Companion: `20261029_MODEL_COMPARISON_ANALYSIS_SPEC.md` (13 measured dimensions).

## 0. Central claim (owner)
A small LLM (≈25 M parameters, atom-level; v5) inside a closed loop with verified feedback and knowledge is **comparable to or better than larger pretrained cyclic-peptide / chemistry language models** (fine-tuned on the same revealed labels with the same loop and knowledge) — NOT general-purpose NLP LLMs (owner clarification 2026-10-30), and better than a fingerprint gradient-boosted baseline, on peptide property/binding ranking.
- **Non-inferiority form:** small+loop yield ≥ 90 % of the strongest large peptide/chemistry LM + loop yield, lower 95 % CI bound above 90 %.
- **Superiority form:** lower 95 % bound of (small+loop − large+loop) > 0.

## Definition update (owner, 2026-10-30): the "small LLM" is the IN-HOUSE hybrid cyclic LLM
"Small" is no longer a claim. The subject model is an **in-house, owned, hybrid (symbolic + neural), loop-native cyclic-peptide LLM** (IH-LM): an open-weight or own base (e.g. PeptideCLM-2 weights if cleared, or our atom LM) plus our hybrid layers (K_phys knowledge prior, lab/source offset with anchors, analog retrieval, edit-space heads, rule-constrained decoding) and a loop update interface (fast symbolic memory + slow neural memory, uncertainty-aware). Its size is whatever the design needs. The central claim: **IH-LM + loop matches or beats external pretrained peptide/chemistry LMs fine-tuned plainly on the same revealed labels (same loop, same controls).** Required ablation: SAME base with vs without the hybrid layers, to attribute any gain to the hybrid design and not the base; parameter/GPU-hour cost is a secondary reported quantity. H5 and the non-inferiority rule apply with "IH-LM" in place of "small model". Hypotheses H1–H4 are tested on IH-LM vs plain fine-tuned bases and vs the baselines.

## 1. Facts the hypotheses rest on (measured this session; sources in the audit logs)
1. The loop with a fingerprint GBM beats random selection in the within-source setting (L3: in-distribution 226.7 vs 50.0, +176.7 [146, 209]; scaffold-shifted 62.5 vs 29.9, +32.6 [16, 52]); the in-distribution regime has near-duplicate leakage by design (22.9 % of pool peptides share a fingerprint with an initial peptide).
2. CycPeptMPDB: 6,960 peptides = 2,460 flat structures; 4,912 peptides (71 %) are in groups of ≥2 stereoisomers (largest 116); median within-group label spread 0.86 log units (up to 1.73 in one lab's series). The baseline fingerprint ignores chirality (2,380 distinct fingerprints).
3. v4 audit: binding "win" at chance against hard negatives on 4/5 targets; target prefix barely used; DPO shifts permeability only.
4. Benchmark: all knowledge/rule arms at chance on the family-disjoint analysis (strongest baseline AUROC 0.620); knowledge-base coverage is 0/46 targets for the gate.

5. Baseline error analysis (2026-10-29, `20261029_BASELINE_ERROR_ANALYSIS.md`): chirality-aware fingerprints raise Spearman only ~0.05 (0.713→0.766 random CV; 0.663→0.712 grouped); the worst errors are not concentrated in stereoisomer groups; small/diverse sources are worst (Faris ρ 0.49, Bhardwaj 0.42); 28 % of identical-fingerprint pairs are label cliffs (>1 SD).

## 2. Hypotheses
**H1 — Sample efficiency.** Pretraining plus knowledge gives the small LLM a prior that reduces the number of revealed labels needed. *Prediction:* the LLM's learning curve is above the baseline's at small n (25–100 labels) and the gap shrinks with n (consistent with prior weight w = n0/(n0+n)). *Measure:* labels-to-reach-baseline-final-performance; area under the learning curve. *Falsified if:* the baseline's curve is not below the LLM's at any n in the pre-specified grid, or the labels-to-baseline ratio's CI includes 1.

**H2 — Stereochemical resolution.** Explicit stereo/topology tokens let the LLM rank stereoisomers that the chirality-blind baseline cannot distinguish. *Prediction:* within-flat-group Spearman ≈ 0 for flat-feature baselines (**only under a single seeded revealed/target split per group; leave-one-out evaluation gives an artifactual negative value — a leave-one-out group-mean predictor scores exactly −1.0; see 20261029_BASELINE_ERROR_ANALYSIS.md**) and > 0 for the LLM, in the held-out-group and SAR settings. *Falsified if:* the LLM's within-group Spearman CI includes 0, or it does not exceed a chirality-aware fingerprint GBM (the fair stereo-aware baseline).

**H3 — Knowledge helps when feedback is scarce.** Rules/knowledge-base signals add most at small n and little at large n. *Prediction:* knowledge-on minus knowledge-off gap decreases with n and is positive at the smallest n for the LLM. *Measure:* the gap per n with CI. *Falsified if:* the gap is zero at all n, or if the model's predictions do not change under the counterfactual probe (rule removed or contradicted). Note the benchmark found knowledge arms at chance; the loop test is distinct (knowledge enters as prior/fusion inside feedback), but this is the least supported hypothesis.

**H4 — Transfer.** A pretrained representation transfers across targets and scaffolds, so the small LLM's advantage persists on held-out target families. *Prediction:* positive small-n advantage on family-held-out folds (`folds_v1.csv`), not only in-distribution. *Falsified if:* the advantage appears only in-distribution or only within one lab's series (shortcut check, dimension 4).

**H4b — Few-label new-target adaptation (cross-target with increasing evidence).** For a held-out target family, performance as a function of revealed labels k ∈ {0, 5, 10, 25} for that target. *Predictions (written before any scored run):* (i) at k=0 all arms are near chance (consistent with the zero-shot null; strongest baseline AUROC 0.62 on analysis I); (ii) all arms, including nearest-neighbour to the revealed compounds, improve with k, largely by matching analog series — so the gain over k=0 alone is not evidence for the LLM; (iii) the test is the gap: LLM minus the strongest baseline (nearest-neighbour to revealed; GBM fit on revealed only; pretrained GBM fine-tuned on revealed) at each k, expected steepest between k=0 and 5 and diminishing after 10; (iv) strong heterogeneity across families. Evidence types are separate conditions: binders only; binders plus measured inactives; knowledge (pharmacophore) only; combinations. *Measures:* gain over k=0, learning-curve slope, labels to reach a fixed AUROC, LLM-minus-baseline gap with family-cluster bootstrap CIs, target counts and power per k. *Falsified (for the LLM claim) if:* the gap's CI includes 0 at all k, or the typicality/no-target validity control exceeds chance. Limits: median target has ~5 cyclic compounds (138 targets ≥50), so only ~100–200 targets qualify; zero-shot expected null, as in the field (3–8 %).

**H5 — Small ≈ large when information is equal.** With the same labels and knowledge, the cost-adjusted performance of the small cyclic-peptide LM in the loop matches larger pretrained peptide/chemistry LMs fine-tuned the same way, because the task is narrow and the information is in the feedback and knowledge, not in pretraining scale. *Prediction:* non-inferiority rule satisfied at lower cost (parameters, USD, latency). *Falsified if:* a larger pretrained peptide/chemistry LM + loop exceeds the small model by more than the margin on the primary metric, or its zero-shot/frozen score already saturates the task (then the loop adds nothing for it; report).

## 3. Competing and null hypotheses (must be reported if they win)
- **N1:** the fingerprint GBM is as good as or better than any LLM at every n (a known outcome on small tabular chemistry data) → the paper's claim reduces to the evaluation design and the stereo-resolved result, if any.
- **N2:** larger pretrained peptide/chemistry LMs dominate through pretraining scale (including possible corpus contamination) → report the contamination check; the small-model claim fails on this task.
- **N3:** apparent gains come from locating one laboratory's series (2020_Townsend holds 52.8 % of within-source hits) → report pick provenance; claims restricted to source-diverse subsets.
- **N4:** feedback does not matter (data-matched one-shot equals the loop; shuffled-label feedback also "improves") → leak or no loop effect; either way the loop claim fails.

## 4. What a retrospective test can and cannot show
Supports: learning from graded feedback, better ranking/selection, sample efficiency, stereo-resolved prediction. Does **not** support: that the model generates better novel molecules (new molecules have no labels); that requires a prospective wet-lab round. The paper states this limit.

## 5. Controls and rules applying to every hypothesis
[...truncated for packet...]

===== HYBRID ARCHITECTURE PROPOSAL =====
# Hybrid symbolic–neural architecture for the cyclic-peptide loop — proposal (2026-10-30)

Status: **proposal; no result.** Subject = the IN-HOUSE hybrid, loop-native cyclic LLM (IH-LM; owner 2026-10-30): owned weights/training/update logic, base = open-weight pretrained peptide LM or our atom LM, not necessarily small. Written before any test. Every component below is a hypothesis with a test; prior-art risk is unchecked unless stated. Evaluation rules (leave-labs-out, family-disjoint, H4b few-label, controls, validity gates) apply to all of it.

## Relation to the earlier hybrid design (added 2026-10-30 after reading it; this proposal did NOT start from it)
Already surveyed, designed and largely built before this session (`20261015_GENERATION_SYSTEM_MASTER.md`, `..._SURVEY_AND_ARCHITECTURE.md`, `20261015_DETAILED_DESIGN_SYMBOLIC_NEURAL_LEARNINGS.md`, `20261013_RULE_VS_NOVELTY_AND_PATH.md`, `20261015_LESSONS_AND_GENERATION_SYSTEM_UPGRADE.md`, `20261021_RULE_CONSTRAINED_GENERATIVE_ARCHITECTURE.md`): the **SNG neurosymbolic pattern** — rules outside the LLM (deterministic: pharmacophore, FTO claims, developability, mechanism) constrain and reject; the LLM proposes in the free space; a verifier scores; the loop revises. Built: target KB (avb6, pdl1), rule induction (`rule_induction.py`), FTO claim layer, rule-conditioned generator, consolidated verifier `score.py`, closed optimiser loop `loop.py`, neural proposer (v4) `neural_generator.py`, expensive-tier dispatch `physics_dispatch.py`, mechanism-matched `scorer_config.py`, reward → DPO bridge (`reward.py`). Its lessons, which this proposal must respect: (i) binding is the easy axis; candidates die on hard gates (selectivity, developability, FTO/novelty, mechanism-correct physics, pharmacophore geometry); (ii) **rules are a good filter and a poor generator** (a fixed-scaffold rule can only emit molecules inside the patented genus); novelty lives in scaffold-hop, ncAA at free positions and the construct; (iii) the moat is the closed loop with an honest verifier, not the generator.
Its own listed stand-ins/gaps (2026-10-15, and this session's audits): `revise` = deterministic repair, not a learned policy; the neural proposer is target-agnostic and palette-restricted; the expensive tier only reads precomputed results and there is no admissible αvβ6 ΔG; ILP is minimal (induced rules for 2 targets from 3+4 and 1+3 examples); the rule-constrained DPO checkpoint trained with a no-op gate; "retrospective closed-loop learning" (challenge C2) was built-synthetic only.
**What this proposal adds relative to that design (not a replacement):** (a) knowledge priors validated *within source* and across labs (K_phys, edit effects) instead of curated rules whose flagship (N-methyl count) is weak and inconsistent within source (median within-lab ρ 0.01–0.10; about half of labs positive depending on the lab filter: KB validation 7/8 labs at ≥2 groups and 6/10 at ≥1 group, WS5 audit 9/18; the pair-level addition effect is real, +0.25 [0.16,0.34]); (b) an explicit lab/source random effect with anchor calibration; (c) analog-retrieval conditioning because analog lookup dominates; (d) a measured retrospective replay (L5/L7, H4b, leave-labs-out) that is exactly challenge C2; (e) the dual-memory loop as the *learned* `revise`/update policy the earlier design left as a stand-in. **What it must not do:** drop the hard-gate verifier ladder, the FTO/novelty layer or the (H, X) rule artefact; and it inherits the genus lesson — symbolic knowledge is used as prior/filter and for edit proposals, not to fix the scaffold.

## Lessons from this study that shape the design (all measured, sources in the audit logs)
1. Cross-lab generalisation is the real failure: Spearman ≈0.67–0.71 grouped by structure vs ≈0.30 leave-labs-out. Source offsets dominate pooled data.
2. A zero-fit physchem knowledge channel (K_phys: TPSA, HBD, logP, Veber, within-source) reaches median per-lab ρ 0.25 on unseen labs — comparable to learned models — but the KB has 73 statements and covers 12/793 targets.
3. Edit-level effects are real and consistent where the absolute rule is not: adding an N-methyl, +0.25 [0.16, 0.34] within source (33,398 pairs); D↔L flips have no consistent direction (SD 0.52) and must be learned in context.
4. With a few revealed labels for a target, nearest-neighbour to the revealed compounds wins (AUROC 0.75→0.87 at k=5→25): data are analog series; analog lookup is the strong baseline, the zero-learning physchem rule ties the loop under scaffold shift, and the loop's picks concentrate in one lab (69 %).
5. Fingerprint models fail on unseen monomers; descriptor channels survive. In-context large LLMs trail a GBM with the same labels at the cheap tier.

## Architecture: knowledge as the base model, neural as the residual, the loop learns both memories
Prediction for compound x in assay/lab s: y = f_K(x) + b_s + g_θ(x | retrieved analogs) + ε.
- **Symbolic memory (fast, interpretable, versioned):** rule/edit priors with effect sizes, CIs, provenance and validity scores (K_phys, N-methyl-addition, D-flip zero prior; extended by mining). Updated by the loop in closed form (conjugate/shrinkage; weight n0/(n0+n)); each rule carries its leave-labs-out validity.
- **Source/lab term b_s as an explicit random effect,** estimated from a few anchor compounds per assay/lab. This turns the largest failure (lab offsets) into a modelled quantity and lets pooled data be used.
- **Neural memory (slow):** a small pretrained peptide LM (reuse, not scratch) with stereo/topology tokens and an open vocabulary; fine-tuned on revealed labels; conditioned on retrieved revealed analogs (retrieval-augmented), because analog lookup is the strongest baseline.
- **Loop:** acquisition by expected information gain over rules, lab offsets and analog series (not greedy yield), with cost-aware routing across the verifier ladder (rules → cheap physics → co-fold/MM-GBSA); graded results update both memories.

## Candidate creative components (each = hypothesis, test, kill criterion)
**C1 Edit-space modelling.** Model and propose *edits* (N-Me at i, D-flip at j, residue swap, ring change) with transferable effect priors; the LLM proposes edits from a measured parent, the symbolic layer supplies the prior, the neural term corrects per scaffold. *Test:* leave-labs-out edit-effect prediction vs absolute-property models; *kill:* no gain over K_phys + analog baseline.
**C2 Hierarchical lab-offset calibration with anchors.** Include k anchor peptides per assay/lab; estimate b_s; pool data across labs. *Test:* leave-labs-out Spearman with vs without anchor calibration at k=3,5,10; *kill:* gain <0.03 Spearman.
**C3 Dual-memory loop.** Symbolic memory learns fast from few labels, neural memory later; show the crossover n*. *Test:* learning curves per memory, knowledge-on/off, shuffled-label control; this is H1/H3 operationalised.
**C4 Retrieval-augmented small LM.** Condition the LM on the k nearest revealed analogs plus rules; the contribution over plain nearest-neighbour is the measured quantity. *Kill:* no gain over NN at any k.
**C5 Constrained decoding with induced rules on a pretrained base.** Rules mined from graded loop data (not 9 hard-coded predicates; not 2-target toy sets) enforced at decoding; compare constrained vs unconstrained generation validity/novelty only (retrospective cannot score novel molecules; wet lab needed).
**C6 Structure-derived interface rules.** Mine hotspot/pharmacophore motifs from the 776 bound-cyclic complexes (training families only) to give target-side knowledge for unseen targets. *Test:* few-label and zero-shot analysis I with vs without; *kill:* control-adjusted gain ≤0.
**C7 Learned verifier routing.** Cost-aware policy over the ladder; *test:* cost per verified hit vs fixed ladder.

## Priorities
C2 and C4 (cheapest, directly address cross-lab failure and the analog-lookup baseline) → C3 (the loop claim, uses existing replay) → C1 → C6 → C5/C7.

## Rules for all components
Pre-register before any scored run; planted-signal control per adapter; leave-labs-out and H4b are primary; contamination-controlled reporting; baselines include chirality-aware GBM, descriptor GBM, K_phys alone, nearest-neighbour to revealed; report nulls. Prior-art check per component before claiming novelty (survey risk table: tokenisation high; stereo-resolved ranking medium-low as a protocol; family-disjoint benchmark low-medium; small-vs-large loop medium).

[...truncated for packet...]

===== IH-LM ARCHITECTURE SPEC =====
# IH-LM — in-house hybrid, loop-native cyclic-peptide language model: architecture specification (2026-10-30)

Status: **specification before implementation; no result.** Working name IH-LM (rename freely). Owner direction: our own model with architectural innovation, claimed as ours; lineage of standard parts disclosed honestly.

## 1. Design principle
A configurable backbone (standard transformer family) wrapped by **five innovation modules that make the model loop-native and hybrid**. The innovation claim lives in the modules and their integration, not in the backbone. Every module is an ablation rung (pre-registered), so each claim is measured.

## 2. Components: what is standard, what is ours
| component | role | status / provenance |
|---|---|---|
| Backbone (decoder or encoder transformer, RoPE/standard attention, configurable depth/width) | sequence modelling | **Standard.** Our implementation of a standard design; initialisation options: (a) from scratch, (b) initialised from open weights where architecturally compatible (e.g. PeptideCLM-2, MIT) — disclosed, licence notice kept. Both reported. |
| Tokenizer: atom-level SMILES with explicit chirality, ring-closure/topology tokens, open vocabulary for unseen monomers | representation | Overlaps published peptide LMs (survey: high prior-art risk) — **not claimed as novel**; our ablation of stereo/topology tokens is a measured contribution only if the survey's gap holds. |
| **M1 Knowledge-prior channel with evidence-weighted fusion** | y_hat = f_K(x) + learned residual; weight n0/(n0+n) shrinks as feedback accumulates; rules carry effect size, CI, provenance, within-source validity | **Ours (design).** Prior art for Bayesian priors/shrinkage is general; the integration as a loop-updated symbolic memory for cyclic-peptide LMs is the claim to test. |
| **M2 Lab/assay offset module** | hierarchical random effect b_s per lab/assay, estimated from k anchor compounds; makes pooled multi-lab data usable | **Ours (design)** for the integration with an LM and anchor protocol; random effects themselves are standard. |
| **M3 Analog-retrieval cross-attention** | conditions predictions on the k nearest revealed analogs (stereo-aware similarity), because analog lookup is the strongest baseline | **Ours (design)** for stereo-aware peptide retrieval conditioning inside the loop; retrieval-augmented models exist generally. |
| **M4 Edit-space head** | predicts effects of edits (N-Me add/shift, D-flip, residue swap, ring change) with transferable priors; proposes edits from a measured parent | **Ours (design)**; matched-pair modelling exists generally — prior-art check before claiming. |
| **M5 Dual-memory loop interface** | fast symbolic memory updated in closed form from graded results + slow neural memory updated by fine-tuning/DPO; calibrated uncertainty head for acquisition; verifier-aware reward head | **Ours (design).** |
| Constrained decoding (rules enforced at generation) | generation validity | Pattern from SNG literature; our rules and integration; evaluated for validity only retrospectively. |

## 3. Provenance and disclosure table (maintained in the repo; goes into the paper's Methods)
For every checkpoint used: name, source URL, licence, whether initialised from it, what we changed. For every standard component: cite the original. Claims in the paper: (i) the five modules and their integration, (ii) measured ablation results, (iii) the loop evaluation design — never the backbone, the tokenisation idea, or third-party weights.

## 4. Implementation contract (for workstream 1)
One model class `IHLM(backbone_cfg, tokenizer_cfg, modules=[M1..M5])` with a `LoopModel`-compatible interface: `score`, `update(mode)`, `fingerprint`, `uncertainty`, `propose_edits`. Backbone swap must not change module code. Each module has a planted-signal test and a leave-labs-out test. Training budget and cost per the staged rules (USD 40 against the high spot price). Own code in `research/guangzhou_all_atom/cyclic_llm/ihlm/`; do not copy third-party modelling code into our files without attribution; any adapted file keeps its licence header.

## 5. Evaluation (unchanged rules)
Ablation ladder on the same backbone: plain → +M1 → +M2 → +M3 → +M4 → (+M5 loop updates); comparators = external pretrained peptide/chemistry LMs fine-tuned plainly + baselines; leave-labs-out, H4b few-label, five controls, validity gates, contamination-controlled reporting; nulls reported.

===== BASELINE ERROR ANALYSIS =====
# Baseline (fingerprint GBM) error analysis — CycPeptMPDB, within-source labels (2026-10-29)
Method: HistGradientBoosting (150 iterations, lr 0.1), 2,048-bit Morgan count fingerprints radius 2, labels = within-source z-scored permeability (PREREG_LOOP L3 grouping), 6,960 peptides; 5-fold CV random vs grouped by flat structure (GroupKFold); chirality-blind (useChirality=False, as in L3) vs chirality-aware (useChirality=True). Script: scratchpad `err_analysis.py` (diagnostic; not a registered result). Caveat: CV state differs from the loop's selection-biased state.

## Results
| quantity | blind | chiral |
|---|---|---|
| distinct fingerprints (of 6,960; 2,460 flat structures) | 2,380 | 6,583 |
| Spearman, random 5-fold CV | 0.713 | 0.766 |
| Spearman, CV grouped by flat structure | 0.663 | 0.712 |
| within-flat-group Spearman under CV | −0.386 | +0.259 |
Near-duplicate inflation (random vs grouped CV) is about 0.05 Spearman for both. Chirality-aware features add about +0.05 overall.

**Correction found while analysing (important).** The blind model's within-group −0.386 is a leave-out artifact: a predictor equal to the mean of the OTHER members of a flat group has within-group Spearman exactly −1.000 (verified on the 340 groups with ≥3 members and nonzero label variance; random scores give −0.025). So "within-group ranking is chance by construction for flat features" holds only when each group is split ONCE into revealed and target members (target members then receive identical blind predictions, ties → 0). The within-group metric must be implemented that way (fixed seeded split per group; evaluate ranking among target members only; also report the revealed-mean reference). The +0.259 (chiral) vs −0.386 (blind) gap above is therefore not interpretable as a stereo effect size.

**By source (blind, random CV):** Townsend n=2,881 MAE 0.53 ρ 0.72; Kelly n=1,518 MAE 0.54 ρ 0.66; CHUGAI n=878 MAE 0.38 ρ 0.72; Furukawa n=662 MAE 0.42 ρ 0.82; **Faris n=207 MAE 0.74 ρ 0.49; Bhardwaj n=133 MAE 0.71 ρ 0.42** — the small, recent, structurally diverse sources are worst.
**By N-methyl count:** MAE 0.53 (0), 0.53 (1–2), 0.54 (3–4), **0.37 (>4)** — N-methyl-rich peptides are easiest. By ring size and size: MAE 0.40–0.54, no strong pattern (largest-size bin 0.50).
**Activity cliffs:** 88,810 pairs share an identical blind fingerprint; 28 % of them (24,483) differ by >1 SD in label — pairs the blind model cannot separate at all.
**Worst-300 errors:** 74 % lie in multi-member flat groups (71 % of all peptides do) and 68 % come from the top-2 sources (63 % of peptides) — the worst errors are NOT concentrated in stereoisomer groups or in the dominant sources.

## What this means for the hypotheses
1. The baseline is already strong (Spearman 0.66–0.77) and chirality-aware fingerprints improve it by about 0.05 overall: the fair stereo opponent is a chirality-aware GBM, and a stereo effect on aggregate error is modest.
2. Where headroom plausibly exists: small/diverse sources (ρ 0.42–0.49) — consistent with H1/H4 (prior + transfer help when per-source data are scarce) — and the 28 % identical-fingerprint cliff pairs (H2, with the corrected metric).
3. Errors are broadly distributed, not dominated by one subgroup; an LLM advantage must show up as shifted learning curves and on low-data sources, not on the dominant series.

===== STRATIFICATION ANALYSIS (Part B headline results) =====
| 0.19 |
| N-Me shift (one N-Me moved) | 2252 | 13 | mean |delta| | 0.29 [0.12, 0.46] | 0.99 | 0.45 [0.41, 0.47] | 0.40 | 0.08 |
| ring +1 residue (any) | 1254 | 5 | mean delta | -0.14 [-0.49, 0.21] | 0.97 | -0.31 [-0.36, -0.26] | 0.47 | 0.07 |
| substitution: aliphatic->aliphatic | 1177 | 21 | mean |delta| | 0.50 [0.40, 0.60] | 0.94 | 0.62 [0.58, 0.66] | 0.52 | 0.21 |
| substitution: aromatic->aromatic | 604 | 12 | mean |delta| | 0.37 [0.22, 0.51] | 0.96 | 0.55 [0.50, 0.60] | 0.56 | 0.18 |
| substitution: aliphatic->polar | 31 | 8 | mean delta | -1.01 [-1.45, -0.57] | 0.85 | -0.66 [-0.98, -0.19] | 0.84 | 0.45 |

**Cliffs (|Δz|>1 SD within source) and pair-ordering accuracy** (same-fold pairs = neither partner label in training; ties 0.5).

| transformation | pairs | cliff rate [CI] | same-fold pairs | acc blind | acc chiral | acc descriptor |
|---|---|---|---|---|---|---|
| D flip (D minus L) | 7451 | 0.19 [0.17, 0.21] | 7451 | 0.50 | 0.62 | 0.56 |
| substitution with D/N-Me change | 5755 | 0.27 [0.25, 0.29] | 1120 | 0.70 | 0.75 | 0.69 |
| N-Me added (with minus without) | 4156 | 0.33 [0.29, 0.37] | 804 | 0.72 | 0.71 | 0.69 |
| D flip + N-Me swap ((D,nonMe) minus (L,Me)) | 3905 | 0.36 [0.32, 0.39] | 767 | 0.73 | 0.71 | 0.70 |
| cap_or_unknown_change | 3621 | 0.37 [0.35, 0.39] | 601 | 0.81 | 0.79 | 0.76 |
| substitution: aliphatic->aromatic | 3019 | 0.34 [0.31, 0.36] | 594 | 0.71 | 0.74 | 0.68 |
| N-Me shift (one N-Me moved) | 2252 | 0.30 [0.27, 0.34] | 361 | 0.58 | 0.60 | 0.56 |
| ring +1 residue (any) | 1254 | 0.32 [0.27, 0.37] | 287 | 0.81 | 0.80 | 0.79 |
| substitution: aliphatic->aliphatic | 1177 | 0.34 [0.31, 0.38] | 234 | 0.77 | 0.76 | 0.77 |
| substitution: aromatic->aromatic | 604 | 0.26 [0.22, 0.30] | 89 | 0.65 | 0.69 | 0.75 |
| substitution: aliphatic->polar | 31 | 0.45 [0.26, 0.61] | 4 | – | – | – |

**Feature-family models** (descriptor GBM, grouped CV by flat structure).

| model | features | Spearman [CI] |
|---|---|---|
| full | 50 | 0.67 [0.63, 0.70] |
| only:physchem | 9 | 0.61 [0.57, 0.65] |
| only:ring_topology | 10 | 0.23 [0.16, 0.30] |
| only:nme_pattern | 7 | 0.36 [0.28, 0.43] |
| only:chirality | 7 | 0.31 [0.27, 0.35] |
| only:composition | 17 | 0.26 [0.19, 0.32] |
| without:physchem | 41 | 0.57 [0.53, 0.61] |
| without:ring_topology | 40 | 0.67 [0.64, 0.70] |
| without:nme_pattern | 43 | 0.66 [0.63, 0.70] |
| without:chirality | 43 | 0.63 [0.59, 0.68] |
| without:composition | 33 | 0.66 [0.62, 0.69] |

**Permutation importance by family** (drop in held-out Spearman; 30 permutations).

| family | mean drop [2.5, 97.5 %] |
|---|---|
| physchem | 0.440 [0.423, 0.455] |
| ring_topology | 0.032 [0.028, 0.036] |
| nme_pattern | 0.220 [0.207, 0.234] |
| chirality | 0.060 [0.055, 0.066] |
| composition | 0.035 [0.032, 0.039] |

**N-methyl × D-residue grid** — mean within-source z [CI] (n).

| N-Me \ D | 0 | 1-2 | >=3 |
|---|---|---|---|
| 0 | -0.17 [-0.30, -0.03] (168) | -0.36 [-0.53, -0.20] (475) | -0.45 [-0.67, -0.22] (273) |
| 1-2 | 0.09 [-0.02, 0.20] (227) | -0.04 [-0.13, 0.03] (1643) | -0.23 [-0.42, -0.08] (1480) |
| 3-4 | 0.11 [-0.03, 0.25] (157) | 0.38 [0.22, 0.54] (619) | 0.37 [0.25, 0.49] (1041) |
| >=5 | -0.01 [-0.11, 0.09] (413) | -0.03 [-0.16, 0.10] (311) | 0.60 [0.08, 0.75] (153) |

**Additive vs interaction** (grouped CV Spearman)

| model | Spearman [CI] |
|---|---|
| ridge_additive(nMe,nD) | 0.23 [0.17, 0.27] |
| ridge_with_product | 0.27 [0.21, 0.33] |
| gbm(nMe,nD) | 0.31 [0.25, 0.37] |

**Source confound** — features with highest between-source share of variance (eta²) and pooled vs within-source Spearman with raw log Papp.

| feature | eta² | pooled ρ | within-source ρ (k) | confounded |
|---|---|---|---|---|
| n_cap_n | 1.00 | -0.13 | -0.03 (1) | False |
| topo_lariat_sc_cterm | 1.00 | -0.13 | -0.03 (1) | False |
| hba | 0.90 | 0.03 | -0.25 (12) | True |
| n_monomers | 0.89 | 0.08 | -0.27 (6) | True |
| tpsa | 0.88 | -0.03 | -0.31 (15) | True |
| topo_lariat_nterm_sc | 0.87 | 0.35 | -0.23 (2) | True |
| n_cap_c | 0.87 | 0.35 | -0.23 (2) | True |
| n_residues | 0.85 | 0.07 | -0.26 (6) | True |
| mw | 0.82 | 0.11 | 0.15 (15) | False |
| heavy | 0.81 | 0.10 | 0.11 (15) | False |
| tail_res | 0.81 | 0.08 | -0.22 (3) | True |
| frac_polar | 0.81 | 0.11 | -0.08 (6) | True |
| ring_atoms_max | 0.79 | 0.09 | -0.10 (8) | True |
| frac_proline | 0.79 | -0.22 | -0.10 (9) | False |

Features flagged source-confounded: 29 of 50.

**Substructure enrichment** (within-source standardised effect, random-effects across sources; BH 10 %). Top 14 by p.

| feature | n present | sources | effect [CI] | I² | sources with + effect | q |
|---|---|---|---|---|---|---|
| has_base:Pr_Gly | 601 | 5 | 0.34 [0.25, 0.42] | 0.00 | 0.80 | 0.000 |
| has_base:Bn_Gly | 1209 | 3 | -0.27 [-0.35, -0.20] | 0.00 | 0.00 | 0.000 |
| n_Nme>=2 | 4293 | 8 | 0.70 [0.34, 1.07] | 0.93 | 0.75 | 0.003 |
| n_Nme>=3 | 2694 | 9 | 0.50 [0.24, 0.77] | 0.89 | 0.67 | 0.003 |
| motif_alternating_Nme | 2464 | 12 | 0.31 [0.09, 0.52] | 0.85 | 0.75 | 0.054 |
| has_Nme_base:L | 5318 | 12 | 0.47 [0.10, 0.83] | 0.93 | 0.83 | 0.121 |
| has_peptoid | 2093 | 8 | 0.31 [0.04, 0.58] | 0.89 | 0.75 | 0.144 |
| has_nalkyl_nonmethyl | 2206 | 9 | 0.23 [0.02, 0.43] | 0.75 | 0.89 | 0.144 |
| smarts:halogen | 140 | 3 | -0.57 [-1.07, -0.06] | 0.88 | 0.00 | 0.144 |
| smarts:basic_aliphatic_amine | 165 | 3 | -0.51 [-0.97, -0.05] | 0.37 | 0.00 | 0.144 |
| arom_fraction>=0.3 | 1173 | 11 | -0.42 [-0.80, -0.04] | 0.92 | 0.18 | 0.144 |
| has_base:V | 629 | 5 | -0.27 [-0.51, -0.02] | 0.52 | 0.00 | 0.144 |
| has_base:T | 2375 | 7 | -0.52 [-1.02, -0.03] | 0.69 | 0.14 | 0.163 |
| has_D_base:L | 4295 | 12 | 0.28 [0.01, 0.55] | 0.89 | 0.67 | 0.166 |


**Source concentration of strata** (share of the stratum's peptides from its largest source; a stratum dominated by one laboratory cannot be separated from that laboratory's effect).

| stratifier | level | n | sources | largest source | share | top-2 share |
|---|---|---|---|---|---|---|
| topology | head_to_tail | 4660 | 44 | 2020_Townsend | 0.62 | 0.76 |
| topology | lariat_sc_cterm | 1521 | 3 | 2021_Kelly | 1.00 | 1.00 |
| topology | lariat_nterm_sc | 779 | 3 | 2013_CHUGAI | 0.81 | 0.99 |
| length | <=5 | 193 | 13 | 2020_Le Roux | 0.24 | 0.46 |
| length | 6 | 1975 | 22 | 2020_Townsend | 0.52 | 0.85 |
| length | 7 | 1904 | 10 | 2020_Townsend | 0.98 | 0.98 |
| length | 8 | 102 | 5 | 2013_CHUGAI | 0.48 | 0.77 |
| length | >=9 | 2786 | 16 | 2021_Kelly | 0.55 | 0.79 |
| n_methyl | 0 | 916 | 29 | 2020_Townsend | 0.49 | 0.65 |
| n_methyl | 1-2 | 3350 | 25 | 2020_Townsend | 0.58 | 0.76 |
| n_methyl | 3-4 | 1817 | 20 | 2021_Kelly | 0.42 | 0.68 |
| n_methyl | >=5 | 877 | 13 | 2013_CHUGAI | 0.61 | 0.77 |
| n_D | 0 | 965 | 25 | 2013_CHUGAI | 0.48 | 0.63 |
| n_D | 1-2 | 3048 | 32 | 2020_Townsend | 0.48 | 0.67 |
| n_D | >=3 | 2947 | 18 | 2021_Kelly | 0.44 | 0.87 |
| peptoid | yes | 2093 | 10 | 2020_Townsend | 0.69 | 0.91 |
| peptoid | no | 4867 | 45 | 2021_Kelly | 0.31 | 0.61 |
| unknown_monomer | yes | 1129 | 22 | 2016_Furukawa | 0.45 | 0.63 |
| unknown_monomer | no | 5831 | 38 | 2020_Townsend | 0.49 | 0.75 |
| ext_backbone | yes | 1078 | 7 | 2020_Townsend | 0.77 | 0.93 |
| ext_backbone | no | 5882 | 45 | 2020_Townsend | 0.35 | 0.61 |
| backbone_mod | yes | 24 | 3 | 2015_Ahlbach | 0.50 | 0.79 |
| backbone_mod | no | 6936 | 44 | 2020_Townsend | 0.41 | 0.63 |
| ring_atoms | low(<=21) | 3487 | 29 | 2020_Townsend | 0.67 | 0.86 |
| ring_atoms | mid | 1769 | 5 | 2021_Kelly | 0.69 | 0.96 |
| ring_atoms | high(>22) | 1704 | 22 | 2013_CHUGAI | 0.39 | 0.57 |
| stereo_group | 1 | 2048 | 40 | 2013_CHUGAI | 0.34 | 0.53 |
| stereo_group | 2-7 | 724 | 24 | 2020_Townsend | 0.62 | 0.77 |
| stereo_group | >=8 | 4188 | 11 | 2020_Townsend | 0.58 | 0.88 |
| source_size | <50 | 571 | 36 | 2015_Wang | 0.08 | 0.17 |
| source_size | 50-299 | 609 | 5 | 2024_Faris | 0.34 | 0.59 |
| source_size | >=300 | 5780 | 4 | 2020_Townsend | 0.50 | 0.76 |
[...truncated for packet...]

===== BENCHMARK RESULTS V3 (validity gate, M3, H4b few-label baselines) =====
# Multi-target retrospective study — V3: validity gate, M3, and few-label adaptation baselines (2026-10-30)
Pre-registration: PREREG §15 (A7, gate + M3 outcome; `a6e07cd56`) and §16 (A8, H4b; reveal sets frozen `79276f09e`). Extends `docs/20261029_RETRO_RECOVERY_RESULTS_V2.md`. Code/data: `research/guangzhou_all_atom/multitarget/integrin_chembl/retro_recovery/`.

## 1. Validity gate (required for every analysis)
Controls with no target information must be at chance: C1 atom-LM typicality (WS1 scorer, reproduced to 1e-16 on 200 compounds), C2 leave-fold-out multi-proxy logistic regression, C3 leave-fold-out Morgan-count logistic regression (not a matching variable), plus Bonferroni-adjusted single proxies. Unevaluable controls or < 8 families = unverifiable (a vacuous pass on a 1-target M3 attempt was caught and fixed with a test).
| benchmark | C1 | C2 | C3 | verdict |
|---|---|---|---|---|
| I (46 targets, 26 fam) | 0.503 [0.458, 0.550] | 0.559 [0.499, 0.619] | **0.584 [0.533, 0.636]** | not clean (C3; O-fraction 0.39, halogen 0.53) |
| M2 (20, 14) | **0.665 [0.551, 0.772]** | **0.690 [0.578, 0.795]** | **0.676 [0.541, 0.803]** | invalid (confirms WS1's finding) |
| M (299, 120) | 0.476 [0.439, 0.513] | 0.469 [0.427, 0.509] | **0.315 [0.279, 0.352]** (below chance) | invalid |
| I remaining items after reveal, k = 5 / 10 / 25 | 0.512 / 0.518 / 0.499 (at chance) | 0.564 / 0.564 / 0.527 | 0.587 / 0.567 / 0.595 (exceed chance) | not clean at every k |
**M3 (typicality + 18 other proxies + similarity matching) is not achievable:** loosest caliper keeps 257 positives / 15 families and C2 0.635 [0.516, 0.753], C3 0.647 [0.510, 0.778] still separate them; tighter calipers leave 70 → 6 positives (6 → 1 families). Power cost 98–100 % of eligible positives. Hypothesis (untested): a target's positives form a chemotype series, so any cross-target-decoy design stays separable by a compound-only classifier. Consequence: **the zero-shot family-held-out claim can only be made on I, under the control-adjusted rule (A7): an arm must beat the strongest of {B0–B4, C1–C3}**; no benchmark in this study passes the gate cleanly, and papers must say so.

## 2. H4b few-label adaptation — baselines (analysis I; frozen reveals: 45 / 44 / 39 targets, 26 / 25 / 21 families at k = 5 / 10 / 25; 5 seeds)
| k | NN (to revealed) AUROC | FP-k (fit on revealed only) | PT+k (pretrained LR + revealed, w = 20) | PT (no-target, other families) | random |
|---|---|---|---|---|---|
| 0 | – | – | – | 0.539 [0.478, 0.605] | 0.478 |
| 5 | **0.753 [0.715, 0.789]** | 0.750 [0.711, 0.787] | 0.672 [0.617, 0.724] | 0.537 | 0.490 |
| 10 | **0.822 [0.784, 0.856]** | 0.817 [0.777, 0.851] | 0.736 [0.688, 0.782] | 0.521 | 0.497 |
| 25 | **0.869 [0.835, 0.899]** | 0.861 [0.817, 0.897] | 0.823 [0.775, 0.865] | 0.517 | 0.507 |
Gain over zero-shot PT: NN +0.214 / +0.300 / +0.342 (all CIs exclude 0); top-10 precision NN 0.78 / 0.83 / 0.96 (random 0.56 / 0.55 / 0.71: I is positive-heavy, so P@10 and EF5 are weakly informative and AUROC is primary). Nothing beats NN: FP-k − NN = −0.004 / −0.005 / −0.008 (CIs include 0); PT+k is 0.05–0.09 below.
**What this means:** (i) few labels of the target help a lot (+0.21 to +0.34 AUROC), but the best method is plain nearest-neighbour to the revealed compounds — the gain is **analog lookup within a target's chemical series** (stereoisomer siblings of revealed compounds are removed; close analogs remain), not demonstrated target-biology learning. (ii) The no-target pretrained model stays at 0.52–0.54, so zero-shot compound-only transfer is near chance on this set despite C2/C3 showing the benchmark carries some compound-only signal. (iii) **The bar for any LLM few-label arm is NN / FP-k at the same k**, and the gain test is against its own k = 0 value; LLM score files are evaluated with `run_s3.py --k K` (`h4b_eval.py`, same remaining items, all-items and contamination-controlled).

## 3. Errors / checks in this pass
Vacuous gate pass fixed + test; PT+k convergence concern checked directly (65 iterations; two runs differ by ≤ 2.2e-5; pretrained models converge at 79–124 iterations); first run kept in `results/superseded/`. M2/I/M gate tables were computed after M2's failing control was known (A7 discloses the order). Not verified: that typicality missingness (very large compounds) does not interact with the gate; family structure is Pfam-based; I has 26 families.
## 4. Remaining gaps
LLM arms (WS1) and loop replay (WS2) not yet scored under H4b; GBM variants dropped for cost; S2 not executed; M3 not achievable → no clean zero-shot benchmark.

===== L5 LOOP RESULTS (aggregate JSON excerpt; 810/810 tasks, within-source hit definition) =====
{"fp_A": {"n_seeds": 30, "total": 236.1, "first200": 120.7}, "kn_A": {"n_seeds": 30, "total": 241.2, "first200": 128.5, "d_total": {"mean": 5.1, "ci": [-18.3, 32.6], "lower_gt0": false}, "d_first200": {"mean": 7.8, "ci": [-17.6, 27.7], "lower_gt0": false}}, "resid_nme_A": {"n_seeds": 30, "total": 238.0, "first200": 118.1, "d_total": {"mean": 1.9, "ci": [-19.9, 34.1], "lower_gt0": false}, "d_first200": {"mean": -2.6, "ci": [-25.3, 37.7], "lower_gt0": false}}, "resid_z_A": {"n_seeds": 30, "total": 242.1, "first200": 119.5, "d_total": {"mean": 6.0, "ci": [-16.1, 33.8], "lower_gt0": false}, "d_first200": {"mean": -1.2, "ci": [-19.7, 35.7], "lower_gt0": false}}, "fuse_nme_A": {"n_seeds": 30, "total": 241.3, "first200": 123.4, "d_total": {"mean": 5.2, "ci": [-17.7, 41.6], "lower_gt0": false}, "d_first200": {"mean": 2.7, "ci": [-10.7, 41.8], "lower_gt0": false}}, "fuse_z_A": {"n_seeds": 30, "total": 244.1, "first200": 128.1, "d_total": {"mean": 8.0, "ci": [-14.7, 48.0], "lower_gt0": false}, "d_first200": {"mean": 7.4, "ci": [-8.7, 43.4], "lower_gt0": false}}, "fp_B": {"n_seeds": 30, "total": 52.3, "first200": 26.5}, "kn_B": {"n_seeds": 30, "total": 76.1, "first200": 33.4, "d_total": {"mean": 23.8, "ci": [-4.0, 54.0], "lower_gt0": false}, "d_first200": {"mean": 7.0, "ci": [-4.0, 18.0], "lower_gt0": false}}, "resid_nme_B": {"n_seeds": 30, "total": 56.1, "first200": 25.0, "d_total": {"mean": 3.9, "ci": [-19.9, 29.4], "lower_gt0": false}, "d_first200": {"mean": -1.5, "ci": [-12.0, 14.8], "lower_gt0": false}}, "resid_z_B": {"n_seeds": 30, "total": 53.9, "first200": 31.4, "d_total": {"mean": 1.6, "ci": [-19.4, 15.9], "lower_gt0": false}, "d_first200": {"mean": 5.0, "ci": [-5.9, 13.9], "lower_gt0": false}}, "fuse_nme_B": {"n_seeds": 30, "total": 59.8, "first200": 25.8, "d_total": {"mean": 7.5, "ci": [-17.7, 40.7], "lower_gt0": false}, "d_first200": {"mean": -0.7, "ci": [-10.6, 10.0], "lower_gt0": false}}, "fuse_z_B": {"n_seeds": 30, "total": 66.2, "first200": 30.2, "d_total": {"mean": 13.9, "ci": [-8.7, 46.6], "lower_gt0": false}, "d_first200": {"mean": 3.7, "ci": [-9.3, 16.4], "lower_gt0": false}}, "fp_C": {"n_seeds": 30, "total": 212.5, "first200": 109.0}, "kn_C": {"n_seeds": 30, "total": 214.4, "first200": 115.0, "d_total": {"mean": 1.9, "ci": [-48.5, 20.4], "lower_gt0": false}, "d_first200": {"mean": 6.1, "ci": [-14.1, 25.0], "lower_gt0": false}}, "resid_nme_C": {"n_seeds": 30, "total": 211.9, "first200": 105.6, "d_total": {"mean": -0.7, "ci": [-33.3, 29.6], "lower_gt0": false}, "d_first200": {"mean": -3.3, "ci": [-25.0, 23.4], "lower_gt0": false}}, "resid_z_C": {"n_seeds": 30, "total": 217.6, "first200": 108.3, "d_total": {"mean": 5.1, "ci": [-21.5, 29.1], "lower_gt0": false}, "d_first200": {"mean": -0.6, "ci": [-23.0, 26.8], "lower_gt0": false}}, "fuse_nme_C

===== KB AUDIT HEADLINE =====
# Knowledge-base audit and gap analysis (2026-10-29)

Scope: the cyclic-peptide / BioMate knowledge bases under `research/guangzhou_all_atom/cyclic_llm/` (read-only), audited for the loop-improves-the-LLM study. Code and results: `research/guangzhou_all_atom/cyclic_llm/kb_audit/`. Rules followed: audit first, positive controls before any verdict, no tuning, IP content (`fto_kb`, FTO entries) not audited or edited per owner instruction. "Verified" below means only what a named check shows.

## 1. Inventory and verdicts
| KB | content (counted) | provenance | consumed? | verdict |
|---|---|---|---|---|
| `experience_kb.py` + `target_kb/*.json` (16 targets) | 151 per-target entry instances = 73 distinct statements: 20 config, 37 active knowledge (16 pharmacophore, 4 metal, 5 physchem, 4 eval_rule, 3 modality, 3 sar, 1 cmc, 1 liability), 16 candidate (FTO: quarantined, "unverifiable") | every active entry carries a citation and `verified=True` (self-asserted); `tier` T1/T2 | yes (loop_batch, methodology_close, register_experience_kb) | well-structured; **thin**: the 16 per-target pharmacophore entries are only 2 distinct statements (RGD-integrin/MIDAS for 4 integrin targets; one generic "PPI hot-spot" sentence for 12 others, including PD-L1) |
| `medchem_kb.py` | liability (RDKit FilterCatalog, 1,585 alerts, ingested), metal 7 elements (one shared citation set), modality 4 statements (cyclic peptide 3, stapled 1), pharmacophore class 5, physchem 5 | cited | yes (via experience_kb, radiopharm_kb) | good for small-molecule liability; peptide-relevant content = 4 modality statements |
| `medchem_kb_product.py` | 45 entries (ADMET 13, physchem 12, modality 10, pharmacophore class 10) | cited | **no non-test consumer found: DEAD** | small-molecule oriented; 11 entries duplicate `medchem_kb` (4 physchem, 5 pharmacophore class, 2 modality) |
| `medchem_kb_ingested_large.json` | summary counts only: RDKit descriptors 210, ChEMBL target classes 905, mechanisms 7,561, approved drugs 4,225 | source named | consumer not traced | no peptide-specific content; not usable as a rule base as stored |
| `pharmacophore_knowledge.py` / `acceptance_gate.py` / `rule_induction.py` | αvβ6 (and PD-L1) hard gates H1–H8; **9 αvβ6-specific predicates** (RGD, RGDL, D-Pro turn, N-methyl, handle, aromatic flanks, head-to-tail); induced rules for 2 targets | literature-grounded | yes (acceptance_gate 11 consumers) | correct for αvβ6; **not general** |
| `knowledge_liability_flags.py` | sequence CMC motifs (NG/NS/NH/NA deamidation, DG/DS isomerisation, Met/Trp oxidation, odd Cys), αvβ6 SAR (pan-RGD, RGDL, lock, renal charge), PD-L1 SAR | cited | yes | canonical-residue and sequence-motif level; not ncAA/stereo/topology aware |
| `peptide_availability.py` | 3-coefficient OLS fit on linear SH3/PDZ peptides (leave-one-domain-out ρ 0.40) | data cited | yes (score.py) | not validated for cyclic/ncAA peptides |
| `admet_tdc_ingested.json` | index of 38 public small-molecule datasets (incl. AqSolDB solubility, PAMPA) | named | — | **no cyclic-peptide data** |
| `fto_kb` | 1 patent | — | — | not audited (IP) |

## 2. Citation check (independent, Crossref)
57 bibliographic citations from `medchem_kb`, `medchem_kb_product` and `experience_kb` checked by author/journal/year/volume/page (`kb_audit/verify_citations.py`, `_pass2.py`, `citation_check.json`): **54 confirmed as real records with the cited triple**, **3 flagged**: Bagal et al. 2013, Nat Rev Drug Discov 12:35 (ion channels) —

===== AUDIT LOG =====
# Code / data / evaluation audit log (started 2026-10-28)
Rule (owner, 2026-10-28): nothing is reported until code, data, evaluation design and output analysis are audited; if a method that should work does not, suspect our own code first. Each entry: what was checked, how, result.

## A1. Retrospective permeability loop (run_loop*.py, CycPeptMPDB) — in progress
| check | method | result |
|---|---|---|
| Duplicate structures merged? | canonical SMILES uniqueness after loader filters | OK: 7,027 rows → 6,960 IDs → 6,958 unique canonical SMILES |
| Label column | `Permeability` vs `PAMPA` on PAMPA rows | 73 of 7,027 rows (1 %) differ; loader uses `Permeability` (generic) — to fix in next version |
| Regime B (scaffold-shifted) leakage | pool vs initial: identical fingerprint / flat structure / stereo-free scaffold, 10 seeds | **0.000 / 0.000 / 0.000 — no leakage; regime B valid** |
| Regime A (in-distribution) near-duplicates | same, 10 seeds | 22.9 % of pool has a fingerprint identical to an initial peptide; 21.7 % same flat structure; 60.7 % same stereo-free scaffold — by design "in-distribution" but inflates the gain; must be stated |
| **Representation** | distinct fingerprints / flat structures | **6,960 peptides = 2,380 distinct Morgan fingerprints, 2,460 flat structures**: ~⅔ of the data are stereoisomers; fingerprint uses no chirality, so the model cannot see stereochemistry. Design flaw for cyclic peptides; fix in next version (chirality-aware features) |
Consequence: L3 loop-vs-random stands as measured with the two caveats above; knowledge-arm result is uninterpretable twice over (scale mismatch → L4; chirality-blind features → next version).


## A2. Stage B cofold selector — inputs (partial)
| check | method | result |
|---|---|---|
| Stored DockQ labels | independent recomputation with the `DockQ` CLI (clean venv, numpy 1.26) on 12 samples (3 test complexes: 29QJ_2 failure case, 9GFC_2, 8R7S_2; samples 0–3) vs `scoring/out2/scores_test.jsonl` | **12/12 match** on DockQ, iRMSD, LRMSD, fnat (to 3 decimals); chain pairing A/Z correct; native.pdb ↔ sample pairing correct |
| Selector / evaluator code | existing unit tests (planted signal detected, shuffled labels → chance, GT columns rejected, rescale-invariant) | 29 passed, 1 skipped |
| Structure-derived features | recomputed independently (Biopython mmCIF parser, brute-force pairwise distances; stored values use gemmi + cKDTree) for the same 12 samples: peptide pLDDT, contact pairs (5.0 Å), clashes (2.2 Å), min peptide–receptor distance; ipTM re-read from confidence JSON | **match**: pLDDT identical to 0.01, clashes 12/12, min distance ≤0.001 Å, ipTM exact; contact pairs 10/12 identical, 2/12 differ by 1 pair of ~300 (coordinate rounding at the 5.0 Å cutoff) — not a bug; features and labels come from the same sample index |
| Still unchecked | the 9 missing test complexes; the 104 train/test split's cluster definition (receptor_cluster40); 123 other complexes not spot-checked (3 of 104 sampled) | pending |
Note: complex 29QJ_2 is a stapled 22-mer helix (cyclic_flag false) — the benchmark mixes stapled and head-to-tail macrocycles; stratify before interpreting.

## To audit next (not yet done)
Stage B inputs (independent DockQ recomputation, sample↔native pairing, feature extraction); leakage audit of the display selector; selector evaluation (abundance null); integrin T1/T2; v4 unified LLM training/eval code; cyclic LLM paper draft numbers vs artifacts.

## A3. Stage B — why the selector is null (train-only diagnostic, 2026-10-28; test set not touched)
155 train complexes, median 25 samples each: 109 all-succeed, 4 none, **42 informative** (mixed success/failure at DockQ ≥ 0.23; random pick succeeds 54 % there, oracle 100 %). Within those 42, mean within-complex Spearman of each GT-free feature with DockQ: best |ρ| = 0.11 (pae_if −0.113, pae_pep_to_rec −0.108, pep_plddt +0.096, if_plddt +0.082, iptm_pep_rec +0.080, ring_strain −0.073, consensus-neighbour +0.062); iptm/confidence_score ≈ 0.065; fraction of complexes with the expected sign 0.36–0.60. **Conclusion: the co-folding model's own confidence and simple geometry features carry almost no within-complex information about pose correctness for these peptides; the null is a property of the signal, not (as far as audited) of the code.** Improvement therefore needs signals independent of Boltz's confidence (cross-model agreement, physics rescoring, knowledge constraints) and more informative training complexes; development on train-grouped CV only, confirmation on fresh post-cutoff complexes (test set was a one-shot).

===== SURVEY 1 (representation/benchmarks): implications + prior-art risk =====
## Implications for our study

**Stratification features worth adding.** Stratify and report by: source publication / lab and assay type (PAMPA, Caco-2, RRCK, MDCK), because values are heterogeneous and series-clustered; canonical-SMILES group (chirality retained) and monomer-composition cluster to expose near-duplicate series; ring size / sequence length (6, 7, 10-mers are the well-covered lengths); topology (circle vs lariat; stapled and bicyclic are outside CycPeptMPDB); N-methyl count and position (exposed vs IMHB-protected amide) and D-residue count and position; backbone-stereo pattern relative to the parent sequence (for paired diastereomer analysis); lipophilicity (logD/ALogP) and exposed-HBD count; and the clipped-value flag (logPexp at -10 / -4 bounds). Within-series membership should be a recorded covariate so within-scaffold and across-scaffold performance can be separated.

**Representation needs.** The representation must keep chirality per residue, N-methylation at amide level, arbitrary ncAA side chains (out-of-vocabulary risk is the weak point of closed HELM monomer sets and of PepLand), and the macrocycle closure/topology (circle, lariat, side-chain bridges). Atom-level SMILES covers these implicitly but forces the model to infer closure from paired digits; HELM covers topology explicitly but not unseen monomers. A fair comparison should include at least a Morgan/Tanimoto GP or GBM, a monomer-level HELM model (HELM-BERT-style) and an atom-level SMILES model (PeptideCLM-style) as controls, with stereo-ablation (flip D to L, strip chirality) run on each.

**Evaluation pitfalls to avoid.** Do not use random splits as the headline (random-to-scaffold drops of 10-20 AUC points are documented). Use group-disjoint splits by canonical SMILES group, monomer-set cluster and source publication, and report leave-one-cluster-out. Use stereo-aware scaffold definitions (the benchmark's Murcko scaffolds ignore chirality). Average or group duplicates before splitting. Always include a strong fingerprint-kernel/GBM baseline, since it matches or beats several deep models here. For any binding benchmark: apply DUD-E-style audits (ligand-only baseline, property-matched decoys, topology bias), LIT-PCBA-style duplicate checks (2D-identical items across splits, a zero-parameter nearest-neighbour baseline), and PDBbind-CleanSplit-style structure/target similarity filtering. For LLM evaluations, test memorisation (blinding) and shortcut properties (molecular weight, length).

**Claims that look already published (so not novel).** Deep and kernel models on CycPeptMPDB; monomer-aware/HELM-based permeability prediction (MonoSeqCP thesis, MD-GAK, HELM-BERT); SMILES chemical LMs that natively encode ncAAs and cyclisation (PeptideCLM, PeptideCLM-2); scaffold and leakage-controlled splits for CycPeptMPDB (Liu et al., Geylan et al., Amirahmadi et al.); the finding that stereoisomer and N-methyl pattern change permeability by orders of magnitude (Rezai 2006, White 2011); chameleonic/IMHB mechanisms (Ramelot 2023, Bhardwaj 2022); the general observation that fine-tuned LLMs are sample-efficient on small chemistry sets (Jablonka 2024) and that fingerprints are hard to beat (Praski 2025).

### Prior-art risk table

| Candidate claim | Closest opened prior art | What is not covered by it (per my searches) | Risk |
|---|---|---|---|
| (a) Stereo-resolved within-scaffold ranking for cyclic peptides | Rezai 2006 and White 2011 (experimental diastereomer/N-Me series); Amirahmadi et al. (stereo as distinct monomers, stereo ablation listed as future work; chirality-blind Murcko scaffolds) | No opened paper reports a within-scaffold ranking metric across stereoisomers/N-Me variants for ML models | Medium-low for the metric/protocol; high if stated as "first to show stereo matters" |
| (b) Family-disjoint matched-decoy benchmark for cyclic-peptide binders | DUD-E bias (Chen 2019), LIT-PCBA audit (Huang 2025), CleanSplit (Graber 2025) define the pitfalls; PepBenchmark (general peptides); an MM/PBSA 50-complex + 81-decoy protein-cyclic-peptide set (snippet only) | No family-disjoint matched-decoy ML benchmark for cyclic-peptide binders found | Low-medium (search coverage limited; methodology borrowed, application new) |
| (c) Small LLM with feedback loop vs large LLMs for peptide property ranking | PeptideCLM/-2, HELM-BERT (small peptide LMs); Jablonka 2024, MolecularGPT, LlaSMol (LLM sample efficiency); ICL shortcut studies; PepALD (reward-driven optimisation, generative) | No opened work compares a small LM with an iterative feedback loop against large LLMs on peptide property ranking | Medium: components are published; the specific loop-vs-large comparison was not found |
| (d) Chirality-aware atom-level tokenisation with topology tokens for macrocycles | PeptideCLM (custom SMILES tokens), PeptideCLM-2 (k-mer tokens), HELM-BERT (topology-aware monomers), PepFoundry (chirality + ring digits), PepALD (ring-closure prediction), PepLand (junction-level graph) | Dedicated, separately ablated chirality and closure/topology tokens in an atom-level vocabulary, tested on stereoisomer pairs | High for the general idea; low-medium only for the specific tokeniser plus ablation |

---

## Unverified (not asserted above, or only as marked snippets)

[...truncated for packet...]

===== SURVEY 2 (few-evidence new target): prior-art risk =====
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
[...truncated for packet...]