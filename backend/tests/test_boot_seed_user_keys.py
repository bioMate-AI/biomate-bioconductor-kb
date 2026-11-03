"""The boot-time GALAXY_API_KEY seed must never revoke another user's API key.

Dev 2026-11-03: Galaxy user 1 is a BioMate user (the first one provisioned — the E2E
fixture). _seed_api_key_from_env assumed user 1 is the admin and soft-deleted all of user
1's other keys at every Galaxy boot, so that user's own key died with each restart (key
created 18:31:14, revoked by the 18:33:38 boot; 250+ revoked keys since September) and every
chat workflow request failed with 401 "Provided API key is not valid" until the next login.

Uses Galaxy's real model on in-memory SQLite.
Run: cd backend && PYTHONPATH=lib pytest tests/test_boot_seed_user_keys.py -v
"""
from __future__ import annotations

from types import SimpleNamespace

import pytest
from sqlalchemy import select

from galaxy.model import mapping
from galaxy.webapps.galaxy.fast_factory import _seed_api_key_from_env

ENV_KEY = "e" * 32
MASTER = "m" * 32
USER1_KEY = "1" * 32


@pytest.fixture
def galaxy(monkeypatch):
    model = mapping.init("/tmp", "sqlite://", create_tables=True)
    s = model.context
    user1 = model.User(email="first.biomate.user@example.org", password="x")
    user1.username = "bm_first"
    s.add(user1)
    s.commit()
    assert user1.id == 1  # the situation on dev: user 1 is a real BioMate user
    k = model.APIKeys()
    k.user_id, k.key = user1.id, USER1_KEY
    s.add(k)
    s.commit()
    monkeypatch.setenv("GALAXY_API_KEY", ENV_KEY)

    def app(master=MASTER, admins=("admin@galaxy.org",)):
        return SimpleNamespace(model=model, config=SimpleNamespace(master_api_key=master, admin_users_list=list(admins)))

    return model, app


def _active(model, key):
    row = model.context.scalars(select(model.APIKeys).filter_by(key=key)).first()
    return row is not None and not row.deleted, (row.user_id if row else None)


def test_master_key_env_touches_no_user_keys(galaxy):
    model, app = galaxy
    _seed_api_key_from_env(app(master=ENV_KEY))
    assert _active(model, USER1_KEY) == (True, 1)
    assert model.context.scalars(select(model.APIKeys).filter_by(key=ENV_KEY)).first() is None


def test_regular_env_key_goes_to_admin_and_spares_user1(galaxy):
    model, app = galaxy
    admin = model.User(email="admin@galaxy.org", password="x")
    admin.username = "admin"
    model.context.add(admin)
    stale = model.APIKeys()
    stale.user_id, stale.key = None, "s" * 32
    model.context.commit()
    stale.user_id = admin.id
    model.context.add(stale)
    model.context.commit()

    _seed_api_key_from_env(app())

    assert _active(model, USER1_KEY) == (True, 1)              # the real user's key survives
    assert _active(model, ENV_KEY) == (True, admin.id)         # env key belongs to the admin
    assert _active(model, "s" * 32) == (False, admin.id)       # only the ADMIN's other keys are retired


def test_legacy_env_key_row_on_user1_moves_to_admin(galaxy):
    model, app = galaxy
    admin = model.User(email="admin@galaxy.org", password="x")
    admin.username = "admin"
    model.context.add(admin)
    legacy = model.APIKeys()
    legacy.user_id, legacy.key = 1, ENV_KEY  # what the old seed left on dev (key id 3 on user 1)
    model.context.add(legacy)
    model.context.commit()

    _seed_api_key_from_env(app())

    assert _active(model, ENV_KEY) == (True, admin.id)
    assert _active(model, USER1_KEY) == (True, 1)


def test_no_admin_user_touches_nothing(galaxy):
    model, app = galaxy
    _seed_api_key_from_env(app())  # admin@galaxy.org does not exist (as on dev)
    assert _active(model, USER1_KEY) == (True, 1)
    assert model.context.scalars(select(model.APIKeys).filter_by(key=ENV_KEY)).first() is None
