"""Static reviewed evidence packing only; no neural module, outcomes or priors.

Pure immutable tuples are returned for a downstream tensor adapter. Tests and any
packing of scientific data must run on authorised remote compute. Review labels
are explicit inputs; this module validates contracts, not scientific correctness.
"""
from dataclasses import dataclass
import hashlib
import json
import math
import re

CATEGORIES=('property','endpoint','assay','closure','scaffold','solvent','edit_type',
            'direction','evidence_type','matched_comparison')
REQUIRED_SCOPE=frozenset(CATEGORIES[:6])
SCOPE_FIELDS=REQUIRED_SCOPE | {'target','site'}
RECORD_FIELDS={'id','permission','review_status','unresolved_flags','source_families',
    'source_id','quote','quote_start','quote_end','scope','parent_ids','embedding_parent_id',
    'categories','position_specific','review_revision','extraction_revision',
    'raw_record_sha256','reviewer_id','reviewer_type'}


def content_digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False,
        separators=(',',':'),allow_nan=False).encode()).hexdigest()


def _exact(value,keys,name):
    if not isinstance(value,dict) or set(value)!=set(keys):
        raise ValueError(name+' has missing or unknown fields')


def _names(value,name,nonempty=True):
    if not isinstance(value,(list,tuple)) or any(not isinstance(v,str) or not v.strip() for v in value):
        raise ValueError(name+' must contain explicit IDs')
    if len(set(value))!=len(value) or (nonempty and not value):
        raise ValueError(name+' contains duplicate or absent IDs')
    return frozenset(value)


def _scope(value):
    if not isinstance(value,dict) or set(value)-SCOPE_FIELDS:
        raise ValueError('unknown scope fields; outcome labels are forbidden')
    if any(not isinstance(v,str) or not v.strip() or v=='*' for v in value.values()):
        raise ValueError('scope requires explicit values')
    return value


@dataclass(frozen=True)
class StaticMemory:
    # Shapes M x d_e, M x len(CATEGORIES), M; index zero is always null.
    molecular: tuple
    categorical: tuple
    categorical_present: tuple
    molecular_present: tuple
    eligible: tuple
    slot_type: tuple                 # 0 null/padding; 1 static evidence
    numeric: tuple                   # M x 0: numeric priors not implemented
    numeric_present: tuple
    audit_json: str                   # non-predictor lineage; never tensorise
    digest: str


