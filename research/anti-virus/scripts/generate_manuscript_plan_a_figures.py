#!/usr/bin/env python3
"""Generate Plan A (epitope) manuscript figures v1. See docs/MANUSCRIPT_FIGURES_V1_PLAN.md."""
from __future__ import annotations

import csv
import json
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.patches import FancyBboxPatch

# Standard one-letter amino acids (IUPAC protein alphabet subset used in predictions)
AA_ORDER = list("ACDEFGHIKLMNPQRSTVWY")
AA_SET = frozenset(AA_ORDER)

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "research" / "anti-virus" / "runs" / "manuscript_figures_v1" / "plan_a"
TSV = (
    ROOT
    / "research"
    / "anti-virus"
    / "runs"
    / "plan_a_epitope_a44876b7_s3_mirror"
    / "predictions"
    / "PLAN_A_SMOKE_GP.tsv"
)
MULTIQC_DATA = (
    ROOT
    / "research"
    / "anti-virus"
    / "runs"
    / "plan_a_epitope_a44876b7_s3_mirror"
    / "multiqc"
    / "multiqc_data"
)
MULTIQC_BINDING = MULTIQC_DATA / "multiqc_binding_affinity_distribution.txt"
MULTIQC_LENGTH = MULTIQC_DATA / "multiqc_binder_length_distribution.txt"
SAMPLE_ID = "PLAN_A_SMOKE_GP"


