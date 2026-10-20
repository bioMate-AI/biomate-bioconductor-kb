#!/usr/bin/env python3
"""
run_gromacs_pmx_fep.py — reviewed entrypoint for the GROMACS/pmx relative-FEP engine.

GENERIC relative binding free energy (ΔΔG) for edges OpenFE cannot do:
residue-mutation / peptide / cyclic-peptide / metal-bridged. Companion engine to
openfe_rbfe (small-molecule congeneric pairs); the composer routes an FEP request
to whichever engine fits the edge (see docs/20261020_GENERIC_PHYSICS_IN_LOOP_FRAMEWORK_DESIGN.md,
Layer B). αvβ6 is the acceptance-test instance, NOT a hardcoded assumption here.

TRANSPARENT STEP CHAIN (the design-corrected model). The engine is NOT a black-box
auto-run. It is five discrete steps, each surfacing PARAMS / INPUTS / OUTPUTS so the
user drives and inspects it step-by-step through BioMate's workflow panel (phase
cards + editable param strip + previewable outputs + QC gate), exactly like
openfe_rbfe's phases:

  1. define_edge   params: receptor, edge{kind,spec}, modality, metal_model
                   input:  receptor PDB (+ peptide/ligand files)   output: edge_spec.json
  2. prepare       build pmx hybrid topology + solvate/ionize      output: prepared_systems.json
                   (per leg: atom counts, staged .gro/.top)        + staged version-independent inputs
  3. equilibrate   params: dt, equil_ns, restraints                output: equil_metrics.json (acceptance check)
  4. fep_production params: lambda_windows, production_ns, repeats, temperature
                                                                   output: dhdl_summary.json (dH/dλ per window)
  5. analyze       output: ddg_summary.json (ΔΔG ± unc) + qc_metrics.json (cycle_closure gate)

Default = the step chain above, advanced one step at a time with QC gates between.
`--run-all` exists as a convenience mode but is NOT the default.

HONESTY CONTRACT (enforced here, not in the .nf): a step that needs tools/GPU it
does not have records an honest status (`requires_tools` / `requires_gpu`) and writes
NULL numerics. It NEVER fabricates a prepared system, an energy, or a ΔΔG. This is the
same contract openfe_rbfe uses, applied per step.

HARD-WON DEFAULTS baked in (from the αvβ6 instance-zero build — each a generic-engine
requirement, not an αvβ6 quirk):
  * version-independent staged inputs: stage .gro + .top, grompp INSIDE the run image
    (never a prebuilt .tpr — tpx version skew between the build box's GROMACS and the
    run image's GROMACS silently breaks a prebuilt .tpr).
  * cyclic_peptide modality: rotate the (arbitrary) numbering origin so mutation sites
    are interior, so pmx gentop's i±1 dihedral lookup never hits a nonexistent resid 0.
  * select the peptide moleculetype BY NAME (fewest residues) in a multi-chain complex
    topology — a positional/last-block heuristic silently no-ops on the complex leg.
  * newline-safe [ molecules ] edits (a missing trailing newline concatenates
    "MN2 3" + "SOL N" -> "3SOL", silently dropping solvent).
  * fail-loudly: any stage failure -> non-zero exit; success only on the real artifact.
  * clear a stale success sentinel at the start of every step.
  * metal_model: cada-vsite preferred (massless virtual-site octahedron, dt=2 fs),
    cada-bonded small-dt (<=0.5 fs) as the validated fallback; `none` for non-metal targets.

NO free-energy or MD logic is duplicated in the .nf — the .nf stages files and calls
this script per step, so exactly the reviewed code runs on Batch.
"""

from __future__ import annotations
import argparse
import json
import os
import shutil
import sys
from typing import Any

STEPS = ["define_edge", "prepare", "equilibrate", "fep_production", "analyze"]

