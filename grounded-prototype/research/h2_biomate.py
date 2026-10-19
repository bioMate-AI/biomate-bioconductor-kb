"""
BioMate integration of Harness² — REUSING the vendored method (research/vendor/
harness2/), not reimplementing it.

This is the `BenchmarkAdapter` + `Proposer` seam that harness2/core/spec.py
documents. It plugs BioMate's deep-research controller in as the *substrate*
(the executor rollout) and the Grounded trust lattice in as the *answer-free
selection signal*, so Google's real recursion / proposer / selection / library
code drives the improvement. Modeled on the upstream `harness2.demo` adapter.

The editable harness here is a c1..c8 tree whose relevant files are:
  * systemprompt.md              — the research system prompt
  * scripts/route_table.json     — the router's intent->source-kind table (kinds_override)
  * scripts/budget.json          — retrieval budget (sources/subq, rounds)

Harness2 proposes edits to these; execute() runs the research controller under
the edited harness; selection picks blindly by the tiered-citation count in the
deliverables (never ground truth); the library banks the lesson.

Run under Python >=3.12 (the vendored core's floor). Governance: adopting the
resulting route table into production stays a human decision (see demo).
"""

from __future__ import annotations

import ast
import json
import os
import sys
from pathlib import Path

# Make the vendored harness2 importable.
_VENDOR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")
if _VENDOR not in sys.path:
    sys.path.insert(0, _VENDOR)

from harness2.core import tree                                   # noqa: E402
from harness2.core.proposer import Proposer, Reply               # noqa: E402
from harness2.core.spec import BenchPrompts, BenchSpec, ChannelSpec  # noqa: E402
from harness2.substrate.opencode import OpencodeSubstrate        # noqa: E402

from engine import to_markdown                                   # noqa: E402
from engine.domains import get_corpus                            # noqa: E402
from engine.retrieve import retrieve as _retrieve                # noqa: E402
from .controller import Budget, Verdict, research                # noqa: E402
from .verifiers import select_verifier                           # noqa: E402

_CMC = get_corpus("cmc")

# Research tasks (one "domain" of biomedical questions). A task may carry
# `ground_truth` -> the loop scores it answer-BASED (a real verifier); without it,
# scoring is answer-FREE (the trust lattice). This is the P0 verifier bridge.
_TASKS = {
    "admet-impurity": ("What are the ADMET and regulatory risks of a mutagenic "
                       "impurity, and how are its acceptable limits justified?"),
    "herg-cardiac": ("What governs hERG cardiac safety assessment, and is there a "
                     "fixed regulatory threshold a compound must pass?"),
    "m7-limit-value": ("What is the acceptable intake (TTC) for a mutagenic "
                       "impurity under ICH M7?"),
}

# ground_truth shape mirrors BioMate's eval tasks; present => answer-based scoring.
_GROUND_TRUTH = {
    "m7-limit-value": {"expected_params": {"TTC": "1.5"}, "must_not_fill": []},
}


def _retrieve_fn(source_id: str, subq: str):
    scored, _ = _retrieve(subq, _CMC, requesting_user="h2", limit=2, min_score=0.5)
    return [s.source for s in scored]


def _tiered_citations(markdown: str) -> int:
    """Answer-free quality signal: count Tier-A/B citation markers in a deliverable."""
    return markdown.count("[A·") + markdown.count("[B·")  # [A· / [B·


# The harness config lives in scripts/route_table.py (a .py file is on the
# editable surface; .json is not). We read it by SAFELY parsing module-level
# assignments with ast — never exec'ing the (possibly edited) file.
_CONFIG_TEMPLATE = (
    "# Research harness config — edited by Harness2's proposer.\n"
    "ROUTE_TABLE = {route_table}\n"
    "BUDGET = {budget}\n"
)


def _write_config(route_table: dict, budget: dict) -> str:
    return _CONFIG_TEMPLATE.format(route_table=json.dumps(route_table),
                                   budget=json.dumps(budget))


def _parse_config(text: str):
    route_table: dict = {}
    budget: dict = {}
    try:
        for node in ast.parse(text).body:
            if (isinstance(node, ast.Assign) and len(node.targets) == 1
                    and isinstance(node.targets[0], ast.Name)):
                name = node.targets[0].id
                if name == "ROUTE_TABLE":
                    route_table = ast.literal_eval(node.value)
                elif name == "BUDGET":
                    budget = ast.literal_eval(node.value)
    except (SyntaxError, ValueError):
        pass
    return route_table, budget


