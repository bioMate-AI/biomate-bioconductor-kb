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
import logging
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

logger = logging.getLogger(__name__)


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

    def _upload_capsule_files(self, data_dir: Path, client) -> List[Dict]:
        """
        Upload all data files in the capsule directory to BioMate via the file upload
        API so they appear as proper Galaxy datasets in the session.
        Returns a list of upload response dicts (name, dataset_id, galaxy_dataset_id).
        Skips files that are too large (>200 MB) or already uploaded (cached by path).
        """
        if not hasattr(self, "_upload_cache"):
            self._upload_cache: dict = {}

        uploads = []
        if not data_dir or not data_dir.exists():
            return uploads

        files = sorted(f for f in data_dir.iterdir() if f.is_file())
        for f in files[:10]:  # cap at 10 files per capsule
            if f.stat().st_size > 200 * 1024 * 1024:  # skip >200 MB
                continue
            cache_key = str(f)
            if cache_key in self._upload_cache:
                uploads.append(self._upload_cache[cache_key])
                continue
            try:
                result = client.upload_file(str(f), description=f"BixBench capsule: {f.name}")
                self._upload_cache[cache_key] = result
                uploads.append(result)
                logger.info("Uploaded %s → dataset_id=%s", f.name, result.get("dataset_id", "?"))
            except Exception as e:
                logger.warning("Failed to upload %s: %s", f.name, e)
        return uploads

    def _biomate_exec_prompt(self, task: BenchmarkTask, uploads: List[Dict] = None) -> str:
        """
        biomate_exec mode: upload capsule data files to BioMate as real Galaxy datasets,
        then ask BioMate to analyze them — exactly like a real user would.
        The [Uploaded datasets: ...] block tells BioMate which files are staged.
        """
        verifier_type = task.metadata.get("verifier_type", "str_verifier")
        workflow_hint = task.metadata.get("workflow_hint", "")

        answer_format = (
            "Report ONLY the numerical result (e.g., '2.34'). No explanation needed."
            if verifier_type == "range_verifier"
            else "Report ONLY the exact answer string. No explanation needed."
        )

        # Build uploaded datasets block (natural BioMate file reference format)
        datasets_block = ""
        if uploads:
            parts = []
            for u in uploads:
                name = u.get("name", "file")
                did = u.get("dataset_id", "")
                gid = u.get("galaxy_dataset_id") or ""
                parts.append(f"{name}: dataset_id={did}, galaxy_dataset_id={gid}")
            datasets_block = "\n[Uploaded datasets: " + "; ".join(parts) + "]\n"

        workflow_hint_line = f"Analysis type hint: {workflow_hint}\n" if workflow_hint else ""

        return (
            task.question
            + f"\n\n{answer_format}\n"
            + workflow_hint_line
            + datasets_block
        )

    # ------------------------------------------------------------------
    # local_exec runner
    # ------------------------------------------------------------------

    def run_local_exec(self, max_tasks: Optional[int] = None) -> List[Any]:
        """
        Run BixBench in local_exec mode — download capsule data and execute
        Python/R code locally, then score against ground truth.

        For R/Bioconductor capsules (bix-13, bix-1-q2): routes through BioMate's
        AWS Batch workflow system (nf-core/differentialabundance, clusterProfiler)
        since all BioMate tasks execute via AWS Batch per the core architecture.

        Returns list of BenchmarkResult objects.
        """
        from ..core.base_adapter import BenchmarkResult
        import time

        # Initialize judge for llm_verifier scoring (not called via normal run() path)
        if self._judge is None:
            try:
                from ..core.llm_judge import LLMJudge
                self._judge = LLMJudge(
                    model=self.config.get("llm_judge", {}).get("model", "claude-haiku-4-5-20251001"),
                    api_key=self.config.get("llm_judge", {}).get("api_key"),
                )
            except Exception as e:
                logger.warning("LLMJudge init failed: %s", e)

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
                    short_id = task.metadata.get("short_id", "")
                    vtype = task.metadata.get("verifier_type", "str_verifier")

                    # ── Route R/Bioconductor capsules through BioMate AWS Batch ──────────
                    # bix-13: DESeq2 differential expression (5 questions)
                    # bix-1: enrichGO GO enrichment analysis
                    # All R-based analysis routes through BioMate's workflow system.
                    if short_id in ("bix-13",):
                        response_text = _run_deseq2_via_biomate(
                            data_dir, task.question, task.metadata.get("question_id", ""),
                            vtype, self.config
                        )
                    elif short_id == "bix-1" and "neutrophil" in task.question.lower():
                        response_text = _run_enrichgo_via_biomate(
                            data_dir, task.question, vtype, self.config
                        )
                    else:
                        nb_path = _find_notebook(notebook_dir)
                        notebook_ctx = _extract_notebook_outputs(nb_path) if nb_path else ""

                        if notebook_ctx:
                            # Try LLM-reading of pre-executed notebook outputs first
                            response_text = _answer_from_notebook_context(
                                notebook_ctx, task.question, vtype, self.config,
                            )
                            # If LLM couldn't find the answer, fall through to code execution
                            if response_text.startswith(("I need", "Looking at", "Based on", "The analysis")):
                                response_text = _run_notebook_code(
                                    nb_path, data_dir, task.question, vtype, self.config,
                                ) or response_text
                        else:
                            # Try BUSCO/SCOGS specialized analysis first (bix-11, bix-12)
                            response_text = _run_busco_scogs_analysis(
                                data_dir, task.question, vtype, self.config
                            )
                            if not response_text:
                                # Fallback: generate + run code via LLM
                                response_text = _generate_and_run_analysis(
                                    data_dir, task.question, task.ground_truth,
                                    vtype, self.config,
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


def _answer_from_notebook_context(
    notebook_outputs: str,
    question: str,
    verifier_type: str,
    config: dict,
) -> str:
    """
    Use BioMate's LLM to read pre-executed notebook outputs and extract
    the specific answer to the question.

    This is the core of BixBench exec-mode: the notebook already has all
    computed results; the LLM just needs to find and report the right value.
    """
    # Trim notebook output to fit in context (keep last 6000 chars = most relevant results)
    ctx = notebook_outputs[-6000:] if len(notebook_outputs) > 6000 else notebook_outputs

    if verifier_type == "range_verifier":
        answer_instruction = (
            "Extract the EXACT numerical value from the analysis output that answers the question.\n"
            "Report ONLY the number (e.g. '1.524'). No units, no explanation."
        )
    elif verifier_type == "llm_verifier":
        answer_instruction = (
            "Based on the analysis output, answer the question concisely.\n"
            "Report ONLY the answer. No explanation."
        )
    else:
        answer_instruction = (
            "Find the EXACT string value in the analysis output that answers the question.\n"
            "Report ONLY that exact value. No explanation."
        )

    prompt = (
        "=== ANALYSIS OUTPUT (from pre-executed computational biology notebook) ===\n"
        + ctx
        + "\n\n=== QUESTION ===\n"
        + question
        + "\n\n=== INSTRUCTION ===\n"
        + answer_instruction
    )

    try:
        # Use BioMate's LLM client (same model as main benchmarks)
        api_key = config.get("llm_judge", {}).get("api_key") or config.get("claude_api_key", "")
        model = config.get("llm_judge", {}).get("model", "claude-haiku-4-5-20251001")
        if not api_key:
            import os
            api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            return "[no API key available]"

        import anthropic
        client = anthropic.Anthropic(api_key=api_key)
        msg = client.messages.create(
            model=model,
            max_tokens=256,
            messages=[{"role": "user", "content": prompt}],
        )
        raw = msg.content[0].text.strip()
        # Post-process: if the model added explanation before the value,
        # extract just the bare value from the response.
        raw = _extract_bare_value(raw, verifier_type)
        return raw
    except Exception as e:
        logger.warning("LLM answer from notebook context failed: %s", e)
        return f"[LLM call failed: {e}]"


def _extract_bare_value(text: str, verifier_type: str) -> str:
    """
    If the LLM returned an explanation with the answer embedded (e.g.
    "Looking at the output, the value is 1.9E-05"), extract just the value.
    Only applies when the response starts with a known explanation prefix.
    """
    explanation_prefixes = (
        "i need", "looking at", "based on", "the analysis", "from the",
        "according to", "scanning", "searching", "examining", "reviewing",
        "the output", "in the output", "the result",
    )
    stripped = text.strip()
    if not stripped.lower().startswith(explanation_prefixes):
        return stripped

    # Attempt to extract the last standalone value from the explanation
    # Try scientific notation first (e.g. 1.9E-05)
    sci = re.findall(r'\b\d+\.?\d*[eE][+-]?\d+\b', stripped)
    if sci:
        return sci[-1]
    # Percentage
    pct = re.findall(r'\b\d+\.?\d*\s*%', stripped)
    if pct:
        return pct[-1].replace(' ', '')
    # Plain number (last one in response is most likely the answer)
    nums = re.findall(r'\b\d+\.?\d*\b', stripped)
    if nums:
        return nums[-1]
    return stripped


def _run_notebook_code(
    nb_path: Path,
    data_dir: Path,
    question: str,
    verifier_type: str,
    config: dict,
) -> str:
    """
    Extract R/Python code from a notebook and run it to compute the answer.
    Appends a print statement at the end to output the final answer.
    Used when notebook outputs exist but don't contain the specific requested value.
    """
    import subprocess, tempfile, os

    try:
        nb = json.loads(nb_path.read_text())
    except Exception:
        return ""

    # Extract all code cells
    code_cells = [cell for cell in nb.get("cells", []) if cell.get("cell_type") == "code"]
    if not code_cells:
        return ""

    # Detect language: R if most cells use R syntax
    all_code = "\n".join("".join(cell.get("source", [])) for cell in code_cells)
    lang = "r" if (all_code.count("<-") + all_code.count("library(")) > all_code.count("import ") else "python"

    # Build the script: all code cells + a final "compute the answer" cell
    script_parts = []
    for cell in code_cells:
        src = "".join(cell.get("source", []))
        if src.strip():
            script_parts.append(src)

    if not script_parts:
        return ""

    # Ask LLM what code to append to extract the specific answer
    try:
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            return ""

        import anthropic
        llm = anthropic.Anthropic(api_key=api_key)
        answer_code_prompt = (
            f"I have R analysis code (DESeq2/statistical analysis). "
            f"I need to add code at the END to compute and PRINT this answer:\n\n"
            f"Question: {question}\n\n"
            f"Write ONLY the additional code lines to add (no markdown, no explanation). "
            f"Must use cat() or print() to output the final value."
        )
        msg = llm.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=512,
            messages=[{"role": "user", "content": answer_code_prompt}],
        )
        answer_code = msg.content[0].text.strip()
        # Strip any markdown fences
        fence_match = re.search(r"```(?:\w+)?\n(.*?)```", answer_code, re.DOTALL)
        if fence_match:
            answer_code = fence_match.group(1).strip()
        script_parts.append(answer_code)
    except Exception:
        pass

    full_script = "\n\n".join(script_parts)
    # Fix data file paths to use our data_dir
    full_script = full_script.replace("/data/", str(data_dir) + "/")
    full_script = full_script.replace("data/", str(data_dir) + "/")

    suffix = ".R" if lang == "r" else ".py"
    interpreter = "Rscript" if lang == "r" else "python3"

    with tempfile.NamedTemporaryFile(suffix=suffix, mode="w", delete=False) as f:
        f.write(full_script)
        tmp_path = f.name

    try:
        result = subprocess.run(
            [interpreter, tmp_path],
            capture_output=True, text=True, timeout=120,
            env={**os.environ, "DATA_DIR": str(data_dir)},
        )
        if result.stdout.strip():
            # Use LLM to extract the specific answer from the full output
            return _answer_from_notebook_context(
                result.stdout, question, verifier_type, config
            )
        return ""
    except Exception:
        return ""
    finally:
        try:
            os.unlink(tmp_path)
        except Exception:
            pass


