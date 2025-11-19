#!/usr/bin/env python3
"""
Feasibility Checker

Checks if a discovered tool is suitable for Galaxy workflow integration
BEFORE spending time on documentation fetching and wrapper generation.

Filters out:
- Web frameworks (dash, flask, django)
- Workflow platforms (galaxy, nextflow, snakemake)
- Pure Python libraries without CLI
- General-purpose tools not specific to bioinformatics

Usage:
    python feasibility_checker.py --tool-json tool_data.json
    python feasibility_checker.py --check-all --discoveries data/discoveries/
"""

import argparse
import json
import logging
import re
from pathlib import Path
from typing import Dict, Tuple, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class FeasibilityChecker:
    """Check if a tool is feasible for Galaxy workflow integration."""

    # Tools that are platforms/frameworks, not workflow tools
    PLATFORM_TOOLS = {
        'galaxy', 'nextflow', 'snakemake', 'cromwell', 'cwltool',
        'airflow', 'luigi', 'prefect', 'dagster', 'argo'
    }

    # Web frameworks - not bioinformatics tools
    WEB_FRAMEWORKS = {
        'dash', 'flask', 'django', 'fastapi', 'streamlit',
        'gradio', 'panel', 'bokeh', 'plotly'
    }

    # General libraries that aren't workflow tools
    GENERAL_LIBRARIES = {
        'numpy', 'scipy', 'pandas', 'matplotlib', 'seaborn',
        'scikit-learn', 'tensorflow', 'pytorch', 'keras'
    }

    # Keywords indicating a platform/framework
    PLATFORM_KEYWORDS = [
        'workflow engine', 'workflow management', 'pipeline framework',
        'workflow dsl', 'workflow platform', 'orchestration'
    ]

    # Keywords indicating a web app/dashboard
    WEB_KEYWORDS = [
        'web app', 'dashboard', 'web interface', 'browser-based',
        'interactive visualization', 'web application'
    ]

    # Keywords indicating a pure library
    LIBRARY_KEYWORDS = [
        'python library', 'python package', 'api for',
        'provides functions', 'module for'
    ]

    # Keywords indicating CLI availability
    CLI_INDICATORS = [
        '--help', '-h', 'usage:', 'command line', 'cli',
        'command-line', 'terminal', 'console', 'arguments',
        'options:', 'flags:', 'subcommands'
    ]

    # Bioinformatics-specific indicators (should have)
    BIO_INDICATORS = [
        'sequence', 'alignment', 'genome', 'protein', 'dna', 'rna',
        'fasta', 'fastq', 'bam', 'sam', 'vcf', 'gff', 'bed',
        'phylogen', 'variant', 'mutation', 'gene', 'transcript',
        'annotation', 'assembly', 'mapping', 'calling'
    ]

    def __init__(self):
        pass

    def check(self, tool: Dict) -> Tuple[bool, str, float]:
        """
        Check if a tool is feasible for workflow integration.

        Args:
            tool: Tool metadata dictionary with keys:
                - name: Tool name
                - description: Tool description
                - readme: README content (optional)
                - language: Programming language
                - topics: GitHub topics (optional)

        Returns:
            Tuple of (feasible, reason, confidence)
            - feasible: True if tool should be processed
            - reason: Explanation of decision
            - confidence: 0.0-1.0 confidence in decision
        """
        name = tool.get('name', '').lower()
        description = (tool.get('description') or '').lower()
        readme = (tool.get('readme') or '').lower()
        language = (tool.get('language') or '').lower()
        topics = [t.lower() for t in tool.get('topics', [])]

        # Check 1: Known platform tools
        if name in self.PLATFORM_TOOLS:
            return False, f"Known workflow platform: {name}", 0.95

        # Check 2: Known web frameworks
        if name in self.WEB_FRAMEWORKS:
            return False, f"Web framework, not bioinformatics tool: {name}", 0.95

        # Check 3: Known general libraries
        if name in self.GENERAL_LIBRARIES:
            return False, f"General-purpose library: {name}", 0.90

        # Check 4: Platform keywords in description
        for keyword in self.PLATFORM_KEYWORDS:
            if keyword in description:
                return False, f"Platform/framework indicator: '{keyword}'", 0.85

        # Check 5: Web app keywords
        for keyword in self.WEB_KEYWORDS:
            if keyword in description:
                return False, f"Web application indicator: '{keyword}'", 0.80

        # Check 6: Library keywords without CLI
        has_library_keyword = any(kw in description for kw in self.LIBRARY_KEYWORDS)
        has_cli_indicator = any(ind in readme for ind in self.CLI_INDICATORS)

        if has_library_keyword and not has_cli_indicator:
            return False, "Python library without CLI interface", 0.75

        # Check 7: Must have some bioinformatics relevance
        has_bio_indicator = (
            any(ind in description for ind in self.BIO_INDICATORS) or
            any(ind in readme[:2000] for ind in self.BIO_INDICATORS) or
            any(any(ind in topic for ind in self.BIO_INDICATORS) for topic in topics)
        )

        if not has_bio_indicator:
            # Check topics for bioinformatics
            bio_topics = {'bioinformatics', 'genomics', 'proteomics', 'computational-biology'}
            if not any(t in bio_topics for t in topics):
                return False, "No bioinformatics indicators found", 0.60

        # Check 8: CLI indicators (positive signal)
        if has_cli_indicator:
            return True, "Has CLI interface indicators", 0.85

        # Check 9: Compiled languages usually have CLI
        compiled_languages = {'c', 'c++', 'rust', 'go', 'java'}
        if language in compiled_languages:
            return True, f"Compiled language ({language}) typically has CLI", 0.70

        # Check 10: Python with entry points check
        if language == 'python':
            # Look for setup.py console_scripts or pyproject.toml scripts
            if 'console_scripts' in readme or 'scripts' in readme:
                return True, "Python with console_scripts entry point", 0.80
            # Look for __main__.py or cli.py patterns
            if '__main__' in readme or 'cli.py' in readme:
                return True, "Python with CLI module", 0.75
            # Default: uncertain for Python
            return True, "Python tool - needs CLI verification", 0.50

        # Default: allow with low confidence
        return True, "No disqualifying factors found", 0.55

    def check_batch(self, tools: List[Dict]) -> Dict[str, List]:
        """
        Check multiple tools and categorize them.

        Returns:
            Dictionary with 'feasible', 'rejected', 'uncertain' lists
        """
        results = {
            'feasible': [],
            'rejected': [],
            'uncertain': []
        }

        for tool in tools:
            feasible, reason, confidence = self.check(tool)

            result = {
                'tool': tool,
                'feasible': feasible,
                'reason': reason,
                'confidence': confidence
            }

            if not feasible:
                results['rejected'].append(result)
            elif confidence >= 0.70:
                results['feasible'].append(result)
            else:
                results['uncertain'].append(result)

        return results


