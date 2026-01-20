#!/usr/bin/env python3
"""
Functional Test: Simulating Biomate Tool Queries

Tests how Biomate would actually query and use the new tools:
1. Tool discovery by capability
2. Knowledge retrieval for guidance
3. Parameter recommendations
4. Usage example retrieval
5. Alternative tool suggestions

Usage:
    python test_biomate_tool_queries.py
"""

import json
import sqlite3
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

# Test scenarios simulating real user queries
TEST_SCENARIOS = [
    {
        "query": "I need to predict protein-ligand binding structure",
        "search_terms": ["structure", "prediction", "ligand", "binding", "docking"],
        "expected_tools": ["Chai-1", "Boltz-2", "AlphaFold 3"],
        "category": "structure-prediction"
    },
    {
        "query": "I want to screen drugs against a target protein",
        "search_terms": ["drug", "screening", "virtual", "docking"],
        "expected_tools": ["DrugCLIP", "Boltz-2"],
        "category": "drug-discovery"
    },
    {
        "query": "I need to predict how cells respond to perturbations",
        "search_terms": ["cell", "perturbation", "response", "single-cell"],
        "expected_tools": ["State"],
        "category": "single-cell"
    },
    {
        "query": "I want to generate DNA sequences",
        "search_terms": ["DNA", "generation", "sequence", "genomics"],
        "expected_tools": ["Evo 2"],
        "category": "genomics"
    },
    {
        "query": "I need to search proteins by function or structure",
        "search_terms": ["protein", "search", "function", "structure"],
        "expected_tools": ["ProTrek"],
        "category": "protein-analysis"
    },
    {
        "query": "I want to design antibodies or intrabodies",
        "search_terms": ["antibody", "intrabody", "design", "scFv"],
        "expected_tools": ["scFv_Pmpnn_AF2"],
        "category": "protein-design"
    },
    {
        "query": "I need to optimize molecules for synthesizability",
        "search_terms": ["synthesis", "synthesizability", "molecule", "optimization"],
        "expected_tools": ["SynCraft"],
        "category": "drug-discovery"
    },
    {
        "query": "I want to predict protein fitness or variant effects",
        "search_terms": ["fitness", "variant", "mutation", "protein"],
        "expected_tools": ["ProFam-1", "ProTrek"],
        "category": "protein-analysis"
    }
]


