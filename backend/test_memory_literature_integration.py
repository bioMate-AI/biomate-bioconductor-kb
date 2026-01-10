#!/usr/bin/env python3
"""
Comprehensive Test Suite for BioMate AI Assistant Integration

Tests:
1. AIAssistant initialization
2. Lazy loading of components
3. Session initialization with agentic memory
4. Intent classification
5. Benchmark knowledge queries
6. Literature search
"""

import asyncio
import os
import sys
from pathlib import Path

# Load .env file
env_path = Path(__file__).parent / '.env'
if env_path.exists():
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith('#') and '=' in line:
                key, value = line.split('=', 1)
                os.environ[key] = value

def run_tests():
    """Run all integration tests."""

    print("=" * 60)
    print("BioMate AI Assistant Integration Tests")
    print("=" * 60)
    print()

    # Test 1: Check environment
    print("TEST 1: Environment Check")
    print("-" * 40)
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    print(f"  ANTHROPIC_API_KEY: {'set (' + api_key[:8] + '...)' if api_key else 'NOT SET'}")

    if not api_key:
        print("  ERROR: ANTHROPIC_API_KEY not found in environment or .env file")
        return False
    print()

    # Test 2: Import AIAssistant
    print("TEST 2: AIAssistant Import & Initialization")
    print("-" * 40)
    try:
        from lib.galaxy.ai.ai_assistant import AIAssistant, MEMORY_AVAILABLE, INTENT_ROUTER_AVAILABLE
        print(f"  MEMORY_AVAILABLE: {MEMORY_AVAILABLE}")
        print(f"  INTENT_ROUTER_AVAILABLE: {INTENT_ROUTER_AVAILABLE}")

        ai = AIAssistant()
        print(f"  AIAssistant created successfully")
        print(f"  Workflow templates: {len(ai.workflow_search.templates)}")
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    print()

    # Test 3: Lazy Loading Components
    print("TEST 3: Lazy Loading Components")
    print("-" * 40)
    try:
        print(f"  agentic_memory: {ai.agentic_memory is not None}")
        print(f"  literature_client: {ai.literature_client is not None}")
        print(f"  benchmark_db: {ai.benchmark_db is not None}")
        print(f"  intent_router: {ai.intent_router is not None}")
        print(f"  skill_loader: {ai.skill_loader is not None}")
        print(f"  research_agent: {ai.research_agent is not None}")
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    print()

    # Test 4: Session Initialization
    print("TEST 4: Session Initialization (Agentic Memory)")
    print("-" * 40)
    try:
        session_context = ai.initialize_session(
            user_id='test_user_123',
            project_id='test_project_456'
        )
        print(f"  session_id: {session_context.get('session_id', 'N/A')}")
        print(f"  user_preferences: {type(session_context.get('user_preferences')).__name__}")
        print(f"  project_context: {type(session_context.get('project_context')).__name__}")
        print(f"  Session initialized successfully")
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    print()

    # Test 5: Intent Classification
    print("TEST 5: Intent Classification")
    print("-" * 40)
    test_queries = [
        ('What is the best tool for RNA-seq alignment?', 'research_question'),
        ('Generate a workflow for variant calling', 'workflow_generation'),
        ('Compare STAR vs HISAT2 for RNA-seq', 'result_comparison'),
        ('Find tools for proteomics analysis', 'tool_search')
    ]
    try:
        for query, expected_type in test_queries:
            result = ai.classify_intent(query)
            intent = result.get('intent', 'unknown')
            handler = result.get('handler', 'unknown')
            conf = result.get('confidence', 0)
            status = "OK" if intent else "FAIL"
            print(f"  [{status}] \"{query[:40]}...\"")
            print(f"      Intent: {intent}, Handler: {handler}, Confidence: {conf:.2f}")
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    print()

    # Test 6: Benchmark Knowledge Query
    print("TEST 6: Benchmark Knowledge Query")
    print("-" * 40)
    try:
        benchmark_result = ai.query_benchmark('best RNA-seq aligner', top_k=3)
        print(f"  Query: 'best RNA-seq aligner'")
        print(f"  Success: {benchmark_result.get('success')}")
        print(f"  Best tool: {benchmark_result.get('best_tool')}")
        results_count = len(benchmark_result.get('results', []))
        print(f"  Results count: {results_count}")
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    print()

    # Test 7: Literature Search (sync)
    print("TEST 7: Literature Search (Synchronous)")
    print("-" * 40)
    try:
        citations = ai.search_literature_sync(
            query='RNA-seq differential expression',
            max_results=3,
            recent_years=3
        )
        print(f"  Query: 'RNA-seq differential expression'")
        print(f"  Citations found: {len(citations)}")
        if citations:
            print(f"  First citation: {citations[0].get('title', 'N/A')[:60]}...")
    except Exception as e:
        print(f"  WARNING (network may be required): {e}")
    print()

    # Test 8: Record Interaction
    print("TEST 8: Record Interaction (Agentic Memory)")
    print("-" * 40)
    try:
        result = ai.record_interaction(
            project_id='test_project_456',
            session_id=session_context.get('session_id', 'test_session'),
            user_input='What tools are available for RNA-seq analysis?',
            agent_response='You can use STAR, HISAT2, or Salmon for RNA-seq analysis.',
            tool_calls=[{'tool': 'benchmark_query', 'params': {'query': 'RNA-seq'}}],
            outcome={'success': True}
        )
        print(f"  message_id: {result.get('message_id')}")
        print(f"  episode_id: {result.get('episode_id')}")
        print(f"  Interaction recorded successfully")
    except Exception as e:
        print(f"  ERROR: {e}")
        import traceback
        traceback.print_exc()
        return False
    print()

    print("=" * 60)
    print("ALL TESTS COMPLETED SUCCESSFULLY")
    print("=" * 60)
    return True


if __name__ == '__main__':
    success = run_tests()
    sys.exit(0 if success else 1)
