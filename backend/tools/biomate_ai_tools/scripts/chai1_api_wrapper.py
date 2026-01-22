#!/usr/bin/env python3
"""Chai-1 API wrapper for Galaxy"""
import argparse
import json
import os
import requests
import sys

BIOLM_API = "https://biolm.ai/api/v3"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sequences", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--num_samples", type=int, default=1)
    parser.add_argument("--api_key", default=None)
    args = parser.parse_args()

    api_key = args.api_key or os.environ.get("BIOLM_API_KEY")
    if not api_key:
        print("ERROR: BIOLM_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    sequences = json.loads(args.sequences)

    headers = {"Authorization": f"Token {api_key}", "Content-Type": "application/json"}
    payload = {"items": [{"sequences": sequences, "num_diffn_samples": args.num_samples}]}

    response = requests.post(f"{BIOLM_API}/chai1/predict/", headers=headers, json=payload, timeout=300)
    response.raise_for_status()

    result = response.json()
    with open(args.output, "w") as f:
        f.write(result.get("cif", str(result)))

if __name__ == "__main__":
    main()
