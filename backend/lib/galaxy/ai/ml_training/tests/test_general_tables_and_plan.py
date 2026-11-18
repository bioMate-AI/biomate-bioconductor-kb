"""General (non-molecular) data + the structured Models-panel training plan.

Covers the 2026-11-10 Models-panel rebuild:
  * one table reader for CSV / TSV / JSONL / NDJSON / parquet;
  * generic learners never require a SMILES column;
  * s3:// datasets are staged by the loaders (LLM + molecular), never NotImplemented;
  * build_training_plan maps structured fields → a validated workflow_ga with the
    right Nextflow wrapper + container, and rejects what cannot actually run.
"""
import json
from pathlib import Path

import pytest

from galaxy.ai.ml_training import datasets as _ds
from galaxy.ai.ml_training.config import ConfigError, DatasetSpec, TrainingConfig
from galaxy.ai.ml_training.datasets import (
    load_dataset, load_instruction_rows, load_tabular_dataset, read_table_rows,
)
from galaxy.ai.ml_training.plan import build_training_plan, supported_metrics


# ── table formats ───────────────────────────────────────────────────────────
def _jsonl(path: Path, rows):
    path.write_text("\n".join(json.dumps(r) for r in rows) + "\n")
    return str(path)


def test_jsonl_table_trains_without_smiles(tmp_path):
    rows = [{"sample_id": f"S{i}", "gene_a": i * 1.5, "gene_b": 10 - i, "subtype": "A" if i % 2 else "B"}
            for i in range(12)]
    rows[3]["gene_a"] = None                      # missing cell → mean-imputed
    path = _jsonl(tmp_path / "expr.jsonl", rows)
    ds = load_tabular_dataset(path, "subtype")
    assert ds.task == "classification"
    assert ds.feature_names == ["gene_a", "gene_b"]   # string sample_id dropped
    assert len(ds) == 12 and set(ds.y) == {"A", "B"}
    assert ds.source.startswith("tabular-jsonl:")
    assert all(isinstance(v, float) for row in ds.X for v in row)


def test_ndjson_and_tsv_are_read(tmp_path):
    nd = _jsonl(tmp_path / "t.ndjson", [{"x": 1, "y": 2.0}, {"x": 3, "y": 4.5}])
    cols, rows = read_table_rows(nd)
    assert cols == ["x", "y"] and rows[1]["y"] == 4.5
    tsv = tmp_path / "t.tsv"
    tsv.write_text("x\ty\n1\t2\n3\t4\n")
    cols, rows = read_table_rows(str(tsv))
    assert cols == ["x", "y"] and rows[0] == {"x": "1", "y": "2"}


def test_parquet_table_is_read(tmp_path):
    pa = pytest.importorskip("pyarrow")
    import pyarrow.parquet as pq
    path = tmp_path / "t.parquet"
    pq.write_table(pa.table({"f1": [1.0, 2.0, 3.0, 4.0], "label": [0.5, 1.5, 2.5, 3.5]}), str(path))
    ds = load_tabular_dataset(str(path), "label", task="regression")
    assert ds.y == [0.5, 1.5, 2.5, 3.5] and ds.feature_names == ["f1"]


def test_jsonl_invalid_line_is_a_clear_error(tmp_path):
    p = tmp_path / "bad.jsonl"
    p.write_text('{"a": 1}\nnot json\n')
    with pytest.raises(ConfigError, match="line 2"):
        read_table_rows(str(p))


def test_molecular_loader_reads_jsonl(tmp_path):
    path = _jsonl(tmp_path / "mols.jsonl", [{"smi": "CCO", "pIC50": 5.1}, {"smi": "c1ccccc1", "pIC50": 6}])
    ds = load_dataset(DatasetSpec(path=path, smiles_col="smi", target_col="pIC50"))
    assert ds.rows == [("CCO", 5.1), ("c1ccccc1", 6.0)]


def test_llm_rows_stage_from_s3(tmp_path, monkeypatch):
    monkeypatch.chdir(tmp_path)

    def fake_run(cmd, **k):
        Path(cmd[4]).write_text(json.dumps({"instruction": "q", "output": "a"}) + "\n")
        class R: returncode = 0
        return R()
    monkeypatch.setattr(_ds.subprocess, "run", fake_run)
    rows = load_instruction_rows(DatasetSpec(s3_uri="s3://b/k/sft.jsonl", split="random"))
    assert rows == [{"instruction": "q", "output": "a"}]


