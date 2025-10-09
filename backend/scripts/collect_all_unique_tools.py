#!/usr/bin/env python3
"""
Collect ALL unique tools with latest versions from Galaxy ToolShed crawled data.

This script reads ALL JSON files from the latest_tools_complete directory,
deduplicates tools, and keeps only the latest version of each unique tool.
"""

import json
import os
from collections import defaultdict
from pathlib import Path
from datetime import datetime


def parse_timestamp(timestamp_str):
    """Parse timestamp string to datetime object."""
    try:
        # Format: 2025-10-08T03-05-31-905Z
        return datetime.strptime(timestamp_str, "%Y-%m-%dT%H-%M-%S-%fZ")
    except:
        return datetime.min


def collect_all_unique_tools(source_dir):
    """
    Collect all unique tools from all JSON files in source directory.

    Returns:
        dict: {unique_tool_key: tool_data_with_metadata}
    """
    source_path = Path(source_dir)
    json_files = sorted(source_path.glob("*.json"))

    # Dictionary to store tools
    # Key: (repo_owner, repo_name, tool_name)
    # Value: complete tool data with metadata
    all_tools = {}

    print(f"Found {len(json_files)} JSON files in {source_dir}")
    print("="*80)

    for json_file in json_files:
        try:
            with open(json_file, 'r', encoding='utf-8') as f:
                data = json.load(f)

            file_timestamp = data.get('timestamp', '')
            parsed_timestamp = parse_timestamp(file_timestamp)

            tools_in_file = 0
            new_tools = 0
            updated_tools = 0

            # Navigate to crawledData
            crawl_data = None
            if isinstance(data, dict) and 'crawledData' in data:
                crawl_data = data['crawledData']
            elif isinstance(data, list):
                crawl_data = {i: item for i, item in enumerate(data)}

            if not crawl_data:
                print(f"⚠️  {json_file.name:55s} | No crawledData found")
                continue

            # Process each category
            items = crawl_data.values() if isinstance(crawl_data, dict) else crawl_data

            for cat_data in items:
                if not isinstance(cat_data, dict) or 'repositories' not in cat_data:
                    continue

                category = cat_data.get('category', 'Unknown')

                for repo in cat_data.get('repositories', []):
                    repo_owner = repo.get('repoOwner', '').strip()
                    repo_name = repo.get('repoName', '').strip()

                    if not repo_owner or not repo_name:
                        continue

                    for tool in repo.get('tools', []):
                        tools_in_file += 1

                        tool_name = tool.get('name', '').strip()
                        tool_version = tool.get('version', '').strip()

                        if not tool_name:
                            continue

                        # Create unique key
                        key = (repo_owner, repo_name, tool_name)

                        # Prepare full tool data
                        tool_data = {
                            'tool_id': f"toolshed.g2.bx.psu.edu/repos/{repo_owner}/{repo_name}/{tool_name.replace(' ', '_')}",
                            'name': tool_name,
                            'version': tool_version,
                            'repo_owner': repo_owner,
                            'repo_name': repo_name,
                            'category': category,
                            'rawText': tool.get('rawText', ''),
                            'htmlContent': tool.get('htmlContent', ''),
                            'url': tool.get('url', ''),
                            'repo_synopsis': repo.get('Synopsis', ''),
                            'repo_url': repo.get('url', ''),
                            'is_installable': repo.get('isInstallable', False),
                            'timestamp': file_timestamp,
                            'source_file': json_file.name
                        }

                        # Check if we already have this tool
                        if key not in all_tools:
                            all_tools[key] = tool_data
                            new_tools += 1
                        else:
                            # Keep the one with later timestamp
                            existing_timestamp = parse_timestamp(all_tools[key]['timestamp'])
                            if parsed_timestamp > existing_timestamp:
                                all_tools[key] = tool_data
                                updated_tools += 1

            print(f"✓ {json_file.name:55s} | {tools_in_file:5d} tools | +{new_tools:4d} new | ~{updated_tools:4d} updated")

        except Exception as e:
            print(f"✗ {json_file.name:55s} | ERROR: {str(e)}")

    return all_tools


def main():
    """Main function."""
    source_dir = "/Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete"

    print("Collecting all unique tools from Galaxy ToolShed crawled data")
    print("="*80)
    print(f"Source directory: {source_dir}\n")

    # Collect all unique tools
    all_tools = collect_all_unique_tools(source_dir)

    # Convert to list for easier processing
    unique_tools_list = list(all_tools.values())

    print("="*80)
    print(f"\n✅ COLLECTION COMPLETE")
    print(f"   Total unique tools (latest versions): {len(unique_tools_list)}")

    # Count by category
    category_counts = defaultdict(int)
    for tool in unique_tools_list:
        category_counts[tool['category']] += 1

    print(f"\n📊 Tools by Category (top 15):")
    for cat, count in sorted(category_counts.items(), key=lambda x: x[1], reverse=True)[:15]:
        print(f"   {cat:40s}: {count:5d} tools")

    # Show sample tool
    if unique_tools_list:
        sample = unique_tools_list[0]
        print(f"\n🔍 Sample Tool Structure:")
        print(f"   Tool ID: {sample['tool_id']}")
        print(f"   Name: {sample['name'][:70]}")
        print(f"   Version: {sample['version']}")
        print(f"   Category: {sample['category']}")
        print(f"   Repo: {sample['repo_owner']}/{sample['repo_name']}")
        print(f"   Has rawText: {len(sample['rawText']) > 0} ({len(sample['rawText'])} chars)")
        print(f"   Has htmlContent: {len(sample['htmlContent']) > 0}")
        print(f"   Is installable: {sample['is_installable']}")

    # Save to output file
    output_file = Path(__file__).parent.parent / "database" / "all_unique_tools.json"
    output_file.parent.mkdir(parents=True, exist_ok=True)

    with open(output_file, 'w', encoding='utf-8') as f:
        json.dump(unique_tools_list, f, indent=2, ensure_ascii=False)

    print(f"\n💾 Saved to: {output_file}")
    print(f"   File size: {output_file.stat().st_size / (1024*1024):.1f} MB")

    return unique_tools_list


if __name__ == '__main__':
    tools = main()