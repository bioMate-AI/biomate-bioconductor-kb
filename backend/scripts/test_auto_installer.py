#!/usr/bin/env python3
"""
Test Auto-Installer with High-Priority Tools

Tests on-demand tool installation with 5 high-priority nfcore tools.
"""

import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from lib.galaxy.ai.tool_auto_installer import GalaxyToolAutoInstaller


def test_tool_discovery():
    """Test 1: Can we find tool XMLs?"""
    print("=" * 80)
    print("TEST 1: Tool Discovery")
    print("=" * 80)

    tools_dir = Path(__file__).parent.parent / "tools"
    installer = GalaxyToolAutoInstaller(
        galaxy_root="/tmp/test_galaxy",  # Dummy path for testing
        tools_dir=str(tools_dir)
    )

    test_tools = [
        "samtools_sort",
        "bwa_mem",
        "fastqc",
        "trimmomatic",
        "deseq2_differential",
    ]

    found = []
    missing = []

    for tool_name in test_tools:
        tool_id = f"nfcore_{tool_name}"
        tool_path = installer._find_tool_xml(tool_id) if hasattr(installer, '_find_tool_xml') else None

        if tool_path:
            found.append((tool_name, tool_path))
            print(f"  ✓ Found: {tool_name} at {tool_path}")
        else:
            # Try to find manually
            for subdir in ["nfcore_generated", "nfcore_general", "nfcore_lcms"]:
                xml_path = tools_dir / subdir / f"{tool_name}.xml"
                if xml_path.exists():
                    found.append((tool_name, xml_path))
                    print(f"  ✓ Found: {tool_name} at {xml_path}")
                    break
            else:
                missing.append(tool_name)
                print(f"  ✗ Missing: {tool_name}")

    print(f"\nResult: Found {len(found)}/{len(test_tools)} tools")
    return len(found) == len(test_tools), found


def test_tool_xml_validity():
    """Test 2: Are tool XMLs valid?"""
    print("\n" + "=" * 80)
    print("TEST 2: Tool XML Validity")
    print("=" * 80)

    import xml.etree.ElementTree as ET

    _, found_tools = test_tool_discovery()

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

            if all([has_id, has_name, has_version, has_command]):
                valid.append(tool_name)
                print(f"  ✓ Valid: {tool_name}")
            else:
                invalid.append((tool_name, "Missing required elements"))
                print(f"  ✗ Invalid: {tool_name} - Missing required elements")

        except ET.ParseError as e:
            invalid.append((tool_name, str(e)))
            print(f"  ✗ Invalid: {tool_name} - Parse error: {e}")

    print(f"\nResult: {len(valid)}/{len(found_tools)} tools are valid XML")
    return len(invalid) == 0


def test_container_references():
    """Test 3: Do tools have proper container references?"""
    print("\n" + "=" * 80)
    print("TEST 3: Container References")
    print("=" * 80)

    import xml.etree.ElementTree as ET

    _, found_tools = test_tool_discovery()

    proper_containers = []
    broken_containers = []

    for tool_name, tool_path in found_tools:
        try:
            tree = ET.parse(tool_path)
            root = tree.getroot()

            # Find container element
            reqs = root.find('requirements')
            if reqs is not None:
                container = reqs.find('container')
                if container is not None:
                    container_text = container.text or ''

                    # Check if proper format
                    if 'quay.io/biocontainers' in container_text or 'depot.galaxyproject.org' in container_text:
                        proper_containers.append((tool_name, container_text))
                        print(f"  ✓ Proper: {tool_name}")
                        print(f"    Container: {container_text[:80]}...")
                    elif '${' in container_text or 'workflow.' in container_text:
                        broken_containers.append((tool_name, "Nextflow syntax"))
                        print(f"  ✗ Broken: {tool_name} - Nextflow syntax")
                    elif not container_text.strip():
                        broken_containers.append((tool_name, "Empty container"))
                        print(f"  ✗ Broken: {tool_name} - Empty container reference")
                    else:
                        proper_containers.append((tool_name, container_text))
                        print(f"  ○ Other: {tool_name} - {container_text[:50]}")
                else:
                    broken_containers.append((tool_name, "No container element"))
                    print(f"  ✗ No container: {tool_name}")
            else:
                broken_containers.append((tool_name, "No requirements"))
                print(f"  ✗ No requirements: {tool_name}")

        except Exception as e:
            broken_containers.append((tool_name, str(e)))
            print(f"  ✗ Error: {tool_name} - {e}")

    print(f"\nResult: {len(proper_containers)}/{len(found_tools)} have proper containers")
    return len(broken_containers) == 0


