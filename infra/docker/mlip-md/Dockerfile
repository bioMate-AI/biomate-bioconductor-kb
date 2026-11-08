# biomate/mlip-md — OpenMM 8 + openmm-ml machine-learned-potential MD (AIMNet2, MACE-OFF23).
# Used by nextflow_nfcore/subworkflows/molecular_dynamics/mlip_md_simulation. The workflow's
# process carries label process_high, which routes to the CPU hpc queue, so PyTorch is the CPU
# build (a CUDA build adds several GB and would not be used there).
# Built by scripts/build_mlip_md_image.sh; the final RUN is an import + energy smoke test, so a
# broken potential install fails the build, not a user run.
FROM docker.io/condaforge/miniforge3:24.11.3-2
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN conda install -y -n base -c conda-forge \
        python=3.11 "openmm>=8.1" openmm-ml openmm-torch "pytorch=*=cpu*" \
        numpy mdtraj rdkit procps-ng \
 && conda clean -afy
RUN pip install --no-cache-dir mace-torch "git+https://github.com/isayevlab/aimnetcentral.git"
ENV PATH=/opt/conda/bin:$PATH
# Smoke: both potentials build an OpenMM System for water and return a finite energy.
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
PY