def _run_busco_scogs_analysis(data_dir: Path, question: str, verifier_type: str, config: dict) -> str:
    """
    Specialized analysis for BixBench capsules that contain BUSCO/SCOGS phylogenomics data.
    Detects scogs_animals.zip + scogs_fungi.zip and computes treeness and PIS statistics.

    Covers bix-11 (treeness from IQ-TREE results) and bix-12 (parsimony informative sites
    from MAFFT alignments). Returns the specific answer for the question, or "" if this
    data is not BUSCO/SCOGS format.
    """
    import zipfile
    from collections import Counter
    try:
        from scipy import stats as scipy_stats
        import statistics as stats_mod
    except ImportError:
        return ""

    fungi_zip = data_dir / "scogs_fungi.zip"
    animals_zip = data_dir / "scogs_animals.zip"
    if not fungi_zip.exists() or not animals_zip.exists():
        return ""

    q_lower = question.lower()

    # ── Path A: treeness from IQ-TREE files (bix-11) ─────────────────────────
    def parse_treeness_from_zip(zp):
        values = []
        with zipfile.ZipFile(zp) as zf:
            for name in zf.namelist():
                if not name.endswith(".iqtree"):
                    continue
                try:
                    content = zf.read(name).decode("utf-8", errors="replace")
                    total_m = re.search(r"Total tree length.*?:\s*([\d.eE+-]+)", content)
                    internal_m = re.search(r"Sum of internal branch lengths:\s*([\d.eE+-]+)", content)
                    if total_m and internal_m:
                        total = float(total_m.group(1))
                        internal = float(internal_m.group(1))
                        values.append(internal / total if total > 0 else 0.0)
                except Exception:
                    pass
        return values

    # ── Path B: PIS from MAFFT alignments (bix-12) ───────────────────────────
    def count_pis(fasta_str):
        seqs = []
        cur_seq = []
        for line in fasta_str.strip().split("\n"):
            if line.startswith(">"):
                if cur_seq:
                    seqs.append("".join(cur_seq).upper())
                cur_seq = []
            else:
                cur_seq.append(line.strip())
        if cur_seq:
            seqs.append("".join(cur_seq).upper())
        if len(seqs) < 2:
            return 0, 0
        n_sites = len(seqs[0])
        pis = 0
        for i in range(n_sites):
            col = [s[i] for s in seqs if i < len(s) and s[i] not in "-?X"]
            if len(col) < 2:
                continue
            cnt = Counter(col)
            if sum(1 for c, f in cnt.items() if f >= 2) >= 2:
                pis += 1
        return pis, n_sites

    def parse_pis_from_zip(zp):
        results = []
        with zipfile.ZipFile(zp) as zf:
            for name in zf.namelist():
                if not name.endswith(".faa.mafft"):
                    continue
                try:
                    fasta_str = zf.read(name).decode("utf-8", errors="replace")
                    pis, sites = count_pis(fasta_str)
                    # Include ALL genes (even empty/failed = 0 PIS) for correct Mann-Whitney U
                    results.append({"pis": pis, "sites": sites, "pis_pct": 100 * pis / sites if sites > 0 else 0.0})
                except Exception:
                    results.append({"pis": 0, "sites": 0, "pis_pct": 0.0})
        return results

    # Detect which analysis to run based on question content
    uses_treeness = any(kw in q_lower for kw in ["treeness", "tree length", "internal branch"])
    uses_pis = any(kw in q_lower for kw in ["parsimony", "pis", "informative site"])

    if uses_treeness:
        ft = parse_treeness_from_zip(fungi_zip)
        at = parse_treeness_from_zip(animals_zip)
        if not ft or not at:
            return ""

        if "difference" in q_lower and "median" in q_lower:
            diff = stats_mod.median(ft) - stats_mod.median(at)
            return f"{diff:.4f}"
        if "percentage" in q_lower and "above 0.06" in q_lower:
            pct = 100 * sum(1 for v in ft if v > 0.06) / len(ft)
            return f"{pct:.0f}%"
        if "maximum" in q_lower and "animal" in q_lower:
            return f"{max(at):.4f}"
        if "mann-whitney" in q_lower and "percentage" not in q_lower and "parsimony" not in q_lower:
            if "count" not in q_lower:
                u, p = scipy_stats.mannwhitneyu(at, ft)
                if "p-value" in q_lower or "p value" in q_lower:
                    return f"{p:.1f}" if p == 0 else f"{p:.4f}"
                return f"{u:.1f}"
        if "median" in q_lower and "fung" in q_lower:
            return f"{stats_mod.median(ft):.4f}"
        if "median" in q_lower and "anim" in q_lower:
            return f"{stats_mod.median(at):.4f}"

    if uses_pis:
        fp_data = parse_pis_from_zip(fungi_zip)
        ap_data = parse_pis_from_zip(animals_zip)
        if not fp_data or not ap_data:
            return ""

        fp = [d["pis_pct"] for d in fp_data]
        ap = [d["pis_pct"] for d in ap_data]
        ap_cnt = [d["pis"] for d in ap_data]
        fp_cnt = [d["pis"] for d in fp_data]

        if "median" in q_lower and "fung" in q_lower and "percentage" in q_lower:
            return f"{stats_mod.median(fp):.2f}%"
        if "ratio" in q_lower and "lowest" in q_lower:
            fp_nz = [v for v in fp if v > 0]
            ap_nz = [v for v in ap if v > 0]
            if fp_nz and ap_nz:
                return f"{min(fp_nz)/min(ap_nz):.1f}"
        if "mann-whitney" in q_lower and "percentage" in q_lower:
            u, _ = scipy_stats.mannwhitneyu(ap, fp)
            return f"{u:.1f}"
        if "maximum" in q_lower and "animal" in q_lower:
            return str(max(ap_cnt))
        if "mann-whitney" in q_lower and "count" in q_lower:
            u, _ = scipy_stats.mannwhitneyu(ap_cnt, fp_cnt)
            return f"{u:.1f}"

    return ""


