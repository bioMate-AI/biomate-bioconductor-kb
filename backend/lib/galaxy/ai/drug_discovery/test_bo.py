"""
Self-contained test suite for BayesianOptimizer.

Run with:
    cd /home/yzhang/biomate && python backend/lib/galaxy/ai/drug_discovery/test_bo.py
"""
import os
import sys
import tempfile
import traceback

# Make the package importable when run directly from the repo root
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))

import numpy as np

from backend.lib.galaxy.ai.drug_discovery.bayesian_optimizer import (
    BayesianOptimizer,
    CampaignDataset,
    RoundProposal,
)


# ---------------------------------------------------------------------------
# Shared test fixtures
# ---------------------------------------------------------------------------

# 20 simple, chemically valid SMILES for the training set
TRAIN_SMILES = [
    "C", "CC", "CCC", "CCCC", "CCCCC",
    "c1ccccc1", "c1cccnc1", "c1ccncc1", "c1ccoc1", "c1ccsc1",
    "CC(=O)O", "CC(=O)N", "CCO", "CCN", "CCCC(=O)O",
    "c1ccc(N)cc1", "c1ccc(O)cc1", "c1ccc(F)cc1", "c1ccc(Cl)cc1", "c1ccc(Br)cc1",
]

# 30 simple SMILES for the virtual library
VIRTUAL_SMILES = [
    "CCCCCC", "CCCCCCC", "CC(C)C", "CC(C)(C)C", "C1CCCCC1",
    "c1ccc2ccccc2c1", "c1cccc2ccccc12", "c1ccc(CC)cc1", "c1ccc(OC)cc1", "c1ccc(CF)cc1",
    "CC(=O)OCC", "CCC(=O)O", "CCCC(N)=O", "NC(=O)c1ccccc1", "c1ccc(C(=O)O)cc1",
    "CC1=CC=CC=C1", "CC1=CN=CC=C1", "FC1=CC=CC=C1", "ClC1=CC=CC=C1", "BrC1=CC=CC=C1",
    "CC(O)C", "CCCO", "CCCN", "CCC(C)O", "CCC(N)C",
    "c1ccc(NC(=O)C)cc1", "c1ccc(OCC)cc1", "c1ccc(NCC)cc1", "CC(=O)Nc1ccccc1", "CCc1cccnc1",
]

CAMPAIGN_ID = "test_campaign_bo_001"
N_TRAIN = len(TRAIN_SMILES)  # 20

RNG = np.random.RandomState(42)

OBJECTIVES = {
    "potency":      RNG.uniform(0.1, 10.0, N_TRAIN),   # IC50-like, lower=better
    "selectivity":  RNG.uniform(0.0, 1.0, N_TRAIN),    # ratio, higher=better
    "admet_score":  RNG.uniform(0.0, 1.0, N_TRAIN),    # composite ADMET, higher=better
}
OBJ_DIRECTIONS = {
    "potency":     "minimize",
    "selectivity": "maximize",
    "admet_score": "maximize",
}


def _make_dataset(smiles: list[str], rng: np.random.RandomState) -> CampaignDataset:
    """Build a CampaignDataset with random Morgan-like features (256-bit)."""
    n = len(smiles)
    features = rng.rand(n, 256)
    objectives = {
        "potency":      rng.uniform(0.1, 10.0, n),
        "selectivity":  rng.uniform(0.0, 1.0, n),
        "admet_score":  rng.uniform(0.0, 1.0, n),
    }
    return CampaignDataset(
        compound_ids=[f"CPD-{i:03d}" for i in range(n)],
        smiles_list=smiles,
        features=features,
        objectives=objectives,
        objective_directions=dict(OBJ_DIRECTIONS),
    )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_passed = 0
_failed = 0


