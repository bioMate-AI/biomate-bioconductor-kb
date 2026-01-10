"""
Evaluators for BioMate Test Harness

Provides multi-level evaluation:
- Tool Evaluator: Tool selection and execution quality
- Workflow Evaluator: Workflow design and orchestration
- Scientific Evaluator: Scientific correctness (SGI-Bench aligned)
"""

import logging
import json
import time
from abc import ABC, abstractmethod
from typing import Dict, List, Any, Optional, Callable
from dataclasses import dataclass, field
from datetime import datetime

from .user_context import (
    UserBenchmarkContext,
    EvaluationTask,
    EvaluationCriteria,
    UserContextDB
)
from .sgi_bench_adapter import (
    SGIScorer,
    SGIPromptTemplates,
    SGITaskType,
    SGISample
)

log = logging.getLogger(__name__)


@dataclass
class EvaluationResult:
    """Result of a single evaluation."""
    evaluator_type: str
    task_type: str
    scores: Dict[str, float]
    weighted_score: float
    details: Dict[str, Any] = field(default_factory=dict)
    timestamp: str = field(default_factory=lambda: datetime.now().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        return {
            "evaluator_type": self.evaluator_type,
            "task_type": self.task_type,
            "scores": self.scores,
            "weighted_score": self.weighted_score,
            "details": self.details,
            "timestamp": self.timestamp
        }


@dataclass
class EvaluationReport:
    """Comprehensive evaluation report."""
    user_id: str
    project_id: str
    dataset_id: str
    results: List[EvaluationResult]
    overall_score: float
    summary: str
    recommendations: List[str]
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())

    def to_dict(self) -> Dict[str, Any]:
        return {
            "user_id": self.user_id,
            "project_id": self.project_id,
            "dataset_id": self.dataset_id,
            "results": [r.to_dict() for r in self.results],
            "overall_score": self.overall_score,
            "summary": self.summary,
            "recommendations": self.recommendations,
            "created_at": self.created_at
        }


class BaseEvaluator(ABC):
    """Base class for all evaluators."""

    def __init__(self, user_context: UserBenchmarkContext = None):
        self.user_context = user_context
        self.evaluator_type = self.__class__.__name__

    @abstractmethod
    def evaluate(
        self,
        prediction: Any,
        ground_truth: Any,
        task_type: EvaluationTask = None
    ) -> EvaluationResult:
        """Evaluate prediction against ground truth."""
        pass

    def _calculate_weighted_score(
        self,
        scores: Dict[str, float],
        weights: Dict[str, float] = None
    ) -> float:
        """Calculate weighted average score."""
        if not weights:
            # Equal weights
            return sum(scores.values()) / len(scores) if scores else 0.0

        total_weight = sum(weights.get(k, 0) for k in scores)
        if total_weight == 0:
            return 0.0

        weighted_sum = sum(scores[k] * weights.get(k, 0) for k in scores)
        return weighted_sum / total_weight


