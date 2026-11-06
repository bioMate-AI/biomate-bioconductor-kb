"""Required parameters of the nf-core pipeline that actually RUNS for a catalog row.

nf-core catalog rows resolve, for display, to a biomni_workflows/nfcore/<name> stub whose
`params.x = null` lines make every null-default param "required" (chipseq: input, genome,
macs_gsize). The executor runs the real downloaded pipeline
(nextflow_executor._resolve_nextflow_path), and Nextflow validates params against THAT
pipeline's nextflow_schema.json (chipseq: fasta, input). The launch gate enforces
required_params, so stub-derived required-ness blocked runs the pipeline accepts and let
through runs it rejects. Both param builders (ai_assistant._get_workflow_params and the
/api/workflows/search parser) take required-ness from here when a schema exists.
"""
import json
import re
from pathlib import Path
from typing import Any, Dict, Optional, Set, Tuple

# Set by the executor on every run; never asked of the user.
EXECUTOR_SET_PARAMS = frozenset({"outdir"})


_UNSET = object()


def _literal(raw: str) -> Any:
    """A Groovy literal from a config line (quoted string, number, true/false/null), else _UNSET."""
    # Quoted first: strings routinely hold URLs, so `//` is a comment only outside quotes.
    m = re.match(r"""\s*(['"])(.*?)\1\s*(//.*)?$""", raw)
    if m:
        return m.group(2)
    raw = raw.split("//", 1)[0].strip()
    if raw in ("true", "false"):
        return raw == "true"
    if raw == "null":
        return None
    if re.fullmatch(r"-?\d+", raw):
        return int(raw)
    if re.fullmatch(r"-?\d+\.\d*", raw):
        return float(raw)
    return _UNSET


def config_param_defaults(config_text: str) -> Dict[str, Any]:
    """{name: default} for the top-level `params { ... }` block of a nextflow.config.

    Values that are not plain literals (expressions, lists, closures) are kept with
    the _UNSET marker so the name still counts as declared.
    """
    out: Dict[str, Any] = {}
    m = re.search(r"(?m)^params\s*\{", config_text)
    if not m:
        return out
    depth, i = 1, m.end()
    line_start = i
    while i < len(config_text) and depth:
        c = config_text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
        elif c == "\n":
            line = config_text[line_start:i]
            if depth == 1:
                lm = re.match(r"\s*([A-Za-z_]\w*)\s*=\s*(.+)$", line)
                if lm:
                    out[lm.group(1)] = _literal(lm.group(2))
            line_start = i + 1
        i += 1
    return out


def executed_pipeline_params(filename: str) -> Optional[Dict[str, Any]]:
    """What the executed nf-core pipeline itself declares, or None (see executed_schema_required).

    {"required": set, "props": {name: schema property}, "known": set of declared param
    names (schema ∪ nextflow.config params), "defaults": {name: the pipeline's own default}}.
    Config defaults win over schema defaults: the config is what Nextflow applies.
    """
    got = executed_schema_required(filename)
    if got is None:
        return None
    required, props = got
    try:
        from galaxy.webapps.galaxy.api.nextflow_executor import _resolve_nextflow_path  # noqa: PLC0415

        cfg_text = (Path(str(_resolve_nextflow_path(filename))).parent / "nextflow.config").read_text(errors="replace")
    except Exception:
        cfg_text = ""
    cfg = config_param_defaults(cfg_text)
    defaults = {k: v["default"] for k, v in props.items() if "default" in v}
    defaults.update({k: v for k, v in cfg.items() if v is not _UNSET})
    return {"required": required, "props": props, "known": set(props) | set(cfg), "defaults": defaults}


def executed_schema_required(filename: str) -> Optional[Tuple[Set[str], Dict[str, dict]]]:
    """(required names, {name: schema property}) for the executed pipeline, or None.

    None when the executor does not resolve the row to a real nf-core pipeline
    (/nf-core-workflows/<name>/, not the modules library) or that pipeline has no
    readable nextflow_schema.json — callers then keep their own required-ness.
    """
    if not filename:
        return None
    try:
        from galaxy.webapps.galaxy.api.nextflow_executor import _resolve_nextflow_path  # noqa: PLC0415

        executed = Path(str(_resolve_nextflow_path(filename)))
    except Exception:  # unresolvable, or executor unavailable (unit tests)
        return None
    s = str(executed)
    if "/nf-core-workflows/" not in s or "/nf-core-workflows/modules/" in s:
        return None
    try:
        schema = json.loads((executed.parent / "nextflow_schema.json").read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    defs = schema.get("$defs") or schema.get("definitions") or {}
    props: Dict[str, dict] = {}
    required: Set[str] = set()
    for group in defs.values():
        if not isinstance(group, dict):
            continue
        props.update({k: v for k, v in (group.get("properties") or {}).items() if isinstance(v, dict)})
        required.update(r for r in (group.get("required") or []) if isinstance(r, str))
    if not props:
        return None
    return required - EXECUTOR_SET_PARAMS, props
