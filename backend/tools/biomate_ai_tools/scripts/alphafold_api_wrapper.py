#!/usr/bin/env python3
"""AlphaFold Database API wrapper - Access 200M+ pre-computed structures

API: https://alphafold.ebi.ac.uk/api
Database: 200+ million predicted structures
No rate limit for reasonable usage
"""
import argparse
import json
import sys
import time

try:
    import requests
except ImportError:
    print("ERROR: 'requests' package required. Install with: pip install requests", file=sys.stderr)
    sys.exit(1)

ALPHAFOLD_API = "https://alphafold.ebi.ac.uk/api"

# Error codes
ERROR_NOT_FOUND = 10
ERROR_RATE_LIMIT = 11
ERROR_SERVER = 12
ERROR_NETWORK = 13


def print_error(error_type, message, suggestion=None):
    """Print formatted error message."""
    print("\n" + "=" * 60, file=sys.stderr)
    print(f"ERROR: {error_type}", file=sys.stderr)
    print("=" * 60, file=sys.stderr)
    print(f"\n{message}\n", file=sys.stderr)
    if suggestion:
        print("WHAT TO DO:", file=sys.stderr)
        print(f"  {suggestion}\n", file=sys.stderr)
    print("=" * 60, file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="AlphaFold Database API")
    parser.add_argument("--uniprot_id", required=True, help="UniProt accession ID")
    parser.add_argument("--format", default="pdb", choices=["pdb", "cif"])
    parser.add_argument("--output", required=True, help="Output structure file")
    parser.add_argument("--metadata", required=True, help="Output metadata JSON")
    parser.add_argument("--retries", type=int, default=3, help="Number of retries")
    args = parser.parse_args()

    uniprot_id = args.uniprot_id.strip().upper()

    # Validate UniProt ID format
    if not uniprot_id or len(uniprot_id) < 4:
        print_error(
            "Invalid UniProt ID",
            f"'{uniprot_id}' is not a valid UniProt accession.",
            "UniProt IDs are typically 6-10 characters (e.g., P12345, A0A0A0ABC1).\n"
            "  Search for your protein at https://www.uniprot.org"
        )
        sys.exit(ERROR_NOT_FOUND)

    print(f"AlphaFold Database: Fetching structure for {uniprot_id}...")

    # Retry logic
    for attempt in range(args.retries):
        try:
            # Get metadata
            response = requests.get(
                f"{ALPHAFOLD_API}/prediction/{uniprot_id}",
                timeout=30
            )

            # Structure not found
            if response.status_code == 404:
                print_error(
                    "Structure Not Found",
                    f"No pre-computed structure found for UniProt ID: {uniprot_id}\n\n"
                    f"The AlphaFold Database contains ~200 million structures, but not all\n"
                    f"proteins are covered.",
                    "Options:\n"
                    "  1. Verify the UniProt ID at https://www.uniprot.org\n"
                    "  2. Use AlphaFold 3 Server to predict a new structure (FREE, 20/day)\n"
                    "  3. Use ESMFold API for sequences up to 400 residues (FREE)\n"
                    "  4. Use Chai-1 for local structure prediction"
                )
                sys.exit(ERROR_NOT_FOUND)

            # Rate limit
            if response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                print_error(
                    "Rate Limit Exceeded",
                    f"AlphaFold API rate limit reached.\n"
                    f"You've made too many requests in a short period.",
                    f"Wait {retry_after} seconds and try again.\n"
                    f"  For batch downloads, use the FTP server:\n"
                    f"  https://alphafold.ebi.ac.uk/download"
                )
                if attempt < args.retries - 1:
                    wait_time = min(int(retry_after), 60)
                    print(f"Waiting {wait_time} seconds before retry...")
                    time.sleep(wait_time)
                    continue
                sys.exit(ERROR_RATE_LIMIT)

            # Server error
            if response.status_code >= 500:
                if attempt < args.retries - 1:
                    print(f"Server error. Retry {attempt + 2}/{args.retries}...")
                    time.sleep(10)
                    continue
                print_error(
                    "Server Error",
                    f"AlphaFold API server error (HTTP {response.status_code}).",
                    "Try again in a few minutes.\n"
                    "  Check status at https://alphafold.ebi.ac.uk"
                )
                sys.exit(ERROR_SERVER)

            response.raise_for_status()
            data = response.json()

            if not data:
                print_error(
                    "Empty Response",
                    f"No data returned for {uniprot_id}.",
                    "Try a different UniProt ID or use AlphaFold 3 Server."
                )
                sys.exit(ERROR_NOT_FOUND)

            entry = data[0] if isinstance(data, list) else data

            # Save metadata
            with open(args.metadata, "w") as f:
                json.dump(entry, f, indent=2)

            # Get structure file
            url_key = "pdbUrl" if args.format == "pdb" else "cifUrl"
            url = entry.get(url_key)
            if not url:
                print_error(
                    "Structure URL Missing",
                    f"No {args.format.upper()} file URL in response.",
                    "Try the other format (pdb/cif) or use AlphaFold 3 Server."
                )
                sys.exit(ERROR_NOT_FOUND)

            struct_response = requests.get(url, timeout=60)

            if struct_response.status_code == 429:
                print_error(
                    "Rate Limit Exceeded",
                    "Rate limit hit while downloading structure file.",
                    "Wait a few minutes and try again."
                )
                sys.exit(ERROR_RATE_LIMIT)

            struct_response.raise_for_status()

            with open(args.output, "w") as f:
                f.write(struct_response.text)

            print(f"\nSUCCESS: Structure retrieved for {uniprot_id}")
            print(f"  Gene: {entry.get('gene', 'N/A')}")
            print(f"  Organism: {entry.get('organismScientificName', 'N/A')}")
            print(f"  Confidence: pLDDT {entry.get('globalMetricValue', 'N/A')}")
            print(f"  Output: {args.output}")
            return 0

        except requests.exceptions.Timeout:
            if attempt < args.retries - 1:
                print(f"Request timed out. Retry {attempt + 2}/{args.retries}...")
                time.sleep(5)
                continue

        except requests.exceptions.ConnectionError:
            if attempt < args.retries - 1:
                print(f"Connection error. Retry {attempt + 2}/{args.retries}...")
                time.sleep(5)
                continue

        except requests.exceptions.RequestException as e:
            print_error(
                "Network Error",
                f"Failed to connect to AlphaFold API: {e}",
                "Check your internet connection and try again."
            )
            sys.exit(ERROR_NETWORK)

    print_error(
        "Connection Failed",
        f"Could not connect after {args.retries} attempts.",
        "Check your internet connection or try again later."
    )
    sys.exit(ERROR_NETWORK)


if __name__ == "__main__":
    sys.exit(main() or 0)
