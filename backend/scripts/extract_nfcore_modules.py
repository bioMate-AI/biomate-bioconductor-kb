#!/usr/bin/env python3
"""
Extract nf-core module names from the nf-core/modules repository.
This will crawl the modules directory and create a list of all modules.
"""

import json
import subprocess
from pathlib import Path

def extract_modules_from_nfcore_repo():
    """
    Extract module list from nf-core/modules repository.
    Assumes the repo is cloned locally or can be cloned.
    """
    # Check if nf-core/modules exists locally
    possible_paths = [
        Path.home() / "nf-core" / "modules",
        Path("/tmp/nf-core-modules"),
    ]

    nfcore_path = None
    for path in possible_paths:
        if path.exists():
            nfcore_path = path
            break

    if not nfcore_path:
        print("nf-core/modules not found locally. Cloning...")
        clone_path = Path("/tmp/nf-core-modules")
        subprocess.run([
            "git", "clone", "--depth=1",
            "https://github.com/nf-core/modules.git",
            str(clone_path)
        ], check=True)
        nfcore_path = clone_path

    # Find all main.nf files in modules/nf-core
    modules_dir = nfcore_path / "modules" / "nf-core"
    if not modules_dir.exists():
        raise FileNotFoundError(f"Modules directory not found: {modules_dir}")

    # Collect module names
    modules = []
    for main_nf in modules_dir.rglob("main.nf"):
        # Get relative path from modules/nf-core/
        rel_path = main_nf.parent.relative_to(modules_dir)
        module_name = str(rel_path).replace(str(Path.cwd()), "")
        modules.append(module_name)

    return sorted(modules)

def main():
    print("Extracting nf-core modules...")

    try:
        modules = extract_modules_from_nfcore_repo()
        print(f"Found {len(modules)} modules")

        # Save to JSON
        output_file = Path(__file__).parent.parent / "nfcore_modules_list.json"
        with open(output_file, 'w') as f:
            json.dump({
                "total_modules": len(modules),
                "modules": modules
            }, f, indent=2)

        print(f"✅ Modules saved to: {output_file}")
        print(f"\nFirst 10 modules:")
        for module in modules[:10]:
            print(f"  - {module}")

    except Exception as e:
        print(f"❌ Error: {e}")
        print("\nFalling back to creating module list from known data...")

        # Fallback: use the 1,629 count mentioned in docs
        # For now, just analyze BioMni without nf-core
        print("Run BioMni analysis only (without nf-core)")
        return

if __name__ == '__main__':
    main()
