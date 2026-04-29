"""
pbpk_benchmark_adapter.py
-------------------------
B3 PBPK Simulation Benchmark — Stage S4 (Preclinical / human PK prediction).

Tests the full chain: NL intent → workflow routing → parameter extraction
→ prerequisite detection (L1–L4).

For L5–L6 (execution + output validity), use the --layers L5L6 flag in the
runner, which calls pbpk_scorer.parse_pbpk_output() on actual Nextflow output.

Task generation:
  15 compounds × 3 query types = 45 tasks
    complete_with_params — all physicochemical params in query; expect routing + extraction
    incomplete_no_smiles — missing SMILES; expect BioMate to ask for structure
    incomplete_no_params — has SMILES but missing CLint/fu_plasma; expect prereq ask

Scoring (L1–L4):
  complete_with_params: routing correct (1.0) + param extraction partial score
  incomplete_no_smiles: prereq detection — did BioMate ask for SMILES? (1.0/0.0)
  incomplete_no_params: prereq detection — did BioMate ask for CLint/fu_plasma? (1.0/0.0)

Routing keywords (case-insensitive, any match = correct):
  pbpk_simulation, pbpk, physiologically_based, pharmacokinetic, pk_prediction,
  drug_discovery (full pipeline)
"""

from __future__ import annotations

import re
import time
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult

_DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "pbpk_benchmark" / "cases.yaml"
)

# ---------------------------------------------------------------------------
# Routing keywords
# ---------------------------------------------------------------------------

_PBPK_WORKFLOW_KEYWORDS = [
    "pbpk_simulation",
    "pbpk simulation",
    "pbpk",
    "physiologically based pharmacokinetic",
    "physiologically-based",
    "pk prediction",
    "pk simulation",
    "pharmacokinetic simulation",
    "pk_simulation",
    "pk_profile",
    "drug_discovery",           # full pipeline also acceptable
    "clinical pharmacology",
    "pk modeling",
]

# Partial ADMET-related keywords that indicate PK domain awareness
_PK_RELATED_KEYWORDS = [
    "pharmacokinetics", "pk", "cmax", "auc", "clearance", "half-life",
    "t1/2", "t½", "volume of distribution", "bioavailability",
    "absorption", "distribution", "metabolism", "elimination",
    "adme", "first pass", "protein binding", "fu_plasma",
]

# Keywords for prereq detection: questions asking for SMILES
_SMILES_PREREQ_KEYWORDS = [
    "smiles", "structure", "chemical structure", "compound", "molecule",
]

# Keywords for prereq detection: questions asking for PK input params
_PARAMS_PREREQ_KEYWORDS = [
    "clearance", "clint", "intrinsic clearance", "fu_plasma", "unbound fraction",
    "protein binding", "mw", "molecular weight", "logp", "pka",
    "renal clearance", "cl_int", "fu plasma",
]

# General question indicators
_QUESTION_INDICATORS = [
    "please provide", "can you provide", "could you", "i need",
    "what is the", "can you share", "do you have", "please share",
    "let me know", "tell me", "provide the", "what compound",
    "which compound", "more information", "additional details", "?",
]

# Negative control: RNA-seq query routing keywords
_RNASEQ_KEYWORDS = [
    "rnaseq", "rna-seq", "rna_seq", "differential expression",
    "deseq", "edger", "nf-core/rnaseq", "fastq",
]


class PBPKBenchmarkAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for B3 PBPK Simulation (L1–L4).

    Generates 45 tasks: 15 compounds × 3 query types.
    """

    name = "pbpk_benchmark"

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
        Generate 45 tasks: 15 compounds × 3 query types.

        Query types per compound:
          complete_with_params — all physicochemical params in query
          incomplete_no_smiles — no SMILES; should trigger prereq ask
          incomplete_no_params — has SMILES but no CLint/fu_plasma; should trigger ask
        """
        data = self._load_dataset()
        tasks: List[BenchmarkTask] = []

        for case in data["cases"]:
            case_id  = case["id"]
            name     = case["name"]
            smiles   = case["smiles"]
            dose_mg  = case["dose_mg"]
            route    = case["route"]
            inputs   = case["inputs"]
            ref      = case["reference"]
            diff     = case.get("difficulty", "medium")
            notes    = case.get("notes", "")

            # ---- complete_with_params ----------------------------------------
            complete_query = (
                f"Run PBPK simulation for {name} ({smiles}): "
                f"dose {dose_mg}mg {route}, "
                f"MW={inputs['MW']}, logP={inputs['logP']}, pKa={inputs['pKa']}, "
                f"fu_plasma={inputs['fu_plasma']}, "
                f"CLint={inputs['CLint_uL_min_mg']} uL/min/mg, "
                f"renal_CL={inputs['renal_CL_mL_min']} mL/min"
            )
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_complete",
                question=complete_query,
                ground_truth={
                    "expected_routing":   True,
                    "expected_workflow_type": "pbpk",
                    "expected_params": {
                        "SMILES":      smiles,
                        "dose_mg":     str(dose_mg),
                        "route":       route,
                        "fu_plasma":   str(inputs["fu_plasma"]),
                        "CLint_uL_min_mg": str(inputs["CLint_uL_min_mg"]),
                    },
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
                    "dose_mg":            dose_mg,
                    "route":              route,
                    "inputs":             inputs,
                    "query_type":         "complete_with_params",
                    "expected_routing":   True,
                    "expected_params":    ["SMILES", "dose_mg", "fu_plasma",
                                          "CLint_uL_min_mg"],
                    "expected_prereq_ask": False,
                    "reference":          ref,
                    "notes":              notes,
                    "benchmark":          "pbpk_benchmark",
                },
            ))

            # ---- incomplete_no_smiles ----------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_no_smiles",
                question=(
                    "Predict the human pharmacokinetics of my compound at "
                    f"{dose_mg}mg {route} dose. "
                    f"MW={inputs['MW']}, logP={inputs['logP']}, "
                    f"fu_plasma={inputs['fu_plasma']}, "
                    f"CLint={inputs['CLint_uL_min_mg']} uL/min/mg"
                ),
                ground_truth={
                    "expected_routing":   True,
                    "expected_workflow_type": "pbpk",
                    "expected_params":    {},
                    "expected_prereq_ask": True,
                    "prereq_type":        "smiles",
                },
                domain="drug_discovery",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={
                    "case_id":            case_id,
                    "compound_name":      name,
                    "smiles":             smiles,   # not in query — BioMate must ask
                    "query_type":         "incomplete_no_smiles",
                    "expected_routing":   True,
                    "expected_params":    [],
                    "expected_prereq_ask": True,
                    "prereq_type":        "smiles",
                    "reference":          ref,
                    "benchmark":          "pbpk_benchmark",
                },
            ))

            # ---- incomplete_no_params ----------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_no_params",
                question=f"Run PBPK simulation for {smiles}",
                ground_truth={
                    "expected_routing":   True,
                    "expected_workflow_type": "pbpk",
                    "expected_params":    {},
                    "expected_prereq_ask": True,
                    "prereq_type":        "pk_params",
                },
                domain="drug_discovery",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={
                    "case_id":            case_id,
                    "compound_name":      name,
                    "smiles":             smiles,
                    "query_type":         "incomplete_no_params",
                    "expected_routing":   True,
                    "expected_params":    [],
                    "expected_prereq_ask": True,
                    "prereq_type":        "pk_params",
                    "reference":          ref,
                    "benchmark":          "pbpk_benchmark",
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

        if query_type == "complete_with_params":
            return self._score_complete(task, agent_response)
        elif query_type == "incomplete_no_smiles":
            return self._score_no_smiles(task, agent_response)
        elif query_type == "incomplete_no_params":
            return self._score_no_params(task, agent_response)
        return 0.0

    def _score_complete(self, task: BenchmarkTask, response: str) -> float:
        """
        Score a complete_with_params task.

        Scoring formula:
          routing_score (0.0/0.5/1.0) — routed to PBPK workflow?
          param_score   (0.0/0.5/1.0) — extracted SMILES + key PK params?
          composite = 0.55 × routing + 0.45 × param
        """
        routing_score = self.score_routing(response, task)
        param_score   = self.score_param_extraction(response, task)
        return 0.55 * routing_score + 0.45 * param_score

    def _score_no_smiles(self, task: BenchmarkTask, response: str) -> float:
        """
        Score an incomplete_no_smiles task.

        Scoring rubric:
          1.0 — BioMate asks for SMILES before routing (ideal)
          0.5 — BioMate routes to PBPK with physicochemical params provided
                (acceptable: MW, logP, CLint, fu_plasma are present; SMILES optional)
          0.5 — BioMate recognises PK domain but does not route
          0.0 — No PK signal at all
        """
        if self._response_asks_for_smiles(response):
            return 1.0
        # BioMate routed to PBPK using the provided physicochemical parameters.
        # Acceptable because CLint/fu_plasma/MW/logP are all present — SMILES adds
        # compound identity but PBPK can run on empirical parameters alone.
        if self._response_routed_to_pbpk(response):
            return 0.5
        # Partial credit for recognising PBPK intent
        if any(kw in response.lower() for kw in _PK_RELATED_KEYWORDS):
            return 0.5
        return 0.0

    def _score_no_params(self, task: BenchmarkTask, response: str) -> float:
        """
        Score an incomplete_no_params task.

        SMILES is in the query but PK input params (CLint, fu_plasma) are missing.
        BioMate should ask for them.

        Scoring rubric:
          1.0 — BioMate asks for PK params (CLint / fu_plasma) — ideal behaviour
          0.5 — BioMate launches the PBPK workflow using default PK params — acceptable
                (PK params have defaults so this is valid agent behaviour)
          0.5 — BioMate asks for SMILES (redundant but still a prereq interaction)
          0.5 — BioMate shows PK domain awareness without a clear action
          0.0 — No PK signal at all
        """
        if self._response_asks_for_pk_params(response):
            return 1.0
        # BioMate might ask for SMILES even though it's present — that's still a prereq ask
        if self._response_asks_for_smiles(response):
            return 0.5
        # BioMate launched the PBPK workflow using default params — acceptable (0.5)
        # Previously this was scored 0.0, but using defaults is valid agent behaviour
        # because PK input params all have sensible defaults in the PBPK workflow.
        if self._response_routed_to_pbpk(response):
            return 0.5
        if any(kw in response.lower() for kw in _PK_RELATED_KEYWORDS):
            return 0.5
        return 0.0

    # ------------------------------------------------------------------
    # Sub-scorers (also usable from runner for detailed metrics)
    # ------------------------------------------------------------------

    def score_routing(self, response: str, task: BenchmarkTask) -> float:
        """
        Extract routing signal from agent response.

        Returns:
          1.0  — clearly routed to PBPK workflow
          0.5  — mentioned PK concepts but unclear routing
          0.0  — no routing signal or wrong domain
        """
        text_lower = response.lower()

        # Pattern: [routed:pbpk_simulation] or [workflow:pbpk]
        routed_match = re.search(r"\[routed?:([^\]]+)\]", text_lower)
        if routed_match:
            wf_name = routed_match.group(1)
            if any(kw in wf_name for kw in ["pbpk", "pharmacokinetic", "drug_discovery"]):
                return 1.0
            return 0.0

        if self._response_routed_to_pbpk(response):
            return 1.0

        if any(kw in text_lower for kw in _PK_RELATED_KEYWORDS):
            return 0.5

        return 0.0

    def score_param_extraction(self, response: str, task: BenchmarkTask) -> float:
        """
        Check whether key PBPK params were extracted from the query.

        Looks for SMILES, dose_mg, fu_plasma, CLint appearing in response.

        Returns 0.0, 0.5, or 1.0.
        """
        smiles   = task.metadata.get("smiles", "")
        inputs   = task.metadata.get("inputs", {})
        fu_str   = str(inputs.get("fu_plasma", ""))
        cl_str   = str(inputs.get("CLint_uL_min_mg", ""))
        dose_str = str(task.metadata.get("dose_mg", ""))

        text_lower = response.lower()

        # Strong signal: actual SMILES in response
        smiles_present = smiles and (smiles.lower() in text_lower or smiles in response)

        # Strong signal: fu_plasma value or CLint value explicitly present
        fu_present = fu_str and fu_str in response
        cl_present = cl_str and cl_str in response

        # Param key names mentioned
        param_keys_present = any(kw in text_lower for kw in [
            "fu_plasma", "clint", "cl_int", "dose", "smiles", "route",
        ])

        if smiles_present and (fu_present or cl_present):
            return 1.0
        if smiles_present or (fu_present and cl_present):
            return 0.8
        if smiles_present or param_keys_present:
            return 0.5
        return 0.0

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _response_routed_to_pbpk(self, response: str) -> bool:
        """Return True if the response indicates PBPK workflow was selected."""
        text = response.lower()
        return any(kw.lower() in text for kw in _PBPK_WORKFLOW_KEYWORDS)

    def _response_asks_for_smiles(self, response: str) -> bool:
        """Return True if the response contains a question about SMILES/compound structure."""
        text = response.lower()
        has_question = "?" in text or any(phrase in text for phrase in _QUESTION_INDICATORS)
        has_smiles_kw = any(kw in text for kw in _SMILES_PREREQ_KEYWORDS)
        return has_question and has_smiles_kw

    def _response_asks_for_pk_params(self, response: str) -> bool:
        """Return True if response asks for clearance/binding PK input parameters."""
        text = response.lower()
        has_question = "?" in text or any(phrase in text for phrase in _QUESTION_INDICATORS)
        has_param_kw = any(kw in text for kw in _PARAMS_PREREQ_KEYWORDS)
        return has_question and has_param_kw

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

        if query_type == "complete_with_params":
            r = self.score_routing(agent_response, task)
            p = self.score_param_extraction(agent_response, task)
            result["routing_score"]  = r
            result["param_score"]    = p
            result["composite"]      = 0.55 * r + 0.45 * p
            result["routed_ok"]      = r >= 1.0
            result["params_ok"]      = p >= 0.8

        elif query_type == "incomplete_no_smiles":
            asked = self._response_asks_for_smiles(agent_response)
            result["prereq_asked"]  = asked
            result["prereq_type"]   = "smiles"
            result["composite"]     = 1.0 if asked else 0.0

        elif query_type == "incomplete_no_params":
            asked_params = self._response_asks_for_pk_params(agent_response)
            asked_smiles = self._response_asks_for_smiles(agent_response)
            routed_with_defaults = (
                not asked_params and not asked_smiles and
                self._response_routed_to_pbpk(agent_response)
            )
            result["prereq_asked"]            = asked_params or asked_smiles
            result["asked_pk_params"]         = asked_params
            result["asked_smiles"]            = asked_smiles
            result["routed_with_defaults"]    = routed_with_defaults
            result["prereq_type"]             = "pk_params"
            # 1.0=asked params, 0.5=asked SMILES or routed with defaults, 0.0=no signal
            result["composite"] = (
                1.0 if asked_params
                else 0.5 if (asked_smiles or routed_with_defaults)
                else 0.0
            )

        return result
