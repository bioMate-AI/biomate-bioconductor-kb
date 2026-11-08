# Perturbation module review — 2026-09-12

Scope: complete source read of `perturbation_observations.py`, `czi_irm_head.py`, `train_czi_irm.py`, and `czi_leave_ko_out_baselines.py` in the immune training worktree. No cloud writes or training-worktree edits were performed by this review lane.

## Verified defects and staged repairs

1. **Numerical comparison loses precision.** `aggregate()` rounds mean correlations to four decimals before `train_czi_irm.py` compares heads against baselines. For example 0.05664 and 0.05663 both become 0.0566. The staged repair preserves numeric precision; formatting should occur only for display. This cannot establish meaningful scientific improvement by itself.
2. **Ambiguous gene mapping silently chooses a row.** Duplicate readout symbols/Ensembl identifiers are resolved to the last entry, blank identifiers map to blank readouts, and mismatched identifier lengths silently truncate through `zip`. The staged repair uses only unique nonempty mappings and rejects length mismatches; a unique Ensembl match still resolves a duplicated symbol.
3. **Invalid aggregate scores accepted.** Infinity enters the reported mean and JSON rather than raising. The staged repair rejects infinite correlations while retaining NaN exclusion for undefined correlations.
4. **Stale donor description.** The baseline module describes `by_donors` as a future independent donor factor. Available source inspection shows overlapping donor pairs. Comments are corrected to require disjoint underlying donors.

Staged files: `/tmp/immune_parallel_module_review/czi_irm_head.py`, `czi_leave_ko_out_baselines.py`, `test_module_review.py`. Six adversarial regressions: original source fails five and passes one; staged source passes all six. These changes have not yet been installed by this lane. Existing predictions were not changed or re-fitted.

## Scientific and architectural limits for the next experiment

- Current head takes target identity and condition only. Donor baseline state cannot be evaluated by merely relabeling its condition environment; it needs an explicit input and a dataset manifest connecting that input to genuinely disjoint donor observations.
- Missing effects remain NaN and training uses observed entries. The active readout axis is frozen from training observations for both baseline and head scoring, which is appropriate. `masked_effect_mse` itself treats infinities as missing, so external callers must use the validation entry point (`effect_observations`) first; the reviewed training path does.
- ERM and IRM use matching per-minibatch equal-condition risks. Random minibatches do not guarantee an exactly equal-condition full-dataset objective when condition sample sizes are highly imbalanced. A donor/state evaluation should use balanced sampling or explicitly document minibatch weighting, with the same schedule across controls.
- IRM environments are culture conditions, not held-out conditions or donors. No causal or donor-generalization conclusion follows from this implementation.
- The tied readout embedding is trained on effects for all readout genes. Unseen target identity therefore has an embedding learned as a readout; this is the intended transfer hypothesis, not direct training on held-out target contrasts. Controls remain essential.
- Undefined constant-prediction correlations are excluded, with zero-change set to an explicitly conventional zero floor. Report scoreable row counts and compare paired eligible populations before stronger gates. Pooled row/seed standard deviation is not uncertainty over independent donors.
- Driver uses fixed epochs and reports only correlations, not reproducible checkpoints/predictions. It is a development comparator; the forthcoming state-aware driver should save split IDs, raw predictions, numeric baseline metrics, and input provenance.
- The retained `no_target_token=False` path aliases unknown targets to gene row 0; current default uses a separate token. Do not use the legacy option for a prospective named-target interface.

No claim was made that these four modules represent the entire immune system, or that passing implementation tests validates biological predictions.

## Follow-up: public loss boundary hardened

Staged `perturbation_observations.py` now rejects either infinity in `masked_effect_mse` and rejects infinities before environment grouping in `environment_risk`. This closes the previously noted public-boundary gap, including an infinity-only group that previously looked missing. NaN masks and training objectives are unchanged. Three additional regression methods cover both infinity signs, ERM/IRM paths, and unchanged loss/zero gradient for a NaN-only group. All nine new test methods pass; the combined existing observation suite plus new suite passes 21 tests. The legacy CLI subprocess in that existing suite runs its original source path, so it is not claimed as a patched-CLI integration check.
