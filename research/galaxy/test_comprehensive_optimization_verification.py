#!/usr/bin/env python3
"""
Comprehensive test to verify all optimizations and improvements made to the workflow generation system.
"""

import sys
sys.path.insert(0, 'lib')

def test_comprehensive_system():
    """Run comprehensive tests of the optimized workflow generation system."""

    print("=" * 80)
    print("🔬 COMPREHENSIVE OPTIMIZATION VERIFICATION")
    print("=" * 80)

    results = {
        "prompt_optimization": False,
        "rag_system": False,
        "workflow_generation": False,
        "api_integration": False
    }

    # 1. Test Prompt Optimization
    print("\n1️⃣  TESTING PROMPT OPTIMIZATION...")
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG

        generator = WorkflowGenerator(config=DEFAULT_AI_CONFIG)

        user_request = "Analyze single-cell RNA-seq data to identify cell types"
        context = "Basic RNA-seq workflow with HISAT2, featureCounts, DESeq2"

        prompt = generator._create_workflow_generation_prompt(user_request, context)

        # Check anti-imitation features
        anti_imitation_features = [
            "DO NOT copy or replicate",
            "FOCUS PRIMARILY on the user's specific request",
            "Be creative and innovative",
            "CUSTOM solution, not a copy"
        ]

        features_present = sum(1 for feature in anti_imitation_features if feature in prompt)

        print(f"   ✅ Prompt generated successfully ({len(prompt)} chars)")
        print(f"   ✅ Anti-imitation features present: {features_present}/{len(anti_imitation_features)}")

        if features_present >= 3:
            results["prompt_optimization"] = True
            print("   🎯 Prompt optimization: PASSED")
        else:
            print("   ❌ Prompt optimization: FAILED")

    except Exception as e:
        print(f"   ❌ Prompt optimization test failed: {str(e)}")

    # 2. Test RAG System
    print("\n2️⃣  TESTING RAG SYSTEM...")
    try:
        from galaxy.ai.rag_workflow_loader import RAGWorkflowRecommender

        data_path = "/Users/renyuankai/work/pywork/normalWork/galaxy_爬虫/galaxy_crawler/galaxy_workflows_crawler_details/output"
        recommender = RAGWorkflowRecommender(data_path)

        # Test search
        search_result = recommender.get_workflow_recommendations(
            "RNA-seq differential expression analysis",
            max_recommendations=3
        )

        workflow_count = len(recommender.rag_engine.workflows)
        search_success = search_result.get('status') == 'success'
        recommendations_count = len(search_result.get('recommendations', []))

        print(f"   ✅ RAG system initialized with {workflow_count} workflows")
        print(f"   ✅ Search executed successfully: {search_success}")
        print(f"   ✅ Recommendations returned: {recommendations_count}")

        if workflow_count > 900 and search_success and recommendations_count > 0:
            results["rag_system"] = True
            print("   🎯 RAG system: PASSED")
        else:
            print("   ❌ RAG system: FAILED")

    except Exception as e:
        print(f"   ❌ RAG system test failed: {str(e)}")

    # 3. Test Workflow Generation
    print("\n3️⃣  TESTING WORKFLOW GENERATION...")
    try:
        from galaxy.ai.workflow_generator import WorkflowGenerator
        from galaxy.ai.config import DEFAULT_AI_CONFIG

        generator = WorkflowGenerator(config=DEFAULT_AI_CONFIG)

        user_request = "Perform ChIP-seq analysis to find protein-DNA binding sites"
        similar_workflows = [
            {
                "name": "ChIP-seq Peak Calling",
                "description": "Basic ChIP-seq analysis workflow",
                "steps": [{"tool_id": "macs2"}, {"tool_id": "deeptools"}],
                "similarity_score": 8.5
            }
        ]

        result = generator.generate_workflow_with_context(user_request, similar_workflows)

        generation_success = result.get('success', False)
        has_workflow = 'workflow' in result
        workflow_steps = len(result.get('workflow', {}).get('steps', [])) if has_workflow else 0

        print(f"   ✅ Workflow generation executed: {generation_success}")
        print(f"   ✅ Workflow structure created: {has_workflow}")
        print(f"   ✅ Workflow steps generated: {workflow_steps}")

        if generation_success and has_workflow and workflow_steps > 0:
            results["workflow_generation"] = True
            print("   🎯 Workflow generation: PASSED")
        else:
            print("   ❌ Workflow generation: FAILED")

    except Exception as e:
        print(f"   ❌ Workflow generation test failed: {str(e)}")

    # 4. Test API Integration (without actual server)
    print("\n4️⃣  TESTING API INTEGRATION STRUCTURE...")
    try:
        # Test if API components are properly structured
        from galaxy.webapps.galaxy.api import ai_assistant
        from galaxy.ai.ai_assistant import AIAssistant

        # Check if key functions exist
        has_two_stage_function = hasattr(ai_assistant, 'get_two_stage_workflow')
        has_ai_assistant_init = hasattr(AIAssistant, '__init__')

        print(f"   ✅ Two-stage API function exists: {has_two_stage_function}")
        print(f"   ✅ AI Assistant class available: {has_ai_assistant_init}")

        if has_two_stage_function and has_ai_assistant_init:
            results["api_integration"] = True
            print("   🎯 API integration structure: PASSED")
        else:
            print("   ❌ API integration structure: FAILED")

    except Exception as e:
        print(f"   ❌ API integration test failed: {str(e)}")

    # Final Results Summary
    print("\n" + "=" * 80)
    print("📊 COMPREHENSIVE TEST RESULTS")
    print("=" * 80)

    passed_tests = sum(results.values())
    total_tests = len(results)

    for test_name, passed in results.items():
        status = "✅ PASSED" if passed else "❌ FAILED"
        formatted_name = test_name.replace("_", " ").title()
        print(f"   {formatted_name:.<40} {status}")

    print(f"\n📈 Overall Score: {passed_tests}/{total_tests} ({passed_tests/total_tests*100:.1f}%)")

    if passed_tests == total_tests:
        print("🎉 ALL OPTIMIZATIONS WORKING CORRECTLY!")
        final_status = "FULLY OPERATIONAL"
    elif passed_tests >= total_tests * 0.75:
        print("✅ MOST OPTIMIZATIONS WORKING - SYSTEM READY")
        final_status = "MOSTLY OPERATIONAL"
    elif passed_tests >= total_tests * 0.5:
        print("⚠️  SOME ISSUES DETECTED - NEEDS ATTENTION")
        final_status = "PARTIALLY OPERATIONAL"
    else:
        print("❌ SIGNIFICANT ISSUES - REQUIRES DEBUGGING")
        final_status = "NEEDS REPAIR"

    print(f"🎯 System Status: {final_status}")
    print("=" * 80)

    return passed_tests == total_tests

if __name__ == "__main__":
    success = test_comprehensive_system()
    exit_code = 0 if success else 1
    sys.exit(exit_code)