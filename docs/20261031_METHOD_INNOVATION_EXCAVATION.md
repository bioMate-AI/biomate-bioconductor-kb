# Method-innovation excavation for a SMALL paper (2026-07 to 2026-10-31)

Status: read-only excavation, one file written, nothing committed, no cloud, no paid API, no web (prior-art checks are [UNVERIFIED] unless a repo document that itself opened the source is cited).
Question (owner): "I only need a small paper, with method innovation. Isn't there any in the past months?"

Number provenance: every number below was READ from the cited file in this session unless tagged [MEM] (remembered from memory notes, not re-read). "Opened" is not "audited": I read heads/headline sections of the cited documents and did not re-run any code.

## 0. Plain answer

Nothing in the repo is a clean "new technique, positive result against a strong baseline, survived audit". The program's own audits retired every candidate of that shape (collected-gold SFT, display-binding selector, v4 LM, cofold selector, RL). What survives is (a) an audited evaluation-methodology contribution (Paper 1, already drafted), (b) an audited empirical finding about the knowledge layer (KB dividend), and (c) a rule+LLM hybrid with a held-out audit but a weak baseline. Paper 1 is the only one writable in about a week, and its "method" is a validity-gate/replay protocol, not a model.

## 1. Ranking

| rank | candidate | verdict |
|---|---|---|
| 1 | Validity gate as an equivalence test + leak-aware replay protocol (Paper 1, `docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md`) | WRITE AFTER ONE CHEAP CONTROL |
| 2 | KB/harness dividend scales inversely with model strength (Paper B) | WRITE AFTER ONE CHEAP CONTROL (a finding, not a technique) |
| 3 | Production rule layer + LLM + IO-abstention guardrail for parameter extraction | NOT READY (one canonical run and a frontier baseline missing) |
| - | Everything else in section 3 | NOT READY or dead (reason per row) |

## 2. Top three in detail

