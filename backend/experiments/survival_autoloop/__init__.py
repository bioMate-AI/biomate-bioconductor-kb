"""Survival (Cox PH) auto-loop: PH-violation / omitted-confounder -> re-fit.

Mirrors the admet/docking/pbpk auto-loop packages so the generic
autoloop_bridge can drive a Cox survival QC gate with the SAME
transport, SSE, and remediation-suggestion machinery.

The realized self-correction for the clinical survival demo:
  naive  Cox  (Surv ~ biomarker)             -> QC gate reads survival_qc.json
  gate   detects an omitted prognostic covariate (confounding) and/or a
         proportional-hazards violation (Schoenfeld global p < 0.05)
  re-fit Cox  (Surv ~ biomarker + covariates [+ strata])   <- tuner remediation
"""