# --- hard-won defaults (see module docstring) --------------------------------
DEFAULTS = {
    "modality": "peptide",
    "metal_model": "none",         # none | cada:<ion>  (cada ion in METAL_IONS)
    "legs": "complex,solvent",
    "dt_fs": 2.0,                  # cada-vsite / non-metal; bonded fallback forces <=0.5
    "equil_ns": 0.7,              # NVT 0.2 ns + NPT 0.5 ns
    "lambda_windows": 12,
    "production_ns": 5.0,
    "protocol_repeats": 3,
    "temperature": 298.15,
    "restraints": "backbone",      # none | backbone | heavy
    "mode": "setup",              # setup | smoke | production
}
METAL_IONS = {"Mn", "Zn", "Ca", "Mg"}
EDGE_KINDS = {"residue_mutation", "peptide_pair"}
MODALITIES = {"peptide", "cyclic_peptide"}
# A cyclic-peptide metal target (cada-bonded) needs the small timestep; cada-vsite
# and non-metal run at dt=2 fs.
GPU_STEPS = {"equilibrate", "fep_production"}

# Gate semantics (design-corrected orchestration). Steps AUTO-ADVANCE between gates
# by default — the user need not click through every step, which preserves the
# closed-loop value — but GATES ALWAYS HALT for explicit user go. Two gate kinds:
#   spend — the step launches GPU/Batch; the chain NEVER auto-spends (confirm-before-run).
#   qc    — the step produces a QC verdict the user must inspect/clear before proceeding;
#           the chain never auto-proceeds past a failed QC.
# This maps 1:1 onto BioMate's workflow panel: auto-advance == the running phase chain;
# a spend gate == a halted phase with "Confirm & Run"; a qc gate == the QC-gate card the
# user clears. Every step still surfaces params/inputs/outputs, and the user can switch to
# manual/step-by-step (--step) or pause at any point.
STEP_GATES = {
    "define_edge":    {"spend": False, "qc": False},   # CPU — auto-advance
    "prepare":        {"spend": False, "qc": False},   # CPU — auto-advance
    "equilibrate":    {"spend": True,  "qc": True},    # GPU spend; emits stability QC
    "fep_production": {"spend": True,  "qc": False},   # GPU spend
    "analyze":        {"spend": False, "qc": True},    # cycle_closure QC verdict
}


def _write(outdir: str, name: str, obj: dict) -> str:
    path = os.path.join(outdir, name)
    with open(path, "w") as fh:
        json.dump(obj, fh, indent=2)
    return path


def _clear_sentinel(outdir: str) -> None:
    """Hard-won: clear any stale success sentinel so a failed re-run can't be
    misread as a prior success."""
    s = os.path.join(outdir, "STEP_OK")
    try:
        if os.path.exists(s):
            os.remove(s)
    except OSError:
        pass


def _gpu_available() -> bool:
    if os.environ.get("BIOMATE_FORCE_NO_GPU") == "1":
        return False
    return shutil.which("nvidia-smi") is not None


def _tools_available() -> dict:
    return {
        "gmx": shutil.which("gmx") is not None
        or os.path.exists("/usr/local/gromacs/bin/gmx"),
        "pmx": _can_import("pmx"),
    }


def _can_import(mod: str) -> bool:
    try:
        __import__(mod)
        return True
    except Exception:
        return False


