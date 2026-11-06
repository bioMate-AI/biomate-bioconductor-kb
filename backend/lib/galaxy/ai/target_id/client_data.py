"""The hospital's own analysis results as an evidence channel.

Each adapter turns one kind of analysis output (a table with one row per gene) into per-gene evidence
scores in [0, 1] that enter target identification next to the public evidence. The formulas are simple,
monotone and written down here so a reviewer can check them; every channel's provenance records the
adapter, the columns used and the row counts. Rows arrive INLINE (the caller reads the file), never as a
server path, so a request cannot make the server read arbitrary files.

3.9-safe, stdlib only.
"""
import math
import re
from typing import Any, Callable, Dict, List, Optional, Tuple

from .channels import Channel
from .types import ChannelResult

MAX_ROWS = 100000
MAX_CHANNELS = 10


def _num(v: Any) -> Optional[float]:
    try:
        x = float(v)
    except (TypeError, ValueError):
        return None
    return None if (math.isnan(x) or math.isinf(x)) else x


def _clip01(x: float) -> float:
    return 0.0 if x < 0 else (1.0 if x > 1 else x)


def _neglog10(p: float) -> float:
    return -math.log10(max(p, 1e-300))


def _truthy(v: Any) -> Optional[float]:
    if isinstance(v, str):
        t = v.strip().lower()
        if t in ("1", "true", "yes", "y", "surface", "membrane", "plasma membrane"):
            return 1.0
        if t in ("0", "false", "no", "n", ""):
            return 0.0
    x = _num(v)
    return None if x is None else _clip01(x)


# Each adapter: (row, cols, params) -> score in [0,1] or None (row unusable).
def _de_up(row, c, p):
    lfc, padj = _num(row.get(c["log2fc"])), _num(row.get(c["padj"]))
    if lfc is None or padj is None or lfc <= 0 or padj > p.get("padj_max", 0.05):
        return 0.0 if (lfc is not None and padj is not None) else None
    return _clip01(lfc / 4.0) * _clip01(_neglog10(padj) / 5.0)


def _survival_adverse(row, c, p):
    hr, pv = _num(row.get(c["hr"])), _num(row.get(c["p"]))
    if hr is None or pv is None:
        return None
    return _clip01(_neglog10(pv) / 5.0) if hr > 1.0 else 0.0


def _recurrence(row, c, p):
    f = _num(row.get(c["freq"]))
    if f is None:
        return None
    if f > 1.0:                       # percentages
        f = f / 100.0
    return _clip01(f / p.get("saturation", 0.2))


def _dependency(row, c, p):
    e = _num(row.get(c["effect"]))
    return None if e is None else _clip01(-e / 1.0)      # gene-effect: -1 is the median essential gene


def _specificity(row, c, p):
    t, n = _num(row.get(c["tumour_fraction"])), _num(row.get(c["normal_fraction"]))
    return None if (t is None or n is None) else _clip01(t - n)


def _surface(row, c, p):
    return _truthy(row.get(c["surface"]))


ADAPTERS: Dict[str, Tuple[Callable, Dict[str, str], str]] = {
    "differential_expression_up": (_de_up, {"gene": "gene", "log2fc": "log2FoldChange", "padj": "padj"},
        "over-expressed in tumour: min(1, log2FC/4) x min(1, -log10(padj)/5); 0 if log2FC<=0 or padj>0.05"),
    "survival_adverse": (_survival_adverse, {"gene": "gene", "hr": "HR", "p": "p"},
        "high expression linked to worse outcome: min(1, -log10(p)/5) if hazard ratio>1 else 0"),
    "mutation_recurrence": (_recurrence, {"gene": "gene", "freq": "frequency"},
        "recurrent alteration: min(1, cohort frequency/0.20); percentages are divided by 100"),
    "dependency": (_dependency, {"gene": "gene", "effect": "effect"},
        "tumour cells need the gene: min(1, -gene_effect) (a gene effect of -1 is the median essential gene)"),
    "cell_type_specificity": (_specificity, {"gene": "gene", "tumour_fraction": "tumour_fraction", "normal_fraction": "normal_fraction"},
        "tumour-cell specificity: max(0, fraction of malignant cells expressing - fraction of normal cells expressing)"),
    "surface_expression": (_surface, {"gene": "gene", "surface": "surface"},
        "present on the cell surface: 1 if true or the supplied 0-1 score"),
}


