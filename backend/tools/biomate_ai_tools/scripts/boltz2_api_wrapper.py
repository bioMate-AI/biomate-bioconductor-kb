#!/usr/bin/env python3
"""Boltz-2 API wrapper - Structure prediction via NVIDIA NIM"""
import argparse
import json
import os
import requests
import sys
import yaml

NVIDIA_NIM_API = "https://integrate.api.nvidia.com/v1"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--api_key", default=None)
    args = parser.parse_args()

    api_key = args.api_key or os.environ.get("NVIDIA_API_KEY")
    if not api_key:
        print("ERROR: NVIDIA_API_KEY not set", file=sys.stderr)
        print("Get your API key at: https://build.nvidia.com/mit/boltz2", file=sys.stderr)
        sys.exit(1)

    # Read input YAML
    with open(args.input, "r") as f:
        input_data = yaml.safe_load(f)

    print("Submitting to Boltz-2 NVIDIA NIM API...")

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    # Convert to Boltz-2 NIM API format
    payload = {
        "sequences": input_data.get("sequences", []),
        "return_confidence": True
    }

    response = requests.post(
        f"{NVIDIA_NIM_API}/biology/mit/boltz2/predict",
        headers=headers,
        json=payload,
        timeout=600  # 10 minute timeout for large structures
    )

    if response.status_code != 200:
        print(f"ERROR: API returned status {response.status_code}", file=sys.stderr)
        print(response.text, file=sys.stderr)
        sys.exit(1)

    result = response.json()

    # Extract structure
    structure = result.get("structure", result.get("cif", ""))

    with open(args.output, "w") as f:
        if isinstance(structure, str):
            f.write(structure)
        else:
            f.write(str(result))

    print("Successfully predicted structure via Boltz-2 API")
    if "confidence" in result:
        print(f"Confidence: {result['confidence']}")
    if "affinity" in result:
        print(f"Binding affinity: {result['affinity']}")

if __name__ == "__main__":
    main()
