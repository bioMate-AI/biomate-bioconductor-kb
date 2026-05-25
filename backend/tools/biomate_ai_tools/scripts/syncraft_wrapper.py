#!/usr/bin/env python3
"""SynCraft wrapper - LLM-guided retrosynthesis for molecular synthesizability

Requires: GEMINI_API_KEY environment variable
Model: Gemini 2.5 Pro (Google AI)

Rate Limits (Gemini API):
- Free tier: 60 requests/minute, 1500 requests/day
- See: https://ai.google.dev/pricing
"""
import argparse
import json
import os
import subprocess
import sys
import time

# SynCraft installation directory
SYNCRAFT_DIR = os.environ.get("SYNCRAFT_DIR", "/opt/biomate/tools_repos/syncraft")

# Error codes
ERROR_NO_API_KEY = 10
ERROR_RATE_LIMIT = 11
ERROR_QUOTA_EXCEEDED = 12
ERROR_INVALID_INPUT = 13
ERROR_API_ERROR = 14


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


def check_api_key():
    """Check if Gemini API key is available."""
    api_key = os.environ.get("GEMINI_API_KEY")
    if not api_key:
        print_error(
            "Missing API Key",
            "GEMINI_API_KEY environment variable is not set.\n"
            "SynCraft requires a Google Gemini API key to function.",
            "Get your FREE API key at: https://aistudio.google.com/apikey\n"
            "  Then set it with: export GEMINI_API_KEY='your-key-here'"
        )
        sys.exit(ERROR_NO_API_KEY)
    return api_key


def validate_smiles(smiles):
    """Basic SMILES validation."""
    if not smiles or len(smiles.strip()) < 2:
        return False, "SMILES string is too short"

    # Check for valid SMILES characters
    valid_chars = set("CNOPSFIBrcnops[]()=#@+-.\\/%0123456789")
    invalid = set(smiles) - valid_chars
    if invalid:
        return False, f"Invalid characters in SMILES: {invalid}"

    # Check for balanced brackets
    if smiles.count('[') != smiles.count(']'):
        return False, "Unbalanced square brackets"
    if smiles.count('(') != smiles.count(')'):
        return False, "Unbalanced parentheses"

    return True, None


def run_syncraft(args):
    """Run SynCraft synthesizability optimization."""
    api_key = check_api_key()

    # Validate SMILES
    valid, error_msg = validate_smiles(args.smiles)
    if not valid:
        print_error(
            "Invalid SMILES",
            f"The provided SMILES string is invalid.\n"
            f"Input: {args.smiles}\n"
            f"Error: {error_msg}",
            "Check your SMILES notation.\n"
            "  Use a tool like https://pubchem.ncbi.nlm.nih.gov to validate."
        )
        sys.exit(ERROR_INVALID_INPUT)

    print("SynCraft: Optimizing molecular synthesizability...")
    print(f"Input SMILES: {args.smiles}")
    print(f"Model: {args.model}")
    print(f"Few-shot examples: {args.few_shot_k}")

    # Create input JSON for SynCraft
    input_data = {
        "molecules": [{"smiles": args.smiles, "id": "input_mol"}]
    }

    input_file = args.output + ".input.json"
    try:
        with open(input_file, "w") as f:
            json.dump(input_data, f)
    except IOError as e:
        print_error(
            "File Error",
            f"Could not write input file: {e}",
            "Check disk space and permissions."
        )
        sys.exit(ERROR_INVALID_INPUT)

    script = os.path.join(SYNCRAFT_DIR, "src", "inference_enhanced.py")

    if not os.path.exists(script):
        print_error(
            "SynCraft Not Found",
            f"SynCraft script not found at: {script}",
            f"Ensure SynCraft is installed at: {SYNCRAFT_DIR}"
        )
        sys.exit(ERROR_INVALID_INPUT)

    cmd = [
        sys.executable, script,
        "--input", input_file,
        "--output", args.output,
        "--model", args.model,
        "--few-shot-k", str(args.few_shot_k),
        "--pass-k", str(args.pass_k)
    ]

    env = os.environ.copy()
    env["PYTHONPATH"] = f"{SYNCRAFT_DIR}/src:{env.get('PYTHONPATH', '')}"

    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            env=env,
            cwd=SYNCRAFT_DIR,
            timeout=300  # 5 minute timeout
        )

        # Clean up input file
        if os.path.exists(input_file):
            os.remove(input_file)

        # Check for rate limit errors in output
        output = result.stdout + result.stderr

        if "429" in output or "rate limit" in output.lower() or "quota" in output.lower():
            print_error(
                "Rate Limit Exceeded",
                "Gemini API rate limit or quota exceeded.\n\n"
                "Free tier limits:\n"
                "  - 60 requests per minute\n"
                "  - 1,500 requests per day",
                "Wait a few minutes and try again.\n"
                "  Or upgrade your Gemini API plan at https://ai.google.dev/pricing"
            )
            sys.exit(ERROR_RATE_LIMIT)

        if "quota" in output.lower() and "exceeded" in output.lower():
            print_error(
                "Daily Quota Exceeded",
                "You've exceeded the daily Gemini API quota.\n\n"
                "Free tier allows 1,500 requests per day.",
                "Wait until tomorrow (quota resets at midnight PT).\n"
                "  Or upgrade your plan at https://ai.google.dev/pricing"
            )
            sys.exit(ERROR_QUOTA_EXCEEDED)

        if "invalid api key" in output.lower() or "api_key_invalid" in output.lower():
            print_error(
                "Invalid API Key",
                "The GEMINI_API_KEY is invalid or expired.",
                "Get a new API key at: https://aistudio.google.com/apikey\n"
                "  Then update: export GEMINI_API_KEY='new-key-here'"
            )
            sys.exit(ERROR_NO_API_KEY)

        if result.returncode != 0:
            print_error(
                "SynCraft Error",
                f"SynCraft execution failed.\n\n"
                f"Error output:\n{result.stderr[:500]}",
                "Check the error message above.\n"
                "  Ensure your SMILES is valid and try again."
            )
            sys.exit(ERROR_API_ERROR)

        print(result.stdout)
        print("\nSUCCESS: Synthesizability optimization complete!")
        print(f"Output: {args.output}")
        return 0

    except subprocess.TimeoutExpired:
        if os.path.exists(input_file):
            os.remove(input_file)
        print_error(
            "Timeout",
            "SynCraft took too long to complete (>5 minutes).",
            "Try a simpler molecule or reduce the number of passes."
        )
        sys.exit(ERROR_API_ERROR)

    except Exception as e:
        if os.path.exists(input_file):
            os.remove(input_file)
        print_error(
            "Unexpected Error",
            f"An unexpected error occurred: {e}",
            "Check the error message and try again."
        )
        sys.exit(ERROR_API_ERROR)


def main():
    parser = argparse.ArgumentParser(description="SynCraft: LLM-guided retrosynthesis")
    parser.add_argument("--smiles", required=True, help="Input SMILES string")
    parser.add_argument("--output", required=True, help="Output JSON file")
    parser.add_argument("--model", default="gemini/gemini-2.5-pro",
                        help="LLM model to use")
    parser.add_argument("--few_shot_k", type=int, default=5,
                        help="Number of few-shot examples")
    parser.add_argument("--pass_k", type=int, default=3,
                        help="Number of parallel inference passes")

    args = parser.parse_args()
    return run_syncraft(args)


if __name__ == "__main__":
    sys.exit(main() or 0)
