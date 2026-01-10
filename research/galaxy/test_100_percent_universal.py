#!/usr/bin/env python3
"""
Test 100% universal path extraction - using job_id as anchor
"""
from pathlib import Path

def extract_relative_path_100_universal(extra_file, job_id):
    """
    100% Universal: use job_id to find split point.
    NO assumptions about directory structure or depth.
    """
    extra_file_path = Path(extra_file)
    parts = extra_file_path.parts

    relative_path = None
    anchor_idx = None

    # Step 1: Find the jobs directory anchor
    for i, part in enumerate(parts):
        if 'jobs' in part.lower() and 'directory' in part.lower():
            anchor_idx = i
            break

    # Step 2: Find job_id after the anchor
    if anchor_idx is not None:
        for j in range(anchor_idx + 1, len(parts)):
            if parts[j] == job_id or parts[j] == str(job_id):
                # Found job_id! Capture everything after it
                if j + 1 < len(parts):
                    relative_path = '/'.join(parts[j + 1:])
                break

    return relative_path

# Comprehensive test cases
test_cases = [
    # Standard Galaxy structure
    ("/Users/user/galaxy/database/jobs_directory/000/621/configs/tmp.txt", "621", "configs/tmp.txt"),

    # Different shard
    ("/opt/galaxy/database/jobs_directory/001/999/working/script.py", "999", "working/script.py"),

    # No shard (job_id directly after jobs_directory)
    ("/var/galaxy/job_working_directory/621/metadata/info.json", "621", "metadata/info.json"),

    # Multiple shard levels
    ("/path/jobs_directory/a/b/c/621/configs/subdir/file.xml", "621", "configs/subdir/file.xml"),

    # No jobs directory
    ("/some/path/without/jobs/621/file.txt", "621", None),

    # Job ID appears but no jobs_directory anchor
    ("/random/path/621/file.txt", "621", None),

    # Real Galaxy example from logs
    ("/Users/renyuankai/work/biometa/galaxy/database/jobs_directory/000/621/configs/tmp2n6r9w3a", "621", "configs/tmp2n6r9w3a"),

    # Nested subdirectories
    ("/opt/jobs_directory/000/621/configs/sub1/sub2/sub3/file.py", "621", "configs/sub1/sub2/sub3/file.py"),
]

print("Testing 100% Universal Path Extraction (with job_id anchor)")
print("=" * 80)

all_passed = True
for i, (input_path, job_id, expected) in enumerate(test_cases, 1):
    result = extract_relative_path_100_universal(input_path, job_id)
    passed = result == expected
    all_passed = all_passed and passed
    status = "✅" if passed else "❌"

    print(f"Test {i}: {status}")
    print(f"  Input:    {input_path}")
    print(f"  Job ID:   {job_id}")
    print(f"  Expected: {expected}")
    print(f"  Got:      {result}")
    print()

print("=" * 80)
if all_passed:
    print("🎯 ALL TESTS PASSED!")
    print()
    print("This implementation is 100% UNIVERSAL because:")
    print("  ✅ No assumptions about directory depth")
    print("  ✅ Uses actual job_id as anchor (not guessing)")
    print("  ✅ Works with 0, 1, 2, or N intermediate directories")
    print("  ✅ Works with any 'jobs*directory' naming")
    print("  ✅ Has safe fallback for edge cases")
else:
    print("❌ Some tests failed - needs improvement")
