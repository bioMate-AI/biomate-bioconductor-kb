"""Prospective synthetic parser regressions; run on isolated EC2, not locally."""
import pytest
import seq2smiles as s


@pytest.mark.parametrize('sequence',['Ac-Ala-Gly-Phe','Ala-Gly-Phe-NH2','Ala-Gly-Phe-OH'])
def test_unsupported_caps_are_not_silently_deleted(sequence):
    with pytest.raises(s.ConvertError,match='terminal modification'):
        s.to_smiles(sequence)


@pytest.mark.parametrize('sequence',['Ala-N-Me-Pro-Gly','Ala-NMe-Hyp-Gly'])
def test_n_methyl_proline_is_not_silently_ignored(sequence):
    with pytest.raises(s.ConvertError,match='N-methyl Pro/Hyp'):
        s.to_smiles(sequence)


def test_compact_one_letter_aspartate_is_not_d_prefix():
    residues,cyclic=s.parse_tokens('DAG')
    assert residues == [('Asp',False,False),('Ala',False,False),('Gly',False,False)]
    assert not cyclic


def test_delimited_one_letter_aspartate_is_preserved():
    assert s.parse_tokens('D-A-G')[0] == s.parse_tokens('DAG')[0]


def test_standalone_nme_matches_explicit_n_me():
    assert s.parse_tokens('Ala-NMe-Phe-Gly')[0] == s.parse_tokens('Ala-N-Me-Phe-Gly')[0]


def test_three_letter_d_prefix_still_supported():
    assert s.parse_tokens('Ala-D-Phe-Gly')[0][1] == ('Phe',True,False)


def test_modifier_order_does_not_invent_an_aspartate_residue():
    assert s.parse_tokens('Ala-NMe-D-Phe-Gly')[0] == s.parse_tokens('Ala-D-NMe-Phe-Gly')[0]
    assert s.parse_tokens('Ala-D-N-Me-Phe-Gly')[0] == s.parse_tokens('Ala-D-NMe-Phe-Gly')[0]
    assert len(s.parse_tokens('Ala-NMe-D-Phe-Gly')[0]) == 3


def test_explicit_l_prefix_is_not_an_extra_leucine():
    assert s.parse_tokens('Ala-L-Phe-Gly')[0] == s.parse_tokens('Ala-Phe-Gly')[0]
    assert s.parse_tokens('L-A-G')[0][0] == ('Leu',False,False)


def test_histidine_one_letter_is_not_deleted_as_terminal_hydrogen():
    assert s.parse_tokens('H-A-G')[0][0] == ('His',False,False)
    with pytest.raises(s.ConvertError,match='ambiguous terminal H'):
        s.to_smiles('H-Ala-Gly-Phe')


def test_compact_cyclic_wrapper_recovers_tokens_without_guessing_closure():
    assert s.parse_tokens('cyclo(AGF)') == (s.parse_tokens('AGF')[0],True)
    with pytest.raises(s.ConvertError,match='closure topology'):
        s.to_smiles('cyclo(AGF)')
    assert s.to_smiles('cyclo(AGF)',closure='head_to_tail')[1:] == (True,3)


@pytest.mark.parametrize('sequence',['AGF2','AGF*','Ala(3)-Gly-Phe','cycloAGF'])
def test_annotations_are_not_silently_stripped(sequence):
    with pytest.raises(s.ConvertError):
        s.to_smiles(sequence)


@pytest.mark.parametrize('sequence',['Ala-Ile-Gly','Ala-Thr-Gly','Ala-Hyp-Gly'])
def test_missing_side_chain_stereochemistry_is_not_a_faithful_structure(sequence):
    with pytest.raises(s.ConvertError,match='side-chain stereochemistry'):
        s.to_smiles(sequence)


@pytest.mark.parametrize('text',['potency 5.3 nM','potency -5 nM','potency 5e-3 nM','Example 15 compound'])
def test_number_occurrence_does_not_match_other_numeric_values(text):
    import verify_patent as v
    assert not v.num_ok({'value':5},text,text)


def test_occurrence_does_not_certify_compound_activity_linkage():
    import verify_patent as v
    passage='Compound A was synthesised successfully whereas Compound B had activity 5 nM.'
    item=dict(kind='example_compound',statement='Compound A activity',compound_id='Compound A',
              quote=passage,activity={'value':5,'unit':'nM','assay':'binding'},structure_format='none')
    ok,_,quality=v.verify(item,passage,passage)
    assert ok and quality['activity_numeric_occurrence']
    assert quality['activity_linkage_status']=='unreviewed' and not quality['method_prior_eligible']


@pytest.mark.parametrize('sequence',['Ala','ala','ALA','aLa'])
def test_single_named_residue_is_not_three_one_letter_residues(sequence):
    with pytest.raises(s.ConvertError,match='fewer than 3'):
        s.to_smiles(sequence)


def test_explicit_one_letter_separators_resolve_named_residue_ambiguity():
    assert s.parse_tokens('A-L-A')[0] == [('Ala',False,False),('Leu',False,False),('Ala',False,False)]


def test_repair_sidecar_preserves_original_and_does_not_promote_candidates():
    import copy
    from repair_sidecar import repair_record
    original=dict(item_id='synthetic',structure_string='Ala-Gly-Phe',structure_format='sequence',
                  structure_status='old_status',activity={'value':5})
    before=copy.deepcopy(original)
    result=repair_record(original)
    assert original==before and result['original']==before
    assert result['repair']['reconstruction_status']=='reconstructed_unreviewed'
    assert result['repair']['graph_parse_ok'] and not result['repair']['method_prior_eligible']
    original['structure_string']='cyclo(AGF)'
    assert repair_record(original)['repair']['reconstruction_status']=='unresolved'


def test_sidecar_hashes_exact_source_bytes_including_crlf():
    import hashlib
    from repair_sidecar import repair_line
    raw=b'{"item_id":"synthetic","structure_format":"name","structure_string":"Compound 1"}\r\n'
    result=repair_line(raw,'source-hash',7)
    assert result['original_record_sha256']==hashlib.sha256(raw).hexdigest()
    assert result['original_record_sha256']!=hashlib.sha256(raw.replace(b'\r\n',b'\n')).hexdigest()
    assert result['input_line']==7 and result['input_sha256']=='source-hash'


@pytest.mark.parametrize('raw',[b'[]\n',b'null\n',b'"not an object"\n'])
def test_sidecar_rejects_non_object_original_records(raw):
    from repair_sidecar import repair_line
    with pytest.raises(ValueError,match='must be a JSON object'):
        repair_line(raw,'source-hash',1)
