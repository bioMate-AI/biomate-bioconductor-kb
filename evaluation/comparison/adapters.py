#!/usr/bin/env python3
"""
Per-system adapter layer for the Phase-1 comparison harness.

Each adapter knows how to turn a TASK (from ``run_phase1.TASKS``) into the EXACT
invocation the corresponding system would receive — the literal chat request, the
agentic task string, or the coding-agent prompt. ``plan()`` is pure
string/dict construction: NO execution, NO API calls, NO spend. ``execute()`` is a
deliberate stub that raises, so nothing can run by accident.

The money gate lives in ``run_phase1.py``; this file never crosses it. The design
here mirrors the R0–R5 ladder and the SYSTEMS ceilings defined there — each adapter
declares the ``expected_max_rung`` its system class can reach on a given task (tier-
aware), so the plan is self-documenting before anyone spends a cent.

Runnable offline:
    python3 evaluation/comparison/adapters.py
"""
from __future__ import annotations

# Import the single source of truth for tasks / systems / ladder from the runner.
# (We never modify run_phase1.py; we only read its data structures.)
try:  # normal package-relative import
    from .run_phase1 import SYSTEMS, TASKS, LADDER, RUNG_INDEX, ladder_ceiling_for
except Exception:  # pragma: no cover - allow running as a bare script
    import os, sys
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from run_phase1 import SYSTEMS, TASKS, LADDER, RUNG_INDEX, ladder_ceiling_for  # type: ignore


# --------------------------------------------------------------------------- base
class Adapter:
    """Base per-system adapter.

    Subclasses set ``name`` (must match a key in ``run_phase1.SYSTEMS``) and
    implement ``_invocation(task)`` to build the EXACT prompt/command the system
    would receive. Everything else — the plan envelope, the expected ceiling, the
    execute() money-gate stub — is shared.
    """

    #: must match a key in run_phase1.SYSTEMS
    name: str = "base"

    def __init__(self):
        if self.name not in SYSTEMS:
            raise KeyError(
                f"adapter name {self.name!r} is not a key in run_phase1.SYSTEMS "
                f"({sorted(SYSTEMS)})"
            )
        self.spec = SYSTEMS[self.name]

    # -- the two required surfaces --------------------------------------------
    def plan(self, task: dict) -> dict:
        """Pure construction. Returns the execution plan for one task on this system.

        No side effects: builds strings/dicts only from ``task`` fields
        (``wf`` / ``inp`` / ``truth``) plus this system's static spec.
        """
        return {
            "system": self.name,
            "task_id": task["id"],
            "invocation": self._invocation(task),
            "allowed_methods": self.spec["methods"],
            "expected_max_rung": self._expected_max_rung(task),
            "notes": self._notes(task),
        }

    def execute(self, task: dict):
        """Deliberate stub — real execution is money-gated.

        Nothing in this scaffold may run a system for real. Wiring an actual
        executor here is the explicit, separately-authorized step before any
        paid run (see run_phase1.py's --execute + REALBIO_PHASE1_CONFIRM gate).
        """
        raise NotImplementedError(
            "real execution is money-gated; wire me before a paid run"
        )

    # -- shared helpers (override _invocation / _notes per system) -------------
    def _expected_max_rung(self, task: dict) -> str:
        """Class-max rung for this system on this task (tier-aware), from run_phase1."""
        return ladder_ceiling_for(task, self.name)

    def _invocation(self, task: dict) -> str:  # pragma: no cover - abstract
        raise NotImplementedError("subclasses build the exact invocation")

    def _notes(self, task: dict) -> str:
        return self.spec["methods"]

    # -- small utilities used to phrase invocations naturally ------------------
    @staticmethod
    def _humanize_wf(wf: str) -> str:
        """Turn a terse pipeline spec into a readable phrase.

        e.g. 'nf-core/rnaseq→differentialabundance→GSEA'
          -> 'nf-core/rnaseq then differentialabundance then GSEA'
        """
        return " then ".join(part.strip() for part in wf.split("→"))

    @staticmethod
    def _truth_as_goal(truth: str) -> str:
        """Phrase the truth-set metric as the deliverable to produce."""
        return truth.strip()


