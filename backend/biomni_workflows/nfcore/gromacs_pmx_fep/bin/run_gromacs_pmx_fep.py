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

STEPS = ["define_edge", "knowledge_liability_gate", "fto_gate",
         "prepare", "equilibrate", "fep_production", "analyze"]

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
    "define_edge":             {"spend": False, "qc": False},  # CPU — auto-advance
    # Knowledge + patent/FTO are CHEAP (zero-compute, no GPU) gates placed BEFORE the
    # expensive physics, so a liability-dirty or patent-occupied edge is dropped before a
    # GPU-hour is spent on it (the research loop's `pharmacophore -> liability/SAR -> FTO ->
    # DOCKING` order, generalised). Each emits a QC verdict (which endpoints PASS/WATCH/HOLD
    # or are FTO-occupied) the user inspects/clears — it never auto-proceeds past a hard flag.
    "knowledge_liability_gate": {"spend": False, "qc": True},  # CPU — SAR/CMC liability verdict
    "fto_gate":                 {"spend": False, "qc": True},  # CPU — patent/FTO verdict
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


# --- knowledge / FTO gates (CPU, pre-physics) --------------------------------
# Generalised from the research loop's `knowledge_liability_flags.py` (universal CMC
# rules are target-agnostic) and `fto_score.py` (patent/FTO). The UNIVERSAL CMC rules
# below are generic; target-specific SAR lives in optional named PACKS. The FTO gate is
# a KB/rule axis (optional claim genus + optional known-compound identity), NOT exhaustive
# IP clearance, and it FAILS OPEN (honest status, no fabricated verdict) when no KB is given.
CATIONIC, ANIONIC = set("RK"), set("DE")
HYDROPHOBIC, AROMATIC = set("AILMFWVYC"), set("FWY")
# cyclic-aware 2-mer CMC liability hotspots (target-agnostic): motif -> (severity, mechanism)
DIPEPTIDE_LIABILITIES = {
    "NG": ("hard", "Asn-Gly deamidation hotspot (fastest)"),
    "NS": ("soft", "Asn-Ser deamidation"), "NH": ("soft", "Asn-His deamidation"),
    "NA": ("soft", "Asn-Ala deamidation (slower)"),
    "DG": ("hard", "Asp-Gly isomerisation -> isoAsp (fastest)"),
    "DS": ("soft", "Asp-Ser isomerisation"), "DP": ("soft", "Asp-Pro acid-labile cleavage"),
}


def parse_peptide(s: str):
    """Parse a cyclo(...)/one-letter/HELM-ish peptide into (residues, mods, scaffold).
    Minimal generic port of knowledge_liability_flags.parse_helm (no target assumptions)."""
    s = (s or "").strip()
    cyclic = s.lower().startswith("cyclo(")
    disulfide = "disulfide" in s.lower()
    if cyclic:
        inner = s[s.index("(") + 1: s.rindex(")")]
    else:
        inner = s.split(" (")[0]
    toks = [t for t in inner.split("-") if t] if "-" in inner else list(inner)
    residues, mods = [], []
    for t in toks:
        t = t.strip()
        d_stereo = n_methyl = False
        core = t[1:-1] if (t.startswith("[") and t.endswith("]")) else t
        if core.startswith("NMe"):
            n_methyl = True; core = core[3:]
        elif core.startswith("d") and len(core) >= 2 and core[1].isupper():
            d_stereo = True; core = core[1:]
        aa = core[:1].upper()
        if aa.isalpha():
            residues.append(aa); mods.append({"d_stereo": d_stereo, "n_methyl": n_methyl})
    return residues, mods, {"cyclic": cyclic, "disulfide": disulfide, "n_cys": residues.count("C")}


def _cyclic_dimers(residues, cyclic):
    seq = "".join(residues)
    pairs = [seq[i:i + 2] for i in range(len(seq) - 1)]
    if cyclic and len(seq) >= 2:
        pairs.append(seq[-1] + seq[0])
    return pairs


