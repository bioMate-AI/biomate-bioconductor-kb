#!/usr/bin/env python3

import json
import sys
import os

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def debug_specific_step_id():
    """
    Debug step ID issues specifically, since the error shows workflow_input_0
    """
    
    print("🔍 Debugging specific step ID resolution...")
    
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import WorkflowStep, WorkflowTemplate
        
        print("✓ Imports successful")
        
        # Create a test case that exactly reproduces the problematic scenario
        print("\n1️⃣ Creating exact reproduction case...")
        
        # This workflow has step 0 as input and step 1 referencing it
        workflow_steps = [
            WorkflowStep(
                step_id=1,
                tool_id="toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
                tool_version="0.72+galaxy1",
                input_connections={
                    'input_file': {
                        'id': 'workflow_input_0',  # This should be resolved to step 0
                        'output_name': 'output',
                        '_original_input_step': 0,
                        '_input_label': 'Input reads'
                    }
                },
                parameters={},
                annotation="FastQC quality control",
                position={'left': 200, 'top': 100}
            )
        ]
        
        # Workflow input corresponding to step 0
        workflow_inputs = [
            {
                'label': 'Input reads',
                'name': 'input_0',  # This should map to the original step 0
                'type': 'data',
                'format': 'fastqsanger',
                'optional': False,
                'description': 'Raw sequencing reads'
            }
        ]
        
        workflow_template = WorkflowTemplate(
            name="Step ID 0 Debug Test",
            description="Test to debug step ID 0 resolution",
            steps=workflow_steps,
            inputs=workflow_inputs,
            outputs=[],
            tags=['debug']
        )
        
        print(f"✓ Created test with workflow_input_0 marker")
        
        # Export and debug step by step
        print("\n2️⃣ Exporting with detailed debugging...")
        
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        
        # Let me manually debug the export process
        print("🔍 Debugging export process:")
        
        # Step 1: Check input step creation
        input_step_id = 0
        input_step_mapping = {}
        original_input_step_mapping = {}
        
        for workflow_input in workflow_template.inputs:
            input_name = workflow_input.get('name', f'input_{input_step_id}')
            print(f"  Creating input step {input_step_id} for '{input_name}'")
            
            # Map both input name and original input step ID to the new step ID
            input_step_mapping[input_name] = input_step_id
            print(f"  → input_step_mapping['{input_name}'] = {input_step_id}")
            
            # Extract original input step ID from input name if it follows the pattern input_X
            if input_name.startswith('input_') and input_name[6:].isdigit():
                original_step_id = int(input_name[6:])
                original_input_step_mapping[original_step_id] = input_step_id
                print(f"  → original_input_step_mapping[{original_step_id}] = {input_step_id}")
            
            input_step_id += 1
        
        # Step 2: Check step connection processing
        for step in workflow_template.steps:
            print(f"\nProcessing step {step.step_id}:")
            updated_connections = {}
            
            for input_name, connection in step.input_connections.items():
                print(f"  Connection {input_name}: {connection}")
                
                if isinstance(connection, dict) and str(connection.get('id', '')).startswith('workflow_input_'):
                    # This is a marked input step connection - reconnect to the actual input step
                    original_input_step = connection.get('_original_input_step')
                    print(f"    → Found workflow_input_ marker, original_input_step = {original_input_step}")
                    
                    # Try to find the correct mapping using the original input step ID
                    if original_input_step is not None and original_input_step in original_input_step_mapping:
                        new_step_id = original_input_step_mapping[original_input_step]
                        updated_connections[input_name] = {
                            'id': new_step_id,
                            'output_name': 'output'
                        }
                        print(f"    ✅ Resolved to step {new_step_id}")
                    else:
                        print(f"    ❌ Could not resolve original_input_step {original_input_step}")
                        print(f"        Available mappings: {original_input_step_mapping}")
                        
                        # Fallback: try to find by input step name
                        input_step_name = f'input_{original_input_step}' if original_input_step is not None else None
                        if input_step_name and input_step_name in input_step_mapping:
                            new_step_id = input_step_mapping[input_step_name]
                            updated_connections[input_name] = {
                                'id': new_step_id,
                                'output_name': 'output'
                            }
                            print(f"    ✅ Fallback resolved to step {new_step_id}")
                        else:
                            print(f"    ❌ Fallback also failed")
                            print(f"        input_step_name = {input_step_name}")
                            print(f"        Available input mappings: {input_step_mapping}")
        
        # Now do the actual export
        print("\n3️⃣ Performing actual export...")
        
        galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
        
        print(f"✅ Export successful! Galaxy workflow has {len(galaxy_workflow['steps'])} steps")
        
        # Validate the result
        print("\n4️⃣ Validating exported workflow...")
        
        for step_id, step_data in galaxy_workflow['steps'].items():
            print(f"\nStep {step_id}:")
            print(f"  Type: {step_data.get('type')}")
            print(f"  Tool ID: {step_data.get('tool_id')}")
            
            input_connections = step_data.get('input_connections', {})
            if input_connections:
                print(f"  Input connections:")
                for input_name, connection in input_connections.items():
                    if isinstance(connection, dict):
                        conn_id = connection.get('id')
                        if isinstance(conn_id, str) and conn_id.startswith('workflow_input_'):
                            print(f"    ❌ {input_name} -> {conn_id} (UNRESOLVED MARKER)")
                            return False
                        else:
                            print(f"    ✅ {input_name} -> Step {conn_id}")
                    else:
                        print(f"    ? {input_name} -> {connection}")
        
        print(f"\n🎉 Step ID 0 resolution working correctly!")
        return True
        
    except Exception as e:
        print(f"❌ Debug failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = debug_specific_step_id()
    if success:
        print(f"\n✅ Step ID resolution is working")
    else:
        print(f"\n❌ Step ID resolution has issues")
    
    sys.exit(0 if success else 1)