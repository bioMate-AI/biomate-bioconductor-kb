"""Synthetic filesystem/time contracts. Execute only in isolated EC2 QA."""
import pytest
from hybrid.run_guard import bind_run, remaining_seconds


def test_restart_cannot_reset_deadline(tmp_path):
    original = bind_run(tmp_path, {'seed': 1}, 100, now=10)
    restored = bind_run(tmp_path, {'seed': 1}, 100, now=60)
    assert restored == original
    assert remaining_seconds(restored, now=80) == 30
    with pytest.raises(ValueError, match='exhausted'):
        bind_run(tmp_path, {'seed': 1}, 100, now=110)


def test_changed_identity_fails(tmp_path):
    bind_run(tmp_path, {'seed': 1}, 100, now=10)
    with pytest.raises(ValueError, match='identity differs'):
        bind_run(tmp_path, {'seed': 2}, 100, now=20)


def test_legacy_checkpoint_fails(tmp_path):
    (tmp_path / 'checkpoint').mkdir()
    (tmp_path / 'checkpoint' / 'ckpt.json').write_text('{}')
    with pytest.raises(ValueError, match='legacy checkpoint'):
        bind_run(tmp_path, {}, 100, now=10)


def test_clock_rollback_and_duration_change_fail(tmp_path):
    record = bind_run(tmp_path, {}, 100, now=10)
    with pytest.raises(ValueError, match='backwards'):
        remaining_seconds(record, now=9)
    with pytest.raises(ValueError, match='duration differs'):
        bind_run(tmp_path, {}, 200, now=20)
