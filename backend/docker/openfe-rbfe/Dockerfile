# BioMate OpenFE RBFE Container
# Real small-molecule relative binding free energy (RBFE / FEP) via OpenFE.
# All packages are open-source (MIT/BSD/Apache); no commercial licence needed.
#
# OpenFE is the field-standard open RBFE engine (Hahn et al., Living J. Comput.
# Mol. Sci. 2022, 4:1497). This image backs
#   backend/biomni_workflows/nextflow_nfcore/subworkflows/drug_discovery/openfe_rbfe
#
# Packages:
#   openfe            : alchemical RBFE engine (LOMAP network + OpenMM RFE protocol)
#   openff-toolkit    : Open Force Field toolkit (Sage 2.x ligand parameters)
#   openmmforcefields : AMBER ff14SB/ff19SB + OpenFF for OpenMM
#   openmm            : GPU/CPU molecular simulation engine (CUDA build for Batch)
#   lomap2            : Lead-optimisation mapper (perturbation-network atom mapping)
#   cinnabar          : RBFE network statistics / MLE ΔG / plotting
#
# NOTE ON PLATFORM: a real RBFE edge needs a GPU. The AWS Batch build must land
# on the GPU queue (galaxy-cloud-queue-gpu). On CPU-only hosts the workflow runs
# in --mode setup/smoke and honestly withholds the ΔΔG (see run_openfe_rbfe.py).
#
# Build (canonical target — referenced by rebuild-base-and-cascade.sh [4/8]):
#   docker buildx build --platform linux/amd64 \
#     -t 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/openfe-rbfe:1.0 \
#     --push -f backend/docker/openfe-rbfe/Dockerfile .

FROM 399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate-nextflow-base:latest

LABEL maintainer="BioMate Team"
LABEL version="1.0"
LABEL description="OpenFE RBFE: real alchemical relative binding free energy via OpenMM + LOMAP + MBAR"

ENV DEBIAN_FRONTEND=noninteractive

# ── System deps (NetCDF/HDF5 for MDAnalysis + OpenMM reporters) ────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    libnetcdf-dev \
    libhdf5-dev \
    && rm -rf /var/lib/apt/lists/*

# ── Core RBFE stack ────────────────────────────────────────────────────────────
# Pin to the OpenFE 1.2.x line whose Python API matches bin/run_openfe_rbfe.py:
#   openfe.SmallMoleculeComponent.from_rdkit / ProteinComponent.from_pdb_file
#   openfe.LomapAtomMapper / lomap_scorers.default_lomap_score
#   openfe.ligand_network_planning.generate_minimal_spanning_network
#   openfe.protocols.openmm_rfe.RelativeHybridTopologyProtocol.default_settings()
#   openfe.execute_dag(...) + protocol.gather([...]).get_estimate()/get_uncertainty()
# openmm>=8.1 ships CUDA kernels; on the GPU Batch node CUDA is auto-selected.
RUN pip install --no-cache-dir \
    "openfe>=1.2.0,<1.4.0" \
    "openff-toolkit>=0.16.0" \
    "openff-units>=0.2.2" \
    "openmmforcefields>=0.12.0" \
    "openmm>=8.1.0" \
    "lomap2>=2.3.0" \
    "cinnabar>=0.5.0" \
    "mdanalysis>=2.7.0" \
    "gufe>=1.1.0" \
    "rdkit>=2024.3.1"

# ── Verify the exact API surface bin/run_openfe_rbfe.py depends on ─────────────
RUN python3 - <<'PY'
import openfe
from openfe import (SmallMoleculeComponent, ProteinComponent, SolventComponent,
                    LomapAtomMapper, ChemicalSystem, Transformation)
from openfe import lomap_scorers, ligand_network_planning
from openfe.protocols.openmm_rfe import RelativeHybridTopologyProtocol
# default_settings must construct and expose the attribute paths we set.
s = RelativeHybridTopologyProtocol.default_settings()
for path in ("thermo_settings.temperature",
             "simulation_settings.equilibration_length",
             "simulation_settings.production_length",
             "lambda_settings.lambda_windows",
             "protocol_repeats"):
    obj = s
    for part in path.split("."):
        obj = getattr(obj, part)
assert hasattr(openfe, "execute_dag"), "openfe.execute_dag missing"
print("OpenFE", openfe.__version__, "RBFE API OK")
PY

WORKDIR /data
CMD ["python3", "-c", "import openfe; print('OpenFE', openfe.__version__, 'ready (RBFE)')"]