# --- metal-model resolution --------------------------------------------------
def resolve_metal(metal_model: str) -> dict:
    """none | cada:<ion> -> {kind, ion, itp, dt_fs, rationale}. Raises on bad input."""
    if metal_model in (None, "", "none"):
        return {"kind": "none", "ion": None, "itp": None, "dt_fs": None}
    if not metal_model.startswith("cada:"):
        raise ValueError(f"metal_model must be 'none' or 'cada:<ion>', got {metal_model!r}")
    ion = metal_model.split(":", 1)[1]
    if ion not in METAL_IONS:
        raise ValueError(f"cada ion must be one of {sorted(METAL_IONS)}, got {ion!r}")
    # vsite octahedron is massless -> no stiff bonds -> stable at dt=2 fs (preferred);
    # bonded is the validated fallback but forces dt<=0.5 fs (4-8x costlier).
    return {
        "kind": "cada-vsite",
        "ion": ion,
        "itp": f"cada_{ion.lower()}_vsite.itp",
        "dt_fs": 2.0,
        "fallback": {"kind": "cada-bonded", "itp": f"cada_{ion.lower()}.itp", "dt_fs": 0.5},
        "source": "Duarte et al. JPCB 2014 (cationic dummy); vsite reformulation preserves charge/LJ/geometry",
    }


# --- per-step validation + param surfacing -----------------------------------
def validate_edge(args) -> dict:
    """define_edge logic: validate + normalise into an edge spec the user reviews."""
    errs = []
    if not args.receptor:
        errs.append("receptor (protein PDB) is required")
    if args.edge_kind not in EDGE_KINDS:
        errs.append(f"edge_kind must be one of {sorted(EDGE_KINDS)}, got {args.edge_kind!r}")
    if not args.edge_spec:
        errs.append("edge_spec is required (e.g. 'P:1 TYR->PHE,P:7 TYR->PHE' or 'pepA|pepB')")
    if args.modality not in MODALITIES:
        errs.append(f"modality must be one of {sorted(MODALITIES)}, got {args.modality!r}")
    try:
        metal = resolve_metal(args.metal_model)
    except ValueError as e:
        errs.append(str(e)); metal = None
    if errs:
        raise ValueError("; ".join(errs))
    spec: dict[str, Any] = {
        "receptor": os.path.basename(args.receptor),
        "edge": {"kind": args.edge_kind, "spec": args.edge_spec},
        "modality": args.modality,
        "metal": metal,
        "legs": [x.strip() for x in args.legs.split(",") if x.strip()],
        # cyclic needs the origin-rotation preprocessing; recorded so PREPARE honours it
        "cyclic_origin_rotation": args.modality == "cyclic_peptide",
    }
    return spec


def param_schema() -> dict:
    """The param schema the workflow panel renders as the editable param strip,
    grouped by step (phase). Mirrors nextflow_schema.json's shape."""
    return {
        "$schema": "https://json-schema.org/draft-07/schema",
        "$id": "biomate-gromacs-pmx-fep",
        "title": "GROMACS/pmx Relative FEP (ΔΔG)",
        "type": "object",
        "steps": STEPS,
        "definitions": {
            "1_define_edge": {
                "title": "1 · Define edge", "type": "object",
                "properties": {
                    "receptor": {"type": "string", "format": "file-path",
                                 "description": "Target protein PDB (dataset chip)."},
                    "edge_kind": {"type": "string", "enum": sorted(EDGE_KINDS),
                                  "default": "residue_mutation",
                                  "description": "residue_mutation (A->B point mutations) or peptide_pair (two peptides)."},
                    "edge_spec": {"type": "string",
                                  "description": "e.g. 'P:1 TYR->PHE,P:7 TYR->PHE' or 'ligandA|ligandB'."},
                    "modality": {"type": "string", "enum": sorted(MODALITIES), "default": "peptide",
                                 "description": "peptide or cyclic_peptide (cyclic adds head-to-tail junction + origin rotation)."},
                    "metal_model": {"type": "string", "default": "none",
                                    "description": "none, or cada:<Mn|Zn|Ca|Mg> for a metal-bridged interface."},
                },
                "required": ["receptor", "edge_spec"],
            },
            "2_prepare": {
                "title": "2 · Prepare systems", "type": "object",
                "properties": {
                    "legs": {"type": "string", "default": "complex,solvent",
                             "description": "Which thermodynamic legs to build."},
                },
            },
            "3_equilibrate": {
                "title": "3 · Equilibrate", "type": "object",
                "properties": {
                    "dt_fs": {"type": "number", "default": 2.0,
                              "description": "MD timestep (fs). cada-bonded forces <=0.5; cada-vsite/non-metal use 2."},
                    "equil_ns": {"type": "number", "default": 0.7, "description": "Total NVT+NPT equilibration (ns)."},
                    "restraints": {"type": "string", "enum": ["none", "backbone", "heavy"], "default": "backbone",
                                   "description": "Position restraints during equilibration."},
                },
            },
            "4_fep_production": {
                "title": "4 · FEP production", "type": "object",
                "properties": {
                    "lambda_windows": {"type": "integer", "default": 12, "description": "Number of λ windows."},
                    "production_ns": {"type": "number", "default": 5.0, "description": "ns per λ window."},
                    "protocol_repeats": {"type": "integer", "default": 3, "description": "Independent repeats (SEM)."},
                    "temperature": {"type": "number", "default": 298.15, "description": "K."},
                },
            },
            "5_analyze": {
                "title": "5 · Analyze (ΔΔG + QC)", "type": "object",
                "properties": {
                    "control_edge_expected": {"type": "number",
                                              "description": "Known ΔΔG for a control edge (kcal/mol); analyze gate checks recovery."},
                },
            },
        },
    }