def _report(name: str, ok: bool, detail: str = ""):
    global _passed, _failed
    status = "PASSED" if ok else "FAILED"
    suffix = f" — {detail}" if detail else ""
    print(f"  [{status}] {name}{suffix}")
    if ok:
        _passed += 1
    else:
        _failed += 1


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_fit_and_propose(db_path: str):
    """Fit the optimizer and propose 5 compounds from the virtual library."""
    print("\n--- Test 1: fit() and propose_next_round() ---")
    try:
        rng = np.random.RandomState(0)
        dataset = _make_dataset(TRAIN_SMILES, rng)

        opt = BayesianOptimizer(campaign_id=CAMPAIGN_ID, db_path=db_path, n_initial=16)
        opt.fit(dataset)

        proposal = opt.propose_next_round(VIRTUAL_SMILES, n_propose=5, diversity_weight=0.2)

        _report("returns RoundProposal", isinstance(proposal, RoundProposal))
        _report("campaign_id correct", proposal.campaign_id == CAMPAIGN_ID)
        _report("round_number == 1", proposal.round_number == 1)
        _report(
            "proposed 5 compounds",
            len(proposal.proposed_compounds) == 5,
            f"got {len(proposal.proposed_compounds)}",
        )
        _report(
            "all proposed SMILES in virtual library",
            all(s in VIRTUAL_SMILES for s in proposal.proposed_compounds),
        )
        _report(
            "no duplicate proposals",
            len(proposal.proposed_compounds) == len(set(proposal.proposed_compounds)),
        )
        _report(
            "scores have 3 objectives",
            set(proposal.scores.keys()) == {"potency", "selectivity", "admet_score"},
        )
        _report(
            "acquisition_values length matches",
            len(proposal.acquisition_values) == 5,
        )
        _report(
            "diversity_score in [0, 1]",
            0.0 <= proposal.diversity_score <= 1.0,
            f"got {proposal.diversity_score:.4f}",
        )
        _report("pareto_front_smiles non-empty", len(proposal.pareto_front_smiles) > 0)

        print("\n  Proposed compounds:")
        for i, smi in enumerate(proposal.proposed_compounds):
            acq = proposal.acquisition_values[i]
            pot = proposal.scores["potency"][i]
            sel = proposal.scores["selectivity"][i]
            adm = proposal.scores["admet_score"][i]
            print(f"    {i+1}. {smi:<30}  acq={acq:.4f}  pot={pot:.4f}  sel={sel:.4f}  admet={adm:.4f}")

        print(f"\n  Pareto front ({len(proposal.pareto_front_smiles)} compounds):")
        for smi in proposal.pareto_front_smiles:
            print(f"    {smi}")

        return proposal, opt, dataset

    except Exception:
        traceback.print_exc()
        _report("test_fit_and_propose", False, "exception raised")
        return None, None, None


def test_insufficient_data(db_path: str):
    """Raise ValueError when fewer than n_initial observations are provided."""
    print("\n--- Test 2: insufficient data guard ---")
    try:
        rng = np.random.RandomState(1)
        small_dataset = _make_dataset(TRAIN_SMILES[:10], rng)  # only 10 < 16

        opt = BayesianOptimizer(
            campaign_id="small_campaign", db_path=db_path, n_initial=16
        )
        opt.fit(small_dataset)

        raised = False
        try:
            opt.propose_next_round(VIRTUAL_SMILES[:5], n_propose=3)
        except ValueError as exc:
            raised = True
            _report(
                "ValueError raised with correct message",
                "Insufficient data" in str(exc),
                str(exc),
            )

        if not raised:
            _report("ValueError raised", False, "no exception raised")

    except Exception:
        traceback.print_exc()
        _report("test_insufficient_data", False, "unexpected exception")


