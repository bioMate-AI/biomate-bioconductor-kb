#!/usr/bin/env python3
"""
Parameter Extractor - Extract structured parameters from tool help text

Extracts parameters from:
1. Tool --help output (run in Docker container)
2. README documentation
3. Man pages
4. Using Claude API for intelligent parsing

This is the HIGHEST PRIORITY enhancement (35% of quality score)

Usage:
    # Extract from Docker help
    python parameter_extractor.py --tool-id auto_foldseek

    # Batch process all tools with missing parameters
    python parameter_extractor.py --all-missing-params

    # Update database with extracted parameters
    python parameter_extractor.py --tool-id auto_foldseek --update-db
"""

import argparse
import json
import logging
import os
import re
import sqlite3
import subprocess
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import anthropic

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ParameterExtractor:
    """
    Extracts structured parameter information from tool help text.
    """

    def __init__(self, db_path: Path, anthropic_api_key: str = None):
        self.db_path = db_path
        self.conn = None
        self.anthropic_api_key = anthropic_api_key or os.getenv('ANTHROPIC_API_KEY')

        if self.anthropic_api_key:
            self.client = anthropic.Anthropic(api_key=self.anthropic_api_key)
        else:
            self.client = None
            logger.warning("No Anthropic API key - LLM-based parsing disabled")

    def connect(self):
        """Connect to database"""
        self.conn = sqlite3.connect(self.db_path)
        self.conn.row_factory = sqlite3.Row

    def disconnect(self):
        """Disconnect from database"""
        if self.conn:
            self.conn.close()

    def get_tool(self, tool_id: str) -> Optional[Dict]:
        """Get tool metadata"""
        cursor = self.conn.execute(
            "SELECT * FROM tools WHERE tool_id = ?",
            (tool_id,)
        )
        row = cursor.fetchone()
        return dict(row) if row else None

    def get_help_text_from_docker(self, docker_image: str, help_command: str = "--help") -> Optional[str]:
        """
        Run tool in Docker container to get help text.
        """
        try:
            # Try to run help command
            cmd = ["docker", "run", "--rm", docker_image, help_command]
            logger.info(f"Running: {' '.join(cmd)}")

            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=30
            )

            # Some tools output to stderr instead of stdout
            help_text = result.stdout or result.stderr

            if help_text and len(help_text) > 100:
                return help_text

            # Try alternative help commands
            for alt_cmd in ["-h", "-help", "help", "--usage"]:
                cmd = ["docker", "run", "--rm", docker_image, alt_cmd]
                result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
                help_text = result.stdout or result.stderr

                if help_text and len(help_text) > 100:
                    return help_text

            return None

        except subprocess.TimeoutExpired:
            logger.error(f"Timeout running Docker help for {docker_image}")
            return None
        except Exception as e:
            logger.error(f"Error running Docker help: {e}")
            return None

    def extract_docker_image(self, tool: Dict) -> Optional[str]:
        """Extract Docker image from requirements field."""
        requirements_str = tool.get('requirements', '[]')
        try:
            requirements = json.loads(requirements_str) if requirements_str else []
            for req in requirements:
                if req.get('type') == 'docker':
                    return req.get('name')
        except:
            pass
        return None

    def parse_help_with_regex(self, help_text: str) -> List[Dict]:
        """
        Parse help text with regex patterns (fast but less accurate).
        """
        parameters = []

        # Common help text patterns
        patterns = [
            # Pattern 1: --flag <type> description
            r'^\s*(--[\w-]+)\s+<([\w\[\]]+)>\s+(.+)$',
            # Pattern 2: -f, --flag <type> description
            r'^\s*-(\w),\s*(--[\w-]+)\s+<([\w\[\]]+)>\s+(.+)$',
            # Pattern 3: --flag description (default: value)
            r'^\s*(--[\w-]+)\s+(.+?)\s+\(default:\s*(.+?)\)$',
            # Pattern 4: --flag [type] description
            r'^\s*(--[\w-]+)\s+\[([\w\[\]]+)\]\s+(.+)$',
        ]

        for line in help_text.split('\n'):
            line = line.strip()
            if not line or line.startswith('#'):
                continue

            for pattern in patterns:
                match = re.match(pattern, line, re.IGNORECASE)
                if match:
                    groups = match.groups()

                    if len(groups) == 3:
                        # --flag <type> description
                        flag, param_type, description = groups
                        param = {
                            'name': flag.lstrip('-').replace('-', '_'),
                            'flag': flag,
                            'type': self._normalize_type(param_type),
                            'label': self._make_label(flag),
                            'help': description.strip(),
                            'optional': True,
                            'source': 'regex_extraction'
                        }
                        parameters.append(param)

                    elif len(groups) == 4:
                        # -f, --flag <type> description or --flag description (default: value)
                        if groups[0].startswith('-') and len(groups[0]) == 2:
                            # -f, --flag pattern
                            short, flag, param_type, description = groups
                            param = {
                                'name': flag.lstrip('-').replace('-', '_'),
                                'flag': flag,
                                'short_flag': f"-{short}",
                                'type': self._normalize_type(param_type),
                                'label': self._make_label(flag),
                                'help': description.strip(),
                                'optional': True,
                                'source': 'regex_extraction'
                            }
                        else:
                            # --flag description (default: value)
                            flag, description, default_value = groups
                            param = {
                                'name': flag.lstrip('-').replace('-', '_'),
                                'flag': flag,
                                'type': self._infer_type_from_default(default_value),
                                'label': self._make_label(flag),
                                'help': description.strip(),
                                'default': self._parse_default_value(default_value),
                                'optional': True,
                                'source': 'regex_extraction'
                            }
                        parameters.append(param)

        return parameters

    def parse_help_with_llm(self, help_text: str, tool_name: str) -> List[Dict]:
        """
        Parse help text using Claude API for better accuracy.
        """
        if not self.client:
            logger.warning("LLM parsing not available (no API key)")
            return []

        prompt = f"""Parse the command-line help text for the tool '{tool_name}' and extract all parameters.

For each parameter, provide:
- name: parameter name (alphanumeric, underscores)
- flag: command-line flag (e.g., --threads, -t)
- type: parameter type (boolean, integer, float, string, select)
- label: human-readable label
- help: description text
- default: default value (if mentioned)
- required: true if required, false if optional
- options: array of valid values (for select type)
- min/max: constraints (for numeric types)

Return ONLY valid JSON array with no markdown formatting.

Help text:
{help_text[:3000]}

JSON output:"""

        try:
            response = self.client.messages.create(
                model="claude-3-5-haiku-20241022",
                max_tokens=4096,
                messages=[
                    {"role": "user", "content": prompt}
                ]
            )

            response_text = response.content[0].text.strip()

            # Remove markdown code blocks if present
            if response_text.startswith('```'):
                response_text = re.sub(r'^```(?:json)?\s*', '', response_text)
                response_text = re.sub(r'\s*```$', '', response_text)

            parameters = json.loads(response_text)

            # Add source tag
            for param in parameters:
                param['source'] = 'llm_extraction'
                # Ensure required fields
                if 'optional' not in param:
                    param['optional'] = not param.get('required', False)

            logger.info(f"LLM extracted {len(parameters)} parameters")
            return parameters

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse LLM response as JSON: {e}")
            logger.error(f"Response: {response_text[:500]}")
            return []
        except Exception as e:
            logger.error(f"LLM parsing error: {e}")
            return []

    def extract_parameters(self, tool: Dict, method: str = 'hybrid') -> Dict:
        """
        Extract parameters using specified method.

        Args:
            tool: Tool metadata dict
            method: 'regex', 'llm', or 'hybrid' (default)

        Returns:
            Extraction result with parameters and metadata
        """
        result = {
            'tool_id': tool['tool_id'],
            'tool_name': tool['name'],
            'extracted_at': datetime.now().isoformat(),
            'method': method,
            'parameters': [],
            'help_text_source': None,
            'success': False,
            'error': None
        }

        # Get Docker image
        docker_image = self.extract_docker_image(tool)
        if not docker_image:
            result['error'] = "No Docker image in requirements"
            logger.warning(f"{tool['tool_id']}: {result['error']}")
            return result

        # Get help text
        logger.info(f"Extracting help text from Docker: {docker_image}")
        help_text = self.get_help_text_from_docker(docker_image)

        if not help_text:
            result['error'] = "Could not get help text from Docker"
            logger.warning(f"{tool['tool_id']}: {result['error']}")
            return result

        result['help_text_source'] = 'docker'
        result['help_text_length'] = len(help_text)

        # Extract parameters
        if method == 'regex':
            parameters = self.parse_help_with_regex(help_text)
        elif method == 'llm':
            parameters = self.parse_help_with_llm(help_text, tool['name'])
        else:  # hybrid
            # Try LLM first (more accurate), fall back to regex
            parameters = self.parse_help_with_llm(help_text, tool['name'])
            if not parameters:
                logger.info("LLM extraction failed, falling back to regex")
                parameters = self.parse_help_with_regex(help_text)

        # Remove duplicates (by name)
        seen_names = set()
        unique_params = []
        for param in parameters:
            if param['name'] not in seen_names:
                seen_names.add(param['name'])
                unique_params.append(param)

        result['parameters'] = unique_params
        result['parameters_count'] = len(unique_params)
        result['success'] = len(unique_params) > 0

        if result['success']:
            logger.info(f"✅ Extracted {len(unique_params)} parameters for {tool['tool_id']}")
        else:
            logger.warning(f"❌ No parameters extracted for {tool['tool_id']}")

        return result

    def update_tool_parameters(self, tool_id: str, parameters: List[Dict]) -> bool:
        """Update tool parameters in database."""
        try:
            parameters_json = json.dumps(parameters)

            self.conn.execute(
                """UPDATE tools
                   SET parameters = ?,
                       updated_at = ?
                   WHERE tool_id = ?""",
                (parameters_json, datetime.now().isoformat(), tool_id)
            )
            self.conn.commit()

            logger.info(f"✅ Updated {tool_id} with {len(parameters)} parameters")
            return True

        except Exception as e:
            logger.error(f"Failed to update database: {e}")
            return False

    def _normalize_type(self, type_str: str) -> str:
        """Normalize parameter type string."""
        type_str = type_str.lower().strip()

        # Map common variations
        type_map = {
            'int': 'integer',
            'num': 'integer',
            'number': 'integer',
            'bool': 'boolean',
            'flag': 'boolean',
            'str': 'string',
            'text': 'string',
            'file': 'data',
            'path': 'data',
            'float': 'float',
            'double': 'float'
        }

        for pattern, normalized in type_map.items():
            if pattern in type_str:
                return normalized

        return 'string'  # Default

    def _infer_type_from_default(self, default_value: str) -> str:
        """Infer parameter type from default value."""
        default_value = default_value.strip().lower()

        if default_value in ['true', 'false']:
            return 'boolean'

        try:
            int(default_value)
            return 'integer'
        except:
            pass

        try:
            float(default_value)
            return 'float'
        except:
            pass

        return 'string'

    def _parse_default_value(self, default_str: str):
        """Parse default value string to appropriate type."""
        default_str = default_str.strip()

        if default_str.lower() == 'true':
            return True
        elif default_str.lower() == 'false':
            return False

        try:
            return int(default_str)
        except:
            pass

        try:
            return float(default_str)
        except:
            pass

        return default_str

    def _make_label(self, flag: str) -> str:
        """Make human-readable label from flag."""
        name = flag.lstrip('-').replace('-', ' ').replace('_', ' ')
        return name.title()


