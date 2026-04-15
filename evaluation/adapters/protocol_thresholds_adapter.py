"""
protocol_thresholds_adapter.py
-------------------------------
Protocol-Aware QC Threshold Benchmark — 20 labeled scenarios.

Tests whether BioMate applies protocol-specific QC profiles instead of
naive universal thresholds, reducing false FAILs on specialized library types.

Dataset: evaluation/datasets/protocol_thresholds/datasets.yaml
20 entries across 16 protocol types (scRNA-seq, FFPE RNA-seq, ATAC-seq,
ChIP-seq, proteomics, metagenomics, spatial, cryo-EM).

Scoring per task:
  1.0  BioMate response matches expected_biomate_action exactly
  0.5  Off-by-one (PASS vs WARN or WARN vs FAIL)
  0.0  Completely wrong (PASS vs FAIL / FAIL vs PASS) or no action extracted

Benchmark claim: BioMate achieves ≥80% exact match on protocol edge cases.
Naive baseline: matches expected_naive_action (expected to score 0% against
expected_biomate_action since naive ≠ BioMate by design for all 20 entries).
"""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask
from ..core.llm_judge import LLMJudge


DATASET_PATH = Path(__file__).parent.parent / "datasets" / "protocol_thresholds" / "datasets.yaml"

# QC classification actions
ACTIONS = {"PASS", "WARN", "FAIL"}

# Regex to extract PASS/WARN/FAIL from response text
_ACTION_RE = re.compile(r"\b(PASS|WARN(?:ING)?|FAIL(?:ED)?|ACCEPTABLE|GOOD|POOR)\b", re.IGNORECASE)

# Normalise synonyms
_NORMALISE = {
    "WARNING": "WARN", "FAILED": "FAIL", "ACCEPTABLE": "WARN",
    "GOOD": "PASS", "POOR": "FAIL",
}


def _extract_action(text: str) -> Optional[str]:
    """Extract PASS/WARN/FAIL from free-form response text."""
    # First look for explicit "Recommendation: PASS/WARN/FAIL" lines
    for line in text.split("\n"):
        m = re.search(r"(?:recommendation|verdict|action|decision|status)[:\s]+([A-Z]+)", line, re.IGNORECASE)
        if m:
            raw = m.group(1).upper()
            if raw in ACTIONS:
                return raw
            normalised = _NORMALISE.get(raw)
            if normalised:
                return normalised

    # Fall back to first PASS/WARN/FAIL anywhere in text
    matches = _ACTION_RE.findall(text)
    for raw in matches:
        raw_upper = raw.upper()
        if raw_upper in ACTIONS:
            return raw_upper
        normalised = _NORMALISE.get(raw_upper)
        if normalised:
            return normalised

    return None


def _score_action(predicted: Optional[str], expected: str) -> float:
    """Score predicted action against expected. 1.0 exact, 0.5 off-by-one, 0.0 wrong."""
    if predicted is None:
        return 0.0
    if predicted == expected:
        return 1.0
    # Off-by-one: PASS↔WARN or WARN↔FAIL
    ordered = ["PASS", "WARN", "FAIL"]
    if predicted in ordered and expected in ordered:
        dist = abs(ordered.index(predicted) - ordered.index(expected))
        return 0.5 if dist == 1 else 0.0
    return 0.0


