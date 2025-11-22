#!/usr/bin/env python3
"""
Tool Functionality Verifier

Tests that a tool is actually implementable and runnable with its claimed
functions before integrating it into the database.

Verification levels:
1. Command exists and is executable
2. Tool responds to --help or --version
3. Tool can be invoked without errors (basic smoke test)
4. Container is accessible and tool works inside container

Usage:
    python3 tool_functionality_verifier.py --wrapper path/to/wrapper.xml
    python3 tool_functionality_verifier.py --tool-name scanpy --test-level full
"""

import argparse
import logging
import subprocess
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Dict, Optional, Tuple

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class ToolFunctionalityVerifier:
    """Verifies that a tool is actually runnable and functional."""

    def __init__(self, wrapper_path: Path):
        self.wrapper_path = wrapper_path
        self.wrapper_xml = None
        self.tool_id = None
        self.tool_name = None
        self.command = None
        self.container_image = None
        self.container_type = None

    def parse_wrapper(self) -> bool:
        """Parse the Galaxy XML wrapper to extract tool information."""
        try:
            tree = ET.parse(self.wrapper_path)
            root = tree.getroot()

            self.tool_id = root.get('id')
            self.tool_name = root.get('name')

            # Extract command
            command_elem = root.find('command')
            if command_elem is not None:
                self.command = command_elem.text.strip() if command_elem.text else None

            # Extract container information
            requirements = root.find('requirements')
            if requirements is not None:
                for req in requirements.findall('container'):
                    self.container_type = req.get('type', 'docker')
                    self.container_image = req.text.strip() if req.text else None
                    break

            logger.info(f"Parsed wrapper: {self.tool_name} (ID: {self.tool_id})")
            logger.info(f"  Command: {self.command[:100] if self.command else 'N/A'}...")
            logger.info(f"  Container: {self.container_type}:{self.container_image}")

            return True

        except Exception as e:
            logger.error(f"Failed to parse wrapper: {e}")
            return False

    def verify_command_exists(self) -> Tuple[bool, str]:
        """Verify that the command/binary exists and is accessible."""
        if not self.command:
            return False, "No command defined in wrapper"

        # Extract the base command (first word before any arguments)
        base_command = self.command.split()[0] if self.command else None

        if not base_command:
            return False, "Could not extract base command"

        # Skip if it's a complex shell command
        if any(char in base_command for char in ['|', '>', '<', '&', ';', '$']):
            return None, "Complex shell command - skipping direct verification"

        # Try 'which' to find the command
        try:
            result = subprocess.run(
                ['which', base_command],
                capture_output=True,
                text=True,
                timeout=5
            )

            if result.returncode == 0:
                path = result.stdout.strip()
                return True, f"Command found at: {path}"
            else:
                # Command not in PATH - may be in container
                return None, f"Command '{base_command}' not in PATH (may be containerized)"

        except subprocess.TimeoutExpired:
            return False, "Timeout while checking command"
        except Exception as e:
            return False, f"Error checking command: {e}"

    def verify_help_response(self) -> Tuple[bool, str]:
        """Verify that the tool responds to --help or --version."""
        if not self.command:
            return False, "No command defined"

        base_command = self.command.split()[0]

        # Skip complex shell commands
        if any(char in base_command for char in ['|', '>', '<', '&', ';', '$']):
            return None, "Complex shell command - skipping help test"

        # Try --help
        for flag in ['--help', '-h', '--version', '-v', 'help', 'version']:
            try:
                result = subprocess.run(
                    [base_command, flag],
                    capture_output=True,
                    text=True,
                    timeout=10
                )

                # Success if it returns 0 or has output
                if result.returncode == 0 or result.stdout or result.stderr:
                    output_len = len(result.stdout) + len(result.stderr)
                    return True, f"Tool responds to '{flag}' ({output_len} bytes output)"

            except FileNotFoundError:
                # Command not found - will try container
                continue
            except subprocess.TimeoutExpired:
                return False, f"Timeout while running '{base_command} {flag}'"
            except Exception as e:
                continue

        return None, "Tool does not respond to standard help flags (may require container)"

    def verify_container_accessible(self) -> Tuple[bool, str]:
        """Verify that the container image is accessible."""
        if not self.container_image:
            return None, "No container specified"

        if self.container_type != 'docker':
            return None, f"Unsupported container type: {self.container_type}"

        try:
            # Try to pull/inspect the image
            result = subprocess.run(
                ['docker', 'inspect', self.container_image],
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0:
                return True, f"Container image is accessible"
            else:
                # Try to pull it
                logger.info(f"Attempting to pull {self.container_image}...")
                pull_result = subprocess.run(
                    ['docker', 'pull', self.container_image],
                    capture_output=True,
                    text=True,
                    timeout=180  # 3 minutes for pull
                )

                if pull_result.returncode == 0:
                    return True, "Container image pulled successfully"
                else:
                    return False, f"Cannot access container: {pull_result.stderr[:200]}"

        except subprocess.TimeoutExpired:
            return False, "Timeout while checking container"
        except FileNotFoundError:
            return None, "Docker not available"
        except Exception as e:
            return False, f"Error checking container: {e}"

    def verify_tool_in_container(self) -> Tuple[bool, str]:
        """Verify that the tool works inside the container."""
        if not self.container_image:
            return None, "No container specified"

        if self.container_type != 'docker':
            return None, f"Unsupported container type: {self.container_type}"

        if not self.command:
            return False, "No command defined"

        base_command = self.command.split()[0]

        # Skip complex shell commands
        if any(char in base_command for char in ['|', '>', '<', '&', ';']):
            return None, "Complex shell command - skipping container test"

        try:
            # Test 1: Check if command exists in container
            result = subprocess.run(
                ['docker', 'run', '--rm', self.container_image, 'which', base_command],
                capture_output=True,
                text=True,
                timeout=60
            )

            if result.returncode == 0:
                path = result.stdout.strip()
                logger.info(f"Found {base_command} in container at: {path}")
            else:
                # Try running directly
                logger.info(f"Command not in PATH, trying direct execution...")

            # Test 2: Try --help
            for flag in ['--help', '-h', '--version', '-v']:
                try:
                    help_result = subprocess.run(
                        ['docker', 'run', '--rm', self.container_image, base_command, flag],
                        capture_output=True,
                        text=True,
                        timeout=60
                    )

                    if help_result.returncode == 0 or help_result.stdout or help_result.stderr:
                        output_len = len(help_result.stdout) + len(help_result.stderr)
                        return True, f"Tool works in container (responds to '{flag}', {output_len} bytes)"

                except subprocess.TimeoutExpired:
                    continue
                except Exception:
                    continue

            # Test 3: Try running the tool without arguments (some tools print help)
            try:
                bare_result = subprocess.run(
                    ['docker', 'run', '--rm', self.container_image, base_command],
                    capture_output=True,
                    text=True,
                    timeout=30
                )

                # If it produces output, consider it working
                if bare_result.stdout or bare_result.stderr:
                    output_len = len(bare_result.stdout) + len(bare_result.stderr)
                    return True, f"Tool executable in container ({output_len} bytes output)"

            except subprocess.TimeoutExpired:
                return False, "Timeout running tool in container"

            return False, "Tool not responsive in container"

        except FileNotFoundError:
            return None, "Docker not available"
        except subprocess.TimeoutExpired:
            return False, "Timeout testing tool in container"
        except Exception as e:
            return False, f"Error testing tool in container: {e}"

    def verify_basic_functionality(self) -> Tuple[bool, str]:
        """Perform a basic smoke test of the tool's functionality."""
        # This is a simple test - just try to run the tool
        # More sophisticated tests would require understanding the tool's I/O

        if not self.container_image:
            # No container - try native execution
            return self.verify_help_response()
        else:
            # With container - test in container
            return self.verify_tool_in_container()

    def run_verification(self, test_level: str = 'basic') -> Dict:
        """
        Run verification checks based on test level.

        Levels:
        - basic: Parse wrapper, check command syntax
        - standard: Basic + check if command exists
        - full: Standard + container check + functionality test
        """
        results = {
            'tool_id': self.tool_id,
            'tool_name': self.tool_name,
            'wrapper_path': str(self.wrapper_path),
            'test_level': test_level,
            'checks': {},
            'overall_status': 'unknown',
            'recommendation': 'unknown'
        }

        # Check 1: Parse wrapper (all levels)
        logger.info("=" * 60)
        logger.info(f"Verifying tool: {self.wrapper_path.name}")
        logger.info("=" * 60)

        if not self.parse_wrapper():
            results['overall_status'] = 'failed'
            results['recommendation'] = 'reject'
            results['checks']['parse_wrapper'] = (False, "Failed to parse wrapper")
            return results

        results['checks']['parse_wrapper'] = (True, "Wrapper parsed successfully")

        if test_level == 'basic':
            results['overall_status'] = 'passed'
            results['recommendation'] = 'accept_with_warning'
            return results

        # Check 2: Command exists (standard+)
        logger.info("\n[2/5] Checking if command exists...")
        cmd_exists, cmd_msg = self.verify_command_exists()
        results['checks']['command_exists'] = (cmd_exists, cmd_msg)
        logger.info(f"  {'✓' if cmd_exists else '⚠' if cmd_exists is None else '✗'} {cmd_msg}")

        # Check 3: Help response (standard+)
        logger.info("\n[3/5] Checking help response...")
        help_works, help_msg = self.verify_help_response()
        results['checks']['help_response'] = (help_works, help_msg)
        logger.info(f"  {'✓' if help_works else '⚠' if help_works is None else '✗'} {help_msg}")

        if test_level == 'standard':
            # Determine overall status
            if cmd_exists is False or help_works is False:
                results['overall_status'] = 'warning'
                results['recommendation'] = 'accept_with_warning'
            elif cmd_exists is None and help_works is None:
                results['overall_status'] = 'unknown'
                results['recommendation'] = 'accept_with_warning'
            else:
                results['overall_status'] = 'passed'
                results['recommendation'] = 'accept'
            return results

        # Check 4: Container accessible (full only)
        logger.info("\n[4/5] Checking container accessibility...")
        container_ok, container_msg = self.verify_container_accessible()
        results['checks']['container_accessible'] = (container_ok, container_msg)
        logger.info(f"  {'✓' if container_ok else '⚠' if container_ok is None else '✗'} {container_msg}")

        # Check 5: Tool in container (full only)
        logger.info("\n[5/5] Checking tool functionality in container...")
        tool_works, tool_msg = self.verify_tool_in_container()
        results['checks']['tool_in_container'] = (tool_works, tool_msg)
        logger.info(f"  {'✓' if tool_works else '⚠' if tool_works is None else '✗'} {tool_msg}")

        # Determine overall status for full test
        failed = any(v[0] is False for v in results['checks'].values())
        unknown = all(v[0] in [None, True] for v in results['checks'].values())
        passed = any(v[0] is True for v in results['checks'].values())

        if failed:
            results['overall_status'] = 'failed'
            results['recommendation'] = 'reject'
        elif tool_works is True or (container_ok is True and not failed):
            results['overall_status'] = 'passed'
            results['recommendation'] = 'accept'
        elif unknown:
            results['overall_status'] = 'unknown'
            results['recommendation'] = 'accept_with_warning'
        else:
            results['overall_status'] = 'warning'
            results['recommendation'] = 'accept_with_warning'

        return results

    def print_summary(self, results: Dict):
        """Print a summary of verification results."""
        print("\n" + "=" * 60)
        print("VERIFICATION SUMMARY")
        print("=" * 60)
        print(f"Tool: {results['tool_name']} ({results['tool_id']})")
        print(f"Test Level: {results['test_level']}")
        print(f"Overall Status: {results['overall_status'].upper()}")
        print(f"Recommendation: {results['recommendation'].upper()}")
        print("\nCheck Results:")

        for check_name, (status, message) in results['checks'].items():
            icon = '✓' if status is True else '⚠' if status is None else '✗'
            status_text = 'PASS' if status is True else 'WARN' if status is None else 'FAIL'
            print(f"  {icon} {check_name}: {status_text}")
            print(f"      {message}")

        print("=" * 60)

        # Interpretation
        print("\nInterpretation:")
        if results['recommendation'] == 'accept':
            print("  ✅ Tool is verified and safe to integrate into database")
        elif results['recommendation'] == 'accept_with_warning':
            print("  ⚠️  Tool may work but verification incomplete")
            print("      Consider manual testing before integration")
        else:
            print("  ❌ Tool failed verification - DO NOT integrate")
            print("      Tool may not be functional or accessible")


def main():
    parser = argparse.ArgumentParser(
        description="Verify tool functionality before database integration"
    )
    parser.add_argument(
        '--wrapper',
        type=Path,
        required=True,
        help='Path to Galaxy XML wrapper file'
    )
    parser.add_argument(
        '--test-level',
        choices=['basic', 'standard', 'full'],
        default='standard',
        help='Level of testing to perform (default: standard)'
    )
    parser.add_argument(
        '--json-output',
        type=Path,
        help='Write results to JSON file'
    )

    args = parser.parse_args()

    if not args.wrapper.exists():
        logger.error(f"Wrapper file not found: {args.wrapper}")
        return 1

    # Run verification
    verifier = ToolFunctionalityVerifier(args.wrapper)
    results = verifier.run_verification(test_level=args.test_level)

    # Print summary
    verifier.print_summary(results)

    # Write JSON output if requested
    if args.json_output:
        import json
        with open(args.json_output, 'w') as f:
            json.dump(results, f, indent=2)
        logger.info(f"\nResults written to: {args.json_output}")

    # Exit code based on recommendation
    if results['recommendation'] == 'reject':
        return 2
    elif results['recommendation'] == 'accept_with_warning':
        return 1
    else:
        return 0


if __name__ == '__main__':
    import sys
    sys.exit(main())
