"""
WorkflowGenerationAdapter — Tests BioMate's ability to route to or generate
Nextflow DSL2 workflows for bioinformatics analysis requests.

Two partitions:

  Partition A (20 tasks) — in-catalog:
    BioMate should recognise the request and return an existing workflow via
    template_reuse or template_adapt.  Scored by:
      - source_correct  (0.5): workflow_card.source is template_reuse or
                               template_adapt (not nextflow_composed)
      - category_match  (0.5): the response text or workflow name contains a
                               keyword that identifies the expected category

  Partition B (20 tasks) — out-of-catalog:
    BioMate must generate novel Nextflow DSL2 code from scratch via
    nextflow_composed.  Scored on three dimensions by LLM judge:
      - tool_correctness    (0–1): expected key tools present and used
      - process_ordering    (0–1): biologically correct dependency order
      - param_completeness  (0–1): mandatory params declared in params block
    Plus two structural checks (each ±10% bonus/penalty applied after avg):
      - has_dsl2 header ('nextflow.enable.dsl = 2' present)
      - has_workflow_block ('workflow {' block present)

    Final B score = mean(tool_correctness, process_ordering, param_completeness)
                    × structure_multiplier

Usage:
    adapter = WorkflowGenerationAdapter(config)
    results = adapter.run(client, max_tasks=None)
"""

import json
import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult
from evaluation.core.llm_judge import LLMJudge

_DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "workflow_generation" / "cases.yaml"
)

# ── Category keyword map ────────────────────────────────────────────────────
# Maps expected_category → terms that should appear in the workflow name or
# BioMate response text (case-insensitive).
_CATEGORY_KEYWORDS: Dict[str, List[str]] = {
    "rnaseq":           ["rnaseq", "rna-seq", "rna_seq", "deseq", "star", "differential expression"],
    "variant_calling":  ["variant", "gatk", "haplotypecaller", "mutect", "germline", "somatic"],
    "proteomics_dia":   ["dia", "diann", "dia-nn", "data-independent", "proteomics"],
    "cryo_em":          ["cryo", "cryosparc", "cryo-em", "cryo_em", "single particle"],
    "alphafold":        ["alphafold", "alpha_fold", "protein structure", "structure prediction"],
    "molecular_dynamics": ["molecular dynamics", "amber", "gromacs", "pmemd", "md simulation"],
    "metagenomics":     ["metagenomics", "microbiome", "qiime", "kraken", "16s", "amplicon"],
    "scrna_seq":        ["scrna", "scRNA", "single.cell", "seurat", "scanpy", "monocle", "10x"],
    "atac_seq":         ["atac", "chromatin", "peak calling", "open chromatin"],
    "chip_seq":         ["chip", "chipseq", "chip-seq", "histone", "macs"],
    "bisulfite_seq":    ["bisulfite", "bismark", "methylation", "wgbs", "cpg"],
    "proteomics_lfq":   ["lfq", "maxquant", "label.free", "proteomics", "dda"],
    "admet":            ["admet", "adme", "toxicity", "absorption", "distribution"],
    "molecular_docking":["docking", "autodock", "vina", "binding", "pocket"],
    "generative_design":["generative", "reinvent", "de novo", "drug design", "scaffold"],
    "gwas":             ["gwas", "genome.wide", "association", "plink"],
    "crispr_screen":    ["crispr", "mageck", "pooled screen", "dropout"],
}

# ── LLM judge prompt for Partition B ───────────────────────────────────────
_JUDGE_PROMPT_B = """\
A bioinformatics workflow was generated for the following task:
TASK: {intent}
KEY TOOLS EXPECTED: {key_tools}

GENERATED NEXTFLOW CODE:
{nf_code}

Score this generated workflow on three dimensions (0.0 to 1.0 each):
1. tool_correctness: Are the expected key tools present and used correctly?
2. process_ordering: Are the computational steps in biologically correct dependency order?
3. param_completeness: Are mandatory input parameters declared in the params block?

Also check: does the code contain 'nextflow.enable.dsl = 2' and a 'workflow {{' block?

Respond ONLY with valid JSON:
{{"tool_correctness": 0.0, "process_ordering": 0.0, "param_completeness": 0.0, "has_dsl2": true, "has_workflow_block": true, "explanation": "brief note"}}
"""