def pack_static_memory(catalogue,feature_schema,embeddings,*,catalogue_digest,
        schema_digest,embeddings_digest,task_scope,parent_ids,allowed_source_families,
        forbidden_source_families=(),forbidden_targets=(),forbidden_parent_ids=(),enabled=True,
        max_slots=16,allow_synthetic=False):
    """Pack one group; downstream batching must preserve the returned digest.

    Embeddings are precomputed frozen features supplied externally. Only records
    explicitly approved for learned conditioning can enter; parent-selection
    permissions do not transfer. No observed-history channel is accepted.
    Ordering is evidence-ID lexical order; capacity includes the null slot.
    """
    if type(max_slots) is not int or max_slots<1:raise ValueError('max_slots must be positive integer')
    if type(enabled) is not bool:raise ValueError('enabled must be boolean')
    for obj,expected in ((catalogue,catalogue_digest),(feature_schema,schema_digest),(embeddings,embeddings_digest)):
        if content_digest(obj)!=expected:raise ValueError('frozen input digest mismatch')
    _exact(feature_schema,{'schema','categories','embedding_width'},'feature schema')
    if feature_schema['schema']!='static_knowledge_features_v1':raise ValueError('unknown feature schema')
    _exact(feature_schema['categories'],CATEGORIES,'categorical vocabulary')
    vocab={}
    for key in CATEGORIES:
        values=feature_schema['categories'][key]
        _names(values,'category vocabulary')
        if list(values[:2])!=['__missing__','__unknown__']:raise ValueError('missing/unknown categories must be reserved')
        vocab[key]={v:i for i,v in enumerate(values)}
    width=feature_schema['embedding_width']
    if type(width) is not int or width<1:raise ValueError('embedding width must be positive')
    _exact(embeddings,{'schema','encoder_identity','review_status','vectors'},'embedding snapshot')
    if embeddings['schema']!='approved_frozen_embeddings_v1' or embeddings['review_status']!='FROZEN_REVIEWED':
        raise ValueError('embedding snapshot is not approved')
    if not isinstance(embeddings['encoder_identity'],str) or not embeddings['encoder_identity']:
        raise ValueError('encoder identity missing')
    if not isinstance(embeddings['vectors'],dict):raise ValueError('embedding vectors must be a mapping')
    _exact(catalogue,{'schema','synthetic','review_status','sources','evidence'},'catalogue')
    if catalogue['schema']!='learned_conditioning_catalogue_v1':raise ValueError('unknown catalogue schema')
    if type(catalogue['synthetic']) is not bool:raise ValueError('invalid synthetic flag')
    if catalogue['synthetic'] and not allow_synthetic:raise ValueError('synthetic catalogue prohibited')
    if catalogue['review_status']!='FROZEN_REVIEWED':raise ValueError('catalogue not frozen reviewed')
    if not isinstance(catalogue['sources'],dict) or not isinstance(catalogue['evidence'],list):
        raise ValueError('invalid catalogue containers')
    task=_scope(task_scope)
    parents=_names(parent_ids,'approved group parents')
    forbidden_parents=_names(forbidden_parent_ids,'forbidden parents',False)
    if parents & forbidden_parents:raise ValueError('group contains forbidden parent')
    allowed=_names(allowed_source_families,'allowed families')
    forbidden=_names(forbidden_source_families,'forbidden families',False)
    targets=_names(forbidden_targets,'forbidden targets',False)
    if allowed & forbidden:raise ValueError('source split overlaps')
    if task.get('target') in targets:raise ValueError('forbidden task target')
    records=catalogue['evidence'];ids=[]
    for row in records:
        if not isinstance(row,dict) or not isinstance(row.get('id'),str) or not row['id']:
            raise ValueError('missing evidence identity')
        ids.append(row['id'])
    if len(set(ids))!=len(ids):raise ValueError('duplicate evidence IDs')
    admitted=[];denied=[]
    for row in sorted(records,key=lambda r:r['id']):
        eid=row['id']
        families=_names(row.get('source_families'),'evidence families')
        # Denied lineage is never dereferenced for source text or molecular vectors.
        if not families<=allowed or families & forbidden:
            denied.append((eid,'source_denied'));continue
        _exact(row,RECORD_FIELDS,'evidence record')
        if row['permission']!='learned_conditioning' or row['review_status']!='approved_for_learned_conditioning':
            denied.append((eid,'learned_permission_missing'));continue
        if row['unresolved_flags']!=[]:
            denied.append((eid,'unresolved_evidence'));continue
        scope=_scope(row['scope'])
        mapped=_names(row['parent_ids'],'evidence parents')
        if (not REQUIRED_SCOPE<=set(scope) or scope.get('target') in targets
                or not mapped & parents or any(task.get(k)!=v for k,v in scope.items())):
            denied.append((eid,'inapplicable_scope_or_parent'));continue
        if type(row['position_specific']) is not bool:raise ValueError('position_specific must be boolean')
        if row['position_specific']:
            denied.append((eid,'local_position_not_supported'));continue
        if not enabled:
            denied.append((eid,'knowledge_disabled'));continue
        if not isinstance(row['raw_record_sha256'],str) or not re.fullmatch(r'[0-9a-f]{64}',row['raw_record_sha256']):
            raise ValueError('immutable raw-record hash missing or invalid')
        if not isinstance(row['reviewer_id'],str) or not row['reviewer_id'].strip():
            raise ValueError('reviewer identity missing')
        if row['reviewer_type'] not in ('human','ai_assisted'):
            raise ValueError('reviewer type missing or invalid')
        if not all(isinstance(row[k],str) and row[k] for k in ('source_id','review_revision','extraction_revision')):
            raise ValueError('review/source revision missing')
        source=catalogue['sources'].get(row['source_id'])
        _exact(source,{'text','sha256','url'},'source record')
        if not all(isinstance(source[k],str) and source[k] for k in source):raise ValueError('source metadata missing')
        if hashlib.sha256(source['text'].encode()).hexdigest()!=source['sha256']:raise ValueError('source hash mismatch')
        start,end=row['quote_start'],row['quote_end']
        if (type(start) is not int or type(end) is not int or not 0<=start<end<=len(source['text'])
                or not isinstance(row['quote'],str) or source['text'][start:end]!=row['quote']):
            raise ValueError('source quotation mismatch')
        cats=row['categories'];_exact(cats,CATEGORIES,'evidence categorical payload')
        for key in REQUIRED_SCOPE:
            if cats[key]!=scope[key]:raise ValueError('categorical scope mismatch')
        cat_values=[];cat_masks=[]
        for key in CATEGORIES:
            value=cats[key]
            if value is not None and (not isinstance(value,str) or not value or value.startswith('__')):
                raise ValueError('categorical payload must be a string or null')
            cat_values.append(0 if value is None else vocab[key].get(value,1))
            cat_masks.append(value is not None)
        parent=row['embedding_parent_id'];vector=(0.0,)*width;present=False
        if parent is not None:
            if not isinstance(parent,str) or not parent:raise ValueError('invalid embedding parent identity')
            if parent in forbidden_parents:raise ValueError('embedding parent is forbidden')
            if parent not in mapped or parent not in parents:raise ValueError('embedding parent not approved for group')
            raw=embeddings['vectors'].get(parent)
            if raw is not None:
                if not isinstance(raw,list) or len(raw)!=width or any(type(v) not in (int,float) or not math.isfinite(v) for v in raw):
                    raise ValueError('invalid frozen embedding shape/value')
                vector=tuple(float(v) for v in raw);present=True
        admitted.append((eid,vector,tuple(cat_values),tuple(cat_masks),present,row))
    selected=admitted[:max_slots-1]
    molecular=[(0.0,)*width];categorical=[(0,)*len(CATEGORIES)]
    cat_present=[(False,)*len(CATEGORIES)];mol_present=[False];mask=[True];types=[0]
    for eid,vector,cat,available,present,row in selected:
        molecular.append(vector);categorical.append(cat);cat_present.append(available)
        mol_present.append(present);mask.append(True);types.append(1)
    while len(mask)<max_slots:
        molecular.append((0.0,)*width);categorical.append((0,)*len(CATEGORIES));cat_present.append((False,)*len(CATEGORIES))
        mol_present.append(False);mask.append(False);types.append(0)
    audit=dict(catalogue_digest=catalogue_digest,schema_digest=schema_digest,embeddings_digest=embeddings_digest,
        encoder_identity=embeddings['encoder_identity'],enabled=enabled,task_scope=task,parent_ids=sorted(parents),
        forbidden_parent_ids=sorted(forbidden_parents),
        selected=[dict(id=r[0],source_id=r[5]['source_id'],review_revision=r[5]['review_revision'],
                       raw_record_sha256=r[5]['raw_record_sha256'],reviewer_id=r[5]['reviewer_id'],
                       reviewer_type=r[5]['reviewer_type'],extraction_revision=r[5]['extraction_revision'],
                       quote_start=r[5]['quote_start'],quote_end=r[5]['quote_end']) for r in selected],
        denied=denied,dropped_ids=[r[0] for r in admitted[max_slots-1:]])
    audit_json=json.dumps(audit,sort_keys=True,separators=(',',':'))
    payload=dict(molecular=molecular,categorical=categorical,categorical_present=cat_present,
        molecular_present=mol_present,eligible=mask,slot_type=types,numeric=[()]*max_slots,
        numeric_present=[()]*max_slots,audit=audit)
    return StaticMemory(tuple(molecular),tuple(categorical),tuple(cat_present),tuple(mol_present),
        tuple(mask),tuple(types),tuple(() for _ in mask),tuple(() for _ in mask),audit_json,content_digest(payload))