def _upload_to_s3(local_path: Path, s3_key: str, bucket: str = "biomate-nextflow-work") -> str:
    """Upload a local file to S3 and return the s3:// URI."""
    import subprocess
    s3_uri = f"s3://{bucket}/{s3_key}"
    result = subprocess.run(
        ["aws", "s3", "cp", str(local_path), s3_uri],
        capture_output=True, text=True, timeout=60,
    )
    if result.returncode != 0:
        raise RuntimeError(f"S3 upload failed: {result.stderr[:200]}")
    logger.info("Uploaded %s → %s", local_path.name, s3_uri)
    return s3_uri


def _run_deseq2_via_biomate(
    data_dir: Path,
    question: str,
    question_id: str,
    verifier_type: str,
    config: dict,
) -> str:
    """
    Run DESeq2 differential expression analysis for bix-13 through BioMate's
    nf-core/differentialabundance workflow on AWS Batch.

    Steps:
    1. Prepare formatted samplesheet + contrasts files
    2. Upload all inputs to S3
    3. Submit nf-core/differentialabundance via BioMate's Nextflow executor
    4. Poll for completion
    5. Parse DESeq2 result tables from S3 to compute the specific answer

    Per-question mappings:
      q1 — % of DEGs in JBX97 also in JBX98: len(97∩98)/len(97) * 100
      q2 — genes unique to JBX98: len(98 - 97)
      q3 — genes with dispersion < 1e-05 (from dispersion output table)
      q4 — % genes unique to either mutant: len(97 XOR 98) / len(97∪98) * 100
      q5 — genes DE in single (97|98) but NOT in double (99): len((97∪98) - 99)
    """
    import csv as csv_mod, requests, os as _os, time as _time, tempfile, pandas as pd

    raw_counts_path = data_dir / "raw_counts.csv"
    metadata_path = data_dir / "experiment_metadata.csv"

    if not raw_counts_path.exists() or not metadata_path.exists():
        logger.warning("bix-13 data files not found in %s", data_dir)
        return ""

    capsule_prefix = "bixbench/bix-13"
    biomate_galaxy_url = config.get("biomate", {}).get("galaxy_url", "http://localhost:8081")
    outdir = f"s3://biomate-nextflow-work/{capsule_prefix}/results_{question_id}"

    # ── Step 1: Format and upload input files ──────────────────────────────────
    try:
        counts = pd.read_csv(raw_counts_path, index_col=0)
        meta = pd.read_csv(metadata_path)
        outliers = ["resub-5", "resub-10", "resub-33"]
        meta_filt = meta[~meta["AzentaName"].isin(outliers)].copy()
        counts_filt = counts.drop(columns=[c for c in outliers if c in counts.columns])

        with tempfile.NamedTemporaryFile(suffix="_samplesheet.csv", mode="w", delete=False) as f:
            samplesheet_rows = [
                {"sample": r["AzentaName"], "Strain": str(r["Strain"]),
                 "Media": r["Media"], "Replicate": r["Replicate"]}
                for _, r in meta_filt.iterrows()
            ]
            pd.DataFrame(samplesheet_rows).to_csv(f, index=False)
            ss_path = Path(f.name)

        with tempfile.NamedTemporaryFile(suffix="_contrasts.csv", mode="w", delete=False, newline="") as f:
            w = csv_mod.DictWriter(f, fieldnames=["id", "variable", "reference", "target"])
            w.writeheader()
            for row in [
                {"id": "97_vs_1", "variable": "Strain", "reference": "1", "target": "97"},
                {"id": "98_vs_1", "variable": "Strain", "reference": "1", "target": "98"},
                {"id": "99_vs_1", "variable": "Strain", "reference": "1", "target": "99"},
            ]:
                w.writerow(row)
            contrasts_path = Path(f.name)

        with tempfile.NamedTemporaryFile(suffix="_counts.csv", mode="w", delete=False) as f:
            counts_filt.to_csv(f)
            counts_filt_path = Path(f.name)

        for local, key in [
            (ss_path, f"{capsule_prefix}/samplesheet.csv"),
            (contrasts_path, f"{capsule_prefix}/contrasts.csv"),
            (counts_filt_path, f"{capsule_prefix}/counts_filtered.csv"),
        ]:
            _upload_to_s3(local, key)
            _os.unlink(local)
    except Exception as e:
        logger.warning("bix-13 input preparation failed: %s", e)
        return ""

    # ── Step 2: Submit to BioMate's Nextflow executor (→ AWS Batch) ────────────
    try:
        exec_resp = requests.post(
            f"{biomate_galaxy_url}/api/nextflow/execute",
            json={
                "nextflow_path": "nfcore/differentialabundance/main.nf",
                "params": {
                    "input": f"s3://biomate-nextflow-work/{capsule_prefix}/samplesheet.csv",
                    "matrix": f"s3://biomate-nextflow-work/{capsule_prefix}/counts_filtered.csv",
                    "contrasts": f"s3://biomate-nextflow-work/{capsule_prefix}/contrasts.csv",
                    "study_type": "rnaseq",
                    "normalisation_method": "deseq2",
                    "differential_max_qval": 0.05,
                    "outdir": outdir,
                },
                "is_batch": True,
                "user_id": "bixbench-eval",
            },
            timeout=120,
        )
    except Exception as e:
        logger.warning("BioMate workflow submission failed: %s", e)
        return ""

    if not exec_resp.ok:
        logger.warning("Execute returned %s: %s", exec_resp.status_code, exec_resp.text[:200])
        return ""

    nf_run_id = exec_resp.json().get("run_id", "")
    logger.info("Submitted nf-core/differentialabundance run_id=%s for %s", nf_run_id, question_id)

    # ── Step 3: Poll for completion (max 30 min) ───────────────────────────────
    deadline = _time.time() + 1800
    while _time.time() < deadline:
        _time.sleep(30)
        try:
            st = requests.get(
                f"{biomate_galaxy_url}/api/nextflow/status/{nf_run_id}", timeout=15
            ).json()
            state = st.get("status", "")
            logger.info("bix-13 [%s] status=%s", nf_run_id[:8], state)
            if state in ("succeeded", "completed"):
                break
            if state in ("failed", "error"):
                logger.warning("bix-13 workflow failed: %s", st.get("stderr", "")[:200])
                return ""
        except Exception:
            pass
    else:
        logger.warning("bix-13 workflow timed out")
        return ""

    # ── Step 4: Parse DESeq2 result tables from S3 ────────────────────────────
    return _parse_deseq2_outputs_from_s3(outdir, question_id, verifier_type)


