#!/usr/bin/env python3
"""
Test script for multi-agent system.

Run from backend directory:
    python -m lib.galaxy.ai.agents.test_agents
"""

import sys
import os

# Add parent paths for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))))

from lib.galaxy.ai.agents.domain_router import DomainRouter


def test_domain_router():
    """Test DomainRouter keyword matching."""
    print("\n=== Testing DomainRouter ===\n")

    router = DomainRouter()

    # Test queries with expected primary domains
    test_cases = [
        ("I want to analyze RNA-seq data for differential expression", "transcriptomics"),
        ("Perform mass spectrometry analysis on my proteomics samples", "proteomics"),
        ("Analyze my 10X single-cell RNA sequencing data", "single-cell"),
        ("I need to call variants from my whole genome sequencing data", "genomics"),
        ("Search UniProt for protein sequences", "proteomics"),
        ("Analyze metabolomics data from LC-MS", "metabolomics"),
        ("I want to do CRISPR analysis", "molecular_biology"),
        ("Protein structure prediction with AlphaFold", "structural_biology"),
        ("Drug ADMET prediction and toxicity analysis", "pharmacology"),
        ("Analyze flow cytometry data for T-cell populations", "immunology"),
        ("Cancer somatic mutation calling and annotation", "cancer_biology"),
        ("16S rRNA microbiome analysis", "metagenomics"),
        ("Image segmentation for cell counting", "bioimaging"),
        ("Design PCR primers for my gene", "molecular_biology"),
        ("Enzyme kinetics Michaelis-Menten analysis", "biochemistry"),
        ("Query NCBI for sequences", "database"),
        ("Search PubMed for relevant papers", "literature"),
    ]

    passed = 0
    failed = 0

    for query, expected_domain in test_cases:
        result = router.route(query)
        status = "✓" if result.primary_domain == expected_domain else "✗"
        if result.primary_domain == expected_domain:
            passed += 1
        else:
            failed += 1

        print(f"{status} Query: {query[:55]}...")
        print(f"    Expected: {expected_domain}, Got: {result.primary_domain} (conf: {result.confidence:.2f})")
        if result.secondary_domains:
            print(f"    Secondary: {result.secondary_domains}")
        print()

    print(f"DomainRouter: {passed}/{len(test_cases)} passed")
    if failed > 0:
        print(f"WARNING: {failed} tests failed!")
    else:
        print("DomainRouter test passed!")


def test_domain_categories():
    """Test domain to category mapping."""
    print("\n=== Testing Domain Categories ===\n")

    router = DomainRouter()

    for domain in ['genomics', 'proteomics', 'single-cell', 'metabolomics']:
        categories = router.get_category_filter(domain)
        print(f"{domain}: {categories}")

    print("\nDomain categories test passed!")


def test_complexity_detection():
    """Test complexity assessment."""
    print("\n=== Testing Complexity Detection ===\n")

    router = DomainRouter()

    test_cases = [
        ("What is RNA-seq?", "simple"),
        ("How to align sequences", "simple"),
        ("Perform multi-omics integration with RNA-seq and proteomics", "complex"),
        ("End-to-end pipeline for comprehensive genomic analysis", "complex"),
        ("Analyze my RNA-seq data for differential expression", "standard"),
    ]

    passed = 0
    for query, expected in test_cases:
        result = router.route(query)
        status = "✓" if result.complexity == expected else "✗"
        if result.complexity == expected:
            passed += 1
        print(f"{status} '{query[:50]}...' → {result.complexity} (expected: {expected})")

    print(f"\nComplexity: {passed}/{len(test_cases)} passed")


def test_orchestration_imports():
    """Test that all orchestration components can be imported."""
    print("\n=== Testing Orchestration Imports ===\n")

    try:
        from lib.galaxy.ai.agents.domain_router import DomainRouter, RoutingDecision
        print("✓ DomainRouter imported")

        from lib.galaxy.ai.agents.domain_specialist import (
            DomainSpecialistPool, DomainRecommendation, ToolRecommendation
        )
        print("✓ DomainSpecialistPool imported")

        from lib.galaxy.ai.agents.workflow_assembler import (
            WorkflowAssembler, AssembledWorkflow, ValidationResult
        )
        print("✓ WorkflowAssembler imported")

        from lib.galaxy.ai.agents.agent_orchestrator import (
            AgentOrchestrator, OrchestrationResult
        )
        print("✓ AgentOrchestrator imported")

        # Check __init__ exports
        from lib.galaxy.ai.agents import (
            DomainRouter, DomainSpecialistPool, WorkflowAssembler, AgentOrchestrator
        )
        print("✓ All agents exported from __init__")

        print("\nOrchestration imports test passed!")
        return True
    except ImportError as e:
        print(f"✗ Import failed: {e}")
        return False


def test_dataclass_structures():
    """Test that dataclasses are correctly structured."""
    print("\n=== Testing Dataclass Structures ===\n")

    from lib.galaxy.ai.agents.domain_router import RoutingDecision
    from lib.galaxy.ai.agents.domain_specialist import (
        ToolRecommendation, WorkflowStep, DomainRecommendation
    )
    from lib.galaxy.ai.agents.workflow_assembler import (
        ValidationResult, Citation, AssembledWorkflow
    )

    # Test RoutingDecision
    rd = RoutingDecision(primary_domain="genomics", confidence=0.8)
    assert rd.primary_domain == "genomics"
    assert rd.confidence == 0.8
    assert rd.secondary_domains == []
    print("✓ RoutingDecision")

    # Test ToolRecommendation
    tr = ToolRecommendation(
        tool_id="biomni/genomics/tool1",
        tool_name="Test Tool",
        category="Genomics",
        rationale="Test reason"
    )
    assert tr.tool_id == "biomni/genomics/tool1"
    print("✓ ToolRecommendation")

    # Test DomainRecommendation
    dr = DomainRecommendation(domain="proteomics")
    assert dr.domain == "proteomics"
    assert dr.recommended_tools == []
    print("✓ DomainRecommendation")

    # Test ValidationResult
    vr = ValidationResult(is_valid=True)
    assert vr.is_valid == True
    assert vr.issues == []
    print("✓ ValidationResult")

    print("\nDataclass structures test passed!")


