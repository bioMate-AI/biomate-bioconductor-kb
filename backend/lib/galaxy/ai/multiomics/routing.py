"""Feature-flagged chat routing for flexible multi-omics integration.

Mirrors `ml_training/routing.py`: a multi-omics INTEGRATION request ("integrate my RNA
and methylation and proteomics") short-circuits to an integration card — which method to
use, why, the per-modality normalization plan, and which workflow to run — instead of the
normal single-workflow search. The method is chosen from the data, not fixed to MOFA2.

Standalone (no ai_assistant import) so it's import-safe and unit-testable. Inert until
`MULTIOMICS_ROUTING=1`, and even then it can only ADD a route, never break one (returns
None for non-integration intents).
"""
from __future__ import annotations

import os
import re
from typing import Any, Dict, List, Optional

from .method_selector import Modality, recommend
from .integration_planner import METHOD_WORKFLOW

# Integration-intent verbs (the request must express *combining* modalities).
_INTEGRATE = re.compile(
    r"\b(integrat\w+|combin\w+|joint\w*|jointly|fus\w+|co-?analy\w+|"
    r"multi-?omics?|multiomics|together)\b|整合|融合|联合分析|联合建模|多组学|跨组学",
    re.I,
)

# Modality keyword → (canonical data_type the selector understands, display label).
# Order matters: more specific (single-cell) patterns first.
# Each pattern carries both English and 中文 aliases (hospital users write Chinese).
# Order matters: more specific (spatial / single-cell) patterns first.
_MODALITY_KEYWORDS: List[tuple] = [
    (re.compile(r"spatial\s*(transcriptom\w+|omics|express\w*)|\bvisium\b|\bmerfish\b|\bslide-?seq\b|\bxenium\b|空间转录组|空间组学|空间组", re.I), "spatial", "spatial"),
    (re.compile(r"\bsc-?atac|single-?cell\s+atac|单细胞\s*atac", re.I), "scatac", "scATAC"),
    (re.compile(r"\bsc-?rna|single-?cell\s+(rna|expression|transcriptom\w+)|单细胞", re.I), "scrna", "scRNA"),
    (re.compile(r"\brna(-?seq)?\b|\btranscriptom\w+|\bmrna\b|gene\s+expression|\bexpression\b|转录组|基因表达|表达矩阵|表达谱", re.I), "rna", "RNA"),
    (re.compile(r"\b(methylat\w+|450k|epic\b|bisulfite)\b|甲基化", re.I), "methylation", "methylation"),
    (re.compile(r"\bmi-?rna\b|微小rna|微rna", re.I), "mirna", "miRNA"),
    (re.compile(r"\b(proteom\w+|rppa|\bprotein\b)\b|蛋白质组|蛋白组|蛋白质谱|蛋白表达", re.I), "proteomics", "proteomics"),
    (re.compile(r"\b(mutation\w*|somatic|\bsnv\b|variant\s+matrix)\b|突变|体细胞变异", re.I), "mutation", "mutation"),
    (re.compile(r"\b(cnv|copy-?number)\b|拷贝数", re.I), "cnv", "CNV"),
    (re.compile(r"\b(metabolom\w+|metabolite\w*)\b|代谢组|代谢物|代谢谱", re.I), "metabolomics", "metabolomics"),
    (re.compile(r"\b(drug-?response|drug\s+sensitivity|\bic50\b)\b|药物敏感|药敏", re.I), "drug_response", "drug-response"),
    (re.compile(r"\batac(-?seq)?\b", re.I), "scatac", "ATAC"),  # bulk ATAC → TF-IDF normalization path
]

# Goal hints → selector `goal` argument (English + 中文).
_GOAL_HINTS: List[tuple] = [
    (re.compile(r"\b(cluster\w*|subtyp\w+|stratif\w+|patient\s+group\w*|prognos\w+)\b|分型|亚型|分层|患者分组|预后分组", re.I), "clustering"),
    (re.compile(r"\b(factor\w*|latent|shared\s+component\w*)\b|潜在因子|共享成分|隐变量", re.I), "factors"),
    (re.compile(r"\b(feature\s+selection|select\w*\s+feature|driver\s+gene\w*|biomarker\w*)\b|特征选择|驱动基因|生物标志", re.I), "feature_selection"),
]


