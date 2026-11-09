# syntax=docker/dockerfile:1
# biomate/mlip-md — OpenMM 8 + openmm-ml machine-learned-potential MD (AIMNet2, MACE-OFF23).
# Used by nextflow_nfcore/subworkflows/molecular_dynamics/mlip_md_simulation, whose process carries
# label process_gpu (GPU queue: g6 L4 / g4dn T4 on the ECS NVIDIA AMI, CUDA 12 drivers). PyTorch is
# the CUDA 12 build; the script falls back to OpenMM's CPU platform when no GPU is visible.
# Built by scripts/build_mlip_md_image.sh; the final RUN is an import + energy smoke test, so a
# broken potential install fails the build, not a user run.
FROM docker.io/condaforge/miniforge3:24.11.3-2
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# The build host has no GPU, so conda sees no __cuda virtual package; declare the target CUDA so the
# solver picks the CUDA PyTorch build. 12.4 runs on any >=525 driver (CUDA minor-version compatibility).
ENV CONDA_OVERRIDE_CUDA=12.4
RUN conda install -y -n base -c conda-forge \
        python=3.11 "openmm>=8.1" openmm-ml openmm-torch "pytorch=*=cuda*" "cuda-version=12.4" \
        numpy mdtraj rdkit procps-ng \
 && conda clean -afy
# Pin numpy to the version conda solved: openmm's compiled extensions (xtc_utils) are built against
# it, and an unconstrained pip pulled numpy 2.2.6 under a numpy-1.x openmm ("numpy.core.multiarray
# failed to import" at `import openmm.app`, run 90a2f0dc, 2026-11-08).
RUN NP="$(python -c 'import numpy; print(numpy.__version__)')" \
 && pip install --no-cache-dir "numpy==${NP}" mace-torch "git+https://github.com/isayevlab/aimnetcentral.git" \
 && python -c "import numpy, sys; assert numpy.__version__ == '${NP}', numpy.__version__"
ENV PATH=/opt/conda/bin:$PATH
# Smoke (CPU platform — the build host has no GPU): both potentials build an OpenMM System for
# water and return a finite energy. CUDA is exercised by the workflow's first real GPU run.
# Needs BuildKit (heredoc RUN); the legacy builder runs `python -` on empty input and passes
# vacuously, so the smoke writes a marker that the last RUN requires.
RUN python - <<'PY'
from openmm.app import Topology, Element
from openmm import Vec3, VerletIntegrator, Context, Platform
from openmm.unit import nanometer, kilojoule_per_mole, femtosecond
from openmmml import MLPotential
import math
top = Topology(); ch = top.addChain(); res = top.addResidue("HOH", ch)
o = top.addAtom("O", Element.getBySymbol("O"), res)
h1 = top.addAtom("H1", Element.getBySymbol("H"), res); h2 = top.addAtom("H2", Element.getBySymbol("H"), res)
pos = [Vec3(0, 0, 0), Vec3(0.0957, 0, 0), Vec3(-0.024, 0.0927, 0)] * nanometer
for name in ("mace-off23-small", "aimnet2"):
    sysm = MLPotential(name).createSystem(top)
    ctx = Context(sysm, VerletIntegrator(1 * femtosecond), Platform.getPlatformByName("CPU"))
    ctx.setPositions(pos)
    e = ctx.getState(getEnergy=True).getPotentialEnergy().value_in_unit(kilojoule_per_mole)
    assert math.isfinite(e), name
    print("smoke", name, round(e, 3), "kJ/mol")
import torch, openmm.app  # openmm.app imports the compiled xtc extension
assert torch.version.cuda, "PyTorch is not the CUDA build"
print("smoke torch", torch.__version__, "cuda", torch.version.cuda)
open("/opt/mlip_smoke_ok", "w").write("ok\n")
PY
RUN test -f /opt/mlip_smoke_ok
