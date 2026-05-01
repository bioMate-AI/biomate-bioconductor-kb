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
    preferred_domains: Optional[List[str]] = None
    key_terms: Optional[List[str]] = None
    skip_chains: bool = False
    force_workflow_name: Optional[str] = None


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
    idx = 0
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
            nfcore_modules_root = backend_root / "nf-core-modules"
            if raw.startswith("nextflow_nfcore/"):
                rest = raw.split("nextflow_nfcore/", 1)[1].strip("/")
                candidates += [
                    nfcore_root / rest,
                    nfcore_root / rest / "main.nf",
                    nfcore_root / "subworkflows" / rest,
                    nfcore_root / "subworkflows" / rest / "main.nf",
                ]
            elif raw.startswith("nfcore/subworkflows/"):
                # Legacy path pattern: nfcore/subworkflows/<workflow> → nf-core-modules/subworkflows/nf-core/<workflow>/main.nf
                rest = raw.split("nfcore/subworkflows/", 1)[1].strip("/")
                candidates += [
                    nfcore_modules_root / "subworkflows" / "nf-core" / rest / "main.nf",
                    nfcore_modules_root / "subworkflows" / "nf-core" / rest,
                ]
            else:
                candidates += [
                    nfcore_root / nf_filename,
                    nfcore_root / "subworkflows" / nf_filename,
                    nfcore_modules_root / "subworkflows" / "nf-core" / nf_filename / "main.nf",
                ]
            abs_path = next((c for c in candidates if c.exists()), candidates[0])
        if not abs_path.exists():
            return steps
        content = abs_path.read_text(encoding="utf-8", errors="replace")

        # Strategy 1: `process NAME {` definitions — the authoritative source.
        # In Nextflow, a `process` is a discrete computational unit (one container,
        # one job on Batch). Comments document intent; they do not define execution.
        for m in re.finditer(r'^process\s+([A-Za-z][A-Za-z0-9_]+)\s*\{', content, re.MULTILINE):
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
        if steps:
            _enrich_steps_with_phase_info(steps, content, nf_filename)
            return steps

        # Strategy 2 (fallback): numbered steps in comment block ("* 1. Step name").
        # Used only when the file contains no `process` definitions — e.g. a wrapper
        # that calls an external pipeline and documents expected logical steps.
        header_lines = []
        for line in content.splitlines():
            if re.match(r'^\s*(process|workflow)\s*\b', line):
                break
            header_lines.append(line)
        header = '\n'.join(header_lines)
        comment_steps = re.findall(r'\*\s+(\d+)\.\s+(.+)', header)
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
    except Exception as exc:
        log.warning(f"[NextflowSteps] Failed to parse steps from {nf_filename}: {exc}")
    # ── Enrich steps with phase groups and per-step params ──────────────────────
    if steps:
        _enrich_steps_with_phase_info(steps, locals().get('content', ''), nf_filename)

    return steps


# ── CryoSPARC phase group mapping (step index → phase group + label) ──────────
_CRYOSPARC_STEP_PHASES: dict = {
    0:  ('A', 'Phase A — Motion Correction & CTF'),
    1:  ('A', 'Phase A — Motion Correction & CTF'),
    2:  ('A', 'Phase A — Motion Correction & CTF'),
    3:  ('A', 'Phase A — Motion Correction & CTF'),
    4:  ('A', 'Phase A — Motion Correction & CTF'),
    5:  ('A', 'Phase A — Motion Correction & CTF'),
    6:  ('B', 'Phase B — Particle Picking'),
    7:  ('B', 'Phase B — Particle Picking'),
    8:  ('B', 'Phase B — Particle Picking'),
    9:  ('B', 'Phase B — Particle Picking'),
    10: ('C', 'Phase C — 2D Classification'),
    11: ('C', 'Phase C — 2D Classification'),
    12: ('C', 'Phase C — 2D Classification'),
    13: ('C', 'Phase C — 2D Classification'),
    14: ('D', 'Phase D — 3D Reconstruction'),
    15: ('D', 'Phase D — 3D Reconstruction'),
    16: ('D', 'Phase D — 3D Reconstruction'),
    17: ('D', 'Phase D — 3D Reconstruction'),
    18: ('E', 'Phase E — Validation & Post-processing'),
    19: ('E', 'Phase E — Validation & Post-processing'),
    20: ('E', 'Phase E — Validation & Post-processing'),
    21: ('E', 'Phase E — Validation & Post-processing'),
    22: ('E', 'Phase E — Validation & Post-processing'),
}

# CryoSPARC per-step parameter lists (param names from workflow params.* declarations)
_CRYOSPARC_STEP_PARAMS: dict = {
    0:  ['movies_path', 'pixel_size', 'voltage', 'total_dose'],               # Import Movies
    1:  ['pixel_size', 'motion_correction_dose_weighting', 'micrograph_batch_size'],  # Patch Motion Correction
    2:  [],                                                                     # Merge Micrographs
    3:  ['voltage', 'spherical_aberration'],                                   # Patch CTF Estimation
    4:  [],                                                                     # Inspect CTF
    5:  [],                                                                     # Micrograph Denoiser
    6:  ['particle_diameter_angstroms', 'molecular_weight_kda'],               # Blob Particle Picker
    7:  [],                                                                     # Inspect Picks Round 1
    8:  ['particle_box_size', 'particle_diameter_angstroms'],                  # Template Picker
    9:  [],                                                                     # Inspect Picks Round 2
    10: ['particle_box_size', 'particle_batch_size'],                          # Extract Particles
    11: [],                                                                     # 2D Classification
    12: [],                                                                     # Select 2D Classes
    13: [],                                                                     # Extract Selected Particles
    14: ['num_ab_initio_classes', 'symmetry'],                                 # Ab-Initio Reconstruction
    15: ['symmetry', 'num_gpu'],                                               # Heterogeneous Refinement
    16: ['symmetry', 'num_gpu'],                                               # Homogeneous Refinement
    17: [],                                                                     # Class Merge and Select
    18: [],                                                                     # Local CTF Refinement
    19: ['max_resolution_refinement', 'pixel_size'],                           # Non-Uniform Refinement
    20: [],                                                                     # Local Resolution Estimation
    21: ['max_resolution_refinement'],                                          # Map Sharpening
    22: [],                                                                     # FSC Validation
}

# Generic phase group assignment via keyword matching (for non-CryoSPARC workflows)
_GENERIC_PHASE_RULES: list = [
    (['IMPORT', 'DOWNLOAD', 'FETCH', 'FASTERQ', 'SRA'],           '1', 'Phase 1 — Input & Download'),
    (['QC', 'FASTP', 'TRIM', 'FASTQC', 'MULTIQC'],                '2', 'Phase 2 — Quality Control'),
    (['ALIGN', 'MAP', 'BWA', 'BOWTIE', 'STAR', 'HISAT', 'SORT'],  '3', 'Phase 3 — Alignment'),
    (['GATK', 'VARIANT', 'CALL', 'GENOTYPE', 'FREEBAYES'],        '4', 'Phase 4 — Variant Calling'),
    (['ANNOTATE', 'SNPEFF', 'VEP', 'FILTER', 'REPORT'],           '5', 'Phase 5 — Annotation & Report'),
]


def _enrich_steps_with_phase_info(
    steps: dict,
    content: str,
    nf_filename: str,
) -> None:
    """Mutates steps in-place: adds phase_group, phase_label, and populates parameters."""
    is_cryosparc = 'cryosparc' in nf_filename.lower()

    # ── Parse per-process params.* references from the .nf file content ──
    process_param_refs: dict = {}
    if content:
        proc_starts = list(re.finditer(r'^process\s+(\w+)\s*\{', content, re.MULTILINE))
        for i, m in enumerate(proc_starts):
            proc_name = m.group(1).upper()
            start = m.end()
            end = proc_starts[i + 1].start() if i + 1 < len(proc_starts) else len(content)
            body = content[start:end]
            refs = list(dict.fromkeys(re.findall(r'params\.([a-zA-Z_]\w*)', body)))
            # Remove internal/infra params
            refs = [r for r in refs if r not in _NF_SKIP_PARAMS]
            process_param_refs[proc_name] = refs

    # ── Assign phase groups and per-step params ──
    for idx_str, step in steps.items():
        idx = int(idx_str)
        tool_id = step.get('tool_id', '').upper()

        if is_cryosparc and idx in _CRYOSPARC_STEP_PHASES:
            pg, pl = _CRYOSPARC_STEP_PHASES[idx]
            step['phase_group'] = pg
            step['phase_label'] = pl
            param_names = _CRYOSPARC_STEP_PARAMS.get(idx, [])
        else:
            # Generic keyword-based assignment
            pg, pl = '', ''
            for keywords, group, label in _GENERIC_PHASE_RULES:
                if any(k in tool_id for k in keywords):
                    pg, pl = group, label
                    break
            step['phase_group'] = pg
            step['phase_label'] = pl
            # Use process body param refs for generic case
            param_names = process_param_refs.get(tool_id, [])

        # Populate parameters as {name: {default: None}} placeholder metadata
        if param_names:
            step['parameters'] = {
                name: {'type': 'string', 'label': name.replace('_', ' ').title(), 'default': None}
                for name in param_names
            }


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
            backend_root / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / nf_filename,
        ]
        # Also try domain aliases (pharmacology ↔ drug_discovery) for each candidate
        _alias_map = {"drug_discovery": "pharmacology", "pharmacology": "drug_discovery"}
        _alias_candidates = []
        for _c in list(_candidates):
            parts = _c.parts
            for i, part in enumerate(parts):
                if part in _alias_map:
                    _alias_candidates.append(FilePath(*parts[:i]) / _alias_map[part] / FilePath(*parts[i + 1:]))
                    break
        _candidates.extend(_alias_candidates)
        abs_path = next((c for c in _candidates if c.exists()), None)
        if abs_path is None:
            return {"parameters": parameters, "parameter_metadata": parameter_metadata}
        content = abs_path.read_text(encoding="utf-8", errors="replace")

        # Scan line-by-line to track [Phase X] / [Global] section headers
        # Header format: // [Phase A] Description  or  // [Global] Description
        section_re = re.compile(r'//\s*\[([A-Za-z][A-Za-z0-9 _-]*)\]')
        param_re = re.compile(
            r'^params\.([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*([^\n/]+?)\s*(?://\s*(.+))?$',
        )
        current_group: str | None = None
        for line in content.splitlines():
            # Check for section header comment
            sec_m = section_re.search(line)
            if sec_m and line.strip().startswith('//'):
                raw_sec = sec_m.group(1).strip()
                # "Phase A" → "A", "Global" → "global", "Phase E" → "E"
                if raw_sec.lower().startswith('phase '):
                    current_group = raw_sec.split()[-1].upper()
                elif raw_sec.lower() in ('global', 'infrastructure', 'performance'):
                    current_group = 'global'
                else:
                    current_group = raw_sec
                continue
            m = param_re.match(line)
            if not m:
                continue
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

            # Extract allowed values from pipe-separated options in comment.
            # Pattern: "Description: opt1 | opt2 | opt3" or "opt1 | opt2 | opt3"
            # The options section follows a colon or is the whole comment when it has pipes.
            allowed_values: List[str] = []
            if comment and "|" in comment:
                # Take the part after the last colon (or whole comment if no colon)
                options_part = comment.split(":")[-1] if ":" in comment else comment
                # Only treat as enum if all tokens look like option values (short, no spaces or simple words)
                raw_opts = [o.strip() for o in options_part.split("|") if o.strip()]
                # Filter: options must be short and not contain long prose
                if raw_opts and all(len(o) <= 40 and " " not in o.split("(")[0].strip() for o in raw_opts):
                    # Strip parenthetical suffixes like "(skips genome alignment)"
                    allowed_values = [o.split("(")[0].strip() for o in raw_opts]

            parameters[name] = val
            meta: Dict[str, Any] = {"type": ptype, "label": label, "level": level}
            if allowed_values:
                meta["allowed_values"] = allowed_values
            if current_group:
                meta["group"] = current_group
            parameter_metadata[name] = meta

    except Exception as exc:
        log.warning(f"[NextflowParams] Failed to parse params from {nf_filename}: {exc}")
    return {"parameters": parameters, "parameter_metadata": parameter_metadata}