def test_save_load_roundtrip(db_path: str, proposal: RoundProposal):
    """save_proposal / load_proposals round-trip preserves all fields."""
    print("\n--- Test 3: save_proposal / load_proposals round-trip ---")
    if proposal is None:
        _report("round-trip (skipped — proposal is None)", False)
        return

    try:
        opt = BayesianOptimizer(campaign_id=CAMPAIGN_ID, db_path=db_path)
        opt.save_proposal(proposal)

        loaded = opt.load_proposals(CAMPAIGN_ID)
        _report("load returns non-empty list", len(loaded) > 0)

        p = loaded[-1]  # last proposal
        _report("campaign_id preserved", p.campaign_id == proposal.campaign_id)
        _report("round_number preserved", p.round_number == proposal.round_number)
        _report(
            "proposed_compounds preserved",
            p.proposed_compounds == proposal.proposed_compounds,
        )
        _report(
            "scores keys preserved",
            set(p.scores.keys()) == set(proposal.scores.keys()),
        )
        _report(
            "acquisition_values preserved",
            len(p.acquisition_values) == len(proposal.acquisition_values),
        )
        _report(
            "pareto_front_smiles preserved",
            p.pareto_front_smiles == proposal.pareto_front_smiles,
        )
        _report(
            "diversity_score preserved",
            abs(p.diversity_score - proposal.diversity_score) < 1e-9,
            f"{p.diversity_score:.6f} vs {proposal.diversity_score:.6f}",
        )
        _report("timestamp preserved", p.timestamp == proposal.timestamp)

    except Exception:
        traceback.print_exc()
        _report("test_save_load_roundtrip", False, "exception raised")


def test_pareto_summary(db_path: str, opt: BayesianOptimizer, dataset: CampaignDataset):
    """get_pareto_summary returns a well-formed dict."""
    print("\n--- Test 4: get_pareto_summary() ---")
    if opt is None or dataset is None:
        _report("pareto_summary (skipped — opt/dataset is None)", False)
        return

    try:
        summary = opt.get_pareto_summary(dataset)

        _report("returns dict", isinstance(summary, dict))
        _report("has n_compounds", "n_compounds" in summary)
        _report(
            "n_compounds matches dataset",
            summary["n_compounds"] == len(dataset.compound_ids),
        )
        _report("has n_pareto", "n_pareto" in summary)
        _report("n_pareto in valid range", 1 <= summary["n_pareto"] <= summary["n_compounds"])
        _report("has pareto_smiles", "pareto_smiles" in summary)
        _report(
            "pareto_smiles length == n_pareto",
            len(summary["pareto_smiles"]) == summary["n_pareto"],
        )
        _report("has objective_ranges", "objective_ranges" in summary)
        _report(
            "objective_ranges has all objectives",
            set(summary["objective_ranges"].keys()) == {"potency", "selectivity", "admet_score"},
        )
        for obj_name, rng_ in summary["objective_ranges"].items():
            _report(
                f"  {obj_name} range min <= max",
                rng_["min"] <= rng_["max"],
                f"min={rng_['min']:.4f} max={rng_['max']:.4f}",
            )
        _report("has round_number", "round_number" in summary)

        print(f"\n  Summary: {summary['n_pareto']}/{summary['n_compounds']} on Pareto front")
        for obj_name, rng_ in summary["objective_ranges"].items():
            print(f"    {obj_name}: [{rng_['min']:.4f}, {rng_['max']:.4f}]")

    except Exception:
        traceback.print_exc()
        _report("test_pareto_summary", False, "exception raised")


def test_multiple_proposals(db_path: str):
    """propose_next_round increments round_number on successive calls."""
    print("\n--- Test 5: successive proposals increment round_number ---")
    try:
        rng = np.random.RandomState(99)
        dataset = _make_dataset(TRAIN_SMILES, rng)

        opt = BayesianOptimizer(
            campaign_id="multi_round_campaign", db_path=db_path, n_initial=16
        )
        opt.fit(dataset)

        p1 = opt.propose_next_round(VIRTUAL_SMILES, n_propose=3)
        p2 = opt.propose_next_round(VIRTUAL_SMILES, n_propose=3)

        _report("first proposal round_number == 1", p1.round_number == 1)
        _report("second proposal round_number == 2", p2.round_number == 2)

    except Exception:
        traceback.print_exc()
        _report("test_multiple_proposals", False, "exception raised")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("BayesianOptimizer Test Suite")
    print("=" * 60)

    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_bo.db")

        proposal, opt, dataset = test_fit_and_propose(db_path)
        test_insufficient_data(db_path)
        test_save_load_roundtrip(db_path, proposal)
        test_pareto_summary(db_path, opt, dataset)
        test_multiple_proposals(db_path)

    print("\n" + "=" * 60)
    print(f"Results: {_passed} PASSED, {_failed} FAILED")
    print("=" * 60)

    sys.exit(0 if _failed == 0 else 1)


if __name__ == "__main__":
    main()
