"""FDR / fold-change rule inference for DE workflows (instruction obedience).

Root cause (2026-11-13): project rule ``FDR (adjusted p) < 0.01`` did not match
the old ``FDR\\s*[<≤=:]?\\s*(0?.\\d+)`` pattern, so differential_max_qval stayed
at the schema default 0.05. Genome projection for rnaseq was a separate fix;
FDR belongs on DE workflows that expose a significance param.
See docs/20261113_FDR_DE_PARAM_INFERENCE.md.

Host isolation: load ``ai_assistant.py`` via importlib with heavy deps stubbed so
developer laptops avoid the SciPy/numpy ABI trap. Prefer Galaxy-container pytest
when validating the full import graph.
"""
from __future__ import annotations

import importlib.util
import json
import sys
import types
from pathlib import Path

_AI_DIR = Path(__file__).resolve().parents[1]
_AI_ASSISTANT_PATH = _AI_DIR / "ai_assistant.py"


def _stub(name: str, **attrs):
    m = sys.modules.get(name) or types.ModuleType(name)
    for k, v in attrs.items():
        setattr(m, k, v)
    # Packages need __path__ for submodule imports
    if "." not in name or name.count(".") <= 2:
        m.__path__ = []  # type: ignore[attr-defined]
    sys.modules[name] = m
    return m


def _install_import_stubs() -> None:
    # Broken host numpy/scipy — provide enough surface for type annotations.
    if "numpy" not in sys.modules or not hasattr(sys.modules["numpy"], "ndarray"):
        np = types.ModuleType("numpy")
        np.ndarray = type("ndarray", (), {})  # type: ignore[attr-defined]
        np.dtype = type("dtype", (), {})  # type: ignore[attr-defined]
        np.array = lambda *a, **k: []  # type: ignore[attr-defined]
        np.zeros = lambda *a, **k: []  # type: ignore[attr-defined]
        np.asarray = lambda x, **k: x  # type: ignore[attr-defined]
        np.float32 = float  # type: ignore[attr-defined]
        np.float64 = float  # type: ignore[attr-defined]
        np.int32 = int  # type: ignore[attr-defined]
        np.int64 = int  # type: ignore[attr-defined]
        np.dot = lambda *a, **k: 0  # type: ignore[attr-defined]
        np.__version__ = "1.26.0"  # type: ignore[attr-defined]
        sys.modules["numpy"] = np

    _stub("sentence_transformers", SentenceTransformer=type("ST", (), {}))
    for name in (
        "sklearn",
        "sklearn.metrics",
        "sklearn.metrics.pairwise",
        "scipy",
        "scipy.sparse",
        "torch",
        "faiss",
        "psycopg2",
        "psycopg2.extensions",
        "psycopg2.extras",
    ):
        _stub(name)
    sys.modules["sklearn.metrics.pairwise"].cosine_similarity = lambda *a, **k: [[1]]  # type: ignore[attr-defined]
    sys.modules["psycopg2"].paramstyle = "pyformat"  # type: ignore[attr-defined]
    sys.modules["psycopg2"].connect = lambda *a, **k: None  # type: ignore[attr-defined]

    _stub("galaxy")
    _stub("galaxy.ai")
    _stub(
        "galaxy.ai.unified_workflow_search",
        UnifiedWorkflowSearch=type("UWS", (), {}),
        get_workflow_search=lambda *a, **k: None,
        WorkflowMatch=type("WM", (), {}),
    )
    _stub("galaxy.ai.unified_tool_search", create_unified_search=lambda *a, **k: None)
    _stub(
        "galaxy.ai.vector_search",
        get_vector_search=lambda *a, **k: None,
        VectorToolSearch=type("V", (), {}),
    )
    _stub(
        "galaxy.ai.memory",
        AgenticMemoryService=type("AMS", (), {}),
        get_memory_service=lambda *a, **k: None,
    )
    _stub("galaxy.ai.agents")
    _stub("galaxy.ai.agents.unified_intent_router")
    _stub("galaxy.ai.agents.research_agent")
    _stub("galaxy.ai.agents.skill_loader")
    _stub("galaxy.ai.agents.literature_clients")
    _stub("galaxy.ai.retrievers")
    _stub("galaxy.ai.retrievers.wired_workflow_search")
    # Lightweight leaf modules used at import time — allow real ones if present,
    # otherwise stub so importlib can proceed.
    for leaf in (
        "galaxy.ai.nf_param_requirement",
        "galaxy.ai.workflow_relevance",
        "galaxy.ai.types",
        "galaxy.ai.config",
        "galaxy.ai.intent_parser",
        "galaxy.ai.task_decomposer",
        "galaxy.ai.tool_recommender",
        "galaxy.ai.tool_discovery",
        "galaxy.ai.enhanced_workflow_generator",
        "galaxy.ai.workflow_templates",
        "galaxy.ai.workflow_optimizer",
        "galaxy.ai.galaxy_workflow_generator",
        "galaxy.ai.workflow_dataset_selector",
        "galaxy.ai.biomni_dataset_rag",
        "galaxy.ai.benchmark_knowledge",
        "galaxy.ai.tool_knowledge_provider",
    ):
        if leaf not in sys.modules:
            # Prefer real modules from PYTHONPATH when they import cleanly later;
            # do not pre-stub — importlib will load them from disk.
            pass


