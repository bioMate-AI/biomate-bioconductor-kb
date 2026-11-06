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
from pathlib import Path
from typing import Dict, Optional, Set, Tuple

# Set by the executor on every run; never asked of the user.
EXECUTOR_SET_PARAMS = frozenset({"outdir"})


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
