#!/usr/bin/env python3
"""
Wrapper Validator - Validate Galaxy XML tool wrappers

Validates:
- XML syntax and structure
- Required elements present
- Container accessibility
- Parameter definitions
- Command template validity

Usage:
    python validate_wrapper.py --wrapper data/wrappers/tool.xml
    python validate_wrapper.py --directory data/wrappers/
"""

import argparse
import logging
import re
import subprocess
from pathlib import Path
from typing import Dict, List, Tuple
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class ValidationResult:
    """
    Stores validation results.
    """

    def __init__(self):
        self.errors = []
        self.warnings = []
        self.info = []
        self.passed = False

    def add_error(self, message: str):
        """Add validation error"""
        self.errors.append(message)
        logger.error(f"ERROR: {message}")

    def add_warning(self, message: str):
        """Add validation warning"""
        self.warnings.append(message)
        logger.warning(f"WARNING: {message}")

    def add_info(self, message: str):
        """Add validation info"""
        self.info.append(message)
        logger.info(f"INFO: {message}")

    def is_valid(self) -> bool:
        """Check if validation passed"""
        return len(self.errors) == 0

    def summary(self) -> str:
        """Generate summary report"""
        lines = [
            "="*60,
            "Validation Summary",
            "="*60,
            f"Errors: {len(self.errors)}",
            f"Warnings: {len(self.warnings)}",
            f"Status: {'PASS' if self.is_valid() else 'FAIL'}",
            ""
        ]

        if self.errors:
            lines.append("ERRORS:")
            for error in self.errors:
                lines.append(f"  - {error}")
            lines.append("")

        if self.warnings:
            lines.append("WARNINGS:")
            for warning in self.warnings:
                lines.append(f"  - {warning}")
            lines.append("")

        if self.info:
            lines.append("INFO:")
            for info in self.info:
                lines.append(f"  - {info}")

        lines.append("="*60)
        return "\n".join(lines)


class XMLValidator:
    """
    Validates XML syntax and structure.
    """

    def validate(self, wrapper_path: Path) -> ValidationResult:
        """Validate XML file"""
        result = ValidationResult()

        # Check file exists
        if not wrapper_path.exists():
            result.add_error(f"File not found: {wrapper_path}")
            return result

        # Parse XML
        try:
            tree = ET.parse(wrapper_path)
            root = tree.getroot()
            result.add_info("XML syntax valid")
        except ET.ParseError as e:
            result.add_error(f"XML parse error: {e}")
            return result

        # Validate root element
        if root.tag != 'tool':
            result.add_error(f"Root element must be 'tool', got '{root.tag}'")

        # Check required attributes
        required_attrs = ['id', 'name', 'version']
        for attr in required_attrs:
            if attr not in root.attrib:
                result.add_error(f"Missing required attribute: {attr}")
            else:
                result.add_info(f"Found {attr}: {root.attrib[attr]}")

        # Check required child elements
        required_children = ['description', 'command']
        for child in required_children:
            if root.find(child) is None:
                result.add_error(f"Missing required element: {child}")
            else:
                result.add_info(f"Found element: {child}")

        # Validate inputs
        self._validate_inputs(root, result)

        # Validate outputs
        self._validate_outputs(root, result)

        # Validate command
        self._validate_command(root, result)

        return result

    def _validate_inputs(self, root: ET.Element, result: ValidationResult):
        """Validate inputs section"""
        inputs = root.find('inputs')
        if inputs is None:
            result.add_warning("No inputs section found")
            return

        params = inputs.findall('param')
        if not params:
            result.add_warning("No input parameters defined")
            return

        result.add_info(f"Found {len(params)} input parameters")

        for param in params:
            name = param.get('name')
            param_type = param.get('type')

            if not name:
                result.add_error("Input parameter missing 'name' attribute")
            if not param_type:
                result.add_error(f"Parameter '{name}' missing 'type' attribute")

            # Validate type
            valid_types = ['text', 'integer', 'float', 'boolean', 'data', 'select']
            if param_type not in valid_types:
                result.add_warning(
                    f"Parameter '{name}' has unusual type: {param_type}"
                )

    def _validate_outputs(self, root: ET.Element, result: ValidationResult):
        """Validate outputs section"""
        outputs = root.find('outputs')
        if outputs is None:
            result.add_warning("No outputs section found")
            return

        data_outputs = outputs.findall('data')
        if not data_outputs:
            result.add_warning("No output files defined")
            return

        result.add_info(f"Found {len(data_outputs)} output files")

        for data in data_outputs:
            name = data.get('name')
            fmt = data.get('format')

            if not name:
                result.add_error("Output missing 'name' attribute")
            if not fmt:
                result.add_warning(f"Output '{name}' missing 'format' attribute")

    def _validate_command(self, root: ET.Element, result: ValidationResult):
        """Validate command section"""
        command = root.find('command')
        if command is None:
            result.add_error("No command section found")
            return

        cmd_text = command.text
        if not cmd_text or not cmd_text.strip():
            result.add_error("Command section is empty")
            return

        # Check for CDATA
        if '<![CDATA[' not in ET.tostring(command, encoding='unicode'):
            result.add_warning("Command not wrapped in CDATA")

        result.add_info("Command section present")