def _build_cryoem_rationale(user_intent: str) -> Dict[str, Any]:
    """Inject expert cryo-EM domain knowledge into scientific_rationale when the
    CryoSPARC SPA workflow is matched.

    Covers:
    - Sample class → pixel size, picker strategy, dose (GENERAL_FRAMEWORK V1/V2)
    - Target resolution → required particle count (GENERAL_FRAMEWORK V5)
    - Scientific question → number of datasets needed (GENERAL_FRAMEWORK V3)
    - Heterogeneity → classification depth (GENERAL_FRAMEWORK V4)
    - Universal invariants (FSC 0.143, MolProbity, reference dataset rule)
    """
    import re as _re

    hints: List[Dict[str, str]] = []
    guidance: List[str] = []

    intent_lower = user_intent.lower()

    # ── Sample class detection ──────────────────────────────────────────────
    # GPCR check must come BEFORE the generic nanodisc/membrane check because
    # GPCR–G protein complexes are frequently prepared in nanodiscs (MSP1D1).
    # Without this ordering, a query like "mu-opioid receptor Gi complex in nanodisc"
    # would be misclassified as membrane_small.
    _GPCR_TERMS = (
        "gpcr", "g protein", "g-protein",
        "gi complex", "gs complex", "gq complex", "go complex",
        "opioid receptor", "adrenergic receptor", "dopamine receptor",
        "muscarinic", "adenosine receptor", "serotonin receptor",
        "adenylyl", "arrestin", "receptor kinase",
        "beta-adrenergic", "alpha-adrenergic",
    )
    if any(t in intent_lower for t in _GPCR_TERMS):
        hints.append({
            "param": "sample_class",
            "recommended": "gpcr_g_protein",
            "rationale": "GPCR–G protein complexes use MSP1D1ΔH5 nanodiscs (POPC:POPG:POPE 3:1:1), apyrase to maintain GTP→GDP hydrolysis, and scFv16 to lock Gi interface. (Source: μOR Cell 2022, D1R PAM preprint 2025)",
            "tool": "CryoSPARC",
        })
    elif any(t in intent_lower for t in ("saposin", "nanodisc", "mfsd", "vmat", "slc", "membrane transporter", "membrane protein")):
        hints.append({
            "param": "sample_class",
            "recommended": "membrane_small",
            "rationale": "Membrane transporters in saposin nanodiscs are <60 kDa TM core — use 0.649 Å/pix and 3-picker strategy (blob+template+TOPAZ). Expect 2–5% particle yield from picked movies. (Source: MFSD2B preprint, VMAT2 Nature 2023)",
            "tool": "CryoSPARC",
        })
        hints.append({
            "param": "pixel_size",
            "recommended": "0.649",
            "rationale": "< 60 kDa membrane TM core requires 0.649 Å/pix at 130,000× on K3 to resolve secondary structure. (Source: MFSD2B 0.649 Å/pix; VMAT2 0.83 Å/pix for 55 kDa full transporter)",
            "tool": "CryoSPARC",
        })
    elif any(t in intent_lower for t in ("ribosome", "spliceosome", "rnp", "proteasome", "complex > 500", "megadalton")):
        hints.append({
            "param": "sample_class",
            "recommended": "large_rna_protein",
            "rationale": "> 500 kDa complexes use 1.06–1.30 Å/pix, defocus −1.5 to −3.0 μm, and 6-class ab initio to capture assembly heterogeneity. (Source: GENERAL_FRAMEWORK spliceosome / ribosome protocol)",
            "tool": "CryoSPARC",
        })
    elif any(t in intent_lower for t in ("bax", "pore", "gasdermin", "perforin", "liposome")):
        hints.append({
            "param": "sample_class",
            "recommended": "pore_forming",
            "rationale": "Pore-forming proteins form arc/ring shapes on liposomes — TOPAZ picking trained on arcs is mandatory. Validate pore activity with ANTS/DPX fluorescence lysis assay (>50% release) before cryo-EM. (Source: BAX pore Science 2025)",
            "tool": "CryoSPARC",
        })
    elif any(t in intent_lower for t in ("virus", "capsid", "icosahedral", "symmetric", "ring atpase")):
        hints.append({
            "param": "sample_class",
            "recommended": "symmetric",
            "rationale": "Symmetric assemblies: always start ab initio in C1, verify symmetry from 2D classes before imposing. Higher total dose (55 e⁻/Å²) tolerated for stable capsids. (Source: HBV/HFTV1 capsid protocol)",
            "tool": "CryoSPARC",
        })

    # ── Target resolution → particle count ─────────────────────────────────
    # Regex matches "3.5 angstrom", "3.5 å", "3.5 Å", or "3.5 resolution".
    # The bare "a\b" alternative was removed — it matched standalone letter "a"
    # causing false positives in sentences like "... at 3 a priori ...".
    tr_match = _re.search(r'(\d+(?:\.\d+)?)\s*(?:å|angstrom)', intent_lower)
    if not tr_match:
        tr_match = _re.search(r'(\d+(?:\.\d+)?)\s*resolution', intent_lower)
    if tr_match:
        tr = float(tr_match.group(1))
        if tr < 2.5:
            count_str = "> 1,000,000 particles"
        elif tr < 3.0:
            count_str = "200,000–1,000,000 particles"
        elif tr < 3.5:
            count_str = "50,000–200,000 particles"
        elif tr < 4.5:
            count_str = "20,000–50,000 particles"
        else:
            count_str = "5,000–20,000 particles"
        hints.append({
            "param": "target_resolution_A",
            "recommended": str(tr),
            "rationale": f"To reach {tr} Å resolution you need approximately {count_str}. (Source: GENERAL_FRAMEWORK V5 resolution-particle count table)",
            "tool": "CryoSPARC",
        })

    # ── Scientific question → dataset count ─────────────────────────────────
    # Reference: GENERAL_FRAMEWORK V3 — never collect drug-only; apo reference mandatory
    if any(t in intent_lower for t in ("drug", "ligand", "inhibitor", "agonist", "antagonist", "compound", "bound")):
        guidance.append(
            "DATASET RULE: Collect an apo (ligand-free) reference dataset in addition to drug-bound. "
            "Drug-only data cannot be interpreted without structural reference. "
            "For multiple drug conditions: N drug states + 1 apo = N+1 total datasets. "
            "Use difference maps (drug_map − apo_map) to isolate ligand density; "
            "accept ligand placement only at ≥ 4σ in the sharpened map. "
            "(Source: CaV1.2 Cell 2023 — 7 drug states + apo; GENERAL_FRAMEWORK V3)"
        )
    # "state" alone is too broad (matches "steady state", "oxidation state", etc.).
    # Require at least one explicit conformational biology term.
    if any(t in intent_lower for t in ("conformational", "open state", "closed state", "open and closed",
                                        "inactivat", "activat", "gating state", "apo state")):
        guidance.append(
            "CONFORMATIONAL STATES: Collect 2–4 datasets capturing distinct states "
            "(e.g., apo, agonist-bound, inhibitor-bound, inactivated). "
            "Use 3DVA (3D Variability Analysis) to decompose heterogeneity into principal components — "
            "first 3 components typically capture the major conformational motions. "
            "(Source: GENERAL_FRAMEWORK V3/V4)"
        )

    # ── Heterogeneity depth ─────────────────────────────────────────────────
    if any(t in intent_lower for t in ("heterogeneous", "flexible", "multi-state", "conformational ensemble")):
        hints.append({
            "param": "heterogeneity",
            "recommended": "medium",
            "rationale": "Medium heterogeneity: 6–8 3D classes + 3DVA on top 3 components. "
                         "For highly flexible samples (pore arcs, spliceosome intermediates): use 'high' — "
                         "multi-body refinement with 3–6 rigid bodies. (Source: GENERAL_FRAMEWORK V4)",
            "tool": "CryoSPARC",
        })

    # ── Universal invariants (always inject for cryo-EM) ────────────────────
    guidance.append(
        "UNIVERSAL RULES: (1) Always report resolution at FSC = 0.143 (gold-standard, Henderson et al. 2012) — "
        "never use 0.5 as primary criterion. "
        "(2) Collect negative-stain EM before cryo-EM to confirm complex assembly and particle size. "
        "(3) MolProbity < 2.0 required for PDB deposition; < 1.5 is excellent. "
        "(4) CTF FOM < 0.1 → discard micrograph regardless of particle count. "
        "(5) Ligand density valid only at ≥ 4σ in sharpened map."
    )

    # ── Pre-cryo-EM checklist (G1-G5) ────────────────────────────────────────
    # Only inject when the query suggests starting fresh (contains "structure of",
    # "determine structure", "solve structure", "cryo-em of", "run cryosparc",
    # "spa pipeline", or doesn't mention an existing dataset/run)
    _new_project_signals = [
        "structure of", "determine structure", "solve structure", "cryo-em of",
        "cryo em of", "spa pipeline", "run cryosparc", "new dataset",
        "fresh grid", "new sample", "just purified",
    ]
    _existing_data_signals = [
        "existing", "already collected", "reprocess", "re-process",
        "have the data", "have movies", "movies are", "micrographs are",
        "dataset ready", "empiar",
    ]
    _is_new_project = (
        any(s in intent_lower for s in _new_project_signals)
        and not any(s in intent_lower for s in _existing_data_signals)
    )
    if _is_new_project:
        guidance.append(
            "PRE-CRYO-EM CHECKLIST (complete before booking microscope time):\n"
            "G1 PURITY: Confirm >90% purity by SDS-PAGE; single symmetric SEC peak "
            "(no shoulders = no aggregation). A280/A260 < 0.6 indicates nucleic acid contamination.\n"
            "G2 CONCENTRATION: Target 3-5 mg/mL. Too dilute (<1 mg/mL) → sparse particles; "
            "too concentrated (>10 mg/mL for membrane proteins) → aggregation on grid.\n"
            "G3 NEGATIVE STAIN (mandatory): Run negative stain EM before cryo. Confirms: "
            "(a) complex assembled correctly, (b) expected particle size (~MW^(1/3) × 13.3 Å), "
            "(c) monodisperse (no aggregates). If negative stain fails, cryo-EM will fail.\n"
            "G4 FUNCTIONAL ASSAY: Confirm >50% activity after purification. "
            "Use: transport flux (SLC), BRET/FRET (GPCR), cAMP accumulation (Gs-coupled), "
            "cytochrome c release (BAX pore), ATPase activity (ring ATPases). "
            "Structural study of inactive protein = wasted beam time.\n"
            "G5 ICE QUALITY: Screen Vitrobot conditions (humidity 100%, temp 4°C, "
            "blot time 2-4 s, force 0-5). For membrane proteins: use fluorinated octyl maltoside "
            "(FOM) 0.02% to prevent preferred orientation. "
            "Check ice thickness by survey: should see individual particles, not a continuous layer.\n"
            "(Source: GENERAL_FRAMEWORK G1-G5; MFSD2B preprint blot conditions; VMAT2 Nature 2023)"
        )

    return {
        "cryo_em_domain_hints": hints,
        "cryo_em_guidance": guidance,
    }


