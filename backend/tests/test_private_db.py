"""
Unit tests for the Private DB Connect capability (galaxy.ai.private_db).

Three groups:
  * validator  — the SELECT-only SQL guard (SECURITY CORE). Runs standalone with
                 NO galaxy/sqlalchemy runtime: `pytest -k validator`.
  * vault      — creds round-trip through a mocked Galaxy Vault (per-user namespace).
  * resolver   — ownership: user A cannot resolve user B's connection.

The executor (SQLAlchemy) is NOT exercised here — it needs a live Postgres; that
is the integration test in the plan (§2.3). These unit tests cover the security
core that must hold with zero infra.
"""
import json
import sys
from pathlib import Path

import pytest

# Make galaxy.ai.private_db importable without standing up Galaxy. private_db
# imports galaxy/sqlalchemy lazily (inside functions), so the module imports even
# when those are absent — this keeps the validator tests infra-free.
_LIB = Path(__file__).parents[1] / "lib"
if str(_LIB) not in sys.path:
    sys.path.insert(0, str(_LIB))

from galaxy.ai import private_db  # noqa: E402
from galaxy.ai.private_db import validate_readonly_sql, SqlValidationError  # noqa: E402


# =============================================================================
# validator — SECURITY CORE. Must pass with no galaxy runtime.
# =============================================================================

class TestValidatorAccepts:
    """Legitimate read-only queries MUST pass."""

    @pytest.mark.parametrize("sql", [
        "SELECT 1",
        "select * from patients",
        "SELECT count(*) FROM patients WHERE egfr_mutation = true",
        "  SELECT id, name FROM t  ",
        "SELECT 1;",                          # single trailing semicolon allowed
        "SELECT a FROM t -- trailing comment", # comment stripped, still a SELECT
        "WITH cte AS (SELECT * FROM t) SELECT * FROM cte",
        "with recursive r as (select 1) select * from r",
        "SELECT * FROM t JOIN u ON t.id = u.id WHERE u.x IN (SELECT y FROM z)",
    ])
    def test_validator_accepts_selects(self, sql):
        out = validate_readonly_sql(sql)
        assert out  # returns cleaned statement
        assert out.lower().lstrip().startswith(("select", "with"))


class TestValidatorRejects:
    """Everything that is not a single read-only SELECT MUST be rejected."""

    @pytest.mark.parametrize("sql", [
        "DROP TABLE patients",
        "drop table patients",
        "DELETE FROM patients",
        "UPDATE patients SET x = 1",
        "INSERT INTO patients VALUES (1)",
        "ALTER TABLE patients ADD COLUMN x int",
        "CREATE TABLE evil (id int)",
        "TRUNCATE patients",
        "GRANT ALL ON patients TO evil",
        "SELECT 1; DROP TABLE patients",             # multi-statement
        "SELECT 1; DELETE FROM patients",            # multi-statement DML
        "SELECT 1;DROP TABLE patients",              # multi-statement, no space
        "SELECT 1 -- ok\n; DROP TABLE patients",     # comment then 2nd stmt
        "SELECT 1 /* x */; DROP TABLE patients",     # block comment then 2nd stmt
        "COPY patients TO '/tmp/out.csv'",           # COPY exfil
        "SELECT * FROM patients; COPY x TO '/tmp/y'",# multi + COPY
        "SELECT pg_read_file('/etc/passwd')",        # file read
        "SELECT * FROM dblink('...', 'select 1')",   # dblink
        "SELECT pg_sleep(60)",                       # DoS
        "SELECT * INTO newtable FROM patients",      # SELECT INTO creates table
        "WITH x AS (DELETE FROM patients RETURNING *) SELECT * FROM x",  # data-modifying CTE
        "SET default_transaction_read_only = off",   # session tamper
        "BEGIN; DELETE FROM patients; COMMIT",       # explicit txn
        "",                                          # empty
        "   ",                                       # whitespace only
        "-- just a comment",                         # comment only
        "/* block */",                               # block comment only
        "EXPLAIN ANALYZE DELETE FROM patients",      # EXPLAIN ANALYZE side-effect
    ])
    def test_validator_rejects_dangerous(self, sql):
        with pytest.raises(SqlValidationError):
            validate_readonly_sql(sql)

    def test_validator_rejects_none(self):
        with pytest.raises(SqlValidationError):
            validate_readonly_sql(None)  # type: ignore[arg-type]

    def test_comment_injection_second_statement_blocked(self):
        # The classic "hide a DROP behind a comment then semicolon" attack.
        attack = "SELECT id FROM t\n-- harmless\n; DROP TABLE t"
        with pytest.raises(SqlValidationError):
            validate_readonly_sql(attack)


# =============================================================================
# In-memory fake Vault mimicking UserVaultWrapper per-user namespacing
# =============================================================================

class _FakeVaultBackend:
    """Shared backend store keyed by the full `user/<id>/<key>` path."""
    def __init__(self):
        self.store = {}


