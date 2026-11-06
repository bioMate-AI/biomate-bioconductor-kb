from pathlib import Path
import sys
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_unimomo_dataset import prepare


def test_staged_paths_replace_source_machine_paths(tmp_path):
    (tmp_path / 'data.bin').write_bytes(b'fixture')
    (tmp_path / 'selected.txt').write_text('fixture\n')
    result = prepare({'dataset': {'train': {'class': 'PeptideDataset', 'mmap_dir': '/old',
                      'specify_index': '/old/selected.txt'}}}, tmp_path)
    assert result['dataset']['train']['specify_index'] == str(tmp_path / 'selected.txt')
    assert result['dataset']['train']['specify_data'] == str(tmp_path / 'data.bin')


def test_missing_or_resampled_dataset_rejected(tmp_path):
    config = {'train': {'class': 'PeptideDataset'}}
    with pytest.raises(ValueError, match='Missing or empty'): prepare(config, tmp_path)
    config['train']['cluster'] = 'clusters.json'
    with pytest.raises(ValueError, match='resample'): prepare(config, tmp_path)
    with pytest.raises(ValueError, match='unwrapped'): prepare({'train': []}, tmp_path)
