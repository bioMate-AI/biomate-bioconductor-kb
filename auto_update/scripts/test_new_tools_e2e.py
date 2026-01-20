#!/usr/bin/env python3
"""
End-to-End Test Suite for New Tools Integration (2026-01-19)

Tests the complete integration of 10 cutting-edge bioinformatics tools:
1. State (Arc Institute virtual cell model)
2. Chai-1 (multi-modal structure prediction)
3. Boltz-2 (protein-ligand docking)
4. Evo 2 (DNA foundation model)
5. DrugCLIP (virtual screening)
6. scFv_Pmpnn_AF2 (intrabody design)
7. ProTrek (trimodal protein language model)
8. ProFam-1 (protein family language model)
9. SynCraft (synthesizability optimization)
10. AlphaFold 3 (structure prediction)

Tests:
- Database presence and field completeness
- Tool knowledge retrieval
- MCP server configuration validation
- Tool search functionality
- Sources.yaml configuration

Usage:
    python test_new_tools_e2e.py
    python test_new_tools_e2e.py --verbose
    python test_new_tools_e2e.py --tool "Boltz-2"
"""

import argparse
import json
import sqlite3
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import yaml

# Expected tools to test
EXPECTED_TOOLS = [
    {"name": "State", "tool_id": "state", "category": "single-cell"},
    {"name": "Chai-1", "tool_id": "chai-1", "category": "structure-prediction"},
    {"name": "Boltz-2", "tool_id": "boltz-2", "category": "structure-prediction"},
    {"name": "Evo 2", "tool_id": "evo-2", "category": "genomics"},
    {"name": "DrugCLIP", "tool_id": "drugclip", "category": "drug-discovery"},
    {"name": "scFv_Pmpnn_AF2", "tool_id": "scfv-pmpnn-af2", "category": "protein-design"},
    {"name": "ProTrek", "tool_id": "protrek", "category": "protein-analysis"},
    {"name": "ProFam-1", "tool_id": "profam-1", "category": "protein-analysis"},
    {"name": "SynCraft", "tool_id": "syncraft", "category": "drug-discovery"},
    {"name": "AlphaFold 3", "tool_id": "alphafold-3", "category": "structure-prediction"},
]

# Required fields that must be non-empty
REQUIRED_TOOL_FIELDS = [
    "tool_id", "name", "description", "category", "help_text",
    "usage_guide", "examples", "parameters"
]

REQUIRED_KNOWLEDGE_FIELDS = [
    "tool_name", "citations", "use_cases", "limitations", "alternatives",
    "hardware_requirements", "dependencies", "recommended_parameters",
    "help_text", "usage_guide", "benchmark_papers"
]


class TestResult:
    """Stores test results with pass/fail status"""

    def __init__(self, name: str):
        self.name = name
        self.passed = True
        self.messages: List[str] = []
        self.details: Dict = {}

    def fail(self, message: str):
        self.passed = False
        self.messages.append(f"✗ {message}")

    def success(self, message: str):
        self.messages.append(f"✓ {message}")

    def info(self, message: str):
        self.messages.append(f"  {message}")


