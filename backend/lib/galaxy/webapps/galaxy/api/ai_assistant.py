"""
Galaxy AI Assistant API

RESTful API endpoints for the Galaxy AI Assistant functionality.
Includes citation management, progressive tuning, and benchmark endpoints.
"""

import ast as _ast
import json
import logging
import uuid
import sqlite3
import re
from datetime import datetime
from pathlib import Path as FilePath
from typing import Dict, List, Any, Optional

from fastapi import HTTPException, Path, Query, Depends
from pydantic import BaseModel, Field

from galaxy import util
from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import (
    DependsOnTrans,
    Router
)

# Import AI components with error handling
try:
    from galaxy.ai.ai_assistant import AIAssistant
    from galaxy.ai.config import AIConfig, DEFAULT_AI_CONFIG
    from galaxy.ai.types import UserRequest, TaskType, IntentType
    AI_AVAILABLE = True
except ImportError as e:
    logging.warning(f"AI Assistant components not available: {e}")
    AI_AVAILABLE = False
    AIAssistant = None
    AIConfig = None
    DEFAULT_AI_CONFIG = None
    UserRequest = None
    TaskType = None
    IntentType = None

# Import progressive tuning components
try:
    from galaxy.ai.progressive_tuning import (
        ProgressiveTuningController,
        TuningConfig,
        SamplingStrategy,
        PilotResult,
        FullRunEstimate
    )
    TUNING_AVAILABLE = True
except ImportError as e:
    logging.warning(f"Progressive tuning components not available: {e}")
    TUNING_AVAILABLE = False
    ProgressiveTuningController = None
    TuningConfig = None
    SamplingStrategy = None

# Import benchmark knowledge components (Added 2025-12-30)
try:
    from galaxy.ai.benchmark_knowledge import BenchmarkKnowledgeDB
    BENCHMARK_AVAILABLE = True
except ImportError as e:
    logging.warning(f"Benchmark knowledge components not available: {e}")
    BENCHMARK_AVAILABLE = False
    BenchmarkKnowledgeDB = None

# Import ResearchAgent and SkillLoader (Added 2025-12-30)
try:
    from galaxy.ai.agents.research_agent import ResearchAgent, create_research_agent
    from galaxy.ai.agents.skill_loader import SkillLoader, create_skill_loader
    RESEARCH_AGENT_AVAILABLE = True
except ImportError as e:
    logging.warning(f"ResearchAgent components not available: {e}")
    RESEARCH_AGENT_AVAILABLE = False
    ResearchAgent = None
    SkillLoader = None

log = logging.getLogger(__name__)

router = Router(tags=["ai_assistant"])

# Global AI assistant instance
_ai_assistant_instance = None


# ── Lightweight Nextflow workflow search (NO LLM required) ──────────────────
try:
    from galaxy.ai.unified_workflow_search import get_workflow_search as _get_workflow_search
    _workflow_search = _get_workflow_search()
    WORKFLOW_SEARCH_AVAILABLE = True
except Exception as _e:
    logging.warning(f"UnifiedWorkflowSearch not available: {_e}")
    _workflow_search = None
    WORKFLOW_SEARCH_AVAILABLE = False

# ── WorkflowSession Redis store ───────────────────────────────────────────────
# Lazy singleton — initialized on first actual use, not at import time.
# This avoids blocking the worker startup when Redis is unavailable.
import os as _os
_session_store = None
_WorkflowSessionStore = None
try:
    from galaxy.ai.workflow_session import WorkflowSessionStore as _WorkflowSessionStore
except Exception as _sess_import_err:
    logging.warning(f"WorkflowSessionStore import failed: {_sess_import_err}")


def _get_session_store():
    """Return (and lazily create) the module-level WorkflowSessionStore."""
    global _session_store
    if _session_store is None and _WorkflowSessionStore is not None:
        try:
            _session_store = _WorkflowSessionStore(
                redis_url=_os.getenv("REDIS_URL")  # None → in-memory fallback, no ping
            )
            log.info("[WorkflowSessionStore] Initialized (Redis=%s)", _os.getenv("REDIS_URL") or "in-memory")
        except Exception as _se:
            log.warning("[WorkflowSessionStore] Init failed, sessions disabled: %s", _se)
    return _session_store

# ── ToolKnowledgeProvider for scientific rationale ───────────────────────────
try:
    from galaxy.ai.tool_knowledge_provider import ToolKnowledgeProvider as _ToolKnowledgeProvider
    _TOOL_KNOWLEDGE_AVAILABLE = True
except Exception as _e:
    logging.warning(f"ToolKnowledgeProvider not available: {_e}")
    _ToolKnowledgeProvider = None
    _TOOL_KNOWLEDGE_AVAILABLE = False


def _extract_scalar_param(v: Any) -> str:
    """Return a clean scalar string from a parameter value (handles string-encoded dicts)."""
    if isinstance(v, dict):
        scalar = v.get("default") or v.get("value") or next(iter(v.values()), v)
        return str(scalar)
    if isinstance(v, str):
        s = v.strip()
        if s.startswith(("{", "[")):
            try:
                parsed = _ast.literal_eval(s)
                if isinstance(parsed, dict):
                    scalar = parsed.get("default") or parsed.get("value") or next(iter(parsed.values()), v)
                    return str(scalar)
                if isinstance(parsed, (list, tuple)) and parsed:
                    return str(parsed[0])
            except (ValueError, SyntaxError):
                pass
    return str(v)


def _build_scientific_rationale_from_tools(workflow_tools: List[str]) -> Dict[str, Any]:
    """Build scientific rationale dict from a workflow's tools_used list.

    Returns an empty dict if no tool_knowledge entries are found with use_cases.
    """
    if not _TOOL_KNOWLEDGE_AVAILABLE or not _ToolKnowledgeProvider or not workflow_tools:
        return {}
    try:
        provider = _ToolKnowledgeProvider()
    except Exception:
        return {}

    seen_lower: set = set()
    core_tools: List[str] = []
    for raw_name in workflow_tools:
        knowledge = provider.get_tool_knowledge(raw_name)
        if (knowledge
                and knowledge.use_cases
                and knowledge.tool_name.lower() not in seen_lower):
            core_tools.append(knowledge.tool_name)
            seen_lower.add(knowledge.tool_name.lower())

    if not core_tools:
        return {}

    rationale: Dict[str, Any] = {
        "tools_used": [],
        "when_to_use": [],
        "do_not_use_when": [],
        "data_requirements": {},
        "key_assumptions": [],
        "common_pitfalls": [],
        "parameter_hints": [],
    }

    for tool_name in core_tools:
        knowledge = provider.get_tool_knowledge(tool_name)
        if knowledge:
            rationale["tools_used"].append(knowledge.tool_name)
            for uc in (knowledge.use_cases or [])[:3]:
                if uc not in rationale["when_to_use"]:
                    rationale["when_to_use"].append(uc)
            for lim in (knowledge.limitations or [])[:3]:
                if lim not in rationale["do_not_use_when"]:
                    rationale["do_not_use_when"].append(lim)
            for param_name, rec in list((knowledge.recommended_parameters or {}).items())[:6]:
                if param_name.startswith('_'):  # skip internal metadata keys like _expert_guidance
                    continue
                rationale["parameter_hints"].append({
                    "param": param_name,
                    "recommended": _extract_scalar_param(rec.recommended_value),
                    "rationale": rec.description or "",
                    "tool": tool_name,
                })

    return rationale if rationale["tools_used"] else {}


def _build_parameter_metadata_from_tools(
    param_keys: List[str],
    tool_ids: Optional[List[str]] = None,
) -> Dict[str, Any]:
    """
    Build parameter_metadata dict for use in workflow search / generation responses.

    For each key in param_keys produces:
        {label, type, help, optional, default}

    Lookup order:
    1. galaxy_ai_tools.db tools.parameters column (JSON list) for any tool_ids given.
    2. Fallback: infer from the param key name.

    Never raises — returns partial/empty dict on any error.
    """
    metadata: Dict[str, Any] = {}
    if not param_keys:
        return metadata

    _TYPE_MAP = {
        'data': 'file',
        'data_collection': 'file',
        'integer': 'integer',
        'float': 'float',
        'boolean': 'boolean',
        'select': 'select',
        'text': 'text',
        'color': 'text',
    }

    try:
        db_path = FilePath(__file__).resolve().parents[5] / "database" / "galaxy_ai_tools.db"
        if db_path.exists() and tool_ids:
            conn = sqlite3.connect(str(db_path))
            try:
                for tool_id in tool_ids:
                    if not tool_id:
                        continue
                    row = conn.execute(
                        "SELECT parameters FROM tools WHERE tool_id = ? LIMIT 1",
                        (str(tool_id),)
                    ).fetchone()
                    if not row or not row[0]:
                        short_name = str(tool_id).split('/')[-1]
                        row = conn.execute(
                            "SELECT parameters FROM tools WHERE LOWER(name) = LOWER(?) LIMIT 1",
                            (short_name,)
                        ).fetchone()
                    if row and row[0]:
                        try:
                            params_list = json.loads(row[0]) if isinstance(row[0], str) else row[0]
                            if isinstance(params_list, list):
                                for p in params_list:
                                    name = p.get('name', '')
                                    if name and name not in metadata:
                                        raw_type = p.get('type', 'text')
                                        metadata[name] = {
                                            'label': p.get('label', name.replace('_', ' ').replace('-', ' ').title()),
                                            'type': _TYPE_MAP.get(raw_type, 'text'),
                                            'help': p.get('help', ''),
                                            'optional': bool(p.get('optional', True)),
                                            'default': p.get('value', p.get('default', None)),
                                        }
                        except Exception:
                            pass
            finally:
                conn.close()
    except Exception:
        pass

    _REQUIRED_KW = ('input', 'output', 'reference', 'sample', 'file', 'genome', 'fasta', 'fastq', 'bam')
    _INT_KW = ('threads', 'cpus', 'cores', 'jobs', 'count', 'num_', 'max_', 'min_', 'k_mer', 'length')
    _FLOAT_KW = ('pvalue', 'p_value', 'fdr', 'threshold', 'ratio', 'fraction', 'rate', 'score')
    _BOOL_KW = ('enable', 'disable', 'use_', 'skip_', 'paired', 'strand')
    _FILE_KW = ('input', 'file', 'fasta', 'fastq', 'bam', 'reference', 'genome')
    for key in param_keys:
        if key not in metadata:
            key_lower = key.lower()
            is_required = any(kw in key_lower for kw in _REQUIRED_KW)
            if any(kw in key_lower for kw in _INT_KW):
                inferred_type = 'integer'
            elif any(kw in key_lower for kw in _FLOAT_KW):
                inferred_type = 'float'
            elif any(kw in key_lower for kw in _BOOL_KW):
                inferred_type = 'boolean'
            elif any(kw in key_lower for kw in _FILE_KW):
                inferred_type = 'file'
            else:
                inferred_type = 'text'
            metadata[key] = {
                'label': key.replace('_', ' ').replace('-', ' ').title(),
                'type': inferred_type,
                'help': '',
                'optional': not is_required,
                'default': None,
            }

    return metadata


class NextflowSearchRequest(BaseModel):
    user_intent: Optional[str] = None
    request_text: Optional[str] = None


def _nextflow_workflow_key(filename: str) -> Optional[str]:
    path = (filename or "").strip().lower()
    if not path:
        return None
    # biomni_nf/domain/workflow/main.nf
    if path.startswith("biomni_nf/"):
        parts = [p for p in path.split("/") if p]
        if len(parts) >= 3:
            return f"{parts[1]}/{parts[2]}"
    # nextflow_nfcore/domain/workflow/main.nf (newer path format for biomni workflows)
    if path.startswith("nextflow_nfcore/"):
        parts = [p for p in path.split("/") if p]
        # Skip "nextflow_nfcore" prefix and "bioconductor" source (R packages, not runnable as nf)
        if len(parts) >= 3 and parts[1] != "bioconductor":
            return f"{parts[1]}/{parts[2]}"
    marker = "/subworkflows/"
    if marker in path:
        tail = path.split(marker, 1)[1]
        parts = [p for p in tail.split("/") if p]
        if len(parts) >= 2:
            return f"{parts[0]}/{parts[1]}"
    return None


