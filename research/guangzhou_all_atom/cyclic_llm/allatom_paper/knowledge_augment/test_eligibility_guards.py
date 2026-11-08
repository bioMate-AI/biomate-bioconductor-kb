"""Small synthetic fixtures test guard behavior, not real scientific eligibility."""
import copy
import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from knowledge_augment import levels as L, prompts as PR


@pytest.fixture
def fixture_inputs(tmp_path, monkeypatch):
    monkeypatch.delenv('KA_ALLOW_UNAUDITED', raising=False)
    paths = dict(L.P)
    for key in ('kb', 'direction', 'audit', 'pins', 'ring_lib', 'soft_pot'):
        paths[key] = str(tmp_path / (key + '.json'))
    monkeypatch.setattr(L, 'P', paths)
    monkeypatch.setattr(PR, 'P', paths)
    rule = dict(id='FIXTURE-OK', kind='rule', tier='T1', quote_verified=True,
                weight_eligible=True, direction='-', feat_mapped={'hbd': -1},
                statement='Synthetic fixture only.', weight=999)
    rules = [rule, dict(rule, id='FIXTURE-QUARANTINE'),
             dict(rule, id='FIXTURE-NOT-WEIGHT', weight_eligible=False),
             dict(rule, id='FIXTURE-PROMPT', kind='card', weight_eligible=False)]
    def write(key, data):
        Path(paths[key]).write_text(json.dumps(data))
    write('kb', {'rules': rules})
    write('direction', {'rules': {r['id']: dict(rule_status='agree', n_cells=2, n_agree_cells=2) for r in rules}})
    write('ring_lib', [])
    write('soft_pot', [])
    def evidence():
        write('audit', dict(kb_sha256=L.sha256_file(paths['kb']), entries={
            'FIXTURE-OK': 'eligible', 'FIXTURE-QUARANTINE': 'quarantined',
            'FIXTURE-NOT-WEIGHT': 'eligible', 'FIXTURE-PROMPT': 'prompt_only'}))
        repin()
    def repin():
        write('pins', {out: L.sha256_file(paths[key]) for out, key in (
            ('kb_sha256','kb'), ('eligibility_audit_sha256','audit'),
            ('direction_sha256','direction'), ('groups_sha256','groups'),
            ('ring_library_sha256','ring_lib'), ('soft_potentials_sha256','soft_pot'))})
    return paths, write, evidence, repin


def test_l0_does_not_require_audit(fixture_inputs):
    lv = L.build_level('L0')
    assert lv.lam_soft == 0 and lv.rule_ids == ()
    assert PR.knowledge_block(lv)[0] == ''


@pytest.mark.parametrize('level', ['L1', 'L2'])
def test_missing_audit_blocks_final(fixture_inputs, level):
    with pytest.raises(L.AuditMissing):
        L.build_level(level)


def test_valid_fixture_is_intersection_and_prompt_quarantine(fixture_inputs):
    _, _, evidence, _ = fixture_inputs
    evidence()
    lv = L.build_level('L1')
    assert lv.rule_ids == ('FIXTURE-OK',)
    assert lv.config['audit']['final_eligible']
    assert 'FIXTURE-QUARANTINE' not in lv.prompt_rule_ids
    assert 'FIXTURE-PROMPT' in lv.prompt_rule_ids
    assert all(x['id'] != 'FIXTURE-QUARANTINE' for x in PR.rule_lines(lv, 100))
    assert L.literature_agreed_source(ids=['FIXTURE-OK']).weights['polar'] == -1
    with pytest.raises(L.PinMismatch):
        L.literature_agreed_source(ids=['FIXTURE-QUARANTINE'])
    with pytest.raises(L.PinMismatch):
        L.literature_agreed_source(ids=['FIXTURE-OK', 'FIXTURE-OK'])


def test_custom_kb_does_not_bypass_audit(fixture_inputs, tmp_path):
    paths, _, evidence, _ = fixture_inputs
    evidence()
    kb = json.loads(Path(paths['kb']).read_text())
    kb['rules'][0]['feat_mapped'] = {'hbd': 1}
    custom = tmp_path / 'custom.json'
    custom.write_text(json.dumps(kb))
    with pytest.raises(L.PinMismatch):
        L.literature_agreed_source(kb_path=str(custom), ids=['FIXTURE-OK'])


def test_custom_direction_must_match_pins(fixture_inputs, tmp_path):
    _, _, evidence, _ = fixture_inputs
    evidence()
    p = tmp_path / 'direction-changed.json'
    p.write_text('{"rules": {}}')
    with pytest.raises(L.PinMismatch):
        L.l1_selection(direction_path=str(p))


def test_missing_pins_blocks_final(fixture_inputs):
    paths, _, evidence, _ = fixture_inputs
    evidence()
    Path(paths['pins']).unlink()
    with pytest.raises(L.AuditMissing):
        L.build_level('L1')


def test_dev_status_visible_in_hash_and_prompt(fixture_inputs, monkeypatch):
    _, _, evidence, _ = fixture_inputs
    monkeypatch.setenv('KA_ALLOW_UNAUDITED', '1')
    dev = L.build_level('L1')
    text, meta = PR.knowledge_block(dev, max_tokens=500)
    assert 'UNAUDITED' in text
    assert meta['audit']['final_eligible'] is False
    assert 'UNAUDITED' in dev.labels[0]
    evidence()
    audited = L.build_level('L1')
    assert audited.config_hash != dev.config_hash
    assert audited.config['audit']['eligibility_audit_sha256']


def test_stale_pins_fail_even_in_development(fixture_inputs, monkeypatch):
    paths, write, evidence, _ = fixture_inputs
    evidence()
    pins = json.loads(Path(paths['pins']).read_text())
    pins['kb_sha256'] = 'wrong'
    write('pins', pins)
    monkeypatch.setenv('KA_ALLOW_UNAUDITED', '1')
    with pytest.raises(L.PinMismatch):
        L.build_level('L1')


def test_audit_hash_changes_config_without_changing_selected_weights(fixture_inputs):
    paths, write, evidence, repin = fixture_inputs
    evidence()
    before = L.build_level('L1')
    audit = json.loads(Path(paths['audit']).read_text())
    audit['review_note'] = 'Synthetic revised provenance only'
    write('audit', audit)
    with pytest.raises(L.PinMismatch):
        L.build_level('L1')
    repin()
    after = L.build_level('L1')
    assert before.soft.weights == after.soft.weights
    assert before.config_hash != after.config_hash


@pytest.mark.parametrize('entries', [
    [{'id': 'FIXTURE-OK', 'decision': 'eligible'}, {'id': 'FIXTURE-OK', 'decision': 'eligible'}],
    {'UNKNOWN': 'eligible'}, {'FIXTURE-OK': 'typo'},
])
def test_invalid_audit_rejected(fixture_inputs, entries):
    paths, write, evidence, _ = fixture_inputs
    evidence()
    write('audit', dict(kb_sha256=L.sha256_file(paths['kb']), entries=entries))
    with pytest.raises(L.PinMismatch):
        L.build_level('L1')


def test_duplicate_json_keys_rejected(fixture_inputs):
    paths, _, evidence, _ = fixture_inputs
    evidence()
    Path(paths['audit']).write_text('{"entries": {}, "entries": {}}')
    with pytest.raises(L.PinMismatch):
        L.build_level('L1')
