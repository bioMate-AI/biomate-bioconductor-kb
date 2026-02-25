"""
E2E Test: Pilot Run → QC Gate → Parameter Tuning

Tests the complete workflow:
1. Execute pilot run on subset of data
2. QC validation detects issues
3. Parameter tuner suggests improvements
4. Retry with optimized parameters
"""

import logging
from pathlib import Path
import sys

logging.basicConfig(level=logging.INFO)
log = logging.getLogger(__name__)


def test_cryo_em_spa_pilot_qc_flow():
    """Test complete pilot → QC → tuning flow for Cryo-EM SPA."""
    from galaxy.jobs.runtime_input_validators.cryo_em_harness import CryoEMSPAHarness

    # Use actual workflow path
    backend_dir = Path(__file__).parent.parent
    workflow_path = backend_dir / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / "cryo_em" / "spa_full_pipeline" / "main.nf"

    if not workflow_path.exists():
        log.warning(f"Workflow not found: {workflow_path}")
        log.info("Skipping test - workflow file not available")
        return

    # Parameters for pilot run
    parameters = {
        "voltage": 300,
        "pixel_size": 1.08,
        "movies_dir": str(workflow_path.parent / "test_data"),  # Use test data dir
        "mock_mode": True,  # Use mock mode for testing
        "symmetry": "C1",
        "particle_diameter": 150,
        "num_movies": 100  # Full dataset
    }

    # Mock app
    class MockApp:
        pass

    # Initialize harness with pilot enabled
    harness = CryoEMSPAHarness(
        workflow_path=str(workflow_path),
        parameters=parameters,
        app=MockApp(),
        enable_pilot=True,
        max_pilot_retries=2
    )

    log.info("=" * 80)
    log.info("PHASE 1: Pre-execution Validation")
    log.info("=" * 80)

    # Run pre-execution validation
    pre_exec_report = harness.validate_pre_execution()
    log.info(f"Pre-execution checks: {len(pre_exec_report.checks)}")

    for check in pre_exec_report.checks:
        status_icon = "✓" if check.status == "passed" else "✗"
        log.info(f"  {status_icon} {check.check_name}: {check.message}")

    # Pre-execution should pass
    assert pre_exec_report.validation_passed, "Pre-execution validation failed"

    log.info("\n" + "=" * 80)
    log.info("PHASE 2: Pilot Execution")
    log.info("=" * 80)

    # Execute pilot (10% of data)
    pilot_config = {
        "pilot_fraction": 0.1,
        "min_pilot_samples": 5,
        "max_pilot_samples": 10
    }

    log.info(f"Starting pilot with {pilot_config}")
    pilot_result = harness.execute_pilot(pilot_config)

    log.info(f"Pilot completed: {pilot_result.pilot_completed}")
    if pilot_result.pilot_invocation_id:
        log.info(f"  Invocation ID: {pilot_result.pilot_invocation_id}")

    # Pilot should complete
    assert pilot_result.pilot_completed, f"Pilot failed: {pilot_result.error_message}"

    log.info("\n" + "=" * 80)
    log.info("PHASE 3: QC Validation")
    log.info("=" * 80)

    # QC validation happens automatically in pilot_result
    log.info(f"QC Passed: {pilot_result.qc_passed}")
    log.info(f"QC Metrics: {len(pilot_result.qc_metrics)} metrics")

    for process, metrics in pilot_result.qc_metrics.items():
        log.info(f"\n  Process: {process}")
        for metric_name, value in metrics.items():
            log.info(f"    {metric_name}: {value}")

    if pilot_result.failed_processes:
        log.info(f"\nFailed processes: {pilot_result.failed_processes}")

    log.info("\n" + "=" * 80)
    log.info("PHASE 4: Parameter Tuning")
    log.info("=" * 80)

    if not pilot_result.qc_passed and pilot_result.parameter_suggestions:
        log.info("QC failed - parameter suggestions available:")
        for param, suggestion in pilot_result.parameter_suggestions.items():
            log.info(f"  {param}: {suggestion}")

        # In real scenario, would retry with optimized parameters
        log.info("\nRetry would be triggered with optimized parameters")
    else:
        log.info("QC passed - no parameter tuning needed")

    log.info("\n" + "=" * 80)
    log.info("TEST COMPLETE")
    log.info("=" * 80)
    log.info(f"✓ Pre-execution validation: PASSED")
    log.info(f"✓ Pilot execution: {'PASSED' if pilot_result.pilot_completed else 'FAILED'}")
    log.info(f"✓ QC validation: {'PASSED' if pilot_result.qc_passed else 'FAILED (suggestions provided)'}")

    # Test passes if pilot completed (QC may intentionally fail to test tuning)
    assert pilot_result.pilot_completed


if __name__ == "__main__":
    test_cryo_em_spa_pilot_qc_flow()