class ContainerValidator:
    """
    Validates container accessibility.
    """

    def validate(self, wrapper_path: Path) -> ValidationResult:
        """Validate container requirements"""
        result = ValidationResult()

        try:
            tree = ET.parse(wrapper_path)
            root = tree.getroot()
        except ET.ParseError:
            result.add_error("Cannot parse XML for container validation")
            return result

        # Find requirements
        requirements = root.find('requirements')
        if requirements is None:
            result.add_warning("No requirements/container section found")
            return result

        # Find container
        container = requirements.find('container')
        if container is None:
            result.add_warning("No container specified in requirements")
            return result

        container_type = container.get('type')
        container_image = container.text

        result.add_info(f"Container type: {container_type}")
        result.add_info(f"Container image: {container_image}")

        # Validate container type
        if container_type not in ['docker', 'singularity']:
            result.add_error(f"Invalid container type: {container_type}")
            return result

        # Check if container is accessible
        if container_type == 'docker':
            accessible = self._check_docker_image(container_image)
            if accessible:
                result.add_info("Docker image is accessible")
            else:
                result.add_warning(
                    f"Docker image may not be accessible: {container_image}"
                )

        return result

    def _check_docker_image(self, image: str) -> bool:
        """
        Check if Docker image exists.

        Note: This requires Docker installed and running.
        """
        try:
            # Check if docker is available
            subprocess.run(
                ['docker', '--version'],
                capture_output=True,
                check=True,
                timeout=5
            )

            # Try to inspect the image (doesn't pull if not present)
            result = subprocess.run(
                ['docker', 'image', 'inspect', image],
                capture_output=True,
                timeout=10
            )

            return result.returncode == 0

        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
            # Docker not available or image not found
            return False


class ParameterValidator:
    """
    Validates parameter consistency between command and inputs.
    """

    def validate(self, wrapper_path: Path) -> ValidationResult:
        """Validate parameter usage"""
        result = ValidationResult()

        try:
            tree = ET.parse(wrapper_path)
            root = tree.getroot()
        except ET.ParseError:
            result.add_error("Cannot parse XML for parameter validation")
            return result

        # Extract parameters from inputs
        inputs = root.find('inputs')
        if inputs is None:
            return result

        input_params = set()
        for param in inputs.findall('param'):
            name = param.get('name')
            if name:
                input_params.add(name)

        result.add_info(f"Defined input parameters: {len(input_params)}")

        # Extract parameters from command
        command = root.find('command')
        if command is None:
            return result

        cmd_text = command.text or ''

        # Find variable references in command
        used_params = set(re.findall(r'\$\{?(\w+)\}?', cmd_text))
        result.add_info(f"Parameters used in command: {len(used_params)}")

        # Check for undefined parameters
        undefined = used_params - input_params
        if undefined:
            for param in undefined:
                result.add_warning(
                    f"Parameter '${param}' used in command but not defined in inputs"
                )

        # Check for unused parameters
        unused = input_params - used_params
        if unused:
            for param in unused:
                result.add_warning(
                    f"Parameter '{param}' defined but not used in command"
                )

        return result


class WrapperValidator:
    """
    Main wrapper validator coordinating all validation checks.
    """

    def __init__(self):
        self.xml_validator = XMLValidator()
        self.container_validator = ContainerValidator()
        self.parameter_validator = ParameterValidator()

    def validate(self, wrapper_path: Path) -> ValidationResult:
        """
        Run all validation checks on wrapper.
        """
        logger.info(f"Validating wrapper: {wrapper_path}")

        # Combined result
        result = ValidationResult()

        # Run XML validation
        xml_result = self.xml_validator.validate(wrapper_path)
        result.errors.extend(xml_result.errors)
        result.warnings.extend(xml_result.warnings)
        result.info.extend(xml_result.info)

        # Only continue if XML is valid
        if not xml_result.is_valid():
            return result

        # Run container validation
        container_result = self.container_validator.validate(wrapper_path)
        result.errors.extend(container_result.errors)
        result.warnings.extend(container_result.warnings)
        result.info.extend(container_result.info)

        # Run parameter validation
        param_result = self.parameter_validator.validate(wrapper_path)
        result.errors.extend(param_result.errors)
        result.warnings.extend(param_result.warnings)
        result.info.extend(param_result.info)

        return result


def main():
    parser = argparse.ArgumentParser(
        description='Validate Galaxy tool wrappers'
    )
    parser.add_argument(
        '--wrapper',
        type=str,
        help='Path to wrapper XML file'
    )
    parser.add_argument(
        '--directory',
        type=str,
        help='Directory containing wrapper XML files'
    )
    parser.add_argument(
        '--strict',
        action='store_true',
        help='Treat warnings as errors'
    )

    args = parser.parse_args()

    if not args.wrapper and not args.directory:
        logger.error("Either --wrapper or --directory required")
        return 1

    validator = WrapperValidator()

    # Collect wrappers to validate
    wrappers = []
    if args.wrapper:
        wrappers.append(Path(args.wrapper))
    elif args.directory:
        directory = Path(args.directory)
        wrappers = list(directory.glob('*.xml'))

    if not wrappers:
        logger.error("No wrappers found to validate")
        return 1

    # Validate all wrappers
    all_passed = True
    for wrapper in wrappers:
        result = validator.validate(wrapper)

        print(f"\n{result.summary()}")

        # Check if passed
        if not result.is_valid():
            all_passed = False
        elif args.strict and result.warnings:
            all_passed = False
            logger.error("Validation failed in strict mode (warnings present)")

    # Summary
    print(f"\n{'='*60}")
    print(f"Validated {len(wrappers)} wrapper(s)")
    print(f"Status: {'PASS' if all_passed else 'FAIL'}")
    print(f"{'='*60}")

    return 0 if all_passed else 1


if __name__ == '__main__':
    exit(main())
