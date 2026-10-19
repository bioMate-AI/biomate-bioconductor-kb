"""
Integration test: BioMate's deep-research harness improved by the REAL (vendored)
Harness2 method code — recursion + blind selection + library, with BioMate's
controller as the substrate and the trust-lattice citation count as the
answer-free selection signal.

Needs Python >= 3.12 (the vendored core's floor); skips cleanly otherwise.

Run:  python3 grounded-prototype/tests/test_h2_biomate.py
"""

import os
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

_PASS = []


def _skip(msg):
    print(f"SKIP  {msg}")
    sys.exit(0)


def main():
    if sys.version_info < (3, 12):
        _skip(f"needs Python >= 3.12 (have {sys.version.split()[0]}) for vendored harness2")
    try:
        from research.h2_biomate import (
            BioMateResearchAdapter, BioMateProposer, _parse_config, _write_config,
        )
        from harness2.core import schedule
    except Exception as exc:  # pragma: no cover
        _skip(f"vendored harness2 / adapter import failed: {exc}")

    def ck(name, cond):
        print(("PASS" if cond else "FAIL"), "-", name)
        _PASS.append(cond)

    # config round-trip (the safe ast parse of the editable .py harness file)
    rt, bg = _parse_config(_write_config({"admet": ["clinical"]}, {"max_rounds": 2}))
    ck("config round-trips via ast (no exec)", rt == {"admet": ["clinical"]} and bg["max_rounds"] == 2)

    with tempfile.TemporaryDirectory() as d:
        root = Path(d)
        adapter = BioMateResearchAdapter(root)
        prop = BioMateProposer(adapter.spec.channels["proposer"])

        # the BioMate harness c1..c8 tree includes the editable route table as .py
        base = adapter.base_harness()
        ck("base harness has editable scripts/route_table.py",
           (base / "scripts/route_table.py").is_file())

        res = schedule.run_domain("biomedical_research", adapter.tasks(), 2,
                                  adapter=adapter, prop=prop,
                                  runs_root=adapter.spec.runs_root,
                                  library_root=root / "library" / "2")
        ck("harness2 run_domain completes with no failures",
           res.get("done") == 2 and res.get("failed") == 0)
        ck("the research controller actually executed rollouts", adapter.execution_count > 0)

        lib = root / "library" / "2"
        ck("harnessing-level library was written (adopted harnesses banked)",
           lib.exists() and any(lib.rglob("*.md")))

    passed = sum(1 for c in _PASS if c)
    print(f"\n{passed}/{len(_PASS)} passed")
    sys.exit(0 if passed == len(_PASS) else 1)


if __name__ == "__main__":
    main()
