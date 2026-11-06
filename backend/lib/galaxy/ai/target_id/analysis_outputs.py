"""Turn a completed analysis run's output file into a hospital-data evidence table, automatically.

A run output is a table with one row per gene (what the platform's differential-expression, survival, recurrence and
dependency workflows write). The file format is recognised from its header, the gene column is found, and a
``client_tables`` entry is built for ``client_data.build_client_channels``. Files are read only from a configured
folder (TARGET_ID_RUN_OUTPUT_ROOT), never from an arbitrary path. 3.9-safe, stdlib only.
"""
import csv
import gzip
import io
import os
import re
from typing import Any, Dict, List, Optional, Tuple

from .client_data import MAX_ROWS
from .table_policy import confine, run_output_root

_GENE_COLUMNS = ["gene_name", "gene_symbol", "symbol", "hgnc_symbol", "external_gene_name", "Gene.symbol", "gene", "Gene", "GENE", "SYMBOL", "ID", "gene_id"]
_BLANK_FIRST = ("", "X", "Unnamed: 0", "row.names", "rownames")

# (label, adapter kind, {adapter role: candidate column names}) in the order they are tried.
SIGNATURES: List[Tuple[str, str, Dict[str, List[str]]]] = [
    ("DESeq2 results", "differential_expression_up", {"log2fc": ["log2FoldChange"], "padj": ["padj"]}),
    ("edgeR results", "differential_expression_up", {"log2fc": ["logFC"], "padj": ["FDR"]}),
    ("limma results", "differential_expression_up", {"log2fc": ["logFC"], "padj": ["adj.P.Val", "adj.P.Value"]}),
    ("Cox regression", "survival_adverse", {"hr": ["HR", "hazard_ratio", "exp(coef)", "HazardRatio"], "p": ["p", "p.value", "Pr(>|z|)", "pvalue", "P"]}),
    ("mutation recurrence", "mutation_recurrence", {"freq": ["frequency", "freq", "mutation_frequency", "alteration_frequency"]}),
    ("dependency screen", "dependency", {"effect": ["effect", "gene_effect", "chronos", "CERES", "ceres"]}),
    ("cell-type specificity", "cell_type_specificity", {"tumour_fraction": ["tumour_fraction", "tumor_fraction"], "normal_fraction": ["normal_fraction"]}),
    ("surface expression", "surface_expression", {"surface": ["surface", "surface_expression", "is_surface"]}),
]


def _open_text(path: str):
    if path.endswith(".gz"):
        return io.TextIOWrapper(gzip.open(path, "rb"), newline="")
    return open(path, "r", newline="")


def _read_table(path: str, max_rows: int) -> Tuple[List[str], List[Dict[str, str]]]:
    with _open_text(path) as fh:
        head = fh.readline()
        fh.seek(0) if not path.endswith(".gz") else None
    delim = "\t" if head.count("\t") >= head.count(",") and "\t" in head else ","
    rows: List[Dict[str, str]] = []
    with _open_text(path) as fh:
        reader = csv.DictReader(fh, delimiter=delim)
        header = list(reader.fieldnames or [])
        for i, row in enumerate(reader):
            if i >= max_rows:
                raise ValueError("%s has more than %d rows" % (os.path.basename(path), max_rows))
            rows.append(row)
    return header, rows


def _find_gene_column(header: List[str], rows: List[Dict[str, str]]) -> str:
    for c in _GENE_COLUMNS:
        if c in header:
            col = c
            break
    else:
        col = header[0] if header and header[0] in _BLANK_FIRST else None
    if col is None:
        raise ValueError("no gene column found (looked for %s); present: %s" % (", ".join(_GENE_COLUMNS[:6]) + ", ...", header))
    sample = [str(r.get(col) or "") for r in rows[:200]]
    if sample and sum(bool(re.match(r"^ENS[A-Z]*G\d+", s)) for s in sample) > len(sample) / 2:
        raise ValueError("the gene column %r holds Ensembl ids; add a gene-symbol column (target identification matches symbols)" % col)
    return col


def detect(header: List[str]) -> Optional[Tuple[str, str, Dict[str, str]]]:
    """Return (format label, adapter kind, column mapping) for the first matching signature, else None."""
    for label, kind, roles in SIGNATURES:
        cols = {}
        for role, candidates in roles.items():
            hit = next((c for c in candidates if c in header), None)
            if hit is None:
                break
            cols[role] = hit
        else:
            return label, kind, cols
    return None


def spec_from_run_output(run_output: Dict[str, Any], root: Optional[str] = None, max_rows: int = MAX_ROWS) -> Dict[str, Any]:
    """Build one ``client_tables`` entry from {path, name?, label?, source_run_id?, kind?, columns?}. Raises ValueError."""
    root = root or run_output_root()
    if not root:
        raise ValueError("run outputs are disabled (no TARGET_ID_RUN_OUTPUT_ROOT configured); send the rows inline as client_tables")
    rel = str(run_output.get("path") or "")
    if not rel:
        raise ValueError("run_outputs entry needs a path")
    try:
        path = confine(rel, root)
    except ValueError:
        raise ValueError("run output %r is outside the allowed folder" % rel)
    if not os.path.isfile(path):
        raise ValueError("run output not found: %s" % os.path.basename(rel))
    header, rows = _read_table(path, max_rows)
    if not rows:
        raise ValueError("run output %s has no rows" % os.path.basename(rel))
    kind = run_output.get("kind")
    cols: Dict[str, str]
    if kind and kind != "auto":
        label, cols = "chosen by the caller (%s)" % kind, dict(run_output.get("columns") or {})
        found = detect(header)
        if found and found[1] == kind and not cols:
            cols = found[2]
    else:
        found = detect(header)
        if not found:
            raise ValueError("format not recognised from the header %s. Supported: %s. Pass kind and columns to map it by hand." % (
                header[:12], "; ".join("%s (%s)" % (l, "+".join(sum(r.values(), [])[:3] if False else [c[0] for c in r.values()])) for l, _, r in SIGNATURES)))
        label, kind, cols = found
        cols.update(run_output.get("columns") or {})
    gene_col = (run_output.get("columns") or {}).get("gene") or _find_gene_column(header, rows)
    cols["gene"] = gene_col
    return {"name": run_output.get("name") or os.path.splitext(os.path.basename(rel))[0], "kind": kind, "rows": rows, "columns": cols,
            "label": run_output.get("label") or label, "source_run_id": run_output.get("source_run_id") or "",
            "params": run_output.get("params") or {}}


def specs_from_run_outputs(run_outputs: Optional[List[Dict[str, Any]]], root: Optional[str] = None) -> List[Dict[str, Any]]:
    out = []
    for i, ro in enumerate(run_outputs or []):
        try:
            out.append(spec_from_run_output(ro, root=root))
        except ValueError as e:
            raise ValueError("run_outputs[%d]: %s" % (i, e))
    return out
