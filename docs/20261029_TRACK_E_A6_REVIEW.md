# Track E proposed A6 independent review — 2026-10-29

Status: **review findings, not a frozen amendment or hybrid result**. Reviewed the remotely generated `/tmp/codex-method-qa-v3/A6_PROPOSED.json` and its producer `research/guangzhou_all_atom/cyclic_llm/allatom_paper/track_e/summarize_eval.py`. The proposed artifact was not modified. This review read existing values and source code; it ran no scientific computations or tests locally.

## Registered controls must remain unchanged

The [Track E preregistration, line 22](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:22) explicitly requires each method's paired shuffled-minus-random seed t-interval to contain zero. [A4, line 75](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:75) preserves the controls. The broader design wording “no method should beat random search” does not replace this operational criterion.

The stored copy-seed contrast is mean −0.01854717158018935, 95% t interval [−0.023483581454589942, −0.013610761705788756], n = 5. Therefore `shuffled_pass=false` is correct. Its negative direction may inform interpretation, but changing the rule to “no positive improvement” after reading this result would be post hoc. Report the failure alongside any verdict. The [helper, line 115](/Users/kky/biomate-review/research/guangzhou_all_atom/cyclic_llm/allatom_paper/track_e/summarize_eval.py:115) implements the registered interval rule.

Copy-seed's planted final top-10 mean is 0.91875 for all five seeds, with 300 calls and `proposal_cap` stops. This meets the reported planted threshold, but does not establish the separate registered copy-seed plateau criterion. That requires checking the seed-set size, unique queried seeds, and trajectory against the best attainable seed-set top-10 score. Do not infer plateau verification from a threshold pass or call count alone. The other stored shuffled contrasts contain zero, and all stored planted thresholds pass.

## Margin and baseline reference

[A4c, lines 86–87](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:86) retains self-stops in the primary analysis and derives the margin from untruncated baseline curves. [A5, line 95](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:95) freezes `f = 0.10` and permits evaluation-family G to be recorded in A6 before any hybrid run. The helper follows `margin = 0.10 × (best untruncated baseline mean − random_lib mean)`.

| Family | Best untruncated baseline | Stored G | Stored margin, SD-AUC |
|---|---|---:|---:|
| F1 | selfies_ga | 1.299910109422422 | 0.1299910109422422 |
| F2 | gp_bo | 2.8229075631232785 | 0.28229075631232786 |

All evaluation methods have ten untruncated runs in the supplied report. F1 edit_ga has five `optimizer_stalled` runs, with 649, 686, 740, 695 and 719 calls; retaining these is correct. Neither the margin nor baseline optimization success validates the held-out verifier.

## Missing conditions before A6 can be treated as frozen and complete

1. **Complete the registered stop-reporting table.** [A4c, line 85](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:85) requires family × method × phase (tuning, evaluation, controls) runs, truncation counts and mean budget fraction at truncation, self-stop counts and mean budget fraction at self-stop. The helper includes evaluation arrays and planted-control arrays, but omits tuning and shuffled-control stop/call summaries and the complete required table. Preserve the original proposal; issue any completed report as a separately identified revision.
2. **Resolve or explicitly retain incomplete control evidence.** Preserve copy-seed shuffled failure and distinguish its still-unaudited plateau from the planted threshold pass. Do not declare that all controls passed. A failed registered control need not prevent recording an honest A6 amendment; it prevents presenting the existing control suite as successful.
3. **Separate descriptive intervals from primary inference.** [Preregistration, line 25](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:25) requires the wider percentile-bootstrap/t interval for per-family primary inference. The helper's baseline contrasts use t intervals only. These may remain explicitly descriptive, and its power/MDE values remain baseline-variance approximations; neither constitutes a formal hybrid gate or measured hybrid variance. Shuffled controls separately and correctly use their explicitly registered t criterion.
4. **Record provenance and commit the reviewed amendment before hybrid results.** [A5, lines 93–96](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:93) freezes configurations, margin fraction, evaluation seeds and budget. Preserve the supplied source hashes and frozen tuned-configuration hash; record the accepted A6 revision and chronology. A file labelled `PROPOSED_A6_REVIEW_REQUIRED` alone is not a committed preregistration. A5 specifies committing evaluation G before any hybrid run; the helper's weaker “before any hybrid result” reminder must not relax that requirement. If that chronology cannot be demonstrated, disclose it rather than claiming prospective freezing.
5. **Retain the gate limitations.** The proposal records F1 held-out floor failure and a VOID replacement, so it does not permit GO. Held-out final scores are not held-out AUC trajectories. No hybrid performance or biological effectiveness claim follows from this baseline/control report.

## Cost interpretation

The helper correctly marks remaining authorized budget as unverified: historical $14 stage-0/1, $4 Track E, $2 U1 and $3.5 M3 reserve fields are caps/reserve labels, not measured spend or additive remaining allowance. Launch-only records lack actual billed duration and Spot prices; summed per-run wall time is not an instance bill when work runs in parallel. [A4 cost record, line 77](/Users/kky/biomate-review/docs/20261031_ALLATOM_TRACK_E_PREREG.md:77) itself labels the historical figure an estimate without a cost log. Do not describe these fields as verified budget headroom or use them alone to justify further expenditure.

No criterion, result artifact, worker or budget authorization was changed by this review.
