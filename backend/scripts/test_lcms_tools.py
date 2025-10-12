#!/usr/bin/env python3
"""
Automated tests for nf-core LC-MS tool wrappers.
Validates Galaxy tool XML syntax, structure, and metadata.
"""

import xml.etree.ElementTree as ET
from pathlib import Path
import json
import sys

def test_xml_validity(xml_path):
    """Test if XML is well-formed"""
    try:
        tree = ET.parse(xml_path)
        return True, "XML is well-formed"
    except ET.ParseError as e:
        return False, f"XML parsing error: {e}"

def test_required_elements(xml_path):
    """Test if XML has all required Galaxy tool elements"""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    required = ['description', 'command', 'inputs', 'outputs', 'help']
    missing = []

    for elem in required:
        if root.find(elem) is None:
            missing.append(elem)

    if missing:
        return False, f"Missing required elements: {', '.join(missing)}"
    return True, "All required elements present"

def test_tool_metadata(xml_path):
    """Test if tool has proper ID, name, version"""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    if 'id' not in root.attrib:
        return False, "Tool missing 'id' attribute"
    if 'name' not in root.attrib:
        return False, "Tool missing 'name' attribute"
    if 'version' not in root.attrib:
        return False, "Tool missing 'version' attribute"

    return True, f"Tool: {root.attrib['name']} v{root.attrib['version']}"

def test_container_requirement(xml_path):
    """Test if tool specifies container"""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    requirements = root.find('requirements')
    if requirements is None:
        return False, "No <requirements> section"

    container = requirements.find('container')
    if container is None:
        return False, "No <container> specified"

    if 'type' not in container.attrib:
        return False, "Container missing 'type' attribute"

    return True, f"Container: {container.text}"

def test_help_section(xml_path):
    """Test if help section contains citations"""
    tree = ET.parse(xml_path)
    root = tree.getroot()

    help_elem = root.find('help')
    if help_elem is None or not help_elem.text:
        return False, "Empty or missing help section"

    citations = root.find('citations')
    if citations is None:
        return False, "No citations section"

    citation_count = len(citations.findall('citation'))
    return True, f"{citation_count} citation(s) found"

def run_all_tests(tools_dir):
    """Run all tests on all tool XMLs"""
    tools_dir = Path(tools_dir)
    xml_files = sorted(tools_dir.glob("*.xml"))

    if not xml_files:
        print(f"❌ No XML files found in {tools_dir}")
        return False

    print(f"\n{'='*70}")
    print(f"Testing {len(xml_files)} nf-core LC-MS tool wrappers")
    print(f"{'='*70}\n")

    all_passed = True
    results = []

    for xml_file in xml_files:
        print(f"Testing: {xml_file.name}")
        tool_passed = True
        tool_results = []

        tests = [
            ("XML validity", test_xml_validity),
            ("Required elements", test_required_elements),
            ("Tool metadata", test_tool_metadata),
            ("Container requirement", test_container_requirement),
            ("Help & citations", test_help_section)
        ]

        for test_name, test_func in tests:
            try:
                passed, message = test_func(xml_file)
                status = "✓" if passed else "✗"
                print(f"  {status} {test_name}: {message}")
                tool_results.append((test_name, passed, message))
                if not passed:
                    tool_passed = False
            except Exception as e:
                print(f"  ✗ {test_name}: Exception - {e}")
                tool_results.append((test_name, False, str(e)))
                tool_passed = False

        if tool_passed:
            print(f"  ✅ {xml_file.name} PASSED all tests\n")
        else:
            print(f"  ❌ {xml_file.name} FAILED some tests\n")
            all_passed = False

        results.append((xml_file.name, tool_passed, tool_results))

    # Summary
    print(f"\n{'='*70}")
    print("TEST SUMMARY")
    print(f"{'='*70}\n")

    passed_count = sum(1 for _, passed, _ in results if passed)
    failed_count = len(results) - passed_count

    print(f"Total tools tested: {len(results)}")
    print(f"Passed: {passed_count} ✅")
    print(f"Failed: {failed_count} ❌")
    print(f"Success rate: {100 * passed_count / len(results):.1f}%\n")

    if all_passed:
        print("🎉 ALL TESTS PASSED! Tools are ready for deployment.")
    else:
        print("⚠️  Some tests failed. Please review failures above.")

    # Save results to JSON
    test_results = {
        "timestamp": "2025-10-12T16:30:00.000Z",
        "total_tools": len(results),
        "passed": passed_count,
        "failed": failed_count,
        "success_rate": round(100 * passed_count / len(results), 1),
        "tools": [
            {
                "filename": filename,
                "passed": passed,
                "tests": [
                    {"name": name, "passed": p, "message": msg}
                    for name, p, msg in test_results
                ]
            }
            for filename, passed, test_results in results
        ]
    }

    results_file = tools_dir.parent / "LCMS_TOOLS_TEST_RESULTS_2025-10-12.json"
    with open(results_file, 'w') as f:
        json.dump(test_results, f, indent=2)

    print(f"\n📄 Test results saved to: {results_file}")

    return all_passed

def main():
    tools_dir = Path(__file__).parent.parent / "tools" / "nfcore_lcms"

    if not tools_dir.exists():
        print(f"❌ Tools directory not found: {tools_dir}")
        sys.exit(1)

    success = run_all_tests(tools_dir)
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
