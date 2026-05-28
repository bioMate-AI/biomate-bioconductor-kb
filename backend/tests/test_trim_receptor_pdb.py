"""Tests for shared receptor PDB trim (Vina / GROMACS parity)."""
import json
import tempfile
import unittest
from pathlib import Path

from biomni_workflows.nextflow_nfcore.lib.trim_receptor_pdb import (
    count_pdb_atoms,
    maybe_trim_receptor,
    trim_pdb_to_search_box,
)


def _write_sample_pdb(path: Path, coords: list[tuple[float, float, float]]) -> None:
    lines = []
    for i, (x, y, z) in enumerate(coords, 1):
        lines.append(
            f"ATOM  {i:5d}  CA  ALA A{i:4d}    {x:8.3f}{y:8.3f}{z:8.3f}  1.00  0.00           C\n"
        )
    lines.append("END\n")
    path.write_text("".join(lines), encoding="utf-8")


class TestTrimReceptorPdb(unittest.TestCase):
    def test_trim_keeps_atoms_in_box(self):
        with tempfile.TemporaryDirectory() as tmp:
            inp = Path(tmp) / "in.pdb"
            out = Path(tmp) / "out.pdb"
            # Pocket at origin; one atom inside, one outside
            _write_sample_pdb(
                inp,
                [(0.0, 0.0, 0.0), (100.0, 100.0, 100.0)],
            )
            n = trim_pdb_to_search_box(inp, out, 0, 0, 0, 20, 20, 20, pad=8.0, min_atoms=1)
            self.assertEqual(n, 1)
            self.assertEqual(count_pdb_atoms(out), 1)

    def test_maybe_trim_skips_small_receptor(self):
        with tempfile.TemporaryDirectory() as tmp:
            inp = Path(tmp) / "in.pdb"
            out = Path(tmp) / "out.pdb"
            _write_sample_pdb(inp, [(0.0, 0.0, 0.0)])
            meta = maybe_trim_receptor(
                inp,
                out,
                auto_trim=True,
                min_input_atoms=5000,
                box_center=(0.0, 0.0, 0.0),
                box_size=(20.0, 20.0, 20.0),
                pad=10.0,
            )
            self.assertFalse(meta["trimmed"])
            self.assertEqual(meta["input_atoms"], 1)

    def test_trim_keeps_whole_residues(self):
        # A residue with one atom inside and one atom outside the box must be kept
        # ENTIRELY (no partial residues → no missing backbone C for pdb4amber).
        with tempfile.TemporaryDirectory() as tmp:
            inp = Path(tmp) / "in.pdb"
            out = Path(tmp) / "out.pdb"
            lines = [
                # Residue A/1: N inside box, but CB far outside — must keep both atoms
                "ATOM      1  N   ALA A   1       0.000   0.000   0.000  1.00  0.00           N\n",
                "ATOM      2  CB  ALA A   1     100.000   0.000   0.000  1.00  0.00           C\n",
                # Residue A/2: entirely outside — dropped
                "ATOM      3  N   ALA A   2     500.000 500.000 500.000  1.00  0.00           N\n",
                "END\n",
            ]
            inp.write_text("".join(lines), encoding="utf-8")
            n = trim_pdb_to_search_box(inp, out, 0, 0, 0, 20, 20, 20, pad=8.0, min_atoms=1)
            self.assertEqual(n, 2)  # both atoms of residue A/1 kept
            body = out.read_text(encoding="utf-8")
            self.assertIn("  CB  ALA A   1", body)  # far atom of in-box residue retained
            self.assertNotIn("ALA A   2", body)     # out-of-box residue dropped

    def test_maybe_trim_large_receptor(self):
        with tempfile.TemporaryDirectory() as tmp:
            inp = Path(tmp) / "in.pdb"
            out = Path(tmp) / "out.pdb"
            coords = [(0.0, 0.0, 0.0)] * 6000 + [(200.0, 200.0, 200.0)] * 1000
            _write_sample_pdb(inp, coords)
            meta = maybe_trim_receptor(
                inp,
                out,
                auto_trim=True,
                min_input_atoms=5000,
                box_center=(0.0, 0.0, 0.0),
                box_size=(20.0, 20.0, 20.0),
                pad=10.0,
            )
            self.assertTrue(meta["trimmed"])
            self.assertEqual(meta["output_atoms"], 6000)
            self.assertIn("REMARK BioMate", out.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
