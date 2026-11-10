# Scientific and editorial review — 7 November 2026

Both manuscripts have been revised as author-review preprints, not certified as submission-ready. The original Markdown manuscripts and their figures were left unchanged. All conclusions below refer to the local evidence snapshot reviewed on this date; no new paid model evaluations were run.

## Deliverables and editorial changes

The revised `realbio.md` and `drugdev.md` are the editable sources for Word and watermarked PDF outputs in `out/`. Results now follow the Introduction, followed by Discussion and Methods. Abstracts are condensed, reference citations are integrated, and unverified release claims and absolute novelty claims are removed. Author names, affiliations, correspondence, funding and declarations remain explicit placeholders.

RealBio retains the original numerical table and routing figure, with corrected terminology and captions. Other original figures are omitted from the revised draft where their interpretation was not sufficiently supported. DrugDev replaces the superseded outcome plots with an information-access diagram and transparent results tables. This is a substantive scientific revision, not only a copyedit; review the narrowed claims before circulation.

## Findings requiring resolution before submission

### RealBio

1. **Catalog selection is not a measured retrieval pipeline.** `evaluation/datasets/public_export/rerun_routing_openrouter.py::build_menu` constructs a fixed sorted menu from the benchmark's correct labels, adding descriptions from the workflow database. No query-specific retrieval occurs in this runner. The revised paper calls the condition catalog-assisted selection and removes the unsupported connection to an approximately 0.80 end-to-end figure. Establish a test-independent catalog, freeze the retrieval implementation and document recall before making an operational retrieval claim.
2. **Conditions are not fully uniform.** `regen_leaderboard_csv.py` prefers described-catalog files but falls back to names-only catalog files. Some model provenance also differs. GPT-5.6 and GPT-5.6-luna are distinct rows; the original omission note concerned GPT-5.6, not the retained luna row. Archive one per-cell manifest including exact model identifier, prompt, catalog, serving configuration, timestamp, retries and denominator. Treat Biomni's catalog-in-both-columns row as a system result, not an ablation.
3. **Rule-layer gain uses answer-informed schemas and a separate scorer.** `evaluation/local_trial/measure_production_param_rules.py::_ap` constructs allowable fields from expected answer keys and forbidden keys. Its local `veq` is not the shared scorer implementation. The reproduced 0.703 / 0.470 / 0.843 values are retained as an exploratory offline comparison. The merged system still has 27 forbidden-field violations. Re-evaluate against real workflow schemas independent of gold answers and one scorer before claiming production F1.
4. **Missing identifiers can disappear from denominators.** The routing and several other scorers skip absent prediction IDs. Enforce complete coverage or count missing predictions as failures under a documented policy, then report per-cell coverage. The manuscript does not silently rescore the original table.
5. **Parameter F1 is a nonstandard key–value convention.** Wrong values on expected keys incur a false negative but not an additional false positive. State this explicitly; report forbidden-field violations alongside F1.
6. **Workflow generation mixes evaluation artifacts.** The saved subset summary differentiates thresholded tool success from mean recall. The legacy aggregate leaderboard has mostly 0.500 workflow-generation values. Do not blend these into one endpoint or imply that 0.95 is mean recall. Freeze and reconcile the subset predictions and scoring version.
7. **The independence audit is narrower than claimed.** The reproduced 15/17 counts expected values in covered probe classes, not 17 independent workflows. Two boundary values remain unfilled and are excluded from that fraction. Zero forbidden-field violations is not a universal zero-hallucination result. Held-out routing claims need sample sizes and matched run receipts before confirmation.
8. Add independent label adjudication, dates and run-level uncertainty. The revised manuscript does not claim statistical parity, causal scale effects, or successful execution of repairs.

### DrugDev

