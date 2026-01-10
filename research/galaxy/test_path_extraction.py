#!/usr/bin/env python3
"""
Test universal path extraction from commands
"""
import re

# Test command (real example from job 607)
command = """times=1; yes -- 'GeneID__tc__Base mean__tc__log2(FC)__tc__StdErr__tc__Wald-Stats__tc__P-value__tc__P-adj__tc__Chromosome__tc__Start__tc__End__tc__Strand__tc__Feature__tc__Gene name' 2>/dev/null | head -n $times >> '/galaxy_execution/datasets/objects/4/2/8/dataset_4283efa5-1d50-490b-9d45-3e53a4670bb5.dat';"""

print("Command:")
print(command)
print()

# Extract paths using the pattern
path_pattern = r'["\']([/][^"\']+)["\']'
paths = set(re.findall(path_pattern, command))

print("Extracted paths:")
for path in sorted(paths):
    print(f"  {path}")
print()

# Check if it matches output files
print("Paths that need directory creation:")
for path in sorted(paths):
    if '/datasets/' in path and path.endswith('.dat'):
        dirname = path.rsplit('/', 1)[0]
        print(f"  mkdir -p {dirname}")
        print(f"    for file: {path}")