def cmc_liability_flags(residues, mods, scaf):
    """Universal (target-agnostic) CMC/chemical liability flags for one peptide."""
    seq = "".join(residues)
    flags = []
    for dp in _cyclic_dimers(residues, scaf["cyclic"]):
        if dp in DIPEPTIDE_LIABILITIES:
            sev, mech = DIPEPTIDE_LIABILITIES[dp]
            flags.append({"severity": sev, "code": f"cmc:{dp}", "detail": mech})
    if "M" in seq:
        flags.append({"severity": "soft", "code": "cmc:Met-ox", "detail": "methionine oxidation liability"})
    if "W" in seq:
        flags.append({"severity": "soft", "code": "cmc:Trp-ox",
                      "detail": "tryptophan oxidation liability (often load-bearing — flag, do not auto-remove)"})
    if scaf["n_cys"] and scaf["n_cys"] % 2 == 1:
        flags.append({"severity": "hard", "code": "cmc:free-Cys",
                      "detail": f"odd Cys count ({scaf['n_cys']}) -> unpaired thiol / scrambling"})
    return flags


def sar_pack_flags(pack, residues, mods, scaf):
    """Optional TARGET-SPECIFIC SAR rule pack (honestly not generic — named packs only).
    Ported in brief from the research avb6/pdl1 SAR; unknown pack -> no flags + a note."""
    import re as _re
    seq = "".join(residues)
    net = sum(1 for a in seq if a in CATIONIC) - sum(1 for a in seq if a in ANIONIC)
    flags = []
    if pack == "avb6":  # RGD integrin radioligand SAR
        w = seq + seq[:6] if scaf["cyclic"] else seq
        if "RGD" in w and "RGDL" not in w:
            flags.append({"severity": "hard", "code": "sar:pan-RGD",
                          "detail": "RGD without RGD-L selectivity element -> pan-integrin (off-target tox)"})
        if _re.search(r"RGDL[A-Z]{2}[LI]", w) or _re.search(r"RGDL[LI]", w):
            flags.append({"severity": "note", "code": "sar:extended-affinity",
                          "detail": "carries RGDL-[L/I] extended high-affinity motif (affinity bonus)"})
        if not (any(m["d_stereo"] and residues[i] == "P" for i, m in enumerate(mods))
                or any(m["n_methyl"] for m in mods)):
            flags.append({"severity": "hard", "code": "sar:no-lock",
                          "detail": "no D-Pro / N-methyl conformational lock"})
        if net > 0:
            flags.append({"severity": "soft", "code": "sar:renal-charge",
                          "detail": f"net charge +{net}; cationic peptides raise kidney dose (dose-limiting organ)"})
    elif pack == "pdl1":  # macrocycle cleft binder SAR
        if seq:
            hf = sum(1 for a in seq if a in HYDROPHOBIC) / len(seq)
            af = sum(1 for a in seq if a in AROMATIC) / len(seq)
            if hf > 0.6:
                flags.append({"severity": "soft", "code": "sar:aggregation",
                              "detail": f"hydrophobic fraction {hf:.2f} > 0.60 -> aggregation / poor solubility"})
            if af > 0.45:
                flags.append({"severity": "soft", "code": "sar:aromatic-stack",
                              "detail": f"aromatic fraction {af:.2f} > 0.45 -> π-stacking aggregation risk"})
    return flags, net


def screen_knowledge_liability(sequences, target_pack=None):
    """Per-sequence CMC (+ optional target SAR pack) liability tiering (PASS/WATCH/HOLD)."""
    rows = []
    for sid, seq in sequences:
        residues, mods, scaf = parse_peptide(seq)
        flags = cmc_liability_flags(residues, mods, scaf)
        pack_flags, net = ([], 0)
        if target_pack:
            pack_flags, net = sar_pack_flags(target_pack, residues, mods, scaf)
            flags += pack_flags
        hard = [f for f in flags if f["severity"] == "hard"]
        soft = [f for f in flags if f["severity"] == "soft"]
        tier = "HOLD" if hard else ("WATCH" if soft else "PASS")
        rows.append({"id": sid, "seq": "".join(residues), "net_charge": net,
                     "n_hard": len(hard), "n_soft": len(soft), "tier": tier, "flags": flags})
    return rows