class ToolEvaluator(BaseEvaluator):
    """
    Evaluates tool selection and execution quality.

    Metrics:
    - selection_accuracy: Was the right tool selected?
    - parameter_correctness: Were parameters configured correctly?
    - execution_success: Did the tool run successfully?
    - output_quality: Quality of tool output
    """

    def evaluate(
        self,
        prediction: Dict[str, Any],
        ground_truth: Dict[str, Any],
        task_type: EvaluationTask = None
    ) -> EvaluationResult:
        """
        Evaluate tool usage.

        Args:
            prediction: Dict with keys: tool_id, parameters, output
            ground_truth: Dict with keys: expected_tool, expected_params, expected_output

        Returns:
            EvaluationResult
        """
        scores = {
            "selection_accuracy": 0.0,
            "parameter_correctness": 0.0,
            "execution_success": 0.0,
            "output_quality": 0.0
        }

        # Tool selection accuracy
        pred_tool = prediction.get('tool_id', '')
        expected_tool = ground_truth.get('expected_tool', '')
        if pred_tool == expected_tool:
            scores["selection_accuracy"] = 1.0
        elif self._tools_equivalent(pred_tool, expected_tool):
            scores["selection_accuracy"] = 0.8

        # Parameter correctness
        pred_params = prediction.get('parameters', {})
        expected_params = ground_truth.get('expected_params', {})
        scores["parameter_correctness"] = self._score_parameters(
            pred_params, expected_params
        )

        # Execution success
        if prediction.get('execution_success', False):
            scores["execution_success"] = 1.0
        elif prediction.get('partial_success', False):
            scores["execution_success"] = 0.5

        # Output quality
        pred_output = prediction.get('output', '')
        expected_output = ground_truth.get('expected_output', '')
        scores["output_quality"] = self._score_output(pred_output, expected_output)

        # Get weights from user context if available
        weights = None
        if self.user_context:
            criteria = self.user_context.get_evaluation_criteria(
                EvaluationTask.DRY_EXPERIMENT  # Tool evaluation maps to dry experiment
            )
            if criteria:
                weights = criteria.scoring_weights

        weighted_score = self._calculate_weighted_score(scores, weights)

        return EvaluationResult(
            evaluator_type=self.evaluator_type,
            task_type=task_type.value if task_type else "tool_evaluation",
            scores=scores,
            weighted_score=weighted_score,
            details={
                "predicted_tool": pred_tool,
                "expected_tool": expected_tool,
                "param_diff": self._get_param_diff(pred_params, expected_params)
            }
        )

    def _tools_equivalent(self, tool1: str, tool2: str) -> bool:
        """Check if two tools are functionally equivalent."""
        # Define equivalent tool groups
        equivalents = {
            frozenset(["star", "hisat2", "tophat"]): "rna_aligner",
            frozenset(["salmon", "kallisto", "rsem"]): "quantifier",
            frozenset(["gatk", "freebayes", "bcftools"]): "variant_caller",
        }

        tool1_lower = tool1.lower()
        tool2_lower = tool2.lower()

        for group in equivalents:
            if tool1_lower in group and tool2_lower in group:
                return True
        return False

    def _score_parameters(
        self,
        pred_params: Dict,
        expected_params: Dict
    ) -> float:
        """Score parameter correctness."""
        if not expected_params:
            return 1.0 if not pred_params else 0.5

        if not pred_params:
            return 0.0

        matches = 0
        for key, expected_val in expected_params.items():
            if key in pred_params:
                if pred_params[key] == expected_val:
                    matches += 1
                elif self._values_close(pred_params[key], expected_val):
                    matches += 0.5

        return matches / len(expected_params)

    def _values_close(self, val1, val2, tolerance=0.1) -> bool:
        """Check if two values are numerically close."""
        try:
            return abs(float(val1) - float(val2)) / max(abs(float(val2)), 1e-10) < tolerance
        except (ValueError, TypeError):
            return str(val1).lower() == str(val2).lower()

    def _score_output(self, pred_output, expected_output) -> float:
        """Score output quality."""
        if not expected_output:
            return 1.0 if pred_output else 0.5

        if not pred_output:
            return 0.0

        # Basic comparison - in practice would use more sophisticated methods
        pred_str = str(pred_output).strip()
        expected_str = str(expected_output).strip()

        if pred_str == expected_str:
            return 1.0
        elif pred_str in expected_str or expected_str in pred_str:
            return 0.5
        return 0.0

    def _get_param_diff(self, pred: Dict, expected: Dict) -> Dict:
        """Get parameter differences."""
        diff = {
            "missing": [],
            "extra": [],
            "different": {}
        }

        for key in expected:
            if key not in pred:
                diff["missing"].append(key)
            elif pred[key] != expected[key]:
                diff["different"][key] = {
                    "predicted": pred[key],
                    "expected": expected[key]
                }

        for key in pred:
            if key not in expected:
                diff["extra"].append(key)

        return diff


