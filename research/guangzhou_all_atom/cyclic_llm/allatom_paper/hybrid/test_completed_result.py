"""Synthetic finalisation identity checks; run on EC2, no model imports."""
import json
from pathlib import Path
import sys

import pytest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from hybrid.run_stage1 import completed_result, file_sha


def write_result(root):
    (root/'run_identity.json').write_text('{"synthetic":"run1"}')
    initialization={'reference':'frozen_adapted_base','adapter_files':{'a':'synthetic'}}
    result=dict(execution_completed=True,initialization_identity=initialization,
                run_identity_sha256=file_sha(root/'run_identity.json'),heldout={'toy':0.25})
    (root/'result.json').write_text(json.dumps(result))
    return initialization,result


def test_absent_result_allows_first_execution(tmp_path):
    assert completed_result(tmp_path,{'reference':'bare'}) is None


def test_completed_output_is_returned_unchanged(tmp_path):
    initialization,result=write_result(tmp_path)
    assert completed_result(tmp_path,initialization)==result


def test_changed_initialization_or_run_rejects_existing_output(tmp_path):
    initialization,_=write_result(tmp_path)
    with pytest.raises(ValueError,match='different initialization/run'):
        completed_result(tmp_path,{'reference':'frozen_initial_base'})
    (tmp_path/'run_identity.json').write_text('{"synthetic":"other"}')
    with pytest.raises(ValueError,match='different initialization/run'):
        completed_result(tmp_path,initialization)


@pytest.mark.parametrize('flag',[None,False,'true'])
def test_incomplete_or_legacy_result_does_not_authorize_rescoring(tmp_path,flag):
    initialization,result=write_result(tmp_path)
    if flag is None:
        result.pop('execution_completed')
    else:
        result['execution_completed']=flag
    (tmp_path/'result.json').write_text(json.dumps(result))
    with pytest.raises(ValueError,match='incomplete'):
        completed_result(tmp_path,initialization)