class _FakeUserVault:
    """Mimics galaxy.security.vault.UserVaultWrapper: namespaces by user id."""
    def __init__(self, backend, user):
        self._backend = backend
        self._user = user

    def _k(self, key):
        return f"user/{self._user.id}/{key}"

    def read_secret(self, key):
        return self._backend.store.get(self._k(key))

    def write_secret(self, key, value):
        self._backend.store[self._k(key)] = value


class _FakeUser:
    def __init__(self, uid):
        self.id = uid


class _FakeApp:
    def __init__(self):
        self.vault = object()  # unused; _user_vault is patched to ignore it


class _FakeTrans:
    def __init__(self, uid):
        self.user = _FakeUser(uid)
        self.app = _FakeApp()


@pytest.fixture
def shared_vault(monkeypatch):
    """Patch private_db._user_vault to return a fake per-user vault over one backend."""
    backend = _FakeVaultBackend()

    def _fake_user_vault(trans):
        if not getattr(trans, "user", None):
            raise PermissionError("auth required")
        return _FakeUserVault(backend, trans.user)

    monkeypatch.setattr(private_db, "_user_vault", _fake_user_vault)
    return backend


# =============================================================================
# vault — creds round-trip
# =============================================================================

class TestCredsRoundTrip:
    def test_create_then_list_hides_password(self, shared_vault):
        trans = _FakeTrans(uid=1)
        meta = private_db.create_connection(
            trans, name="clinical", host="db.internal", port=5432,
            dbname="clin", user="ro_user", password="s3cret",
        )
        assert "password" not in meta
        assert meta["name"] == "clinical"
        assert meta["conn_id"]

        # list returns public metadata only — never the password
        conns = private_db.list_connections(trans)
        assert len(conns) == 1
        assert "password" not in conns[0]
        assert conns[0]["name"] == "clinical"

        # the password IS persisted in the vault blob (encrypted-at-rest in prod)
        raw = private_db._user_vault(trans).read_secret(
            f"{private_db.VAULT_PREFIX}/{meta['conn_id']}"
        )
        blob = json.loads(raw)
        assert blob["password"] == "s3cret"

    def test_delete_removes_connection(self, shared_vault):
        trans = _FakeTrans(uid=1)
        meta = private_db.create_connection(
            trans, name="x", host="h", port=5432, dbname="d",
            user="u", password="p",
        )
        cid = meta["conn_id"]
        assert private_db.list_connections(trans)
        private_db.delete_connection(trans, cid)
        assert private_db.list_connections(trans) == []

    def test_rejects_unsupported_driver(self, shared_vault):
        trans = _FakeTrans(uid=1)
        with pytest.raises(ValueError):
            private_db.create_connection(
                trans, name="x", host="h", port=1521, dbname="d",
                user="u", password="p", driver="oracle",
            )


# =============================================================================
# resolver — ownership isolation
# =============================================================================

class TestResolverOwnership:
    def test_user_b_cannot_resolve_user_a_connection(self, shared_vault):
        trans_a = _FakeTrans(uid=1)
        trans_b = _FakeTrans(uid=2)

        meta = private_db.create_connection(
            trans_a, name="a-db", host="h", port=5432, dbname="d",
            user="u", password="p",
        )
        cid = meta["conn_id"]

        # Owner resolves fine.
        blob = private_db._resolve_connection(trans_a, cid)
        assert blob["conn_id"] == cid

        # Different user → PermissionError (not found; 404-not-403 at the API).
        with pytest.raises(PermissionError):
            private_db._resolve_connection(trans_b, cid)

    def test_run_query_cross_user_returns_error_not_data(self, shared_vault):
        trans_a = _FakeTrans(uid=1)
        trans_b = _FakeTrans(uid=2)
        meta = private_db.create_connection(
            trans_a, name="a-db", host="h", port=5432, dbname="d",
            user="u", password="p",
        )
        # user B tries to query user A's connection: must fail at ownership,
        # BEFORE any SQL executes.
        out = private_db.run_query(trans_b, meta["conn_id"], "SELECT 1", user_id=2)
        assert out["success"] is False
        assert "rows" not in out

    def test_run_query_rejects_bad_sql_before_execution(self, shared_vault):
        trans_a = _FakeTrans(uid=1)
        meta = private_db.create_connection(
            trans_a, name="a-db", host="h", port=5432, dbname="d",
            user="u", password="p",
        )
        # Ownership passes, but the SQL validator must reject the DROP before any
        # engine is created (no sqlalchemy needed to prove this).
        out = private_db.run_query(trans_a, meta["conn_id"], "DROP TABLE t", user_id=1)
        assert out["success"] is False
        assert "validator" in out["error"].lower()


# =============================================================================
# error sanitization — no credential leakage
# =============================================================================

class TestErrorSanitization:
    def test_safe_error_redacts_dsn_userinfo(self):
        e = Exception("could not connect to postgresql://ro:s3cret@db.internal:5432/clin")
        msg = private_db._safe_error(e)
        assert "s3cret" not in msg
        assert "<redacted>" in msg

    def test_safe_error_redacts_password_param(self):
        e = Exception("connection failed password=hunter2 host=db")
        msg = private_db._safe_error(e)
        assert "hunter2" not in msg
