"""
bixbench_adapter.py
-------------------
Adapter for BixBench v1.5 (205 questions, futurehouse/bixbench on HuggingFace).

BixBench tests agents on real-world computational biology scenarios.
Published baselines (MCQ mode):
  GPT-4o:            ~40%
  Claude 3.5 Sonnet: ~45%
  Biomni (exec mode): 52.2%

Two evaluation modes:
  hf_mcq (default): Load from HuggingFace; present question + 4 MCQ choices;
    BioMate uses scientific reasoning to select. No code execution needed.
    Scores scientific literacy and domain reasoning.
    Random baseline: 25%.

  local_exec: Requires CodeOcean capsule data + local repo.
    Presents question + data files; BioMate launches Nextflow workflow to compute.
    Scores execution accuracy. Requires paths.bixbench_repo in config.yaml.

Citation: arXiv:2503.00096 (FutureHouse, Feb 2025)
          Dataset: huggingface.co/datasets/futurehouse/bixbench
"""

from __future__ import annotations

import json
import random
import re
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask
from ..core.llm_judge import LLMJudge


# MCQ letter extraction
_LETTER_RE = re.compile(r"\b([A-D])\b")

EVAL_MODES = ("hf_mcq", "local_exec", "biomate_exec")


class BixBenchAdapter(BenchmarkAdapter):
    """
    BixBench benchmark adapter — HuggingFace MCQ mode by default.

    Loads 205 questions from futurehouse/bixbench; formats as 4-choice MCQ
    (ideal + 3 distractors shuffled into A/B/C/D). BioMate answers using
    scientific reasoning. Scored as exact letter match.
    """

    name = "bixbench"

    def __init__(self, config: Dict[str, Any],
                 mode: str = "hf_mcq",
                 max_tasks: Optional[int] = None,
                 category_filter: Optional[str] = None,
                 seed: int = 42):
        super().__init__(config)
        if mode not in EVAL_MODES:
            raise ValueError(f"mode must be one of {EVAL_MODES}")
        self.mode = mode
        self.max_tasks = max_tasks
        self.category_filter = category_filter
        self.seed = seed
        self._judge: Optional[LLMJudge] = None
        self._rng = random.Random(seed)

    def prepare(self, client) -> None:
        self._judge = LLMJudge(model=self.config["llm_judge"]["model"], api_key=self.config.get("llm_judge",{}).get("api_key"))

    def load_tasks(self) -> List[BenchmarkTask]:
        if self.mode == "hf_mcq":
            return self._load_hf_mcq_tasks()
        return self._load_local_exec_tasks()

    def _load_hf_mcq_tasks(self) -> List[BenchmarkTask]:
        from datasets import load_dataset
        ds = load_dataset("futurehouse/bixbench")["train"]

        tasks: List[BenchmarkTask] = []
        for ex in ds:
            if self.category_filter:
                cats = ex.get("categories", "")
                if self.category_filter.lower() not in cats.lower():
                    continue

            # Build MCQ: shuffle ideal + distractors into A/B/C/D
            ideal = str(ex["ideal"]).strip()
            distractors_raw = ex.get("distractors", "[]")
            if isinstance(distractors_raw, str):
                try:
                    distractors = json.loads(distractors_raw.replace("'", '"'))
                except Exception:
                    distractors = []
            else:
                distractors = list(distractors_raw)
            distractors = [str(d).strip() for d in distractors[:3]]

            # Ensure exactly 4 choices
            choices_vals = [ideal] + distractors
            while len(choices_vals) < 4:
                choices_vals.append("(unknown)")
            choices_vals = choices_vals[:4]

            shuffled = choices_vals[:]
            self._rng.shuffle(shuffled)
            letters = ["A", "B", "C", "D"]
            correct_letter = letters[shuffled.index(ideal)]

            choices_text = "\n".join(
                f"  {letters[i]}) {shuffled[i]}" for i in range(4)
            )
            full_question = (
                f"{ex['question'].strip()}\n\n"
                f"Choices:\n{choices_text}"
            )

            tasks.append(BenchmarkTask(
                task_id=f"bixbench__{ex['short_id']}__{ex['question_id']}",
                question=full_question,
                ground_truth=correct_letter,
                domain="life_science",
                difficulty="hard",
                task_type="reasoning",
                answer_type="multiple_choice",
                metadata={
                    "short_id": ex["short_id"],
                    "question_id": ex["question_id"],
                    "categories": ex.get("categories", ""),
                    "ideal": ideal,
                    "correct_letter": correct_letter,
                    "eval_mode": ex.get("eval_mode", "str_verifier"),
                    "source": "bixbench_hf",
                    "mode": "hf_mcq",
                },
            ))

        if self.max_tasks:
            tasks = tasks[:self.max_tasks]
        return tasks

    def _load_local_exec_tasks(self) -> List[BenchmarkTask]:
        """
        Load from local BixBench repo with CodeOcean data.
        Used for both local_exec (Python/R execution) and biomate_exec (BioMate workflow execution).
        Requires paths.bixbench_repo in config.yaml.

        Data acquisition:
          git clone https://github.com/Future-House/BixBench
          # Then download CodeOcean capsule data per scenario README instructions
        """
        repo = self.config["paths"].get("bixbench_repo", "")
        if not repo:
            raise ValueError(
                "paths.bixbench_repo not set in config.yaml.\n"
                "Run: git clone https://github.com/Future-House/BixBench\n"
                "Then set paths.bixbench_repo in evaluation/config.yaml"
            )
        repo_path = Path(repo)
        scenarios_dir = repo_path / "bixbench" / "data" / "scenarios"
        if not scenarios_dir.exists():
            scenarios_dir = repo_path / "scenarios"
        if not scenarios_dir.exists():
            raise FileNotFoundError(f"BixBench scenarios not found at {scenarios_dir}")

        mode_tag = self.mode  # "local_exec" or "biomate_exec"

        tasks: List[BenchmarkTask] = []
        for scenario_dir in sorted(scenarios_dir.iterdir()):
            if not scenario_dir.is_dir():
                continue
            questions_file = scenario_dir / "questions.json"
            if not questions_file.exists():
                continue
            questions = json.loads(questions_file.read_text())
            data_dir = scenario_dir / "data"
            data_summary = _summarize_data_dir(data_dir) if data_dir.exists() else ""

            for q in questions:
                full_q = q["question"]
                if data_summary:
                    full_q = f"You have access to:\n{data_summary}\n\n{full_q}"

                # Determine BioMate workflow hint from question content
                workflow_hint = _infer_workflow_hint(full_q)

                tasks.append(BenchmarkTask(
                    task_id=f"bixbench__{scenario_dir.name}__{q['id']}",
                    question=full_q,
                    ground_truth=q["answer"],
                    domain="life_science",
                    difficulty="hard",
                    task_type="workflow" if mode_tag == "biomate_exec" else "code",
                    answer_type=q.get("answer_type", "open"),
                    metadata={
                        "scenario": scenario_dir.name,
                        "source": "bixbench_local",
                        "mode": mode_tag,
                        "data_dir": str(data_dir) if data_dir.exists() else "",
                        "verifier_type": q.get("answer_type", "str_verifier"),
                        "workflow_hint": workflow_hint,
                    },
                ))
        if self.max_tasks:
            tasks = tasks[:self.max_tasks]
        return tasks

    @staticmethod
    def _strip_workflow_preamble(response: str) -> str:
        """Strip BioMate workflow-detection preamble, same as SGIBenchRunner."""
        import re
        markers = [
            r"\*\*Missing:[^\n]*\n",
            r"\*\*Running:\*\* workflow[^\n]*\n",
            r"\*\*Understood from your message\*\*[^\n]*\n",
        ]
        cleaned = response
        last_end = 0
        for marker in markers:
            for m in re.finditer(marker, cleaned, re.IGNORECASE):
                if m.end() > last_end:
                    last_end = m.end()
        if last_end > 0:
            cleaned = cleaned[last_end:].lstrip("\n•- ")
        return cleaned.strip() or response

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        answer_type = task.metadata.get("answer_type", "open")

        if self.mode == "biomate_exec":
            return self._score_biomate_exec(task, agent_response)

        if answer_type == "multiple_choice":
            # Strip workflow-detection preamble before extracting letter
            clean = self._strip_workflow_preamble(agent_response)
            predicted = _extract_letter(clean)
            expected = str(task.ground_truth).strip().upper()
            return 1.0 if predicted == expected else 0.0

        # Open answer: LLM judge
        if self._judge is None:
            return 0.0
        clean = self._strip_workflow_preamble(agent_response)
        return self._judge.binary_score(
            question=task.question,
            ground_truth=task.ground_truth,
            agent_answer=clean,
        )

    def _score_biomate_exec(self, task: BenchmarkTask, agent_response: str) -> float:
        """
        Score a biomate_exec response.

        BixBench verifier types:
          range_verifier — ground truth is a numerical range string like "1-50" or "2.34-2.36"
          str_verifier   — ground truth is an exact string match

        Strategy:
          1. Extract the numerical result or key string from BioMate's workflow output
          2. Apply the appropriate verifier logic
        """
        gt = str(task.ground_truth).strip()
        verifier = task.metadata.get("verifier_type", "str_verifier")

        # Strip preamble — BioMate may still emit workflow-detection boilerplate
        clean = self._strip_workflow_preamble(agent_response)

        if verifier == "range_verifier":
            return _score_range_verifier(clean, gt)
        else:
            # str_verifier: exact string match after normalization
            return _score_str_verifier(clean, gt)

    def task_prompt(self, task: BenchmarkTask) -> str:
        if self.mode == "biomate_exec":
            return self._biomate_exec_prompt(task)
        # hf_mcq and local_exec: present as closed-book MCQ or knowledge question
        return (
            "SCIENTIFIC KNOWLEDGE TEST — MULTIPLE CHOICE\n"
            "============================================\n"
            "IMPORTANT: This is a CLOSED-BOOK exam. All information needed is IN the question.\n"
            "You MUST respond with a single letter: A, B, C, or D.\n"
            "Rules:\n"
            "- DO NOT ask for data files, accessions, or uploaded datasets\n"
            "- DO NOT suggest running a workflow or writing code\n"
            "- DO NOT say you cannot answer without data — all info is in the question\n"
            "- DO select the best answer from your training knowledge\n"
            "- If the question involves a computation you cannot do, STILL pick the most plausible letter\n"
            "- EVEN IF UNCERTAIN, you MUST end your response with a single letter (A, B, C, or D)\n\n"
            + task.question
            + "\n\n[REQUIRED] Final answer letter (A/B/C/D): "
        )

    def _biomate_exec_prompt(self, task: BenchmarkTask) -> str:
        """
        biomate_exec mode: ask BioMate to run the appropriate workflow on the provided data,
        then report the specific numerical or string result requested.

        BioMate's competitive advantage is workflow execution — this prompt directs it to
        use its workflow pool rather than answer from knowledge.
        """
        data_dir = task.metadata.get("data_dir", "")
        workflow_hint = task.metadata.get("workflow_hint", "")
        verifier_type = task.metadata.get("verifier_type", "str_verifier")

        data_line = (
            f"Data directory: {data_dir}\n"
            f"All input files for this analysis are in the directory above.\n"
        ) if data_dir else ""

        workflow_line = (
            f"Suggested workflow type: {workflow_hint}\n"
        ) if workflow_hint else ""

        answer_format = (
            "Report ONLY the numerical result or range (e.g., '2.34' or '10-50'). "
            "No explanation needed."
            if verifier_type == "range_verifier"
            else "Report ONLY the exact answer string. No explanation needed."
        )

        return (
            "BIOINFORMATICS ANALYSIS TASK\n"
            "=============================\n"
            + data_line
            + workflow_line
            + "\nTask:\n"
            + task.question
            + f"\n\n{answer_format}\n"
            "Run the appropriate BioMate workflow on the provided data and report the result."
        )


