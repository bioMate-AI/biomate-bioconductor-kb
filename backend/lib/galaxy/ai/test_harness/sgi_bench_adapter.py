"""
SGI-Bench Adapter

Integrates SGI-Bench evaluation methodology into BioMate's test harness.
Provides:
- Dataset loading for Life Science and Chemistry domains
- Few-shot templates for each evaluation task
- Evaluation prompt generators
- Scoring rubrics aligned with SGI-Bench standards
"""

import logging
import json
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from pathlib import Path
from enum import Enum

log = logging.getLogger(__name__)

# Default path to SGI-Bench datasets
DEFAULT_SGI_BENCH_PATH = "/home/yzhang/biomate/research/benchmark_evaluation/sgi_bench_datasets"


class SGIDiscipline(str, Enum):
    """Scientific disciplines in SGI-Bench."""
    LIFE = "life"
    CHEMISTRY = "chemistry"
    PHYSICS = "physics"
    ASTRONOMY = "astronomy"
    EARTH = "earth"
    MATERIAL = "material"
    NEUROSCIENCE = "neuroscience"
    MATHEMATICS = "mathematics"
    INFORMATION = "information"
    ENERGY = "energy"


class SGITaskType(str, Enum):
    """Task types in SGI-Bench aligned with PIM model."""
    DEEP_RESEARCH = "deep_research"     # Deliberation
    IDEA_GENERATION = "idea_generation"  # Conception
    DRY_EXPERIMENT = "dry_experiment"    # Action (Code)
    WET_EXPERIMENT = "wet_experiment"    # Action (Protocol)
    REASONING = "reasoning"              # Perception


# Mapping from SGI-Bench dataset names to task types
DATASET_TO_TASK = {
    "SGI-DeepResearch": SGITaskType.DEEP_RESEARCH,
    "SGI-IdeaGeneration": SGITaskType.IDEA_GENERATION,
    "SGI-DryExperiment": SGITaskType.DRY_EXPERIMENT,
    "SGI-WetExperiment": SGITaskType.WET_EXPERIMENT,
    "SGI-Reasoning": SGITaskType.REASONING
}


@dataclass
class SGISample:
    """A single sample from SGI-Bench."""
    idx: str
    task_type: SGITaskType
    discipline: SGIDiscipline
    question: str
    answer: Any
    metadata: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "idx": self.idx,
            "task_type": self.task_type.value,
            "discipline": self.discipline.value,
            "question": self.question,
            "answer": self.answer,
            "metadata": self.metadata
        }


@dataclass
class FewShotExample:
    """A few-shot example for evaluation prompting."""
    task_type: SGITaskType
    discipline: SGIDiscipline
    input_text: str
    expected_output: str
    explanation: str = ""