class WorkflowEvaluator(BaseEvaluator):
    """
    Evaluates workflow design and execution quality.

    Metrics:
    - structure_correctness: Workflow structure matches expected
    - step_ordering: Steps are in correct order
    - data_flow: Data flows correctly between steps
    - completeness: All required steps are present
    """

    def evaluate(
        self,
        prediction: Dict[str, Any],
        ground_truth: Dict[str, Any],
        task_type: EvaluationTask = None
    ) -> EvaluationResult:
        """
        Evaluate workflow.

        Args:
            prediction: Dict with keys: steps, connections, outputs
            ground_truth: Dict with expected workflow structure

        Returns:
            EvaluationResult
        """
        scores = {
            "structure_correctness": 0.0,
            "step_ordering": 0.0,
            "data_flow": 0.0,
            "completeness": 0.0
        }

        pred_steps = prediction.get('steps', [])
        expected_steps = ground_truth.get('steps', [])

        # Completeness - all required steps present
        if expected_steps:
            pred_step_ids = set(s.get('id', s.get('tool_id', '')) for s in pred_steps)
            expected_step_ids = set(s.get('id', s.get('tool_id', '')) for s in expected_steps)
            intersection = pred_step_ids & expected_step_ids
            scores["completeness"] = len(intersection) / len(expected_step_ids)

        # Step ordering
        scores["step_ordering"] = self._score_ordering(pred_steps, expected_steps)

        # Data flow
        pred_connections = prediction.get('connections', [])
        expected_connections = ground_truth.get('connections', [])
        scores["data_flow"] = self._score_data_flow(
            pred_connections, expected_connections
        )

        # Structure correctness (overall)
        scores["structure_correctness"] = (
            scores["completeness"] * 0.4 +
            scores["step_ordering"] * 0.3 +
            scores["data_flow"] * 0.3
        )

        # Get weights from user context
        weights = None
        if self.user_context:
            criteria = self.user_context.get_evaluation_criteria(
                EvaluationTask.WET_EXPERIMENT  # Workflow maps to wet experiment
            )
            if criteria:
                weights = criteria.scoring_weights

        weighted_score = self._calculate_weighted_score(scores, weights)

        return EvaluationResult(
            evaluator_type=self.evaluator_type,
            task_type=task_type.value if task_type else "workflow_evaluation",
            scores=scores,
            weighted_score=weighted_score,
            details={
                "predicted_steps": len(pred_steps),
                "expected_steps": len(expected_steps),
                "missing_steps": list(
                    set(s.get('id', '') for s in expected_steps) -
                    set(s.get('id', '') for s in pred_steps)
                )
            }
        )

    def _score_ordering(self, pred_steps: List, expected_steps: List) -> float:
        """Score step ordering using longest common subsequence."""
        if not expected_steps:
            return 1.0 if not pred_steps else 0.5

        pred_ids = [s.get('id', s.get('tool_id', '')) for s in pred_steps]
        expected_ids = [s.get('id', s.get('tool_id', '')) for s in expected_steps]

        # Calculate LCS length
        lcs_length = self._lcs_length(pred_ids, expected_ids)
        return lcs_length / len(expected_ids)

    def _lcs_length(self, seq1: List, seq2: List) -> int:
        """Calculate length of longest common subsequence."""
        m, n = len(seq1), len(seq2)
        dp = [[0] * (n + 1) for _ in range(m + 1)]

        for i in range(1, m + 1):
            for j in range(1, n + 1):
                if seq1[i-1] == seq2[j-1]:
                    dp[i][j] = dp[i-1][j-1] + 1
                else:
                    dp[i][j] = max(dp[i-1][j], dp[i][j-1])

        return dp[m][n]

    def _score_data_flow(
        self,
        pred_connections: List,
        expected_connections: List
    ) -> float:
        """Score data flow correctness."""
        if not expected_connections:
            return 1.0

        if not pred_connections:
            return 0.0

        # Normalize connections to comparable format
        pred_set = set(self._normalize_connection(c) for c in pred_connections)
        expected_set = set(self._normalize_connection(c) for c in expected_connections)

        intersection = pred_set & expected_set
        return len(intersection) / len(expected_set)

    def _normalize_connection(self, conn: Any) -> tuple:
        """Normalize connection to comparable tuple."""
        if isinstance(conn, dict):
            return (conn.get('from', ''), conn.get('to', ''))
        elif isinstance(conn, (list, tuple)) and len(conn) >= 2:
            return (str(conn[0]), str(conn[1]))
        return (str(conn), '')