def _infer_workflow_hint(question: str) -> str:
    """
    Map BixBench question content to the most likely BioMate workflow category.
    Used in biomate_exec mode to help BioMate select the right pipeline.
    """
    q = question.lower()
    if any(k in q for k in ["scrna", "single-cell", "seurat", "scanpy", "umap", "cell cluster"]):
        return "Single-cell RNA-seq (Seurat / Scanpy)"
    if any(k in q for k in ["deseq2", "differential expression", "rna-seq", "rnaseq", "count matrix", "tpm", "fpkm"]):
        return "RNA-seq differential expression (DESeq2 / nf-core/rnaseq)"
    if any(k in q for k in ["logistic regression", "odds ratio", "survival", "cox", "kaplan"]):
        return "Statistical analysis (logistic regression / survival analysis)"
    if any(k in q for k in ["gwas", "genome-wide association", "snp", "variant", "plink"]):
        return "GWAS / variant association analysis"
    if any(k in q for k in ["chip-seq", "chipseq", "peak", "atac", "open chromatin"]):
        return "ChIP-seq / ATAC-seq peak analysis"
    if any(k in q for k in ["metagenom", "16s", "microbiome", "kraken", "metaphlan"]):
        return "Metagenomics / microbiome profiling"
    if any(k in q for k in ["proteom", "mass spec", "peptide", "protein quantif"]):
        return "Proteomics (DIA-NN / MaxQuant)"
    if any(k in q for k in ["methylat", "bisulfite", "cpg", "dnmt"]):
        return "DNA methylation / bisulfite sequencing"
    if any(k in q for k in ["pathway", "enrichment", "gsea", "go term", "kegg"]):
        return "Pathway enrichment analysis (GSEA)"
    return ""