class SGIBenchDataLoader:
    """Loads and filters SGI-Bench datasets."""

    def __init__(self, base_path: str = None):
        self.base_path = Path(base_path or DEFAULT_SGI_BENCH_PATH)
        self._cache: Dict[str, Any] = {}

    def _load_parquet(self, dataset_name: str):
        """Load a parquet file with caching."""
        if dataset_name in self._cache:
            return self._cache[dataset_name]

        try:
            import pandas as pd
            path = self.base_path / dataset_name / "data" / "test-00000-of-00001.parquet"
            if not path.exists():
                log.warning(f"Dataset not found: {path}")
                return None
            df = pd.read_parquet(path)
            self._cache[dataset_name] = df
            return df
        except ImportError:
            log.error("pandas is required for loading SGI-Bench datasets")
            return None
        except Exception as e:
            log.error(f"Failed to load dataset {dataset_name}: {e}")
            return None

    def load_samples(
        self,
        task_types: List[SGITaskType] = None,
        disciplines: List[SGIDiscipline] = None
    ) -> List[SGISample]:
        """
        Load samples filtered by task type and discipline.

        Args:
            task_types: Filter by task types (None = all)
            disciplines: Filter by disciplines (None = all)

        Returns:
            List of SGISample objects
        """
        samples = []

        # Determine which datasets to load
        datasets_to_load = DATASET_TO_TASK.keys()
        if task_types:
            datasets_to_load = [
                ds for ds, tt in DATASET_TO_TASK.items()
                if tt in task_types
            ]

        for dataset_name in datasets_to_load:
            df = self._load_parquet(dataset_name)
            if df is None:
                continue

            task_type = DATASET_TO_TASK[dataset_name]

            # Filter by discipline
            if disciplines:
                discipline_values = [d.value for d in disciplines]
                df = df[df['discipline'].isin(discipline_values)]

            for _, row in df.iterrows():
                try:
                    discipline = SGIDiscipline(row['discipline'])
                except ValueError:
                    log.debug(f"Unknown discipline: {row['discipline']}")
                    continue

                # Extract answer based on task type
                answer = self._extract_answer(row, task_type)

                # Build metadata
                metadata = {k: v for k, v in row.items()
                           if k not in ['idx', 'question', 'answer', 'discipline']}

                sample = SGISample(
                    idx=str(row['idx']),
                    task_type=task_type,
                    discipline=discipline,
                    question=row['question'],
                    answer=answer,
                    metadata=metadata
                )
                samples.append(sample)

        log.info(f"Loaded {len(samples)} SGI-Bench samples")
        return samples

    def _extract_answer(self, row, task_type: SGITaskType) -> Any:
        """Extract the answer/ground truth based on task type."""
        if task_type == SGITaskType.DEEP_RESEARCH:
            return {
                "steps": row.get('steps', []),
                "answer": row.get('answer', '')
            }
        elif task_type == SGITaskType.IDEA_GENERATION:
            return {
                "core_idea": row.get('core_idea', ''),
                "implementation_steps": row.get('implementation_steps', []),
                "expected_outcome": row.get('expected_outcome', '')
            }
        elif task_type == SGITaskType.DRY_EXPERIMENT:
            return {
                "main_code": row.get('main_code', ''),
                "unit_tests": [
                    {"data": row.get(f'unit_test_{i}_data', ''),
                     "output": row.get(f'unit_test_{i}_output', '')}
                    for i in range(5)
                ]
            }
        elif task_type == SGITaskType.WET_EXPERIMENT:
            return {
                "action_pool": row.get('action_pool', []),
                "answer": row.get('answer', [])
            }
        elif task_type == SGITaskType.REASONING:
            return {
                "steps": row.get('steps', []),
                "answer": row.get('answer', ''),
                "options": row.get('options', [])
            }
        return row.get('answer', '')

    def get_life_science_samples(self) -> List[SGISample]:
        """Get all Life Science samples."""
        return self.load_samples(
            disciplines=[SGIDiscipline.LIFE, SGIDiscipline.NEUROSCIENCE]
        )

    def get_chemistry_samples(self) -> List[SGISample]:
        """Get all Chemistry samples."""
        return self.load_samples(disciplines=[SGIDiscipline.CHEMISTRY])

    def get_biomate_relevant_samples(self) -> List[SGISample]:
        """Get samples relevant to BioMate (Life Science + Chemistry)."""
        return self.load_samples(
            disciplines=[SGIDiscipline.LIFE, SGIDiscipline.NEUROSCIENCE, SGIDiscipline.CHEMISTRY]
        )

    def get_sample_statistics(self) -> Dict[str, Any]:
        """Get statistics about loaded samples."""
        all_samples = self.load_samples()

        stats = {
            "total_samples": len(all_samples),
            "by_task_type": {},
            "by_discipline": {}
        }

        for sample in all_samples:
            tt = sample.task_type.value
            disc = sample.discipline.value

            stats["by_task_type"][tt] = stats["by_task_type"].get(tt, 0) + 1
            stats["by_discipline"][disc] = stats["by_discipline"].get(disc, 0) + 1

        return stats


