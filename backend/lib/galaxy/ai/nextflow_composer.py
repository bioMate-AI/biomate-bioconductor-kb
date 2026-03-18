"""
NextflowComposer — LLM-driven Nextflow DSL2 workflow generator from tool search.

Used as the fallback when no high/medium confidence workflow match is found.

Strategy
--------
1. Retrieve relevant tools from UnifiedToolSearch (uses all 12 k+ tools table entries).
2. Enrich each tool's context with:
   - ``wrapper_path``       — path to existing .nf file (include{} ready, 3,463 tools)
   - ``best_practice_functions`` — ordered function/step sequence with I/O typing
   - ``scientific_context`` — primary omics, suitable analysis designs
3. Split tools into two buckets:
   - *Composable* (has wrapper_path): emit ``include { } from`` directives
   - *Ad-hoc*     (no wrapper_path):  LLM generates a minimal process block
4. LLM writes a complete DSL2 ``main.nf`` that chains the tools in biological order.
5. Write the file to ``biomni_workflows/nextflow_generated/<slug>/main.nf``.
6. Return the relative path so the frontend / executor can run it with Nextflow.

Author: BioMate Team
"""

from __future__ import annotations

import json
import logging
import re
import sqlite3
import textwrap
import unicodedata
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

log = logging.getLogger(__name__)

# ── Paths ─────────────────────────────────────────────────────────────────────
_HERE = Path(__file__).resolve()
BACKEND_ROOT = _HERE.parents[3]          # backend/
DB_PATH = BACKEND_ROOT / "database" / "galaxy_ai_tools.db"
BIOC_NF_BASE = BACKEND_ROOT / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / "bioconductor"
NFCORE_MOD_BASE = BACKEND_ROOT / "nf-core-modules" / "modules" / "nf-core"
GENERATED_BASE = BACKEND_ROOT / "biomni_workflows" / "nextflow_generated"

# Relative path prefix used in include{} directives (relative to the generated workflow dir)
_BIOC_INCLUDE_PREFIX    = "../../../nextflow_nfcore/subworkflows/bioconductor"
_NFCORE_INCLUDE_PREFIX  = "../../../../nf-core-modules/modules/nf-core"
_BIOMNI_INCLUDE_PREFIX  = "../../../nextflow_nfcore/subworkflows"


# ── Helpers ───────────────────────────────────────────────────────────────────

def _slugify(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^\w\s-]", "", text.lower())
    return re.sub(r"[\s_-]+", "_", text).strip("_")[:60]


def _process_name(tool_id: str) -> str:
    """Convert tool_id to a valid Nextflow PROCESS_NAME."""
    name = re.sub(r"[^a-zA-Z0-9]", "_", tool_id.upper())
    return re.sub(r"_+", "_", name).strip("_")


def _include_path_for(wrapper_path: str) -> Tuple[str, str]:
    """
    Determine the include path and process name for a tool with a wrapper_path.

    Returns (process_name, include_statement).
    """
    wp = wrapper_path.lstrip("/")
    if "bioconductor/" in wp:
        pkg = wp.split("bioconductor/")[-1].split("/")[0]
        proc = f"BIOC_{pkg.upper()}_WORKFLOW"
        include = f"include {{ {proc} }} from '{_BIOC_INCLUDE_PREFIX}/{pkg}/main.nf'"
    elif "nf-core-modules/modules/nf-core/" in wp:
        rest = wp.split("nf-core-modules/modules/nf-core/")[-1]  # e.g. star/align/main.nf
        mod_path = rest.replace("/main.nf", "")                  # star/align
        proc = _process_name(f"nfcore_{mod_path}")
        include = f"include {{ {proc} }} from '{_NFCORE_INCLUDE_PREFIX}/{mod_path}/main.nf'"
    elif "nextflow_nfcore/subworkflows/" in wp:
        rest = wp.split("nextflow_nfcore/subworkflows/")[-1].replace("/main.nf", "")
        proc = _process_name(rest)
        include = f"include {{ {proc} }} from '{_BIOMNI_INCLUDE_PREFIX}/{rest}/main.nf'"
    else:
        proc = _process_name(wp.replace("/main.nf", ""))
        include = f"// NOTE: Resolve path for {wrapper_path}"
    return proc, include


# ── Tool context builder ──────────────────────────────────────────────────────

