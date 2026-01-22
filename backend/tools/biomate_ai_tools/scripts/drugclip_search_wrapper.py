#!/usr/bin/env python3
"""DrugCLIP Search wrapper - Access pre-computed virtual screening database

Website: https://drugclip.com
FREE service - no API key required
Database: 10K proteins × 500M compounds pre-screened
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

DRUGCLIP_API = "https://drugclip.com/api"

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


def write_fallback_output(output_path, target, message):
    """Write fallback output with instructions."""
    with open(output_path, "w") as f:
        f.write("# DrugCLIP Search Results\n")
        f.write(f"# Target: {target}\n")
        f.write(f"# Status: {message}\n")
        f.write("# Visit https://drugclip.com for manual search\n")
        f.write("#\n")
        f.write("rank\tsmiles\tscore\tcompound_id\n")


def main():
    parser = argparse.ArgumentParser(description="DrugCLIP Search - Virtual screening database")
    parser.add_argument("--uniprot_id", required=True, help="Target protein UniProt ID")
    parser.add_argument("--top_k", type=int, default=100, help="Number of top hits")
    parser.add_argument("--output", required=True, help="Output file")
    parser.add_argument("--retries", type=int, default=3, help="Number of retries")
    args = parser.parse_args()

    uniprot_id = args.uniprot_id.strip().upper()

    # Validate UniProt ID
    if not uniprot_id or len(uniprot_id) < 4:
        print_error(
            "Invalid UniProt ID",
            f"'{uniprot_id}' is not a valid UniProt accession.",
            "UniProt IDs are typically 6-10 characters (e.g., P12345).\n"
            "  Search at https://www.uniprot.org to find the correct ID."
        )
        sys.exit(ERROR_NOT_FOUND)

    print(f"DrugCLIP Search: Looking for pre-computed hits for {uniprot_id}...")

    for attempt in range(args.retries):
        try:
            response = requests.get(
                f"{DRUGCLIP_API}/search",
                params={"target": uniprot_id, "top_k": args.top_k},
                timeout=60
            )

            # Success
            if response.status_code == 200:
                results = response.json()
                hits = results.get("hits", [])

                if not hits:
                    print(f"\nNote: No pre-computed results for {uniprot_id}")
                    print("This protein may not be in the DrugCLIP database (10K proteins).")
                    print("Use the web interface for custom screening: https://drugclip.com")
                    write_fallback_output(args.output, uniprot_id, "No pre-computed results")
                    return 0

                with open(args.output, "w") as f:
                    f.write("rank\tsmiles\tscore\tcompound_id\n")
                    for i, hit in enumerate(hits[:args.top_k], 1):
                        f.write(f"{i}\t{hit.get('smiles', 'N/A')}\t{hit.get('score', 'N/A')}\t"
                                f"{hit.get('id', 'N/A')}\n")

                print(f"\nSUCCESS: Found {len(hits)} compounds for {uniprot_id}")
                print(f"Output: {args.output}")
                return 0

            # Not found
            elif response.status_code == 404:
                print_error(
                    "Target Not Found",
                    f"Protein {uniprot_id} is not in the DrugCLIP database.\n\n"
                    f"DrugCLIP has pre-computed results for ~10,000 proteins.\n"
                    f"Your target may not be included.",
                    "Options:\n"
                    "  1. Use the web interface for custom screening: https://drugclip.com\n"
                    "  2. Use local DrugCLIP tool to screen your own target\n"
                    "  3. Check if the UniProt ID is correct"
                )
                write_fallback_output(args.output, uniprot_id, "Target not in database")
                sys.exit(ERROR_NOT_FOUND)

            # Rate limit
            elif response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                print_error(
                    "Rate Limit Exceeded",
                    f"DrugCLIP API rate limit reached.",
                    f"Wait {retry_after} seconds and try again.\n"
                    f"  Or use the web interface: https://drugclip.com"
                )
                if attempt < args.retries - 1:
                    wait_time = min(int(retry_after), 60)
                    print(f"Waiting {wait_time} seconds before retry...")
                    time.sleep(wait_time)
                    continue
                write_fallback_output(args.output, uniprot_id, "Rate limit exceeded")
                sys.exit(ERROR_RATE_LIMIT)

            # Server error
            elif response.status_code >= 500:
                if attempt < args.retries - 1:
                    print(f"Server error. Retry {attempt + 2}/{args.retries}...")
                    time.sleep(10)
                    continue
                print_error(
                    "Server Error",
                    f"DrugCLIP server error (HTTP {response.status_code}).",
                    "Try the web interface: https://drugclip.com"
                )
                write_fallback_output(args.output, uniprot_id, "Server error")
                sys.exit(ERROR_SERVER)

            # Other errors - provide fallback
            else:
                print(f"Note: API returned status {response.status_code}", file=sys.stderr)
                print(f"Please use https://drugclip.com directly for {uniprot_id}")
                write_fallback_output(args.output, uniprot_id, f"HTTP {response.status_code}")
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
            print(f"Note: Could not connect to DrugCLIP API: {e}", file=sys.stderr)
            break

    # Fallback for connection issues
    print(f"\nCould not connect to DrugCLIP API.")
    print(f"Please use the web interface: https://drugclip.com")
    write_fallback_output(args.output, uniprot_id, "Connection failed - use web interface")
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
