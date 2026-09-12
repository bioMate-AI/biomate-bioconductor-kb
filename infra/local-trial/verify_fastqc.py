#!/usr/bin/env python3
"""Verify trial artifacts independently of job status; QC FAIL is not execution failure."""
import argparse
import hashlib
import json
from pathlib import Path
from zipfile import ZipFile


def verify(html, archive):
    html, archive = Path(html), Path(archive)
    if b'<html' not in html.read_bytes().lower():
        raise ValueError('Missing HTML report')
    with ZipFile(archive) as z:
        def read_one(suffix):
            names = [n for n in z.namelist() if n.endswith('/' + suffix)]
            if len(names) != 1:
                raise ValueError('Expected exactly one ' + suffix)
            if z.getinfo(names[0]).file_size > 5_000_000:
                raise ValueError('Unexpectedly large metrics file')
            return z.read(names[0]).decode('utf-8')
        data = read_one('fastqc_data.txt')
        summary = read_one('summary.txt')
    block = data.split('>>Basic Statistics\t', 1)
    if len(block) != 2:
        raise ValueError('Missing basic statistics')
    rows = block[1].split('>>END_MODULE', 1)[0].splitlines()[1:]
    stats = dict(line.split('\t', 1) for line in rows if '\t' in line and not line.startswith('#'))
    for key, expected in [('Total Sequences', '100'), ('Sequence length', '100'), ('%GC', '50')]:
        if stats.get(key) != expected:
            raise ValueError(f'{key}: expected {expected}, got {stats.get(key)}')
    modules = []
    for line in summary.splitlines():
        fields = line.split('\t')
        if len(fields) != 3 or fields[0] not in {'PASS', 'WARN', 'FAIL'}:
            raise ValueError('Invalid module summary')
        modules.append({'status': fields[0], 'module': fields[1]})
    if not modules or not any(m['module'] == 'Basic Statistics' for m in modules):
        raise ValueError('Missing summary modules')
    return {'artifact_validation_passed': True, 'synthetic_input': True,
            'statistics': stats, 'qc_modules': modules,
            'interpretation': 'Functional execution evidence only; repeated synthetic reads may fail QC.',
            'sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in (html, archive)}}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('html', type=Path)
    parser.add_argument('archive', type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.html, args.archive), indent=2))
