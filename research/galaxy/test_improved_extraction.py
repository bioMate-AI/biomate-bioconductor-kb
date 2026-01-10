#!/usr/bin/env python3
"""
Improved universal path extraction - handle various Galaxy directory structures
"""
from pathlib import Path

def extract_relative_path_v2(extra_file, job_id):
    """
    Universal path extraction with job_id context.

    Strategy:
    1. Find 'jobs' + 'directory' pattern as anchor
    2. Find job_id in the path after anchor
    3. Capture everything after job_id
    """
    extra_file_path = Path(extra_file)
    parts = extra_file_path.parts

    # Find the anchor (anything with 'jobs' and 'directory')
    anchor_idx = None
    for i, part in enumerate(parts):
        if 'jobs' in part.lower() and 'directory' in part.lower():
            anchor_idx = i
            break

    if anchor_idx is None:
        return None

    # Find job_id after the anchor
    job_id_idx = None
    for i in range(anchor_idx + 1, len(parts)):
        if parts[i] == job_id or parts[i] == str(job_id):
            job_id_idx = i
            break

    if job_id_idx is None or job_id_idx + 1 >= len(parts):
        # No job_id found or no parts after it
        return None

    # Capture everything after job_id
    relative_parts = parts[job_id_idx + 1:]
    return '/'.join(relative_parts)

# Test cases with job_id context
test_cases = [
    # (input_path, job_id, expected_output)
    ("/Users/user/galaxy/database/jobs_directory/000/621/configs/tmp.txt", "621", "configs/tmp.txt"),
    ("/opt/galaxy/database/jobs_directory/001/999/working/script.py", "999", "working/script.py"),
    ("/var/galaxy/job_working_directory/def/metadata/info.json", "def", "metadata/info.json"),
    ("/path/jobs_directory/000/621/configs/subdir/file.xml", "621", "configs/subdir/file.xml"),
    ("/some/path/without/jobs/file.txt", "123", None),
]

print("Testing improved universal path extraction (with job_id):")
print("=" * 80)

all_passed = True
for input_path, job_id, expected in test_cases:
    result = extract_relative_path_v2(input_path, job_id)
    passed = result == expected
    all_passed = all_passed and passed
    status = "✅" if passed else "❌"
    print(f"{status} Input: {input_path}")
    print(f"   Job ID:   {job_id}")
    print(f"   Expected: {expected}")
    print(f"   Got:      {result}")
    print()

print("=" * 80)
print("Conclusion:")
if all_passed:
    print("✅ All tests passed! This is a TRULY universal solution.")
    print("   - Works with any 'jobs*directory' pattern")
    print("   - Uses job_id to find the split point")
    print("   - No assumptions about directory structure")
else:
    print("❌ Some tests failed.")
