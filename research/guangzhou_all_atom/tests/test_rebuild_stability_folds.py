import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    'rebuild_folds', Path(__file__).parents[1] / 'rebuild_stability_folds.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

HEADER = "ID,SMILES,label,cluster\n"


def write_csv(tmp_path, rows):
    p = tmp_path / 'src.csv'
    p.write_text(HEADER + ''.join(f"{i},{s},{l},{c}\n" for i, s, l, c in rows))
    return p


def test_identical_structure_never_crosses_folds(tmp_path):
    # Same molecule (ethanol) placed in three different clusters with a duplicated ID.
    src = write_csv(tmp_path, [
        ('1', 'CCO', '0', '1'),
        ('1', 'OCC', '0', '2'),      # same structure, duplicate ID, different cluster
        ('2', 'CCO', '0', '3'),      # same structure, different ID/cluster
        ('3', 'c1ccccc1', '1', '1'),
        ('4', 'CCN', '1', '2'),
    ])
    records, audit = module.rebuild(src, n_folds=2)
    assert audit['unique_structures'] == 3            # ethanol, benzene, ethylamine
    assert audit['structures_crossing_folds'] == 0
    assert audit['ids_crossing_folds'] == {}
    # ethanol collapsed the three source clusters/IDs into one record + one fold
    ethanol = [r for r in records if r['canonical_smiles'] == 'CCO'][0]
    assert set(ethanol['source_ids']) == {'1', '2'}
    assert set(ethanol['source_clusters']) == {'1', '2', '3'}


def test_conflicting_labels_are_flagged_not_dropped(tmp_path):
    src = write_csv(tmp_path, [
        ('1', 'CCO', '0', '1'),
        ('2', 'CCO', '1', '2'),      # same structure, opposite label
        ('3', 'c1ccccc1', '0', '1'),
    ])
    records, audit = module.rebuild(src, n_folds=2)
    assert audit['label_conflict_structures'] == 1
    conflict = [r for r in records if r['label_conflict']][0]
    assert conflict['canonical_smiles'] == 'CCO'
    assert conflict['label_votes'] == {'0': 1, '1': 1}


def test_fully_shared_clusters_report_unusable_merge(tmp_path):
    # A structure shared across both clusters links them into one merge component.
    src = write_csv(tmp_path, [
        ('1', 'CCO', '0', '1'),
        ('2', 'CCO', '0', '2'),
        ('3', 'c1ccccc1', '1', '2'),
    ])
    records, audit = module.rebuild(src, n_folds=2)
    assert audit['cluster_merge_components'] == 1
    assert audit['cluster_merge_verdict'] == 'unusable'


def test_labels_are_stratified_across_folds(tmp_path):
    rows = [(str(i), f"C{'C' * i}O", '0' if i % 2 else '1', '1') for i in range(1, 21)]
    src = write_csv(tmp_path, rows)
    records, audit = module.rebuild(src, n_folds=5)
    # Each fold should hold both labels roughly evenly (10 of each across 5 folds -> 2 each).
    for fold in range(1, 6):
        labels = [r['label'] for r in records if r['fold'] == fold]
        assert labels.count('0') == 2 and labels.count('1') == 2
