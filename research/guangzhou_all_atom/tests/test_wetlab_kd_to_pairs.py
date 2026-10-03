import sys
from pathlib import Path
import pytest
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from wetlab_kd_to_pairs import build, _parse_kd


def pairs(tmp_path, value, strong='12', drop_weak=False):
    csv = tmp_path / 'kd.csv'
    csv.write_text(f'id,seq,target,kd_nM\nA,ACDE,T,{strong}\nB,FGHI,T,{value}\n')
    return build(csv, drop_weak=drop_weak)[0].pairs


@pytest.mark.parametrize('value', ['', 'NA', 'n/a', 'none'])
def test_missing_is_not_a_negative(tmp_path, value):
    assert not pairs(tmp_path, value)


@pytest.mark.parametrize('value', ['typo', 'NaN', 'inf', '0', '-1', '>bad'])
def test_invalid_measurements_fail_closed(tmp_path, value):
    with pytest.raises(ValueError, match='Row 3'): pairs(tmp_path, value)


def test_censoring_does_not_reverse_preference(tmp_path):
    assert not pairs(tmp_path, '>50', strong='800')
    result = pairs(tmp_path, '>1000')
    assert len(result) == 1 and not result[0].weak
    assert result[0].provenance['rejected'] == 'measured_KD_lower_bound'


def test_qualitative_nonbinder_is_weak(tmp_path):
    assert pairs(tmp_path, 'nb')[0].weak
    assert not pairs(tmp_path, 'nb', drop_weak=True)


def test_units_and_noise(tmp_path):
    assert _parse_kd('1.2μM') == 1200
    assert not pairs(tmp_path, '15')
    assert pairs(tmp_path, '1.2uM')[0].chosen_id == 'A'
