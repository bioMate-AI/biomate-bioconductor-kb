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
    sa = FakeAssistant(unresolved={"rna", "lysate", "secretome", "integrate"})
    sa.workflow_search = _Catalog(*[t["nextflow_path"] for t in tasks])  # routed paths are catalog workflows
    out = plan_dag_from_tasks(sa, tasks)
    assert [s["nextflow_path"] for s in out["workflow"]["pipeline_steps"]] == [f"chosen/{t['id']}.nf" for t in FORK_JOIN]


class _Catalog:
    """workflow_search stand-in: an in-memory catalog of executable workflows."""
    def __init__(self, *paths):
        import sqlite3
        self._db = sqlite3.connect(":memory:", check_same_thread=False)
        self._db.execute("CREATE TABLE workflows (filename TEXT, executable INTEGER)")
        self._db.executemany("INSERT INTO workflows VALUES (?, 1)", [(p,) for p in paths])

    def _get_connection(self):
        class _C:  # close() must not close the shared in-memory DB
            def __init__(s, db): s.db = db
            def execute(s, *a): return s.db.execute(*a)
            def close(s): pass
        return _C(self._db)


def test_caller_supplied_path_used_only_if_in_catalog():
    sa = FakeAssistant()
    sa.workflow_search = _Catalog("routed/rna_from_chat.nf")
    tasks = [dict(FORK_JOIN[0], nextflow_path="routed/rna_from_chat.nf"),
             dict(FORK_JOIN[1], nextflow_path="/tmp/not_a_catalog_workflow.nf"),
             FORK_JOIN[2], FORK_JOIN[3]]
    out = plan_dag_from_tasks(sa, tasks)
    paths = [s["nextflow_path"] for s in out["workflow"]["pipeline_steps"]]
    assert paths[0] == "routed/rna_from_chat.nf"   # the turn's own routing, a catalog workflow
    assert paths[1] == PATHS["lysate"]              # untrusted path ignored → resolved from the task


# ── Plan-time inputs (P2, 2026-11-11): bind uploads to DECLARED params, list what is still needed ──
DECLARED = {
    "bioc/deseq2_de/main.nf": {"required": [{"name": "matrix", "default": None},
                                            {"name": "samplesheet", "default": None},
                                            {"name": "contrast_variable", "default": None}],
                               "optional": [{"name": "outdir", "default": "./results"}]},
    "bioc/limma_proteomics_de/main.nf": {"required": [{"name": "input", "default": None}], "optional": []},
    "bioc/mixomics_spls/main.nf": {"required": [{"name": "rna_results", "default": None}], "optional": []},
}


class InputsAssistant(FakeAssistant):
    """Adds the single-workflow param parser + a binder with the production contract:
    binds only to a DECLARED param, only on a clear filename cue, marks it autoFilled."""
    def _parse_nextflow_params(self, path):
        return {k: [dict(p) for p in v] for k, v in DECLARED.get(path, {"required": [], "optional": []}).items()}

    def _bind_uploaded_datasets_to_params(self, req, opt, uploaded):
        cues = {"matrix": ("count", "matrix"), "samplesheet": ("sample", "metadata")}
        for p in req + opt:
            terms = cues.get(p["name"])
            hit = next((u for u in uploaded if terms and any(t in u["name"].lower() for t in terms)), None)
            if hit:
                p.update(value=hit["s3_uri"], default=hit["s3_uri"], autoFilled=True)
        return req, opt


UPLOADS = [{"name": "counts_matrix.csv", "s3_uri": "s3://b/counts_matrix.csv"},
           {"name": "sample_metadata.csv", "s3_uri": "s3://b/sample_metadata.csv"}]


def test_root_steps_get_uploads_bound_and_missing_required_listed():
    out = plan_dag_from_tasks(InputsAssistant(), FORK_JOIN, uploaded_datasets=UPLOADS)
    rna, lysate, _sec, integ = out["workflow"]["pipeline_steps"]
    assert rna["params"]["matrix"] == "s3://b/counts_matrix.csv"
    assert rna["params"]["samplesheet"] == "s3://b/sample_metadata.csv"
    assert rna["bound_from_uploads"] == ["matrix", "samplesheet"]
    assert rna["missing_inputs"] == ["contrast_variable"]       # declared, required, no upload matches it
    assert lysate["missing_inputs"] == ["input"]                 # nothing bound — said, not left empty
    assert "outdir" not in rna["missing_inputs"]                 # has a default → never "needed"


def test_dependent_step_is_not_checked_and_unwired_fan_in_needs_mapping():
    out = plan_dag_from_tasks(InputsAssistant(), FORK_JOIN, uploaded_datasets=UPLOADS)
    integ = out["workflow"]["pipeline_steps"][3]
    assert integ["missing_inputs"] == []          # its data comes from earlier steps
    assert integ["needs_input_mapping"] is True   # two of its three branches are not wired


def test_no_binding_is_invented_without_a_declared_param():
    out = plan_dag_from_tasks(InputsAssistant(), FORK_JOIN,
                              uploaded_datasets=[{"name": "notes.md", "s3_uri": "s3://b/notes.md"}])
    for st in out["workflow"]["pipeline_steps"]:
        assert st["bound_from_uploads"] == []
        assert "notes" not in str(st["params"])


def test_steps_carry_resolution_and_a_workflow_label():
    out = plan_dag_from_tasks(FakeAssistant(), FORK_JOIN)
    steps = out["workflow"]["pipeline_steps"]
    assert {s["resolution"] for s in steps} == {"catalog_workflow"}
    assert steps[0]["workflow_label"] == "deseq2_de"   # no catalog name available → workflow directory
    assert steps[0]["missing_inputs"] == []            # no param parser → nothing claimed missing


