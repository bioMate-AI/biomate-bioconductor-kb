#!/usr/bin/env python3

import json
import sys
import os

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def test_complete_save_process():
    """
    Test the complete workflow save process that might be causing the error
    """
    
    print("🧪 Testing complete workflow save process...")
    
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import WorkflowStep, WorkflowTemplate
        
        print("✓ Core imports successful")
        
        # Create test workflow that reproduces the issue
        print("\n1️⃣ Creating problematic workflow...")
        
        workflow_steps = [
            WorkflowStep(
                step_id=1,
                tool_id="toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
                tool_version="0.72+galaxy1",
                input_connections={
                    'input_file': {
                        'id': 'workflow_input_0',
                        'output_name': 'output',
                        '_original_input_step': 0,
                        '_input_label': 'Input reads'
                    }
                },
                parameters={},
                annotation="FastQC",
                position={'left': 200, 'top': 100}
            )
        ]
        
        workflow_inputs = [
            {
                'label': 'Input reads',
                'name': 'input_0',
                'type': 'data',
                'format': 'fastqsanger',
                'optional': False,
                'description': 'Raw reads'
            }
        ]
        
        workflow_template = WorkflowTemplate(
            name="End-to-End Test Workflow",
            description="Test workflow for debugging save issues",
            steps=workflow_steps,
            inputs=workflow_inputs,
            outputs=[],
            tags=['test']
        )
        
        print(f"✓ Created workflow with {len(workflow_steps)} steps")
        
        # Export to Galaxy format
        print("\n2️⃣ Exporting to Galaxy format...")
        
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
        
        print(f"✅ Export successful: {len(galaxy_workflow['steps'])} steps")
        
        # Validate no workflow_input_ markers remain
        print("\n3️⃣ Validating export result...")
        
        remaining_markers = []
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict):
                    conn_id = str(connection.get('id', ''))
                    if conn_id.startswith('workflow_input_'):
                        remaining_markers.append(f"Step {step_id}.{input_name} -> {conn_id}")
        
        if remaining_markers:
            print(f"❌ Found remaining workflow_input_ markers: {remaining_markers}")
            return False
        else:
            print("✅ No workflow_input_ markers found")
        
        # Test JSON serialization like Galaxy would do
        print("\n4️⃣ Testing JSON serialization...")
        
        try:
            json_str = json.dumps(galaxy_workflow, indent=2, sort_keys=True)
            print("✅ JSON serialization successful")
        except Exception as json_error:
            print(f"❌ JSON serialization failed: {json_error}")
            return False
        
        # Print the final workflow for inspection
        print(f"\n5️⃣ Final workflow structure:")
        print(f"Steps: {list(galaxy_workflow['steps'].keys())}")
        
        for step_id, step_data in galaxy_workflow['steps'].items():
            step_type = step_data.get('type', 'unknown')
            tool_id = step_data.get('tool_id')
            print(f"  Step {step_id} ({step_type}): {tool_id or 'input'}")
            
            connections = step_data.get('input_connections', {})
            for input_name, connection in connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    print(f"    → {input_name} connects to Step {target_id}")
        
        # Validate that all connections point to existing steps
        print(f"\n6️⃣ Validating all connections...")
        
        all_step_ids = {int(step_id) for step_id in galaxy_workflow['steps'].keys()}
        connection_errors = []
        
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    if target_id not in all_step_ids:
                        connection_errors.append(f"Step {step_id}.{input_name} -> {target_id} (not found)")
        
        if connection_errors:
            print(f"❌ Connection validation failed: {connection_errors}")
            return False
        else:
            print("✅ All connections are valid")
        
        print(f"\n🎉 End-to-end workflow processing successful!")
        print(f"   The export_to_galaxy_format fix is working correctly")
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_complete_save_process()
    
    if success:
        print(f"\n✅ Complete save process works - the issue might be elsewhere")
    else:
        print(f"\n❌ Found issues in the save process")
    
    sys.exit(0 if success else 1)