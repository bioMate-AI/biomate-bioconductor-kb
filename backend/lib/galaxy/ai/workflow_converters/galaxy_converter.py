"""
Galaxy Workflow Converter

Bidirectional conversion between Galaxy .ga format and BioMate Unified Workflow Format.

Functions:
- GalaxyToUnifiedConverter: Galaxy .ga → BUWF
- UnifiedToGalaxyConverter: BUWF → Galaxy .ga

Author: BioMate Team
Date: 2025-11-19
"""

import json
import logging
from typing import Dict, List, Any, Optional
from pathlib import Path

from .base_converter import BaseConverter
from ..workflow_abstraction import (
    UnifiedWorkflow, HighLevelStep, DetailedStep,
    DataInput, DataOutput, Parameter,
    WorkflowFormat, ExecutionEngine, ParameterType,
    generate_step_id, generate_workflow_id
)

log = logging.getLogger(__name__)


class GalaxyToUnifiedConverter(BaseConverter):
    """
    Convert Galaxy .ga workflow to BioMate Unified Workflow Format.

    Strategy:
    1. Parse .ga JSON
    2. Extract metadata (name, creator, license, etc.)
    3. Parse workflow steps
    4. Group steps into high-level steps (for UI presentation)
    5. Build unified workflow structure

    The key challenge is grouping fine-grained Galaxy tool steps into
    meaningful high-level steps. We use multiple strategies:
    - Tool function patterns (e.g., QC tools → QC step)
    - Annotations and labels
    - Sequential tool patterns
    """

    def __init__(self, tool_database=None):
        """
        Initialize converter.

        Args:
            tool_database: Optional tool database for looking up tool metadata
        """
        self.tool_database = tool_database

    def convert(self, galaxy_workflow: Dict[str, Any]) -> UnifiedWorkflow:
        """
        Convert Galaxy .ga workflow to UnifiedWorkflow.

        Args:
            galaxy_workflow: Galaxy .ga JSON (as dict)

        Returns:
            UnifiedWorkflow instance
        """

        # 1. Validate input
        is_valid, errors = self.validate(galaxy_workflow)
        if not is_valid:
            raise ValueError(f"Invalid Galaxy workflow: {', '.join(errors)}")

        # 2. Extract metadata
        metadata = self._extract_metadata(galaxy_workflow)

        # 3. Parse all Galaxy steps
        galaxy_steps = galaxy_workflow.get("steps", {})
        parsed_steps = self._parse_galaxy_steps(galaxy_steps)

        # 4. Group into high-level steps (initially one-to-one mapping)
        # Note: Apply group_workflow_steps() from workflow_grouper.py for intelligent grouping
        high_level_steps = self._create_simple_high_level_steps(parsed_steps)

        # 5. Build unified workflow
        workflow = UnifiedWorkflow(
            workflow_id=generate_workflow_id(),
            name=metadata["name"],
            description=metadata["annotation"],
            high_level_steps=high_level_steps,
            source_format=WorkflowFormat.GALAXY,
            execution_engine=ExecutionEngine.GALAXY,
            creator=metadata.get("creator", []),
            license=metadata.get("license", "MIT"),
            tags=metadata.get("tags", []),
            version=str(metadata.get("version", "1.0")),
            source_workflow=galaxy_workflow
        )

        # Log conversion stats
        self._log_conversion_stats(workflow)

        return workflow

    def validate(self, galaxy_workflow: Dict[str, Any]) -> tuple[bool, list[str]]:
        """
        Validate Galaxy workflow structure.

        Args:
            galaxy_workflow: Galaxy .ga JSON

        Returns:
            (is_valid, error_messages)
        """
        errors = []

        # Check required fields
        if not isinstance(galaxy_workflow, dict):
            errors.append("Workflow must be a dictionary")
            return (False, errors)

        if "a_galaxy_workflow" not in galaxy_workflow:
            errors.append("Missing 'a_galaxy_workflow' field")

        if "steps" not in galaxy_workflow:
            errors.append("Missing 'steps' field")

        # Validate steps structure
        steps = galaxy_workflow.get("steps", {})
        if not isinstance(steps, dict):
            errors.append("'steps' must be a dictionary")
        else:
            for step_id, step in steps.items():
                if not isinstance(step, dict):
                    errors.append(f"Step {step_id} must be a dictionary")
                elif "type" not in step:
                    errors.append(f"Step {step_id} missing 'type' field")

        return (len(errors) == 0, errors)

    def _extract_metadata(self, galaxy_workflow: Dict[str, Any]) -> Dict[str, Any]:
        """Extract workflow metadata."""
        return {
            "name": galaxy_workflow.get("name", "Unnamed Workflow"),
            "annotation": galaxy_workflow.get("annotation", ""),
            "creator": galaxy_workflow.get("creator", []),
            "license": galaxy_workflow.get("license", "MIT"),
            "tags": galaxy_workflow.get("tags", []),
            "version": galaxy_workflow.get("version", 1),
            "format_version": galaxy_workflow.get("format-version", "0.1")
        }

    def _parse_galaxy_steps(
        self,
        galaxy_steps: Dict[str, Dict[str, Any]]
    ) -> List[DetailedStep]:
        """
        Parse Galaxy workflow steps into DetailedStep objects.

        Args:
            galaxy_steps: Galaxy workflow steps dict

        Returns:
            List of DetailedStep objects (sorted by step ID)
        """
        detailed_steps = []

        # Sort steps by ID to maintain order
        sorted_step_ids = sorted(galaxy_steps.keys(), key=int)

        for step_id in sorted_step_ids:
            step = galaxy_steps[step_id]
            step_type = step.get("type", "")

            # Skip input steps (they'll be handled as workflow inputs)
            if step_type in ("data_input", "data_collection_input", "parameter_input"):
                continue

            # Parse tool step
            if step_type == "tool":
                detailed_step = self._parse_tool_step(step_id, step)
                if detailed_step:
                    detailed_steps.append(detailed_step)

            # Parse subworkflow step
            elif step_type == "subworkflow":
                detailed_step = self._parse_subworkflow_step(step_id, step)
                if detailed_step:
                    detailed_steps.append(detailed_step)

        return detailed_steps

    def _parse_tool_step(
        self,
        step_id: str,
        step: Dict[str, Any]
    ) -> Optional[DetailedStep]:
        """
        Parse a Galaxy tool step.

        Args:
            step_id: Galaxy step ID
            step: Galaxy step dict

        Returns:
            DetailedStep or None
        """
        tool_id = step.get("tool_id", "")
        if not tool_id:
            log.warning(f"Step {step_id} has no tool_id")
            return None

        # Extract tool name from step or tool_id
        tool_name = step.get("name") or step.get("label") or self._extract_tool_name(tool_id)

        # Parse inputs
        inputs = self._parse_step_inputs(step)

        # Parse outputs
        outputs = self._parse_step_outputs(step)

        # Parse parameters from tool_state
        parameters = self._parse_tool_parameters(step)

        # Create detailed step
        detailed_step = DetailedStep(
            step_id=generate_step_id("detailed"),
            tool_id=tool_id,
            tool_name=tool_name,
            tool_version=step.get("tool_version", ""),
            description=step.get("annotation", ""),
            parameters=parameters,
            inputs=inputs,
            outputs=outputs,
            annotation=step.get("annotation", ""),
            label=step.get("label", ""),
            source_step_id=str(step_id),
            source_format=WorkflowFormat.GALAXY
        )

        # Try to extract container info from tool database
        if self.tool_database:
            tool_info = self.tool_database.get_tool_info(tool_id)
            if tool_info:
                detailed_step.container = tool_info.get("container", "")

        return detailed_step

    def _parse_subworkflow_step(
        self,
        step_id: str,
        step: Dict[str, Any]
    ) -> Optional[DetailedStep]:
        """
        Parse a Galaxy subworkflow step.

        For now, treat as a single detailed step.
        In the future, we could recursively parse the subworkflow.
        """
        subworkflow = step.get("subworkflow", {})
        name = subworkflow.get("name", "Subworkflow")

        return DetailedStep(
            step_id=generate_step_id("detailed"),
            tool_id=f"subworkflow_{step_id}",
            tool_name=name,
            description=subworkflow.get("annotation", ""),
            annotation=step.get("annotation", ""),
            label=step.get("label", ""),
            source_step_id=str(step_id),
            source_format=WorkflowFormat.GALAXY
        )

    def _parse_step_inputs(self, step: Dict[str, Any]) -> List[DataInput]:
        """
        Parse step inputs from input_connections.

        Args:
            step: Galaxy step dict

        Returns:
            List of DataInput objects
        """
        inputs = []
        input_connections = step.get("input_connections", {})

        for input_name, connection in input_connections.items():
            # Handle both single connection and multiple connections
            if isinstance(connection, dict):
                connections = [connection]
            elif isinstance(connection, list):
                connections = connection
            else:
                continue

            for conn in connections:
                source_step = conn.get("id")
                source_output = conn.get("output_name", "")

                inputs.append(DataInput(
                    name=input_name,
                    source=f"step_{source_step}.{source_output}"
                ))

        return inputs

    def _parse_step_outputs(self, step: Dict[str, Any]) -> List[DataOutput]:
        """
        Parse step outputs.

        Args:
            step: Galaxy step dict

        Returns:
            List of DataOutput objects
        """
        outputs = []
        workflow_outputs = step.get("workflow_outputs", [])

        # Galaxy workflow_outputs format: list of {output_name: str, label: str}
        for wo in workflow_outputs:
            if isinstance(wo, dict):
                output_name = wo.get("output_name", "")
                label = wo.get("label", output_name)

                outputs.append(DataOutput(
                    name=output_name,
                    description=label,
                    is_workflow_output=True
                ))

        return outputs

    def _parse_tool_parameters(
        self,
        step: Dict[str, Any]
    ) -> Dict[str, Parameter]:
        """
        Parse tool parameters from tool_state.

        Galaxy tool_state is a JSON-encoded string containing tool parameters.

        Args:
            step: Galaxy step dict

        Returns:
            Dict of Parameter objects
        """
        parameters = {}
        tool_state = step.get("tool_state", "{}")

        # Parse JSON tool_state
        try:
            if isinstance(tool_state, str):
                state = json.loads(tool_state)
            else:
                state = tool_state

            # Convert to Parameter objects
            for param_name, param_value in state.items():
                # Skip internal Galaxy fields
                if param_name.startswith("__"):
                    continue

                # Determine parameter type
                param_type = self._infer_parameter_type(param_value)

                parameters[param_name] = Parameter(
                    name=param_name,
                    type=param_type,
                    value=param_value
                )

        except json.JSONDecodeError:
            log.warning(f"Failed to parse tool_state for step {step.get('id')}")

        return parameters

    def _infer_parameter_type(self, value: Any) -> ParameterType:
        """Infer parameter type from value."""
        if isinstance(value, bool):
            return ParameterType.BOOLEAN
        elif isinstance(value, int):
            return ParameterType.INTEGER
        elif isinstance(value, float):
            return ParameterType.FLOAT
        elif isinstance(value, str):
            return ParameterType.STRING
        elif isinstance(value, dict):
            # Galaxy often uses dicts for complex parameters
            return ParameterType.STRING
        else:
            return ParameterType.STRING

    def _extract_tool_name(self, tool_id: str) -> str:
        """
        Extract human-readable tool name from tool ID.

        Examples:
        - toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.72 → FastQC
        - STAR_ALIGN → STAR Align
        """
        # Remove ToolShed prefix
        if "/" in tool_id:
            parts = tool_id.split("/")
            # Usually format: .../repos/owner/tool_name/tool_id/version
            if len(parts) >= 3:
                tool_name = parts[-2]
            else:
                tool_name = parts[-1]
        else:
            tool_name = tool_id

        # Clean up name
        tool_name = tool_name.replace("_", " ").replace("-", " ")
        tool_name = tool_name.title()

        return tool_name

    def _create_simple_high_level_steps(
        self,
        detailed_steps: List[DetailedStep]
    ) -> List[HighLevelStep]:
        """
        Create simple high-level steps (one detailed step per high-level step).

        This is a placeholder until we implement intelligent grouping.

        Args:
            detailed_steps: List of DetailedStep objects

        Returns:
            List of HighLevelStep objects
        """
        high_level_steps = []

        for idx, detailed_step in enumerate(detailed_steps):
            high_level_step = HighLevelStep(
                step_id=generate_step_id("hl"),
                name=detailed_step.tool_name,
                description=detailed_step.description,
                detailed_steps=[detailed_step],
                inputs=detailed_step.inputs,
                outputs=detailed_step.outputs,
                parameters=detailed_step.parameters,
                order=idx
            )
            high_level_steps.append(high_level_step)

        return high_level_steps


