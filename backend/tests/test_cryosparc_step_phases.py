"""CryoSPARC standard SPA phase map must cover every parsed process.

Regression for the "Other Steps" / shifted A–E labels bug: the old
index-keyed ``_CRYOSPARC_STEP_PHASES`` only covered 0–22 while
``cryosparc_standard_spa/main.nf`` declares 33 processes, so
TEMPLATE_PICKER→SHARPEN (23–32) got empty ``phase_group`` and the UI
bucketed them as Other while early indices wore the wrong letters.
"""
from __future__ import annotations

import importlib.util
import re
import sys
import types
from pathlib import Path

BACKEND = Path(__file__).resolve().parents[1]
MAIN_NF = (
    BACKEND
    / "biomni_workflows"
    / "nextflow_nfcore"
    / "subworkflows"
    / "cryo_em"
    / "cryosparc_standard_spa"
    / "main.nf"
)
AI_ASSISTANT_PY = (
    BACKEND / "lib" / "galaxy" / "webapps" / "galaxy" / "api" / "ai_assistant.py"
)

_PROC_RE = re.compile(r"^process\s+([A-Za-z][A-Za-z0-9_]+)\s*\{", re.MULTILINE)


def _process_names_from_main_nf() -> list[str]:
    """Same order ``_parse_nextflow_steps`` Strategy 1 emits."""
    return _PROC_RE.findall(MAIN_NF.read_text(encoding="utf-8", errors="replace"))


def _stub(name: str, **attrs):
    mod = types.ModuleType(name)
    for key, value in attrs.items():
        setattr(mod, key, value)
    sys.modules[name] = mod
    return mod


def _load_ai_assistant():
    """Load api/ai_assistant.py without the full Galaxy runtime (beaker, etc.)."""
    if "galaxy.webapps.galaxy.api.ai_assistant" in sys.modules:
        return sys.modules["galaxy.webapps.galaxy.api.ai_assistant"]

    _stub(
        "fastapi",
        HTTPException=Exception,
        Path=lambda *a, **k: None,
        Query=lambda *a, **k: None,
        Depends=lambda *a, **k: None,
    )

    class _BaseModel:
        pass

    class _Field:
        def __init__(self, *a, **k):
            pass

    def _field_validator(*a, **k):
        def deco(f):
            return f

        return deco

    pydantic = _stub("pydantic")
    pydantic.BaseModel = _BaseModel
    pydantic.Field = _Field
    pydantic.field_validator = _field_validator

    _stub("galaxy")
    _stub("galaxy.util")
    _stub("galaxy.managers")
    _stub("galaxy.managers.context", ProvidesUserContext=object)
    _stub("galaxy.webapps")
    _stub("galaxy.webapps.galaxy")
    _stub(
        "galaxy.webapps.galaxy.api",
        DependsOnTrans=object,
        Router=lambda *a, **k: types.SimpleNamespace(
            cbv=lambda cls: cls,
            get=lambda *a, **k: (lambda f: f),
            post=lambda *a, **k: (lambda f: f),
            put=lambda *a, **k: (lambda f: f),
            delete=lambda *a, **k: (lambda f: f),
        ),
    )
    _stub("galaxy.ai")
    _stub("galaxy.ai.ai_assistant", AIAssistant=None)
    _stub("galaxy.ai.config", AIConfig=None, DEFAULT_AI_CONFIG=None)
    _stub(
        "galaxy.ai.types",
        UserRequest=None,
        TaskType=None,
        IntentType=None,
    )

    spec = importlib.util.spec_from_file_location(
        "galaxy.webapps.galaxy.api.ai_assistant", AI_ASSISTANT_PY
    )
    mod = importlib.util.module_from_spec(spec)
    sys.modules["galaxy.webapps.galaxy.api.ai_assistant"] = mod
    assert spec.loader is not None
    spec.loader.exec_module(mod)
    return mod


def test_main_nf_declares_33_processes_in_parse_order():
    procs = _process_names_from_main_nf()
    assert len(procs) == 33
    assert procs[0] == "INIT_CRYOSPARC_PROJECT"
    assert procs[23] == "TEMPLATE_PICKER"
    assert procs[32] == "SHARPEN"


def test_cryosparc_phase_map_covers_every_process_name():
    mod = _load_ai_assistant()
    procs = _process_names_from_main_nf()
    missing = [p for p in procs if p not in mod._CRYOSPARC_STEP_PHASES]
    assert not missing, (
        "Unmapped cryo processes will render as Other Steps / empty phase_group: "
        f"{missing}"
    )
    # Map must stay name-keyed (not fragile int indices 0..N).
    assert all(isinstance(k, str) for k in mod._CRYOSPARC_STEP_PHASES)


def test_parsed_cryosparc_steps_never_land_in_other():
    mod = _load_ai_assistant()
    steps = mod._parse_nextflow_steps(str(MAIN_NF))
    assert len(steps) == 33

    bad = []
    by_tool = {}
    for sid, st in steps.items():
        tool_id = st.get("tool_id", "")
        pg = (st.get("phase_group") or "").strip()
        by_tool[tool_id] = pg
        if not pg or pg.lower() == "other":
            bad.append((sid, tool_id, repr(pg)))

    assert not bad, f"steps with empty/other phase_group: {bad}"
    # Late SPA: template pick stays in 2D/picking loop (C); sharpen is Phase E.
    assert by_tool["TEMPLATE_PICKER"] == "C"
    assert by_tool["SHARPEN"] == "E"
    assert by_tool["VOLUME_TOOLS"] == "E"
    assert by_tool["INIT_CRYOSPARC_PROJECT"] == "A"
    assert by_tool["BLOB_PICKER_BATCH"] == "B"
    assert by_tool["AB_INITIO_BATCH"] == "D"