def test_workflow_label_prefers_the_catalog_name():
    import sqlite3

    class _Named:
        def __init__(self):
            self.db = sqlite3.connect(":memory:", check_same_thread=False)
            self.db.execute("CREATE TABLE workflows (filename TEXT, executable INTEGER, name TEXT)")
            self.db.execute("INSERT INTO workflows VALUES (?, 1, ?)", (PATHS["rna"], "DESeq2 differential expression"))

        def _get_connection(self):
            db = self.db

            class _C:
                def execute(s, *a): return db.execute(*a)
                def close(s): pass
            return _C()

    sa = FakeAssistant()
    sa.workflow_search = _Named()
    out = plan_dag_from_tasks(sa, FORK_JOIN)
    assert out["workflow"]["pipeline_steps"][0]["workflow_label"] == "DESeq2 differential expression"


def test_unbound_header_declared_data_input_is_needed_not_silently_sample_data():
    """dev 2026-11-11: root workflows that declare data only via '// Input:' headers (surfaced as
    OPTIONAL file params because the executor falls back to sample data) reported nothing missing —
    the plan looked ready but would have analyzed sample data. Unbound data files are needed."""
    class HeaderAssistant(FakeAssistant):
        def _parse_nextflow_params(self, path):
            return {"required": [],
                    "optional": [{"name": "proteinGroups", "type": "file", "default": None},
                                 {"name": "reference_fasta", "type": "file", "default": "s3://ref/genome.fa"},
                                 {"name": "fdr", "type": "number", "default": None}]}

        def _bind_uploaded_datasets_to_params(self, req, opt, uploaded):
            return req, opt

    out = plan_dag_from_tasks(HeaderAssistant(), FORK_JOIN, uploaded_datasets=UPLOADS)
    root = out["workflow"]["pipeline_steps"][0]
    assert root["missing_inputs"] == ["proteinGroups"]   # data file not provided → needed
    # a file param with a real default, and a non-file optional param, are not flagged
    assert "reference_fasta" not in root["missing_inputs"] and "fdr" not in root["missing_inputs"]


# ── Self-correction against the user's data (2026-11-11): a root step whose workflow cannot take the
#    uploads is re-resolved to a confident candidate that can, before the plan is wired ──
SALMON = "rna/salmon_quant_de.nf"      # needs quant.sf — cannot take a counts matrix
COUNTS_DE = "rna/deseq2_counts.nf"     # declares matrix + samplesheet


class _Search:
    def __init__(self, ranked):
        self.ranked = ranked

    def search(self, desc):
        return self.ranked


class RerouteAssistant(InputsAssistant):
    def __init__(self, ranked, **kw):
        super().__init__(**kw)
        self.workflow_search = _Search(ranked)

    def _parse_nextflow_params(self, path):
        if path == SALMON:
            return {"required": [], "optional": [{"name": "quant", "type": "file", "default": None}]}
        if path == COUNTS_DE:
            return {"required": [{"name": "matrix", "default": None}, {"name": "samplesheet", "default": None}],
                    "optional": []}
        return super()._parse_nextflow_params(path)


def _rna_tasks():
    return [dict(FORK_JOIN[0], nextflow_path=None), FORK_JOIN[1], FORK_JOIN[2], FORK_JOIN[3]]


def test_root_step_is_rerouted_to_a_workflow_that_takes_the_users_data():
    sa = RerouteAssistant([{"filename": COUNTS_DE, "score": 9.0}])
    sa._resolve_task_to_workflow = lambda t: (
        {"nextflow_path": SALMON, "parameters": {}} if t["id"] == "rna" else FakeAssistant._resolve_task_to_workflow(sa, t))
    out = plan_dag_from_tasks(sa, _rna_tasks(), uploaded_datasets=UPLOADS)
    rna = out["workflow"]["pipeline_steps"][0]
    assert rna["nextflow_path"] == COUNTS_DE
    assert rna["params"]["matrix"] == "s3://b/counts_matrix.csv" and rna["missing_inputs"] == []
    assert rna["rerouted_from"] == "salmon_quant_de"
    assert "counts_matrix.csv" in rna["reroute_reason"]


def test_no_reroute_below_confidence_or_when_nothing_binds():
    for ranked in ([{"filename": COUNTS_DE, "score": 3.0}],            # below the confidence bar
                   [{"filename": SALMON + ".alt.nf", "score": 9.0}]):  # a candidate that binds nothing
        sa = RerouteAssistant(ranked)
        sa._resolve_task_to_workflow = lambda t: (
            {"nextflow_path": SALMON, "parameters": {}} if t["id"] == "rna" else FakeAssistant._resolve_task_to_workflow(sa, t))
        rna = plan_dag_from_tasks(sa, _rna_tasks(), uploaded_datasets=UPLOADS)["workflow"]["pipeline_steps"][0]
        assert rna["nextflow_path"] == SALMON and "rerouted_from" not in rna
        assert rna["missing_inputs"] == ["quant"]   # honest fallback: say what is needed


def test_no_reroute_when_current_workflow_already_takes_the_data():
    sa = RerouteAssistant([{"filename": SALMON, "score": 12.0}])
    out = plan_dag_from_tasks(sa, FORK_JOIN, uploaded_datasets=UPLOADS)   # rna → deseq2_de (binds matrix)
    assert "rerouted_from" not in out["workflow"]["pipeline_steps"][0]
