"""
scorers/
--------
Output parsing and scientific validity scoring functions for BioMate
drug development benchmarks (B1–B5).

Modules:
    admet_scorer   — parse_admet_output, score_admet_case, score_admet_batch
    docking_scorer — parse_docking_output, spearman_rho, score_docking_system,
                     score_docking_batch
    pbpk_scorer    — parse_pbpk_output, within_2fold, score_pbpk_case, score_pbpk_batch
    boin_scorer    — parse_boin_output, score_boin_case, score_boin_batch
"""

from .admet_scorer import (
    parse_admet_output,
    classify_herg,
    score_admet_case,
    score_admet_batch,
)
from .docking_scorer import (
    parse_docking_output,
    spearman_rho,
    score_docking_system,
    score_docking_batch,
)
from .pbpk_scorer import (
    parse_pbpk_output,
    within_2fold,
    score_pbpk_case,
    score_pbpk_batch,
)
from .boin_scorer import (
    parse_boin_output,
    score_boin_case,
    score_boin_batch,
)

__all__ = [
    # ADMET
    "parse_admet_output",
    "classify_herg",
    "score_admet_case",
    "score_admet_batch",
    # Docking
    "parse_docking_output",
    "spearman_rho",
    "score_docking_system",
    "score_docking_batch",
    # PBPK
    "parse_pbpk_output",
    "within_2fold",
    "score_pbpk_case",
    "score_pbpk_batch",
    # BOIN
    "parse_boin_output",
    "score_boin_case",
    "score_boin_batch",
]