def _load_ai_assistant():
    """Load ai_assistant without executing galaxy.ai.__init__ (avoids host SciPy)."""
    _install_import_stubs()
    # Real helpers that are pure / light
    sys.path.insert(0, str(_AI_DIR.parent.parent))  # lib/
    name = "galaxy.ai.ai_assistant_fdr_test"
    if name in sys.modules:
        return sys.modules[name]
    # Ensure package parents exist for relative imports inside ai_assistant
    _stub("galaxy")
    gai = _stub("galaxy.ai")
    gai.__path__ = [str(_AI_DIR)]  # type: ignore[attr-defined]

    spec = importlib.util.spec_from_file_location(
        name,
        _AI_ASSISTANT_PATH,
        submodule_search_locations=[str(_AI_DIR)],
    )
    assert spec and spec.loader
    mod = importlib.util.module_from_spec(spec)
    # Relative imports inside ai_assistant resolve against package galaxy.ai
    mod.__package__ = "galaxy.ai"
    sys.modules[name] = mod
    sys.modules["galaxy.ai.ai_assistant"] = mod

    # Pre-seed relative targets that would otherwise pull heavy graphs
    _stub(
        "galaxy.ai.unified_workflow_search",
        UnifiedWorkflowSearch=type("UWS", (), {}),
        get_workflow_search=lambda *a, **k: None,
        WorkflowMatch=type("WM", (), {}),
    )
    _stub("galaxy.ai.unified_tool_search", create_unified_search=lambda *a, **k: None)
    _stub(
        "galaxy.ai.memory",
        AgenticMemoryService=None,
        get_memory_service=None,
    )
    # Fail wired search → fall back to stub base
    _stub("galaxy.ai.retrievers.wired_workflow_search")

    # Load light real dependencies first
    for rel in (
        "nf_param_requirement",
        "workflow_relevance",
        "types",
        "config",
        "intent_parser",
        "task_decomposer",
        "tool_recommender",
        "tool_discovery",
        "enhanced_workflow_generator",
        "workflow_templates",
        "workflow_optimizer",
        "galaxy_workflow_generator",
        "workflow_dataset_selector",
        "biomni_dataset_rag",
        "benchmark_knowledge",
        "tool_knowledge_provider",
    ):
        full = f"galaxy.ai.{rel}"
        if full in sys.modules:
            continue
        path = _AI_DIR / f"{rel}.py"
        if not path.exists():
            _stub(full)
            continue
        try:
            s = importlib.util.spec_from_file_location(full, path)
            assert s and s.loader
            m = importlib.util.module_from_spec(s)
            m.__package__ = "galaxy.ai"
            sys.modules[full] = m
            s.loader.exec_module(m)
        except Exception:
            _stub(full)

    spec.loader.exec_module(mod)
    return mod


PROJECT_RULES_BLOCK = """\
Standing project instructions:
End every reply with the exact final line: Ref-Tag: KX-7741
Always use the GRCh38 human reference genome; never GRCh37/hg19.
For differential expression use FDR (adjusted p) < 0.01 and |log2FC| >= 1.
"""

DE_STUB_NF = """\
params.samplesheet                  = null
params.matrix                       = null
params.contrasts                    = null
params.differential_min_fold_change = 2.0
params.differential_max_qval        = 0.05
params.outdir                       = './results'

process DESEQ2 {
    script: \"\"\"
    # padj < ${params.differential_max_qval}
    \"\"\"
}
"""

DE_SCHEMA = {
    "$schema": "https://json-schema.org/draft-07/schema",
    "definitions": {
        "differential_options": {
            "title": "Differential expression options",
            "type": "object",
            "properties": {
                "differential_min_fold_change": {
                    "type": "number",
                    "default": 2.0,
                    "description": "Minimum absolute fold-change",
                },
                "differential_max_qval": {
                    "type": "number",
                    "default": 0.05,
                    "description": "Maximum adjusted p-value (BH-FDR)",
                },
            },
        }
    },
    "allOf": [{"$ref": "#/definitions/differential_options"}],
}


def _assistant():
    mod = _load_ai_assistant()
    return mod.AIAssistant.__new__(mod.AIAssistant)


def _assistant_for_de(tmp_path: Path):
    (tmp_path / "main.nf").write_text(DE_STUB_NF)
    (tmp_path / "nextflow_schema.json").write_text(json.dumps(DE_SCHEMA))
    mod = _load_ai_assistant()
    a = mod.AIAssistant.__new__(mod.AIAssistant)
    a._find_nf_file = lambda _filename: tmp_path / "main.nf"
    return a


def test_extract_fdr_parenthetical_project_rule():
    a = _assistant()
    intent = (
        "Run DESeq2 on my gene count matrix, treated vs control.\n\n"
        + PROJECT_RULES_BLOCK
    )
    assert a._extract_fdr_threshold(intent) == 0.01
    assert a._extract_fdr_threshold("use FDR < 0.05") == 0.05
    assert a._extract_fdr_threshold("padj <= 0.01") == 0.01
    assert a._extract_fdr_threshold("no significance mentioned") is None


