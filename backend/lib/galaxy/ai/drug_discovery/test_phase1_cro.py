"""
Phase 1 CRO Readiness — Integration test suite.

Tests:
  T1  ModelValidationService — full 31-drug validation, EMA criterion
  T2  ModelValidationService — filtered subset
  T3  ModelValidationService — per-compound metrics sanity
  T4  ApplicabilityDomainChecker — leverage threshold / in-domain / out-of-domain
  T5  ApplicabilityDomainChecker — confidence interval computation
  T6  ApplicabilityDomainChecker — batch mode
  T7  BayesianOptimizer.propose_next_round() — new fields present
  T8  BayesianOptimizer.propose_next_round() — CI and AD values are plausible
  T9  API endpoint — model-validation response structure
  T10 API endpoint — propose response includes confidence_intervals + ad_statuses

Run:
    cd /home/yzhang/biomate/backend
    python lib/galaxy/ai/drug_discovery/test_phase1_cro.py
"""

import math
import os
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "..", "..", ".."))

_passed = 0
_failed = 0


def _ok(name: str, detail: str = ""):
    global _passed
    _passed += 1
    suf = f" — {detail}" if detail else ""
    print(f"  [PASSED] {name}{suf}")


def _fail(name: str, detail: str = ""):
    global _failed
    _failed += 1
    suf = f" — {detail}" if detail else ""
    print(f"  [FAILED] {name}{suf}")


def _check(name: str, condition: bool, detail: str = ""):
    if condition:
        _ok(name, detail)
    else:
        _fail(name, detail)


# ---------------------------------------------------------------------------
# T1 / T2 / T3  ModelValidationService
# ---------------------------------------------------------------------------

def test_model_validation_full():
    print("\n--- T1: Full 31-drug PBPK validation ---")
    from backend.lib.galaxy.ai.drug_discovery.model_validation import ModelValidationService

    svc = ModelValidationService()
    report = svc.run_pbpk_validation()

    _check("n_compounds >= 30", report.n_reference_compounds >= 30,
           f"got {report.n_reference_compounds}")
    _check("AAFE_Cmax < 3.0 (acceptable accuracy)", report.metrics.AAFE_Cmax < 3.0,
           f"AAFE={report.metrics.AAFE_Cmax}")
    _check("AAFE_AUC < 1.5 (near-perfect AUC)", report.metrics.AAFE_AUC < 1.5,
           f"AAFE={report.metrics.AAFE_AUC}")
    _check("within_2fold_Cmax >= 0.67 (EMA criterion)", report.metrics.within_2fold_Cmax >= 0.67,
           f"{report.metrics.within_2fold_Cmax*100:.1f}%")
    _check("within_2fold_AUC >= 0.67 (EMA criterion)", report.metrics.within_2fold_AUC >= 0.67,
           f"{report.metrics.within_2fold_AUC*100:.1f}%")
    _check("R2_Cmax > 0.85 (good correlation)", report.metrics.R2_Cmax > 0.85,
           f"R2={report.metrics.R2_Cmax}")
    _check("R2_AUC > 0.95 (excellent AUC correlation)", report.metrics.R2_AUC > 0.95,
           f"R2={report.metrics.R2_AUC}")
    _check("ema_criterion_met is True", report.ema_criterion_met)
    _check("regulatory_summary non-empty", len(report.regulatory_summary) > 100)
    _check("warnings is a list", isinstance(report.warnings, list))

    # per_compound sanity
    _check("per_compound length matches n_reference", len(report.per_compound) == report.n_reference_compounds)
    for r in report.per_compound:
        if r.fold_error_Cmax is not None:
            _check(f"{r.name} fold_error_Cmax is positive float",
                   isinstance(r.fold_error_Cmax, float) and r.fold_error_Cmax > 0,
                   f"fold={r.fold_error_Cmax}")
            break  # just check one


def test_model_validation_subset():
    print("\n--- T2: Subset validation (high-quality drugs only) ---")
    from backend.lib.galaxy.ai.drug_discovery.model_validation import ModelValidationService

    svc = ModelValidationService()
    # These drugs have consistent CL/Vd/F references and simple PK
    names = ["Aspirin", "Ibuprofen", "Warfarin", "Caffeine", "Theophylline",
             "Paracetamol", "Alprazolam", "Diazepam"]
    report = svc.run_pbpk_validation(drug_names=names)

    _check("subset n_compounds correct", report.n_reference_compounds == len(names),
           f"got {report.n_reference_compounds}")
    _check("subset AAFE_Cmax < 2.0", report.metrics.AAFE_Cmax < 2.0,
           f"AAFE={report.metrics.AAFE_Cmax}")
    _check("subset within_2fold_Cmax >= 0.75", report.metrics.within_2fold_Cmax >= 0.75,
           f"{report.metrics.within_2fold_Cmax*100:.1f}%")
    _check("subset within_2fold_AUC = 1.0", report.metrics.within_2fold_AUC == 1.0,
           f"{report.metrics.within_2fold_AUC*100:.1f}%")