class _ToolContext:
    """Enriched per-tool context passed to the LLM."""

    def __init__(self, row: sqlite3.Row):
        self.tool_id: str        = row["tool_id"]
        self.name: str           = row["name"] or self.tool_id
        self.description: str    = (row["description"] or "")[:300]
        self.category: str       = row["category"] or ""
        self.wrapper_path: str   = row["wrapper_path"] or ""
        self.language: str       = row["language"] or ""
        self.usage_guide: str    = (row["usage_guide"] or "")[:200]

        # Parse JSON fields
        self.best_practice_functions: Dict = {}
        if row["best_practice_functions"]:
            try:
                self.best_practice_functions = json.loads(row["best_practice_functions"])
            except Exception:
                pass

        self.scientific_context: Dict = {}
        if row["scientific_context"]:
            try:
                self.scientific_context = json.loads(row["scientific_context"])
            except Exception:
                pass

        self.nfcore_metadata: Dict = {}
        if row["nfcore_metadata"]:
            try:
                self.nfcore_metadata = json.loads(row["nfcore_metadata"])
            except Exception:
                pass

    @property
    def has_nf_wrapper(self) -> bool:
        return bool(self.wrapper_path)

    @property
    def process_name(self) -> str:
        if self.has_nf_wrapper:
            return _include_path_for(self.wrapper_path)[0]
        return _process_name(self.tool_id)

    @property
    def include_statement(self) -> str:
        if self.has_nf_wrapper:
            return _include_path_for(self.wrapper_path)[1]
        return ""

    def step_summary(self) -> str:
        """Short step sequence for LLM context (from best_practice_functions or vignette)."""
        if self.best_practice_functions:
            steps = []
            seen_steps: set = set()
            for fn, meta in self.best_practice_functions.items():
                step_label = meta.get("step", "")
                if step_label and step_label not in seen_steps:
                    seen_steps.add(step_label)
                    inp = meta.get("inputs", [])
                    out = meta.get("outputs", [])
                    steps.append(f"{step_label}({fn}) [{' → '.join(inp)} → {' → '.join(out)}]")
            return "; ".join(steps[:6])

        # Fallback: nfcore vignette workflows
        vw = self.nfcore_metadata.get("vignette_workflows", [])
        if vw:
            vw0 = vw[0]
            return f"{vw0.get('title','')} ({vw0.get('total_steps',0)} steps)"
        return ""

    def primary_inputs(self) -> List[str]:
        oc = self.scientific_context.get("omics_applicability", {})
        return oc.get("primary_omics", [])

    def to_llm_block(self, idx: int) -> str:
        lines = [
            f"{idx}. [{('NF-WRAPPER' if self.has_nf_wrapper else 'GENERATE')}] {self.name}",
            f"   tool_id    : {self.tool_id}",
            f"   description: {self.description}",
            f"   category   : {self.category}",
        ]
        if self.has_nf_wrapper:
            lines.append(f"   include    : {self.include_statement}")
            lines.append(f"   process    : {self.process_name}")
        if self.usage_guide:
            lines.append(f"   usage      : {self.usage_guide[:150]}")
        step_sum = self.step_summary()
        if step_sum:
            lines.append(f"   steps      : {step_sum}")
        omics = self.primary_inputs()
        if omics:
            lines.append(f"   omics      : {', '.join(omics)}")
        return "\n".join(lines)


# ── NextflowComposer ──────────────────────────────────────────────────────────

