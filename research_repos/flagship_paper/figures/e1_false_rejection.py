#!/usr/bin/env python3
"""Figure 1 — Profile-blind QC false-rejection rate per profile per sample type.

Reads results/e1_false_rejection_per_profile.csv and produces a grouped
bar chart per domain (HTS, LNP). Output: figures/e1_false_rejection.png
and figures/e1_false_rejection.pdf.
"""
from __future__ import annotations

import csv
from collections import defaultdict
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

ROOT = Path(__file__).resolve().parent.parent
SRC  = ROOT / "results" / "e1_false_rejection_per_profile.csv"
OUT_PNG = Path(__file__).resolve().parent / "e1_false_rejection.png"
OUT_PDF = Path(__file__).resolve().parent / "e1_false_rejection.pdf"

GT_ORDER = ["default_grade", "marginal", "truly_bad"]
GT_LABEL = {
    "default_grade": "Valid\n(default-grade)",
    "marginal":      "Valid\n(marginal/biology-driven)",
    "truly_bad":     "Truly bad\n(should reject)",
}

DOMAIN_PROFILES = {
    "hts": ["default", "screening_grade", "confirmatory_grade"],
    "lnp": ["clinical", "research_grade", "mrna_specialized"],
}
DOMAIN_TITLE = {
    "hts": "HTS plate QC (Z'-factor, signal window)",
    "lnp": "LNP formulation QC (Z-avg, PDI, EE)",
}
PROFILE_COLOR = {
    "default":            "#c0392b",
    "screening_grade":    "#27ae60",
    "confirmatory_grade": "#8e44ad",
    "clinical":           "#c0392b",
    "research_grade":     "#27ae60",
    "mrna_specialized":   "#2980b9",
}


def load() -> dict:
    # data[domain][profile][gt_class] = rejection_rate
    d: dict = defaultdict(lambda: defaultdict(dict))
    with SRC.open() as f:
        for row in csv.DictReader(f):
            d[row["domain"]][row["profile"]][row["ground_truth_quality"]] = \
                float(row["rejection_rate"])
    return d


def main():
    data = load()
    fig, axes = plt.subplots(1, 2, figsize=(13.5, 5.0), constrained_layout=True)

    for ax, domain in zip(axes, ["hts", "lnp"]):
        profiles = DOMAIN_PROFILES[domain]
        x = np.arange(len(GT_ORDER))
        n_p = len(profiles)
        bar_w = 0.78 / n_p
        for i, prof in enumerate(profiles):
            ys = [data[domain][prof].get(c, 0.0) for c in GT_ORDER]
            offset = (i - (n_p - 1) / 2) * bar_w
            bars = ax.bar(x + offset, ys, bar_w,
                          label=prof, color=PROFILE_COLOR[prof],
                          edgecolor="black", linewidth=0.5)
            for b, y in zip(bars, ys):
                ax.text(b.get_x() + b.get_width() / 2, y + 0.015,
                        f"{y*100:.0f}%", ha="center", va="bottom",
                        fontsize=8)
        ax.set_xticks(x)
        ax.set_xticklabels([GT_LABEL[c] for c in GT_ORDER], fontsize=9)
        ax.set_ylim(0, 1.12)
        ax.set_ylabel("Rejection rate")
        ax.set_title(DOMAIN_TITLE[domain], fontsize=11)
        ax.axhline(0.5, color="grey", lw=0.5, ls=":")
        ax.legend(title="Profile", fontsize=8, title_fontsize=9, loc="upper left")
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)

    fig.suptitle(
        "E1 — Profile-blind QC falsely rejects biology-driven valid samples; "
        "profile-aware QC recovers them",
        fontsize=12, y=1.04,
    )
    fig.savefig(OUT_PNG, dpi=180, bbox_inches="tight")
    fig.savefig(OUT_PDF, bbox_inches="tight")
    print(f"Wrote: {OUT_PNG.name}, {OUT_PDF.name}")


if __name__ == "__main__":
    main()