def test_model_validation_per_compound():
    print("\n--- T3: Per-compound result structure ---")
    from backend.lib.galaxy.ai.drug_discovery.model_validation import ModelValidationService

    svc = ModelValidationService()
    report = svc.run_pbpk_validation(drug_names=["Caffeine"])
    assert report.n_reference_compounds == 1
    r = report.per_compound[0]

    _check("name == Caffeine", r.name == "Caffeine")
    _check("dose_mg == 200", r.dose_mg == 200.0)
    _check("route == oral", r.route == "oral")
    _check("predicted_Cmax is float", isinstance(r.predicted_Cmax, float))
    _check("predicted_AUC is float", isinstance(r.predicted_AUC, float))
    _check("percent_error_Cmax is float", isinstance(r.percent_error_Cmax, float))
    _check("fold_error_Cmax > 0", r.fold_error_Cmax > 0)
    _check("fold_error_AUC near 1.0 (AUC should be accurate)",
           0.7 <= r.fold_error_AUC <= 1.3, f"fold_AUC={r.fold_error_AUC}")
    _check("caffeine fold_Cmax within 2-fold",
           0.5 <= r.fold_error_Cmax <= 2.0, f"fold={r.fold_error_Cmax}")


# ---------------------------------------------------------------------------
# T4 / T5 / T6  ApplicabilityDomainChecker
# ---------------------------------------------------------------------------

def test_ad_in_domain():
    print("\n--- T4: AD checker — in-domain and out-of-domain ---")
    from backend.lib.galaxy.ai.drug_discovery.applicability_domain import ApplicabilityDomainChecker

    # Structured training set: 20 compounds with bits 0-63 active, bits 64-127 silent.
    # A query with ONLY bits 64-127 active is structurally orthogonal → very high leverage.
    n_train = 20
    n_bits = 128
    training_fps = np.zeros((n_train, n_bits))
    rng = np.random.RandomState(42)
    for i in range(n_train):
        # Each compound has ~10 random bits in the first 64 bits
        active = rng.choice(64, size=10, replace=False)
        training_fps[i, active] = 1.0

    checker = ApplicabilityDomainChecker(training_fps, leverage_factor=3.0)
    _check("leverage_threshold > 0", checker.leverage_threshold > 0,
           f"h*={checker.leverage_threshold:.6f}")

    # In-domain: identical to training point 0 — must be within threshold
    in_fp = training_fps[0].copy()
    r_in = checker.check("CC(=O)O", in_fp)
    _check("in-domain status", r_in.ad_status == "in_domain",
           f"leverage={r_in.leverage:.4f} threshold={r_in.leverage_threshold:.4f}")

    # Out-of-domain: bits 64-127 only — completely outside training feature space
    ood_fp = np.zeros(n_bits)
    ood_fp[64:74] = 1.0   # bits entirely absent from training set
    r_ood = checker.check("c1ccccc1", ood_fp)
    _check("out-of-domain status", r_ood.ad_status == "out_of_domain",
           f"leverage={r_ood.leverage:.4f} threshold={r_ood.leverage_threshold:.4f}")
    _check("out-of-domain has warning", len(r_ood.warnings) > 0)


def test_ad_confidence_interval():
    print("\n--- T5: AD checker — 95% CI from GP std ---")
    from backend.lib.galaxy.ai.drug_discovery.applicability_domain import ApplicabilityDomainChecker

    rng = np.random.RandomState(7)
    X_train = (rng.rand(20, 128) > 0.8).astype(float)
    checker = ApplicabilityDomainChecker(X_train)

    # With gp_mean + gp_std
    fp = X_train[5].copy()
    r = checker.check("CCO", fp, gp_mean=0.65, gp_std=0.10)

    _check("CI is tuple of 2", isinstance(r.confidence_interval_95, tuple) and len(r.confidence_interval_95) == 2)
    lo, hi = r.confidence_interval_95
    _check("CI lower = max(0, mean - 1.96*std)", abs(lo - max(0.0, 0.65 - 1.96 * 0.10)) < 1e-3,
           f"lo={lo:.4f}")
    _check("CI upper = min(1, mean + 1.96*std)", abs(hi - min(1.0, 0.65 + 1.96 * 0.10)) < 1e-3,
           f"hi={hi:.4f}")
    _check("predicted_mean == 0.65", abs(r.predicted_mean - 0.65) < 1e-4)

    # Without GP info
    r_no_ci = checker.check("CCCC", fp)
    _check("no CI when gp_mean/std not passed", r_no_ci.confidence_interval_95 is None)

    # High uncertainty warning
    r_hi = checker.check("CCCO", fp, gp_mean=0.50, gp_std=0.30)
    has_uncertainty_warn = any("uncertainty" in w.lower() or "confidence" in w.lower() for w in r_hi.warnings)
    _check("high-uncertainty warning present when std > 0.25", has_uncertainty_warn)


