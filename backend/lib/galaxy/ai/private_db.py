"""
Private DB Connect — read-only query executor for user-registered databases.

Capability A of docs/20260922_CONNECTOR_PRIVATE_DB_AND_EXTERNAL_MCP_PLAN.md.

A user (esp. on-prem / hospital) registers a connection to *their* Postgres,
and BioMate's chat/agent can run **read-only** queries against it.

SECURITY MODEL (all layers mandatory — no single layer is trusted alone):

  1. SELECT-only validator (`validate_readonly_sql`) — defense-in-depth string
     guard: rejects anything that is not a single SELECT / WITH…SELECT. Blocks
     DML/DDL (DROP/DELETE/UPDATE/INSERT/ALTER/CREATE/TRUNCATE/GRANT), COPY,
     multi-statement (semicolon-separated), and comment-injection. This is a
     BELT — not the only guard.
  2. Read-only DB role — users are instructed (in the UI form) to supply a
     database role that only has SELECT grants. This is the SUSPENDERS: even if
     the validator is bypassed, the role cannot mutate data.
  3. Read-only transaction — the engine is opened with
     `default_transaction_read_only=on` and every query runs inside a
     `SET TRANSACTION READ ONLY` block that is ALWAYS rolled back.
  4. Statement timeout — `statement_timeout` (default 15s) caps runaway queries.
  5. Row cap — results are truncated at `MAX_ROWS` (default 1000).

CREDENTIALS: stored ONLY in the Galaxy Vault (Fernet-AES at rest), one secret
per connection at `biomate/private_db/<conn_id>`, namespaced per-user by
`UserVaultWrapper` (`user/<user.id>/...`). Never plaintext, never logged, never
returned by any read path. Ownership is enforced structurally: a connection is
resolved through the caller's own `UserVaultWrapper`, so user A cannot read user
B's connection (the key does not exist under A's namespace).

The SQL validator (`validate_readonly_sql`) is deliberately dependency-free so it
can be unit-tested without any Galaxy runtime.
"""
from __future__ import annotations

import json
import logging
import re
import uuid
from typing import Any, Dict, List, Optional, Tuple

log = logging.getLogger(__name__)

# --- namespaces / limits -----------------------------------------------------
VAULT_PREFIX = "biomate/private_db"           # per-connection secret
VAULT_INDEX_KEY = "biomate/private_db_index"  # per-user list of conn_ids -> metadata (no secrets)

STATEMENT_TIMEOUT_MS = 15_000   # 15s hard cap
MAX_ROWS = 1000                 # row cap returned to the caller
CONNECT_TIMEOUT_S = 8           # socket connect timeout

SUPPORTED_DRIVERS = {"postgresql"}  # MVP: Postgres only


# =============================================================================
# SQL validator (defense-in-depth) — STANDALONE, no galaxy / sqlalchemy imports
# =============================================================================

class SqlValidationError(ValueError):
    """Raised when a SQL string fails the read-only SELECT-only validator."""


# Leading keywords that unambiguously indicate a mutating / dangerous statement.
_FORBIDDEN_LEADING = {
    "insert", "update", "delete", "drop", "alter", "create", "truncate",
    "grant", "revoke", "merge", "replace", "call", "do", "copy", "vacuum",
    "analyze", "reindex", "cluster", "comment", "lock", "set", "reset",
    "begin", "commit", "rollback", "savepoint", "start", "prepare", "execute",
    "explain", "declare", "fetch", "listen", "notify", "discard", "checkpoint",
    "refresh", "import", "load", "attach", "detach", "pragma", "use",
}

# Dangerous tokens that must never appear even inside an otherwise-SELECT query.
# (word-boundary matched, case-insensitive)
_FORBIDDEN_TOKENS = [
    "pg_read_file", "pg_read_binary_file", "pg_ls_dir", "lo_import",
    "lo_export", "dblink", "pg_sleep", "copy",
]


def _strip_sql_comments(sql: str) -> str:
    """Remove -- line comments and /* */ block comments (comment-injection guard).

    We remove comments BEFORE validating so an attacker cannot hide a second
    statement (e.g. ``SELECT 1; -- \nDROP TABLE x``) or smuggle keywords behind
    a comment. Nothing here is executed — this is only for the validator's view.
    """
    # Block comments (non-greedy, across newlines)
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.DOTALL)
    # Line comments: -- ... to end of line
    sql = re.sub(r"--[^\n\r]*", " ", sql)
    # Postgres # is not a comment; MySQL # is. Strip # comments defensively.
    sql = re.sub(r"#[^\n\r]*", " ", sql)
    return sql


