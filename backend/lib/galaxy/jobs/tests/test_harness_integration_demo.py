"""
Test Harness Integration Demo

Demonstrates the complete test harness flow:
1. Pre-execution validation
2. Pilot execution
3. QC validation
4. Parameter tuning
5. Retry with optimized parameters
"""

import logging
from pathlib import Path
from typing import Dict, Any

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

log = logging.getLogger(__name__)


def demo_cryo_em_spa_harness():
    """
    Demonstrate Cryo-EM SPA workflow validation with test harness.
    """
    log.info("=" * 80)
    log.info("TEST HARNESS INTEGRATION DEMO: Cryo-EM SPA Workflow")
    log.info("=" * 80)

    try:
        from galaxy.jobs.runtime_input_validators.cryo_em_harness import CryoEMSPAHarness

        # Workflow path (use actual path if available)
        backend_dir = Path(__file__).parent.parent.parent.parent.parent
        workflow_path = backend_dir / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / "cryo_em" / "spa_full_pipeline" / "main.nf"

        if not workflow_path.exists():
            log.warning(f"Workflow not found: {workflow_path}")
            log.info("Using mock workflow path for demo")
            workflow_path = Path("/mock/workflow/main.nf")

        # Workflow parameters
        parameters = {
            "voltage": 300,  # 300 kV (valid)
            "pixel_size": 1.08,  # 1.08 Å/pixel
            "movies_dir": "/data/cryo_em/movies",
            "mock_mode": True,  # Enable mock mode for demo
            "symmetry": "C1",
            "particle_diameter": 150
        }

        # Create mock app for demo
        class MockApp:
            pass

        app = MockApp()

        # Initialize test harness
        log.info("\n[1] Initializing test harness...")
        harness = CryoEMSPAHarness(
            workflow_path=str(workflow_path),
            parameters=parameters,
            app=app,
            enable_pilot=True,  # Enable pilot execution
            max_pilot_retries=2  # Allow up to 2 retries
        )

        log.info(f"  Workflow: {workflow_path}")
        log.info(f"  Parameters: {len(parameters)} params")
        log.info(f"  Pilot: enabled (max 2 retries)")

        # Run full validation
        log.info("\n[2] Running full validation...")
        report = harness.run_full_validation()

        # Display results
        log.info("\n" + "=" * 80)
        log.info("VALIDATION REPORT")
        log.info("=" * 80)

        # Pre-execution checks
        log.info(f"\n[Pre-execution Validation]")
        log.info(f"  Total checks: {len(report.pre_execution_checks)}")
        for check in report.pre_execution_checks:
            status_symbol = {
                "passed": "✓",
                "failed": "✗",
                "warning": "⚠",
                "skipped": "-"
            }.get(check.status.value, "?")
            log.info(f"  {status_symbol} {check.message}")

        # Pilot results
        if report.pilot_result:
            log.info(f"\n[Pilot Execution]")
            log.info(f"  Completed: {report.pilot_result.pilot_completed}")
            log.info(f"  QC Passed: {report.pilot_result.qc_passed}")
            log.info(f"  Retry Count: {report.pilot_result.retry_count}")

            if report.pilot_result.error_message:
                log.error(f"  Error: {report.pilot_result.error_message}")

            if report.pilot_result.failed_processes:
                log.info(f"  Failed Processes:")
                for proc in report.pilot_result.failed_processes:
                    log.info(f"    - {proc}")

            if report.pilot_result.parameter_suggestions:
                log.info(f"  Parameter Suggestions:")
                for param, value in report.pilot_result.parameter_suggestions.items():
                    log.info(f"    - {param}: {value}")

        # Final status
        log.info(f"\n[Final Status]")
        log.info(f"  Validation Passed: {'YES ✓' if report.validation_passed else 'NO ✗'}")

        if report.final_parameters:
            log.info(f"  Final Parameters: {len(report.final_parameters)} params")
            # Show any optimized parameters
            optimized = {
                k: v for k, v in report.final_parameters.items()
                if k not in parameters or parameters[k] != v
            }
            if optimized:
                log.info(f"  Optimized Parameters:")
                for param, value in optimized.items():
                    original = parameters.get(param, "N/A")
                    log.info(f"    - {param}: {original} → {value}")

        # Recommendations
        if report.recommendations:
            log.info(f"\n[Recommendations]")
            for rec in report.recommendations:
                log.info(f"  • {rec}")

        log.info("\n" + "=" * 80)

        return report

    except ImportError as e:
        log.error(f"Import error: {e}")
        log.error("Make sure test harness components are available")
        raise
    except Exception as e:
        log.error(f"Demo failed: {e}", exc_info=True)
        raise