class NewToolsE2ETester:
    """End-to-end tester for new tools integration"""

    def __init__(self, verbose: bool = False):
        self.verbose = verbose
        self.auto_update_dir = Path(__file__).parent.parent
        self.db_path = self.auto_update_dir.parent / "backend" / "database" / "galaxy_ai_tools.db"
        self.sources_yaml = self.auto_update_dir / "config" / "sources.yaml"
        self.mcp_config = self.auto_update_dir.parent / "Biomni" / "tutorials" / "examples" / "add_mcp_server" / "mcp_config.yaml"

        self.results: List[TestResult] = []

    def run_all_tests(self, tool_filter: Optional[str] = None) -> bool:
        """Run all tests and return overall pass/fail status"""
        print("=" * 80)
        print("NEW TOOLS E2E TEST SUITE")
        print("=" * 80)
        print(f"Database: {self.db_path}")
        print(f"Sources: {self.sources_yaml}")
        print(f"MCP Config: {self.mcp_config}")
        print()

        # Filter tools if requested
        tools_to_test = EXPECTED_TOOLS
        if tool_filter:
            tools_to_test = [t for t in EXPECTED_TOOLS if tool_filter.lower() in t['name'].lower()]
            if not tools_to_test:
                print(f"No tools matching filter: {tool_filter}")
                return False

        # Run test suites
        self.test_database_connectivity()
        self.test_sources_yaml_configuration()
        self.test_mcp_configuration()
        self.test_tools_table(tools_to_test)
        self.test_tool_knowledge_table(tools_to_test)
        self.test_tool_search(tools_to_test)
        self.test_field_completeness(tools_to_test)

        # Print results
        return self.print_summary()

    def test_database_connectivity(self):
        """Test that database is accessible"""
        result = TestResult("Database Connectivity")

        try:
            if not self.db_path.exists():
                result.fail(f"Database file not found: {self.db_path}")
            else:
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()

                # Check tables exist
                cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
                tables = [row[0] for row in cursor.fetchall()]

                if 'tools' in tables:
                    result.success("'tools' table exists")
                else:
                    result.fail("'tools' table not found")

                if 'tool_knowledge' in tables:
                    result.success("'tool_knowledge' table exists")
                else:
                    result.fail("'tool_knowledge' table not found")

                conn.close()

        except Exception as e:
            result.fail(f"Database connection error: {e}")

        self.results.append(result)

    def test_sources_yaml_configuration(self):
        """Test that sources.yaml has all manual repos configured"""
        result = TestResult("Sources YAML Configuration")

        try:
            if not self.sources_yaml.exists():
                result.fail(f"sources.yaml not found: {self.sources_yaml}")
            else:
                with open(self.sources_yaml) as f:
                    config = yaml.safe_load(f)

                manual_repos = config.get('manual_repos', [])
                result.info(f"Found {len(manual_repos)} manual repositories")

                # Check each expected tool
                repo_names = [r.get('name', '').lower() for r in manual_repos]

                for tool in EXPECTED_TOOLS:
                    tool_name = tool['name'].lower()
                    # Check various name formats
                    found = any(
                        tool_name in name or
                        tool_name.replace('-', ' ') in name or
                        tool_name.replace(' ', '-') in name or
                        tool_name.replace('_', '-') in name
                        for name in repo_names
                    )

                    if found:
                        result.success(f"{tool['name']} configured in manual_repos")
                    else:
                        result.fail(f"{tool['name']} NOT found in manual_repos")

        except Exception as e:
            result.fail(f"Error reading sources.yaml: {e}")

        self.results.append(result)

    def test_mcp_configuration(self):
        """Test MCP server configurations"""
        result = TestResult("MCP Server Configuration")

        try:
            if not self.mcp_config.exists():
                result.fail(f"MCP config not found: {self.mcp_config}")
            else:
                with open(self.mcp_config) as f:
                    config = yaml.safe_load(f)

                mcp_servers = config.get('mcp_servers', {})
                result.info(f"Found {len(mcp_servers)} MCP server configurations")

                # Check expected MCP servers (Boltz, Chai-1, AlphaFold)
                expected_mcp = ['boltz', 'chai1', 'alphafold']

                for server_name in expected_mcp:
                    if server_name in mcp_servers:
                        server = mcp_servers[server_name]
                        enabled = server.get('enabled', False)
                        has_command = 'command' in server
                        has_tools = 'tools' in server

                        status = "enabled" if enabled else "disabled"
                        result.success(f"{server_name} MCP server configured ({status})")

                        if has_command:
                            result.info(f"  Command: {' '.join(server['command'][:3])}...")
                        if has_tools:
                            result.info(f"  Tools: {len(server['tools'])} defined")
                    else:
                        result.fail(f"{server_name} MCP server NOT configured")

        except Exception as e:
            result.fail(f"Error reading MCP config: {e}")

        self.results.append(result)

    def test_tools_table(self, tools: List[Dict]):
        """Test that all tools are in the main tools table"""
        result = TestResult("Tools Table Entries")

        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            for tool in tools:
                # Try multiple ID formats
                possible_ids = [
                    tool['tool_id'],
                    tool['tool_id'].replace('-', '_'),
                    tool['name'].lower().replace(' ', '-'),
                    tool['name'].lower().replace(' ', '_'),
                    f"auto_{tool['tool_id']}",
                ]

                found = False
                for tool_id in possible_ids:
                    cursor.execute(
                        "SELECT tool_id, name, category FROM tools WHERE tool_id = ? OR name = ?",
                        (tool_id, tool['name'])
                    )
                    row = cursor.fetchone()
                    if row:
                        found = True
                        result.success(f"{tool['name']} found (id: {row[0]}, category: {row[2]})")
                        break

                if not found:
                    result.fail(f"{tool['name']} NOT found in tools table")

            conn.close()

        except Exception as e:
            result.fail(f"Database query error: {e}")

        self.results.append(result)

    def test_tool_knowledge_table(self, tools: List[Dict]):
        """Test that all tools have knowledge entries"""
        result = TestResult("Tool Knowledge Entries")

        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            for tool in tools:
                cursor.execute(
                    "SELECT tool_name, primary_citation, use_cases, limitations FROM tool_knowledge WHERE tool_name = ?",
                    (tool['name'],)
                )
                row = cursor.fetchone()

                if row:
                    has_citations = row[1] and row[1] not in ('', '[]', 'null', '{}')
                    has_use_cases = row[2] and row[2] not in ('', '[]', 'null')
                    has_limitations = row[3] and row[3] not in ('', '[]', 'null')

                    if has_citations and has_use_cases and has_limitations:
                        result.success(f"{tool['name']} has complete knowledge entry")
                    else:
                        missing = []
                        if not has_citations: missing.append("primary_citation")
                        if not has_use_cases: missing.append("use_cases")
                        if not has_limitations: missing.append("limitations")
                        result.fail(f"{tool['name']} missing: {', '.join(missing)}")
                else:
                    result.fail(f"{tool['name']} NOT found in tool_knowledge table")

            conn.close()

        except Exception as e:
            result.fail(f"Database query error: {e}")

        self.results.append(result)

    def test_tool_search(self, tools: List[Dict]):
        """Test tool search functionality"""
        result = TestResult("Tool Search Functionality")

        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()

            # Test search queries
            search_queries = [
                ("structure prediction", ["Chai-1", "Boltz-2", "AlphaFold 3"]),
                ("protein", ["ProTrek", "ProFam-1", "Chai-1"]),
                ("drug discovery", ["DrugCLIP", "SynCraft"]),
                ("single cell", ["State"]),
                ("genomics", ["Evo 2"]),
            ]

            for query, expected_tools in search_queries:
                cursor.execute("""
                    SELECT name FROM tools
                    WHERE name LIKE ? OR description LIKE ? OR category LIKE ?
                """, (f"%{query}%", f"%{query}%", f"%{query}%"))

                found_names = [row[0] for row in cursor.fetchall()]
                matches = [t for t in expected_tools if t in found_names]

                if len(matches) >= 1:
                    result.success(f"Search '{query}': found {len(matches)}/{len(expected_tools)} expected tools")
                else:
                    result.fail(f"Search '{query}': found {len(matches)}/{len(expected_tools)} expected tools")

            conn.close()

        except Exception as e:
            result.fail(f"Search test error: {e}")

        self.results.append(result)

    def test_field_completeness(self, tools: List[Dict]):
        """Test that all required fields are populated"""
        result = TestResult("Field Completeness")

        try:
            conn = sqlite3.connect(self.db_path)
            conn.row_factory = sqlite3.Row
            cursor = conn.cursor()

            total_fields = 0
            populated_fields = 0

            for tool in tools:
                cursor.execute(
                    "SELECT * FROM tools WHERE name = ?",
                    (tool['name'],)
                )
                row = cursor.fetchone()

                if row:
                    tool_fields = 0
                    tool_populated = 0
                    missing = []

                    for field in REQUIRED_TOOL_FIELDS:
                        if field in row.keys():
                            total_fields += 1
                            tool_fields += 1
                            value = row[field]
                            if value and str(value) not in ('', '[]', '{}', 'null', 'None'):
                                populated_fields += 1
                                tool_populated += 1
                            else:
                                missing.append(field)

                    completeness = (tool_populated / tool_fields * 100) if tool_fields > 0 else 0

                    if completeness >= 100:
                        result.success(f"{tool['name']}: {completeness:.0f}% complete")
                    elif completeness >= 80:
                        result.info(f"{tool['name']}: {completeness:.0f}% complete (missing: {', '.join(missing)})")
                    else:
                        result.fail(f"{tool['name']}: {completeness:.0f}% complete (missing: {', '.join(missing)})")

            overall = (populated_fields / total_fields * 100) if total_fields > 0 else 0
            result.info(f"Overall field completeness: {overall:.1f}% ({populated_fields}/{total_fields})")

            conn.close()

        except Exception as e:
            result.fail(f"Completeness test error: {e}")

        self.results.append(result)

    def print_summary(self) -> bool:
        """Print test summary and return overall status"""
        print()
        print("=" * 80)
        print("TEST RESULTS SUMMARY")
        print("=" * 80)

        all_passed = True

        for result in self.results:
            status = "PASS" if result.passed else "FAIL"
            status_icon = "✓" if result.passed else "✗"
            print(f"\n{status_icon} {result.name}: {status}")

            if self.verbose or not result.passed:
                for msg in result.messages:
                    print(f"  {msg}")

            if not result.passed:
                all_passed = False

        print()
        print("=" * 80)
        passed_count = sum(1 for r in self.results if r.passed)
        total_count = len(self.results)

        if all_passed:
            print(f"✓ ALL TESTS PASSED ({passed_count}/{total_count})")
        else:
            print(f"✗ SOME TESTS FAILED ({passed_count}/{total_count} passed)")
        print("=" * 80)

        return all_passed


def main():
    parser = argparse.ArgumentParser(description="E2E tests for new tools integration")
    parser.add_argument("--verbose", "-v", action="store_true", help="Show detailed output")
    parser.add_argument("--tool", type=str, help="Filter to specific tool by name")
    args = parser.parse_args()

    tester = NewToolsE2ETester(verbose=args.verbose)
    success = tester.run_all_tests(tool_filter=args.tool)

    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