def test_ad_batch():
    print("\n--- T6: AD checker — batch mode ---")
    from backend.lib.galaxy.ai.drug_discovery.applicability_domain import ApplicabilityDomainChecker

    rng = np.random.RandomState(99)
    X_train = (rng.rand(25, 128) > 0.8).astype(float)
    checker = ApplicabilityDomainChecker(X_train)

    n_query = 10
    fps = (rng.rand(n_query, 128) > 0.8).astype(float)
    smiles = [f"C{'C'*i}" for i in range(n_query)]
    means = rng.uniform(0.3, 0.9, n_query)
    stds  = rng.uniform(0.02, 0.15, n_query)

    results = checker.check_batch(smiles, fps, gp_means=means, gp_stds=stds)

    _check("batch returns correct count", len(results) == n_query)
    statuses = {r.ad_status for r in results}
    _check("batch statuses are valid strings", statuses.issubset({"in_domain", "out_of_domain", "unknown"}))
    _check("all results have CI", all(r.confidence_interval_95 is not None for r in results))
    _check("all CIs have lo <= hi", all(r.confidence_interval_95[0] <= r.confidence_interval_95[1] for r in results))


# ---------------------------------------------------------------------------
# T7 / T8  BayesianOptimizer new fields
# ---------------------------------------------------------------------------

def test_bo_new_fields_present():
    print("\n--- T7: BayesianOptimizer — new CI/AD fields present in proposal ---")
    from backend.lib.galaxy.ai.drug_discovery.bayesian_optimizer import BayesianOptimizer, RoundProposal
    import dataclasses

    # Check dataclass fields
    field_names = {f.name for f in dataclasses.fields(RoundProposal)}
    _check("confidence_intervals field exists", "confidence_intervals" in field_names)
    _check("ad_statuses field exists", "ad_statuses" in field_names)
    _check("gp_stds field exists", "gp_stds" in field_names)


def test_bo_propose_ci_and_ad():
    print("\n--- T8: BayesianOptimizer — CI and AD plausible in actual proposal ---")
    from backend.lib.galaxy.ai.drug_discovery.bayesian_optimizer import BayesianOptimizer

    rng = np.random.RandomState(42)
    n_train = 20

    # 20 training + virtual library using random fingerprints
    train_smiles = [f"C{'C'*i}" for i in range(n_train)]
    virtual_smiles = [f"c1{'c'*i}cccc1" for i in range(1, 11)]  # 10 virtual

    with tempfile.TemporaryDirectory() as tmpdir:
        db_path = os.path.join(tmpdir, "test_ci.db")
        opt = BayesianOptimizer(campaign_id="ci-test", db_path=db_path, n_initial=16)

        fps = rng.rand(n_train, 256)
        scores = rng.uniform(0.2, 0.9, n_train).tolist()

        import sqlite3
        with sqlite3.connect(db_path) as conn:
            conn.execute("""CREATE TABLE IF NOT EXISTS campaigns
                (campaign_id TEXT, compound_id TEXT, smiles TEXT, composite_score REAL)""")
            for i in range(n_train):
                conn.execute("INSERT INTO campaigns VALUES (?,?,?,?)",
                             ("ci-test", f"C{i}", train_smiles[i], scores[i]))

        from backend.lib.galaxy.ai.drug_discovery.bayesian_optimizer import CampaignDataset
        dataset = CampaignDataset(
            compound_ids=[f"C{i}" for i in range(n_train)],
            smiles_list=train_smiles,
            features=fps,
            objectives={"composite_score": np.array(scores)},
            objective_directions={"composite_score": "maximize"},
        )
        opt._dataset = dataset
        opt._gp_models = {}
        from sklearn.gaussian_process import GaussianProcessRegressor
        from sklearn.gaussian_process.kernels import Matern
        from sklearn.preprocessing import MinMaxScaler

        scaler = MinMaxScaler()
        y = scaler.fit_transform(np.array(scores).reshape(-1, 1)).ravel()
        gp = GaussianProcessRegressor(kernel=Matern(nu=2.5), n_restarts_optimizer=1, random_state=42)
        gp.fit(fps, y)
        opt._gp_models["composite_score"] = gp
        opt._dataset.features = fps

        # Virtual library needs feature vectors too — use random
        virtual_fps = rng.rand(len(virtual_smiles), 256)

        # Monkey-patch featurise to return the pre-computed matrix
        original_featurise = opt._featurise
        call_count = [0]
        def mock_featurise(smiles_list):
            call_count[0] += 1
            return virtual_fps
        opt._featurise = mock_featurise

        proposal = opt.propose_next_round(virtual_smiles, n_propose=3, diversity_weight=0.2)

    _check("confidence_intervals non-empty", bool(proposal.confidence_intervals),
           f"keys={list(proposal.confidence_intervals.keys())}")
    _check("ad_statuses length == 3", len(proposal.ad_statuses) == 3,
           f"got {len(proposal.ad_statuses)}")
    _check("gp_stds non-empty", bool(proposal.gp_stds))

    cis = proposal.confidence_intervals.get("composite_score", [])
    _check("CI count == 3", len(cis) == 3)
    if cis:
        lo, hi = cis[0]
        _check("CI has lo <= hi", lo <= hi, f"({lo:.3f}, {hi:.3f})")
        _check("CI values in [0,1]", 0.0 <= lo and hi <= 1.0, f"({lo:.3f},{hi:.3f})")

    valid_statuses = {"in_domain", "out_of_domain", "unknown"}
    _check("AD statuses valid", all(s in valid_statuses for s in proposal.ad_statuses),
           str(proposal.ad_statuses))


