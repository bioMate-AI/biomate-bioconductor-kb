import json
from pathlib import Path
from types import SimpleNamespace
from galaxy.ai.drug_discovery import regulatory_training_jobs as jobs
from galaxy.ai.drug_discovery import regulatory_training_worker as worker


def test_worker_compiler_input_excludes_foreign_and_unbound_rows(tmp_path, monkeypatch):
    pairs = tmp_path / 'pairs.jsonl'
    rows = [
        {'chosen':'my preference','meta':{'user_id':'owner','org_id':'project'}},
        {'chosen':'foreign secret','meta':{'user_id':'stranger','org_id':'project'}},
        {'chosen':'unbound legacy','meta':{'org_id':'project'}},
        {'chosen':'different project','meta':{'user_id':'owner','org_id':'other'}},
        {'chosen':'global legacy','meta':{}},
    ]
    pairs.write_text(''.join(json.dumps(row)+'\n' for row in rows))
    monkeypatch.setattr(jobs,'DPO_PAIRS_PATH',pairs)
    assert jobs.count_edit_pairs('project','owner') == 1
    job = SimpleNamespace(user_id='owner',org_id='project')
    with worker._owned_pair_file(job) as path:
        serialized = path.read_text()
        assert 'my preference' in serialized
        assert 'foreign secret' not in serialized
        assert 'unbound legacy' not in serialized
        assert 'different project' not in serialized
        assert 'global legacy' not in serialized
        location = path
    assert not location.exists()
    assert len(pairs.read_text().splitlines()) == 5
