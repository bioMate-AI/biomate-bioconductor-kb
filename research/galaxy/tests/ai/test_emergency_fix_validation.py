#!/usr/bin/env python3

import json
import sys
import os

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def test_emergency_fix_validation():
    """
    Test the emergency fix validation with problematic workflow_input_ markers
    """
    
    print("🚨 Testing emergency fix validation...")
    
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        
        print("✓ Imports successful")
        
        # Create a workflow generator to test the validation
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        
        # Create a problematic Galaxy workflow with workflow_input_ markers
        print("\n1️⃣ Creating problematic Galaxy workflow with unresolved markers...")
        
        problematic_workflow = {
            'a_galaxy_workflow': 'true',
            'annotation': 'Test problematic workflow',
            'format-version': '0.1',
            'name': 'Problematic Test Workflow',
            'steps': {
                '0': {
                    'id': 0,
                    'type': 'data_input',
                    'tool_id': None,
                    'tool_version': None,
                    'annotation': 'Input step',
                    'input_connections': {},
                    'inputs': [{'name': 'input_0', 'description': 'Test input'}],
                    'label': 'Test Input',
                    'name': 'Input dataset',
                    'outputs': [],
                    'position': {'left': 0, 'top': 100},
                    'post_job_actions': {},
                    'tool_state': '{"format": "auto", "optional": false}',
                    'uuid': 'test-uuid-1',
                    'workflow_outputs': []
                },
                '1': {
                    'id': 1,
                    'type': 'tool',
                    'tool_id': 'toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1',
                    'tool_version': '0.72+galaxy1',
                    'annotation': 'FastQC tool',
                    'input_connections': {
                        'input_file': {
                            'id': 'workflow_input_0',  # This is the problematic marker!
                            'output_name': 'output'
                        }
                    },
                    'inputs': {},
                    'position': {'left': 200, 'top': 100},
                    'post_job_actions': {},
                    'tool_state': '{}',
                    'uuid': 'test-uuid-2',
                    'workflow_outputs': []
                }
            },
            'tags': ['test'],
            'uuid': 'test-workflow-uuid',
            'version': 1
        }
        
        print(f"✓ Created problematic workflow with workflow_input_0 marker")
        
        # Test the validation function
        print("\n2️⃣ Running emergency validation...")
        
        # This should detect and fix the workflow_input_ marker
        generator._validate_and_clean_final_workflow(problematic_workflow)
        
        print(f"✅ Emergency validation completed")
        
        # Check if the marker was fixed
        print("\n3️⃣ Checking if markers were resolved...")
        
        remaining_markers = []
        for step_id, step_data in problematic_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict):
                    conn_id = str(connection.get('id', ''))
                    if conn_id.startswith('workflow_input_'):
                        remaining_markers.append(f"Step {step_id}.{input_name} -> {conn_id}")
        
        if remaining_markers:
            print(f"❌ Emergency fix failed - remaining markers: {remaining_markers}")
            return False
        else:
            print("✅ All workflow_input_ markers were resolved by emergency fix")
        
        # Verify the connection is now valid
        print("\n4️⃣ Verifying corrected connections...")
        
        step_1_connections = problematic_workflow['steps']['1']['input_connections']
        if 'input_file' in step_1_connections:
            connection = step_1_connections['input_file']
            conn_id = connection.get('id')
            
            if conn_id == 0:
                print(f"✅ Connection correctly resolved: input_file -> Step {conn_id}")
            else:
                print(f"❌ Connection not properly resolved: input_file -> {conn_id}")
                return False
        else:
            print("❌ Connection was removed entirely")
            return False
        
        # Test JSON serialization after fix
        print("\n5️⃣ Testing JSON serialization after fix...")
        
        try:
            json_str = json.dumps(problematic_workflow, indent=2)
            print("✅ JSON serialization successful after fix")
        except Exception as json_error:
            print(f"❌ JSON serialization failed after fix: {json_error}")
            return False
        
        print(f"\n🎉 Emergency fix validation successful!")
        print(f"   The emergency validation properly handles workflow_input_ markers")
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_emergency_fix_validation()
    
    if success:
        print(f"\n✅ Emergency fix validation works correctly")
    else:
        print(f"\n❌ Emergency fix validation has issues")
    
    sys.exit(0 if success else 1)