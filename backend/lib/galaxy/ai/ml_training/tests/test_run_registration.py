from dataclasses import replace
import json
import sqlite3
from pathlib import Path

import pytest
from galaxy.ai.ml_training.run_registration import (
    OwnedTrainingRun, StagedTrainingOutputs, RunTrainingRegistration,
    RegistrationAccessError, RegistrationConflict,
)
from galaxy.ai.drug_discovery.custom_model_registry import CustomModelRegistry, artifact_sha256


@pytest.fixture
def setup(tmp_path):
    artifact = tmp_path / 'published' / 'artifact'
    artifact.mkdir(parents=True)
    # Inert artifact bytes test persistence without loading/executing any pickle.
    (artifact / 'model.pkl').write_bytes(b'published-model-bytes')
    (artifact / 'metadata.json').write_text('{"model_type":"sklearn_tabular"}')
    run = OwnedTrainingRun('run-1', 'owner', 'project-1', 'completed', 'Tumor subtype',
                           'sklearn_tabular', 'classification', 'auc', 0.7, True)
    document = {'name': run.model_name, 'metrics': {'test_auc': 0.85},
                'gate': {'gates': [{'name': 'auc', 'measured': 0.85, 'threshold': 0.7, 'status': 'pass'}]}}
    staged = StagedTrainingOutputs(str(artifact), artifact_sha256(str(artifact)), document)
    calls = []
    def stage(r):
        calls.append(r.run_id)
        return staged
    core = RunTrainingRegistration(str(tmp_path / 'central'), lambda rid: run if rid == run.run_id else None, stage)
    return core, run, staged, calls


def test_persists_exact_artifact_candidate_without_promotion_and_reopens(setup):
    core, run, staged, _ = setup
    version = core.register('owner', run.run_id)
    assert (version.version, version.status) == (1, 'candidate')
    assert version.created_by == 'owner'
    assert version.artifact_sha256 == staged.expected_artifact_sha256
    assert Path(version.artifact_dir) != Path(staged.artifact_dir)
    db_path = Path(version.artifact_dir).parent.parent / 'models.db'
    reopened = CustomModelRegistry(str(db_path))
    got = reopened.get_version(version.campaign_id, run.model_name, 1)
    assert got.metrics == {'test_auc': 0.85}
    assert got.spec['sourceRunId'] == run.run_id
    assert got.spec['sourceOwnerId'] == run.owner_id
    assert reopened.get_active_version(version.campaign_id, run.model_name) is None


def test_replay_is_idempotent_across_new_core_instances(setup):
    core, run, staged, _ = setup
    one = core.register('owner', run.run_id)
    fresh = RunTrainingRegistration(str(core.root), lambda _: run, lambda _: staged)
    two = fresh.register('owner', run.run_id)
    assert two.version == one.version
    with sqlite3.connect(str(Path(one.artifact_dir).parent.parent / 'models.db')) as db:
        assert db.execute('SELECT COUNT(*) FROM custom_model_versions').fetchone()[0] == 1


def test_failed_gate_is_rejected_and_failed_pipeline_cannot_be_candidate(setup):
    core, run, staged, _ = setup
    staged.metrics_document['gate']['gates'][0].update(measured=0.4, status='halt')
    assert core.register('owner', run.run_id).status == 'rejected'
    run2 = replace(run, run_id='run-2', status='failed')
    staged.metrics_document['gate']['gates'][0].update(measured=0.85, status='pass')
    core2 = RunTrainingRegistration(str(core.root), lambda _: run2, lambda _: staged)
    assert core2.register('owner', run2.run_id).status == 'rejected'


def test_ownership_checked_before_artifact_access(setup):
    core, run, _, calls = setup
    for user, rid in [(None, run.run_id), ('stranger', run.run_id), ('owner', 'unknown')]:
        with pytest.raises(RegistrationAccessError):
            core.register(user, rid)
    assert calls == []
    assert not core.root.exists()


def test_checksum_mismatch_and_mutated_registered_artifact_fail_closed(setup):
    core, run, staged, _ = setup
    (Path(staged.artifact_dir) / 'model.pkl').write_bytes(b'mutated')
    with pytest.raises(RegistrationConflict, match='checksum'):
        core.register('owner', run.run_id)
    (Path(staged.artifact_dir) / 'model.pkl').write_bytes(b'published-model-bytes')
    version = core.register('owner', run.run_id)
    (Path(version.artifact_dir) / 'model.pkl').write_bytes(b'changed-central-model')
    with pytest.raises(RegistrationConflict, match='checksum'):
        core.register('owner', run.run_id)


def test_changed_evidence_cannot_create_new_version_on_replay(setup):
    core, run, staged, _ = setup
    core.register('owner', run.run_id)
    staged.metrics_document['metrics']['test_auc'] = 0.99
    with pytest.raises(RegistrationConflict, match='source changed'):
        core.register('owner', run.run_id)


def test_owner_project_scopes_are_separate_not_client_campaigns(setup):
    core, run, staged, _ = setup
    first = core.register('owner', run.run_id)
    other = replace(run, owner_id='another-owner')
    second = RunTrainingRegistration(str(core.root), lambda _: other, lambda _: staged).register('another-owner', other.run_id)
    assert second.campaign_id != first.campaign_id
    assert second.version == first.version == 1


def test_missing_gate_is_rejected_not_invented_pass(setup):
    core, run, staged, _ = setup
    staged.metrics_document.pop('gate')
    assert core.register('owner', run.run_id).status == 'rejected'


def test_symlink_artifact_is_rejected(setup, tmp_path):
    core, run, staged, _ = setup
    outside = tmp_path / 'private'; outside.write_text('secret')
    (Path(staged.artifact_dir) / 'link').symlink_to(outside)
    with pytest.raises(ValueError, match='symbolic links'):
        core.register('owner', run.run_id)


def test_inconsistent_gate_cannot_override_measured_metrics(setup):
    core, run, staged, _ = setup
    staged.metrics_document['metrics']['test_auc'] = 0.4
    version = core.register('owner', run.run_id)
    assert version.status == 'rejected'
    assert version.metrics['test_auc'] == 0.4


def test_no_gate_threshold_does_not_invent_reviewable_quality(setup):
    core, run, staged, _ = setup
    run = replace(run, gate_threshold=None)
    another = RunTrainingRegistration(str(core.root), lambda _: run, lambda _: staged)
    assert another.register('owner', run.run_id).status == 'rejected'


def test_list_is_owner_project_scoped_and_redacts_local_paths(setup):
    from galaxy.ai.ml_training.run_registration import list_registered_run_versions
    core, run, staged, _ = setup
    core.register('owner', run.run_id)
    rows = list_registered_run_versions(str(core.root), 'owner', run.project_id, run.run_id)
    assert len(rows) == 1 and rows[0]['version'] == 1
    assert 'artifact_dir' not in rows[0]
    assert list_registered_run_versions(str(core.root), 'stranger', run.project_id) == []
    assert list_registered_run_versions(str(core.root), 'owner', 'wrong-project') == []
    assert list_registered_run_versions(str(core.root), 'owner', run.project_id, 'wrong-run') == []


def test_concurrent_registration_creates_one_immutable_version(setup):
    from concurrent.futures import ThreadPoolExecutor
    core, run, staged, _ = setup
    def register(_):
        independent = RunTrainingRegistration(str(core.root), lambda _: run, lambda _: staged)
        return independent.register('owner', run.run_id).version
    with ThreadPoolExecutor(max_workers=2) as executor:
        assert list(executor.map(register, range(2))) == [1, 1]