1. **Incompatible dose denominators.** The legacy `score.py::score_boin` excludes the two null-dose labels: it scores 18 cases, despite a leaderboard header saying 20. The oracle and structured-response experiment score 20. The revised paper separates these protocols and removes the mixed-denominator plot. Author decision needed: define no-dose cases as legitimate outcomes, adopt one policy and rescore all raw predictions.
2. **Oracle access is privileged.** The reference uses the hidden curve, not solver-visible inputs. Its 17/20, safety 0.90 and fidelity 1.00 reproduce. It is not an executable mechanistic pipeline or a guaranteed upper bound. Three label-policy disagreements must be adjudicated independently.
3. **The rule is not the full BOIN design.** The implementation uses a fixed target-plus-0.10 band and nearest-to-target selection with higher-dose tie breaking. It lacks sequential patient allocation and the full Bayesian elimination/final-selection procedure. The manuscript now labels this as a benchmark rule and cites BOIN only to distinguish it.
4. **Malformed responses may receive credit.** `e2e_scorecard.py::score_item` and `evaluation/local_trial/dose_eval_spark.py::score_item` accept absent dose fields as no-dose answers in null-reference cases, even for `{}`. Contradictory flags, invalid probabilities and incomplete curves need explicit validation. Existing scores remain unchanged and provisional. Recompute from raw responses with a versioned validated scorer; derived outcome-only receipts may be insufficient. The sampled direct-provider GPT hand runs did not mark the two credited no-dose items as empty, so this audit does not claim those particular two hits are caused by empty responses.
5. **Generated PK references are not full oral Cmax or steady-state models.** `generate_pk_v2.py` computes F × dose / molecular-weight / volume with unit conversion. There is no absorption, clearance-time course or accumulation calculation. `generate_dose_v2.py` also calls an instantaneous concentration steady-state in a comment. The revised text states the actual formula and assumptions. Decide whether to rename the endpoint or implement and validate the intended PK model.
6. **PK reference provenance requires scientific validation.** The 15 hand-authored references reproduce as scorer inputs; their clinical analyte, total/free concentration, units, source study, formulation, route and context are not established by reproducing scores. Obtain source-level evidence before treating them as physiological truth. The generated tier has 15 additional cases, but the reported PK leaderboard is only the hand tier.
7. **Run provenance and summaries differ.** `results_fixed` uses a GPT-6.1-sol-pro label; `results_direct` uses GPT-6.1-sol. These are not merged. Per-item Gemini direct-provider fidelity averages also differ slightly from the saved summary. Receipt-derived means are stored in `audit/dose_receipt_summary.json`; no disputed summary value is silently substituted into the original manuscript. The three generated Opus repeat files are 1.00, 1.00, 0.95 in file order, not the chronological order implied by the old prose.
8. **Superseded scorecard removed.** The original Figure 3 expressly used smaller-budget results superseded by the text. It is unsuitable as a current results plot. A 20,000-token claim in prose does not replace run metadata; the earlier runner specifies 12,000 tokens.
9. The tier contrast does not isolate exposure–response inference, model scale or reasoning. References and task construction change together. The cross-stage track remains unmeasured across a model roster. Do not describe it as completed execution validation.

## Reproduced checks

- Ran both leaderboard scripts in `--stdout` mode; preserved output under `audit/` without overwriting the stored leaderboards.
- Reproduced the rule-layer experiment and held-out deterministic audit.
- Imported the oracle routine without running its writing CLI; reproduced 0.85 / 0.90 / 1.00 at n=20.
- Aggregated all 22 retained dose receipt files from fixed, direct, repeated-generated and local configurations; stored counts, outcomes, fidelity and empty counts.
- Inspected the actual dose and PK scorers, catalog builder and generated-reference formulas.
- Verified primary reference pages for SWE-bench, MLE-bench, ScienceAgentBench, CORE-Bench, PaperBench, BixBench, TrialBench and Therapeutics Data Commons. The 2016 BOIN article's indexed primary record supports the bibliographic details; full-text access encountered an access challenge. These checks are not a systematic novelty review.

## Author decisions still needed

Provide final author metadata and release identifiers; approve the narrowed scientific scope; resolve the dose-label policy and PK reference definitions. Then freeze data/scorer versions, validate malformed-output handling, recompute affected scores and add paired uncertainty. A polished document cannot substitute for these scientific decisions.

## Document verification

Final Word files contain six pages each; final PDFs contain seven pages each. All pages were rendered and visually inspected, including the corrected tables and equations. DrugDev Word equations remain editable OMML; PDFs use Chrome MathML rendering. PREPRINT watermarks are present in both formats. Original manuscript hashes were checked unchanged. Unified source diffs and the evidence audit are retained in `audit/`.
