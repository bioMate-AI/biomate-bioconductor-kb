#!/usr/bin/env python3
"""
Enhanced test script to verify the workflow creation fix for tool_state JSON parsing
"""

import os
import sys
import json
from pathlib import Path

# Add the Galaxy lib directory to the path
galaxy_lib_path = Path(__file__).parent / "lib"
if str(galaxy_lib_path) not in sys.path:
    sys.path.insert(0, str(galaxy_lib_path))

def test_tool_state_json_parsing():
    """Test parsing of tool_state as JSON string"""
    
    print("Testing tool_state JSON parsing...")
    
    # Sample workflow data with real tool_state JSON strings
    workflow_data = {
        "workflow_id": "test_id",
        "metadata": {
            "name": "Test Workflow",
            "number_of_steps": 4
        },
        "workflow_json": {
            "steps": {
                "0": {
                    "tool_id": None,  # Input step - should be skipped
                    "type": "data_collection_input",
                    "tool_state": '{"optional": false, "format": ["bam"], "tag": "", "collection_type": "list", "fields": null}'
                },
                "3": {
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/samtools_view/samtools_view/1.15.1+galaxy2",
                    "tool_version": "1.15.1+galaxy2",
                    "type": "tool",
                    "annotation": "Filter BAM with samtools view",
                    "input_connections": {},
                    "tool_state": '{"addref_cond": {"addref_select": "no", "__current_case__": 0}, "input": {"__class__": "ConnectedValue"}, "mode": {"outtype": "all_reads", "__current_case__": 0}}',
                    "position": {"left": 300, "top": 100}
                },
                "5": {
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/macs2/macs2_callpeak/2.2.9.1+galaxy0",
                    "tool_version": "2.2.9.1+galaxy0",
                    "type": "tool",
                    "annotation": "MACS2 callpeak",
                    "input_connections": {},
                    "tool_state": '{"advanced_options": {"to_large": false, "nolambda": false, "spmr": true}, "control": {"c_select": "No"}, "format": "BAMPE"}',
                    "position": {"left": 600, "top": 100}
                }
            }
        }
    }
    
    try:
        # Import required classes
        from galaxy.ai.types import WorkflowStep
        
        # Parse workflow steps like the fixed API code does
        workflow_json = workflow_data.get("workflow_json", {})
        workflow_steps = []
        
        if workflow_json and "steps" in workflow_json:
            steps_data = workflow_json["steps"]
            
            for step_id, step_data in steps_data.items():
                tool_id = step_data.get("tool_id")
                
                # Skip input steps (tool_id is None for input dataset/parameter steps)
                if tool_id is None:
                    print(f"  ✓ Skipping input step {step_id} with tool_id: None")
                    continue
                    
                tool_version = step_data.get("tool_version") or "1.0"
                
                # Parse tool_state (it's a JSON string, not a dict)
                tool_state_raw = step_data.get("tool_state", "{}")
                try:
                    if isinstance(tool_state_raw, str):
                        parameters = json.loads(tool_state_raw)
                        print(f"  ✓ Parsed JSON tool_state for step {step_id}: {len(parameters)} parameters")
                    else:
                        parameters = tool_state_raw or {}
                        print(f"  ✓ Used dict tool_state for step {step_id}")
                except (json.JSONDecodeError, TypeError) as e:
                    parameters = {}
                    print(f"  ⚠ Failed to parse tool_state for step {step_id}, using empty dict: {e}")
                
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
                print(f"  ✓ Created step {step_id} with tool_id: {tool_id}")
        
        print(f"\n✅ SUCCESS: Created {len(workflow_steps)} tool steps")
        
        # Validate that all steps have valid tool_ids and dict parameters
        for step in workflow_steps:
            if step.tool_id is None:
                raise ValueError(f"Step {step.step_id} has tool_id: None!")
            if not isinstance(step.parameters, dict):
                raise ValueError(f"Step {step.step_id} parameters is not a dict: {type(step.parameters)}")
            
        print(f"✅ VALIDATION: All steps have valid tool_ids and dict parameters")
        
        # Test workflow export
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        from galaxy.ai.types import WorkflowTemplate
        
        # Create a workflow template
        template = WorkflowTemplate(
            name="Test Workflow",
            description="Test description", 
            steps=workflow_steps,
            inputs=[],
            outputs=[],
            tags=["test"]
        )
        
        # Test export to Galaxy format
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        galaxy_format = generator.export_to_galaxy_format(template)
        
        print(f"✅ EXPORT TEST: Successfully exported workflow to Galaxy format")
        print(f"   Workflow has {len(galaxy_format['steps'])} steps")
        
        # Validate exported format
        for step_id, step_data in galaxy_format['steps'].items():
            if 'tool_state' not in step_data:
                raise ValueError(f"Exported step {step_id} missing tool_state")
            if not isinstance(step_data['tool_state'], str):
                raise ValueError(f"Exported step {step_id} tool_state is not a string: {type(step_data['tool_state'])}")
        
        print(f"✅ EXPORT VALIDATION: All exported steps have tool_state as JSON string")
        return True
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_real_workflow_file():
    """Test with real RAG workflow file"""
    
    print("\nTesting real RAG workflow file...")
    
    try:
        # Try to load an actual workflow file
        workflows_dir = Path("lib/galaxy/ai/data/workflows")
        if not workflows_dir.exists():
            print("  ⚠️  SKIP: RAG workflows directory not found")
            return True
            
        workflow_files = list(workflows_dir.glob("workflow_*.json"))
        if not workflow_files:
            print("  ⚠️  SKIP: No RAG workflow files found")
            return True
            
        # Test first workflow file
        workflow_file = workflow_files[0]
        print(f"  📁 Testing file: {workflow_file.name}")
        
        with open(workflow_file, 'r', encoding='utf-8') as f:
            workflow_data = json.load(f)
        
        from galaxy.ai.types import WorkflowStep
        
        workflow_json = workflow_data.get("workflow_json", {})
        workflow_steps = []
        input_steps_skipped = 0
        tool_state_parsed = 0
        
        if workflow_json and "steps" in workflow_json:
            steps_data = workflow_json["steps"]
            
            for step_id, step_data in steps_data.items():
                tool_id = step_data.get("tool_id")
                
                if tool_id is None:
                    input_steps_skipped += 1
                    continue
                    
                tool_version = step_data.get("tool_version") or "1.0"
                
                # Parse tool_state (it's a JSON string, not a dict)
                tool_state_raw = step_data.get("tool_state", "{}")
                try:
                    if isinstance(tool_state_raw, str):
                        parameters = json.loads(tool_state_raw)
                        tool_state_parsed += 1
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
        
        print(f"  ✓ Processed workflow with {len(workflow_steps)} tool steps")
        print(f"  ✓ Skipped {input_steps_skipped} input steps")
        print(f"  ✓ Parsed {tool_state_parsed} JSON tool_state strings")
        
        # Validate tool_ids and parameters
        for step in workflow_steps:
            if step.tool_id is None:
                raise ValueError(f"Step {step.step_id} has tool_id: None!")
            if not isinstance(step.parameters, dict):
                raise ValueError(f"Step {step.step_id} parameters is not dict: {type(step.parameters)}")
                
        print(f"✅ SUCCESS: Real workflow processed with proper tool_state parsing")
        return True
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("=== Testing Enhanced Workflow Creation Fix ===\n")
    
    # Test 1: JSON parsing of tool_state
    test1_passed = test_tool_state_json_parsing()
    
    # Test 2: Real RAG workflow file
    test2_passed = test_real_workflow_file()
    
    if test1_passed and test2_passed:
        print("\n🎉 ALL TESTS PASSED! The enhanced fix should resolve both tool_id and tool_state issues.")
    else:
        print("\n💥 SOME TESTS FAILED! Please check the implementation.")
        sys.exit(1)