class NextflowComposer:
    """
    Generates runnable Nextflow DSL2 workflows from tool search results.

    This replaces the Galaxy .ga fallback path for medium- and low-confidence
    cases.  All 12 k+ tools in the ``tools`` table are searchable; those with
    a ``wrapper_path`` become ``include{}`` directives pointing at real .nf
    files on disk.
    """

    MAX_TOOLS = 25  # tools retrieved from index before LLM selection

    def __init__(self, config=None):
        self.config = config
        self._tool_search = None
        self._llm = None

    # ── lazy init ────────────────────────────────────────────────────────────

    def _get_tool_search(self):
        if self._tool_search is None:
            from .unified_tool_search import create_unified_search
            self._tool_search = create_unified_search()
        return self._tool_search

    def _get_llm(self):
        if self._llm is None:
            from .llm_client import LLMClient
            from .config import DEFAULT_AI_CONFIG
            self._llm = LLMClient(self.config or DEFAULT_AI_CONFIG)
        return self._llm

    # ── DB tool enrichment ────────────────────────────────────────────────────

    def _enrich_from_db(self, tool_ids: List[str]) -> List[_ToolContext]:
        """Fetch enriched tool metadata from the tools table for the given IDs."""
        if not tool_ids or not DB_PATH.exists():
            return []
        conn = sqlite3.connect(str(DB_PATH))
        conn.row_factory = sqlite3.Row
        try:
            placeholders = ",".join("?" * len(tool_ids))
            rows = conn.execute(
                f"SELECT tool_id, name, description, category, language, "
                f"       wrapper_path, usage_guide, best_practice_functions, "
                f"       scientific_context, nfcore_metadata "
                f"FROM tools WHERE tool_id IN ({placeholders})",
                tool_ids,
            ).fetchall()
            by_id = {r["tool_id"]: _ToolContext(r) for r in rows}
            # Preserve search-result order
            return [by_id[tid] for tid in tool_ids if tid in by_id]
        finally:
            conn.close()

    # ── Tool retrieval ────────────────────────────────────────────────────────

    def _retrieve_tools(self, user_intent: str) -> List[_ToolContext]:
        """Search tools table and return enriched tool contexts."""
        ts = self._get_tool_search()
        raw = ts.search(user_intent, limit=self.MAX_TOOLS)
        if not raw:
            log.warning("[NextflowComposer] No tools found for intent")
            return []
        tool_ids = [t["tool_id"] for t in raw if t.get("tool_id")]
        enriched = self._enrich_from_db(tool_ids)
        log.info(
            f"[NextflowComposer] Retrieved {len(enriched)} tools "
            f"({sum(1 for t in enriched if t.has_nf_wrapper)} with .nf wrapper)"
        )
        return enriched

    # ── Prompt building ────────────────────────────────────────────────────────

    def _build_prompt(self, user_intent: str, tools: List[_ToolContext]) -> str:
        composable  = [t for t in tools if t.has_nf_wrapper]
        adhoc       = [t for t in tools if not t.has_nf_wrapper]

        catalog_lines = ["## TOOLS WITH EXISTING .nf WRAPPERS (preferred — use include{}):\n"]
        for i, t in enumerate(composable, 1):
            catalog_lines.append(t.to_llm_block(i))
            catalog_lines.append("")

        if adhoc:
            catalog_lines.append("\n## TOOLS WITHOUT .nf WRAPPERS (generate simple process block):\n")
            for i, t in enumerate(adhoc, len(composable) + 1):
                catalog_lines.append(t.to_llm_block(i))
                catalog_lines.append("")

        catalog = "\n".join(catalog_lines)

        return textwrap.dedent(f"""
            You are an expert Nextflow DSL2 workflow engineer for BioMate.

            ## TASK
            Generate a COMPLETE, RUNNABLE Nextflow DSL2 `main.nf` workflow for:

            **{user_intent}**

            ## AVAILABLE TOOLS (use ONLY these — do not invent tool IDs)

            {catalog}

            ## RULES

            1. **NF-WRAPPER tools**: use the exact `include {{ PROCESS_NAME }} from 'path'` line shown.
               Do NOT rewrite these processes — they already exist on disk.

            2. **GENERATE tools**: write a minimal `process PROCESS_NAME {{ ... }}` block that runs
               the tool via `script:` using its description as guidance.  Use:
                 - `container 'biomate/biomni-tools:latest'` as a safe default
                 - `label 'process_medium'`
                 - Proper `input:` / `output:` / `script:` sections

            3. **Workflow block**: chain selected tools in biologically correct order.
               Use `Channel.empty()` for optional inputs.  Emit key outputs.

            4. **Only select tools that are actually relevant** to the user intent.
               You may skip irrelevant tools from the list.

            5. Follow nf-core DSL2 conventions:
               - `nextflow.enable.dsl = 2`
               - `tuple val(meta), path(...)` for primary data channels
               - `emit:` named outputs
               - `versions.yml` tracking if possible

            6. Add a top-of-file comment block with:
               - User intent
               - Selected tools and why
               - Expected inputs/outputs

            ## OUTPUT FORMAT
            Return ONLY the raw Nextflow DSL2 `main.nf` content.
            Do NOT wrap in markdown fences or add extra explanation.
            Start with `#!/usr/bin/env nextflow`.
        """).strip()

    # ── LLM call ─────────────────────────────────────────────────────────────

    def _call_llm(self, prompt: str) -> str:
        llm = self._get_llm()
        response = llm.generate(prompt, max_tokens=4096)
        # Strip markdown fences if LLM ignored the instruction
        response = re.sub(r"^```[a-z]*\n?", "", response.strip(), flags=re.MULTILINE)
        response = re.sub(r"\n?```$", "", response.strip(), flags=re.MULTILINE)
        return response.strip()

    # ── Write to disk ─────────────────────────────────────────────────────────

    def _write_workflow(self, nf_content: str, slug: str) -> Path:
        ts = datetime.now().strftime("%Y%m%d_%H%M%S")
        wf_dir = GENERATED_BASE / f"{ts}_{slug}"
        wf_dir.mkdir(parents=True, exist_ok=True)
        nf_file = wf_dir / "main.nf"
        nf_file.write_text(nf_content)
        log.info(f"[NextflowComposer] Wrote generated workflow to {nf_file}")
        return nf_file

    # ── Public API ────────────────────────────────────────────────────────────

    def compose_workflow(
        self,
        user_intent: str,
        reference_match=None,          # Optional: medium-confidence WorkflowMatch for context
        max_tools: int = 25,
    ) -> Dict[str, Any]:
        """
        Compose a Nextflow DSL2 workflow for the given user intent.

        Args:
            user_intent:      The user's analysis request (natural language).
            reference_match:  Optional medium-confidence workflow match to use as context.
            max_tools:        Number of tools to retrieve from the search index.

        Returns dict with keys:
            success         : bool
            nextflow_path   : str  — relative path to the generated main.nf
            workflow_name   : str
            workflow_type   : 'nextflow'
            source          : 'nextflow_composed'
            tools_used      : List[str]
            composable_count: int  — tools with existing .nf wrappers
            adhoc_count     : int  — tools with LLM-generated process blocks
            message         : str
            error           : str  (only on failure)
        """
        self.MAX_TOOLS = max_tools
        log.info(f"[NextflowComposer] Composing workflow for: {user_intent}")

        # 1. Retrieve tools
        tools = self._retrieve_tools(user_intent)
        if not tools:
            return {
                "success": False,
                "error": "No tools found in index for this intent",
                "message": f"Could not find relevant tools for: {user_intent}",
            }

        composable = [t for t in tools if t.has_nf_wrapper]
        adhoc = [t for t in tools if not t.has_nf_wrapper]
        log.info(
            f"[NextflowComposer] Tool split: {len(composable)} composable "
            f"(include{{}}), {len(adhoc)} ad-hoc (generate process)"
        )

        # 2. Build prompt — inject reference workflow context if available
        prompt = self._build_prompt(user_intent, tools)
        if reference_match:
            ref_ctx = (
                f"\n\n## REFERENCE WORKFLOW (medium-confidence match, use as structural guide)\n"
                f"Name: {reference_match.name}\n"
                f"Description: {reference_match.description}\n"
                f"Tools used: {reference_match.tools}\n"
            )
            prompt = prompt + ref_ctx

        # 3. LLM generates DSL2 main.nf
        try:
            nf_content = self._call_llm(prompt)
        except Exception as e:
            log.error(f"[NextflowComposer] LLM error: {e}")
            return {"success": False, "error": str(e), "message": "LLM workflow generation failed"}

        if not nf_content or len(nf_content) < 100:
            return {"success": False, "error": "LLM returned empty workflow", "message": "Empty response from LLM"}

        # 4. Write to disk
        slug = _slugify(user_intent)
        nf_file = self._write_workflow(nf_content, slug)

        # 5. Build relative path (relative to BACKEND_ROOT for executor)
        rel_path = str(nf_file.relative_to(BACKEND_ROOT))

        return {
            "success": True,
            "nextflow_path": rel_path,
            "workflow_name": user_intent[:80],
            "workflow_type": "nextflow",
            "source": "nextflow_composed",
            "tools_used": [t.tool_id for t in tools],
            "composable_count": len(composable),
            "adhoc_count": len(adhoc),
            "needs_user_feedback": True,
            "message": (
                f"Composed Nextflow workflow using {len(composable)} existing .nf modules "
                f"and {len(adhoc)} generated process blocks"
            ),
        }
