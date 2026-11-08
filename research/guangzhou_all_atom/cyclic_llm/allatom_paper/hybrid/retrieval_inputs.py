"""Validate a hash-verified reviewed retrieval store before building its index.

No chemistry is inferred here: canonicalization is an explicit caller dependency.
Source-family/compound/scaffold assignments must already have been reviewed.
"""
import hashlib
import json
import math


def _ids(values, name):
    if isinstance(values, (str, bytes)):
        raise ValueError(name+' must be a collection of IDs')
    values=tuple(values)
    if any(not isinstance(v,str) or not v.strip() for v in values) or len(values)!=len(set(values)):
        raise ValueError(name+' requires unique nonempty IDs')
    return frozenset(values)


def validate_retrieval_inputs(document, *, allowed_score_keys, allowed_source_families,
        forbidden_source_families=(), forbidden_compounds=(), forbidden_scaffolds=(),
        forbidden_targets=(), forbidden_docs=(), allow_synthetic=False, canonicalize):
    """Return (Row-compatible dictionaries, aligned provenance dictionaries).

    Caller verifies document bytes against its frozen hash, permits synthetic data
    only in smoke mode, and rejects an empty store for study runs. Score keys are
    an explicit training-observation whitelist, never inferred from their names.
    No denied row is silently dropped: a contaminated input fails as a whole.
    """
    if not isinstance(document,dict) or document.get('schema')!='reviewed_retrieval_v1':
        raise ValueError('unknown reviewed retrieval schema')
    if set(document)-{'schema','review_status','synthetic','rows'}:
        raise ValueError('unknown reviewed retrieval document fields')
    if 'synthetic' in document and not isinstance(document['synthetic'],bool):
        raise ValueError('synthetic flag must be boolean')
    synthetic=document.get('synthetic',False)
    if synthetic and not allow_synthetic:
        raise ValueError('synthetic retrieval store prohibited')
    if not synthetic and document.get('review_status')!='FROZEN_REVIEWED':
        raise ValueError('retrieval store is not reviewed/frozen')
    allowed=_ids(allowed_source_families,'allowed_source_families')
    forbidden=_ids(forbidden_source_families,'forbidden_source_families')
    score_keys=_ids(allowed_score_keys,'allowed_score_keys')
    if not allowed or not score_keys:raise ValueError('source and training-score whitelists must be nonempty')
    if allowed & forbidden:raise ValueError('source allowlist overlaps forbidden families')
    compounds=_ids(forbidden_compounds,'forbidden_compounds')
    scaffolds=_ids(forbidden_scaffolds,'forbidden_scaffolds')
    targets=_ids(forbidden_targets,'forbidden_targets')
    docs=_ids(forbidden_docs,'forbidden_docs')
    raw_rows=document.get('rows')
    if not isinstance(raw_rows,list):raise ValueError('retrieval rows must be a list')
    rows=[];provenance=[];seen=set()
    fields={'smiles','scores','doc','doc_year','target','source','source_families','compound_id','scaffold_id'}
    for index,row in enumerate(raw_rows):
        if not isinstance(row,dict) or set(row)!=fields:
            raise ValueError('retrieval row has missing or unknown fields')
        for key in ('smiles','doc','target','source','compound_id','scaffold_id'):
            if not isinstance(row[key],str) or not row[key].strip():raise ValueError('retrieval row missing '+key)
        if not isinstance(row['doc_year'],int) or isinstance(row['doc_year'],bool) or not 1000<=row['doc_year']<=9999:
            raise ValueError('retrieval doc_year must be an explicit year')
        if not isinstance(row['source_families'],list):raise ValueError('source_families must be a list')
        families=_ids(row['source_families'],'source_families')
        if not families or not families<=allowed or families & forbidden:
            raise ValueError('retrieval source lineage denied')
        if row['compound_id'] in compounds or row['scaffold_id'] in scaffolds:
            raise ValueError('retrieval compound/scaffold leakage')
        if row['target'] in targets or row['doc'] in docs:
            raise ValueError('retrieval target/document leakage')
        scores=row['scores']
        if not isinstance(scores,dict) or not scores or not set(scores)<=score_keys:
            raise ValueError('retrieval scores must contain only whitelisted training observations')
        if any(isinstance(v,bool) or not isinstance(v,(int,float)) or not math.isfinite(v) for v in scores.values()):
            raise ValueError('retrieval scores must be finite numeric observations')
        chemical=canonicalize(row['smiles'])
        if not isinstance(chemical,(tuple,list)) or len(chemical)!=2 or any(not isinstance(v,str) or not v for v in chemical):
            raise ValueError('retrieval molecule failed canonicalization')
        canonical,flat=chemical
        if canonical in seen:raise ValueError('duplicate canonical retrieval molecule; reviewed aggregation required')
        seen.add(canonical)
        rows.append(dict(smiles=canonical,flat_key=flat,values=dict(scores),doc=row['doc'],
                         doc_year=row['doc_year'],target=row['target'],source=row['source']))
        provenance.append(dict(row_index=index,input_smiles=row['smiles'],smiles=canonical,
            source_families=sorted(families),compound_id=row['compound_id'],scaffold_id=row['scaffold_id'],
            synthetic=synthetic,row_sha256=hashlib.sha256(json.dumps(row,sort_keys=True,allow_nan=False).encode()).hexdigest()))
    return rows,provenance
