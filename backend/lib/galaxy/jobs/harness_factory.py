"""
Factory for creating appropriate test harness based on workflow type.
"""

import logging
from pathlib import Path
from typing import Dict, Any, Optional

log = logging.getLogger(__name__)


def get_harness_for_workflow(
    workflow_path: str,
    parameters: Dict[str, Any],
    app: Any,
    enable_pilot: bool = True,
    max_pilot_retries: int = 2
):
    """
    Factory function to create the appropriate test harness for a workflow.

    Args:
        workflow_path: Path to the workflow file
        parameters: Workflow parameters
        app: Galaxy app instance
        enable_pilot: Whether to enable pilot runs
        max_pilot_retries: Maximum number of pilot retries

    Returns:
        Instance of appropriate harness subclass, or None if no harness available
    """
    workflow_path_obj = Path(workflow_path)

    # Determine harness type based on workflow path
    try:
        # Cryo-EM workflows
        if 'cryo_em' in str(workflow_path) or 'cryosparc' in str(workflow_path).lower():
            from galaxy.jobs.runtime_input_validators.cryo_em_harness import CryoEMSPAHarness
            log.info(f"Creating CryoEMSPAHarness for workflow: {workflow_path}")
            return CryoEMSPAHarness(
                workflow_path=workflow_path,
                parameters=parameters,
                app=app,
                enable_pilot=enable_pilot,
                max_pilot_retries=max_pilot_retries
            )

        # RNA-Seq workflows
        elif 'rnaseq' in str(workflow_path).lower() or 'rna_seq' in str(workflow_path):
            from galaxy.jobs.runtime_input_validators.genomics_harness import RNASeqWorkflowHarness
            log.info(f"Creating RNASeqWorkflowHarness for workflow: {workflow_path}")
            return RNASeqWorkflowHarness(
                workflow_path=workflow_path,
                parameters=parameters,
                app=app,
                enable_pilot=enable_pilot,
                max_pilot_retries=max_pilot_retries
            )

        # ChIP-Seq workflows
        elif 'chipseq' in str(workflow_path).lower() or 'chip_seq' in str(workflow_path):
            from galaxy.jobs.runtime_input_validators.genomics_harness import ChIPSeqWorkflowHarness
            log.info(f"Creating ChIPSeqWorkflowHarness for workflow: {workflow_path}")
            return ChIPSeqWorkflowHarness(
                workflow_path=workflow_path,
                parameters=parameters,
                app=app,
                enable_pilot=enable_pilot,
                max_pilot_retries=max_pilot_retries
            )

        # ATAC-Seq workflows
        elif 'atacseq' in str(workflow_path).lower() or 'atac_seq' in str(workflow_path):
            from galaxy.jobs.runtime_input_validators.genomics_harness import ATACSeqWorkflowHarness
            log.info(f"Creating ATACSeqWorkflowHarness for workflow: {workflow_path}")
            return ATACSeqWorkflowHarness(
                workflow_path=workflow_path,
                parameters=parameters,
                app=app,
                enable_pilot=enable_pilot,
                max_pilot_retries=max_pilot_retries
            )

        else:
            log.warning(f"No specific harness available for workflow: {workflow_path}")
            log.info("Using BaseWorkflowTestHarness with generic validation")
            from galaxy.jobs.workflow_test_harness import BaseWorkflowTestHarness
            return BaseWorkflowTestHarness(
                workflow_path=workflow_path,
                parameters=parameters,
                app=app,
                enable_pilot=enable_pilot,
                max_pilot_retries=max_pilot_retries
            )

    except ImportError as e:
        log.error(f"Failed to import harness class: {e}")
        return None
    except Exception as e:
        log.error(f"Failed to create harness: {e}")
        return None
