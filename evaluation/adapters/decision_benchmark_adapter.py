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
    from evaluation.scorers.decision_scorer import (
        score_decision, score_categorical_decision, score_set_decision,
        score_numeric_decision,
    )
    from evaluation.scorers.boin_scorer import score_mtd_decision
    from evaluation.scorers.chain_scorer import score_chain
except ImportError:  # pragma: no cover
    from scorers.decision_scorer import (  # type: ignore
        score_decision, score_categorical_decision, score_set_decision,
        score_numeric_decision,
    )
    from scorers.boin_scorer import score_mtd_decision  # type: ignore
    from scorers.chain_scorer import score_chain  # type: ignore

_DATASET_DIR = Path(__file__).parent.parent / "datasets" / "drugdev_export"

# Named decision-task datasets in the DrugDev series (archetype → jsonl). The runner
# iterates these; each is loadable on its own via config["dataset"].
DECISION_DATASETS = {
    "leadopt_triage":    _DATASET_DIR / "leadopt_triage" / "data.jsonl",     # archetype C
    "fep_selection":     _DATASET_DIR / "fep_selection" / "data.jsonl",      # archetype E
    "dose_decision":     _DATASET_DIR / "dose_decision" / "data.jsonl",      # archetype H
    "tissue_exposure":   _DATASET_DIR / "tissue_exposure" / "data.jsonl",    # archetype F2
    "special_population": _DATASET_DIR / "special_population" / "data.jsonl", # archetype F4
    "process_knowledge": _DATASET_DIR / "process_knowledge" / "data.jsonl",  # archetype P
    "workflow_chain":    _DATASET_DIR / "workflow_chain" / "data.jsonl",     # archetype W
    "dose_projection":   _DATASET_DIR / "dose_projection" / "data.jsonl",    # archetype F1/G
    "dose_schedule":     _DATASET_DIR / "dose_schedule" / "data.jsonl",      # archetype F3
}

_DEFAULT_DATASET = DECISION_DATASETS["leadopt_triage"]