def demo_rna_seq_harness():
    """
    Demonstrate RNA-Seq workflow validation with test harness.
    """
    log.info("\n\n" + "=" * 80)
    log.info("TEST HARNESS INTEGRATION DEMO: RNA-Seq Workflow")
    log.info("=" * 80)

    try:
        from galaxy.jobs.runtime_input_validators.genomics_harness import RNASeqWorkflowHarness

        # Workflow path
        backend_dir = Path(__file__).parent.parent.parent.parent.parent
        workflow_path = backend_dir / "biomni_workflows" / "nextflow_nfcore" / "subworkflows" / "genomics" / "rnaseq" / "main.nf"

        if not workflow_path.exists():
            workflow_path = Path("/mock/rnaseq_workflow/main.nf")

        # Workflow parameters
        parameters = {
            "fastq_dir": "/data/rnaseq/fastq",
            "genome_reference": "/refs/hg38.fa",
            "star_index": "/refs/hg38_star",
            "mock_mode": True,
            "threads": 8
        }

        # Create mock app
        class MockApp:
            pass

        app = MockApp()

        # Initialize harness
        log.info("\n[1] Initializing RNA-Seq test harness...")
        harness = RNASeqWorkflowHarness(
            workflow_path=str(workflow_path),
            parameters=parameters,
            app=app,
            enable_pilot=True,
            max_pilot_retries=1
        )

        # Run validation
        log.info("\n[2] Running validation...")
        report = harness.run_full_validation()

        # Display results
        log.info("\n" + "=" * 80)
        log.info("VALIDATION REPORT")
        log.info("=" * 80)
        log.info(f"  Validation Passed: {'YES ✓' if report.validation_passed else 'NO ✗'}")
        log.info(f"  Pre-execution checks: {len(report.pre_execution_checks)}")

        if report.pilot_result:
            log.info(f"  Pilot completed: {report.pilot_result.pilot_completed}")
            log.info(f"  QC passed: {report.pilot_result.qc_passed}")

        log.info("=" * 80)

        return report

    except Exception as e:
        log.error(f"Demo failed: {e}", exc_info=True)
        raise


if __name__ == "__main__":
    log.info("\n")
    log.info("╔" + "=" * 78 + "╗")
    log.info("║" + " " * 20 + "TEST HARNESS INTEGRATION DEMO" + " " * 28 + "║")
    log.info("╚" + "=" * 78 + "╝")

    # Run demos
    try:
        # Demo 1: Cryo-EM SPA
        cryo_em_report = demo_cryo_em_spa_harness()

        # Demo 2: RNA-Seq
        rnaseq_report = demo_rna_seq_harness()

        # Summary
        log.info("\n\n" + "=" * 80)
        log.info("DEMO COMPLETE")
        log.info("=" * 80)
        log.info(f"  Cryo-EM SPA: {'PASSED ✓' if cryo_em_report.validation_passed else 'FAILED ✗'}")
        log.info(f"  RNA-Seq: {'PASSED ✓' if rnaseq_report.validation_passed else 'FAILED ✗'}")
        log.info("=" * 80)

        log.info("\n✓ Test harness integration demo completed successfully!")
        log.info("\nNext steps:")
        log.info("  1. Connect to actual pilot API (remove mock mode)")
        log.info("  2. Test with real workflows")
        log.info("  3. Verify QC calculators work with real outputs")
        log.info("  4. Validate parameter optimization improves results")

    except Exception as e:
        log.error(f"\n✗ Demo failed: {e}")
        raise
