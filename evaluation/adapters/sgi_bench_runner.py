"""
sgi_bench_runner.py
-------------------
Runs the full SGI-Bench life-science evaluation against the live BioMate API.

The SGI-Bench adapter and datasets already exist at:
  backend/lib/galaxy/ai/test_harness/sgi_bench_adapter.py
  research/benchmark_evaluation/sgi_bench_datasets/

This runner wires them to BioMateEvalClient so real LLM responses
replace the mock responses used in the validation run.

Status: 503 life-science samples loaded; validation passed (Dec 2025).
Gap filled here: calls real BioMate API instead of returning mock scores.

Citation: SGI-Bench — "Probing Scientific General Intelligence of LLMs"
          PDF at research/benchmark_evaluation/Probing Scientific General Intelligence of LLMs.pdf
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Dict, List

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask
from ..core.llm_judge import LLMJudge


class SGIBenchRunner(BenchmarkAdapter):
    """
    Full SGI-Bench life-science run via the existing sgi_bench_adapter.

    Covers 503 samples across 5 task types:
      deep_research, idea_generation, dry_experiment, wet_experiment, reasoning

    Scoring rubrics per task type (from sgi_bench_adapter.py):
      Deep Research:    step_accuracy, final_answer_accuracy, reasoning_validity
      Idea Generation:  novelty, feasibility, workflow_coherence
      Dry Experiment:   execution_success, unit_test_pass_rate, scientific_correctness
      Wet Experiment:   sequence_similarity, parameter_accuracy, temporal_coherence
      Reasoning:        answer_accuracy, reasoning_validity, comparative_ability
    """

    name = "sgi_bench_life"

    def __init__(self, config: Dict[str, Any], max_samples: int = 503):
        super().__init__(config)
        self.max_samples = max_samples

        harness_path = config["paths"].get(
            "sgi_bench_adapter",
            "/home/yzhang/biomate/backend/lib/galaxy/ai/test_harness",
        )
        # Add backend/lib to path so we can import galaxy.ai.test_harness
        backend_lib = str(Path(harness_path).parent.parent.parent.parent / "lib")
        if backend_lib not in sys.path:
            sys.path.insert(0, backend_lib)

        self._loader = None
        self._judge = None

    def prepare(self, client) -> None:
        from galaxy.ai.test_harness.sgi_bench_adapter import SGIBenchDataLoader
        datasets_path = self.config["paths"]["sgi_bench_datasets"]
        self._loader = SGIBenchDataLoader(datasets_path)
        self._judge = LLMJudge(model=self.config["llm_judge"]["model"], api_key=self.config.get("llm_judge",{}).get("api_key"))

    def load_tasks(self) -> List[BenchmarkTask]:
        if self._loader is None:
            self.prepare(None)

        from galaxy.ai.test_harness.sgi_bench_adapter import SGIDiscipline
        all_samples = self._loader.load_samples(
            disciplines=[SGIDiscipline.LIFE],
        )
        samples = all_samples[:self.max_samples] if self.max_samples else all_samples

        import numpy as np

        def _to_json_safe(obj):
            """Recursively convert numpy arrays/scalars to Python types for JSON serialization."""
            if isinstance(obj, dict):
                return {k: _to_json_safe(v) for k, v in obj.items()}
            if isinstance(obj, (list, tuple)):
                return [_to_json_safe(v) for v in obj]
            if isinstance(obj, np.ndarray):
                return obj.tolist()
            if isinstance(obj, (np.integer,)):
                return int(obj)
            if isinstance(obj, (np.floating,)):
                return float(obj)
            return obj

        tasks = []
        for sample in samples:
            tasks.append(BenchmarkTask(
                task_id=f"sgi_bench_life__{sample.idx}",
                question=sample.question,
                ground_truth=_to_json_safe(sample.answer),
                domain="life_science",
                difficulty="hard",
                task_type=sample.task_type.value,
                answer_type="open",
                metadata={
                    "sgi_idx": sample.idx,
                    "task_type": sample.task_type.value,
                    "discipline": sample.discipline.value,
                    "source": "sgi_bench",
                },
            ))
        return tasks

    def task_prompt(self, task: BenchmarkTask) -> str:
        """
        Frame question as a direct knowledge question to prevent BioMate
        from routing to tool/workflow mode.

        Uses strong explicit DO-NOT rules (same pattern as BixBench/BiomniEval1)
        to prevent the assistant from entering workflow-routing mode on knowledge
        questions. All format compliance is handled here in the adapter layer.
        """
        task_type = task.metadata.get("task_type", "reasoning")

        type_instruction = {
            "deep_research": (
                "Answer directly from your knowledge of published biomedical research.\n"
                "If the question requires a numerical calculation, perform the calculation yourself — step by step.\n"
                "DO NOT say you need a tool to compute numbers.\n"
                "Give a concise, factual answer with your reasoning."
            ),
            "reasoning": (
                "Apply your scientific domain expertise to reason through this question.\n"
                "If the question requires a calculation or numerical step, perform it directly.\n"
                "DO NOT say tools are needed for arithmetic or domain-specific calculations.\n"
                "Give a direct, structured answer showing your reasoning."
            ),
            "idea_generation": (
                "IMPORTANT: The context describes related works leading up to a SPECIFIC published paper.\n"
                "Your task is to IDENTIFY and DESCRIBE that specific paper's core contribution.\n"
                "DO NOT generate an entirely new idea — infer and recall the real published breakthrough\n"
                "that logically follows from the related work citations provided.\n"
                "Describe: (1) the core method/architecture, (2) the key technical innovations,\n"
                "(3) the performance/results achieved. Be specific and precise."
            ),
            "dry_experiment": (
                "Describe what the experiment would produce or what the expected result is.\n"
                "Answer from your knowledge of established protocols."
            ),
            "wet_experiment": (
                "Describe the experimental parameters, expected sequences, or protocol steps.\n"
                "Answer from your knowledge of the method."
            ),
        }.get(task_type, "Answer the question directly and concisely.")

        return (
            "LIFE SCIENCE KNOWLEDGE EVALUATION\n"
            "===================================\n"
            "This is a direct scientific knowledge question. You MUST answer it.\n"
            "Rules:\n"
            "- DO NOT ask for data files, FASTQ files, or uploaded datasets\n"
            "- DO NOT suggest running a bioinformatics workflow or pipeline\n"
            "- DO NOT say you need experimental data to answer\n"
            "- DO NOT offer to set up a workflow instead of answering\n"
            "- DO answer directly from your training knowledge\n"
            f"- Task type: {task_type.replace('_', ' ').title()} — {type_instruction}\n\n"
            + task.question
        )

    @staticmethod
    def _extract_substantive_answer(response: str) -> str:
        """
        Strip BioMate workflow-detection preamble from a response.

        When BioMate's router enters workflow mode before recognising a
        knowledge question, the response looks like:
            "**Understood from your message**\n• Input: ...\n\n
             **Running:** workflow\n...\n\n**Missing: ...**\n\n[REAL ANSWER]"

        We strip everything up to (and including) the last "**Missing:**…"
        block so the LLM judge only sees the substantive scientific content.
        """
        import re
        # Common preamble markers emitted by BioMate's workflow detector
        markers = [
            r"\*\*Missing:[^\n]*\n",          # **Missing: ...\n
            r"\*\*Running:\*\* workflow[^\n]*\n",
            r"\*\*Understood from your message\*\*[^\n]*\n",
        ]
        cleaned = response
        # Find the last occurrence of any marker and take everything after it
        last_end = 0
        for marker in markers:
            for m in re.finditer(marker, cleaned, re.IGNORECASE):
                if m.end() > last_end:
                    last_end = m.end()
        if last_end > 0:
            cleaned = cleaned[last_end:].lstrip("\n•- ")
        return cleaned.strip() or response  # fallback to full response if nothing stripped

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Score using LLM judge (Haiku).
        SGIScorer requires structured dict predictions incompatible with BioMate
        free-text responses, so we use an LLM judge for all task types.
        Strips workflow-detection preamble before judging so the real answer
        is evaluated rather than the routing noise.
        """
        if self._judge is None:
            self._judge = LLMJudge(model=self.config["llm_judge"]["model"], api_key=self.config.get("llm_judge",{}).get("api_key"))

        gt = task.ground_truth
        gt_text = str(gt.get("answer", gt)) if isinstance(gt, dict) else str(gt)

        # Extract the substantive answer, stripping any workflow-mode preamble
        clean_response = self._extract_substantive_answer(agent_response)

        return self._judge.binary_score(
            question=task.question,
            ground_truth=gt_text,
            agent_answer=clean_response,
        )
