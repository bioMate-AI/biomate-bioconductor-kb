#!/usr/bin/env python3

import json
import sys
import os

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def debug_step_id_0_case():
    """
    Debug the specific case where we get workflow_input_0 error
    This might happen when the original workflow has step ID 0 as an input step
    """
    
    print("🔍 Debugging step ID 0 case...")
    
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import WorkflowStep, WorkflowTemplate
        
        print("✓ Imports successful")
        
        # Create a problematic scenario with step ID 0
        print("\n1️⃣ Creating problematic scenario with step ID 0...")
        
        # This is a common pattern where step 0 is an input step
        workflow_steps = [
            WorkflowStep(
                step_id=1,
                tool_id="toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
                tool_version="0.72+galaxy1",
                input_connections={
                    'input_file': {
                        'id': 'workflow_input_0',  # References input step 0
                        'output_name': 'output',
                        '_original_input_step': 0,
                        '_input_label': 'Raw reads'
                    }
                },
                parameters={},
                annotation="FastQC quality control",
                position={'left': 200, 'top': 100}
            )
        ]
        
        workflow_inputs = [
            {
                'label': 'Raw reads',
                'name': 'input_0',
                'type': 'data',
                'format': 'fastqsanger',
                'optional': False,
                'description': 'Raw sequencing reads'
            }
        ]
        
        workflow_template = WorkflowTemplate(
            name="Debug Step 0 Workflow",
            description="Test case for step ID 0 issue",
            steps=workflow_steps,
            inputs=workflow_inputs,
            outputs=[],
            tags=['debug']
        )
        
        print(f"✓ Created workflow with step referencing workflow_input_0")
        
        # Export and examine
        print("\n2️⃣ Exporting to Galaxy format...")
        
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
        
        print(f"✅ Export successful! Galaxy workflow has {len(galaxy_workflow['steps'])} steps")
        
        # Examine the exported steps in detail
        print("\n3️⃣ Examining exported steps...")
        
        for step_id, step_data in galaxy_workflow['steps'].items():
            print(f"\nStep {step_id}:")
            print(f"  Type: {step_data.get('type')}")
            print(f"  Tool ID: {step_data.get('tool_id')}")
            print(f"  Label: {step_data.get('label', 'N/A')}")
            
            input_connections = step_data.get('input_connections', {})
            if input_connections:
                print(f"  Connections:")
                for input_name, connection in input_connections.items():
                    if isinstance(connection, dict):
                        conn_id = connection.get('id')
                        output_name = connection.get('output_name', 'N/A')
                        if isinstance(conn_id, str) and conn_id.startswith('workflow_input_'):
                            print(f"    🔴 {input_name} -> {conn_id} ({output_name}) [PROBLEMATIC]")
                        else:
                            print(f"    ✅ {input_name} -> Step {conn_id} ({output_name})")
                    else:
                        print(f"    ? {input_name} -> {connection}")
            else:
                print(f"  No input connections")
        
        # Validate step ID mapping
        print("\n4️⃣ Validating step ID mapping...")
        
        available_step_ids = {int(sid) for sid in galaxy_workflow['steps'].keys()}
        print(f"Available step IDs: {sorted(available_step_ids)}")
        
        # Check if input_0 maps to step 0
        input_step_found = None
        for step_id, step_data in galaxy_workflow['steps'].items():
            if step_data.get('tool_id') is None and step_data.get('label') == 'Raw reads':
                input_step_found = int(step_id)
                print(f"Found input step for 'Raw reads' at step ID: {input_step_found}")
                break
        
        if input_step_found is None:
            print("❌ Input step for 'Raw reads' not found!")
            return False
        
        # Check connections point to correct step
        print("\n5️⃣ Checking connection resolution...")
        
        connection_errors = []
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    
                    if isinstance(target_id, str) and target_id.startswith('workflow_input_'):
                        connection_errors.append(f"Step {step_id}.{input_name} -> {target_id}")
                    elif target_id not in available_step_ids:
                        connection_errors.append(f"Step {step_id}.{input_name} -> Step {target_id} (not found)")
                    else:
                        print(f"✅ Step {step_id}.{input_name} -> Step {target_id} (valid)")
        
        if connection_errors:
            print(f"❌ Connection errors found: {connection_errors}")
            return False
        else:
            print("✅ All connections are valid")
        
        # Test JSON serialization
        print("\n6️⃣ Testing JSON serialization...")
        
        try:
            json_str = json.dumps(galaxy_workflow, indent=2)
            print("✅ JSON serialization successful")
        except Exception as json_error:
            print(f"❌ JSON serialization failed: {json_error}")
            return False
        
        print(f"\n🎉 Step ID 0 case working correctly!")
        return True
        
    except Exception as e:
        print(f"❌ Debug failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = debug_step_id_0_case()
    if success:
        print(f"\n✅ Step ID 0 case is working - the issue might be elsewhere")
    else:
        print(f"\n❌ Step ID 0 case has issues - this might be the root cause")
    
    sys.exit(0 if success else 1)