def main():
    parser = argparse.ArgumentParser(
        description='Extract structured parameters from tool help text'
    )

    parser.add_argument(
        '--tool-id',
        help='Specific tool ID to process'
    )

    parser.add_argument(
        '--all-missing-params',
        action='store_true',
        help='Process all tools with empty or dummy parameters'
    )

    parser.add_argument(
        '--db-path',
        type=Path,
        default=Path('/home/yzhang/biomate/backend/database/galaxy_ai_tools.db'),
        help='Path to database'
    )

    parser.add_argument(
        '--anthropic-api-key',
        default=os.getenv('ANTHROPIC_API_KEY'),
        help='Anthropic API key for LLM parsing'
    )

    parser.add_argument(
        '--method',
        choices=['regex', 'llm', 'hybrid'],
        default='hybrid',
        help='Extraction method'
    )

    parser.add_argument(
        '--update-db',
        action='store_true',
        help='Update database with extracted parameters'
    )

    parser.add_argument(
        '--output',
        type=Path,
        help='Save extraction results to JSON file'
    )

    args = parser.parse_args()

    extractor = ParameterExtractor(args.db_path, args.anthropic_api_key)
    extractor.connect()

    try:
        results = []

        if args.tool_id:
            # Process single tool
            tool = extractor.get_tool(args.tool_id)
            if not tool:
                logger.error(f"Tool not found: {args.tool_id}")
                return 1

            result = extractor.extract_parameters(tool, method=args.method)
            results.append(result)

            # Print results
            print("="*80)
            print(f"PARAMETER EXTRACTION: {result['tool_name']} ({result['tool_id']})")
            print("="*80)
            print(f"Method: {result['method']}")
            print(f"Success: {result['success']}")
            print(f"Parameters extracted: {result.get('parameters_count', 0)}")

            if result['success']:
                print(f"\n📋 Extracted Parameters:")
                for param in result['parameters'][:10]:  # Show first 10
                    print(f"  • {param['name']:20s} ({param['type']:10s}) - {param.get('help', '')[:50]}")

                if len(result['parameters']) > 10:
                    print(f"  ... and {len(result['parameters']) - 10} more")

                # Update database if requested
                if args.update_db:
                    success = extractor.update_tool_parameters(
                        result['tool_id'],
                        result['parameters']
                    )
                    if success:
                        print(f"\n✅ Database updated with {len(result['parameters'])} parameters")
            else:
                print(f"\n❌ Extraction failed: {result.get('error', 'Unknown error')}")

        elif args.all_missing_params:
            # Process all tools with missing/dummy parameters
            cursor = extractor.conn.execute("""
                SELECT * FROM tools
                WHERE auto_discovered = 1
                AND (parameters IS NULL OR parameters = '[]' OR parameters LIKE '%Parameter for%')
            """)
            tools = [dict(row) for row in cursor.fetchall()]

            print(f"Processing {len(tools)} tools with missing/dummy parameters...")
            print("="*80)

            for i, tool in enumerate(tools, 1):
                print(f"\n[{i}/{len(tools)}] Processing: {tool['tool_id']}")

                result = extractor.extract_parameters(tool, method=args.method)
                results.append(result)

                if result['success']:
                    print(f"  ✅ Extracted {result['parameters_count']} parameters")

                    if args.update_db:
                        extractor.update_tool_parameters(
                            result['tool_id'],
                            result['parameters']
                        )
                else:
                    print(f"  ❌ Failed: {result.get('error', 'Unknown')}")

            # Summary
            print("\n" + "="*80)
            print("SUMMARY")
            print("="*80)
            successful = [r for r in results if r['success']]
            failed = [r for r in results if not r['success']]

            print(f"Total tools: {len(results)}")
            print(f"✅ Successful: {len(successful)}")
            print(f"❌ Failed: {len(failed)}")

            if successful:
                total_params = sum(r['parameters_count'] for r in successful)
                avg_params = total_params / len(successful)
                print(f"📊 Total parameters extracted: {total_params}")
                print(f"📊 Average per tool: {avg_params:.1f}")

        else:
            parser.print_help()
            return 1

        # Save results if requested
        if args.output:
            with open(args.output, 'w') as f:
                json.dump(results, f, indent=2)
            print(f"\n✅ Results saved to: {args.output}")

        return 0

    finally:
        extractor.disconnect()


if __name__ == '__main__':
    exit(main())