# ── DOM component: an editable SKILL (the only editable-as-data BioMate surface).
# The skill carries the ADMET evidence-routing knowledge as prose Harness2 edits.
_SKILL_REL = "skills/admet-evidence/SKILL.md"
_SKILL_TEMPLATE = (
    "---\n"
    "name: admet-evidence\n"
    "description: Evidence sources for ADMET and regulatory impurity questions.\n"
    "---\n"
    "# ADMET evidence routing\n"
    "For an ADMET or impurity question, consult these source kinds (comma-separated):\n"
    "sources: {sources}\n"
)


def _write_skill(sources: List[str]) -> str:
    return _SKILL_TEMPLATE.format(sources=", ".join(sources))


def _parse_skill_sources(text: str) -> List[str]:
    for line in text.splitlines():
        s = line.strip()
        if s.lower().startswith("sources:"):
            return [t.strip() for t in s.split(":", 1)[1].split(",") if t.strip()]
    return []


def _read_opt(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


class BioMateResearchAdapter:
    """Implements harness2.core.spec.BenchmarkAdapter over the research controller."""

    def __init__(self, root: Path):
        self.root = Path(root)
        self.substrate = OpencodeSubstrate()
        channel = ChannelSpec("opencode", "local/deterministic")
        self.spec = BenchSpec(
            name="biomate-research",
            runs_root=self.root / "runs",
            install_mode="workspace_config",
            prompts=BenchPrompts(work="answer a biomedical question with cited, tiered evidence"),
            channels={"proposer": channel, "selector": channel},
        )
        self.execution_count = 0
        base = {name: "" for name in self.substrate.surface().always_on}
        base["systemprompt.md"] = "Answer with tiered, cited evidence; flag gaps honestly.\n"
        base["scripts/route_table.py"] = _write_config(
            {}, {"max_sources_per_subq": 3, "max_rounds": 1})  # INV knob: budget
        base[_SKILL_REL] = _write_skill(  # DOM knob: ADMET evidence routing (a skill)
            ["knowledge_base", "regulatory", "publication", "patent"])
        tree.write_tree(self.substrate.surface(), base, self.base_harness(), stubs=False)

    # ── BenchmarkAdapter protocol ────────────────────────────────────────────
    def tasks(self, split: str = "all") -> list[str]:
        return list(_TASKS)

    def domain_of(self, task_id: str) -> str:
        return "biomedical_research"

    def task_prompt(self, task_id: str) -> str:
        return _TASKS[task_id]

    def task_files(self, task_id: str) -> Path:
        p = self.root / "sources" / task_id
        p.mkdir(parents=True, exist_ok=True)
        (p / "question.txt").write_text(_TASKS[task_id], encoding="utf-8")
        return p

    def base_harness(self) -> Path:
        return self.root / "base"

    def validate_tree(self, harness: "tree.Tree") -> None:
        if "scripts/route_table.py" not in harness:
            raise ValueError("The research executor requires scripts/route_table.py")

    def _config(self, harness_dir: Path | None):
        hd = Path(harness_dir or self.base_harness())

        def _read(rel):  # omitted-is-inherited: fall back to base for untouched files
            p = hd / rel
            if not p.is_file():
                p = self.base_harness() / rel
            return p.read_text(encoding="utf-8") if p.is_file() else ""

        kinds, bg = _parse_config(_read("scripts/route_table.py"))   # INV: budget (+ overrides)
        budget = Budget(max_sources_per_subq=int(bg.get("max_sources_per_subq", 3)),
                        max_rounds=int(bg.get("max_rounds", 1)))
        # DOM: the admet-evidence SKILL supplies the ADMET source-kind routing.
        skill_sources = _parse_skill_sources(_read(_SKILL_REL))
        if skill_sources:
            kinds = {**kinds, "admet": skill_sources}
        return kinds, budget

    def execute(self, task_id, harness_dir, run_id, *, timeout=None) -> Path:
        self.execution_count += 1
        kinds, budget = self._config(harness_dir)
        res = research(_TASKS[task_id], user="h2", retrieve_fn=_retrieve_fn,
                       decompose_fn=lambda q: [q],
                       assess_fn=lambda q, ev: Verdict(sufficient=True),
                       budget=budget, kinds_override=kinds or None)
        answer_md = to_markdown(res.answer)
        run_dir = self.root / "executions" / run_id
        run_dir.mkdir(parents=True, exist_ok=True)
        (run_dir / "answer.txt").write_text(answer_md, encoding="utf-8")
        traj = "[ACTION] route+retrieve+synthesize\n[OBSERVATION]\n" + "\n".join(
            f"round {t.round}: {t.retrievals} retrievals, +{t.new_authoritative} authoritative"
            for t in res.trace) + "\n"
        (run_dir / "trajectory.md").write_text(traj, encoding="utf-8")
        return run_dir

    def delivered(self, run_dir: Path) -> bool:
        return (run_dir / "answer.txt").is_file()

    def trajectory(self, run_dir: Path, *, obs_trunc: int) -> str:
        return (run_dir / "trajectory.md").read_text(encoding="utf-8")

    def deliverable_text(self, run_dir: Path) -> str:
        return (run_dir / "answer.txt").read_text(encoding="utf-8")

    def deliverable_files(self, run_dir: Path) -> dict:
        return {"answer.txt": self.deliverable_text(run_dir)}

    def score(self, run_dir: Path, task_id: str) -> dict:
        """Harness2 judge hook — called ONLY post-selection, for reporting/library
        (selection itself stays blind). The P0 bridge: BioMate's real ground-truth
        verifier when the task has one, else the answer-free trust lattice. Swap in
        the production scorers (evaluation/scorers/*) by implementing the same
        Verifier.score(ground_truth, response) signature."""
        deliverable = self.deliverable_text(run_dir)
        gt = _GROUND_TRUTH.get(task_id)
        verifier = select_verifier(gt)
        value = verifier.score(gt, deliverable)
        return {"score": round(float(value), 4), "verifier": verifier.name,
                "answer_free": verifier.answer_free}


class BioMateProposer(Proposer):
    """Scripted proposer/selector (stands in for an LLM channel, like DemoProposer).

    * propose  -> edit scripts/route_table.json (broaden a use-case's source kinds)
    * select.* -> BLIND: pick the deliverable with the most Tier-A/B citations
                  (the Grounded trust-lattice signal; never a ground-truth answer)
    * experience.* -> bank a lesson when the harness actually changed
    """

    def call(self, mission, context_dir, label, **kwargs) -> Reply:
        ctx = Path(context_dir)
        workspace = None
        if label.startswith("select."):
            best, best_n = None, -1
            for p in sorted((ctx / "candidates").glob("*.md")):
                n = _tiered_citations(p.read_text(encoding="utf-8"))
                if n > best_n:
                    best_n, best = n, p.stem
            text = (f"<why>Most authoritative tiered citations ({best_n}).</why>\n"
                    f"```choice\n{best}\n```")
        elif label.startswith("experience."):
            changed = (_read_opt(ctx / "harness" / _SKILL_REL)
                       != _read_opt(ctx / "base_harness" / _SKILL_REL))
            text = (
                "<experience>\ncue: biomedical ADMET/regulatory questions\n"
                "lesson: broaden the admet-evidence SKILL to include clinical sources.\n"
                "evidence: the probe deliverable carried more Tier-A/B citations than the base.\n"
                "confidence: moderate (observed citation contrast)\n</experience>"
                if changed else "NO_ENTRY"
            )
        else:
            # Propose a DOM edit: broaden the editable admet-evidence SKILL.
            workspace = ctx / "harness"
            skill_path = workspace / _SKILL_REL
            sources = _parse_skill_sources(_read_opt(skill_path)) or [
                "knowledge_base", "regulatory", "publication", "patent"]
            if "clinical" not in sources:
                sources = sources + ["clinical"]
            skill_path.parent.mkdir(parents=True, exist_ok=True)
            skill_path.write_text(_write_skill(sources), encoding="utf-8")
            text = "<notes>Broadened the admet-evidence SKILL to include clinical sources.</notes>"
        reply = Reply(label=label, text=text, ok=True, attempts=1, workspace=workspace)
        self._calls.append(reply)
        return reply
