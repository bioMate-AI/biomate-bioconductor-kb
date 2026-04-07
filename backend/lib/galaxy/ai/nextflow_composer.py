"""
NextflowComposer — LLM-driven Nextflow DSL2 workflow generator from tool search.

Used as the fallback when no high/medium confidence workflow match is found.

Strategy (latency-optimised — single LLM call in the hot path)
--------------------------------------------------------------
L0  SubworkflowLibrary cache lookup          ~1 ms   (JSON read, 0 LLM calls)
L1  Tool retrieval from tools table          ~20 ms  (SQLite FTS)
L2  Wrapper-path validation + substitution   ~10 ms  (disk stat, no LLM)
    - NF-WRAPPER: wrapper_path file exists on disk → include{}  (preferred)
    - GENERATE  : no wrapper_path → LLM writes minimal process block
    - BAD-PATH  : wrapper_path set but file missing → substitute with
                  next-best tool of same category from retrieved list
L3  Single LLM call: generate full DSL2 .nf with pre-validated tool list
L4  Syntax validation + write to disk
    Store result in SubworkflowLibrary (non-blocking, for future cache hits)

Author: BioMate Team
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
import sqlite3
import textwrap
import threading
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
LIBRARY_PATH   = BACKEND_ROOT / "database" / "subworkflow_library"

# Relative path prefix used in include{} directives (relative to the generated workflow dir).
#
# Generated workflows live at:
#   GENERATED_BASE / "{ts}_{slug}" / main.nf
# i.e. backend/biomni_workflows/nextflow_generated/{ts}_{slug}/main.nf
#
# From that directory:
#   ../  → nextflow_generated/
#   ../../  → biomni_workflows/          ← bioc + biomni targets are here
#   ../../../  → backend/               ← nf-core-modules target is here
_BIOC_INCLUDE_PREFIX    = "../../nextflow_nfcore/subworkflows/bioconductor"
_NFCORE_INCLUDE_PREFIX  = "../../../nf-core-modules/modules/nf-core"
_BIOMNI_INCLUDE_PREFIX  = "../../nextflow_nfcore/subworkflows"

# Cache quality threshold: only return cached workflows with this minimum score.
_CACHE_MIN_QUALITY = 70.0
# Structural similarity threshold for cache hits (Jaccard on tool IDs).
_CACHE_MIN_JACCARD = 0.75


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
    def wrapper_on_disk(self) -> bool:
        """True iff wrapper_path is set AND the file actually exists on disk."""
        if not self.wrapper_path:
            return False
        wp = self.wrapper_path.lstrip("/")
        return (BACKEND_ROOT / wp).exists()

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

    Generation pipeline (single LLM call in the hot path):
      L0  SubworkflowLibrary cache   → instant (0 LLM calls on hit)
      L1  Tool retrieval             → SQLite FTS
      L2  Wrapper-path validation    → disk stat, no LLM; bad paths substituted
      L3  LLM generates full DSL2    → one call with pre-validated tool list
      L4  Syntax validation + write
          Store result in library (background thread, non-blocking)
    """

    MAX_TOOLS = 25

    def __init__(self, config=None):
        self.config = config
        self._tool_search = None
        self._llm = None
        self._library = None

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

    def _get_library(self):
        """Lazy-load SubworkflowLibrary (creates database/subworkflow_library/ on first use)."""
        if self._library is None:
            try:
                from .subworkflow_library import SubworkflowLibrary
                self._library = SubworkflowLibrary(LIBRARY_PATH)
            except Exception as e:
                log.warning(f"[NextflowComposer] SubworkflowLibrary unavailable: {e}")
        return self._library

    # ── L0: SubworkflowLibrary cache ─────────────────────────────────────────

    def _cache_key(self, user_intent: str, tools: List[_ToolContext]) -> str:
        """Deterministic cache key: hash of normalised intent + sorted top-5 tool IDs."""
        norm_intent = re.sub(r"\s+", " ", user_intent.lower().strip())
        top_ids = sorted(t.tool_id for t in tools[:10])
        raw = f"{norm_intent}|{'|'.join(top_ids)}"
        return hashlib.sha256(raw.encode()).hexdigest()

    def _check_cache(self, user_intent: str, tools: List[_ToolContext]) -> Optional[Dict[str, Any]]:
        """
        L0 cache lookup.  Returns a compose_workflow-compatible dict on hit,
        None on miss.  Uses structural (Jaccard) matching so near-identical
        queries reuse the same cached workflow.
        """
        lib = self._get_library()
        if lib is None:
            return None
        try:
            tool_ids = [t.tool_id for t in tools]
            matches = lib.find_structural_matches(tool_ids, top_k=3)
            for pattern, similarity in matches:
                if similarity >= _CACHE_MIN_JACCARD and pattern.quality_score >= _CACHE_MIN_QUALITY:
                    cached_path = BACKEND_ROOT / pattern.nextflow_code  # stores rel path in nextflow_code
                    if cached_path.exists():
                        log.info(
                            f"[NextflowComposer] L0 cache HIT — similarity={similarity:.2f}, "
                            f"quality={pattern.quality_score}, pattern={pattern.name}"
                        )
                        rel_path = str(cached_path.relative_to(BACKEND_ROOT))
                        return {
                            "success": True,
                            "nextflow_path": rel_path,
                            "workflow_name": pattern.description or user_intent[:80],
                            "workflow_type": "nextflow",
                            "source": "subworkflow_library_cache",
                            "cache_hit": True,
                            "cache_similarity": round(similarity, 3),
                            "tools_used": pattern.tools,
                            "composable_count": len([t for t in tools if t.wrapper_on_disk]),
                            "adhoc_count": 0,
                            "needs_user_feedback": True,
                            "validation": {"is_valid": True, "warnings": [], "missing_includes": [], "issues": [], "suggestions": []},
                            "message": f"Returned cached Nextflow workflow (similarity {similarity:.0%}): {pattern.name}",
                        }
        except Exception as e:
            log.debug(f"[NextflowComposer] Cache lookup error (non-fatal): {e}")
        return None

    def _store_in_library_async(
        self,
        user_intent: str,
        tools: List[_ToolContext],
        rel_path: str,
        quality_score: float,
    ) -> None:
        """Store a generated workflow in the SubworkflowLibrary in a background thread."""
        def _store():
            lib = self._get_library()
            if lib is None:
                return
            try:
                composable = [t for t in tools if t.wrapper_on_disk]
                categories = list({t.category for t in tools if t.category})
                lib.add_pattern(
                    name=_slugify(user_intent),
                    description=user_intent[:200],
                    biological_purpose=user_intent,
                    tools=[t.tool_id for t in tools],
                    nextflow_code=rel_path,   # store rel path, not the full NF source
                    quality_score=quality_score,
                    input_types=list({o for t in tools for o in t.primary_inputs()}),
                    output_types=[],
                    category=categories[0] if categories else "general",
                )
                log.debug(f"[NextflowComposer] Stored workflow in SubworkflowLibrary: {rel_path}")
            except Exception as e:
                log.debug(f"[NextflowComposer] Library store error (non-fatal): {e}")

        threading.Thread(target=_store, daemon=True).start()

    # ── L2: Tool-plan validation + substitution ───────────────────────────────

    def _validate_and_filter_tools(self, tools: List[_ToolContext]) -> List[_ToolContext]:
        """
        L2: Pre-generation tool validation using disk stat only (no LLM, no network).

        Classification:
          NF-WRAPPER  wrapper_path set AND file exists on disk → use include{}
          GENERATE    no wrapper_path                          → LLM writes process block
          BAD-PATH    wrapper_path set BUT file missing        → substitute or demote to GENERATE

        Substitution rule for BAD-PATH tools:
          Find another tool in the retrieved list with the same ``category``
          that is either NF-WRAPPER or GENERATE.  If found, keep the substitute
          and drop the BAD-PATH tool (avoids hallucinated include{} at generation time).

        Returns the filtered/substituted tool list (preserves order; composable first).
        """
        good: List[_ToolContext] = []
        bad_paths: List[_ToolContext] = []
        substituted = 0

        for t in tools:
            if not t.wrapper_path:
                good.append(t)   # GENERATE — fine
            elif t.wrapper_on_disk:
                good.append(t)   # NF-WRAPPER — verified
            else:
                bad_paths.append(t)  # BAD-PATH

        if bad_paths:
            good_cats = {t.category: t for t in good}
            for bt in bad_paths:
                if bt.category in good_cats:
                    # A same-category tool already in good list — just drop bt
                    log.debug(
                        f"[NextflowComposer] L2 BAD-PATH dropped: {bt.tool_id} "
                        f"(substitute present: {good_cats[bt.category].tool_id})"
                    )
                    substituted += 1
                else:
                    # No substitute available — demote to GENERATE (clear wrapper_path)
                    bt.wrapper_path = ""
                    good.append(bt)
                    log.debug(f"[NextflowComposer] L2 BAD-PATH demoted to GENERATE: {bt.tool_id}")

            log.info(
                f"[NextflowComposer] L2 validation: {len(good)} tools OK, "
                f"{substituted} bad-path substituted/dropped, "
                f"{len(bad_paths) - substituted} demoted to GENERATE"
            )
        else:
            log.info(f"[NextflowComposer] L2 validation: all {len(good)} tools clean")

        # Sort: composable (NF-WRAPPER with verified disk path) first
        good.sort(key=lambda t: (0 if t.wrapper_on_disk else 1))
        return good

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

    def _retrieve_tools(self, user_intent: str, key_terms: Optional[List[str]] = None) -> List[_ToolContext]:
        """Search tools table and return enriched tool contexts.

        key_terms (LLM-extracted domain terms from intent decomposition) are appended
        to the search query when they add new vocabulary not already present in user_intent.
        This improves FTS recall without double-searching.
        """
        ts = self._get_tool_search()
        query = user_intent
        if key_terms:
            extra = " ".join(t for t in key_terms if t.lower() not in user_intent.lower())
            if extra.strip():
                query = f"{user_intent} {extra}"
                log.debug(f"[NextflowComposer] Augmented search query with key_terms: +{extra.strip()!r}")
        raw = ts.search(query, limit=self.MAX_TOOLS)
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

            7. Declare ALL user-configurable inputs in a `params {{ }}` block at the top:
               - Required inputs: `params.reads = null` (null signals required)
               - Optional inputs: `params.outdir = 'results'` (provide a sensible default)
               - Add `if (!params.reads) error "Required parameter: --reads"` guard in the
                 workflow body for each required parameter.
               This ensures the BioMate UI can display and fill in parameters before execution.

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

    # ── Nextflow validation ───────────────────────────────────────────────────

    def validate_workflow(self, nf_content: str) -> Dict[str, Any]:
        """
        Validate a generated Nextflow DSL2 workflow without executing it.

        Checks performed:
        1. Has nextflow.enable.dsl = 2
        2. Has at least one workflow{} block
        3. All include{} paths reference files that exist on disk
        4. No obvious syntax errors (missing braces, etc.)

        For Nextflow, tool availability is handled by container images — there is
        no equivalent of Galaxy's ToolShed install step.  What matters is that
        the included .nf module files are present on disk.

        Returns dict with: valid (bool), warnings (list), missing_includes (list)
        """
        warnings: List[str] = []
        missing_includes: List[str] = []

        # 1. DSL2 marker
        if "nextflow.enable.dsl" not in nf_content:
            warnings.append("Missing 'nextflow.enable.dsl = 2' declaration")

        # 2. Must have a workflow block
        if not re.search(r'\bworkflow\s+\w*\s*\{', nf_content):
            warnings.append("No 'workflow { }' block found")

        # 3. Resolve every include{} path
        include_pattern = re.compile(
            r"include\s*\{[^}]+\}\s*from\s*['\"]([^'\"]+)['\"]"
        )
        # All generated workflows live one level inside GENERATED_BASE, so any
        # single-level placeholder subdir gives the correct relative-path math.
        _wf_placeholder = GENERATED_BASE / "_validation_ref"
        for m in include_pattern.finditer(nf_content):
            raw_path = m.group(1)
            # Convert relative path to absolute (relative to the generated wf dir)
            if raw_path.startswith("."):
                candidate = (_wf_placeholder / raw_path).resolve()
            else:
                candidate = BACKEND_ROOT / raw_path
            if not candidate.exists():
                missing_includes.append(raw_path)
                warnings.append(f"include path not found on disk: {raw_path}")

        # 4. Balanced braces (rough check)
        open_b = nf_content.count("{")
        close_b = nf_content.count("}")
        if abs(open_b - close_b) > 3:
            warnings.append(
                f"Possible unbalanced braces: {open_b} '{{' vs {close_b} '}}'"
            )

        is_valid = len(missing_includes) == 0 and not any(
            "No 'workflow" in w for w in warnings
        )

        log.info(
            f"[NextflowComposer] Validation: valid={is_valid}, "
            f"warnings={len(warnings)}, missing_includes={len(missing_includes)}"
        )
        return {
            "valid": is_valid,
            "warnings": warnings,
            "missing_includes": missing_includes,
        }

    # ── Public API ────────────────────────────────────────────────────────────

    def compose_workflow(
        self,
        user_intent: str,
        reference_match=None,
        max_tools: int = 25,
        key_terms: Optional[List[str]] = None,
    ) -> Dict[str, Any]:
        """
        Compose a Nextflow DSL2 workflow for the given user intent.

        Pipeline (single LLM call in the hot path):
          L0  Cache check            → 0 LLM calls on hit
          L1  Tool retrieval         → SQLite FTS (augmented by key_terms when supplied)
          L2  Wrapper-path validation→ disk stat, substitutes bad paths
          L3  LLM generates DSL2     → one call with pre-validated tools
          L4  Syntax validation + write to disk
              If missing_includes found → strip bad includes, retry LLM once (max 2 calls total)
              Store in library (background thread)

        Args:
            user_intent:     Natural language description of the analysis goal.
            reference_match: Optional medium-confidence WorkflowMatch for structural context.
            max_tools:       Number of tools retrieved from the index.
            key_terms:       LLM-extracted domain terms to augment tool search.

        Returns dict with keys:
            success          bool
            nextflow_path    str   relative path to generated main.nf
            workflow_name    str
            workflow_type    'nextflow'
            source           'nextflow_composed' | 'subworkflow_library_cache'
            cache_hit        bool  (True when L0 served the response)
            tools_used       List[str]
            composable_count int   tools with verified .nf wrappers on disk
            adhoc_count      int   tools that needed a generated process block
            validation       dict
            message          str
            error            str  (only on failure)
        """
        self.MAX_TOOLS = max_tools
        log.info(f"[NextflowComposer] Composing workflow for: {user_intent}")

        # L1: Retrieve tools from index (always needed; also used for cache key)
        tools = self._retrieve_tools(user_intent, key_terms=key_terms)
        if not tools:
            return {
                "success": False,
                "error": "No tools found in index for this intent",
                "message": f"Could not find relevant tools for: {user_intent}",
            }

        # L0: Cache check (uses the retrieved tool list as part of the key)
        cached = self._check_cache(user_intent, tools)
        if cached:
            return cached

        # L2: Validate wrapper paths on disk; substitute/demote bad-path tools
        tools = self._validate_and_filter_tools(tools)

        composable = [t for t in tools if t.wrapper_on_disk]
        adhoc      = [t for t in tools if not t.wrapper_on_disk]
        log.info(
            f"[NextflowComposer] Tool split after L2: {len(composable)} NF-WRAPPER "
            f"(verified on disk), {len(adhoc)} GENERATE"
        )

        # L3: Build prompt with pre-validated tool list and call LLM (single call)
        prompt = self._build_prompt(user_intent, tools)
        if reference_match:
            # Convert opaque Galaxy tool IDs (ToolShed URLs) to readable names.
            # e.g. "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73+galaxy0"
            #   → "fastqc"
            # Nextflow or plain tool IDs are passed through unchanged.
            def _readable_tool_id(tid: str) -> str:
                if "/" in tid and "toolshed" in tid.lower():
                    parts = tid.rstrip("/").split("/")
                    # ToolShed URL pattern: .../repos/<owner>/<repo>/<tool_id>/<version>
                    # The tool name is the 4th segment from the end (tool_id field)
                    return parts[-2] if len(parts) >= 2 else parts[-1]
                return tid

            readable_tools = [_readable_tool_id(t) for t in (reference_match.tools or [])]
            # Deduplicate while preserving order
            seen: set = set()
            unique_tools = [t for t in readable_tools if not (t in seen or seen.add(t))]  # type: ignore[func-returns-value]
            prompt += (
                f"\n\n## REFERENCE WORKFLOW (medium-confidence match — use as structural guide)\n"
                f"Name: {reference_match.name}\n"
                f"Description: {reference_match.description}\n"
                f"Steps include: {', '.join(unique_tools)}\n"
                f"Use this as a structural guide for the biologically correct step order.\n"
            )

        # L3+L4 loop: up to 2 LLM calls total.
        # Attempt 0 is the normal single call.  If include paths are still missing
        # after L4 validation, we strip the bad include{} lines and retry once so the
        # LLM can regenerate those blocks as inline process definitions instead.
        nf_content = ""
        validation: Dict[str, Any] = {}
        for attempt in range(2):
            try:
                nf_content = self._call_llm(prompt)
            except Exception as e:
                log.error(f"[NextflowComposer] LLM error (attempt {attempt}): {e}")
                if attempt == 0:
                    return {"success": False, "error": str(e), "message": "LLM workflow generation failed"}
                break  # use best-effort content from attempt 0 if available; we have none here

            if not nf_content or len(nf_content) < 100:
                if attempt == 0:
                    return {"success": False, "error": "LLM returned empty workflow", "message": "Empty response from LLM"}
                break

            # L4: Syntax validation (include paths, DSL2 marker, brace balance)
            validation = self.validate_workflow(nf_content)
            if not validation["missing_includes"]:
                break  # all includes resolved — done

            if attempt == 0:
                missing = validation["missing_includes"]
                log.warning(
                    f"[NextflowComposer] L4 attempt 0: {len(missing)} include path(s) unresolved "
                    f"— retrying with correction prompt: {missing}"
                )
                # Strip broken include{} lines from the content and add a correction note
                correction_lines = [
                    f"  {p}" for p in missing
                ]
                prompt += (
                    "\n\n## CORRECTION REQUIRED — Include Paths\n"
                    "The following `include{}` paths you generated do NOT exist on disk:\n"
                    + "\n".join(correction_lines)
                    + "\n\nFor each of these broken includes, replace the `include{}` directive with an "
                    "inline `process` block (GENERATE style) using `container 'biomate/biomni-tools:latest'` "
                    "and `label 'process_medium'`. Do NOT use those include{} paths again."
                )
            else:
                log.warning(
                    f"[NextflowComposer] L4 attempt 1: {len(validation['missing_includes'])} "
                    "include path(s) still unresolved — writing best-effort result"
                )

        # Write to disk
        slug = _slugify(user_intent)
        nf_file = self._write_workflow(nf_content, slug)
        rel_path = str(nf_file.relative_to(BACKEND_ROOT))

        # Quality score: 100 if all includes resolve, reduced by missing count
        n_missing = len(validation["missing_includes"])
        quality = max(40.0, 100.0 - n_missing * 15.0)

        # Store in SubworkflowLibrary in the background (non-blocking)
        self._store_in_library_async(user_intent, tools, rel_path, quality)

        return {
            "success": True,
            "nextflow_path": rel_path,
            "workflow_name": user_intent[:80],
            "workflow_type": "nextflow",
            "source": "nextflow_composed",
            "cache_hit": False,
            "tools_used": [t.tool_id for t in tools],
            "composable_count": len(composable),
            "adhoc_count": len(adhoc),
            "needs_user_feedback": True,
            "validation": {
                "is_valid": validation["valid"],
                "warnings": validation["warnings"],
                "missing_includes": validation["missing_includes"],
                "issues": [f"Missing include: {p}" for p in validation["missing_includes"]],
                "suggestions": (
                    ["L2 substitution active — any missing includes were hallucinated by LLM outside the tool list"]
                    if validation["missing_includes"] else []
                ),
            },
            "message": (
                f"Composed Nextflow workflow: {len(composable)} verified NF-WRAPPER modules, "
                f"{len(adhoc)} generated process blocks"
                + (f" — {n_missing} include path(s) need review" if n_missing else "")
            ),
        }
