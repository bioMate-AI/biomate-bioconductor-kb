#!/usr/bin/env python3
"""Evo 2 API wrapper for Galaxy - DNA generation via NVIDIA NIM"""
import argparse
import json
import os
import requests
import sys

NVIDIA_NIM_API = "https://integrate.api.nvidia.com/v1"

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sequence", required=True)
    parser.add_argument("--task", default="generation", choices=["generation", "scoring"])
    parser.add_argument("--num_tokens", type=int, default=100)
    parser.add_argument("--temperature", type=float, default=1.0)
    parser.add_argument("--output", required=True)
    parser.add_argument("--api_key", default=None)
    args = parser.parse_args()

    api_key = args.api_key or os.environ.get("NVIDIA_API_KEY")
    if not api_key:
        print("ERROR: NVIDIA_API_KEY not set", file=sys.stderr)
        print("Get your API key at: https://build.nvidia.com/arcinstitute/evo-2-40b", file=sys.stderr)
        sys.exit(1)

    # Validate DNA sequence
    valid_bases = set("ATCGatcg")
    sequence = args.sequence.strip()
    if not all(c in valid_bases for c in sequence):
        print("ERROR: Sequence must contain only A, T, C, G characters", file=sys.stderr)
        sys.exit(1)

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    if args.task == "generation":
        # Use completion endpoint for DNA generation
        payload = {
            "model": "arcinstitute/evo-2-40b",
            "prompt": sequence.upper(),
            "max_tokens": args.num_tokens,
            "temperature": args.temperature,
            "top_p": 0.95
        }

        response = requests.post(
            f"{NVIDIA_NIM_API}/completions",
            headers=headers,
            json=payload,
            timeout=300
        )
        response.raise_for_status()

        result = response.json()
        generated = result.get("choices", [{}])[0].get("text", "")

        with open(args.output, "w") as f:
            f.write(f"# Evo 2 DNA Generation Result\n")
            f.write(f"# Input sequence length: {len(sequence)}\n")
            f.write(f"# Generated tokens: {args.num_tokens}\n")
            f.write(f"# Temperature: {args.temperature}\n\n")
            f.write(f"# Input sequence:\n{sequence}\n\n")
            f.write(f"# Generated continuation:\n{generated}\n\n")
            f.write(f"# Full sequence:\n{sequence}{generated}\n")

        print(f"Successfully generated {len(generated)} bases")

    else:  # scoring
        # Use embedding/scoring endpoint
        payload = {
            "model": "arcinstitute/evo-2-40b",
            "input": sequence.upper()
        }

        response = requests.post(
            f"{NVIDIA_NIM_API}/embeddings",
            headers=headers,
            json=payload,
            timeout=300
        )
        response.raise_for_status()

        result = response.json()

        with open(args.output, "w") as f:
            f.write(f"# Evo 2 Sequence Scoring Result\n")
            f.write(f"# Input sequence length: {len(sequence)}\n\n")
            f.write(f"# Sequence:\n{sequence}\n\n")
            f.write(f"# Raw API response:\n{json.dumps(result, indent=2)}\n")

        print(f"Successfully scored sequence of length {len(sequence)}")

if __name__ == "__main__":
    main()