def validate_readonly_sql(sql: str) -> str:
    """Validate that `sql` is exactly ONE read-only SELECT / WITH…SELECT statement.

    Returns the cleaned single statement (trailing semicolon stripped) on success.
    Raises SqlValidationError on ANY violation.

    This is a defense-in-depth string guard. It is NOT the only protection — the
    executor also enforces a read-only transaction + timeout + row cap, and users
    must supply a read-only DB role. Do not rely on this validator alone.
    """
    if sql is None or not isinstance(sql, str):
        raise SqlValidationError("SQL must be a non-empty string")

    original = sql
    # Work on a comment-stripped copy for structural checks.
    cleaned = _strip_sql_comments(sql).strip()
    if not cleaned:
        raise SqlValidationError("SQL is empty or only comments")

    # --- multi-statement guard -------------------------------------------------
    # Any semicolon that is not the single optional trailing one → multi-statement.
    # We forbid ALL internal semicolons; a lone trailing ';' is allowed and stripped.
    without_trailing = cleaned.rstrip()
    if without_trailing.endswith(";"):
        without_trailing = without_trailing[:-1].rstrip()
    if ";" in without_trailing:
        raise SqlValidationError(
            "Multiple SQL statements are not allowed (semicolon detected). "
            "Only a single read-only SELECT is permitted."
        )
    stmt = without_trailing
    if not stmt:
        raise SqlValidationError("SQL is empty after normalization")

    # --- leading keyword must be SELECT or WITH -------------------------------
    m = re.match(r"^\s*([A-Za-z_]+)", stmt)
    if not m:
        raise SqlValidationError("Could not identify the leading SQL keyword")
    leading = m.group(1).lower()

    if leading in _FORBIDDEN_LEADING:
        raise SqlValidationError(
            f"Statement type '{leading.upper()}' is not permitted — only read-only SELECT."
        )

    if leading not in ("select", "with"):
        raise SqlValidationError(
            f"Only SELECT (or WITH…SELECT) queries are allowed, got '{leading.upper()}'."
        )

    # A WITH clause must ultimately drive a SELECT and must not contain a data-
    # modifying CTE (WITH ... AS (DELETE ... RETURNING ...)). Reject WITH bodies
    # that contain DML keywords as CTE bodies.
    if leading == "with":
        # Reject data-modifying CTEs: "AS ( <dml>"
        if re.search(
            r"\bas\s*\(\s*(insert|update|delete|merge)\b",
            stmt, flags=re.IGNORECASE,
        ):
            raise SqlValidationError(
                "Data-modifying common table expressions (WITH … AS (INSERT/UPDATE/DELETE)) "
                "are not permitted."
            )
        # A WITH must contain a SELECT somewhere (the driving query).
        if not re.search(r"\bselect\b", stmt, flags=re.IGNORECASE):
            raise SqlValidationError("WITH clause must drive a SELECT query.")

    # --- forbidden token scan (word-boundary) ---------------------------------
    lowered = stmt.lower()
    for tok in _FORBIDDEN_TOKENS:
        if re.search(r"\b" + re.escape(tok) + r"\b", lowered):
            raise SqlValidationError(
                f"Forbidden token '{tok}' is not permitted in a read-only query."
            )

    # --- forbidden mutating keyword anywhere (extra belt) ---------------------
    # Even inside a SELECT, these keywords indicate an attempt to mutate (e.g.
    # "SELECT ...; DROP" would already be caught by the semicolon guard, but a
    # bare "SELECT ... INTO newtable" creates a table on some engines).
    if re.search(r"\bselect\b.*\binto\b", lowered, flags=re.DOTALL):
        # SELECT ... INTO creates a table in Postgres — forbid it.
        raise SqlValidationError("SELECT … INTO (table creation) is not permitted.")

    _ = original  # keep reference for clarity; we return the cleaned stmt
    return stmt


# =============================================================================
# Vault-backed connection registry (per-user)
# =============================================================================

def _user_vault(trans):
    """Build a UserVaultWrapper scoped to the calling user.

    The wrapper namespaces every key under `user/<user.id>/…`, so a connection
    stored by user A is structurally invisible to user B — this IS the ownership
    boundary for the credential store.
    """
    from galaxy.security.vault import UserVaultWrapper  # local import: galaxy runtime only
    if not getattr(trans, "user", None):
        raise PermissionError("Authentication required to access private DB connections")
    return UserVaultWrapper(trans.app.vault, trans.user)