class UnifiedToGalaxyConverter(BaseConverter):
    """
    Convert BioMate Unified Workflow to Galaxy .ga format.

    Strategy:
    1. Flatten high-level steps into individual tool steps
    2. Generate Galaxy step IDs and connections
    3. Map tool IDs to Galaxy ToolShed format
    4. Generate .ga JSON
    """

    def convert(self, unified_workflow: UnifiedWorkflow) -> Dict[str, Any]:
        """
        Convert UnifiedWorkflow to Galaxy .ga JSON.

        Args:
            unified_workflow: UnifiedWorkflow instance

        Returns:
            Galaxy .ga JSON (as dict)
        """

        # 1. Validate input
        is_valid, errors = unified_workflow.validate()
        if not is_valid:
            raise ValueError(f"Invalid unified workflow: {', '.join(errors)}")

        # 2. Build Galaxy workflow structure
        galaxy_workflow = {
            "a_galaxy_workflow": "true",
            "format-version": "0.1",
            "name": unified_workflow.name,
            "annotation": unified_workflow.description,
            "tags": unified_workflow.tags,
            "license": unified_workflow.license,
            "version": unified_workflow.version,
            "steps": {}
        }

        # Add creator if available
        if unified_workflow.creator:
            galaxy_workflow["creator"] = unified_workflow.creator

        # 3. Generate Galaxy steps from detailed steps
        step_id = 0
        step_id_mapping = {}  # Map DetailedStep.step_id → Galaxy step_id

        for hl_step in unified_workflow.high_level_steps:
            for detailed_step in hl_step.detailed_steps:
                galaxy_step = self._convert_to_galaxy_step(
                    detailed_step,
                    step_id,
                    step_id_mapping
                )
                galaxy_workflow["steps"][str(step_id)] = galaxy_step
                step_id_mapping[detailed_step.step_id] = step_id
                step_id += 1

        log.info(f"Converted unified workflow to Galaxy format: {len(galaxy_workflow['steps'])} steps")

        return galaxy_workflow

    def validate(self, unified_workflow: UnifiedWorkflow) -> tuple[bool, list[str]]:
        """
        Validate unified workflow before conversion.

        Args:
            unified_workflow: UnifiedWorkflow to validate

        Returns:
            (is_valid, error_messages)
        """
        return unified_workflow.validate()

    def _convert_to_galaxy_step(
        self,
        detailed_step: DetailedStep,
        step_id: int,
        step_id_mapping: Dict[str, int]
    ) -> Dict[str, Any]:
        """
        Convert DetailedStep to Galaxy step format.

        Args:
            detailed_step: DetailedStep to convert
            step_id: Galaxy step ID
            step_id_mapping: Mapping of DetailedStep IDs to Galaxy step IDs

        Returns:
            Galaxy step dict
        """

        # Build input connections
        input_connections = {}
        for input_data in detailed_step.inputs:
            if input_data.source:
                # Parse source format: "step_X.output_name"
                if "." in input_data.source:
                    source_step_ref, output_name = input_data.source.split(".", 1)
                    # Extract source step ID
                    if source_step_ref.startswith("step_"):
                        source_step_id_str = source_step_ref[5:]  # Remove "step_" prefix
                        # Look up in mapping
                        # For now, assume direct mapping
                        input_connections[input_data.name] = {
                            "id": source_step_id_str,
                            "output_name": output_name
                        }

        # Build workflow outputs
        workflow_outputs = []
        for output in detailed_step.outputs:
            if output.is_workflow_output:
                workflow_outputs.append({
                    "output_name": output.name,
                    "label": output.description or output.name
                })

        # Encode tool parameters
        tool_state = self._encode_tool_state(detailed_step.parameters)

        # Build Galaxy step
        galaxy_step = {
            "id": step_id,
            "type": "tool",
            "tool_id": detailed_step.tool_id,
            "tool_version": detailed_step.tool_version,
            "name": detailed_step.tool_name,
            "annotation": detailed_step.annotation,
            "label": detailed_step.label,
            "tool_state": tool_state,
            "input_connections": input_connections,
            "workflow_outputs": workflow_outputs,
            "position": {
                "left": step_id * 220 + 10,
                "top": 10
            }
        }

        return galaxy_step

    def _encode_tool_state(self, parameters: Dict[str, Parameter]) -> str:
        """
        Encode parameters as Galaxy tool_state JSON string.

        Args:
            parameters: Dict of Parameter objects

        Returns:
            JSON-encoded tool_state string
        """
        state = {}
        for param_name, param in parameters.items():
            state[param_name] = param.value

        return json.dumps(state)
