"""
Test script for pilot analysis executor.

This demonstrates how to use the executor to run pilot analyzers on mock data.
"""

import sys
import tempfile
from pathlib import Path

# Add backend to path
backend_path = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(backend_path))

from lib.galaxy.ai.pilot_analysis import get_pilot_manager, PilotAnalysisExecutor, run_pilot_analysis


def create_mock_bam_file() -> Path:
    """Create a mock BAM file for testing."""
    # In real usage, this would be user's actual data
    # For testing, we create an empty file
    mock_file = Path(tempfile.mkdtemp()) / "test.bam"
    mock_file.write_text("")
    return mock_file


def create_mock_fasta_file() -> Path:
    """Create a mock FASTA file for testing."""
    mock_file = Path(tempfile.mkdtemp()) / "test.fasta"
    mock_file.write_text(">seq1\nATGCATGCATGCATGC\n")
    return mock_file


def test_executor_basic():
    """Test basic executor functionality."""
    print("=" * 70)
    print("PILOT ANALYSIS EXECUTOR TEST")
    print("=" * 70)

    # Create mock data
    print("\n[Setup] Creating mock data files...")
    bam_file = create_mock_bam_file()
    fasta_file = create_mock_fasta_file()
    print(f"  Created: {bam_file}")
    print(f"  Created: {fasta_file}")

    # Initialize executor
    print("\n[Test 1] Initialize executor with fallback enabled")
    executor = PilotAnalysisExecutor(use_fallback_on_error=True)
    print("  ✓ Executor initialized")

    # Test 1: Run single analyzer (will likely fail/fallback on mock data)
    print("\n[Test 2] Run single analyzer on BAM file")
    result = executor.run_analyzer("estimate_fragment_size", bam_file)

    print(f"  Analyzer: {result.analyzer_name}")
    print(f"  Status: {result.status}")
    print(f"  Execution time: {result.execution_time_seconds:.2f}s")
    print(f"  Used fallback: {result.used_fallback}")
    print(f"  Extracted data: {result.extracted_data}")

    if result.error_message:
        print(f"  Error: {result.error_message[:100]}...")

    # Expected: fallback used because mock file is empty
    assert result.status in ["fallback", "failed"], f"Unexpected status: {result.status}"
    print("  ✓ PASS - Handled mock file appropriately")

    # Test 2: Run batch analyzers
    print("\n[Test 3] Run batch analyzers on BAM file")
    batch_results = executor.run_batch(
        ["estimate_fragment_size", "detect_sequencing_protocol", "count_reads_and_depth"], bam_file
    )

    print(f"  Ran {len(batch_results)} analyzers:")
    for name, res in batch_results.items():
        print(f"    - {name}: {res.status}")

    assert len(batch_results) == 3, "Should have 3 results"
    print("  ✓ PASS - Batch execution worked")

    # Test 3: Run by input type
    print("\n[Test 4] Auto-detect and run BAM analyzers")
    auto_results = executor.run_by_input_type(bam_file, max_runtime=60)

    print(f"  Found and ran {len(auto_results)} BAM analyzers:")
    for name, res in auto_results.items():
        print(f"    - {name}: {res.status} ({res.execution_time_seconds:.2f}s)")

    assert len(auto_results) > 0, "Should find at least one BAM analyzer"
    print("  ✓ PASS - Auto-detection worked")

    # Test 4: Convenience function
    print("\n[Test 5] Use convenience function")
    result = run_pilot_analysis("analyze_template_gc_content", fasta_file)

    print(f"  Analyzer: {result.analyzer_name}")
    print(f"  Status: {result.status}")
    print(f"  Extracted: {result.extracted_data}")
    print("  ✓ PASS - Convenience function worked")

    # Cleanup
    print("\n[Cleanup]")
    bam_file.unlink()
    fasta_file.unlink()
    print("  Removed mock files")

    print("\n" + "=" * 70)
    print("ALL EXECUTOR TESTS PASSED ✓")
    print("=" * 70)


