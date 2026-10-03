"""Bind a DPO dataset config to the explicitly staged, immutable mmap bundle."""
import argparse
from pathlib import Path
import yaml


def prepare(config, data_dir):
    data_dir = Path(data_dir).resolve()
    dataset = config.get('dataset', config)
    train = dataset.get('train')
    if not isinstance(train, dict) or train.get('class') != 'PeptideDataset':
        raise ValueError('DPO requires one unwrapped PeptideDataset train split with stable IDs')
    if train.get('cluster'):
        raise ValueError('DPO dataset must not resample candidate IDs')
    train = dict(train)
    train['mmap_dir'] = str(data_dir)
    for field, default in (('specify_data', 'data.bin'), ('specify_index', 'index.txt')):
        path = data_dir / Path(train.get(field) or default).name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f'Missing or empty staged dataset file: {path}')
        train[field] = str(path)
    return {'dataset': {'train': train}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', required=True, type=Path)
    parser.add_argument('--data-dir', required=True, type=Path)
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    args.config.write_text(yaml.safe_dump(prepare(config, args.data_dir)))