class ScientificEvaluator(BaseEvaluator):
    """
    Evaluates scientific correctness using SGI-Bench aligned criteria.

    Supports all SGI-Bench task types:
    - Deep Research (Deliberation)
    - Idea Generation (Conception)
    - Dry Experiment (Code)
    - Wet Experiment (Protocol)
    - Reasoning (Perception)
    """

    def __init__(
        self,
        user_context: UserBenchmarkContext = None,
        llm_evaluator: Callable[[str], str] = None
    ):
        """
        Initialize scientific evaluator.

        Args:
            user_context: User's benchmark context
            llm_evaluator: Optional LLM function for qualitative evaluation
        """
        super().__init__(user_context)
        self.llm_evaluator = llm_evaluator
        self.scorer = SGIScorer()

    def evaluate(
        self,
        prediction: Any,
        ground_truth: Any,
        task_type: EvaluationTask = None
    ) -> EvaluationResult:
        """
        Evaluate scientific correctness.

        Args:
            prediction: Model's response
            ground_truth: Expected answer from SGI-Bench
            task_type: Type of evaluation task

        Returns:
            EvaluationResult
        """
        if task_type is None:
            task_type = EvaluationTask.REASONING

        # Map EvaluationTask to SGITaskType
        task_mapping = {
            EvaluationTask.DEEP_RESEARCH: SGITaskType.DEEP_RESEARCH,
            EvaluationTask.IDEA_GENERATION: SGITaskType.IDEA_GENERATION,
            EvaluationTask.DRY_EXPERIMENT: SGITaskType.DRY_EXPERIMENT,
            EvaluationTask.WET_EXPERIMENT: SGITaskType.WET_EXPERIMENT,
            EvaluationTask.REASONING: SGITaskType.REASONING
        }

        sgi_task = task_mapping.get(task_type, SGITaskType.REASONING)

        # Use appropriate scorer
        if sgi_task == SGITaskType.DEEP_RESEARCH:
            scores = self.scorer.score_deep_research(prediction, ground_truth)
        elif sgi_task == SGITaskType.IDEA_GENERATION:
            scores = self.scorer.score_idea_generation(prediction, ground_truth)
        elif sgi_task == SGITaskType.DRY_EXPERIMENT:
            scores = self.scorer.score_dry_experiment(
                prediction if isinstance(prediction, str) else prediction.get('code', ''),
                ground_truth
            )
        elif sgi_task == SGITaskType.WET_EXPERIMENT:
            scores = self.scorer.score_wet_experiment(prediction, ground_truth)
        elif sgi_task == SGITaskType.REASONING:
            scores = self.scorer.score_reasoning(prediction, ground_truth)
        else:
            scores = {"accuracy": 0.0}

        # Get weights from user context or use defaults
        weights = None
        if self.user_context:
            criteria = self.user_context.get_evaluation_criteria(task_type)
            if criteria:
                weights = criteria.scoring_weights

        weighted_score = self._calculate_weighted_score(scores, weights)

        # Optional LLM-based qualitative evaluation
        llm_feedback = None
        if self.llm_evaluator and weighted_score < 0.8:
            llm_feedback = self._get_llm_feedback(prediction, ground_truth, task_type)

        return EvaluationResult(
            evaluator_type=self.evaluator_type,
            task_type=task_type.value,
            scores=scores,
            weighted_score=weighted_score,
            details={
                "sgi_task_type": sgi_task.value,
                "llm_feedback": llm_feedback
            }
        )

    def _get_llm_feedback(
        self,
        prediction: Any,
        ground_truth: Any,
        task_type: EvaluationTask
    ) -> Optional[str]:
        """Get LLM-based qualitative feedback."""
        if not self.llm_evaluator:
            return None

        try:
            prompt = f"""Evaluate the following scientific response:

Task Type: {task_type.value}

Prediction:
{json.dumps(prediction, indent=2) if isinstance(prediction, dict) else str(prediction)}

Expected:
{json.dumps(ground_truth, indent=2) if isinstance(ground_truth, dict) else str(ground_truth)}

Provide brief feedback on:
1. Scientific accuracy
2. Completeness
3. Key improvements needed

Feedback:"""
            return self.llm_evaluator(prompt)
        except Exception as e:
            log.warning(f"LLM evaluation failed: {e}")
            return None

    def evaluate_sgi_sample(
        self,
        prediction: Any,
        sample: SGISample
    ) -> EvaluationResult:
        """
        Evaluate against an SGI-Bench sample.

        Args:
            prediction: Model's response
            sample: SGI-Bench sample with ground truth

        Returns:
            EvaluationResult
        """
        # Map SGITaskType to EvaluationTask
        task_mapping = {
            SGITaskType.DEEP_RESEARCH: EvaluationTask.DEEP_RESEARCH,
            SGITaskType.IDEA_GENERATION: EvaluationTask.IDEA_GENERATION,
            SGITaskType.DRY_EXPERIMENT: EvaluationTask.DRY_EXPERIMENT,
            SGITaskType.WET_EXPERIMENT: EvaluationTask.WET_EXPERIMENT,
            SGITaskType.REASONING: EvaluationTask.REASONING
        }

        task_type = task_mapping.get(sample.task_type, EvaluationTask.REASONING)

        result = self.evaluate(prediction, sample.answer, task_type)
        result.details["sample_idx"] = sample.idx
        result.details["discipline"] = sample.discipline.value

        return result


