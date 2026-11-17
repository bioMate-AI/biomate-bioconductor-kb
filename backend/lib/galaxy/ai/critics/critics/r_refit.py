"""
Thin Python orchestrator for the reusable survival R stats script.

Separates the "call R and parse JSON" plumbing from the critic logic. The critic
decides WHETHER to recompute (advisory default: it does not; it uses the contract's
emitted numbers); this module is HOW, when it chooses to.

Per the repo's execution policy, heavy R belongs on BioMate's Batch workers / the
run itself, not installed locally. This orchestrator therefore:
  * invokes a local ``Rscript`` only if one is already on PATH (dev convenience),
  * never installs anything,
  * returns None on any failure so the critic falls back to the contract values.
A production deployment would instead dispatch ``survival_refit.R`` as a short
BioMate ``run_code`` / Batch step; the parsing contract (the printed JSON) is identical.
"""
from __future__ import annotations

import json
import logging
import os
import shutil
import subprocess
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)

_R_SCRIPT = os.path.join(os.path.dirname(os.path.dirname(__file__)), "r", "survival_refit.R")


def run_survival_refit(
    csv_path: str,
    primary: str,
    confounders: Optional[List[str]] = None,
    *,
    timeout_s: int = 120,
) -> Optional[Dict[str, Any]]:
    """Run ``survival_refit.R`` and return its parsed survival_qc JSON, or None.

    Returns None (never raises) when Rscript is unavailable, the data path is
    missing, the script errors, or the output does not parse — the critic then uses
    the contract's already-emitted naive/adjusted HRs.
    """
    rscript = shutil.which("Rscript")
    if not rscript:
        log.info("[critics] Rscript not on PATH — skipping local re-fit")
        return None
    if not (csv_path and os.path.exists(csv_path)):
        log.info("[critics] clinical CSV not locally available (%s) — skipping re-fit", csv_path)
        return None
    if not os.path.exists(_R_SCRIPT):
        log.warning("[critics] survival_refit.R missing at %s", _R_SCRIPT)
        return None

    cmd = [rscript, _R_SCRIPT, csv_path, primary, ",".join(confounders or [])]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout_s)
    except Exception as exc:
        log.warning("[critics] survival_refit.R invocation failed: %s", exc)
        return None
    if proc.returncode != 0:
        log.warning("[critics] survival_refit.R exit %d: %s", proc.returncode, proc.stderr.strip()[:400])
        return None
    try:
        return json.loads(proc.stdout.strip())
    except Exception as exc:
        log.warning("[critics] survival_refit.R output parse failed: %s", exc)
        return None
