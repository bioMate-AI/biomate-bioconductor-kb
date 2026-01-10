#!/usr/bin/env python3
"""
Test Galaxy Tool Executor
"""

import asyncio
import sys
import os
import logging

# Setup logging
logging.basicConfig(level=logging.DEBUG, format='%(name)s - %(levelname)s - %(message)s')

# Add galaxy_cloud to path
sys.path.insert(0, os.path.dirname(__file__))

from galaxy_cloud.galaxy_workflow.tool_executor import GalaxyToolExecutor, CollectionElement


async def test_collection_element_identifiers():
    """Test parsing and command generation for collection_element_identifiers tool"""

    executor = GalaxyToolExecutor()

    tool_id = "toolshed.g2.bx.psu.edu/repos/iuc/collection_element_identifiers/collection_element_identifiers/0.0.2"

    print(f"\n{'=' * 70}")
    print(f"Testing tool: {tool_id}")
    print(f"{'=' * 70}\n")

    # Step 1: Fetch XML
    print("Step 1: Fetching tool XML...")
    xml_content = await executor.get_tool_xml(tool_id)
    if xml_content:
        print(f"✓ Successfully fetched XML ({len(xml_content)} characters)")
        print(f"\nFirst 500 characters:")
        print(xml_content[:500])
    else:
        print("✗ Failed to fetch XML")
        return

    # Step 2: Parse XML
    print(f"\n{'=' * 70}")
    print("Step 2: Parsing tool XML...")
    tool_info = executor.parse_tool_xml(xml_content)
    print(f"✓ Tool name: {tool_info.get('name')}")
    print(f"✓ Tool version: {tool_info.get('version')}")
    print(f"✓ Command: {tool_info.get('command')}")
    print(f"✓ Configfiles: {list(tool_info.get('configfiles', {}).keys())}")
    print(f"✓ Inputs: {list(tool_info.get('inputs', {}).keys())}")
    print(f"✓ Outputs: {list(tool_info.get('outputs', {}).keys())}")

    if tool_info.get('configfiles'):
        print(f"\nConfigfile 'cf' template:")
        print(tool_info['configfiles'].get('cf', ''))

    # Step 3: Build command with mock input
    print(f"\n{'=' * 70}")
    print("Step 3: Building command with mock collection...")

    # Create mock collection input
    mock_collection = [
        CollectionElement('sample1'),
        CollectionElement('sample2'),
        CollectionElement('sample3')
    ]

    input_files = {
        'input_collection': mock_collection
    }

    output_files = {
        'output': '/data/output.txt'
    }

    tool_state = {}

    result = await executor.build_tool_command(
        tool_id=tool_id,
        tool_state=tool_state,
        input_files=input_files,
        output_files=output_files
    )

    if result:
        print(f"✓ Command generated successfully:")
        print(f"\nCommand: {result['command']}")
        print(f"\nConfigfiles:")
        for name, content in result['configfiles'].items():
            print(f"  {name}:")
            print(f"    {content}")
        print(f"\nWorking directory: {result['working_dir']}")
    else:
        print("✗ Failed to build command")

    print(f"\n{'=' * 70}")
    print("Test completed!")
    print(f"{'=' * 70}\n")


if __name__ == "__main__":
    asyncio.run(test_collection_element_identifiers())
