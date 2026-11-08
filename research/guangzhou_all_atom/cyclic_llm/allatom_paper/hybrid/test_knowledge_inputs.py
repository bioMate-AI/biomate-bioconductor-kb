"""Synthetic configuration checks; not evidence qualification."""
from pathlib import Path
import sys
import pytest
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.knowledge_inputs import resolve_knowledge_inputs


def fixture():
    policy=dict(review_status='FROZEN_REVIEWED',allowed_source_families=['EXTERNAL_REVIEWED'],
                forbidden_source_families=['EXCLUDED_EXTERNAL'])
    return dict(scope={'property':'synthetic'},source_policy=policy),dict(knowledge_source_policy=policy)


def test_explicit_external_family_is_allowed_without_assay_membership():
    task,manifest=fixture()
    scope,allowed,forbidden=resolve_knowledge_inputs(task,manifest,study=True,
        training_source_families=['TRAIN'],forbidden_source_families=['STOP','HELDOUT'])
    assert allowed==('EXTERNAL_REVIEWED',) and scope=={'property':'synthetic'}
    assert set(forbidden)=={'STOP','HELDOUT','EXCLUDED_EXTERNAL'}


def test_study_policy_must_be_frozen_and_cannot_override_heldout():
    task,manifest=fixture()
    with pytest.raises(ValueError,match='differs'):
        resolve_knowledge_inputs(task,{},study=True)
    with pytest.raises(ValueError,match='overlaps'):
        resolve_knowledge_inputs(task,manifest,study=True,forbidden_source_families=['EXTERNAL_REVIEWED'])
    with pytest.raises(ValueError,match='explicit reviewed'):
        resolve_knowledge_inputs({'property':'synthetic'},manifest,study=True)


def test_scope_only_is_legacy_smoke_only():
    scope,allowed,forbidden=resolve_knowledge_inputs({'property':'synthetic'},{},study=False,
        training_source_families=['TRAIN'],forbidden_source_families=['STOP'])
    assert allowed==('TRAIN',) and forbidden==('STOP',)


def test_bad_source_policy_rejected():
    task,manifest=fixture()
    task['source_policy']['allowed_source_families']=['EXTERNAL_REVIEWED','EXTERNAL_REVIEWED']
    with pytest.raises(ValueError,match='unique'):
        resolve_knowledge_inputs(task,manifest,study=True)
