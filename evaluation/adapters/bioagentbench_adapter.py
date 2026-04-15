"""
bioagentbench_adapter.py
------------------------
Adapter for BioAgentBench — pipeline execution + robustness testing.

BioAgentBench tests bioinformatics pipeline agents on:
  - 3 pipeline types: RNA-seq, variant calling, metagenomics
  - 5 variants per pipeline: baseline + 4 perturbation types

Perturbation types:
  P1: corrupted_input     — truncated FASTQ, malformed VCF
  P2: decoy_files         — misleading filenames in working directory
  P3: prompt_bloat        — extra irrelevant context injected into task
  P4: missing_intermediate — required intermediate file deleted mid-run

BioMate's unique advantage: prereq validation + approval gate should
detect P1 and P4 explicitly and recover; P3 tests domain routing robustness.

Citation: arXiv:2601.21800 (Jan 2026)

Setup:
    # Download dataset from paper's GitHub (check arXiv for repo link)
    # Set paths.bioagentbench_dir in config.yaml
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult
from ..core.llm_judge import LLMJudge


PIPELINE_TYPES = ["rnaseq", "variant_calling", "metagenomics"]
PERTURBATIONS = ["baseline", "corrupted_input", "decoy_files", "prompt_bloat", "missing_intermediate"]

# Domain-specific validity checks on pipeline outputs
VALIDITY_CHECKS = {
    "rnaseq": {
        "required_outputs": ["counts_matrix", "differential_expression"],
        "format_check": lambda text: any(kw in text.lower() for kw in ["deseq2", "edger", "differential", "counts"]),
    },
    "variant_calling": {
        "required_outputs": ["vcf", "variants"],
        "format_check": lambda text: any(kw in text.lower() for kw in ["vcf", "variant", "snp", "indel"]),
    },
    "metagenomics": {
        "required_outputs": ["taxonomy", "diversity"],
        "format_check": lambda text: any(kw in text.lower() for kw in ["taxa", "microbiome", "diversity", "kraken"]),
    },
}

# Failure mode classification
class FailureMode:
    SILENT    = "SILENT_FAILURE"        # wrong output, no error reported
    DETECTED  = "DETECTED_UNRECOVERED"  # error reported, pipeline aborted
    RECOVERED = "DETECTED_RECOVERED"    # error reported, pipeline succeeded anyway
    FALSE_ALARM = "FALSE_ALARM"         # error reported on a valid input


class BioAgentBenchAdapter(BenchmarkAdapter):
    """
    BioAgentBench adapter — pipeline completion + robustness scoring.

    Key metric: robustness_score = fraction of perturbations where BioMate
    either recovers (DETECTED_RECOVERED) or correctly reports the issue
    (DETECTED_UNRECOVERED), vs silently producing wrong output (SILENT_FAILURE).

    Frontier model baselines: complete baseline tasks but fail all 4 perturbations.
    BioMate target: maintain completion on baseline + detect 3/4 perturbation types.
    """

    name = "bioagentbench"

    def __init__(self, config: Dict[str, Any],
                 pipeline_types: Optional[List[str]] = None,
                 perturbations: Optional[List[str]] = None):
        super().__init__(config)
        self.pipeline_types = pipeline_types or PIPELINE_TYPES
        self.perturbations = perturbations or PERTURBATIONS

        bench_dir = config["paths"].get("bioagentbench_dir", "")
        if not bench_dir:
            raise ValueError(
                "paths.bioagentbench_dir not set in config.yaml.\n"
                "Download the BioAgentBench dataset from arXiv:2601.21800 GitHub."
            )
        self.bench_dir = Path(bench_dir)
        self._judge: Optional[LLMJudge] = None

    def prepare(self, client) -> None:
        self._judge = LLMJudge(model=self.config["llm_judge"]["model"], api_key=self.config.get("llm_judge",{}).get("api_key"))

    def load_tasks(self) -> List[BenchmarkTask]:
        tasks = []
        for pipeline in self.pipeline_types:
            for perturbation in self.perturbations:
                task_dir = self.bench_dir / pipeline / perturbation
                if not task_dir.exists():
                    continue

                task_file = task_dir / "task.json"
                if not task_file.exists():
                    continue

                task_data = json.loads(task_file.read_text())

                tasks.append(BenchmarkTask(
                    task_id=f"bioagentbench__{pipeline}__{perturbation}",
                    question=task_data["task_description"],
                    ground_truth={
                        "pipeline": pipeline,
                        "perturbation": perturbation,
                        "expected_outputs": task_data.get("expected_outputs", []),
                        "is_valid_input": perturbation != "corrupted_input",
                    },
                    domain="life_science",
                    difficulty="hard" if perturbation != "baseline" else "medium",
                    task_type="workflow",
                    answer_type="open",
                    metadata={
                        "pipeline": pipeline,
                        "perturbation": perturbation,
                        "task_dir": str(task_dir),
                        "data_files": task_data.get("data_files", []),
                        "source": "bioagentbench",
                    },
                ))
        return tasks

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Scoring:
          Baseline task:    1.0 if pipeline output present and valid; else 0.0
          Perturbation:     1.0 if DETECTED_RECOVERED
                            0.5 if DETECTED_UNRECOVERED (caught the error)
                            0.0 if SILENT_FAILURE (wrong output, no error)
                           -0.5 if FALSE_ALARM on baseline (penalize noise)
        """
        gt = task.ground_truth
        pipeline = gt["pipeline"]
        perturbation = gt["perturbation"]
        is_valid = gt["is_valid_input"]

        response_lower = agent_response.lower()
        validity = VALIDITY_CHECKS[pipeline]

        # Check output validity
        output_valid = validity["format_check"](agent_response)

        # Check if BioMate reported an error / issue
        error_reported = any(kw in response_lower for kw in [
            "error", "failed", "corrupt", "invalid", "missing", "cannot",
            "unable to", "issue detected", "prerequisite", "warning",
        ])

        if perturbation == "baseline":
            if not is_valid:
                return 0.0
            if output_valid:
                return 1.0
            if error_reported:
                return -0.5   # false alarm on valid input
            return 0.0

        # Perturbation cases
        failure_mode = self._classify_failure(output_valid, error_reported, is_valid)

        scores = {
            FailureMode.RECOVERED:   1.0,
            FailureMode.DETECTED:    0.5,
            FailureMode.SILENT:      0.0,
            FailureMode.FALSE_ALARM: -0.5,
        }
        return scores.get(failure_mode, 0.0)

    def _classify_failure(self, output_valid: bool, error_reported: bool,
                          is_valid_input: bool) -> str:
        if not is_valid_input:
            if output_valid and not error_reported:
                return FailureMode.SILENT
            if error_reported and output_valid:
                return FailureMode.RECOVERED
            if error_reported and not output_valid:
                return FailureMode.DETECTED
            return FailureMode.SILENT
        else:
            if error_reported:
                return FailureMode.FALSE_ALARM
            return FailureMode.RECOVERED if output_valid else FailureMode.SILENT

    def robustness_score(self, results: List[BenchmarkResult],
                         pipeline: Optional[str] = None) -> Dict[str, float]:
        """
        Compute robustness metrics from a set of results.
        Returns: {baseline_rate, detection_rate, recovery_rate, silent_failure_rate}
        """
        baseline = [r for r in results
                    if r.metadata.get("perturbation") == "baseline"
                    and (pipeline is None or r.metadata.get("pipeline") == pipeline)]
        perturbed = [r for r in results
                     if r.metadata.get("perturbation") != "baseline"
                     and (pipeline is None or r.metadata.get("pipeline") == pipeline)]

        baseline_rate = sum(1 for r in baseline if r.score >= 1.0) / max(len(baseline), 1)
        recovery_rate = sum(1 for r in perturbed if r.score >= 1.0) / max(len(perturbed), 1)
        detection_rate = sum(1 for r in perturbed if r.score >= 0.5) / max(len(perturbed), 1)
        silent_rate = sum(1 for r in perturbed if r.score <= 0.0) / max(len(perturbed), 1)

        return {
            "baseline_completion": baseline_rate,
            "recovery_rate": recovery_rate,
            "detection_rate": detection_rate,
            "silent_failure_rate": silent_rate,
        }