class DecisionBenchmarkAdapter(BenchmarkAdapter):
    """Context-rich drug-development *decision* tasks, scored on the recommendation."""

    name = "decision_benchmark"

    def __init__(self, config: Dict[str, Any]):
        super().__init__(config)
        ds = (config or {}).get("dataset")
        if ds and str(ds) in DECISION_DATASETS:      # a named archetype dataset
            self._dataset_path = DECISION_DATASETS[str(ds)]
        elif ds:                                      # an explicit path
            self._dataset_path = Path(ds)
        else:
            self._dataset_path = _DEFAULT_DATASET
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
                    "scorer":     it.get("scorer", "decision"),
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
        """Dispatch to the scorer the task declares: 'mtd' (dose-escalation decision,
        via boin_scorer) or 'decision' (advance/deprioritize, via decision_scorer)."""
        kind = task.metadata.get("scorer", "decision")
        if kind == "mtd":
            return score_mtd_decision(agent_response, task.ground_truth)
        if kind == "categorical":
            return score_categorical_decision(agent_response, task.ground_truth)
        if kind == "set":
            return score_set_decision(agent_response, task.ground_truth)
        if kind == "chain":
            return score_chain(agent_response, task.ground_truth)
        if kind == "numeric":
            return score_numeric_decision(agent_response, task.ground_truth)
        return score_decision(agent_response, task.ground_truth, task.metadata.get("labels"))


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

    # ---- archetype E: FEP-guided selection (decision scorer) ----
    fep = DecisionBenchmarkAdapter(config={"dataset": "fep_selection"})
    ftasks = fep.load_tasks()
    ck("E: loads fep_selection", len(ftasks) == 2 and all("L1" in t.question for t in ftasks))
    ft = ftasks[0]
    fok = ("FEP shows L1 and L2 bind ~3 kcal/mol tighter than the lead; L5 is +3 kcal/mol "
           "weaker.\nDECISION:\n  advance: L1, L2\n  deprioritize: L5\n  primary_liability: weaker binding")
    ck("E: correct FEP selection → high score", fep.score(ft, fok) > 0.95)
    ck("E: advancing the weakest binder → low score",
       fep.score(ft, "DECISION:\n  advance: L5\n  deprioritize: L1\n  primary_liability: none") < 0.3)

    # ---- archetype H: dose-escalation MTD (mtd scorer) ----
    dose = DecisionBenchmarkAdapter(config={"dataset": "dose_decision"})
    dtasks = dose.load_tasks()
    ck("H: loads dose_decision (3 tasks, mtd scorer)",
       len(dtasks) == 3 and all(t.metadata["scorer"] == "mtd" for t in dtasks))
    d1 = next(t for t in dtasks if t.task_id == "DOSE-001")
    ck("H: correct MTD → high score",
       dose.score(d1, "The MTD is dose level 5 (150 mg).") == 1.0)
    d2 = next(t for t in dtasks if t.task_id == "DOSE-002")
    ck("H: 'MTD not reached' recognised → high score",
       dose.score(d2, "All tested doses were well tolerated; the MTD was not reached.") == 1.0)
    ck("H: naming a dose when MTD not reached → low score",
       dose.score(d2, "The MTD is dose level 3 (40 mg).") == 0.0)

    # ---- archetype F2: tissue/organ exposure (categorical scorer) ----
    tis = DecisionBenchmarkAdapter(config={"dataset": "tissue_exposure"})
    ttasks = tis.load_tasks()
    ck("F2: loads tissue_exposure (categorical)",
       len(ttasks) == 3 and all(t.metadata["scorer"] == "categorical" for t in ttasks))
    t01 = next(t for t in ttasks if t.task_id == "TISSUE-01")
    # The verdict words appear only as the two OFFERED enum choices in the format line
    # (both present ⇒ neither is singled out); the context must not assert the conclusion.
    ql = t01.question.lower()
    ck("F2: prompt offers both choices, does not assert the verdict",
       "reaches_target" in ql and "excluded" in ql
       and "is excluded" not in ql and "cns-excluded" not in ql)
    ck("F2: correct 'excluded' + P-gp rationale → high score",
       tis.score(t01, "P-gp efflux at the BBB limits brain exposure.\nverdict: excluded") > 0.9)
    ck("F2: wrong 'reaches_target' → low score",
       tis.score(t01, "verdict: reaches_target") < 0.2)

    # ---- archetype F4: special-population dose (categorical scorer) ----
    pop = DecisionBenchmarkAdapter(config={"dataset": "special_population"})
    ptasks = pop.load_tasks()
    ck("F4: loads special_population (4 tasks)", len(ptasks) == 4)
    p1 = next(t for t in ptasks if t.task_id == "POP-01")
    ck("F4: metformin eGFR 25 → contraindicated correct → high score",
       pop.score(p1, "Below eGFR 30 with lactic-acidosis risk in renal impairment, metformin is "
                     "contraindicated.\naction: avoid_or_contraindicated") > 0.9)
    p4 = next(t for t in ptasks if t.task_id == "POP-04")
    ck("F4: negative control (no_change) not over-adjusted → high score",
       pop.score(p4, "Acetaminophen is hepatically cleared; no renal dose adjustment.\n"
                     "action: no_change") > 0.9)
    ck("F4: over-adjusting the negative control → low score",
       pop.score(p4, "action: avoid_or_contraindicated") < 0.2)

    # ---- archetype P: process/stage knowledge (categorical + set) ----
    proc = DecisionBenchmarkAdapter(config={"dataset": "process_knowledge"})
    prtasks = proc.load_tasks()
    ck("P: loads process_knowledge (6 tasks, categorical+set)",
       len(prtasks) == 6 and {t.metadata["scorer"] for t in prtasks} == {"categorical", "set"})
    pind = next(t for t in prtasks if t.task_id == "PROC-02")
    ck("P: IND prerequisites set answered correctly → high score",
       proc.score(pind, "Phase 2 efficacy and the NDA come later.\nrequired: GLP toxicology, "
                        "CMC manufacturing, nonclinical pharmacology/PK package (2.6), "
                        "phase 1 clinical protocol. This is the IND package.") > 0.9)
    pseq = next(t for t in prtasks if t.task_id == "PROC-04")
    ck("P: 'Phase III before Phase I' → correct 'no'",
       proc.score(pseq, "No — Phase 1 must come first.\nverdict: no") > 0.9)

    # ---- archetype W: long workflow chains (chain scorer) ----
    chain = DecisionBenchmarkAdapter(config={"dataset": "workflow_chain"})
    ctasks = chain.load_tasks()
    ck("W: loads workflow_chain (3 chains)",
       len(ctasks) == 3 and all(t.metadata["scorer"] == "chain" for t in ctasks))
    crna = next(t for t in ctasks if t.task_id == "CHAIN-rnaseq")
    good_chain = ("From FASTQ:\nchain: QC/FastQC -> alignment (STAR) -> quantification "
                  "(featureCounts) -> differential expression (DESeq2) -> pathway enrichment "
                  "(enrichGO) -> report")
    ck("W: correct ordered RNA-seq chain → high score", chain.score(crna, good_chain) > 0.9)
    cremed = next(t for t in ctasks if t.task_id == "CHAIN-admet-remediation")
    bad_order = ("chain: decide to advance -> estimate PK -> re-screen ADMET -> redesign -> "
                 "initial ADMET screen for hERG")
    ck("W: reversed remediation loop → low order/gate score",
       chain.score(cremed, bad_order) < chain.score(cremed,
           "chain: ADMET screen flags hERG -> redesign the analogue -> re-screen ADMET to "
           "confirm the fix -> re-estimate PK (PBPK) -> advance/hold decision"))

    # ---- archetype F1/G: dose projection (numeric scorer) ----
    dp = DecisionBenchmarkAdapter(config={"dataset": "dose_projection"})
    dptasks = dp.load_tasks()
    ck("F1/G: loads dose_projection (3 numeric tasks)",
       len(dptasks) == 3 and all(t.metadata["scorer"] == "numeric" for t in dptasks))
    mrsd = next(t for t in dptasks if t.task_id == "DOSEPROJ-01")
    ck("F1/G: correct MRSD (0.81) within fold → high score",
       dp.score(mrsd, "HED = 50*6/37 = 8.1 mg/kg; with a safety factor of 10 from the NOAEL.\n"
                      "answer: MRSD 0.81 mg/kg") > 0.95)
    ck("F1/G: wrong MRSD (50) → low score",
       dp.score(mrsd, "answer: 50 mg/kg") < 0.2)

    # ---- archetype F3: dose schedule (categorical scorer) ----
    ds = DecisionBenchmarkAdapter(config={"dataset": "dose_schedule"})
    dstasks = ds.load_tasks()
    ck("F3: loads dose_schedule (3 tasks)", len(dstasks) == 3)
    beta = next(t for t in dstasks if t.task_id == "SCHED-01")
    ck("F3: beta-lactam → frequent/continuous correct",
       ds.score(beta, "Time>MIC-driven, so maximize time above MIC.\n"
                      "verdict: frequent_or_continuous") > 0.9)
    amino = next(t for t in dstasks if t.task_id == "SCHED-02")
    ck("F3: aminoglycoside → extended-interval correct, not frequent",
       ds.score(amino, "Concentration-dependent with a high peak target.\n"
                       "verdict: high_dose_extended_interval") > 0.9
       and ds.score(amino, "verdict: frequent_or_continuous") < 0.2)

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