def style_axes(ax) -> None:
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def fig_workflow() -> None:
    fig, ax = plt.subplots(figsize=(7.2, 2.4), dpi=300)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 3)
    ax.axis("off")
    boxes = [
        (0.3, 1.2, 1.8, 1.2, "GP segment\n(FASTA / samplesheet)"),
        (2.5, 1.2, 1.8, 1.2, "nf-core\nepitopeprediction"),
        (4.7, 1.2, 1.6, 1.2, "MHCnuggets\n(class I 8–12)"),
        (6.7, 1.2, 1.6, 1.2, "HLA-A*02:01\nHLA-B*07:02"),
        (8.7, 1.2, 1.1, 1.2, "Tables +\nMultiQC"),
    ]
    for x, y, w, h, txt in boxes:
        ax.add_patch(FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.05", facecolor="#E8F4FC", edgecolor="#2E86AB", linewidth=1.2))
        ax.text(x + w / 2, y + h / 2, txt, ha="center", va="center", fontsize=8)
    for i in range(len(boxes) - 1):
        x0, y0, w0, _, _ = boxes[i]
        x1, _, _, _, _ = boxes[i + 1]
        ax.annotate(
            "",
            xy=(x1, y0 + 0.6),
            xytext=(x0 + w0, y0 + 0.6),
            arrowprops=dict(arrowstyle="->", color="#444444", lw=1.2),
        )
    ax.set_title("Fig. A1 | Epitopeprediction workflow (conceptual)", fontsize=10, fontweight="bold", loc="left")
    fig.savefig(OUT / "FigA1_workflow.png", bbox_inches="tight")
    fig.savefig(OUT / "FigA1_workflow.pdf", bbox_inches="tight")
    plt.close(fig)


def count_negative_binders(rows: list[dict[str, str]]) -> int:
    n = 0
    for row in rows:
        b = str(row.get("binder", "")).strip().lower()
        if b in ("false", "0", "no"):
            n += 1
    return n


def fig_graphical_abstract(n_peptide_allele: int, n_negative_binders: int) -> None:
    fig, ax = plt.subplots(figsize=(6.5, 3.0), dpi=300)
    ax.set_xlim(0, 10)
    ax.set_ylim(0, 4)
    ax.axis("off")
    ax.text(
        5,
        3.72,
        "ANDV glycoprotein segment → in silico class I epitope map (conceptual schematic)",
        ha="center",
        fontsize=10,
        fontweight="bold",
    )
    binder_label = (
        f"{n_negative_binders} negative\nbinder calls\n(MHCnuggets)"
        if n_negative_binders == n_peptide_allele
        else f"{n_negative_binders}/{n_peptide_allele} negative\nbinder calls"
    )
    stages = [
        (1, 1.5, "Benchmark\nsegment"),
        (3.5, 1.5, "nf-core\npipeline"),
        (6, 1.5, f"{n_peptide_allele} peptide–\nallele scores"),
        (8.5, 1.5, binder_label),
    ]
    for x, y, t in stages:
        ax.add_patch(FancyBboxPatch((x - 0.55, y - 0.45), 1.1, 1.0, boxstyle="round,pad=0.04", facecolor="#F4F1DE", edgecolor="#BC6C25"))
        ax.text(x, y, t, ha="center", va="center", fontsize=8)
    for i in range(len(stages) - 1):
        ax.annotate("", xy=(stages[i + 1][0] - 0.55, 1.5), xytext=(stages[i][0] + 0.55, 1.5), arrowprops=dict(arrowstyle="->", lw=1.2, color="#283618"))
    ax.text(5, 0.35, "Computational baseline — not clinical immunogenicity", ha="center", fontsize=8, style="italic", color="#555555")
    fig.savefig(OUT / "GA_plan_a.png", bbox_inches="tight")
    fig.savefig(OUT / "GA_plan_a.pdf", bbox_inches="tight")
    plt.close(fig)


def load_tsv() -> list[dict[str, str]]:
    rows = []
    with TSV.open(newline="", encoding="utf-8") as f:
        r = csv.DictReader(f, delimiter="\t")
        for row in r:
            rows.append(row)
    return rows


def fig_ba_by_allele(rows: list[dict[str, str]]) -> None:
    by_allele: dict[str, list[float]] = defaultdict(list)
    for row in rows:
        try:
            ba = float(row["BA"])
        except (KeyError, ValueError):
            continue
        by_allele[row.get("allele", "?")].append(ba)
    fig, ax = plt.subplots(figsize=(3.5, 2.8), dpi=300)
    colors = {"HLA-A*02:01": "#0077B6", "HLA-B*07:02": "#F77F00"}
    for allele, vals in sorted(by_allele.items()):
        ax.hist(vals, bins=40, alpha=0.55, label=allele, color=colors.get(allele, "#6C757D"), density=True)
    ax.set_xlabel("Predicted binding affinity (BA)")
    ax.set_ylabel("Density")
    ax.legend(frameon=False, fontsize=7)
    style_axes(ax)
    ax.set_title("Fig. A2 | BA distribution by allele", fontsize=10, fontweight="bold", loc="left")
    fig.savefig(OUT / "FigA2_BA_by_allele.png", bbox_inches="tight")
    fig.savefig(OUT / "FigA2_BA_by_allele.pdf", bbox_inches="tight")
    plt.close(fig)


def parse_multiqc_binding(path: Path) -> tuple[list[float], list[int]]:
    lines = path.read_text(encoding="utf-8").strip().splitlines()
    if len(lines) < 2:
        raise SystemExit(f"Expected ≥2 lines in {path}")
    h = lines[0].split("\t")
    if h[0].strip() != "Sample":
        raise SystemExit(f"Unexpected header in {path}")
    edges = [float(x) for x in h[1:] if x.strip()]
    for line in lines[1:]:
        parts = line.split("\t")
        if not parts or parts[0].strip() != SAMPLE_ID:
            continue
        counts = [int(float(x)) for x in parts[1 : 1 + len(edges)]]
        if len(counts) != len(edges):
            raise SystemExit(f"Count/edge mismatch in {path}: {len(counts)} vs {len(edges)}")
        return edges, counts
    raise SystemExit(f"No row for {SAMPLE_ID} in {path}")


def parse_multiqc_length(path: Path) -> tuple[list[int], list[float]]:
    lines = path.read_text(encoding="utf-8").strip().splitlines()
    if len(lines) < 2:
        raise SystemExit(f"Expected ≥2 lines in {path}")
    h = lines[0].split("\t")
    if h[0].strip() != "Sample":
        raise SystemExit(f"Unexpected header in {path}")
    lengths = [int(x) for x in h[1:]]
    for line in lines[1:]:
        parts = line.split("\t")
        if not parts or parts[0].strip() != SAMPLE_ID:
            continue
        props = [float(x) for x in parts[1 : 1 + len(lengths)]]
        if len(props) != len(lengths):
            raise SystemExit(f"Proportion/length mismatch in {path}")
        return lengths, props
    raise SystemExit(f"No row for {SAMPLE_ID} in {path}")


def fig_multiqc_summary() -> tuple[int, int]:
    if not MULTIQC_BINDING.is_file():
        raise SystemExit(f"Missing MultiQC file: {MULTIQC_BINDING}")
    if not MULTIQC_LENGTH.is_file():
        raise SystemExit(f"Missing MultiQC file: {MULTIQC_LENGTH}")
    edges, counts = parse_multiqc_binding(MULTIQC_BINDING)
    lengths, props = parse_multiqc_length(MULTIQC_LENGTH)
    last_w = edges[-1] - edges[-2]
    stair_edges = edges + [edges[-1] + last_w]

    fig, (ax0, ax1) = plt.subplots(1, 2, figsize=(6.8, 2.8), dpi=300)
    ax0.stairs(counts, stair_edges, fill=True, color="#457B9D", alpha=0.75, edgecolor="#1D3557", linewidth=0.6)
    ax0.set_xlabel("Binding affinity (bin lower edge)")
    ax0.set_ylabel("Count")
    style_axes(ax0)
    ax0.text(0.02, 0.98, "a", transform=ax0.transAxes, fontsize=11, fontweight="bold", va="top")

    x = range(len(lengths))
    ax1.bar(x, props, color="#E76F51", alpha=0.85, edgecolor="#8D3B2F", linewidth=0.5)
    ax1.set_xticks(list(x))
    ax1.set_xticklabels([str(L) for L in lengths])
    ax1.set_xlabel("Peptide length (aa)")
    ax1.set_ylabel("Proportion")
    ax1.set_ylim(0, max(props) * 1.15 if props else 1.0)
    style_axes(ax1)
    ax1.text(0.02, 0.98, "b", transform=ax1.transAxes, fontsize=11, fontweight="bold", va="top")

    fig.suptitle("Fig. A4 | MultiQC binding affinity and length summary", fontsize=10, fontweight="bold", x=0.02, ha="left", y=1.02)
    fig.tight_layout()
    fig.savefig(OUT / "FigA4_multiqc_summary.png", bbox_inches="tight")
    fig.savefig(OUT / "FigA4_multiqc_summary.pdf", bbox_inches="tight")
    plt.close(fig)
    return sum(counts), len(lengths)


def fig_by_length(rows: list[dict[str, str]]) -> None:
    by_len_ba: dict[int, list[float]] = defaultdict(list)
    by_len_rank: dict[int, list[float]] = defaultdict(list)
    for row in rows:
        seq = row.get("sequence", "")
        L = len(seq)
        if L < 8 or L > 12:
            continue
        try:
            ba = float(row["BA"])
            rank = float(row["rank"])
        except (KeyError, ValueError):
            continue
        by_len_ba[L].append(ba)
        by_len_rank[L].append(rank)
    lengths = sorted(set(by_len_ba) | set(by_len_rank))
    if not lengths:
        raise SystemExit("No rows with valid BA/rank and peptide length 8–12; check TSV columns.")
    fig, (ax0, ax1) = plt.subplots(1, 2, figsize=(6.8, 2.8), dpi=300, sharex=True)
    pos = range(len(lengths))
    parts0 = ax0.violinplot(
        [by_len_ba[L] for L in lengths], positions=pos, showmeans=True, showmedians=False
    )
    for b in parts0["bodies"]:
        b.set_facecolor("#457B9D")
        b.set_alpha(0.65)
    ax0.set_xticks(list(pos))
    ax0.set_xticklabels([str(L) for L in lengths])
    ax0.set_xlabel("Peptide length (aa)")
    ax0.set_ylabel("BA (MHCnuggets)")
    style_axes(ax0)
    ax0.text(0.02, 0.98, "a", transform=ax0.transAxes, fontsize=11, fontweight="bold", va="top")

    parts1 = ax1.violinplot(
        [by_len_rank[L] for L in lengths], positions=pos, showmeans=True, showmedians=False
    )
    for b in parts1["bodies"]:
        b.set_facecolor("#E76F51")
        b.set_alpha(0.65)
    ax1.set_xticks(list(pos))
    ax1.set_xticklabels([str(L) for L in lengths])
    ax1.set_xlabel("Peptide length (aa)")
    ax1.set_ylabel("Rank score")
    style_axes(ax1)
    ax1.text(0.02, 0.98, "b", transform=ax1.transAxes, fontsize=11, fontweight="bold", va="top")

    fig.suptitle("Fig. A3 | BA and rank by peptide length", fontsize=10, fontweight="bold", x=0.02, ha="left", y=1.02)
    fig.tight_layout()
    fig.savefig(OUT / "FigA3_metrics_by_peptide_length.png", bbox_inches="tight")
    fig.savefig(OUT / "FigA3_metrics_by_peptide_length.pdf", bbox_inches="tight")
    plt.close(fig)


def fig_sequence_profile(rows: list[dict[str, str]]) -> int:
    """Stacked per-position amino-acid frequencies (N→C), lengths 8–12; all peptide–allele rows."""
    max_pos = 12
    counts = np.zeros((max_pos, len(AA_ORDER)), dtype=float)
    n_used = 0
    for row in rows:
        seq = (row.get("sequence") or "").strip().upper()
        if not (8 <= len(seq) <= 12):
            continue
        if not all(c in AA_SET for c in seq):
            continue
        n_used += 1
        for i, c in enumerate(seq):
            if i >= max_pos:
                break
            counts[i, AA_ORDER.index(c)] += 1.0
    if n_used == 0:
        raise SystemExit("Fig A5: no rows with sequence length 8–12 and standard 20 AA letters.")
    row_totals = counts.sum(axis=1)
    with np.errstate(divide="ignore", invalid="ignore"):
        freq = np.where(row_totals[:, np.newaxis] > 0, counts / row_totals[:, np.newaxis], 0.0)

    fig, ax = plt.subplots(figsize=(7.2, 3.2), dpi=300)
    x = np.arange(1, max_pos + 1)
    cmap = plt.get_cmap("tab20")
    colors = [cmap(i % 20) for i in range(len(AA_ORDER))]
    bottom = np.zeros(max_pos)
    for j, aa in enumerate(AA_ORDER):
        h = freq[:, j]
        ax.bar(x, h, width=0.82, bottom=bottom, color=colors[j], edgecolor="white", linewidth=0.35, label=aa)
        bottom += h
    ax.set_xlim(0.35, max_pos + 0.65)
    ax.set_ylim(0, 1.0)
    ax.set_xlabel("Position (N→C in predicted peptide)")
    ax.set_ylabel("Frequency")
    ax.set_xticks(x)
    ax.legend(ncol=10, fontsize=6, frameon=False, loc="upper center", bbox_to_anchor=(0.5, -0.18), columnspacing=0.6)
    style_axes(ax)
    ax.set_title(
        "Fig. A5 | Amino-acid frequency by position (length 8–12 aa; all peptide–allele rows)",
        fontsize=10,
        fontweight="bold",
        loc="left",
    )
    fig.subplots_adjust(bottom=0.28)
    fig.savefig(OUT / "FigA5_sequence_profile.png", bbox_inches="tight")
    fig.savefig(OUT / "FigA5_sequence_profile.pdf", bbox_inches="tight")
    plt.close(fig)
    return max_pos


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    meta: dict = {
        "tsv": str(TSV),
        "n_rows": 0,
        "multiqc_binding_affinity_distribution": str(MULTIQC_BINDING),
        "multiqc_binder_length_distribution": str(MULTIQC_LENGTH),
    }
    if not TSV.is_file():
        raise SystemExit(f"Missing TSV: {TSV}")
    rows = load_tsv()
    meta["n_rows"] = len(rows)
    n_neg = count_negative_binders(rows)
    meta["n_negative_binders"] = n_neg
    meta["figures"] = {
        "GA_plan_a": {"kind": "conceptual_schematic", "data_source": "TSV row count + binder column"},
        "FigA1_workflow": {"kind": "conceptual_schematic", "data_source": "pipeline narrative"},
        "FigA2_BA_by_allele": {"kind": "data_plot", "data_source": str(TSV)},
        "FigA3_metrics_by_peptide_length": {"kind": "data_plot", "data_source": str(TSV)},
        "FigA4_multiqc_summary": {"kind": "data_plot", "data_source": [str(MULTIQC_BINDING), str(MULTIQC_LENGTH)]},
        "FigA5_sequence_profile": {"kind": "data_plot", "data_source": str(TSV)},
    }
    fig_graphical_abstract(len(rows), n_neg)
    fig_workflow()
    fig_ba_by_allele(rows)
    fig_by_length(rows)
    n_bind_counts, n_len_cols = fig_multiqc_summary()
    meta["multiqc_binding_affinity_total_counts"] = n_bind_counts
    meta["multiqc_binder_length_n_columns"] = n_len_cols
    meta["fig_a5_positions"] = fig_sequence_profile(rows)
    (OUT / "figure_metadata.json").write_text(json.dumps(meta, indent=2), encoding="utf-8")
    print(f"Wrote figures to {OUT}")


if __name__ == "__main__":
    main()
