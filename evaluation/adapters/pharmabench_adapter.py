"""
pharmabench_adapter.py
----------------------
Adapter for PharmaBench — ADMET property prediction orchestration.

PharmaBench: 11 ADMET datasets, 52,482 entries (Scientific Data/Nature, 2024).
Used by Mozi (March 2026) and DrugAgent (PAMPA F1=0.92).

BioMate's evaluation framing:
  NOT testing ML model accuracy (that's a fixed dataset ML benchmark).
  Testing whether BioMate correctly:
    1. Selects the right ADMET workflow for the property type
    2. Routes to the correct prediction tool (ADMET-ML, RDKit, ChEMBL lookup)
    3. Interprets the output and classifies the compound correctly
    4. Reports confidence and evidence source

Benchmark tasks: given a SMILES + property type → expected classification.
BioMate must identify the property type, select the correct sub-workflow,
and return the correct prediction.

Citation: Zhu W et al. "PharmaBench." Scientific Data. 2024.
          doi:10.1038/s41597-024-03793-0
          https://github.com/mindrank-ai/PharmaBench

Setup:
    git clone https://github.com/mindrank-ai/PharmaBench
    # Set paths.pharmabench_repo in config.yaml
"""

from __future__ import annotations

import json
import random
from pathlib import Path
from typing import Any, Dict, List, Optional

import yaml

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask
from ..core.llm_judge import LLMJudge


# PharmaBench dataset names and their prediction task type
PHARMABENCH_DATASETS = {
    "Caco2":         {"type": "regression",     "unit": "log Papp (cm/s)", "property": "intestinal_absorption"},
    "PAMPA":         {"type": "classification", "class_pos": "permeable",  "property": "membrane_permeability"},
    "Bioavailability": {"type": "classification", "class_pos": "bioavailable", "property": "oral_bioavailability"},
    "PPB":           {"type": "regression",     "unit": "% bound",         "property": "plasma_protein_binding"},
    "VD":            {"type": "regression",     "unit": "L/kg",            "property": "volume_of_distribution"},
    "CYP1A2":        {"type": "classification", "class_pos": "inhibitor",  "property": "cyp1a2_inhibition"},
    "CYP2C9":        {"type": "classification", "class_pos": "inhibitor",  "property": "cyp2c9_inhibition"},
    "CYP2C19":       {"type": "classification", "class_pos": "inhibitor",  "property": "cyp2c19_inhibition"},
    "CYP2D6":        {"type": "classification", "class_pos": "inhibitor",  "property": "cyp2d6_inhibition"},
    "hERG":          {"type": "classification", "class_pos": "blocker",    "property": "herg_cardiotoxicity"},
    "DILI":          {"type": "classification", "class_pos": "toxic",      "property": "drug_induced_liver_injury"},
}

# How many test-set samples to evaluate per dataset (keep small for cost)
SAMPLES_PER_DATASET = 20


