#!/usr/bin/env python3
"""Unit tests for the gromacs_pmx_fep engine's PURE-PYTHON logic — the hard-won
correctness helpers (origin rotation, junction injection, metal-topology newline
safety, mutation parsing) and the knowledge/FTO gates. The gmx/pmx subprocess
orchestration in _real_prepare runs only in the run image and is not covered here.

Run: python3 tests/test_engine.py   (no pytest dependency; plain asserts)
"""
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "bin"))
import run_gromacs_pmx_fep as E  # noqa: E402


def test_rotate_cyclic_origin_avb6():
    # αvβ6 instance: 9-mer, mutations at orig resid 1 and 7.
    order, new_mut = E.rotate_cyclic_origin(9, [1, 7])
    assert order == [3, 4, 5, 6, 7, 8, 9, 1, 2], order           # matches validated build
    assert sorted(new_mut) == [5, 8], new_mut                    # orig7->5, orig1->8 (both interior)
    for m in new_mut:                                            # no mutation at a terminus
        assert 1 < m < 9, m


def test_rotate_cyclic_origin_general_and_interior_guarantee():
    for n, muts in [(7, [1]), (8, [2, 6]), (12, [1, 12]), (10, [5])]:
        order, new_mut = E.rotate_cyclic_origin(n, muts)
        assert sorted(order) == list(range(1, n + 1))            # a valid permutation
        for m in new_mut:
            assert 1 < m < n, (n, muts, new_mut)                 # every mutation interior


def test_rotate_cyclic_origin_raises_when_too_dense():
    # every residue is a mutation -> no valid origin
    try:
        E.rotate_cyclic_origin(4, [1, 2, 3, 4])
        assert False, "expected ValueError"
    except ValueError:
        pass


def test_apply_rotation_to_pdb():
    with tempfile.TemporaryDirectory() as d:
        src = os.path.join(d, "pep.pdb")
        with open(src, "w") as fh:
            # 3 residues, 1 atom each (CA), resSeq 1..3
            for rs, nm in [(1, "GLY"), (2, "ALA"), (3, "SER")]:
                fh.write("ATOM  %5d  CA  %s P%4d      0.000   0.000   0.000  1.00  0.00           C\n"
                         % (rs, nm, rs))
        out = os.path.join(d, "rot.pdb")
        E.apply_rotation_to_pdb(src, [3, 1, 2], out)             # start at orig 3
        lines = [l for l in open(out) if l.startswith("ATOM")]
        # new resSeq 1,2,3 carry orig residues SER, GLY, ALA
        assert lines[0][17:20] == "SER" and int(lines[0][22:26]) == 1
        assert lines[1][17:20] == "GLY" and int(lines[1][22:26]) == 2
        assert lines[2][17:20] == "ALA" and int(lines[2][22:26]) == 3


_MINI_TOP = """\
[ moleculetype ]
Protein_chain_P   3
[ atoms ]
     1   NH1  1  GLY   N   1  -0.3  14.0
     2    H   1  GLY  HN   2   0.3   1.0
     3   CT1  1  GLY  CA   3   0.0  12.0
     4    C   1  GLY   C   4   0.5  12.0
     5    O   1  GLY   O   5  -0.5  16.0
     6   NH1  2  ALA   N   6  -0.3  14.0
     7   CT1  2  ALA  CA   7   0.0  12.0
     8    C   2  ALA   C   8   0.5  12.0
     9    O   2  ALA   O   9  -0.5  16.0
[ bonds ]
     1     3     1
[ system ]
x
[ molecules ]
Protein_chain_P 1
"""


def test_add_cyclic_junction_inline():
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "fep.top"), "w").write(_MINI_TOP)
        status = E.add_cyclic_junction(d)
        assert status.startswith("JUNC_OK"), status
        assert "bonds=1" in status and "angles=4" in status and "dih=6" in status and "impr=2" in status, status
        body = open(os.path.join(d, "fep.top")).read()
        assert "CYCJUNC head-to-tail amide" in body
        # junction bond connects last-res C (atom 8) to first-res N (atom 1)
        assert "    8     1     1 ; CYCJUNC" in body, body


