#!/usr/bin/env python3

import json
import sys
import os
import traceback

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

def debug_real_workflow_creation():
    """
    Debug the actual workflow creation to find where workflow_input_ markers come from
    """
    
    print("🔍 Debugging real workflow creation...")
    
    try:
        # Import necessary components
        from galaxy.webapps.galaxy.api.ai_assistant import _clean_input_connections
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import WorkflowStep, WorkflowTemplate
        
        print("✓ Imports successful")
        
        # Let's try to simulate what happens in create_workflow_from_ai
        print("\n1️⃣ Simulating RAG workflow data that might cause the error...")
        
        # This mimics what we might get from RAG system
        rag_workflow_json = {
            "steps": {
                "0": {
                    "tool_id": None,
                    "type": "data_input",
                    "label": "Input reads",
                    "tool_state": '{"format": "fastqsanger", "optional": false}'
                },
                "1": {
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
                    "tool_version": "0.72+galaxy1",
                    "input_connections": {
                        "input_file": {"id": 0, "output_name": "output"}
                    },
                    "tool_state": '{"contaminants": null, "adapters": null}',
                    "annotation": "FastQC quality control",
                    "position": {"left": 200, "top": 100}
                }
            }
        }
        
        print(f"✓ Created test RAG workflow with {len(rag_workflow_json['steps'])} steps")
        
        # Step 2: Process like the AI assistant does
        print("\n2️⃣ Converting to WorkflowStep objects...")
        
        workflow_steps = []
        steps_data = rag_workflow_json["steps"]
        
        for step_id, step_data in steps_data.items():
            # Extract step information from workflow JSON
            tool_id = step_data.get("tool_id")
            
            # Skip input steps (tool_id is None for input dataset/parameter steps)
            if tool_id is None:
                print(f"  → Skipping input step {step_id}: {step_data.get('label', 'Unknown')}")
                continue
                
            tool_version = step_data.get("tool_version") or "1.0"
            
            # Parse tool_state (it's a JSON string, not a dict)
            tool_state_raw = step_data.get("tool_state", "{}")
            try:
                if isinstance(tool_state_raw, str):
                    parameters = json.loads(tool_state_raw)
                else:
                    parameters = tool_state_raw or {}
            except (json.JSONDecodeError, TypeError):
                parameters = {}
            
            # Create Galaxy WorkflowStep object from real data
            step = WorkflowStep(
                step_id=int(step_id),
                tool_id=tool_id,
                tool_version=tool_version,
                input_connections=step_data.get("input_connections", {}),
                parameters=parameters,
                annotation=step_data.get("annotation", f"Step {int(step_id) + 1}"),
                position=step_data.get("position", {"left": int(step_id) * 100, "top": 100})
            )
            workflow_steps.append(step)
            print(f"  → Created tool step {step_id}: {tool_id}")
        
        print(f"✓ Created {len(workflow_steps)} WorkflowStep objects")
        
        # Step 3: Clean input connections
        print("\n3️⃣ Cleaning input connections...")
        
        cleaned_steps, workflow_inputs = _clean_input_connections(workflow_steps, steps_data)
        
        print(f"✓ Cleaned connections: {len(cleaned_steps)} steps, {len(workflow_inputs)} inputs")
        
        # Examine the cleaned connections
        print("\n4️⃣ Examining cleaned connections...")
        for i, step in enumerate(cleaned_steps):
            print(f"  Step {step.step_id} ({step.tool_id}):")
            for input_name, connection in step.input_connections.items():
                if isinstance(connection, dict):
                    conn_id = connection.get('id')
                    if isinstance(conn_id, str) and conn_id.startswith('workflow_input_'):
                        print(f"    🔴 {input_name} -> {conn_id} (PROBLEMATIC MARKER)")
                        print(f"       Original step: {connection.get('_original_input_step')}")
                        print(f"       Label: {connection.get('_input_label')}")
                    else:
                        print(f"    ✓ {input_name} -> {conn_id}")
                else:
                    print(f"    ? {input_name} -> {connection}")
        
        # Step 4: Create WorkflowTemplate
        print("\n5️⃣ Creating WorkflowTemplate...")
        
        workflow_template = WorkflowTemplate(
            name="Debug Test Workflow",
            description="Workflow to debug the connection issue",
            steps=cleaned_steps,
            inputs=workflow_inputs,
            outputs=[],
            tags=['debug']
        )
        
        print(f"✓ WorkflowTemplate created")
        
        # Step 5: Export to Galaxy format
        print("\n6️⃣ Exporting to Galaxy format...")
        
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        
        try:
            galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
            print(f"✅ Export successful! Galaxy workflow has {len(galaxy_workflow['steps'])} steps")
            
            # Check the final result
            print("\n7️⃣ Checking final Galaxy workflow...")
            
            for step_id, step_data in galaxy_workflow['steps'].items():
                step_type = step_data.get('type', 'unknown')
                tool_id = step_data.get('tool_id')
                
                if tool_id:
                    print(f"  Step {step_id} (tool): {tool_id}")
                else:
                    print(f"  Step {step_id} (input): {step_type}")
                
                input_connections = step_data.get('input_connections', {})
                for input_name, connection in input_connections.items():
                    if isinstance(connection, dict):
                        conn_id = connection.get('id')
                        if isinstance(conn_id, str) and conn_id.startswith('workflow_input_'):
                            print(f"    ❌ {input_name} -> {conn_id} (STILL HAS MARKER!)")
                        else:
                            print(f"    ✓ {input_name} -> {conn_id}")
            
            # Check if all step IDs exist
            print("\n8️⃣ Validating step ID references...")
            
            all_step_ids = {int(step_id) for step_id in galaxy_workflow['steps'].keys()}
            print(f"  Available step IDs: {sorted(all_step_ids)}")
            
            invalid_connections = []
            for step_id, step_data in galaxy_workflow['steps'].items():
                input_connections = step_data.get('input_connections', {})
                for input_name, connection in input_connections.items():
                    if isinstance(connection, dict) and 'id' in connection:
                        target_id = connection['id']
                        if isinstance(target_id, str) and target_id.startswith('workflow_input_'):
                            invalid_connections.append(f"Step {step_id}.{input_name} -> {target_id}")
                        elif target_id not in all_step_ids:
                            invalid_connections.append(f"Step {step_id}.{input_name} -> {target_id} (not found)")
            
            if invalid_connections:
                print(f"  ❌ Found invalid connections: {invalid_connections}")
                return False
            else:
                print("  ✅ All connections are valid")
                return True
                
        except Exception as export_error:
            print(f"❌ Export failed: {export_error}")
            traceback.print_exc()
            return False
        
    except Exception as e:
        print(f"❌ Debug failed: {e}")
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = debug_real_workflow_creation()
    if success:
        print(f"\n🎉 DEBUG SUCCESSFUL - The fix appears to be working")
    else:
        print(f"\n❌ DEBUG REVEALED ISSUES - The fix needs more work")
    
    sys.exit(0 if success else 1)