def screen_fto(sequences, claim_kb=None, known_compounds=None):
    """Patent/FTO verdict per sequence. KB/rule axis, NOT exhaustive IP clearance.
    - claim_kb (optional): a genus spec {form, motif, ...}; without it -> honest no_claim_kb.
    - known_compounds (optional): list of known/patented sequences -> nearest identity (novelty axis).
    Fails OPEN: no KB and no known-compounds -> status 'no_fto_reference', verdict None (never fabricated)."""
    def _ident(a, b):
        if not a or not b:
            return 0.0
        n = min(len(a), len(b))
        return round(sum(x == y for x, y in zip(a[:n], b[:n])) / max(len(a), len(b)), 2)
    rows = []
    for sid, seq in sequences:
        residues, _, scaf = parse_peptide(seq)
        bb = "".join(residues)
        row = {"id": sid, "backbone": bb, "cyclic": scaf["cyclic"],
               "caveat": "KB/rule FTO axis (genus membership + known-compound identity); "
                         "NOT exhaustive IP clearance — a live patent-office search is a separate, deeper check."}
        if not claim_kb and not known_compounds:
            row.update({"status": "no_fto_reference", "verdict": None,
                        "note": "No claim-genus KB or known-compound set supplied -> FTO fails OPEN "
                                "(no fabricated verdict). Supply --claim-kb and/or --known-compounds to screen."})
            rows.append(row); continue
        row["status"] = "screened"
        if known_compounds:
            nearest = max(((_ident(bb, "".join(parse_peptide(k)[0])), k) for k in known_compounds),
                          default=(0.0, None))
            row["nearest_known_identity"] = nearest[0]
            row["nearest_known"] = nearest[1]
            row["novelty_watch"] = nearest[0] >= 0.85  # close analog of a known/patented compound
        if claim_kb:
            motif = claim_kb.get("motif")
            form_ok = (claim_kb.get("cyclic") in (None, scaf["cyclic"]))
            size_ok = (claim_kb.get("ring_size") in (None, len(residues)))
            w = bb + bb[:6] if scaf["cyclic"] else bb
            motif_in = (motif is None) or (motif in w)
            row["claim_form_match"] = bool(form_ok and size_ok and motif_in)
            row["occupied"] = bool(form_ok and size_ok and motif_in)  # inside the genus FORM+motif
            row["verdict"] = ("INSIDE claim genus (form+motif) -> redesign/DoE before progressing"
                              if row["occupied"] else "OUTSIDE claim genus form -> FTO-clear on this claim")
        rows.append(row)
    return rows