class BiomateToolQueryTester:
    """Simulates Biomate tool queries"""

    def __init__(self):
        self.db_path = Path(__file__).parent.parent.parent / "backend" / "database" / "galaxy_ai_tools.db"
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row
        self.results = []

    def run_all_tests(self) -> bool:
        """Run all test scenarios"""
        print("=" * 80)
        print("BIOMATE TOOL QUERY FUNCTIONAL TESTS")
        print("=" * 80)
        print(f"Database: {self.db_path}")
        print()

        all_passed = True

        # Test 1: Tool discovery by capability
        print("\n" + "=" * 40)
        print("TEST 1: Tool Discovery by Capability")
        print("=" * 40)
        if not self.test_tool_discovery():
            all_passed = False

        # Test 2: Knowledge retrieval
        print("\n" + "=" * 40)
        print("TEST 2: Knowledge Retrieval for Guidance")
        print("=" * 40)
        if not self.test_knowledge_retrieval():
            all_passed = False

        # Test 3: Parameter recommendations
        print("\n" + "=" * 40)
        print("TEST 3: Parameter Recommendations")
        print("=" * 40)
        if not self.test_parameter_recommendations():
            all_passed = False

        # Test 4: Usage example retrieval
        print("\n" + "=" * 40)
        print("TEST 4: Usage Example Retrieval")
        print("=" * 40)
        if not self.test_usage_examples():
            all_passed = False

        # Test 5: Alternative suggestions
        print("\n" + "=" * 40)
        print("TEST 5: Alternative Tool Suggestions")
        print("=" * 40)
        if not self.test_alternatives():
            all_passed = False

        # Summary
        print("\n" + "=" * 80)
        if all_passed:
            print("✓ ALL FUNCTIONAL TESTS PASSED")
        else:
            print("✗ SOME FUNCTIONAL TESTS FAILED")
        print("=" * 80)

        self.conn.close()
        return all_passed

    def test_tool_discovery(self) -> bool:
        """Test finding tools by capability/search terms"""
        cursor = self.conn.cursor()
        passed = True

        for scenario in TEST_SCENARIOS:
            # Build search query
            conditions = []
            params = []
            for term in scenario['search_terms']:
                conditions.append(
                    "(name LIKE ? OR description LIKE ? OR category LIKE ? OR help_text LIKE ?)"
                )
                params.extend([f"%{term}%"] * 4)

            query = f"""
                SELECT DISTINCT name, category, quality_score
                FROM tools
                WHERE {' OR '.join(conditions)}
                ORDER BY quality_score DESC
            """

            cursor.execute(query, params)
            found_tools = [row['name'] for row in cursor.fetchall()]

            # Check if expected tools are found
            matches = [t for t in scenario['expected_tools'] if t in found_tools]
            success = len(matches) >= 1

            if success:
                print(f"✓ Query: '{scenario['query'][:50]}...'")
                print(f"  Found: {matches}")
            else:
                print(f"✗ Query: '{scenario['query'][:50]}...'")
                print(f"  Expected: {scenario['expected_tools']}, Found: {found_tools[:5]}")
                passed = False

        return passed

    def test_knowledge_retrieval(self) -> bool:
        """Test retrieving tool knowledge for AI guidance"""
        cursor = self.conn.cursor()
        passed = True

        test_tools = ['Chai-1', 'State', 'DrugCLIP', 'Evo 2', 'AlphaFold 3']

        for tool_name in test_tools:
            cursor.execute("""
                SELECT
                    tool_name,
                    primary_citation,
                    use_cases,
                    limitations,
                    alternatives,
                    recommended_parameters
                FROM tool_knowledge
                WHERE tool_name = ?
            """, (tool_name,))

            row = cursor.fetchone()

            if row:
                # Verify knowledge is usable
                has_citation = row['primary_citation'] and len(row['primary_citation']) > 10
                has_use_cases = row['use_cases'] and len(row['use_cases']) > 10
                has_limitations = row['limitations'] and len(row['limitations']) > 10
                has_alternatives = row['alternatives'] and len(row['alternatives']) > 10

                if all([has_citation, has_use_cases, has_limitations, has_alternatives]):
                    # Parse and verify JSON
                    try:
                        citation = json.loads(row['primary_citation'])
                        use_cases = json.loads(row['use_cases'])
                        limitations = json.loads(row['limitations'])

                        print(f"✓ {tool_name}: Knowledge complete")
                        print(f"    Citation: {citation.get('title', 'N/A')[:50]}...")
                        print(f"    Use cases: {len(use_cases)} defined")
                        print(f"    Limitations: {len(limitations)} noted")
                    except json.JSONDecodeError:
                        print(f"✗ {tool_name}: Invalid JSON in knowledge")
                        passed = False
                else:
                    missing = []
                    if not has_citation: missing.append("citation")
                    if not has_use_cases: missing.append("use_cases")
                    if not has_limitations: missing.append("limitations")
                    if not has_alternatives: missing.append("alternatives")
                    print(f"✗ {tool_name}: Missing {', '.join(missing)}")
                    passed = False
            else:
                print(f"✗ {tool_name}: No knowledge entry found")
                passed = False

        return passed

    def test_parameter_recommendations(self) -> bool:
        """Test retrieving parameter recommendations"""
        cursor = self.conn.cursor()
        passed = True

        test_tools = ['Chai-1', 'Boltz-2', 'Evo 2']

        for tool_name in test_tools:
            cursor.execute("""
                SELECT name, parameters
                FROM tools
                WHERE name = ?
            """, (tool_name,))

            row = cursor.fetchone()

            if row and row['parameters']:
                try:
                    params = json.loads(row['parameters'])

                    if isinstance(params, dict):
                        # Count parameters with defaults
                        param_count = sum(
                            len(v) if isinstance(v, dict) else 1
                            for v in params.values()
                        )
                        has_defaults = 'default' in str(params)

                        if param_count > 0 and has_defaults:
                            print(f"✓ {tool_name}: {param_count}+ parameters with defaults")
                        else:
                            print(f"⚠ {tool_name}: Parameters exist but no defaults")
                    elif isinstance(params, list):
                        print(f"✓ {tool_name}: {len(params)} parameters defined")
                    else:
                        print(f"⚠ {tool_name}: Unexpected parameter format")

                except json.JSONDecodeError:
                    print(f"✗ {tool_name}: Invalid JSON in parameters")
                    passed = False
            else:
                print(f"✗ {tool_name}: No parameters found")
                passed = False

        return passed

    def test_usage_examples(self) -> bool:
        """Test retrieving usage examples"""
        cursor = self.conn.cursor()
        passed = True

        test_tools = ['State', 'DrugCLIP', 'ProTrek', 'AlphaFold 3', 'SynCraft']

        for tool_name in test_tools:
            cursor.execute("""
                SELECT name, examples, usage_guide, help_text
                FROM tools
                WHERE name = ?
            """, (tool_name,))

            row = cursor.fetchone()

            if row:
                has_examples = row['examples'] and len(row['examples']) > 50
                has_guide = row['usage_guide'] and len(row['usage_guide']) > 100
                has_help = row['help_text'] and len(row['help_text']) > 50

                if has_examples and has_guide and has_help:
                    # Check for code snippets
                    has_code = '```' in row['examples'] or 'import' in row['examples'] or '#' in row['examples']

                    print(f"✓ {tool_name}:")
                    print(f"    Examples: {len(row['examples'])} chars, code: {has_code}")
                    print(f"    Guide: {len(row['usage_guide'])} chars")
                    print(f"    Help: {len(row['help_text'])} chars")
                else:
                    missing = []
                    if not has_examples: missing.append("examples")
                    if not has_guide: missing.append("usage_guide")
                    if not has_help: missing.append("help_text")
                    print(f"✗ {tool_name}: Missing or short {', '.join(missing)}")
                    passed = False
            else:
                print(f"✗ {tool_name}: Tool not found")
                passed = False

        return passed

    def test_alternatives(self) -> bool:
        """Test retrieving alternative tool suggestions"""
        cursor = self.conn.cursor()
        passed = True

        test_tools = ['Chai-1', 'Boltz-2', 'DrugCLIP', 'State']

        for tool_name in test_tools:
            cursor.execute("""
                SELECT tool_name, alternatives
                FROM tool_knowledge
                WHERE tool_name = ?
            """, (tool_name,))

            row = cursor.fetchone()

            if row and row['alternatives']:
                try:
                    alternatives = json.loads(row['alternatives'])

                    if isinstance(alternatives, list) and len(alternatives) >= 2:
                        print(f"✓ {tool_name}: {len(alternatives)} alternatives")
                        print(f"    -> {', '.join(alternatives[:3])}")
                    else:
                        print(f"⚠ {tool_name}: Only {len(alternatives)} alternatives")

                except json.JSONDecodeError:
                    print(f"✗ {tool_name}: Invalid JSON in alternatives")
                    passed = False
            else:
                print(f"✗ {tool_name}: No alternatives found")
                passed = False

        return passed


def main():
    tester = BiomateToolQueryTester()
    success = tester.run_all_tests()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
