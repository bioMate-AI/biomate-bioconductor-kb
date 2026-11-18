"""Unit tests for rule-first ml_training intent routing."""
import pytest

from galaxy.ai.ml_training.routing import (
    detect_training_intent, extract_training_config, route_ml_training, nextflow_path_for,
)


def test_llm_gpu_tier_is_opt_in(monkeypatch):
    """DPO/GRPO run on the CPU wrapper by default; only ML_TRAINING_GPU_LLM=1 routes
    them to the GPU wrapper (so the flag can't silently require unprovisioned infra)."""
    monkeypatch.delenv("ML_TRAINING_GPU_LLM", raising=False)
    assert nextflow_path_for("trl_dpo") == "ml_training/chemprop_train.nf"
    assert nextflow_path_for("trl_grpo") == "ml_training/chemprop_train.nf"
    monkeypatch.setenv("ML_TRAINING_GPU_LLM", "1")
    assert nextflow_path_for("trl_dpo") == "ml_training/trl_train.nf"
    assert nextflow_path_for("trl_grpo") == "ml_training/trl_train.nf"
    # Diffusion routing is unaffected by the flag; supervised types stay on the default.
    assert nextflow_path_for("protein_diffusion") == "ml_training/diffusion_train.nf"
    assert nextflow_path_for("sklearn_tabular") == "ml_training/chemprop_train.nf"


@pytest.mark.parametrize("text,expected", [
    ("Train a classifier to predict hERG blockers", True),
    ("build a QSAR model for solubility", True),
    ("fine-tune a GNN on my compounds", True),
    ("predict hERG for these SMILES", False),         # inference, not training
    ("screen this library for ADMET", False),
    ("what is the logP of aspirin?", False),
    ("", False),
])
def test_intent_detection(text, expected):
    assert detect_training_intent(text) is expected


def test_herg_alias_maps_to_tdc_classification():
    cfg = extract_training_config("train a model to classify hERG blockers")
    assert cfg.dataset.name == "tdc:hERG"
    assert cfg.task_type == "classification"
    assert cfg.model_type == "ludwig_tabular"   # default DL = CPU-runnable Ludwig
    assert cfg.metric == "auc"


def test_chemprop_is_opt_in_by_mention():
    cfg = extract_training_config("train a chemprop GNN to classify hERG blockers")
    assert cfg.model_type == "chemprop_gnn"


def test_regression_alias_maps_correctly():
    cfg = extract_training_config("build a model for Caco2 permeability")
    assert cfg.dataset.name == "tdc:Caco2_Wang"
    assert cfg.task_type == "regression"
    assert cfg.metric == "mae"


def test_baseline_hint_selects_sklearn():
    cfg = extract_training_config("train a quick baseline classifier for hERG")
    assert cfg.model_type == "sklearn_gbr"


def test_user_data_overrides_alias_dataset_but_keeps_target():
    cfg = extract_training_config("train a hERG classifier on my data",
                                  dataset_s3_uri="s3://b/mine.csv")
    assert cfg.dataset.s3_uri == "s3://b/mine.csv"
    assert cfg.dataset.target_col == "Y"   # from hERG alias


def test_regression_hint_without_alias():
    cfg = extract_training_config("train a model to predict IC50 values",
                                  dataset_s3_uri="s3://b/x.csv")
    assert cfg.task_type == "regression"


def test_unresolvable_dataset_raises_without_llm():
    with pytest.raises(ValueError):
        extract_training_config("train a classifier for my target")


def test_llm_fallback_fills_dataset_gap():
    def fake_llm(_text):
        return {"dataset": "tdc:AMES", "task_type": "classification", "target_col": "Y"}
    cfg = extract_training_config("train a mutagenicity model", llm_fill=fake_llm)
    assert cfg.dataset.name == "tdc:AMES"


def test_route_returns_workflow_ga_for_training_intent():
    ga = route_ml_training("train a classifier for hERG blockers")
    assert ga is not None
    assert ga["domain"] == "ml_training"
    assert "required_params" in ga and "scientific_rationale" in ga


def test_route_returns_none_for_non_training():
    assert route_ml_training("predict hERG for aspirin") is None


def test_route_returns_none_when_ambiguous():
    # training intent but no resolvable dataset → fall through to normal router
    assert route_ml_training("train a classifier for my custom endpoint") is None


# --- generic (non-molecular) tabular routing: expression matrix -> subtype ----

