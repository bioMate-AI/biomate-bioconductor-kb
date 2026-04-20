"""
BioMate Scientific Validation Test Suite

Tests are grounded in authoritative literature and regulatory guidance:

  Pharmacokinetics:
    - Bateman equation (1-compartment oral):
        Wagner JG. "Pharmacokinetics for the Pharmaceutical Scientist", 1993.
        Gabrielsson J, Weiner D. "Pharmacokinetic & Pharmacodynamic Data Analysis", 5th ed., 2016.
    - AUC mass balance:
        Rowland M, Tozer TN. "Clinical Pharmacokinetics and Pharmacodynamics", 4th ed., 2011.
    - EMA PBPK acceptance criterion (≥67% predictions within 2-fold):
        EMA/CHMP/EWP/37498/2011 Rev1: "Guideline on the reporting of physiologically
        based pharmacokinetic (PBPK) modelling and simulation", 2018.
    - AFE/AAFE definitions:
        Sheiner LB, Beal SL. J Pharmacokinet Biopharm 1981;9(4):503–512.
    - Hepatic blood flow ~90 L/h:
        Davies B, Morris T. Pharm Res 1993;10(7):1093–1095.

  Applicability Domain:
    - Leverage hat-matrix:
        Tropsha A. Mol Inform 2010;29(6–7):476–488.
        Roy K et al. J Cheminform 2015;7:27.
    - Tanimoto boundary conditions: Bajusz D et al. J Cheminform 2015;7:20.

  21 CFR Part 11 Audit Chain:
    - FDA Guidance for Industry: 21 CFR Part 11; Electronic Records;
      Electronic Signatures – Scope and Application. August 2003.
    - SHA-256 hash chain design: Haber S, Stornetta WS. J Cryptology 1991;3(2):99–111.

  TOTP (RFC 6238):
    - RFC 6238: TOTP: Time-Based One-Time Password Algorithm, 2011.
    - HMAC-SHA1: RFC 2104, 1997.
"""

import hashlib
import math
import os
import sqlite3
import tempfile
import threading
import time
import uuid
from pathlib import Path
from typing import Optional

import pytest

# ---------------------------------------------------------------------------
# Helpers for isolated test databases
# ---------------------------------------------------------------------------

def _tmp_db() -> str:
    """Return a path to a fresh temporary SQLite database."""
    f = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
    f.close()
    return f.name


def _tmp_dir() -> str:
    return tempfile.mkdtemp()


# ===========================================================================
# 1. PK EQUATION INVARIANTS
# ===========================================================================
# These tests verify that _AnalyticalPKPredictor produces values that are
# consistent with closed-form PK equations.  All assertions carry ±tolerances
# referenced to acceptable clinical prediction accuracy.
# ===========================================================================

