#!/usr/bin/env python3
"""Convert mmCIF structure to PDB (first model). Used by ANDV science sprint."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from Bio.PDB import MMCIFParser, PDBIO


def main() -> None:
    ap = argparse.ArgumentParser(description="Convert mmCIF to PDB (first model).")
    ap.add_argument("cif", type=Path, help="Input .cif path")
    ap.add_argument("-o", "--output", type=Path, required=True, help="Output .pdb path")
    args = ap.parse_args()
    if not args.cif.is_file():
        raise SystemExit(f"Input not found: {args.cif}")

    parser = MMCIFParser(QUIET=True)
    structure = parser.get_structure(args.cif.stem, str(args.cif))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    io = PDBIO()
    io.set_structure(structure)
    io.save(str(args.output))
    print(f"Wrote {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
