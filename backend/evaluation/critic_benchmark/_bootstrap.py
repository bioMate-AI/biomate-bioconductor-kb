"""Put ``backend/lib`` on sys.path so ``galaxy.ai.critics`` imports whether the
benchmark is run from the repo root, this directory, or a test harness.

The critics package is READ-ONLY to this benchmark; we only import it.
"""
from __future__ import annotations

import os
import sys
import types


def repo_backend_lib() -> str:
    """Absolute path to ``backend/lib`` (the import root for ``galaxy.ai.critics``).

    This file lives at ``backend/evaluation/critic_benchmark/_bootstrap.py``, so
    ``backend/lib`` is three levels up + ``lib``.
    """
    here = os.path.dirname(os.path.abspath(__file__))
    backend = os.path.dirname(os.path.dirname(here))      # .../backend
    return os.path.join(backend, "lib")


def ensure_critics_importable() -> None:
    lib = repo_backend_lib()
    if lib not in sys.path:
        sys.path.insert(0, lib)
    # In a healthy env `galaxy.ai.critics` imports directly. In a minimal/broken local
    # env, galaxy/ai/__init__.py eagerly imports the heavy AI/scipy stack (unrelated to
    # the stdlib-only critics package) and may fail; fall back to a lightweight
    # `galaxy.ai` namespace stub so the read-only critics package still imports. This
    # mirrors tests/test_critics_framework.py; healthy envs never hit the fallback.
    try:  # noqa: SIM105
        import galaxy.ai.critics  # noqa: F401
    except Exception:
        stub = types.ModuleType("galaxy.ai")
        stub.__path__ = [os.path.join(lib, "galaxy", "ai")]
        sys.modules["galaxy.ai"] = stub


ensure_critics_importable()