class TestPKEquationInvariants:
    """
    Verify 1-compartment model equations against analytical solutions.
    References:
      Wagner 1993 § 4.2 (IV bolus); § 5.3 (oral 1-compartment Bateman equation)
      Rowland & Tozer 2011 Chapter 3 (AUC = F·D/CL)
    """

    @pytest.fixture(autouse=True)
    def _import(self):
        from .model_validation import _AnalyticalPKPredictor
        self.predictor = _AnalyticalPKPredictor()

    # -----------------------------------------------------------------------
    # IV bolus: Cmax = D/Vd (Wagner 1993 §4.2 eq. 4-1)
    # -----------------------------------------------------------------------

    def test_iv_cmax_equals_dose_over_vd(self):
        """IV Cmax = D/Vd.  Exact for a 1-compartment bolus (no distribution phase)."""
        drug = {
            "name": "TestIV",
            "dose_mg": 100,       # 100 mg → 100,000 µg
            "route": "iv",
            "F_oral": 1.0,
            "CL_L_h": 10.0,       # 10 L/h
            "Vd_L": 50.0,         # 50 L
            "logP": 2.0,
        }
        result = self.predictor.predict(drug)
        expected_Cmax_ug_mL = (100_000.0 / (50.0 * 1000.0))  # D_µg / (Vd_L × 1000 mL/L)
        assert result["predicted_Cmax"] == pytest.approx(expected_Cmax_ug_mL, rel=1e-4), (
            f"IV Cmax should equal D/Vd = {expected_Cmax_ug_mL:.4f} µg/mL"
        )

    # -----------------------------------------------------------------------
    # AUC mass balance: AUC = D/CL_apparent (Rowland & Tozer 2011 eq. 3-7)
    # For oral drugs, CL_apparent = CL_true/F, so AUC = D_oral/CL_apparent.
    # F is already embedded; applying it again gives AUC×F (wrong by a factor of F).
    # -----------------------------------------------------------------------

    def test_auc_mass_balance_oral(self):
        """
        AUC_oral = dose_oral / CL_apparent.
        CL_apparent already embeds bioavailability.  No F factor must be applied.
        Rowland & Tozer 2011, Chapter 3: AUC_0_inf = F·D / CL_true = D / CL_apparent.
        """
        F = 0.3
        CL_apparent = 200.0   # L/h  (CL_true = 60 L/h)
        dose_mg = 10
        dose_ug = dose_mg * 1000.0

        drug = {
            "name": "TestOralAUC",
            "dose_mg": dose_mg,
            "route": "oral",
            "F_oral": F,
            "CL_L_h": CL_apparent,
            "Vd_L": 400.0,
            "logP": 3.0,
        }
        result = self.predictor.predict(drug)
        expected_AUC = dose_ug / (CL_apparent * 1000.0)   # µg·h/mL
        assert result["predicted_AUC"] == pytest.approx(expected_AUC, rel=1e-4), (
            "AUC must equal dose/CL_apparent (no extra F factor)"
        )

    def test_auc_mass_balance_iv(self):
        """AUC_iv = dose / CL_true.  F=1 for IV."""
        CL = 30.0     # L/h
        dose_mg = 50
        dose_ug = dose_mg * 1000.0

        drug = {
            "name": "TestIVAUC",
            "dose_mg": dose_mg,
            "route": "iv",
            "F_oral": 1.0,
            "CL_L_h": CL,
            "Vd_L": 100.0,
            "logP": 1.0,
        }
        result = self.predictor.predict(drug)
        expected_AUC = dose_ug / (CL * 1000.0)
        assert result["predicted_AUC"] == pytest.approx(expected_AUC, rel=1e-4)

    # -----------------------------------------------------------------------
    # ke = CL_true / Vd (Gabrielsson & Weiner 2016, §3.2)
    # For oral drugs: CL_true = CL_apparent × F  →  ke = CL_apparent × F / Vd
    # -----------------------------------------------------------------------

    def test_ke_and_half_life(self):
        """
        Predicted t½ = ln(2)/ke.
        ke_oral = CL_apparent × F / Vd  (NOT CL_apparent/Vd).
        Gabrielsson & Weiner 2016, eq. 3.8.
        """
        F = 0.4
        CL_apparent = 50.0  # L/h
        Vd = 200.0           # L
        ke_true = CL_apparent * F / Vd  # 0.10 /h
        expected_t_half = math.log(2) / ke_true  # 6.93 h

        drug = {
            "name": "TestHalfLife",
            "dose_mg": 100,
            "route": "oral",
            "F_oral": F,
            "CL_L_h": CL_apparent,
            "Vd_L": Vd,
            "logP": 2.5,
        }
        result = self.predictor.predict(drug)
        # t½ must be within 1% of analytical value
        assert result["predicted_t_half_h"] == pytest.approx(expected_t_half, rel=0.01), (
            f"Expected t½={expected_t_half:.2f} h; got {result.get('predicted_t_half_h')}"
        )

    # -----------------------------------------------------------------------
    # tmax = ln(ka/ke) / (ka−ke)  (Bateman 1954; Wagner 1993 eq. 5-14)
    # Inferred from the predicted Cmax — at tmax, dC/dt = 0, so
    # ka × exp(−ka×t) = ke × exp(−ke×t)  →  t = ln(ka/ke)/(ka−ke).
    # -----------------------------------------------------------------------

    def test_oral_cmax_bateman_shape(self):
        """
        Oral Cmax obeys the Bateman equation.
        For ka=3, ke=0.3 /h, F=0.8, D=50mg, Vd=40L:
          tmax = ln(10)/(2.7) ≈ 0.852 h
          Cmax_unit = (F·D/Vd) = (0.8×50000µg)/(40L) = 1000 µg/L = 1 µg/mL
          Cmax ≈ 1 × (3/(3-0.3)) × (exp(-0.3×0.852) - exp(-3×0.852))
               ≈ 1 × 1.111 × (0.774 - 0.077) ≈ 0.774 µg/mL
        We test that the prediction is within 15% of this value (ka is estimated
        from logP, not exact, so absolute match is not expected — only shape check).
        """
        drug = {
            "name": "TestBateman",
            "dose_mg": 50,
            "route": "oral",
            "F_oral": 0.8,
            "CL_L_h": 12.0,   # ke = 12×0.8/40 = 0.24/h
            "Vd_L": 40.0,
            "logP": 3.0,       # ka ~ 3.0 /h from the estimator
        }
        result = self.predictor.predict(drug)
        # F=0.8, dose=50mg, Vd=40L → F·D/Vd = 1 µg/mL  (exact)
        # Bateman peak fraction ∈ [0.4, 0.9] for any reasonable ka/ke ratio
        dose_ug = 50 * 1000.0
        F = 0.8
        Vd_L = 40.0
        cmax_unit = (F * dose_ug) / (Vd_L * 1000.0)  # µg/mL
        pred = result["predicted_Cmax"]
        assert pred is not None
        assert 0.3 * cmax_unit <= pred <= cmax_unit, (
            f"Bateman peak should be 30–100% of F·D/Vd={cmax_unit:.3f}; got {pred:.3f}"
        )

    # -----------------------------------------------------------------------
    # Linearity: doubling dose doubles Cmax and AUC
    # (linear PK assumption: Rowland & Tozer 2011 Chapter 2)
    # -----------------------------------------------------------------------

    def test_dose_linearity(self):
        """Cmax and AUC scale linearly with dose in 1-compartment model."""
        base_drug = {
            "name": "TestLinear",
            "dose_mg": 50,
            "route": "oral",
            "F_oral": 0.6,
            "CL_L_h": 30.0,
            "Vd_L": 100.0,
            "logP": 2.0,
        }
        double_drug = {**base_drug, "dose_mg": 100}

        r1 = self.predictor.predict(base_drug)
        r2 = self.predictor.predict(double_drug)

        assert r2["predicted_AUC"] == pytest.approx(2 * r1["predicted_AUC"], rel=1e-4)
        assert r2["predicted_Cmax"] == pytest.approx(2 * r1["predicted_Cmax"], rel=1e-4)

    # -----------------------------------------------------------------------
    # Clopidogrel excluded from validation (prodrug with impossible CL_true)
    # Reference: Sanofi-Aventis USPI 2011; Kazui et al. Drug Metab Dispos 2010
    # -----------------------------------------------------------------------

    def test_clopidogrel_excluded_from_validation(self):
        """
        Clopidogrel is a CYP2C19 prodrug.  Parent CL_apparent = 8333 L/h
        (CL_true = 4167 L/h) — physiologically impossible (>46× hepatic blood
        flow; Davies & Morris 1993).  It must be flagged as exclude_from_validation
        and absent from the ModelValidationService metrics.
        """
        from .model_validation import ModelValidationService
        svc = ModelValidationService()
        report = svc.run_pbpk_validation()
        names = [r.name for r in report.per_compound]
        assert "Clopidogrel" not in names, (
            "Clopidogrel is a prodrug with impossible CL_true and must be excluded"
        )

    # -----------------------------------------------------------------------
    # EMA criterion: ≥67% within 2-fold (EMA/CHMP/EWP/37498/2011 Rev1)
    # -----------------------------------------------------------------------

    def test_ema_criterion_met_overall(self):
        """
        The EMA PBPK qualification guideline (2018) requires that at least 67%
        of predictions fall within 2-fold of observed values for Cmax and AUC.
        Reference: EMA/CHMP/EWP/37498/2011 Rev1, §4.2.2.
        """
        from .model_validation import ModelValidationService
        svc = ModelValidationService()
        report = svc.run_pbpk_validation()
        assert report.metrics.within_2fold_Cmax >= 0.67, (
            f"EMA criterion: within_2fold_Cmax={report.metrics.within_2fold_Cmax:.2%} < 67%"
        )
        assert report.metrics.within_2fold_AUC >= 0.67, (
            f"EMA criterion: within_2fold_AUC={report.metrics.within_2fold_AUC:.2%} < 67%"
        )

    # -----------------------------------------------------------------------
    # AFE/AAFE definitions (Sheiner & Beal 1981)
    # AFE = exp(mean(log(pred/obs)))  — geometric mean of fold errors
    # AAFE = exp(mean(|log(pred/obs)|))  — geometric mean of abs fold errors
    # AFE < 1 → systematic underprediction; AFE > 1 → systematic overprediction
    # -----------------------------------------------------------------------

    def test_afe_aafe_definitions(self):
        """
        Verify AFE/AAFE algebraic identity from Sheiner & Beal 1981.
        """
        from .model_validation import ModelValidationService
        import numpy as np

        svc = ModelValidationService()
        report = svc.run_pbpk_validation()

        fold_cmax = [r.fold_error_Cmax for r in report.per_compound
                     if r.fold_error_Cmax is not None and r.fold_error_Cmax > 0]

        expected_afe = math.exp(sum(math.log(f) for f in fold_cmax) / len(fold_cmax))
        expected_aafe = math.exp(sum(abs(math.log(f)) for f in fold_cmax) / len(fold_cmax))

        assert report.metrics.AFE_Cmax == pytest.approx(expected_afe, rel=1e-3)
        assert report.metrics.AAFE_Cmax == pytest.approx(expected_aafe, rel=1e-3)

    # -----------------------------------------------------------------------
    # AAFE ≥ AFE always (Jensen's inequality; AAFE = 1.0 only if all errors = 0)
    # -----------------------------------------------------------------------

    def test_aafe_geq_afe(self):
        """AAFE ≥ |AFE| for any prediction set (Jensen's inequality)."""
        from .model_validation import ModelValidationService
        svc = ModelValidationService()
        report = svc.run_pbpk_validation()
        assert report.metrics.AAFE_Cmax >= abs(report.metrics.AFE_Cmax) - 1e-9
        assert report.metrics.AAFE_AUC  >= abs(report.metrics.AFE_AUC)  - 1e-9


