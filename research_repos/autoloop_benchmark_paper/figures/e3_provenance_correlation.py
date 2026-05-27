"""E3: Correlation between QC gate provenance grade and auto-loop convergence.

Joins evaluation/results/autoloop/autoloop_results.csv to a gate→provenance
mapping derived from backend/config/qc_evidence.yaml, then:
  - per-scenario 2x3 contingency table (converged x {GOLD, SILVER, BRONZE})
  - Fisher's exact / chi-squared test
  - bootstrap 95% CI on GOLD-vs-BRONZE convergence difference
  - per-domain stacked-bar + scatter Figure 3

Writes:
  results/e3_provenance_correlation.csv
  figures/e3_provenance_correlation.png
"""
from __future__ import annotations

import csv
from pathlib import Path
from collections import Counter, defaultdict

import numpy as np
import matplotlib.pyplot as plt
from scipy import stats

ROOT = Path(__file__).resolve().parents[3]
RESULTS_CSV = ROOT / "evaluation/results/autoloop/autoloop_results.csv"
OUT_DIR = Path(__file__).resolve().parents[1]
RES_DIR = OUT_DIR / "results"
FIG_DIR = OUT_DIR / "figures"
RES_DIR.mkdir(exist_ok=True, parents=True)
FIG_DIR.mkdir(exist_ok=True, parents=True)

# --- Gate → provenance mapping (derived from backend/config/qc_evidence.yaml) ---
# `none`        : no failing gate triggered (baseline pass) — excluded from
#                 provenance analysis (no remediation to attribute).
# `persistent`  : escalated after multiple failed remediations — attributed to
#                 the dominant gate of that domain (best-effort).
# `multi`       : two simultaneous gate failures (ADMET) — attributed to the
#                 lowest-provenance triggering gate (conservative).
GATE_PROV = {
    ("ADMET", "hERG"): "GOLD",            # admet_herg_ic50
    ("ADMET", "Ames"): "GOLD",            # admet_ames
    ("ADMET", "DILI"): "SILVER",          # admet_dili_probability
    ("ADMET", "multi"): "SILVER",         # mixed hERG+DILI/Ro5 — take min
    ("ADMET", "persistent"): "GOLD",      # dominant ADMET gates are GOLD
    ("CYP_DDI", "R1_clinical"): "GOLD",   # cyp_ddi_r1_basic
    ("CYP_DDI", "R1_investigate"): "GOLD",
    ("CYP_DDI", "persistent"): "GOLD",
    ("Docking", "weak_score"): "BRONZE",  # docking_binding_score
    ("Docking", "no_poses"): "BRONZE",    # docking_valid_poses
    ("Docking", "persistent"): "BRONZE",
    ("NCA_PK", "high_extrap"): "GOLD",    # nca_auc_extrap
    ("NCA_PK", "poor_slope"): "SILVER",   # nca_terminal_slope_coverage
    ("NCA_PK", "persistent"): "GOLD",     # AUC-extrap is dominant
}

PROV_SCORE = {"GOLD": 3, "SILVER": 2, "BRONZE": 1}
COLORS = {"GOLD": "#d4a017", "SILVER": "#a8a8a8", "BRONZE": "#8c5a2b"}


def load_rows():
    with RESULTS_CSV.open() as f:
        return list(csv.DictReader(f))


