"""
target_structure_adapter.py
---------------------------
B5 Target Structure Benchmark.

Evaluates the BioMate agent's ability to:
  L1 — Route to a structure prediction workflow (AlphaFold, Boltz, Chai, etc.)
  L2 — Identify druggable binding pockets
  L3 — Ask for missing sequence information (prerequisite detection)

Task generation:
  10 protein targets × 2 query types = 20 tasks
    complete      — UniProt ID + first 50 chars of FASTA given; expect routing + pocket mention
    incomplete    — No sequence given; expect BioMate to ask for sequence/FASTA

Scoring (L1–L4):
  complete:      1.0 if structure/pocket keywords present; 0.0 otherwise
  incomplete:    1.0 if BioMate asks for sequence; 0.0 otherwise
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult

_DATASET_PATH = (
    Path(__file__).parent.parent / "datasets" / "target_structure_benchmark" / "cases.yaml"
)

# ---------------------------------------------------------------------------
# Keyword sets
# ---------------------------------------------------------------------------

# Structure prediction workflow indicators
_STRUCTURE_KEYWORDS = [
    "alphafold",
    "alpha fold",
    "boltz",
    "chai",
    "esmfold",
    "esm fold",
    "rosettafold",
    "structure prediction",
    "protein structure",
    "3d structure",
    "three-dimensional structure",
    "fold",
    "homology model",
    "structure model",
    "protein folding",
    "structure workflow",
    "predict.*structure",
    "structure.*predict",
]

# Pocket / druggability detection indicators
_POCKET_KEYWORDS = [
    "pocket",
    "binding site",
    "druggable",
    "active site",
    "allosteric",
    "fpocket",
    "dosurf",
    "p2rank",
    "sitemap",
    "binding cavity",
    "cavity",
    "drug.*binding",
    "binding.*drug",
]

# Question / prerequisite indicators
_QUESTION_INDICATORS = [
    "please provide", "can you provide", "could you provide",
    "i need", "what is the", "can you share", "do you have",
    "please share", "let me know", "tell me", "provide the",
    "more information", "additional details", "?",
]

# Sequence prerequisite keywords
_SEQUENCE_PREREQ_KEYWORDS = [
    "sequence", "fasta", "amino acid", "protein sequence",
    "aa sequence", "uniprot", "accession", "pdb",
]


class TargetStructureAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for B5 Target Structure (L1–L4).

    Generates 20 tasks: 10 protein targets × 2 query types.
    """

    name = "target_structure_benchmark"

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
        Generate 20 tasks: 10 targets × 2 query types.

        Query types per target:
          complete   — UniProt ID + truncated FASTA; expect workflow routing
          incomplete — no sequence; expect BioMate to ask for sequence/FASTA
        """
        data = self._load_dataset()
        tasks: List[BenchmarkTask] = []

        for case in data["cases"]:
            case_id    = case["id"]
            name       = case["name"]
            uniprot_id = case["uniprot_id"]
            fasta      = case["fasta"]
            pockets    = case.get("expected_pocket_residues", [])
            druggable  = case.get("expected_druggable", True)
            difficulty = case.get("difficulty", "medium")

            # ---- complete query ------------------------------------------------
            fasta_snippet = fasta[:50]
            complete_question = (
                f"Predict the 3D structure of {name} (UniProt: {uniprot_id}) "
                f"and identify druggable binding pockets. "
                f"Sequence: {fasta_snippet}..."
            )
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_complete",
                question=complete_question,
                ground_truth={
                    "expected_routing":  True,
                    "expected_pockets":  pockets,
                    "expected_druggable": druggable,
                    "expected_prereq_ask": False,
                },
                domain="protein_structure",
                difficulty=difficulty,
                task_type="workflow",
                answer_type="open",
                metadata={
                    "case_id":      case_id,
                    "target_name":  name,
                    "uniprot_id":   uniprot_id,
                    "fasta":        fasta,
                    "query_type":   "complete",
                    "expected_pocket_residues": pockets,
                    "expected_druggable":       druggable,
                    "benchmark":    "target_structure_benchmark",
                },
            ))

            # ---- incomplete query (no sequence) --------------------------------
            incomplete_question = (
                "Predict the structure and identify pockets for a protein target"
            )
            tasks.append(BenchmarkTask(
                task_id=f"{case_id}_incomplete",
                question=incomplete_question,
                ground_truth={
                    "expected_routing":    True,
                    "expected_prereq_ask": True,
                    "prereq_type":         "sequence",
                },
                domain="protein_structure",
                difficulty="easy",
                task_type="workflow",
                answer_type="open",
                metadata={
                    "case_id":      case_id,
                    "target_name":  name,
                    "uniprot_id":   uniprot_id,
                    "fasta":        fasta,   # not in query — BioMate must ask
                    "query_type":   "incomplete",
                    "expected_prereq_ask": True,
                    "prereq_type":         "sequence",
                    "benchmark":    "target_structure_benchmark",
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
        Score agent response.

        Returns 0.0–1.0:
          complete:   1.0 if structure prediction + pocket keywords present
          incomplete: 1.0 if BioMate asks for sequence/FASTA; 0.5 if partial signal
        """
        query_type = task.metadata.get("query_type", "")
        if query_type == "complete":
            return self._score_complete(task, agent_response)
        elif query_type == "incomplete":
            return self._score_incomplete(task, agent_response)
        return 0.0

    def _score_complete(self, task: BenchmarkTask, response: str) -> float:
        """
        Score a complete query.

        Routing criterion: mentions a structure prediction tool/workflow.
        Pocket criterion: mentions pocket / binding site / druggable.

        Returns:
          1.0 — both structure routing and pocket detection present
          0.5 — only structure routing OR only pocket keyword
          0.0 — neither
        """
        structure_hit = self._has_structure_keyword(response)
        pocket_hit    = self._has_pocket_keyword(response)

        if structure_hit and pocket_hit:
            return 1.0
        if structure_hit or pocket_hit:
            return 0.5
        return 0.0

    def _score_incomplete(self, task: BenchmarkTask, response: str) -> float:
        """
        Score an incomplete query (no sequence given).

        BioMate should ask for the protein sequence / FASTA / UniProt accession.

        Returns:
          1.0 — asks for sequence
          0.5 — mentions structure prediction but does not ask
          0.0 — no signal
        """
        if self._asks_for_sequence(response):
            return 1.0
        if self._has_structure_keyword(response):
            return 0.5
        return 0.0

    # ------------------------------------------------------------------
    # Sub-helpers
    # ------------------------------------------------------------------

    def _has_structure_keyword(self, response: str) -> bool:
        text_lower = response.lower()
        for kw in _STRUCTURE_KEYWORDS:
            if re.search(kw, text_lower):
                return True
        return False

    def _has_pocket_keyword(self, response: str) -> bool:
        text_lower = response.lower()
        for kw in _POCKET_KEYWORDS:
            if re.search(kw, text_lower):
                return True
        return False

    def _asks_for_sequence(self, response: str) -> bool:
        text_lower = response.lower()
        has_question = any(ind in text_lower for ind in _QUESTION_INDICATORS)
        has_seq_kw   = any(kw in text_lower for kw in _SEQUENCE_PREREQ_KEYWORDS)
        return has_question and has_seq_kw

    # ------------------------------------------------------------------
    # Detailed sub-scores for runner display
    # ------------------------------------------------------------------

    def score_detailed(self, task: BenchmarkTask, agent_response: str) -> Dict[str, Any]:
        """Return a dict with sub-scores for display."""
        query_type = task.metadata.get("query_type", "")
        result: Dict[str, Any] = {"query_type": query_type}

        if query_type == "complete":
            s = self._has_structure_keyword(agent_response)
            p = self._has_pocket_keyword(agent_response)
            result["structure_routing"] = s
            result["pocket_detected"]   = p
            result["composite"]         = self._score_complete(task, agent_response)

        elif query_type == "incomplete":
            asked = self._asks_for_sequence(agent_response)
            has_struct = self._has_structure_keyword(agent_response)
            result["prereq_asked"]      = asked
            result["has_struct_kw"]     = has_struct
            result["composite"]         = self._score_incomplete(task, agent_response)

        return result
