"""Observed HAP1 peptide quantities for presentation-assay reconstruction.

No non-detection negatives, inferred assay limits, median-per-KO normalization,
binding labels or invented paired transcript/protein measurements.
"""
import csv, hashlib, io, json, math, zipfile
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np
import openpyxl


def accepted(row):
    try:
        q, gq, value = float(row['Q.Value']), float(row['Global.Q.Value']), float(row['Precursor.Quantity'])
    except (ValueError, KeyError, TypeError): return 'invalid_numeric'
    if not all(math.isfinite(v) for v in (q,gq,value)): return 'invalid_numeric'
    if not 0 <= q <= .01 or not 0 <= gq <= .01: return 'q_value_filter'
    if value <= 0: return 'unquantified'
    if not row['Stripped.Sequence'] or set(row['Stripped.Sequence']) - set('ACDEFGHIKLMNPQRSTVWY'):
        return 'invalid_sequence'
    return None


def prepare(path, out, uri):
    path, out = Path(path), Path(out)
    if out.exists(): raise ValueError('Refusing existing output')
    counts=Counter(); measurements={}; metadata={}; gene_sets=defaultdict(set)
    with zipfile.ZipFile(path) as z:
        workbook=openpyxl.load_workbook(io.BytesIO(z.read('Raw_file_list.xlsx')),read_only=True,data_only=True)
        for condition, biological, run, technical in list(workbook['immunopep_library_search'].values)[1:]:
            if not run: continue
            record={'condition':str(condition).upper(), 'biological_replicate':str(biological), 'technical_replicate':str(technical)}
            if str(run) in metadata and metadata[str(run)] != record: raise ValueError('Conflicting run identity')
            metadata[str(run)]=record
        with z.open('Search_results_DIA.tsv') as stream:
            for row in csv.DictReader(io.TextIOWrapper(stream), delimiter='\t'):
                counts['rows_read']+=1
                why=accepted(row)
                if why: counts[why]+=1; continue
                run=row['Run']
                if run not in metadata:
                    # Quantity can supervise reconstruction without inventing a KO
                    # or replicate identity. It cannot supervise conditional delta.
                    metadata[run]={'condition':None,'biological_replicate':None,
                                   'technical_replicate':None,'mapping_status':'unmapped_exact_run'}
                    counts['unmapped_run_ids']+=1
                key=(run,row['Precursor.Id'])
                value=float(row['Precursor.Quantity'])
                record=(row['Stripped.Sequence'],value)
                if key in measurements:
                    if measurements[key] != record: raise ValueError('Conflicting duplicate run/precursor measurement')
                    counts['exact_duplicate_precursors']+=1;continue
                measurements[key]=record
                gene_sets[row['Stripped.Sequence']].update(g for g in row.get('Genes','').split(';') if g)
                counts['accepted_precursors']+=1
    # Sum distinct quantified precursor forms within a run; keep run identities.
    abundance=defaultdict(float)
    for (run,_),(peptide,value) in measurements.items(): abundance[run,peptide]+=value
    runs=sorted(metadata); peptides=sorted({p for _,p in abundance});ri={r:i for i,r in enumerate(runs)};pi={p:i for i,p in enumerate(peptides)}
    values=np.zeros((len(runs),len(peptides)),np.float32);observed=np.zeros(values.shape,bool)
    for (run,peptide),value in abundance.items():values[ri[run],pi[peptide]]=np.log2(value);observed[ri[run],pi[peptide]]=True
    out.mkdir(parents=True)
    np.savez_compressed(out/'values.npz',values=values,observed=observed)
    schema={'source_uri':uri,'source_sha256':hashlib.file_digest(path.open('rb'),'sha256').hexdigest(),
        'modality':'presentation','feature_namespace':'peptide_sequence','features':['presentation:'+p for p in peptides],
        'sample_ids':runs,'study_ids':['PXD056426']*len(runs),'sample_metadata':[metadata[r] for r in runs],
        'source_genes':{p:sorted(gene_sets[p]) for p in peptides},'values_file':'values.npz',
        'scale':'log2 summed distinct positive precursor quantities per peptide/run; no per-condition median rescaling',
        'eligible_objective':'masked_assay_reconstruction','downstream_supervision_ready':False,
        'coverage':dict(counts, samples=len(runs), features=len(peptides), observed_entries=int(observed.sum()),missing_entries=int((~observed).sum())),
        'limits':['Missing detection is unobserved, never negative','Technical replicates must share split with biological replicate',
                  'Keep whole study together for cross-study evaluation','Allele-specific binding and assay censoring thresholds not established',
                  'Ambiguous source genes retained as sets, not resolved by first-match','No H4 delta supervision asserted']}
    (out/'schema.json').write_text(json.dumps(schema,indent=2)+'\n')
    return schema

if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser();p.add_argument('--source',required=True);p.add_argument('--output',required=True);p.add_argument('--source-uri',required=True)
    a=p.parse_args();print(json.dumps(prepare(a.source,a.output,a.source_uri)['coverage']))