# --------------------------------------------------------------------- BioMate
class BioMateAdapter(Adapter):
    """BioMate — curated, QC-gated pipeline execution via the chat/workflow API.

    Invocation = the natural-language request a user actually types into BioMate's
    chat. BioMate routes it to an indexed/curated workflow, runs it on AWS Batch,
    applies QC gates, and returns a governed, reproducible result — hence the R5
    ceiling on CPU/DB tasks.
    """

    name = "biomate"

    def _invocation(self, task: dict) -> str:
        wf = self._humanize_wf(task["wf"])
        return (
            f"Run {wf} on {task['inp']}. "
            f"Report {self._truth_as_goal(task['truth'])}. "
            f"Use the appropriate curated workflow with QC gates, validate all "
            f"parameters against the schema, and give me a governed, reproducible "
            f"result with an audit trail and a downloadable methods report."
        )

    def _notes(self, task: dict) -> str:
        return (
            "Routed through BioMate chat -> curated/indexed workflow -> AWS Batch; "
            "QC-gated, param-validated, audit-trailed (R5-capable on CPU/DB tier)."
        )


# ----------------------------------------------------------------------- Biomni
class BiomniAdapter(Adapter):
    """Biomni — general biomedical agent. Invocation = an agentic task string.

    In-domain the agent can execute to a correct result (R4); it is not a governed,
    QC-gated pipeline, so it does not reach R5.
    """

    name = "biomni"

    def _invocation(self, task: dict) -> str:
        wf = self._humanize_wf(task["wf"])
        return (
            f"Task: {wf} on input {task['inp']}. "
            f"Objective (how you will be scored): {self._truth_as_goal(task['truth'])}. "
            f"Plan the analysis, select and run the appropriate tools autonomously, "
            f"and report the final metric with the evidence behind it."
        )

    def _notes(self, task: dict) -> str:
        return "Agentic biomedical execution (in-domain); R4 ceiling — not QC-governed (no R5)."


# ------------------------------------------------------- coding agents (shared)
class _CodeAgentAdapter(Adapter):
    """Shared prompt-builder for full-latitude coding agents (Claude Code / Codex).

    The prompt grants total latitude: install anything, write & run code, use any
    tool/DB, produce the exact metric the task's truth-set demands. Ceiling is R4
    on CPU/DB tasks and R2 on GPU tasks (infra/reliability, not a rule cap — see
    run_phase1.ladder_ceiling_for).
    """

    #: human label for the agent, used in the prompt preamble
    agent_label = "coding agent"

    def _invocation(self, task: dict) -> str:
        wf = self._humanize_wf(task["wf"])
        gpu_note = (
            " NOTE: this task normally needs a GPU — if none is available, do as much "
            "as you can on CPU and be explicit about what you could not run."
            if task["tier"] == "gpu"
            else ""
        )
        return (
            f"You are {self.agent_label} with FULL latitude. "
            f"Goal: run {wf} on {task['inp']} and produce this metric: "
            f"{self._truth_as_goal(task['truth'])}. "
            f"You may install whatever you need, write and run code, use any tool, "
            f"CLI, container, or database, and download public reference data. "
            f"There is no restriction on method — just produce the correct metric, "
            f"show the commands you ran, and report the final number.{gpu_note}"
        )

    def _notes(self, task: dict) -> str:
        if task["tier"] == "gpu":
            return "Full-latitude coding agent; GPU tier -> R2 ceiling (infra/reliability limited)."
        return "Full-latitude coding agent (install/code/run any tool/DB); R4 ceiling on CPU/DB."


class ClaudeCodeAdapter(_CodeAgentAdapter):
    name = "claude_code"
    agent_label = "Claude Code, a coding agent"


class CodexAdapter(_CodeAgentAdapter):
    name = "codex"
    agent_label = "Codex, a coding agent"


# --------------------------------------------------------------------- bare LLM
class BareLLMAdapter(Adapter):
    """Bare LLM — design-only. Invocation forbids execution.

    The model is asked to DESCRIBE the exact workflow, tools, and params — not to
    run anything. Ceiling is R1 (design) on execution tasks, and R4 only on the
    pure-reasoning task (T13, BOIN design), where the correct answer is derivable
    by reasoning alone. Both facts come from run_phase1.ladder_ceiling_for.
    """

    name = "bare_llm"

    def _invocation(self, task: dict) -> str:
        wf = self._humanize_wf(task["wf"])
        if task["id"] == "T13":
            # Pure-reasoning task: the correct answer IS derivable without execution.
            return (
                f"Design and DERIVE the answer for: {wf} on {task['inp']}. "
                f"Produce {self._truth_as_goal(task['truth'])} by reasoning. "
                f"Show the derivation. Do not run any external tool — reason it out."
            )
        return (
            f"Design only — DO NOT execute anything. For the task '{wf}' on "
            f"{task['inp']}, describe the exact workflow, the specific tools/packages, "
            f"and the precise parameters you would use to obtain "
            f"{self._truth_as_goal(task['truth'])}. "
            f"Give the plan and parameters; do not run code and do not fabricate results."
        )

    def _notes(self, task: dict) -> str:
        if task["id"] == "T13":
            return "Bare LLM; pure-reasoning task -> R4 achievable by derivation (no execution needed)."
        return "Bare LLM; design-only (no execution) -> R1 ceiling on execution tasks."


