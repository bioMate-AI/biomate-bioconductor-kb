#!/usr/bin/env python3

import json
import sys
import os

# Add the lib directory to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

from galaxy.ai.workflow_generator import WorkflowGenerator
from galaxy.ai.config import DEFAULT_AI_CONFIG
from galaxy.ai.types import WorkflowStep, WorkflowTemplate

def test_complex_workflow_fix():
    """
    Test the fix with a more complex workflow that has multiple input steps
    and step-to-step connections, similar to what RAG workflows generate.
    """
    
    print("🔬 Testing complex workflow input connection fix...")
    
    # Create a realistic workflow with multiple inputs and interconnected steps
    workflow_steps = [
        # Step that depends on input step 0
        WorkflowStep(
            step_id=1,
            tool_id="toolshed.g2.bx.psu.edu/repos/iuc/fastqc/fastqc/0.72+galaxy1",
            tool_version="0.72+galaxy1",
            input_connections={
                'input_file': {
                    'id': 'workflow_input_0',
                    'output_name': 'output',
                    '_original_input_step': 0,
                    '_input_label': 'Raw reads'
                }
            },
            parameters={},
            annotation="Quality control of raw reads",
            position={'left': 200, 'top': 100}
        ),
        # Step that depends on input step 2 (parameter)
        WorkflowStep(
            step_id=3,
            tool_id="toolshed.g2.bx.psu.edu/repos/iuc/trim_galore/trim_galore/0.6.7+galaxy0",
            tool_version="0.6.7+galaxy0",
            input_connections={
                'singlePaired|input_singles': {
                    'id': 'workflow_input_0',  # Same input as step 1
                    'output_name': 'output',
                    '_original_input_step': 0,
                    '_input_label': 'Raw reads'
                }
            },
            parameters={
                'singlePaired': {'sPaired': 'single'},
                'params': {'settingsType': 'default'}
            },
            annotation="Trim adapters and low quality bases",
            position={'left': 200, 'top': 300}
        ),
        # Step that depends on previous tool step (step 3) and another input
        WorkflowStep(
            step_id=4,
            tool_id="toolshed.g2.bx.psu.edu/repos/iuc/hisat2/hisat2/2.2.1+galaxy0",
            tool_version="2.2.1+galaxy0",
            input_connections={
                'library|input_1': {
                    'id': 3,  # References step 3 (trim_galore)
                    'output_name': 'trimmed_reads'
                },
                'reference_genome|index': {
                    'id': 'workflow_input_1',  # Reference genome input
                    'output_name': 'output',
                    '_original_input_step': 1,
                    '_input_label': 'Reference genome'
                }
            },
            parameters={
                'library': {'type': 'single'},
                'reference_genome': {'source': 'history'}
            },
            annotation="Align trimmed reads to reference genome",
            position={'left': 400, 'top': 300}
        ),
        # Final step that depends on step 4
        WorkflowStep(
            step_id=5,
            tool_id="toolshed.g2.bx.psu.edu/repos/iuc/samtools_sort/samtools_sort/1.13+galaxy1",
            tool_version="1.13+galaxy1",
            input_connections={
                'input1': {
                    'id': 4,  # References step 4 (hisat2)
                    'output_name': 'output_alignments'
                }
            },
            parameters={
                'sort_mode': 'coordinate'
            },
            annotation="Sort aligned reads by coordinate",
            position={'left': 600, 'top': 300}
        )
    ]
    
    # Multiple workflow inputs
    workflow_inputs = [
        {
            'label': 'Raw reads',
            'name': 'input_0',
            'type': 'data',
            'format': 'fastqsanger',
            'optional': False,
            'description': 'Raw sequencing reads'
        },
        {
            'label': 'Reference genome',
            'name': 'input_1', 
            'type': 'data',
            'format': 'fasta',
            'optional': False,
            'description': 'Reference genome for alignment'
        },
        {
            'label': 'Quality threshold',
            'name': 'input_2',
            'type': 'parameter',
            'parameter_type': 'integer',
            'optional': True,
            'description': 'Minimum quality score threshold'
        }
    ]
    
    # Create workflow template
    workflow_template = WorkflowTemplate(
        name="RNA-seq Analysis Pipeline",
        description="Complete RNA-seq analysis from raw reads to sorted alignments",
        steps=workflow_steps,
        inputs=workflow_inputs,
        outputs=[],
        tags=['rna-seq', 'alignment', 'quality-control']
    )
    
    print(f"✓ Created complex workflow: {len(workflow_steps)} steps, {len(workflow_inputs)} inputs")
    
    # Export and validate
    try:
        generator = WorkflowGenerator(DEFAULT_AI_CONFIG)
        galaxy_workflow = generator.export_to_galaxy_format(workflow_template)
        
        print(f"✅ Export successful! Galaxy workflow has {len(galaxy_workflow['steps'])} total steps")
        
        # Detailed validation
        step_ids = set(int(step_id) for step_id in galaxy_workflow['steps'].keys())
        print(f"✓ Step IDs: {sorted(step_ids)}")
        
        # Check connections
        for step_id, step_data in galaxy_workflow['steps'].items():
            input_connections = step_data.get('input_connections', {})
            if input_connections:
                print(f"✓ Step {step_id} connections: {list(input_connections.keys())}")
                
                # Verify no workflow_input_ markers remain
                for input_name, connection in input_connections.items():
                    if isinstance(connection, dict):
                        conn_id = connection.get('id')
                        if isinstance(conn_id, str) and conn_id.startswith('workflow_input_'):
                            raise Exception(f"Found unresolved workflow_input_ marker: {conn_id}")
                        if conn_id not in step_ids:
                            raise Exception(f"Connection to non-existent step: {conn_id}")
        
        print("✅ All connections properly resolved and validated")
        
        # Test JSON serialization (what Galaxy does)
        try:
            json_workflow = json.dumps(galaxy_workflow, indent=2)
            print("✅ Workflow JSON serialization successful")
        except Exception as json_error:
            raise Exception(f"JSON serialization failed: {json_error}")
        
        print(f"\n🎉 COMPLEX WORKFLOW TEST PASSED!")
        return True
        
    except Exception as e:
        print(f"❌ Test failed: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = test_complex_workflow_fix()
    sys.exit(0 if success else 1)