"""Prepare measured ribosome/proteome matrices for assay reconstruction only.

This does not infer translation efficiency, protein deltas or biological donor
independence. Source/sample context must be added before downstream supervision.
"""
import argparse, hashlib, json
from pathlib import Path
import numpy as np
import pandas as pd


def prepare(source, output, kind, source_uri, study_id):
    source, output = Path(source), Path(output)
    if output.exists(): raise ValueError('Refusing to replace prepared data')
    if not source_uri or not study_id: raise ValueError('Explicit source and study required')
    table = pd.read_csv(source, sep='\t')
    if kind == 'ribosome':
        identifier = 'Geneid'
        annotation = ['Geneid', 'Chr', 'Start', 'End', 'Strand', 'Length']
        if not set(annotation).issubset(table): raise ValueError('Expected featureCounts ribosome schema')
        samples = [c for c in table if c not in annotation]
        raw = table[samples].to_numpy(dtype=np.float64).T
        if not np.isfinite(raw).all() or (raw < 0).any() or (raw != np.floor(raw)).any():
            raise ValueError('Ribosome measurements must be finite nonnegative integer counts')
        library = raw.sum(1, keepdims=True)
        if (library <= 0).any(): raise ValueError('Empty ribosome library')
        values = np.log1p(raw / library * 1e4).astype(np.float32)
        observed = np.ones(raw.shape, dtype=bool)
        scale = 'log1p(count / complete-source-library * 10000)'
        namespace = 'ensembl_gene'
    elif kind == 'proteome':
        identifier = 'Genes'
        if identifier not in table: raise ValueError('Expected DIA-NN unique gene matrix')
        samples = [c for c in table if c != identifier]
        raw = table[samples].to_numpy(dtype=np.float64).T
        if np.isinf(raw).any() or (raw[np.isfinite(raw)] < 0).any():
            raise ValueError('Invalid protein quantities')
        # Non-detection is not measured absence; no fake zero targets or limits.
        observed = np.isfinite(raw) & (raw > 0)
        values = np.zeros(raw.shape, dtype=np.float32)
        values[observed] = np.log2(raw[observed]).astype(np.float32)
        scale = 'log2 positive DIA-NN gene quantity; unquantified entries masked'
        namespace = 'gene_symbol'
    else: raise ValueError('Unknown quantitative assay')
    if table[identifier].isna().any(): raise ValueError('Missing feature identity')
    features = table[identifier].astype(str).tolist()
    if len(set(features)) != len(features) or any(not x.strip() or ';' in x for x in features):
        raise ValueError('Duplicate, empty or ambiguous feature identifiers')
    if len(set(samples)) != len(samples): raise ValueError('Duplicate sample identities')
    if not observed.any(1).all(): raise ValueError('No measured features for sample')
    output.mkdir(parents=True)
    np.savez_compressed(output/'values.npz', values=values, observed=observed)
    schema = {'source_uri': source_uri, 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
              'modality': kind, 'feature_namespace': namespace, 'features': features,
              'sample_ids': samples, 'study_ids': [study_id]*len(samples), 'scale': scale,
              'values_file': 'values.npz', 'eligible_objective': 'masked_assay_reconstruction',
              'coverage': {'samples': len(samples), 'features': len(features), 'observed_entries': int(observed.sum()),
                           'missing_entries': int((~observed).sum()), 'feature_cap': None, 'sample_cap': None},
              'downstream_supervision_ready': False,
              'limits': ['No inferred cross-assay pairing', 'No inferred biological replicate independence',
                         'Not translation-efficiency or perturbation-delta labels',
                         'Study-level split required; technical pools stay together']}
    (output/'schema.json').write_text(json.dumps(schema, indent=2)+'\n')
    return schema


if __name__ == '__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--output',required=True)
    p.add_argument('--kind',choices=['ribosome','proteome'],required=True)
    p.add_argument('--source-uri',required=True);p.add_argument('--study-id',required=True)
    a=p.parse_args(); print(json.dumps(prepare(a.source,a.output,a.kind,a.source_uri,a.study_id)['coverage']))
