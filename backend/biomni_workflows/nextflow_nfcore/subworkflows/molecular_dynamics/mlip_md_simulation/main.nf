#!/usr/bin/env nextflow
/*
 * molecular_dynamics/mlip_md_simulation
 *
 * Short, QM-accurate molecular dynamics / geometry optimization driven by a
 * machine-learned interatomic potential (MLIP) instead of a classical force
 * field. Runs on OpenMM 8 via openmm-ml, so a neural-network potential provides
 * the forces for a fully GPU-accelerated integrator — near-DFT accuracy at a
 * fraction of ab-initio cost.
 *
 * Potentials (params.mlip):
 *   - aimnet2  (DEFAULT): AIMNet2 — a charge-aware equivariant NNP trained on a
 *              broad organic/druglike chemical space incl. charged and
 *              zwitterionic species. Best default for drug-like ligands.
 *              Anstine, Zubatyuk & Isayev, "AIMNet2: A Neural Network Potential
 *              to Meet your Neutral, Charged, Organic, and Elemental-Organic
 *              Needs", Chem. Sci. 2025; doi:10.1039/D4SC08572H.
 *   - mace_off: MACE-OFF — a transferable equivariant message-passing potential
 *              for neutral organic chemistry (MACE-OFF23).
 *              Kovács et al., "MACE-OFF: Short-Range Transferable Machine
 *              Learning Force Fields for Organic Molecules", JACS 2025;
 *              doi:10.1021/jacs.4c07099.
 *
 * Engine: OpenMM 8 (Eastman et al., PLoS Comput. Biol. 2017;13(7):e1005659)
 *         + openmm-ml MLPotential API (github.com/openmm/openmm-ml).
 *
 * The process runs minimization → short NVT (Langevin) and writes
 * mlip_md_summary.json (final potential energy, heavy-atom RMSD vs the input
 * structure, potential used, n_steps, temperature) plus a trajectory (DCD).
 *
 * --mock true takes a GPU/OpenMM-free deterministic branch that emits a
 * well-formed summary so the DAG can be dry-run locally (see tests/).
 */

nextflow.enable.dsl = 2

// ── Parameters ────────────────────────────────────────────────────────────────
params.outdir          = './results'
params.input_structure = null       // PDB of the system (protein-ligand or small molecule); REQUIRED
params.mlip            = 'aimnet2'   // 'aimnet2' (default) | 'mace_off'
params.n_steps         = 5000        // NVT integration steps after minimization
params.temperature_k   = 300         // NVT thermostat temperature (Kelvin)
params.mock            = false       // true => deterministic, dependency-free dry-run branch

// No clean public biocontainer bundles OpenMM 8 + openmm-ml + a CUDA build +
// the AIMNet2/MACE-OFF model weights, so this is a purpose-built image
// (conda-forge env pinned in tests/README-style header below). On AWS it must
// be mirrored to ECR, mirroring the biomni-admet pattern.
//   conda create -n mlip -c conda-forge python=3.10 \
//       "openmm>=8.1" openmm-ml openmm-torch nnpops \
//       pytorch pytorch-cuda=12.1 aimnet2 mace-torch rdkit mdtraj
// Verified in conda-forge (2026-07): openmm 8.3-8.5.2, openmm-torch 1.1-1.5.1,
// openmm-ml 1.0-1.7 (noarch), nnpops 0.2-0.7 all exist; base image
// condaforge/miniforge3:24.11.3-2 exists on Docker Hub (HTTP 200).
params.mlip_container  = System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/mlip-md:x86' : 'biomate/mlip-md:latest'

