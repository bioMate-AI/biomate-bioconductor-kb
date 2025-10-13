#!/usr/bin/env python3
"""
Simple Tool Testing - No Dependencies

Tests tool availability and quality without importing complex modules.
"""

from pathlib import Path
import xml.etree.ElementTree as ET


def test_tool_discovery():
    """Test 1: Can we find high-priority tools?"""
    print("=" * 80)
    print("TEST 1: High-Priority Tool Discovery")
    print("=" * 80)

    tools_dir = Path(__file__).parent.parent / "tools"

    high_priority = [
        # Alignment (7 tools)
        "bwa_mem", "bowtie2_align", "hisat2_align", "star_align",
        "samtools_sort", "samtools_index", "samtools_view",
        # QC (4 tools)
        "fastqc", "multiqc", "trimmomatic", "fastp",
        # Variant Calling (4 tools)
        "gatk4_haplotypecaller", "bcftools_call", "bcftools_filter", "vcftools",
        # Quantification (4 tools)
        "salmon_quant", "kallisto_quant", "featurecounts", "htseq_count",
        # Differential Expression (3 tools)
        "deseq2_differential", "edger", "limma_differential"
    ]

    found = []
    missing = []

    for tool_name in high_priority:
        # Search in all nfcore directories
        found_path = None
        for subdir in ["nfcore_generated", "nfcore_general", "nfcore_lcms"]:
            xml_path = tools_dir / subdir / f"{tool_name}.xml"
            if xml_path.exists():
                found_path = xml_path
                break

        if found_path:
            found.append((tool_name, found_path))
            print(f"  ✓ {tool_name:<30} {found_path.parent.name}")
        else:
            missing.append(tool_name)
            print(f"  ✗ {tool_name:<30} NOT FOUND")

    print(f"\nResult: {len(found)}/{len(high_priority)} high-priority tools found")
    return len(found), len(missing), found, missing


def test_xml_validity(found_tools):
    """Test 2: Are tool XMLs valid?"""
    print("\n" + "=" * 80)
    print("TEST 2: XML Validity")
    print("=" * 80)

    valid = []
    invalid = []

    for tool_name, tool_path in found_tools:
        try:
            tree = ET.parse(tool_path)
            root = tree.getroot()

            # Check required elements
            has_id = root.get('id') is not None
            has_name = root.get('name') is not None
            has_version = root.get('version') is not None
            has_command = root.find('command') is not None
            has_inputs = root.find('inputs') is not None
            has_outputs = root.find('outputs') is not None

            if all([has_id, has_name, has_version, has_command, has_inputs, has_outputs]):
                valid.append(tool_name)
                print(f"  ✓ {tool_name:<30} Valid")
            else:
                missing_elems = []
                if not has_id: missing_elems.append("id")
                if not has_name: missing_elems.append("name")
                if not has_version: missing_elems.append("version")
                if not has_command: missing_elems.append("command")
                if not has_inputs: missing_elems.append("inputs")
                if not has_outputs: missing_elems.append("outputs")

                invalid.append((tool_name, f"Missing: {', '.join(missing_elems)}"))
                print(f"  ✗ {tool_name:<30} Missing: {', '.join(missing_elems)}")

        except ET.ParseError as e:
            invalid.append((tool_name, f"Parse error: {e}"))
            print(f"  ✗ {tool_name:<30} Parse error")

    print(f"\nResult: {len(valid)}/{len(found_tools)} tools have valid XML")
    return len(valid), len(invalid)


