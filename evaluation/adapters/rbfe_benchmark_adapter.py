"""
rbfe_benchmark_adapter.py
-------------------------
N1 RBFE / FEP Benchmark — Stage S3 (Lead Optimization).

Tests the full chain for relative binding free-energy prediction on a congeneric
ligand series:

  L1–L4 (routing + prerequisite detection), scored offline from the agent's text:
    complete          — target + congeneric series given; expect routing to an
                        FEP/RBFE (or MM-GBSA) workflow and the target echoed back
    incomplete        — vague "optimise my lead series"; no ligands/structures;
                        expect BioMate to ask for the ligand series / reference
    negative_control  — wrong-domain query (RNA-seq); expect NOT routed to FEP

  L5–L6 (execution + ΔΔG accuracy), scored from a real run's output directory via
    rbfe_scorer.parse_rbfe_output() + rbfe_scorer.score_rbfe_series() against the
    series' experimental `reference` ΔΔG. Call score_execution(task, output_dir)
    from the runner's --layers L5L6 path after the openfe_rbfe / *_mmgbsa workflow
    completes on Batch. (The execution itself is live-stack; this adapter only
    selects, prompts, and scores — it does not launch Batch.)

Gold: evaluation/datasets/drugdev_export/rbfe_benchmark/data.jsonl
  8 congeneric series / 264 ligands, real experimental ΔΔG derived from the MIT
  Merck/Schindler FEP benchmark (see that dir's README for attribution).

CPU self-test (no live stack, no external data):
    python3 evaluation/adapters/rbfe_benchmark_adapter.py --selftest
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Union

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask

# Scorer lives in evaluation/scorers; import is resilient to the two common
# sys.path roots (repo root on path, or evaluation/ on path).
try:
    from evaluation.scorers.rbfe_scorer import parse_rbfe_output, score_rbfe_series
except ImportError:  # pragma: no cover - path fallback
    from scorers.rbfe_scorer import parse_rbfe_output, score_rbfe_series  # type: ignore

_DATASET_PATH = (
    Path(__file__).parent.parent
    / "datasets" / "drugdev_export" / "rbfe_benchmark" / "data.jsonl"
)

# ---------------------------------------------------------------------------
# Routing keywords (case-insensitive, any match = routed to a free-energy workflow)
# ---------------------------------------------------------------------------

_RBFE_WORKFLOW_KEYWORDS = [
    "openfe_rbfe",
    "amber_peptide_mmgbsa",
    "peptide_mmgbsa",
    "rbfe",
    "relative binding free energy",
    "free energy perturbation",
    "free-energy perturbation",
    "fep+",
    "fep ",
    " fep",
    "mm-gbsa",
    "mm/gbsa",
    "mmgbsa",
    "alchemical",
    "thermodynamic integration",
    "lead optimization",      # stage-level acceptable
    "lead optimisation",
]

# Softer signal — recognised the free-energy / affinity-ranking intent
_RBFE_RELATED_KEYWORDS = [
    "ddg",
    "delta delta g",
    "binding free energy",
    "binding affinity",
    "congeneric",
    "perturbation",
    "relative affinity",
    "affinity ranking",
]

# Negative control: an RNA-seq request must NOT route to a free-energy workflow
_RNASEQ_KEYWORDS = [
    "rnaseq", "rna-seq", "rna_seq", "differential expression",
    "deseq", "edger", "nf-core/rnaseq",
]

# Prereq detection — did BioMate ask for the ligand series / structures?
_PREREQ_QUESTION_KEYWORDS = [
    "ligand", "series", "reference ligand", "congeneric", "sdf", "structure",
    "structures", "smiles", "compounds", "which target", "what target",
    "provide", "share", "upload", "need", "missing", "?",
]


class RbfeBenchmarkAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for N1 RBFE / FEP (S3 lead optimisation).

    Generates 24 tasks: 8 congeneric series × 3 query types (complete / incomplete /
    negative_control) for L1–L4; L5–L6 ΔΔG accuracy scored via score_execution().
    """

    name = "rbfe_benchmark"

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        self._dataset: Optional[List[dict]] = None

    # ------------------------------------------------------------------
    # Dataset loading (jsonl — one congeneric series per line)
    # ------------------------------------------------------------------

    def _load_dataset(self) -> List[dict]:
        if self._dataset is None:
            with open(_DATASET_PATH) as f:
                self._dataset = [json.loads(line) for line in f if line.strip()]
        return self._dataset

    def load_tasks(self) -> List[BenchmarkTask]:
        """8 series × 3 query types = 24 tasks (L1–L4)."""
        tasks: List[BenchmarkTask] = []

        for series in self._load_dataset():
            sid       = series["id"]
            target    = series["target"]
            pdb       = series.get("pdb")
            ref_lig   = series.get("reference_ligand")
            reference = series.get("reference", {})
            n_lig     = series.get("n_ligands", len(reference))
            diff      = series.get("difficulty", "hard")

            common_meta = {
                "series_id":        sid,
                "target":           target,
                "pdb":              pdb,
                "reference_ligand": ref_lig,
                "n_ligands":        n_lig,
                "reference":        reference,   # experimental ΔΔG, for L5–L6
                "benchmark":        "rbfe_benchmark",
            }

            # ---- complete --------------------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{sid}_complete",
                question=(
                    f"I have a congeneric series of {n_lig} ligands against {target} "
                    f"(reference ligand {ref_lig}). Compute the relative binding free "
                    f"energies (ΔΔG) for the series."
                ),
                ground_truth={
                    "expected_routing": True,
                    "expected_workflow_type": "rbfe",
                    "expected_target": target,
                    "expected_prereq_ask": False,
                    "reference": reference,
                },
                domain="drug_discovery",
                difficulty=diff,
                task_type="workflow",
                answer_type="json",
                metadata={**common_meta, "query_type": "complete",
                          "expected_routing": True, "expected_prereq_ask": False},
            ))

            # ---- incomplete -----------------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{sid}_incomplete",
                question=(
                    "I want to rank my lead compounds by binding free energy before "
                    "picking which analogues to synthesise next."
                ),
                ground_truth={
                    "expected_routing": True,
                    "expected_workflow_type": "rbfe",
                    "expected_prereq_ask": True,
                    "reference": {},
                },
                domain="drug_discovery",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={**common_meta, "query_type": "incomplete",
                          "expected_routing": True, "expected_prereq_ask": True},
            ))

            # ---- negative_control -----------------------------------------
            tasks.append(BenchmarkTask(
                task_id=f"{sid}_negctrl",
                question=(
                    "Perform RNA-seq differential expression analysis on my FASTQ files"
                ),
                ground_truth={
                    "expected_routing": False,
                    "expected_workflow_type": "rnaseq",
                    "expected_prereq_ask": False,
                    "reference": {},
                },
                domain="transcriptomics",
                difficulty="easy",
                task_type="workflow",
                answer_type="json",
                metadata={**common_meta, "query_type": "negative_control",
                          "expected_routing": False, "expected_prereq_ask": False},
            ))

        return tasks

    # ------------------------------------------------------------------
    # Prompt rendering
    # ------------------------------------------------------------------

    def task_prompt(self, task: BenchmarkTask) -> str:
        return task.question

    # ------------------------------------------------------------------
    # Scoring — L1–L4 (offline, from agent text)
    # ------------------------------------------------------------------

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        query_type = task.metadata.get("query_type", "")
        if query_type == "complete":
            return self._score_complete(task, agent_response)
        if query_type == "incomplete":
            return self._score_incomplete(task, agent_response)
        if query_type == "negative_control":
            return self._score_negative_control(task, agent_response)
        return 0.0

    def _score_complete(self, task: BenchmarkTask, response: str) -> float:
        """0.6 × routing + 0.4 × target-echo."""
        routing = self.score_routing(response, task)
        target  = self.score_target_extraction(response, task)
        return 0.6 * routing + 0.4 * target

    def _score_incomplete(self, task: BenchmarkTask, response: str) -> float:
        """Pass if BioMate asks for the ligand series / structures before running."""
        if self._response_asks_for_series(response):
            return 1.0
        # Proceeding to a ΔΔG calc without the ligands is a failure
        if self._response_routed_to_rbfe(response):
            return 0.0
        if any(kw in response.lower() for kw in _RBFE_RELATED_KEYWORDS):
            return 0.5
        return 0.0

    def _score_negative_control(self, task: BenchmarkTask, response: str) -> float:
        """1.0 = routed to rnaseq, 0.0 = wrongly routed to RBFE, else 0.5."""
        if self._response_routed_to_rbfe(response):
            return 0.0
        if any(kw in response.lower() for kw in _RNASEQ_KEYWORDS):
            return 1.0
        return 0.5

    # ------------------------------------------------------------------
    # Scoring — L5–L6 (execution + ΔΔG accuracy, from a real run's output dir)
    # ------------------------------------------------------------------

    def score_execution(
        self, task: BenchmarkTask, output_dir: Union[str, Path],
        *, within_kcal: float = 1.0,
    ) -> Dict[str, Any]:
        """
        Score a completed FEP/MM-GBSA run against the series' experimental ΔΔG.

        `output_dir` is the real run's output directory (ddg_results.csv / .json etc.);
        parse_rbfe_output reads it. Returns the full rbfe_scorer metric dict augmented
        with execution flags. Called from the runner's L5L6 path — NOT from run()
        (which only has the agent's text).
        """
        reference = task.metadata.get("reference") or task.ground_truth.get("reference", {})
        predicted = parse_rbfe_output(output_dir)
        metrics = score_rbfe_series(predicted, reference, within_kcal=within_kcal)
        metrics["ran"] = len(predicted) > 0
        metrics["produced_valid_ddg"] = metrics["n"] > 0
        metrics["coverage"] = (metrics["n"] / len(reference)) if reference else 0.0
        return metrics

    # ------------------------------------------------------------------
    # Sub-scorers
    # ------------------------------------------------------------------

    def score_routing(self, response: str, task: BenchmarkTask) -> float:
        """1.0 routed to a free-energy workflow, 0.5 soft signal, 0.0 none/wrong."""
        text = response.lower()

        routed_match = re.search(r"\[routed?:([^\]]+)\]", text)
        if routed_match:
            wf = routed_match.group(1)
            if any(kw in wf for kw in ["rbfe", "fep", "mmgbsa", "mm-gbsa",
                                       "free_energy", "free-energy", "alchem"]):
                return 1.0
            return 0.0

        if self._response_routed_to_rbfe(response):
            return 1.0
        if any(kw in text for kw in _RBFE_RELATED_KEYWORDS):
            return 0.5
        return 0.0

    def score_target_extraction(self, response: str, task: BenchmarkTask) -> float:
        """Did the agent echo the target (strong) or a related param (moderate)?"""
        target = str(task.metadata.get("target", "")).strip()
        if not target:
            return 0.0
        text = response.lower()
        if target.lower() in text:
            return 1.0
        if any(kw in text for kw in ["target", "congeneric", "reference ligand",
                                     "series", "ligand"]):
            return 0.5
        return 0.0

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _response_routed_to_rbfe(self, response: str) -> bool:
        text = response.lower()
        return any(kw.lower() in text for kw in _RBFE_WORKFLOW_KEYWORDS)

    def _response_asks_for_series(self, response: str) -> bool:
        text = response.lower()
        has_question = "?" in text or any(
            phrase in text for phrase in [
                "please provide", "can you provide", "could you", "i need",
                "what is the", "can you share", "do you have", "please share",
                "let me know", "tell me", "provide the", "upload", "which",
            ]
        )
        has_series_kw = any(kw in text for kw in _PREREQ_QUESTION_KEYWORDS)
        return has_question and has_series_kw

    # ------------------------------------------------------------------
    # Detailed per-task metadata for runner display
    # ------------------------------------------------------------------

    def score_detailed(self, task: BenchmarkTask, agent_response: str) -> Dict[str, Any]:
        query_type = task.metadata.get("query_type", "")
        result: Dict[str, Any] = {"query_type": query_type}

        if query_type == "complete":
            r = self.score_routing(agent_response, task)
            t = self.score_target_extraction(agent_response, task)
            result.update(routing_score=r, target_score=t,
                          composite=0.6 * r + 0.4 * t,
                          routed_ok=r >= 1.0, target_ok=t >= 1.0)
        elif query_type == "incomplete":
            asked = self._response_asks_for_series(agent_response)
            result.update(prereq_asked=asked, composite=1.0 if asked else 0.0)
        elif query_type == "negative_control":
            to_rbfe = self._response_routed_to_rbfe(agent_response)
            to_rnaseq = any(kw in agent_response.lower() for kw in _RNASEQ_KEYWORDS)
            result.update(routed_to_rbfe=to_rbfe, routed_to_rnaseq=to_rnaseq,
                          composite=0.0 if to_rbfe else (1.0 if to_rnaseq else 0.5))
        return result


