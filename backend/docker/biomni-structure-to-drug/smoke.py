"""CI smoke for biomni-structure-to-drug, run INSIDE the built image before push.

The 2026-04-07 image shipped without fpocket although the Dockerfile builds it (the image predated the fpocket
lines, and the Dockerfile's own check, `fpocket --help | head -1`, passes even when fpocket is absent because a
pipe returns head's status). This smoke runs fpocket for real and requires its output, plus the docking stack.
"""
import math
import os
import shutil
import subprocess
import tempfile

assert shutil.which("fpocket"), "fpocket is not on PATH"

# A small synthetic two-sheet protein-like slab with a groove between the sheets, so fpocket has a cavity to find.
lines, serial = [], 1
for sheet, z in ((0, 0.0), (1, 9.0)):
    for i in range(12):
        for j in range(6):
            x, y = i * 3.8, j * 4.8 + (2.4 if sheet else 0.0)
            for name, dx, dy, dz, el in (("N", 0.0, 0.0, 0.0, "N"), ("CA", 1.46, 0.0, 0.3, "C"), ("C", 2.0, 1.2, 0.6, "C"),
                                         ("O", 1.5, 2.3, 0.4, "O"), ("CB", 1.9, -1.0, 1.4 if sheet == 0 else -1.4, "C")):
                res = sheet * 100 + i * 6 + j + 1
                lines.append("ATOM  %5d  %-3s LEU A%4d    %8.3f%8.3f%8.3f  1.00  0.00           %s" % (serial, name, res, x + dx, y + dy, z + dz, el))
                serial += 1
work = tempfile.mkdtemp()
pdb = os.path.join(work, "slab.pdb")
open(pdb, "w").write("\n".join(lines) + "\nEND\n")
r = subprocess.run(["fpocket", "-f", pdb], capture_output=True, text=True, timeout=300)
info = os.path.join(work, "slab_out", "slab_info.txt")
assert r.returncode == 0, "fpocket exited %s: %s" % (r.returncode, (r.stderr or r.stdout)[-500:])
assert os.path.exists(info), "fpocket wrote no info file (stdout tail: %s)" % r.stdout[-300:]
n_pockets = sum(1 for ln in open(info) if ln.strip().startswith("Pocket") and ln.strip().endswith(":"))

from rdkit import Chem  # noqa: E402
assert Chem.MolFromSmiles("C#Cc1cccc(Nc2ncnc3cc(OCCOC)c(OCCOC)cc23)c1") is not None, "RDKit failed on erlotinib"
from vina import Vina  # noqa: E402,F401
import meeko  # noqa: E402,F401
assert shutil.which("obabel"), "obabel is not on PATH"

print("SMOKE PASS: fpocket ran (%d pockets on the test slab) + rdkit + vina + meeko + obabel" % n_pockets, flush=True)
