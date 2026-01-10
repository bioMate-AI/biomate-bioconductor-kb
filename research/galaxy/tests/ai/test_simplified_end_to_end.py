#!/usr/bin/env python3

import json
import sys
import os

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def simplified_clean_input_connections(workflow_steps, original_steps_data):
    """
    Simplified version of _clean_input_connections for testing
    """
    existing_step_ids = set(step.step_id for step in workflow_steps)
    
    # Identify input steps
    input_step_info = {}
    for step_id, step_data in original_steps_data.items():
        if step_data.get("tool_id") is None:
            input_step_info[int(step_id)] = {
                'type': step_data.get('type', 'data_input'),
                'label': step_data.get('label', f'Input {step_id}'),
                'tool_state': step_data.get('tool_state', '{}')
            }
    
    needed_input_steps = set()
    cleaned_steps = []
    
    from galaxy.ai.types import WorkflowStep
    
    for step in workflow_steps:
        cleaned_connections = {}
        
        for input_name, connection in step.input_connections.items():
            if isinstance(connection, dict) and 'id' in connection:
                referenced_step_id = connection['id']
                
                if referenced_step_id in existing_step_ids:
                    cleaned_connections[input_name] = connection
                elif referenced_step_id in input_step_info:
                    input_info = input_step_info[referenced_step_id]
                    needed_input_steps.add(referenced_step_id)
                    
                    # Create the problematic workflow_input_ marker
                    cleaned_connections[input_name] = {
                        'id': f'workflow_input_{referenced_step_id}',
                        'output_name': connection.get('output_name', 'output'),
                        '_original_input_step': referenced_step_id,
                        '_input_label': input_info['label']
                    }
            else:
                cleaned_connections[input_name] = connection
        
        cleaned_step = WorkflowStep(
            step_id=step.step_id,
            tool_id=step.tool_id,
            tool_version=step.tool_version,
            input_connections=cleaned_connections,
            parameters=step.parameters,
            annotation=step.annotation,
            position=step.position
        )
        cleaned_steps.append(cleaned_step)
    
    # Create workflow inputs
    workflow_inputs = []
    for input_step_id in sorted(needed_input_steps):
        input_info = input_step_info[input_step_id]
        
        try:
            tool_state = json.loads(input_info['tool_state']) if isinstance(input_info['tool_state'], str) else input_info['tool_state']
        except:
            tool_state = {}
        
        workflow_inputs.append({
            'label': input_info['label'],
            'name': f'input_{input_step_id}',
            'type': 'data',
            'format': tool_state.get('format', 'auto'),
            'optional': tool_state.get('optional', False),
            'description': f"Workflow input: {input_info['label']}"
        })
    
    return cleaned_steps, workflow_inputs