# ── config rules ────────────────────────────────────────────────────────────
def test_molecular_model_rejects_featurizer_none():
    with pytest.raises(ConfigError, match="SMILES"):
        TrainingConfig(name="m", model_type="sklearn_gbr", featurizer="none",
                       dataset=DatasetSpec(path="x.csv")).validate()


def test_generic_ludwig_rejects_scaffold_split():
    with pytest.raises(ConfigError, match="scaffold"):
        TrainingConfig(name="m", model_type="ludwig_tabular", featurizer="none",
                       dataset=DatasetSpec(path="x.csv", split="scaffold")).validate()


def test_generic_ludwig_config_has_one_number_input_per_column():
    from galaxy.ai.ml_training.ludwig_adapter import to_ludwig_tabular_config
    cfg = TrainingConfig(name="m", task_type="classification", model_type="ludwig_tabular",
                         featurizer="none", dataset=DatasetSpec(path="x.csv", split="random"))
    conf = to_ludwig_tabular_config(cfg.validate(), ["g1", "g2"], "subtype")
    assert [f["name"] for f in conf["input_features"]] == ["g1", "g2"]
    assert conf["output_features"] == [{"name": "subtype", "type": "category"}]


# ── structured plan ─────────────────────────────────────────────────────────
BASE = {"dataset_s3_uri": "s3://biomate-nextflow-work/uploads/project-p/expr.jsonl",
        "dataset_name": "expr.jsonl"}


def test_plan_generic_tabular_classification():
    out = build_training_plan({**BASE, "model_type": "sklearn_tabular", "target_col": "subtype",
                               "task_type": "classification", "metric": "macro_f1",
                               "gate_threshold": 0.6})
    ga = out["workflow_ga"]
    assert out["nextflow_path"] == "ml_training/chemprop_train.nf"
    assert ga["domain"] == "ml_training" and ga["source_dataset_name"] == "expr.jsonl"
    p = ga["parameters"]
    assert p["dataset"] == BASE["dataset_s3_uri"] and p["target_col"] == "subtype"
    assert p["featurizer"] == "none" and p["split"] == "kfold" and p["gate_threshold"] == 0.6
    assert ga["name"] == "subtype classification model"
    assert out["compute_config"]["container"].endswith("/biomate/ml-training:latest")


def test_plan_generic_ludwig_uses_random_split_and_no_smiles():
    out = build_training_plan({**BASE, "model_type": "ludwig_tabular", "target_col": "y",
                               "task_type": "regression"})
    p = out["workflow_ga"]["parameters"]
    assert p["featurizer"] == "none" and p["split"] == "random" and p["metric"] == "mae"


def test_plan_molecular_requires_smiles_column():
    with pytest.raises(ConfigError, match="smiles_col"):
        build_training_plan({**BASE, "model_type": "sklearn_gbr", "target_col": "y",
                             "task_type": "regression"})
    out = build_training_plan({**BASE, "model_type": "sklearn_gbr", "target_col": "y",
                               "task_type": "classification", "smiles_col": "smi"})
    p = out["workflow_ga"]["parameters"]
    assert p["smiles_col"] == "smi" and p["featurizer"] == "rdkit_2d" and p["split"] == "scaffold"
    assert p["metric"] == "auc"


def test_plan_rejects_metric_the_trainer_never_reports():
    with pytest.raises(ConfigError, match="metric"):
        build_training_plan({**BASE, "model_type": "sklearn_gbr", "smiles_col": "smi",
                             "target_col": "y", "task_type": "classification", "metric": "f1"})
    assert supported_metrics("sklearn_tabular", "none", "regression") == ("r2", "mae")


def test_plan_requires_target_and_s3():
    with pytest.raises(ConfigError, match="target_col"):
        build_training_plan({**BASE, "model_type": "sklearn_tabular", "task_type": "regression"})
    with pytest.raises(ConfigError, match="s3://"):
        build_training_plan({"dataset_s3_uri": "/local/x.csv", "model_type": "sklearn_tabular",
                             "target_col": "y", "task_type": "regression"})


def test_plan_rejects_unrunnable_types_with_reason():
    with pytest.raises(ConfigError, match="no training loop"):
        build_training_plan({**BASE, "model_type": "chemprop_gnn"})
    with pytest.raises(ConfigError, match="Nextflow wrapper"):
        build_training_plan({**BASE, "model_type": "tabular_diffusion"})