def test_container_references(found_tools):
    """Test 3: Do tools have proper container references?"""
    print("\n" + "=" * 80)
    print("TEST 3: Container References")
    print("=" * 80)

    proper = []
    broken = []

    for tool_name, tool_path in found_tools:
        try:
            tree = ET.parse(tool_path)
            root = tree.getroot()

            reqs = root.find('requirements')
            if reqs is not None:
                container = reqs.find('container')
                if container is not None:
                    container_text = (container.text or '').strip()

                    if not container_text:
                        broken.append((tool_name, "Empty"))
                        print(f"  ✗ {tool_name:<30} Empty container")
                    elif '${' in container_text or 'workflow.' in container_text:
                        broken.append((tool_name, "Nextflow syntax"))
                        print(f"  ✗ {tool_name:<30} Nextflow syntax")
                    elif 'quay.io/biocontainers' in container_text:
                        proper.append((tool_name, container_text))
                        # Show first 50 chars of container
                        cont_short = container_text[:50] + ("..." if len(container_text) > 50 else "")
                        print(f"  ✓ {tool_name:<30} {cont_short}")
                    elif 'depot.galaxyproject.org' in container_text:
                        proper.append((tool_name, container_text))
                        print(f"  ✓ {tool_name:<30} depot.galaxyproject.org")
                    else:
                        proper.append((tool_name, container_text))
                        print(f"  ○ {tool_name:<30} Custom: {container_text[:40]}")
                else:
                    broken.append((tool_name, "No container element"))
                    print(f"  ✗ {tool_name:<30} No container element")
            else:
                broken.append((tool_name, "No requirements"))
                print(f"  ✗ {tool_name:<30} No requirements section")

        except Exception as e:
            broken.append((tool_name, str(e)))
            print(f"  ✗ {tool_name:<30} Error: {e}")

    print(f"\nResult: {len(proper)}/{len(found_tools)} have proper containers")
    return len(proper), len(broken)


def test_all_nfcore_tools():
    """Test 4: Count all nfcore tools available"""
    print("\n" + "=" * 80)
    print("TEST 4: All nf-core Tools Count")
    print("=" * 80)

    tools_dir = Path(__file__).parent.parent / "tools"

    counts = {}
    total = 0

    for subdir in ["nfcore_generated", "nfcore_general", "nfcore_lcms"]:
        dir_path = tools_dir / subdir
        if dir_path.exists():
            xml_files = list(dir_path.glob("*.xml"))
            counts[subdir] = len(xml_files)
            total += len(xml_files)
            print(f"  {subdir:<25} {len(xml_files)} tools")

    print(f"\n  Total nf-core tools: {total}")
    return total


def main():
    """Run all tests"""
    print("\n" + "╔" + "=" * 78 + "╗")
    print("║" + " " * 25 + "TOOL TEST SUITE" + " " * 38 + "║")
    print("╚" + "=" * 78 + "╝\n")

    # Test 1: Discovery
    found_count, missing_count, found_tools, missing_tools = test_tool_discovery()

    # Test 2: XML Validity (only on found tools)
    if found_tools:
        valid_count, invalid_count = test_xml_validity(found_tools)

        # Test 3: Containers (only on found tools)
        proper_count, broken_count = test_container_references(found_tools)
    else:
        valid_count = invalid_count = 0
        proper_count = broken_count = 0

    # Test 4: Total count
    total_tools = test_all_nfcore_tools()

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)
    print(f"  High-priority tools found:    {found_count}/22")
    print(f"  Valid XML structure:          {valid_count}/{found_count if found_count > 0 else 0}")
    print(f"  Proper container references:  {proper_count}/{found_count if found_count > 0 else 0}")
    print(f"  Total nf-core tools available: {total_tools}")

    if missing_count > 0:
        print(f"\n  ⚠️  Missing {missing_count} high-priority tools:")
        for tool in missing_tools[:10]:  # Show first 10
            print(f"      - {tool}")

    # Pass/Fail
    print("\n" + "=" * 80)
    if found_count >= 18 and valid_count >= found_count * 0.9 and proper_count >= found_count * 0.9:
        print("✅ PASS: Tools are ready for on-demand installation")
        print("=" * 80)
        return 0
    else:
        print("⚠️  REVIEW NEEDED: Some issues detected")
        if found_count < 18:
            print(f"   - Only {found_count}/22 high-priority tools found")
        if valid_count < found_count * 0.9:
            print(f"   - Only {valid_count}/{found_count} have valid XML")
        if proper_count < found_count * 0.9:
            print(f"   - Only {proper_count}/{found_count} have proper containers")
        print("=" * 80)
        return 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