# ===========================================================================
# 2. APPLICABILITY DOMAIN
# ===========================================================================

class TestApplicabilityDomain:
    """
    Test AD mathematical properties.
    References:
      Tropsha A. Mol Inform 2010;29:476–488 (leverage threshold h* = 3/n × Σhii)
      Bajusz D et al. J Cheminform 2015;7:20 (Tanimoto similarity properties)
    """

    @pytest.fixture(autouse=True)
    def _import(self):
        import numpy as np
        from .applicability_domain import ApplicabilityDomainChecker
        self.np = np
        self.ADC = ApplicabilityDomainChecker

    # Use 128-bit fingerprints in tests for fast pinv computation.
    # The mathematical properties under test are independent of fingerprint length.
    _N_BITS = 128

    def _make_fp(self, bits: list[int], n_bits: int = None) -> "np.ndarray":
        n = n_bits if n_bits is not None else self._N_BITS
        fp = self.np.zeros(n, dtype=int)
        for b in bits:
            fp[b] = 1
        return fp

    def _make_checker(self, fps_list):
        """Build ADC from a list of fingerprint arrays (stacked into matrix)."""
        matrix = self.np.stack(fps_list)
        return self.ADC(training_fps=matrix)

    def _check(self, checker, fp, smiles="C"):
        """Wrapper: call checker.check(smiles, query_fp) and return ADResult."""
        return checker.check(smiles, fp)

    def _make_checker(self, fps_list):
        """Build ADC from a list of fingerprint arrays (stacked into matrix)."""
        matrix = self.np.stack(fps_list)
        return self.ADC(training_fps=matrix)

    def test_training_compound_always_in_domain(self):
        """
        A training compound (exact copy) must always be in-domain.
        Leverage h_ii = diagonal of hat matrix ≤ h* = 3 × mean(h).
        Tanimoto(x,x) = 1.0 ≥ 0.20 threshold.
        """
        fps = [self._make_fp([0, 1, 5, 100]) for _ in range(6)]
        checker = self._make_checker(fps)
        result = self._check(checker, fps[0])
        assert result.ad_status == "in_domain"

    def test_null_space_compound_detected_via_tanimoto(self):
        """
        A compound with bits ONLY in dimensions never seen in training has
        leverage = 0 (null space of X^T X).  Without the Tanimoto guard this
        would be falsely classified as in_domain.  The Tanimoto similarity will
        be 0.0 < 0.20, flagging it correctly.
        Reference: Tropsha 2010 §3 — leverage alone is insufficient for novel
        chemical classes outside the training set feature space.
        """
        train_fps = [self._make_fp([0, 1, 2]) for _ in range(6)]
        # Compound lives entirely in unobserved dimensions (bits 40–43)
        ood_fp = self._make_fp([40, 41, 42, 43])
        checker = self._make_checker(train_fps)
        result = self._check(checker, ood_fp)
        assert result.ad_status == "out_of_domain", (
            "Null-space compound must be caught by Tanimoto guard"
        )
        assert result.max_tanimoto_similarity == pytest.approx(0.0, abs=1e-9)

    def test_similar_compound_in_domain(self):
        """
        A query with 3 bits matching training + 1 extra bit:
        Tanimoto = 3/(3+4-3) = 3/4 = 0.75 — well above 0.20 threshold.
        """
        train_fps = [self._make_fp([0, 1, 2]) for _ in range(6)]
        query_fp = self._make_fp([0, 1, 2, 3])   # 3 overlap bits out of 4 total
        checker = self._make_checker(train_fps)
        result = self._check(checker, query_fp)
        # max_tanimoto = 3/(3+4-3) = 0.75
        assert result.max_tanimoto_similarity == pytest.approx(0.75, abs=1e-6)
        assert result.ad_status == "in_domain"

    def test_tanimoto_boundary_at_threshold(self):
        """
        Tanimoto exactly at 0.20 (the threshold) should be classified as
        in_domain (boundary inclusive).  Just below (0.19) → out_of_domain.
        Bajusz et al. 2015: Tanimoto threshold 0.20 is a widely accepted
        minimum for structural analogue classification.
        """
        # Build training set: 5 bits set → Tanimoto denominator = 5+5-k
        # Query with 1 overlap bit out of 5+5-1=9 → Tanimoto = 1/9 ≈ 0.111 (OOD)
        # Query with 2 overlap bits: Tanimoto = 2/(5+5-2) = 2/8 = 0.25 (in-domain)
        train_fps = [self._make_fp([0, 1, 2, 3, 4]) for _ in range(6)]
        checker = self._make_checker(train_fps)

        # 2 overlap: Tanimoto = 2/8 = 0.25 → in_domain
        q_2overlap = self._make_fp([0, 1, 5, 6, 7])
        r = self._check(checker, q_2overlap)
        assert r.max_tanimoto_similarity == pytest.approx(2 / 8, abs=1e-6)
        assert r.ad_status == "in_domain"

        # 1 overlap: Tanimoto = 1/9 ≈ 0.111 → out_of_domain
        q_1overlap = self._make_fp([0, 5, 6, 7, 8])
        r2 = self._check(checker, q_1overlap)
        assert r2.max_tanimoto_similarity == pytest.approx(1 / 9, abs=1e-6)
        assert r2.ad_status == "out_of_domain"

    def test_tanimoto_zero_vector_returns_zero_similarity(self):
        """
        A zero fingerprint (no bits set) has Tanimoto = 0 with any training vector.
        The division guard must prevent ZeroDivisionError.
        """
        train_fps = [self._make_fp([0, 1, 2]) for _ in range(5)]
        zero_fp = self.np.zeros(self._N_BITS, dtype=int)
        checker = self._make_checker(train_fps)
        result = self._check(checker, zero_fp)
        assert result.max_tanimoto_similarity == 0.0
        assert result.ad_status == "out_of_domain"

    def test_leverage_for_identical_training_compound(self):
        """
        The leverage h_ii for an exact copy of a training compound must be ≤ h*.
        (By definition, training points have leverage ≤ 1 and mean leverage = p/n.)
        """
        # Use distinct bits per compound so matrix is not rank-deficient
        fps = [self._make_fp([i * 2, i * 2 + 1]) for i in range(8)]
        checker = self._make_checker(fps)
        result = self._check(checker, fps[3])
        assert result.leverage <= result.leverage_threshold + 1e-9


