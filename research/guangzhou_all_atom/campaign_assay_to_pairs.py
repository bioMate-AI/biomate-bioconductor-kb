"""Bridge persisted campaign KD assays to candidate-ID-linked diffusion preferences.

Call with the platform AssayIngestionService and an explicitly scoped candidate
manifest. Ambiguous replicates and unsupported qualifiers require resolution
before training; they are never silently averaged or promoted to exact values.
"""
import csv
import math
from pathlib import Path
from tempfile import TemporaryDirectory
from wetlab_kd_to_pairs import build


def export_campaign_pairs(service, campaign_id, manifest, *, simulated=False):
    if manifest.get('campaign_id') != campaign_id:
        raise ValueError('Candidate manifest campaign mismatch')
    if manifest.get('data_origin') not in ('measured', 'simulated'):
        raise ValueError('Manifest must declare measured or simulated data_origin')
    if (manifest['data_origin'] == 'simulated') != simulated:
        raise ValueError('Simulation flag must match manifest data_origin')
    candidates = {}
    for candidate in manifest['candidates']:
        key = candidate['id']
        if key in candidates:
            raise ValueError(f'Duplicate candidate ID: {key}')
        if not candidate.get('target') or not candidate.get('sequence'):
            raise ValueError(f'{key}: target and sequence required')
        candidates[key] = candidate
    seen, rows, assay_ids = set(), [], {}
    for assay in service.get_campaign_results(campaign_id):
        if assay['assay_type'] != 'Kd':
            continue
        key = assay['compound_id']
        if key not in candidates:
            raise ValueError(f'Assay candidate missing from manifest: {key}')
        if key in seen:
            raise ValueError(f'Replicate KD rows require explicit resolution: {key}')
        seen.add(key)
        value = assay['value_uM']
        if value is None or not math.isfinite(value) or value <= 0:
            raise ValueError(f'{key}: KD must be positive and finite')
        operator = assay.get('operator') or '='
        if operator not in ('=', '>'):
            raise ValueError(f'{key}: unsupported KD qualifier {operator!r}')
        candidate = candidates[key]
        rows.append([key, candidate['sequence'], candidate['target'],
                     ('>' if operator == '>' else '') + str(value * 1000)])
        assay_ids[key] = str(assay['id'])
    with TemporaryDirectory() as temp:
        path = Path(temp) / 'kd.csv'
        with path.open('w', newline='') as handle:
            writer = csv.writer(handle)
            writer.writerow(['id', 'seq', 'target', 'kd_nM'])
            writer.writerows(rows)
        pairs, _ = build(path, simulated=simulated)
    for pair in pairs.pairs:
        pair.provenance.update(campaign_id=campaign_id,
                               chosen_assay_id=assay_ids[pair.chosen_id],
                               rejected_assay_id=assay_ids[pair.rejected_id],
                               data_origin=manifest['data_origin'])
    return pairs
