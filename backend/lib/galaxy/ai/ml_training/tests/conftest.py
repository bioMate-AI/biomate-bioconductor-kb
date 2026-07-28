"""Test bootstrap for the ml_training package.

Registers `galaxy` and `galaxy.ai` as path-only package stubs BEFORE any test
imports, so importing `galaxy.ai.ml_training.*` does not execute the heavy
`galaxy/ai/__init__.py` chain (intent_parser → llm_client → httpx → anthropic …).
These ml_training modules only need the lightweight `drug_discovery` siblings
(BaseModelWrapper etc.), which import cleanly.

The `if pkg not in sys.modules` guard means that when the real `galaxy.ai` has
already been imported normally (dev/CI with all deps present), we leave it
untouched — the stubs only kick in when it hasn't been loaded yet.
"""
import os
import sys
import types

_LIB = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", ".."))
if _LIB not in sys.path:
    sys.path.insert(0, _LIB)

for _pkg, _sub in (("galaxy", "galaxy"), ("galaxy.ai", "galaxy/ai")):
    if _pkg not in sys.modules:
        _m = types.ModuleType(_pkg)
        _m.__path__ = [os.path.join(_LIB, _sub)]  # namespace-style: no __init__ side effects
        sys.modules[_pkg] = _m