def main():
    rows = load_rows()

    # Per-scenario: keep only rows with a non-`none` gate (remediation actually triggered)
    triggered = [r for r in rows if r["gate_type"] != "none"]

    # 2x3 contingency: converged x {GOLD, SILVER, BRONZE}
    per_grade = defaultdict(lambda: {"converged": 0, "escalated": 0, "iters": []})
    per_scenario_records = []

    for r in triggered:
        key = (r["domain"], r["gate_type"])
        prov = GATE_PROV.get(key)
        if prov is None:
            continue
        converged = r["escalated"] == "False"
        per_grade[prov]["converged" if converged else "escalated"] += 1
        per_grade[prov]["iters"].append(int(r["iterations"]))
        per_scenario_records.append({
            "task_id": r["task_id"],
            "domain": r["domain"],
            "gate_type": r["gate_type"],
            "provenance": prov,
            "converged": int(converged),
            "iterations": int(r["iterations"]),
            "escalated": r["escalated"],
        })

    # Write per-scenario CSV
    out_csv = RES_DIR / "e3_provenance_correlation.csv"
    with out_csv.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=list(per_scenario_records[0].keys()))
        w.writeheader()
        w.writerows(per_scenario_records)

    # --- Contingency table & stats ---
    grades = ["GOLD", "SILVER", "BRONZE"]
    conv = [per_grade[g]["converged"] for g in grades]
    esc = [per_grade[g]["escalated"] for g in grades]
    table = np.array([conv, esc])
    n_by_grade = [c + e for c, e in zip(conv, esc)]
    rate_by_grade = [c / (c + e) if (c + e) else 0 for c, e in zip(conv, esc)]

    print("\n=== 2x3 Contingency (converged x grade) ===")
    print(f"             {'GOLD':>8} {'SILVER':>8} {'BRONZE':>8}")
    print(f"converged   {conv[0]:>8d} {conv[1]:>8d} {conv[2]:>8d}")
    print(f"escalated   {esc[0]:>8d} {esc[1]:>8d} {esc[2]:>8d}")
    print(f"rate        {rate_by_grade[0]:>8.3f} {rate_by_grade[1]:>8.3f} {rate_by_grade[2]:>8.3f}")
    print(f"N           {n_by_grade[0]:>8d} {n_by_grade[1]:>8d} {n_by_grade[2]:>8d}")

    chi2, p_chi2, dof, expected = stats.chi2_contingency(table)
    print(f"\nChi-squared: chi2={chi2:.3f}, dof={dof}, p={p_chi2:.4f}")
    if (expected < 5).any():
        print(f"  (expected cell <5 present — Fisher's exact preferred)")

    # Fisher's exact on GOLD vs BRONZE (2x2)
    sub = np.array([[conv[0], conv[2]], [esc[0], esc[2]]])
    odds, p_fisher = stats.fisher_exact(sub, alternative="two-sided")
    print(f"Fisher GOLD vs BRONZE: odds={odds:.3f}, p={p_fisher:.4f}")

    # Bootstrap 95% CI on (rate_GOLD - rate_BRONZE)
    gold_outcomes = [1] * conv[0] + [0] * esc[0]
    bronze_outcomes = [1] * conv[2] + [0] * esc[2]
    rng = np.random.default_rng(42)
    diffs = []
    for _ in range(1000):
        g = rng.choice(gold_outcomes, size=len(gold_outcomes), replace=True)
        b = rng.choice(bronze_outcomes, size=len(bronze_outcomes), replace=True)
        diffs.append(g.mean() - b.mean())
    ci_lo, ci_hi = np.percentile(diffs, [2.5, 97.5])
    obs_diff = rate_by_grade[0] - rate_by_grade[2]
    print(f"Observed rate diff (GOLD - BRONZE) = {obs_diff:.3f}")
    print(f"Bootstrap 95% CI: [{ci_lo:.3f}, {ci_hi:.3f}]")

    # Per-domain weighted provenance score vs convergence (from provided CSVs)
    per_domain = []
    with (RES_DIR / "e2_convergence_per_domain.csv").open() as f:
        conv_map = {r["domain"]: r for r in csv.DictReader(f)}
    with (RES_DIR / "e2_provenance_per_domain.csv").open() as f:
        for r in csv.DictReader(f):
            d = r["domain"]
            g, s, b = int(r["gold"]), int(r["silver"]), int(r["bronze"])
            tot = g + s + b
            weighted = (3 * g + 2 * s + 1 * b) / tot if tot else 0
            per_domain.append({
                "domain": d,
                "gold": g, "silver": s, "bronze": b,
                "weighted_prov": weighted,
                "convergence_pct": float(conv_map[d]["autoloop_gate_pass_within_3_pct"]),
                "escalation_pct": float(conv_map[d]["escalation_rate_pct"]),
            })
    # Pearson on 4 points (descriptive)
    xs = np.array([d["weighted_prov"] for d in per_domain])
    ys = np.array([d["convergence_pct"] for d in per_domain])
    r_pearson, p_pearson = stats.pearsonr(xs, ys)
    print(f"\nPer-domain (N=4): Pearson r={r_pearson:.3f}, p={p_pearson:.4f}  (descriptive only)")

    # === Figure 3 ===
    fig, (axA, axB) = plt.subplots(1, 2, figsize=(12, 5))

    # Panel A — stacked bars
    domains = [d["domain"] for d in per_domain]
    gold_pcts = [d["gold"] / (d["gold"]+d["silver"]+d["bronze"]) * 100 for d in per_domain]
    silver_pcts = [d["silver"] / (d["gold"]+d["silver"]+d["bronze"]) * 100 for d in per_domain]
    bronze_pcts = [d["bronze"] / (d["gold"]+d["silver"]+d["bronze"]) * 100 for d in per_domain]
    axA.bar(domains, gold_pcts, color=COLORS["GOLD"], label="GOLD")
    axA.bar(domains, silver_pcts, bottom=gold_pcts, color=COLORS["SILVER"], label="SILVER")
    axA.bar(domains, bronze_pcts,
            bottom=[g + s for g, s in zip(gold_pcts, silver_pcts)],
            color=COLORS["BRONZE"], label="BRONZE")
    axA.set_ylabel("Gate provenance composition (%)")
    axA.set_title("A. Per-domain gate provenance composition")
    axA.legend(loc="lower right", fontsize=9)
    axA.set_ylim(0, 100)

    # Panel B — weighted provenance vs convergence
    for d in per_domain:
        axB.scatter(d["weighted_prov"], d["convergence_pct"], s=140,
                    color="#1f77b4", edgecolor="black", zorder=3)
        axB.annotate(d["domain"], (d["weighted_prov"], d["convergence_pct"]),
                     textcoords="offset points", xytext=(8, 4), fontsize=10)
    # Regression line (descriptive)
    slope, intercept = np.polyfit(xs, ys, 1)
    xline = np.linspace(xs.min() - 0.2, xs.max() + 0.2, 50)
    axB.plot(xline, slope * xline + intercept, "--", color="gray", alpha=0.6,
             label=f"linear fit (r={r_pearson:.2f})")
    axB.set_xlabel("Weighted provenance score (GOLD=3, SILVER=2, BRONZE=1)")
    axB.set_ylabel("Auto-loop convergence within 3 retries (%)")
    axB.set_title("B. Provenance composition vs convergence")
    axB.set_ylim(80, 102)
    axB.legend(loc="lower right", fontsize=9)
    axB.grid(alpha=0.3)

    plt.suptitle(
        f"Figure 3. Gate provenance vs auto-loop convergence "
        f"(per-scenario Fisher p={p_fisher:.3f}, GOLD-BRONZE 95%CI [{ci_lo:.2f}, {ci_hi:.2f}])",
        fontsize=11,
    )
    plt.tight_layout()
    out_fig = FIG_DIR / "e3_provenance_correlation.png"
    plt.savefig(out_fig, dpi=160, bbox_inches="tight")
    print(f"\nWrote {out_fig}")
    print(f"Wrote {out_csv}")

    # Surface concentration of Docking escalations
    docking_esc = [r for r in per_scenario_records
                   if r["domain"] == "Docking" and not r["converged"]]
    types = Counter(r["gate_type"] for r in docking_esc)
    print(f"\nDocking non-converged scenarios by gate_type: {dict(types)}")


if __name__ == "__main__":
    main()
