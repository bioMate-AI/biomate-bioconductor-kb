# Paper 1 takeover audit — 2026-10-29

Initial read-only review of the manuscript, figure generators and stored results, followed by a manuscript revision after the user's explicit new instruction to polish paper 1. The date follows the user's current calendar. Existing filenames dated October 30–31 are retained as identifiers, not treated as proof of execution dates. No AWS job, Drive write, release or submission was performed by this workstream.

## Manuscript ownership and evidence

The local master is `docs/20261030_MANUSCRIPT_EVAL_CONTROLS_DRAFT_v2.md`. The handoff initially protected manuscript edits; the user's subsequent explicit request to polish paper 1 superseded that hold. `git status --short` showed no change to the manuscript before revision. Its baseline is available at commit `b6f44a3dee81b5cf2d02aa212a6839ce95851459`, with a temporary byte copy at `/tmp/paper1_before_codex_polish.md`. The old long draft is `docs/20261029_MANUSCRIPT_LOOP_SMALL_LLM_DRAFT.md`. Working decisions, unresolved issues and the number-to-file registry are in `docs/20261031_PROGRESS_PAPER1.md`.

The Drive snapshot is [Paper 1 working copy](https://docs.google.com/document/d/15IasdhKzy-L-BNW5gpmZoKu9zxCpcRTq1UV0ynBWRFI/edit), recorded in `docs/20261031_PAPER1_DRIVE_COPY.md` as a conversion of commit `164bcd82d98bc48e01da15bf9ccadb9eb750dbea`. Its current remote contents were not checked. The handoff supersedes the earlier Drive-master arrangement: do not overwrite or reconcile either copy automatically.

## Verified local findings

- The manuscript contains no embedded figures. The handoff's figure-building agent failed at the spending limit; no completed new main-figure package was identified.
- `research/guangzhou_all_atom/figures_paper/committed/` contains ten figure stems, each as PDF and PNG, plus eight table files in its manifest. All **28** SHA-256 entries match local bytes. The status document describes eleven rendered items because it also lists `F11_coverage_partial`, which is absent from the committed manifest. Hash integrity does not establish current scientific suitability.
- `research/guangzhou_all_atom/cyclic_llm/loop_retro/results/l7_aggregate.json` matches the frozen SHA-256 `ebc525090740249f50ec4e2d96cd809e6b6b802c0f42ad2f7815f2dbdb76387e`.
- `cyclic_llm/paper1_cluster/results/paper1_cluster.json` independently contains the aware learner, regime L, full-protocol loop-minus-frozen yield estimate **47.3**, cluster-t interval **[-53.011, 147.611]**, 14 source clusters, top-source share **0.887**, and estimate without that source **0.9**. All paths in this paragraph are relative to `research/guangzhou_all_atom/`.
- The full manuscript verifier was inspected but not run: `cyclic_llm/qa_audit/verify_artifacts.py` executes `verify_v2_numbers.py`, which writes `qa_audit/v2_unchecked_numbers.txt`. Its membership checks are weaker than verifying that a quoted number belongs to the stated quantity.

## Figure defects to resolve before reuse

1. **L5 interval labels are wrong.** `figures_paper/f_l5_loop.py` uses `ci95` while labelling panel (a) and its caption as a bootstrap confidence interval of the mean. In `loop_retro/results/l5_aggregate.json`, regime B has `ci95=[-1.6,44.1]` (the registered per-seed spread) and `ci95_mean=[17.7,26.5]` (the post hoc mean interval). Preserve the registered decision and show the two interval types separately; do not silently substitute the favourable mean interval. The registered criterion remains unmet.
2. **The original gate figure is obsolete as a main result.** `figures_paper/f3_validity_gates.py` reads original gate files and labels chance-excluding controls as failed. It does not show calibration/error rates, the corrected interpretation of analysis M, or the calibrated analysis-I verdict carried by censoring and assay type. It cannot support the manuscript's current calibrated-gate claim without revision.
3. **The older figure scope exceeds paper 1.** The pending cost/performance, larger-model comparisons, architecture ladder and corpus-overlap placeholders in `docs/20261030_FIGURES_STATUS.md` are not evidence of completed results. Keep model-method results with the separate method paper. Avoid assembling every legacy plot merely because it exists.

## Main figures to build from existing results

| Figure | Scientific question and panels | Exact local evidence |
|---|---|---|
| 1. What does retrospective feedback measure? | Replay schematic distinguishing initial labels, acquisition labels and held-out evaluation; source/scaffold/family boundaries; transductive normalisation marked explicitly. Adapt F1/FCV, with legends aligned to the current Methods. | `figures_paper/f1_schematic.py`, `figures_paper/f_cv_schemes.py`; manuscript Methods; `cyclic_llm/loop_retro/PREREG_LOOP.md`. |
| 2. Yield is reproducible across seeds but concentrated by source | Learners shown separately; full versus sub protocol explicit; paired forest of seed and source-cluster intervals; source contribution and leave-largest-source-out sensitivity. Include held-out within-source ranking in a separate panel so yield is not mistaken for generalisation. | `cyclic_llm/paper1_cluster/results/paper1_cluster.json`; `cyclic_llm/loop_retro/results/l7_aggregate.json`. |
| 3. Calibrating the validity instrument changes the interpretation | Original versus calibrated false-alarm rate by family count; VALID/INCONCLUSIVE/BIASED frequencies; sensitivity only at tested planted shortcut strengths; analysis-I censoring and assay controls with calibrated thresholds. | `multitarget/integrin_chembl/retro_recovery/gate_positive_control/results/gpc_summary.json`; `gate_calibration/results/gcal_eval.json`, `calibration_frozen.json`, `real_records.json` under the same recovery directory. |
| 4. Limits of few-label transfer | Family-equal performance against exact-potency neighbour controls, by label count and hard stratum; distinguish screening from confirmatory inference. Use as main or extended data depending on final narrative length. | `cyclic_llm/ihlm_backbone/pilot4/results/test_summary.json`; Methods and Appendix B; existing `figures_paper/f_h4b_fewlabel.py` is only historical context and must not substitute its different benchmark. |

All evidence paths in the table beginning `figures_paper/`, `cyclic_llm/` or `multitarget/` are rooted at `research/guangzhou_all_atom/`. New figure generators should select records by explicit analysis, learner, regime, protocol, contrast and metric; assert exact values and source hashes; export vector PDF plus PNG; and include sample units and interval definitions in legends. Visually inspect final pages at journal column size. No new GPU run is necessary to build these figures.

## Claim boundaries and remaining work

The manuscript already limits loop-versus-random gains to a transductive upper bound. Causal source normalisation using revealed labels only has no implementation/result in the progress record; source-matched random has code but no result. These remain experimental gaps, not prose fixes. The original gate's false alarms and calibrated gate's narrower tested scope must be displayed together. Calibrated detection below AUROC 0.65 remains untested. Reconcile the recorded **2,900 versus 2,940** validation-record discrepancy before reporting an overall denominator. Retain source-id-as-laboratory limitations and the unresolved CycPeptMPDB data-licence question.

For the eventual rewrite, build connected Results paragraphs around the two primary findings, move decision rule lists and provenance tables into Methods/supplement, and use figures for contrasts now repeated across tables. Do this only on top of the user's saved master. Do not claim a new all-atom architecture result in this benchmarking paper.

A targeted filename search under `/Users/kky/.claude/skills` and `/Users/kky/.codex/skills` found no Nature/scientific-writing/manuscript-writing skill. This is a bounded negative search, not proof it is unavailable elsewhere; no skill was installed or substituted. Figure preparation and evidence checks can proceed without it.

## Prose revision after renewed authorization

The new manuscript has approximately 2,400 words from title through Discussion, followed by references, Methods and supplementary numerical records. The two contribution/claim tables were replaced by connected narrative. All eleven references remain verbatim; all six numerical tables remain intact in the supplementary material. Supporting architecture-development and knowledge-channel claims are not promoted into primary findings.

Four figure references and their exact generator legends are embedded using portable paths under `docs/figures/paper1_review_20261029/`; the parent workstream owns AWS rendering and visual inspection. Legends were extracted as literal strings from `research/guangzhou_all_atom/figures_paper/paper1_review.py` without executing it locally. Figure 2 distinguishes seed-t from source-t intervals; Figure 3 compares gates on matched validation records; Figure 4 separates descriptive curves from registered 97.5% screening contrasts. Availability of the rendered files and final visual inspection must be verified by the parent before distribution.

The revision corrects a substantive contradiction: the old abstract and introduction claimed revealed-label-only normalisation even though Methods and the progress record explicitly said the implemented replay was transductive. The new abstract, Results and Methods consistently state the implemented condition and the missing causal-normalisation experiment. Regime-L acquisition yield is also explicitly distinguished from ranking on unseen sources. Overlapping model intervals are no longer described as establishing indistinguishability without a paired test.

In the absence of the requested local writing skill, organization follows the official [Nature formatting guide](https://www.nature.com/nature/for-authors/formatting-guide) and [initial-submission guidance](https://www.nature.com/nature/for-authors/initial-submission): a concise narrative supported by four display items, with detailed Methods and supplementary records separated. This is a fallback to published guidance, not use of the missing skill, a journal decision or a claim of submission readiness. Authorship, funding, conflicts, public archival identifiers and final journal-specific requirements still require resolution before submission.

## Independent review resolution

Applied the seven scientific corrections in `docs/20261029_PAPER1_SUBMISSION_REVIEW.md` to the manuscript and figure renderer without running new analysis or rendering locally:

1. Source shares now explicitly divide absolute source contribution by the sum of absolute contributions. The 0.9-hit sensitivity subtracts an observed contribution; neither training nor acquisition was rerun. Figure 2's marker label is “Largest contribution subtracted”.
2. Removed the unsupported prospective upper-bound claim from prose and Figure 1. Prospective bias remains unquantified.
3. Distinguished candidate-subset bootstrap ranking contrasts from full-pool t-interval contrasts. Supplementary Table 2 identifies subset frozen/shuffled columns versus full-pool random feedback. Supplementary Table 1 identifies the distinct L7 versus source-cluster bootstrap estimates; Figure 2 displays t-intervals.
4. Figure 3 now identifies nulls as permutations on real structures and synthetic family structures. Its point-rate reference line is not presented as proof of a population ceiling. The threshold annotation moved to a boxed upper-right label for the parent's remote visual recheck.
5. Detection claims apply to tested cells. The censoring shortcut was tested only at AUROC 0.65 in the 25-family design. Observed zero VALID events retain an approximate 0.060 upper confidence bound per cell.
6. Methods and Supplementary Note D give the exact acceptance conditions: false-alarm point rate ≤0.10 and upper 95% bound ≤0.15; detection point rate ≥0.80 at 0.65 or ≥0.90 at 0.70; VALID point rate ≤0.05 at 0.65. The real-data raw-max permutation test and add-one correction are separate from the standardised calibrated gate.
7. Historical primary-control intervals are identified as historical with 25/25/26 families for typicality/multiproxy/fingerprint, respectively; they are not presented as calibration-recomputed intervals.

Also changed the scaffold-rule comparison from equivalence-like “matched” to “did not detectably outperform”, removed Supplementary Table 3's categorical “so negative”, replaced rulebook language with actions performed, and defined the hard stratum as the bottom tercile of maximum revealed-set Tanimoto similarity for each target/seed/budget (minimum five queries), rather than an unstated fixed threshold. Added inspected model/acquisition settings to Methods. The complete versioned architecture/software-default index remains part of the reproducibility-package requirement, not a fabricated completed deliverable.

### Numerical provenance to retain in the review package

Paths below are rooted at `research/guangzhou_all_atom/`.

| Manuscript quantity | Source and selection |
|---|---|
| Historical analysis-I primary intervals, including fingerprint 0.533–0.636 | `multitarget/integrin_chembl/retro_recovery/results/validity_gate_I.json`, `primary.C1_atomlm_typicality`, `primary.C2_multiproxy_leave_fold_out`, `primary.C3_morgan_fp_leave_fold_out`; counts 25, 25, 26 |
| Calibrated real-I values, flags and permutation tests | `multitarget/integrin_chembl/retro_recovery/gate_calibration/results/gcal_eval.json`, `real.I`; primary intervals here are independently recomputed and must not replace the historical intervals silently |
| Full-pool aware 47.3 yield and 34.6–58.2 seed-bootstrap interval in Supplementary Table 1 | `cyclic_llm/loop_retro/results/l7_aggregate.json`, `small["gbm_aware|L"].contrasts["loop - frozen [yield]"]` |
| Figure 2 seed-t/source-t intervals, contribution shares and subtraction | `cyclic_llm/paper1_cluster/results/paper1_cluster.json`, `rows` selected by analysis L7, learner, regime L, contrast `loop-frozen`, and metric; the independent seed-bootstrap field is 34.2–58.2 for aware yield and is not plotted |
| Candidate-subset ranking in Supplementary Table 2 | `cyclic_llm/loop_retro/results/l7_aggregate.json`, learner/regime `contrasts_cluster` entries `loop_sub - frozen_sub [E source-rho]` and `loop_sub - shuffled_sub [E source-rho]`; random-feedback column selects `loop - random_fb [E source-rho]` |
| Hard-stratum definition and selected few-label settings | `cyclic_llm/ihlm_backbone/pilot4/p4eval.py`; result record `cyclic_llm/ihlm_backbone/pilot4/results/test_summary.json` |

The independent review's submission blockers remain open: author/declaration metadata, journal confirmation, reviewer access, release/reconstruction package, reporting summary and citation verification. These are not resolved by the scientific corrections. Parent workstream owns rerendering, renewed visual QA, review-package assembly and final submission-readiness decision.

The parent subsequently checked bibliographic identity in browser sources for references 3, 6, 10 and 11 (author/title/arXiv correspondence); reference 10's arXiv record explicitly lists ICLR 2026. PubMed record 42557596 confirmed reference 2's authors/title and *Journal of Cheminformatics* 18(1):108, DOI and 4 August 2026 publication date. This is a bibliographic identity check only, not independent full-text verification of the manuscript's scientific claims. The parent's corrected-figure rerender was dispatched as SSM command `725ddeff-6abc-4095-9813-5dd4c8cb473f`; completion and visual quality are not inferred from dispatch.
