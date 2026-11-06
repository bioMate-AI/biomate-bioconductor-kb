"""
INTEGRATION test for the Private DB read-only executor (galaxy.ai.private_db).

Unlike test_private_db.py (which covers the validator + vault + ownership with
zero infra), this suite proves the **executor** enforces read-only against a
LIVE Postgres — i.e. that the security model survives even if the string
validator were bypassed.

It is marked ``@pytest.mark.integration`` and SKIPS entirely unless a live test
Postgres is pointed at via env vars, so it never breaks CI:

    PRIVATE_DB_TEST_HOST      (default 127.0.0.1)
    PRIVATE_DB_TEST_PORT      (default 5439)
    PRIVATE_DB_TEST_DBNAME    (default testdb)
    PRIVATE_DB_TEST_ROLE      read-only DB role (default 'ro')
    PRIVATE_DB_TEST_PASSWORD  password for that role   (REQUIRED to run)
    PRIVATE_DB_TEST_SUPERUSER a role WITH write grants  (optional, default 'postgres')
    PRIVATE_DB_TEST_SUPERPW   password for the superuser (optional)

The suite expects a table `patients(id, name, age)` with >=3 rows and a role
that has ONLY SELECT (no INSERT/UPDATE/DELETE/CREATE). See the harness in the
integration-test setup for the exact provisioning.

WHY BOTH ROLES: the read-only role proves the "suspenders" (role grants). The
optional superuser role proves the "belt" transaction guard in isolation — that
even a WRITE-CAPABLE role is blocked by the executor's read-only transaction
(`default_transaction_read_only=on` + `SET TRANSACTION READ ONLY`). If no
superuser creds are supplied, that one test skips.
"""
import importlib.util
import os
import sys
import time
from pathlib import Path

import pytest

# Load galaxy.ai.private_db by FILE PATH rather than `from galaxy.ai import ...`.
# The `galaxy.ai` package __init__ eagerly imports the whole AI/LLM stack
# (httpx, intent_parser, …) which we don't want to require for this executor
# test. private_db itself only lazy-imports sqlalchemy inside functions, so
# loading the file directly gives us the real module with no heavy deps.
_PRIVATE_DB_PATH = Path(__file__).parents[1] / "lib" / "galaxy" / "ai" / "private_db.py"
_spec = importlib.util.spec_from_file_location("private_db_under_test", _PRIVATE_DB_PATH)
private_db = importlib.util.module_from_spec(_spec)
sys.modules["private_db_under_test"] = private_db
_spec.loader.exec_module(private_db)

validate_readonly_sql = private_db.validate_readonly_sql
SqlValidationError = private_db.SqlValidationError


# --- gate: skip the whole module unless a live PG is configured --------------
_PW = os.environ.get("PRIVATE_DB_TEST_PASSWORD")
pytestmark = [
    pytest.mark.integration,
    pytest.mark.skipif(
        not _PW,
        reason="PRIVATE_DB_TEST_PASSWORD not set — no live Postgres; integration test skipped",
    ),
]

HOST = os.environ.get("PRIVATE_DB_TEST_HOST", "127.0.0.1")
PORT = int(os.environ.get("PRIVATE_DB_TEST_PORT", "5439"))
DBNAME = os.environ.get("PRIVATE_DB_TEST_DBNAME", "testdb")
RO_ROLE = os.environ.get("PRIVATE_DB_TEST_ROLE", "ro")
RO_PW = _PW
SUPER_ROLE = os.environ.get("PRIVATE_DB_TEST_SUPERUSER", "postgres")
# NB: SUPER_PW may legitimately be "" (empty) under `initdb --auth=trust`, where
# the superuser needs no password. We therefore gate the belt-in-isolation test
# on the presence of the ENV VAR itself, not on a truthy password value.
_SUPER_CONFIGURED = "PRIVATE_DB_TEST_SUPERUSER" in os.environ or "PRIVATE_DB_TEST_SUPERPW" in os.environ
SUPER_PW = os.environ.get("PRIVATE_DB_TEST_SUPERPW", "")


# --- in-memory fake Vault mimicking UserVaultWrapper per-user namespacing -----
# (Same shape as test_private_db.py so run_query exercises the REAL resolve →
# validate → execute chain, only the credential store is faked.)
class _FakeVaultBackend:
    def __init__(self):
        self.store = {}


class _FakeUserVault:
    def __init__(self, backend, user):
        self.backend = backend
        self.user = user

    def _k(self, key):
        return f"user/{self.user.id}/{key}"

    def read_secret(self, key):
        return self.backend.store.get(self._k(key))

    def write_secret(self, key, value):
        self.backend.store[self._k(key)] = value


