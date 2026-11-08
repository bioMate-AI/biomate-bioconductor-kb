"""Synthetic data only; caller supplies a fake canonicalizer, no chemistry run."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.retrieval_inputs import validate_retrieval_inputs


def document():
    return dict(schema='reviewed_retrieval_v1',review_status='FROZEN_REVIEWED',synthetic=True,rows=[
        dict(smiles='SYNTHETIC',scores={'train':1.2},doc='DOC',doc_year=2020,target='TARGET',
             source='synthetic',source_families=['ALLOWED'],compound_id='CMP',scaffold_id='SCAF')])


def check(doc,**kw):
    args=dict(allowed_score_keys=['train'],allowed_source_families=['ALLOWED'],
              allow_synthetic=True,canonicalize=lambda s:('CANON','FLAT'))
    args.update(kw)
    return validate_retrieval_inputs(doc,**args)


def test_row_compatible_output_preserves_provenance():
    rows,provenance=check(document())
    assert rows[0]==dict(smiles='CANON',flat_key='FLAT',values={'train':1.2},doc='DOC',doc_year=2020,target='TARGET',source='synthetic')
    assert provenance[0]['compound_id']=='CMP' and provenance[0]['source_families']==['ALLOWED']
    assert len(provenance[0]['row_sha256'])==64


@pytest.mark.parametrize('name,value',[('forbidden_source_families',['ALLOWED']),
    ('forbidden_compounds',['CMP']),('forbidden_scaffolds',['SCAF']),
    ('forbidden_targets',['TARGET']),('forbidden_docs',['DOC'])])
def test_exclusions_reject_whole_input(name,value):
    with pytest.raises(ValueError):check(document(),**{name:value})


@pytest.mark.parametrize('scores',[{'heldout':1.0},{'train':float('nan')},{'train':float('inf')},{'train':True},{}])
def test_only_finite_training_observations(scores):
    doc=document();doc['rows'][0]['scores']=scores
    with pytest.raises(ValueError):check(doc)


def test_synthetic_opt_in_and_real_review_required():
    with pytest.raises(ValueError,match='synthetic'):check(document(),allow_synthetic=False)
    doc=document();doc['synthetic']=False;doc['review_status']='DRAFT'
    with pytest.raises(ValueError,match='reviewed'):check(doc)


def test_duplicate_or_invalid_chemistry_rejected():
    doc=document();doc['rows'].append(dict(doc['rows'][0],smiles='OTHER'))
    with pytest.raises(ValueError,match='duplicate'):check(doc)
    with pytest.raises(ValueError,match='canonicalization'):check(document(),canonicalize=lambda s:None)


def test_unknown_provenance_and_extra_labels_rejected():
    doc=document();doc['rows'][0]['source_families']=[]
    with pytest.raises(ValueError,match='lineage'):check(doc)
    doc=document();doc['rows'][0]['heldout_score']=1.0
    with pytest.raises(ValueError,match='unknown fields'):check(doc)


def test_empty_rows_explicitly_returned_for_caller_study_gate():
    doc=document();doc['rows']=[]
    assert check(doc)==([],[])
