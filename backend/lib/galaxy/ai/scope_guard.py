"""scope_guard.py — on-prem deployment-scope enforcement (allow-list).

A scoped on-prem deployment ships the FULL catalog DB but is restricted to a
required subset of workflows/tools/instruments. This module is the single
runtime authority that decides whether a given workflow/tool is in scope.

Design (see docs/20261005_ONPREM_SCOPE_LAYER_PLAN.md):
  * Enforce, don't subtract — the DB ships whole; scope is an allow-list here.
  * FAIL-SAFE OFF for SaaS: enforcement is active ONLY when a manifest is
    configured via BIOMATE_SCOPE_MANIFEST. Unset / unreadable → every check
    returns True (no-op), so the paying platform is never accidentally scoped.
  * One manifest.json is the source of truth (built by build_scope_manifest.py).

The manifest shape this reads (extra keys ignored):
  {
    "workflows": {
      "by_nextflow_path": ["nextflow_nfcore/.../rnaseq/main.nf", ...],
      "by_name":          ["nf-core/rnaseq", ...]
    },
    "tools_allowlist": ["fastqc", "star", ...],
    "instruments":     ["illumina_novaseq", ...]
  }
"""

from __future__ import annotations

import json
import logging
import os
import threading
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)

_ENV_VAR = "BIOMATE_SCOPE_MANIFEST"

# (mtime, parsed-manifest) cache so we parse once and re-read only on change.
_lock = threading.Lock()
_cache: Dict[str, Any] = {"path": None, "mtime": None, "data": None}


class ScopeError(Exception):
    """Raised when an out-of-scope workflow/tool is requested on a scoped deployment.

    Carries a 409 status and a structured payload for the HTTP layer.
    """

    status_code = 409

    def __init__(self, workflow: str = "", reason: str = "", scope_hint: str = ""):
        self.payload = {
            "error": "OUT_OF_SCOPE",
            "workflow": workflow,
            "message": reason
            or "This workflow is not available in this deployment's configured scope.",
            "scope_hint": scope_hint,
        }
        super().__init__(self.payload["message"])


# ── manifest loading ─────────────────────────────────────────────────────────

def _manifest_path() -> Optional[str]:
    p = (os.environ.get(_ENV_VAR) or "").strip()
    return p or None


