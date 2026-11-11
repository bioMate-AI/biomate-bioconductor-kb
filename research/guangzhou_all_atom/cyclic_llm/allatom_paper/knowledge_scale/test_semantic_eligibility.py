"""Synthetic review contracts, not evidence-quality measurements. Run on AWS only."""
import hashlib
from eligibility import assess_review,record_sha256
from verify import number_ok,schema_errors,strict_ok


def fixture():
    text='Synthetic scaffold comparison supports only its named endpoint.'
    record={'id':'SYNTHETIC','quote':text,'direction':'increases'}
    review=dict(schema='k2_semantic_review_v1',record_id='SYNTHETIC',raw_sha256=record_sha256(record),
        review_status='APPROVED_SCOPED_CLAIM',reviewer_type='ai_assisted',reviewer_id='synthetic',
        review_revision='fixture',reviewed_at='2026-10-29',source_id='SYNTHETIC',source_url='https://example.invalid',
        claim=text,claim_origin='primary_result',source_sha256=hashlib.sha256(text.encode()).hexdigest(),
        quote=text,quote_start=0,quote_end=len(text),unresolved_flags=[],source_families=['SYNTHETIC'],
        scope={k:'synthetic' for k in ('property','assay','scaffold','closure','solvent','endpoint')},
        checks={k:'supported' for k in ('endpoint','entity','direction','comparator','scope','claim_origin',
        'source_overlap','compound_overlap','scaffold_overlap','target_overlap')},
        requested_permission='conditional_proposal',action='select_parent',approved_parent_ids=['P1'],
        parent_map_sha256='1'*64,applicability_review='APPROVED')
    return record,review,text


def test_complete_review_contract_and_original_unchanged():
    record,review,text=fixture();before=dict(record)
    assert assess_review(record,review,text)['permission']=='conditional_proposal'
    assert record==before


def test_quote_or_strict_status_alone_never_grants_permission():
    record,review,text=fixture()
    for field in ('checks','raw_sha256','source_families','approved_parent_ids','review_status'):
        bad=dict(review);bad.pop(field)
        assert assess_review(record,bad,text)['permission']=='quarantined'


def test_parent_map_hash_requires_hexadecimal_digest():
    record,review,text=fixture()
    review['parent_map_sha256']='z'*64
    assert 'parent_map_hash_missing' in assess_review(record,review,text)['reasons']


def test_changed_raw_source_background_and_numeric_prior_rejected():
    record,review,text=fixture()
    assert assess_review(dict(record,direction='decreases'),review,text)['permission']=='quarantined'
    assert assess_review(record,review,text+' changed')['permission']=='quarantined'
    for change in ({'claim_origin':'review_background'},{'requested_permission':'numeric_prior'},
                   {'action':'methylate'},{'unresolved_flags':['direction']}):
        assert assess_review(record,dict(review,**change),text)['permission']=='quarantined'


def test_number_occurrence_preserves_sign_and_decimal_boundaries():
    assert not number_ok({'value':5},'energy -5','energy -5')
    assert not number_ok({'value':5},'energy −5','energy −5')
    assert not number_ok({'value':5},'energy 5.2','energy 5.2')
    assert number_ok({'value':-5},'energy -5','energy -5')
    assert not number_ok({'value':float('inf')},'inf','inf')


def test_malformed_fields_and_nan_confidence_fail_closed():
    assert schema_errors(['not','object'])
    assert schema_errors({'statement':42,'quote':[],'scope':{}})
    rule=dict(proxy_entailment='YES',confidence=float('nan'),quote='cyclic peptide permeability',
              statement='permeability increases',property='permeability',direction='increases')
    assert not strict_ok(rule)
