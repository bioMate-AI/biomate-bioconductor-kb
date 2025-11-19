#!/usr/bin/env python3
"""
LLM-Based Feasibility Checker

Uses Claude to determine if a tool is suitable for Galaxy workflow integration.
This is more generalizable than hardcoded rules.

Usage:
    python llm_feasibility_checker.py --tool-json tool_data.json
"""

import argparse
import json
import logging
import os
from pathlib import Path
from typing import Dict, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    import anthropic
    HAS_ANTHROPIC = True
except ImportError:
    HAS_ANTHROPIC = False


class LLMFeasibilityChecker:
    """Use LLM to check if a tool is feasible for Galaxy workflow integration."""

    SYSTEM_PROMPT = """You are an expert in bioinformatics tools and Galaxy workflow systems.

Your task is to evaluate if a software tool is suitable for integration into Galaxy as a workflow tool.

A tool is SUITABLE if:
1. It has a command-line interface (CLI) that can be invoked with parameters
2. It processes biological/scientific data files
3. It can be used as a step in a computational pipeline
4. It produces output files that can be used by other tools

A tool is NOT SUITABLE if:
1. It's a Python/R library without CLI (must be imported, not invoked)
2. It's a web framework or dashboard (Flask, Dash, Streamlit)
3. It's a workflow engine/platform itself (Nextflow, Snakemake, Galaxy)
4. It's a general-purpose library (NumPy, Pandas, TensorFlow)
5. It's educational material (tutorials, courses, workshops)
6. It's an IDE, editor, or development tool

Respond with a JSON object containing:
{
  "suitable": true/false,
  "reason": "Brief explanation",
  "confidence": 0.0-1.0,
  "tool_type": "cli_tool" | "library" | "platform" | "web_app" | "educational" | "other"
}"""

    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.getenv('ANTHROPIC_API_KEY')
        if not self.api_key:
            raise ValueError("ANTHROPIC_API_KEY required for LLM feasibility checker")

        if not HAS_ANTHROPIC:
            raise ImportError("anthropic package required: pip install anthropic")

        self.client = anthropic.Anthropic(api_key=self.api_key)

    def check(self, tool: Dict) -> Tuple[bool, str, float, str]:
        """
        Check if a tool is feasible using LLM.

        Args:
            tool: Tool metadata dictionary

        Returns:
            Tuple of (feasible, reason, confidence, tool_type)
        """
        # Build the prompt with tool information
        tool_info = self._format_tool_info(tool)

        try:
            response = self.client.messages.create(
                model="claude-sonnet-4-5-20250929",
                max_tokens=500,
                system=self.SYSTEM_PROMPT,
                messages=[
                    {
                        "role": "user",
                        "content": f"Evaluate this tool for Galaxy workflow integration:\n\n{tool_info}"
                    }
                ]
            )

            # Parse response
            result_text = response.content[0].text

            # Extract JSON from response
            try:
                # Try to find JSON in response
                if '{' in result_text:
                    json_start = result_text.index('{')
                    json_end = result_text.rindex('}') + 1
                    result = json.loads(result_text[json_start:json_end])
                else:
                    result = json.loads(result_text)

                return (
                    result.get('suitable', False),
                    result.get('reason', 'Unknown'),
                    result.get('confidence', 0.5),
                    result.get('tool_type', 'unknown')
                )
            except json.JSONDecodeError:
                logger.warning(f"Failed to parse LLM response: {result_text}")
                return False, "Failed to parse LLM response", 0.5, "unknown"

        except Exception as e:
            logger.error(f"LLM check failed: {e}")
            return False, f"LLM error: {str(e)}", 0.0, "error"

    def _format_tool_info(self, tool: Dict) -> str:
        """Format tool information for the LLM prompt."""
        parts = []

        name = tool.get('name', 'Unknown')
        parts.append(f"Name: {name}")

        if tool.get('description'):
            parts.append(f"Description: {tool['description']}")

        if tool.get('language'):
            parts.append(f"Language: {tool['language']}")

        if tool.get('topics'):
            parts.append(f"Topics: {', '.join(tool['topics'])}")

        if tool.get('readme'):
            # Truncate README to first 2000 chars
            readme = tool['readme'][:2000]
            if len(tool['readme']) > 2000:
                readme += "..."
            parts.append(f"\nREADME excerpt:\n{readme}")

        return "\n".join(parts)