def _score_range_verifier(response: str, ground_truth: str) -> float:
    """
    BixBench range_verifier: ground truth is a range like '10-50' or '2.34-2.36'.
    Extract a number from the response and check if it falls within the range.
    Score: 1.0 if within range, 0.0 otherwise.
    """
    import re

    # Parse ground truth range
    m = re.search(r"([-\d.]+)\s*[-–]\s*([-\d.]+)", ground_truth)
    if not m:
        # Single value — exact match within tolerance
        try:
            gt_val = float(re.sub(r"[^\d.\-]", "", ground_truth))
        except ValueError:
            return 0.0
        lo, hi = gt_val * 0.95, gt_val * 1.05
    else:
        try:
            lo, hi = float(m.group(1)), float(m.group(2))
        except ValueError:
            return 0.0

    # Extract all numbers from response and check if any is in range
    numbers = re.findall(r"-?\d+\.?\d*(?:[eE][+-]?\d+)?", response)
    for num_str in numbers:
        try:
            val = float(num_str)
            if lo <= val <= hi:
                return 1.0
        except ValueError:
            continue
    return 0.0


def _score_str_verifier(response: str, ground_truth: str) -> float:
    """
    BixBench str_verifier: normalized string match.
    Checks if the ground truth string appears in the response (case-insensitive).
    """
    gt_norm = ground_truth.strip().lower().strip('"\'')
    resp_norm = response.strip().lower()
    if gt_norm in resp_norm:
        return 1.0
    # Try after removing whitespace and punctuation
    import re
    gt_clean = re.sub(r"[^a-z0-9]", "", gt_norm)
    resp_clean = re.sub(r"[^a-z0-9]", "", resp_norm)
    return 1.0 if gt_clean and gt_clean in resp_clean else 0.0


