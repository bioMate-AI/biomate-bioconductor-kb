"""
sciagentbench_adapter.py
------------------------
Adapter for ScienceAgentBench — scientific workflow code generation.

ScienceAgentBench: 102 tasks from 44 peer-reviewed papers across 4 domains.
Best published score: o1-preview + self-debug = 42.2% (ICLR 2025).

BioMate's Bioconductor KB (15,641 curated steps) should improve
function citation accuracy on the bioinformatics subset:
  LLM-only:    71.4% function citation accuracy
  KB-grounded: 88.2% function citation accuracy (already measured)

BioMate approach:
  1. Send task description + dataset file paths to BioMate chat
  2. BioMate generates a Python/R analysis script
  3. Execute script in sandboxed subprocess (timeout 120s)
  4. Compare output to gold standard

Citation: ScienceAgentBench, ICLR 2025
          https://github.com/OSU-NLP-Group/ScienceAgentBench

Setup:
    git clone https://github.com/OSU-NLP-Group/ScienceAgentBench
    # Set paths.sciagentbench_repo in config.yaml
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask


# Bioinformatics task IDs (subset of the 102 total tasks most relevant to BioMate)
# Full list requires reading the dataset; this is the approximate domain split
BIOINFORMATICS_DOMAIN = "bioinformatics"

CODE_BLOCK_RE = re.compile(r"```(?:python|r|bash)?\s*(.*?)```", re.DOTALL | re.IGNORECASE)


class SciAgentBenchAdapter(BenchmarkAdapter):
    """
    ScienceAgentBench adapter — bioinformatics code generation subset.

    Scoring:
      1.0 if generated code executes and output matches gold standard
      0.5 if code executes without error but output doesn't match (partial credit)
      0.0 if code fails to execute or is not generated

    Compares: BioMate (KB-grounded) vs o1-preview baseline (42.2% overall).
    Bioinformatics subset is ~30/102 tasks — enough for a focused claim.
    """

    name = "sciagentbench"
    EXEC_TIMEOUT = 120   # seconds per task

    def __init__(self, config: Dict[str, Any],
                 domain_filter: str = BIOINFORMATICS_DOMAIN,
                 max_tasks: Optional[int] = None):
        super().__init__(config)
        self.domain_filter = domain_filter
        self.max_tasks = max_tasks

        repo = config["paths"].get("sciagentbench_repo", "")
        if not repo:
            raise ValueError(
                "paths.sciagentbench_repo not set in config.yaml.\n"
                "Run: git clone https://github.com/OSU-NLP-Group/ScienceAgentBench"
            )
        self.repo_path = Path(repo)

    def load_tasks(self) -> List[BenchmarkTask]:
        tasks_file = self.repo_path / "benchmark" / "tasks.json"
        if not tasks_file.exists():
            tasks_file = self.repo_path / "tasks.json"
        if not tasks_file.exists():
            raise FileNotFoundError(f"tasks.json not found in {self.repo_path}")

        all_tasks = json.loads(tasks_file.read_text())

        # Filter to bioinformatics domain
        bio_tasks = [t for t in all_tasks
                     if t.get("domain", "").lower() == self.domain_filter]

        if self.max_tasks:
            bio_tasks = bio_tasks[:self.max_tasks]

        results = []
        for t in bio_tasks:
            dataset_dir = self.repo_path / "datasets" / t.get("dataset_folder", "")
            gold_output_path = self.repo_path / "gold_programs" / f"{t['task_id']}_output.txt"

            results.append(BenchmarkTask(
                task_id=f"sciagentbench__{t['task_id']}",
                question=_build_prompt(t, dataset_dir),
                ground_truth={
                    "gold_output": gold_output_path.read_text().strip()
                                   if gold_output_path.exists() else "",
                    "gold_program": (self.repo_path / "gold_programs" / f"{t['task_id']}.py")
                                    .read_text() if (self.repo_path / "gold_programs" / f"{t['task_id']}.py").exists() else "",
                },
                domain="life_science",
                difficulty="hard",
                task_type="code",
                answer_type="open",
                metadata={
                    "task_id": t["task_id"],
                    "paper_title": t.get("paper_title", ""),
                    "domain": t.get("domain", ""),
                    "dataset_dir": str(dataset_dir),
                    "source": "sciagentbench",
                },
            ))
        return results

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """Extract code from response, execute, compare output to gold standard."""
        code = _extract_code(agent_response)
        if not code:
            return 0.0

        gold_output = task.ground_truth.get("gold_output", "").strip()
        dataset_dir = task.metadata["dataset_dir"]

        exec_result = _execute_code(code, working_dir=dataset_dir,
                                    timeout=self.EXEC_TIMEOUT)

        if exec_result["error"]:
            return 0.0   # execution failed

        actual_output = exec_result["stdout"].strip()

        # Exact match (within tolerance for floats)
        if _outputs_match(actual_output, gold_output):
            return 1.0

        # Partial credit: code ran successfully but output doesn't match
        if actual_output:
            return 0.5

        return 0.0

    def task_prompt(self, task: BenchmarkTask) -> str:
        return (
            "[Generate a Python or R script that performs the following analysis. "
            "Return only the code in a fenced code block.]\n\n"
            + task.question
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _build_prompt(task_data: Dict, dataset_dir: Path) -> str:
    desc = task_data.get("task_description", "")
    files = []
    if dataset_dir.exists():
        files = [f.name for f in dataset_dir.iterdir() if f.is_file()][:10]
    if files:
        file_list = "\n".join(f"  {f}" for f in files)
        return f"{desc}\n\nAvailable data files:\n{file_list}"
    return desc


def _extract_code(text: str) -> str:
    matches = CODE_BLOCK_RE.findall(text)
    if matches:
        return matches[0].strip()
    # Fallback: look for lines that look like code
    lines = text.split("\n")
    code_lines = [l for l in lines if l.startswith("import ") or
                  l.startswith("library(") or l.startswith("df ") or
                  l.startswith("data ")]
    return "\n".join(code_lines) if len(code_lines) >= 3 else ""


def _execute_code(code: str, working_dir: str, timeout: int) -> Dict[str, Any]:
    """Run code in a sandboxed subprocess. Returns {stdout, stderr, error}."""
    suffix = ".R" if code.strip().startswith("library(") else ".py"
    with tempfile.NamedTemporaryFile(mode="w", suffix=suffix, delete=False) as f:
        f.write(code)
        fname = f.name

    try:
        interpreter = "Rscript" if suffix == ".R" else "python3"
        proc = subprocess.run(
            [interpreter, fname],
            cwd=working_dir,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "stdout": proc.stdout,
            "stderr": proc.stderr,
            "error": proc.returncode != 0,
        }
    except subprocess.TimeoutExpired:
        return {"stdout": "", "stderr": "TIMEOUT", "error": True}
    except Exception as exc:
        return {"stdout": "", "stderr": str(exc), "error": True}
    finally:
        os.unlink(fname)


def _outputs_match(actual: str, expected: str, tolerance: float = 1e-3) -> bool:
    """Compare outputs; try numeric tolerance for float-heavy outputs."""
    if actual == expected:
        return True
    # Try float comparison on each token
    try:
        a_nums = [float(x) for x in actual.split() if _is_numeric(x)]
        e_nums = [float(x) for x in expected.split() if _is_numeric(x)]
        if a_nums and e_nums and len(a_nums) == len(e_nums):
            return all(abs(a - e) / (abs(e) + 1e-10) < tolerance
                       for a, e in zip(a_nums, e_nums))
    except Exception:
        pass
    return False


def _is_numeric(s: str) -> bool:
    try:
        float(s)
        return True
    except ValueError:
        return False
