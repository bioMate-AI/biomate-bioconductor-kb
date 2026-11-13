"""Is a `params.X = null` in a BioMate .nf workflow actually required?

Both param builders (ai_assistant._parse_nextflow_params and the /api/workflows/search
parser) marked every null-default param required, and the launch gate enforces
required_params. Many null params are optional by the workflow's own code — GROMACS MD's
box_center/box_size (`params.box_center ?: ''`, "No box_center provided; ligand left at
original coordinates"), pmx FEP's control_edge_expected (`params.control_edge_expected != null
? …`) — so those runs were refused before any compute (2026-11-08).

Rule, read from the workflow source:
  - required  if the code enforces presence: `if (!params.X …) { error/exit … }` or a message
    like "params.X is required" / "--X is required" / "Please provide --X";
  - optional  if the code handles absence: `params.X ?:`, `params.X != null`, `params.X == null`,
    `if (params.X)` / `params.X ?` (ternary);
  - otherwise unchanged (required) — no evidence either way.

Exception (2026-11-13 clinic gate): an elvis fallback to bundled demo/test/example data
(`params.movies_path ?: "${baseDir}/test_data"`) is NOT "optional for the user" — it is a
dev convenience. Treating it as optional let CryoSPARC SPA reach Running with Movies Path
unset. Demo elvis still counts as required for clinic users.
"""
import re

_REQUIRED_MSG = r"(?:params\.|--){n}\b[^\n\"']{{0,40}}\b(?:is |are )?required|(?:provide|supply|specify)[^\n\"']{{0,20}}--{n}\b"
_ABSENCE_HANDLED = (
    r"params\.{n}\s*\?:",                  # elvis default
    r"params\.{n}\s*[!=]=\s*null",          # explicit null test
    r"\bif\s*\(\s*params\.{n}\s*\)",        # if (params.X)
    r"params\.{n}\s*\?\s*[^:?.]",           # ternary on presence: params.X ? a : b
)
def null_param_is_required(nf_text: str, name: str) -> bool:
    """True unless the workflow's own code shows a null `params.<name>` is optional."""
    if not nf_text or not name:
        return True
    n = re.escape(name)
    enforced = re.search(_REQUIRED_MSG.format(n=n), nf_text, re.IGNORECASE) or re.search(
        r"if\s*\([^)]*!\s*params\.%s\b[^)]*\)\s*\{?[^}]{0,200}?\b(?:error|exit)\b" % n, nf_text, re.DOTALL)
    if enforced:
        return True
    # Demo/test elvis is a developer fallback, not a clinic optional
    # (cryosparc_standard_spa: params.movies_path ?: "${baseDir}/test_data").
    if re.search(
        r"params\.%s\s*\?:[^\n]*(?:test_data|testdata|example_data|exampledata|/examples?/|"
        r"demo_data|demodata|baseDir\}\s*/\s*test|baseDir\s*/\s*test)" % n,
        nf_text,
        re.IGNORECASE,
    ):
        return True
    return not any(re.search(p.format(n=n), nf_text) for p in _ABSENCE_HANDLED)