def _extract_letter(text: str) -> Optional[str]:
    """Extract A/B/C/D from response. Tries explicit patterns before fallback."""
    t = text.strip()

    # 1. Response starts with just a letter (ideal case)
    m = re.match(r"^([A-D])[.\s\n]", t, re.IGNORECASE)
    if m:
        return m.group(1).upper()

    # 2. Explicit "Answer: X" or "My answer is X" pattern
    m = re.search(r"(?:answer(?:\s+is)?|choice|select(?:ion)?|correct\s+(?:answer|option)|option)[:\s]+\*{0,2}([A-D])\b", t, re.IGNORECASE)
    if m:
        return m.group(1).upper()

    # 3. Bold **A** or "**A)**" pattern
    m = re.search(r"\*\*([A-D])\b", t)
    if m:
        return m.group(1).upper()

    # 4. "The answer is A" / "I would choose B"
    m = re.search(r"(?:would\s+(?:choose|select|go\s+with)|the\s+answer\s+is|correct\s+is)\s+([A-D])\b", t, re.IGNORECASE)
    if m:
        return m.group(1).upper()

    # 5. Last standalone A/B/C/D in the response
    letters = _LETTER_RE.findall(t.upper())
    return letters[-1] if letters else None


def _summarize_data_dir(data_dir: Path) -> str:
    lines = []
    for f in sorted(data_dir.rglob("*")):
        if f.is_file():
            lines.append(f"  {f.name} ({f.stat().st_size // 1024} KB)")
    return "\n".join(lines[:20])