def _validate_extracted_params(
    extracted: Dict[str, Any],
    all_params: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """
    Schema-level guardrail: reject or normalize param values that violate the workflow schema.

    For each extracted param:
    - If the schema has allowed_values (parsed from pipe-separated comment options),
      validate the extracted value against that list (case-insensitive).
    - If the value is not in the allowed set, drop it and log a warning.
    - If the value matches case-insensitively but uses wrong casing, correct it.

    Special-cases genome and strandedness via canonical alias maps even when
    the schema has no explicit allowed_values list (e.g., external tools).
    """
    # Build lookup: param_name → allowed_values list from schema
    allowed_map: Dict[str, List[str]] = {}
    for p in all_params:
        av = p.get("allowed_values", [])
        if av:
            allowed_map[p["name"]] = av

    # Always apply genome and strandedness canonical maps regardless of schema
    # (these are so common that hallucinations are very likely without them)
    _genome_canonical: Dict[str, str] = {}
    for canonical, aliases in {
        "GRCh38": {"hg38", "human", "homo_sapiens", "homo sapiens", "grch38", "grch38.p14", "homo_sapiens_grch38", "GRCh38"},
        "GRCh37": {"hg19", "grch37", "GRCh37"},
        "GRCm39": {"mm39", "mouse", "mus_musculus", "mus musculus", "grcm39", "mus_musculus_grcm39", "GRCm39"},
        "GRCm38": {"mm10", "grcm38", "GRCm38"},
        "Rnor_6.0": {"rnor6", "rnor_6.0", "rat", "rattus_norvegicus", "rattus norvegicus", "Rnor_6.0"},
        "GRCz11": {"grcz11", "zebrafish", "danio_rerio", "danio rerio", "GRCz11"},
        "BDGP6": {"bdgp6", "drosophila", "dm6", "drosophila_melanogaster", "drosophila melanogaster", "BDGP6"},
        "WBcel235": {"wbcel235", "c. elegans", "c.elegans", "caenorhabditis_elegans", "caenorhabditis elegans", "WBcel235"},
        "R64-1-1": {"r64-1-1", "r64", "saccharomyces_cerevisiae", "s. cerevisiae", "yeast", "s288c", "R64-1-1"},
        "TAIR10": {"tair10", "arabidopsis", "arabidopsis_thaliana", "arabidopsis thaliana", "at", "TAIR10"},
    }.items():
        _genome_canonical[canonical.lower()] = canonical
        for a in aliases:
            _genome_canonical[a.lower()] = canonical

    _strand_canonical: Dict[str, str] = {
        "reverse": "reverse", "rf": "reverse", "dutp": "reverse", "dUTP": "reverse",
        "forward": "forward", "fr": "forward", "ligation": "forward",
        "unstranded": "unstranded", "none": "unstranded", "no": "unstranded",
        "auto": "auto",
    }

    validated: Dict[str, Any] = {}
    for name, value in extracted.items():
        v_str = str(value).strip()

        # Genome: always normalize via canonical map
        if name == "genome":
            canonical = _genome_canonical.get(v_str.lower())
            if canonical:
                validated[name] = canonical
            else:
                log.warning("[ParamGuardrail] genome=%r not in canonical list — dropping", v_str)
                # Don't include unknown genome values — they will cause workflow failures
            continue

        # Strandedness: always normalize
        if name == "strandedness":
            canonical = _strand_canonical.get(v_str.lower())
            if canonical:
                validated[name] = canonical
            else:
                log.warning("[ParamGuardrail] strandedness=%r not recognized — dropping", v_str)
            continue

        # Schema-declared allowed values
        allowed = allowed_map.get(name, [])
        if allowed:
            match = next((a for a in allowed if a.lower() == v_str.lower()), None)
            if match:
                validated[name] = match  # use canonical casing from schema
            else:
                log.warning(
                    "[ParamGuardrail] %s=%r not in allowed values %s — dropping",
                    name, v_str, allowed,
                )
            continue

        # No schema constraint — keep as-is
        validated[name] = value

    return validated


def _rule_based_param_inference(user_intent: str, all_params: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    Deterministic pre-inference for common biological parameters.
    Runs before the LLM call to ensure consistent extraction of well-known mappings.
    These rules encode domain knowledge that is stable and unambiguous.
    """
    result: Dict[str, Any] = {}
    text = user_intent.lower()
    param_names = {p["name"] for p in all_params}

    # ── Organism → genome reference ─────────────────────────────────────────
    if "genome" in param_names:
        _genome_patterns = [
            # Explicit genome IDs
            (r'\b(GRCh38|hg38|GRCh38\.p\d+)\b', 'GRCh38'),
            (r'\b(GRCh37|hg19|GRCh37\.p\d+)\b', 'GRCh37'),
            (r'\b(GRCm39|mm39)\b', 'GRCm39'),
            (r'\b(GRCm38|mm10|GRCm38\.p\d+)\b', 'GRCm38'),
            (r'\b(Rnor_6\.0|rnor6|rnor_6)\b', 'Rnor_6.0'),
            (r'\b(GRCz11|grcz11|danio_rerio)\b', 'GRCz11'),
            (r'\b(BDGP6|bdgp6|drosophila_melanogaster|dm6)\b', 'BDGP6'),
            (r'\b(R64-1-1|r64|saccharomyces_cerevisiae|s288c)\b', 'R64-1-1'),
            (r'\b(TAIR10|tair10|arabidopsis_thaliana)\b', 'TAIR10'),
            (r'\b(WBcel235|wbcel235|caenorhabditis_elegans)\b', 'WBcel235'),
            # Organism names → canonical genome
            (r'\bhuman\b|\bhomo\s+sapiens\b|\bhuman\s+(?:cell|tissue|sample|patient|tumor|cancer|plasma|blood|brain|lung|liver|kidney|colon|breast|skin|heart|muscle|bone|ovary|prostate)\b', 'GRCh38'),
            # Clinical/patient context implies human samples
            (r'\bpatient\b|\bclinical\s+(?:trial|sample|cohort|specimen)\b|\bcolorectal\b|\badenocarcinoma\b|\bleukem\b|\blymphoma\b|\bmelanoma\b|\bglioma\b|\bglioblastoma\b|\borganoid.*(?:cancer|tumor|patient)\b', 'GRCh38'),
            (r'\bmouse\b|\bmurine\b|\bmus\s+musculus\b|\bC57BL\b|\bBALB/c\b|\bMDCK\b', 'GRCm39'),
            (r'\brat\b|\battus\s+norvegicus\b|\bSprague\b|\bWistar\b', 'Rnor_6.0'),
            (r'\bzebrafish\b|\bdanio\s+rerio\b|\bzebra\s+fish\b', 'GRCz11'),
            (r'\bdrosophila\b|\bfruit\s*fly\b|\bmelanogaster\b', 'BDGP6'),
            (r'\byeast\b|\bsaccharomyces\b|\bs\.\s*cerevisiae\b', 'R64-1-1'),
            (r'\barabidopsis\b|\bplant\b.*\bmodel\b|\bA\.\s*thaliana\b', 'TAIR10'),
            (r'\bC\.\s*elegans\b|\bworm\b|\bnematode\b', 'WBcel235'),
        ]
        import re as _re
        for pattern, genome_id in _genome_patterns:
            if _re.search(pattern, text, _re.IGNORECASE):
                result["genome"] = genome_id
                break

    # ── Strandedness ─────────────────────────────────────────────────────────
    if "strandedness" in param_names:
        import re as _re
        # Library prep kit → strandedness mapping (checked BEFORE generic terms)
        # These are well-established mappings in the field:
        _KIT_REVERSE = [
            r'TruSeq\s+Stranded',          # Illumina TruSeq Stranded mRNA/Total RNA = dUTP = reverse
            r'KAPA\s+Stranded',             # KAPA Stranded RNA-Seq = reverse
            r'NEBNext.*?Ultra.*?II.*?Direct', # NEBNext Ultra II Directional = reverse
            r'ribo-?zero.*?strand',    # Ribo-zero + any strand term (stranded, strand-specific, etc.)
            r'strand.*?ribo-?zero',
            r'Lexogen.*?SENSE',             # Lexogen SENSE = reverse
            r'SMARTer.*?Stranded',          # SMARTer Stranded = reverse
        ]
        _KIT_FORWARD = [
            r'ScriptSeq',                   # Epicentre ScriptSeq = forward
            r'Ovation\s+SoLo',              # Ovation SoLo = forward
            r'Ion\s+Total\s+RNA',           # Ion RNA library = forward
            r'Lexogen\s+CORALL',            # CORALL = forward
            r'NextFlex\s+Rapid\s+Directional', # NextFlex Directional = forward
            r'Directagen\s+forward',
        ]
        _KIT_UNSTRANDED = [
            r'SMART-?seq\s*(?:2|v2|v3|v4|Ultra|plate)',  # SMARTseq = unstranded (full-length)
            r'SMART-?seq\s+full',
            r'Clontech\s+SMARTer.*?PCR',
            r'TeloPrime',
            r'VN-seq',
            r'CEL-?seq',                    # CEL-seq = unstranded
            r'Drop-?seq',                   # Drop-seq = unstranded
            r'10[Xx]\s+Chromium.*?RNA',     # 10X Chromium = unstranded (scRNA-seq)
        ]
        _strand_found = False
        for pat in _KIT_REVERSE:
            if _re.search(pat, user_intent, _re.IGNORECASE):
                result["strandedness"] = "reverse"
                _strand_found = True
                break
        if not _strand_found:
            for pat in _KIT_FORWARD:
                if _re.search(pat, user_intent, _re.IGNORECASE):
                    result["strandedness"] = "forward"
                    _strand_found = True
                    break
        if not _strand_found:
            for pat in _KIT_UNSTRANDED:
                if _re.search(pat, user_intent, _re.IGNORECASE):
                    result["strandedness"] = "unstranded"
                    _strand_found = True
                    break
        if not _strand_found:
            # Fallback: generic terms
            if _re.search(r'\b(reverse|rf|dUTP|dutp|reverse.strand)\b', text, _re.IGNORECASE):
                result["strandedness"] = "reverse"
            elif _re.search(r'\b(forward|fr|ligation|forward.strand)\b', text, _re.IGNORECASE):
                result["strandedness"] = "forward"
            elif _re.search(r'\b(unstranded|no.strand|strand.unknown|non-stranded|full.length.*single.cell|random.hexamer|without\s+(?:strand|directionality))\b', text, _re.IGNORECASE):
                result["strandedness"] = "unstranded"

    # ── MACS genome size ─────────────────────────────────────────────────────
    if "macs_gsize" in param_names:
        if result.get("genome", "").startswith("GRCh"):
            result["macs_gsize"] = "hs"
        elif result.get("genome", "").startswith("GRCm"):
            result["macs_gsize"] = "mm"
        elif "BDGP" in result.get("genome", ""):
            result["macs_gsize"] = "dm"
        elif "WBcel" in result.get("genome", ""):
            result["macs_gsize"] = "ce"

    # ── MD simulation: unit conversion (LLM unreliable at arithmetic) ────────
    # "100 ns" + "2 fs timestep" → n_steps and dt
    # Rule: n_steps = length_ns * 1e6 / timestep_fs  (ns→fs = ×1e6, then ÷ step)
    #       dt = timestep_fs / 1000  (fs→ps for GROMACS)
    import re as _re
    _has_nsteps = "n_steps" in param_names
    _has_dt = "dt" in param_names
    if _has_nsteps or _has_dt:
        _len_ns = None
        _step_fs = None
        _m_ns = _re.search(r'(\d+(?:\.\d+)?)\s*ns\b', text, _re.IGNORECASE)
        _m_us = _re.search(r'(\d+(?:\.\d+)?)\s*[µu]s\b', text, _re.IGNORECASE)
        _m_fs = _re.search(r'(\d+(?:\.\d+)?)\s*fs\b', text, _re.IGNORECASE)
        _m_ps = _re.search(r'(\d+(?:\.\d+)?)\s*ps\b(?!\s*\d)', text, _re.IGNORECASE)
        if _m_ns:
            _len_ns = float(_m_ns.group(1))
        elif _m_us:
            _len_ns = float(_m_us.group(1)) * 1000
        if _m_fs:
            _step_fs = float(_m_fs.group(1))
        elif _m_ps:
            _step_fs = float(_m_ps.group(1)) * 1000  # ps → fs

        if _len_ns is not None:
            # Use extracted timestep or default 2 fs
            _ts = _step_fs if _step_fs is not None else 2.0
            if _has_nsteps and "n_steps" not in result:
                result["n_steps"] = int(_len_ns * 1_000_000 / _ts)
            if _has_dt and "dt" not in result and _step_fs is not None:
                result["dt"] = round(_step_fs / 1000, 6)  # fs → ps

    # ── Sequencing coverage (WGS/WES) ────────────────────────────────────────
    if "genome_coverage" in param_names and "genome_coverage" not in result:
        _m_cov = _re.search(r'(\d+)\s*[xX×]\s*(?:coverage|depth|sequencing)', text)
        if not _m_cov:
            _m_cov = _re.search(r'(?:coverage|depth)\s+(?:of\s+)?(\d+)\s*[xX×]?', text)
        if _m_cov:
            result["genome_coverage"] = int(_m_cov.group(1))

    # ── Negation patterns: "remove X" / "no X" → keep_x=False ───────────────
    if "keep_mito" in param_names and "keep_mito" not in result:
        if _re.search(r'(?:remove|filter|exclude|strip|discard)\s+(?:mitochondrial|mito)\b', text, _re.IGNORECASE):
            result["keep_mito"] = False
        elif _re.search(r'(?:no|without)\s+(?:mitochondrial|mito)\b', text, _re.IGNORECASE):
            result["keep_mito"] = False

    # ── Library type: single-end / paired-end ────────────────────────────────
    # Check paired-end FIRST so "not single-end" matches paired-end, not single_end=True
    if "single_end" in param_names and "single_end" not in result:
        if _re.search(r'\bpaired.end\b|\bpaired\s+end\b|not\s+single.end', text, _re.IGNORECASE):
            result["single_end"] = False
        elif _re.search(r'\bsingle.end\b|\bSE\s+reads\b|\bsingle\s+end\b', text, _re.IGNORECASE):
            result["single_end"] = True

    if "paired_end" in param_names and "paired_end" not in result:
        if _re.search(r'\bpaired.end\b|\bPE\b|\bpaired\s+end\b', text, _re.IGNORECASE):
            result["paired_end"] = True
        elif _re.search(r'\bsingle.end\b|\bSE\b|\bsingle\s+end\b', text, _re.IGNORECASE):
            result["paired_end"] = False

    # ── WES mode (whole exome sequencing) ────────────────────────────────────
    if "wes" in param_names and "wes" not in result:
        if _re.search(r'\bWES\b|\bwhole.exome\b|\bexome\s+(?:seq|sequencing|capture)\b', text, _re.IGNORECASE):
            result["wes"] = True

    # ── Variant calling tool selection ────────────────────────────────────────
    if "tools" in param_names and "tools" not in result:
        # Mutect2: for somatic / tumor-only calling
        if _re.search(r'\bmutect2?\b|\btumor.only\b|\bno\s+matched\s+normal\b|\bsomatic.*no.*normal\b', text, _re.IGNORECASE):
            result["tools"] = "mutect2"
        # HaplotypeCaller: germline calling (includes joint genotyping via GVCF)
        elif _re.search(r'\bhaplotypecaller\b|\bgermline\s+variant\b|\bjoint.*germline\b|\bGVCF\b|\bjoint\s+genotyping\b|\bcohort\s+genotyping\b|\bgermline\s+(?:single|variant|snp|indel|calling|wgs|wes)\b|\bsingle\s+sample.*germline\b|\bgermline.*single\s+sample\b', text, _re.IGNORECASE):
            result["tools"] = "haplotypecaller"

    # ── Pseudo-aligner ────────────────────────────────────────────────────────
    if "pseudo_aligner" in param_names and "pseudo_aligner" not in result:
        if _re.search(r'\bsalmon\b|\bpseudo.align\b.*salmon|salmon.*\bpseudo', text, _re.IGNORECASE):
            result["pseudo_aligner"] = "salmon"
        elif _re.search(r'\bkallisto\b', text, _re.IGNORECASE):
            result["pseudo_aligner"] = "kallisto"

    # ── Broad vs narrow peak calling (ChIP-seq/ATAC-seq) ─────────────────────
    # Uses macs2_broad if present; falls back to narrow_peak
    _broad_key = "macs2_broad" if "macs2_broad" in param_names else ("narrow_peak" if "narrow_peak" in param_names else None)
    if _broad_key and _broad_key not in result:
        _broad_marks = r'H3K27me3|H3K9me3|H3K27ac|H3K4me1|H3K36me3|broad\s+histone|broad\s+mark|broad\s+peak'
        _narrow_marks = r'H3K4me3|H3K9ac|H3K36me2|transcription\s+factor|TF\s+binding|narrow\s+peak|sharp\s+peak'
        if _re.search(_broad_marks, user_intent, _re.IGNORECASE):
            result[_broad_key] = True if _broad_key == "macs2_broad" else False
        elif _re.search(_narrow_marks, user_intent, _re.IGNORECASE):
            result[_broad_key] = False if _broad_key == "macs2_broad" else True

    # ── 16S amplicon region ────────────────────────────────────────────────────
    if "region" in param_names and "region" not in result:
        _m_region = _re.search(r'\b(V[1-9](?:-V[1-9])?)\b', user_intent)
        if _m_region:
            result["region"] = _m_region.group(1).upper()

    # ── UMI-based library ─────────────────────────────────────────────────────
    if "with_umi" in param_names and "with_umi" not in result:
        if _re.search(r'\bUMI\b|\bunique\s+molecular\s+identifier', user_intent, _re.IGNORECASE):
            result["with_umi"] = True

    # ── Joint germline calling ────────────────────────────────────────────────
    if "joint_germline" in param_names and "joint_germline" not in result:
        if _re.search(r'\bjoint\s+(?:germline|genotyping|calling)\b|\bmulti.?sample.*germline\b', text, _re.IGNORECASE):
            result["joint_germline"] = True

    # ── scRNA-seq protocol (10x Genomics version) ────────────────────────────
    # nf-core/scrnaseq uses 'protocol' (values: 10XV3, 10XV2, dropseq, etc.)
    _protocol_key = "protocol" if "protocol" in param_names else ("chemistry" if "chemistry" in param_names else None)
    if _protocol_key and _protocol_key not in result:
        if _re.search(r'10[xX]\s*(?:Genomics\s*)?(?:Chromium\s*)?v?3\.?1?|Chromium\s*v?3\.?1?\b|10[xX]v3', user_intent, _re.IGNORECASE):
            result[_protocol_key] = "10XV3"
        elif _re.search(r'10[xX]\s*(?:Genomics\s*)?(?:Chromium\s*)?v?2\.?0?|Chromium\s*v?2\.?0?\b|10[xX]v2', user_intent, _re.IGNORECASE):
            result[_protocol_key] = "10XV2"
        elif _re.search(r'\bDrop-?seq\b|\bDrop\s+seq\b', user_intent, _re.IGNORECASE):
            result[_protocol_key] = "dropseq"

    # ── scRNA-seq aligner ─────────────────────────────────────────────────────
    if "aligner" in param_names and "aligner" not in result:
        if _re.search(r'\bDrop-?seq\b|\bDrop\s+seq\b', user_intent, _re.IGNORECASE):
            result["aligner"] = "star"
        elif _re.search(r'\bkallisto\b|\bkb.?python\b|\bkb-?python\b', user_intent, _re.IGNORECASE):
            result["aligner"] = "kallisto"
        elif _re.search(r'\bSTARsolo\b|\bSTAR\s+solo\b', user_intent, _re.IGNORECASE):
            result["aligner"] = "star"

    # ── Ampliseq: known primer sequences ─────────────────────────────────────
    # Maps standard primer names to their sequences so users can say "341F/806R"
    _PRIMER_MAP = {
        r'341F.*806R|806R.*341F|V3.V4': ('CCTACGGGNGGCWGCAG', 'GACTACNVGGGTWTCTAATCC'),
        r'515F.*806R|806R.*515F|V4\b(?!\s*-\s*V[56])': ('GTGYCAGCMGCCGCGGTAA', 'GGACTACNVGGGTWTCTAAT'),
        r'27F.*534R|534R.*27F|V1.V3': ('AGAGTTTGATCMTGGCTCAG', 'ATTACCGCGGCTGCTGG'),
        r'515F.*926R|926R.*515F|V4.V5': ('GTGYCAGCMGCCGCGGTAA', 'CCGYCAATTYMTTTRAGTTT'),
    }
    if "FW_primer" in param_names and "FW_primer" not in result:
        for pat, (fw, rv) in _PRIMER_MAP.items():
            if _re.search(pat, user_intent, _re.IGNORECASE):
                result["FW_primer"] = fw
                if "RV_primer" in param_names and "RV_primer" not in result:
                    result["RV_primer"] = rv
                break

    # ── Known adapter sequences ───────────────────────────────────────────────
    _ADAPTER_MAP = {
        r'Nextera\s*(?:XT|Rapid\s*Transposase|transposase)': 'CTGTCTCTTATACACATCT',
        r'TruSeq\s*(?:Universal|HT|CD)': 'AGATCGGAAGAGC',
        r'Nextera\s*(?:v2|v2\s+adapter|Flex)': 'CTGTCTCTTATACACATCT',
    }
    for clip_param in ('clip_r1', 'adapter_r1', 'adapter1'):
        if clip_param in param_names and clip_param not in result:
            for pat, seq in _ADAPTER_MAP.items():
                if _re.search(pat, user_intent, _re.IGNORECASE):
                    result[clip_param] = seq
                    break
            break

    # ── Proteomics: database selection ───────────────────────────────────────
    if "database" in param_names and "database" not in result:
        if _re.search(r'UniProt\s*Swiss.?Prot|Swiss.?Prot\s*curated|swissprot', user_intent, _re.IGNORECASE):
            result["database"] = "uniprot_swissprot"
        elif _re.search(r'UniProt\s*TrEMBL|TrEMBL|unreviewed', user_intent, _re.IGNORECASE):
            result["database"] = "uniprot_trembl"
        elif _re.search(r'\bUniRef\s*100\b', user_intent, _re.IGNORECASE):
            result["database"] = "uniref100"

    # ── Proteomics: isobaric labeling reagent ─────────────────────────────────
    if "labeling_reagent" in param_names and "labeling_reagent" not in result:
        _TMT_PAT = {
            r'TMT.?16|16.?plex.*TMT|TMT.*16.?plex': 'TMT16plex',
            r'TMT.?11|11.?plex.*TMT|TMT.*11.?plex': 'TMT11plex',
            r'TMT.?10|10.?plex.*TMT|TMT.*10.?plex': 'TMT10plex',
            r'TMT.?6|6.?plex.*TMT|TMT.*6.?plex': 'TMT6plex',
            r'\bTMT\b(?!\d)': 'TMT6plex',  # plain TMT → default 6-plex
            r'iTRAQ.?8|8.?plex.*iTRAQ|iTRAQ.*8.?plex': 'iTRAQ8plex',
            r'iTRAQ.?4|4.?plex.*iTRAQ|iTRAQ.*4.?plex': 'iTRAQ4plex',
        }
        for pat, reagent in _TMT_PAT.items():
            if _re.search(pat, user_intent, _re.IGNORECASE):
                result["labeling_reagent"] = reagent
                break

    # ── Mass spec quantification method / labeling type ──────────────────────
    for _qm_key in ("quantification_method", "lib"):
        if _qm_key in param_names and _qm_key not in result:
            if _re.search(r'\bSILAC\b|\bstable\s+isotope\s+label', user_intent, _re.IGNORECASE):
                result[_qm_key] = "SILAC"
            elif _re.search(r'\bTMT\b|\biTRAQ\b|\bisobaric', user_intent, _re.IGNORECASE):
                result[_qm_key] = "isobaric"
            elif _re.search(r'\bLFQ\b|\blabel.free\b|\blabel\s+free', user_intent, _re.IGNORECASE):
                result[_qm_key] = "LFQ"
            break

    # ── Ribo-zero strand-specific → reverse strandedness ─────────────────────
    # (added to _KIT_REVERSE check above, but also catch here as fallback)
    if "strandedness" in param_names and "strandedness" not in result:
        if _re.search(r'ribo.?zero.*strand|strand.?spec.*ribo.?zero|strand.?spec.*RNA.?seq', user_intent, _re.IGNORECASE):
            result["strandedness"] = "reverse"

    # ── CryoSPARC defocus range ───────────────────────────────────────────────
    _has_defocus_min = "defocus_min_um" in param_names
    _has_defocus_max = "defocus_max_um" in param_names
    if _has_defocus_min or _has_defocus_max:
        _m_defocus = _re.search(r'defocus\s+range\s+(\d+\.?\d*)\s+to\s+(\d+\.?\d*)', user_intent, _re.IGNORECASE)
        if not _m_defocus:
            _m_defocus = _re.search(r'(\d+\.?\d*)\s+to\s+(\d+\.?\d*)\s*(?:µm|um|micrometer)', user_intent, _re.IGNORECASE)
        if _m_defocus:
            if _has_defocus_min and "defocus_min_um" not in result:
                result["defocus_min_um"] = float(_m_defocus.group(1))
            if _has_defocus_max and "defocus_max_um" not in result:
                result["defocus_max_um"] = float(_m_defocus.group(2))

    # ── CryoSPARC symmetry ───────────────────────────────────────────────────
    if "symmetry" in param_names and "symmetry" not in result:
        _m_sym = _re.search(r'\b([CDIT]\d*|O\b|I[12]?)\s*symmetry\b|\bsymmetry\s+([CDIT]\d*|O\b|I[12]?)\b|\b(asymmetric|C1)\b', user_intent, _re.IGNORECASE)
        if _m_sym:
            _sym_val = _m_sym.group(1) or _m_sym.group(2) or _m_sym.group(3)
            if _sym_val and 'asymmetric' in _sym_val.lower():
                result["symmetry"] = "C1"
            elif _sym_val:
                result["symmetry"] = _sym_val.upper()

    # ── GPU acceleration flag ─────────────────────────────────────────────────
    if "gpu_acceleration" in param_names and "gpu_acceleration" not in result:
        if _re.search(r'\bno\s+GPU\b|\bCPU.?only\b|\bno\s+gpu\s+accel', user_intent, _re.IGNORECASE):
            result["gpu_acceleration"] = False
        elif _re.search(r'\bGPU\b|\bgpu\s+accel', user_intent, _re.IGNORECASE):
            result["gpu_acceleration"] = True

    # ── narrow_peak from ChIP-seq context ────────────────────────────────────
    if "narrow_peak" in param_names and "narrow_peak" not in result:
        if _re.search(r'\bnarrow\s+peak|TF\s+binding|transcription\s+factor', user_intent, _re.IGNORECASE):
            result["narrow_peak"] = True
        elif _re.search(r'\bbroad\s+peak|broad\s+domain|H3K27me3|H3K9me3', user_intent, _re.IGNORECASE):
            result["narrow_peak"] = False

    # ── q-value threshold (peak calling) ─────────────────────────────────────
    if "qvalue" in param_names and "qvalue" not in result:
        _m_q = _re.search(r'q.?value\s+(?:of\s+)?(\d+\.?\d*)|(\d+\.?\d*)\s+q.?value', user_intent, _re.IGNORECASE)
        if _m_q:
            result["qvalue"] = float(_m_q.group(1) or _m_q.group(2))

    # ── "not single-end" / "paired-end" as single_end: False ─────────────────
    # Extra rule: "not single-end" explicitly → single_end=False
    if "single_end" in param_names and "single_end" not in result:
        if _re.search(r'not\s+single.end|paired.end\s+(?:library|reads|ChIP|RNA)', user_intent, _re.IGNORECASE):
            result["single_end"] = False

    # ── Coverage rules (sarek target_coverage, ampliseq) ─────────────────────
    if "target_coverage" in param_names and "target_coverage" not in result:
        _m_tc = _re.search(r'(\d{3,})\s*[xX×]\s*(?:coverage|depth|amplicon|panel)', user_intent, _re.IGNORECASE)
        if not _m_tc:
            _m_tc = _re.search(r'(?:coverage|depth)\s+(?:of\s+)?(\d{3,})\s*[xX×]?', user_intent, _re.IGNORECASE)
        if _m_tc:
            result["target_coverage"] = int(_m_tc.group(1))

    return result


def _infer_params_from_intent_llm(
    user_intent: str,
    workflow_name: str,
    all_params: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Extract parameter values from user's natural language message.

    Step 1: deterministic rule-based inference for well-known biological params.
    Step 2: LLM-based extraction for remaining explicit values in the message.

    Falls back silently to {} on any error or when ANTHROPIC_API_KEY is unset.
    """
    # Step 1: deterministic rules (always runs, no API cost)
    result = _rule_based_param_inference(user_intent, all_params)

    api_key = _os.getenv("ANTHROPIC_API_KEY")
    if not api_key or not all_params:
        return result

    # Skip params that cannot come from natural language
    _SKIP_TYPES = {"file", "boolean"}
    _SKIP_SUFFIXES = ("_path", "_file", "_dir", "_bam", "_fastq", "_fasta", "_vcf", "_gtf", "_bed")
    # Skip purely technical/infra params the user never sets in prose
    _SKIP_NAMES = {"outdir", "publish_dir_mode", "randomSeed", "random_seed", "max_memory", "max_cpus", "max_time"}
    extractable = [
        p for p in all_params
        if not str(p.get("type", "")).lower() in _SKIP_TYPES
        and not any(p["name"].endswith(s) for s in _SKIP_SUFFIXES)
        and p["name"] not in _SKIP_NAMES
    ]
    if not extractable:
        return result

    # Exclude params already filled by rule-based step
    extractable = [p for p in extractable if p["name"] not in result]
    if not extractable:
        return result

    # Show current defaults so the LLM knows what to replace
    param_descriptions = "\n".join(
        f'  - "{p["name"]}": {p.get("description") or p.get("label") or p["name"]}'
        + (f' (current default: {p["default"]})' if p.get("default") is not None else ' (required)')
        for p in extractable
    )

    prompt = f"""You are extracting workflow parameter values from a bioinformatics research request.

Workflow: {workflow_name}
User message: {user_intent}

Parameters to check (ONLY extract if the user explicitly provides a different value than the current default):
{param_descriptions}

Rules:
- Return ONLY parameters explicitly stated by the user. Never infer or guess.
- For text search queries, extract the search string.
- For gene names, extract the gene symbol (e.g. "TP53").
- For SMILES strings, extract the full SMILES.
- For PDB IDs, extract the 4-character code (e.g. "1M17", "6OIM").
- For protein sequences, extract the full sequence string.
- For numeric params (exhaustiveness, max_spots, n_iter, etc.), extract the number.
- For coordinate arrays like box_center, extract as a JSON array (e.g. [22.0, 2.5, 17.0]).
- For box_size when given as a single number N, return [N, N, N].
- For enum/select params, extract the most appropriate option.
- If a value equals the current default, do NOT include it unless the user explicitly named it.
- If a value is not clearly present in the message, do NOT include that parameter.

Return ONLY a JSON object, no markdown, no explanation.
Example: {{"pdb_id": "1M17", "ligand_smiles": "C#Cc1cccc(Nc2ncnc3cc(OCCO)c(OCCO)cc23)c1", "exhaustiveness": 4, "box_center": [22.0, 2.5, 17.0], "box_size": [20.0, 20.0, 20.0]}}"""

    try:
        from galaxy.ai.gemini_flash import call_gemini_flash as _gemini_flash  # noqa: PLC0415
        raw = _gemini_flash(
            messages=[{"role": "user", "content": prompt}],
            max_tokens=400,
            temperature=0.0,
        ).strip()
        raw = raw.replace("```json", "").replace("```", "").strip()
        extracted = json.loads(raw)
        if isinstance(extracted, dict):
            llm_result: Dict[str, Any] = {}
            for k, v in extracted.items():
                if isinstance(v, (int, float, bool)):
                    llm_result[str(k)] = v
                elif isinstance(v, list):
                    # Keep lists as strings using JSON-style repr so Nextflow
                    # receives "--param '[x, y, z]'" on the CLI.
                    llm_result[str(k)] = json.dumps(v)
                else:
                    llm_result[str(k)] = str(v)
            # Merge: rule-based results take priority (deterministic, validated).
            # LLM only fills params the rule-based step did NOT handle.
            for k, v in llm_result.items():
                result.setdefault(k, v)
    except Exception as exc:
        log.debug("_infer_params_from_intent_llm failed (%s) — no pre-fill", exc)
    # Guardrail: validate all extracted values against schema allowed_values and
    # canonical alias maps. Drops or normalizes values that would cause workflow failures.
    return _validate_extracted_params(result, all_params)


class RankedSearchRequest(BaseModel):
    query: str
    limit: int = 10
    preferred_domains: Optional[List[str]] = None


@router.post(
    "/api/ai_assistant/search_ranked",
    summary="Return a ranked list of workflows for IR evaluation (MRR/P@K/NDCG)."
)
def search_ranked(
    request: RankedSearchRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Return a ranked list of up to `limit` workflows for a query.

    Used by the IR evaluation layer to compute MRR, P@K, and NDCG@K without
    going through the full chat pipeline.  Includes chain candidates (returned
    first with type='chain') followed by individual workflow matches.

    Response:
      {
        "results": [
          {"rank": 1, "name": "nf-core/rnaseq", "display_name": "...",
           "description": "...", "source": "nfcore", "format": "nextflow",
           "score": 14.3, "type": "workflow"},
          ...
        ],
        "query": "..."
      }
    """
    if not _workflow_search:
        raise HTTPException(status_code=503, detail="Workflow search not available")

    ranked: List[Dict[str, Any]] = []

    # Individual workflow results (primary ranking signal)
    try:
        wf_results = _workflow_search.search(
            request.query,
            limit=request.limit,
            preferred_domains=request.preferred_domains or None,
        )
        for r in wf_results:
            ranked.append({
                "rank": 0,
                "name": r.name,
                "display_name": getattr(r, "display_name", None) or r.name,
                "description": (getattr(r, "description", None) or "")[:200],
                "source": getattr(r, "source", ""),
                "format": getattr(r, "format", ""),
                "score": round(r.score, 3),
                "type": "workflow",
            })
    except Exception as exc:
        log.warning("[search_ranked] workflow search failed: %s", exc)

    # Chains: appended after workflows so individual workflow rankings are not
    # displaced.  Chain search requires LLM confirmation; without a wired-up LLM
    # client on the singleton used by this endpoint the chain would be selected by
    # embedding similarity alone and always appear rank-1, corrupting IR metrics.
    try:
        chain_results = _workflow_search.search_chains(request.query, min_score=0.35, limit=3)
        for c in chain_results:
            ranked.append({
                "rank": 0,  # will be set below
                "name": c.name,
                "display_name": c.display_name or c.name,
                "description": (c.description or "")[:200],
                "source": "chain",
                "format": "chain",
                "score": None,  # chains use cosine similarity, not raw score
                "type": "chain",
            })
    except Exception as exc:
        log.warning("[search_ranked] chain search failed: %s", exc)

    # Assign ranks
    for i, item in enumerate(ranked):
        item["rank"] = i + 1

    return {"query": request.query, "results": ranked}


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
        # Use min_score=0.35 to avoid weak-overlap false positives.
        # The internal default of 0.15 is too permissive — direct single-pipeline
        # queries (e.g. "germline variant calling") would otherwise match complex
        # chains (e.g. rare_disease_multimodal_workup) via 2-3 shared tokens.
        chain_candidates = [] if request.skip_chains else _workflow_search.search_chains(user_intent, min_score=0.35)
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
        # ── Forced workflow (bypasses search for param-extraction benchmarks) ──
        if request.force_workflow_name:
            # Search by exact name match — used by param_prefill benchmark to
            # ensure param extraction is tested on the correct workflow regardless
            # of how routing would normally classify the query.
            forced_results = _workflow_search.search(
                request.force_workflow_name, limit=5, include_workflow_json=False,
            )
            if forced_results:
                # Prefer exact name match
                _forced = next(
                    (r for r in forced_results
                     if getattr(r, "name", "").lower() == request.force_workflow_name.lower()),
                    forced_results[0],
                )
                results = [_forced]
            else:
                results = []
        else:
            # ── Individual Nextflow workflow search ──────────────────────────────
            results = _workflow_search.search(
                user_intent, limit=5, include_workflow_json=False,
                preferred_domains=request.preferred_domains or None,
                key_terms=request.key_terms or None,
            )
        if not results:
            return {"success": False, "message": "No matching workflows found"}

        def _is_executable_nextflow_match(match: Any) -> bool:
            if getattr(match, "format", "") != "nextflow":
                return False
            filename = (getattr(match, "filename", "") or "").lower()
            name = (getattr(match, "name", "") or "").lower()
            tags = [str(t).lower() for t in (getattr(match, "tags", []) or [])]

            # Exclude subworkflow library paths — any path containing /subworkflows/ is
            # a pipeline component, not a standalone entry point the user would run directly.
            if "/subworkflows/" in filename:
                return False
            if filename.startswith("nf-core-modules/"):
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

        # Helper: resolve a DB filename to an absolute path, checking biomni_workflows/ and
        # nf-core-workflows/ prefixes.  nf-core DB entries use 'nfcore/<pipeline>/main.nf'
        # but the actual files live under 'backend/nf-core-workflows/<pipeline>/main.nf'.
        def _nf_file_exists(fname: str) -> bool:
            if not fname:
                return False
            _root = FilePath(__file__).resolve().parents[5]
            _backend = _root / "backend"
            # Strip leading 'nfcore/' to get bare pipeline path for nf-core-workflows lookup
            _nfcore_bare = fname.removeprefix("nfcore/") if fname.startswith("nfcore/") else None
            candidates = [
                FilePath(fname) if FilePath(fname).is_absolute() else _root / fname,
                _root / "biomni_workflows" / fname,
                _root / "biomni_workflows" / "nextflow_nfcore" / fname,
                _backend / "biomni_workflows" / fname,
                _backend / "biomni_workflows" / "nextflow_nfcore" / fname,
            ]
            if _nfcore_bare:
                candidates += [
                    _backend / "nf-core-workflows" / _nfcore_bare,
                    _root / "nf-core-workflows" / _nfcore_bare,
                ]
            for candidate in candidates:
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

        # Inject cryo-EM domain knowledge when the matched workflow is CryoSPARC SPA
        _is_cryoem_spa = (
            "cryosparc" in (best.name or "").lower()
            or "cryosparc" in (best.filename or "").lower()
            or "cryo_em" in (best.domain or "").lower()
            or "cryo-em" in (best.description or "").lower()
        )
        if _is_cryoem_spa:
            _cryo_extra = _build_cryoem_rationale(user_intent)
            if not isinstance(scientific_rationale, dict):
                scientific_rationale = {}
            # Merge domain hints into parameter_hints
            existing_hints = scientific_rationale.get("parameter_hints", [])
            existing_hint_params = {h.get("param") for h in existing_hints}
            for _h in _cryo_extra.get("cryo_em_domain_hints", []):
                if _h.get("param") not in existing_hint_params:
                    existing_hints.append(_h)
            scientific_rationale["parameter_hints"] = existing_hints
            # Add guidance as key_assumptions (surfaced in the AI rationale panel)
            existing_ka = scientific_rationale.get("key_assumptions", [])
            for _g in _cryo_extra.get("cryo_em_guidance", []):
                if _g not in existing_ka:
                    existing_ka.append(_g)
            scientific_rationale["key_assumptions"] = existing_ka

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
            _entry: dict = {
                "name": _pname,
                "label": _pmeta.get("label", _pname.replace("_", " ").title()),
                "description": _pmeta.get("label", _pname.replace("_", " ").title()),
                "default": _wf_parameters.get(_pname),
            }
            if _pmeta.get("group"):
                _entry["group"] = _pmeta["group"]
            if _pmeta.get("level") == "required":
                _req_params.append(_entry)
            else:
                _opt_params.append(_entry)

        # Inject SRA accession into reads param when user provided one.
        # Keeps reads in required_params (correct semantics) but sets default so the viewer
        # pre-fills the field and the Run button is not blocked (hasUnfilledRequired uses p.value).
        _sra_accession = re.search(r'\b([SED]RR\d{6,9}|GSE\d{4,9}|GSM\d{4,9}|E-MTAB-\d{4,9}|PXD\d{4,9})\b', user_intent, re.IGNORECASE)
        if _sra_accession:
            _acc = _sra_accession.group(1).upper()
            _req_params = [
                {**_p, 'default': _acc, 'sra_accession': True}
                if _p['name'] in ('reads', 'input', 'fastq', 'sample', 'reads1', 'reads2')
                else _p
                for _p in _req_params
            ]

        # LLM-based extraction: fill any remaining unfilled params from natural language
        _llm_extracted = _infer_params_from_intent_llm(
            user_intent, best.name, _req_params + _opt_params
        )
        if _llm_extracted:
            def _apply_llm_fill(params: list) -> list:
                result = []
                for p in params:
                    if p['name'] in _llm_extracted:
                        # Apply LLM extraction regardless of existing defaults —
                        # the user explicitly stated this value in their query so it
                        # should override the workflow schema default (e.g. pdb_id,
                        # ligand_smiles, exhaustiveness, etc.)
                        result.append({**p, 'default': str(_llm_extracted[p['name']]), 'llm_extracted': True, 'autoFilled': True})
                    else:
                        result.append(p)
                return result
            _req_params = _apply_llm_fill(_req_params)
            _opt_params = _apply_llm_fill(_opt_params)
            log.info("LLM param extraction for %s: filled/overrode %s", best.name, list(_llm_extracted.keys()))

        # Only treat params as "missing" if they have no pre-filled default (e.g. SRR accession injected)
        _truly_missing = [p for p in _req_params if not p.get('default')]
        _prereq_validation = None
        if _truly_missing:
            _prereq_validation = {
                "requirements": {
                    "parameters": [
                        {"stepId": "workflow", "paramName": p["name"], "optional": False, "defaultValue": None}
                        for p in _truly_missing
                    ]
                },
                "analysis": {
                    "missingInputs": [],
                    "missingParameters": [{"stepId": "workflow", "paramName": p["name"]} for p in _truly_missing],
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
    session_datasets: Optional[List[Dict[str, Any]]] = Field(None, description="User's actual session-uploaded datasets")
    preferred_domains: Optional[List[str]] = Field(None, description="LLM-inferred domain preferences for search ranking")
    penalized_domains: Optional[List[str]] = Field(None, description="LLM-inferred domains to penalize in search ranking")
    key_terms: Optional[List[str]] = Field(None, description="LLM-extracted technical terms to boost FTS recall")
    credential_map: Optional[Dict[str, bool]] = Field(None, description="Per-tool credential availability (True=available, False=not). When provided, takes precedence over server-side vault lookup.")


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


class DatabaseQueryRequest(BaseModel):
    database: str = Field(default="auto", description="Target database name or 'auto' to detect from query")
    query: str = Field(..., description="Search term or entity identifier")


@router.post(
    "/api/databases/query",
    summary="Query a biological database (UniProt, NCBI Gene, KEGG, PDB, etc.)"
)
def query_biological_database(
    request: DatabaseQueryRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Route a biological entity query to the appropriate public REST API.
    Supports: auto (detect from query), ncbi_gene, uniprot, pdb, alphafold,
              kegg, reactome, go, hpo, chebi, chembl, interpro, string,
              ensembl, gnomad, dbsnp, clinvar, pubmed.
    """
    ai = get_ai_assistant(trans)
    if not ai:
        return {"success": False, "error": "AI assistant not available"}
    try:
        return ai.query_database(request.database, request.query)
    except Exception as e:
        import traceback
        log.warning(f"[databases/query] {request.database}({request.query}): {e}")
        return {"success": False, "error": str(e), "traceback": traceback.format_exc()}


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


@router.get(
    "/api/ai_assistant/workflow_catalog",
    summary="Catalog statistics: workflow counts by source + chain count."
)
def workflow_catalog_stats(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Return indexed workflow counts and chain count for health monitoring."""
    try:
        if not WORKFLOW_SEARCH_AVAILABLE or not _workflow_search:
            return {"error": "Workflow search not available", "total_workflows": 0}
        stats = _workflow_search.get_stats()
        chain_count = stats.get("chains", {}).get("total", 0)
        return {
            "total_workflows": stats.get("total", 0),
            "by_source": stats.get("by_source", {}),
            "by_format": stats.get("by_format", {}),
            "chain_count": chain_count,
        }
    except Exception as exc:
        log.error("workflow_catalog_stats error: %s", exc)
        return {"error": str(exc), "total_workflows": 0}


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
        # uploaded_datasets = user's actual session-uploaded files (threaded from
        # req.session.uploadedDatasets via enrichedContext.sessionDatasets → session_datasets).
        # request.available_datasets contains BioMNI public reference datasets used for
        # knowledge retrieval — NOT user input files.
        uploaded_datasets = request.session_datasets or None
        import sys
        print(f"[DEBUG generate_workflow] session_datasets={request.session_datasets}", file=sys.stderr, flush=True)
        print(f"[DEBUG generate_workflow] uploaded_datasets={uploaded_datasets}", file=sys.stderr, flush=True)

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
        # Guard: only inject when the prior pipeline is TOPICALLY related to the current query.
        # Extracting meaningful tokens from the workflow path and checking overlap prevents
        # cross-domain contamination (e.g. a Schrodinger docking session bleeding into ADMET queries).
        effective_intent = request.request_text
        _NOISE_WORDS = {"main", "nf", "nextflow", "nfcore", "subworkflows", "biomni", "core", "pipeline", "workflow"}

        def _workflow_tokens(wf_name: str) -> set:
            import re as _re
            raw = wf_name.lower()
            tokens: set = set()
            for part in _re.split(r"[/_\-\.]", raw):
                part = part.strip()
                if len(part) >= 3 and part not in _NOISE_WORDS:
                    tokens.add(part)
            return tokens

        def _query_is_related_to_prior(query: str, wf_name: str) -> bool:
            wf_tokens = _workflow_tokens(wf_name)
            q_lower = query.lower()
            return any(tok in q_lower for tok in wf_tokens)

        # "pending" means the step was generated but the run never started (the frontend
        # executes independently). Only inject context for genuinely active runs.
        _ACTIVE_STATUSES = {"running", "paused"}

        if _session_store:
            try:
                sess = _session_store.get(session_id)
                if sess and sess.steps:
                    last_step = sess.steps[-1]
                    # Only inject context when the prior run is still active — completed/failed
                    # runs represent finished work; injecting them causes the LLM to treat a
                    # new query as a continuation of the old task instead of a fresh request.
                    if last_step.status not in _ACTIVE_STATUSES:
                        log.info(
                            "[generate_workflow] Session %s has %d step(s); skipping prior context (status=%s — terminal)",
                            session_id, len(sess.steps), last_step.status,
                        )
                    elif _query_is_related_to_prior(request.request_text, last_step.workflow_name):
                        prior_ctx = (
                            f"[Active pipeline: {last_step.workflow_name}, "
                            f"step {last_step.index + 1}, status={last_step.status}, "
                            f"params={list(last_step.params.keys())}] "
                        )
                        effective_intent = prior_ctx + request.request_text
                        log.info(
                            "[generate_workflow] Session %s has %d step(s); injected prior context (related query)",
                            session_id, len(sess.steps),
                        )
                    else:
                        log.info(
                            "[generate_workflow] Session %s has %d step(s); skipping prior context (unrelated query: '%s')",
                            session_id, len(sess.steps), request.request_text[:60],
                        )
            except Exception as _se:
                log.debug("[generate_workflow] Session lookup failed (non-fatal): %s", _se)

        # Route through LangGraph pipeline when BIOMATE_USE_LANGGRAPH=true.
        # The pipeline wraps generate_workflow_unified with tracing + checkpointing.
        # Falls back transparently to direct call on any failure.
        # Build per-user credential availability map so the routing pipeline can
        # fall back to open-source alternatives when a licensed tool is not configured.
        # If the frontend already built the map (via user-scoped proxy), use it directly.
        # Otherwise fall back to server-side vault lookup via trans.user.
        if request.credential_map is not None:
            credential_map: Dict[str, bool] = dict(request.credential_map)
            log.debug("[generate_workflow] credential_map supplied by frontend: %s", credential_map)
        else:
            credential_map = {}
            try:
                from galaxy.webapps.galaxy.api.credentials_api import get_effective_credential
                from galaxy.webapps.galaxy.api.license_registry import LICENSE_REGISTRY as _LR
                for _tid in _LR:
                    _, _src = get_effective_credential(trans, _tid)
                    credential_map[_tid] = (_src != "none")
                log.debug("[generate_workflow] credential_map from vault: %s", credential_map)
            except Exception as _cred_err:
                log.debug("[generate_workflow] credential_map build failed (non-fatal): %s", _cred_err)

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
                key_terms=request.key_terms or None,
                preferred_domains=request.preferred_domains or None,
                penalized_domains=request.penalized_domains or None,
                credential_map=credential_map or None,
            )

        # Chain responses carry a different payload (no workflow_ga / citations).
        # Return them directly so the frontend WorkflowChainPlan component can render.
        if result.get('workflow_type') == 'chain':
            chain_resp: Dict[str, Any] = {
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
            if result.get('knowledge_highlights'):
                chain_resp['knowledge_highlights'] = result['knowledge_highlights']
            return chain_resp

        if result['success']:
            # Process citations from the result
            citations = []
            raw_citations = result.get('citations', [])
            for cit_data in raw_citations:
                # _build_workflow_citations returns flat dicts (doi, title, etc. at top level)
                # Legacy path may have nested {'citation': {...}} — support both
                citation_info = cit_data.get('citation', cit_data)
                # Normalize authors to list (ToolKnowledgeProvider may return string)
                raw_authors = citation_info.get('authors', [])
                if isinstance(raw_authors, str):
                    raw_authors = [a.strip() for a in raw_authors.split(',') if a.strip()]
                citations.append(CitationModel(
                    tool_id=cit_data.get('tool_id', ''),
                    tool_name=cit_data.get('tool_name', ''),
                    doi=citation_info.get('doi'),
                    pmid=citation_info.get('pmid'),
                    title=citation_info.get('title', ''),
                    authors=raw_authors,
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
            if _num_movies is None and request.request_text:
                import re as _re
                _m = _re.search(r'\bnum_movies\s*=\s*(\d+)', request.request_text, _re.IGNORECASE)
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
                },
                # License-aware rerouting notice (present when routing fell back to OSS alternative)
                **({'license_notice': result['license_notice']} if result.get('license_notice') else {}),
                # Domain knowledge highlights (best_practices, qc_thresholds, literature_guidance)
                **({'knowledge_highlights': result['knowledge_highlights']} if result.get('knowledge_highlights') else {}),
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
        # uploaded_datasets = user's actual session-uploaded files (threaded from
        # req.session.uploadedDatasets via enrichedContext.sessionDatasets → session_datasets).
        # request.available_datasets contains BioMNI public reference datasets — not user files.
        uploaded_datasets = request.session_datasets or None

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
# Study Run Log Endpoints  (required by pilot study plan)
# GET /api/sessions/{session_id}/audit  — per-session run log
# GET /api/study/runs                   — all runs for the authenticated user
# ============================================================================

@router.get(
    "/api/sessions/{session_id}/audit",
    summary="Return the durable run log for a specific session/run."
)
def get_session_audit(
    session_id: str,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Return the run-level JSON audit record written by StudyRunLogger for the
    given session_id (== Nextflow invocation_id or run_id).

    This endpoint satisfies the pilot study plan requirement:
      GET /api/sessions/{session_id}/audit
    """
    try:
        from galaxy.ai.study_run_logger import StudyRunLogger
        record = StudyRunLogger.get_log(session_id)
        if not record:
            raise HTTPException(status_code=404, detail=f"No run log found for session {session_id}")
        return {"success": True, "session_id": session_id, "run_log": record}
    except HTTPException:
        raise
    except Exception as exc:
        log.error("Error fetching session audit %s: %s", session_id, exc)
        raise HTTPException(status_code=500, detail=str(exc))


@router.get(
    "/api/study/runs",
    summary="List all durable run logs for the authenticated user."
)
def list_study_runs(
    limit: int = Query(100, ge=1, le=1000),
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """
    Return all run-level JSON logs written by StudyRunLogger for the current user.
    Includes timing, status, workflow name, and output summary for every execution.
    """
    try:
        from galaxy.ai.study_run_logger import StudyRunLogger
        user_id = str(trans.user.id) if trans.user else None
        all_runs = StudyRunLogger.list_logs(user_id=user_id)
        # Most recent first
        all_runs = sorted(all_runs, key=lambda r: r.get("result_delivered_at") or "", reverse=True)
        return {
            "success": True,
            "user_id": user_id,
            "count": len(all_runs),
            "runs": all_runs[:limit],
        }
    except Exception as exc:
        log.error("Error listing study runs: %s", exc)
        raise HTTPException(status_code=500, detail=str(exc))


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

_DOMAIN_PROFILE_AVAILABLE = False
_get_memory_service = None
DOMAIN_TAXONOMY: dict = {}
DOMAIN_LABELS: dict = {}

try:
    from galaxy.ai.domain_taxonomy import DOMAIN_TAXONOMY, DOMAIN_LABELS, get_topics_for_domains
except Exception as _dt_err:
    logging.warning(f"Domain taxonomy not available: {_dt_err}")

try:
    from galaxy.ai.memory.agentic_memory import get_memory_service as _get_memory_service
    _DOMAIN_PROFILE_AVAILABLE = True
except Exception as _dp_err:
    logging.warning(f"Domain profile memory not available (psycopg2/PostgreSQL): {_dp_err}")


# ── SQLite fallback for domain profile persistence ───────────────────────────
# Stores domain profiles in galaxy_ai_tools.db when PostgreSQL is unavailable.
# galaxy_ai_tools.db is at backend/galaxy_ai_tools.db; this file is at
# backend/lib/galaxy/webapps/galaxy/api/ → 5 levels up = backend/
import json as _json_dp
import os as _os_dp

_PROFILE_DB_PATH = _os_dp.path.normpath(_os_dp.path.join(
    _os_dp.path.dirname(_os_dp.path.abspath(__file__)),
    "..", "..", "..", "..", "..", "galaxy_ai_tools.db"
))


def _ensure_profile_table() -> None:
    with sqlite3.connect(_PROFILE_DB_PATH) as conn:
        conn.execute("""
            CREATE TABLE IF NOT EXISTS user_domain_profiles (
                user_email       TEXT PRIMARY KEY,
                domains          TEXT NOT NULL DEFAULT '[]',
                topics           TEXT NOT NULL DEFAULT '[]',
                institution_type TEXT,
                updated_at       TEXT
            )
        """)
        # Safe migration: add institution_type column if it doesn't exist yet
        try:
            conn.execute("ALTER TABLE user_domain_profiles ADD COLUMN institution_type TEXT")
        except Exception:
            pass  # column already exists
        conn.commit()


def _sqlite_save_profile(email: str, domains: list, topics: list, institution_type: Optional[str] = None) -> None:
    _ensure_profile_table()
    import datetime as _dt
    now = _dt.datetime.utcnow().isoformat()
    with sqlite3.connect(_PROFILE_DB_PATH) as conn:
        conn.execute("""
            INSERT INTO user_domain_profiles (user_email, domains, topics, institution_type, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(user_email) DO UPDATE SET
                domains          = excluded.domains,
                topics           = excluded.topics,
                institution_type = excluded.institution_type,
                updated_at       = excluded.updated_at
        """, (email, _json_dp.dumps(domains), _json_dp.dumps(topics), institution_type, now))
        conn.commit()


def _sqlite_load_profile(email: str) -> dict:
    try:
        _ensure_profile_table()
        with sqlite3.connect(_PROFILE_DB_PATH) as conn:
            row = conn.execute(
                "SELECT domains, topics, institution_type FROM user_domain_profiles WHERE user_email = ?",
                (email,)
            ).fetchone()
        if row:
            return {
                "domains": _json_dp.loads(row[0]),
                "topics": _json_dp.loads(row[1]),
                "institution_type": row[2],
            }
    except Exception as _load_err:
        logging.warning(f"SQLite profile load error: {_load_err}")
    return {"domains": [], "topics": [], "institution_type": None}


class DomainProfileRequest(BaseModel):
    domains: List[str] = Field(default_factory=list, description="Selected research domain keys")
    topics: List[str] = Field(default_factory=list, description="Selected topic strings")
    institution_type: Optional[str] = Field(default=None, description="Institution type")


@router.post(
    "/api/user/domain-profile",
    summary="Save the user's research domain profile."
)
def set_domain_profile(
    request: DomainProfileRequest,
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Store user research domain and topic selections.

    Primary storage: agentic_memory (PostgreSQL) when available.
    Fallback: SQLite user_domain_profiles table in galaxy_ai_tools.db.
    """
    user = getattr(trans, "user", None)
    if not user:
        raise HTTPException(status_code=401, detail="Authentication required")

    user_email = getattr(user, "email", None)
    if not user_email:
        raise HTTPException(status_code=400, detail="Cannot resolve user identity")

    # Primary: PostgreSQL agentic_memory
    if _DOMAIN_PROFILE_AVAILABLE:
        try:
            memory = _get_memory_service()
            ltm_user = memory.users.get_or_create_user(email=user_email)
            memory.update_domain_profile(
                user_id=ltm_user["id"],
                domains=request.domains,
                topics=request.topics,
            )
            # Always persist institution_type to SQLite even when Postgres handles domains
            _sqlite_save_profile(user_email, request.domains, request.topics, request.institution_type)
            return {"success": True, "domains": request.domains, "topics": request.topics,
                    "institution_type": request.institution_type, "storage": "postgres"}
        except Exception as exc:
            logging.warning(f"Postgres domain profile save failed, falling back to SQLite: {exc}")

    # Fallback: SQLite (always available, no extra dependencies)
    try:
        _sqlite_save_profile(user_email, request.domains, request.topics, request.institution_type)
        return {"success": True, "domains": request.domains, "topics": request.topics,
                "institution_type": request.institution_type, "storage": "sqlite"}
    except Exception as exc:
        log.error(f"Failed to save domain profile (SQLite fallback): {exc}")
        raise HTTPException(status_code=500, detail=str(exc))


@router.get(
    "/api/user/domain-profile",
    summary="Get the user's research domain profile."
)
def get_domain_profile(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Retrieve user research domain and topic selections.

    Reads from agentic_memory (PostgreSQL) when available, falls back to SQLite.
    """
    user = getattr(trans, "user", None)
    if not user:
        return {"domains": [], "topics": []}

    user_email = getattr(user, "email", None)
    if not user_email:
        return {"domains": [], "topics": []}

    # Primary: PostgreSQL agentic_memory (domains/topics only); institution_type always from SQLite
    if _DOMAIN_PROFILE_AVAILABLE:
        try:
            memory = _get_memory_service()
            ltm_user = memory.users.get_or_create_user(email=user_email)
            pg_profile = memory.get_domain_profile(user_id=ltm_user["id"])
            sqlite_profile = _sqlite_load_profile(user_email)
            # Merge: use Postgres for domains/topics, SQLite for institution_type
            pg_profile["institution_type"] = sqlite_profile.get("institution_type")
            return pg_profile
        except Exception as exc:
            logging.warning(f"Postgres domain profile read failed, falling back to SQLite: {exc}")

    # Fallback: SQLite
    return _sqlite_load_profile(user_email)


@router.get(
    "/api/user/domain-taxonomy",
    summary="Get the full domain taxonomy for the domain profile selector."
)
def get_domain_taxonomy(
    trans: ProvidesUserContext = DependsOnTrans
) -> Dict[str, Any]:
    """Return the static domain taxonomy (domains + labels + topics).
    Domain taxonomy is always available regardless of memory service status.
    """
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

# ── Input Data Analysis ────────────────────────────────────────────────────────

class AnalyzeInputDataRequest(BaseModel):
    workflow_id: Optional[str] = None
    workflow_name: Optional[str] = None
    parameters: Dict[str, Any] = {}


@router.post(
    "/api/ai_assistant/analyze-input-data",
    summary="Analyze workflow input parameters and return recommendations."
)
def analyze_input_data(request: AnalyzeInputDataRequest) -> Dict[str, Any]:
    """
    Analyzes workflow parameters before execution and returns actionable recommendations.
    Calls LLM when ANTHROPIC_API_KEY is available, falls back to rule-based analysis.
    """
    import os as _os
    import json as _json

    workflow_name = request.workflow_name or request.workflow_id or "unknown"
    parameters = request.parameters

    # Build a list of potential issues from the parameters
    issues = []

    # Check for common parameter problems using simple heuristics
    for param_name, param_value in parameters.items():
        # Missing / empty required-looking params
        if param_value is None or param_value == "" or param_value == []:
            if any(kw in param_name.lower() for kw in ["input", "genome", "fasta", "gtf", "ref", "reads"]):
                issues.append({
                    "parameter": param_name,
                    "type": "missing_required",
                    "current_value": param_value,
                })
            continue

        val_str = str(param_value)

        # Local path that looks wrong for AWS
        if isinstance(param_value, str) and param_value.startswith("/") and not param_value.startswith("/tmp"):
            issues.append({
                "parameter": param_name,
                "type": "local_path_in_aws",
                "current_value": param_value,
            })

        # Suspiciously small numbers for resource params
        if param_name.lower() in ("max_memory", "max_cpus", "memory"):
            try:
                num = float(re.sub(r"[^0-9.]", "", val_str))
                if param_name.lower() == "max_memory" and num < 4:
                    issues.append({
                        "parameter": param_name,
                        "type": "low_resource",
                        "current_value": param_value,
                    })
            except (ValueError, TypeError):
                pass

    api_key = _os.getenv("ANTHROPIC_API_KEY")
    recommendations: List[Dict[str, Any]] = []

    if api_key and issues:
        try:
            from galaxy.ai.gemini_flash import call_gemini_flash as _gemini_flash  # noqa: PLC0415
            prompt = f"""You are a bioinformatics workflow parameter expert.
Workflow: {workflow_name}
Current parameters: {_json.dumps(parameters, indent=2)}
Detected issues: {_json.dumps(issues, indent=2)}

For each issue (and any other problems you notice), return a JSON array of recommendations:
[
  {{
    "parameter": "<name>",
    "fix_type": "set_value|add_missing|fix_type|aws_resource",
    "current_value": "<current or null>",
    "recommended_value": "<recommended>",
    "reason": "<1 sentence why>",
    "risk_level": "low|medium|high",
    "auto_apply": true|false
  }}
]
Return ONLY the JSON array, no markdown."""
            raw = _gemini_flash(
                messages=[{"role": "user", "content": prompt}],
                max_tokens=600,
                temperature=0.1,
                json_mode=True,
            ).strip()
            raw = raw.replace("```json", "").replace("```", "").strip()
            recommendations = _json.loads(raw)
        except Exception as exc:
            log.warning("analyze_input_data LLM call failed: %s — using rule-based fallback", exc)

    # Rule-based fallback / supplement
    if not recommendations:
        aws_config = {
            "instance_type": _os.environ.get("AWS_INSTANCE_TYPE", "m5.xlarge"),
            "max_memory": _os.environ.get("AWS_MAX_MEMORY", "16GB"),
            "max_cpus": _os.environ.get("AWS_MAX_CPUS", "4"),
        }
        rule_result = generate_rule_based_fixes(issues, aws_config)
        recommendations = rule_result.get("recommendations", [])

    critical_count = sum(1 for r in recommendations if r.get("risk_level") == "high")
    auto_apply_count = sum(1 for r in recommendations if r.get("auto_apply"))

    return {
        "recommendations": recommendations,
        "critical_count": critical_count,
        "auto_apply_count": auto_apply_count,
    }


# ── D4: Workflow Error Explanation ─────────────────────────────────────────────

class ExplainErrorRequest(BaseModel):
    run_id: Optional[str] = None
    workflow_name: Optional[str] = None
    error_log: str = ""
    max_log_chars: int = 4000


@router.post(
    "/api/workflows/explain_error",
    summary="Parse a Nextflow error log and return a human-readable explanation + fix suggestion."
)
def explain_workflow_error(request: ExplainErrorRequest) -> Dict[str, Any]:
    """
    Takes a Nextflow error log and returns:
      - error_type: category of error (e.g. 'missing_parameter', 'docker_pull', 'resource_limit', 'data_format')
      - human_summary: plain-English explanation of what went wrong
      - suggested_fix: actionable instruction
      - chat_prompt: a pre-composed message the user can send to the chat to fix the issue
    """
    import anthropic as _anthropic
    import os as _os

    api_key = _os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        # Fallback: simple regex-based error classification without LLM
        log_lower = request.error_log.lower()
        if "no such file" in log_lower or "file not found" in log_lower:
            error_type = "missing_file"
            human_summary = "A required input file was not found."
            suggested_fix = "Check that your input file paths are correct and the files exist."
            chat_prompt = f"The workflow {request.workflow_name or ''} failed because a file was not found. Can you help me fix the input file path?"
        elif "docker" in log_lower and ("pull" in log_lower or "error" in log_lower):
            error_type = "docker_pull"
            human_summary = "Docker could not pull the required container image."
            suggested_fix = "Ensure Docker is running and you have internet access to pull the image."
            chat_prompt = f"The workflow {request.workflow_name or ''} failed with a Docker pull error. Can you suggest an alternative container or fix?"
        elif "memory" in log_lower or "oom" in log_lower or "out of memory" in log_lower:
            error_type = "resource_limit"
            human_summary = "The job ran out of memory."
            suggested_fix = "Increase the memory allocation in the workflow parameters."
            chat_prompt = f"The workflow {request.workflow_name or ''} ran out of memory. Can you increase the memory limit?"
        elif "missing" in log_lower and "param" in log_lower:
            error_type = "missing_parameter"
            human_summary = "A required parameter is missing."
            suggested_fix = "Provide the required parameter value."
            chat_prompt = f"The workflow {request.workflow_name or ''} failed due to a missing parameter. What parameter do I need to provide?"
        else:
            error_type = "unknown"
            human_summary = "An unexpected error occurred during workflow execution."
            suggested_fix = "Review the error log for details."
            chat_prompt = f"The workflow {request.workflow_name or ''} failed. Here is the error: {request.error_log[:200]}"
        return {
            "error_type": error_type,
            "human_summary": human_summary,
            "suggested_fix": suggested_fix,
            "chat_prompt": chat_prompt,
            "llm_used": False,
        }

    try:
        from galaxy.ai.gemini_flash import call_gemini_flash as _gemini_flash  # noqa: PLC0415
        truncated_log = request.error_log[-request.max_log_chars:] if len(request.error_log) > request.max_log_chars else request.error_log

        system_prompt = """You are a bioinformatics workflow debugging assistant.
A Nextflow workflow has failed. Analyze the error log and respond ONLY with valid JSON:
{
  "error_type": "<one of: missing_parameter, missing_file, docker_pull, resource_limit, data_format, permission_denied, nextflow_syntax, unknown>",
  "human_summary": "<1-2 sentences: what went wrong in plain language a scientist can understand>",
  "suggested_fix": "<1-2 sentences: the specific action to fix this>",
  "chat_prompt": "<the exact message a user should type in the chat to get help fixing this issue>"
}

Keep responses concise and actionable. The chat_prompt should be ready to paste."""

        result_text = _gemini_flash(
            messages=[{"role": "user", "content": f"Workflow: {request.workflow_name or 'unknown'}\n\nError log:\n{truncated_log}"}],
            system=system_prompt,
            max_tokens=400,
            temperature=0.1,
            json_mode=True,
        ).strip()
        result_text = result_text.replace("```json", "").replace("```", "").strip()
        import json as _json
        result = _json.loads(result_text)
        result["llm_used"] = True
        return result

    except Exception as exc:
        log.error("explain_workflow_error LLM call failed: %s", exc)
        return {
            "error_type": "unknown",
            "human_summary": "An error occurred during workflow execution.",
            "suggested_fix": "Review the full error log for details.",
            "chat_prompt": f"The workflow failed. Can you help me debug this error?",
            "llm_used": False,
            "llm_error": str(exc),
        }
