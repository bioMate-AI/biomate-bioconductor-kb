#!/usr/bin/env python3
"""
Test universal path extraction logic
"""
from pathlib import Path

test_cases = [
    # (input_path, expected_output)
    ("/Users/user/galaxy/database/jobs_directory/000/621/configs/tmp.txt", "configs/tmp.txt"),
    ("/opt/galaxy/database/jobs_directory/001/999/working/script.py", "working/script.py"),
    ("/var/galaxy/job_working_directory/abc/def/metadata/info.json", "metadata/info.json"),
    ("/path/jobs_directory/000/621/configs/subdir/file.xml", "configs/subdir/file.xml"),
    ("/some/path/without/jobs/file.txt", None),  # No anchor, should return None
]

def extract_relative_path(extra_file):
    """Universal path extraction logic"""
    extra_file_path = Path(extra_file)
    parts = extra_file_path.parts

    relative_path = None
    for i, part in enumerate(parts):
        if 'jobs' in part.lower() and 'directory' in part.lower():
            # Found the anchor
            # Skip the next 2 parts (shard and job_id)
            if i + 3 < len(parts):
                relative_parts = parts[i + 3:]
                relative_path = '/'.join(relative_parts)
            break

    return relative_path

print("Testing universal path extraction:")
print("=" * 80)

for input_path, expected in test_cases:
    result = extract_relative_path(input_path)
    status = "✅" if result == expected else "❌"
    print(f"{status} Input: {input_path}")
    print(f"   Expected: {expected}")
    print(f"   Got:      {result}")
    print()

print("=" * 80)
print("Conclusion:")
if all(extract_relative_path(inp) == exp for inp, exp in test_cases):
    print("✅ All tests passed! This is a universal solution.")
else:
    print("❌ Some tests failed.")
