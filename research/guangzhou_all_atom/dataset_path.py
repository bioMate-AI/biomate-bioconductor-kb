"""G8: one shared dataset-path resolver for the cyclic-peptide stage scripts.

Before this, each stage script hard-coded its training-CSV path (data/raw/..., data/processed/...)
and none imported the registry. This module is the single adoption point: stage scripts resolve a
dataset by its cyclic_data_registry name, cache-first, with the committed relative path as a
fallback when the registry is unavailable (e.g. a bare EC2 box without the registry cached).

Behaviour-preserving: the registry's local_path for these datasets is exactly the committed path,
so resolve(name, fallback) returns the same file the scripts used to hard-code — it just routes
through the one registry so the path lives in a single place (cyclic_data_registry.yaml).
"""
from __future__ import annotations

import importlib.util
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parent
_REGISTRY = None  # memoised registry instance (None => not yet loaded / unavailable)


def resolve(registry_name: str, fallback_rel: Optional[str] = None,
            *, allow_download: bool = False) -> Path:
    """Resolve a dataset to a local path via cyclic_data_registry (cache-first).

    Falls back to ROOT/fallback_rel if the registry is missing/uncached and a fallback is given;
    otherwise re-raises the registry error so a genuinely-missing dataset is not silently masked.
    """
    global _REGISTRY
    try:
        if _REGISTRY is None:
            spec = importlib.util.spec_from_file_location("cyclic_data_registry",
                                                          ROOT / "cyclic_data_registry.py")
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)  # type: ignore[union-attr]
            _REGISTRY = mod.registry()
        return _REGISTRY.resolve_path(registry_name, allow_download=allow_download)
    except Exception:  # noqa: BLE001 — registry missing / not cached
        if fallback_rel is not None:
            return ROOT / fallback_rel
        raise