process MLIP_MD_SIMULATION {
    tag "$meta.id"
    label 'process_high'                    // GPU: MLIP forces run on CUDA
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    container params.mlip_container

    input:
    tuple val(meta), path(structure)

    output:
    tuple val(meta), path("mlip_md_summary.json"), emit: summary
    tuple val(meta), path("mlip_md_trajectory.dcd"), optional: true, emit: trajectory
    path "versions.yml",                           emit: versions

    script:
    """
    export PARAM_STRUCTURE='${structure}'
    export PARAM_MLIP='${params.mlip}'
    export PARAM_N_STEPS='${params.n_steps}'
    export PARAM_TEMPERATURE_K='${params.temperature_k}'
    export PARAM_MOCK='${params.mock}'
    export PARAM_MOL_ID='${meta.id}'

    python3 << 'PYEOF'
import json, os, hashlib

structure   = os.environ.get("PARAM_STRUCTURE", "")
mlip        = (os.environ.get("PARAM_MLIP", "aimnet2") or "aimnet2").lower()
n_steps     = int(float(os.environ.get("PARAM_N_STEPS", "5000") or 5000))
temperature = float(os.environ.get("PARAM_TEMPERATURE_K", "300") or 300)
mock        = str(os.environ.get("PARAM_MOCK", "false")).lower() in ("true", "1", "yes")
mol_id      = os.environ.get("PARAM_MOL_ID", "system")

# openmm-ml exposes AIMNet2 / MACE-OFF via the MLPotential name registry.
_POTENTIAL = {"aimnet2": "aimnet2", "mace_off": "mace-off23"}
if mlip not in _POTENTIAL:
    raise SystemExit("Unknown params.mlip=%r; choose 'aimnet2' or 'mace_off'" % mlip)
potential_name = _POTENTIAL[mlip]

traj_path = "mlip_md_trajectory.dcd"

# ── MOCK branch: deterministic, no GPU / OpenMM required ─────────────────────
# Wires the DAG end-to-end for local dry-runs. Values are derived
# deterministically from the input + params so tests can assert exact fields.
if mock:
    with open(structure, "rb") as _f:
        digest = hashlib.sha256(_f.read()).hexdigest()
    seed = int(digest[:8], 16)
    # Plausible negative potential energy (kJ/mol) and a small positive RMSD (nm).
    final_energy_kj_mol = round(-1000.0 - (seed % 5000) - n_steps * 0.01, 4)
    rmsd_nm = round(0.02 + (seed % 100) / 1000.0, 4)
    # Emit an empty placeholder trajectory so the optional output channel exists.
    open(traj_path, "w").close()
    summary = {
        "mol_id": mol_id,
        "mock": True,
        "potential": mlip,
        "openmm_ml_potential_name": potential_name,
        "n_steps": n_steps,
        "temperature_k": temperature,
        "final_potential_energy_kj_mol": final_energy_kj_mol,
        "rmsd_vs_input_nm": rmsd_nm,
        "trajectory": traj_path,
        "engine": "mock",
        "note": "Deterministic mock run (no GPU/OpenMM); for DAG wiring test only.",
    }
    with open("mlip_md_summary.json", "w") as f:
        json.dump(summary, f, indent=2)
    print("mlip_md_simulation[MOCK]: %s via %s, %d steps" % (mol_id, mlip, n_steps))
    raise SystemExit(0)

# ── REAL branch: OpenMM 8 + openmm-ml MLIP dynamics ──────────────────────────
import numpy as np
from openmm.app import PDBFile, DCDReporter, Simulation
from openmm import LangevinMiddleIntegrator, Platform
from openmm.unit import kelvin, picosecond, femtosecond, nanometer, kilojoule_per_mole
from openmmml import MLPotential

pdb = PDBFile(structure)
input_positions = np.array(pdb.positions.value_in_unit(nanometer))

# Build an all-atom ML-potential system for the whole topology.
potential = MLPotential(potential_name)
system = potential.createSystem(pdb.topology)

integrator = LangevinMiddleIntegrator(
    temperature * kelvin, 1.0 / picosecond, 1.0 * femtosecond
)
# Prefer CUDA on the GPU worker; fall back to CPU if unavailable.
try:
    platform = Platform.getPlatformByName("CUDA")
except Exception:
    platform = Platform.getPlatformByName("CPU")

sim = Simulation(pdb.topology, system, integrator, platform)
sim.context.setPositions(pdb.positions)

# Energy minimization (geometry optimization).
sim.minimizeEnergy()

# Short NVT with the ML potential; save a light trajectory.
sim.reporters.append(DCDReporter(traj_path, max(1, n_steps // 100)))
sim.context.setVelocitiesToTemperature(temperature * kelvin)
if n_steps > 0:
    sim.step(n_steps)

state = sim.context.getState(getEnergy=True, getPositions=True)
final_energy = state.getPotentialEnergy().value_in_unit(kilojoule_per_mole)
final_positions = np.array(state.getPositions().value_in_unit(nanometer))

# Heavy-atom (non-hydrogen) RMSD vs the input structure, no re-alignment
# (MD frame is in the same reference frame as the minimized start).
heavy = [i for i, a in enumerate(pdb.topology.atoms()) if a.element is not None and a.element.symbol != "H"]
if heavy:
    d = final_positions[heavy] - input_positions[heavy]
    rmsd_nm = float(np.sqrt((d * d).sum(axis=1).mean()))
else:
    rmsd_nm = float(np.sqrt(((final_positions - input_positions) ** 2).sum(axis=1).mean()))

summary = {
    "mol_id": mol_id,
    "mock": False,
    "potential": mlip,
    "openmm_ml_potential_name": potential_name,
    "n_steps": n_steps,
    "temperature_k": temperature,
    "final_potential_energy_kj_mol": round(final_energy, 4),
    "rmsd_vs_input_nm": round(rmsd_nm, 4),
    "trajectory": traj_path,
    "engine": "openmm8_openmm-ml",
    "platform": platform.getName(),
    "n_atoms": pdb.topology.getNumAtoms(),
}
with open("mlip_md_summary.json", "w") as f:
    json.dump(summary, f, indent=2)
print("mlip_md_simulation: %s via %s on %s, E=%.2f kJ/mol, RMSD=%.3f nm"
      % (mol_id, mlip, platform.getName(), final_energy, rmsd_nm))
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        openmm: \$(python3 -c "import openmm; print(openmm.version.version)" 2>/dev/null || echo "n/a(mock)")
        openmm-ml: \$(python3 -c "import openmmml; print(getattr(openmmml,'__version__','installed'))" 2>/dev/null || echo "n/a(mock)")
        potential: '${params.mlip}'
    END_VERSIONS
    """
}

workflow MLIP_MD_SIMULATION_WORKFLOW {
    take:
    ch_structures   // channel: [ val(meta), path(structure) ]

    main:
    MLIP_MD_SIMULATION(ch_structures)

    emit:
    summary    = MLIP_MD_SIMULATION.out.summary
    trajectory = MLIP_MD_SIMULATION.out.trajectory
    versions   = MLIP_MD_SIMULATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    if (!params.input_structure) {
        error "Please provide --input_structure (a PDB file of the system)"
    }
    if (!(params.mlip in ['aimnet2', 'mace_off'])) {
        error "params.mlip must be 'aimnet2' or 'mace_off' (got '${params.mlip}')"
    }

    ch_structures = Channel.of(params.input_structure)
        .map { p -> [ [id: file(p).baseName], file(p) ] }

    MLIP_MD_SIMULATION_WORKFLOW(ch_structures)

    MLIP_MD_SIMULATION_WORKFLOW.out.summary.view { "Summary: $it" }
}