# --------------------------------------------------------------------- registry
ADAPTERS = {
    "biomate":     BioMateAdapter,
    "biomni":      BiomniAdapter,
    "claude_code": ClaudeCodeAdapter,
    "codex":       CodexAdapter,
    "bare_llm":    BareLLMAdapter,
}

# Sanity: every adapter name must be a real SYSTEMS key. (coscientist has no
# dedicated adapter in this phase — it only attempts chemistry tasks; it is left
# for a later phase and is intentionally absent from ADAPTERS.)
for _n, _cls in ADAPTERS.items():
    assert _n in SYSTEMS, f"{_n} not in run_phase1.SYSTEMS"
    assert _cls.name == _n, f"{_cls.__name__}.name ({_cls.name!r}) != registry key {_n!r}"


# --------------------------------------------------------------------- self-test
def _task_by_id(tid: str) -> dict:
    for t in TASKS:
        if t["id"] == tid:
            return t
    raise KeyError(tid)


if __name__ == "__main__":
    import json

    cpu_task = _task_by_id("T01")   # nf-core/rnaseq chain — representative CPU task
    gpu_task = _task_by_id("T08")   # cryo-EM — representative GPU (Phase-2) task
    # A pure-reasoning CPU task, to show the bare-LLM R4 special case:
    reasoning_task = _task_by_id("T13")

    print("=" * 78)
    print("Phase-1 adapters — plan() preview (NO execution, NO spend)")
    print("=" * 78)

    for label, task in (("CPU task", cpu_task), ("GPU task", gpu_task)):
        print(f"\n### {label}: {task['id']} — {task['wf']}")
        print(f"    input: {task['inp']}")
        print(f"    truth: {task['truth']}\n")
        for name, cls in ADAPTERS.items():
            plan = cls().plan(task)
            print(f"  --- {name} (expected_max_rung={plan['expected_max_rung']}) ---")
            print(f"      invocation: {plan['invocation']}")
            print(f"      notes:      {plan['notes']}")
        print()

    print("### Pure-reasoning special case:", reasoning_task["id"], "— bare_llm")
    plan = BareLLMAdapter().plan(reasoning_task)
    print(f"    expected_max_rung: {plan['expected_max_rung']}  (R4 on reasoning task)")
    print(f"    invocation: {plan['invocation']}")

    # Show one full plan() dict verbatim, to prove the envelope shape.
    print("\n### Full plan() dict (biomate on the CPU task):")
    print(json.dumps(BioMateAdapter().plan(cpu_task), indent=2))

    # execute() must ALWAYS raise — nothing may run by accident.
    print("\n### execute() money-gate stub check:")
    for name, cls in ADAPTERS.items():
        try:
            cls().execute(cpu_task)
        except NotImplementedError as e:
            print(f"  {name:<12} raised NotImplementedError: {e}")
        else:  # pragma: no cover - would be a bug
            raise AssertionError(f"{name}.execute did NOT raise — money gate broken!")

    # Hard asserts (fail loudly if anyone breaks the contract).
    for name, cls in ADAPTERS.items():
        a = cls()
        p = a.plan(cpu_task)
        assert set(p) == {
            "system", "task_id", "invocation", "allowed_methods",
            "expected_max_rung", "notes",
        }, f"{name}: wrong plan() keys: {sorted(p)}"
        assert p["system"] == name
        assert p["task_id"] == cpu_task["id"]
        assert isinstance(p["invocation"], str) and p["invocation"]
        assert p["expected_max_rung"] in RUNG_INDEX
        try:
            a.execute(cpu_task)
        except NotImplementedError:
            pass
        else:
            raise AssertionError(f"{name}.execute must raise NotImplementedError")

    print("\nAll asserts passed. plan() is pure; execute() is stubbed. No spend.")
