"""Unit tests for the TrainingConfig → Ludwig config adapter (no ludwig needed)."""
import pytest

from galaxy.ai.ml_training.config import TrainingConfig, DatasetSpec, Hyperparams
from galaxy.ai.ml_training.ludwig_adapter import (to_ludwig_config, add_split_column,
                                                  FEATURE_COLUMNS, SPLIT_COLUMN)


def _cfg(**over):
    base = dict(name="hERG (ludwig)", model_type="ludwig_tabular",
                dataset=DatasetSpec(name="tdc:hERG", target_col="Y"),
                hyperparams=Hyperparams(epochs=7, batch_size=16, learning_rate=0.002,
                                        hidden_size=64, depth=2, dropout=0.1))
    base.update(over)
    return TrainingConfig(**base)


def test_classification_maps_to_binary_output():
    lc = to_ludwig_config(_cfg(task_type="classification"), target_col="Y")
    assert lc["output_features"] == [{"name": "Y", "type": "binary"}]


def test_regression_maps_to_number_output():
    lc = to_ludwig_config(_cfg(task_type="regression"), target_col="Y")
    assert lc["output_features"][0]["type"] == "number"


def test_input_features_are_number_over_descriptor_columns():
    lc = to_ludwig_config(_cfg(), target_col="Y")
    names = [f["name"] for f in lc["input_features"]]
    assert names == FEATURE_COLUMNS
    assert all(f["type"] == "number" for f in lc["input_features"])


def test_hyperparams_flow_into_trainer_and_encoder():
    lc = to_ludwig_config(_cfg(), target_col="Y")
    assert lc["trainer"]["epochs"] == 7
    assert lc["trainer"]["batch_size"] == 16
    assert lc["trainer"]["learning_rate"] == 0.002
    enc = lc["input_features"][0]["encoder"]
    assert enc["type"] == "dense"
    assert enc["output_size"] == 64
    assert enc["dropout"] == 0.1


def test_split_probabilities_reflect_dataset_fracs():
    cfg = _cfg(dataset=DatasetSpec(name="tdc:hERG", target_col="Y", split="random",
                                   val_frac=0.15, test_frac=0.15))
    lc = to_ludwig_config(cfg, target_col="Y")
    assert lc["preprocessing"]["split"]["type"] == "random"
    probs = lc["preprocessing"]["split"]["probabilities"]
    assert abs(sum(probs) - 1.0) < 1e-9
    assert probs == [0.7, 0.15, 0.15]


def test_scaffold_split_uses_fixed_partition_column():
    """Ludwig has no scaffold splitter: a scaffold request must map to a fixed
    split over precomputed partitions, never to Ludwig's random split."""
    lc = to_ludwig_config(_cfg(), target_col="Y")   # DatasetSpec default split=scaffold
    assert lc["preprocessing"]["split"] == {"type": "fixed", "column": SPLIT_COLUMN}


def test_add_split_column_writes_scaffold_partitions():
    pytest.importorskip("rdkit")
    pd = pytest.importorskip("pandas")
    smiles = ["c1ccccc1C", "c1ccccc1CC", "c1ccccc1O", "C1CCCCC1C", "C1CCCCC1N",
              "c1ccncc1C", "c1ccncc1N", "CCO", "CCN", "CCCC"]
    df = pd.DataFrame({"_smiles": smiles})
    meta = add_split_column(df, _cfg(dataset=DatasetSpec(name="tdc:hERG", target_col="Y",
                                                         val_frac=0.2, test_frac=0.2)))
    assert meta["method"] == "bemis_murcko_scaffold"
    assert set(df[SPLIT_COLUMN]) <= {0, 1, 2}
    from galaxy.ai.ml_training.splits import bemis_murcko_scaffold
    by_scaffold = {}
    for smi, part in zip(df["_smiles"], df[SPLIT_COLUMN]):
        by_scaffold.setdefault(bemis_murcko_scaffold(smi), set()).add(part)
    assert all(len(parts) == 1 for parts in by_scaffold.values())


def test_ludwig_tabular_is_a_valid_model_type():
    _cfg().validate()  # must not raise
