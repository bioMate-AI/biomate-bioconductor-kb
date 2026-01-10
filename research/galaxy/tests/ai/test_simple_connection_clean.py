#!/usr/bin/env python3
"""
Simplified test for connection cleaning logic without full Galaxy imports
"""

import json
from pathlib import Path

def simple_clean_input_connections(workflow_steps, original_steps_data):
    """
    Simplified version of _clean_input_connections for testing
    """
    # Create a map of existing step IDs
    existing_step_ids = set(step['step_id'] for step in workflow_steps)
    
    # Identify input steps (steps with tool_id=None) in original data
    input_step_ids = set()
    for step_id, step_data in original_steps_data.items():
        if step_data.get("tool_id") is None:
            input_step_ids.add(int(step_id))
    
    # Clean up input connections for each workflow step
    cleaned_steps = []
    connections_removed = 0
    
    for step in workflow_steps:
        cleaned_connections = {}
        
        # Filter out connections that reference filtered input steps or non-existent steps
        for input_name, connection in step['input_connections'].items():
            if isinstance(connection, dict) and 'id' in connection:
                referenced_step_id = connection['id']
                
                # Keep the connection only if it references an existing step
                if referenced_step_id in existing_step_ids:
                    cleaned_connections[input_name] = connection
                elif referenced_step_id in input_step_ids:
                    # This connection references an input step - we skip it
                    print(f"  → Removing connection from step {step['step_id']} to input step {referenced_step_id}")
                    connections_removed += 1
                    continue
                else:
                    # This connection references a non-existent step
                    print(f"  ⚠️  Step {step['step_id']} references non-existent step {referenced_step_id}")
                    connections_removed += 1
                    continue
            else:
                # Keep non-dict connections or connections without 'id'
                cleaned_connections[input_name] = connection
        
        # Create a cleaned step
        cleaned_step = step.copy()
        cleaned_step['input_connections'] = cleaned_connections
        cleaned_steps.append(cleaned_step)
    
    print(f"  ✓ Total connections removed: {connections_removed}")
    return cleaned_steps

def test_simple_connection_cleaning():
    """Test connection cleaning with simplified workflow data"""
    
    print("🔍 Testing simplified connection cleaning...")
    
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
        
        # Create simplified workflow steps (only tool steps)
        workflow_steps = []
        for step_id, step_data in steps_data.items():
            tool_id = step_data.get("tool_id")
            
            if tool_id is None:
                continue
                
            # Create simplified step structure
            step = {
                'step_id': int(step_id),
                'tool_id': tool_id,
                'input_connections': step_data.get("input_connections", {})
            }
            workflow_steps.append(step)
        
        print(f"✓ Created {len(workflow_steps)} simplified workflow steps")
        
        # Analyze connections before cleaning
        connections_to_input = 0
        connections_to_tools = 0
        total_connections = 0
        
        for step in workflow_steps:
            for input_name, connection in step['input_connections'].items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    total_connections += 1
                    if target_id in input_steps:
                        connections_to_input += 1
                    elif target_id in tool_steps:
                        connections_to_tools += 1
        
        print(f"✓ Before cleaning:")
        print(f"  → Total connections: {total_connections}")
        print(f"  → Connections to input steps: {connections_to_input}")
        print(f"  → Connections to tool steps: {connections_to_tools}")
        
        # Clean the connections
        cleaned_steps = simple_clean_input_connections(workflow_steps, steps_data)
        
        # Analyze connections after cleaning
        cleaned_total = 0
        cleaned_invalid = 0
        
        for step in cleaned_steps:
            for input_name, connection in step['input_connections'].items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    cleaned_total += 1
                    if target_id in input_steps:
                        cleaned_invalid += 1
        
        print(f"✓ After cleaning:")
        print(f"  → Total connections remaining: {cleaned_total}")
        print(f"  → Invalid connections to input steps: {cleaned_invalid}")
        
        if cleaned_invalid == 0:
            print(f"✅ SUCCESS: All connections to input steps removed!")
            
            # Validate that all remaining connections point to valid tool steps
            existing_tool_step_ids = set(step['step_id'] for step in cleaned_steps)
            invalid_tool_refs = 0
            
            for step in cleaned_steps:
                for input_name, connection in step['input_connections'].items():
                    if isinstance(connection, dict) and 'id' in connection:
                        target_id = connection['id']
                        if target_id not in existing_tool_step_ids:
                            invalid_tool_refs += 1
            
            if invalid_tool_refs == 0:
                print(f"✅ All remaining connections point to valid tool steps!")
            else:
                print(f"❌ Found {invalid_tool_refs} connections to non-existent tool steps")
                return False
                
            return True
        else:
            print(f"❌ Still have {cleaned_invalid} invalid connections")
            return False
            
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("=== Testing Simple Connection Cleaning ===\n")
    
    success = test_simple_connection_cleaning()
    
    if success:
        print("\n🎉 Simple connection cleaning works correctly!")
        print("The full implementation should resolve the step ID validation errors.")
    else:
        print("\n💥 Simple connection cleaning test failed!")