def _sanitise_name(name: str) -> str:
    n = re.sub(r"[^a-z0-9_]+", "_", str(name or "data").strip().lower()).strip("_")[:40] or "data"
    return n


class ClientTableChannel(Channel):
    """In-memory evidence channel built from the hospital's own analysis table."""

    evidence_kind = "client_data"

    def __init__(self, name: str, scores: Dict[str, float], provenance: Dict[str, Any]):
        self.name = "client_" + _sanitise_name(name)
        self._scores = dict(scores)
        self._prov = dict(provenance)

    def run(self, context: Dict[str, Any]) -> ChannelResult:
        return ChannelResult(channel=self.name, scores=dict(self._scores), provenance=dict(self._prov),
                             evidence_kind="client_data")


def build_client_channels(specs: Optional[List[Dict[str, Any]]], max_rows: int = MAX_ROWS) -> List[ClientTableChannel]:
    """Validate ``specs`` and build one channel per spec. Raises ValueError with an actionable message.

    spec: {"name": str, "kind": one of ADAPTERS, "rows": [ {col: value, ...}, ...],
           "columns": optional {role: column name}, "params": optional adapter parameters,
           "label": optional text, "source_run_id": optional id of the analysis that produced the table}
    """
    chans: List[ClientTableChannel] = []
    if not specs:
        return chans
    if len(specs) > MAX_CHANNELS:
        raise ValueError("at most %d client tables per request" % MAX_CHANNELS)
    seen = set()
    for i, spec in enumerate(specs):
        if not isinstance(spec, dict):
            raise ValueError("client_tables[%d] must be an object" % i)
        kind = spec.get("kind")
        if kind not in ADAPTERS:
            raise ValueError("client_tables[%d]: unknown kind %r; choose one of %s" % (i, kind, sorted(ADAPTERS)))
        rows = spec.get("rows")
        if not isinstance(rows, list) or not rows:
            raise ValueError("client_tables[%d] (%s): rows must be a non-empty list of objects" % (i, kind))
        if len(rows) > max_rows:
            raise ValueError("client_tables[%d]: %d rows exceeds the limit of %d" % (i, len(rows), max_rows))
        fn, default_cols, desc = ADAPTERS[kind]
        cols = dict(default_cols)
        cols.update({k: v for k, v in (spec.get("columns") or {}).items() if k in default_cols})
        present = set(rows[0].keys()) if isinstance(rows[0], dict) else set()
        missing = [role for role, col in cols.items() if col not in present]
        if missing:
            raise ValueError("client_tables[%d] (%s): columns not found for %s. Present: %s. Map them with 'columns'." % (
                i, kind, ", ".join("%s=%r" % (m, cols[m]) for m in missing), sorted(present)))
        params = spec.get("params") or {}
        scores: Dict[str, float] = {}
        skipped = 0
        for row in rows:
            if not isinstance(row, dict):
                skipped += 1
                continue
            gene = str(row.get(cols["gene"]) or "").strip().upper()
            sc = fn(row, cols, params) if gene else None
            if sc is None:
                skipped += 1
                continue
            if sc > scores.get(gene, -1.0):
                scores[gene] = float(sc)
        if not any(v > 0 for v in scores.values()):
            raise ValueError("client_tables[%d] (%s): no gene received a positive score (%d rows, %d unusable). "
                             "Check the column mapping and the values." % (i, kind, len(rows), skipped))
        name = _sanitise_name(spec.get("name") or kind)
        if name in seen:
            raise ValueError("duplicate client table name %r" % name)
        seen.add(name)
        prov = {"source": "client_data", "kind": kind, "adapter": desc, "columns": cols, "n_rows": len(rows),
                "n_scored": len(scores), "n_skipped": skipped, "label": str(spec.get("label") or "")[:200],
                "source_run_id": str(spec.get("source_run_id") or "")[:100]}
        chans.append(ClientTableChannel(name, scores, prov))
    return chans
