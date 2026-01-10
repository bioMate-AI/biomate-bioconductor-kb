#!/usr/bin/env python3
"""
Galaxy wrapper for UniProt REST API queries.
Directly queries UniProt without requiring the full Biomni library.
"""

import argparse
import json
import sys
import urllib.request
import urllib.parse
import urllib.error


def query_uniprot_api(query=None, accession=None, output_format="fasta"):
    """
    Query UniProt REST API.

    Args:
        query: Search query string
        accession: Direct UniProt accession ID
        output_format: Output format (fasta, json, txt, gff)

    Returns:
        str: API response content
    """
    base_url = "https://rest.uniprot.org"

    # Map format to UniProt format parameter
    format_map = {
        "fasta": "fasta",
        "json": "json",
        "txt": "txt",
        "gff": "gff"
    }
    fmt = format_map.get(output_format, "fasta")

    if accession:
        # Direct accession lookup
        url = f"{base_url}/uniprotkb/{accession}.{fmt}"
    elif query:
        # Search query
        encoded_query = urllib.parse.quote(query)
        url = f"{base_url}/uniprotkb/search?query={encoded_query}&format={fmt}"
    else:
        raise ValueError("Either query or accession must be provided")

    # Make request
    try:
        req = urllib.request.Request(url)
        req.add_header('User-Agent', 'Galaxy-BioMate/1.0 (UniProt query tool)')

        with urllib.request.urlopen(req, timeout=60) as response:
            content = response.read().decode('utf-8')

            if not content.strip():
                return f"No results found for: {accession or query}"

            return content

    except urllib.error.HTTPError as e:
        if e.code == 404:
            return f"Entry not found: {accession or query}"
        raise Exception(f"UniProt API error: {e.code} - {e.reason}")
    except urllib.error.URLError as e:
        raise Exception(f"Network error: {e.reason}")


def main():
    parser = argparse.ArgumentParser(description="Query UniProt REST API")
    parser.add_argument("--query", help="Search query string")
    parser.add_argument("--accession", help="UniProt accession ID")
    parser.add_argument("--format", default="fasta",
                        choices=["fasta", "json", "txt", "gff"],
                        help="Output format")
    parser.add_argument("--output", required=True, help="Output file path")

    args = parser.parse_args()

    if not args.query and not args.accession:
        print("Error: Either --query or --accession must be provided", file=sys.stderr)
        sys.exit(1)

    try:
        result = query_uniprot_api(
            query=args.query,
            accession=args.accession,
            output_format=args.format
        )

        with open(args.output, 'w') as f:
            f.write(result)

        print(f"Successfully queried UniProt", file=sys.stderr)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
