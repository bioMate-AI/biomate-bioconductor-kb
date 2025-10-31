#!/usr/bin/env python3
"""
Test script for direct instrument parsers (Illumina, ONT, PacBio)

Usage:
    python test_direct_parsers.py
"""

import os
import sys
from pathlib import Path

# Add lib to path
lib_path = Path(__file__).parent.parent.parent / "lib"
sys.path.insert(0, str(lib_path))

from galaxy.instruments.parsers.illumina import IlluminaParser
from galaxy.instruments.parsers.ont import ONTParser
from galaxy.instruments.parsers.pacbio import PacBioParser


def test_illumina_parser():
    """Test Illumina FASTQ parser"""
    print("\n" + "="*70)
    print("Testing Illumina Parser")
    print("="*70)

    parser = IlluminaParser()
    test_file = Path(__file__).parent / "test_illumina.fastq"

    # Validate file
    assert parser.validate(str(test_file)), "Illumina validation failed"
    print("✓ File validation passed")

    # Get metadata
    metadata = parser.get_metadata(str(test_file))
    print(f"✓ Metadata extracted: {metadata.manufacturer} {metadata.model}")
    print(f"  Run ID: {metadata.run_id}")
    print(f"  Flowcell: {metadata.flowcell_id}")

    # Parse file
    result = parser.parse(str(test_file))

    assert result.success, f"Parsing failed: {result.errors}"
    print(f"✓ Parsing successful")
    print(f"  Total reads: {result.total_reads}")
    print(f"  Total samples: {len(result.samples)}")
    print(f"  Processing time: {result.processing_time:.3f}s")

    # Check samples
    for sample in result.samples:
        print(f"\n  Sample: {sample.sample_id}")
        print(f"    Read count: {sample.read_count}")
        print(f"    Total bases: {sample.total_bases}")
        print(f"    Mean length: {sample.mean_read_length:.1f}bp")
        print(f"    Mean quality: Q{sample.mean_quality:.1f}")
        # Calculate mean GC from reads
        if sample.reads:
            mean_gc = sum(r.gc_content for r in sample.reads) / len(sample.reads)
            print(f"    GC content: {mean_gc:.1f}%")

    print("\n✓ Illumina parser test PASSED")
    return True


def test_ont_parser():
    """Test ONT FASTQ parser"""
    print("\n" + "="*70)
    print("Testing ONT Parser")
    print("="*70)

    parser = ONTParser()
    test_file = Path(__file__).parent / "test_ont.fastq"

    # Validate file
    assert parser.validate(str(test_file)), "ONT validation failed"
    print("✓ File validation passed")

    # Get metadata
    metadata = parser.get_metadata(str(test_file))
    print(f"✓ Metadata extracted: {metadata.manufacturer} {metadata.model}")
    print(f"  Run ID: {metadata.run_id}")

    # Parse file
    result = parser.parse(str(test_file))

    assert result.success, f"Parsing failed: {result.errors}"
    print(f"✓ Parsing successful")
    print(f"  Total reads: {result.total_reads}")
    print(f"  Total samples: {len(result.samples)}")
    print(f"  Processing time: {result.processing_time:.3f}s")

    # Check samples
    for sample in result.samples:
        print(f"\n  Sample: {sample.sample_id}")
        print(f"    Read count: {sample.read_count}")
        print(f"    Total bases: {sample.total_bases}")
        print(f"    Mean length: {sample.mean_read_length:.1f}bp")
        print(f"    Mean quality: Q{sample.mean_quality:.1f}")
        print(f"    N50: {sample.metadata.get('n50', 0)}bp")

    print("\n✓ ONT parser test PASSED")
    return True


def test_pacbio_parser():
    """Test PacBio FASTQ parser"""
    print("\n" + "="*70)
    print("Testing PacBio Parser")
    print("="*70)

    parser = PacBioParser()
    test_file = Path(__file__).parent / "test_pacbio.fastq"

    # Validate file
    assert parser.validate(str(test_file)), "PacBio validation failed"
    print("✓ File validation passed")

    # Get metadata
    metadata = parser.get_metadata(str(test_file))
    print(f"✓ Metadata extracted: {metadata.manufacturer} {metadata.model}")
    print(f"  Run ID: {metadata.run_id}")

    # Parse file
    result = parser.parse(str(test_file))

    assert result.success, f"Parsing failed: {result.errors}"
    print(f"✓ Parsing successful")
    print(f"  Total reads: {result.total_reads}")
    print(f"  Total samples: {len(result.samples)}")
    print(f"  Processing time: {result.processing_time:.3f}s")

    # Check samples
    for sample in result.samples:
        print(f"\n  Sample: {sample.sample_id}")
        print(f"    Read count: {sample.read_count}")
        print(f"    Total bases: {sample.total_bases}")
        print(f"    Mean length: {sample.mean_read_length:.1f}bp")
        print(f"    Mean quality: Q{sample.mean_quality:.1f}")
        print(f"    N50: {sample.metadata.get('n50', 0)}bp")
        print(f"    Mean accuracy: {sample.metadata.get('mean_accuracy', 0):.2f}%")

    print("\n✓ PacBio parser test PASSED")
    return True


def main():
    """Run all parser tests"""
    print("\n" + "="*70)
    print("Direct Instrument Parser Test Suite")
    print("="*70)

    tests = [
        ("Illumina", test_illumina_parser),
        ("ONT", test_ont_parser),
        ("PacBio", test_pacbio_parser),
    ]

    passed = 0
    failed = 0

    for name, test_func in tests:
        try:
            if test_func():
                passed += 1
        except Exception as e:
            print(f"\n✗ {name} parser test FAILED: {e}")
            import traceback
            traceback.print_exc()
            failed += 1

    # Summary
    print("\n" + "="*70)
    print("Test Summary")
    print("="*70)
    print(f"Passed: {passed}/{len(tests)}")
    print(f"Failed: {failed}/{len(tests)}")

    if failed == 0:
        print("\n✓ All tests PASSED!")
        return 0
    else:
        print(f"\n✗ {failed} test(s) FAILED")
        return 1


if __name__ == "__main__":
    sys.exit(main())
