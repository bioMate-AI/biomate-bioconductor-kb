"""Policy for server-side evidence tables: a request may not make the server read arbitrary files.

A table path is accepted only when a table root is configured (TARGET_ID_TABLE_ROOT) and the resolved path
lies inside it. Only a fixed set of keyword arguments is passed through. 3.9-safe, stdlib only.
"""
import os
from typing import Any, Dict, List, Optional

ALLOWED_KEYS = ("path", "name", "target_col", "score_col", "filter_col", "context_filter_key", "delimiter")


def table_root() -> Optional[str]:
    r = os.environ.get("TARGET_ID_TABLE_ROOT")
    return os.path.realpath(r) if r else None


def safe_table_specs(tables: Optional[List[Dict[str, Any]]], root: Optional[str] = None) -> List[Dict[str, Any]]:
    """Return sanitised TableChannel kwargs, or raise ValueError describing what was refused."""
    out: List[Dict[str, Any]] = []
    if not tables:
        return out
    root = os.path.realpath(root) if root else table_root()
    if not root:
        raise ValueError("server-side tables are disabled (no TARGET_ID_TABLE_ROOT configured); "
                         "send the rows inline as client_tables instead")
    for i, spec in enumerate(tables):
        if not isinstance(spec, dict) or not spec.get("path"):
            raise ValueError("tables[%d] needs a path" % i)
        clean = {k: v for k, v in spec.items() if k in ALLOWED_KEYS}
        p = os.path.realpath(os.path.join(root, str(clean["path"])) if not os.path.isabs(str(clean["path"])) else str(clean["path"]))
        if os.path.commonpath([root, p]) != root:
            raise ValueError("tables[%d]: path is outside the allowed table root" % i)
        clean["path"] = p
        out.append(clean)
    return out