def test_add_cyclic_junction_no_atoms():
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "fep.top"), "w").write("[ system ]\nx\n[ molecules ]\n")
        assert E.add_cyclic_junction(d) == "JUNC_NO_ATOMS"


def test_merge_metal_topology_newline_safe():
    with tempfile.TemporaryDirectory() as d:
        top = os.path.join(d, "fep.top")
        # no trailing newline on the last [molecules] line -> the bug case
        open(top, "w").write('#include "ff.itp"\n[ molecules ]\nProtein_chain_P 1')
        E.merge_metal_topology(top, "cada_mn.itp", "MN2", 3)
        txt = open(top).read()
        assert '#include "cada_mn.itp"' in txt
        assert txt.endswith("\n"), "must end in newline so a later SOL append is on its own line"
        lines = txt.strip().splitlines()
        assert lines[-1].split()[0] == "MN2" and lines[-1].split()[1] == "3"
        # simulate gmx solvate appending SOL and confirm it is NOT concatenated onto MN2
        with open(top, "a") as fh:
            fh.write("SOL 100\n")
        last_two = open(top).read().strip().splitlines()[-2:]
        assert last_two[0].startswith("MN2") and last_two[1].startswith("SOL"), last_two


def test_parse_mutations():
    resids, lines = E._parse_mutations("P:1 TYR->PHE,P:7 TYR->PHE")
    assert resids == [1, 7], resids
    assert lines == ["P 1 PHE", "P 7 PHE"], lines
    # tolerant of the 'P 1 PHE' shorthand (no ->)
    resids2, lines2 = E._parse_mutations("P 3 ALA")
    assert resids2 == [3] and lines2 == ["P 3 ALA"]


def test_knowledge_liability_gate_tiers():
    rows = E.screen_knowledge_liability(
        [("clean", "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])"),
         ("dirty", "cyclo(R-G-D-N-G-M-C)")], target_pack="avb6")
    by = {r["id"]: r for r in rows}
    assert by["dirty"]["tier"] == "HOLD", by["dirty"]
    codes = {f["code"] for f in by["dirty"]["flags"]}
    assert "cmc:NG" in codes and "cmc:free-Cys" in codes          # universal CMC
    assert "sar:pan-RGD" in codes                                 # avb6 pack SAR


def test_fto_gate_fails_open_without_kb():
    rows = E.screen_fto([("x", "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])")])
    assert rows[0]["status"] == "no_fto_reference"
    assert rows[0]["verdict"] is None                             # never a fabricated verdict


def test_fto_gate_novelty_and_claim():
    # identity axis: a candidate identical to a known compound -> novelty_watch
    rows = E.screen_fto([("x", "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])")],
                        known_compounds=["cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])"])
    assert rows[0]["nearest_known_identity"] == 1.0 and rows[0]["novelty_watch"] is True
    # claim genus: form+motif match -> occupied
    rows2 = E.screen_fto([("x", "cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])")],
                         claim_kb={"cyclic": True, "ring_size": 9, "motif": "RGDL"})
    assert rows2[0]["occupied"] is True and "INSIDE" in rows2[0]["verdict"]



def test_pep3_receptor_bundled_under_project_dir():
    """Guard: coldstart pep-3 must resolve receptor without sibling sample_data.
    Bare receptor=1BXL.pdb (catalog seed) maps via _resolveReceptor → assets/.
    """
    wf = os.path.join(HERE, "..")
    asset = os.path.join(wf, "assets", "1BXL.pdb")
    assert os.path.isfile(asset) and os.path.getsize(asset) > 1000, asset
    nf = open(os.path.join(wf, "main.nf"), encoding="utf-8").read()
    assert "_resolveReceptor" in nf
    assert 'projectDir}/assets/1BXL.pdb' in nf
    assert "equalsIgnoreCase('1BXL.pdb')" in nf


def main():

    tests = [v for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    passed = 0
    for t in tests:
        t()
        print(f"  PASS {t.__name__}")
        passed += 1
    print(f"\n{passed}/{len(tests)} passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