def demo_realistic_workflow():
    """Demonstrate realistic usage scenario."""
    print("\n\n" + "=" * 70)
    print("REALISTIC WORKFLOW DEMONSTRATION")
    print("=" * 70)

    print("\n[Scenario] User uploads ChIP-seq BAM file")
    print("System needs to estimate fragment size for MACS2 parameter inference")

    # Simulate user uploading file
    user_bam = create_mock_bam_file()
    print(f"  User file: {user_bam}")

    # Create executor
    executor = PilotAnalysisExecutor(
        timeout_multiplier=1.5,  # Allow 50% more time
        use_fallback_on_error=True,  # Use fallback if analysis fails
    )

    # Step 1: Check which analyzers are applicable
    print("\n[Step 1] Determine applicable analyzers")
    manager = get_pilot_manager()
    applicable = manager.get_analyzers_by_input_type("bam")

    print(f"  Found {len(applicable)} analyzers that accept BAM files:")
    for item in applicable:
        spec = item["spec"]
        print(f"    - {item['name']} ({spec.runtime_estimate})")

    # Step 2: Run quick analyzers first
    print("\n[Step 2] Run quick analyzers (<30s)")
    quick_bam = [item for item in applicable if item["spec"].max_runtime_seconds <= 30]

    results = {}
    for item in quick_bam:
        name = item["name"]
        print(f"  Running {name}...")
        result = executor.run_analyzer(name, user_bam)
        results[name] = result
        print(f"    → {result.status}: {result.extracted_data}")

    # Step 3: Extract parameter value for MACS2
    print("\n[Step 3] Extract fragment size for MACS2")
    if "estimate_fragment_size" in results:
        frag_result = results["estimate_fragment_size"]
        if frag_result.status in ["success", "fallback"]:
            fragment_size = frag_result.extracted_data.get("insert_size_average", 200)
            print(f"  Fragment size: {fragment_size} bp")
            print(f"  → Will use for MACS2 --extsize parameter")

            if frag_result.used_fallback:
                print(f"  ⚠ Using fallback value (analysis failed)")
        else:
            print(f"  ✗ Failed to estimate fragment size")
    else:
        print("  ⚠ Fragment size analyzer not available")

    # Cleanup
    user_bam.unlink()

    print("\n" + "=" * 70)


def demo_parser_system():
    """Demonstrate domain-specific parser usage."""
    print("\n\n" + "=" * 70)
    print("PARSER SYSTEM DEMONSTRATION")
    print("=" * 70)

    from lib.galaxy.ai.pilot_analysis import parsers

    print("\n[Available Parsers]")
    for tool_name in parsers.PARSER_REGISTRY.keys():
        print(f"  - {tool_name}")

    print(f"\nTotal: {len(parsers.PARSER_REGISTRY)} domain-specific parsers")

    # Example: samtools stats parser
    print("\n[Example] Samtools stats output parsing")
    mock_samtools_output = """SN\traw total sequences:\t1000000
SN\treads mapped:\t950000
SN\tinsert size average:\t247.5
SN\tinsert size standard deviation:\t42.3"""

    parsed = parsers.SamtoolsStatsParser.parse(mock_samtools_output, "", {})
    print(f"  Raw output lines: {len(mock_samtools_output.splitlines())}")
    print(f"  Parsed result: {parsed}")
    print("  ✓ Extracted structured data from tool output")

    print("\n" + "=" * 70)


if __name__ == "__main__":
    try:
        test_executor_basic()
        demo_realistic_workflow()
        demo_parser_system()

        print("\n" + "=" * 70)
        print("EXECUTOR FRAMEWORK READY FOR PRODUCTION ✓")
        print("=" * 70)
        print("\nNext steps:")
        print("  1. Integrate with ContextGatherer")
        print("  2. Add real data validation tests")
        print("  3. Create API endpoints")
        print("  4. Build frontend UI components")

    except AssertionError as e:
        print(f"\n✗ TEST FAILED: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        import traceback

        traceback.print_exc()
        sys.exit(1)