class CompositeEvaluator:
    """
    Combines multiple evaluators for comprehensive evaluation.

    Runs Tool, Workflow, and Scientific evaluators and aggregates results.
    """

    def __init__(
        self,
        user_context: UserBenchmarkContext = None,
        llm_evaluator: Callable[[str], str] = None
    ):
        self.user_context = user_context
        self.tool_evaluator = ToolEvaluator(user_context)
        self.workflow_evaluator = WorkflowEvaluator(user_context)
        self.scientific_evaluator = ScientificEvaluator(user_context, llm_evaluator)

    def evaluate(
        self,
        prediction: Dict[str, Any],
        ground_truth: Dict[str, Any],
        include_tool: bool = True,
        include_workflow: bool = True,
        include_scientific: bool = True
    ) -> EvaluationReport:
        """
        Run comprehensive evaluation.

        Args:
            prediction: Dict containing tool, workflow, and/or scientific predictions
            ground_truth: Dict containing expected values
            include_tool: Include tool evaluation
            include_workflow: Include workflow evaluation
            include_scientific: Include scientific evaluation

        Returns:
            EvaluationReport with all results
        """
        results = []
        total_score = 0.0
        count = 0

        if include_tool and 'tool' in prediction:
            tool_result = self.tool_evaluator.evaluate(
                prediction.get('tool', {}),
                ground_truth.get('tool', {})
            )
            results.append(tool_result)
            total_score += tool_result.weighted_score
            count += 1

        if include_workflow and 'workflow' in prediction:
            workflow_result = self.workflow_evaluator.evaluate(
                prediction.get('workflow', {}),
                ground_truth.get('workflow', {})
            )
            results.append(workflow_result)
            total_score += workflow_result.weighted_score
            count += 1

        if include_scientific and 'scientific' in prediction:
            task_type = EvaluationTask(
                ground_truth.get('task_type', 'reasoning')
            )
            scientific_result = self.scientific_evaluator.evaluate(
                prediction.get('scientific', {}),
                ground_truth.get('scientific', {}),
                task_type
            )
            results.append(scientific_result)
            total_score += scientific_result.weighted_score
            count += 1

        overall_score = total_score / count if count > 0 else 0.0

        # Generate summary and recommendations
        summary = self._generate_summary(results, overall_score)
        recommendations = self._generate_recommendations(results)

        return EvaluationReport(
            user_id=self.user_context.user_id if self.user_context else "unknown",
            project_id=ground_truth.get('project_id', 'default'),
            dataset_id=ground_truth.get('dataset_id', 'default'),
            results=results,
            overall_score=overall_score,
            summary=summary,
            recommendations=recommendations
        )

    def _generate_summary(
        self,
        results: List[EvaluationResult],
        overall_score: float
    ) -> str:
        """Generate evaluation summary."""
        if not results:
            return "No evaluation results available."

        summary_parts = [
            f"Overall Score: {overall_score:.2%}",
            "",
            "Breakdown:"
        ]

        for result in results:
            summary_parts.append(
                f"  - {result.evaluator_type}: {result.weighted_score:.2%}"
            )
            for metric, score in result.scores.items():
                summary_parts.append(f"      {metric}: {score:.2%}")

        return "\n".join(summary_parts)

    def _generate_recommendations(
        self,
        results: List[EvaluationResult]
    ) -> List[str]:
        """Generate improvement recommendations."""
        recommendations = []

        for result in results:
            weak_metrics = [
                (metric, score) for metric, score in result.scores.items()
                if score < 0.7
            ]

            for metric, score in weak_metrics:
                if metric == "selection_accuracy":
                    recommendations.append(
                        "Consider reviewing tool selection criteria and available alternatives"
                    )
                elif metric == "parameter_correctness":
                    recommendations.append(
                        "Parameter configuration needs attention - check documentation"
                    )
                elif metric == "step_ordering":
                    recommendations.append(
                        "Review workflow step dependencies and ordering logic"
                    )
                elif metric == "scientific_correctness":
                    recommendations.append(
                        "Scientific reasoning needs improvement - consider literature review"
                    )
                elif "accuracy" in metric:
                    recommendations.append(
                        f"Improve {metric.replace('_', ' ')} through additional validation"
                    )

        # Deduplicate
        return list(dict.fromkeys(recommendations))


