#!/usr/bin/env python3
"""ESMFold API wrapper - Free protein structure prediction from Meta

API: https://api.esmatlas.com
Limits: 400 residues max, rate limited
"""
import argparse
import sys
import time

try:
    import requests
except ImportError:
    print("ERROR: 'requests' package required. Install with: pip install requests", file=sys.stderr)
    sys.exit(1)

ESMFOLD_API = "https://api.esmatlas.com/foldSequence/v1/pdb/"

# Error codes and messages
ERROR_RATE_LIMIT = 10
ERROR_SERVER = 11
ERROR_VALIDATION = 12
ERROR_TIMEOUT = 13
ERROR_UNKNOWN = 14


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
    parser = argparse.ArgumentParser(description="ESMFold API - Free structure prediction")
    parser.add_argument("--sequence", required=True, help="Protein sequence")
    parser.add_argument("--output", required=True, help="Output PDB file")
    parser.add_argument("--retries", type=int, default=3, help="Number of retries on failure")
    args = parser.parse_args()

    sequence = args.sequence.strip().upper().replace(" ", "").replace("\n", "")

    # Validate sequence
    valid_aa = set("ACDEFGHIKLMNPQRSTVWY")
    invalid_chars = set(sequence) - valid_aa
    if invalid_chars:
        print_error(
            "Invalid Sequence",
            f"Sequence contains invalid characters: {invalid_chars}\n"
            f"Only standard amino acids are allowed: {''.join(sorted(valid_aa))}",
            "Check your sequence for non-standard residues or nucleotides."
        )
        sys.exit(ERROR_VALIDATION)

    if len(sequence) > 400:
        print_error(
            "Sequence Too Long",
            f"Your sequence has {len(sequence)} residues.\n"
            f"ESMFold API limit is 400 residues maximum.",
            "Use AlphaFold 3 Server or Chai-1 for longer sequences (no length limit)."
        )
        sys.exit(ERROR_VALIDATION)

    if len(sequence) < 10:
        print_error(
            "Sequence Too Short",
            f"Your sequence has only {len(sequence)} residues.\n"
            f"Minimum recommended length is 10 residues.",
            "Provide a longer protein sequence."
        )
        sys.exit(ERROR_VALIDATION)

    print(f"ESMFold API: Predicting structure for {len(sequence)} residue sequence...")

    # Retry logic with exponential backoff
    last_error = None
    for attempt in range(args.retries):
        try:
            response = requests.post(
                ESMFOLD_API,
                data=sequence,
                headers={"Content-Type": "text/plain"},
                timeout=300
            )

            # Success
            if response.status_code == 200:
                with open(args.output, "w") as f:
                    f.write(response.text)
                print(f"\nSUCCESS: Structure predicted for {len(sequence)} residues")
                print(f"Output saved to: {args.output}")
                return 0

            # Rate limit
            elif response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                print_error(
                    "Rate Limit Exceeded",
                    f"ESMFold API rate limit reached.\n"
                    f"Too many requests in a short period.",
                    f"Wait {retry_after} seconds and try again.\n"
                    f"  Alternatively, use AlphaFold 3 Server (20 jobs/day) or Chai-1 (local)."
                )
                if attempt < args.retries - 1:
                    wait_time = min(int(retry_after), 60)
                    print(f"Waiting {wait_time} seconds before retry {attempt + 2}/{args.retries}...")
                    time.sleep(wait_time)
                    continue
                sys.exit(ERROR_RATE_LIMIT)

            # Server error
            elif response.status_code >= 500:
                print_error(
                    "Server Error",
                    f"ESMFold API server error (HTTP {response.status_code}).\n"
                    f"The service may be temporarily unavailable.",
                    "Try again in a few minutes.\n"
                    "  If the problem persists, use AlphaFold 3 Server or Chai-1."
                )
                if attempt < args.retries - 1:
                    wait_time = 30 * (attempt + 1)
                    print(f"Waiting {wait_time} seconds before retry {attempt + 2}/{args.retries}...")
                    time.sleep(wait_time)
                    continue
                sys.exit(ERROR_SERVER)

            # Client error
            elif response.status_code == 400:
                print_error(
                    "Bad Request",
                    f"The API rejected your request.\n"
                    f"Response: {response.text[:200]}",
                    "Check that your sequence contains only valid amino acids."
                )
                sys.exit(ERROR_VALIDATION)

            # Other errors
            else:
                print_error(
                    "API Error",
                    f"Unexpected response from ESMFold API.\n"
                    f"HTTP Status: {response.status_code}\n"
                    f"Response: {response.text[:200]}",
                    "Try again later or use an alternative tool."
                )
                sys.exit(ERROR_UNKNOWN)

        except requests.exceptions.Timeout:
            last_error = "timeout"
            if attempt < args.retries - 1:
                print(f"Request timed out. Retry {attempt + 2}/{args.retries}...")
                time.sleep(10)
                continue

        except requests.exceptions.ConnectionError as e:
            last_error = str(e)
            if attempt < args.retries - 1:
                print(f"Connection error. Retry {attempt + 2}/{args.retries}...")
                time.sleep(10)
                continue

        except requests.exceptions.RequestException as e:
            last_error = str(e)
            break

    # All retries failed
    print_error(
        "Connection Failed",
        f"Could not connect to ESMFold API after {args.retries} attempts.\n"
        f"Last error: {last_error}",
        "Check your internet connection.\n"
        "  If the problem persists, use AlphaFold 3 Server or Chai-1 (local)."
    )
    sys.exit(ERROR_TIMEOUT)


if __name__ == "__main__":
    sys.exit(main() or 0)