### 2.1 Paper 1: equivalence-test validity gate + leak-aware replay protocol
(a) Method. A retrospective peptide benchmark is declared VALID only if every no-target/typicality control is evaluable, none excludes chance, and each primary 90 % interval lies in [0.45, 0.55] (an equivalence test, TOST-style); unevaluable controls are explicit UNVERIFIABLE. The replay protocol reveals a label only when a policy selects the peptide and adds data-matched one-shot, random, shuffled-label and frozen controls, within-group ranking with one revealed/target split, laboratory-cluster bootstrap, and a quantified transductive source-standardisation leak.
(b) Evidence (read from `docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md` abstract and section 1.1, and `docs/20261031_PAPER1_MORNING_PACKAGE.md`):
- 6,960 PAMPA labels, 41 literature sources (CycPeptMPDB) plus a BindingDB/ChEMBL family-held-out binder benchmark.
- Loop minus frozen initial fit: +8.0 hits/500 (CI of mean 3.6 to 12.5) in-distribution; +1.5 (-1.9 to 4.8) scaffold-shifted; full-pool held-out-lab regimes +47.3 (34.6 to 58.2, chirality-aware GBM), +13.2 (blind GBM); matched candidate-subset values +8.4 / +3.1, so the large full-pool numbers are largely a protocol effect.
- Loop minus random +186 (in-distribution) is flagged post hoc, transductive, upper bound; 63.6 % of inactives censored vs 3.1 % of positives; no benchmark built is VALID (analysis I: NOT_VALID_BIASED; equivalence unreachable at 14 to 26 families).
- Baselines: random, shuffled-label, frozen, one-shot, kNN/GBM/GP; split = leave-lab/target-family; interval types labelled per number (spread vs CI of mean vs cluster).
- Verifier: 123 checks, final_pass clean (`research/guangzhou_all_atom/cyclic_llm/qa_audit/verify_artifacts.py`, `final_pass.py`) per the morning package; I did not re-run it.
(c) Audit status. Strongest in the repo: independent data review, three committee rounds (round 3: major revision), red-team (`docs/20261030_REDTEAM_REVIEW.md`, R1-R15), claim ledger (`docs/20261030_CLAIM_EVIDENCE_LEDGER.md`, not read in full). Red-team items still open: R1 (title promises an LM comparison that was never run; v2 retitles), R5 (seed intervals do not describe new labs; needs lab-cluster resampling on every headline contrast), R10 (no "random within the highest-yield source" or source-prior arm), R7 (database version/hash undocumented). The morning package lists the causal-normalisation arm as NOT implemented, so loop-minus-random stays demoted. Superseded numbers exist (pre-source-correction K_phys, T1 cells); they are labelled.
(d) Prior-art risk. Draft itself says "we claim no benchmark or architecture novelty" and cites PepBenchmark, an inter-laboratory PROTAC-permeability ceiling (arXiv 2605.11764) and Amirahmadi (arXiv 2511.21566) with tags LIT-SUMMARY / LIT-VERIFIED (`docs/20261030_PRIOR_ART_PEPBENCHMARK_PROTAC_CEILING.md`: similarity-controlled evaluation and inter-lab ceilings are NOT novel). Equivalence-testing of benchmark validity as a gate: [UNVERIFIED] by me; the draft does not cite a primary source for it. Risk: high that a referee calls it "standard TOST plus decoy baselines".
(e) Referee demands / cost. (i) Lab-cluster resampling on every headline contrast (CPU, hours, USD 0). (ii) Causal-normalisation arm to price the transductive leak (CPU on existing code; ledger says planned; est. one working day, USD 0 to about 15 spot [estimate]). (iii) Source-prior and within-top-source random arms (T2 code can supply, est. USD 1 to 3 [estimate from T2 doc A4.4]). (iv) A positive control showing the gate CAN pass: no benchmark passes, so a referee will ask whether VALID is reachable at all; a planted-valid synthetic benchmark closes this (CPU, hours). (v) Reconcile CycPeptMPDB counts (R7). The cheap control to do first is (iv).
(f) Venue. J Cheminformatics, JCIM, Digital Discovery, or an ML-for-drug-discovery workshop (draft's own list). Not NeurIPS main.
(g) Verdict: WRITE AFTER ONE CHEAP CONTROL (planted-valid benchmark showing the gate can return VALID). Honest framing: an evaluation-and-controls paper with a negative headline, not a method that wins.

### 2.2 KB / harness dividend scales inversely with model strength
(a) Method. Not a technique; a measured regularity: supplying grounded candidate context (retrieved catalog with descriptions) lifts selection accuracy more for weaker models, and removes scientifically invalid choices. Companion contribution: a task-split rule (harness-carried vs LLM-bound).
(b) Evidence (read from `docs/20261004_KB_DIVIDEND_UNIFIED.md`, `docs/20261004_BIOC_SELECTION_MATRIX_RESULTS.md`, `docs/20261022_OPEN_MODEL_BARE_VS_HARNESS_ONPREM.md`, `docs/20261026_HELDOUT_INDEPENDENCE_AUDIT.md`):
- Bioc method selection, n=40: base Qwen3.5-9B bare 0.800 -> +KB 0.950 (+15.0pp), invalid-regime 0.125 -> 0; gpt-5.6 1.000 -> 1.000; opus-5 1.000 -> 0.975; gemini-3.1-pro 0.975 -> 1.000; deepseek-v4-pro 0.825 -> 0.923.
- Routing (RealBio cross_domain_routing, n=200): 9B 0.18 -> 0.815 (+63.5pp); Opus-5 0.615 -> 0.960. A separate 10-open-model table gives +39 to +70pp with the 9B at 0.12 -> 0.82 (different run); the claim registry (`docs/20261026_RESULTS_RELEASE_v1_CLAIM_REGISTRY.md`) uses 9B 0.180 -> 0.905 as canonical under the described menu. Three different 9B routing pairs exist in the repo.
- Held-out independence audit: the dividend "reproduces on held-out queries" with the same inverse-scaling pattern (numbers in that doc, not extracted by me).
- Interval type: none reported. n=40 bioc, n=200 routing. No CIs (the doc itself says "report CIs").
(c) Audit status. Held-out independence audit (2026-10-26) positive. Caveats in-file: routing dividend is a retrieval dividend, bioc is an in-context-description dividend; frontier near ceiling so bioc discriminates only weak models; RealBio self-grading caveat. The adjacent SFT claims were retracted (section 3 row 1) and the program's own conclusion is "the harness, not the SFT, is the lever", which is consistent with this finding. No leak/retract note found against the dividend itself (grep of `dividend` files for retract/leak/superseded returned only the SFT-verdict docs reinforcing it).
(d) Prior-art risk. High: "retrieval/in-context knowledge helps small models more than frontier models" is close to folklore; [UNVERIFIED] by me (no primary source opened). The novel angle would be the invalid-regime (scientific-validity) metric and the task-split rule.
(e) Referee demands / cost. Bootstrap CIs on the existing predictions (CPU, hours, USD 0); reconcile the three 9B routing pairs into one table with matched menus; a harder-for-frontier task (the doc admits frontier is at ceiling); a non-BioMate retrieval baseline (BM25 or generic dense retriever on the same catalog) to show the "knowledge layer" is BioMate-specific. Last item may need LLM calls (paid, needs approval) [estimate: tens of USD on OpenRouter].
(f) Venue. NeurIPS D&B analysis track / Bioinformatics / PLOS Comp Biol (Paper B draft's list), likely weak for "method innovation".
(g) Verdict: WRITE AFTER ONE CHEAP CONTROL (CIs plus one reconciled matched-menu table). Do not present it as method innovation.

### 2.3 Rule layer + LLM + abstention guardrail for parameter extraction
(a) Method. Hybrid extraction: deterministic rules (alias normalisation, unit conversion, negation, organism-to-genome, strandedness kits), LLM for free text, schema-allowed-value validation, and an IO guardrail that drops hallucinated prose inputs; rules abstain outside covered classes.
(b) Evidence (read from `docs/20261026_RESULTS_RELEASE_v1_CLAIM_REGISTRY.md` section 2, `docs/20261026_HELDOUT_INDEPENDENCE_AUDIT.md`): raw on-prem 9B F1 0.703 (P 0.785 / R 0.636, 53 must_not_fill violations); rule layer alone 0.470 (P 0.960, R 0.311, 4 violations); production rules + 9B + IO guardrail 0.843 (P 0.900, R 0.793, 27 violations). Held-out set (fresh items, authored without reusing tuned items): covered classes 15/17 = 88 %, zero hallucinations; uncovered organisms correctly abstained.
(c) Audit status. The rule layer and scorer were changed after error inspection (dev-tuned); the held-out audit was the rebuttal and is positive but n=17 covered items. Registry says the 0.843 is an "offline approximation" and the canonical run (`run_param_prefill.py` vs the live backend) is still to run. A later fix (commit 3cc6ff724 message) says F1 0.803 -> 0.843, i.e. the number moved with post-hoc guardrail changes [commit message read, not diff]. Different 9B pair elsewhere (0.628 vs 0.703 raw; `docs/20261024_SFT_CLEAN_EVAL_VERDICT.md` vs registry): unreconciled. 
(d) Prior-art risk. Rules-plus-LLM hybrids and schema-constrained extraction are standard [UNVERIFIED]. The CLAUDE.md hybrid-extraction principle is a design rule, not a result.
(e) Referee demands / cost. Canonical run on the live backend (hours; backend access); a frontier-model baseline with the same schema validation (paid API, needs approval); n well above 17 held-out items; CIs; ablation per rule class. Estimate 2 to 3 days plus a modest API bill [estimate].
(f) Venue. Bioinformatics Applications Note, or the RealBio paper as a section.
(g) Verdict: NOT READY.

## 3. Other leads checked

| # | lead | finding (file) | verdict |
|---|---|---|---|
| 1 | Collected-gold SFT, decomposition node-F1 0.36 -> 0.73 | RETRACTED. 0.73 is decomposition_v2, in-distribution/leaked; out-of-generator decomposition_real is 0.016 (base) vs 0.087 (v3 adapter) (`docs/20261019_ONPREM_LLM_V3_SFT_MEASURED_AND_GRPO_READY.md`). Later SFT on clean data regressed routing 0.885 -> 0.53 and, with deployment-condition prompts, 0.880 -> 0.835, param F1 0.634 -> 0.516, decomp structure_acc 0.368 -> 0.000 (`20261024_SFT_CLEAN_EVAL_VERDICT.md`, `20261025_DEPCOND_SFT_EVAL_VERDICT.md`). Memory lead is wrong/superseded. | DEAD (publishable only as a negative: "naive SFT harms a base+harness system", two conditions, n=200/170) |
| 2 | Execution grader as verifiable reward, unified GRPO over 12,275 rows | Grader persisted store and reward ladder built and CPU-selftested; unified GRPO fired 2026-10-22 and stalled: frac_reward_zero_std 0.95 to 1.0, KL about 0.001, step about 150/400 (`20261023_RL_DATAGEN_STUDY_DESIGN_SURVEY.md`). No trained-adapter result found. Also a train==test flaw was found and fixed (22 train / 8 eval). | NOT READY (no result) |
| 3 | KB dividend | section 2.2 | rank 2 |
| 4 | Evidence-tiered trust lattice (grounded-prototype) | Only found as design/prototype in `20261014_GROUNDED_STANDARDS_ASSISTANT.md` (not read beyond title); no controlled comparison located | NOT READY [not opened in depth] |
| 5 | Target-ID: channels -> OT harmonic-sum arbiter | Fusion does NOT beat OpenTargets-alone: 0/17 (expand), 3/17 (corroborate), mean AUROC 0.583 vs 0.610 (`20261021_TARGETID_FUSION_VS_OPENTARGETS_BENCHMARK.md`). LLM channel adds: LLM alone 0.764 vs OT-genetics 0.424 (10 immune diseases), but a memorization control tempered the claim (`20261025_TARGETID_LLM_CHANNEL_CONTRIBUTION.md`). This is the immune track, excluded per instructions. The "IMPRES 0.598" is a field bar quoted in the fusion doc, not our result. | EXCLUDED / NOT READY |
| 6 | Verifiable guardrails + gate families G1-G8 | Taxonomy plus implementation described; manuscript states large-scale and SRVL results are future work, evaluation is a pre-registered protocol (`20261027_MANUSCRIPT_verifiable_guardrails_scientific_agents.md`). No measured result against a baseline. Possible IP sensitivity (SRVL formulation): flagged, not summarised. | NOT READY (position paper) |
| 7 | Drug novelty/FTO gate (20/22) | Engineering gate (Tanimoto NN vs known actives, optional patent presence); no baseline or accuracy evaluation; `20261005_DRUG_NOVELTY_FTO_GATE.md`. Patent-claim mapping docs (`20261014_AVB6_FTO_READ.md`) are IP/legal-sensitive: flagged, not read for summary. | NOT A PAPER |
| 8 | Lane arbiter, dense-cosine resonance | Overall accuracy 39.1 % (keyword) -> 95.0 % -> 97.1 % with guards (`20260909_LANE_ARBITER_CATALOG_RESONANCE.md`). Self-built eval (200 cloud + 40 instant), guards tuned on the same set, a cosine threshold of 0.60; weak keyword baseline. Engineering, no CIs. | NOT A PAPER |
| 9a | BoltzGen/Boltz generate -> physics rerank / cofold selector | Stage B one-shot (104 post-cutoff complexes): selector S2 59.6 % vs default 57.7 %, random 59.6 %; primary claim NOT SUPPORTED (`20261027_PROGRAM_STATUS_VERIFIED.md`). | DEAD (negative result, could be a short note) |
| 9b | HELM/ncAA monomer LM, unified v4, display-binding selector | "Within-target win" WITHDRAWN: k-mer LR matches the LM on Abeta42 (0.986 vs 0.990) and hIAPP; only PADI4 may hold (`20261027_SELECTOR_LEAKAGE_AUDIT.md`). v4 audit: hard-negative AUC at chance on 4 of 5 targets; ncAA fraction equals training rate (`20261028_V4_LLM_AUDIT_AND_EVAL.md`). | DEAD |
| 9c | IH-LM ladder (symbolic retrieval, K prior, offsets, edit layer) | No module claimed under the pre-registered rule; M3 analog retrieval consistent (L: dev +12.1 hits, conf +9.5) but shuffled-label gate control fails in A and L; full model below GBM/GP on yield in L (`20261030_IHLM_LADDER_RESULTS.md`). | NOT READY |
| 9d | Evidence-weighted fusion (T1/T1b) | Corrected: F2 beats its own components at k=5 (+0.058 [0.010, 0.108], 16 labs) but loses to the learned prior PT+k (-0.132 at k=5); exploratory, 5 seeds, planted control (i) failed (`20261031_T1_T1B_RECOMPUTED_CORRECTED.md`) | exploratory, folded into Paper 1 section 6 |
| 9e | Acquisition (T2), pilots 3/4, C2 binding loop | T2 PARTIAL (S1 only in regime B; S3 fails), "NOT SUPPORTED as a technique claim"; pilots 3/4 are go/no-go not paper evidence; C2 margin over random is mostly the fixed cross-target transfer model (learn - fixed +0.050) with paralog-leakage risk (`20261030_TECHNIQUE_T2_ACQUISITION.md`, `20261030_C2_RERUN_AND_ANCHOR_TEST.md`) | NOT READY |

## 4. IP / sensitivity flags (not summarised)
- `docs/20261014_AVB6_FTO_READ.md` and patent-claim mapping in the cyclic program (named patent family and claim reading): legal/IP-sensitive.
- SRVL formulation and rule-compiler substrate in the guardrails manuscript: possible patentable subject matter; check with the owner before any public preprint.
- Unpublished cyclic-peptide candidate sequences and CRO order files (`*_CRO_ORDER*`, `*_PDL1_ORDER*`): not for a methods paper.

## 5. What I did not do
- No web search; all prior-art statements are [UNVERIFIED] unless the cited repo document opened the source itself.
- Did not read `20261030_CLAIM_EVIDENCE_LEDGER.md` (111 KB) in full, nor the 25 other docs the earlier excavation (`20261030_UNMINED_ASSETS_EXCAVATION.md`) left unopened; a claim here that "nothing else qualifies" is bounded by that.
- Did not re-run any verifier, test or evaluation.
