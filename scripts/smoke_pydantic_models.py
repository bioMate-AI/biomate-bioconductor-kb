#!/usr/bin/env python3
"""Fast pre-push guard against forward-reference Pydantic boot crashes.

What this catches:
  - `from __future__ import annotations` in a module + `payload: Any = None`
    on a Pydantic model without `Any` imported → PydanticUserError at
    app startup ("X is not fully defined; you should define ...")
  - Any other unresolvable forward reference in a Pydantic schema
  - Pydantic model schema build errors (forwardref cycles, missing types)

What this does NOT catch:
  - Runtime route logic errors
  - Database connection errors
  - Missing env vars
  - FastAPI dependency resolution

Use the full `scripts/smoke_boot.sh` for those.

Runtime: <2 seconds for the whole drug_discovery router family.
Exit codes:
  0  all models resolve cleanly
  1  one or more PydanticUserError / SchemaError / TypeError
  2  import error (a module under check doesn't even import)
"""
from __future__ import annotations

import importlib
import inspect
import sys
from pathlib import Path

# Modules to walk. Add new routers / Pydantic-heavy files here.
TARGETS = [
    "galaxy.ai.drug_discovery.ind_actions_router",
    "galaxy.ai.drug_discovery.feedback_router",
    "galaxy.ai.drug_discovery.pipeline_data_writer",
]

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend" / "lib"))


def main() -> int:
    failures: list[tuple[str, str, str]] = []  # (module, class, error)

    for mod_name in TARGETS:
        try:
            mod = importlib.import_module(mod_name)
        except Exception as exc:
            print(f"[FAIL] {mod_name}: import error → {exc}", file=sys.stderr)
            return 2

        try:
            from pydantic import BaseModel
        except ImportError:
            print("[SKIP] pydantic not installed", file=sys.stderr)
            return 0

        # Walk every BaseModel subclass declared in this module
        for name, obj in inspect.getmembers(mod, inspect.isclass):
            if obj.__module__ != mod_name:
                continue
            if not issubclass(obj, BaseModel) or obj is BaseModel:
                continue
            try:
                # Forces forward-reference resolution. If `Any` (or any
                # other annotation symbol) wasn't imported, this raises
                # PydanticUserError("X is not fully defined").
                obj.model_rebuild(force=True)
                # And actually try to instantiate with all required fields
                # bypassed via model_construct (skips validation but exercises
                # the schema build path).
                obj.model_construct()
            except Exception as exc:
                msg = str(exc).splitlines()[0][:200]
                failures.append((mod_name, name, msg))

    if failures:
        print("Pydantic model smoke check FAILED:", file=sys.stderr)
        for mod_name, cls_name, msg in failures:
            print(f"  - {mod_name}.{cls_name}: {msg}", file=sys.stderr)
        return 1

    print(f"[ok] {len(TARGETS)} modules, all Pydantic models resolve cleanly")
    return 0


if __name__ == "__main__":
    sys.exit(main())