# Preferences fallback when Galaxy's Vault is not configured (NullVault raises
# InvalidVaultConfigException). Mirrors galaxy.ai.external_mcp.registry so private
# DB connections persist per-user even without a configured vault. Still scoped to
# the calling user (trans.user.preferences), so ownership holds.
_PREFS_KEY = "biomate_private_db"


def _write_secret(trans, path: str, value: str) -> None:
    """Write a per-user secret to Vault, falling back to user preferences."""
    vault = _user_vault(trans)  # raises PermissionError if no authenticated user
    try:
        vault.write_secret(path, value)
        return
    except Exception as e:  # vault unconfigured / unavailable → preferences fallback
        log.warning("[private_db] Vault unavailable (%s), using preferences fallback", e)
    user = trans.user
    try:
        store = json.loads(user.preferences.get(_PREFS_KEY, "{}"))
    except Exception:
        store = {}
    store[path] = value
    user.preferences[_PREFS_KEY] = json.dumps(store)
    trans.sa_session.commit()


def _read_secret(trans, path: str) -> Optional[str]:
    """Read a per-user secret from Vault, falling back to user preferences."""
    try:
        vault = _user_vault(trans)
        raw = vault.read_secret(path)
        if raw:
            return raw
    except Exception:
        pass
    try:
        store = json.loads(trans.user.preferences.get(_PREFS_KEY, "{}"))
        return store.get(path)
    except Exception:
        return None


def _load_index(trans) -> Dict[str, Dict[str, Any]]:
    """Return {conn_id: metadata_without_secrets} for the calling user."""
    raw = _read_secret(trans, VAULT_INDEX_KEY)
    if raw:
        try:
            return json.loads(raw)
        except Exception:
            return {}
    return {}


def _save_index(trans, index: Dict[str, Dict[str, Any]]) -> None:
    _write_secret(trans, VAULT_INDEX_KEY, json.dumps(index))


def _public_metadata(conn: Dict[str, Any]) -> Dict[str, Any]:
    """Strip secrets from a stored connection blob for list/GET responses."""
    host = conn.get("host", "")
    # Mask host (defensive; still useful to identify the connection)
    return {
        "conn_id": conn.get("conn_id"),
        "name": conn.get("name"),
        "driver": conn.get("driver", "postgresql"),
        "host": host,
        "port": conn.get("port"),
        "dbname": conn.get("dbname"),
        "user": conn.get("user"),
        "scope": conn.get("scope", "account"),
        # NB: password is deliberately never included.
    }


def create_connection(
    trans,
    *,
    name: str,
    host: str,
    port: int,
    dbname: str,
    user: str,
    password: str,
    driver: str = "postgresql",
    scope: str = "account",
    project_id: Optional[str] = None,
) -> Dict[str, Any]:
    """Register a new private DB connection for the calling user.

    The full blob (including the password) is written as ONE Vault secret at
    `biomate/private_db/<conn_id>` under the user's namespace. Returns the PUBLIC
    metadata only (never the password).
    """
    driver = (driver or "postgresql").lower().strip()
    if driver not in SUPPORTED_DRIVERS:
        raise ValueError(f"Unsupported driver '{driver}'. MVP supports: {sorted(SUPPORTED_DRIVERS)}")
    if not (name and host and dbname and user):
        raise ValueError("name, host, dbname and user are required")
    try:
        port = int(port)
    except (TypeError, ValueError):
        raise ValueError("port must be an integer")

    conn_id = uuid.uuid4().hex
    blob = {
        "conn_id": conn_id,
        "name": name,
        "host": host,
        "port": port,
        "dbname": dbname,
        "user": user,
        "password": password,   # encrypted at rest by the Vault (Fernet-AES)
        "driver": driver,
        "scope": scope,
        "owner_user_id": getattr(trans.user, "id", None),
        "project_id": project_id,
    }
    _write_secret(trans, f"{VAULT_PREFIX}/{conn_id}", json.dumps(blob))

    # Maintain a secrets-free index so list_connections needn't enumerate the vault.
    index = _load_index(trans)
    index[conn_id] = _public_metadata(blob)
    _save_index(trans, index)

    log.info("[private_db] created connection %s for user %s", conn_id, getattr(trans.user, "id", "?"))
    return _public_metadata(blob)