def _extract_modalities(text: str) -> List[Modality]:
    """Pull the distinct omics modalities named in the request.

    Patterns are tried most-specific first, and each match's span is blanked out
    of the working text so a later generic pattern can't re-claim it — e.g.
    "spatial transcriptomics" resolves to spatial only, not spatial + RNA.
    """
    seen: Dict[str, Modality] = {}
    work = text
    for pat, dtype, label in _MODALITY_KEYWORDS:
        if dtype in seen:
            continue
        m = pat.search(work)
        if m:
            seen[dtype] = Modality(name=label, data_type=dtype)
            work = work[:m.start()] + (" " * (m.end() - m.start())) + work[m.end():]
    return list(seen.values())


def _infer_goal(text: str) -> Optional[str]:
    for pat, goal in _GOAL_HINTS:
        if pat.search(text):
            return goal
    return None


def detect_multiomics_intent(text: str) -> bool:
    """True iff the request expresses integrating ≥2 distinct omics modalities."""
    return bool(_INTEGRATE.search(text)) and len(_extract_modalities(text)) >= 2


def _build_card(rec: Dict[str, Any], mods: List[Modality]) -> Dict[str, Any]:
    method = rec.get("recommended_method")
    norm = rec.get("normalization_plan") or {}
    mod_names = ", ".join(m.name for m in mods)
    runnable = method in METHOD_WORKFLOW  # StabMap etc. are not in the map yet
    norm_txt = "; ".join(f"{k}→{v}" for k, v in norm.items())
    rationale = (rec.get("rationale") or "").strip()
    if norm_txt:
        rationale += f"  Per-modality normalization: {norm_txt}."
    if not runnable:
        alts = [a for a in (rec.get("alternatives") or []) if a in METHOD_WORKFLOW]
        rationale += (f"  Note: {method} best fits this data shape but is not yet a packaged "
                      f"workflow; nearest runnable alternative(s): {alts or 'none'}.")
    factor_method = method in {"MOFA2", "MCIA", "JIVE", "MFA"}
    # Execution is a 2-step pipeline: per-modality normalization THEN integration.
    # Surface both stages so the card isn't misleading (MOFA2 etc. don't normalize internally).
    pipeline_stages = ["normalize"] + ([method] if runnable else [])
    return {
        "name": f"Multi-omics integration — {method}",
        "domain": "multi-omics",
        "description": (f"Normalize each modality, then integrate {mod_names} using {method}."
                        if runnable else f"Integrate {mod_names} using {method}."),
        "scientific_rationale": rationale,
        "nextflow_path": METHOD_WORKFLOW.get(method),
        "pipeline": pipeline_stages,
        "method": method,
        "runnable": runnable,
        "alternatives": rec.get("alternatives"),
        "normalization_plan": norm,
        "overlap_type": rec.get("overlap_type"),
        "warnings": rec.get("warnings") or [],
        "required_params": [{
            "name": "omics",
            "type": "file[]",
            "required": True,
            "description": f"One features×samples CSV per modality ({mod_names}).",
        }],
        "optional_params": [{
            "name": "n_factors" if factor_method else "n_clusters",
            "type": "int",
            "required": False,
            "description": "latent factors" if factor_method else "cluster count",
        }],
        "steps": {},  # lazily fetched
    }


def route_multiomics_result(
    text: str,
    *,
    enabled: Optional[bool] = None,
) -> Optional[Dict[str, Any]]:
    """Feature-flagged router entry for `ai_assistant.generate_workflow_unified`.

    Returns a generate_workflow_unified-shaped result dict when the flag is on AND the
    text is a multi-omics integration request naming ≥2 modalities; otherwise None (the
    caller falls through to normal workflow search). `enabled=None` reads the
    MULTIOMICS_ROUTING env flag (default OFF), so wiring this in is inert until enabled.
    """
    if enabled is None:
        enabled = os.environ.get("MULTIOMICS_ROUTING") == "1"
    if not enabled:
        return None
    mods = _extract_modalities(text)
    if not (_INTEGRATE.search(text) and len(mods) >= 2):
        return None
    rec = recommend(mods, goal=_infer_goal(text))
    ga = _build_card(rec, mods)
    return {
        "success": True,
        "workflow_ga": ga,
        "source": "multiomics",
        "confidence": 1.0,
        "message": ga["scientific_rationale"],
        "datasets_assigned": False,
    }