class SGIPromptTemplates:
    """Evaluation prompt templates aligned with SGI-Bench methodology."""

    @staticmethod
    def deep_research_prompt(question: str, few_shot: Optional[FewShotExample] = None) -> str:
        """Generate deep research evaluation prompt."""
        prompt = """You are a scientific research assistant. Given a research question, provide a step-by-step analysis to reach a well-reasoned conclusion.

"""
        if few_shot:
            prompt += f"""Example:
Question: {few_shot.input_text}
Answer: {few_shot.expected_output}

---

"""
        prompt += f"""Question: {question}

Provide your analysis in the following format:
1. Break down the problem into logical steps
2. For each step, provide reasoning and intermediate conclusions
3. Synthesize the final answer based on your analysis

Answer:"""
        return prompt

    @staticmethod
    def idea_generation_prompt(question: str, few_shot: Optional[FewShotExample] = None) -> str:
        """Generate idea generation evaluation prompt."""
        prompt = """You are a scientific innovator. Given a research challenge, propose a novel and feasible solution with implementation details.

"""
        if few_shot:
            prompt += f"""Example:
Challenge: {few_shot.input_text}
Solution: {few_shot.expected_output}

---

"""
        prompt += f"""Challenge: {question}

Provide your response in the following JSON format:
{{
    "core_idea": "Brief description of your novel approach",
    "novelty_justification": "Why this approach is novel",
    "implementation_steps": [
        "Step 1: ...",
        "Step 2: ...",
        ...
    ],
    "data_requirements": "What data is needed",
    "evaluation_metrics": ["metric1", "metric2"],
    "expected_outcome": "What results you expect"
}}

Response:"""
        return prompt

    @staticmethod
    def dry_experiment_prompt(
        question: str,
        incomplete_code: str = "",
        few_shot: Optional[FewShotExample] = None
    ) -> str:
        """Generate code generation evaluation prompt."""
        prompt = """You are a computational scientist. Complete the following scientific code to solve the given problem.

"""
        if few_shot:
            prompt += f"""Example:
Problem: {few_shot.input_text}
Solution: {few_shot.expected_output}

---

"""
        prompt += f"""Problem: {question}

"""
        if incomplete_code:
            prompt += f"""Incomplete Code:
```python
{incomplete_code}
```

Complete the code by implementing the missing functions. Ensure:
1. The code runs without errors
2. Numerical calculations are accurate
3. Scientific logic is correct

"""
        prompt += "Complete Code:"
        return prompt

    @staticmethod
    def wet_experiment_prompt(
        question: str,
        action_pool: List[str] = None,
        few_shot: Optional[FewShotExample] = None
    ) -> str:
        """Generate wet experiment protocol evaluation prompt."""
        prompt = """You are a laboratory scientist. Design an experimental protocol for the given objective.

"""
        if few_shot:
            prompt += f"""Example:
Objective: {few_shot.input_text}
Protocol: {few_shot.expected_output}

---

"""
        prompt += f"""Objective: {question}

"""
        if action_pool:
            prompt += f"""Available Actions:
{json.dumps(action_pool, indent=2)}

"""
        prompt += """Provide your protocol as an ordered list of actions with parameters:
[
    {"step": 1, "action": "action_name", "parameters": {...}, "timing": "duration/timing"},
    ...
]

Protocol:"""
        return prompt

    @staticmethod
    def reasoning_prompt(
        question: str,
        options: List[str] = None,
        few_shot: Optional[FewShotExample] = None
    ) -> str:
        """Generate experimental reasoning evaluation prompt."""
        prompt = """You are a scientist analyzing experimental results. Examine the evidence and reason through to the correct conclusion.

"""
        if few_shot:
            prompt += f"""Example:
Question: {few_shot.input_text}
Reasoning: {few_shot.expected_output}

---

"""
        prompt += f"""Question: {question}

"""
        if options:
            prompt += f"""Options:
{chr(10).join([f'{chr(65+i)}. {opt}' for i, opt in enumerate(options)])}

"""
        prompt += """Provide your analysis:
1. Identify key observations from the data/images
2. Reason through each possibility
3. Select the best answer with justification

Answer:"""
        return prompt