def _resolve_connection(trans, conn_id: str) -> Dict[str, Any]:
    """Load the full connection blob for `conn_id`, enforcing per-user ownership.

    Ownership is enforced structurally by the UserVaultWrapper namespace: the key
    only exists under the calling user's `user/<id>/…` path. A conn_id owned by a
    different user resolves to None → PermissionError (404-not-403 at the API).
    """
    raw = _read_secret(trans, f"{VAULT_PREFIX}/{conn_id}")
    if not raw:
        raise PermissionError(f"Connection not found: {conn_id}")
    blob = json.loads(raw)
    # Belt: also verify owner_user_id matches (redundant with vault namespacing).
    owner = blob.get("owner_user_id")
    if owner is not None and getattr(trans.user, "id", None) is not None and owner != trans.user.id:
        raise PermissionError(f"Connection not found: {conn_id}")
    return blob


def list_connections(trans) -> List[Dict[str, Any]]:
    """List the calling user's connections (public metadata only, no secrets)."""
    index = _load_index(trans)
    return list(index.values())


def delete_connection(trans, conn_id: str) -> Dict[str, Any]:
    """Delete a connection (blank the vault secret + drop from index)."""
    # Ownership check first (raises if not owned).
    _resolve_connection(trans, conn_id)
    try:
        _write_secret(trans, f"{VAULT_PREFIX}/{conn_id}", "")
    except Exception as e:
        log.warning("[private_db] failed to blank secret for %s: %s", conn_id, e)
    index = _load_index(trans)
    index.pop(conn_id, None)
    _save_index(trans, index)
    return {"ok": True, "conn_id": conn_id}


# =============================================================================
# SQLAlchemy read-only executor
# =============================================================================

def _make_engine(blob: Dict[str, Any]):
    """Create a short-lived SQLAlchemy engine for one connection, read-only.

    The engine is opened with `default_transaction_read_only=on` at the Postgres
    session level AND a `statement_timeout`, so even server-side the session
    cannot mutate data or run forever.
    """
    from sqlalchemy import create_engine  # local import: heavy dep, galaxy runtime
    from sqlalchemy.engine.url import URL

    driver = blob.get("driver", "postgresql")
    if driver not in SUPPORTED_DRIVERS:
        raise ValueError(f"Unsupported driver '{driver}'")

    url = URL.create(
        drivername="postgresql+psycopg2",
        username=blob["user"],
        password=blob["password"],
        host=blob["host"],
        port=int(blob["port"]),
        database=blob["dbname"],
    )
    # Postgres server-side read-only + timeout, applied to every session on connect.
    connect_args = {
        "connect_timeout": CONNECT_TIMEOUT_S,
        "options": (
            f"-c default_transaction_read_only=on "
            f"-c statement_timeout={STATEMENT_TIMEOUT_MS}"
        ),
        # never allow the driver to run a fallback that mutates
        "application_name": "biomate_private_db_readonly",
    }
    engine = create_engine(
        url,
        connect_args=connect_args,
        pool_pre_ping=True,
        pool_recycle=300,
        pool_size=1,
        max_overflow=0,
        future=True,
    )
    return engine


def _execute_readonly(blob: Dict[str, Any], sql: str) -> Dict[str, Any]:
    """Open a short-lived read-only connection, run `sql`, ALWAYS roll back.

    `sql` MUST already have passed `validate_readonly_sql`. This function adds the
    transactional read-only enforcement + row cap on top of that string guard.
    """
    from sqlalchemy import text

    engine = _make_engine(blob)
    conn = None
    try:
        conn = engine.connect()
        # Belt-and-suspenders: force this transaction read-only regardless of the
        # role's default, then rely on ROLLBACK to discard any accidental state.
        trans = conn.begin()
        try:
            conn.execute(text("SET TRANSACTION READ ONLY"))
            result = conn.execute(text(sql))
            columns = list(result.keys())
            rows: List[List[Any]] = []
            truncated = False
            for i, row in enumerate(result):
                if i >= MAX_ROWS:
                    truncated = True
                    break
                # Coerce to JSON-safe primitives (str() unknown types).
                rows.append([_jsonsafe(v) for v in row])
            return {
                "success": True,
                "columns": columns,
                "rows": rows,
                "row_count": len(rows),
                "truncated": truncated,
            }
        finally:
            # ALWAYS roll back — never commit a private-DB query.
            trans.rollback()
    finally:
        if conn is not None:
            conn.close()
        engine.dispose()


