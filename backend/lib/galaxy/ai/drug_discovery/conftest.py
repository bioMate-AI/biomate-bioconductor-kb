"""Pytest configuration for the drug_discovery tree.

Excludes hand-rolled smoke scripts that are named `test_*.py` but are
actually standalone runners invoked as `python3 path/to/file.py` rather
than pytest test files. Without these exclusions, pytest's collection
phase tries to import them and hits a top-level `sys.exit(...)` that
crashes the whole collection run — so every other test in this tree
silently fails to run too.

The canonical example is `test_real_e2e.py` (a 40-check container
smoke script documented in `docs/DRUG_DISCOVERY_IMPLEMENTATION.md` and
invoked by hand inside the biomate Docker image). Renaming it would
require a fan-out edit across 7+ docs that link to its current path,
so the lower-risk fix is to tell pytest to ignore it here.
"""
# Pytest reads this name at collection time and skips matching paths.
collect_ignore_glob = [
    "test_real_e2e.py",
]