# ---------------------------------------------------------------------------
# T9 / T10  API endpoint structure (via direct async call)
# ---------------------------------------------------------------------------

def test_api_validation_endpoint():
    print("\n--- T9: API endpoint — model-validation response structure ---")
    import asyncio

    async def _run():
        from backend.lib.galaxy.ai.drug_discovery.api_router import get_model_validation
        result = await get_model_validation("pbpk", drug_names=None)
        return result

    result = asyncio.run(_run())

    required_keys = {"model_type", "dataset_name", "n_reference_compounds",
                     "per_compound", "metrics", "regulatory_summary", "ema_criterion_met", "warnings"}
    _check("response has all required keys", required_keys.issubset(result.keys()))
    _check("model_type == pbpk", result["model_type"] == "pbpk")
    _check("ema_criterion_met True", result["ema_criterion_met"] is True)

    m = result["metrics"]
    _check("metrics has AAFE_Cmax", "AAFE_Cmax" in m)
    _check("metrics has R2_AUC", "R2_AUC" in m)
    _check("AAFE_AUC < 1.1 (near-perfect)", m["AAFE_AUC"] < 1.1,
           f"AAFE_AUC={m['AAFE_AUC']}")
    _check("within_2fold_AUC = 1.0", m["within_2fold_AUC"] == 1.0,
           f"{m['within_2fold_AUC']*100:.1f}%")
    _check("within_2fold_Cmax >= 0.67", m["within_2fold_Cmax"] >= 0.67,
           f"{m['within_2fold_Cmax']*100:.1f}%")


def test_api_validation_invalid_model():
    print("\n--- T10: API endpoint — 400 on unknown model type ---")
    import asyncio
    from fastapi import HTTPException

    async def _run():
        from backend.lib.galaxy.ai.drug_discovery.api_router import get_model_validation
        try:
            await get_model_validation("unknown_model", drug_names=None)
            return False  # should have raised
        except HTTPException as e:
            return e.status_code == 400

    ok = asyncio.run(_run())
    _check("unknown model_type returns 400", ok)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("=" * 60)
    print("Phase 1 CRO Readiness — Test Suite")
    print("=" * 60)

    test_model_validation_full()
    test_model_validation_subset()
    test_model_validation_per_compound()
    test_ad_in_domain()
    test_ad_confidence_interval()
    test_ad_batch()
    test_bo_new_fields_present()
    test_bo_propose_ci_and_ad()
    test_api_validation_endpoint()
    test_api_validation_invalid_model()

    print()
    print("=" * 60)
    print(f"Results: {_passed} PASSED, {_failed} FAILED")
    print("=" * 60)

    sys.exit(0 if _failed == 0 else 1)


if __name__ == "__main__":
    main()