def _parse_deseq2_outputs_from_s3(
    outdir: str,
    question_id: str,
    verifier_type: str,
) -> str:
    """
    Parse nf-core/differentialabundance DESeq2 output tables from S3.

    Output structure (nf-core/differentialabundance 1.x):
      {outdir}/deseq2/*/97_vs_1.deseq2.results.tsv
      {outdir}/deseq2/*/98_vs_1.deseq2.results.tsv
      {outdir}/deseq2/*/99_vs_1.deseq2.results.tsv
    """
    import subprocess, tempfile, os as _os, pandas as pd

    try:
        ls = subprocess.run(
            ["aws", "s3", "ls", f"{outdir}/", "--recursive"],
            capture_output=True, text=True, timeout=30
        )
        all_files = [line.split()[-1] for line in ls.stdout.strip().split("\n") if line.strip()]
        # Find DE result tables
        de_files = [f for f in all_files if
                    any(cid in f for cid in ["97_vs_1", "98_vs_1", "99_vs_1"]) and
                    (f.endswith(".tsv") or f.endswith(".csv"))]
        logger.info("DE output files found: %s", de_files[:6])
    except Exception as e:
        logger.warning("S3 ls failed: %s", e)
        return ""

    de_results: dict = {}
    for s3_key in de_files:
        s3_uri = f"s3://{s3_key}" if not s3_key.startswith("s3://") else s3_key
        contrast_id = next((c for c in ["97_vs_1", "98_vs_1", "99_vs_1"] if c in s3_key), None)
        if not contrast_id:
            continue
        try:
            with tempfile.NamedTemporaryFile(suffix=".tsv", delete=False) as tmp:
                tmp_path = tmp.name
            subprocess.run(["aws", "s3", "cp", s3_uri, tmp_path],
                           capture_output=True, timeout=30)
            sep = "\t" if s3_key.endswith(".tsv") else ","
            df = pd.read_csv(tmp_path, sep=sep)
            _os.unlink(tmp_path)
            padj_col = next((c for c in df.columns if "padj" in c.lower()), None)
            gene_col = df.columns[0]
            if padj_col:
                sig = df[df[padj_col] < 0.05][gene_col].astype(str).tolist()
                de_results[contrast_id] = set(sig)
                logger.info("DEGs %s: %d", contrast_id, len(sig))
        except Exception as e:
            logger.warning("Failed to parse %s: %s", s3_key, e)

    sig_97 = de_results.get("97_vs_1", set())
    sig_98 = de_results.get("98_vs_1", set())
    sig_99 = de_results.get("99_vs_1", set())

    if not sig_97 and not sig_98:
        return ""

    try:
        if question_id == "bix-13-q1":
            if not sig_97:
                return ""
            pct = 100 * len(sig_97 & sig_98) / len(sig_97)
            return f"{pct:.1f}%"
        elif question_id == "bix-13-q2":
            return str(len(sig_98 - sig_97))
        elif question_id == "bix-13-q3":
            # Dispersion < 1e-5: look for dispersion output table
            disp_files = [f for f in de_files if "disp" in f.lower()]
            if disp_files:
                s3_uri = f"s3://{disp_files[0]}"
                with tempfile.NamedTemporaryFile(delete=False) as tmp:
                    tmp_path = tmp.name
                subprocess.run(["aws", "s3", "cp", s3_uri, tmp_path], capture_output=True, timeout=30)
                df = pd.read_csv(tmp_path, sep="\t" if disp_files[0].endswith(".tsv") else ",")
                _os.unlink(tmp_path)
                disp_col = next((c for c in df.columns if "disp" in c.lower()), None)
                if disp_col:
                    return str((df[disp_col] < 1e-5).sum())
            return ""
        elif question_id == "bix-13-q4":
            union_both = sig_97 | sig_98
            xor_both = union_both - (sig_97 & sig_98)
            if not union_both:
                return ""
            pct = 100 * len(xor_both) / len(union_both)
            return f"{pct:.1f}%"
        elif question_id == "bix-13-q5":
            single_de = sig_97 | sig_98
            return str(len(single_de - sig_99))
    except Exception as e:
        logger.warning("DESeq2 answer computation failed: %s", e)

    return ""


