"""
decision_benchmark_adapter.py
-----------------------------
Adapter for the *practical / context-rich* DrugDev benchmark tasks — the decision
archetypes (lead-op triage, target go/no-go, hit triage, dose selection, …) rather
than tool-routing. Each task is a project vignette: the data a scientist has, the
constraint, and the decision required. The agent runs the relevant BioMate workflow
and returns a recommendation; this adapter scores the DECISION via decision_scorer
(the real run itself is graded end-to-end by execution_grader in the L5–L6 path).

One adapter serves any decision-task dataset (a jsonl of items with `context`,
`compounds`/`inputs`, `decision_required`, `ground_truth`). Point it at a dataset via
config["dataset"] or the `dataset` kwarg; defaults to the lead-op triage exemplar.

Gold item shape (see evaluation/datasets/drugdev_export/leadopt_triage/data.jsonl):
  { id, stage, archetype, difficulty, title, context,
    compounds:[{label, admet_case_id|smiles, name}], decision_required,
    ground_truth:{advance_best, deprioritize, primary_liability, liability_aliases,
                  rationale_must_mention},
    evidence:{...}  # real measured values behind the decision (audit/provenance) }

CPU self-test (no live stack):
    python3 evaluation/adapters/decision_benchmark_adapter.py --selftest
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from evaluation.core.base_adapter import BenchmarkAdapter, BenchmarkTask

try:
    from evaluation.scorers.decision_scorer import score_decision
except ImportError:  # pragma: no cover
    from scorers.decision_scorer import score_decision  # type: ignore

_DEFAULT_DATASET = (
    Path(__file__).parent.parent
    / "datasets" / "drugdev_export" / "leadopt_triage" / "data.jsonl"
)


class DecisionBenchmarkAdapter(BenchmarkAdapter):
    """Context-rich drug-development *decision* tasks, scored on the recommendation."""

    name = "decision_benchmark"

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        ds = (config or {}).get("dataset")
        self._dataset_path = Path(ds) if ds else _DEFAULT_DATASET
        self._items: Optional[List[dict]] = None

    def _load(self) -> List[dict]:
        if self._items is None:
            with open(self._dataset_path) as f:
                self._items = [json.loads(line) for line in f if line.strip()]
        return self._items

    # ------------------------------------------------------------------
    def load_tasks(self) -> List[BenchmarkTask]:
        tasks: List[BenchmarkTask] = []
        for it in self._load():
            gt = it["ground_truth"]
            labels = [c["label"] for c in it.get("compounds", [])] or \
                sorted(set(gt.get("advance_best", [])) | set(gt.get("deprioritize", [])))
            tasks.append(BenchmarkTask(
                task_id=it["id"],
                question=self._render(it),
                ground_truth=gt,
                domain="drug_discovery",
                difficulty=it.get("difficulty", "medium"),
                task_type="reasoning",
                answer_type="open",
                metadata={
                    "benchmark":  self.name,
                    "archetype":  it.get("archetype"),
                    "stage":      it.get("stage"),
                    "labels":     labels,
                    "compounds":  it.get("compounds", []),
                    "evidence":   it.get("evidence", {}),
                },
            ))
        return tasks

    def _render(self, it: dict) -> str:
        """Render the project vignette sent to BioMate."""
        lines = [it.get("context", "").strip(), ""]
        if it.get("compounds"):
            lines.append("Candidate compounds:")
            for c in it["compounds"]:
                ref = c.get("smiles") or c.get("admet_case_id") or ""
                lines.append(f"  {c['label']}: {c.get('name', c['label'])}"
                             + (f"  [{ref}]" if ref else ""))
            lines.append("")
        lines.append(it.get("decision_required", "").strip())
        return "\n".join(lines).strip()

    def task_prompt(self, task: BenchmarkTask) -> str:
        return task.question

    # ------------------------------------------------------------------
    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        return float(self.score_detailed(task, agent_response)["score"])

    def score_detailed(self, task: BenchmarkTask, agent_response: str) -> Dict[str, Any]:
        labels = task.metadata.get("labels")
        return score_decision(agent_response, task.ground_truth, labels)


# ---------------------------------------------------------------------------
def _selftest() -> int:
    R: List[bool] = []

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name)
        R.append(bool(cond))

    adapter = DecisionBenchmarkAdapter(config={})
    tasks = adapter.load_tasks()
    ck("loads the lead-op triage exemplar (3 tasks)", len(tasks) == 3)
    ck("difficulties span easy→hard",
       {t.difficulty for t in tasks} == {"easy", "medium", "hard"})

    easy = next(t for t in tasks if t.difficulty == "easy")
    ck("prompt carries the vignette context + compounds + decision ask",
       "congeneric series" in easy.question and "C3" in easy.question
       and "DECISION" in easy.question)
    ck("ground truth hidden from prompt (no 'Terfenadine'/IC50 leak)",
       "terfenadine" not in easy.question.lower() and "0.2" not in easy.question)

    # a correct recommendation scores high
    good = ("Ran ADMET across the series. C3 shows a hERG IC50 of 0.2 µM — a clear "
            "cardiotox/QT liability — while C1, C2, C4 are hERG-safe.\n"
            "DECISION:\n  advance: C1, C2, C4\n  deprioritize: C3\n  primary_liability: hERG")
    sg = adapter.score(easy, good)
    ck("correct recommendation → high score", sg > 0.95)

    # dropping a clean compound and advancing the liability → low
    bad = ("DECISION:\n  advance: C3\n  deprioritize: C1\n  primary_liability: solubility")
    sb = adapter.score(easy, bad)
    ck("advancing the liability compound → low score", sb < 0.3)

    hard = next(t for t in tasks if t.difficulty == "hard")
    hd = ("C3 stacks Ames-positive genotoxicity, DILI and a Ro5 failure — the worst "
          "profile. C1 and C4 have clean DILI/Ames and the widest hERG margins.\n"
          "DECISION:\n  advance: C1, C4\n  deprioritize: C3\n  primary_liability: genotoxicity")
    sh = adapter.score(hard, hd)
    ck("hard trade-off answered correctly → high score", sh > 0.9)

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
    _repo_root = Path(__file__).resolve().parent.parent.parent
    if str(_repo_root) not in sys.path:
        sys.path.insert(0, str(_repo_root))
    sys.exit(main())
