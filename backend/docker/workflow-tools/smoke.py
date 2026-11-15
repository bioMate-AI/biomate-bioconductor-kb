"""CI smoke for workflow-tools — run INSIDE the built image before push.

Mirrors the import/functional checks the Dockerfile already declares (RDKit,
ViennaRNA, AutoDock Vina, Biopython, Meeko) so a dependency drift that breaks any
of them fails CI here instead of when a real Batch workflow uses the image.
Extend with a real end-to-end call for the tool you rely on most.
"""
from rdkit import Chem
import math

assert Chem.MolFromSmiles("c1ccccc1") is not None, "RDKit failed to parse benzene"

import RNA

struct, mfe = RNA.fold("GGCAUAUGCUUAGUGCAUAUGC")
assert len(struct) == 22 and isinstance(mfe, float) and math.isfinite(mfe), "ViennaRNA fold failed"

from vina import Vina  # noqa: F401
import Bio  # noqa: F401
import meeko  # noqa: F401
import cv2  # noqa: F401
import PyPDF2  # noqa: F401
import flowio  # noqa: F401  # FCS reader for flow-cytometry workflows
from DeepPurpose import DTI, utils  # noqa: F401


def load_canonical_function(workflow_path, function_name):
    """Load only the named function from the actual read-only workflow fixture.

    Do not run workflow top-level parameter/output code or substitute a second
    implementation. Missing/ambiguous input fails instead of falling back.
    """
    import ast
    from pathlib import Path
    import re

    path = Path(workflow_path)
    if not path.is_file() or path.stat().st_size > 2 * 1024 * 1024:
        raise ValueError("Canonical workflow fixture missing or too large")
    text = path.read_text()
    blocks = re.findall(r"python3 << 'PYEOF'\n(.*?)^PYEOF\s*$", text, re.M | re.S)
    if len(blocks) != 1:
        raise ValueError("Expected exactly one canonical Python body")
    tree = ast.parse(blocks[0], filename=str(path))
    functions = [node for node in tree.body if isinstance(node, ast.FunctionDef) and node.name == function_name]
    if len(functions) != 1 or functions[0].decorator_list:
        raise ValueError("Missing, duplicate or decorated canonical function")
    selected = ast.Module(body=functions, type_ignores=[])
    namespace = {}
    exec(compile(selected, str(path), "exec"), namespace)
    return namespace[function_name]

# Prove an actual workflow entry point emits usable data, not merely imports.
# This fixture tests basic chemistry only, not ADMET accuracy or learned models.
import csv
import os
import tempfile
import importlib.util

# A stale SDK must not accidentally satisfy the scientific contract.
assert importlib.util.find_spec("biomni") is None, "Obsolete wrapper SDK remains in image"
canonical_path = os.environ.get("BIOMATE_SMOKE_WORKFLOW_FILE", "/canonical-workflow.nf")
calculate_physicochemical_properties = load_canonical_function(canonical_path, "calculate_physicochemical_properties")

original_directory = os.getcwd()
try:
    with tempfile.TemporaryDirectory(prefix="workflow-tools-smoke-") as directory:
        os.chdir(directory)
        result = calculate_physicochemical_properties("CCO")
        assert isinstance(result, str) and "ERROR" not in result.upper(), result
        with open("physicochemical_properties.csv", newline="") as handle:
            rows = list(csv.reader(handle))
        assert rows[0] == ["Property", "Value"], rows[:1]
        properties = dict(rows[1:])
        assert properties["SMILES"] == "CCO", properties
        assert math.isclose(float(properties["Molecular Weight"]), 46.07, abs_tol=0.02), properties
        assert int(properties["Heavy Atoms"]) == 3, properties
        assert int(properties["H-Bond Donors"]) == 1, properties
        invalid = calculate_physicochemical_properties("not-a-molecule")
        assert isinstance(invalid, str) and invalid.startswith("ERROR:"), invalid
finally:
    os.chdir(original_directory)

print(f"SMOKE PASS: core imports + ViennaRNA(mfe={mfe:.2f}) + canonical workflow ethanol output + invalid-input rejection; no wrapper SDK", flush=True)