def main():
    parser = argparse.ArgumentParser(
        description='Check tool feasibility for Galaxy integration'
    )

    parser.add_argument(
        '--tool-json',
        type=Path,
        help='JSON file with single tool data'
    )

    parser.add_argument(
        '--discoveries',
        type=Path,
        help='Directory with discovery JSON files'
    )

    parser.add_argument(
        '--output',
        type=Path,
        help='Output file for results'
    )

    args = parser.parse_args()

    checker = FeasibilityChecker()

    if args.tool_json:
        with open(args.tool_json) as f:
            tool = json.load(f)

        feasible, reason, confidence = checker.check(tool)

        status = "✅ FEASIBLE" if feasible else "❌ REJECTED"
        print(f"{status}: {tool.get('name', 'Unknown')}")
        print(f"  Reason: {reason}")
        print(f"  Confidence: {confidence:.0%}")

    elif args.discoveries:
        # Load all discovery files
        all_tools = []
        for json_file in args.discoveries.glob('*.json'):
            with open(json_file) as f:
                tools = json.load(f)
                if isinstance(tools, list):
                    all_tools.extend(tools)
                else:
                    all_tools.append(tools)

        results = checker.check_batch(all_tools)

        print("=" * 60)
        print("FEASIBILITY CHECK RESULTS")
        print("=" * 60)

        print(f"\n✅ Feasible: {len(results['feasible'])}")
        for r in results['feasible']:
            print(f"  • {r['tool'].get('name')}: {r['reason']} ({r['confidence']:.0%})")

        print(f"\n⚠️  Uncertain: {len(results['uncertain'])}")
        for r in results['uncertain']:
            print(f"  • {r['tool'].get('name')}: {r['reason']} ({r['confidence']:.0%})")

        print(f"\n❌ Rejected: {len(results['rejected'])}")
        for r in results['rejected']:
            print(f"  • {r['tool'].get('name')}: {r['reason']} ({r['confidence']:.0%})")

        if args.output:
            with open(args.output, 'w') as f:
                json.dump(results, f, indent=2, default=str)
            print(f"\n✓ Results saved to: {args.output}")

    else:
        parser.print_help()


if __name__ == '__main__':
    main()