def test_simplified_end_to_end():
    """
    Simplified test that reproduces the workflow_input_X error and validates the fix
    """
    
    print("🧪 Testing simplified end-to-end workflow creation...")
    
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import WorkflowStep, WorkflowTemplate
        
        print("✓ Imports successful")
        
        # Create test scenario that reproduces the error
        print("\n1️⃣ Creating test scenario...")
        
        # Original workflow structure (simulating RAG data)
        raw_workflow_data = {
            "steps": {
                "0": {
                    "tool_id": None,  # Input step
                    "type": "data_input", 
                    "label": "Input reads",
                    "tool_state": '{"format": "fastqsanger"}'
                },
                "1": {
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
                    "tool_version": "0.72+galaxy1", 
                    "input_connections": {
                        "input_file": {"id": 0, "output_name": "output"}  # References input step 0
                    },
                    "tool_state": '{}',
                    "annotation": "FastQC",
                    "position": {"left": 200, "top": 100}
                },
                "4": {  # Use step ID 4 to match the original error
                    "tool_id": None,  # Another input step
                    "type": "data_input",
                    "label": "Reference genome", 
                    "tool_state": '{"format": "fasta"}'
                },
                "5": {
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/hisat2/hisat2/2.2.1+galaxy0",
                    "tool_version": "2.2.1+galaxy0",
                    "input_connections": {
                        "library|input_1": {"id": 1, "output_name": "html_file"},
                        "reference_genome|index": {"id": 4, "output_name": "output"}  # This becomes workflow_input_4
                    },
                    "tool_state": '{}',
                    "annotation": "HISAT2",
                    "position": {"left": 400, "top": 100}
                }
            }
        }
        
        # Convert to WorkflowSteps (filtering input steps)
        print("\n2️⃣ Converting to WorkflowSteps...")
        workflow_steps = []
        for step_id, step_data in raw_workflow_data["steps"].items():
            if step_data.get("tool_id") is None:
                continue
                
            step = WorkflowStep(
                step_id=int(step_id),
                tool_id=step_data["tool_id"],
                tool_version=step_data["tool_version"],
                input_connections=step_data.get("input_connections", {}),
                parameters={},
                annotation=step_data.get("annotation", ""),
                position=step_data.get("position", {"left": 0, "top": 0})
            )
            workflow_steps.append(step)
        
        print(f"✓ Created {len(workflow_steps)} workflow steps")
        
        # Apply connection cleaning
        print("\n3️⃣ Applying connection cleaning...")
        cleaned_steps, workflow_inputs = simplified_clean_input_connections(workflow_steps, raw_workflow_data["steps"])
        
        # Verify we have the problematic workflow_input_4 marker
        workflow_input_4_found = False
        for step in cleaned_steps:
            for input_name, connection in step.input_connections.items():
                if isinstance(connection, dict):
                    conn_id = str(connection.get('id', ''))
                    if conn_id == 'workflow_input_4':
                        workflow_input_4_found = True
                        print(f"✓ Found problematic 'workflow_input_4' marker in step {step.step_id}.{input_name}")
        
        if not workflow_input_4_found:
            raise Exception("Test setup error: workflow_input_4 marker not found")
        
        # Create workflow template
        print("\n4️⃣ Creating WorkflowTemplate...")
        workflow_template = WorkflowTemplate(
            name="Test Workflow",
            description="Test workflow to reproduce and fix the workflow_input_4 error",
            steps=cleaned_steps,
            inputs=workflow_inputs,
            outputs=[],
            tags=['test']
        )
        
        # Export to Galaxy format (this is where our fix is applied)
        print("\n5️⃣ Exporting to Galaxy format (applying fix)...")
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
        
        print(f"✅ Export successful! Created {len(galaxy_workflow['steps'])} steps")
        
        # Validate the fix worked
        print("\n6️⃣ Validating the fix...")
        
        # Check that no workflow_input_ markers remain
        remaining_markers = []
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict):
                    conn_id = str(connection.get('id', ''))
                    if conn_id.startswith('workflow_input_'):
                        remaining_markers.append(f"Step {step_id}.{input_name} -> {conn_id}")
        
        if remaining_markers:
            raise Exception(f"Fix failed: Found remaining workflow_input_ markers: {remaining_markers}")
        
        print("✅ No workflow_input_ markers remain")
        
        # Simulate Galaxy validation
        print("\n7️⃣ Simulating Galaxy validation...")
        step_ids = {str(step_data['id']) for step_data in galaxy_workflow['steps'].values()}
        
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = str(connection['id'])
                    if target_id not in step_ids:
                        raise Exception(f"Invalid connection. Failed to find input step id {target_id}")
        
        print("✅ Galaxy validation passed!")
        
        print(f"\n🎉 SIMPLIFIED END-TO-END TEST PASSED!")
        print(f"   ✅ Successfully reproduced the 'workflow_input_4' scenario")
        print(f"   ✅ Fix correctly resolved all workflow_input_ markers") 
        print(f"   ✅ Galaxy validation passes without the original error")
        print(f"   ✅ The workflow can now be saved successfully!")
        
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_simplified_end_to_end()
    sys.exit(0 if success else 1)