# --- step implementations ----------------------------------------------------
def step_define_edge(args) -> dict:
    spec = validate_edge(args)
    out = {"step": "define_edge", "status": "ok", "edge_spec": spec,
           "note": "Review/edit the edge, then advance to Prepare."}
    _write(args.outdir, "edge_spec.json", spec)
    return out


def step_prepare(args) -> dict:
    """Build the pmx hybrid topology + solvate/ionize per leg. Emits a previewable
    summary (atom counts, both legs) and STAGES version-independent .gro/.top.
    Honesty: if GROMACS/pmx are absent (local/setup), report requires_tools and
    describe the plan WITHOUT fabricating a prepared system."""
    tools = _tools_available()
    legs = [x.strip() for x in args.legs.split(",") if x.strip()]
    plan = {
        "step": "prepare", "legs": legs, "modality": args.modality,
        "cyclic_origin_rotation": args.modality == "cyclic_peptide",
        "metal": resolve_metal(args.metal_model),
        "staged_inputs": "version-independent .gro + .top (grompp runs in the run image)",
        "moleculetype_selection": "by name = fewest-residue chain (robust in multi-chain complex)",
    }
    if not (tools["gmx"] and tools["pmx"]) or args.mode == "setup":
        out = {**plan, "status": "requires_tools",
               "tools_present": tools,
               "prepared_systems": None,
               "note": "PREPARE needs GROMACS+pmx in the run image. Setup mode / missing tools "
                       "-> plan only, NO fabricated systems. Real run builds pmx hybrid -> "
                       "solvate -> genion per leg and reports real atom counts."}
        _write(args.outdir, "prepared_systems.json", out)
        return out
    # Real build would run here (pmx mutate/gentop -> editconf -> solvate -> genion),
    # honouring origin-rotation (cyclic) and by-name moleculetype selection, writing
    # per-leg {atoms, gro, top}. Deliberately not inlined with fabricated numbers.
    out = {**plan, "status": "built", "prepared_systems": _real_prepare(args, legs)}
    _write(args.outdir, "prepared_systems.json", out)
    return out


def _real_prepare(args, legs):  # pragma: no cover - requires gmx+pmx
    raise NotImplementedError(
        "Real PREPARE executes in the GROMACS+pmx run image; the validated reference "
        "implementation is research/guangzhou_all_atom/fep/preflight/build_fep_setup.sh "
        "(instance-zero). Generalising it into this module is the remaining engine work; "
        "until then PREPARE honestly reports requires_tools rather than fabricating.")