class HybridFeasibilityChecker:
    """
    Hybrid checker that uses fast rules first, then LLM for uncertain cases.
    """

    # Quick rejection patterns (definitely not suitable)
    QUICK_REJECT_NAMES = {
        'galaxy', 'nextflow', 'snakemake', 'cromwell', 'airflow',
        'dash', 'flask', 'django', 'streamlit', 'gradio'
    }

    # Quick accept patterns (likely CLI tools)
    CLI_INDICATORS = [
        '--help', '-h', 'usage:', 'command line', 'cli',
        'argparse', 'click', 'typer', 'fire'
    ]

    def __init__(self, api_key: str = None):
        self.api_key = api_key or os.getenv('ANTHROPIC_API_KEY')
        self.llm_checker = None
        if self.api_key and HAS_ANTHROPIC:
            try:
                self.llm_checker = LLMFeasibilityChecker(self.api_key)
            except Exception as e:
                logger.warning(f"LLM checker not available: {e}")

    def check(self, tool: Dict) -> Tuple[bool, str, float, str]:
        """
        Check feasibility using hybrid approach.

        Returns:
            Tuple of (feasible, reason, confidence, tool_type)
        """
        name = tool.get('name', '').lower()
        description = (tool.get('description') or '').lower()
        readme = (tool.get('readme') or '').lower()

        # Quick rejection for known bad patterns
        if name in self.QUICK_REJECT_NAMES:
            return False, f"Known unsuitable tool type: {name}", 0.95, "platform"

        # Quick rejection for platform keywords
        platform_keywords = ['workflow engine', 'workflow management', 'pipeline framework']
        for kw in platform_keywords:
            if kw in description:
                return False, f"Platform indicator: {kw}", 0.90, "platform"

        # Quick rejection for web framework keywords
        web_keywords = ['web app', 'dashboard', 'web interface']
        for kw in web_keywords:
            if kw in description:
                return False, f"Web application: {kw}", 0.90, "web_app"

        # Quick acceptance for strong CLI indicators
        for indicator in self.CLI_INDICATORS:
            if indicator in readme:
                return True, f"Has CLI indicator: {indicator}", 0.85, "cli_tool"

        # Compiled languages usually have CLI
        language = (tool.get('language') or '').lower()
        if language in {'c', 'c++', 'rust', 'go', 'java'}:
            return True, f"Compiled language ({language}) typically has CLI", 0.75, "cli_tool"

        # Use LLM for uncertain cases
        if self.llm_checker:
            logger.info(f"  Using LLM for uncertain case: {tool.get('name')}")
            return self.llm_checker.check(tool)

        # Fallback: reject Python without CLI indicators
        if language == 'python':
            if 'library' in description or 'package' in description:
                return False, "Python library without CLI indicators", 0.70, "library"
            return False, "Python project - uncertain without LLM", 0.50, "unknown"

        # Default: uncertain
        return False, "Unable to determine - no LLM available", 0.40, "unknown"


def main():
    parser = argparse.ArgumentParser(
        description='LLM-based tool feasibility checker'
    )

    parser.add_argument(
        '--tool-json',
        type=Path,
        help='JSON file with tool data'
    )

    parser.add_argument(
        '--api-key',
        help='Anthropic API key (or set ANTHROPIC_API_KEY env var)'
    )

    parser.add_argument(
        '--use-llm',
        action='store_true',
        help='Always use LLM (not hybrid)'
    )

    args = parser.parse_args()

    if args.tool_json:
        with open(args.tool_json) as f:
            tool = json.load(f)

        if args.use_llm:
            checker = LLMFeasibilityChecker(args.api_key)
        else:
            checker = HybridFeasibilityChecker(args.api_key)

        feasible, reason, confidence, tool_type = checker.check(tool)

        status = "✅ SUITABLE" if feasible else "❌ NOT SUITABLE"
        print(f"{status}: {tool.get('name', 'Unknown')}")
        print(f"  Type: {tool_type}")
        print(f"  Reason: {reason}")
        print(f"  Confidence: {confidence:.0%}")
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