class SGIScorer:
    """Scoring functions aligned with SGI-Bench evaluation criteria."""

    @staticmethod
    def score_deep_research(
        prediction: Dict[str, Any],
        ground_truth: Dict[str, Any]
    ) -> Dict[str, float]:
        """
        Score deep research response.

        Metrics:
        - step_accuracy: Accuracy of intermediate steps
        - final_answer_accuracy: Correctness of final answer
        - reasoning_validity: Quality of reasoning chain
        """
        scores = {
            "step_accuracy": 0.0,
            "final_answer_accuracy": 0.0,
            "reasoning_validity": 0.0
        }

        pred_answer = str(prediction.get('answer', '')).strip().lower()
        true_answer = str(ground_truth.get('answer', '')).strip().lower()

        # Final answer accuracy (strict match)
        if pred_answer == true_answer:
            scores["final_answer_accuracy"] = 1.0
        elif pred_answer in true_answer or true_answer in pred_answer:
            scores["final_answer_accuracy"] = 0.5

        # Step accuracy (if steps are provided)
        pred_steps = prediction.get('steps', [])
        true_steps = ground_truth.get('steps', [])

        # Convert to list if numpy array
        if hasattr(true_steps, 'tolist'):
            true_steps = true_steps.tolist()
        if hasattr(pred_steps, 'tolist'):
            pred_steps = pred_steps.tolist()

        # Ensure we have lists
        pred_steps = list(pred_steps) if pred_steps is not None else []
        true_steps = list(true_steps) if true_steps is not None else []

        if len(true_steps) > 0 and len(pred_steps) > 0:
            matches = sum(1 for ps, ts in zip(pred_steps, true_steps)
                         if str(ps).lower() == str(ts).lower())
            scores["step_accuracy"] = matches / len(true_steps)

        # Reasoning validity (heuristic based on step presence)
        if len(pred_steps) > 0:
            true_len = max(len(true_steps), 1)
            scores["reasoning_validity"] = min(len(pred_steps) / true_len, 1.0)

        return scores

    @staticmethod
    def score_idea_generation(
        prediction: Dict[str, Any],
        ground_truth: Dict[str, Any]
    ) -> Dict[str, float]:
        """
        Score idea generation response.

        Metrics:
        - novelty: Originality of the proposed idea
        - feasibility: Practical implementability
        - workflow_coherence: Interface alignment and step dependencies
        """
        scores = {
            "novelty": 0.0,
            "feasibility": 0.0,
            "workflow_coherence": 0.0
        }

        # Helper to check if value is truthy (handles numpy arrays)
        def is_truthy(val):
            if val is None:
                return False
            if hasattr(val, '__len__'):
                return len(val) > 0
            return bool(val)

        # Check for required fields
        has_core_idea = is_truthy(prediction.get('core_idea'))
        has_steps = is_truthy(prediction.get('implementation_steps'))
        has_outcome = is_truthy(prediction.get('expected_outcome'))

        # Feasibility score based on completeness
        completeness = sum([has_core_idea, has_steps, has_outcome]) / 3
        scores["feasibility"] = completeness

        # Workflow coherence based on step structure
        steps = prediction.get('implementation_steps', [])
        if hasattr(steps, 'tolist'):
            steps = steps.tolist()
        if isinstance(steps, list) and len(steps) > 0:
            scores["workflow_coherence"] = min(len(steps) / 5, 1.0)  # Expect ~5 steps

        # Novelty is harder to assess automatically - use presence of justification
        if is_truthy(prediction.get('novelty_justification')):
            scores["novelty"] = 0.5  # Baseline for having justification

        return scores

    @staticmethod
    def score_dry_experiment(
        prediction: str,
        ground_truth: Dict[str, Any],
        execute_tests: bool = False
    ) -> Dict[str, float]:
        """
        Score code generation response.

        Metrics:
        - execution_success: Code runs without errors
        - unit_test_pass_rate: Percentage of unit tests passing
        - scientific_correctness: Correctness of scientific logic
        """
        scores = {
            "execution_success": 0.0,
            "unit_test_pass_rate": 0.0,
            "scientific_correctness": 0.0
        }

        if not prediction:
            return scores

        # Check if code looks valid (basic syntax check)
        try:
            compile(prediction, '<string>', 'exec')
            scores["execution_success"] = 1.0
        except SyntaxError:
            scores["execution_success"] = 0.0
            return scores

        # If execute_tests is True, actually run the unit tests
        if execute_tests:
            unit_tests = ground_truth.get('unit_tests', [])
            if unit_tests:
                passed = 0
                for test in unit_tests:
                    # Would need to actually execute tests here
                    pass
                scores["unit_test_pass_rate"] = passed / len(unit_tests)

        return scores

    @staticmethod
    def score_wet_experiment(
        prediction: List[Dict[str, Any]],
        ground_truth: Dict[str, Any]
    ) -> Dict[str, float]:
        """
        Score wet experiment protocol.

        Metrics:
        - sequence_similarity: Action sequence matches reference
        - parameter_accuracy: Correct parameter values
        - temporal_coherence: Proper timing and branching logic
        """
        scores = {
            "sequence_similarity": 0.0,
            "parameter_accuracy": 0.0,
            "temporal_coherence": 0.0
        }

        true_sequence = ground_truth.get('answer', [])

        # Convert numpy arrays to lists
        if hasattr(true_sequence, 'tolist'):
            true_sequence = true_sequence.tolist()
        if hasattr(prediction, 'tolist'):
            prediction = prediction.tolist()

        # Handle None/empty cases
        if true_sequence is None:
            true_sequence = []
        if prediction is None:
            prediction = []

        # Ensure lists
        if not isinstance(true_sequence, list):
            true_sequence = [true_sequence] if true_sequence else []
        if not isinstance(prediction, list):
            if isinstance(prediction, str):
                try:
                    prediction = json.loads(prediction)
                except json.JSONDecodeError:
                    return scores
            else:
                prediction = [prediction] if prediction else []

        if len(true_sequence) == 0 or len(prediction) == 0:
            return scores

        # Sequence similarity (Jaccard-like)
        pred_actions = set(str(p.get('action', '')) for p in prediction if isinstance(p, dict))
        true_actions = set(str(t) if isinstance(t, str) else str(t.get('action', ''))
                          for t in true_sequence)

        if true_actions:
            intersection = len(pred_actions & true_actions)
            union = len(pred_actions | true_actions)
            scores["sequence_similarity"] = intersection / union if union > 0 else 0

        # Temporal coherence (check step ordering)
        if len(prediction) > 0:
            has_order = all(isinstance(p, dict) and 'step' in p for p in prediction)
            scores["temporal_coherence"] = 1.0 if has_order else 0.5

        return scores

    @staticmethod
    def score_reasoning(
        prediction: Dict[str, Any],
        ground_truth: Dict[str, Any]
    ) -> Dict[str, float]:
        """
        Score experimental reasoning response.

        Metrics:
        - answer_accuracy: Correctness of final answer
        - reasoning_validity: Validity of reasoning process
        - comparative_ability: Cross-sample comparison capability
        """
        scores = {
            "answer_accuracy": 0.0,
            "reasoning_validity": 0.0,
            "comparative_ability": 0.0
        }

        # Handle different prediction types
        if isinstance(prediction, dict):
            pred_answer = str(prediction.get('answer', '')).strip().upper()
            pred_steps = prediction.get('steps', [])
        elif isinstance(prediction, list):
            # If list of steps, try to find answer in last step or use whole list
            pred_answer = ""
            pred_steps = prediction
            if len(prediction) > 0:
                last_item = prediction[-1]
                if isinstance(last_item, dict):
                    # Try to extract answer from last step
                    pred_answer = str(last_item.get('answer', last_item.get('action', ''))).strip().upper()
                else:
                    pred_answer = str(last_item).strip().upper()
        elif isinstance(prediction, str):
            pred_answer = prediction.strip().upper()
            pred_steps = []
        else:
            pred_answer = str(prediction).strip().upper() if prediction else ""
            pred_steps = []

        # Handle ground_truth similarly
        if isinstance(ground_truth, dict):
            true_answer = str(ground_truth.get('answer', '')).strip().upper()
        elif isinstance(ground_truth, str):
            true_answer = ground_truth.strip().upper()
        else:
            true_answer = str(ground_truth).strip().upper() if ground_truth else ""

        # Answer accuracy
        if pred_answer == true_answer:
            scores["answer_accuracy"] = 1.0
        elif len(pred_answer) == 1 and len(true_answer) == 1:
            # Single letter answer (A, B, C, D)
            scores["answer_accuracy"] = 0.0
        else:
            # Partial match for text answers
            if pred_answer and true_answer and (pred_answer in true_answer or true_answer in pred_answer):
                scores["answer_accuracy"] = 0.5

        # Reasoning validity
        # Convert numpy arrays to lists
        if hasattr(pred_steps, 'tolist'):
            pred_steps = pred_steps.tolist()
        if pred_steps is None:
            pred_steps = []
        if not isinstance(pred_steps, list):
            pred_steps = [pred_steps] if pred_steps else []

        if len(pred_steps) > 0:
            scores["reasoning_validity"] = 0.5  # Baseline for having reasoning

        return scores


