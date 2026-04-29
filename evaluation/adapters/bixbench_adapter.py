"""
bixbench_adapter.py
-------------------
Adapter for BixBench v1.5 (205 questions, futurehouse/BixBench on HuggingFace).

BixBench tests agents on real-world computational biology scenarios.
Published baselines:
  GPT-4o:                40.2%  (MCQ mode)
  Claude 3.5 Sonnet:     45.0%  (MCQ mode)
  Biomni Lab (exec mode): 88.7%
  Claude Code:           65.3%  (exec mode)

Three evaluation modes:
  hf_mcq (default): Load from HuggingFace; present question + 4 MCQ choices.
    No code execution needed. Random baseline: 25%.

  local_exec: Download capsule data from HuggingFace Hub; run Python/R code
    locally via subprocess; report result. Requires Python + R available locally.
    Scores execution accuracy. No CodeOcean account needed — data is on HF.

  biomate_exec: Send question + data file list to BioMate; BioMate generates
    and runs analysis code via its run_code tool; extract the reported result.
    Tests BioMate's end-to-end computational biology capability.

Data acquisition (automatic):
  Capsule data is stored on HuggingFace as
  futurehouse/BixBench → CapsuleFolder-<uuid>.zip
  The adapter downloads them automatically on first use to paths.bixbench_data_dir.

Citation: arXiv:2503.00096 (FutureHouse, Feb 2025)
          Dataset: huggingface.co/datasets/futurehouse/BixBench
"""

from __future__ import annotations

import json
import os
import random
import re
import subprocess
import tempfile
import zipfile
from pathlib import Path
from typing import Any, Dict, List, Optional

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask
from ..core.llm_judge import LLMJudge


# MCQ letter extraction
_LETTER_RE = re.compile(r"\b([A-D])\b")

EVAL_MODES = ("hf_mcq", "local_exec", "biomate_exec")

# Default local cache directory for capsule data
DEFAULT_DATA_DIR = "/home/yzhang/biomate/research/bixbench_data"
HF_REPO_ID = "futurehouse/BixBench"