def _load_runnable_nextflow_keys() -> set[str]:
    backend_root = FilePath(__file__).resolve().parents[5]
    passed_file = backend_root / "biomni_workflows" / "nextflow_nfcore" / "test_results" / "passed_workflows.txt"
    if not passed_file.exists():
        return set()
    try:
        lines = [ln.strip().lower() for ln in passed_file.read_text(errors="replace").splitlines()]
        return {ln for ln in lines if ln and "/" in ln}
    except OSError:
        return set()


def _parse_memory_gb(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        try:
            return float(value)
        except (TypeError, ValueError):
            return None
    text = str(value).strip().lower()
    if not text:
        return None
    match = re.search(r"(\d+(?:\.\d+)?)", text)
    if not match:
        return None
    try:
        return float(match.group(1))
    except (TypeError, ValueError):
        return None


def _collect_workflow_hardware_requirements(workflow_tools: List[str]) -> Optional[Dict[str, Any]]:
    tools = [str(t).strip() for t in (workflow_tools or []) if str(t).strip()]
    if not tools:
        return None

    db_path = FilePath(__file__).resolve().parents[5] / "database" / "galaxy_ai_tools.db"
    if not db_path.exists():
        return None

    conn = None
    gpu_required = False
    max_memory_gb = 0.0
    tool_runtime_hints: List[Dict[str, Any]] = []
    seen_tool_ids: set[str] = set()

    try:
        conn = sqlite3.connect(str(db_path))
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()

        for tool_ref in tools:
            candidates = [tool_ref]
            if "/" in tool_ref:
                candidates.append(tool_ref.split("/")[-1])
            pattern = f"%{tool_ref}%"

            row = None
            for cand in candidates:
                cursor.execute(
                    """
                    SELECT tool_id, name, execution_info
                    FROM tools
                    WHERE LOWER(tool_id) = LOWER(?)
                       OR LOWER(name) = LOWER(?)
                    LIMIT 1
                    """,
                    (cand, cand),
                )
                row = cursor.fetchone()
                if row:
                    break

            if not row:
                cursor.execute(
                    """
                    SELECT tool_id, name, execution_info
                    FROM tools
                    WHERE LOWER(tool_id) LIKE LOWER(?)
                       OR LOWER(name) LIKE LOWER(?)
                    ORDER BY CASE
                      WHEN LOWER(tool_id) LIKE LOWER(?) THEN 0
                      ELSE 1
                    END
                    LIMIT 1
                    """,
                    (pattern, pattern, pattern),
                )
                row = cursor.fetchone()

            if not row:
                continue

            tool_id = str(row["tool_id"] or "").strip()
            if not tool_id or tool_id in seen_tool_ids:
                continue
            seen_tool_ids.add(tool_id)

            raw_info = row["execution_info"]
            if not raw_info:
                continue
            try:
                exec_info = json.loads(raw_info) if isinstance(raw_info, str) else raw_info
            except Exception:
                continue
            if not isinstance(exec_info, dict):
                continue

            requires_gpu = bool(exec_info.get("gpu", False))
            memory_gb = _parse_memory_gb(exec_info.get("memory"))
            if requires_gpu:
                gpu_required = True
            if memory_gb is not None:
                max_memory_gb = max(max_memory_gb, memory_gb)

            tool_runtime_hints.append(
                {
                    "tool_id": tool_id,
                    "tool_name": row["name"] or tool_id,
                    "gpu": requires_gpu,
                    "memory_gb": memory_gb,
                    "container_image": exec_info.get("image"),
                    "runtime_type": exec_info.get("type"),
                }
            )
    except Exception as exc:
        log.warning(f"[NextflowSearch] Hardware requirement lookup failed: {exc}")
        return None
    finally:
        try:
            if conn is not None:
                conn.close()
        except Exception:
            pass

    if not tool_runtime_hints:
        return None

    return {
        "gpu_required": gpu_required,
        "min_memory_gb": round(max_memory_gb, 2) if max_memory_gb > 0 else None,
        "tools_analyzed": len(tool_runtime_hints),
        "tool_runtime_hints": tool_runtime_hints[:12],
        "source": "ai_tool_db.execution_info",
    }


def _parse_nextflow_steps(nf_filename: str) -> Dict[str, Any]:
    """Parse step names from a Nextflow .nf file for display in the workflow viewer.

    Tries two strategies:
    1. Comment header with numbered steps (e.g. ``* 1. Import Movies``)
    2. UPPERCASE process calls in the workflow body
    """
    steps: Dict[str, Any] = {}
    if not nf_filename:
        return steps
    try:
        backend_root = FilePath(__file__).resolve().parents[5]
        nf_path = FilePath(nf_filename)
        if nf_path.is_absolute():
            abs_path = nf_path
        else:
            # Try simple path first, then the same resolution hierarchy as _resolve_nextflow_path
            candidates: list[FilePath] = [backend_root / nf_filename]
            raw = str(nf_filename)
            nfcore_root = backend_root / "biomni_workflows" / "nextflow_nfcore"
            if raw.startswith("nextflow_nfcore/"):
                rest = raw.split("nextflow_nfcore/", 1)[1].strip("/")
                candidates += [
                    nfcore_root / rest,
                    nfcore_root / rest / "main.nf",
                    nfcore_root / "subworkflows" / rest,
                    nfcore_root / "subworkflows" / rest / "main.nf",
                ]
            else:
                candidates += [
                    nfcore_root / nf_filename,
                    nfcore_root / "subworkflows" / nf_filename,
                ]
            abs_path = next((c for c in candidates if c.exists()), candidates[0])
        if not abs_path.exists():
            return steps
        content = abs_path.read_text(encoding="utf-8", errors="replace")

        # Strategy 1: numbered steps in comment block ("* 1. Import Movies")
        comment_steps = re.findall(r'\*\s+(\d+)\.\s+(.+)', content)
        if comment_steps:
            for raw_num, raw_name in comment_steps:
                idx = int(raw_num) - 1
                clean = raw_name.strip().rstrip('*').strip()
                if not clean:
                    continue
                tool_id = re.sub(r'[^A-Za-z0-9]+', '_', clean.upper()).strip('_')
                steps[str(idx)] = {
                    "id": str(idx),
                    "name": clean,
                    "tool_id": tool_id,
                    "annotation": clean,
                    "description": "",
                    "type": "tool",
                    "parameters": {},
                    "inputs": {},
                }
            if steps:
                return steps

        # Strategy 2: UPPERCASE_CALL(...) process invocations in workflow body
        in_workflow = False
        idx = 0
        for line in content.splitlines():
            stripped = line.strip()
            if re.match(r'^workflow\b', stripped):
                in_workflow = True
                continue
            if in_workflow:
                m = re.match(r'([A-Z][A-Z0-9_]+)\s*\(', stripped)
                if m:
                    proc = m.group(1)
                    human = proc.replace('_', ' ').title()
                    steps[str(idx)] = {
                        "id": str(idx),
                        "name": human,
                        "tool_id": proc,
                        "annotation": human,
                        "description": "",
                        "type": "tool",
                        "parameters": {},
                        "inputs": {},
                    }
                    idx += 1
    except Exception as exc:
        log.warning(f"[NextflowSteps] Failed to parse steps from {nf_filename}: {exc}")
    return steps


# Internal params to skip — not user-facing
_NF_SKIP_PARAMS = {
    "mock_mode", "use_cryosparc", "cryosparc_license", "cryosparc_host",
    "cryosparc_port", "cryosparc_lane", "dose_per_frame",
    "ctf_fitting_resolution_min", "ctf_fitting_resolution_max",
    "particle_box_size", "outdir", "project_name", "sample_type",
    "motion_correction_dose_weighting", "enable_low_memory_mode",
}


def _parse_nextflow_params(nf_filename: str) -> Dict[str, Any]:
    """Parse user-facing params from a Nextflow .nf file.

    Returns ``{"parameters": {name: value, ...}, "parameter_metadata": {name: {...}, ...}}``.
    """
    parameters: Dict[str, Any] = {}
    parameter_metadata: Dict[str, Any] = {}
    if not nf_filename:
        return {"parameters": parameters, "parameter_metadata": parameter_metadata}
    try:
        backend_root = FilePath(__file__).resolve().parents[5]
        # Try multiple candidate paths (DB paths omit biomni_workflows/ prefix)
        _candidates = [
            FilePath(nf_filename) if FilePath(nf_filename).is_absolute() else backend_root / nf_filename,
            backend_root / "biomni_workflows" / nf_filename,
            backend_root / "biomni_workflows" / "nextflow_nfcore" / nf_filename,
        ]
        abs_path = next((c for c in _candidates if c.exists()), None)
        if abs_path is None:
            return {"parameters": parameters, "parameter_metadata": parameter_metadata}
        content = abs_path.read_text(encoding="utf-8", errors="replace")

        # Match: params.name = value  // optional comment
        param_re = re.compile(
            r'^params\.([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*([^\n/]+?)\s*(?://\s*(.+))?$',
            re.MULTILINE,
        )
        for m in param_re.finditer(content):
            name = m.group(1).strip()
            raw_val = m.group(2).strip()
            comment = (m.group(3) or "").strip()

            if name in _NF_SKIP_PARAMS:
                continue

            # Determine value and type
            val: Any
            ptype: str
            if raw_val.lower() == "null":
                val = None
                if name.endswith("_path") or name.endswith("_ref"):
                    ptype = "file"
                else:
                    ptype = "string"
            elif raw_val.lower() in ("true", "false"):
                val = raw_val.lower() == "true"
                ptype = "boolean"
            elif re.fullmatch(r"-?\d+", raw_val):
                val = int(raw_val)
                ptype = "integer"
            elif re.fullmatch(r"-?\d+\.\d+", raw_val):
                val = float(raw_val)
                ptype = "float"
            elif raw_val.startswith(("'", '"')):
                val = raw_val.strip("'\"")
                ptype = "string"
            else:
                val = raw_val
                ptype = "string"

            # Level — any param with null value is required (user must supply it)
            _RECOMMENDED_PARAMS = {"spherical_aberration", "total_dose", "symmetry"}
            if val is None:
                level = "required"
            elif name in _RECOMMENDED_PARAMS:
                level = "recommended"
            else:
                level = "optional"

            # Label: use comment or prettify key
            label = comment if comment else name.replace("_", " ").title()

            parameters[name] = val
            parameter_metadata[name] = {"type": ptype, "label": label, "level": level}

    except Exception as exc:
        log.warning(f"[NextflowParams] Failed to parse params from {nf_filename}: {exc}")
    return {"parameters": parameters, "parameter_metadata": parameter_metadata}


@router.post(
    "/api/ai_assistant/search_nextflow_workflow",
    summary="Search Nextflow workflow database (no LLM required)."
)
def search_nextflow_workflow(
    request: NextflowSearchRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Lightweight endpoint: search workflow database and return Nextflow path.
    Does NOT require AI assistant or LLM API key.
    """
    user_intent = request.user_intent or request.request_text or ""
    if not user_intent:
        raise HTTPException(status_code=400, detail="user_intent is required")

    if not _workflow_search:
        raise HTTPException(status_code=503, detail="Workflow search not available")

    try:
        # ── Chain pre-check (Step 0) ─────────────────────────────────────────
        # Before searching individual Nextflow workflows, check whether a
        # curated multi-step chain matches the query.  Chains outrank any
        # single-workflow match because they represent authoritative, vetted
        # multi-tool pipelines for complex analyses.
        # search_chains returns List[WorkflowChain] already filtered at ≥0.15;
        # we only act when at least one chain is returned (score already enough
        # to be meaningful — chain match is always preferred over single wf).
        chain_candidates = _workflow_search.search_chains(user_intent)
        if chain_candidates:
            best_chain = chain_candidates[0]
            log.info(
                f"[search_nextflow_workflow] Chain match '{best_chain.name}' — returning chain payload"
            )
            return {
                "success": True,
                "workflow_type": "chain",
                "chain_name": best_chain.name,
                "chain_display_name": best_chain.display_name,
                "chain_domain": best_chain.domain,
                "chain_description": best_chain.description,
                "chain_steps": best_chain.steps,   # already List[dict]
                "chain_connections": best_chain.connections,
                "required_inputs": best_chain.required_inputs,
                "expected_outputs": best_chain.expected_outputs,
                "all_chains": [
                    {"name": c.name, "display_name": c.display_name}
                    for c in chain_candidates[:5]
                ],
                "source": "chain_lookup",
                "confidence": 9,
                "message": f"Multi-step pipeline: {best_chain.display_name}",
                "note": best_chain.description,
                "execution_engine": "chain",
                "citations": [],
                "methods_section": None,
                "parameter_recommendations": {},
                "pilot_run_suggested": False,
            }
        # ── Individual Nextflow workflow search ──────────────────────────────
        results = _workflow_search.search(user_intent, limit=5, include_workflow_json=False)
        if not results:
            return {"success": False, "message": "No matching workflows found"}

        def _is_executable_nextflow_match(match: Any) -> bool:
            if getattr(match, "format", "") != "nextflow":
                return False
            filename = (getattr(match, "filename", "") or "").lower()
            name = (getattr(match, "name", "") or "").lower()
            tags = [str(t).lower() for t in (getattr(match, "tags", []) or [])]

            # Exclude known non-entry nf-core subworkflow library paths.
            if filename.startswith("nfcore/subworkflows/"):
                return False
            if filename.startswith("nf-core-modules/"):
                return False
            if "nf-core-modules/subworkflows/" in filename:
                return False
            if "/nf-core-modules/subworkflows/" in filename:
                return False
            if "/nfcore/subworkflows/" in filename:
                return False
            if "subworkflow" in name:
                return False
            if any("subworkflow" in t for t in tags):
                return False

            return filename.endswith("/main.nf") or (
                filename.endswith(".nf") and ("/workflows/" in filename or "biomni_nf/" in filename)
            )

        runnable_keys = _load_runnable_nextflow_keys()

        def _is_runnable_nextflow_match(match: Any) -> bool:
            if not runnable_keys:
                return True
            key = _nextflow_workflow_key((getattr(match, "filename", "") or ""))
            return bool(key and key in runnable_keys)

        best = results[0]
        if best.format == "nextflow" and not _is_executable_nextflow_match(best):
            executable = next(
                (r for r in results if _is_executable_nextflow_match(r) and _is_runnable_nextflow_match(r)),
                None,
            )
            if not executable:
                executable = next((r for r in results if _is_executable_nextflow_match(r)), None)
            if executable:
                best = executable
            else:
                fallback = next((r for r in results if getattr(r, "format", "") != "nextflow"), None)
                if fallback:
                    best = fallback
        elif best.format == "nextflow" and not _is_runnable_nextflow_match(best):
            runnable_executable = next(
                (r for r in results if _is_executable_nextflow_match(r) and _is_runnable_nextflow_match(r)),
                None,
            )
            if runnable_executable:
                best = runnable_executable

        # Helper: resolve a DB filename to an absolute path, checking biomni_workflows/ prefix too
        def _nf_file_exists(fname: str) -> bool:
            if not fname:
                return False
            _root = FilePath(__file__).resolve().parents[5]
            for candidate in [
                FilePath(fname) if FilePath(fname).is_absolute() else _root / fname,
                _root / "biomni_workflows" / fname,
                _root / "biomni_workflows" / "nextflow_nfcore" / fname,
            ]:
                if candidate.exists():
                    return True
            return False

        # Skip phantom DB entries whose .nf file doesn't exist on disk
        if best.format == "nextflow" and best.filename and not _nf_file_exists(best.filename):
            _disk_best = next(
                (r for r in results if r is not best
                 and _is_executable_nextflow_match(r)
                 and getattr(r, "filename", "")
                 and _nf_file_exists(r.filename)),
                None,
            )
            if _disk_best:
                best = _disk_best

        workflow_tools = getattr(best, "tools", []) or []
        hardware_requirements = _collect_workflow_hardware_requirements(workflow_tools)
        scientific_rationale = _build_scientific_rationale_from_tools(workflow_tools)

        # Build parameter_metadata from scientific_rationale parameter_hints
        _search_param_keys = [
            h.get("param", "")
            for h in (scientific_rationale or {}).get("parameter_hints", [])
            if h.get("param", "")
        ]
        _search_parameter_metadata = _build_parameter_metadata_from_tools(_search_param_keys)

        # Parse user-facing params from the .nf file for Nextflow workflows
        _nf_parsed = _parse_nextflow_params(best.filename) if best.format == "nextflow" and best.filename else {}
        _wf_parameters = _nf_parsed.get("parameters", {})
        _wf_parameter_metadata = _nf_parsed.get("parameter_metadata", None) or _search_parameter_metadata

        # Build required/optional param lists consumed by nextflow-workflow-viewer.tsx
        _req_params: list = []
        _opt_params: list = []
        for _pname, _pmeta in (_wf_parameter_metadata.items() if isinstance(_wf_parameter_metadata, dict) else []):
            _entry = {
                "name": _pname,
                "label": _pmeta.get("label", _pname.replace("_", " ").title()),
                "description": _pmeta.get("label", _pname.replace("_", " ").title()),
                "default": _wf_parameters.get(_pname),
            }
            if _pmeta.get("level") == "required":
                _req_params.append(_entry)
            else:
                _opt_params.append(_entry)

        _prereq_validation = None
        if _req_params:
            _prereq_validation = {
                "requirements": {
                    "parameters": [
                        {"stepId": "workflow", "paramName": p["name"], "optional": False, "defaultValue": None}
                        for p in _req_params
                    ]
                },
                "analysis": {
                    "missingInputs": [],
                    "missingParameters": [{"stepId": "workflow", "paramName": p["name"]} for p in _req_params],
                    "inputMappings": [],
                },
            }

        _return_dict: dict = {
            "success": True,
            "workflow_type": best.format,
            "nextflow_path": best.filename if best.format == "nextflow" else None,
            "workflow_name": best.name,
            "format": best.format,
            "source": "template_reuse",
            "confidence": int(best.score),
            "message": f"Found workflow: {best.name}",
            "description": best.description,
            "domain": best.domain,
            "step_count": best.step_count,
            "scientific_rationale": scientific_rationale,
            "parameter_metadata": _wf_parameter_metadata,
            "required_params": _req_params,
            "optional_params": _opt_params,
            "workflow_ga": {
                "name": best.name,
                "description": best.description,
                "annotation": best.description,
                "tags": best.tags,
                "format": best.format,
                "nextflow_path": best.filename if best.format == "nextflow" else None,
                "workflow_type": best.format,
                "steps": _parse_nextflow_steps(best.filename) if best.format == "nextflow" and best.filename else {},
                "parameters": _wf_parameters,
                "parameter_metadata": _wf_parameter_metadata,
                "required_params": _req_params,
                "optional_params": _opt_params,
                "hardware_requirements": hardware_requirements,
                "scientific_rationale": scientific_rationale,
            },
            "hardware_requirements": hardware_requirements,
            "datasets_assigned": False,
            "generated_parameters": _req_params + _opt_params,
            "validation": {"is_valid": True, "issues": [], "warnings": [], "suggestions": []},
            "tool_installation": {"success": True, "message": "Nextflow workflow", "failed_tools": []}
        }
        if _prereq_validation:
            _return_dict["prerequisitesValidation"] = _prereq_validation
        return _return_dict
    except Exception as e:
        log.error(f"Nextflow workflow search failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))


def get_ai_assistant(trans) -> Optional[AIAssistant]:
    """Get or create AI Assistant instance."""
    global _ai_assistant_instance

    log.info(f"[DEBUG] get_ai_assistant called, AI_AVAILABLE={AI_AVAILABLE}")
    log.info(f"[DEBUG] _ai_assistant_instance is None: {_ai_assistant_instance is None}")

    if not AI_AVAILABLE:
        log.warning("[DEBUG] AI modules not available - import failed")
        return None

    if _ai_assistant_instance is None:
        try:
            # Get AI configuration from Galaxy config using the configuration loader
            log.info("[DEBUG] Accessing trans.app...")
            app = trans.app
            log.info(f"[DEBUG] Got app: {app}")

            log.info("[DEBUG] Getting enable_ai_assistant config...")
            # Check environment variable directly as fallback
            import os
            ai_enabled = getattr(app.config, 'enable_ai_assistant', os.environ.get('GALAXY_CONFIG_ENABLE_AI_ASSISTANT', 'false').lower() == 'true')
            log.info(f"[DEBUG] enable_ai_assistant config value: {ai_enabled}")

            if not ai_enabled:
                log.warning("[DEBUG] AI Assistant not enabled in config")
                return None

            # Use the proper AI configuration loader
            log.info("[DEBUG] Importing configure_ai_assistant...")
            from galaxy.config.ai_config import configure_ai_assistant
            log.info("[DEBUG] Calling configure_ai_assistant...")
            # Explicitly set enable_ai_assistant in config_dict
            # Also force anthropic provider if ANTHROPIC_API_KEY is set but provider defaults to openai
            import os as _os
            config_dict = dict(app.config.__dict__)
            config_dict['enable_ai_assistant'] = True
            if _os.environ.get('ANTHROPIC_API_KEY') and not _os.environ.get('GALAXY_AI_LLM_PROVIDER'):
                config_dict['ai_llm_provider'] = 'anthropic'
                config_dict['ai_llm_api_key'] = _os.environ['ANTHROPIC_API_KEY']
            ai_config = configure_ai_assistant(config_dict, app.config.config_dir)
            log.info(f"[DEBUG] configure_ai_assistant returned: {ai_config}")

            if not ai_config:
                log.warning("AI Assistant enabled but configuration failed")
                return None

            log.info("[DEBUG] About to create AIAssistant instance...")
            # DO NOT pass galaxy_app to avoid triggering toolbox loading which causes OOM
            # All tool access is via database queries, not galaxy_app.toolbox
            _ai_assistant_instance = AIAssistant(ai_config, galaxy_app=None)
            log.info("[DEBUG] AIAssistant instance created!")
            log.info("AI Assistant initialized successfully (without galaxy_app to avoid OOM)")

        except Exception as e:
            log.error(f"Failed to initialize AI Assistant: {e}")
            import traceback
            log.error(traceback.format_exc())
            return None

    return _ai_assistant_instance


# Pydantic models for API requests/responses
class AIRequestModel(BaseModel):
    """Model for AI assistant requests."""
    request_text: str = Field(..., description="Natural language research request")
    context: Optional[Dict[str, Any]] = Field(None, description="Additional context")
    available_datasets: Optional[List[Dict[str, Any]]] = Field(None, description="Available datasets")
    preferred_tools: Optional[List[str]] = Field(None, description="Preferred tools")
    constraints: Optional[Dict[str, Any]] = Field(None, description="Execution constraints")


class AIResponseModel(BaseModel):
    """Model for AI assistant responses."""
    request_id: str
    parsed_intent: str
    decomposed_tasks: List[Dict[str, Any]]
    tool_recommendations: List[Dict[str, Any]]
    workflow_template: Optional[Dict[str, Any]]
    workflow_recommendations: List[Dict[str, Any]] = []
    confidence: float
    execution_plan: Optional[str]
    warnings: List[str]


# Citation models
class CitationModel(BaseModel):
    """Model for tool citations."""
    tool_id: str = Field(..., description="Tool identifier")
    tool_name: str = Field(..., description="Tool display name")
    doi: Optional[str] = Field(None, description="Digital Object Identifier")
    pmid: Optional[str] = Field(None, description="PubMed ID")
    title: str = Field(..., description="Citation title")
    authors: List[str] = Field(default_factory=list, description="Author list")
    year: Optional[int] = Field(None, description="Publication year")
    journal: Optional[str] = Field(None, description="Journal name")
    formatted_apa: str = Field("", description="APA formatted citation")
    formatted_short: str = Field("", description="Short citation format")
    formatted_bibtex: str = Field("", description="BibTeX format")


class MethodsSectionModel(BaseModel):
    """Model for auto-generated methods section."""
    text: str = Field(..., description="Methods section text")
    style: str = Field("short", description="Citation style used")
    tools_cited: List[str] = Field(default_factory=list, description="Tools with citations")
    tools_missing_citations: List[str] = Field(default_factory=list, description="Tools without citations")


class ParameterRecommendationModel(BaseModel):
    """Model for parameter recommendations."""
    parameter_name: str = Field(..., description="Parameter name")
    recommended_value: Any = Field(..., description="Recommended value")
    current_value: Optional[Any] = Field(None, description="Current/default value")
    confidence: float = Field(0.8, description="Recommendation confidence")
    source: str = Field("best_practice", description="Source: benchmark, protocol, best_practice")
    reason: Optional[str] = Field(None, description="Reason for recommendation")


# Pilot run models
class TuningConfigModel(BaseModel):
    """Model for tuning configuration."""
    pilot_fraction: float = Field(0.1, ge=0.05, le=0.3, description="Fraction of data for pilot")
    sampling_strategy: str = Field("stratified", description="Sampling strategy")
    strata_column: Optional[str] = Field(None, description="Column for stratified sampling")
    min_pilot_samples: int = Field(3, ge=1, description="Minimum pilot samples")
    max_pilot_samples: int = Field(50, ge=1, description="Maximum pilot samples")


class StartPilotRequest(BaseModel):
    """Request to start a pilot run."""
    workflow_id: Optional[str] = Field(None, description="Existing Galaxy workflow ID")
    workflow_definition: Optional[Dict[str, Any]] = Field(None, description="Workflow definition JSON (.ga format)")
    total_samples: int = Field(..., description="Total number of samples")
    config: Optional[TuningConfigModel] = Field(None, description="Tuning configuration")
    sample_ids: Optional[List[str]] = Field(None, description="Sample IDs if available")
    inputs: Optional[List[Dict[str, Any]]] = Field(None, description="Input datasets for the workflow")
    history_id: Optional[str] = Field(None, description="History ID to use (creates sandbox if not provided)")


class PilotStatusResponse(BaseModel):
    """Response for pilot run status."""
    pilot_id: str
    status: str  # 'pending', 'running', 'complete', 'failed'
    progress: float = 0.0
    runtime_seconds: Optional[float] = None
    peak_memory_gb: Optional[float] = None
    quality_metrics: Optional[Dict[str, float]] = None
    error_message: Optional[str] = None


class FullRunEstimateResponse(BaseModel):
    """Response for full run estimation."""
    estimated_runtime_seconds: float
    estimated_runtime_display: str
    estimated_memory_gb: float
    estimated_cost_usd: Optional[float] = None
    confidence: float = 0.8
    scaling_factors: Dict[str, float] = Field(default_factory=dict)


class BibTeXExportRequest(BaseModel):
    """Request to export citations as BibTeX."""
    workflow_ga: Dict[str, Any] = Field(..., description="Galaxy workflow JSON")
    include_all: bool = Field(True, description="Include all tools or only cited ones")


# Enhanced workflow generation response
class WorkflowGenerationResponse(BaseModel):
    """Enhanced response for workflow generation with citations."""
    success: bool
    workflow_ga: Optional[Dict[str, Any]] = None
    source: Optional[str] = None  # template_reuse, template_adapted, from_scratch
    confidence: float = 0.0
    message: str = ""

    # Citation fields
    citations: List[CitationModel] = Field(default_factory=list)
    methods_section: Optional[MethodsSectionModel] = None

    # Pilot run suggestion
    pilot_run_suggested: bool = False
    tuning_config: Optional[TuningConfigModel] = None

    # Parameter recommendations
    parameter_recommendations: Dict[str, ParameterRecommendationModel] = Field(default_factory=dict)


# In-memory storage for pilot runs (would be database in production)
_pilot_runs: Dict[str, Dict[str, Any]] = {}


@router.get(
    "/api/ai_assistant/test_init",
    summary="Test AI Assistant initialization only"
)
def test_ai_init(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Test if AI Assistant can be initialized without crashing."""
    try:
        ai_assistant = get_ai_assistant(trans)
        if ai_assistant:
            return {"success": True, "message": "AI Assistant initialized successfully"}
        else:
            return {"success": False, "message": "AI Assistant not available"}
    except Exception as e:
        import traceback
        return {
            "success": False,
            "error": str(e),
            "traceback": traceback.format_exc()
        }

@router.get(
    "/api/ai_assistant/status",
    summary="Get AI Assistant status and configuration."
)
def get_ai_status(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Get AI Assistant status and configuration - lightweight check without full initialization."""

    if not AI_AVAILABLE:
        return {
            "available": False,
            "error": "AI Assistant components not installed",
            "ready": False
        }

    # Don't initialize AI Assistant for status check - just validate configuration
    app = trans.app
    ai_enabled = getattr(app.config, 'enable_ai_assistant', False)

    if not ai_enabled:
        return {
            "available": AI_AVAILABLE,
            "enabled": False,
            "ready": False,
            "error": "AI Assistant not enabled in configuration"
        }

    # Check if we can configure AI Assistant (without full initialization)
    from galaxy.config.ai_config import configure_ai_assistant
    try:
        ai_config = configure_ai_assistant(app.config.__dict__, app.config.config_dir)
        if not ai_config:
            return {
                "available": AI_AVAILABLE,
                "enabled": ai_enabled,
                "ready": False,
                "error": "AI Assistant configuration failed"
            }

        api_key_configured = bool(ai_config.llm_api_key)

        return {
            "available": AI_AVAILABLE,
            "enabled": ai_enabled,
            "api_key_configured": api_key_configured,
            "ready": True,
            "llm_provider": ai_config.llm_provider,
            "llm_model": ai_config.llm_model
        }
    except Exception as e:
        log.error(f"Status check error: {e}")
        return {
            "available": AI_AVAILABLE,
            "enabled": ai_enabled,
            "ready": False,
            "error": f"Configuration error: {str(e)}"
        }


@router.post(
    "/api/ai_assistant/process_request",
    summary="Process a natural language research request."
)
def process_research_request(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> AIResponseModel:
    """Process a natural language research request."""
    
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    try:
        # Create UserRequest object
        user_request = UserRequest(
            user_id=str(trans.user.id) if trans.user else "anonymous",
            request_text=request.request_text,
            context=request.context,
            available_datasets=request.available_datasets,
            preferred_tools=request.preferred_tools,
            constraints=request.constraints
        )
        
        # Process the request
        ai_response = ai_assistant.process_request(user_request)
        
        # Convert to API response format
        return AIResponseModel(
            request_id=ai_response.request_id,
            parsed_intent=ai_response.parsed_intent.value,
            decomposed_tasks=[
                {
                    "id": task.id,
                    "name": task.name,
                    "description": task.description,
                    "task_type": task.task_type.value,
                    "intent_type": task.intent_type.value,
                    "confidence": task.confidence,
                    "estimated_duration": task.estimated_duration
                }
                for task in ai_response.decomposed_tasks
            ],
            tool_recommendations=[
                {
                    "tool_id": rec.tool.id,
                    "tool_name": rec.tool.name,
                    "confidence": rec.confidence,
                    "reasoning": rec.reasoning,
                    "estimated_runtime": rec.estimated_runtime
                }
                for rec in ai_response.tool_recommendations
            ],
            workflow_template=(
                _workflow_to_dict(ai_response.workflow_template)
                if ai_response.workflow_template else None
            ),
            workflow_recommendations=getattr(ai_response, 'workflow_recommendations', []),
            confidence=ai_response.confidence,
            execution_plan=ai_response.execution_plan,
            warnings=ai_response.warnings
        )
        
    except Exception as e:
        log.error(f"Error processing AI request: {e}")
        raise HTTPException(status_code=500, detail=f"Error processing request: {str(e)}")


@router.post(
    "/api/ai_assistant/create_workflow",
    summary="Create a Galaxy workflow from AI-generated template."
)
def create_workflow_from_ai(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Create a Galaxy workflow from AI-generated template."""
    
    # Check if user is authenticated
    if not trans.user:
        raise HTTPException(
            status_code=401, 
            detail="Authentication required. Please log in to Galaxy to create workflows."
        )
    
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    try:
        # Process the request to get workflow template
        user_request = UserRequest(
            user_id=str(trans.user.id),
            request_text=request.request_text,
            context=request.context,
            available_datasets=request.available_datasets,
            preferred_tools=request.preferred_tools,
            constraints=request.constraints
        )
        
        ai_response = ai_assistant.process_request(user_request)
        
        if not ai_response.workflow_template:
            raise HTTPException(status_code=400, detail="Could not generate workflow template")
        
        # Convert to Galaxy workflow format
        galaxy_workflow = ai_assistant.workflow_generator.export_to_galaxy_format(
            ai_response.workflow_template
        )
        
        # Save the workflow to Galaxy's workflow system using the standard API approach
        try:
            # Import required classes
            from galaxy.managers.workflows import WorkflowCreateOptions
            
            # Use the workflow_contents_manager to create workflow
            workflow_contents_manager = trans.app.workflow_contents_manager
            
            # Normalize the workflow format
            raw_workflow_description = workflow_contents_manager.normalize_workflow_format(trans, galaxy_workflow)
            
            # Create workflow creation options
            workflow_create_options = WorkflowCreateOptions(
                publish=False,
                importable=False,
                import_tools=False
            )
            
            # Use the workflow_contents_manager to build workflow from description
            created_workflow = workflow_contents_manager.build_workflow_from_raw_description(
                trans,
                raw_workflow_description,
                workflow_create_options
            )
            
            # Get workflow information
            stored_workflow = created_workflow.stored_workflow
            workflow = created_workflow.workflow
            workflow_id = stored_workflow.id
            encoded_id = trans.security.encode_id(workflow_id)
            
            return {
                "workflow_id": encoded_id,
                "workflow_name": stored_workflow.name,
                "message": f"Workflow '{stored_workflow.name}' created and saved successfully!",
                "workflow_url": f"/workflow/editor?id={encoded_id}",
                "note": "Workflow saved to your workflows list - check Workflow menu → My Workflows",
                "status": "success",
                "number_of_steps": len(workflow.steps) if workflow.steps else 0
            }
            
        except Exception as save_error:
            import traceback
            error_details = traceback.format_exc()
            log.error(f"Failed to save workflow to Galaxy system: {save_error}")
            log.error(f"Full error traceback: {error_details}")
            
            # Return detailed error for debugging
            return {
                "workflow": galaxy_workflow,
                "message": "Workflow generated but could not be saved",
                "note": "The AI successfully generated a workflow, but there was an error saving it to Galaxy",
                "error": f"Save error: {str(save_error)}",
                "error_details": error_details,
                "status": "partial_success"
            }
        
    except Exception as e:
        log.error(f"Error creating workflow: {e}")
        raise HTTPException(status_code=500, detail=f"Error creating workflow: {str(e)}")


@router.post(
    "/api/ai_assistant/get_workflow_recommendations",
    summary="Get workflow recommendations based on user request."
)
def get_workflow_recommendations(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Get multiple workflow recommendations for user request."""
    
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")
    
    try:
        # Create UserRequest object
        user_request = UserRequest(
            user_id=str(trans.user.id) if trans.user else "anonymous",
            request_text=request.request_text,
            context=request.context,
            available_datasets=request.available_datasets,
            preferred_tools=request.preferred_tools,
            constraints=request.constraints
        )
        
        # Get workflow recommendations
        recommendations = ai_assistant.workflow_generator.get_workflow_recommendations(user_request)
        
        return {
            "recommendations": recommendations,
            "total_options": len(recommendations),
            "status": "success"
        }
        
    except Exception as e:
        log.error(f"Error getting workflow recommendations: {e}")
        raise HTTPException(status_code=500, detail=f"Error getting recommendations: {str(e)}")


@router.post(
    "/api/ai_assistant/generate_workflow",
    summary="Generate workflow using unified search-first approach."
)
def generate_workflow_unified(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Generate workflow using unified search-first approach.

    This endpoint uses the complete unified architecture:
    1. Search existing templates first (WorkflowSearchRAG)
    2. If high confidence (>0.8): Reuse template
    3. If medium confidence (0.5-0.8): Adapt template
    4. If low confidence (<0.5): Generate from scratch with tool constraint
    5. Always assign datasets via WorkflowDatasetSelector
    """

    import sys
    print("[DEBUG] generate_workflow_unified endpoint called", file=sys.stderr, flush=True)
    print(f"[DEBUG] Request text: {request.request_text}", file=sys.stderr, flush=True)

    print("[DEBUG] About to call get_ai_assistant...", file=sys.stderr, flush=True)
    ai_assistant = get_ai_assistant(trans)
    print(f"[DEBUG] get_ai_assistant returned: {ai_assistant}", file=sys.stderr, flush=True)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        # Extract uploaded dataset IDs if provided
        uploaded_datasets = None
        if request.available_datasets:
            uploaded_datasets = [ds.get('id') for ds in request.available_datasets if ds.get('id')]

        user_id = str(trans.user.id) if getattr(trans, "user", None) else None

        # Extract session_id from request context (threaded from frontend via context.session_id)
        session_id = (
            (request.context or {}).get("session_id")
            or user_id
            or "anon"
        )

        # ── N4: WorkflowSession — inject prior session context into user_intent ─
        # Load the active session for this user/session.  If prior steps exist,
        # prepend a compact summary so the backend knows the active workflow state
        # (enables "change the padj to 0.01" to find the right step without a
        # full re-query from the frontend).
        effective_intent = request.request_text
        if _session_store:
            try:
                sess = _session_store.get(session_id)
                if sess and sess.steps:
                    last_step = sess.steps[-1]
                    prior_ctx = (
                        f"[Active pipeline: {last_step.workflow_name}, "
                        f"step {last_step.index + 1}, status={last_step.status}, "
                        f"params={list(last_step.params.keys())}] "
                    )
                    effective_intent = prior_ctx + request.request_text
                    log.info(
                        "[generate_workflow] Session %s has %d step(s); injected prior context",
                        session_id, len(sess.steps),
                    )
            except Exception as _se:
                log.debug("[generate_workflow] Session lookup failed (non-fatal): %s", _se)

        # Route through LangGraph pipeline when BIOMATE_USE_LANGGRAPH=true.
        # The pipeline wraps generate_workflow_unified with tracing + checkpointing.
        # Falls back transparently to direct call on any failure.
        use_langgraph = _os.getenv("BIOMATE_USE_LANGGRAPH", "false").lower() in ("1", "true", "yes")
        if use_langgraph:
            result = ai_assistant.run_via_pipeline(
                user_intent=effective_intent,
                session_id=session_id,
                user_id=user_id,
                uploaded_datasets=uploaded_datasets,
            )
        else:
            # Generate workflow using unified approach (default / stable path)
            result = ai_assistant.generate_workflow_unified(
                user_intent=effective_intent,
                uploaded_datasets=uploaded_datasets,
                user_id=user_id,
            )

        # Chain responses carry a different payload (no workflow_ga / citations).
        # Return them directly so the frontend WorkflowChainPlan component can render.
        if result.get('workflow_type') == 'chain':
            return {
                'success': True,
                'workflow_type': 'chain',
                'chain_name': result.get('chain_name'),
                'chain_display_name': result.get('chain_display_name'),
                'chain_domain': result.get('chain_domain'),
                'chain_description': result.get('chain_description'),
                'chain_steps': result.get('chain_steps', []),
                'chain_connections': result.get('chain_connections', []),
                'required_inputs': result.get('required_inputs', []),
                'expected_outputs': result.get('expected_outputs', []),
                'all_chains': result.get('all_chains', []),
                'source': 'chain_lookup',
                'confidence': result.get('confidence', 9),
                'message': result.get('message', ''),
                'note': result.get('note', ''),
                'execution_engine': 'chain',
                'citations': [],
                'methods_section': None,
                'parameter_recommendations': {},
                'pilot_run_suggested': False,
            }

        if result['success']:
            # Process citations from the result
            citations = []
            raw_citations = result.get('citations', [])
            for cit_data in raw_citations:
                citation_info = cit_data.get('citation', {})
                citations.append(CitationModel(
                    tool_id=cit_data.get('tool_id', ''),
                    tool_name=cit_data.get('tool_name', ''),
                    doi=citation_info.get('doi'),
                    pmid=citation_info.get('pmid'),
                    title=citation_info.get('title', ''),
                    authors=citation_info.get('authors', []),
                    year=citation_info.get('year'),
                    journal=citation_info.get('journal'),
                    formatted_apa=citation_info.get('formatted_apa', ''),
                    formatted_short=citation_info.get('formatted_short', ''),
                    formatted_bibtex=citation_info.get('formatted_bibtex', '')
                ))

            # Build methods section model if available
            methods_section = None
            if result.get('methods_section'):
                methods_section = MethodsSectionModel(
                    text=result['methods_section'],
                    style="short",
                    tools_cited=[c.tool_id for c in citations],
                    tools_missing_citations=[]  # Could be populated from result
                )

            # Process parameter recommendations
            param_recommendations = {}
            for param_data in result.get('generated_parameters', []):
                if param_data.get('parameters'):
                    for param_name, param_value in param_data['parameters'].items():
                        param_recommendations[f"{param_data['tool_id']}:{param_name}"] = ParameterRecommendationModel(
                            parameter_name=param_name,
                            recommended_value=param_value,
                            confidence=param_data.get('confidence', 0.8),
                            source="llm_generated",
                            reason=param_data.get('reasoning', '')
                        )

            # ============================================================================
            # Enhanced Pilot Run Suggestion Logic
            # Considers: dataset count, confidence, tool installation, validation
            # ============================================================================
            uploaded_datasets = request.available_datasets or []
            confidence = result.get('confidence', 0.5)
            tool_installation = result.get('tool_installation', {})
            validation = result.get('validation', {})

            # Build pilot suggestion reasons
            pilot_reasons = []

            # Reason 1: Large dataset count (>20 datasets)
            if len(uploaded_datasets) > 20:
                pilot_reasons.append(f"Large dataset count ({len(uploaded_datasets)} datasets)")

            # Reason 2: Tool installation issues
            failed_tools = tool_installation.get('failed_tools', [])
            if failed_tools:
                pilot_reasons.append(f"Missing/failed tools: {', '.join(failed_tools[:3])}")

            # Reason 3: Low confidence workflow generation
            if confidence < 0.7:
                pilot_reasons.append(f"Low generation confidence ({confidence:.0%})")

            # Reason 4: Validation warnings or issues
            validation_warnings = validation.get('warnings', [])
            validation_issues = validation.get('issues', [])
            if validation_issues:
                pilot_reasons.append(f"Validation issues: {len(validation_issues)} found")
            elif validation_warnings:
                pilot_reasons.append(f"Validation warnings: {len(validation_warnings)}")

            # Reason 5: Generated from scratch (no template match)
            if result.get('source') == 'from_scratch':
                pilot_reasons.append("Workflow generated from scratch (no template match)")

            # Reason 6: Large cryo-EM dataset (num_movies > 1000)
            _num_movies = None
            for _pd in result.get('generated_parameters', []):
                for _key in ('num_movies', 'num_micrographs', 'movie_count'):
                    if _key in _pd.get('parameters', {}):
                        try:
                            _num_movies = int(_pd['parameters'][_key])
                        except (ValueError, TypeError):
                            pass
            if _num_movies is None and request.message:
                import re as _re
                _m = _re.search(r'\bnum_movies\s*=\s*(\d+)', request.message, _re.IGNORECASE)
                if _m:
                    try:
                        _num_movies = int(_m.group(1))
                    except (ValueError, TypeError):
                        pass
            if _num_movies and _num_movies > 1000:
                pilot_reasons.append(
                    f"Large cryo-EM dataset ({_num_movies:,} movies) — "
                    f"pilot run on ~200 movies recommended before full processing"
                )

            # Suggest pilot if ANY reason exists
            pilot_suggested = len(pilot_reasons) > 0

            # Build pilot suggestion message
            pilot_message = None
            if pilot_suggested:
                pilot_message = "Pilot run recommended: " + "; ".join(pilot_reasons)
                log.info(f"[PilotSuggestion] {pilot_message}")

            # Pass through parameter_metadata from the AI assistant result (already built there).
            # If the result doesn't carry it (e.g. generate_workflow_unified path),
            # fall back to an empty dict — the frontend treats missing metadata gracefully.
            _endpoint_parameter_metadata = result.get('parameter_metadata') or {}

            # ── N4: Save workflow step to WorkflowSession ──────────────────────
            _sess_store2 = _get_session_store()
            if _sess_store2:
                try:
                    sess = _sess_store2.get_or_create(session_id, user_intent=request.request_text)
                    wf_name = result.get('nextflow_path') or result.get('workflow_type', 'unknown')
                    nf_path = result.get('nextflow_path', '')
                    # Params: flatten generated_parameters into {tool_id: {params}}
                    step_params: dict = {}
                    for _pd in result.get('generated_parameters', []):
                        step_params.update(_pd.get('parameters', {}))
                    out_types = [
                        p.get('output_type', '') for p in result.get('generated_parameters', [])
                        if p.get('output_type')
                    ]
                    sess.add_step(
                        workflow_name=wf_name,
                        nextflow_path=nf_path,
                        params=step_params,
                        output_types=out_types or ['bam'],
                    )
                    _sess_store2.save(sess)
                    log.info(
                        "[generate_workflow] Saved step %d to session %s",
                        len(sess.steps) - 1, session_id,
                    )
                except Exception as _se:
                    log.debug("[generate_workflow] Session save failed (non-fatal): %s", _se)

            return {
                'success': True,
                'workflow_ga': result['workflow_ga'],
                'workflow_type': result.get('workflow_type'),
                'nextflow_path': result.get('nextflow_path'),
                'execution_engine': result.get('execution_engine'),
                'hardware_requirements': result.get('hardware_requirements'),
                'source': result['source'],
                'confidence': confidence,
                'template_match_score': result.get('template_match_score', 0.0),
                'datasets_assigned': result.get('datasets_assigned', False),
                'generated_parameters': result.get('generated_parameters', []),
                'message': result.get('message', 'Workflow generated successfully'),
                'note': f"Generated using {result['source']} strategy",
                # Citation fields
                'citations': [c.model_dump() for c in citations],
                'methods_section': methods_section.model_dump() if methods_section else None,
                'parameter_recommendations': {k: v.model_dump() for k, v in param_recommendations.items()},
                # Parameter metadata for frontend required/optional UI
                'parameter_metadata': _endpoint_parameter_metadata,
                # Enhanced pilot suggestion
                'pilot_run_suggested': pilot_suggested,
                'pilot_reasons': pilot_reasons,
                'pilot_message': pilot_message,
                'tuning_config': TuningConfigModel().model_dump() if pilot_suggested else None,
                # Validation info for frontend display
                'validation': {
                    'is_valid': validation.get('is_valid', True),
                    'issues': validation_issues,
                    'warnings': validation_warnings,
                    'suggestions': validation.get('suggestions', [])
                },
                'tool_installation': {
                    'success': tool_installation.get('success', True),
                    'message': tool_installation.get('message', ''),
                    'failed_tools': failed_tools
                }
            }
        else:
            return {
                'success': False,
                'error': result.get('error', 'Unknown error'),
                'message': result.get('message', 'Workflow generation failed'),
                'citations': [],
                'methods_section': None,
                'parameter_recommendations': {},
                'pilot_run_suggested': False
            }

    except Exception as e:
        log.error(f"Error in unified workflow generation: {e}")
        raise HTTPException(status_code=500, detail=f"Error generating workflow: {str(e)}")


def _workflow_to_dict(workflow_template) -> Dict[str, Any]:
    """Convert workflow template to dictionary."""
    if not workflow_template:
        return None

    return {
        "name": workflow_template.name,
        "description": workflow_template.description,
        "steps": [
            {
                "step_id": step.step_id,
                "tool_id": step.tool_id,
                "tool_version": step.tool_version,
                "annotation": step.annotation,
                "parameters": step.parameters
            }
            for step in workflow_template.steps
        ],
        "inputs": workflow_template.inputs,
        "outputs": workflow_template.outputs,
        "tags": workflow_template.tags
    }


# ============================================================================
# Multi-Agent Workflow Generation
# ============================================================================

class WorkflowCorrectionRequest(BaseModel):
    """Request to submit a user correction for learning."""
    request_id: str = Field(..., description="Request ID from workflow generation")
    correction_type: str = Field(..., description="Type: domain, tool_selection, parameters")
    original_value: Any = Field(..., description="Original suggested value")
    corrected_value: Any = Field(..., description="User's corrected value")
    reason: Optional[str] = Field(None, description="Reason for correction")


class WorkflowOutcomeRequest(BaseModel):
    """Request to record workflow execution outcome."""
    request_id: str = Field(..., description="Request ID from workflow generation")
    success: bool = Field(..., description="Whether workflow executed successfully")
    user_kept: bool = Field(True, description="Whether user kept/used the workflow")
    rating: Optional[int] = Field(None, ge=1, le=5, description="User rating 1-5")


@router.post(
    "/api/ai_assistant/generate_workflow_multi_agent",
    summary="Generate workflow using multi-agent system with LLM-enhanced routing."
)
def generate_workflow_multi_agent(
    request: AIRequestModel,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Generate workflow using multi-agent system with LLM-enhanced routing.

    This endpoint uses a 3-agent architecture:
    1. EnhancedDomainRouter - Routes with hybrid keyword + LLM approach
    2. DomainSpecialists - Parallel domain-specific recommendations
    3. WorkflowAssembler - Synthesizes and validates workflow

    Features:
    - LLM-enhanced routing for ambiguous queries
    - User pattern personalization
    - Full audit trail for all generations
    - Learning from corrections and outcomes

    Returns request_id for submitting corrections/outcomes.
    """
    import sys
    print("[DEBUG] generate_workflow_multi_agent endpoint called", file=sys.stderr, flush=True)

    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        # Extract uploaded dataset IDs if provided
        uploaded_datasets = None
        if request.available_datasets:
            uploaded_datasets = [ds.get('id') for ds in request.available_datasets if ds.get('id')]

        # Generate session ID for audit tracking
        session_id = request.context.get('session_id') if request.context else None

        # Generate workflow using multi-agent system with auditing
        result = ai_assistant.generate_workflow_multi_agent(
            user_intent=request.request_text,
            user_id=str(trans.user.id) if trans.user else None,
            session_id=session_id,
            uploaded_datasets=uploaded_datasets
        )

        if result['success']:
            return {
                'success': True,
                'workflow_ga': result['workflow_ga'],
                'source': result['source'],
                'confidence': result['confidence'],
                'message': result.get('message', 'Workflow generated successfully'),
                'timing': result.get('timing', {}),
                'domain_sources': result.get('domain_sources', []),
                'citations': result.get('citations', []),
                'validation': result.get('validation', {}),
                'note': f"Generated using multi-agent system ({', '.join(result.get('domain_sources', []))})",
                # Audit and learning fields
                'request_id': result.get('request_id'),
                'audit_id': result.get('audit_id'),
                'routing_method': result.get('routing_method', 'keyword')
            }
        else:
            return {
                'success': False,
                'error': result.get('error', 'Unknown error'),
                'message': 'Multi-agent workflow generation failed',
                'timing': result.get('timing', {}),
                'request_id': result.get('request_id'),
                'audit_id': result.get('audit_id')
            }

    except Exception as e:
        log.error(f"Error in multi-agent workflow generation: {e}")
        raise HTTPException(status_code=500, detail=f"Error generating workflow: {str(e)}")


# ============================================================================
# Correction and Learning Endpoints
# ============================================================================

@router.post(
    "/api/ai_assistant/workflow/{request_id}/correction",
    summary="Submit user correction for learning."
)
def submit_workflow_correction(
    request_id: str = Path(..., description="Request ID from workflow generation"),
    correction: WorkflowCorrectionRequest = ...,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Submit a user correction for learning.

    This records the correction and triggers learning:
    - Domain corrections update user preferences and router keywords
    - Tool corrections update tool preferences
    - Parameter corrections are stored for batch learning

    Args:
        request_id: Request ID from generate_workflow_multi_agent
        correction: Correction details (type, original, corrected values)

    Returns:
        Dict with correction and learning results
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        user_id = str(trans.user.id) if trans.user else None
        if not user_id:
            raise HTTPException(status_code=401, detail="Authentication required for corrections")

        result = ai_assistant.record_workflow_correction(
            request_id=request_id,
            user_id=user_id,
            correction_type=correction.correction_type,
            original_value=correction.original_value,
            corrected_value=correction.corrected_value,
            reason=correction.reason
        )

        return {
            'success': result.get('recorded', False) or result.get('learned', False),
            'recorded': result.get('recorded', False),
            'learned': result.get('learned', False),
            'actions': result.get('actions', []),
            'message': 'Correction recorded and learning applied' if result.get('learned') else 'Correction recorded'
        }

    except Exception as e:
        log.error(f"Error recording correction: {e}")
        raise HTTPException(status_code=500, detail=f"Error recording correction: {str(e)}")


@router.post(
    "/api/ai_assistant/workflow/{request_id}/outcome",
    summary="Record workflow execution outcome."
)
def record_workflow_outcome(
    request_id: str = Path(..., description="Request ID from workflow generation"),
    outcome: WorkflowOutcomeRequest = ...,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Record workflow execution outcome for learning.

    This records whether the workflow:
    - Executed successfully
    - Was kept/used by the user
    - User rating (optional)

    Positive outcomes reinforce domain preferences.
    Negative outcomes are tracked for analysis.

    Args:
        request_id: Request ID from generate_workflow_multi_agent
        outcome: Outcome details

    Returns:
        Dict with learning results
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        user_id = str(trans.user.id) if trans.user else None
        if not user_id:
            raise HTTPException(status_code=401, detail="Authentication required")

        result = ai_assistant.record_workflow_outcome(
            request_id=request_id,
            user_id=user_id,
            success=outcome.success,
            user_kept=outcome.user_kept,
            rating=outcome.rating
        )

        return {
            'success': True,
            'learned': result.get('learned', False),
            'actions': result.get('actions', []),
            'message': 'Outcome recorded'
        }

    except Exception as e:
        log.error(f"Error recording outcome: {e}")
        raise HTTPException(status_code=500, detail=f"Error recording outcome: {str(e)}")


# ============================================================================
# Audit Endpoints
# ============================================================================

@router.get(
    "/api/ai_assistant/audit/history",
    summary="Get workflow generation history."
)
def get_audit_history(
    limit: int = Query(50, ge=1, le=200, description="Max records to return"),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Get user's workflow generation history.

    Returns a list of audit records for the authenticated user,
    including query text, routing decisions, success/failure, and timing.

    Args:
        limit: Maximum number of records to return (default 50)

    Returns:
        Dict with audit history
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        user_id = str(trans.user.id) if trans.user else None
        if not user_id:
            raise HTTPException(status_code=401, detail="Authentication required")

        history = ai_assistant.get_workflow_audit_history(user_id, limit)

        return {
            'success': True,
            'user_id': user_id,
            'count': len(history),
            'history': history
        }

    except Exception as e:
        log.error(f"Error fetching audit history: {e}")
        raise HTTPException(status_code=500, detail=f"Error fetching history: {str(e)}")


@router.get(
    "/api/ai_assistant/audit/statistics",
    summary="Get workflow generation statistics."
)
def get_audit_statistics(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Get workflow generation statistics.

    Returns statistics about:
    - Total generations
    - Success/failure rates
    - Routing method distribution
    - Average latencies
    - Domain distribution

    For authenticated users, returns personal statistics.
    For admins, can access global statistics.

    Returns:
        Dict with audit statistics
    """
    ai_assistant = get_ai_assistant(trans)
    if not ai_assistant:
        raise HTTPException(status_code=503, detail="AI Assistant not available")

    try:
        user_id = str(trans.user.id) if trans.user else None

        # Get user-specific statistics
        stats = ai_assistant.get_workflow_audit_statistics(user_id)

        return {
            'success': True,
            'user_id': user_id,
            'statistics': stats
        }

    except Exception as e:
        log.error(f"Error fetching statistics: {e}")
        raise HTTPException(status_code=500, detail=f"Error fetching statistics: {str(e)}")


# ============================================================================
# Pilot Run Endpoints
# ============================================================================

@router.post(
    "/api/ai_assistant/pilot/start",
    summary="Start a pilot run for parameter tuning."
)
def start_pilot_run(
    request: StartPilotRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Start a pilot run on a subset of data.

    This runs the workflow on a small sample to:
    - Estimate full run time and resources
    - Tune parameters before full execution
    - Validate workflow before committing to full analysis
    """
    if not TUNING_AVAILABLE:
        raise HTTPException(
            status_code=503,
            detail="Progressive tuning components not available"
        )

    try:
        # Generate pilot ID
        pilot_id = f"pilot_{uuid.uuid4().hex[:12]}"

        # Convert config model to TuningConfig
        config = None
        if request.config:
            config = TuningConfig(
                pilot_fraction=request.config.pilot_fraction,
                min_pilot_samples=request.config.min_pilot_samples,
                max_pilot_samples=request.config.max_pilot_samples,
                sampling_strategy=SamplingStrategy(request.config.sampling_strategy),
                strata_column=request.config.strata_column
            )
        else:
            config = TuningConfig()

        # Calculate pilot size
        controller = ProgressiveTuningController(config=config)
        pilot_size = controller.calculate_pilot_size(request.total_samples)

        # Get workflow managers
        from galaxy.managers.workflows import WorkflowsManager
        from galaxy.managers.histories import HistoryManager

        workflows_manager = trans.app.workflow_manager
        history_manager = trans.app.history_manager

        # Create sandbox history for pilot run
        sandbox_history_name = f"[Pilot Run] {pilot_id}"
        if request.history_id:
            history = history_manager.get_accessible(request.history_id, trans.user)
        else:
            history = history_manager.create(
                trans.user,
                name=sandbox_history_name
            )

        # Get or import workflow
        galaxy_workflow_id = None
        if request.workflow_id:
            galaxy_workflow_id = request.workflow_id
        elif request.workflow_definition:
            # Import workflow definition
            from galaxy.managers.workflows import MissingToolsException
            try:
                workflow_import_result = workflows_manager.import_workflow(
                    trans,
                    request.workflow_definition,
                    fill_defaults=True
                )
                galaxy_workflow_id = workflow_import_result.id
            except MissingToolsException as e:
                raise HTTPException(
                    status_code=400,
                    detail=f"Workflow has missing tools: {str(e)}"
                )
        else:
            raise HTTPException(
                status_code=400,
                detail="Either workflow_id or workflow_definition is required"
            )

        # Sample inputs for pilot (take first N based on pilot_size)
        pilot_inputs = {}
        if request.inputs:
            # For pilot, we take a subset of inputs based on pilot_size
            # This is simplified - in production, use proper sampling strategy
            sampled_inputs = request.inputs[:pilot_size] if len(request.inputs) > pilot_size else request.inputs

            # Convert inputs to Galaxy format
            for idx, input_data in enumerate(sampled_inputs):
                step_id = input_data.get('step_id', idx)
                if 'src' in input_data and 'id' in input_data:
                    pilot_inputs[str(step_id)] = {
                        'src': input_data['src'],
                        'id': input_data['id']
                    }

        # Invoke workflow
        from galaxy.schema.workflows import WorkflowInvocationPayload
        invoke_payload = WorkflowInvocationPayload(
            history_id=history.id,
            inputs=pilot_inputs,
            # Add pilot marker in parameters
            parameters_normalized=True,
            allow_tool_state_corrections=True
        )

        # [NEW] Run test harness validation before invoking workflow
        from galaxy.jobs.harness_factory import get_harness_for_workflow

        # Get workflow file path if available (for test harness)
        workflow_path = None
        # TODO: Extract workflow path from stored_workflow if available

        # Create harness and run pre-execution validation
        harness = None
        if workflow_path:
            harness = get_harness_for_workflow(
                workflow_path=str(workflow_path),
                parameters=request.parameters or {},
                app=trans.app,
                enable_pilot=True,
                max_pilot_retries=2
            )

            if harness:
                log.info(f"[Pilot] Running pre-execution validation with {harness.__class__.__name__}")
                validation_report = harness.validate_pre_execution()

                if not validation_report.validation_passed:
                    log.warning(f"[Pilot] Pre-execution validation failed: {validation_report.checks}")
                    # Continue anyway but log the issues
                    for check in validation_report.checks:
                        if check.status == "failed":
                            log.error(f"  - {check.check_name}: {check.message}")

        # Get workflow and invoke
        stored_workflow = workflows_manager.get_stored_workflow(trans, galaxy_workflow_id, by_stored_id=True)
        invocation = workflows_manager.invoke_workflow(
            trans,
            stored_workflow,
            invoke_payload
        )

        # Store pilot run info with Galaxy invocation ID
        _pilot_runs[pilot_id] = {
            "pilot_id": pilot_id,
            "workflow_id": galaxy_workflow_id,
            "galaxy_invocation_id": invocation.id,
            "galaxy_history_id": history.id,
            "status": "running",
            "progress": 0.0,
            "total_samples": request.total_samples,
            "pilot_size": pilot_size,
            "config": config.to_dict(),
            "started_at": datetime.now().isoformat(),
            "completed_at": None,
            "runtime_seconds": None,
            "peak_memory_gb": None,
            "quality_metrics": None,
            "error_message": None
        }

        log.info(f"[Pilot] Started pilot run {pilot_id} with Galaxy invocation {invocation.id}")

        return {
            "pilot_id": pilot_id,
            "status": "running",
            "pilot_size": pilot_size,
            "galaxy_invocation_id": invocation.id,
            "galaxy_history_id": history.id,
            "message": f"Pilot run started with {pilot_size} samples in sandbox history",
            "config": config.to_dict()
        }

    except HTTPException:
        raise
    except Exception as e:
        log.error(f"Error starting pilot run: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"Error starting pilot: {str(e)}")


@router.get(
    "/api/ai_assistant/pilot/{pilot_id}/status",
    summary="Get pilot run status."
)
def get_pilot_status(
    pilot_id: str = Path(..., description="Pilot run ID"),
    trans: ProvidesUserContext = DependsOnTrans
) -> PilotStatusResponse:
    """Get the current status of a pilot run by checking Galaxy invocation."""

    if pilot_id not in _pilot_runs:
        raise HTTPException(status_code=404, detail=f"Pilot run {pilot_id} not found")

    pilot_data = _pilot_runs[pilot_id]

    # If already complete or failed, return cached status
    if pilot_data["status"] in ("complete", "failed"):
        return PilotStatusResponse(
            pilot_id=pilot_id,
            status=pilot_data["status"],
            progress=pilot_data.get("progress", 0.0),
            runtime_seconds=pilot_data.get("runtime_seconds"),
            peak_memory_gb=pilot_data.get("peak_memory_gb"),
            quality_metrics=pilot_data.get("quality_metrics"),
            error_message=pilot_data.get("error_message")
        )

    # Check Galaxy invocation status
    galaxy_invocation_id = pilot_data.get("galaxy_invocation_id")
    if galaxy_invocation_id:
        try:
            from galaxy.webapps.galaxy.services.invocations import InvocationsService
            invocations_service = trans.app.invocations_service

            # Get invocation state
            invocation = invocations_service.get_invocation(trans, galaxy_invocation_id)

            # Map Galaxy state to pilot status
            galaxy_state = invocation.state
            if galaxy_state in ("scheduled", "new", "ready"):
                pilot_data["status"] = "running"
                pilot_data["progress"] = 0.1
            elif galaxy_state == "running":
                # Calculate progress from step states
                total_steps = len(invocation.steps) if invocation.steps else 1
                completed_steps = sum(1 for s in (invocation.steps or []) if s.state == "ok")
                pilot_data["progress"] = (completed_steps / total_steps) * 100
                pilot_data["status"] = "running"
            elif galaxy_state == "ok":
                # Pilot completed successfully
                pilot_data["status"] = "complete"
                pilot_data["progress"] = 100.0
                pilot_data["completed_at"] = datetime.now().isoformat()

                # Calculate runtime
                if pilot_data.get("started_at"):
                    started = datetime.fromisoformat(pilot_data["started_at"])
                    completed = datetime.now()
                    pilot_data["runtime_seconds"] = (completed - started).total_seconds()

                # Collect metrics from job info (simplified)
                pilot_data["quality_metrics"] = {
                    "steps_completed": len([s for s in (invocation.steps or []) if s.state == "ok"]),
                    "total_steps": len(invocation.steps) if invocation.steps else 0
                }

                # Estimate memory from job metrics (placeholder - would need job manager access)
                pilot_data["peak_memory_gb"] = 2.0  # Default estimate

            elif galaxy_state in ("error", "failed"):
                pilot_data["status"] = "failed"
                pilot_data["error_message"] = f"Galaxy invocation failed: {galaxy_state}"
                # Get error details from failed steps
                for step in (invocation.steps or []):
                    if step.state == "error" and hasattr(step, 'job_state'):
                        pilot_data["error_message"] = f"Step {step.order_index} failed"
                        break

            elif galaxy_state == "cancelled":
                pilot_data["status"] = "failed"
                pilot_data["error_message"] = "Pilot run was cancelled"

        except Exception as e:
            log.warning(f"Could not fetch Galaxy invocation status: {e}")
            # Keep existing status if Galaxy query fails

    return PilotStatusResponse(
        pilot_id=pilot_id,
        status=pilot_data["status"],
        progress=pilot_data.get("progress", 0.0),
        runtime_seconds=pilot_data.get("runtime_seconds"),
        peak_memory_gb=pilot_data.get("peak_memory_gb"),
        quality_metrics=pilot_data.get("quality_metrics"),
        error_message=pilot_data.get("error_message")
    )


@router.get(
    "/api/ai_assistant/pilot/{pilot_id}/estimate",
    summary="Get full run estimate from pilot results."
)
def get_full_run_estimate(
    pilot_id: str = Path(..., description="Pilot run ID"),
    cost_per_hour_usd: float = Query(0.50, description="Cost per compute hour"),
    trans: ProvidesUserContext = DependsOnTrans
) -> FullRunEstimateResponse:
    """
    Get estimated resources for full run based on pilot results.

    Returns:
    - Estimated runtime
    - Estimated memory
    - Estimated cost
    - Confidence level
    """
    if not TUNING_AVAILABLE:
        raise HTTPException(
            status_code=503,
            detail="Progressive tuning components not available"
        )

    if pilot_id not in _pilot_runs:
        raise HTTPException(status_code=404, detail=f"Pilot run {pilot_id} not found")

    pilot_data = _pilot_runs[pilot_id]

    if pilot_data["status"] != "complete":
        raise HTTPException(
            status_code=400,
            detail=f"Pilot run not complete. Status: {pilot_data['status']}"
        )

    try:
        # Create a simple object with pilot metrics for estimation
        class SimplePilotResult:
            def __init__(self, data):
                self.runtime_seconds = data.get("runtime_seconds", 60.0)
                self.samples_used = data.get("pilot_size", 10)
                self.peak_memory_gb = data.get("peak_memory_gb", 4.0)

        pilot_result = SimplePilotResult(pilot_data)
        full_size = pilot_data["total_samples"]

        # Use controller to estimate
        controller = ProgressiveTuningController()
        estimate = controller.estimate_full_run(
            pilot_result=pilot_result,
            full_size=full_size,
            cost_per_hour_usd=cost_per_hour_usd
        )

        return FullRunEstimateResponse(
            estimated_runtime_seconds=estimate["estimated_runtime_seconds"],
            estimated_runtime_display=estimate["estimated_runtime_display"],
            estimated_memory_gb=estimate["estimated_memory_gb"],
            estimated_cost_usd=estimate.get("estimated_cost_usd"),
            confidence=estimate.get("confidence", 0.8),
            scaling_factors=estimate.get("scaling_factors", {})
        )

    except Exception as e:
        log.error(f"Error estimating full run: {e}")
        raise HTTPException(status_code=500, detail=f"Error estimating: {str(e)}")


# ============================================================================
# Citation Export Endpoints
# ============================================================================

@router.post(
    "/api/ai_assistant/citations/export",
    summary="Export workflow citations as BibTeX."
)
def export_citations_bibtex(
    request: BibTeXExportRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Export all tool citations from a workflow as BibTeX format.

    This allows users to easily add citations to their publications.
    """
    try:
        from galaxy.ai.methods_generator import MethodsSectionGenerator
        from galaxy.ai.tool_knowledge_provider import get_tool_knowledge_provider

        knowledge_provider = get_tool_knowledge_provider()
        if not knowledge_provider:
            return {
                "success": False,
                "error": "Tool knowledge provider not available",
                "bibtex": ""
            }

        generator = MethodsSectionGenerator(knowledge_provider)
        bibtex = generator.generate_bibtex(request.workflow_ga)

        # Also get summary
        summary = generator.get_citations_summary(request.workflow_ga)

        return {
            "success": True,
            "bibtex": bibtex,
            "total_tools": summary["total_steps"],
            "tools_with_citations": summary["steps_with_citations"],
            "missing_citations": summary["missing_citations"]
        }

    except Exception as e:
        log.error(f"Error exporting citations: {e}")
        return {
            "success": False,
            "error": str(e),
            "bibtex": ""
        }


@router.post(
    "/api/ai_assistant/citations/methods",
    summary="Generate methods section text."
)
def generate_methods_section(
    request: BibTeXExportRequest,
    style: str = Query("short", description="Citation style: short, apa, numbered"),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Generate publication-ready methods section from workflow.

    Automatically describes each tool with proper citations.
    """
    try:
        from galaxy.ai.methods_generator import MethodsSectionGenerator
        from galaxy.ai.tool_knowledge_provider import get_tool_knowledge_provider

        knowledge_provider = get_tool_knowledge_provider()
        if not knowledge_provider:
            return {
                "success": False,
                "error": "Tool knowledge provider not available",
                "methods_text": ""
            }

        generator = MethodsSectionGenerator(knowledge_provider)
        methods_text = generator.generate(
            workflow=request.workflow_ga,
            citation_style=style,
            include_parameters=True,
            include_versions=True
        )

        summary = generator.get_citations_summary(request.workflow_ga)

        return {
            "success": True,
            "methods_text": methods_text,
            "style": style,
            "tools_cited": [c["tool"] for c in summary["citations"]],
            "tools_missing_citations": summary["missing_citations"]
        }

    except Exception as e:
        log.error(f"Error generating methods section: {e}")
        return {
            "success": False,
            "error": str(e),
            "methods_text": ""
        }


# ============================================================================
# Benchmark Endpoints (Updated 2025-12-30 - Connected to BenchmarkKnowledgeDB)
# ============================================================================

# Pydantic models for benchmark API
class BenchmarkQueryRequest(BaseModel):
    """Request model for benchmark queries."""
    query: str = Field(..., description="Natural language query about tool performance")
    constraints: Dict[str, Any] = Field(default_factory=dict, description="Context constraints")
    top_k: int = Field(default=5, description="Number of results to return")


class ToolComparisonRequest(BaseModel):
    """Request model for tool comparison."""
    tool_a: str = Field(..., description="First tool name")
    tool_b: str = Field(..., description="Second tool name")
    task: Optional[str] = Field(None, description="Task context for comparison")


@router.get(
    "/api/ai_assistant/benchmarks/{scenario}",
    summary="Get benchmark results for a scenario."
)
def get_benchmark_results(
    scenario: str = Path(..., description="Benchmark scenario name"),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Get benchmark comparison results for tools/parameters.

    Available scenarios:
    - rna_seq_alignment: RNA-seq read alignment tool comparison
    - variant_calling: Variant calling tool comparison
    - single_cell_integration: Single-cell batch integration comparison
    - differential_expression: Differential expression analysis comparison
    """
    try:
        # Try to use BenchmarkKnowledgeDB first (primary source)
        if BENCHMARK_AVAILABLE and BenchmarkKnowledgeDB:
            try:
                benchmark_db = BenchmarkKnowledgeDB()

                # Query the benchmark database with the scenario as search term
                results = benchmark_db.query_semantic(scenario, top_k=10)

                if results:
                    tools_compared = []
                    metrics = {}
                    recommendations = []

                    for result in results:
                        tool_name = result.get('tool_name', '')
                        if tool_name and tool_name not in tools_compared:
                            tools_compared.append(tool_name)

                        # Collect metrics
                        if result.get('metric_name') and result.get('metric_value'):
                            key = f"{tool_name}_{result['metric_name']}"
                            metrics[key] = {
                                'tool': tool_name,
                                'metric': result['metric_name'],
                                'value': result['metric_value'],
                                'rank': result.get('rank')
                            }

                        # Get recommendations from decision rules
                        if result.get('evidence_text'):
                            recommendations.append({
                                'tool': tool_name,
                                'evidence': result['evidence_text'],
                                'doi': result.get('doi')
                            })

                    return {
                        "scenario": scenario,
                        "available": True,
                        "tools_compared": tools_compared,
                        "metrics": metrics,
                        "recommendations": recommendations[:5],
                        "source": "benchmark_knowledge_db"
                    }
            except Exception as db_err:
                log.warning(f"BenchmarkKnowledgeDB query failed: {db_err}")

        # Fallback to test harness
        try:
            from galaxy.ai.test_harness import load_benchmark_results
            results = load_benchmark_results(scenario)
            if results:
                return {
                    "scenario": scenario,
                    "available": True,
                    "tools_compared": results.get("tools", []),
                    "metrics": results.get("metrics", {}),
                    "recommendations": results.get("recommendations", []),
                    "last_run": results.get("timestamp"),
                    "source": "test_harness"
                }
        except ImportError:
            pass

        # No data available
        return {
            "scenario": scenario,
            "available": False,
            "message": "No benchmark data available for this scenario",
            "tools_compared": [],
            "metrics": {},
            "recommendations": []
        }

    except Exception as e:
        log.error(f"Error fetching benchmarks: {e}")
        return {
            "scenario": scenario,
            "available": False,
            "error": str(e)
        }


@router.post(
    "/api/ai_assistant/benchmark_query",
    summary="Query benchmarks with natural language."
)
def query_benchmarks(
    request: BenchmarkQueryRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Query benchmark knowledge with natural language.

    Example queries:
    - "best RNA-seq aligner"
    - "fastest variant caller for WGS"
    - "memory-efficient single-cell integration"
    """
    try:
        if not BENCHMARK_AVAILABLE or not BenchmarkKnowledgeDB:
            return {
                "success": False,
                "error": "Benchmark knowledge system not available"
            }

        benchmark_db = BenchmarkKnowledgeDB()

        # Use semantic query
        results = benchmark_db.query_semantic(request.query, top_k=request.top_k)

        if not results:
            return {
                "success": True,
                "query": request.query,
                "results": [],
                "message": "No matching benchmarks found"
            }

        # Get the best tool
        best_result = results[0] if results else None
        best_tool = best_result.get('tool_name') if best_result else None

        # Format results
        formatted_results = []
        for result in results:
            formatted_results.append({
                "tool": result.get('tool_name'),
                "rank": result.get('rank'),
                "metric": result.get('metric_name'),
                "value": result.get('metric_value'),
                "evidence": result.get('evidence_text'),
                "study": result.get('study_name'),
                "doi": result.get('doi')
            })

        # Check for context-aware recommendations
        recommendation = None
        if request.constraints:
            rec = benchmark_db.get_recommendation_for_condition(
                condition_type=list(request.constraints.keys())[0] if request.constraints else None,
                condition_value=list(request.constraints.values())[0] if request.constraints else None
            )
            if rec:
                recommendation = {
                    "tool": rec.get('tool_name'),
                    "reason": rec.get('recommendation_text'),
                    "condition": request.constraints
                }

        return {
            "success": True,
            "query": request.query,
            "best_tool": best_tool,
            "evidence": best_result.get('evidence_text') if best_result else None,
            "results": formatted_results,
            "recommendation": recommendation
        }

    except Exception as e:
        log.error(f"Error querying benchmarks: {e}")
        return {
            "success": False,
            "error": str(e)
        }


@router.post(
    "/api/ai_assistant/tool_comparison",
    summary="Compare two tools with benchmark evidence."
)
def compare_tools(
    request: ToolComparisonRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Compare two tools using benchmark evidence.

    Returns winner, detailed comparison, and supporting evidence.
    """
    try:
        if not BENCHMARK_AVAILABLE or not BenchmarkKnowledgeDB:
            return {
                "success": False,
                "error": "Benchmark knowledge system not available"
            }

        benchmark_db = BenchmarkKnowledgeDB()

        # Use the compare_tools method from BenchmarkKnowledgeDB
        comparison = benchmark_db.compare_tools(request.tool_a, request.tool_b, request.task)

        if not comparison:
            return {
                "success": True,
                "tool_a": request.tool_a,
                "tool_b": request.tool_b,
                "comparison_available": False,
                "message": f"No benchmark data available comparing {request.tool_a} and {request.tool_b}"
            }

        return {
            "success": True,
            "tool_a": request.tool_a,
            "tool_b": request.tool_b,
            "comparison_available": True,
            "winner": comparison.get('winner'),
            "comparison": comparison.get('comparison', {}),
            "evidence_text": comparison.get('evidence_text'),
            "studies": comparison.get('studies', []),
            "recommendation": comparison.get('recommendation')
        }

    except Exception as e:
        log.error(f"Error comparing tools: {e}")
        return {
            "success": False,
            "error": str(e)
        }


# ============================================================================
# Research Agent Endpoints (Added 2025-12-30)
# ============================================================================

class ResearchQueryRequest(BaseModel):
    """Request model for research queries."""
    query: str = Field(..., description="Research question to answer")
    context: Dict[str, Any] = Field(default_factory=dict, description="Optional context")
    include_citations: bool = Field(default=True, description="Include literature citations")
    include_benchmark_evidence: bool = Field(default=True, description="Include benchmark evidence")
    max_citations: int = Field(default=5, description="Maximum number of citations")


@router.post(
    "/api/ai_assistant/research_query",
    summary="Answer research questions with literature-backed evidence."
)
def answer_research_query(
    request: ResearchQueryRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Answer a research question with literature-backed evidence.

    Uses the ResearchAgent to:
    - Analyze the question and extract key concepts
    - Search benchmark knowledge for tool comparisons
    - Load relevant scientific skills for guidance
    - Synthesize an evidence-based response

    Example queries:
    - "What's the best alignment algorithm for long-read RNA-seq?"
    - "How does STAR compare to HISAT2 for RNA-seq alignment?"
    - "What are the best practices for single-cell RNA-seq normalization?"
    """
    try:
        if not RESEARCH_AGENT_AVAILABLE:
            # Fall back to benchmark query if ResearchAgent not available
            if BENCHMARK_AVAILABLE and BenchmarkKnowledgeDB:
                benchmark_db = BenchmarkKnowledgeDB()
                results = benchmark_db.query_semantic(request.query, top_k=5)

                if results:
                    best_result = results[0]
                    return {
                        "success": True,
                        "query": request.query,
                        "answer": best_result.get('evidence_text', 'No detailed answer available.'),
                        "citations": [],
                        "benchmark_evidence": {
                            "best_tool": best_result.get('tool_name'),
                            "results": results
                        },
                        "confidence": 0.7,
                        "source": "benchmark_fallback"
                    }

            return {
                "success": False,
                "error": "Research agent not available"
            }

        # Create ResearchAgent — build an LLMClient from the shared AI
        # assistant's config so the same API key is used.
        _research_llm = None
        try:
            _shared = get_ai_assistant(trans)
            if _shared is not None:
                from galaxy.ai.llm_client import LLMClient
                _research_llm = LLMClient(_shared.config)
        except Exception:
            pass
        research_agent = create_research_agent(llm_client=_research_llm)

        # Answer the question synchronously
        response = research_agent.answer_question_sync(
            question=request.query,
            context=request.context,
            include_citations=request.include_citations,
            include_benchmark_evidence=request.include_benchmark_evidence
        )

        # Format citations for JSON
        citations_json = []
        for citation in response.citations:
            citations_json.append({
                "title": citation.title,
                "authors": citation.authors,
                "year": citation.year,
                "journal": citation.journal,
                "doi": citation.doi,
                "pmid": citation.pmid
            })

        return {
            "success": True,
            "query": request.query,
            "answer": response.answer,
            "citations": citations_json,
            "benchmark_evidence": response.benchmark_evidence,
            "confidence": response.confidence,
            "follow_up_questions": response.follow_up_questions,
            "methods_used": response.methods_used,
            "source": "research_agent"
        }

    except Exception as e:
        log.error(f"Error answering research query: {e}")
        return {
            "success": False,
            "query": request.query,
            "error": str(e)
        }


@router.get(
    "/api/ai_assistant/skills/available",
    summary="Get list of available scientific skills."
)
def get_available_skills(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Get list of available claude-scientific-skills.

    Returns skills organized by category:
    - scientific-databases: PubMed, UniProt, ChEMBL, etc.
    - scientific-thinking: hypothesis-generation, peer-review, etc.
    - scientific-packages: scanpy, biopython, rdkit, etc.
    """
    try:
        if not RESEARCH_AGENT_AVAILABLE or not SkillLoader:
            return {
                "available": False,
                "message": "SkillLoader not available"
            }

        skill_loader = create_skill_loader()
        skills = skill_loader.get_available_skills()
        categories = skill_loader.get_skill_categories()

        return {
            "available": True,
            "total_skills": len(skills),
            "categories": categories,
            "skills": [
                {
                    "name": s.name,
                    "description": s.description,
                    "path": s.path
                }
                for s in skills
            ]
        }

    except Exception as e:
        log.error(f"Error getting available skills: {e}")
        return {
            "available": False,
            "error": str(e)
        }


# Note: Unified Execution endpoints are implemented in frontend/server/routes.ts
# using the /api/workflows/execute API. This avoids duplication and leverages
# the existing storage layer, Galaxy state poller, and SSE infrastructure.


# ── User Domain Profile endpoints ────────────────────────────────────────────

try:
    from galaxy.ai.memory.agentic_memory import get_memory_service as _get_memory_service
    from galaxy.ai.domain_taxonomy import DOMAIN_TAXONOMY, DOMAIN_LABELS, get_topics_for_domains
    _DOMAIN_PROFILE_AVAILABLE = True
except Exception as _dp_err:
    logging.warning(f"Domain profile components not available: {_dp_err}")
    _DOMAIN_PROFILE_AVAILABLE = False


class DomainProfileRequest(BaseModel):
    domains: List[str] = Field(default_factory=list, description="Selected research domain keys")
    topics: List[str] = Field(default_factory=list, description="Selected topic strings")


@router.post(
    "/api/user/domain-profile",
    summary="Save the user's research domain profile."
)
def set_domain_profile(
    request: DomainProfileRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Store user research domain and topic selections in LTM."""
    if not _DOMAIN_PROFILE_AVAILABLE:
        raise HTTPException(status_code=503, detail="Domain profile service not available")

    user = getattr(trans, "user", None)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")

    user_email = getattr(user, "email", None)
    if not user_email:
        raise HTTPException(status_code=400, detail="Cannot resolve user identity")

    try:
        memory = _get_memory_service()
        ltm_user = memory.users.get_or_create_user(email=user_email)
        memory.update_domain_profile(
            user_id=ltm_user["id"],
            domains=request.domains,
            topics=request.topics,
        )
        return {
            "success": True,
            "domains": request.domains,
            "topics": request.topics,
        }
    except Exception as exc:
        log.error(f"Failed to save domain profile: {exc}")
        raise HTTPException(status_code=500, detail=str(exc))


@router.get(
    "/api/user/domain-profile",
    summary="Get the user's research domain profile."
)
def get_domain_profile(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Retrieve user research domain and topic selections from LTM."""
    if not _DOMAIN_PROFILE_AVAILABLE:
        return {"domains": [], "topics": []}

    user = getattr(trans, "user", None)
    if not user:
        return {"domains": [], "topics": []}

    user_email = getattr(user, "email", None)
    if not user_email:
        return {"domains": [], "topics": []}

    try:
        memory = _get_memory_service()
        ltm_user = memory.users.get_or_create_user(email=user_email)
        return memory.get_domain_profile(user_id=ltm_user["id"])
    except Exception as exc:
        log.error(f"Failed to get domain profile: {exc}")
        return {"domains": [], "topics": []}


@router.get(
    "/api/user/domain-taxonomy",
    summary="Get the full domain taxonomy for the domain profile selector."
)
def get_domain_taxonomy(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Return the static domain taxonomy (domains + labels + topics)."""
    if not _DOMAIN_PROFILE_AVAILABLE:
        return {"domains": {}, "labels": {}}
    return {
        "domains": DOMAIN_TAXONOMY,
        "labels": DOMAIN_LABELS,
    }


# ── C3b: Session Summary endpoint ─────────────────────────────────────────────

class SessionSummaryRequest(BaseModel):
    summary: str = Field(..., description="2-3 sentence summary of compressed conversation turns")
    session_id: Optional[str] = Field(None, description="LTM session ID")
    user_id: Optional[str] = Field(None, description="User ID for attribution")


@router.post(
    "/api/ai_assistant/memory/session-summary",
    summary="Store a session summary generated when context is compressed."
)
def store_session_summary(
    request: SessionSummaryRequest,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    """
    Persist a short summary of conversation turns that were dropped during
    context compression.  The summary is written to the LtmSession.summary
    field so future sessions can bootstrap from it.
    """
    if not _DOMAIN_PROFILE_AVAILABLE:
        # Re-use the same availability flag; both need agentic_memory
        return {"success": False, "reason": "memory service not available"}

    if not request.summary:
        raise HTTPException(status_code=400, detail="summary must not be empty")

    try:
        from galaxy.ai.memory.agentic_memory import get_db_session as _get_db_session, LtmSession
        session_id = request.session_id

        if session_id:
            with _get_db_session() as db_session:
                ltm_session = db_session.query(LtmSession).filter(
                    LtmSession.id == session_id
                ).first()
                if ltm_session:
                    ltm_session.summary = request.summary
                    log.info("[ltm] Session summary stored for session %s", session_id)
                else:
                    log.debug("[ltm] session %s not found — summary not persisted", session_id)

        return {
            "success": True,
            "session_id": session_id,
            "summary_length": len(request.summary),
        }
    except Exception as exc:
        log.error("Failed to store session summary: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))