def _gpu_step(args, step_name: str, outfile: str, numeric_keys: list[str]) -> dict:
    """Shared honesty contract for equilibrate / fep_production / analyze:
    a step needing a GPU with none present is RUNNABLE/held with NULL numerics,
    never a fabricated result."""
    if not _gpu_available() or args.mode in ("setup", "smoke"):
        out = {"step": step_name, "status": "requires_gpu",
               "mode": args.mode, "gpu_present": _gpu_available()}
        for k in numeric_keys:
            out[k] = None
        out["note"] = (f"{step_name} needs a GPU and sampling time. No GPU / setup|smoke mode "
                       f"-> status=requires_gpu, numerics=null (no fabrication). On the spot GPU "
                       f"queue it runs and fills these. dt honours the metal model "
                       f"(cada-vsite=2fs, cada-bonded<=0.5fs).")
        _write(args.outdir, outfile, out)
        return out
    raise NotImplementedError(  # pragma: no cover - requires GPU
        f"{step_name} production path runs in the GPU run image (fail-loudly chain; "
        f"success only on the real artifact).")


def step_equilibrate(args) -> dict:
    return _gpu_step(args, "equilibrate", "equil_metrics.json",
                     ["potential_kj_mol", "temperature_k", "pressure_bar",
                      "density_kg_m3", "peptide_rmsd_nm", "lincs_warnings"])


def step_fep_production(args) -> dict:
    return _gpu_step(args, "fep_production", "dhdl_summary.json",
                     ["n_windows_completed", "mean_dhdl_kj_mol"])


def step_analyze(args) -> dict:
    """ΔΔG + uncertainty + cycle_closure QC gate. Writes qc_metrics.json keyed so the
    QC trace monitor picks up the gate (process ANALYZE). Never fabricates a ΔΔG."""
    res = _gpu_step(args, "analyze", "ddg_summary.json",
                    ["ddg_kcal_per_mol", "ddg_sem_kcal_per_mol"])
    # QC gate row (mirrors openfe's cycle_closure gate shape)
    expected = args.control_edge_expected
    qc = {
        "process": "ANALYZE", "domain": "drug_discovery",
        "cycle_closure_kcal_per_mol": None,
        "fep_cycle_closure_status": "requires_gpu" if res["status"] == "requires_gpu" else "pending",
        "control_edge_expected_kcal_per_mol": expected,
        "control_edge_recovered": None,
        "note": "Gate: a control edge's ΔΔG must recover its known value within replicate error "
                "before candidate edges are admissible. Null until a real production run exists.",
    }
    _write(args.outdir, "qc_metrics.json", qc)
    res["qc"] = qc
    return res


STEP_FN = {
    "define_edge": step_define_edge,
    "prepare": step_prepare,
    "equilibrate": step_equilibrate,
    "fep_production": step_fep_production,
    "analyze": step_analyze,
}


def run_step(step: str, args) -> dict:
    os.makedirs(args.outdir, exist_ok=True)
    _clear_sentinel(args.outdir)
    out = STEP_FN[step](args)
    # fail-loudly: a step that errored would have raised; a step that completed (built
    # or honestly-held) marks the sentinel. Downstream reads output JSON, not the sentinel.
    with open(os.path.join(args.outdir, "STEP_OK"), "w") as fh:
        fh.write(f"{step}:{out.get('status')}\n")
    return out


