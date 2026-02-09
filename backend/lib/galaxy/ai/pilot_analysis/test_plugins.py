"""
Test script to verify pilot analysis plugin architecture.

Run with: python -m lib.galaxy.ai.pilot_analysis.test_plugins
"""

import sys
from pathlib import Path

# Add backend to path
backend_path = Path(__file__).parent.parent.parent.parent
sys.path.insert(0, str(backend_path))

from lib.galaxy.ai.pilot_analysis import get_pilot_manager


def test_plugin_manager():
    """Test basic plugin manager functionality."""
    print("=" * 70)
    print("PILOT ANALYSIS PLUGIN ARCHITECTURE TEST")
    print("=" * 70)

    manager = get_pilot_manager()

    # Test 1: List domains
    print("\n[Test 1] List registered domains:")
    domains = manager.list_domains()
    print(f"  Found {len(domains)} domains: {', '.join(sorted(domains))}")
    assert len(domains) == 7, f"Expected 7 domains, found {len(domains)}"
    print("  ✓ PASS")

    # Test 2: Get analyzer by name
    print("\n[Test 2] Get specific analyzer:")
    analyzer = manager.get_analyzer("estimate_fragment_size")
    assert analyzer is not None, "Analyzer not found"
    print(f"  Name: {analyzer.name}")
    print(f"  Category: {analyzer.category}")
    print(f"  Tool: {analyzer.tool}")
    print(f"  Runtime: {analyzer.runtime_estimate}")
    print(f"  Max runtime: {analyzer.max_runtime_seconds}s")
    print("  ✓ PASS")

    # Test 3: Get all analyzers for a domain
    print("\n[Test 3] Get domain-specific analyzers:")
    genomics = manager.get_domain_analyzers("genomics")
    print(f"  Genomics has {len(genomics)} analyzers:")
    for name in genomics.keys():
        print(f"    - {name}")
    assert len(genomics) == 6, f"Expected 6 genomics analyzers, found {len(genomics)}"
    print("  ✓ PASS")

    # Test 4: Get quick analyzers
    print("\n[Test 4] Get quick analyzers (<30s):")
    quick = manager.get_quick_analyzers(max_runtime=30)
    print(f"  Found {len(quick)} quick analyzers:")
    for item in quick[:5]:  # Show first 5
        print(f"    - {item['name']} ({item['domain']}) - {item['spec'].max_runtime_seconds}s")
    if len(quick) > 5:
        print(f"    ... and {len(quick) - 5} more")
    assert len(quick) > 0, "No quick analyzers found"
    print("  ✓ PASS")

    # Test 5: Get analyzers by input type
    print("\n[Test 5] Get analyzers by input type (bam):")
    bam_analyzers = manager.get_analyzers_by_input_type("bam")
    print(f"  Found {len(bam_analyzers)} analyzers that accept BAM files:")
    for item in bam_analyzers:
        print(f"    - {item['name']} ({item['domain']})")
    assert len(bam_analyzers) > 0, "No BAM analyzers found"
    print("  ✓ PASS")

    # Test 6: Analyzer count by domain
    print("\n[Test 6] Analyzer count by domain:")
    counts = manager.get_analyzer_count_by_domain()
    total = 0
    for domain, count in sorted(counts.items()):
        print(f"  {domain:20} {count:2} analyzers")
        total += count
    print(f"  {'TOTAL':20} {total:2} analyzers")
    assert total == 20, f"Expected 20 total analyzers, found {total}"
    print("  ✓ PASS")

    # Test 7: Check dependencies (without actually checking system)
    print("\n[Test 7] Domain dependencies:")
    for domain in sorted(domains):
        plugin = manager.get_domain_plugin(domain)
        if plugin:
            deps = plugin.dependencies
            print(f"  {domain:20} requires: {', '.join(deps) if deps else 'none'}")
    print("  ✓ PASS (structure verified)")

    # Test 8: Summary report
    print("\n[Test 8] Manager summary:")
    print(manager.summary())
    print("  ✓ PASS")

    # Test 9: Export to legacy format
    print("\n[Test 9] Export to legacy format:")
    legacy = manager.export_to_legacy_format()
    assert "PILOT_ANALYZERS" in legacy
    assert "ANALYZER_CATEGORIES" in legacy
    print(f"  Exported {len(legacy['PILOT_ANALYZERS'])} analyzers")
    print(f"  Exported {len(legacy['ANALYZER_CATEGORIES'])} categories")
    print("  ✓ PASS")

    # Test 10: Cryo-EM domain specifics
    print("\n[Test 10] Cryo-EM domain specifics:")
    cryoem = manager.get_domain_analyzers("cryo_em")
    print(f"  Cryo-EM analyzers:")
    for name, spec in cryoem.items():
        print(f"    - {name}")
        print(f"      Input: {spec.input_type}, Output: {spec.output_type}")
        if spec.units:
            print(f"      Units: {spec.units}")
    assert len(cryoem) == 3, f"Expected 3 cryo-EM analyzers, found {len(cryoem)}"
    print("  ✓ PASS")

    print("\n" + "=" * 70)
    print("ALL TESTS PASSED ✓")
    print("=" * 70)


def demo_usage():
    """Demonstrate practical usage scenarios."""
    print("\n\n" + "=" * 70)
    print("USAGE DEMONSTRATION")
    print("=" * 70)

    manager = get_pilot_manager()

    # Scenario 1: User uploaded a BAM file for ChIP-seq
    print("\n[Scenario 1] User uploaded ChIP-seq BAM file")
    print("Finding appropriate analyzers...")

    bam_analyzers = manager.get_analyzers_by_input_type("bam")
    genomics_analyzers = [a for a in bam_analyzers if a['domain'] == 'genomics']

    print(f"Found {len(genomics_analyzers)} genomics analyzers for BAM files:")
    for item in genomics_analyzers:
        spec = item['spec']
        print(f"  • {item['name']}")
        print(f"    → {spec.description}")
        print(f"    → Runtime: {spec.runtime_estimate}")
        print(f"    → Extracts: {spec.extract}")
        print()

    # Scenario 2: Quick analysis before workflow execution
    print("[Scenario 2] Pre-workflow quick analysis (<30s)")
    print("Finding fast analyzers for initial characterization...")

    quick_genomics = [
        item for item in manager.get_quick_analyzers(30)
        if item['domain'] == 'genomics'
    ]

    print(f"Found {len(quick_genomics)} quick genomics analyzers:")
    for item in quick_genomics:
        print(f"  • {item['name']} ({item['spec'].max_runtime_seconds}s)")

    # Scenario 3: Cryo-EM initial data check
    print("\n[Scenario 3] Cryo-EM data upload - initial quality check")
    print("Running CTF analysis and particle detection...")

    cryoem_analyzers = manager.get_domain_analyzers("cryo_em")
    for name, spec in cryoem_analyzers.items():
        print(f"  • {name}")
        print(f"    Command: {spec.command_template}")
        print(f"    Extracts: {spec.extract}")
        if spec.thresholds:
            print(f"    Thresholds: {spec.thresholds}")
        print()

    print("=" * 70)


if __name__ == "__main__":
    try:
        test_plugin_manager()
        demo_usage()
    except AssertionError as e:
        print(f"\n✗ TEST FAILED: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n✗ ERROR: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