class _FakeUser:
    def __init__(self, uid):
        self.id = uid


class _FakeApp:
    def __init__(self):
        self.vault = object()


class _FakeTrans:
    def __init__(self, uid):
        self.user = _FakeUser(uid)
        self.app = _FakeApp()


@pytest.fixture
def shared_vault(monkeypatch):
    backend = _FakeVaultBackend()

    def _fake_user_vault(trans):
        if not getattr(trans, "user", None):
            raise PermissionError("Authentication required")
        return _FakeUserVault(backend, trans.user)

    monkeypatch.setattr(private_db, "_user_vault", _fake_user_vault)
    return backend


def _register(trans, *, role, password):
    """Register a private-DB connection to the live test PG as `role`."""
    meta = private_db.create_connection(
        trans,
        name=f"itest-{role}",
        host=HOST,
        port=PORT,
        dbname=DBNAME,
        user=role,
        password=password,
        driver="postgresql",
    )
    return meta["conn_id"]


# =============================================================================
# 1. Real query round-trips through the read-only role
# =============================================================================

class TestReadOnlyRoleReads:
    def test_select_returns_real_rows(self, shared_vault):
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=RO_ROLE, password=RO_PW)

        res = private_db.run_query(trans, cid, "SELECT id, name, age FROM patients ORDER BY id")
        assert res["success"] is True, res
        assert res["columns"] == ["id", "name", "age"]
        assert res["row_count"] >= 3
        assert res["truncated"] is False
        # rows are JSON-safe primitives
        first = res["rows"][0]
        assert isinstance(first[0], int)
        assert isinstance(first[1], str)

    def test_row_cap_and_truncated_flag(self, shared_vault):
        """generate_series produces > MAX_ROWS rows → capped at MAX_ROWS + truncated=True."""
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=RO_ROLE, password=RO_PW)

        over = private_db.MAX_ROWS + 500
        sql = f"SELECT g AS n FROM generate_series(1, {over}) AS g"
        res = private_db.run_query(trans, cid, sql)
        assert res["success"] is True, res
        assert res["row_count"] == private_db.MAX_ROWS
        assert res["truncated"] is True

    def test_row_cap_not_triggered_when_under(self, shared_vault):
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=RO_ROLE, password=RO_PW)
        sql = "SELECT g FROM generate_series(1, 10) AS g"
        res = private_db.run_query(trans, cid, sql)
        assert res["success"] is True, res
        assert res["row_count"] == 10
        assert res["truncated"] is False


# =============================================================================
# 2. SECURITY PROOF — writes blocked at BOTH layers
# =============================================================================

class TestValidatorLayerBlocksWrites:
    """Layer (a): the string validator rejects mutating / multi-statement SQL."""

    @pytest.mark.parametrize("sql", [
        "DROP TABLE patients",
        "DELETE FROM patients",
        "UPDATE patients SET age = 0",
        "INSERT INTO patients(name, age) VALUES ('x', 1)",
        "SELECT 1; DROP TABLE patients",           # multi-statement
        "TRUNCATE patients",
    ])
    def test_validator_rejects(self, sql):
        with pytest.raises(SqlValidationError):
            validate_readonly_sql(sql)

    def test_run_query_reports_validator_rejection(self, shared_vault):
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=RO_ROLE, password=RO_PW)
        res = private_db.run_query(trans, cid, "DELETE FROM patients")
        assert res["success"] is False
        assert "validator" in res["error"].lower()
        # and the data is untouched
        after = private_db.run_query(trans, cid, "SELECT count(*) AS c FROM patients")
        assert after["success"] is True
        assert after["rows"][0][0] >= 3