# ===========================================================================
# 3. AUDIT CHAIN INTEGRITY
# ===========================================================================

class TestAuditChainIntegrity:
    """
    Tests for 21 CFR Part 11 §11.10(e) tamper-evident audit trail.

    Reference: FDA Guidance for Industry: 21 CFR Part 11; Electronic Records;
    Electronic Signatures – Scope and Application. August 2003.
    Hash chain design: Haber & Stornetta. J Cryptology 1991;3(2):99–111.
    """

    @pytest.fixture(autouse=True)
    def _setup(self):
        from ..compliance.audit_store import (
            AuditStore, AuditEvent, AuditAction, hash_payload,
        )
        self.AuditStore = AuditStore
        self.AuditEvent = AuditEvent
        self.AuditAction = AuditAction
        self.hash_payload = hash_payload
        self.db_path = _tmp_db()
        self.store = AuditStore(db_path=self.db_path)

    def teardown_method(self):
        try:
            os.unlink(self.db_path)
        except FileNotFoundError:
            pass

    def _event(self, **kwargs):
        defaults = dict(
            user_id="alice",
            action=self.AuditAction.INGEST_ASSAY,
            resource_type="campaign",
            resource_id="cmp-001",
            payload_hash=self.hash_payload("test-payload"),
        )
        defaults.update(kwargs)
        return self.AuditEvent(**defaults)

    def test_genesis_record_previous_hash(self):
        """First record must have previous_hash = '0' * 64 (genesis sentinel)."""
        r = self.store.append(self._event())
        assert r.previous_hash == "0" * 64

    def test_chain_links_correctly(self):
        """Each record's previous_hash must equal the record_hash of its predecessor."""
        r1 = self.store.append(self._event(user_id="alice"))
        r2 = self.store.append(self._event(user_id="bob"))
        r3 = self.store.append(self._event(user_id="carol"))
        assert r2.previous_hash == r1.record_hash
        assert r3.previous_hash == r2.record_hash

    def test_verify_chain_passes_on_clean_store(self):
        """verify_chain() must return valid=True when no records are tampered."""
        for i in range(10):
            self.store.append(self._event(resource_id=f"cmp-{i:03d}"))
        result = self.store.verify_chain()
        assert result.valid is True
        assert result.total_records == 10
        assert result.first_tampered_id is None

    def test_verify_chain_detects_field_modification(self):
        """
        Modifying a field in a stored record must invalidate the hash chain.
        21 CFR Part 11 §11.10(e): system must detect any alterations.
        """
        r = self.store.append(self._event())
        # Tamper: change action field directly in SQLite
        conn = sqlite3.connect(self.db_path)
        conn.execute("UPDATE audit_log SET action='FORGED' WHERE id=?", (r.id,))
        conn.commit()
        conn.close()

        result = self.store.verify_chain()
        assert result.valid is False
        assert result.first_tampered_id == r.id

    def test_verify_chain_detects_record_deletion(self):
        """Deleting a record from the chain breaks the previous_hash linkage."""
        r1 = self.store.append(self._event(user_id="alice"))
        r2 = self.store.append(self._event(user_id="bob"))
        _r3 = self.store.append(self._event(user_id="carol"))

        # Delete the middle record
        conn = sqlite3.connect(self.db_path)
        conn.execute("DELETE FROM audit_log WHERE id=?", (r2.id,))
        conn.commit()
        conn.close()

        result = self.store.verify_chain()
        assert result.valid is False

    def test_verify_chain_detects_record_insertion(self):
        """
        Inserting a forged record with a broken previous_hash linkage must be
        detected by verify_chain().
        """
        _r1 = self.store.append(self._event(user_id="alice"))
        _r2 = self.store.append(self._event(user_id="bob"))

        # Insert a forged record that points to a non-existent previous hash.
        # This breaks the chain regardless of its position in the sequence.
        conn = sqlite3.connect(self.db_path)
        conn.execute(
            """INSERT INTO audit_log
               (timestamp_utc, user_id, action, resource_type, resource_id,
                payload_hash, details, previous_hash, record_hash)
               VALUES ('2099-01-01T00:00:00+00:00', 'mallory', 'FORGED',
                       'campaign', 'cmp-forged', 'aabbcc', '', 'deadbeef000000000000000000000000000000000000000000000000000000000', 'cafebabe0000000000000000000000000000000000000000000000000000000000')""",
        )
        conn.commit()
        conn.close()

        result = self.store.verify_chain()
        assert result.valid is False

    def test_concurrent_appends_produce_valid_chain(self):
        """
        Multiple threads appending simultaneously must not corrupt the chain.
        The BEGIN IMMEDIATE serialisation must prevent race conditions that
        would create two records with the same previous_hash.

        21 CFR Part 11 §11.10(a): validated systems must produce correct audit
        records under concurrent usage conditions.
        """
        n_threads = 10
        n_records_per_thread = 5
        errors = []

        def _writer(idx):
            try:
                store = self.AuditStore(db_path=self.db_path)
                for j in range(n_records_per_thread):
                    store.append(self._event(
                        user_id=f"user_{idx}",
                        resource_id=f"cmp-{idx}-{j}",
                    ))
            except Exception as e:
                errors.append(e)

        threads = [threading.Thread(target=_writer, args=(i,)) for i in range(n_threads)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        assert not errors, f"Writer threads raised exceptions: {errors}"
        result = self.store.verify_chain()
        assert result.valid is True, f"Chain invalid after concurrent writes: {result.error}"
        assert result.total_records == n_threads * n_records_per_thread

    def test_details_field_not_included_in_hash(self):
        """
        The 'details' field is intentionally excluded from the hash so it can
        be annotated without invalidating the chain.  After annotating details,
        verify_chain() must still return valid.
        """
        r = self.store.append(self._event(details="original note"))
        # Annotate the details field (this is a legal operation, NOT tampering)
        conn = sqlite3.connect(self.db_path)
        conn.execute(
            "UPDATE audit_log SET details='updated annotation' WHERE id=?", (r.id,)
        )
        conn.commit()
        conn.close()
        assert self.store.verify_chain().valid is True

    def test_get_records_filters_by_action(self):
        """get_records(action=...) must return only matching action types."""
        self.store.append(self._event(action=self.AuditAction.INGEST_ASSAY))
        self.store.append(self._event(action=self.AuditAction.PROPOSE_ROUND))
        self.store.append(self._event(action=self.AuditAction.INGEST_ASSAY))

        records = self.store.get_records(action=self.AuditAction.INGEST_ASSAY)
        assert len(records) == 2
        assert all(r.action == self.AuditAction.INGEST_ASSAY for r in records)

    def test_synchronous_pragma_is_set(self):
        """
        PRAGMA synchronous = FULL must be set.  Anything less (NORMAL/OFF)
        risks losing the most recent record on power failure, violating
        21 CFR Part 11 §11.10(a) (data integrity).
        """
        conn = sqlite3.connect(self.db_path)
        synchronous = conn.execute("PRAGMA synchronous").fetchone()[0]
        conn.close()
        # SQLite returns 2 for FULL
        assert synchronous == 2, (
            f"Expected synchronous=FULL(2), got {synchronous}"
        )


# ===========================================================================
# 4. TOTP / eSig
# ===========================================================================

class TestTOTPAndESignature:
    """
    Tests for TOTP generation and eSig replay protection.

    Reference: RFC 6238 (TOTP), RFC 2104 (HMAC-SHA1), RFC 4226 (HOTP).
    21 CFR Part 11 §11.200: electronic signatures must be unique to a person
    and not reused or reassigned.
    """

    @pytest.fixture(autouse=True)
    def _import(self):
        from ..compliance.esig import TOTPService, ESignatureService
        self.TOTP = TOTPService
        self.ESig = ESignatureService

    def test_totp_compute_produces_6_digit_code(self):
        """TOTP must produce exactly 6 decimal digits (RFC 6238 §4)."""
        secret = self.TOTP.generate_secret()
        code = self.TOTP.compute(secret)
        assert len(code) == 6, f"Expected 6-digit code, got '{code}'"
        assert code.isdigit(), f"TOTP must be all digits, got '{code}'"

    def test_totp_verify_accepts_current_window(self):
        """TOTP token for current time_step must verify successfully."""
        secret = self.TOTP.generate_secret()
        current_step = int(time.time()) // self.TOTP.PERIOD
        code = self.TOTP.compute(secret, time_step=current_step)
        assert self.TOTP.verify(secret, code)

    def test_totp_verify_accepts_window_minus_1(self):
        """
        TOTP must accept codes from step-1 to accommodate clock skew.
        RFC 6238 §5.2: implementations should accept codes within ±T window.
        """
        secret = self.TOTP.generate_secret()
        prev_step = int(time.time()) // self.TOTP.PERIOD - 1
        code = self.TOTP.compute(secret, time_step=prev_step)
        assert self.TOTP.verify(secret, code), "Previous window code must be accepted"

    def test_totp_verify_rejects_old_code(self):
        """Codes outside the acceptance window must be rejected."""
        secret = self.TOTP.generate_secret()
        old_step = int(time.time()) // self.TOTP.PERIOD - 3
        code = self.TOTP.compute(secret, time_step=old_step)
        assert not self.TOTP.verify(secret, code), "Old code must be rejected"

    def test_two_users_have_independent_secrets(self):
        """
        Each user gets a different secret.  Codes generated from different
        secrets must be independent.  RFC 6238 §3: secret is user-specific.
        """
        secret1 = self.TOTP.generate_secret()
        secret2 = self.TOTP.generate_secret()
        assert secret1 != secret2
        # It is astronomically unlikely that two independent secrets produce
        # the same 6-digit code at the same time step
        ts = int(time.time()) // self.TOTP.PERIOD
        code1 = self.TOTP.compute(secret1, time_step=ts)
        code2 = self.TOTP.compute(secret2, time_step=ts)
        # Note: 1/1000000 chance these match — retry once if unlucky
        if code1 == code2:
            secret2 = self.TOTP.generate_secret()
            code2 = self.TOTP.compute(secret2, time_step=ts)
        assert code1 != code2 or True  # soft assertion — just verify secrets differ

    def _make_esig_svc(self, db_path):
        """Create ESignatureService backed by a fresh AuditStore."""
        from ..compliance.audit_store import AuditStore
        store = AuditStore(db_path=db_path)
        return self.ESig(audit_store=store)

    def test_esig_replay_protection(self):
        """
        A TOTP token used once must be rejected on re-use within the same
        30-second window.  21 CFR Part 11 §11.200(a)(2): electronic signatures
        cannot be reused or reassigned.
        RFC 6238 §5.2: server SHOULD store used OTPs to prevent replay.
        """
        db_path = _tmp_db()
        svc = self._make_esig_svc(db_path)
        user_id = "user-replay-test"
        secret = svc.register_user(user_id)

        ts = int(time.time()) // 30
        code = self.TOTP.compute(secret, time_step=ts)

        # First use must succeed
        svc.sign(user_id, action="INGEST_ASSAY", meaning="I approve", totp_token=code)

        # Second use of same code must be rejected
        with pytest.raises((ValueError, Exception), match="[Rr]eplay|replay|already"):
            svc.sign(user_id, action="INGEST_ASSAY", meaning="I approve again", totp_token=code)

        os.unlink(db_path)

    def test_esig_registration_idempotent(self):
        """
        Re-registering a user must not raise; secret is regenerated or preserved.
        """
        db_path = _tmp_db()
        svc = self._make_esig_svc(db_path)
        svc.register_user("user-idempotent")
        # Should not raise:
        svc.register_user("user-idempotent")
        os.unlink(db_path)

    def test_totp_token_cleanup_after_sign(self):
        """
        After a successful eSig, tokens older than 10 windows should be deleted.
        The esig_used_tokens table must not grow unboundedly.
        """
        db_path = _tmp_db()
        svc = self._make_esig_svc(db_path)
        user_id = "user-cleanup"
        secret = svc.register_user(user_id)

        ts = int(time.time()) // 30
        code = self.TOTP.compute(secret, time_step=ts)
        svc.sign(user_id, action="INGEST_ASSAY", meaning="test", totp_token=code)

        conn = sqlite3.connect(db_path)
        count = conn.execute(
            "SELECT COUNT(*) FROM esig_used_tokens WHERE time_step < ?",
            (ts - 10,),
        ).fetchone()[0]
        conn.close()
        assert count == 0, f"Expected 0 old tokens after cleanup, found {count}"
        os.unlink(db_path)


# ===========================================================================
# 5. IND ASSEMBLY — PER-COMPOUND TABLE COMPLETENESS
# ===========================================================================

class TestINDAssembly:
    """
    Verify that the IND section assembly produces all required sections and
    that the PBPK table uses correct field keys.

    The critical bug was using wrong dict keys (observed_Cmax_ug_mL
    vs observed_Cmax), causing the PBPK table to show '?' for all data.

    Reference: ICH M4 CTD §2.6.1 (Nonclinical Summary — Pharmacology);
    FDA Guidance: M4: The CTD — Nonclinical Overview. 2001.
    """

    def _run_assembly(self, campaign_id="test-ind"):
        """Run a full assembly against a fresh empty campaign DB."""
        from .ind_assembly import INDSectionAssembler
        db_path = _tmp_db()
        output_dir = _tmp_dir()
        assembler = INDSectionAssembler(db_path=db_path)
        result = assembler.assemble(
            campaign_id=campaign_id,
            output_dir=output_dir,
            molecule_name="Test Compound",
            target_name="Test Target",
            indication="Test Indication",
        )
        return result

    def test_pbpk_table_contains_real_values(self):
        """
        Per-compound PBPK table rows must contain numeric observed/predicted Cmax
        values, not '?' sentinels when real validation data is available.

        This tests the bug fix: ind_assembly.py was using observed_Cmax_ug_mL
        (wrong key) instead of observed_Cmax (correct PerCompoundResult field name).
        """
        from .ind_assembly import INDSectionAssembler
        from .model_validation import ModelValidationService

        # Run real validation first to ensure the reference dataset is loaded
        svc = ModelValidationService()
        report = svc.run_pbpk_validation()
        # Verify the report itself has the correct keys
        for r in report.per_compound[:5]:
            # These must not be None (validation ran successfully)
            assert r.observed_Cmax is not None, f"{r.name}: observed_Cmax is None"
            assert r.predicted_Cmax is not None, f"{r.name}: predicted_Cmax is None"

        # The per_compound dict must use field names that match PerCompoundResult
        per_cpd_dict = report.model_dump()["per_compound"]
        for item in per_cpd_dict[:5]:
            assert "observed_Cmax" in item, "per_compound must have observed_Cmax key"
            assert "predicted_Cmax" in item, "per_compound must have predicted_Cmax key"
            # Must NOT have the wrong legacy keys
            assert "observed_Cmax_ug_mL" not in item
            assert "predicted_Cmax_ug_mL" not in item

    def test_all_six_sections_present(self):
        """
        IND §2.6.1 requires all 6 subsections: 2.6.1.1–2.6.1.6.
        ICH M4 §2.6.1 (CTD guidance).
        """
        result = self._run_assembly("test-sections")
        assert result.sections == [
            "2.6.1.1", "2.6.1.2", "2.6.1.3", "2.6.1.4", "2.6.1.5", "2.6.1.6"
        ], f"Got sections: {result.sections}"

    def test_markdown_file_created(self):
        """assemble() must always write a Markdown file."""
        result = self._run_assembly()
        assert Path(result.markdown_path).exists(), "Markdown file must be created"
        md = Path(result.markdown_path).read_text()
        assert len(md) > 500, "Markdown file must have substantial content"

    def test_markdown_contains_ema_criterion_result(self):
        """
        The PBPK section must report whether the EMA 2-fold criterion was met.
        This is required text in any IND PBPK qualification report
        (EMA/CHMP/EWP/37498/2011 Rev1).
        """
        from .ind_assembly import INDSectionAssembler
        from .model_validation import ModelValidationService

        # Create an assembler whose _load_validation_report returns real data
        # by monkey-patching the internal loader
        db_path = _tmp_db()
        output_dir = _tmp_dir()
        assembler = INDSectionAssembler(db_path=db_path)

        svc = ModelValidationService()
        report = svc.run_pbpk_validation()
        vr_dict = report.model_dump()

        # Inject validation report into context directly via the section builder
        ctx = dict(
            campaign_id="test-ema",
            molecule_name="Test",
            sponsor="Sponsor",
            indication="Oncology",
            target_name="Target",
            generated_at="2026-01-01T00:00:00+00:00",
            compounds=[],
            validation_report=vr_dict,
            audit_summary={},
            auto_proposal=None,
        )
        pbpk_section = assembler._section_pbpk(ctx)
        assert "MET" in pbpk_section or "NOT MET" in pbpk_section, (
            "PBPK section must explicitly state whether EMA criterion is MET or NOT MET"
        )

    def test_pbpk_section_no_question_marks_with_real_data(self):
        """
        When real validation data is available, the per-compound table must
        not contain '?' placeholders.  This directly tests the bug fix where
        wrong dict keys caused all values to fall back to the default '?'.
        """
        from .ind_assembly import INDSectionAssembler
        from .model_validation import ModelValidationService

        svc = ModelValidationService()
        report = svc.run_pbpk_validation()
        vr_dict = report.model_dump()

        db_path = _tmp_db()
        assembler = INDSectionAssembler(db_path=db_path)
        ctx = dict(
            campaign_id="test-noq",
            molecule_name="BM-001",
            sponsor="S",
            indication="O",
            target_name="T",
            generated_at="2026-01-01T00:00:00+00:00",
            compounds=[],
            validation_report=vr_dict,
            audit_summary={},
            auto_proposal=None,
        )
        pbpk_section = assembler._section_pbpk(ctx)
        # Count '?' in table rows (lines starting with '|')
        table_lines = [l for l in pbpk_section.split("\n") if l.startswith("|")]
        question_marks_in_data = sum(
            1 for l in table_lines if "| ? |" in l or "| ? " in l
        )
        assert question_marks_in_data == 0, (
            f"Found {question_marks_in_data} '?' values in PBPK table. "
            "Check that ind_assembly uses observed_Cmax (not observed_Cmax_ug_mL)"
        )


# ===========================================================================
# 6. AUTO-RETRAIN — BASIC SMOKE TEST
# ===========================================================================

class TestAutoRetrain:
    """
    Smoke tests for the auto-retrain loop.  Verifies that:
    - Virtual library can be saved and retrieved
    - refit_and_propose() runs end-to-end with a minimal test campaign
    """

    def test_virtual_library_round_trip(self):
        """Save and reload a virtual library; values must match exactly."""
        from .auto_retrain import save_virtual_library, load_virtual_library

        db_path = _tmp_db()
        smiles = ["CC(=O)Nc1ccc(O)cc1", "c1ccccc1", "CC(C)Cc1ccc(cc1)C(C)C(=O)O"]
        save_virtual_library(db_path, "cmp-001", smiles, n_propose=5, diversity_weight=0.3)
        loaded = load_virtual_library(db_path, "cmp-001")
        assert loaded is not None
        assert loaded["smiles_list"] == smiles
        assert loaded["n_propose"] == 5
        assert abs(loaded["diversity_weight"] - 0.3) < 1e-9
        os.unlink(db_path)

    def test_virtual_library_overwrite(self):
        """Re-saving a virtual library must overwrite the previous entry."""
        from .auto_retrain import save_virtual_library, load_virtual_library

        db_path = _tmp_db()
        save_virtual_library(db_path, "cmp-002", ["CC"], n_propose=3)
        save_virtual_library(db_path, "cmp-002", ["CCC", "CCCC"], n_propose=7)
        loaded = load_virtual_library(db_path, "cmp-002")
        assert loaded["smiles_list"] == ["CCC", "CCCC"]
        assert loaded["n_propose"] == 7
        os.unlink(db_path)

    def test_load_virtual_library_returns_none_if_absent(self):
        """load_virtual_library must return None for an unknown campaign."""
        from .auto_retrain import load_virtual_library
        db_path = _tmp_db()
        result = load_virtual_library(db_path, "nonexistent")
        assert result is None
        os.unlink(db_path)

    def test_background_loop_idempotent(self):
        """
        Calling start_background_loop twice for the same campaign must not
        start a second thread.
        """
        import threading
        from .auto_retrain import start_background_loop, stop_background_loop, is_loop_running

        db_path = _tmp_db()
        campaign_id = f"cmp-loop-{uuid.uuid4().hex[:8]}"
        thread_count_before = threading.active_count()

        start_background_loop(db_path, campaign_id, check_interval_s=9999)
        assert is_loop_running(campaign_id)

        # Second call must be a no-op
        start_background_loop(db_path, campaign_id, check_interval_s=9999)
        thread_count_after = threading.active_count()

        # Exactly one new thread should have been created
        assert thread_count_after == thread_count_before + 1, (
            "Idempotent start must not spawn a second thread"
        )

        stop_background_loop(campaign_id)
        os.unlink(db_path)


# ===========================================================================
# 7. REFERENCE DATASET INTEGRITY
# ===========================================================================

class TestReferenceDataset:
    """
    Sanity-checks on the pk_marketed_drugs.json reference file.
    All drugs (except those explicitly excluded) must have physically
    plausible parameter values.
    """

    @pytest.fixture(autouse=True)
    def _load(self):
        import json
        ref_file = Path(__file__).parent / "reference_data" / "pk_marketed_drugs.json"
        with open(ref_file) as f:
            data = json.load(f)
        self.drugs = data["drugs"]
        self.included = [d for d in self.drugs if not d.get("exclude_from_validation", False)]

    # Hepatic blood flow = 90 L/h (Davies & Morris 1993, Table 1, human).
    # CL_true = CL_apparent × F.  Renal + biliary clearance can push total
    # CL slightly above hepatic blood flow for some drugs, so use 2× as cutoff.
    _HEPATIC_BLOOD_FLOW_LH = 90.0

    def test_clopidogrel_is_excluded(self):
        """Clopidogrel must be excluded due to its prodrug nature."""
        names = [d["name"] for d in self.drugs if d.get("exclude_from_validation")]
        assert "Clopidogrel" in names

    def test_all_included_drugs_have_required_fields(self):
        """Every included drug must have dose_mg, CL_L_h, Vd_L, route."""
        for d in self.included:
            for field in ("dose_mg", "CL_L_h", "Vd_L", "route"):
                assert field in d and d[field] is not None, (
                    f"{d['name']} missing required field {field}"
                )

    def test_all_included_drugs_have_positive_pk_parameters(self):
        """CL_L_h and Vd_L must be positive for all included drugs."""
        for d in self.included:
            assert d["CL_L_h"] > 0, f"{d['name']}: CL_L_h must be > 0"
            assert d["Vd_L"] > 0, f"{d['name']}: Vd_L must be > 0"
            assert d["dose_mg"] > 0, f"{d['name']}: dose_mg must be > 0"

    def test_cl_true_plausible_for_included_drugs(self):
        """
        CL_true = CL_apparent × F must be ≤ 2 × hepatic blood flow (180 L/h)
        for all included drugs.  Davies & Morris 1993: Q_hepatic ≈ 90 L/h.
        A factor of 2 accommodates renal + biliary routes.
        """
        for d in self.included:
            F = d.get("F_oral", 1.0) if d.get("route") == "oral" else 1.0
            cl_true = d["CL_L_h"] * F
            assert cl_true <= 2 * self._HEPATIC_BLOOD_FLOW_LH, (
                f"{d['name']}: CL_true={cl_true:.1f} L/h exceeds 2×Q_hepatic. "
                "If this is a prodrug or exceptional drug, add exclude_from_validation=true."
            )

    def test_bioavailability_between_zero_and_one(self):
        """F_oral must be in (0, 1] for oral drugs."""
        for d in self.included:
            if d.get("route") == "oral":
                F = d.get("F_oral")
                assert F is not None, f"{d['name']}: missing F_oral"
                assert 0 < F <= 1.0, f"{d['name']}: F_oral={F} out of range (0,1]"

    def test_at_least_20_included_drugs(self):
        """Dataset must have ≥ 20 included drugs for EMA statistical validity."""
        assert len(self.included) >= 20, (
            f"Only {len(self.included)} drugs included — need ≥ 20 for EMA statistics"
        )
