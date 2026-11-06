# Target-specificity development gate

Frozen before computing the new comparisons: use prior donor-held-out predictions and guide-only attenuation coefficients; no model refitting or tuning. Reuse the development data explicitly.

Apply a common readout mask excluding every perturbed target symbol (16 genes from the 132-gene panel). This prevents a mismatched target's direct effect from contaminating the null comparison. Recompute every arm on exactly the same mask; do not compare its absolute MSE to earlier masks.

Compare no-change, unattenuated condition/target means and ridge variants, and the same training-guide attenuation applied to each. Assess whether attenuated target-specific estimates improve over attenuated condition mean. For each true target, enumerate all 15 alternative target identities within the same held-out donor and condition. Report both expected error of a mismatched target prediction and error of the mean of alternative predictions. No random seed or favorable mismatch selected.

Report equal-donor MSE, donor/condition summaries and per-target descriptive changes. No p-values or confidence intervals from dependent target rows; no declaration of new validation or production readiness. This can reject adding model complexity, but cannot establish independent generalization.
