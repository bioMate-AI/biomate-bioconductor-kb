"""
Private DB Connect API — register / test / list / delete user database connections.

Capability A of docs/20260922_CONNECTOR_PRIVATE_DB_AND_EXTERNAL_MCP_PLAN.md.

Endpoints (auto-discovered by include_all_package_routers):
  POST   /api/biomate/db-connections          — create a connection (creds → Vault)
  GET    /api/biomate/db-connections          — list connections (public metadata only)
  DELETE /api/biomate/db-connections/{conn_id}— delete a connection
  POST   /api/biomate/db-connections/verify   — test raw params before saving
  POST   /api/biomate/db-connections/{conn_id}/test — test a saved connection

Storage: Galaxy Vault (per-user namespaced UserVaultWrapper), keyed at
`biomate/private_db/<conn_id>`. Credentials are NEVER returned by any read path,
NEVER logged, and NEVER placed in error strings (see private_db._safe_error).

The query executor lives in galaxy.ai.private_db and runs in THIS backend (where
the SQLAlchemy driver + pooling live), per the plan (§2.2, executor stays backend
side to avoid a second decrypt hop across the Node↔Galaxy boundary).
"""
import logging
from typing import Any, Dict, Optional

from fastapi import HTTPException
from pydantic import BaseModel, Field

from galaxy.managers.context import ProvidesUserContext
from galaxy.webapps.galaxy.api import DependsOnTrans, Router

log = logging.getLogger(__name__)

router = Router(tags=["private_db"])


# ---------------------------------------------------------------------------
# Request models
# ---------------------------------------------------------------------------

class CreateConnectionRequest(BaseModel):
    name: str = Field(..., description="Friendly connection name")
    host: str = Field(..., description="Database host")
    port: int = Field(default=5432, description="Database port")
    dbname: str = Field(..., description="Database name")
    user: str = Field(..., description="Database user (use a READ-ONLY role)")
    password: str = Field(..., description="Database password (stored encrypted in Vault)")
    driver: str = Field(default="postgresql", description="DB driver (MVP: postgresql)")
    scope: str = Field(default="account", description="account | project | request")
    project_id: Optional[str] = Field(default=None, description="Optional project scope")


class VerifyConnectionRequest(BaseModel):
    host: str
    port: int = 5432
    dbname: str
    user: str
    password: str
    driver: str = "postgresql"


# ---------------------------------------------------------------------------
# Routes
# ---------------------------------------------------------------------------

@router.post(
    "/api/biomate/db-connections",
    summary="Register a private database connection (read-only)",
)
def create_db_connection(
    request: CreateConnectionRequest,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    from galaxy.ai import private_db
    if not getattr(trans, "user", None):
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        meta = private_db.create_connection(
            trans,
            name=request.name,
            host=request.host,
            port=request.port,
            dbname=request.dbname,
            user=request.user,
            password=request.password,
            driver=request.driver,
            scope=request.scope,
            project_id=request.project_id,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"ok": True, "connection": meta}


@router.get(
    "/api/biomate/db-connections",
    summary="List the current user's private database connections (no secrets)",
)
def list_db_connections(
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    from galaxy.ai import private_db
    if not getattr(trans, "user", None):
        raise HTTPException(status_code=401, detail="Authentication required")
    return {"connections": private_db.list_connections(trans)}


@router.delete(
    "/api/biomate/db-connections/{conn_id}",
    summary="Delete a private database connection",
)
def delete_db_connection(
    conn_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    from galaxy.ai import private_db
    if not getattr(trans, "user", None):
        raise HTTPException(status_code=401, detail="Authentication required")
    try:
        return private_db.delete_connection(trans, conn_id)
    except PermissionError:
        # 404-not-403: do not reveal existence of another user's connection.
        raise HTTPException(status_code=404, detail="Connection not found")


@router.post(
    "/api/biomate/db-connections/{conn_id}/test",
    summary="Test a saved private database connection (SELECT 1 + list schemas)",
)
def test_db_connection(
    conn_id: str,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    from galaxy.ai import private_db
    if not getattr(trans, "user", None):
        raise HTTPException(status_code=401, detail="Authentication required")
    return private_db.test_connection(trans, conn_id)


@router.post(
    "/api/biomate/db-connections/verify",
    summary="Test raw connection params before saving (verify form)",
)
def verify_db_connection(
    request: VerifyConnectionRequest,
    trans: ProvidesUserContext = DependsOnTrans,
) -> Dict[str, Any]:
    from galaxy.ai import private_db
    if not getattr(trans, "user", None):
        raise HTTPException(status_code=401, detail="Authentication required")
    return private_db.test_connection_params(
        host=request.host,
        port=request.port,
        dbname=request.dbname,
        user=request.user,
        password=request.password,
        driver=request.driver,
    )
