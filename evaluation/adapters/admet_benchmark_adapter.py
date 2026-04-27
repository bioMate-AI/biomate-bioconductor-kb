"""
admet_benchmark_adapter.py
--------------------------
B1 ADMET Screening Benchmark — Stage S2 (Hit-to-Lead).

Tests the full chain: NL intent → workflow routing → parameter extraction
→ prerequisite detection (L1–L4).

For L5–L6 (execution + output validity), use the --layers L5L6 flag in the
runner, which calls admet_scorer.parse_admet_output() on actual Nextflow output.

Task generation:
  20 compounds × 3 query types = 60 tasks
    complete_single  — SMILES in query; expect routing + param extraction
    incomplete       — no SMILES; expect BioMate to ask for SMILES
    negative_control — wrong-domain query; expect NOT routed to ADMET

Scoring (L1–L4):
  complete_single:   routing correct (1.0) + smiles param extracted (partial)
  incomplete:        prereq detection — did BioMate ask for SMILES? (1.0/0.0)
  negative_control:  correctly NOT routed to ADMET (1.0/0.0)

Routing keywords (case-insensitive, any match = correct):
  predict_admet_properties, admet_pred, admet_screening, admet_properties,
  admet, drug_discovery (full pipeline), pharmacology
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult

_DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "admet_benchmark" / "cases.yaml"
)

# ---------------------------------------------------------------------------
# Routing keywords
# ---------------------------------------------------------------------------

_ADMET_WORKFLOW_KEYWORDS = [
    "predict_admet_properties",
    "admet_pred",
    "admet_screening",
    "admet_properties",
    "admet workflow",
    "admet pipeline",
    "pharmacology",
    "drug_discovery",      # full pipeline also acceptable
    "admet analysis",
    "admet profiling",
    "toxicity prediction",
]

# Keywords that indicate BioMate recognised an ADMET request but may be wrong domain
_ADMET_RELATED_KEYWORDS = [
    "admet",
    "herg",
    "dili",
    "ames",
    "lipinski",
    "rule of five",
    "ro5",
    "toxicity",
    "safety profile",
]

# For negative control: expect these keywords (rnaseq correct for RNA-seq query)
_RNASEQ_KEYWORDS = [
    "rnaseq", "rna-seq", "rna_seq", "differential expression",
    "deseq", "edger", "nf-core/rnaseq",
]

# Keywords indicating BioMate is asking for more info (prereq detection)
_PREREQ_QUESTION_KEYWORDS = [
    "smiles", "structure", "compound", "molecule", "chemical",
    "please provide", "can you share", "what compound", "which compound",
    "what molecule", "what is the smiles", "input", "missing", "need",
    "provide", "share the", "?",
]


class AdmetBenchmarkAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for B1 ADMET Screening (L1–L4).

    Generates 60 tasks: 20 compounds × 3 query types.
    """

    name = "admet_benchmark"

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self._dataset: Optional[dict] = None

    # ------------------------------------------------------------------
    # Dataset loading
    # ------------------------------------------------------------------

    def _load_dataset(self) -> dict:
        if self._dataset is None:
            with open(_DATASET_PATH) as f:
                self._dataset = yaml.safe_load(f)
        return self._dataset

    def load_tasks(self) -> List[BenchmarkTask]:
        """
        Generate 60 tasks: 20 compounds × 3 query types.

        Query types per compound:
          complete_single  — SMILES embedded in query
          incomplete       — no SMILES; should trigger prereq ask
          negative_control — RNA-seq query (wrong domain)
        """
        data = self._load_dataset()
        tasks: List[BenchmarkTask] = []

        for case in data["cases"]:
            case_id   = case["id"]
            name      = case["name"]
            smiles    = case["smiles"]
            ref       = case["reference"]
            diff      = case.get("difficulty", "medium")

            # ---- complete_single ----------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_complete",
                question=f"Run ADMET screening on this compound: {smiles}",
                ground_truth={
                    "expected_routing": True,
                    "expected_workflow_type": "admet",
                    "expected_params": {"smiles_list": smiles},
                    "expected_prereq_ask": False,
                },
                domain="drug_discovery",
                difficulty=diff,
                task_type="workflow",
                answer_type="json",
                metadata={
                    "case_id":            case_id,
                    "compound_name":      name,
                    "smiles":             smiles,
                    "query_type":         "complete_single",
                    "expected_routing":   True,
                    "expected_params":    ["smiles_list"],
                    "expected_prereq_ask": False,
                    "reference":          ref,
                    "benchmark":          "admet_benchmark",
                },
            ))

            # ---- incomplete ----------------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_incomplete",
                question=(
                    "I need to check the ADMET profile of my lead compound "
                    "before advancing to in vivo studies"
                ),
                ground_truth={
                    "expected_routing": True,
                    "expected_workflow_type": "admet",
                    "expected_params": {},
                    "expected_prereq_ask": True,
                },
                domain="drug_discovery",
                difficulty="easy",           # prereq detection is well-defined
                task_type="workflow",
                answer_type="json",
                metadata={
                    "case_id":            case_id,
                    "compound_name":      name,
                    "smiles":             smiles,   # not in query — BioMate must ask
                    "query_type":         "incomplete",
                    "expected_routing":   True,
                    "expected_params":    [],
                    "expected_prereq_ask": True,
                    "reference":          ref,
                    "benchmark":          "admet_benchmark",
                },
            ))

            # ---- negative_control ----------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_negctrl",
                question=(
                    "Perform RNA-seq differential expression analysis on my FASTQ files"
                ),
                ground_truth={
                    "expected_routing":   False,     # should NOT route to ADMET
                    "expected_workflow_type": "rnaseq",
                    "expected_params":    {},
                    "expected_prereq_ask": False,
                },
                domain="transcriptomics",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={
                    "case_id":            case_id,
                    "compound_name":      name,
                    "smiles":             smiles,
                    "query_type":         "negative_control",
                    "expected_routing":   False,
                    "expected_params":    [],
                    "expected_prereq_ask": False,
                    "reference":          ref,
                    "benchmark":          "admet_benchmark",
                },
            ))

        return tasks

    # ------------------------------------------------------------------
    # Prompt rendering
    # ------------------------------------------------------------------

    def task_prompt(self, task: BenchmarkTask) -> str:
        """Return the NL string to send to BioMate for this task."""
        return task.question

    # ------------------------------------------------------------------
    # Scoring
    # ------------------------------------------------------------------

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Score agent response for L1–L4 evaluation.

        Returns 0.0–1.0 composite score per task type.
        """
        query_type = task.metadata.get("query_type", "")

        if query_type == "complete_single":
            return self._score_complete(task, agent_response)
        elif query_type == "incomplete":
            return self._score_incomplete(task, agent_response)
        elif query_type == "negative_control":
            return self._score_negative_control(task, agent_response)
        return 0.0

    def _score_complete(self, task: BenchmarkTask, response: str) -> float:
        """
        Score a complete_single task.

        Scoring formula:
          routing_score  (0.0 / 0.5 / 1.0)   — did it route to ADMET?
          param_score    (0.0 / 0.5 / 1.0)    — did it extract SMILES?
          composite = 0.6 × routing + 0.4 × param
        """
        routing_score = self.score_routing(response, task)
        param_score   = self.score_param_extraction(response, task)
        return 0.6 * routing_score + 0.4 * param_score

    def _score_incomplete(self, task: BenchmarkTask, response: str) -> float:
        """
        Score an incomplete task.

        Passes if BioMate asks for SMILES / compound structure.
        Also deduct if BioMate immediately routes to ADMET without asking.
        """
        # Check if a needs_input / prereq signal was surfaced in response text
        if self._response_asks_for_smiles(response):
            return 1.0
        # If it proceeded to route without asking, that's a failure
        if self._response_routed_to_admet(response):
            return 0.0
        # Ambiguous — partial credit for recognising ADMET intent
        if any(kw in response.lower() for kw in _ADMET_RELATED_KEYWORDS):
            return 0.5
        return 0.0

    def _score_negative_control(self, task: BenchmarkTask, response: str) -> float:
        """
        Score a negative_control task.

        1.0 = BioMate correctly routed to rnaseq (or similar), NOT to ADMET.
        0.5 = BioMate routed to something else unrelated to ADMET.
        0.0 = BioMate incorrectly routed to ADMET.
        """
        routed_to_admet = self._response_routed_to_admet(response)
        routed_to_rnaseq = any(kw in response.lower() for kw in _RNASEQ_KEYWORDS)

        if routed_to_admet:
            return 0.0
        if routed_to_rnaseq:
            return 1.0
        return 0.5  # correctly avoided ADMET but wrong workflow

    # ------------------------------------------------------------------
    # Sub-scorers (also usable from runner for detailed metrics)
    # ------------------------------------------------------------------

    def score_routing(self, response: str, task: BenchmarkTask) -> float:
        """
        Extract routing signal from agent response.

        Checks for:
          1. [routed:workflow_name] pattern (set by evaluation harness)
          2. workflow_card present in response metadata
          3. ADMET-specific keywords in free text

        Returns:
          1.0  — clearly routed to ADMET workflow
          0.5  — mentioned ADMET but unclear routing
          0.0  — no routing signal or wrong domain
        """
        text_lower = response.lower()

        # Pattern: [routed:predict_admet_properties] or [workflow:admet_screening]
        routed_match = re.search(r"\[routed?:([^\]]+)\]", text_lower)
        if routed_match:
            wf_name = routed_match.group(1)
            if any(kw in wf_name for kw in ["admet", "pharmacol", "drug_discovery"]):
                return 1.0
            return 0.0

        # Explicit workflow name in text (e.g. "I'll use predict_admet_properties")
        if self._response_routed_to_admet(response):
            return 1.0

        # Partial ADMET signal
        if any(kw in text_lower for kw in _ADMET_RELATED_KEYWORDS):
            return 0.5

        return 0.0

    def score_param_extraction(self, response: str, task: BenchmarkTask) -> float:
        """
        Check whether the SMILES was extracted from the query into params.

        Looks for:
          1. SMILES appearing in a tool call or JSON param block
          2. smiles_list key mention
          3. SMILES string itself present anywhere in response

        Returns 0.0, 0.5, or 1.0.
        """
        smiles = task.metadata.get("smiles", "")
        if not smiles:
            return 0.0

        text_lower = response.lower()
        smiles_lower = smiles.lower()

        # Strong signal: smiles_list param key mentioned
        if "smiles_list" in text_lower:
            return 1.0

        # Strong signal: actual SMILES string present (BioMate echoed it back)
        if smiles_lower in text_lower or smiles in response:
            return 1.0

        # Moderate signal: param extraction mention
        if any(kw in text_lower for kw in ["smiles", "structure", "compound_list"]):
            return 0.5

        return 0.0

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _response_routed_to_admet(self, response: str) -> bool:
        """Return True if the response indicates ADMET workflow was selected."""
        text = response.lower()
        return any(kw.lower() in text for kw in _ADMET_WORKFLOW_KEYWORDS)

    def _response_asks_for_smiles(self, response: str) -> bool:
        """Return True if the response contains a question about SMILES/compound."""
        text = response.lower()
        # Must contain a question indicator AND an SMILES/compound keyword
        has_question = "?" in text or any(
            phrase in text for phrase in [
                "please provide", "can you provide", "could you", "i need",
                "what is the", "can you share", "do you have", "please share",
                "let me know", "tell me", "provide the",
            ]
        )
        has_smiles_kw = any(kw in text for kw in _PREREQ_QUESTION_KEYWORDS)
        return has_question and has_smiles_kw

    # ------------------------------------------------------------------
    # Detailed per-task metadata for runner display
    # ------------------------------------------------------------------

    def score_detailed(
        self, task: BenchmarkTask, agent_response: str
    ) -> Dict[str, Any]:
        """
        Return a dict with sub-scores for detailed runner output.

        Used by the runner for the per-task display line.
        """
        query_type = task.metadata.get("query_type", "")
        result: Dict[str, Any] = {"query_type": query_type}

        if query_type == "complete_single":
            r = self.score_routing(agent_response, task)
            p = self.score_param_extraction(agent_response, task)
            result["routing_score"]  = r
            result["param_score"]    = p
            result["composite"]      = 0.6 * r + 0.4 * p
            result["routed_ok"]      = r >= 1.0
            result["params_ok"]      = p >= 1.0

        elif query_type == "incomplete":
            asked = self._response_asks_for_smiles(agent_response)
            result["prereq_asked"]   = asked
            result["composite"]      = 1.0 if asked else 0.0

        elif query_type == "negative_control":
            to_admet   = self._response_routed_to_admet(agent_response)
            to_rnaseq  = any(kw in agent_response.lower() for kw in _RNASEQ_KEYWORDS)
            result["routed_to_admet"]  = to_admet
            result["routed_to_rnaseq"] = to_rnaseq
            result["composite"]        = (
                0.0 if to_admet else (1.0 if to_rnaseq else 0.5)
            )

        return result
