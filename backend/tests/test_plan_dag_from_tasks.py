"""plan_dag_from_tasks: the live caller of build_dag_plan (POST /api/ai_assistant/plan_dag).

The bulk RNA-seq + DIA proteomics request (external user, 2026-11-03) is a fork/join: per-layer
differential analyses in parallel, then integration. Chat used to drop that structure. These pin:
independent branches stay roots (not chained), fan-in dependencies are kept, unresolvable tasks
and untypeable handoffs refuse the plan with a reason, and fan-in edges without a data connection
are reported instead of implied.

Run: cd backend && PYTHONPATH=lib pytest tests/test_plan_dag_from_tasks.py -v
"""
from galaxy.ai.decomposed_dag import plan_dag_from_tasks

PATHS = {
    "rna": "bioc/deseq2_de/main.nf",
    "lysate": "bioc/limma_proteomics_de/main.nf",
    "secretome": "bioc/limma_proteomics_de/main.nf",
    "integrate": "bioc/mixomics_spls/main.nf",
}
TYPES = {
    "bioc/deseq2_de/main.nf": (["counts_matrix"], ["csv"]),
    "bioc/limma_proteomics_de/main.nf": (["tsv_proteins"], ["csv"]),
    "bioc/mixomics_spls/main.nf": (["csv"], ["csv"]),
}


class FakeAssistant:
    def __init__(self, unresolved=(), types=None):
        self.unresolved, self.types = set(unresolved), types or TYPES

    def _resolve_task_to_workflow(self, task):
        key = task["description"].split()[0]
        return None if key in self.unresolved else {"nextflow_path": PATHS[key], "parameters": {}}

    def _workflow_io_types(self, path):
        return self.types.get(path)


FORK_JOIN = [
    {"id": "rna", "description": "rna differential expression KO vs WT", "depends_on": []},
    {"id": "lys", "description": "lysate protein differential abundance", "depends_on": []},
    {"id": "sec", "description": "secretome protein differential abundance", "depends_on": []},
    {"id": "int", "description": "integrate RNA and protein results", "depends_on": [1, 2, 3]},
]


def test_fork_join_becomes_one_dag_card():
    out = plan_dag_from_tasks(FakeAssistant(), FORK_JOIN, name="Bulk RNA + proteomics integration")
    assert out["success"] is True
    card = out["workflow"]
    assert card["workflow_type"] == "pipeline" and card["execution_mode"] == "dag"
    assert [s["depends_on"] for s in card["pipeline_steps"]] == [[], [], [], [1, 2, 3]]
    assert card["max_parallel"] == 3  # three independent branches in the first wave
    assert card["name"] == "Bulk RNA + proteomics integration"


def test_fan_in_edges_without_a_data_connection_are_reported():
    out = plan_dag_from_tasks(FakeAssistant(), FORK_JOIN)
    # one typed 'csv' input on the integration step → only one branch is wired
    assert len(out["workflow"]["connections"]) == 1
    assert len(out["unwired_dependencies"]) == 2
    assert out["workflow"]["unwired_dependencies"] == out["unwired_dependencies"]


def test_independent_tasks_are_not_chained():
    tasks = [{"description": "rna de", "depends_on": []}, {"description": "lysate de", "depends_on": []}]
    out = plan_dag_from_tasks(FakeAssistant(), tasks)
    assert [s["depends_on"] for s in out["workflow"]["pipeline_steps"]] == [[], []]
    assert "unwired_dependencies" not in out["workflow"]


def test_refuses_with_a_reason():
    out = plan_dag_from_tasks(FakeAssistant(unresolved={"integrate"}), FORK_JOIN)
    assert out == {"success": False, "reason": "unresolved_task", "tasks": out["tasks"]}
    assert [t["resolved"] for t in out["tasks"]] == [True, True, True, False]
    assert plan_dag_from_tasks(FakeAssistant(), FORK_JOIN[:1])["reason"] == "fewer_than_two_tasks"


def test_untypeable_fan_in_keeps_the_order_and_reports_every_dependency():
    # catalog type metadata often generic: no typed handoff → order-only plan, nothing fabricated
    no_types = FakeAssistant(types={**TYPES, "bioc/mixomics_spls/main.nf": (["h5ad"], ["csv"])})
    out = plan_dag_from_tasks(no_types, FORK_JOIN)
    assert out["success"] is True and out["order_only"] is True
    card = out["workflow"]
    assert card["connections"] == []
    assert [s["depends_on"] for s in card["pipeline_steps"]] == [[], [], [], [1, 2, 3]]
    assert len(out["unwired_dependencies"]) == 3


def test_routing_chosen_paths_are_used_instead_of_a_bare_search():
    tasks = [dict(t, nextflow_path=f"chosen/{t['id']}.nf") for t in FORK_JOIN]
    out = plan_dag_from_tasks(FakeAssistant(unresolved={"rna", "lysate", "secretome", "integrate"}), tasks)
    assert [s["nextflow_path"] for s in out["workflow"]["pipeline_steps"]] == [f"chosen/{t['id']}.nf" for t in FORK_JOIN]