def _edge_sequences(args):
    """Resolve the edge's endpoint sequence(s) to screen. --sequences 'A|B' (or 'A,B') if given;
    else a peptide_pair edge_spec of the same shape; else none (honest no_sequence)."""
    raw = (args.sequences or "").strip()
    if not raw and args.edge_kind == "peptide_pair" and ("|" in (args.edge_spec or "")):
        raw = args.edge_spec
    if not raw:
        return []
    parts = [p.strip() for p in raw.replace("|", ",").split(",") if p.strip()]
    return [(f"endpoint_{i+1}", p) for i, p in enumerate(parts)]


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
            "2_knowledge_liability_gate": {
                "title": "2 · Knowledge / liability gate", "type": "object",
                "properties": {
                    "sequences": {"type": "string",
                                  "description": "Edge endpoint peptide sequence(s) 'A|B' to screen (CMC + SAR)."},
                    "target_pack": {"type": "string",
                                    "description": "Optional target SAR pack (avb6, pdl1); universal CMC rules always run."},
                },
            },
            "3_fto_gate": {
                "title": "3 · Patent / FTO gate", "type": "object",
                "properties": {
                    "claim_kb": {"type": "string", "format": "file-path",
                                 "description": "Optional claim-genus KB JSON; without it FTO fails open (no fabricated verdict)."},
                    "known_compounds": {"type": "string",
                                        "description": "Optional known/patented sequences 'A|B' for the novelty/identity axis."},
                },
            },
            "4_prepare": {
                "title": "4 · Prepare systems", "type": "object",
                "properties": {
                    "legs": {"type": "string", "default": "complex,solvent",
                             "description": "Which thermodynamic legs to build."},
                },
            },
            "5_equilibrate": {
                "title": "5 · Equilibrate", "type": "object",
                "properties": {
                    "dt_fs": {"type": "number", "default": 2.0,
                              "description": "MD timestep (fs). cada-bonded forces <=0.5; cada-vsite/non-metal use 2."},
                    "equil_ns": {"type": "number", "default": 0.7, "description": "Total NVT+NPT equilibration (ns)."},
                    "restraints": {"type": "string", "enum": ["none", "backbone", "heavy"], "default": "backbone",
                                   "description": "Position restraints during equilibration."},
                },
            },
            "6_fep_production": {
                "title": "6 · FEP production", "type": "object",
                "properties": {
                    "lambda_windows": {"type": "integer", "default": 12, "description": "Number of λ windows."},
                    "production_ns": {"type": "number", "default": 5.0, "description": "ns per λ window."},
                    "protocol_repeats": {"type": "integer", "default": 3, "description": "Independent repeats (SEM)."},
                    "temperature": {"type": "number", "default": 298.15, "description": "K."},
                },
            },
            "7_analyze": {
                "title": "7 · Analyze (ΔΔG + QC)", "type": "object",
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


def step_knowledge_liability_gate(args) -> dict:
    """CPU, pre-physics. Flags CMC/SAR liabilities on the edge endpoint sequence(s) and
    tiers each PASS/WATCH/HOLD, so a HOLD edge is caught before any GPU is spent. QC gate:
    the chain halts for the user to inspect/clear. Honest: no sequence -> no_sequence."""
    seqs = _edge_sequences(args)
    if not seqs:
        out = {"step": "knowledge_liability_gate", "status": "no_sequence",
               "rows": [], "note": "No endpoint sequence to screen (give --sequences 'A|B' or a "
                                   "peptide_pair edge_spec). Zero-compute SAR/CMC screen skipped honestly."}
        _write(args.outdir, "knowledge_liability.json", out)
        return out
    rows = screen_knowledge_liability(seqs, target_pack=args.target_pack or None)
    worst = "HOLD" if any(r["tier"] == "HOLD" for r in rows) else (
        "WATCH" if any(r["tier"] == "WATCH" for r in rows) else "PASS")
    out = {"step": "knowledge_liability_gate", "status": "screened", "worst_tier": worst,
           "target_pack": args.target_pack or None, "rows": rows,
           "note": "Zero-compute CMC (universal) + optional target-SAR-pack liability screen. "
                   "HOLD = design out the hard liability before spending FEP; WATCH = flagged, proceed with caveat."}
    _write(args.outdir, "knowledge_liability.json", out)
    return out


def step_fto_gate(args) -> dict:
    """CPU, pre-physics. Patent/FTO screen (KB/rule axis, NOT exhaustive IP clearance) on the
    edge endpoint sequence(s). Fails OPEN (honest status, no fabricated verdict) without a
    claim-genus KB or known-compound set. QC gate: halts for user inspection."""
    seqs = _edge_sequences(args)
    if not seqs:
        out = {"step": "fto_gate", "status": "no_sequence", "rows": [],
               "note": "No endpoint sequence to screen for FTO. Give --sequences."}
        _write(args.outdir, "fto.json", out)
        return out
    claim_kb = None
    if args.claim_kb:
        try:
            with open(args.claim_kb) as fh:
                claim_kb = json.load(fh)
        except OSError as e:
            out = {"step": "fto_gate", "status": "claim_kb_unreadable", "rows": [],
                   "note": f"--claim-kb {args.claim_kb} could not be read ({e}); not fabricating a verdict."}
            _write(args.outdir, "fto.json", out)
            return out
    known = [k.strip() for k in (args.known_compounds or "").replace("|", ",").split(",") if k.strip()] or None
    rows = screen_fto(seqs, claim_kb=claim_kb, known_compounds=known)
    occupied = any(r.get("occupied") for r in rows)
    novelty_watch = any(r.get("novelty_watch") for r in rows)
    status = "screened" if (claim_kb or known) else "no_fto_reference"
    out = {"step": "fto_gate", "status": status, "any_claim_occupied": occupied,
           "any_novelty_watch": novelty_watch, "rows": rows,
           "note": "Patent/FTO KB-rule axis (genus membership + known-compound identity). "
                   "NOT exhaustive IP clearance — a live patent search is a separate deeper check. "
                   "Fails OPEN without a KB rather than fabricating."}
    _write(args.outdir, "fto.json", out)
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


# --- PREPARE build helpers (generalised from build_fep_setup.sh) -------------
# The PURE-PYTHON helpers below (origin rotation, junction injection, metal merges)
# are the hard-won correctness logic and are unit-tested. The gmx/pmx subprocess
# orchestration in _real_prepare is a faithful port of the validated build_leg and runs
# ONLY in the GROMACS+pmx run image (gated by _tools_available); locally it is never
# reached (step_prepare returns requires_tools), so the honesty contract holds.
import re as _re
import subprocess as _subprocess


def rotate_cyclic_origin(n_res: int, mut_resids):
    """A cyclic peptide's numbering origin is arbitrary. Choose a new start residue so
    EVERY mutation site is interior (never new-position 1 or N) and the linear 'cut' falls
    on a non-mutated junction — so pmx gentop's i±1 dihedral lookup never hits resid 0.
    Returns (order, new_mut_positions); order[new-1] = original resid. Generalises the
    αvβ6 hardcoded order=[3,4,5,6,7,8,9,1,2]. Raises if no such origin exists."""
    M = set(mut_resids)

    def prev(k):
        return k - 1 if k > 1 else n_res
    for k in range(1, n_res + 1):
        if k in M or prev(k) in M:
            continue
        order = [((k - 1 + i) % n_res) + 1 for i in range(n_res)]
        new_mut = [order.index(m) + 1 for m in mut_resids]
        return order, new_mut
    raise ValueError(f"no cyclic origin leaves all mutation sites {sorted(M)} interior "
                     f"(ring size {n_res}); edge too dense for the rotation approach")


def apply_rotation_to_pdb(pdb_path: str, order, out_path: str) -> None:
    """Rewrite a peptide PDB in the rotated residue order (coordinates unchanged; only
    resSeq renumbered), matching build_fep_setup.sh's rotate step."""
    byres: dict[int, list] = {}
    for ln in open(pdb_path):
        if ln.startswith(("ATOM", "HETATM")):
            rs = int(ln[22:26]); byres.setdefault(rs, []).append(ln.rstrip("\n"))
    out = []
    for newid, orig in enumerate(order, 1):
        for ln in byres[orig]:
            out.append(ln[:22] + ("%4d" % newid) + ln[26:])
    with open(out_path, "w") as fh:
        fh.write("\n".join(out) + "\nEND\n")


def add_cyclic_junction(workdir: str) -> str:
    """Fully parameterize the head-to-tail junction (bond + Urey-Bradley angles + proper
    + improper dihedrals, CHARMM36m functs 1/5/9/2) in the PEPTIDE moleculetype — selected
    BY NAME as the fewest-residue [atoms] block across fep.top + its local #includes (robust
    in a multi-chain complex). Params left empty -> grompp resolves by atom type. CMAP at the
    2 junction residues is omitted (bounded approximation; backbone func-9 dihedrals carry the
    torsional energy). Faithful port of build_fep_setup.sh's add_cyclic_junction. Returns a
    status string (JUNC_OK ... / JUNC_NO_ATOMS / JUNC_ATOM_MISSING ...)."""
    top = os.path.join(workdir, "fep.top")
    t0 = open(top).read()
    cands = [top]
    for inc in _re.findall(r'#include\s+"([^"]+)"', t0):
        if (not inc.startswith("/")) and inc.endswith(".itp") and os.path.exists(os.path.join(workdir, inc)):
            cands.append(os.path.join(workdir, inc))
    best = None
    for fn in cands:
        tt = open(fn).read()
        for m in _re.finditer(r"\[ atoms \](.*?)(?=\n\[|\Z)", tt, _re.S):
            amap, resnrs = {}, set()
            for ln in m.group(1).splitlines():
                p = ln.split()
                if len(p) >= 5 and p[0].isdigit():
                    amap[(int(p[2]), p[4])] = int(p[0]); resnrs.add(int(p[2]))
            if resnrs and (best is None or len(resnrs) < best[0]):
                best = (len(resnrs), fn, m.end(), tt, amap, min(resnrs), max(resnrs))
    if best is None:
        return "JUNC_NO_ATOMS"
    nres, fn, endpos, tt, amap, r1, rN = best

    def A(rnr, *names):
        for n in names:
            if (rnr, n) in amap:
                return amap[(rnr, n)]
        return None
    N1, CA1, C1 = A(r1, "N"), A(r1, "CA"), A(r1, "C")
    HN1 = A(r1, "HN", "H", "H1", "HT1")
    NN, CAN, CN = A(rN, "N"), A(rN, "CA"), A(rN, "C")
    ON = A(rN, "O", "O1", "OT1", "OC1")
    if not all([N1, CA1, C1, NN, CAN, CN, ON]):
        return (f"JUNC_ATOM_MISSING file={os.path.basename(fn)} nres={nres} r1={r1} rN={rN}")
    bonds = [(CN, N1)]
    angles = [(CAN, CN, N1), (ON, CN, N1), (CN, N1, CA1)]
    if HN1:
        angles.append((CN, N1, HN1))
    dih = [(CAN, CN, N1, CA1), (ON, CN, N1, CA1), (NN, CAN, CN, N1), (CN, N1, CA1, C1)]
    if HN1:
        dih += [(CAN, CN, N1, HN1), (ON, CN, N1, HN1)]
    impr = [(CN, CAN, N1, ON)]
    if HN1:
        impr.append((N1, CN, CA1, HN1))
    ins = "\n[ bonds ]\n" + "".join("%5d %5d     1 ; CYCJUNC head-to-tail amide\n" % b for b in bonds)
    ins += "[ angles ]\n" + "".join("%5d %5d %5d     5 ; CYCJUNC\n" % a for a in angles)
    ins += "[ dihedrals ]\n" + "".join("%5d %5d %5d %5d     9 ; CYCJUNC proper\n" % d for d in dih)
    ins += "[ dihedrals ]\n" + "".join("%5d %5d %5d %5d     2 ; CYCJUNC improper\n" % i for i in impr)
    with open(fn, "w") as fh:
        fh.write(tt[:endpos] + ins + tt[endpos:])
    return (f"JUNC_OK file={os.path.basename(fn)} r1={r1} rN={rN} bonds={len(bonds)} "
            f"angles={len(angles)} dih={len(dih)} impr={len(impr)} HN={'y' if HN1 else 'n'} cmap=OMITTED")


def merge_metal_topology(topfile: str, itp_name: str, resname: str, count: int) -> None:
    """Include the CaDA metal itp after the first #include and append the metal molecule to
    [ molecules ] WITH a guaranteed trailing newline — so a later `gmx solvate` SOL append
    lands on its own line (a missing newline concatenated 'MN2 3'+'SOL N' -> '3SOL' and
    silently dropped the waters). Faithful port."""
    lines = open(topfile).read().splitlines()
    out, done = [], False
    for ln in lines:
        out.append(ln)
        if ln.strip().startswith("#include") and not done:
            out.append(f'#include "{itp_name}"'); done = True
    s = "\n".join(out).rstrip("\n") + f"\n{resname:<18} {count}\n"
    with open(topfile, "w") as fh:
        fh.write(s)


def merge_metal_gro(box_gro: str, metal_pdb: str, resname: str) -> int:
    """Append the metal (CaDA dummy) atoms from a PDB to a solute box .gro BEFORE solvation.
    Returns the number of atoms added. Faithful port of the mngro step."""
    g = open(box_gro).read().splitlines()
    n = int(g[1]); body = g[2:2 + n]; box = g[2 + n]
    mn = []; resn = 1; idx = 0
    for ln in open(metal_pdb):
        if ln.startswith("HETATM"):
            x = float(ln[30:38]) / 10; y = float(ln[38:46]) / 10; z = float(ln[46:54]) / 10
            nm = ln[12:16].strip()
            if nm == "MN" and idx != 0:
                resn += 1
            mn.append("%5d%-5s%5s%5d%8.3f%8.3f%8.3f" % (resn, resname, nm, (n + len(mn) + 1) % 100000, x, y, z))
            idx += 1
    with open(box_gro, "w") as fh:
        fh.write(g[0] + "\n%d\n" % (n + len(mn)) + "\n".join(body + mn) + "\n" + box + "\n")
    return len(mn)


def _parse_mutations(edge_spec: str):
    """'P:1 TYR->PHE,P:7 TYR->PHE' (or 'P 1 PHE,...') -> (resids, pmx_script_lines).
    pmx expects 'CHAIN RESID NEWRES' per line."""
    resids, lines = [], []
    for part in edge_spec.split(","):
        part = part.strip()
        if not part:
            continue
        m = _re.match(r"([A-Za-z]):?\s*(\d+)\s+([A-Z]{3})\s*(?:->\s*([A-Z]{3}))?", part)
        if not m:
            raise ValueError(f"unparseable mutation {part!r}; expected 'P:1 TYR->PHE'")
        chain, resid, a, b = m.group(1), int(m.group(2)), m.group(3), m.group(4)
        new = b or a
        resids.append(resid); lines.append(f"{chain} {resid} {new}")
    return resids, lines


def _sh(cmd: str, cwd: str, logname: str, env: dict):
    """Run a shell stage, fail loudly (raise on non-zero), tee to a log. Mirrors the
    build_leg stage calls; success only on return 0."""
    with open(os.path.join(cwd, logname), "w") as log:
        r = _subprocess.run(cmd, cwd=cwd, shell=True, stdout=log, stderr=_subprocess.STDOUT, env=env)
    if r.returncode != 0:
        tail = open(os.path.join(cwd, logname)).read().splitlines()[-6:]
        raise RuntimeError(f"stage failed ({logname} rc={r.returncode}): " + " | ".join(tail))


def _real_prepare(args, legs):  # pragma: no cover - requires gmx+pmx (runs in run image)
    """Build the pmx hybrid + solvated system per leg, faithful to the validated
    build_fep_setup.sh, generalised (FF/mutations/metal from params; no αvβ6 hardcoding).
    Runs ONLY where gmx+pmx exist (gated upstream). Fail-loudly; returns per-leg real
    atom counts + staged version-independent files. NEVER fabricates numbers."""
    ff = args.force_field
    metal = resolve_metal(args.metal_model)
    env = dict(os.environ)
    workroot = os.path.join(args.outdir, "build")
    os.makedirs(workroot, exist_ok=True)
    # inputs expected staged next to outdir: receptor.pdb, peptide.pdb, (metal itp + metal pdb if metal)
    receptor = os.path.join(args.outdir, "receptor.pdb")
    peptide = os.path.join(args.outdir, "peptide.pdb")
    mut_resids, pmx_lines = _parse_mutations(args.edge_spec)
    pep_use = peptide
    if args.modality == "cyclic_peptide":
        n_res = len({int(l[22:26]) for l in open(peptide) if l.startswith(("ATOM", "HETATM"))})
        order, new_mut = rotate_cyclic_origin(n_res, mut_resids)
        pep_use = os.path.join(workroot, "peptide_rot.pdb")
        apply_rotation_to_pdb(peptide, order, pep_use)
        # remap mutation resids to the rotated numbering for the pmx script
        remap = {orig: new for new, orig in enumerate(order, 1)}
        pmx_lines = [f"{l.split()[0]} {remap[int(l.split()[1])]} {l.split()[2]}" for l in pmx_lines]
    muts = os.path.join(workroot, "muts.txt")
    open(muts, "w").write("\n".join(pmx_lines) + "\n")
    pmxcli = os.environ.get("PMXCLI", "pmx")
    results = {}
    for leg in legs:
        W = os.path.join(workroot, leg); os.makedirs(W, exist_ok=True)
        with_metal = (leg == "complex" and metal["kind"] != "none")
        if leg == "solvent":
            start = os.path.join(W, "start.pdb"); shutil.copy(pep_use, start)
        else:  # complex: receptor + rotated peptide as one PDB (chains A,B,P)
            start = os.path.join(W, "start.pdb")
            with open(start, "w") as fh:
                for ln in open(receptor):
                    if ln.startswith(("ATOM", "TER")):
                        fh.write(ln)
                fh.write("TER\n")
                for ln in open(pep_use):
                    if ln.startswith(("ATOM", "HETATM")):
                        fh.write(ln)
                fh.write("END\n")
        env["GMXLIB"] = os.environ.get("GMXLIB", "")
        _sh(f"gmx pdb2gmx -f start.pdb -o conf.pdb -p topol.top -i posre.itp -ff {ff} -water tip3p -ignh < /dev/null",
            W, f"{leg}_pdb2gmx.out", env)
        _sh(f"{pmxcli} mutate -f conf.pdb -o hybrid.pdb -ff {ff} --script {muts} --ref start.pdb",
            W, f"{leg}_mutate.out", env)
        _sh(f"gmx pdb2gmx -f hybrid.pdb -o hconf.pdb -p htop.top -i hposre.itp -ff {ff} -water tip3p < /dev/null",
            W, f"{leg}_hpdb2gmx.out", env)
        _sh(f"{pmxcli} gentop -p htop.top -o fep.top -ff {ff}", W, f"{leg}_gentop.out", env)
        if args.modality == "cyclic_peptide":
            jr = add_cyclic_junction(W)
            if not jr.startswith("JUNC_OK"):
                raise RuntimeError(f"{leg} cyclic junction: {jr}")
        if with_metal:
            itp = metal.get("itp") if metal["kind"] == "cada-vsite" else metal["fallback"]["itp"]
            shutil.copy(os.path.join(args.outdir, itp), os.path.join(W, itp))
            merge_metal_topology(os.path.join(W, "fep.top"), itp, f"{metal['ion'].upper()}2", 3)
        _sh("gmx editconf -f hconf.pdb -o box.gro -c -d 1.2 -bt dodecahedron", W, f"{leg}_editconf.out", env)
        if with_metal:
            merge_metal_gro(os.path.join(W, "box.gro"),
                            os.path.join(args.outdir, f"{metal['ion'].lower()}_metal.pdb"), f"{metal['ion'].upper()}2")
        _sh("gmx solvate -cp box.gro -cs spc216.gro -p fep.top -o solv.gro", W, f"{leg}_solvate.out", env)
        _sh(f"gmx grompp -f {args.outdir}/mdp/em.mdp -c solv.gro -p fep.top -o ions.tpr -maxwarn 20",
            W, f"{leg}_ionsgrompp.out", env)
        _sh("echo SOL | gmx genion -s ions.tpr -o ionized.gro -p fep.top -pname NA -nname CL -neutral -conc 0.15",
            W, f"{leg}_genion.out", env)
        _sh(f"gmx grompp -f {args.outdir}/mdp/em.mdp -c ionized.gro -p fep.top -o em.tpr -maxwarn 20",
            W, f"{leg}_emgrompp.out", env)
        natoms = None
        d = _subprocess.run("gmx dump -s em.tpr", cwd=W, shell=True,
                            stdout=_subprocess.PIPE, stderr=_subprocess.DEVNULL, env=env, text=True)
        mobj = _re.search(r"natoms\s*=\s*(\d+)", d.stdout or "")
        if mobj:
            natoms = int(mobj.group(1))
        results[leg] = {"atoms": natoms, "staged": ["fep.top", "ionized.gro", "em.tpr"],
                        "cyclic_junction": args.modality == "cyclic_peptide", "metal": with_metal}
    return results


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
    "knowledge_liability_gate": step_knowledge_liability_gate,
    "fto_gate": step_fto_gate,
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
    p.add_argument("--force-field", default="charmm36m-mut", dest="force_field",
                   help="GROMACS force field for pdb2gmx/pmx (default charmm36m-mut; provides the hybrid residues).")
    # knowledge_liability_gate / fto_gate (CPU, pre-physics)
    p.add_argument("--sequences", default="", dest="sequences",
                   help="Edge endpoint peptide sequence(s) to screen, 'A|B' or 'A,B' "
                        "(e.g. 'cyclo(F-R-G-D-L-A-F-[dP]-[NMeK])|cyclo(Y-R-G-D-L-A-Y-[dP]-[NMeK])').")
    p.add_argument("--target-pack", default="", dest="target_pack",
                   help="Optional target SAR rule pack for the liability gate (e.g. avb6, pdl1). "
                        "Universal CMC rules always run; a pack adds target-specific SAR.")
    p.add_argument("--claim-kb", default="", dest="claim_kb",
                   help="Optional FTO claim-genus KB JSON {cyclic,ring_size,motif}; without it FTO fails open.")
    p.add_argument("--known-compounds", default="", dest="known_compounds",
                   help="Optional known/patented sequences ('A|B') for the FTO novelty (identity) axis.")
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
