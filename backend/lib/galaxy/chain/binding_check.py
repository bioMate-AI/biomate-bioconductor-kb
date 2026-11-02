"""Pre-launch check that chain connections bind to parameters the downstream
workflow actually declares.

A connection's ``to_input`` is written into the downstream run's parameters by
``workflow_chain._apply_connection_handoffs``. If the downstream workflow never
reads ``params.<to_input>`` the value is silently ignored, so the chain would
launch a Batch job that cannot consume the upstream artifact. This module lets
the executor fail before launch instead.

stdlib only; Python 3.9 safe. Path resolution mirrors
``nextflow_executor._resolve_nextflow_path`` / ``_candidate_bases``.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Set, Tuple

_PARAM_RE = re.compile(r"params\.([A-Za-z_]\w*)")
_MAX_DECLARED = 30


def _default_roots() -> List[Path]:
    roots = []  # type: List[Path]
    for part in os.environ.get("NEXTFLOW_SEARCH_ROOTS", "").split(":"):
        part = part.strip()
        if part:
            roots.append(Path(part))
    backend = Path(__file__).resolve().parents[3]
    nfc = backend / "biomni_workflows" / "nextflow_nfcore"
    roots.extend([
        backend,
        nfc,
        nfc / "subworkflows",
        nfc / "workflows",
        backend / "nf-core-workflows",
        backend / "nf-core-workflows" / "modules" / "biomate-ai-tools",
        backend / "biomni_workflows" / "nfcore",
        backend / "nf-core-modules",
        backend / "nf-core-modules" / "subworkflows" / "nf-core",
    ])
    seen = set()  # type: Set[str]
    out = []  # type: List[Path]
    for r in roots:
        if str(r) not in seen:
            seen.add(str(r))
            out.append(r)
    return out


def _candidates(raw: str) -> List[Path]:
    cands = [Path(raw)]
    if raw.startswith("nfcore/subworkflows/"):
        name = raw.split("nfcore/subworkflows/", 1)[1].strip("/")
        cands += [Path("subworkflows") / name / "main.nf", Path(name) / "main.nf"]
    elif raw.startswith("nfcore/"):
        rest = raw.split("nfcore/", 1)[1].strip("/")
        cands += [Path(rest), Path(rest) / "main.nf"]
    elif raw.startswith("biomni_nf/"):
        rest = raw.split("biomni_nf/", 1)[1].strip("/")
        cands += [Path("subworkflows") / rest, Path("subworkflows") / rest / "main.nf"]
    elif raw.startswith("nextflow_nfcore/"):
        rest = raw.split("nextflow_nfcore/", 1)[1].strip("/")
        cands += [Path(rest), Path(rest) / "main.nf",
                  Path("subworkflows") / rest, Path("subworkflows") / rest / "main.nf"]
    expanded = []  # type: List[Path]
    for c in cands:
        expanded.append(c)
        if c.suffix != ".nf":
            expanded += [c.with_suffix(".nf"), c / "main.nf"]
    return expanded


def _resolve(nextflow_path: str, roots: Optional[Iterable[Path]]) -> Optional[Path]:
    p = Path(nextflow_path)
    if p.is_absolute() and p.is_file():
        return p
    for root in (list(roots) if roots is not None else _default_roots()):
        for c in _candidates(nextflow_path):
            t = (Path(root) / c)
            if t.is_file() and t.suffix == ".nf":
                return t.resolve()
    if p.is_file() and p.suffix == ".nf":
        return p.resolve()
    return None


def _schema_keys(schema_path: Path) -> Set[str]:
    try:
        data = json.loads(schema_path.read_text(errors="replace"))
    except (OSError, ValueError):
        return set()
    keys = set()  # type: Set[str]
    if not isinstance(data, dict):
        return keys
    props = data.get("properties")
    if isinstance(props, dict):
        keys.update(props)
    for section in ("definitions", "$defs"):
        defs = data.get(section)
        if isinstance(defs, dict):
            for d in defs.values():
                if isinstance(d, dict) and isinstance(d.get("properties"), dict):
                    keys.update(d["properties"])
    return keys


def declared_params(nextflow_path: str, roots: Optional[Iterable[Path]] = None) -> Optional[Set[str]]:
    """Params a workflow declares (``params.X`` in main.nf + nextflow_schema.json).

    Returns None when the workflow file cannot be found/read (undeterminable);
    never an empty set for that case.
    """
    if not nextflow_path:
        return None
    nf = _resolve(str(nextflow_path), roots)
    if nf is None:
        return None
    try:
        text = nf.read_text(errors="replace")
    except OSError:
        return None
    found = set(_PARAM_RE.findall(text))
    schema = nf.parent / "nextflow_schema.json"
    if schema.is_file():
        found |= _schema_keys(schema)
    return found


def check_connections(
    steps: List[Dict[str, Any]],
    connections: List[Dict[str, Any]],
    roots: Optional[Iterable[Path]] = None,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """Return ``(problems, undeterminable)`` for connections (1-based step numbers).

    A problem: the connection's ``to_input`` is not declared by the downstream
    workflow. Undeterminable: downstream workflow file not found (not a problem).
    """
    problems = []  # type: List[Dict[str, Any]]
    undeterminable = []  # type: List[Dict[str, Any]]
    cache = {}  # type: Dict[str, Optional[Set[str]]]
    for conn in connections or []:
        to_input = str(conn.get("to_input") or "")
        if not to_input:
            continue
        try:
            to_step = int(conn.get("to_step", -1))
            from_step = int(conn.get("from_step", -1))
        except (TypeError, ValueError):
            continue
        if to_step < 1 or to_step > len(steps):
            continue
        step = steps[to_step - 1]
        nf_path = step.get("nextflow_path") or ""
        if nf_path not in cache:
            cache[nf_path] = declared_params(nf_path, roots)
        declared = cache[nf_path]
        workflow = step.get("workflow_name") or nf_path
        base = {"from_step": from_step, "to_step": to_step, "to_input": to_input, "workflow": workflow}
        if declared is None:
            undeterminable.append(dict(base, nextflow_path=nf_path))
            continue
        if to_input in declared:
            continue
        shown = sorted(declared)[:_MAX_DECLARED]
        problems.append(dict(
            base,
            declared=shown,
            message=(
                "Connection step %s -> step %s binds to '%s', but workflow '%s' does not declare "
                "that parameter (declared: %s). Refusing to launch." % (
                    from_step, to_step, to_input, workflow, ", ".join(shown) or "none")
            ),
        ))
    return problems, undeterminable
