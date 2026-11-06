"""
Tests for decomposition + flow-pattern selection (Part A).

Proves the harness recovers PARALLEL structure the live composer collapses away,
infers dependency edges deterministically from I/O handoff, validates plans before
the DAG engine, emits the benchmark/engine plan shape, and that the StructureVerifier
scores that plan the way evaluation/datasets/decomposition_v2/score.py does and
routes through the P0 verifier bridge.

Run:  python3 grounded-prototype/tests/test_decompose.py
"""

import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

from research.decompose import (  # noqa: E402
    SubTask, infer_edges, build_plan, validate_plan, structure_of, select_pattern,
    SINGLE, PARALLEL, SEQUENTIAL, ITERATIVE_QC,
)
from research.verifiers import StructureVerifier, select_verifier  # noqa: E402

_R = []


def ck(name, cond):
    print(("PASS" if cond else "FAIL"), "-", name)
    _R.append(cond)


def _raises(fn):
    try:
        fn()
        return False
    except Exception:
        return True


# ── independent sub-tasks with no handoff => PARALLEL (the over-collapse fix) ──
indep = [
    SubTask("ADMET screen of the hit series", order=1),
    SubTask("Molecular docking of the hit series", order=2),
    SubTask("PK/PD modelling of the lead", order=3),
]
p_indep = build_plan(indep)
ck("no I/O handoff -> every node is a parallel root",
   all(n["depends_on"] == [] for n in p_indep))
ck("independent goal classifies PARALLEL", structure_of(p_indep) == PARALLEL)
ck("select_pattern returns PARALLEL for independent multi-task",
   select_pattern("Run ADMET, docking and PK in parallel", p_indep) == PARALLEL)

# ── genuine data handoff => SEQUENTIAL edges inferred from produces/consumes ──
chain = [
    SubTask("Align reads", order=1, produces=["bam"]),
    SubTask("Call variants", order=2, produces=["vcf"], consumes=["bam"]),
    SubTask("Annotate variants", order=3, consumes=["vcf"]),
]
edges = infer_edges(chain)
ck("variant-calling consumes alignment output -> edge 1->2", edges[2] == [1])
ck("annotation consumes variant output -> edge 2->3", edges[3] == [2])
p_chain = build_plan(chain)
ck("handoff chain classifies SEQUENTIAL", structure_of(p_chain) == SEQUENTIAL)

# ── mixed: a parallel pair that both feed a join ──
mixed = [
    SubTask("Bulk RNA-seq quant", order=1, produces=["counts_bulk"]),
    SubTask("scRNA-seq quant", order=2, produces=["counts_sc"]),
    SubTask("Multi-omics integration", order=3, consumes=["counts_bulk", "counts_sc"]),
]
p_mixed = build_plan(mixed)
ck("join node depends on BOTH parallel producers", p_mixed[2]["depends_on"] == [1, 2])
ck("fan-in classifies MIXED", structure_of(p_mixed) == "mixed")

# ── single and iterative-QC overlays ──
ck("single-node plan -> SINGLE",
   select_pattern("Run nf-core/rnaseq", build_plan([SubTask("rnaseq", 1)])) == SINGLE)
ck("QC-loop goal -> ITERATIVE_QC regardless of topology",
   select_pattern("run ADMET and remediate until it passes the hERG gate", p_indep) == ITERATIVE_QC)

# ── validation guardrails (deterministic, before the DAG engine) ──
ck("dangling depends_on raises",
   _raises(lambda: validate_plan([{"sub_task": "x", "order": 1, "depends_on": [9]}])))
ck("self-dependency raises",
   _raises(lambda: validate_plan([{"sub_task": "x", "order": 1, "depends_on": [1]}])))
ck("a cycle raises", _raises(lambda: validate_plan([
    {"sub_task": "a", "order": 1, "depends_on": [2]},
    {"sub_task": "b", "order": 2, "depends_on": [1]},
])))

# ── injectable depends_fn (the LLM override for prose-only handoff) ──
p_llm = build_plan(indep, depends_fn=lambda sts: {1: [], 2: [1], 3: [2]})
ck("depends_fn override drives the plan edges", structure_of(p_llm) == SEQUENTIAL)

# ── StructureVerifier mirrors decomposition_v2/score.py on the emitted plan ──
sv = StructureVerifier()
gold = {"gold_subtasks": [
    {"sub_task": "Align reads", "order": 1, "depends_on": [], "domain": "genomics"},
    {"sub_task": "Call variants", "order": 2, "depends_on": [1], "domain": "variant_calling"},
    {"sub_task": "Annotate variants", "order": 3, "depends_on": [2], "domain": "variant_calling"},
]}
ck("exact plan scores high", sv.score(gold, json.dumps(p_chain)) > 0.9)
# a wrong-structure answer (everything parallel) must score below the exact plan
wrong = [{"sub_task": s["sub_task"], "order": s["order"], "depends_on": []} for s in p_chain]
ck("collapsing the chain to all-parallel scores strictly worse",
   sv.score(gold, json.dumps(wrong)) < sv.score(gold, json.dumps(p_chain)))
ck("non-JSON response scores 0", sv.score(gold, "I cannot decompose this") == 0.0)

# ── P0 verifier bridge routes a decomposition task to the (real or mirror) decomp scorer ──
_v = select_verifier(gold)
ck("select_verifier routes a gold_subtasks task to a decomposition scorer",
   _v.name in ("decomp_structure_real", "decomp_structure") and _v.answer_free is False)


if __name__ == "__main__":
    passed = sum(1 for c in _R if c)
    print(f"\n{passed}/{len(_R)} passed")
    sys.exit(0 if passed == len(_R) else 1)
