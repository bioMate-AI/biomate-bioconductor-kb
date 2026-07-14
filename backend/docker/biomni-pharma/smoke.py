"""CI smoke for biomni-pharma — run INSIDE the built image before push.

Basic import/sanity for the pharma stack (RDKit + molfeat + ChEMBL client). Extend
with a real end-to-end call for the tool you rely on most (e.g. molfeat featurizer or
an aizynthfinder retro step); the point is that a dependency drift fails CI here rather
than in a live Batch run.
"""
from rdkit import Chem

assert Chem.MolFromSmiles("CCO") is not None, "RDKit failed to parse ethanol"

import molfeat  # noqa: F401
import chembl_webresource_client  # noqa: F401

print("SMOKE PASS: rdkit + molfeat + chembl_webresource_client import OK", flush=True)
