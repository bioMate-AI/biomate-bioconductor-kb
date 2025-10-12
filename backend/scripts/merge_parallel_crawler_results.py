#!/usr/bin/env python3
"""
Merge parallel crawler category files into single JSON for tool collection.
"""

import json
from pathlib import Path
from datetime import datetime


def merge_parallel_crawler_results(categories_dir: str, output_file: str):
    """
    Merge all category/*.json files into a single crawledData structure.
    """
    categories_path = Path(categories_dir)

    if not categories_path.exists():
        raise FileNotFoundError(f"Categories directory not found: {categories_dir}")

    # Collect all category files
    category_files = sorted(categories_path.glob("*.json"))

    print(f"Found {len(category_files)} category files")

    # Build merged structure
    merged_data = {
        "timestamp": datetime.now().isoformat(),
        "version": "v3_parallel",
        "crawledData": {}
    }

    total_repos = 0
    total_tools = 0

    for idx, cat_file in enumerate(category_files):
        try:
            with open(cat_file, 'r') as f:
                cat_data = json.load(f)

            category_name = cat_data.get('category', cat_file.stem)
            repos = cat_data.get('repositories', [])

            # Count tools
            tools_in_cat = sum(len(repo.get('tools', [])) for repo in repos)

            merged_data['crawledData'][idx] = cat_data

            total_repos += len(repos)
            total_tools += tools_in_cat

            print(f"  ✓ {category_name:40s}: {len(repos):4d} repos, {tools_in_cat:5d} tools")

        except Exception as e:
            print(f"  ✗ Error processing {cat_file.name}: {e}")

    # Add statistics
    merged_data['statistics'] = {
        'totalCategories': len(category_files),
        'totalRepositories': total_repos,
        'totalTools': total_tools
    }

    # Save merged file
    output_path = Path(output_file)
    with open(output_path, 'w') as f:
        json.dump(merged_data, f, indent=2)

    print(f"\n✅ Merged Results:")
    print(f"   Categories: {len(category_files)}")
    print(f"   Repositories: {total_repos}")
    print(f"   Tools: {total_tools}")
    print(f"   Output: {output_path}")

    return merged_data


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description="Merge parallel crawler results")
    parser.add_argument(
        '--categories-dir',
        default='/Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete/categories',
        help='Directory containing category JSON files'
    )
    parser.add_argument(
        '--output',
        default='/Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete/parallel_crawler_merged.json',
        help='Output merged JSON file'
    )

    args = parser.parse_args()

    merge_parallel_crawler_results(args.categories_dir, args.output)
