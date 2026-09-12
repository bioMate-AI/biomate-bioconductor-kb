# Source design and selection audit — 2026-09-12

The source retains a processing-run label, but it does **not** provide matched cross-run replicates of the same guide/donor/condition. This limits what run correction and replication can establish.

## Run structure

The local source README describes pseudobulks as sums of cell UMI counts aggregated by guide, donor and culture condition. It defines `10xrun_id` as a processing batch (R1 or R2), while single-cell objects retain `lane_id` and concatenate lanes. A run label is not evidence of an independent biological replicate.

Independent grouping of the newly saved `metadata.npz` found 278,684 unique `(donor_id, culture_condition, guide_id)` keys, each associated with exactly one run. There are no same-key R1/R2 pairs in this object. Donors CE0006864 and CE0008678 appear only in R2; CE0008162 and CE0010866 appear in both runs. More specifically, every one of the 12 donor/condition groups has exactly one run. Existing donor/condition control matching therefore already matches processing run. No additional within-group run correction is possible. Run, donor and condition are not fully crossed, so the object cannot identify an independent run effect or create independent replication.

The original target/control extractors retained source row indices but omitted `10xrun_id` from prepared NPZ metadata. Source-row rebinding now confirms that their donor/condition aggregation already implicitly matched processing run. Omitting the field reduced explicit provenance but did not cause control run mismatch in this source. This audit required no expression re-reading. Any corrected comparison must retain donor, condition, guide, run, control-pool identity and cell/library support in its provenance.

## Effectiveness filtering

The README calls `keep_effective_guides` a significance-based t-test flag. Its guide-efficiency table documents Welch's t-tests of guide-cell versus non-targeting-cell target-gene expression, with significant knockdown defined as BH-adjusted p-value < 0.1 and a negative t-statistic. It says NTC counts span all samples. However, the README does not supply the exact code joining that table to the pseudobulk flag, or establish that guide selection was independently recomputed inside each donor fold. Treat the relationship as documented context, not a verified exact implementation.

The saved flag audit establishes that `keep_for_DE` equals the conjunction of cell, count, effective-guide and test-gene flags. Of 267,666 targeting profiles, 239,206 pass basic cell/count QC but only 224,761 pass `keep_for_DE`: 14,445 additional exclusions. All 11,018 NTC profiles pass the effective-guide/test-gene flags; their 10,303 eligible profiles are selected only by the cell/count flags.

The pilot additionally starts from a previously outcome-selected target panel and requires complete coverage of all four donors and three conditions. Hash ordering avoids a new expression-based ranking, but does not undo upstream success/coverage selection. These data cannot estimate prospective performance across all perturbations. An observed on-target reduction in this panel is also not independent validation of efficacy.

## Defensible next validation

1. Retain explicit run metadata and assert the verified one-run-per-donor/condition invariant. Existing NTC references are already run-matched; do not report an artificial additional correction. Preserve disjoint guide pools and report thin control strata.
2. Compare NTC pseudo-effects under the same normalization, support rules and run matching. Separate raw expression agreement, on-target efficacy and downstream effect agreement. Exclude the directly perturbed readout from downstream summaries.
3. Treat this composition audit as a diagnostic on the reused development panel. Do not interpret improvement as external validation, and do not tune expression/support thresholds on these results before calling the same rows a test set.
4. For a broader prospective benchmark, predeclare targets and basic count/cell eligibility without outcome-significance filters; define readouts externally or on training donors only. Report all eligible perturbations and a separate efficacy-conditioned analysis. Preserve guide identity across train/test design and assess held-out donors and held-out targets as different generalization tasks.
5. Use independent donors or an independently generated experiment for biological validation. The source's arrayed Th1/Th2 bulk-RNA/flow validation tables are potential orthogonal checks, but donor overlap, target selection, experimental provenance and endpoint compatibility must be inspected first. Their availability in a README does not establish their independence or suitability.

Four donor identities remain the biological replication limit of the present pseudobulk experiment. Neither two runs, 192 contrasts, 18,129 readouts nor six overlapping donor-pair DE modalities increases that number.

## Local evidence

- `../baseline_state_data/source_readme.md`: pseudobulk, guide-efficiency, donor-pair and validation-table definitions.
- `../baseline_state_data/targeting_flag_audit.json` and `control_flag_audit.json`: empirical flag relationships.
- `../target_state_data/extract_target_pseudobulk.py` and `manifest.json`: selected panel and coverage rules.
- `metadata.npz` and `manifest.json`: current source-bound run/donor/guide metadata; this audit used only local files and made no new network reads.
