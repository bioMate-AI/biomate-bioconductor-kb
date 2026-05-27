#!/usr/bin/env python3
"""Experiment E1 — Profile-blind QC vs profile-aware QC.

Demonstrates that workflows with fixed (default-profile) QC thresholds
falsely reject samples whose biology deviates from the typical case,
while a profile-aware system recovers that data.

Domains: HTS (Z'-factor, signal window) and LNP (Z-avg, PDI, EE).

Thresholds are anchored to backend/config/qc_evidence.yaml:
  HTS:
    - Zhang JH 1999 (Z'-factor): excellent >=0.5; "doable" 0.4-0.5
    - Iversen PW 2006 (signal window): SW>=2 adequate
  LNP:
    - Yamamoto 2019, FDA Liposome 2018, ISO 22412:2017
    - Clinical: Z-avg 60-120 nm, PDI<0.2, EE>=85%
    - Onpattro CMC + LNP-mRNA community range for research/mRNA grades

This script does NOT import or modify backend/lib/galaxy/ai/retrievers/*.
It reimplements profile threshold logic locally with identical anchors,
to comply with the parallel-session safety rule.
"""

from __future__ import annotations

import csv
import json
import random
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

random.seed(20260527)  # reproducibility

OUT = Path(__file__).resolve().parent / "results"
OUT.mkdir(parents=True, exist_ok=True)

# ----------------------------------------------------------------------
# Profile thresholds
# ----------------------------------------------------------------------

HTS_PROFILES = {
    # default = Zhang 1999 "excellent" + Iversen 2006 SW>=2
    "default":            {"z_prime_min": 0.5, "sw_min": 2.0},
    # primary screen — Zhang 1999 "doable" band
    "screening_grade":    {"z_prime_min": 0.4, "sw_min": 1.5},
    # confirmatory / dose-response — stricter than default
    "confirmatory_grade": {"z_prime_min": 0.7, "sw_min": 2.5},
}

LNP_PROFILES = {
    # clinical, Yamamoto 2019 + Onpattro CMC
    "clinical":         {"zavg_lo": 60.0, "zavg_hi": 120.0, "pdi_max": 0.20, "ee_min": 85.0},
    # early-stage research
    "research_grade":   {"zavg_lo": 40.0, "zavg_hi": 150.0, "pdi_max": 0.30, "ee_min": 70.0},
    # mRNA-LNP clinical (tighter)
    "mrna_specialized": {"zavg_lo": 80.0, "zavg_hi": 110.0, "pdi_max": 0.15, "ee_min": 90.0},
}


# ----------------------------------------------------------------------
# Pass/fail logic
# ----------------------------------------------------------------------

def hts_pass(metrics: dict, profile: str) -> bool:
    p = HTS_PROFILES[profile]
    return metrics["z_prime"] >= p["z_prime_min"] and metrics["signal_window"] >= p["sw_min"]


def lnp_pass(metrics: dict, profile: str) -> bool:
    p = LNP_PROFILES[profile]
    return (p["zavg_lo"] <= metrics["z_avg_nm"] <= p["zavg_hi"]
            and metrics["pdi"] < p["pdi_max"]
            and metrics["ee_pct"] >= p["ee_min"])


# ----------------------------------------------------------------------
# Scenario generators
# ----------------------------------------------------------------------

def _u(lo, hi):
    return random.uniform(lo, hi)


