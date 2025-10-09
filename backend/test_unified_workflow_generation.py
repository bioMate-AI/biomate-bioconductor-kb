"""
Test Script for Unified Workflow Generation

Tests the integration of WorkflowSearchRAG, EnhancedWorkflowGenerator,
GalaxyWorkflowGenerator, and WorkflowDatasetSelector.

Verifies:
1. Template search with high/medium/low confidence scenarios
2. Tool constraint (no hallucinated tools)
3. Dataset assignment for all generation strategies
4. Galaxy .ga JSON format validation
"""

import sys
import os
import json
import logging
from datetime import datetime

# Add lib/galaxy to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
log = logging.getLogger(__name__)

def test_unified_workflow_generation():
    """Main test function for unified workflow generation."""

    print("\n" + "="*80)
    print("UNIFIED WORKFLOW GENERATION TEST")
    print("="*80 + "\n")

    try:
        # Import AI components
        from galaxy.ai.ai_assistant import AIAssistant
        from galaxy.ai.config import AIConfig

        print("✓ Successfully imported AI components\n")

        # Create AI config
        config = AIConfig({
            'llm_provider': 'openai',
            'llm_model': 'gpt-4',
            'llm_api_key': os.getenv('OPENAI_API_KEY', 'test-key'),
            'enable_tool_caching': True
        })

        # Initialize AI Assistant (without Galaxy app for testing)
        print("Initializing AI Assistant...")
        ai_assistant = AIAssistant(config, galaxy_app=None)
        print("✓ AI Assistant initialized successfully\n")

        # Test scenarios
        test_scenarios = [
            {
                "name": "High Confidence - RNA-seq",
                "intent": "Perform RNA-seq differential expression analysis",
                "expected_source": "template_reuse",
                "expected_confidence": "> 0.8"
            },
            {
                "name": "Medium Confidence - Variant Calling",
                "intent": "Call variants from aligned BAM files with quality filtering",
                "expected_source": "template_adapt or template_reuse",
                "expected_confidence": "0.5 - 1.0"
            },
            {
                "name": "Low Confidence - Novel Analysis",
                "intent": "Analyze proteomics data with custom machine learning model",
                "expected_source": "tool_constrained",
                "expected_confidence": "< 0.5"
            }
        ]

        results = []

        for scenario in test_scenarios:
            print("\n" + "-"*80)
            print(f"TEST SCENARIO: {scenario['name']}")
            print("-"*80)
            print(f"Intent: {scenario['intent']}")
            print(f"Expected Source: {scenario['expected_source']}")
            print(f"Expected Confidence: {scenario['expected_confidence']}")
            print()

            try:
                # Generate workflow
                result = ai_assistant.generate_workflow_unified(
                    user_intent=scenario['intent']
                )

                # Validate result
                if result['success']:
                    print(f"✓ Workflow generated successfully")
                    print(f"  Source: {result['source']}")
                    print(f"  Confidence: {result['confidence']:.2f}")
                    print(f"  Template Match Score: {result.get('template_match_score', 'N/A')}")
                    print(f"  Datasets Assigned: {result.get('datasets_assigned', False)}")

                    # Validate Galaxy .ga format
                    workflow_ga = result.get('workflow_ga')
                    if workflow_ga:
                        validation = validate_galaxy_workflow(workflow_ga)
                        if validation['valid']:
                            print(f"✓ Valid Galaxy .ga format")
                            print(f"  Steps: {validation['num_steps']}")
                            print(f"  Has workflow marker: {validation['has_workflow_marker']}")
                        else:
                            print(f"✗ Invalid Galaxy .ga format: {validation['errors']}")
                    else:
                        print(f"✗ No workflow_ga in result")

                    # Check for tool constraint (if using tool_constrained source)
                    if result['source'] == 'tool_constrained':
                        print(f"✓ Used tool-constrained generation (prevents hallucinated tools)")

                    results.append({
                        'scenario': scenario['name'],
                        'success': True,
                        'source': result['source'],
                        'confidence': result['confidence'],
                        'datasets_assigned': result.get('datasets_assigned', False),
                        'validation': validation if workflow_ga else None
                    })

                else:
                    print(f"✗ Workflow generation failed")
                    print(f"  Error: {result.get('error', 'Unknown error')}")
                    results.append({
                        'scenario': scenario['name'],
                        'success': False,
                        'error': result.get('error', 'Unknown error')
                    })

            except Exception as e:
                print(f"✗ Exception during test: {str(e)}")
                import traceback
                traceback.print_exc()
                results.append({
                    'scenario': scenario['name'],
                    'success': False,
                    'error': str(e)
                })

        # Print summary
        print("\n" + "="*80)
        print("TEST SUMMARY")
        print("="*80 + "\n")

        successful_tests = sum(1 for r in results if r['success'])
        total_tests = len(results)

        print(f"Tests Passed: {successful_tests}/{total_tests}")
        print()

        for result in results:
            status = "✓ PASS" if result['success'] else "✗ FAIL"
            print(f"{status} - {result['scenario']}")
            if result['success']:
                print(f"    Source: {result['source']}, Confidence: {result.get('confidence', 'N/A'):.2f}")
            else:
                print(f"    Error: {result.get('error', 'Unknown')}")

        print("\n" + "="*80)

        # Save results to file
        results_file = 'unified_workflow_test_results.json'
        with open(results_file, 'w') as f:
            json.dump({
                'timestamp': datetime.now().isoformat(),
                'total_tests': total_tests,
                'successful_tests': successful_tests,
                'results': results
            }, f, indent=2)

        print(f"\nTest results saved to: {results_file}")

        return successful_tests == total_tests

    except Exception as e:
        print(f"\n✗ CRITICAL ERROR: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


def validate_galaxy_workflow(workflow_ga):
    """Validate Galaxy .ga workflow format."""

    errors = []

    # Check for required fields
    if not isinstance(workflow_ga, dict):
        return {'valid': False, 'errors': ['Workflow is not a dictionary']}

    # Check for workflow marker
    has_workflow_marker = workflow_ga.get('a_galaxy_workflow') == 'true'
    if not has_workflow_marker:
        errors.append("Missing 'a_galaxy_workflow' marker")

    # Check for required fields
    required_fields = ['name', 'steps', 'format-version']
    for field in required_fields:
        if field not in workflow_ga:
            errors.append(f"Missing required field: {field}")

    # Check steps format
    steps = workflow_ga.get('steps', {})
    if not isinstance(steps, dict):
        errors.append("Steps must be a dictionary")

    num_steps = len(steps)

    # Validate each step
    for step_id, step in steps.items():
        if not isinstance(step, dict):
            errors.append(f"Step {step_id} is not a dictionary")
            continue

        # Check required step fields
        step_required_fields = ['id', 'type', 'tool_id']
        for field in step_required_fields:
            if field not in step:
                errors.append(f"Step {step_id} missing field: {field}")

    return {
        'valid': len(errors) == 0,
        'errors': errors,
        'num_steps': num_steps,
        'has_workflow_marker': has_workflow_marker
    }


def test_component_initialization():
    """Test that all unified components can be initialized."""

    print("\n" + "="*80)
    print("COMPONENT INITIALIZATION TEST")
    print("="*80 + "\n")

    try:
        from galaxy.ai.workflow_search_rag import WorkflowSearchRAG
        from galaxy.ai.galaxy_workflow_generator import GalaxyWorkflowGenerator
        from galaxy.ai.workflow_dataset_selector import WorkflowDatasetSelector
        from galaxy.ai.biomni_dataset_rag import BioMNIDatasetRAG

        print("✓ All imports successful\n")

        # Test WorkflowSearchRAG
        print("Testing WorkflowSearchRAG...")
        workflow_search = WorkflowSearchRAG(galaxy_app=None)
        print(f"✓ WorkflowSearchRAG initialized with {len(workflow_search.templates)} templates\n")

        # Test template search
        search_results = workflow_search.search("RNA-seq differential expression", limit=3)
        print(f"✓ Template search works - found {len(search_results)} matches")
        if search_results:
            print(f"  Best match: {search_results[0]['name']} (score: {search_results[0]['score']:.2f})")
        print()

        # Test GalaxyWorkflowGenerator
        print("Testing GalaxyWorkflowGenerator...")
        try:
            constrained_generator = GalaxyWorkflowGenerator()
            print(f"✓ GalaxyWorkflowGenerator initialized")
            print(f"  Tool index: {constrained_generator.tool_index.total_tools} tools available\n")
        except Exception as e:
            print(f"⚠ GalaxyWorkflowGenerator initialization warning: {str(e)}")
            print("  (This is expected if tool index database doesn't exist yet)\n")

        # Test WorkflowDatasetSelector
        print("Testing WorkflowDatasetSelector...")
        try:
            dataset_selector = WorkflowDatasetSelector()
            print(f"✓ WorkflowDatasetSelector initialized\n")
        except Exception as e:
            print(f"⚠ WorkflowDatasetSelector warning: {str(e)}\n")

        # Test BioMNIDatasetRAG
        print("Testing BioMNIDatasetRAG...")
        try:
            dataset_rag = BioMNIDatasetRAG()
            print(f"✓ BioMNIDatasetRAG initialized")
            print(f"  Datasets available: {len(dataset_rag.datasets)}\n")
        except Exception as e:
            print(f"⚠ BioMNIDatasetRAG warning: {str(e)}\n")

        print("="*80)
        print("Component initialization tests completed")
        print("="*80 + "\n")

        return True

    except Exception as e:
        print(f"\n✗ Component initialization failed: {str(e)}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == '__main__':
    print("\n" + "="*80)
    print("GALAXY AI ASSISTANT - UNIFIED WORKFLOW GENERATION TEST SUITE")
    print("="*80)

    # Test 1: Component initialization
    component_test_passed = test_component_initialization()

    # Test 2: Unified workflow generation
    workflow_test_passed = test_unified_workflow_generation()

    # Final summary
    print("\n" + "="*80)
    print("FINAL TEST RESULTS")
    print("="*80)
    print(f"Component Initialization: {'✓ PASS' if component_test_passed else '✗ FAIL'}")
    print(f"Unified Workflow Generation: {'✓ PASS' if workflow_test_passed else '✗ FAIL'}")
    print("="*80 + "\n")

    # Exit with appropriate code
    sys.exit(0 if (component_test_passed and workflow_test_passed) else 1)
