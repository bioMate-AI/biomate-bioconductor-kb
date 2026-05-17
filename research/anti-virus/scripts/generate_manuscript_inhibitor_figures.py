#!/usr/bin/env python3
"""Generate inhibitor manuscript figures v1. See docs/MANUSCRIPT_FIGURES_V1_PLAN.md."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch

ROOT = Path(__file__).resolve().parents[3]
RUN = ROOT / "research" / "anti-virus" / "runs" / "andv_nf_pipeline_20260513T032000Z"
OUT = ROOT / "research" / "anti-virus" / "runs" / "manuscript_figures_v1" / "inhibitor"
POCKETS = RUN / "01_pocket" / "structure_pockets.json"
PHARM_SUMMARY = RUN / "02_pharmacophore" / "summary.json"
DOCK = RUN / "04_docking_vina" / "docking_autodock_vina_results.json"
SCORE = RUN / "06_reinvent4" / "score_history.json"

# RDKit is optional; 2D ligand panel (Fig B5) is skipped if unavailable.
try:
    from rdkit import Chem
    from rdkit.Chem import Draw

    _RDKIT_AVAILABLE = True
except ImportError:
    _RDKIT_AVAILABLE = False

DOCKING_LABEL_SHORT = {
    "CC(=O)Oc1ccccc1C(=O)O": "Aspirin",
    "Oc1ccccc1": "Phenol",
    "CC(=O)Nc1ccc(O)cc1": "Paracetamol",
}


def style_axes(ax) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def sorted_docking_results(dj: dict[str, Any]) -> list[dict[str, Any]]:
    """Strongest (most negative) Vina score first — matches Fig B3 bar order (top = best)."""
    return sorted(
        dj.get("results", []),
        key=lambda r: float(r.get("best_affinity_kcal_mol", 0.0)),
    )


def docking_row_label(r: dict[str, Any]) -> str:
    smi = r.get("smiles", "")
    return DOCKING_LABEL_SHORT.get(smi, smi[:14] + "…")


def load_funnel_counts(dj: dict[str, Any]) -> tuple[int | None, int | None, int, bool]:
    """Return (n_library_screened, n_passed_filter, n_docked, used_pharmacophore_summary)."""
    n_docked = dj.get("n_ligands_docked")
    if n_docked is None:
        n_docked = len(dj.get("results", []))
    else:
        n_docked = int(n_docked)
    if not PHARM_SUMMARY.is_file():
        return None, None, n_docked, False
    ph = json.loads(PHARM_SUMMARY.read_text(encoding="utf-8"))
    n_lib = ph.get("n_library_screened")
    n_pass = ph.get("n_passed_filter")
    if n_lib is None or n_pass is None:
        return None, None, n_docked, False
    return int(n_lib), int(n_pass), n_docked, True


def fig_graphical_abstract() -> None:
    fig, ax = plt.subplots(figsize=(6.5, 3.0), dpi=300)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 4)
    ax.axis("off")
    ax.text(
        5,
        3.45,
        "ANDV GP (PDB 9P3I) — integrated in silico triage (conceptual schematic)",
        ha="center",
        fontsize=10,
        fontweight="bold",
    )
    stages = [
        (1.0, 1.5, "Pocket\nsurvey"),
        (2.9, 1.5, "Pharmacophore\nfilter"),
        (4.8, 1.5, "ADMET /\nproperties"),
        (6.7, 1.5, "AutoDock\nVina"),
        (8.5, 1.5, "Generative\nstep (06)"),
    ]
    for x, y, t in stages:
        ax.add_patch(FancyBboxPatch((x - 0.55, y - 0.45), 1.1, 1.0, boxstyle="round,pad=0.04", facecolor="#E9F5F0", edgecolor="#1B7F5A"))
        ax.text(x, y, t, ha="center", va="center", fontsize=8)
    for i in range(len(stages) - 1):
        ax.annotate("", xy=(stages[i + 1][0] - 0.55, 1.5), xytext=(stages[i][0] + 0.55, 1.5), arrowprops=dict(arrowstyle="->", lw=1.2, color="#283618"))
    ax.text(5, 0.35, "Computational — no antiviral assay claims", ha="center", fontsize=8, style="italic", color="#555555")
    fig.savefig(OUT / "GA_inhibitor.png", bbox_inches="tight")
    fig.savefig(OUT / "GA_inhibitor.pdf", bbox_inches="tight")
    plt.close(fig)


def fig_pockets() -> None:
    data = json.loads(POCKETS.read_text(encoding="utf-8"))
    pockets = sorted(data.get("pockets", []), key=lambda p: float(p.get("druggability_score", 0)), reverse=True)[:8]
    ids = [str(p["pocket_id"]) for p in pockets]
    scores = [float(p["druggability_score"]) for p in pockets]
    volumes = [float(p.get("volume_A3", 0.0)) for p in pockets]

    fig, ax1 = plt.subplots(figsize=(4.0, 2.9), dpi=300)
    x = range(len(ids))
    ax1.bar(ids, scores, color="#264653", label="Druggability", zorder=2)
    ax1.set_xlabel("Pocket id (ranked by druggability)")
    ax1.set_ylabel("Druggability score", color="#264653")
    ax1.tick_params(axis="y", labelcolor="#264653")
    style_axes(ax1)

    ax2 = ax1.twinx()
    ax2.plot(ids, volumes, "o-", color="#E76F51", lw=1.6, markersize=5, label="Volume (Å³)", zorder=3)
    ax2.set_ylabel("Pocket volume (Å³)", color="#E76F51")
    ax2.tick_params(axis="y", labelcolor="#E76F51")
    ax2.spines["top"].set_visible(False)

    lines1, lab1 = ax1.get_legend_handles_labels()
    lines2, lab2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, lab1 + lab2, loc="upper right", frameon=False, fontsize=7)

    ax1.set_title("Fig. B1 | Top pockets: druggability and volume", fontsize=10, fontweight="bold", loc="left")
    fig.savefig(OUT / "FigB1_pocket_druggability.png", bbox_inches="tight")
    fig.savefig(OUT / "FigB1_pocket_druggability.pdf", bbox_inches="tight")
    plt.close(fig)


def fig_funnel(n_lib: int | None, n_pass: int | None, n_dock: int, data_driven: bool) -> None:
    fig, ax = plt.subplots(figsize=(3.2, 3.0), dpi=300)
    ax.axis("off")
    if data_driven and n_lib is not None and n_pass is not None:
        levels = [
            ("Screening\nlibrary", 3.2, str(n_lib)),
            ("Pharmacophore\npass", 1.8, str(n_pass)),
            ("Docked\nligands", 0.9, str(n_dock)),
        ]
        subtitle = (
            f"Counts from pharmacophore summary and docking JSON ({n_lib} → {n_pass} → {n_dock}); "
            "box widths are not proportional to n"
        )
        use_counts_in_boxes = True
    else:
        levels = [
            ("Screening\nlibrary", 3.2, None),
            ("Pharmacophore\npass", 1.8, None),
            ("Docked\nligands", 0.9, str(n_dock)),
        ]
        subtitle = f"Demonstration scale (n = {n_dock} docked); schematic when pharmacophore summary is missing"
        use_counts_in_boxes = False
    y = 4.0
    for label, width, count_txt in levels:
        left = (4 - width) / 2
        ax.add_patch(FancyBboxPatch((left, y), width, 0.75, boxstyle="round,pad=0.02", facecolor="#E0B1CB", edgecolor="#5C4D6F"))
        if use_counts_in_boxes and count_txt is not None:
            ax.text(2, y + 0.48, label, ha="center", va="center", fontsize=9)
            ax.text(2, y + 0.2, f"n = {count_txt}", ha="center", va="center", fontsize=9, fontweight="bold")
        elif count_txt is not None:
            ax.text(2, y + 0.48, label, ha="center", va="center", fontsize=9)
            ax.text(2, y + 0.2, f"n = {count_txt}", ha="center", va="center", fontsize=9, fontweight="bold")
        else:
            ax.text(2, y + 0.35, label, ha="center", va="center", fontsize=9)
        y -= 1.05
    ax.set_xlim(0, 4)
    ax.set_ylim(0, 5)
    ax.text(2, 0.28, subtitle, ha="center", fontsize=7, style="italic")
    title = "Fig. B2 | In silico funnel"
    if data_driven:
        title += " (data-labeled)"
    else:
        title += " (schematic)"
    ax.set_title(title, fontsize=10, fontweight="bold", loc="center", y=0.98)
    fig.savefig(OUT / "FigB2_pipeline_funnel.png", bbox_inches="tight")
    fig.savefig(OUT / "FigB2_pipeline_funnel.pdf", bbox_inches="tight")
    plt.close(fig)


def fig_docking() -> None:
    dj = json.loads(DOCK.read_text(encoding="utf-8"))
    results = sorted_docking_results(dj)
    labels = [docking_row_label(r) for r in results]
    vals = [float(r["best_affinity_kcal_mol"]) for r in results]
    fig, ax = plt.subplots(figsize=(3.5, 2.8), dpi=300)
    ax.barh(labels, vals, color="#2A9D8F")
    ax.invert_yaxis()
    ax.set_xlabel("Best Vina score (kcal mol⁻¹)")
    style_axes(ax)
    ax.set_title("Fig. B3 | Docking scores (filtered set)", fontsize=10, fontweight="bold", loc="left")
    fig.savefig(OUT / "FigB3_docking_scores.png", bbox_inches="tight")
    fig.savefig(OUT / "FigB3_docking_scores.pdf", bbox_inches="tight")
    plt.close(fig)


def fig_reinvent() -> None:
    sh = json.loads(SCORE.read_text(encoding="utf-8"))
    hist = sh.get("history") or []
    epochs = [h["epoch"] for h in hist]
    means = [h["mean_score"] for h in hist]
    tops = [h["top_score"] for h in hist]
    tool = sh.get("tool", "")
    fig, ax = plt.subplots(figsize=(3.5, 2.6), dpi=300)
    if len(epochs) >= 2:
        ax.plot(epochs, means, "o-", color="#8338EC", label="Mean score")
        ax.plot(epochs, tops, "s--", color="#FF006E", label="Top score")
        ax.legend(frameon=False, fontsize=7)
    else:
        ax.scatter([1], means or [sh.get("final_mean_score", 0)], s=80, color="#8338EC", zorder=3, label="Mean (epoch 1)")
        ax.set_xticks([1])
        ax.set_xlabel("RL epoch")
        ax.text(1, (means[0] if means else 0) + 0.02, "Single-epoch log\n(filter removed all)", ha="center", fontsize=7, color="#555555")
    ax.set_ylabel("Composite score (mean / top)")
    style_axes(ax)
    title = "Fig. B4 | Generative step score history"
    if tool:
        title += f" ({tool})"
    ax.set_title(title, fontsize=10, fontweight="bold", loc="left")
    fig.savefig(OUT / "FigB4_generative_score_history.png", bbox_inches="tight")
    fig.savefig(OUT / "FigB4_generative_score_history.pdf", bbox_inches="tight")
    plt.close(fig)


def fig_docked_ligands_2d(dj: dict[str, Any]) -> tuple[bool, str]:
    """Best-effort 2D structures; requires RDKit. Same ligand order as Fig B3.

    Returns (written, skip_reason). skip_reason is empty when written.
    """
    if not _RDKIT_AVAILABLE:
        return False, "rdkit_not_importable"
    results = sorted_docking_results(dj)
    mols = []
    legends = []
    for r in results:
        smi = r.get("smiles", "")
        mol = Chem.MolFromSmiles(smi)
        if mol is None:
            return False, f"smiles_parse_failed:{smi[:40]}"
        mols.append(mol)
        legends.append(docking_row_label(r))
    fig, axes = plt.subplots(1, len(mols), figsize=(5.4, 2.0), dpi=300)
    if len(mols) == 1:
        axes = [axes]
    for ax, mol, leg in zip(axes, mols, legends):
        ax.imshow(Draw.MolToImage(mol, size=(360, 360)))
        ax.set_title(leg, fontsize=9)
        ax.axis("off")
    fig.suptitle("Fig. B5 | Docked ligands (2D)", fontsize=10, fontweight="bold", x=0.02, ha="left", y=0.98)
    plt.tight_layout(rect=(0, 0, 1, 0.88))
    fig.savefig(OUT / "FigB5_docked_ligands_2d.png", bbox_inches="tight")
    fig.savefig(OUT / "FigB5_docked_ligands_2d.pdf", bbox_inches="tight")
    plt.close(fig)
    return True, ""


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    for p in (POCKETS, DOCK, SCORE):
        if not p.is_file():
            raise SystemExit(f"Missing: {p}")
    dj = json.loads(DOCK.read_text(encoding="utf-8"))
    n_lib, n_pass, n_dock, funnel_data = load_funnel_counts(dj)

    fig_graphical_abstract()
    fig_pockets()
    fig_funnel(n_lib, n_pass, n_dock, funnel_data)
    fig_docking()
    fig_reinvent()
    b5_written, b5_skip = fig_docked_ligands_2d(dj)

    sh = json.loads(SCORE.read_text(encoding="utf-8"))
    meta: dict[str, Any] = {
        "run_dir": str(RUN),
        "figures": {
            "GA_inhibitor": {"kind": "conceptual_schematic", "data_source": "pipeline narrative"},
            "FigB1_pocket_druggability": {"kind": "data_plot", "data_source": str(POCKETS)},
            "FigB2_pipeline_funnel": {
                "kind": "conceptual_schematic_with_data_labels",
                "data_source": str(PHARM_SUMMARY) if funnel_data else str(DOCK),
                "note": "Funnel box widths are visual only; n labels from JSON when available",
            },
            "FigB3_docking_scores": {"kind": "data_plot", "data_source": str(DOCK)},
            "FigB4_generative_score_history": {"kind": "data_plot", "data_source": str(SCORE)},
            "FigB5_docked_ligands_2d": {"kind": "data_plot", "data_source": str(DOCK)},
        },
        "inputs": {
            "pockets": str(POCKETS),
            "pharmacophore_summary": str(PHARM_SUMMARY) if PHARM_SUMMARY.is_file() else None,
            "docking": str(DOCK),
            "score_history": str(SCORE),
        },
        "n_docked": n_dock,
        "funnel": {
            "n_library_screened": n_lib,
            "n_passed_filter": n_pass,
            "n_ligands_docked": n_dock,
            "used_pharmacophore_summary": funnel_data,
        },
        "score_history_tool": sh.get("tool"),
        "rdkit_available": _RDKIT_AVAILABLE,
        "fig_b5_docked_ligands_2d_written": b5_written,
        "fig_b5_skip_reason": b5_skip if not b5_written else None,
    }
    (OUT / "figure_metadata.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"Wrote figures to {OUT}")
    if b5_written:
        print("Fig B5 (2D ligands): written")
    elif not _RDKIT_AVAILABLE:
        print("Fig B5 skipped: RDKit not importable")
    else:
        print(f"Fig B5 skipped: {b5_skip}")


if __name__ == "__main__":
    main()