def run_sgi_bench_evaluation(
    samples: List[SGISample],
    model_runner: Callable[[str], str],
    user_context: UserBenchmarkContext = None
) -> Dict[str, Any]:
    """
    Run SGI-Bench evaluation on a set of samples.

    Args:
        samples: List of SGI-Bench samples to evaluate
        model_runner: Function that takes a prompt and returns model response
        user_context: Optional user context for personalized criteria

    Returns:
        Dict with evaluation results and statistics
    """
    evaluator = ScientificEvaluator(user_context)
    results = []

    for sample in samples:
        # Generate prompt
        prompt = SGIPromptTemplates.reasoning_prompt(
            sample.question,
            sample.metadata.get('options', [])
        )

        # Get model response
        try:
            start_time = time.time()
            response = model_runner(prompt)
            elapsed = time.time() - start_time

            # Parse response
            prediction = {"answer": response, "steps": []}

            # Evaluate
            result = evaluator.evaluate_sgi_sample(prediction, sample)
            result.details["response_time"] = elapsed

            results.append({
                "sample_idx": sample.idx,
                "task_type": sample.task_type.value,
                "discipline": sample.discipline.value,
                "result": result.to_dict()
            })

        except Exception as e:
            log.error(f"Evaluation failed for sample {sample.idx}: {e}")
            results.append({
                "sample_idx": sample.idx,
                "error": str(e)
            })

    # Calculate statistics
    successful = [r for r in results if "result" in r]
    avg_score = sum(
        r["result"]["weighted_score"] for r in successful
    ) / len(successful) if successful else 0.0

    # Group by task type
    by_task = {}
    for r in successful:
        task = r["task_type"]
        if task not in by_task:
            by_task[task] = []
        by_task[task].append(r["result"]["weighted_score"])

    task_averages = {
        task: sum(scores) / len(scores)
        for task, scores in by_task.items()
    }

    return {
        "total_samples": len(samples),
        "successful_evaluations": len(successful),
        "failed_evaluations": len(results) - len(successful),
        "average_score": avg_score,
        "scores_by_task_type": task_averages,
        "detailed_results": results
    }