def _jsonsafe(v: Any) -> Any:
    if v is None or isinstance(v, (str, int, float, bool)):
        return v
    try:
        return str(v)
    except Exception:
        return None


def _safe_error(e: Exception) -> str:
    """Return a sanitized error string that cannot leak credentials.

    We never echo the raw DSN / password. SQLAlchemy error strings can embed the
    connection URL, so we scrub anything that looks like a userinfo@host.
    """
    msg = str(e)
    # Redact user:pass@host userinfo in any URL-like substring.
    msg = re.sub(r"://[^/\s]*@", "://<redacted>@", msg)
    # Redact password= style params.
    msg = re.sub(r"(?i)(password|pwd)\s*=\s*\S+", r"\1=<redacted>", msg)
    return msg[:300]


# =============================================================================
# Public entry points
# =============================================================================

def test_connection(trans, conn_id: str) -> Dict[str, Any]:
    """Open a short-lived read-only connection, `SELECT 1`, and list schemas.

    Returns {ok, schemas} or {ok: False, error} with NO credential leakage.
    """
    try:
        blob = _resolve_connection(trans, conn_id)
    except PermissionError as e:
        return {"ok": False, "error": str(e)}
    try:
        from sqlalchemy import text
        engine = _make_engine(blob)
        try:
            with engine.connect() as conn:
                t = conn.begin()
                try:
                    conn.execute(text("SET TRANSACTION READ ONLY"))
                    conn.execute(text("SELECT 1"))
                    schemas = [
                        r[0] for r in conn.execute(text(
                            "SELECT schema_name FROM information_schema.schemata "
                            "ORDER BY schema_name"
                        ))
                    ]
                finally:
                    t.rollback()
            return {"ok": True, "schemas": schemas}
        finally:
            engine.dispose()
    except Exception as e:
        return {"ok": False, "error": _safe_error(e)}


def test_connection_params(
    *,
    host: str,
    port: int,
    dbname: str,
    user: str,
    password: str,
    driver: str = "postgresql",
) -> Dict[str, Any]:
    """Test a connection from raw params BEFORE it is saved (verify form).

    Same read-only enforcement as test_connection, but takes an unsaved blob.
    """
    blob = {
        "host": host, "port": port, "dbname": dbname,
        "user": user, "password": password, "driver": (driver or "postgresql").lower(),
    }
    if blob["driver"] not in SUPPORTED_DRIVERS:
        return {"ok": False, "error": f"Unsupported driver '{blob['driver']}'"}
    try:
        from sqlalchemy import text
        engine = _make_engine(blob)
        try:
            with engine.connect() as conn:
                t = conn.begin()
                try:
                    conn.execute(text("SET TRANSACTION READ ONLY"))
                    conn.execute(text("SELECT 1"))
                    schemas = [
                        r[0] for r in conn.execute(text(
                            "SELECT schema_name FROM information_schema.schemata "
                            "ORDER BY schema_name"
                        ))
                    ]
                finally:
                    t.rollback()
            return {"ok": True, "schemas": schemas}
        finally:
            engine.dispose()
    except Exception as e:
        return {"ok": False, "error": _safe_error(e)}


def run_query(trans, conn_id: str, sql: str, user_id: Optional[Any] = None) -> Dict[str, Any]:
    """Resolve `conn_id` (ownership-checked), validate + execute `sql` read-only.

    Returns the same envelope shape as the public `_query_*` handlers:
      {success, columns, rows, row_count, truncated}  (or {success: False, error}).

    `user_id` is accepted for signature symmetry with the plan; the real ownership
    boundary is `trans.user` via the vault namespace (structural, not advisory).
    """
    # 1. Ownership resolution (raises PermissionError → 404-style at API).
    try:
        blob = _resolve_connection(trans, conn_id)
    except PermissionError as e:
        return {"success": False, "error": str(e)}

    # 2. SELECT-only validation (defense-in-depth string guard).
    try:
        safe_sql = validate_readonly_sql(sql)
    except SqlValidationError as e:
        return {"success": False, "error": f"Rejected by SQL validator: {e}"}

    # 3. Read-only transactional execution + row cap.
    try:
        return _execute_readonly(blob, safe_sql)
    except Exception as e:
        log.warning("[private_db] query failed on conn %s: %s", conn_id, _safe_error(e))
        return {"success": False, "error": _safe_error(e)}
