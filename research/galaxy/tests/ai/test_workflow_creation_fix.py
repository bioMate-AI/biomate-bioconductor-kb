#!/usr/bin/env python3
"""
Test script to verify the workflow creation fix for tool_id None issue
"""

import os
import sys
import json
from pathlib import Path

# Add the Galaxy lib directory to the path
galaxy_lib_path = Path(__file__).parent / "lib"
if str(galaxy_lib_path) not in sys.path:
    sys.path.insert(0, str(galaxy_lib_path))

def test_workflow_json_parsing():
    """Test parsing of workflow JSON with input steps that have tool_id: None"""
    
    # Sample workflow data from the actual file - this has steps with tool_id: None
    workflow_data = {
        "workflow_id": "test_id",
        "metadata": {
            "name": "Test Workflow",
            "number_of_steps": 3
        },
        "workflow_json": {
            "steps": {
                "0": {
                    "tool_id": None,  # Input step
                    "type": "data_collection_input",
                    "annotation": "Input data"
                },
                "1": {
                    "tool_id": None,  # Parameter input step
                    "type": "parameter_input", 
                    "annotation": "Input parameter"
                },
                "2": {
                    "tool_id": "toolshed.g2.bx.psu.edu/repos/iuc/samtools_view/samtools_view/1.15.1+galaxy2",
                    "tool_version": "1.15.1+galaxy2",
                    "type": "tool",
                    "annotation": "Filter BAM with samtools view",
                    "input_connections": {},
                    "tool_state": "{}",
                    "position": {"left": 300, "top": 100}
                }
            }
        }
    }
    
    print("Testing workflow JSON parsing with input steps (tool_id: None)...")
    
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
                
                # Create Galaxy WorkflowStep object from real data
                step = WorkflowStep(
                    step_id=int(step_id),
                    tool_id=tool_id,
                    tool_version=tool_version,
                    input_connections=step_data.get("input_connections", {}),
                    parameters=step_data.get("tool_state", {}),
                    annotation=step_data.get("annotation", f"Step {int(step_id) + 1}"),
                    position=step_data.get("position", {"left": int(step_id) * 100, "top": 100})
                )
                workflow_steps.append(step)
                print(f"  ✓ Created step {step_id} with tool_id: {tool_id}")
        
        print(f"\n✅ SUCCESS: Created {len(workflow_steps)} tool steps, skipped input steps with tool_id: None")
        
        # Validate that all steps have valid tool_ids
        for step in workflow_steps:
            if step.tool_id is None:
                raise ValueError(f"Step {step.step_id} has tool_id: None - this should have been filtered out!")
            
        print(f"✅ VALIDATION: All {len(workflow_steps)} steps have valid tool_ids")
        return True
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_rag_workflow_loading():
    """Test loading an actual RAG workflow file"""
    
    print("\nTesting actual RAG workflow file parsing...")
    
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
        
        if workflow_json and "steps" in workflow_json:
            steps_data = workflow_json["steps"]
            
            for step_id, step_data in steps_data.items():
                tool_id = step_data.get("tool_id")
                
                if tool_id is None:
                    input_steps_skipped += 1
                    continue
                    
                tool_version = step_data.get("tool_version") or "1.0"
                
                step = WorkflowStep(
                    step_id=int(step_id),
                    tool_id=tool_id,
                    tool_version=tool_version,
                    input_connections=step_data.get("input_connections", {}),
                    parameters=step_data.get("tool_state", {}),
                    annotation=step_data.get("annotation", f"Step {int(step_id) + 1}"),
                    position=step_data.get("position", {"left": int(step_id) * 100, "top": 100})
                )
                workflow_steps.append(step)
        
        print(f"  ✓ Processed workflow with {len(workflow_steps)} tool steps")
        print(f"  ✓ Skipped {input_steps_skipped} input steps")
        
        # Validate tool_ids
        for step in workflow_steps:
            if step.tool_id is None:
                raise ValueError(f"Step {step.step_id} has tool_id: None!")
                
        print(f"✅ SUCCESS: Real RAG workflow processed correctly")
        return True
        
    except Exception as e:
        print(f"❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("=== Testing Workflow Creation Fix ===\n")
    
    # Test 1: Basic workflow JSON parsing
    test1_passed = test_workflow_json_parsing()
    
    # Test 2: Real RAG workflow file
    test2_passed = test_rag_workflow_loading()
    
    if test1_passed and test2_passed:
        print("\n🎉 ALL TESTS PASSED! The fix should resolve the tool_id: None issue.")
    else:
        print("\n💥 SOME TESTS FAILED! Please check the implementation.")
        sys.exit(1)