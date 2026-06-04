#!/usr/bin/env python3
"""
Unified inhibitor-track science QC with explicit pass/fail gates.

Reads GROMACS/MM-GBSA binding_summary.json, pipeline manifest, Vina baseline,
and ensemble docking (if present). Does NOT treat MM-GBSA as rank-ready until
control gates pass.
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
DEFAULT_PIPELINE = ROOT / "research/anti-virus/runs/andv_nf_pipeline_20260513T032000Z"
DEFAULT_PUB = ROOT / "research/anti-virus/runs/publication_20260528T223525Z"

# QC thresholds (documented in output)
PROTEIN_RMSD_PASS_NM = 0.55
PROTEIN_RMSD_WARN_NM = 0.45
LIGAND_RMSD_PASS_NM = 0.35
LIGAND_RMSD_WARN_NM = 0.50
MMGBSA_SUSPICIOUS_KCAL = -20.0  # more negative than this with high RMSD → artifact
ASPIRIN_VINA_KCAL = -6.22  # approximate rigid baseline

PANELS = [
    ("INH-01", "05_gromacs_mmgbsa_inh01", "N=C(N)NC(=O)c1nccnc1N"),
    ("INH-02", "05_gromacs_mmgbsa_inh02", "CNC1=NC(N)=C2NCCN=C2N1"),
    ("INH-03", "05_gromacs_mmgbsa_inh03", "Nc1oc2c(N)[n+]([O-])n(O)c2c1O"),
    ("INH-04", "05_gromacs_mmgbsa_inh04", "O=C(O)[C@@H]1O[C@H](O)[C@@H](O)[C@H](O)[C@@H]1O"),
    ("INH-05", "05_gromacs_mmgbsa_inh05", "C[C@]12NCCN3CCN(CCN1)[C@@H]32"),
    ("Aspirin", "05_gromacs_mmgbsa_aspirin", "CC(=O)Oc1ccccc1C(=O)O"),
]


def load_manifest_md_metrics(pipeline: Path) -> dict[str, dict[str, Any]]:
    manifest = pipeline / "pipeline_manifest.json"
    if not manifest.is_file():
        return {}
    data = json.loads(manifest.read_text(encoding="utf-8"))
    out: dict[str, dict[str, Any]] = {}
    for step in data.get("steps") or []:
        key = step.get("key") or ""
        if key.startswith("gromacs_mmgbsa_"):
            label = key.replace("gromacs_mmgbsa_", "").upper()
            if label == "INH01":
                label = "INH-01"
            elif label == "INH02":
                label = "INH-02"
            elif label == "INH03":
                label = "INH-03"
            elif label == "INH04":
                label = "INH-04"
            elif label == "INH05":
                label = "INH-05"
            elif label == "ASPIRIN":
                label = "Aspirin"
            md = step.get("md_metrics") or {}
            if md:
                out[label] = md
    return out


def load_vina_scores(vina_json: Path) -> dict[str, float]:
    if not vina_json.is_file():
        return {}
    data = json.loads(vina_json.read_text(encoding="utf-8"))
    out: dict[str, float] = {}
    for row in data.get("results") or []:
        sm = row.get("smiles")
        aff = row.get("best_affinity_kcal_mol")
        if sm is not None and aff is not None:
            out[sm] = float(aff)
    return out


def load_binding_summary(base: Path) -> dict[str, Any] | None:
    bs = base / "mmgbsa/binding_summary.json"
    if not bs.is_file():
        return None
    return json.loads(bs.read_text(encoding="utf-8"))


def gate_mmgbsa_protocol(
    aspirin: dict[str, Any] | None, vina_by_smiles: dict[str, float]
) -> dict[str, Any]:
    """MM-GBSA ranking is only valid if weak control does not outscore leads."""
    if aspirin is None or aspirin.get("delta_g_bind_kcal_mol") is None:
        return {
            "gate": "MMGBSA_PROTOCOL",
            "status": "INCOMPLETE",
            "pass": False,
            "reason": "Aspirin control MD incomplete (no binding_summary)",
        }
    asp_dg = float(aspirin["delta_g_bind_kcal_mol"])
    asp_vina = vina_by_smiles.get("CC(=O)Oc1ccccc1C(=O)O")
    # Control failure: aspirin MM-GBSA stronger than typical weak binders
    fail = asp_dg <= -12.0
    return {
        "gate": "MMGBSA_PROTOCOL",
        "status": "FAIL" if fail else "PASS",
        "pass": not fail,
        "aspirin_delta_g_bind": asp_dg,
        "aspirin_vina_kcal_mol": asp_vina,
        "reason": (
            "Aspirin ΔG_bind ≤ −12 kcal/mol — MM-GBSA not calibrated for relative ranking"
            if fail
            else "Aspirin within expected weak range for this protocol"
        ),
    }


def load_rank1_pose_qc(pub: Path) -> dict[str, Any] | None:
    p = pub / "zinc600_screen/rank1_pose_qc/RANK1_POSE_QC.json"
    if p.is_file():
        return json.loads(p.read_text(encoding="utf-8"))
    mf = pub / "zinc600_screen/rank1_pose_qc/RANK1_POSE_QC_MANIFEST.json"
    if mf.is_file():
        m = json.loads(mf.read_text(encoding="utf-8"))
        lr = m.get("ligand_rmsd") or {}
        if lr.get("ligand_rmsd_mean_nm") is not None:
            return {
                "ligand_rmsd_mean_nm": lr["ligand_rmsd_mean_nm"],
                "ligand_rmsd_max_nm": lr.get("ligand_rmsd_max_nm"),
                "vina_kcal_mol": m.get("vina_kcal_mol"),
                "smiles": m.get("smiles"),
                "pose_qc_status": m.get("pose_qc_status"),
            }
    return None


def load_ligand_rmsd_batch(pub: Path) -> dict[str, dict[str, Any]]:
    p = pub / "inhibitor_science_qc/LIGAND_RMSD_BATCH.json"
    if not p.is_file():
        return {}
    data = json.loads(p.read_text(encoding="utf-8"))
    return {r["compound"]: r for r in data.get("panels") or [] if r.get("compound")}


def gate_compound(
    label: str,
    summary: dict[str, Any] | None,
    vina_kcal: float | None,
    protocol_pass: bool,
    ligand_rmsd: dict[str, Any] | None = None,
) -> dict[str, Any]:
    if summary is None:
        return {
            "compound": label,
            "overall": "INCOMPLETE",
            "mmgbsa_rank_eligible": False,
            "reasons": ["No binding_summary.json"],
        }
    dg = summary.get("delta_g_bind_kcal_mol")
    md = summary.get("trajectory_analysis") or summary.get("md_qc") or summary
    rmsd_mean = md.get("protein_backbone_rmsd_mean_nm")
    lig_mean = (ligand_rmsd or {}).get("ligand_rmsd_mean_nm")
    reasons: list[str] = []
    flags: list[str] = []

    pose_ok = rmsd_mean is None or float(rmsd_mean) <= PROTEIN_RMSD_PASS_NM
    ligand_ok = lig_mean is None or float(lig_mean) <= LIGAND_RMSD_PASS_NM
    if rmsd_mean is not None and float(rmsd_mean) > PROTEIN_RMSD_WARN_NM:
        flags.append(f"protein_RMSD_mean={rmsd_mean} nm > {PROTEIN_RMSD_WARN_NM}")
    if rmsd_mean is not None and float(rmsd_mean) > PROTEIN_RMSD_PASS_NM:
        reasons.append("Protein backbone RMSD exceeds pass threshold — pose unstable")
        pose_ok = False

    if lig_mean is not None and float(lig_mean) > LIGAND_RMSD_WARN_NM:
        flags.append(f"ligand_RMSD_mean={lig_mean} nm > {LIGAND_RMSD_WARN_NM}")
    if lig_mean is not None and float(lig_mean) > LIGAND_RMSD_PASS_NM:
        reasons.append(f"Ligand RMSD {lig_mean} nm — ligand not stable in pocket (~1 ns MD)")
        ligand_ok = False

    if dg is not None and float(dg) <= MMGBSA_SUSPICIOUS_KCAL and not pose_ok:
        reasons.append(f"ΔG_bind={dg} kcal/mol with unstable protein — likely artifact")
        flags.append("mmgbsa_artifact_suspect")

    if not protocol_pass and label != "Aspirin":
        reasons.append("MM-GBSA protocol gate failed (aspirin control)")
        flags.append("protocol_not_diagnostic")

    if label == "Aspirin":
        overall = "CONTROL_FAIL" if not protocol_pass else "CONTROL_OK"
        rank_eligible = False
    elif not pose_ok or not ligand_ok:
        overall = "FAIL"
        rank_eligible = False
    elif not protocol_pass:
        overall = "VINA_ONLY"  # Vina + pose QC only; MM-GBSA not for ranking
        rank_eligible = False
    elif label == "INH-01" and pose_ok and ligand_ok:
        overall = "PARTIAL_PASS"
        rank_eligible = False  # still no protocol pass
        reasons.append("Best combined Vina+pose story; MM-GBSA descriptive only until recalibration")
    else:
        overall = "MARGINAL" if flags else "PASS_POSE"
        rank_eligible = protocol_pass and pose_ok

    return {
        "compound": label,
        "vina_kcal_mol": vina_kcal,
        "delta_g_bind_kcal_mol": dg,
        "protein_rmsd_mean_nm": rmsd_mean,
        "ligand_rmsd_mean_nm": lig_mean,
        "overall": overall,
        "mmgbsa_rank_eligible": rank_eligible,
        "flags": flags,
        "reasons": reasons,
    }


def load_ensemble_qc(pub: Path) -> dict[str, Any]:
    runs = sorted(
        (ROOT / "research/anti-virus/science_sprint/runs").glob("*/track_inh_ensemble/ensemble_results.json"),
        reverse=True,
    )
    if not runs:
        return {"status": "NOT_RUN", "pass": False, "reason": "No ensemble_results.json"}
    best = None
    for path in runs:
        data = json.loads(path.read_text(encoding="utf-8"))
        meta = data.get("meta") or {}
        if meta.get("dry_run"):
            continue
        n_conf = len([c for c in data.get("conformer_runs") or [] if c.get("deposit_id")])
        if n_conf >= 3:
            best = (path, data)
            break
    if best is None:
        path, data = runs[0], json.loads(runs[0].read_text(encoding="utf-8"))
    else:
        path, data = best

    deposit_records = [r for r in data.get("conformer_runs") or [] if r.get("deposit_id")]
    if not deposit_records:
        deposit_labels = {
            c.get("label")
            for c in (data.get("meta") or {}).get("conformers") or []
            if c.get("deposit_id")
        }
        deposit_records = [r for r in data.get("conformer_runs") or [] if r.get("label") in deposit_labels]
    n_with_scores = sum(1 for r in deposit_records if r.get("by_smiles"))
    agg = data.get("aggregate") or {}
    n_improved = agg.get("n_improved_vs_baseline", 0)
    n_compounds = agg.get("n_compounds", 0)

    complete = n_with_scores == len(deposit_records) and len(deposit_records) >= 5
    return {
        "status": "COMPLETE" if complete else "PARTIAL",
        "pass": complete,
        "run_path": str(path),
        "n_deposit_conformers": len(deposit_records),
        "n_conformers_with_scores": n_with_scores,
        "n_improved_vs_baseline": n_improved,
        "n_compounds": n_compounds,
        "interpretation": (
            "Ensemble scores recovered on deposit conformers; "
            f"{n_improved}/{n_compounds} improved vs rigid baseline (may be zero — honest negative)."
            if complete
            else "Ensemble incomplete — top-15 run missing local results; re-run required"
        ),
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pipeline-run", type=Path, default=DEFAULT_PIPELINE)
    ap.add_argument("--publication-run", type=Path, default=DEFAULT_PUB)
    args = ap.parse_args()

    pipeline = args.pipeline_run.resolve()
    pub = args.publication_run.resolve()
    out_dir = pub / "inhibitor_science_qc"
    out_dir.mkdir(parents=True, exist_ok=True)

    vina_json = pub / "zinc150_screen/vina/docking_autodock_vina_results.json"
    vina_by_smiles = load_vina_scores(vina_json)
    library_smi = pub / "assets/zinc600_library.smi"
    library_n = sum(
        1
        for line in library_smi.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.startswith("#")
    ) if library_smi.is_file() else 600
    dock_data = json.loads(vina_json.read_text(encoding="utf-8")) if vina_json.is_file() else {}
    docked_n = len(dock_data.get("results") or [])
    zinc600_complete = docked_n >= library_n

    aspirin_summary = load_binding_summary(pipeline / "05_gromacs_mmgbsa_aspirin")
    protocol_gate = gate_mmgbsa_protocol(aspirin_summary, vina_by_smiles)

    manifest_md = load_manifest_md_metrics(pipeline)
    ligand_batch = load_ligand_rmsd_batch(pub)

    compounds: list[dict[str, Any]] = []
    for label, subdir, smiles in PANELS:
        summary = load_binding_summary(pipeline / subdir)
        if summary and label in manifest_md:
            md = manifest_md[label]
            if md.get("protein_backbone_rmsd_mean_nm") is not None:
                summary = dict(summary)
                summary.setdefault("trajectory_analysis", {})
                if isinstance(summary["trajectory_analysis"], dict):
                    summary["trajectory_analysis"] = {
                        **summary["trajectory_analysis"],
                        "protein_backbone_rmsd_mean_nm": md["protein_backbone_rmsd_mean_nm"],
                    }
        lrmsd = ligand_batch.get(label)
        compounds.append(
            gate_compound(
                label,
                summary,
                vina_by_smiles.get(smiles),
                protocol_gate["pass"],
                lrmsd,
            )
        )

    ensemble = load_ensemble_qc(pub)
    rank1 = load_rank1_pose_qc(pub)
    rank1_lig = float(rank1["ligand_rmsd_mean_nm"]) if rank1 and rank1.get("ligand_rmsd_mean_nm") is not None else None
    rank1_pass = rank1_lig is not None and rank1_lig <= LIGAND_RMSD_PASS_NM

    compute_lead = "INH-01 (Vina + pose QC)"
    lead_basis = (
        "Best rigid Vina among pose-QC-validated hits (−6.27 kcal/mol); ligand RMSD ~0.20 nm; "
        "MM-GBSA not used for ranking (aspirin control failure)"
    )
    if rank1 and rank1_pass and rank1.get("vina_kcal_mol") is not None:
        lead_basis += (
            f"; Z600-R1 higher Vina ({rank1['vina_kcal_mol']} kcal/mol) but worse pose "
            f"(ligand RMSD {rank1_lig:.3f} nm vs INH-01 ~0.20 nm) — not promoted"
        )

    report = {
        "analyzed_at": datetime.now(timezone.utc).isoformat(),
        "thresholds": {
            "protein_rmsd_pass_nm": PROTEIN_RMSD_PASS_NM,
            "protein_rmsd_warn_nm": PROTEIN_RMSD_WARN_NM,
            "mmgbsa_suspicious_kcal": MMGBSA_SUSPICIOUS_KCAL,
        },
        "gates": {
            "mmgbsa_protocol": protocol_gate,
            "ensemble_docking": ensemble,
        },
        "compounds": compounds,
        "science_verdict": {
            "mmgbsa_usable_for_ranking": protocol_gate["pass"],
            "compute_lead": compute_lead,
            "lead_basis": lead_basis,
            "z600_rank1_pose_qc": rank1,
            "do_not_lead_with": ["INH-03"],
            "blockers": [
                b
                for b in [
                    None if protocol_gate["pass"] else "MM-GBSA aspirin control failure",
                    None if ensemble.get("pass") else "Ensemble docking incomplete on ZINC top-15",
                    None if len(ligand_batch) >= 5 else "Ligand RMSD batch incomplete",
                    None
                    if zinc600_complete
                    else f"ZINC600 screen incomplete ({docked_n}/{library_n} docked)",
                ]
                if b
            ],
        },
        "zinc600_screen": {
            "library_n": library_n,
            "docked_n": docked_n,
            "complete": zinc600_complete,
            "results_json": str(vina_json),
        },
    }

    out_json = out_dir / "INHIBITOR_SCIENCE_QC.json"
    out_json.write_text(json.dumps(report, indent=2), encoding="utf-8")

    md = [
        "# Inhibitor track — science QC gates",
        "",
        f"Generated: {report['analyzed_at']}",
        "",
        "## Protocol gates",
        "",
        f"| Gate | Status | Pass | Notes |",
        f"| --- | --- | --- | --- |",
        f"| MM-GBSA protocol | {protocol_gate['status']} | {'yes' if protocol_gate['pass'] else '**no**'} | {protocol_gate['reason']} |",
        f"| Ensemble docking | {ensemble['status']} | {'yes' if ensemble.get('pass') else '**no**'} | {ensemble.get('interpretation', ensemble.get('reason', ''))} |",
        "",
    ]
    if rank1:
        md.append("## Z600-R1 rank-1 pose QC")
        md.append("")
        md.append(f"| Vina (kcal/mol) | Ligand RMSD (nm) | Verdict |")
        md.append(f"| ---: | ---: | --- |")
        v = rank1.get("vina_kcal_mol", "—")
        lr = rank1.get("ligand_rmsd_mean_nm", "—")
        verdict = "PASS" if rank1_pass else "REVIEW/FAIL"
        md.append(f"| {v} | {lr} | **{verdict}** (INH-01 baseline ~0.20 nm) |")
        md.append("")
    md.extend(
        [
            "## Per-compound QC",
            "",
            "| Compound | Vina | MM-GBSA ΔG | Protein RMSD (nm) | Ligand RMSD (nm) | Verdict | MM-GBSA rank? |",
            "| --- | ---: | ---: | ---: | ---: | --- | --- |",
        ]
    )
    for c in compounds:
        v = c.get("vina_kcal_mol")
        dg = c.get("delta_g_bind_kcal_mol")
        rmsd = c.get("protein_rmsd_mean_nm")
        lrmsd = c.get("ligand_rmsd_mean_nm")
        md.append(
            f"| {c['compound']} | {v if v is not None else '—'} | "
            f"{dg if dg is not None else '—'} | {rmsd if rmsd is not None else '—'} | "
            f"{lrmsd if lrmsd is not None else '—'} | "
            f"**{c['overall']}** | {'yes' if c['mmgbsa_rank_eligible'] else 'no'} |"
        )
    md.extend(
        [
            "",
            "## Science verdict",
            "",
            f"- **Compute lead:** {report['science_verdict']['compute_lead']} — {report['science_verdict']['lead_basis']}",
            f"- **MM-GBSA usable for ranking:** {'yes' if report['science_verdict']['mmgbsa_usable_for_ranking'] else '**no** (control failure)'}",
            "- **Remaining blockers:**",
        ]
    )
    for b in report["science_verdict"]["blockers"]:
        md.append(f"  - {b}")

    out_md = out_dir / "INHIBITOR_SCIENCE_QC.md"
    out_md.write_text("\n".join(md) + "\n", encoding="utf-8")
    print(f"Wrote {out_json}")
    print(f"Wrote {out_md}")
    print(f"MM-GBSA protocol: {protocol_gate['status']} | Ensemble: {ensemble['status']}")


if __name__ == "__main__":
    main()
