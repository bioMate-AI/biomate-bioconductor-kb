"""
CompBioBenchAdapter — evaluates BioMate against CompBioBench v1.

Source: Nair et al. (Genentech/Roche), bioRxiv 2026.04.06.716850
Leaderboard: https://huggingface.co/spaces/Genentech/compbiobench-leaderboard-v1

Submission format: TSV with columns question_id, answer
  - answers are scored server-side by the benchmark authors against a private key
  - scoring is exact string match (case-insensitive after stripping)

Prompt contract (matching the benchmark's own prompt template):
  - BioMate receives the question + resolved file paths
  - Must output "FINAL ANSWER:" followed by exactly one line with the answer
  - Any text after FINAL ANSWER is stripped

BioMate approach:
  - Leverages existing workflows + tools first (more reliable)
  - Falls back to generating custom Nextflow code for novel tasks
  - Uses ResearchAgent for API-based data retrieval (Ensembl, ClinVar, GTEx, etc.)
"""

from __future__ import annotations

import csv
import os
import re
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Optional

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult

_TSV_PATH = Path(__file__).parent.parent / "datasets" / "compbiobench" / "raw" / "compbiobench.v1.tsv"
_DATA_DIR = Path(__file__).parent.parent / "datasets" / "compbiobench" / "data"

# Prompt appended to every question — matches the benchmark's own format rules
_ANSWER_FORMAT_INSTRUCTION = """

IMPORTANT: This is a direct bioinformatics question requiring a specific answer.
DO NOT ask for file uploads. DO NOT launch a workflow. DO NOT ask for clarification.
Use your built-in knowledge, APIs (Ensembl, ClinVar, GTEx, 1000G, ENCODE, etc.),
and tools (ViennaRNA, bcftools, Biopython, gget, etc.) to compute the answer directly.

Steps:
1. Identify what data/computation is needed
2. Use the appropriate API or tool to get it
3. Compute the specific answer in the exact format the question requests

When you have the answer, end your response with EXACTLY:

FINAL ANSWER:
<your answer here>

RULES:
- 'FINAL ANSWER:' must appear verbatim, on its own line
- The answer goes on the next line, in the exact format the question specifies
- Nothing after the answer
- If you truly cannot compute the answer, write 'FINAL ANSWER:\nunable to compute'
"""


_BAD_ANSWER_PATTERNS = [
    "I processed your request using the available tools",
    "Confirm the intended analysis priority",
    "Open your [CRO Compliance workspace]",
    "upload the required inputs",
    "workflow generation failed",
    "What exact input files do you have",
]


def _parse_final_answer(response: str) -> str:
    """Extract answer after the last 'FINAL ANSWER:' marker.
    Returns empty string if no marker found — avoids using BioMate's
    generic workflow-routing messages as answers.
    """
    if not response:
        return ""
    if "FINAL ANSWER:" in response:
        after = response.split("FINAL ANSWER:")[-1].strip()
        first_line = after.split("\n")[0].strip()
        answer = first_line if first_line else after.strip()
        # Reject known non-answers
        if any(p in answer for p in _BAD_ANSWER_PATTERNS):
            return "ERROR: no specific answer"
        return answer
    # No FINAL ANSWER marker — BioMate didn't follow the format
    return ""