def gen_hts_scenarios() -> list[dict]:
    """50 HTS scenarios.

    - 20 default-grade   : Z' in [0.55, 0.85], SW in [2.2, 5.0]
                           (well above Zhang "excellent")
    - 20 marginal        : Z' in [0.40, 0.49], SW in [1.5, 1.99]
                           (Zhang "doable", below default, above screening_grade)
    - 10 truly bad       : Z' in [-0.10, 0.35], SW in [0.6, 1.4]
                           (Zhang "screen will not work" band)
    """
    scens: list[dict] = []
    sid = 0
    for _ in range(20):
        sid += 1
        scens.append({
            "scenario_id": f"HTS-{sid:03d}",
            "domain": "hts",
            "sample_type": "primary_screen_excellent",
            "ground_truth_quality": "default_grade",
            "z_prime": round(_u(0.55, 0.85), 3),
            "signal_window": round(_u(2.2, 5.0), 3),
        })
    for _ in range(20):
        sid += 1
        # biology rationale: live-cell or low-signal target assay
        scens.append({
            "scenario_id": f"HTS-{sid:03d}",
            "domain": "hts",
            "sample_type": "live_cell_low_signal_target",
            "ground_truth_quality": "marginal",
            "z_prime": round(_u(0.40, 0.49), 3),
            "signal_window": round(_u(1.50, 1.99), 3),
        })
    for _ in range(10):
        sid += 1
        scens.append({
            "scenario_id": f"HTS-{sid:03d}",
            "domain": "hts",
            "sample_type": "failed_plate",
            "ground_truth_quality": "truly_bad",
            "z_prime": round(_u(-0.10, 0.35), 3),
            "signal_window": round(_u(0.60, 1.40), 3),
        })
    return scens


def gen_lnp_scenarios() -> list[dict]:
    """50 LNP scenarios.

    - 20 default-grade : clinical, Z-avg 70-115 nm, PDI 0.05-0.18, EE 86-95%
    - 20 marginal      : research/in-vitro mechanism batches:
                         Z-avg in 40-60 or 120-150 nm (research-permissible)
                         PDI in 0.20-0.29
                         EE in 70-84%
                         At least one metric outside clinical band but inside research.
    - 10 truly bad     : Z-avg <40 or >150, PDI >=0.30, EE <70%
    """
    scens: list[dict] = []
    sid = 0
    for _ in range(20):
        sid += 1
        scens.append({
            "scenario_id": f"LNP-{sid:03d}",
            "domain": "lnp",
            "sample_type": "clinical_grade_lnp",
            "ground_truth_quality": "default_grade",
            "z_avg_nm":  round(_u(70.0, 115.0), 2),
            "pdi":       round(_u(0.05, 0.18), 3),
            "ee_pct":    round(_u(86.0, 95.0), 2),
        })
    # Marginal: vary which dimension is biology-driven off-clinical.
    # Mode A: large-particle research batch (Z-avg 120-150, PDI 0.20-0.29, EE 75-84)
    # Mode B: small-particle research batch (Z-avg 40-59, PDI 0.20-0.29, EE 75-84)
    # Mode C: in-vitro mechanism batch (clinical Z-avg, but PDI 0.20-0.29 + EE 70-84)
    marginal_modes = ["A", "B", "C"]
    for i in range(20):
        sid += 1
        mode = marginal_modes[i % 3]
        if mode == "A":
            z, pdi, ee = _u(120.0, 150.0), _u(0.20, 0.29), _u(75.0, 84.0)
            sample = "research_large_particle_batch"
        elif mode == "B":
            z, pdi, ee = _u(40.0, 59.0),  _u(0.20, 0.29), _u(75.0, 84.0)
            sample = "research_small_particle_batch"
        else:
            z, pdi, ee = _u(70.0, 115.0), _u(0.20, 0.29), _u(70.0, 84.0)
            sample = "in_vitro_mechanism_batch"
        scens.append({
            "scenario_id": f"LNP-{sid:03d}",
            "domain": "lnp",
            "sample_type": sample,
            "ground_truth_quality": "marginal",
            "z_avg_nm":  round(z, 2),
            "pdi":       round(pdi, 3),
            "ee_pct":    round(ee, 2),
        })
    for _ in range(10):
        sid += 1
        # Truly bad: aggregated / poorly-encapsulated batch
        scens.append({
            "scenario_id": f"LNP-{sid:03d}",
            "domain": "lnp",
            "sample_type": "aggregated_or_poor_encapsulation",
            "ground_truth_quality": "truly_bad",
            "z_avg_nm":  round(random.choice([_u(20.0, 35.0), _u(160.0, 220.0)]), 2),
            "pdi":       round(_u(0.30, 0.45), 3),
            "ee_pct":    round(_u(40.0, 65.0), 2),
        })
    return scens


# ----------------------------------------------------------------------
# Driver
# ----------------------------------------------------------------------