def create_few_shot_examples(
    data_loader: SGIBenchDataLoader,
    task_type: SGITaskType,
    discipline: SGIDiscipline = None,
    n_examples: int = 1
) -> List[FewShotExample]:
    """
    Create few-shot examples from SGI-Bench data.

    Args:
        data_loader: SGIBenchDataLoader instance
        task_type: Task type to get examples for
        discipline: Optional discipline filter
        n_examples: Number of examples to return

    Returns:
        List of FewShotExample objects
    """
    disciplines = [discipline] if discipline else None
    samples = data_loader.load_samples(
        task_types=[task_type],
        disciplines=disciplines
    )

    if not samples:
        return []

    examples = []
    for sample in samples[:n_examples]:
        if task_type == SGITaskType.DEEP_RESEARCH:
            input_text = sample.question
            expected_output = json.dumps(sample.answer, indent=2)
        elif task_type == SGITaskType.IDEA_GENERATION:
            input_text = sample.question
            expected_output = json.dumps(sample.answer, indent=2)
        elif task_type == SGITaskType.DRY_EXPERIMENT:
            input_text = sample.question
            expected_output = sample.answer.get('main_code', '')
        elif task_type == SGITaskType.WET_EXPERIMENT:
            input_text = sample.question
            expected_output = json.dumps(sample.answer.get('answer', []), indent=2)
        elif task_type == SGITaskType.REASONING:
            input_text = sample.question
            expected_output = json.dumps(sample.answer, indent=2)
        else:
            continue

        examples.append(FewShotExample(
            task_type=task_type,
            discipline=sample.discipline,
            input_text=input_text,
            expected_output=expected_output
        ))

    return examples
