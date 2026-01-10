#!/usr/bin/env python3
"""
Test to verify RAG data structure and connection cleaning
"""

import os
import sys
import json
from pathlib import Path

# Add the Galaxy lib directory to the path
galaxy_lib_path = Path(__file__).parent / "lib"
if str(galaxy_lib_path) not in sys.path:
    sys.path.insert(0, str(galaxy_lib_path))

def test_connection_cleaning():
    """Test the input connection cleaning logic"""
    
    print("🔍 Testing input connection cleaning logic...")
    
    try:
        # Load actual workflow data
        workflows_dir = Path("lib/galaxy/ai/data/workflows")
        if not workflows_dir.exists():
            print("❌ RAG workflows directory not found")
            return False
            
        workflow_files = list(workflows_dir.glob("workflow_*.json"))
        if not workflow_files:
            print("❌ No RAG workflow files found")
            return False
            
        # Use the first workflow file
        workflow_file = workflow_files[0]
        print(f"📁 Testing workflow: {workflow_file.name}")
        
        with open(workflow_file, 'r', encoding='utf-8') as f:
            workflow_data = json.load(f)
        
        workflow_json = workflow_data.get("workflow_json", {})
        steps_data = workflow_json.get("steps", {})
        
        print(f"✓ Original workflow has {len(steps_data)} total steps")
        
        # Analyze step types
        input_steps = []
        tool_steps = []
        
        for step_id, step_data in steps_data.items():
            tool_id = step_data.get("tool_id")
            if tool_id is None:
                input_steps.append(int(step_id))
            else:
                tool_steps.append(int(step_id))
        
        print(f"  → Input steps (will be filtered): {sorted(input_steps)}")
        print(f"  → Tool steps (will be kept): {sorted(tool_steps)}")
        
        # Analyze connections before cleaning
        connections_to_input = {}
        connections_to_tools = {}
        
        for step_id, step_data in steps_data.items():
            if step_data.get("tool_id") is None:
                continue  # Skip input steps
                
            input_connections = step_data.get("input_connections", {})
            for input_name, connection in input_connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    if target_id in input_steps:
                        connections_to_input.setdefault(int(step_id), []).append(target_id)
                    elif target_id in tool_steps:
                        connections_to_tools.setdefault(int(step_id), []).append(target_id)
        
        print(f"  → Steps with connections to input steps: {dict(connections_to_input)}")
        print(f"  → Steps with connections to tool steps: {dict(connections_to_tools)}")
        
        # Create WorkflowStep objects (like the API does)
        from galaxy.ai.types import WorkflowStep
        
        workflow_steps = []
        for step_id, step_data in steps_data.items():
            tool_id = step_data.get("tool_id")
            
            if tool_id is None:
                continue
                
            tool_version = step_data.get("tool_version") or "1.0"
            
            tool_state_raw = step_data.get("tool_state", "{}")
            try:
                if isinstance(tool_state_raw, str):
                    parameters = json.loads(tool_state_raw)
                else:
                    parameters = tool_state_raw or {}
            except (json.JSONDecodeError, TypeError):
                parameters = {}
            
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
        
        print(f"✓ Created {len(workflow_steps)} WorkflowStep objects")
        
        # Import the cleaning function
        sys.path.append(str(Path(__file__).parent / "lib/galaxy/webapps/galaxy/api"))
        from ai_assistant import _clean_input_connections
        
        # Clean the connections
        cleaned_steps = _clean_input_connections(workflow_steps, steps_data)
        
        print(f"✓ Cleaned connections for {len(cleaned_steps)} steps")
        
        # Analyze the results
        connections_removed = 0
        connections_kept = 0
        
        for i, (original_step, cleaned_step) in enumerate(zip(workflow_steps, cleaned_steps)):
            original_conn_count = len(original_step.input_connections)
            cleaned_conn_count = len(cleaned_step.input_connections)
            
            if original_conn_count != cleaned_conn_count:
                removed = original_conn_count - cleaned_conn_count
                connections_removed += removed
                print(f"  → Step {cleaned_step.step_id}: {removed} connections removed, {cleaned_conn_count} kept")
            else:
                connections_kept += cleaned_conn_count
        
        print(f"✓ Total connections removed: {connections_removed}")
        print(f"✓ Total connections kept: {connections_kept}")
        
        # Validate that no references to input steps remain
        invalid_references = []
        for step in cleaned_steps:
            for input_name, connection in step.input_connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    if target_id in input_steps:
                        invalid_references.append((step.step_id, target_id))
        
        if invalid_references:
            print(f"❌ Found {len(invalid_references)} invalid references to input steps: {invalid_references}")
            return False
        
        print(f"✅ No invalid references to input steps found!")
        
        # Validate that all references point to existing tool steps
        existing_tool_step_ids = set(step.step_id for step in cleaned_steps)
        invalid_tool_references = []
        
        for step in cleaned_steps:
            for input_name, connection in step.input_connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    if target_id not in existing_tool_step_ids:
                        invalid_tool_references.append((step.step_id, target_id))
        
        if invalid_tool_references:
            print(f"❌ Found {len(invalid_tool_references)} invalid references to non-existent tool steps: {invalid_tool_references}")
            return False
        
        print(f"✅ All step references point to valid existing tool steps!")
        
        print(f"\n🎉 CONNECTION CLEANING SUCCESS!")
        print(f"   Original workflow: {len(steps_data)} steps ({len(input_steps)} input, {len(tool_steps)} tool)")
        print(f"   Filtered workflow: {len(cleaned_steps)} tool steps")
        print(f"   Connections to input steps removed: {connections_removed}")
        print(f"   Valid connections preserved: {connections_kept}")
        
        return True
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("=== Testing RAG Connection Cleaning ===\n")
    
    success = test_connection_cleaning()
    
    if success:
        print("\n✅ Connection cleaning should resolve the step ID validation errors!")
    else:
        print("\n💥 Connection cleaning test failed!")
        sys.exit(1)