# ---------------------------------------------------------------------------
# CPU self-test (no live stack, no Batch) — exercises load_tasks, L1–L4 score,
# and the L5–L6 score_execution path against a synthesised output dir.
# ---------------------------------------------------------------------------

def _selftest() -> int:
    import csv
    import tempfile

    R: List[bool] = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name)
        R.append(bool(cond))

    adapter = RbfeBenchmarkAdapter(config={})
    tasks = adapter.load_tasks()
    series = adapter._load_dataset()
    ck(f"load_tasks = 3 × {len(series)} series", len(tasks) == 3 * len(series))
    ck("every task carries a reference dict in metadata",
       all("reference" in t.metadata for t in tasks))

    complete = next(t for t in tasks if t.metadata["query_type"] == "complete")
    incomplete = next(t for t in tasks if t.metadata["query_type"] == "incomplete")
    negctrl = next(t for t in tasks if t.metadata["query_type"] == "negative_control")

    # L1–L4 routing
    tgt = complete.metadata["target"]
    good = f"[routed:openfe_rbfe] I'll run the RBFE free energy perturbation on {tgt}."
    ck("complete: routed+target → 1.0", adapter.score(complete, good) == 1.0)
    ck("complete: unrelated text → 0.0", adapter.score(complete, "Let's plot a heatmap.") == 0.0)

    ck("incomplete: asks for ligand series → 1.0",
       adapter.score(incomplete, "Which congeneric ligand series should I use? Please share the SDF.") == 1.0)
    ck("incomplete: silently runs RBFE → 0.0",
       adapter.score(incomplete, "Running openfe_rbfe now.") == 0.0)

    ck("negctrl: routes to rnaseq → 1.0",
       adapter.score(negctrl, "[routed:nf-core/rnaseq] running differential expression") == 1.0)
    ck("negctrl: wrongly routes to RBFE → 0.0",
       adapter.score(negctrl, "I'll run openfe_rbfe free energy perturbation.") == 0.0)

    # L5–L6 execution scoring against a synthesised run dir
    ref = complete.metadata["reference"]
    with tempfile.TemporaryDirectory() as td:
        # oracle output: predicted == experimental
        with open(Path(td) / "ddg_results.csv", "w", newline="") as f:
            w = csv.writer(f)
            w.writerow(["ligand", "ddg"])
            for lig, ddg in ref.items():
                w.writerow([lig, ddg])
        oracle = adapter.score_execution(complete, td)
        # Perfect prediction: rmse/mue 0, within 1.0, spearman 1.0, full coverage.
        # The composite `score` may sit just below 1.0 because the scorer's
        # Kendall-τ-a deflates on tied experimental ΔΔG (documented in rbfe_scorer);
        # accuracy signals are exact, so require score ≥ 0.95, not == 1.0.
        ck("score_execution oracle: ran, valid, full coverage, perfect accuracy, score ≥ 0.95",
           oracle["ran"] and oracle["produced_valid_ddg"]
           and abs(oracle["coverage"] - 1.0) < 1e-9
           and oracle["rmse"] == 0.0 and oracle["mue"] == 0.0
           and oracle["within_frac"] == 1.0 and oracle["spearman"] == 1.0
           and oracle["score"] >= 0.95)

    with tempfile.TemporaryDirectory() as td:
        empty = adapter.score_execution(complete, td)
        ck("score_execution empty dir: not ran, score 0.0",
           (not empty["ran"]) and empty["score"] == 0.0 and empty["n"] == 0)

    passed = sum(R)
    print(f"\n{passed}/{len(R)} passed")
    return 0 if passed == len(R) else 1


def main() -> int:
    import argparse
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--selftest", action="store_true", help="CPU self-test; no live stack")
    args = ap.parse_args()
    if args.selftest:
        return _selftest()
    ap.error("nothing to do; use --selftest (the adapter is driven by the runner)")


if __name__ == "__main__":
    import sys
    # Allow `python3 evaluation/adapters/rbfe_benchmark_adapter.py` from repo root
    _repo_root = Path(__file__).resolve().parent.parent.parent
    if str(_repo_root) not in sys.path:
        sys.path.insert(0, str(_repo_root))
    sys.exit(main())
