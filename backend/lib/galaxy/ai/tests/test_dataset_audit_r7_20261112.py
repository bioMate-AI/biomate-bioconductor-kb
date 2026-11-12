"""
Behavioural tests for the backend items of live audit ROUND 6 of the dataset panel (2026-11-12):

* 3 — a small design table (18 rows, donor nested in condition) said Watch for ``group_nested``
  while the ``label_few_rows`` note claimed that "columns that reveal the group were not
  checked". The design check (batch / donor columns against the groups) DOES run below the row
  floor; only group balance and the per-column screen are skipped. The note now says exactly that.
* 4 — PDB: "Chains (1): A." restated the CHAINS stat tile. The finding names the chain IDs only.
* 8 — a column with one value in EVERY row was called "Near-constant (over 99% a single value)".
  A constant column is stated as constant (``constant_columns``); near-constant keeps its own code.

Every test fails on the profiler at 84ec28c1dd. Deterministic, no network.

Run standalone (no pytest needed):
    cd backend && python3.9 lib/galaxy/ai/tests/test_dataset_audit_r7_20261112.py
"""
from __future__ import annotations

import importlib.util
import inspect
import json
import os
import random
import re
import sys
import tempfile

_HERE = os.path.dirname(os.path.abspath(__file__))
_AI = os.environ.get("BM_AI_DIR") or os.path.abspath(os.path.join(_HERE, ".."))


def _load(name: str, fname: str):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_AI, fname))
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)  # type: ignore[union-attr]
    return mod


dp = _load("_dp_audit_r7_under_test", "data_perception.py")

try:
    import pytest

    @pytest.fixture
    def tmp():
        with tempfile.TemporaryDirectory() as d:
            yield d
except ImportError:  # standalone main() supplies tmp
    pass


def _w(tmp, name, data):
    path = os.path.join(tmp, name)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb" if isinstance(data, bytes) else "w", **({} if isinstance(data, bytes) else {"newline": ""})) as f:
        f.write(data)
    return path


def _tsv(tmp, name, header, rows):
    return _w(tmp, name, "\t".join(header) + "\n" + "".join("\t".join(str(c) for c in r) + "\n" for r in rows))


def _codes(prof):
    return {f["code"]: f for f in prof["findings"]}


def _once(prof):
    codes = [f["code"] for f in prof["findings"]]
    dupes = sorted({c for c in codes if codes.count(c) > 1})
    assert not dupes, (dupes, prof["findings"])


def _texts(prof):
    """Every sentence the planning view shows: notes, plan observations and plan effects."""
    out = list(prof.get("notes") or [])
    for pi in prof.get("planImpact") or []:
        out += [pi["observed"], pi["effect"]]
    return out


def _fastq(tmp, name, n=20):
    rec = "".join(f"@r{i}\nACGTACGTAC\n+\nIIIIIIIIII\n" for i in range(n))
    return _w(tmp, name, rec)


# ---------------------------------------------------------------------------
# 3 — the small-table note is truthful about what was checked
# ---------------------------------------------------------------------------
def _design_nested(tmp):
    rnd = random.Random(3)
    rows = []
    for d in range(6):
        cond = "ctrl" if d < 3 else "treat"
        for r in range(3):
            rows.append([f"s{d}_{r}", cond, f"donor{d}", round(rnd.gauss(10, 2), 3), round(rnd.gauss(5, 1), 3)])
    return dp.profile_dataset(_tsv(tmp, "design_nested.tsv", ["sample", "condition", "donor", "expr_a", "expr_b"], rows))


def test_3_small_design_table_note_does_not_contradict_the_design_check(tmp):
    prof = _design_nested(tmp)
    codes = _codes(prof)
    assert "group_nested" in codes, prof["findings"]
    assert "label_few_rows" in codes, prof["findings"]
    text = dp._EN_TEXT["label_few_rows"]
    # It must not say the group-revealing check was skipped wholesale while a design finding on
    # the same group column is shown: it says what WAS checked below the row floor.
    assert "reveal the group were not checked" not in text, text
    assert re.search(r"batch|donor", text, re.I) and re.search(r"still", text, re.I), text