def test_expression_matrix_routes_to_sklearn_tabular_kfold():
    cfg = extract_training_config(
        "train a subtype classifier on this gene expression matrix",
        dataset_s3_uri="s3://bkt/expr.csv")
    assert cfg.model_type == "sklearn_tabular"
    assert cfg.dataset.split == "kfold" and cfg.dataset.cv_folds == 5
    assert cfg.task_type == "classification"
    assert cfg.dataset.target_col == "subtype"
    assert cfg.dataset.s3_uri == "s3://bkt/expr.csv"


def test_chinese_subtype_expression_request_routes_tabular():
    cfg = extract_training_config("用这份基因表达矩阵训练一个亚型预测模型")
    assert cfg.model_type == "sklearn_tabular"
    assert cfg.dataset.split == "kfold"
    assert cfg.dataset.target_col == "subtype"


def test_molecular_request_is_not_hijacked_by_tabular_branch():
    # a drug-discovery alias must still win over the generic tabular branch
    cfg = extract_training_config("train a hERG blocker classifier")
    assert cfg.model_type != "sklearn_tabular"
    assert cfg.dataset.name == "tdc:hERG"


# ── Attached training data (dev 2026-11-11) ─────────────────────────────────────────────────────
# "Train a potency predictor on our in-house assay data." + bace_assays.csv produced a
# SCAFFOLD-HOPPING card (required param `input_smiles`, "the compound series to hop"): the router
# never saw the attachment, could not resolve a dataset, returned None, and the request fell
# through to the catalog search. The user's attached table IS the dataset.
POTENCY = ("Train a potency predictor on our in-house assay data.\n"
           "[Attached files: bace_assays.csv]\n"
           "[Prepared inputs: Train a BACE1 potency predictor on the real published BACE assays, "
           "using SMILES and pIC50. The Train/Valid/Test splits are supplied.]")
ATTACHED_CSV = [{"name": "bace_assays.csv", "datasetId": "ebb2b218",
                 "s3Uri": "s3://bucket/uploads/ebb2b218/bace_assays.csv"}]


def test_training_request_without_data_still_falls_through():
    # unchanged behaviour: nothing to train on, no recognised public assay → normal search
    assert route_ml_training(POTENCY) is None


def test_attached_table_resolves_the_training_dataset():
    ga = route_ml_training(POTENCY, uploaded_datasets=ATTACHED_CSV)
    assert ga is not None, "a training request with an attached assay table must route to training"
    assert ga["domain"] == "ml_training"
    assert ga["nextflow_path"] == "ml_training/chemprop_train.nf"
    required = {p["name"]: p["value"] for p in ga["required_params"]}
    assert required["dataset"] == "s3://bucket/uploads/ebb2b218/bace_assays.csv"
    # the label column the request names, not a neutral "y" the user would have to correct
    assert required["target_col"] == "pIC50"
    # the card title says what was built
    assert ga["name"] == "potency predictor"


@pytest.mark.parametrize("attached,resolved", [
    ([{"name": "reads_R1.fastq.gz"}, {"name": "reads_R2.fastq.gz"}], None),   # raw reads are not training data
    ([{"name": "sample.bam"}], None),
    ([{"name": "notes.txt"}, {"name": "assays.csv", "s3Uri": "s3://b/assays.csv"}], "s3://b/assays.csv"),
    ([{"name": "corpus.jsonl", "path": "/data/corpus.jsonl"}], "/data/corpus.jsonl"),
    ([], None),
    (None, None),
])
def test_only_readable_training_tables_qualify(attached, resolved):
    from galaxy.ai.ml_training.routing import select_training_dataset
    assert select_training_dataset(attached) == resolved


def test_raw_reads_attachment_keeps_the_normal_search_path():
    assert route_ml_training("Train a model on these reads",
                             uploaded_datasets=[{"name": "r1.fastq.gz"}]) is None


@pytest.mark.parametrize("text,col", [
    ("train a model on SMILES and pIC50", "pIC50"),
    ("fit a regressor on the IC50_nM column", "IC50_nM"),
    ("train on measured logP", "logP"),
    ("train a model on our compounds", None),
])
def test_target_column_is_read_from_the_request(text, col):
    from galaxy.ai.ml_training.routing import _infer_target_col
    assert _infer_target_col(text) == col


def test_attached_file_wins_over_the_public_alias():
    # "train an hERG classifier" + THEIR hERG table → train on their file, not tdc:hERG
    ga = route_ml_training("Train an hERG classifier and gate the design loop on it",
                           uploaded_datasets=[{"name": "herg.csv", "s3Uri": "s3://b/herg.csv"}])
    required = {p["name"]: p["value"] for p in ga["required_params"]}
    assert required["dataset"] == "s3://b/herg.csv"
