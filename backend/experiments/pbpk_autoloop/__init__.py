"""PBPK auto-loop — wraps the existing pbpk_ind_submission / pbpk_screening
QC profiles in qc_trace_monitor.py with a parameter-tuning remediation layer.

Built 2026-05-22 to close the gap identified in
docs/20260521_DEPLOYMENT_MISTAKES_LESSONS.md and the 2026-05-22 audit:
PBPK math (ODEs, mass balance, lung-blood coupling) is correct per the
2026-04-18 scientific audit, but no autoloop fired on PBPK gate failures.
"""
