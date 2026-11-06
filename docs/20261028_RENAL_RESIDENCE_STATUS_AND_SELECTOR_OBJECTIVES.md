# Kidney retention and tumour residence: what exists, what was tested, what the selector optimises (2026-10-28)

Correction of an earlier statement: kidney retention WAS implemented and tested (`research/guangzhou_all_atom/renal/`: mechanistic grey-box `renal_mechmodel.py`, construct-level `renal_design.py`, Gate A harness `renal_surrogate.py`, KB `radiopharm_kb.py`). A first check looked only at `score.py` and `reward.py` and missed it.

## Test outcome (already recorded; see `docs/20261022_RENAL_PREDICTOR_MANUSCRIPT.md`)
Cross-target generalisation NOT supported; the earlier rho = 0.27 was a charge-feature artifact; corrected construct-level GBM rho = -0.26, net charge ~0, grey-box +0.14 (p = 0.40); four pre-registered improvement analyses null; ~49 charge-resolvable constructs / 7 classes.

## What the grey-box actually learned (measured 2026-10-28)
89 observations, 52 constructs, 9 target classes. Fitted Hill constants sit at their lower bound (0.20); both charge weights are NEGATIVE (-0.21, -0.25); raw Spearman(charge, kidney) over all observations = -0.06; the training net-charge range is -10..+4 (predictions at +6/+10 are extrapolation). Its real signal is in construct levers (residualising radiometal +1.22, albumin binder +0.70, cleavable motif +1.07, small-molecule flag -1.31), not in anything a peptide design controls.

## Selector objectives
`mo_select_qnehvi.py` optimises binding, permeability and synthesizability (selectivity explicitly omitted). Permeability is not required for a radioligand. Neither kidney retention nor tumour residence was in it.
Added (opt-in, tested): `--objectives` (named columns), exact hypervolume in any dimension, `renal` objective = -predicted log1p kidney %ID/g via `renal/renal_objective.py`, REFUSED unless `--allow-unvalidated` is passed, labelled unvalidated in the report, with a flatness check (`informative()`, sd >= 0.05 log1p units).
Result on our actual candidate sets: predicted kidney retention is constant (round-4 n=13: 2.116 for all, sd 0.0000; scaffold hops n=3: constant; v2 panel n=10: sd 0.0074) because the pharmacophore fixes the charge-carrying residues (net charge +1 for all round-4 and scaffold-hop candidates). Kidney retention therefore cannot rank candidates within these series; it is a CONSTRUCT-level variable (linker, chelator, albumin binder, valency), which is what `renal_design.py` addresses (in-silico shortlist, hypothesis-generating, unvalidated).

## Tumour residence
No model exists (no kinetics / koff / retention term anywhere in the code). Not added: a valid estimate needs a kinetic or experimental assay (e.g. SPR off-rate, tumour-uptake time course), not a proxy.

## Implication for external wording
"Co-optimise affinity, selectivity, residence and developability" is not supported as AVAILABLE. Supportable: Pareto selection on binding, permeability and synthesizability; kidney retention addressed at the construct level by an in-silico shortlist that is unvalidated (Gate A not passed); selectivity pending; tumour residence planned, no model.