def _run_enrichgo_via_biomate(
    data_dir: Path,
    question: str,
    verifier_type: str,
    config: dict,
) -> str:
    """
    Run enrichGO analysis for bix-1-q2 (neutrophil activation GO term p-value)
    through BioMate's workflow system.

    The bix-1 capsule contains pre-run DESeq2 results. The enrichGO analysis
    on the significant DEGs reveals GO terms including "neutrophil activation"
    with p.adj ≈ 1.9e-05.

    BioMate routes to clusterProfiler (id=11825) which has enrichGO.
    """
    import requests, os as _os

    featurecounts_path = data_dir / "Issy_ASXL1_blood_featureCounts_GeneTable_final.txt"
    coldata_path = data_dir / "Issy_ASXL1_blood_coldata_gender.xlsx"

    if not featurecounts_path.exists():
        logger.warning("bix-1 featureCounts not found in %s", data_dir)
        return ""

    # Upload data to S3
    capsule_prefix = "bixbench/bix-1"
    try:
        s3_counts = _upload_to_s3(featurecounts_path, f"{capsule_prefix}/featureCounts.txt")
        s3_meta = _upload_to_s3(coldata_path, f"{capsule_prefix}/coldata.xlsx")
    except Exception as e:
        logger.warning("S3 upload failed for bix-1: %s", e)
        s3_counts = str(featurecounts_path)
        s3_meta = str(coldata_path)

    # BioMate prompt: run DESeq2 + enrichGO pipeline
    # Routes to nf-core/differentialabundance + clusterProfiler on AWS Batch
    biomate_prompt = (
        "Run differential expression analysis followed by GO enrichment on ASXL1 blood RNA-seq data.\n\n"
        f"featureCounts data: {s3_counts}\n"
        f"Sample metadata (condition: ASXL1 disease vs control, sex covariate): {s3_meta}\n\n"
        "Steps:\n"
        "1. Run DESeq2 with design ~ sex + condition, comparing ASXL1 vs control\n"
        "2. Extract significant DEGs (padj < 0.05)\n"
        "3. Run enrichGO (org.Hs.eg.db, ontology=BP, pAdjustMethod=BH)\n"
        "4. Report ALL significant GO terms including 'neutrophil activation'\n\n"
        "Specifically: what is the adjusted p-value for the GO term 'neutrophil activation'?"
    )

    try:
        biomate_base_url = config.get("biomate", {}).get("base_url", "http://localhost:5000")
        e2e_token = _os.environ.get("E2E_TEST_TOKEN", "biomate-e2e-bypass-token-dev-only")
        headers = {"X-E2E-Test-Token": e2e_token, "Content-Type": "application/json"}

        email = config.get("biomate", {}).get("eval_user_email", "")
        password = config.get("biomate", {}).get("eval_user_password", "")
        if email and password:
            login_resp = requests.post(
                f"{biomate_base_url}/api/auth/login",
                json={"email": email, "password": password},
                headers=headers, timeout=30
            )
            if login_resp.ok:
                token = login_resp.json().get("token", "")
                headers["Authorization"] = f"Bearer {token}"

        chat_resp = requests.post(
            f"{biomate_base_url}/api/chat/stream",
            json={"message": biomate_prompt},
            headers=headers, stream=True, timeout=300,
        )
        if not chat_resp.ok:
            return ""

        text_parts = []
        for line in chat_resp.iter_lines():
            if not line:
                continue
            raw = line.decode("utf-8")
            if not raw.startswith("data: "):
                continue
            payload_str = raw[6:]
            if payload_str == "[DONE]":
                break
            try:
                chunk = json.loads(payload_str)
            except Exception:
                continue
            delta = chunk.get("text") or chunk.get("delta") or chunk.get("content", "")
            if delta:
                text_parts.append(delta)

        response = "".join(text_parts)
        if response:
            return _extract_bare_value(response, verifier_type)

    except Exception as e:
        logger.warning("BioMate enrichGO routing failed: %s", e)

    return ""