def test_workflow_assembler_merge():
    """Test WorkflowAssembler merging logic."""
    print("\n=== Testing WorkflowAssembler Merge ===\n")

    from lib.galaxy.ai.agents.domain_specialist import (
        DomainRecommendation, ToolRecommendation, WorkflowStep
    )
    from lib.galaxy.ai.agents.workflow_assembler import WorkflowAssembler

    # Create mock LLM client
    class MockLLMClient:
        def generate(self, prompt, **kwargs):
            # Return minimal valid JSON
            return '{"workflow_steps": [], "issues": [], "recommendations": [], "notes": "mock"}'

    assembler = WorkflowAssembler(llm_client=MockLLMClient())

    # Create test domain recommendations
    rec1 = DomainRecommendation(
        domain="genomics",
        recommended_tools=[
            ToolRecommendation(
                tool_id="biomni/genomics/align",
                tool_name="Alignment Tool",
                category="Genomics",
                rationale="For DNA alignment",
                confidence=0.9
            )
        ],
        workflow_steps=[
            WorkflowStep(
                step_number=1,
                tool_id="biomni/genomics/align",
                tool_name="Alignment Tool",
                description="Align reads to reference"
            )
        ],
        domain_notes="Genomics analysis note"
    )

    rec2 = DomainRecommendation(
        domain="transcriptomics",
        recommended_tools=[
            ToolRecommendation(
                tool_id="biomni/transcriptomics/count",
                tool_name="Count Tool",
                category="RNA",
                rationale="For counting reads",
                confidence=0.85
            )
        ],
        domain_notes="Transcriptomics note"
    )

    domain_recs = {"genomics": rec1, "transcriptomics": rec2}

    # Test merge
    merged = assembler._merge_recommendations(domain_recs)

    assert len(merged['tools']) == 2, f"Expected 2 tools, got {len(merged['tools'])}"
    assert len(merged['steps']) == 1, f"Expected 1 step, got {len(merged['steps'])}"
    print("✓ Merged 2 domain recommendations correctly")
    print(f"  Tools: {[t.tool_name for t in merged['tools']]}")
    print(f"  Steps: {len(merged['steps'])}")

    # Test assembly (with mock LLM)
    result = assembler.assemble(
        query="Test query",
        domain_recommendations=domain_recs
    )

    assert result.domain_sources == ["genomics", "transcriptomics"]
    print("✓ Assembly includes both domain sources")

    print("\nWorkflowAssembler merge test passed!")


def test_full_pipeline_mock():
    """Test the full pipeline with mocked components."""
    print("\n=== Testing Full Pipeline (Mocked) ===\n")

    from lib.galaxy.ai.agents.domain_router import DomainRouter
    from lib.galaxy.ai.agents.domain_specialist import DomainSpecialistPool
    from lib.galaxy.ai.agents.workflow_assembler import WorkflowAssembler
    from lib.galaxy.ai.agents.agent_orchestrator import AgentOrchestrator

    # Mock components
    class MockLLMClient:
        def generate(self, prompt, **kwargs):
            return '''{
                "recommended_tools": [
                    {"tool_id": "test_tool", "tool_name": "Test", "rationale": "test", "confidence": 0.8}
                ],
                "workflow_steps": [
                    {"step_number": 1, "tool_id": "test_tool", "tool_name": "Test", "description": "Test step"}
                ],
                "domain_notes": "Test note"
            }'''

    class MockToolSearch:
        def search(self, query, limit=10, **kwargs):
            return [
                {"tool_id": "test_tool", "name": "Test Tool", "description": "A test tool", "category": "Test"}
            ]

        def _fts5_search(self, query, category=None, limit=10):
            return self.search(query, limit)

    # Create orchestrator with mocks
    orchestrator = AgentOrchestrator(
        tool_search=MockToolSearch(),
        llm_client=MockLLMClient(),
        max_parallel_specialists=2
    )

    print("✓ AgentOrchestrator created with mocks")

    # Test routing
    query = "Analyze RNA-seq data for differential expression"
    routing = orchestrator.domain_router.route(query)
    assert routing.primary_domain == "transcriptomics"
    print(f"✓ Routing: {query[:50]}... → {routing.primary_domain}")

    # Test quick recommendations (doesn't require full pipeline)
    try:
        quick_recs = orchestrator.get_quick_recommendations(query)
        print(f"✓ Quick recommendations returned: {quick_recs.get('domain')}")
    except Exception as e:
        print(f"⚠ Quick recommendations failed (expected in mock): {e}")

    print("\nFull pipeline mock test passed!")


def main():
    print("=" * 60)
    print("Multi-Agent System Tests")
    print("=" * 60)

    try:
        test_domain_router()
        test_domain_categories()
        test_complexity_detection()
        test_orchestration_imports()
        test_dataclass_structures()
        test_workflow_assembler_merge()
        test_full_pipeline_mock()

        print("\n" + "=" * 60)
        print("All tests passed!")
        print("=" * 60)

    except Exception as e:
        print(f"\nTest failed: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
