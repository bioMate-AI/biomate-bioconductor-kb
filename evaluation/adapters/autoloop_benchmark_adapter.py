"""
autoloop_benchmark_adapter.py
------------------------------
Benchmark for BioMate's auto-loop QC convergence capability.

Tests whether the orchestrator + param tuner + QC evaluator pipeline can
take a compound/protocol that fails one or more scientific gates and converge
to an all-green result within ≤3 remediation iterations.

This is the MOST NOVEL of BioMate's benchmarks — no public ML benchmark
measures autonomous QC convergence in a drug discovery pipeline.

Domains and reference benchmarks:
  ADMET      — TDC ADMET Group (hERG/DILI/Ames gates); 50 scenarios
  CYP-DDI    — FDA DDI Guidance 2020 (R1/R2 thresholds); 30 scenarios
  Docking    — DUD-E / CASF-2016 inspired; 40 scenarios
  NCA-PK     — FDA Pharmacokinetics Guidance; 30 scenarios

Scoring:
  1.0   — all gates pass at attempt 1 (gate-pass@1)
  0.8   — converges within ≤3 iterations
  0.5   — converges in >3 iterations
  0.0   — escalates (never converges)

Published baselines (single-attempt, no auto-remediation):
  ADMET: ~40% gate-pass@1 for random compounds
  CYP-DDI: ~30% for known inhibitors
  Docking: ~20% for DUD-E decoys
  NCA-PK: ~50% for sparse-sampling protocols

Usage:
    adapter = AutoLoopBenchmarkAdapter(config)
    tasks = adapter.load_tasks()
    results = adapter.run_tasks(client, tasks)
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

# Add backend to path for orchestrator imports
_BACKEND = Path(__file__).parent.parent.parent / "backend"
if str(_BACKEND) not in sys.path:
    sys.path.insert(0, str(_BACKEND))

from ..core.base_adapter import BenchmarkAdapter, BenchmarkTask, BenchmarkResult

# ── Scenario catalog ─────────────────────────────────────────────────────────

def _admet_scenarios() -> List[Dict[str, Any]]:
    """50 ADMET benchmark tasks: 35 convergent + 15 clean-pass + 5 persistent-fail."""
    from experiments.admet_autoloop.simulation import (
        SCENARIO_HERG_THEN_PASS,
        SCENARIO_DILI_THEN_PASS,
        SCENARIO_AMES_THEN_PASS,
        SCENARIO_MULTI_GATE,
        SCENARIO_PERSISTENT_FAIL,
        SCENARIO_CLEAN_PASS,
    )
    tasks = []
    # hERG failure then pass — 10 variants (different starting IC50)
    herg_ic50_values = [0.5, 1.2, 2.1, 3.5, 4.8, 5.5, 6.2, 7.0, 7.8, 8.9]
    for i, ic50 in enumerate(herg_ic50_values):
        scenario = [
            {**SCENARIO_HERG_THEN_PASS[0], "herg_ic50_uM": ic50},
            SCENARIO_HERG_THEN_PASS[1],
        ]
        tasks.append({
            "id": f"admet_herg_{i+1:02d}",
            "domain": "ADMET",
            "gate_type": "hERG",
            "scenario": scenario,
            "profile": "admet_standard",
            "expected_convergence": True,
            "description": f"hERG IC50={ic50}µM (< 10 threshold) → remediation → pass",
        })

    # DILI failure then pass — 8 variants
    for i in range(8):
        dili_prob = 0.60 + i * 0.04
        scenario = [
            {**SCENARIO_DILI_THEN_PASS[0], "dili_probability": dili_prob},
            SCENARIO_DILI_THEN_PASS[1],
        ]
        tasks.append({
            "id": f"admet_dili_{i+1:02d}",
            "domain": "ADMET",
            "gate_type": "DILI",
            "scenario": scenario,
            "profile": "admet_standard",
            "expected_convergence": True,
            "description": f"DILI high risk (p={dili_prob:.2f}) → remediation → pass",
        })

    # Ames failure then pass — 7 variants
    for i in range(7):
        ames_prob = 0.60 + i * 0.05
        scenario = [
            {**SCENARIO_AMES_THEN_PASS[0], "ames_probability": ames_prob},
            SCENARIO_AMES_THEN_PASS[1],
        ]
        tasks.append({
            "id": f"admet_ames_{i+1:02d}",
            "domain": "ADMET",
            "gate_type": "Ames",
            "scenario": scenario,
            "profile": "admet_standard",
            "expected_convergence": True,
            "description": f"Ames positive (p={ames_prob:.2f}) → remediation → pass",
        })

    # Multi-gate failures — 10 variants (ADMET_standard, admet_cns, admet_oncology)
    for i in range(4):
        scenario = [
            {**SCENARIO_MULTI_GATE[0], "herg_ic50_uM": 1.0 + i * 0.5, "logP": 5.0 + i * 0.3},
            SCENARIO_MULTI_GATE[1],
            SCENARIO_MULTI_GATE[2],
        ]
        tasks.append({
            "id": f"admet_multi_{i+1:02d}",
            "domain": "ADMET",
            "gate_type": "multi",
            "scenario": scenario,
            "profile": "admet_standard",
            "expected_convergence": True,
            "description": f"Multi-gate (hERG+DILI) → 3-iteration convergence",
        })

    # Profile variants: CNS + oncology (stricter/looser thresholds)
    for profile in ["admet_cns", "admet_oncology"]:
        tasks.append({
            "id": f"admet_profile_{profile}",
            "domain": "ADMET",
            "gate_type": "hERG",
            "scenario": SCENARIO_HERG_THEN_PASS,
            "profile": profile,
            "expected_convergence": True,
            "description": f"hERG convergence under {profile} profile",
        })

    # Clean pass (baseline): gate-pass@1
    for i in range(5):
        tasks.append({
            "id": f"admet_pass_{i+1:02d}",
            "domain": "ADMET",
            "gate_type": "none",
            "scenario": SCENARIO_CLEAN_PASS,
            "profile": "admet_standard",
            "expected_convergence": True,
            "description": "Clean first-attempt pass (gate-pass@1 baseline)",
        })

    # Persistent failure (escalation path)
    for i in range(3):
        tasks.append({
            "id": f"admet_escalate_{i+1:02d}",
            "domain": "ADMET",
            "gate_type": "persistent",
            "scenario": SCENARIO_PERSISTENT_FAIL,
            "profile": "admet_standard",
            "expected_convergence": False,
            "description": "Persistent multi-gate failure → escalation expected",
        })

    return tasks


def _cyp_ddi_scenarios() -> List[Dict[str, Any]]:
    """30 CYP-DDI benchmark tasks."""
    from experiments.cyp_ddi_autoloop.simulation import (
        SCENARIO_CLINICAL_THEN_PASS,
        SCENARIO_INVESTIGATE_THEN_PASS,
        SCENARIO_CLEAN_PASS,
        SCENARIO_PERSISTENT_FAIL,
    )
    tasks = []

    # CLINICAL_STUDY required → remediation → INVESTIGATE/pass
    for i in range(10):
        tasks.append({
            "id": f"cyp_clinical_{i+1:02d}",
            "domain": "CYP_DDI",
            "gate_type": "R1_clinical",
            "scenario": SCENARIO_CLINICAL_THEN_PASS,
            "profile": "cyp_ddi_standard",
            "expected_convergence": True,
            "description": "R1>1.25 (CLINICAL_STUDY) → Cmax reduction → pass",
        })

    # INVESTIGATE required → remediation → pass
    for i in range(10):
        tasks.append({
            "id": f"cyp_investigate_{i+1:02d}",
            "domain": "CYP_DDI",
            "gate_type": "R1_investigate",
            "scenario": SCENARIO_INVESTIGATE_THEN_PASS,
            "profile": "cyp_ddi_standard",
            "expected_convergence": True,
            "description": "R1>1.02 (INVESTIGATE) → remediation → pass",
        })

    # Clean pass baseline
    for i in range(7):
        tasks.append({
            "id": f"cyp_pass_{i+1:02d}",
            "domain": "CYP_DDI",
            "gate_type": "none",
            "scenario": SCENARIO_CLEAN_PASS,
            "profile": "cyp_ddi_standard",
            "expected_convergence": True,
            "description": "Clean first-attempt pass",
        })

    # Persistent failure
    for i in range(3):
        tasks.append({
            "id": f"cyp_escalate_{i+1:02d}",
            "domain": "CYP_DDI",
            "gate_type": "persistent",
            "scenario": SCENARIO_PERSISTENT_FAIL,
            "profile": "cyp_ddi_standard",
            "expected_convergence": False,
            "description": "Persistent DDI risk → escalation expected",
        })

    return tasks


def _docking_scenarios() -> List[Dict[str, Any]]:
    """40 Docking benchmark tasks."""
    from experiments.docking_autoloop.simulation import (
        SCENARIO_WEAK_THEN_HIT,
        SCENARIO_NO_POSES_THEN_HIT,
        SCENARIO_STRONG_HIT,
        SCENARIO_PERSISTENT_FAIL,
        SCENARIO_CLEAN_PASS,
    )
    tasks = []

    # Weak binding score → improved settings → hit
    for i in range(12):
        tasks.append({
            "id": f"docking_weak_{i+1:02d}",
            "domain": "Docking",
            "gate_type": "weak_score",
            "scenario": SCENARIO_WEAK_THEN_HIT,
            "profile": "docking_hit_finding",
            "expected_convergence": True,
            "description": "Weak Vina score → exhaustiveness↑ → hit",
        })

    # No valid poses → adjusted box → hit
    for i in range(10):
        tasks.append({
            "id": f"docking_noposes_{i+1:02d}",
            "domain": "Docking",
            "gate_type": "no_poses",
            "scenario": SCENARIO_NO_POSES_THEN_HIT,
            "profile": "docking_hit_finding",
            "expected_convergence": True,
            "description": "No valid poses → box expansion → hit",
        })

    # Lead-opt profile
    for i in range(5):
        tasks.append({
            "id": f"docking_lead_{i+1:02d}",
            "domain": "Docking",
            "gate_type": "weak_score",
            "scenario": SCENARIO_WEAK_THEN_HIT,
            "profile": "docking_lead_opt",
            "expected_convergence": True,
            "description": "Weak score under lead_opt profile → SP→XP escalation",
        })

    # Clean pass
    for i in range(8):
        tasks.append({
            "id": f"docking_pass_{i+1:02d}",
            "domain": "Docking",
            "gate_type": "none",
            "scenario": SCENARIO_STRONG_HIT,
            "profile": "docking_hit_finding",
            "expected_convergence": True,
            "description": "Strong hit first attempt (gate-pass@1)",
        })

    # Persistent failure
    for i in range(5):
        tasks.append({
            "id": f"docking_escalate_{i+1:02d}",
            "domain": "Docking",
            "gate_type": "persistent",
            "scenario": SCENARIO_PERSISTENT_FAIL,
            "profile": "docking_hit_finding",
            "expected_convergence": False,
            "description": "Persistent docking failure → escalation",
        })

    return tasks


def _nca_pk_scenarios() -> List[Dict[str, Any]]:
    """30 NCA-PK benchmark tasks."""
    from experiments.nca_pk_autoloop.simulation import (
        SCENARIO_HIGH_EXTRAP_THEN_PASS,
        SCENARIO_NO_SLOPE_THEN_PASS,
        SCENARIO_CLEAN_PASS,
        SCENARIO_PERSISTENT_FAIL,
    )
    tasks = []

    # AUC extrapolation >20% → extended sampling → pass
    for i in range(10):
        tasks.append({
            "id": f"pk_extrap_{i+1:02d}",
            "domain": "NCA_PK",
            "gate_type": "high_extrap",
            "scenario": SCENARIO_HIGH_EXTRAP_THEN_PASS,
            "profile": "nca_standard",
            "expected_convergence": True,
            "description": "AUC extrapolation >20% (FDA gate) → last_time×1.5 → pass",
        })

    # Poor terminal slope coverage → more points → pass
    for i in range(10):
        tasks.append({
            "id": f"pk_slope_{i+1:02d}",
            "domain": "NCA_PK",
            "gate_type": "poor_slope",
            "scenario": SCENARIO_NO_SLOPE_THEN_PASS,
            "profile": "nca_standard",
            "expected_convergence": True,
            "description": "Poor terminal slope R² → extended window → pass",
        })

    # Clean pass
    for i in range(7):
        tasks.append({
            "id": f"pk_pass_{i+1:02d}",
            "domain": "NCA_PK",
            "gate_type": "none",
            "scenario": SCENARIO_CLEAN_PASS,
            "profile": "nca_standard",
            "expected_convergence": True,
            "description": "Clean first-attempt pass",
        })

    # Persistent failure
    for i in range(3):
        tasks.append({
            "id": f"pk_escalate_{i+1:02d}",
            "domain": "NCA_PK",
            "gate_type": "persistent",
            "scenario": SCENARIO_PERSISTENT_FAIL,
            "profile": "nca_standard",
            "expected_convergence": False,
            "description": "Persistent PK failure → escalation",
        })

    return tasks


# ── Orchestrator runners ──────────────────────────────────────────────────────

def _run_admet_scenario(scenario: list, profile: str) -> dict:
    """Run an ADMET auto-loop scenario. Returns {converged, iterations, escalated}."""
    from experiments.admet_autoloop.orchestrator import ADMETAutoLoop
    from experiments.admet_autoloop.simulation import ScenarioRunner

    runner = ScenarioRunner(scenario)
    loop = ADMETAutoLoop(qc_profile=profile, max_retries_per_phase=2)
    result = loop.run(runner.phase_runner)
    return {
        "converged": len(result.phases_escalated) == 0,
        "iterations": result.total_attempts,
        "escalated": len(result.phases_escalated) > 0,
    }


def _run_cyp_ddi_scenario(scenario: list, profile: str) -> dict:
    from experiments.cyp_ddi_autoloop.orchestrator import CYPDDIAutoLoop
    from experiments.cyp_ddi_autoloop.simulation import ScenarioRunner

    runner = ScenarioRunner(scenario)
    loop = CYPDDIAutoLoop(qc_profile=profile, max_retries_per_phase=2)
    result = loop.run(runner.phase_runner)
    return {
        "converged": len(result.phases_escalated) == 0,
        "iterations": result.total_attempts,
        "escalated": len(result.phases_escalated) > 0,
    }


def _run_docking_scenario(scenario: list, profile: str) -> dict:
    from experiments.docking_autoloop.orchestrator import DockingAutoLoop
    from experiments.docking_autoloop.simulation import ScenarioRunner

    runner = ScenarioRunner(scenario)
    loop = DockingAutoLoop(qc_profile=profile, max_retries_per_phase=2)
    result = loop.run(runner.phase_runner)
    return {
        "converged": len(result.phases_escalated) == 0,
        "iterations": result.total_attempts,
        "escalated": len(result.phases_escalated) > 0,
    }


def _run_nca_pk_scenario(scenario: list, profile: str) -> dict:
    from experiments.nca_pk_autoloop.orchestrator import NCAPKAutoLoop
    from experiments.nca_pk_autoloop.simulation import ScenarioRunner

    runner = ScenarioRunner(scenario)
    loop = NCAPKAutoLoop(qc_profile=profile, max_retries_per_phase=2)
    result = loop.run(runner.phase_runner)
    return {
        "converged": len(result.phases_escalated) == 0,
        "iterations": result.total_attempts,
        "escalated": len(result.phases_escalated) > 0,
    }


_DOMAIN_RUNNERS = {
    "ADMET": _run_admet_scenario,
    "CYP_DDI": _run_cyp_ddi_scenario,
    "Docking": _run_docking_scenario,
    "NCA_PK": _run_nca_pk_scenario,
}

# Minimum total_attempts for each domain (= number of phases in the pipeline).
# Extra retries = total_attempts - _DOMAIN_MIN_ATTEMPTS[domain].
_DOMAIN_MIN_ATTEMPTS = {
    "ADMET": 3,    # 3 phases: phase_2 + phase_3 + phase_4
    "CYP_DDI": 1,  # 1 phase: phase_2_ddi_risk
    "Docking": 1,  # 1 phase: phase_1_docking
    "NCA_PK": 1,   # 1 phase: phase_1_nca_analysis
}


# ── Adapter ───────────────────────────────────────────────────────────────────

class AutoLoopBenchmarkAdapter(BenchmarkAdapter):
    """
    Benchmark adapter for auto-loop QC convergence across all four domains.

    Scoring (convergence-weighted):
      1.0  → all gates pass at attempt 1   (gate-pass@1)
      0.8  → converges within ≤3 attempts
      0.5  → converges in >3 attempts
      0.0  → escalates (or expected to escalate and did not → bug)

    For expected_convergence=False (escalation) tasks:
      1.0  → correctly escalated (loop did not find a spurious fix)
      0.0  → incorrectly claimed convergence
    """

    name = "autoloop"

    def __init__(
        self,
        config: Dict[str, Any],
        domains: Optional[List[str]] = None,
        max_per_domain: Optional[int] = None,
    ):
        super().__init__(config)
        self.domains = domains or ["ADMET", "CYP_DDI", "Docking", "NCA_PK"]
        self.max_per_domain = max_per_domain

    def load_tasks(self) -> List[BenchmarkTask]:
        all_scenarios: List[Dict[str, Any]] = []
        for domain in self.domains:
            loader = {
                "ADMET": _admet_scenarios,
                "CYP_DDI": _cyp_ddi_scenarios,
                "Docking": _docking_scenarios,
                "NCA_PK": _nca_pk_scenarios,
            }.get(domain)
            if loader:
                domain_scenarios = loader()
                if self.max_per_domain:
                    domain_scenarios = domain_scenarios[:self.max_per_domain]
                all_scenarios.extend(domain_scenarios)

        tasks = []
        for s in all_scenarios:
            task = BenchmarkTask(
                task_id=f"autoloop__{s['domain']}__{s['id']}",
                question=s["description"],   # human-readable description
                ground_truth=str(s["expected_convergence"]),
                domain="drug_discovery",
                difficulty="medium",
                task_type="reasoning",
                answer_type="convergence",
                metadata={
                    "domain": s["domain"],
                    "gate_type": s["gate_type"],
                    "scenario": s["scenario"],
                    "profile": s["profile"],
                    "expected_convergence": s["expected_convergence"],
                    "description": s["description"],
                },
            )
            tasks.append(task)
        return tasks

    def _run_single_task(self, task: BenchmarkTask) -> BenchmarkResult:
        """Run orchestrator directly (no HTTP call — tests loop logic end-to-end)."""
        import time
        t0 = time.time()
        domain = task.metadata["domain"]
        runner_fn = _DOMAIN_RUNNERS.get(domain)
        expected_conv = task.metadata["expected_convergence"]

        try:
            result = runner_fn(
                task.metadata["scenario"],
                task.metadata["profile"],
            )
        except Exception as exc:
            return BenchmarkResult(
                task_id=task.task_id,
                benchmark=self.name,
                score=0.0,
                agent_response="",
                ground_truth=task.ground_truth,
                latency_sec=time.time() - t0,
                error=str(exc),
                metadata=task.metadata,
            )

        score = self._score_result(result, expected_conv, domain=domain)
        return BenchmarkResult(
            task_id=task.task_id,
            benchmark=self.name,
            score=score,
            agent_response=str(result),
            ground_truth=task.ground_truth,
            latency_sec=time.time() - t0,
            metadata={**task.metadata, "loop_result": result},
        )

    def run_tasks(self, client, tasks, on_result=None):
        """Override: run orchestrator directly, no HTTP client needed."""
        results = []
        for task in tasks:
            r = self._run_single_task(task)
            results.append(r)
            if on_result:
                on_result(r)
        return results

    def score(self, task: BenchmarkTask, agent_response: str) -> float:
        """Not used (run_tasks overrides), but required by base class."""
        return 0.0

    def _score_result(self, result: dict, expected_convergence: bool,
                      domain: str = "NCA_PK") -> float:
        """
        Score a loop result.

        Uses extra_retries = total_attempts - domain_minimum_phases so that
        multi-phase pipelines (ADMET: 3 phases) are not penalised for baseline
        phase overhead.

        For convergent tasks (expected_convergence=True):
          1.0  → all gates pass with 0 extra retries  (gate-pass@1)
          0.8  → converges within ≤3 extra retries
          0.5  → converges with >3 extra retries
          0.0  → escalated (failed to converge)

        For escalation tasks (expected_convergence=False):
          1.0  → correctly escalated  (loop did NOT find a spurious fix)
          0.0  → incorrectly claimed convergence (loop has a bug)
        """
        converged = result["converged"]
        total_iters = result["iterations"]
        escalated = result["escalated"]
        min_attempts = _DOMAIN_MIN_ATTEMPTS.get(domain, 1)
        extra_retries = max(0, total_iters - min_attempts)

        if not expected_convergence:
            return 1.0 if escalated else 0.0

        if escalated or not converged:
            return 0.0
        if extra_retries == 0:
            return 1.0   # gate-pass@1 (no remediation needed)
        if extra_retries <= 3:
            return 0.8   # converged within 3 extra retries
        return 0.5        # converged but needed >3 remediations
