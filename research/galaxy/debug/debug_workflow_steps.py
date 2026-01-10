#!/usr/bin/env python3
"""
Debug script to trace through the complete workflow creation process 
and identify any remaining issues
"""

import os
import sys
import json
from pathlib import Path

# Add the Galaxy lib directory to the path
galaxy_lib_path = Path(__file__).parent / "lib"
if str(galaxy_lib_path) not in sys.path:
    sys.path.insert(0, str(galaxy_lib_path))

def simulate_workflow_creation_process():
    """Simulate the complete workflow creation process from AI assistant"""
    
    print("🔍 Simulating complete workflow creation process...")
    
    try:
        # Step 1: Load RAG workflow data (like the API does)
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
        print(f"📁 Using workflow file: {workflow_file.name}")
        
        with open(workflow_file, 'r', encoding='utf-8') as f:
            workflow_data = json.load(f)
        
        best_match = {
            "workflow_id": workflow_data["workflow_id"],
            "name": workflow_data["metadata"]["name"],
            "description": workflow_data["metadata"].get("annotations", [""])[0] if workflow_data["metadata"].get("annotations") else "",
            "similarity_score": 12.5,
            "workflow_json": workflow_data["workflow_json"]
        }
        
        print(f"✓ Loaded workflow: {best_match['name']}")
        print(f"✓ Workflow has {len(best_match['workflow_json']['steps'])} total steps")
        
        # Step 2: Create WorkflowStep objects (like ai_assistant.py does)
        from galaxy.ai.types import WorkflowStep, WorkflowTemplate
        
        workflow_json = best_match.get("workflow_json", {})
        workflow_steps = []
        
        if workflow_json and "steps" in workflow_json:
            steps_data = workflow_json["steps"]
            input_steps = 0
            tool_steps = 0
            
            for step_id, step_data in steps_data.items():
                tool_id = step_data.get("tool_id")
                
                # Skip input steps (tool_id is None for input dataset/parameter steps)
                if tool_id is None:
                    input_steps += 1
                    print(f"  → Skipping input step {step_id}: {step_data.get('type', 'unknown')}")
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
                tool_steps += 1
                
                print(f"  ✓ Tool step {step_id}: {tool_id[:50]}{'...' if len(tool_id) > 50 else ''}")
        
            # Sort steps by step_id to maintain order
            workflow_steps.sort(key=lambda x: x.step_id)
            
            print(f"✓ Processed {input_steps} input steps (skipped), {tool_steps} tool steps (kept)")
        
        # Step 3: Create WorkflowTemplate (like ai_assistant.py does)
        workflow_template = WorkflowTemplate(
            name=best_match["name"],
            description=best_match["description"],
            steps=workflow_steps,
            inputs=[],  # Will be populated by Galaxy
            outputs=[],  # Will be populated by Galaxy 
            tags=workflow_data["metadata"].get("tags", [])
        )
        
        print(f"✓ Created WorkflowTemplate with {len(workflow_template.steps)} steps")
        
        # Step 4: Export to Galaxy format (like workflow_generator.py does)
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG
        
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
        
        print(f"✓ Exported to Galaxy format with {len(galaxy_workflow['steps'])} steps")
        
        # Step 5: Validate the final Galaxy workflow format
        print("\n🔍 Validating final Galaxy workflow format...")
        
        required_fields = ['a_galaxy_workflow', 'name', 'steps', 'format-version']
        for field in required_fields:
            if field not in galaxy_workflow:
                raise ValueError(f"Missing required field: {field}")
        
        print("✓ All required top-level fields present")
        
        # Validate each step
        for step_id, step_data in galaxy_workflow['steps'].items():
            required_step_fields = ['id', 'type', 'tool_id', 'tool_version', 'tool_state']
            for field in required_step_fields:
                if field not in step_data:
                    raise ValueError(f"Step {step_id} missing required field: {field}")
            
            # Validate tool_state is a JSON string
            if not isinstance(step_data['tool_state'], str):
                raise ValueError(f"Step {step_id} tool_state should be string, got {type(step_data['tool_state'])}")
            
            # Validate tool_state can be parsed as JSON
            try:
                json.loads(step_data['tool_state'])
            except json.JSONDecodeError as e:
                raise ValueError(f"Step {step_id} tool_state is not valid JSON: {e}")
        
        print(f"✓ All {len(galaxy_workflow['steps'])} steps have valid format and JSON tool_state")
        
        # Step 6: Test JSON serialization (what happens when sending to Galaxy API)
        try:
            final_json = json.dumps(galaxy_workflow, indent=2)
            print(f"✓ Final workflow JSON serialization successful ({len(final_json)} chars)")
        except Exception as e:
            raise ValueError(f"Failed to serialize final workflow to JSON: {e}")
        
        print(f"\n🎉 COMPLETE SUCCESS: End-to-end workflow creation simulation passed!")
        print(f"   Original workflow: {len(workflow_data['workflow_json']['steps'])} steps")
        print(f"   Input steps filtered: {input_steps}")  
        print(f"   Tool steps processed: {tool_steps}")
        print(f"   Final Galaxy workflow: {len(galaxy_workflow['steps'])} steps")
        
        return True
        
    except Exception as e:
        print(f"\n❌ SIMULATION FAILED: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("=== Complete Workflow Creation Debug ===\n")
    
    success = simulate_workflow_creation_process()
    
    if success:
        print("\n✅ The workflow creation process should now work without errors!")
    else:
        print("\n💥 There are still issues that need to be addressed.")
        sys.exit(1)