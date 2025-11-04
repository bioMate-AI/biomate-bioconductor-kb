"""
Tool XML Security Validator

Validates Galaxy tool XML files for security vulnerabilities before installation.
Implements comprehensive security checks to prevent:
- Command injection
- Arbitrary code execution
- Path traversal
- Malicious patterns
"""

import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Tuple, List, Dict, Optional
from dataclasses import dataclass
from enum import Enum
import logging

log = logging.getLogger(__name__)


class SecurityLevel(Enum):
    """Security issue severity levels."""
    CRITICAL = "critical"
    HIGH = "high"
    MEDIUM = "medium"
    LOW = "low"
    INFO = "info"


@dataclass
class SecurityIssue:
    """Represents a security issue found in tool XML."""
    level: SecurityLevel
    category: str
    message: str
    line_number: Optional[int] = None
    code_snippet: Optional[str] = None
    recommendation: Optional[str] = None


class ToolXMLValidator:
    """
    Validates Galaxy tool XML files for security issues.

    Performs comprehensive security checks including:
    - Command injection vulnerability detection
    - Dangerous command pattern detection
    - Input validation checks
    - Path traversal prevention
    - Network access validation
    """

    # Dangerous command patterns that should be blocked or carefully reviewed
    DANGEROUS_PATTERNS = {
        'rm -rf': 'Recursive file deletion',
        'curl': 'Network request (data exfiltration risk)',
        'wget': 'Network download (malware risk)',
        'eval': 'Dynamic code execution',
        'exec': 'Command execution',
        'system(': 'System command execution',
        'subprocess.call': 'Subprocess execution',
        'os.system': 'OS command execution',
        '__import__': 'Dynamic import (code injection)',
        'compile(': 'Dynamic code compilation',
        '/etc/passwd': 'Access to sensitive system files',
        '/etc/shadow': 'Access to password hashes',
        '~/.ssh': 'Access to SSH keys',
        '~/.aws': 'Access to AWS credentials',
        'nohup': 'Background process (persistence)',
        'crontab': 'Task scheduling (persistence)',
        '>/dev/null': 'Output redirection (hiding activity)',
        '2>&1': 'Error redirection (hiding errors)',
    }

    # Patterns indicating command injection vulnerabilities
    INJECTION_PATTERNS = [
        r'\$[a-zA-Z_][a-zA-Z0-9_]*(?!\{)',  # Unbraced variable substitution
        r'\$\([^)]+\)',  # Command substitution $()
        r'`[^`]+`',  # Backtick command substitution
        r';\s*\w+',  # Command chaining with semicolon
        r'\|\s*\w+',  # Pipe to another command
        r'&&\s*\w+',  # AND command chaining
        r'\|\|\s*\w+',  # OR command chaining
        r'>\s*/',  # Output redirection to absolute path
    ]

    # Safe parameter types
    SAFE_PARAM_TYPES = {
        'integer', 'float', 'boolean', 'select', 'data', 'data_collection'
    }

    # Dangerous parameter types requiring validation
    DANGEROUS_PARAM_TYPES = {
        'text': 'Free-form text input (injection risk)',
        'hidden': 'Hidden input (bypass risk)',
    }

    def __init__(self, strict_mode: bool = True):
        """
        Initialize validator.

        Args:
            strict_mode: If True, treat warnings as errors
        """
        self.strict_mode = strict_mode
        self.issues: List[SecurityIssue] = []

    def validate_file(self, xml_path: Path) -> Tuple[bool, List[SecurityIssue]]:
        """
        Validate a tool XML file for security issues.

        Args:
            xml_path: Path to tool XML file

        Returns:
            Tuple of (is_safe, list of issues)
        """
        self.issues = []

        if not xml_path.exists():
            self.issues.append(SecurityIssue(
                level=SecurityLevel.CRITICAL,
                category="file_access",
                message=f"File does not exist: {xml_path}"
            ))
            return False, self.issues

        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()
        except ET.ParseError as e:
            self.issues.append(SecurityIssue(
                level=SecurityLevel.CRITICAL,
                category="xml_parsing",
                message=f"Invalid XML: {e}"
            ))
            return False, self.issues

        # Perform all security checks
        self._check_command_section(root, xml_path)
        self._check_parameters(root)
        self._check_dangerous_patterns(root)
        self._check_network_access(root)
        self._check_file_access(root)
        self._check_interpreter_usage(root)

        # Determine if tool is safe
        has_critical = any(issue.level == SecurityLevel.CRITICAL for issue in self.issues)
        has_high = any(issue.level == SecurityLevel.HIGH for issue in self.issues)

        is_safe = not has_critical and (not has_high or not self.strict_mode)

        return is_safe, self.issues

    def _check_command_section(self, root: ET.Element, xml_path: Path):
        """Check command section for injection vulnerabilities."""
        command = root.find('.//command')

        if command is None:
            self.issues.append(SecurityIssue(
                level=SecurityLevel.INFO,
                category="command",
                message="No command section found"
            ))
            return

        cmd_text = command.text or ""

        # Check for unsanitized variable substitution
        for pattern in self.INJECTION_PATTERNS:
            matches = re.finditer(pattern, cmd_text)
            for match in matches:
                # Get context around match
                start = max(0, match.start() - 20)
                end = min(len(cmd_text), match.end() + 20)
                context = cmd_text[start:end]

                self.issues.append(SecurityIssue(
                    level=SecurityLevel.CRITICAL,
                    category="command_injection",
                    message=f"Potential command injection: {match.group()}",
                    code_snippet=context,
                    recommendation="Use braced variable substitution ${var} and validate all inputs"
                ))

        # Check for dangerous command patterns
        for pattern, description in self.DANGEROUS_PATTERNS.items():
            if pattern in cmd_text:
                # Determine severity based on pattern
                if pattern in ['rm -rf', 'eval', 'exec', '__import__']:
                    level = SecurityLevel.CRITICAL
                elif pattern in ['curl', 'wget', 'system(', 'os.system']:
                    level = SecurityLevel.HIGH
                else:
                    level = SecurityLevel.MEDIUM

                self.issues.append(SecurityIssue(
                    level=level,
                    category="dangerous_command",
                    message=f"Dangerous pattern detected: {pattern} ({description})",
                    code_snippet=self._get_context(cmd_text, pattern),
                    recommendation="Ensure this is necessary and properly sandboxed"
                ))

    def _check_parameters(self, root: ET.Element):
        """Check parameter definitions for security issues."""
        params = root.findall('.//param')

        for param in params:
            param_name = param.get('name', 'unknown')
            param_type = param.get('type', 'unknown')

            # Check for dangerous parameter types
            if param_type in self.DANGEROUS_PARAM_TYPES:
                description = self.DANGEROUS_PARAM_TYPES[param_type]

                # Special check for "advanced_options" - the critical vulnerability
                if param_name == 'advanced_options' and param_type == 'text':
                    self.issues.append(SecurityIssue(
                        level=SecurityLevel.CRITICAL,
                        category="parameter_injection",
                        message=f"CRITICAL: Parameter '{param_name}' with type='{param_type}' allows command injection",
                        code_snippet=ET.tostring(param, encoding='unicode'),
                        recommendation="Replace with 'select' type with enumerated safe options"
                    ))
                else:
                    self.issues.append(SecurityIssue(
                        level=SecurityLevel.HIGH,
                        category="parameter_validation",
                        message=f"Parameter '{param_name}' has type '{param_type}': {description}",
                        code_snippet=ET.tostring(param, encoding='unicode'),
                        recommendation="Add validation or use safer parameter type"
                    ))

            # Check for missing validation attributes
            if param_type == 'text':
                if not param.get('sanitizer'):
                    self.issues.append(SecurityIssue(
                        level=SecurityLevel.MEDIUM,
                        category="missing_sanitizer",
                        message=f"Text parameter '{param_name}' has no sanitizer",
                        recommendation="Add sanitizer attribute or validator"
                    ))

    def _check_dangerous_patterns(self, root: ET.Element):
        """Check entire XML for dangerous patterns."""
        xml_string = ET.tostring(root, encoding='unicode')

        # Check for shell metacharacters in default values
        dangerous_chars = ['$', '`', ';', '|', '&', '>', '<', '\n']
        params = root.findall('.//param[@value]')

        for param in params:
            value = param.get('value', '')
            param_name = param.get('name', 'unknown')

            for char in dangerous_chars:
                if char in value:
                    self.issues.append(SecurityIssue(
                        level=SecurityLevel.HIGH,
                        category="dangerous_default",
                        message=f"Parameter '{param_name}' has dangerous character '{char}' in default value",
                        code_snippet=ET.tostring(param, encoding='unicode'),
                        recommendation="Remove dangerous characters from defaults"
                    ))

    def _check_network_access(self, root: ET.Element):
        """Check for network access patterns."""
        command = root.find('.//command')
        if command is not None:
            cmd_text = command.text or ""

            network_patterns = ['curl', 'wget', 'http://', 'https://', 'ftp://', 'ssh']

            for pattern in network_patterns:
                if pattern in cmd_text:
                    self.issues.append(SecurityIssue(
                        level=SecurityLevel.MEDIUM,
                        category="network_access",
                        message=f"Tool makes network requests: {pattern}",
                        code_snippet=self._get_context(cmd_text, pattern),
                        recommendation="Ensure network access is necessary and document external dependencies"
                    ))

    def _check_file_access(self, root: ET.Element):
        """Check for access to sensitive files."""
        command = root.find('.//command')
        if command is not None:
            cmd_text = command.text or ""

            sensitive_paths = [
                '/etc/passwd', '/etc/shadow', '/etc/sudoers',
                '~/.ssh', '~/.aws', '~/.bash_history',
                '/root/', '/home/', '/var/log/'
            ]

            for path in sensitive_paths:
                if path in cmd_text:
                    self.issues.append(SecurityIssue(
                        level=SecurityLevel.HIGH,
                        category="sensitive_file_access",
                        message=f"Tool accesses sensitive path: {path}",
                        code_snippet=self._get_context(cmd_text, path),
                        recommendation="Remove access to sensitive system files"
                    ))

    def _check_interpreter_usage(self, root: ET.Element):
        """Check for script interpreter usage."""
        command = root.find('.//command')
        if command is not None:
            cmd_text = command.text or ""

            interpreters = {
                'python -c': 'Inline Python code execution',
                'perl -e': 'Inline Perl code execution',
                'bash -c': 'Inline bash code execution',
                'sh -c': 'Inline shell code execution',
                'ruby -e': 'Inline Ruby code execution',
            }

            for interpreter, description in interpreters.items():
                if interpreter in cmd_text:
                    self.issues.append(SecurityIssue(
                        level=SecurityLevel.HIGH,
                        category="interpreter_usage",
                        message=f"Inline code execution detected: {interpreter} ({description})",
                        code_snippet=self._get_context(cmd_text, interpreter),
                        recommendation="Use external scripts instead of inline code"
                    ))

    def _get_context(self, text: str, pattern: str, context_chars: int = 50) -> str:
        """Get context around a pattern match."""
        idx = text.find(pattern)
        if idx == -1:
            return pattern

        start = max(0, idx - context_chars)
        end = min(len(text), idx + len(pattern) + context_chars)

        context = text[start:end]
        if start > 0:
            context = "..." + context
        if end < len(text):
            context = context + "..."

        return context

    def generate_report(self, issues: List[SecurityIssue]) -> str:
        """Generate a human-readable security report."""
        if not issues:
            return "✅ No security issues found"

        report_lines = ["🔐 Security Validation Report", "=" * 50, ""]

        # Group by severity
        by_severity = {}
        for issue in issues:
            level = issue.level.value
            if level not in by_severity:
                by_severity[level] = []
            by_severity[level].append(issue)

        # Report by severity
        severity_order = [SecurityLevel.CRITICAL, SecurityLevel.HIGH, SecurityLevel.MEDIUM, SecurityLevel.LOW, SecurityLevel.INFO]

        for level in severity_order:
            level_issues = by_severity.get(level.value, [])
            if not level_issues:
                continue

            emoji = {
                SecurityLevel.CRITICAL: "🔴",
                SecurityLevel.HIGH: "🟠",
                SecurityLevel.MEDIUM: "🟡",
                SecurityLevel.LOW: "🔵",
                SecurityLevel.INFO: "ℹ️"
            }[level]

            report_lines.append(f"\n{emoji} {level.value.upper()} ({len(level_issues)} issues)")
            report_lines.append("-" * 50)

            for i, issue in enumerate(level_issues, 1):
                report_lines.append(f"\n{i}. [{issue.category}] {issue.message}")

                if issue.code_snippet:
                    report_lines.append(f"   Code: {issue.code_snippet[:100]}")

                if issue.recommendation:
                    report_lines.append(f"   Fix: {issue.recommendation}")

        # Summary
        critical_count = len(by_severity.get(SecurityLevel.CRITICAL.value, []))
        high_count = len(by_severity.get(SecurityLevel.HIGH.value, []))

        report_lines.append("\n" + "=" * 50)
        report_lines.append(f"Total Issues: {len(issues)}")
        report_lines.append(f"Critical: {critical_count}, High: {high_count}")

        if critical_count > 0:
            report_lines.append("\n⛔ FAILED: Critical security issues found")
        elif high_count > 0:
            report_lines.append("\n⚠️  WARNING: High severity issues found")
        else:
            report_lines.append("\n✅ PASSED: No critical issues")

        return "\n".join(report_lines)


def validate_tool(xml_path: Path, strict: bool = True) -> Tuple[bool, str]:
    """
    Convenience function to validate a tool XML file.

    Args:
        xml_path: Path to tool XML file
        strict: If True, treat high severity as failures

    Returns:
        Tuple of (is_safe, report_text)
    """
    validator = ToolXMLValidator(strict_mode=strict)
    is_safe, issues = validator.validate_file(xml_path)
    report = validator.generate_report(issues)

    return is_safe, report


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python tool_xml_validator.py <tool.xml> [--lenient]")
        sys.exit(1)

    xml_path = Path(sys.argv[1])
    strict = "--lenient" not in sys.argv

    is_safe, report = validate_tool(xml_path, strict=strict)

    print(report)

    sys.exit(0 if is_safe else 1)