def _manifest() -> Optional[Dict[str, Any]]:
    """Return the parsed manifest, or None when enforcement is off/misconfigured.

    Re-reads the file when its mtime changes. Any read/parse error → None
    (fail-safe OFF) with a warning; it never raises into the request path.
    """
    path = _manifest_path()
    if not path:
        return None
    try:
        mtime = os.path.getmtime(path)
    except OSError as e:
        log.warning("[scope_guard] %s=%s not readable (%s) — enforcement OFF", _ENV_VAR, path, e)
        return None
    with _lock:
        if _cache["path"] == path and _cache["mtime"] == mtime and _cache["data"] is not None:
            return _cache["data"]
        try:
            with open(path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            if not isinstance(data, dict):
                raise ValueError("manifest root is not an object")
            _cache.update({"path": path, "mtime": mtime, "data": data})
            wfp = len(((data.get("workflows") or {}).get("by_nextflow_path")) or [])
            log.info("[scope_guard] loaded scope manifest %s (%d in-scope workflow paths)", path, wfp)
            return data
        except Exception as e:  # noqa: BLE001 — fail safe, never break dispatch on a bad file
            log.warning("[scope_guard] failed to parse %s (%s) — enforcement OFF", path, e)
            return None


def enforcement_enabled() -> bool:
    """True iff a usable scope manifest is configured. Fail-safe OFF otherwise."""
    return _manifest() is not None


# ── path / name matching ─────────────────────────────────────────────────────

# Known on-disk prefixes the execute request may carry; stripped before matching
# so an absolute container path matches a relative catalog nextflow_path.
_STRIP_PREFIXES = (
    "/app/lib/galaxy/webapps/galaxy/api/",
    "/app/lib/galaxy/",
    "/app/",
    "backend/lib/galaxy/webapps/galaxy/api/",
    "backend/",
    "lib/galaxy/",
)


def _norm_path(p: str) -> str:
    """Normalize a nextflow_path to a comparable relative form (no leading ./ or /)."""
    if not p:
        return ""
    p = p.strip().replace("\\", "/")
    p = p.lstrip("./")
    for pre in _STRIP_PREFIXES:
        if p.startswith(pre):
            p = p[len(pre):]
    return p.lstrip("/")


def _path_matches(req: str, allowed: str) -> bool:
    """Match two normalized paths by exact or trailing-component suffix.

    Robust to absolute-vs-relative and differing roots: the shorter path must be
    a whole-component suffix of the longer (e.g. '.../rnaseq/main.nf' matches
    'nextflow_nfcore/subworkflows/.../rnaseq/main.nf').
    """
    if not req or not allowed:
        return False
    if req == allowed:
        return True
    a = req.split("/")
    b = allowed.split("/")
    short, long = (a, b) if len(a) <= len(b) else (b, a)
    return long[-len(short):] == short


def is_workflow_in_scope(*, nextflow_path: str = "", name: str = "") -> bool:
    """True if the workflow is in scope (or enforcement is off)."""
    m = _manifest()
    if m is None:
        return True  # enforcement off → allow
    wf = m.get("workflows") or {}
    req = _norm_path(nextflow_path)
    if req:
        for allowed in wf.get("by_nextflow_path") or []:
            if _path_matches(req, _norm_path(str(allowed))):
                return True
    if name:
        names = {str(n).strip().lower() for n in (wf.get("by_name") or [])}
        if name.strip().lower() in names:
            return True
    return False


def is_tool_in_scope(tool: str) -> bool:
    m = _manifest()
    if m is None:
        return True
    if not tool:
        return True
    allow = {str(t).strip().lower() for t in (m.get("tools_allowlist") or [])}
    return (not allow) or (tool.strip().lower() in allow)


def is_instrument_in_scope(instrument: str) -> bool:
    m = _manifest()
    if m is None:
        return True
    if not instrument:
        return True
    allow = {str(i).strip().lower() for i in (m.get("instruments") or [])}
    # Empty instruments list in a manifest means "no per-deployment restriction".
    return (not allow) or (instrument.strip().lower() in allow)


def filter_workflows(rows: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Drop out-of-scope rows from a search/router result list.

    Expects each row to carry a 'nextflow_path' and/or 'name' key (common across
    UnifiedWorkflowSearch results). No-op when enforcement is off.
    """
    if _manifest() is None:
        return rows
    out = []
    for r in rows:
        np = str(r.get("nextflow_path") or r.get("nextflow_file") or "")
        nm = str(r.get("name") or r.get("workflow_name") or "")
        if is_workflow_in_scope(nextflow_path=np, name=nm):
            out.append(r)
    return out


# ── dispatch gate ────────────────────────────────────────────────────────────

def _uploads_allowed() -> bool:
    """Whether arbitrary uploaded .nf (file_content) may run on a scoped deployment.

    Default: NO. A raw uploaded workflow has no catalog identity, so its scope
    cannot be verified — fail closed. An operator can opt in explicitly.
    """
    return (os.environ.get("BIOMATE_SCOPE_ALLOW_UPLOADS", "").strip().lower()
            in ("1", "true", "yes", "on"))


def assert_in_scope_or_raise(
    *, nextflow_path: str = "", name: str = "", file_content: Optional[str] = None
) -> None:
    """Raise ScopeError(409) if the requested workflow is out of scope.

    No-op when enforcement is off (SaaS). Raw uploaded workflows (file_content)
    are rejected on a scoped deployment unless BIOMATE_SCOPE_ALLOW_UPLOADS is set,
    because their scope cannot be verified against the catalog.
    """
    if _manifest() is None:
        return  # enforcement off
    if file_content and not _uploads_allowed():
        raise ScopeError(
            workflow=(name or nextflow_path or "uploaded-workflow"),
            reason=("Uploading and running an arbitrary workflow is disabled on this "
                    "scoped deployment (its scope cannot be verified)."),
            scope_hint="Use a catalog workflow that is within this deployment's scope.",
        )
    if is_workflow_in_scope(nextflow_path=nextflow_path, name=name):
        return
    raise ScopeError(
        workflow=(name or nextflow_path or "unknown"),
        reason="This workflow is not in this deployment's configured scope.",
        scope_hint="Contact your administrator to add its domain/workflow to the deployment scope.",
    )