@dataclass
class ProfileResult:
    profile: str
    domain: str
    by_class: dict = field(default_factory=dict)  # class -> {n, pass, fail}

    def record(self, gt_class: str, passed: bool):
        b = self.by_class.setdefault(gt_class, {"n": 0, "passed": 0, "failed": 0})
        b["n"] += 1
        b["passed" if passed else "failed"] += 1


def write_scenarios_csv(scens: list[dict], path: Path, metric_cols: list[str]):
    cols = ["scenario_id", "domain", "sample_type", "ground_truth_quality"] + metric_cols
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for s in scens:
            w.writerow({k: s.get(k) for k in cols})


def run_domain(domain: str, scens: list[dict], profiles: dict,
               pass_fn: Callable[[dict, str], bool]) -> tuple[list[dict], dict]:
    per_pair: list[dict] = []
    summaries: dict[str, ProfileResult] = {
        p: ProfileResult(profile=p, domain=domain) for p in profiles
    }
    for s in scens:
        for prof in profiles:
            passed = pass_fn(s, prof)
            per_pair.append({
                "scenario_id": s["scenario_id"],
                "domain": domain,
                "sample_type": s["sample_type"],
                "ground_truth_quality": s["ground_truth_quality"],
                "profile": prof,
                "passed": int(passed),
            })
            summaries[prof].record(s["ground_truth_quality"], passed)
    return per_pair, summaries


def main():
    # ---- scenarios
    hts = gen_hts_scenarios()
    lnp = gen_lnp_scenarios()
    write_scenarios_csv(hts, OUT / "e1_hts_scenarios.csv",
                        ["z_prime", "signal_window"])
    write_scenarios_csv(lnp, OUT / "e1_lnp_scenarios.csv",
                        ["z_avg_nm", "pdi", "ee_pct"])

    # ---- run
    hts_pairs, hts_sum = run_domain("hts", hts, HTS_PROFILES, hts_pass)
    lnp_pairs, lnp_sum = run_domain("lnp", lnp, LNP_PROFILES, lnp_pass)

    # ---- per (scenario, profile) raw
    raw_path = OUT / "e1_per_scenario_profile.csv"
    with raw_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=[
            "scenario_id", "domain", "sample_type",
            "ground_truth_quality", "profile", "passed"
        ])
        w.writeheader()
        for row in hts_pairs + lnp_pairs:
            w.writerow(row)

    # ---- false-rejection table
    # false_rejection := rejected when ground_truth_quality is valid for
    # that profile (default_grade or marginal for the *appropriate* profile).
    # For paper Figure 1 we report rejection_rate per (profile, gt_class)
    # — the claim is most cleanly read from this table.
    fr_path = OUT / "e1_false_rejection_per_profile.csv"
    with fr_path.open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["domain", "profile", "ground_truth_quality",
                    "n", "n_passed", "n_failed", "rejection_rate"])
        for summary_map in (hts_sum, lnp_sum):
            for prof, pr in summary_map.items():
                for cls, c in pr.by_class.items():
                    rate = c["failed"] / c["n"] if c["n"] else 0.0
                    w.writerow([pr.domain, prof, cls,
                                c["n"], c["passed"], c["failed"],
                                round(rate, 4)])

    # ---- console report ----
    print("\n=== HTS scenario distribution ===")
    _dump_dist(hts, ["z_prime", "signal_window"])
    print("\n=== LNP scenario distribution ===")
    _dump_dist(lnp, ["z_avg_nm", "pdi", "ee_pct"])
    print(f"\nWrote: {raw_path.name}, e1_hts_scenarios.csv, "
          f"e1_lnp_scenarios.csv, {fr_path.name}")


def _dump_dist(scens, metrics):
    by_cls: dict[str, list[dict]] = {}
    for s in scens:
        by_cls.setdefault(s["ground_truth_quality"], []).append(s)
    for cls, group in by_cls.items():
        line = [f"  {cls:14s} n={len(group):2d}"]
        for m in metrics:
            vals = [g[m] for g in group]
            line.append(f"{m}=[{min(vals):.3f}, {max(vals):.3f}]")
        print("  ".join(line))


if __name__ == "__main__":
    main()
