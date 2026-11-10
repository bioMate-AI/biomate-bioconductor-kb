"""Synthetic M1 certificate-binding checks; remote CPU QA only."""
import copy
from pathlib import Path
import sys

import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.run_stage1 import validate_m1_evidence


def identity():
    return dict(schema='hybrid_initialization_v1',reference='frozen_adapted_base',
                base_files={'model.safetensors':'base'},adapter_files={'adapter_model.safetensors':'adapter'})


def test_matching_reviewed_real_model_decision_is_accepted():
    expected=identity()
    validate_m1_evidence(dict(passed=True,real_model=True,
                             initialization_identity=copy.deepcopy(expected)),expected)


@pytest.mark.parametrize('field,value',[('passed',False),('passed',1),('passed','true'),
                                      ('real_model',False),('real_model',1),('real_model','true')])
def test_truthy_values_are_not_reviewed_boolean_decisions(field,value):
    expected=identity()
    evidence=dict(passed=True,real_model=True,initialization_identity=expected)
    evidence[field]=value
    with pytest.raises(ValueError,match='M1 has not passed'):
        validate_m1_evidence(evidence,expected)


def test_certificate_for_bare_or_changed_adapter_cannot_validate_adapted_run():
    expected=identity()
    for previous in (None,dict(reference='frozen_initial_base'),
                     dict(expected,adapter_files={'adapter_model.safetensors':'changed'})):
        with pytest.raises(ValueError,match='initialization differs'):
            validate_m1_evidence(dict(passed=True,real_model=True,
                                     initialization_identity=previous),expected)


def test_non_mapping_certificate_fails_closed():
    with pytest.raises(ValueError,match='M1 has not passed'):
        validate_m1_evidence([],identity())