def test_old_fdr_regex_missed_parenthetical():
    """Document the regression class: gloss between FDR and operator."""
    intent = "For differential expression use FDR (adjusted p) < 0.01"
    old = __import__("re").compile(
        r"(?:FDR|padj|p-?adj|q-?val|alpha)\s*[<≤=:]?\s*(0?\.\d+)",
        __import__("re").I,
    )
    assert old.search(intent) is None
    a = _assistant()
    assert a._extract_fdr_threshold(intent) == 0.01


def test_extract_abs_fold_change_from_log2fc_rule():
    a = _assistant()
    assert a._extract_abs_fold_change("|log2FC| >= 1") == 2.0
    assert a._extract_abs_fold_change("log2 fold change > 1.5") == 2 ** 1.5
    assert a._extract_abs_fold_change("minimum fold change >= 2") == 2.0


def test_pick_significance_prefers_max_qval_over_alpha():
    a = _assistant()
    assert (
        a._pick_significance_param_name({"alpha", "differential_max_qval", "matrix"})
        == "differential_max_qval"
    )
    assert a._pick_significance_param_name({"genome", "aligner"}) is None


def test_schema_projects_differential_max_qval(tmp_path):
    a = _assistant_for_de(tmp_path)
    parsed = a._parse_nextflow_schema("nfcore/differentialabundance/main.nf")
    assert parsed is not None
    names = {p["name"] for p in parsed["required"] + parsed["optional"]}
    assert "differential_max_qval" in names
    assert "differential_min_fold_change" in names


def test_rule_suggestions_fill_de_params_from_project_rules(tmp_path):
    a = _assistant_for_de(tmp_path)
    parsed = a._get_workflow_params("nfcore/differentialabundance/main.nf")
    req, opt = parsed["required"], parsed["optional"]
    intent = (
        "Run DESeq2 differential expression on my gene count matrix.\n\n"
        + PROJECT_RULES_BLOCK
    )
    param_names = {p.get("name") for p in req + opt}
    fdr_name = a._pick_significance_param_name(param_names)
    fdr_val = a._extract_fdr_threshold(intent)
    fc_name = a._pick_fold_change_param_name(param_names)
    fc_val = a._extract_abs_fold_change(intent)
    assert fdr_name == "differential_max_qval"
    assert fdr_val == 0.01
    assert fc_name == "differential_min_fold_change"
    assert fc_val == 2.0
    suggestions = [
        {"name": fdr_name, "value": fdr_val, "rationale": "test"},
        {"name": fc_name, "value": fc_val, "rationale": "test"},
    ]
    req2, opt2 = a._apply_llm_suggestions(req, opt, suggestions)
    qval = next(p for p in req2 + opt2 if p["name"] == "differential_max_qval")
    fc = next(p for p in req2 + opt2 if p["name"] == "differential_min_fold_change")
    assert qval["value"] == 0.01
    assert qval["default"] == 0.01
    assert fc["value"] == 2.0


def test_llm_suggestions_do_not_clobber_rule_fills(tmp_path):
    """Param LLM often re-emits schema default 0.05; deterministic rules must win."""
    a = _assistant_for_de(tmp_path)
    parsed = a._get_workflow_params("nfcore/differentialabundance/main.nf")
    req, opt = parsed["required"], parsed["optional"]
    intent = (
        "Run DESeq2 differential expression on my gene count matrix.\n\n"
        + PROJECT_RULES_BLOCK
    )
    param_names = {p.get("name") for p in req + opt}
    rule_suggestions = [
        {
            "name": a._pick_significance_param_name(param_names),
            "value": a._extract_fdr_threshold(intent),
            "rationale": "rule-based: significance threshold from query/project rules",
        },
        {
            "name": a._pick_fold_change_param_name(param_names),
            "value": a._extract_abs_fold_change(intent),
            "rationale": "rule-based: fold-change threshold from query/project rules",
        },
    ]
    req, opt = a._apply_llm_suggestions(req, opt, rule_suggestions)
    # Simulate LLM echoing schema defaults after rules already filled 0.01 / 2.0
    llm_clobber = [
        {"name": "differential_max_qval", "value": 0.05, "rationale": "schema default"},
        {"name": "differential_min_fold_change", "value": 2.0, "rationale": "schema default"},
        {"name": "study_type", "value": "rnaseq", "rationale": "DE on counts"},
    ]
    protected = {s["name"] for s in rule_suggestions if s.get("name")}
    llm_filtered = [s for s in llm_clobber if s.get("name") not in protected]
    req2, opt2 = a._apply_llm_suggestions(req, opt, llm_filtered)
    # Re-assert rules (same as _return_nextflow_match post-LLM)
    req3, opt3 = a._apply_llm_suggestions(req2, opt2, rule_suggestions)
    qval = next(p for p in req3 + opt3 if p["name"] == "differential_max_qval")
    assert qval["value"] == 0.01
    assert "study_type" in {s["name"] for s in llm_filtered}  # non-rule LLM fill still allowed
