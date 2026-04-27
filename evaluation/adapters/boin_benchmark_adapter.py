"""
boin_benchmark_adapter.py
-------------------------
B4 BOIN Clinical Trial Design Benchmark — Stage S5/S6 (IND / Phase I).

Tests the full chain: NL intent → workflow routing → parameter extraction
→ prerequisite detection (L1–L4).

For L5–L6 (execution + output validity), use the --layers L5L6 flag in the
runner, which calls boin_scorer.parse_boin_output() on actual Nextflow output.

Task generation:
  20 scenarios × 3 query types = 60 tasks
    complete     — all dose escalation params in query; expect routing + extraction
    incomplete   — missing required params; expect BioMate to ask
    negative_control — wrong domain (RNA-seq); expect NOT routed to clinical trial

Scoring (L1–L4):
  complete:          routing correct (1.0) + param extraction partial score
  incomplete:        prereq detection — did BioMate ask for dose levels / PK? (1.0/0.0)
  negative_control:  correctly NOT routed to clinical trial (1.0/0.0)

Routing keywords (case-insensitive, any match = correct):
  clinical_trial_simulation, boin, dose_escalation, phase_i, phase_1,
  mtd, dose_finding, drug_discovery (full pipeline)
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult

_DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "boin_benchmark" / "cases.yaml"
)

# ---------------------------------------------------------------------------
# Routing keywords
# ---------------------------------------------------------------------------

_BOIN_WORKFLOW_KEYWORDS = [
    "clinical_trial_simulation",
    "clinical trial simulation",
    "boin_dose_escalation",
    "boin dose escalation",
    "boin",
    "dose escalation",
    "dose_escalation",
    "phase i trial",
    "phase 1 trial",
    "phase i dose",
    "phase 1 dose",
    "mtd",
    "dose finding",
    "dose_finding",
    "drug_discovery",           # full pipeline also acceptable
    "phase i study",
    "maximum tolerated dose",
    "clinical pharmacology",
]

# Partial keywords indicating trial/PK domain awareness
_CLINICAL_RELATED_KEYWORDS = [
    "dose escalation", "dlt", "dose-limiting", "toxicity", "phase i",
    "phase 1", "mtd", "boin", "3+3", "cohort", "starting dose",
    "recommended dose", "dose levels", "clinical trial",
]

# Keywords for prereq detection: questions about dose levels / trial params
_TRIAL_PREREQ_KEYWORDS = [
    "dose levels", "starting dose", "dose_levels_json", "dlt rate",
    "target toxicity", "pk parameters", "clearance", "volume of distribution",
    "n_simulations", "dose escalation scheme",
]

# General question indicators
_QUESTION_INDICATORS = [
    "please provide", "can you provide", "could you", "i need",
    "what is the", "can you share", "do you have", "please share",
    "let me know", "tell me", "provide the", "what are the",
    "specify", "more information", "additional details", "?",
]

# Negative control: RNA-seq query routing keywords
_RNASEQ_KEYWORDS = [
    "rnaseq", "rna-seq", "rna_seq", "differential expression",
    "deseq", "edger", "nf-core/rnaseq", "fastq",
    "gene expression", "transcript",
]


class BOINClinicalBenchmarkAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for B4 BOIN Clinical Trial Design (L1–L4).

    Generates 60 tasks: 20 scenarios × 3 query types.
    """

    name = "boin_benchmark"

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
        Generate 60 tasks: 20 scenarios × 3 query types.

        Query types per scenario:
          complete     — all required params embedded in query
          incomplete   — missing dose levels + PK params; should trigger prereq ask
          negative_control — RNA-seq query (wrong domain)
        """
        data = self._load_dataset()
        tasks: List[BenchmarkTask] = []

        for case in data["cases"]:
            case_id   = case["id"]
            scenario  = case["scenario"]
            inputs    = case["inputs"]
            ref       = case["reference"]
            diff      = case.get("difficulty", "medium")
            notes     = case.get("notes", "")

            # ---- complete -----------------------------------------------
            complete_query = (
                f"Design a Phase I dose escalation trial for my oncology compound. "
                f"Scenario: {scenario}. "
                f"Starting dose {inputs['starting_dose_mg']}mg, "
                f"max dose {inputs['max_dose_mg']}mg, "
                f"dose levels: {inputs['dose_levels_json']}, "
                f"target DLT rate {inputs['DLT_rate_target']}, "
                f"use {inputs['design']} design. "
                f"PK params: CL={inputs['pk_CL_L_h']} L/h, "
                f"Vd={inputs['pk_Vd_L']} L, "
                f"ka={inputs['pk_ka_h']} h-1."
            )

            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_complete",
                question=complete_query,
                ground_truth={
                    "expected_routing":   True,
                    "expected_workflow_type": "boin",
                    "expected_params": {
                        "starting_dose_mg":  str(inputs["starting_dose_mg"]),
                        "dose_levels_json":  inputs["dose_levels_json"],
                        "DLT_rate_target":   str(inputs["DLT_rate_target"]),
                        "design":            inputs["design"],
                        "pk_CL_L_h":         str(inputs["pk_CL_L_h"]),
                        "pk_Vd_L":           str(inputs["pk_Vd_L"]),
                    },
                    "expected_prereq_ask": False,
                },
                domain="drug_discovery",
                difficulty=diff,
                task_type="workflow",
                answer_type="json",
                metadata={
                    "case_id":            case_id,
                    "scenario":           scenario,
                    "inputs":             inputs,
                    "query_type":         "complete",
                    "expected_routing":   True,
                    "expected_params":    [
                        "starting_dose_mg", "dose_levels_json",
                        "DLT_rate_target", "design",
                        "pk_CL_L_h", "pk_Vd_L",
                    ],
                    "expected_prereq_ask": False,
                    "reference":          ref,
                    "notes":              notes,
                    "benchmark":          "boin_benchmark",
                },
            ))

            # ---- incomplete -----------------------------------------------
            # Deliberately omit dose_levels_json and PK params
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_incomplete",
                question="Design a BOIN Phase I trial for my compound",
                ground_truth={
                    "expected_routing":   True,
                    "expected_workflow_type": "boin",
                    "expected_params":    {},
                    "expected_prereq_ask": True,
                    "prereq_type":        "trial_params",
                },
                domain="drug_discovery",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={
                    "case_id":            case_id,
                    "scenario":           scenario,
                    "inputs":             inputs,
                    "query_type":         "incomplete",
                    "expected_routing":   True,
                    "expected_params":    [],
                    "expected_prereq_ask": True,
                    "prereq_type":        "trial_params",
                    "reference":          ref,
                    "benchmark":          "boin_benchmark",
                },
            ))

            # ---- negative_control ----------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_negctrl",
                question=(
                    "Analyze the differential gene expression in my RNA-seq data"
                ),
                ground_truth={
                    "expected_routing":   False,
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
                    "scenario":           scenario,
                    "query_type":         "negative_control",
                    "expected_routing":   False,
                    "expected_params":    [],
                    "expected_prereq_ask": False,
                    "reference":          ref,
                    "benchmark":          "boin_benchmark",
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

        if query_type == "complete":
            return self._score_complete(task, agent_response)
        elif query_type == "incomplete":
            return self._score_incomplete(task, agent_response)
        elif query_type == "negative_control":
            return self._score_negative_control(task, agent_response)
        return 0.0

    def _score_complete(self, task: BenchmarkTask, response: str) -> float:
        """
        Score a complete task.

        Scoring formula:
          routing_score (0.0/0.5/1.0) — routed to clinical trial simulation?
          param_score   (0.0/0.5/1.0) — extracted dose levels + PK params?
          composite = 0.55 × routing + 0.45 × param
        """
        routing_score = self.score_routing(response, task)
        param_score   = self.score_param_extraction(response, task)
        return 0.55 * routing_score + 0.45 * param_score

    def _score_incomplete(self, task: BenchmarkTask, response: str) -> float:
        """
        Score an incomplete task.

        Passes if BioMate asks for dose levels / PK parameters.
        """
        if self._response_asks_for_trial_params(response):
            return 1.0
        # If it tried to route without params, partial credit only if it shows
        # BOIN awareness
        if self._response_routed_to_boin(response):
            return 0.0
        if any(kw in response.lower() for kw in _CLINICAL_RELATED_KEYWORDS):
            return 0.5
        return 0.0

    def _score_negative_control(self, task: BenchmarkTask, response: str) -> float:
        """
        Score a negative_control task.

        1.0 = BioMate correctly routed to rnaseq, NOT to clinical trial.
        0.5 = BioMate routed to something other than clinical trial.
        0.0 = BioMate incorrectly routed to clinical trial / BOIN.
        """
        routed_to_boin   = self._response_routed_to_boin(response)
        routed_to_rnaseq = any(kw in response.lower() for kw in _RNASEQ_KEYWORDS)

        if routed_to_boin:
            return 0.0
        if routed_to_rnaseq:
            return 1.0
        return 0.5  # correctly avoided BOIN but wrong workflow

    # ------------------------------------------------------------------
    # Sub-scorers (also usable from runner for detailed metrics)
    # ------------------------------------------------------------------

    def score_routing(self, response: str, task: BenchmarkTask) -> float:
        """
        Extract routing signal from agent response.

        Returns:
          1.0  — clearly routed to clinical trial simulation / BOIN
          0.5  — mentioned clinical trial concepts but unclear routing
          0.0  — no routing signal or wrong domain
        """
        text_lower = response.lower()

        # Pattern: [routed:clinical_trial_simulation] or [workflow:boin]
        routed_match = re.search(r"\[routed?:([^\]]+)\]", text_lower)
        if routed_match:
            wf_name = routed_match.group(1)
            if any(kw in wf_name for kw in [
                "boin", "clinical_trial", "dose_escalation", "drug_discovery"
            ]):
                return 1.0
            return 0.0

        if self._response_routed_to_boin(response):
            return 1.0

        if any(kw in text_lower for kw in _CLINICAL_RELATED_KEYWORDS):
            return 0.5

        return 0.0

    def score_param_extraction(self, response: str, task: BenchmarkTask) -> float:
        """
        Check whether key dose escalation parameters were extracted from the query.

        Looks for: starting_dose_mg, dose_levels_json, DLT_rate_target, design (BOIN)
        appearing in response.

        Returns 0.0, 0.5, or 1.0.
        """
        inputs   = task.metadata.get("inputs", {})
        start_mg = str(inputs.get("starting_dose_mg", ""))
        dlt_rate = str(inputs.get("DLT_rate_target", ""))
        design   = str(inputs.get("design", ""))

        text_lower = response.lower()

        # Strong signal: dose levels JSON present
        dose_json = inputs.get("dose_levels_json", "")
        dose_json_present = dose_json and (dose_json in response)

        # Strong signal: design name mentioned
        design_present = design and design.lower() in text_lower

        # Starting dose value present
        start_present = start_mg and start_mg in response

        # DLT rate present
        dlt_present = dlt_rate and dlt_rate in response

        # Param key names mentioned
        param_keys_present = any(kw in text_lower for kw in [
            "starting_dose", "dose_levels", "dlt_rate", "dlt rate",
            "target dlt", "pk_cl", "pk_vd", "clearance",
        ])

        if (dose_json_present or start_present) and (dlt_present or design_present):
            return 1.0
        if dose_json_present or (start_present and design_present):
            return 0.8
        if start_present or dlt_present or param_keys_present:
            return 0.5
        return 0.0

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _response_routed_to_boin(self, response: str) -> bool:
        """Return True if the response indicates clinical trial / BOIN workflow selected."""
        text = response.lower()
        return any(kw.lower() in text for kw in _BOIN_WORKFLOW_KEYWORDS)

    def _response_asks_for_trial_params(self, response: str) -> bool:
        """Return True if response asks for dose escalation or PK params."""
        text = response.lower()
        has_question = "?" in text or any(phrase in text for phrase in _QUESTION_INDICATORS)
        has_trial_kw = any(kw in text for kw in _TRIAL_PREREQ_KEYWORDS)
        return has_question and has_trial_kw

    # ------------------------------------------------------------------
    # Detailed per-task metadata for runner display
    # ------------------------------------------------------------------

    def score_detailed(
        self, task: BenchmarkTask, agent_response: str
    ) -> Dict[str, Any]:
        """
        Return a dict with sub-scores for detailed runner output.
        """
        query_type = task.metadata.get("query_type", "")
        result: Dict[str, Any] = {"query_type": query_type}

        if query_type == "complete":
            r = self.score_routing(agent_response, task)
            p = self.score_param_extraction(agent_response, task)
            result["routing_score"]  = r
            result["param_score"]    = p
            result["composite"]      = 0.55 * r + 0.45 * p
            result["routed_ok"]      = r >= 1.0
            result["params_ok"]      = p >= 0.8

        elif query_type == "incomplete":
            asked = self._response_asks_for_trial_params(agent_response)
            result["prereq_asked"]  = asked
            result["prereq_type"]   = "trial_params"
            result["composite"]     = 1.0 if asked else 0.0

        elif query_type == "negative_control":
            to_boin   = self._response_routed_to_boin(agent_response)
            to_rnaseq = any(kw in agent_response.lower() for kw in _RNASEQ_KEYWORDS)
            result["routed_to_boin"]   = to_boin
            result["routed_to_rnaseq"] = to_rnaseq
            result["composite"]        = (
                0.0 if to_boin else (1.0 if to_rnaseq else 0.5)
            )

        return result