class CompBioBenchAdapter(BenchmarkAdapter):
    """Runs CompBioBench v1 tasks through BioMate and produces a submission TSV."""

    name = "compbiobench"

    def load_tasks(self) -> list[BenchmarkTask]:
        if not _TSV_PATH.exists():
            raise FileNotFoundError(f"CompBioBench TSV not found: {_TSV_PATH}")

        tasks = []
        with open(_TSV_PATH) as f:
            for row in csv.DictReader(f, delimiter="\t"):
                qid = row["question_id"]
                question = row["question"]
                file_paths_raw = (row.get("file_paths") or "").strip()
                domain = row.get("domain", "").lower().replace("-", "_").replace(" ", "_")

                # Resolve file paths to local data directory
                resolved_files: list[str] = []
                missing_files: list[str] = []
                if file_paths_raw:
                    for fname in re.split(r"[,;\s]+", file_paths_raw):
                        fname = fname.strip()
                        if not fname:
                            continue
                        local = _DATA_DIR / fname
                        if local.exists():
                            resolved_files.append(str(local))
                        else:
                            missing_files.append(fname)

                # Build prompt for BioMate — plain question, no routing hacks.
                # BioMate's own intent classifier should route direct bioinformatics
                # lookups/computations to research_question + run_code, not workflow_generation.
                prompt_parts = [f"QUESTION: {question}"]
                if resolved_files:
                    prompt_parts.append("\nINPUT FILES (available locally):")
                    for f in resolved_files:
                        prompt_parts.append(f"  {f}")
                if missing_files:
                    prompt_parts.append("\nNOTE: The following files were not found locally:")
                    for f in missing_files:
                        prompt_parts.append(f"  {f}")
                prompt_parts.append(_ANSWER_FORMAT_INSTRUCTION)
                prompt = "\n".join(prompt_parts)

                tasks.append(BenchmarkTask(
                    task_id=f"compbiobench__{qid}",
                    question=prompt,
                    ground_truth=None,  # private — scored via leaderboard submission
                    difficulty=str(row.get("difficulty", "hard")),
                    task_type="open_ended",
                    answer_type="text",
                    metadata={
                        "question_id": qid,
                        "domain": domain,
                        "benchmark": "compbiobench",
                        "skills_tested": row.get("skills_tested", ""),
                        "internet_required": row.get("internet_required", "").lower() == "true",
                        "gpu_preferred": row.get("gpu_preferred", "").lower() == "true",
                        "has_local_files": bool(resolved_files),
                        "needs_files": bool(file_paths_raw),  # True = task has files in TSV
                        "missing_files": missing_files,
                        "original_question": question,
                    },
                ))
        return tasks

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """Score is determined server-side — return 0.0 as placeholder."""
        return 0.0

    def run(self, client, max_tasks: Optional[int] = None) -> list[BenchmarkResult]:
        tasks = self.load_tasks()
        if max_tasks:
            tasks = tasks[:max_tasks]

        domain_counts: dict[str, int] = {}
        for t in tasks:
            d = t.metadata.get("domain", "?")
            domain_counts[d] = domain_counts.get(d, 0) + 1

        print(f"\n[CompBioBench] {len(tasks)} tasks")
        for d, n in sorted(domain_counts.items(), key=lambda x: -x[1]):
            print(f"  {d}: {n}")
        has_files = sum(1 for t in tasks if t.metadata.get("has_local_files"))
        print(f"  With local files: {has_files}/{len(tasks)}")
        print()

        max_workers = self.config.get("concurrency", {}).get("max_parallel_tasks", 2)
        results: list[BenchmarkResult] = []

        def _run_one(task: BenchmarkTask) -> BenchmarkResult:
            t0 = time.time()
            error: Optional[str] = None
            agent_response = ""
            extracted_answer = ""

            try:
                resp = client.ask(task.question)
                agent_response = (
                    resp.text if hasattr(resp, "text") and resp.text
                    else resp.message if hasattr(resp, "message")
                    else str(resp)
                )
                extracted_answer = _parse_final_answer(agent_response)
            except Exception as exc:
                error = str(exc)

            qid = task.metadata.get("question_id", task.task_id)
            domain = task.metadata.get("domain", "?")
            has_ans = "✓" if extracted_answer and not extracted_answer.startswith("ERROR") else "✗"
            print(
                f"  [{qid}] {domain:<22} {has_ans} "
                f"answer={extracted_answer[:60]!r} ({time.time()-t0:.0f}s)"
            )

            return BenchmarkResult(
                task_id=task.task_id,
                benchmark=self.name,
                score=0.0,  # scored externally
                agent_response=extracted_answer[:4000],
                ground_truth=task.ground_truth,
                latency_sec=time.time() - t0,
                metadata={**task.metadata, "raw_response_len": len(agent_response)},
                error=error,
            )

        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            futures = {pool.submit(_run_one, t): t for t in tasks}
            for future in as_completed(futures):
                results.append(future.result())

        return results

    def write_submission_tsv(self, results: list[BenchmarkResult], output_path: str) -> None:
        """Write submission TSV in CompBioBench leaderboard format."""
        with open(output_path, "w", newline="") as f:
            writer = csv.writer(f, delimiter="\t")
            writer.writerow(["question_id", "answer"])
            answered = 0
            for r in sorted(results, key=lambda x: x.task_id):
                qid = r.metadata.get("question_id", r.task_id.replace("compbiobench__", ""))
                answer = r.agent_response or ""
                writer.writerow([qid, answer])
                if answer and not answer.startswith("ERROR"):
                    answered += 1
        print(f"  Submission TSV: {output_path} ({answered}/{len(results)} answered)")
