"""
DMTA Simulation Harness — BioMate vs. Baselines

Simulates a 3-round Design-Make-Test-Analyse active learning loop using:
  - BioMate BayesianOptimizer as the proposal engine
  - A held-out ChEMBL activity dataset as the oracle (ground truth)
  - Three baselines: random screening, Tanimoto similarity, single-pass BO

Usage
-----
# Download ChEMBL data first (requires chembl_webresource_client):
python scripts/download_chembl.py --target CHEMBL203 --output data/egfr_chembl.csv

# Run simulation:
python scripts/run_dmta_simulation.py \\
    --activity-file data/egfr_chembl.csv \\
    --n-rounds 3 \\
    --n-propose 10 \\
    --n-seeds 10 \\
    --active-threshold 7.0 \\
    --output results/egfr_dmta/

# Run on multiple targets (will create one subdirectory per target):
python scripts/run_dmta_simulation.py \\
    --activity-file data/egfr_chembl.csv data/jak2_chembl.csv data/bace1_chembl.csv \\
    --output results/multi_target/

Outputs (per target, per seed)
-------------------------------
results/{target}/{seed:02d}/
    round_{n}_proposals.csv       — SMILES proposed + oracle score
    round_{n}_metrics.json        — EF, HR, cumulative recovery
    summary.json                  — all-round summary + bootstrap CIs
results/{target}/
    aggregate_metrics.json        — mean ± SD across seeds
    convergence_curves.csv        — for Figure 3

References
----------
  Truchon & Bayly, J. Chem. Inf. Model. 2007 — Enrichment Factor definition
  Renz et al., ACS Cent. Sci. 2019 — DRD2 active learning benchmark design
  Pyzer-Knapp et al., Annu. Rev. Mater. Res. 2022 — active learning in chemistry
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import math
import os
import random
import sqlite3
import sys
import tempfile
import time
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Optional

import numpy as np

# Allow running from repo root
sys.path.insert(0, str(Path(__file__).parent.parent / "backend"))

log = logging.getLogger(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class ActivityRecord:
    smiles: str
    compound_id: str
    pic50: float          # -log10(IC50_M), higher = more potent


@dataclass
class RoundMetrics:
    round_number: int
    method: str           # biomate | random | similarity | single_pass
    proposed_smiles: list[str]
    oracle_pic50: list[float]   # ground-truth pIC50 for each proposed compound
    n_actives: int        # number meeting active_threshold in this round's proposals
    hit_rate: float       # n_actives / n_proposed
    cumulative_actives: int     # total actives found up to this round
    cumulative_recovery: float  # cumulative_actives / total_actives_in_library


@dataclass
class SeedResult:
    seed: int
    target: str
    total_actives: int     # actives in full virtual library
    rounds: list[RoundMetrics] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Oracle: wraps a held-out ChEMBL pIC50 lookup
# ---------------------------------------------------------------------------

class ChEMBLOracle:
    """
    Looks up ground-truth pIC50 from a pre-loaded activity dict.
    Compounds not in the oracle return None (simulate "untestable").
    """

    def __init__(self, activity_dict: dict[str, float], active_threshold: float = 7.0):
        self._activity = activity_dict           # smiles -> pIC50
        self.active_threshold = active_threshold

    def query(self, smiles_list: list[str]) -> dict[str, Optional[float]]:
        return {s: self._activity.get(s) for s in smiles_list}

    def is_active(self, smiles: str) -> bool:
        v = self._activity.get(smiles)
        return v is not None and v >= self.active_threshold

    def total_actives(self, library: list[str]) -> int:
        return sum(1 for s in library if self.is_active(s))


# ---------------------------------------------------------------------------
# ChEMBL CSV loader
# ---------------------------------------------------------------------------

def load_activity_csv(path: str, active_threshold: float = 7.0) -> tuple[list[ActivityRecord], ChEMBLOracle]:
    """
    Load a ChEMBL activity CSV with columns: smiles, compound_id, pic50
    (or: smiles, compound_id, ic50_nm — will convert automatically).

    Returns: (all_records, oracle)
    """
    records = []
    seen_smiles = set()

    with open(path) as f:
        reader = csv.DictReader(f)
        for row in reader:
            smiles = row.get("smiles", row.get("canonical_smiles", "")).strip()
            if not smiles or smiles in seen_smiles:
                continue
            seen_smiles.add(smiles)

            cid = row.get("compound_id", row.get("chembl_id", f"cpd_{len(records)}"))

            # Support both pic50 column and ic50_nm column
            if "pic50" in row and row["pic50"]:
                try:
                    pic50 = float(row["pic50"])
                except ValueError:
                    continue
            elif "ic50_nm" in row and row["ic50_nm"]:
                try:
                    ic50_nm = float(row["ic50_nm"])
                    pic50 = 9.0 - math.log10(ic50_nm)   # pIC50 = -log10(IC50_M) = 9 - log10(IC50_nM)
                except ValueError:
                    continue
            else:
                continue

            records.append(ActivityRecord(smiles=smiles, compound_id=cid, pic50=pic50))

    if not records:
        raise ValueError(f"No valid records found in {path}")

    activity_dict = {r.smiles: r.pic50 for r in records}
    oracle = ChEMBLOracle(activity_dict, active_threshold)
    log.info("Loaded %d compounds from %s (actives: %d @ pIC50 ≥ %.1f)",
             len(records), path, oracle.total_actives([r.smiles for r in records]), active_threshold)
    return records, oracle


# ---------------------------------------------------------------------------
# Fingerprint utilities (RDKit fallback to random if unavailable)
# ---------------------------------------------------------------------------

def _compute_fp(smiles: str, n_bits: int = 2048) -> Optional[np.ndarray]:
    try:
        from rdkit import Chem
        from rdkit.Chem import AllChem
        mol = Chem.MolFromSmiles(smiles)
        if mol is None:
            return None
        bv = AllChem.GetMorganFingerprintAsBitVect(mol, radius=2, nBits=n_bits)
        return np.array(bv)
    except ImportError:
        rng = np.random.default_rng(abs(hash(smiles)) % (2**31))
        fp = np.zeros(n_bits, dtype=int)
        fp[rng.choice(n_bits, size=40, replace=False)] = 1
        return fp


def tanimoto(a: np.ndarray, b: np.ndarray) -> float:
    dot = float(a @ b)
    denom = float(a @ a) + float(b @ b) - dot
    return dot / denom if denom > 0 else 0.0


def max_tanimoto_to_set(query_fp: np.ndarray, train_fps: list[np.ndarray]) -> float:
    if not train_fps:
        return 0.0
    return max(tanimoto(query_fp, t) for t in train_fps)


# ---------------------------------------------------------------------------
# Baseline: random screening
# ---------------------------------------------------------------------------

def propose_random(
    library: list[str],
    already_tested: set[str],
    n_propose: int,
    rng: random.Random,
) -> list[str]:
    candidates = [s for s in library if s not in already_tested]
    return rng.sample(candidates, min(n_propose, len(candidates)))


# ---------------------------------------------------------------------------
# Baseline: Tanimoto similarity screening
# ---------------------------------------------------------------------------

def propose_similarity(
    library: list[str],
    seed_fps: list[np.ndarray],
    already_tested: set[str],
    n_propose: int,
) -> list[str]:
    candidates = [(s, _compute_fp(s)) for s in library if s not in already_tested]
    candidates = [(s, fp) for s, fp in candidates if fp is not None]
    scored = [(s, max_tanimoto_to_set(fp, seed_fps)) for s, fp in candidates]
    scored.sort(key=lambda x: -x[1])
    return [s for s, _ in scored[:n_propose]]


# ---------------------------------------------------------------------------
# BioMate Bayesian Optimizer wrapper
# ---------------------------------------------------------------------------

def propose_biomate(
    library: list[str],
    trained_smiles: list[str],
    trained_scores: list[float],
    already_tested: set[str],
    n_propose: int,
    campaign_id: str,
    db_path: str,
    diversity_weight: float = 0.2,
) -> list[str]:
    """
    Fit BayesianOptimizer on current training data, propose from library.
    Returns SMILES list (n_propose entries or fewer if library is exhausted).
    """
    from lib.galaxy.ai.drug_discovery.bayesian_optimizer import (
        BayesianOptimizer, CampaignDataset,
    )

    if len(trained_smiles) < 2:
        # Insufficient data — fall back to random
        log.warning("propose_biomate: insufficient training data (%d), using random", len(trained_smiles))
        rng = random.Random(42)
        candidates = [s for s in library if s not in already_tested]
        return rng.sample(candidates, min(n_propose, len(candidates)))

    opt = BayesianOptimizer(
        campaign_id=campaign_id,
        db_path=db_path,
        n_initial=max(2, len(trained_smiles)),
    )

    fps = opt._featurise(trained_smiles)
    dataset = CampaignDataset(
        compound_ids=[f"cpd_{i}" for i in range(len(trained_smiles))],
        smiles_list=trained_smiles,
        features=fps,
        objectives={"pic50": np.array(trained_scores, dtype=float)},
        objective_directions={"pic50": "maximize"},
    )
    opt.fit(dataset)

    # Exclude already-tested compounds from proposals
    vl = [s for s in library if s not in already_tested]
    if not vl:
        return []

    proposal = opt.propose_next_round(
        virtual_library_smiles=vl,
        n_propose=min(n_propose, len(vl)),
        diversity_weight=diversity_weight,
    )
    return proposal.proposed_compounds


# ---------------------------------------------------------------------------
# Enrichment metrics
# ---------------------------------------------------------------------------

def compute_enrichment_factor(
    oracle: ChEMBLOracle,
    library: list[str],
    proposed: list[str],
    fraction: float = 0.05,
) -> float:
    """
    EF_f = (hit_rate_proposed) / (hit_rate_random)
    where fraction = 0.05 means top-5% of proposed vs. expected if random.

    Truchon & Bayly, J. Chem. Inf. Model. 2007.
    """
    total_actives = oracle.total_actives(library)
    if total_actives == 0 or len(library) == 0:
        return 0.0
    n_proposed = len(proposed)
    n_active_proposed = sum(1 for s in proposed if oracle.is_active(s))
    hit_rate_proposed = n_active_proposed / n_proposed if n_proposed > 0 else 0.0
    hit_rate_random = total_actives / len(library)
    return hit_rate_proposed / hit_rate_random if hit_rate_random > 0 else 0.0


# ---------------------------------------------------------------------------
# Core simulation loop
# ---------------------------------------------------------------------------

def run_one_seed(
    all_records: list[ActivityRecord],
    oracle: ChEMBLOracle,
    seed: int,
    target_name: str,
    n_rounds: int = 3,
    n_propose: int = 10,
    seed_fraction: float = 0.05,
    diversity_weight: float = 0.2,
    output_dir: Optional[Path] = None,
) -> SeedResult:
    rng = random.Random(seed)
    np_rng = np.random.default_rng(seed)

    library = [r.smiles for r in all_records]
    total_actives = oracle.total_actives(library)

    # Seed split: seed_fraction of all compounds → initial training set
    n_seed = max(2, int(len(all_records) * seed_fraction))
    seed_idx = np_rng.choice(len(all_records), size=n_seed, replace=False)
    seed_records = [all_records[i] for i in seed_idx]

    # Training data (grows each round)
    trained_smiles = [r.smiles for r in seed_records]
    trained_scores = [r.pic50 for r in seed_records]
    already_tested = set(trained_smiles)

    # Pre-compute seed fingerprints for similarity baseline
    seed_fps = [_compute_fp(s) for s in trained_smiles]
    seed_fps = [fp for fp in seed_fps if fp is not None]

    # BioMate needs an isolated DB per seed
    tmp_db = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    tmp_db.close()
    campaign_id = f"{target_name}_seed{seed:02d}"

    result = SeedResult(seed=seed, target=target_name, total_actives=total_actives)
    cumulative: dict[str, int] = {"biomate": 0, "random": 0, "similarity": 0, "single_pass": 0}

    # Single-pass BO: fit once on seed, never update
    single_pass_trained_smiles = list(trained_smiles)
    single_pass_trained_scores = list(trained_scores)

    log.info("Seed %d: library=%d, seed=%d, actives=%d", seed, len(library), n_seed, total_actives)

    for round_num in range(1, n_rounds + 1):
        round_data = {}

        # --- BioMate ---
        bm_proposals = propose_biomate(
            library, trained_smiles, trained_scores,
            already_tested, n_propose, campaign_id, tmp_db.name, diversity_weight,
        )
        round_data["biomate"] = bm_proposals

        # --- Random ---
        rand_proposals = propose_random(library, already_tested, n_propose, rng)
        round_data["random"] = rand_proposals

        # --- Similarity ---
        sim_proposals = propose_similarity(library, seed_fps, already_tested, n_propose)
        round_data["similarity"] = sim_proposals

        # --- Single-pass BO (no auto-retrain) ---
        sp_proposals = propose_biomate(
            library, single_pass_trained_smiles, single_pass_trained_scores,
            already_tested, n_propose, f"{campaign_id}_sp", tmp_db.name, diversity_weight,
        )
        round_data["single_pass"] = sp_proposals

        # Oracle feedback (only for BioMate — update training set)
        oracle_results = oracle.query(bm_proposals)
        for smiles, pic50 in oracle_results.items():
            if pic50 is not None:
                trained_smiles.append(smiles)
                trained_scores.append(pic50)
            already_tested.add(smiles)
            # Also update seed_fps for similarity baseline
            fp = _compute_fp(smiles)
            if fp is not None:
                seed_fps.append(fp)

        # Metrics per method per round
        for method, proposals in round_data.items():
            oracle_vals = [oracle._activity.get(s) for s in proposals]
            n_actives = sum(1 for s in proposals if oracle.is_active(s))
            cumulative[method] += n_actives
            hit_rate = n_actives / len(proposals) if proposals else 0.0
            cum_recovery = cumulative[method] / total_actives if total_actives > 0 else 0.0
            ef5 = compute_enrichment_factor(oracle, library, proposals, fraction=0.05)

            metrics = RoundMetrics(
                round_number=round_num,
                method=method,
                proposed_smiles=proposals,
                oracle_pic50=[v if v is not None else float("nan") for v in oracle_vals],
                n_actives=n_actives,
                hit_rate=hit_rate,
                cumulative_actives=cumulative[method],
                cumulative_recovery=cum_recovery,
            )
            result.rounds.append(metrics)

            # Save round CSV
            if output_dir:
                round_dir = output_dir / f"{seed:02d}"
                round_dir.mkdir(parents=True, exist_ok=True)
                csv_path = round_dir / f"round_{round_num}_{method}.csv"
                with open(csv_path, "w", newline="") as f:
                    w = csv.writer(f)
                    w.writerow(["smiles", "oracle_pic50", "is_active"])
                    for s, v in zip(proposals, oracle_vals):
                        w.writerow([s, v if v is not None else "", oracle.is_active(s)])

        log.info(
            "  Round %d — BioMate HR=%.2f%% (EF5=%.2f) | Random HR=%.2f%% | Sim HR=%.2f%%",
            round_num,
            round_data_hit_rate(round_data["biomate"], oracle) * 100,
            ef5,
            round_data_hit_rate(round_data["random"], oracle) * 100,
            round_data_hit_rate(round_data["similarity"], oracle) * 100,
        )

    os.unlink(tmp_db.name)
    return result


def round_data_hit_rate(proposals: list[str], oracle: ChEMBLOracle) -> float:
    if not proposals:
        return 0.0
    return sum(1 for s in proposals if oracle.is_active(s)) / len(proposals)


# ---------------------------------------------------------------------------
# Bootstrap confidence intervals
# ---------------------------------------------------------------------------

def bootstrap_ci(values: list[float], n_bootstrap: int = 1000, ci: float = 0.90) -> tuple[float, float]:
    """Return (lower, upper) bootstrap confidence interval."""
    if not values:
        return (0.0, 0.0)
    arr = np.array(values)
    samples = np.random.choice(arr, size=(n_bootstrap, len(arr)), replace=True).mean(axis=1)
    lo = float(np.percentile(samples, (1 - ci) / 2 * 100))
    hi = float(np.percentile(samples, (1 + ci) / 2 * 100))
    return (lo, hi)


# ---------------------------------------------------------------------------
# Aggregate across seeds
# ---------------------------------------------------------------------------

def aggregate_results(seed_results: list[SeedResult], n_rounds: int, output_dir: Path) -> dict:
    methods = ["biomate", "random", "similarity", "single_pass"]

    # Build: method -> round -> list of metric values across seeds
    hr_by_round: dict[str, dict[int, list[float]]] = {m: {r: [] for r in range(1, n_rounds + 1)} for m in methods}
    cr_by_round: dict[str, dict[int, list[float]]] = {m: {r: [] for r in range(1, n_rounds + 1)} for m in methods}
    ef5_by_round: dict[str, dict[int, list[float]]] = {m: {r: [] for r in range(1, n_rounds + 1)} for m in methods}

    for sr in seed_results:
        oracle = ChEMBLOracle({})  # dummy — metrics already computed
        for rm in sr.rounds:
            hr_by_round[rm.method][rm.round_number].append(rm.hit_rate)
            cr_by_round[rm.method][rm.round_number].append(rm.cumulative_recovery)

    # Convergence CSV for Figure 3
    rows = []
    for method in methods:
        for r in range(1, n_rounds + 1):
            vals = cr_by_round[method][r]
            mean = float(np.mean(vals)) if vals else 0.0
            sd = float(np.std(vals)) if vals else 0.0
            lo, hi = bootstrap_ci(vals)
            rows.append({
                "method": method,
                "round": r,
                "mean_cumulative_recovery": mean,
                "sd": sd,
                "ci_lo": lo,
                "ci_hi": hi,
            })

    convergence_path = output_dir / "convergence_curves.csv"
    with open(convergence_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["method", "round", "mean_cumulative_recovery", "sd", "ci_lo", "ci_hi"])
        w.writeheader()
        w.writerows(rows)

    # Final round hit rate summary
    summary = {}
    for method in methods:
        final_hr = hr_by_round[method][n_rounds]
        mean_hr = float(np.mean(final_hr)) if final_hr else 0.0
        lo, hi = bootstrap_ci(final_hr)
        summary[method] = {
            "mean_hit_rate_final_round": mean_hr,
            "ci_90_lo": lo,
            "ci_90_hi": hi,
        }

    summary_path = output_dir / "aggregate_metrics.json"
    with open(summary_path, "w") as f:
        json.dump({"methods": summary, "n_seeds": len(seed_results)}, f, indent=2)

    log.info("=== Results ===")
    for method, s in summary.items():
        log.info("  %s: hit_rate=%.1f%% [%.1f%%–%.1f%%]",
                 method, s["mean_hit_rate_final_round"]*100,
                 s["ci_90_lo"]*100, s["ci_90_hi"]*100)

    return summary


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(description="DMTA simulation harness for BioMate vs. baselines")
    p.add_argument("--activity-file", nargs="+", required=True,
                   help="Path(s) to ChEMBL activity CSV (smiles, compound_id, pic50 or ic50_nm columns)")
    p.add_argument("--n-rounds", type=int, default=3, help="Number of DMTA rounds")
    p.add_argument("--n-propose", type=int, default=10, help="Compounds proposed per round")
    p.add_argument("--n-seeds", type=int, default=10, help="Number of random seeds for bootstrap")
    p.add_argument("--seed-fraction", type=float, default=0.05, help="Fraction of library used as seed")
    p.add_argument("--active-threshold", type=float, default=7.0, help="pIC50 threshold for 'active'")
    p.add_argument("--diversity-weight", type=float, default=0.2,
                   help="Bayesian optimizer diversity weight (0=pure EI, 1=pure diversity)")
    p.add_argument("--output", required=True, help="Output directory")
    p.add_argument("--seed-start", type=int, default=0, help="First random seed value")
    return p.parse_args()


def main():
    args = parse_args()
    output_root = Path(args.output)
    output_root.mkdir(parents=True, exist_ok=True)

    for activity_file in args.activity_file:
        target_name = Path(activity_file).stem.replace("_chembl", "")
        target_dir = output_root / target_name
        target_dir.mkdir(exist_ok=True)
        log.info("=== Target: %s ===", target_name)

        all_records, oracle = load_activity_csv(activity_file, args.active_threshold)

        if oracle.total_actives([r.smiles for r in all_records]) == 0:
            log.error("No active compounds found at pIC50 ≥ %.1f — check your threshold", args.active_threshold)
            continue

        seed_results = []
        for i in range(args.n_seeds):
            seed_val = args.seed_start + i
            log.info("--- Seed %d/%d ---", i + 1, args.n_seeds)
            try:
                sr = run_one_seed(
                    all_records, oracle,
                    seed=seed_val,
                    target_name=target_name,
                    n_rounds=args.n_rounds,
                    n_propose=args.n_propose,
                    seed_fraction=args.seed_fraction,
                    diversity_weight=args.diversity_weight,
                    output_dir=target_dir,
                )
                seed_results.append(sr)
            except Exception as exc:
                log.error("Seed %d failed: %s", seed_val, exc, exc_info=True)

        if seed_results:
            aggregate_results(seed_results, args.n_rounds, target_dir)

    log.info("Done. Results in %s", output_root)


if __name__ == "__main__":
    main()