class ProtocolThresholdsAdapter(BenchmarkAdapter):
    """
    BioMate-unique benchmark: protocol-specific QC threshold evaluation.

    Sends each of the 20 labeled QC scenarios to BioMate via chat,
    asking it to classify the sample as PASS/WARN/FAIL using the
    protocol-appropriate QC profile. Scores against expert-labeled ground truth.
    """

    name = "protocol_thresholds"

    def __init__(self, config: Dict[str, Any],
                 protocol_filter: Optional[str] = None):
        super().__init__(config)
        self.protocol_filter = protocol_filter

    def load_tasks(self) -> List[BenchmarkTask]:
        with open(DATASET_PATH) as f:
            entries = yaml.safe_load(f)

        if self.protocol_filter:
            entries = [e for e in entries if self.protocol_filter in e.get("protocol", "")]

        tasks = []
        for entry in entries:
            prompt = self._build_prompt(entry)
            tasks.append(BenchmarkTask(
                task_id=f"protocol_thresholds__{entry['id']}",
                question=prompt,
                ground_truth=entry["expected_biomate_action"],
                domain="qc_governance",
                difficulty="medium",
                task_type="reasoning",
                answer_type="binary",
                metadata={
                    "entry_id": entry["id"],
                    "protocol": entry["protocol"],
                    "biomate_profile": entry.get("biomate_profile", ""),
                    "accession": entry.get("accession", ""),
                    "ground_truth_validity": entry.get("ground_truth", ""),
                    "expected_naive_action": entry.get("expected_naive_action", ""),
                    "expected_biomate_action": entry["expected_biomate_action"],
                    "notes": entry.get("notes", ""),
                    "source": "protocol_thresholds",
                },
            ))
        return tasks

    def _build_prompt(self, entry: Dict) -> str:
        protocol_label = entry["protocol"].replace("_", " ").title()
        problem = entry.get("universal_threshold_problem", "").strip()
        accession = entry.get("accession", "")
        notes = entry.get("notes", "").strip()

        prompt_lines = [
            f"I need a QC assessment for a {protocol_label} sample.",
        ]
        if accession:
            prompt_lines.append(f"Dataset accession: {accession}")
        if problem:
            prompt_lines.append(
                f"\nContext about this protocol's QC challenges:\n{problem}"
            )
        if notes:
            prompt_lines.append(f"\nAdditional notes: {notes}")
        prompt_lines.append(
            f"\nGiven the protocol type ({protocol_label}) and these QC characteristics, "
            f"should this sample be: PASS (acceptable quality for analysis), "
            f"WARN (proceed with caution / flag for review), or "
            f"FAIL (do not proceed)? "
            f"Please use protocol-specific criteria appropriate for {protocol_label} data "
            f"rather than universal thresholds."
        )
        return "\n".join(prompt_lines)

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        expected = task.ground_truth  # PASS / WARN / FAIL
        predicted = _extract_action(agent_response)
        return _score_action(predicted, expected)

    def task_prompt(self, task: BenchmarkTask) -> str:
        protocol = task.metadata.get("protocol", "").replace("_", " ").title()
        biomate_profile = task.metadata.get("biomate_profile", "")
        accession = task.metadata.get("accession", "")
        accession_note = (
            f"\nIMPORTANT: The accession '{accession}' is provided for context only. "
            "DO NOT attempt to look it up or fetch real data. "
            "Treat this as a hypothetical scenario with the metrics described below.\n"
        ) if accession else ""
        return (
            "QC CLASSIFICATION TEST — PROTOCOL-SPECIFIC KNOWLEDGE\n"
            "=====================================================\n"
            "HYPOTHETICAL SCENARIO: All QC metrics are provided inline.\n"
            "No real data lookup, pipeline, or tool execution is needed or allowed.\n\n"
            "You MUST respond with exactly one of: PASS, WARN, or FAIL\n"
            "Rules:\n"
            "- DO NOT fetch data, look up accessions, or request files\n"
            "- DO NOT suggest running a bioinformatics pipeline\n"
            "- DO NOT say you cannot compute QC results — this is a knowledge question\n"
            "- DO answer based solely on your knowledge of protocol-specific QC standards\n"
            "- The question contains all the context you need\n"
            f"- Apply the {protocol} QC profile"
            + (f" (BioMate profile: {biomate_profile})" if biomate_profile else "")
            + ", not universal defaults\n"
            "- KEY RULE: If the sample characteristics are EXPECTED for this protocol type\n"
            "  (e.g. low UMI for low-input, degradation for FFPE, low contrast for membrane\n"
            "  proteins, low biomass for CSF), and there is no additional critical failure,\n"
            "  the verdict is PASS — not WARN. Only give WARN if there is a concern\n"
            "  BEYOND what the protocol inherently produces.\n"
            + accession_note
            + "\n"
            + task.question
            + "\n\nVerdict (write PASS, WARN, or FAIL on the first line, then explain):"
        )