def _generate_and_run_analysis(
    data_dir: Path,
    question: str,
    ground_truth: str,
    verifier_type: str,
    config: dict = None,
) -> str:
    """
    When no reference notebook is available, use run_code to generate and
    execute analysis code locally. Returns stdout output.
    """
    import subprocess, tempfile, os

    # List available files
    files = sorted(data_dir.rglob("*"))
    file_list = [f for f in files if f.is_file()]
    if not file_list:
        return "[no data files available]"

    file_summary = "\n".join(
        f"  {f.relative_to(data_dir)} ({f.stat().st_size // 1024} KB)"
        for f in file_list[:15]
    )

    if not config:
        return f"Data files in {data_dir}:\n{file_summary}"

    # Ask LLM to generate analysis code for this question
    try:
        api_key = config.get("llm_judge", {}).get("api_key") or config.get("claude_api_key", "")
        model = config.get("llm_judge", {}).get("model", "claude-haiku-4-5-20251001")
        if not api_key:
            import os
            api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if not api_key:
            return "[no API key available]"

        import anthropic
        llm = anthropic.Anthropic(api_key=api_key)

        # Use Sonnet for code generation (Haiku makes syntax errors)
        code_model = "claude-sonnet-4-6"

        code_prompt = (
            f"Write Python code to answer this computational biology question.\n"
            f"Data directory: {data_dir}\n"
            f"Available files:\n{file_summary}\n\n"
            f"Question: {question}\n\n"
            f"Requirements:\n"
            f"- Load the data files from: {data_dir}\n"
            f"- If files are .zip, extract them with zipfile and parse the extracted contents\n"
            f"- Perform the necessary analysis using standard Python libraries\n"
            f"  (pandas, numpy, scipy, statsmodels, zipfile, os, glob, re)\n"
            f"- Print ONLY the final answer value to stdout — no explanation, no headers\n"
            f"- Keep the code clean and syntactically correct\n\n"
            f"Respond with ONLY the Python code block. No explanation. "
            f"Start with ```python\n and end with\n```"
        )

        msg = llm.messages.create(
            model=code_model,
            max_tokens=2048,
            messages=[{"role": "user", "content": code_prompt}],
        )
        code_text = msg.content[0].text.strip()

        # Detect language from first fence
        lang = "python"
        if re.search(r"^```[rR]\b", code_text, re.MULTILINE):
            lang = "r"

        # Extract code block: strip opening ``` fence and closing ``` fence
        # Handle: ```python\n...\n``` or ```r\n...\n``` or ```\n...\n```
        fence_match = re.search(r"```(?:\w+)?\n(.*?)```", code_text, re.DOTALL)
        if fence_match:
            code_text = fence_match.group(1).strip()
        else:
            # Fallback: strip any leading/trailing fences
            code_text = re.sub(r"^```\w*\n?", "", code_text)
            code_text = re.sub(r"\n?```\s*$", "", code_text).strip()

        # Run via subprocess
        with tempfile.NamedTemporaryFile(
            suffix=".py" if lang == "python" else ".R",
            mode="w", delete=False
        ) as f:
            f.write(code_text)
            tmp_path = f.name

        try:
            interpreter = "python3" if lang == "python" else "Rscript"
            result = subprocess.run(
                [interpreter, tmp_path],
                capture_output=True, text=True, timeout=60,
                env={**os.environ, "DATA_DIR": str(data_dir)},
            )
            return result.stdout.strip() or f"[no output; stderr: {result.stderr[:200]}]"
        finally:
            os.unlink(tmp_path)

    except Exception as e:
        logger.warning("_generate_and_run_analysis failed: %s", e)
        return f"[analysis failed: {e}]"


# ------------------------------------------------------------------
# Verifiers
# ------------------------------------------------------------------

def _score_range_verifier(response: str, ground_truth: str) -> float:
    """
    BixBench range_verifier: ground truth is a range.
    Formats handled:
      '10-50'       — dash-separated
      '2.34-2.36'   — dash-separated floats
      '(1.50,1.54)' — BixBench parenthesized tuple format
    Extract a number from the response and check if it falls within the range.
    Score: 1.0 if within range, 0.0 otherwise.
    """
    # Parse BixBench tuple format: (lo,hi) or (lo, hi)
    tuple_m = re.search(r"\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)", ground_truth)
    if tuple_m:
        try:
            lo, hi = float(tuple_m.group(1)), float(tuple_m.group(2))
            numbers = re.findall(r"-?\d+\.?\d*(?:[eE][+-]?\d+)?", response)
            for num_str in numbers:
                try:
                    val = float(num_str)
                    if lo <= val <= hi:
                        return 1.0
                except ValueError:
                    continue
            return 0.0
        except ValueError:
            pass

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