class TestDbLayerBlocksWrites:
    """Layer (b): BYPASS the validator; run raw DML through the executor's
    read-only connection path → the DB ITSELF must refuse it.

    This is the KEY assertion: it proves defense survives even if the string
    validator were bypassed entirely. We call the private _execute_readonly
    directly with un-validated SQL, using the resolved blob.
    """

    def _blob(self, shared_vault, *, role, password):
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=role, password=password)
        return private_db._resolve_connection(trans, cid)

    @pytest.mark.parametrize("sql", [
        "INSERT INTO patients(name, age) VALUES ('Mallory', 99)",
        "UPDATE patients SET age = 0",
        "DELETE FROM patients",
        "DROP TABLE patients",
        "CREATE TABLE evil (x int)",
    ])
    def test_readonly_role_write_refused_by_db(self, shared_vault, sql):
        """Read-only ROLE path: role lacks the grant AND txn is read-only."""
        blob = self._blob(shared_vault, role=RO_ROLE, password=RO_PW)
        with pytest.raises(Exception) as exc:
            private_db._execute_readonly(blob, sql)
        msg = str(exc.value).lower()
        # Either the role grant blocks it ("permission denied") or the read-only
        # transaction blocks it ("read-only transaction"). Both are acceptable —
        # what matters is the DB REFUSED the write.
        assert (
            "permission denied" in msg
            or "read-only" in msg
            or "read only" in msg
            or "cannot execute" in msg
        ), f"expected DB refusal, got: {msg!r}"

    @pytest.mark.parametrize("sql", [
        "INSERT INTO patients(name, age) VALUES ('Mallory', 99)",
        "UPDATE patients SET age = 0",
        "DELETE FROM patients",
        "DROP TABLE patients",
        "CREATE TABLE evil (x int)",
    ])
    def test_write_capable_role_still_blocked_by_readonly_txn(self, shared_vault, sql):
        """Belt-in-isolation: even a WRITE-CAPABLE role is blocked by the
        executor's read-only transaction (default_transaction_read_only +
        SET TRANSACTION READ ONLY). Skips if no superuser role supplied."""
        if not _SUPER_CONFIGURED:
            pytest.skip("no write-capable role configured (PRIVATE_DB_TEST_SUPERUSER) — belt-in-isolation skipped")
        blob = self._blob(shared_vault, role=SUPER_ROLE, password=SUPER_PW)
        with pytest.raises(Exception) as exc:
            private_db._execute_readonly(blob, sql)
        msg = str(exc.value).lower()
        assert (
            "read-only" in msg or "read only" in msg or "cannot execute" in msg
        ), f"expected read-only transaction refusal, got: {msg!r}"

    def test_data_unchanged_after_all_write_attempts(self, shared_vault):
        """After every blocked write attempt above, the table is intact."""
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=RO_ROLE, password=RO_PW)
        res = private_db.run_query(trans, cid, "SELECT count(*) AS c FROM patients")
        assert res["success"] is True
        assert res["rows"][0][0] >= 3


# =============================================================================
# 3. statement_timeout actually fires
# =============================================================================

class TestStatementTimeout:
    def test_pg_sleep_exceeds_timeout_errors(self, shared_vault):
        """pg_sleep(30) under the 15s statement_timeout must error (canceled).

        pg_sleep is on the validator's forbidden-token list, so we bypass the
        validator and hit _execute_readonly directly — this specifically proves
        the SERVER-SIDE statement_timeout, not the string guard."""
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=RO_ROLE, password=RO_PW)
        blob = private_db._resolve_connection(trans, cid)

        start = time.time()
        with pytest.raises(Exception) as exc:
            # 30s > 15s statement_timeout → server cancels the statement.
            private_db._execute_readonly(blob, "SELECT pg_sleep(30)")
        elapsed = time.time() - start
        msg = str(exc.value).lower()
        # Postgres reports "canceling statement due to statement timeout".
        assert (
            "statement timeout" in msg
            or "canceling statement" in msg
            or "timeout" in msg
        ), f"expected a statement-timeout error, got: {msg!r}"
        # It must fire around the 15s cap, well before the 30s sleep would finish.
        assert elapsed < 25, f"timeout did not fire promptly (elapsed {elapsed:.1f}s)"


# =============================================================================
# 4. test_connection / test_connection_params against the live role
# =============================================================================

class TestConnectionHelpers:
    def test_test_connection_ok_with_readonly_role(self, shared_vault):
        trans = _FakeTrans(uid=1)
        cid = _register(trans, role=RO_ROLE, password=RO_PW)
        res = private_db.test_connection(trans, cid)
        assert res["ok"] is True, res
        assert "public" in res["schemas"]

    def test_test_connection_params_failure_is_sanitized(self):
        """A failed connection returns ok=False WITHOUT leaking the password.

        We force a deterministic failure with an unreachable host:port (works
        regardless of the server's auth mode — trust auth would accept any
        password, so a wrong-password path is not reliable). The point is that
        the returned error string is scrubbed of the credential.
        """
        secret = "s3cr3t-should-not-leak"
        res = private_db.test_connection_params(
            host="127.0.0.1", port=1,  # nothing listens on port 1
            dbname=DBNAME, user=RO_ROLE, password=secret,
        )
        assert res["ok"] is False
        # error must NOT leak the password anywhere in the message
        assert secret not in res["error"], res["error"]
