"""CI smoke for biomni-tools — run INSIDE the built image before push.

Mirrors the import/functional checks the Dockerfile already declares (RDKit,
ViennaRNA, AutoDock Vina, Biopython, Meeko) so a dependency drift that breaks any
of them fails CI here instead of when a real Batch workflow uses the image.
Extend with a real end-to-end call for the tool you rely on most.
"""
from rdkit import Chem

assert Chem.MolFromSmiles("c1ccccc1") is not None, "RDKit failed to parse benzene"

import RNA

struct, mfe = RNA.fold("GGCAUAUGCUUAGUGCAUAUGC")
assert struct and isinstance(mfe, float), "ViennaRNA fold failed"

from vina import Vina  # noqa: F401
import Bio  # noqa: F401
import meeko  # noqa: F401

print(f"SMOKE PASS: rdkit + ViennaRNA(mfe={mfe:.2f}) + vina + biopython + meeko OK", flush=True)