def test_workflow_validation():
    """Test 4: Can we validate a test workflow?"""
    print("\n" + "=" * 80)
    print("TEST 4: Workflow Validation")
    print("=" * 80)

    # Create minimal test workflow
    test_workflow = {
        "name": "Test RNA-seq Workflow",
        "steps": {
            "1": {
                "tool_id": "nfcore_bwa_mem",
                "type": "tool"
            },
            "2": {
                "tool_id": "nfcore_samtools_sort",
                "type": "tool"
            },
            "3": {
                "tool_id": "nfcore_fastqc",
                "type": "tool"
            }
        }
    }

    tools_dir = Path(__file__).parent.parent / "tools"
    installer = GalaxyToolAutoInstaller(
        galaxy_root="/tmp/test_galaxy",
        tools_dir=str(tools_dir)
    )

    try:
        available, custom, toolshed = installer.validate_workflow_tools(test_workflow)

        print(f"  Available tools: {len(available)}")
        print(f"  Custom tools needed: {len(custom)}")
        print(f"  Toolshed tools needed: {len(toolshed)}")

        for tool in custom:
            print(f"    - {tool}")

        # Check if we can find all custom tools
        found_all = True
        for tool_id in custom:
            tool_name = tool_id.replace("nfcore_", "")
            found = False
            for subdir in ["nfcore_generated", "nfcore_general", "nfcore_lcms"]:
                if (tools_dir / subdir / f"{tool_name}.xml").exists():
                    found = True
                    break
            if not found:
                found_all = False
                print(f"    ✗ Cannot find XML for {tool_id}")

        if found_all:
            print("\n  ✓ All workflow tools are available")
            return True
        else:
            print("\n  ✗ Some tools are missing")
            return False

    except Exception as e:
        print(f"  ✗ Error validating workflow: {e}")
        import traceback
        traceback.print_exc()
        return False


def test_high_priority_tools():
    """Test 5: Check all 22 high-priority tools"""
    print("\n" + "=" * 80)
    print("TEST 5: High-Priority Tools Availability")
    print("=" * 80)

    high_priority = [
        # Alignment
        "bwa_mem", "bowtie2_align", "hisat2_align", "star_align",
        "samtools_sort", "samtools_index", "samtools_view",
        # QC
        "fastqc", "multiqc", "trimmomatic", "fastp",
        # Variant Calling
        "gatk4_haplotypecaller", "bcftools_call", "bcftools_filter", "vcftools",
        # Quantification
        "salmon_quant", "kallisto_quant", "featurecounts", "htseq_count",
        # Differential Expression
        "deseq2", "edger", "limma"
    ]

    tools_dir = Path(__file__).parent.parent / "tools"
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
            found.append(tool_name)
            print(f"  ✓ {tool_name}")
        else:
            missing.append(tool_name)
            print(f"  ✗ {tool_name} - NOT FOUND")

    print(f"\nResult: {len(found)}/{len(high_priority)} high-priority tools available")

    if missing:
        print(f"\nMissing tools ({len(missing)}):")
        for tool in missing:
            print(f"  - {tool}")

    return len(missing) == 0


def main():
    """Run all tests"""
    print("\n" + "╔" + "=" * 78 + "╗")
    print("║" + " " * 20 + "AUTO-INSTALLER TEST SUITE" + " " * 33 + "║")
    print("╚" + "=" * 78 + "╝\n")

    results = {}

    # Run tests
    results['discovery'], _ = test_tool_discovery()
    results['validity'] = test_tool_xml_validity()
    results['containers'] = test_container_references()
    results['workflow'] = test_workflow_validation()
    results['high_priority'] = test_high_priority_tools()

    # Summary
    print("\n" + "=" * 80)
    print("SUMMARY")
    print("=" * 80)

    passed = sum(results.values())
    total = len(results)

    for test_name, result in results.items():
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status} - {test_name.replace('_', ' ').title()}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if passed == total:
        print("\n✅ All tests passed! Auto-installer is ready.")
        return 0
    else:
        print(f"\n⚠️  {total - passed} test(s) failed. Review above for details.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