# ---------------------------------------------------------------------------
# 4 — PDB chains: the IDs, not the count again
# ---------------------------------------------------------------------------
_PDB_TWO_CHAINS = """HEADER    TEST                                    01-JAN-00   1XYZ
EXPDTA    X-RAY DIFFRACTION
ATOM      1  CA  LEU A   1      11.900  12.500  13.000  1.00 62.00           C
ATOM      2  CA  GLY A   2      12.900  13.500  14.000  1.00 30.00           C
TER       3      GLY A   2
ATOM      4  CA  LEU B   1      21.900  22.500  23.000  1.00 62.00           C
ATOM      5  CA  GLY B   2      22.900  23.500  24.000  1.00 30.00           C
TER       6      GLY B   2
END
"""


class _StubGalaxy:
    """Galaxy's datatype registry as the dev container has it (chain IDs from Pdb.set_meta);
    the local Python 3.9 cannot import Galaxy's datatypes, so the metadata is supplied."""
    GENERIC_EXTS = frozenset({"data", "binary", "txt", "text", "tabular", "tsv"})

    def identify(self, path, name=None):
        return "pdb"

    def metadata(self, path, ext):
        return {"chain_ids": ["A", "B"]} if ext == "pdb" else {}

    def label_for(self, ext):
        return (ext or "").upper()

    def spec_column_names(self, ext):
        return None


def test_4_structure_chains_names_ids_without_restating_the_count(tmp):
    saved = list(dp._GF_MODULE)
    dp._GF_MODULE[:] = [_StubGalaxy()]
    try:
        prof = dp.profile_dataset(_w(tmp, "two.pdb", _PDB_TWO_CHAINS))
    finally:
        dp._GF_MODULE[:] = saved
    f = _codes(prof).get("structure_chains")
    assert f is not None, prof["findings"]
    assert {"code": "chains", "value": 2} in [{"code": s["code"], "value": s["value"]} for s in prof["stats"]], prof["stats"]
    assert "{{count}}" not in dp._EN_TEXT["structure_chains"], dp._EN_TEXT["structure_chains"]
    assert "{{chains}}" in dp._EN_TEXT["structure_chains"]
    # The count param stays for older clients that read the stat from the finding.
    assert f["params"]["count"] == 2 and list(f["params"]["chains"]) == ["A", "B"], f


# ---------------------------------------------------------------------------
# 8 — constant is constant; near-constant is near-constant
# ---------------------------------------------------------------------------
def test_8_constant_column_is_called_constant(tmp):
    rnd = random.Random(8)
    rows = [[f"s{i}", "EGFR", "x" if i == 0 else "y", round(rnd.gauss(10, 2), 3)] for i in range(200)]
    prof = dp.profile_dataset(_tsv(tmp, "const.tsv", ["sample", "gene", "flag", "value"], rows))
    codes = _codes(prof)
    assert "constant_columns" in codes, prof["findings"]
    assert list(codes["constant_columns"]["params"]["columns"]) == ["gene"], codes["constant_columns"]
    assert codes["constant_columns"]["level"] == "watch", codes["constant_columns"]
    assert "near_constant" in codes and list(codes["near_constant"]["params"]["columns"]) == ["flag"], prof["findings"]
    assert "near" not in dp._EN_TEXT["constant_columns"].lower(), dp._EN_TEXT["constant_columns"]
    # A table whose only "constant" problem is a constant column is not called clean.
    assert "table_clean" not in codes and "table_clean_unlabelled" not in codes, prof["findings"]
    # Below the row floor it is a neutral note, as near-constant is.
    few = dp.profile_dataset(_tsv(tmp, "few.tsv", ["sample", "gene", "value"],
                                  [[f"s{i}", "EGFR", i * 1.5] for i in range(6)]))
    fc = _codes(few).get("constant_columns")
    assert fc is not None and fc["level"] == "info" and fc["params"].get("expected") == "few_rows", few["findings"]


def main():
    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for t in tests:
        with tempfile.TemporaryDirectory() as d:
            try:
                t(d) if inspect.signature(t).parameters else t()
                print(f"PASS {t.__name__}")
            except Exception as exc:  # noqa: BLE001 — report every failure, then exit non-zero
                failed += 1
                print(f"FAIL {t.__name__}: {type(exc).__name__}: {str(exc)[:300]}")
    print(f"\n{len(tests) - failed}/{len(tests)} round-7 dataset-audit tests passed.")
    if failed:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
