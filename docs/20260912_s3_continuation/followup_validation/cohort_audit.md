# Follow-up cohort and donor grouping audit

This audit reads sample metadata and analysis source only. No expression outcomes or notebook outputs were inspected.

The validation metadata lists 17 unique donors; none of their internal IDs overlap the four screen donors. The eight IL10IL21 Diff087/Diff092 files represent **seven biological donors**, not eight.

The [publication analysis source](https://github.com/emdann/GWT_perturbseq_analysis_2025/blob/aa5c84a973c0e1a090b0072dc5b080bf7fbbed38/src/5_cytokine_regulators/cytokine_followup_regulator.ipynb) explicitly identifies DonorC2 as DonorC in a different differentiation batch (source cell 22); the following cell calculates control references separately by donor and batch. The pinned repository commit is `aa5c84a973c0e1a090b0072dc5b080bf7fbbed38`.

| Batch | Source alias | Canonical alias | Split group |
|---|---|---|---|
| Diff087 | DonorA | DonorA | CE0011482 |
| Diff087 | DonorC | DonorC | CE0011506 |
| Diff087 | DonorF | DonorF | CE0011182 |
| Diff087 | DonorG | DonorG | CE0011120 |
| Diff092 | DonorB | DonorB | CE0010625 |
| Diff092 | DonorC2 | DonorC | CE0011506 |
| Diff092 | DonorD | DonorD | CE0009992 |
| Diff092 | DonorH | DonorH | CE0011304 |

For any cross-validation, hold all samples of a biological donor together, including both DonorC batches. Compute perturbation/control contrasts within donor and differentiation batch, additionally matching the verified culture condition and assay. Aggregate or weight at donor level so the repeated DonorC batch does not count as an eighth independent donor. Report donor-held-out and batch sensitivity separately; two differentiation batches cannot establish broad batch generalization.

These are donor-independent follow-up samples from the same study and experimental program. They are not an independent-study replication cohort, and the selected follow-up target panel is not an unbiased test of all targets. The metadata and directory establish donor grouping, but do not by themselves establish rawcount column target/guide mapping or culture condition; those mappings remain required before scoring.

Machine-readable file groups, source hashes, unresolved items, and the absence of screen-donor overlap are recorded in `donor_grouping.json`. No demographic fields are reproduced.
