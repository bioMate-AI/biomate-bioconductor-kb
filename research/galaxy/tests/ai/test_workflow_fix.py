#!/usr/bin/env python3

import json
import sys
import os

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

from galaxy.ai.workflow_generator import WorkflowGenerator
from galaxy.ai.config import DEFAULT_AI_CONFIG
from galaxy.ai.types import WorkflowStep, WorkflowTemplate

def test_workflow_input_fix():
    """
    Test the fix for workflow_input_X connection error.
    
    This test replicates the exact scenario that causes the error:
    1. RAG workflow with input steps that are filtered out during cleaning
    2. Tool steps that reference these input steps via temporary workflow_input_X markers
    3. Export to Galaxy format should properly reconnect without errors
    """
    
    print("🧪 Testing workflow input connection fix...")
    
    # Step 1: Create a scenario that mimics the RAG workflow structure
    print("\n1️⃣ Creating test workflow with input step connections...")
    
    # Simulate cleaned workflow steps with workflow_input_X markers
    # This represents what happens after _clean_input_connections() runs
    workflow_steps = [
        WorkflowStep(
            step_id=1,  # Original step ID from RAG workflow
            tool_id="toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
            tool_version="0.72+galaxy1",
            input_connections={
                'input_file': {
                    'id': 'workflow_input_4',  # This is the problematic marker
                    'output_name': 'output',
                    '_original_input_step': 4,  # Original input step ID
                    '_input_label': 'Input Dataset'
                }
            },
            parameters={'contaminants': None, 'adapters': None},
            annotation="FastQC step",
            position={'left': 100, 'top': 100}
        ),
        WorkflowStep(
            step_id=2,
            tool_id="toolshed.g2.bx.psu.edu/repos/iuc/multiqc/multiqc/1.11+galaxy0",
            tool_version="1.11+galaxy0",
            input_connections={
                'results_0|software_cond|input': {
                    'id': 1,  # References previous tool step
                    'output_name': 'html_file'
                }
            },
            parameters={'title': '', 'comment': ''},
            annotation="MultiQC step",
            position={'left': 300, 'top': 100}
        )
    ]
    
    # Create workflow inputs (these would normally be created during cleaning)
    workflow_inputs = [
        {
            'label': 'Input Dataset',
            'name': 'input_4',
            'type': 'data',
            'format': 'fastqsanger',
            'optional': False,
            'description': 'Raw sequencing data for quality control analysis'
        }
    ]
    
    # Create workflow template
    workflow_template = WorkflowTemplate(
        name="FastQC Quality Control Analysis",
        description="Quality control analysis workflow using FastQC and MultiQC",
        steps=workflow_steps,
        inputs=workflow_inputs,
        outputs=[],
        tags=['quality-control', 'fastqc', 'multiqc']
    )
    
    print(f"✓ Created workflow template with {len(workflow_steps)} steps and {len(workflow_inputs)} inputs")
    
    # Step 2: Export to Galaxy format using the fixed export function
    print("\n2️⃣ Exporting to Galaxy format...")
    
    try:
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
        
        print(f"✅ Export successful! Galaxy workflow has {len(galaxy_workflow['steps'])} total steps")
        
    except Exception as export_error:
        print(f"❌ Export failed with error: {export_error}")
        return False
    
    # Step 3: Validate the exported workflow structure
    print("\n3️⃣ Validating exported workflow structure...")
    
    # Check that all steps have valid IDs
    step_ids = list(galaxy_workflow['steps'].keys())
    print(f"✓ Step IDs in exported workflow: {step_ids}")
    
    # Check that no workflow_input_X markers remain
    workflow_input_markers = []
    for step_id, step_data in galaxy_workflow['steps'].items():
        input_connections = step_data.get('input_connections', {})
        for input_name, connection in input_connections.items():
            if isinstance(connection, dict):
                conn_id = connection.get('id')
                if isinstance(conn_id, str) and conn_id.startswith('workflow_input_'):
                    workflow_input_markers.append(f"Step {step_id}.{input_name} -> {conn_id}")
    
    if workflow_input_markers:
        print(f"❌ Found remaining workflow_input_ markers: {workflow_input_markers}")
        return False
    else:
        print("✅ No workflow_input_ markers found - all connections properly resolved")
    
    # Check that input steps were created
    input_steps = [step for step_id, step in galaxy_workflow['steps'].items() 
                  if step.get('tool_id') is None]
    print(f"✓ Found {len(input_steps)} input steps")
    
    # Check that tool steps have proper connections
    tool_steps = [step for step_id, step in galaxy_workflow['steps'].items() 
                 if step.get('tool_id') is not None]
    print(f"✓ Found {len(tool_steps)} tool steps")
    
    # Verify connections point to valid step IDs
    all_step_ids = {int(step_id) for step_id in galaxy_workflow['steps'].keys()}
    
    invalid_connections = []
    for step_id, step_data in galaxy_workflow['steps'].items():
        input_connections = step_data.get('input_connections', {})
        for input_name, connection in input_connections.items():
            if isinstance(connection, dict) and 'id' in connection:
                target_id = connection['id']
                if target_id not in all_step_ids:
                    invalid_connections.append(f"Step {step_id}.{input_name} -> Step {target_id} (not found)")
    
    if invalid_connections:
        print(f"❌ Found invalid connections: {invalid_connections}")
        return False
    else:
        print("✅ All connections point to valid step IDs")
    
    # Step 4: Test Galaxy workflow validation (simulate what Galaxy does)
    print("\n4️⃣ Simulating Galaxy workflow validation...")
    
    try:
        # Simulate the validation logic from workflows.py
        steps_by_external_id = {str(step_data['id']): step_data 
                              for step_id, step_data in galaxy_workflow['steps'].items()}
        
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            for input_name, conn_list in input_connections.items():
                if not isinstance(conn_list, list):
                    conn_list = [conn_list] if conn_list else []
                
                for conn_dict in conn_list:
                    if isinstance(conn_dict, dict):
                        if "output_name" not in conn_dict or "id" not in conn_dict:
                            raise Exception(f"Invalid connection [{conn_dict}] - must be dict with output_name and id fields.")
                        
                        external_id = str(conn_dict["id"])
                        if external_id not in steps_by_external_id:
                            raise Exception(f"Invalid connection. Failed to find input step id {external_id}")
        
        print("✅ Galaxy workflow validation passed!")
        
    except Exception as validation_error:
        print(f"❌ Galaxy workflow validation failed: {validation_error}")
        return False
    
    # Step 5: Output summary
    print(f"\n🎉 TEST PASSED! Workflow input connection fix is working correctly.")
    print(f"   - Exported workflow has {len(galaxy_workflow['steps'])} steps")
    print(f"   - All workflow_input_X markers resolved")
    print(f"   - All connections point to valid steps")
    print(f"   - Galaxy validation passed")
    
    return True

if __name__ == "__main__":
    success = test_workflow_input_fix()
    sys.exit(0 if success else 1)