# Framing prefix added to every task prompt
_INTENT_PREFIX = (
    "I need to run the following bioinformatics analysis. "
    "Please help me set up the workflow:\n\n"
)


class WorkflowGenerationAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for workflow generation / routing capability.

    Partition A — routing accuracy to existing catalog workflows.
    Partition B — quality of from-scratch Nextflow DSL2 code generation.
    """

    name = "workflow_generation"

    def __init__(self, config: Dict[str, Any]) -> None:
        super().__init__(config)
        self._partition_filter: Optional[str] = config.get(
            "workflow_generation", {}
        ).get("partition_filter")  # "A", "B", or None

        llm_config = config.get("llm_judge", {})
        try:
            self._judge = LLMJudge(
                model=llm_config.get("model", "claude-haiku-4-5-20251001"),
                api_key=llm_config.get("api_key"),
                max_tokens=llm_config.get("max_tokens", 400),
                temperature=llm_config.get("temperature", 0.0),
            )
        except (KeyError, Exception):
            self._judge = None  # fallback to structural checks only

    # ── BenchmarkAdapter interface ─────────────────────────────────────────

    def load_tasks(self) -> List[BenchmarkTask]:
        with open(_DATASET_PATH) as fh:
            data = yaml.safe_load(fh)

        tasks: List[BenchmarkTask] = []
        for case in data["cases"]:
            partition = case["partition"]
            if self._partition_filter and partition != self._partition_filter:
                continue

            task = BenchmarkTask(
                task_id=case["id"],
                question=_INTENT_PREFIX + case["intent"],
                ground_truth=case.get("expected_category") or case.get("key_tools", []),
                domain="life_science",
                difficulty=case.get("difficulty", "medium"),
                task_type="workflow",
                answer_type="open",
                metadata={
                    "partition": partition,
                    "intent": case["intent"],
                    "expected_category": case.get("expected_category", ""),
                    "key_tools": case.get("key_tools", []),
                    "benchmark": "workflow_generation",
                },
            )
            tasks.append(task)
        return tasks

    def task_prompt(self, task: BenchmarkTask) -> str:
        """Return the exact string sent to BioMate."""
        return task.question

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Score using only the text response (no workflow_card access).
        Used by the base class run() loop when this adapter is NOT overriding run().
        Partition A: keyword check only (source unknown without workflow_card).
        Partition B: structural check only (no .nf file path available).
        Override run() is the preferred path for full scoring.
        """
        partition = task.metadata.get("partition", "A")
        if partition == "A":
            return self._score_partition_a_text(task, agent_response, workflow_card=None)
        return self._score_partition_b_text_only(task, agent_response)

    # ── Custom run() to access workflow_card ──────────────────────────────

    def run(
        self, client, max_tasks: Optional[int] = None
    ) -> List[BenchmarkResult]:
        """
        Override base run() so we can access ChatResponse.workflow_card for
        source checking (Partition A) and .nf file reading (Partition B).
        Uses ThreadPoolExecutor with max_workers=4 (generation is slow).
        """
        from concurrent.futures import ThreadPoolExecutor, as_completed

        tasks = self.load_tasks()
        if max_tasks:
            tasks = tasks[:max_tasks]

        self.prepare(client)
        results: List[BenchmarkResult] = []
        concurrency = self.config.get("concurrency", {}).get(
            "max_parallel_tasks", 4
        )

        def _run_one(task: BenchmarkTask) -> BenchmarkResult:
            t0 = time.time()
            error: Optional[str] = None
            response_text = ""
            workflow_card: Optional[Dict[str, Any]] = None

            try:
                response = client.ask(self.task_prompt(task))
                response_text = response.text
                workflow_card = response.workflow_card
            except Exception as exc:
                error = str(exc)

            score = 0.0
            extra_meta: Dict[str, Any] = {}
            if not error:
                try:
                    score, extra_meta = self._score_full(
                        task, response_text, workflow_card
                    )
                except Exception as exc:
                    error = f"scoring error: {exc}"

            combined_meta = {**task.metadata, **extra_meta}
            return BenchmarkResult(
                task_id=task.task_id,
                benchmark=self.name,
                score=score,
                agent_response=response_text[:2000],
                ground_truth=task.ground_truth,
                latency_sec=time.time() - t0,
                metadata=combined_meta,
                error=error,
            )

        with ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = {pool.submit(_run_one, t): t for t in tasks}
            for future in as_completed(futures):
                results.append(future.result())

        self.teardown(client)
        return results

    # ── Scoring helpers ────────────────────────────────────────────────────

    def _score_full(
        self,
        task: BenchmarkTask,
        agent_response: str,
        workflow_card: Optional[Dict[str, Any]],
    ) -> tuple[float, Dict[str, Any]]:
        """
        Full scoring path (called from overridden run()).
        Returns (score 0.0–1.0, extra metadata dict).
        """
        partition = task.metadata.get("partition", "A")
        if partition == "A":
            score = self._score_partition_a_text(task, agent_response, workflow_card)
            source = (workflow_card or {}).get("source", "none")
            return score, {"source": source}
        else:
            score, detail = self._score_partition_b(task, agent_response, workflow_card)
            return score, detail

    def _score_partition_a_text(
        self,
        task: BenchmarkTask,
        agent_response: str,
        workflow_card: Optional[Dict[str, Any]],
    ) -> float:
        """
        Partition A scoring:
          - 0.5 for source_correct: source is template_reuse or template_adapt
          - 0.5 for category_match: response/workflow name contains category keywords
        """
        source_score = 0.0
        category_score = 0.0

        # Source check (requires workflow_card)
        if workflow_card:
            source = workflow_card.get("source", "")
            if source in ("template_reuse", "template_adapt"):
                source_score = 0.5
        else:
            # No workflow card: BioMate returned clarification or error.
            # Give partial credit if the response at least mentions a workflow.
            if re.search(r"workflow|pipeline|nextflow", agent_response, re.IGNORECASE):
                source_score = 0.25

        # Category keyword check
        expected_cat = task.metadata.get("expected_category", "")
        keywords = _CATEGORY_KEYWORDS.get(expected_cat, [])
        search_text = agent_response.lower()
        if workflow_card:
            search_text += " " + (workflow_card.get("name", "") or "").lower()

        if keywords:
            if any(kw.lower() in search_text for kw in keywords):
                category_score = 0.5

        return source_score + category_score

    def _score_partition_b(
        self,
        task: BenchmarkTask,
        agent_response: str,
        workflow_card: Optional[Dict[str, Any]],
    ) -> tuple[float, Dict[str, Any]]:
        """
        Partition B scoring via LLM judge on the generated .nf code.
        Falls back to structural-only scoring when judge unavailable or file missing.
        Returns (score, detail_dict).
        """
        intent = task.metadata.get("intent", task.question)
        key_tools: List[str] = task.metadata.get("key_tools", [])
        detail: Dict[str, Any] = {"key_tools": key_tools}

        # Resolve .nf file path
        nf_code = ""
        if workflow_card:
            nf_path_str = workflow_card.get("nextflow_path", "")
            detail["source"] = workflow_card.get("source", "none")
            if nf_path_str:
                nf_path = Path(nf_path_str)
                if nf_path.exists():
                    try:
                        nf_code = nf_path.read_text(encoding="utf-8")
                        detail["nf_path"] = str(nf_path)
                    except OSError as exc:
                        detail["file_error"] = str(exc)
                else:
                    detail["file_error"] = f"nextflow_path not found on disk: {nf_path_str}"
        else:
            detail["source"] = "none"

        # If no .nf file, try to extract a fenced code block from the response text
        if not nf_code:
            nf_code = self._extract_nf_code_block(agent_response)

        if not nf_code:
            # No generated code at all
            detail["score_breakdown"] = {"tool_correctness": 0.0, "process_ordering": 0.0, "param_completeness": 0.0}
            return 0.0, detail

        # Structural checks (always applied, no LLM needed)
        has_dsl2 = bool(re.search(r"nextflow\.enable\.dsl\s*=\s*2", nf_code))
        has_workflow_block = bool(re.search(r"\bworkflow\s*\{", nf_code))
        detail["has_dsl2"] = has_dsl2
        detail["has_workflow_block"] = has_workflow_block

        # LLM judge scoring
        if self._judge is not None:
            score, breakdown = self._llm_judge_b(intent, key_tools, nf_code)
            # Merge has_dsl2 / has_workflow_block from LLM response (prefer LLM)
            has_dsl2 = breakdown.get("has_dsl2", has_dsl2)
            has_workflow_block = breakdown.get("has_workflow_block", has_workflow_block)
            detail["has_dsl2"] = has_dsl2
            detail["has_workflow_block"] = has_workflow_block
            detail["score_breakdown"] = {
                k: breakdown.get(k, 0.0)
                for k in ("tool_correctness", "process_ordering", "param_completeness")
            }
            detail["judge_explanation"] = breakdown.get("explanation", "")
        else:
            # Fallback: keyword presence check for each tool in the code
            score, breakdown = self._keyword_judge_b(key_tools, nf_code)
            detail["score_breakdown"] = breakdown

        # Apply structure multiplier: missing DSL2 header or workflow block each
        # reduce the final score by 10 percentage points (floor at 0).
        structure_penalty = (0 if has_dsl2 else 0.1) + (0 if has_workflow_block else 0.1)
        score = max(0.0, score - structure_penalty)
        return round(score, 4), detail

    # ── LLM judge ─────────────────────────────────────────────────────────

    def _llm_judge_b(
        self,
        intent: str,
        key_tools: List[str],
        nf_code: str,
    ) -> tuple[float, Dict[str, Any]]:
        """
        Call LLM judge with the 3-dimension rubric for Partition B.
        Returns (mean_score, raw_verdict_dict).
        """
        prompt = _JUDGE_PROMPT_B.format(
            intent=intent,
            key_tools=", ".join(key_tools),
            nf_code=nf_code[:3000],  # cap to avoid token overflow
        )
        try:
            raw = self._judge._call(prompt, max_tokens=400)
            json_match = re.search(r"\{[^{}]+\}", raw, re.DOTALL)
            if json_match:
                verdict = json.loads(json_match.group())
                dims = [
                    float(verdict.get("tool_correctness", 0.0)),
                    float(verdict.get("process_ordering", 0.0)),
                    float(verdict.get("param_completeness", 0.0)),
                ]
                mean_score = sum(dims) / len(dims)
                return mean_score, verdict
        except Exception:
            pass
        # Judge call failed — fall back to keyword check
        score, breakdown = self._keyword_judge_b(key_tools, nf_code)
        return score, breakdown

    def _keyword_judge_b(
        self,
        key_tools: List[str],
        nf_code: str,
    ) -> tuple[float, Dict[str, Any]]:
        """
        Fallback scorer: fraction of expected tools mentioned in the .nf code.
        Applies uniformly across all three rubric dimensions.
        """
        if not key_tools:
            return 0.5, {"tool_correctness": 0.5, "process_ordering": 0.5, "param_completeness": 0.5}
        code_lower = nf_code.lower()
        hits = sum(1 for t in key_tools if t.lower() in code_lower)
        ratio = hits / len(key_tools)
        return ratio, {
            "tool_correctness": ratio,
            "process_ordering": ratio,  # cannot assess order without LLM
            "param_completeness": ratio,
        }

    # ── Fallback text-only scoring for Partition B ────────────────────────

    def _score_partition_b_text_only(
        self, task: BenchmarkTask, agent_response: str
    ) -> float:
        """
        Called from the base-class score() path where workflow_card is not available.
        Attempts to extract a code block from the response text and keyword-score it.
        """
        key_tools: List[str] = task.metadata.get("key_tools", [])
        nf_code = self._extract_nf_code_block(agent_response) or agent_response
        has_dsl2 = bool(re.search(r"nextflow\.enable\.dsl\s*=\s*2", nf_code))
        has_workflow_block = bool(re.search(r"\bworkflow\s*\{", nf_code))
        score, _ = self._keyword_judge_b(key_tools, nf_code)
        structure_penalty = (0 if has_dsl2 else 0.1) + (0 if has_workflow_block else 0.1)
        return max(0.0, score - structure_penalty)

    # ── Utility ───────────────────────────────────────────────────────────

    @staticmethod
    def _extract_nf_code_block(text: str) -> str:
        """
        Extract the first fenced code block tagged as nextflow, groovy, or
        plain triple-backtick from the response text.
        Returns the code as a string, or empty string if none found.
        """
        pattern = re.compile(
            r"```(?:nextflow|groovy|nf|)?\n(.*?)```",
            re.DOTALL | re.IGNORECASE,
        )
        match = pattern.search(text)
        return match.group(1).strip() if match else ""