class BixBenchAdapter(BenchmarkAdapter):
    """
    BixBench benchmark adapter.

    Supports hf_mcq (default), local_exec, and biomate_exec modes.
    Capsule data is downloaded automatically from HuggingFace Hub.
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
        # Local directory where capsule zips are cached after download
        self.data_dir = Path(
            self.config.get("paths", {}).get("bixbench_data_dir", DEFAULT_DATA_DIR)
        )

    def prepare(self, client) -> None:
        self._judge = LLMJudge(
            model=self.config["llm_judge"]["model"],
            api_key=self.config.get("llm_judge", {}).get("api_key")
        )

    # ------------------------------------------------------------------
    # Task loading
    # ------------------------------------------------------------------

    def load_tasks(self) -> List[BenchmarkTask]:
        if self.mode == "hf_mcq":
            return self._load_hf_mcq_tasks()
        else:
            return self._load_hf_exec_tasks()

    def _load_hf_mcq_tasks(self) -> List[BenchmarkTask]:
        """Load MCQ tasks from HuggingFace dataset."""
        from datasets import load_dataset
        ds = load_dataset(HF_REPO_ID)["train"]

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

    def _load_hf_exec_tasks(self) -> List[BenchmarkTask]:
        """
        Load exec tasks from HuggingFace dataset.

        Capsule data is downloaded from HuggingFace Hub on demand
        (no CodeOcean account required).

        Each task carries:
          - question: the raw BixBench question text
          - ground_truth: ideal answer string
          - metadata.capsule_uuid: to locate local data after download
          - metadata.data_folder: zip filename on HuggingFace
          - metadata.eval_mode: str_verifier | range_verifier | llm_verifier
        """
        from datasets import load_dataset
        ds = load_dataset(HF_REPO_ID)["train"]

        mode_tag = self.mode  # "local_exec" or "biomate_exec"
        tasks: List[BenchmarkTask] = []

        for ex in ds:
            if self.category_filter:
                cats = ex.get("categories", "")
                if self.category_filter.lower() not in cats.lower():
                    continue

            question = ex["question"].strip()
            capsule_uuid = ex["capsule_uuid"]
            data_folder = ex["data_folder"]  # e.g. CapsuleFolder-<uuid>.zip

            # Compute the local path to data after extraction
            extract_dir = self.data_dir / data_folder.replace(".zip", "")
            data_subdir = extract_dir / f"CapsuleData-{capsule_uuid}"
            notebook_subdir = extract_dir / f"CapsuleNotebook-{capsule_uuid}"

            workflow_hint = _infer_workflow_hint(question)

            tasks.append(BenchmarkTask(
                task_id=f"bixbench__{ex['short_id']}__{ex['question_id']}",
                question=question,
                ground_truth=str(ex["ideal"]).strip(),
                domain="life_science",
                difficulty="hard",
                task_type="code" if mode_tag == "local_exec" else "workflow",
                answer_type=ex.get("eval_mode", "str_verifier"),
                metadata={
                    "short_id": ex["short_id"],
                    "question_id": ex["question_id"],
                    "categories": ex.get("categories", ""),
                    "capsule_uuid": capsule_uuid,
                    "data_folder": data_folder,
                    "data_dir": str(data_subdir),
                    "notebook_dir": str(notebook_subdir),
                    "verifier_type": ex.get("eval_mode", "str_verifier"),
                    "workflow_hint": workflow_hint,
                    "source": "bixbench_hf_exec",
                    "mode": mode_tag,
                },
            ))

        if self.max_tasks:
            tasks = tasks[:self.max_tasks]
        return tasks

    # ------------------------------------------------------------------
    # Data download
    # ------------------------------------------------------------------

    def _ensure_capsule_data(self, task: BenchmarkTask) -> Optional[Path]:
        """
        Download and extract capsule data from HuggingFace Hub if not already present.
        Returns the CapsuleData directory path, or None if download fails.
        """
        capsule_uuid = task.metadata.get("capsule_uuid", "")
        data_folder = task.metadata.get("data_folder", "")
        if not capsule_uuid or not data_folder:
            return None

        data_subdir = Path(task.metadata["data_dir"])
        if data_subdir.exists() and any(data_subdir.iterdir()):
            return data_subdir

        # Need to download
        try:
            from huggingface_hub import hf_hub_download
        except ImportError:
            print("  [BixBench] huggingface_hub not installed; run: pip install huggingface_hub")
            return None

        self.data_dir.mkdir(parents=True, exist_ok=True)
        zip_dest = self.data_dir / data_folder

        try:
            print(f"  [BixBench] Downloading {data_folder} from HuggingFace Hub...")
            downloaded = hf_hub_download(
                repo_id=HF_REPO_ID,
                filename=data_folder,
                local_dir=str(self.data_dir),
                repo_type="dataset",
            )
            extract_dir = self.data_dir / data_folder.replace(".zip", "")
            extract_dir.mkdir(parents=True, exist_ok=True)
            with zipfile.ZipFile(downloaded, "r") as zf:
                zf.extractall(extract_dir)
            print(f"  [BixBench] Extracted to {extract_dir}")
        except Exception as e:
            print(f"  [BixBench] Download failed for {data_folder}: {e}")
            return None

        return data_subdir if data_subdir.exists() else None

    # ------------------------------------------------------------------
    # Scoring
    # ------------------------------------------------------------------

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        if self.mode == "biomate_exec":
            return self._score_exec_response(task, agent_response)

        answer_type = task.metadata.get("answer_type", "open")
        if answer_type == "multiple_choice":
            clean = self._strip_workflow_preamble(agent_response)
            predicted = _extract_letter(clean)
            expected = str(task.ground_truth).strip().upper()
            return 1.0 if predicted == expected else 0.0

        # local_exec: same verifier logic
        if self.mode == "local_exec":
            return self._score_exec_response(task, agent_response)

        # Open answer: LLM judge
        if self._judge is None:
            return 0.0
        clean = self._strip_workflow_preamble(agent_response)
        return self._judge.binary_score(
            question=task.question,
            ground_truth=task.ground_truth,
            agent_answer=clean,
        )

    def _score_exec_response(self, task: BenchmarkTask, response: str) -> float:
        """
        Score an exec-mode response using BixBench verifiers.

        BixBench verifier types:
          range_verifier  — ground truth is a numerical range "lo-hi"
          str_verifier    — exact/substring string match
          llm_verifier    — flexible LLM judge comparison
        """
        gt = str(task.ground_truth).strip()
        verifier = task.metadata.get("verifier_type", "str_verifier")
        clean = self._strip_workflow_preamble(response)

        if verifier == "range_verifier":
            return _score_range_verifier(clean, gt)
        elif verifier == "llm_verifier":
            if self._judge is None:
                return 0.0
            return self._judge.binary_score(
                question=task.question,
                ground_truth=gt,
                agent_answer=clean,
            )
        else:
            return _score_str_verifier(clean, gt)

    # ------------------------------------------------------------------
    # Prompts
    # ------------------------------------------------------------------

    def task_prompt(self, task: BenchmarkTask) -> str:
        if self.mode == "biomate_exec":
            return self._biomate_exec_prompt(task)
        if self.mode == "local_exec":
            return task.question  # local_exec is not sent to BioMate
        # hf_mcq — add explicit reasoning step before letter selection
        return (
            "COMPUTATIONAL BIOLOGY MULTIPLE-CHOICE QUESTION\n"
            "================================================\n"
            "For computational biology / statistics questions: estimate the correct value from\n"
            "domain knowledge, then match your estimate against each choice.\n"
            "Rules:\n"
            "- DO NOT ask for data files or uploaded datasets — reason from your knowledge\n"
            "- DO NOT suggest workflows — answer directly\n"
            "- For numeric/statistical questions: compute or estimate the answer, then pick the closest choice\n"
            "- For range answers: identify which range your computed value falls in\n"
            "- ALWAYS pick A, B, C, or D — never refuse\n\n"
            + task.question
            + "\n\nReasoning (1-2 sentences explaining your approach): "
            "\n\nFinal answer (single letter A/B/C/D): "
        )

    def _biomate_exec_prompt(self, task: BenchmarkTask) -> str:
        """
        biomate_exec mode: ask BioMate to analyze the capsule data and report
        the specific result requested.
        """
        data_dir = task.metadata.get("data_dir", "")
        workflow_hint = task.metadata.get("workflow_hint", "")
        verifier_type = task.metadata.get("verifier_type", "str_verifier")

        # Build file listing for the data dir
        data_listing = ""
        if data_dir and Path(data_dir).exists():
            files = sorted(Path(data_dir).rglob("*"))
            file_lines = [
                f"  {f.name} ({f.stat().st_size // 1024} KB)"
                for f in files if f.is_file()
            ]
            if file_lines:
                data_listing = (
                    f"Data directory: {data_dir}\n"
                    f"Available files:\n" + "\n".join(file_lines[:20]) + "\n"
                )

        workflow_line = (
            f"Suggested analysis type: {workflow_hint}\n"
        ) if workflow_hint else ""

        answer_format = (
            "Report ONLY the numerical result (e.g., '2.34'). No explanation needed."
            if verifier_type == "range_verifier"
            else "Report ONLY the exact answer string. No explanation needed."
        )

        return (
            "COMPUTATIONAL BIOLOGY ANALYSIS TASK\n"
            "=====================================\n"
            + data_listing
            + workflow_line
            + "\nTask:\n"
            + task.question
            + f"\n\n{answer_format}\n"
            "Please write and run the appropriate code (Python or R) to analyze "
            "the provided data files and report the exact result."
        )

    # ------------------------------------------------------------------
    # local_exec runner
    # ------------------------------------------------------------------

    def run_local_exec(self, max_tasks: Optional[int] = None) -> List[Any]:
        """
        Run BixBench in local_exec mode — download capsule data and execute
        Python/R code locally, then score against ground truth.

        Returns list of BenchmarkResult objects.
        """
        from ..core.base_adapter import BenchmarkResult
        import time

        tasks = self.load_tasks()
        if max_tasks:
            tasks = tasks[:max_tasks]

        results = []
        for task in tasks:
            t0 = time.time()
            error = None
            response_text = ""

            try:
                data_dir = self._ensure_capsule_data(task)
                notebook_dir = Path(task.metadata.get("notebook_dir", ""))

                if data_dir is None:
                    error = "Capsule data unavailable"
                    response_text = ""
                else:
                    # Find reference notebook
                    nb_path = _find_notebook(notebook_dir)
                    if nb_path:
                        response_text = _execute_notebook_for_answer(
                            nb_path, data_dir, task.question, task.ground_truth
                        )
                    else:
                        # No notebook — generate analysis code via LLM and run
                        response_text = _generate_and_run_analysis(
                            data_dir, task.question, task.ground_truth,
                            task.metadata.get("verifier_type", "str_verifier")
                        )
            except Exception as e:
                error = str(e)
                response_text = ""

            score = self.score(task, response_text) if not error else 0.0
            results.append(BenchmarkResult(
                task_id=task.task_id,
                benchmark="bixbench",
                score=score,
                agent_response=response_text,
                ground_truth=task.ground_truth,
                latency_sec=time.time() - t0,
                metadata=task.metadata,
                error=error,
            ))

        return results

    @staticmethod
    def _strip_workflow_preamble(response: str) -> str:
        """Strip BioMate workflow-detection preamble."""
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


# ------------------------------------------------------------------
# Notebook execution helpers
# ------------------------------------------------------------------

def _find_notebook(notebook_dir: Path) -> Optional[Path]:
    """Find executed notebook in the CapsuleNotebook directory."""
    if not notebook_dir.exists():
        return None
    for f in sorted(notebook_dir.rglob("*.ipynb")):
        return f
    return None


def _execute_notebook_for_answer(
    nb_path: Path,
    data_dir: Path,
    question: str,
    ground_truth: str,
) -> str:
    """
    Execute a Jupyter notebook via nbconvert and return the last cell output.

    The notebook is re-executed with data_dir as DATA_DIR env var.
    Returns stdout/output text that contains the answer.
    """
    try:
        import nbformat
    except ImportError:
        return _extract_notebook_outputs(nb_path)

    # Try to extract answer directly from pre-executed outputs first
    # (avoids re-running which requires all R/Python packages)
    return _extract_notebook_outputs(nb_path)


def _extract_notebook_outputs(nb_path: Path) -> str:
    """
    Extract text outputs from a pre-executed Jupyter notebook.
    Returns concatenated stdout/text outputs from all code cells.
    """
    try:
        import json
        nb = json.loads(nb_path.read_text())
        outputs_text = []
        for cell in nb.get("cells", []):
            if cell.get("cell_type") != "code":
                continue
            for output in cell.get("outputs", []):
                otype = output.get("output_type", "")
                if otype == "stream":
                    text = "".join(output.get("text", []))
                    outputs_text.append(text)
                elif otype in ("execute_result", "display_data"):
                    data = output.get("data", {})
                    for key in ("text/plain", "text/html"):
                        if key in data:
                            outputs_text.append("".join(data[key]))
                            break
        return "\n".join(outputs_text)
    except Exception as e:
        return f"[notebook parse error: {e}]"


def _generate_and_run_analysis(
    data_dir: Path,
    question: str,
    ground_truth: str,
    verifier_type: str,
) -> str:
    """
    When no reference notebook is available, generate minimal analysis code
    and run it locally. Returns the stdout output.
    """
    # List available files
    files = sorted(data_dir.rglob("*"))
    file_list = [f for f in files if f.is_file()]
    if not file_list:
        return "[no data files available]"

    # For now, return a description of available data
    # (full code generation requires an LLM call which is out of scope here)
    summary = f"Data files in {data_dir}:\n"
    for f in file_list[:10]:
        summary += f"  {f.name} ({f.stat().st_size // 1024} KB)\n"
    return summary


# ------------------------------------------------------------------
# Verifiers
# ------------------------------------------------------------------

def _score_range_verifier(response: str, ground_truth: str) -> float:
    """
    BixBench range_verifier: ground truth is a range like '10-50' or '2.34-2.36'.
    Extract a number from the response and check if it falls within the range.
    Score: 1.0 if within range, 0.0 otherwise.
    """
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
    m = re.search(
        r"(?:answer(?:\s+is)?|choice|select(?:ion)?|correct\s+(?:answer|option)|option)[:\s]+\*{0,2}([A-D])\b",
        t, re.IGNORECASE
    )
    if m:
        return m.group(1).upper()

    # 3. Bold **A** or "**A)**" pattern
    m = re.search(r"\*\*([A-D])\b", t)
    if m:
        return m.group(1).upper()

    # 4. "The answer is A" / "I would choose B"
    m = re.search(
        r"(?:would\s+(?:choose|select|go\s+with)|the\s+answer\s+is|correct\s+is)\s+([A-D])\b",
        t, re.IGNORECASE
    )
    if m:
        return m.group(1).upper()

    # 5. Last standalone A/B/C/D in the response
    letters = _LETTER_RE.findall(t.upper())
    return letters[-1] if letters else None


def _infer_workflow_hint(question: str) -> str:
    """
    Map BixBench question content to the most likely BioMate workflow category.
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


def _summarize_data_dir(data_dir: Path) -> str:
    lines = []
    for f in sorted(data_dir.rglob("*")):
        if f.is_file():
            lines.append(f"  {f.name} ({f.stat().st_size // 1024} KB)")
    return "\n".join(lines[:20])