def test_plan_llm_dpo_uses_trl_image_and_text_generation():
    out = build_training_plan({**BASE, "model_type": "trl_dpo",
                               "llm": {"base_model": "HuggingFaceTB/SmolLM2-135M-Instruct", "beta": 0.2}})
    ga = out["workflow_ga"]
    assert ga["parameters"]["task_type"] == "text_generation" and ga["parameters"]["beta"] == 0.2
    assert ga["parameters"]["metric"] == "train_loss"
    assert out["compute_config"]["container"].endswith("/biomate/trl-training:latest")


def test_plan_adapt_of_marks_adaptation_and_threads_base_ref():
    """`adapt_of` threads a registry base-model ref through config → plan → ga so the run
    is tagged an adaptation (for registration to version the base, not register a fresh
    model). Absent ⇒ an ordinary training run. Model-type-agnostic."""
    # No adapt_of ⇒ ordinary training.
    train = build_training_plan({**BASE, "model_type": "trl_dpo",
                                 "llm": {"base_model": "HuggingFaceTB/SmolLM2-135M-Instruct"}})
    assert train["adapt_of"] is None and train["workflow_type"] == "training"
    assert train["workflow_ga"]["workflow_type"] == "training"
    assert train["workflow_ga"]["description"].startswith("Train ")

    # adapt_of set ⇒ adaptation, threaded into the plan, the ga, and the round-tripped config.
    adapt = build_training_plan({**BASE, "model_type": "trl_dpo",
                                 "adapt_of": "custom:camp1/potency-llm",
                                 "llm": {"base_model": "HuggingFaceTB/SmolLM2-135M-Instruct"}})
    assert adapt["adapt_of"] == "custom:camp1/potency-llm"
    assert adapt["workflow_type"] == "adaptation"
    ga = adapt["workflow_ga"]
    assert ga["workflow_type"] == "adaptation" and ga["adapt_of"] == "custom:camp1/potency-llm"
    assert ga["description"].startswith("Adapt ")
    assert "new version of custom:camp1/potency-llm" in ga["description"]
    assert adapt["config"]["adapt_of"] == "custom:camp1/potency-llm"   # survives to_dict/asdict

    # Model-type-agnostic: a supervised adaptation is tagged the same way.
    sup = build_training_plan({**BASE, "model_type": "sklearn_tabular", "target_col": "subtype",
                               "task_type": "classification", "adapt_of": "custom:camp1/herg"})
    assert sup["workflow_type"] == "adaptation" and sup["config"]["adapt_of"] == "custom:camp1/herg"


def test_plan_llm_rejects_unknown_spec_field_and_composite_reward():
    with pytest.raises(ConfigError, match="unknown llm field"):
        build_training_plan({**BASE, "model_type": "ludwig_llm", "llm": {"bogus": 1}})
    with pytest.raises(ConfigError, match="composite"):
        build_training_plan({**BASE, "model_type": "trl_grpo", "llm": {"reward": "composite"}})


def test_plan_scrna_diffusion_routes_to_its_wrapper_and_image():
    out = build_training_plan({**BASE, "model_type": "scrna_diffusion",
                               "sc": {"finetune": False}})
    assert out["nextflow_path"] == "ml_training/scrna_diffusion_train.nf"
    assert out["workflow_ga"]["parameters"]["sc_finetune"] is False
    assert out["compute_config"]["container"].endswith("/biomate/sc-diffusion-training:latest")


# ── dataset size floor (dev run c0d27792: 1-row contrasts.csv → 5-fold CV crash) ──
def test_plan_refuses_a_dataset_too_small_for_its_split():
    req = {**BASE, "model_type": "sklearn_tabular", "target_col": "variable", "task_type": "classification"}
    with pytest.raises(ConfigError, match=r"^dataset_too_small:1:10:"):
        build_training_plan(req, rows_of=lambda uri: 1)
    assert build_training_plan(req, rows_of=lambda uri: 240)["workflow_ga"]


def test_plan_does_not_refuse_when_row_count_is_unknown():
    req = {**BASE, "model_type": "sklearn_tabular", "target_col": "subtype", "task_type": "classification"}
    assert build_training_plan(req, rows_of=lambda uri: None)["workflow_ga"]