def run_chain(args) -> list:
    """Gate-respecting orchestration (the default transparent chain). Auto-advances
    through non-gate steps; HALTS at a spend gate BEFORE running (never auto-spends)
    and at a qc gate AFTER running (never auto-proceeds past a QC verdict), unless the
    user has explicitly cleared that gate via --gates-cleared. Each halt is an honest
    'awaiting user go' record the panel renders as a confirm/QC card."""
    cleared = set(args.gates_cleared or [])
    results = []
    for s in STEPS:
        g = STEP_GATES[s]
        if g["spend"] and s not in cleared:
            results.append({"step": s, "status": "halted_at_spend_gate", "gate": "spend",
                            "auto_advanced_to_here": True,
                            "note": f"'{s}' launches GPU/Batch — chain halts for explicit user go "
                                    f"(confirm-before-run; never auto-spends). Inspect its params, "
                                    f"then proceed with --gates-cleared {s} (or the panel's Confirm & Run)."})
            break
        out = run_step(s, args)
        results.append(out)
        if g["qc"] and s not in cleared:
            results.append({"step": s, "status": "halted_at_qc_gate", "gate": "qc",
                            "note": f"'{s}' produced a QC verdict to inspect — chain halts; never "
                                    f"auto-proceeds past QC. Clear with --gates-cleared {s} to continue."})
            break
    return results


def build_argparser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="GROMACS/pmx relative-FEP engine (stepwise).")
    p.add_argument("--step", choices=STEPS, help="Run exactly one step (manual / step-by-step drive).")
    p.add_argument("--run-all", action="store_true",
                   help="Run the transparent chain: auto-advance between gates, HALT at spend/QC gates "
                        "for explicit user go. (Convenience default orchestration; still gate-enforced.)")
    p.add_argument("--gates-cleared", nargs="*", default=[], dest="gates_cleared",
                   help="Gate steps the user has explicitly cleared (e.g. equilibrate), so the chain "
                        "proceeds past that spend/QC gate. Nothing cleared by default -> gates halt.")
    p.add_argument("--print-schema", action="store_true", help="Print the param schema and exit.")
    p.add_argument("--outdir", default="./results/gromacs_pmx_fep")
    # define_edge
    p.add_argument("--receptor")
    p.add_argument("--edge-kind", default="residue_mutation", dest="edge_kind")
    p.add_argument("--edge-spec", default="", dest="edge_spec")
    p.add_argument("--modality", default=DEFAULTS["modality"])
    p.add_argument("--metal-model", default=DEFAULTS["metal_model"], dest="metal_model")
    p.add_argument("--legs", default=DEFAULTS["legs"])
    # equilibrate
    p.add_argument("--dt-fs", type=float, default=DEFAULTS["dt_fs"], dest="dt_fs")
    p.add_argument("--equil-ns", type=float, default=DEFAULTS["equil_ns"], dest="equil_ns")
    p.add_argument("--restraints", default=DEFAULTS["restraints"])
    # fep_production
    p.add_argument("--lambda-windows", type=int, default=DEFAULTS["lambda_windows"], dest="lambda_windows")
    p.add_argument("--production-ns", type=float, default=DEFAULTS["production_ns"], dest="production_ns")
    p.add_argument("--protocol-repeats", type=int, default=DEFAULTS["protocol_repeats"], dest="protocol_repeats")
    p.add_argument("--temperature", type=float, default=DEFAULTS["temperature"])
    # analyze
    p.add_argument("--control-edge-expected", type=float, default=None, dest="control_edge_expected")
    p.add_argument("--mode", default=DEFAULTS["mode"], choices=["setup", "smoke", "production"])
    return p


def main(argv=None) -> int:
    args = build_argparser().parse_args(argv)
    if args.print_schema:
        print(json.dumps(param_schema(), indent=2))
        return 0
    os.makedirs(args.outdir, exist_ok=True)
    try:
        if args.run_all:
            results = run_chain(args)
            print(json.dumps({"run_all": True, "gates_cleared": args.gates_cleared,
                              "steps": results}, indent=2))
        elif args.step:
            print(json.dumps(run_step(args.step, args), indent=2))
        else:
            sys.stderr.write("Provide --step <name> (transparent chain) or --run-all.\n")
            return 2
    except (ValueError, NotImplementedError) as e:
        # fail-loudly: surface the error and exit non-zero (no silent success)
        sys.stderr.write(f"ERROR [{getattr(args,'step',None)}]: {e}\n")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
