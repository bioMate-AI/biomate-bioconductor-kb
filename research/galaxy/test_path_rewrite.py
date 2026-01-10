#!/usr/bin/env python3
"""
Test path rewriting for output directories
"""

# Simulate path rewriting
local_database_root = "/Users/renyuankai/work/biometa/galaxy/database"
container_datasets_root = "/galaxy_execution/datasets"

local_path = "/Users/renyuankai/work/biometa/galaxy/database/objects/4/2/8/dataset_4283efa5-1d50-490b-9d45-3e53a4670bb5.dat"

# Simple replacement (what UniversalPathRewriter does)
container_path = local_path.replace(
    f"{local_database_root}/objects",
    f"{container_datasets_root}/objects"
)

print(f"Local path:     {local_path}")
print(f"Container path: {container_path}")
print()
print(f"Expected: /galaxy_execution/datasets/objects/4/2/8/dataset_4283efa5-1d50-490b-9d45-3e53a4670bb5.dat")
print(f"Match: {container_path == '/galaxy_execution/datasets/objects/4/2/8/dataset_4283efa5-1d50-490b-9d45-3e53a4670bb5.dat'}")