class PharmaBenchAdapter(BenchmarkAdapter):
    """
    PharmaBench adapter — ADMET workflow selection + prediction accuracy.

    For each SMILES + property type, BioMate must:
      1. Identify the property type from the question
      2. Select and run the correct ADMET sub-workflow
      3. Return a prediction matching the ground truth

    Scoring:
      correct_prediction: 1.0 if prediction matches ground truth (classification)
                          or within 20% relative error (regression)
      workflow_selected:  0.3 bonus if BioMate names the correct tool/approach
      total max:          1.0 (capped)
    """

    name = "pharmabench"

    def __init__(self, config: Dict[str, Any],
                 datasets: Optional[List[str]] = None,
                 samples_per_dataset: int = SAMPLES_PER_DATASET):
        super().__init__(config)
        self.target_datasets = datasets or list(PHARMABENCH_DATASETS.keys())
        self.samples_per_dataset = samples_per_dataset

        repo = config["paths"].get("pharmabench_repo", "")
        if not repo:
            raise ValueError(
                "paths.pharmabench_repo not set in config.yaml.\n"
                "Run: git clone https://github.com/mindrank-ai/PharmaBench"
            )
        self.repo_path = Path(repo)
        self._judge: Optional[LLMJudge] = None

    def prepare(self, client) -> None:
        self._judge = LLMJudge(model=self.config["llm_judge"]["model"], api_key=self.config.get("llm_judge",{}).get("api_key"))

    def load_tasks(self) -> List[BenchmarkTask]:
        tasks = []
        for dataset_name in self.target_datasets:
            meta = PHARMABENCH_DATASETS.get(dataset_name)
            if not meta:
                continue

            # Try to load test split CSV
            test_file = self._find_test_file(dataset_name)
            if not test_file:
                continue

            samples = self._load_samples(test_file, dataset_name, meta)
            tasks.extend(samples[:self.samples_per_dataset])

        return tasks

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        meta = task.metadata
        pred_type = meta["prediction_type"]
        ground_truth = task.ground_truth

        response_lower = agent_response.lower()

        # Score prediction accuracy
        if pred_type == "classification":
            pos_label = meta["class_pos"].lower()
            neg_label = "not " + pos_label

            if pos_label in response_lower and ground_truth == 1:
                pred_correct = 1.0
            elif (neg_label in response_lower or
                  any(w in response_lower for w in ["non-", "inactive", "negative", "not likely"])) \
                 and ground_truth == 0:
                pred_correct = 1.0
            else:
                pred_correct = 0.0
        else:
            # Regression: look for a numeric value in response
            import re
            nums = re.findall(r"-?\d+\.?\d*(?:[eE][+-]?\d+)?", agent_response)
            if nums:
                try:
                    predicted = float(nums[0])
                    expected = float(ground_truth)
                    rel_error = abs(predicted - expected) / (abs(expected) + 1e-10)
                    pred_correct = 1.0 if rel_error < 0.20 else 0.0
                except Exception:
                    pred_correct = 0.0
            else:
                pred_correct = 0.0

        # Bonus: correct workflow/tool named
        expected_tool = meta.get("expected_tool_keywords", [])
        tool_bonus = 0.0
        if expected_tool and any(kw in response_lower for kw in expected_tool):
            tool_bonus = 0.3

        return min(1.0, pred_correct + (tool_bonus if pred_correct > 0 else 0))

    def task_prompt(self, task: BenchmarkTask) -> str:
        prop = task.metadata["property_name"]
        return (
            f"Predict the {prop} for the following compound using BioMate's "
            f"ADMET prediction tools. Return the prediction clearly.\n\n"
            + task.question
        )

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _find_test_file(self, dataset_name: str) -> Optional[Path]:
        """Search common PharmaBench directory layouts for the test CSV."""
        candidates = [
            self.repo_path / "data" / dataset_name / "test.csv",
            self.repo_path / "datasets" / dataset_name / "test.csv",
            self.repo_path / f"{dataset_name}_test.csv",
            self.repo_path / "processed" / f"{dataset_name}_test.csv",
        ]
        for c in candidates:
            if c.exists():
                return c
        return None

    def _load_samples(self, csv_path: Path, dataset_name: str,
                      meta: Dict) -> List[BenchmarkTask]:
        import csv
        samples = []
        with open(csv_path) as f:
            reader = csv.DictReader(f)
            rows = list(reader)

        # Random sample (seed fixed for reproducibility)
        rng = random.Random(42)
        rows = rng.sample(rows, min(self.samples_per_dataset * 3, len(rows)))

        for i, row in enumerate(rows):
            smiles = row.get("smiles") or row.get("SMILES") or row.get("Smiles", "")
            label = row.get("label") or row.get("Label") or row.get("y", "")
            if not smiles or label == "":
                continue

            prop_name = meta["property"].replace("_", " ")
            if meta["type"] == "classification":
                question = (
                    f"Compound SMILES: {smiles}\n\n"
                    f"Is this compound a {meta['class_pos']} for {prop_name}? "
                    f"Answer with yes/no and a brief explanation."
                )
            else:
                question = (
                    f"Compound SMILES: {smiles}\n\n"
                    f"Predict the {prop_name} value for this compound. "
                    f"Report the numeric value with units ({meta['unit']})."
                )

            samples.append(BenchmarkTask(
                task_id=f"pharmabench__{dataset_name}__{i}",
                question=question,
                ground_truth=int(label) if meta["type"] == "classification" else float(label),
                domain="drug_discovery",
                difficulty="medium",
                task_type="reasoning",
                answer_type="open",
                metadata={
                    "dataset": dataset_name,
                    "prediction_type": meta["type"],
                    "property_name": prop_name,
                    "class_pos": meta.get("class_pos", ""),
                    "unit": meta.get("unit", ""),
                    "smiles": smiles,
                    "expected_tool_keywords": ["admet", "rdkit", "chembl", "swissadme", "pkcsm"],
                    "source": "pharmabench",
                },
            ))
            if len(samples) >= self.samples_per_dataset:
                break

        return samples
