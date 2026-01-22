#!/usr/bin/env python3
"""ProTrek Search wrapper - Search proteins by function, sequence, or structure

API: http://search-protrek.com
FREE service - no API key required
Database: 5B+ proteins (UniProt, NCBI, MGnify)
"""
import argparse
import sys
import time

try:
    import requests
except ImportError:
    print("ERROR: 'requests' package required. Install with: pip install requests", file=sys.stderr)
    sys.exit(1)

PROTREK_API = "http://search-protrek.com/api"

# Error codes
ERROR_RATE_LIMIT = 10
ERROR_SERVER = 11
ERROR_NETWORK = 12
ERROR_VALIDATION = 13


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


def write_fallback_output(output_path, query, message):
    """Write fallback output with instructions."""
    with open(output_path, "w") as f:
        f.write("# ProTrek Search Results\n")
        f.write(f"# Query: {query}\n")
        f.write(f"# Status: {message}\n")
        f.write("# Visit http://search-protrek.com for manual search\n")
        f.write("#\n")
        f.write("rank\tprotein_id\tscore\torganism\tdescription\n")


def main():
    parser = argparse.ArgumentParser(description="ProTrek Search - Protein search by function/sequence")
    parser.add_argument("--query", required=True, help="Search query")
    parser.add_argument("--search_type", default="function", choices=["function", "sequence"])
    parser.add_argument("--database", default="uniprot", choices=["uniprot", "ncbi", "mgnify"])
    parser.add_argument("--top_k", type=int, default=100)
    parser.add_argument("--output", required=True)
    parser.add_argument("--retries", type=int, default=3)
    args = parser.parse_args()

    query = args.query.strip()

    # Validate query
    if not query:
        print_error(
            "Empty Query",
            "Search query cannot be empty.",
            "Provide a function description or protein sequence."
        )
        sys.exit(ERROR_VALIDATION)

    if args.search_type == "sequence" and len(query) < 10:
        print_error(
            "Sequence Too Short",
            f"Sequence query has only {len(query)} characters.\n"
            f"Minimum recommended length is 10 amino acids.",
            "Provide a longer sequence for meaningful results."
        )
        sys.exit(ERROR_VALIDATION)

    print(f"ProTrek Search: Searching {args.database} by {args.search_type}...")
    print(f"Query: {query[:50]}{'...' if len(query) > 50 else ''}")

    for attempt in range(args.retries):
        try:
            response = requests.post(
                f"{PROTREK_API}/search",
                json={
                    "query": query,
                    "type": args.search_type,
                    "database": args.database,
                    "top_k": args.top_k
                },
                timeout=120
            )

            # Success
            if response.status_code == 200:
                results = response.json()
                hits = results.get("hits", [])

                with open(args.output, "w") as f:
                    f.write("rank\tprotein_id\tscore\torganism\tdescription\n")
                    for i, hit in enumerate(hits[:args.top_k], 1):
                        f.write(f"{i}\t{hit.get('id', 'N/A')}\t{hit.get('score', 'N/A')}\t"
                                f"{hit.get('organism', 'N/A')}\t{hit.get('description', 'N/A')}\n")

                print(f"\nSUCCESS: Found {len(hits)} proteins")
                print(f"Output: {args.output}")
                return 0

            # Rate limit
            elif response.status_code == 429:
                retry_after = response.headers.get("Retry-After", "60")
                print_error(
                    "Rate Limit Exceeded",
                    f"ProTrek API rate limit reached.\n"
                    f"You've made too many requests.",
                    f"Wait {retry_after} seconds and try again.\n"
                    f"  Or use the web interface: http://search-protrek.com"
                )
                if attempt < args.retries - 1:
                    wait_time = min(int(retry_after), 60)
                    print(f"Waiting {wait_time} seconds before retry...")
                    time.sleep(wait_time)
                    continue
                write_fallback_output(args.output, query, "Rate limit exceeded")
                sys.exit(ERROR_RATE_LIMIT)

            # Server error
            elif response.status_code >= 500:
                if attempt < args.retries - 1:
                    print(f"Server error ({response.status_code}). Retry {attempt + 2}/{args.retries}...")
                    time.sleep(10)
                    continue
                print_error(
                    "Server Error",
                    f"ProTrek server error (HTTP {response.status_code}).",
                    "The service may be temporarily unavailable.\n"
                    "  Try the web interface: http://search-protrek.com"
                )
                write_fallback_output(args.output, query, "Server error")
                sys.exit(ERROR_SERVER)

            # Other errors
            else:
                print(f"Note: API returned status {response.status_code}", file=sys.stderr)
                print("Falling back to manual search instructions.", file=sys.stderr)
                write_fallback_output(args.output, query, f"HTTP {response.status_code}")
                print(f"\nPlease use http://search-protrek.com directly")
                return 0

        except requests.exceptions.Timeout:
            if attempt < args.retries - 1:
                print(f"Request timed out. Retry {attempt + 2}/{args.retries}...")
                time.sleep(10)
                continue
            print_error(
                "Request Timeout",
                "The search took too long to complete.",
                "Try a shorter query or use the web interface:\n"
                "  http://search-protrek.com"
            )
            write_fallback_output(args.output, query, "Timeout")
            sys.exit(ERROR_NETWORK)

        except requests.exceptions.ConnectionError:
            if attempt < args.retries - 1:
                print(f"Connection error. Retry {attempt + 2}/{args.retries}...")
                time.sleep(10)
                continue
            print_error(
                "Connection Failed",
                "Could not connect to ProTrek API.",
                "Check your internet connection.\n"
                "  Or use the web interface: http://search-protrek.com"
            )
            write_fallback_output(args.output, query, "Connection failed")
            sys.exit(ERROR_NETWORK)

        except requests.exceptions.RequestException as e:
            print_error(
                "Network Error",
                f"Request failed: {e}",
                "Use the web interface: http://search-protrek.com"
            )
            write_fallback_output(args.output, query, str(e))
            sys.exit(ERROR_NETWORK)

    print_error(
        "All Retries Failed",
        f"Could not complete search after {args.retries} attempts.",
        "Use the web interface: http://search-protrek.com"
    )
    write_fallback_output(args.output, query, "All retries failed")
    sys.exit(ERROR_NETWORK)


if __name__ == "__main__":
    sys.exit(main() or 0)
