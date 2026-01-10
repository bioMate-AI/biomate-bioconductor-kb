#!/usr/bin/env python3
"""
Debug the workflow connections to understand why steps can't connect properly
"""

import json
from pathlib import Path

def analyze_workflow_connections():
    """Analyze workflow connections and identify connection issues"""
    
    print("🔍 Analyzing workflow connection issues...")
    
    try:
        # Load actual workflow data
        workflows_dir = Path("lib/galaxy/ai/data/workflows")
        workflow_file = list(workflows_dir.glob("workflow_*.json"))[0]
        
        with open(workflow_file, 'r', encoding='utf-8') as f:
            workflow_data = json.load(f)
        
        workflow_json = workflow_data.get("workflow_json", {})
        steps_data = workflow_json.get("steps", {})
        
        print(f"📁 Analyzing workflow: {workflow_file.name}")
        print(f"✓ Workflow: {workflow_data['metadata']['name']}")
        
        # Separate input and tool steps
        input_steps = {}
        tool_steps = {}
        
        for step_id, step_data in steps_data.items():
            step_id_int = int(step_id)
            if step_data.get("tool_id") is None:
                input_steps[step_id_int] = step_data
            else:
                tool_steps[step_id_int] = step_data
        
        print(f"\n📊 Step Analysis:")
        print(f"   Input steps: {len(input_steps)} - {sorted(input_steps.keys())}")
        print(f"   Tool steps: {len(tool_steps)} - {sorted(tool_steps.keys())}")
        
        # Analyze input step details
        print(f"\n📥 Input Steps Details:")
        for step_id, step_data in input_steps.items():
            step_type = step_data.get('type', 'unknown')
            label = step_data.get('label', 'No label')
            print(f"   Step {step_id}: {step_type} - '{label}'")
            
            if 'inputs' in step_data and step_data['inputs']:
                for inp in step_data['inputs']:
                    inp_name = inp.get('name', 'unnamed')
                    inp_desc = inp.get('description', '')[:50]
                    print(f"     → Input: {inp_name} - {inp_desc}")
        
        # Analyze which tool steps originally connected to input steps
        print(f"\n🔗 Original Connections to Input Steps:")
        broken_connections = {}
        
        for step_id, step_data in tool_steps.items():
            connections = step_data.get('input_connections', {})
            for input_name, connection in connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    if target_id in input_steps:
                        tool_name = step_data.get('label', f"Step {step_id}")
                        input_step_label = input_steps[target_id].get('label', f"Input {target_id}")
                        output_name = connection.get('output_name', 'output')
                        
                        if step_id not in broken_connections:
                            broken_connections[step_id] = []
                        broken_connections[step_id].append({
                            'input_name': input_name,
                            'target_step': target_id,
                            'target_label': input_step_label,
                            'output_name': output_name
                        })
        
        print(f"   Found {len(broken_connections)} tool steps with broken input connections:")
        for step_id, connections in broken_connections.items():
            tool_name = tool_steps[step_id].get('label', f"Step {step_id}")
            print(f"   Step {step_id} ({tool_name}):")
            for conn in connections:
                print(f"     → {conn['input_name']} was connected to {conn['target_label']} (step {conn['target_step']}) output '{conn['output_name']}'")
        
        # Analyze step dependencies after filtering
        print(f"\n🔄 Step Dependencies After Filtering:")
        remaining_connections = {}
        orphaned_steps = []
        
        for step_id, step_data in tool_steps.items():
            connections = step_data.get('input_connections', {})
            valid_connections = {}
            
            for input_name, connection in connections.items():
                if isinstance(connection, dict) and 'id' in connection:
                    target_id = connection['id']
                    if target_id in tool_steps:  # Only connections to other tool steps
                        valid_connections[input_name] = connection
            
            if valid_connections:
                remaining_connections[step_id] = valid_connections
            elif step_id in broken_connections:
                # This step had connections but they were all to input steps
                orphaned_steps.append(step_id)
        
        print(f"   Steps with valid connections: {len(remaining_connections)}")
        print(f"   Orphaned steps (no inputs after filtering): {len(orphaned_steps)}")
        
        if orphaned_steps:
            print(f"   Orphaned steps: {sorted(orphaned_steps)}")
            for step_id in sorted(orphaned_steps):
                tool_name = tool_steps[step_id].get('label', f"Step {step_id}")
                tool_id = tool_steps[step_id].get('tool_id', 'unknown')[:50]
                print(f"     → Step {step_id}: {tool_name} ({tool_id})")
        
        # Suggest solutions
        print(f"\n💡 Solutions to Fix Connection Issues:")
        print(f"   1. Convert input step connections to workflow inputs")
        print(f"   2. Create proper input dataset declarations") 
        print(f"   3. Map original input step outputs to workflow parameters")
        
        # Analyze what types of inputs we need
        print(f"\n📋 Required Workflow Inputs (based on broken connections):")
        input_types = {}
        
        for step_id in input_steps:
            step_data = input_steps[step_id]
            step_type = step_data.get('type')
            label = step_data.get('label', f'Input {step_id}')
            
            if step_type == 'data_collection_input':
                tool_state = step_data.get('tool_state', '{}')
                try:
                    state_data = json.loads(tool_state) if isinstance(tool_state, str) else tool_state
                    collection_type = state_data.get('collection_type', 'unknown')
                    formats = state_data.get('format', [])
                    input_types[step_id] = {
                        'type': 'data_collection',
                        'collection_type': collection_type,
                        'formats': formats,
                        'label': label
                    }
                except:
                    input_types[step_id] = {'type': 'data_collection', 'label': label}
                    
            elif step_type == 'parameter_input':
                tool_state = step_data.get('tool_state', '{}')
                try:
                    state_data = json.loads(tool_state) if isinstance(tool_state, str) else tool_state
                    param_type = state_data.get('parameter_type', 'unknown')
                    input_types[step_id] = {
                        'type': 'parameter',
                        'parameter_type': param_type,
                        'label': label
                    }
                except:
                    input_types[step_id] = {'type': 'parameter', 'label': label}
        
        for step_id, input_info in input_types.items():
            print(f"   Input {step_id}: {input_info}")
        
        return {
            'input_steps': input_steps,
            'tool_steps': tool_steps,
            'broken_connections': broken_connections,
            'orphaned_steps': orphaned_steps,
            'required_inputs': input_types
        }
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    print("=== Workflow Connection Analysis ===\n")
    
    result = analyze_workflow_connections()
    
    if result:
        print(f"\n✅ Analysis complete! Key issues identified:")
        print(f"   • {len(result['broken_connections'])} tool steps lost their input connections")
        print(f"   • {len(result['orphaned_steps'])} steps are now orphaned (no inputs)")
        print(f"   • {len(result['required_inputs'])} workflow inputs need to be created")
        print(f"\nNext step: Modify the connection cleaning logic to create proper workflow inputs")
    else:
        print(f"\n💥 Analysis failed!")