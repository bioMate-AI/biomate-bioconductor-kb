"""
BUWF Serialization Utilities

Functions for serializing BioMate Unified Workflow Format (BUWF) to/from JSON.
Used by both API endpoints and testing scripts.
"""

from typing import Dict, Any
from ..workflow_abstraction import UnifiedWorkflow


def serialize_buwf(workflow: UnifiedWorkflow) -> Dict[str, Any]:
    """
    Serialize BUWF workflow to JSON-compatible dict.

    Args:
        workflow: UnifiedWorkflow object

    Returns:
        JSON-serializable dictionary with all workflow data
    """
    return {
        "workflow_id": workflow.workflow_id,
        "name": workflow.name,
        "description": workflow.description,
        "source_format": workflow.source_format.value,
        "execution_engine": workflow.execution_engine.value,
        "creator": workflow.creator,
        "license": workflow.license,
        "tags": workflow.tags,
        "high_level_steps": [
            {
                "step_id": step.step_id,
                "name": step.name,
                "description": step.description,
                "category": step.category.value,
                "icon": step.icon,
                "color": step.color,
                "order": step.order,
                "detailed_steps": [
                    {
                        "step_id": det.step_id,
                        "tool_id": det.tool_id,
                        "tool_name": det.tool_name,
                        "tool_version": det.tool_version,
                        "container": det.container,
                        "cpu": det.cpu,
                        "memory": det.memory,
                        "runtime_estimate": det.runtime_estimate,
                        "inputs": [
                            {
                                "name": inp.name,
                                "data_type": inp.data_type,
                                "format": inp.format,
                                "optional": inp.optional,
                                "description": inp.description
                            }
                            for inp in det.inputs
                        ],
                        "outputs": [
                            {
                                "name": out.name,
                                "data_type": out.data_type,
                                "format": out.format,
                                "description": out.description
                            }
                            for out in det.outputs
                        ],
                        "parameters": {
                            name: {
                                "name": param.name,
                                "type": param.type.value,
                                "value": param.value,
                                "required": param.required,
                                "default": param.default
                            }
                            for name, param in det.parameters.items()
                        }
                    }
                    for det in step.detailed_steps
                ],
                "inputs": [
                    {
                        "name": inp.name,
                        "data_type": inp.data_type,
                        "format": inp.format,
                        "optional": inp.optional,
                        "description": inp.description
                    }
                    for inp in step.inputs
                ],
                "outputs": [
                    {
                        "name": out.name,
                        "data_type": out.data_type,
                        "format": out.format,
                        "description": out.description
                    }
                    for out in step.outputs
                ]
            }
            for step in workflow.high_level_steps
        ]
    }


def deserialize_buwf(data: Dict[str, Any]) -> UnifiedWorkflow:
    """
    Deserialize JSON dict to BUWF workflow object.

    Args:
        data: JSON dictionary with workflow data

    Returns:
        UnifiedWorkflow object
    """
    import json
    return UnifiedWorkflow.from_json(json.dumps(data))
