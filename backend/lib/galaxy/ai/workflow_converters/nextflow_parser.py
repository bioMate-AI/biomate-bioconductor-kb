"""
Nextflow DSL Parser

Parses Nextflow DSL2 .nf files and extracts workflow structure:
- Workflow definitions
- Process invocations
- Channel operations
- Include statements
- Input/output declarations

Strategy:
- Regex-based parsing for common patterns
- Line-by-line analysis with state machine
- Handles Nextflow DSL2 syntax

Author: BioMate Team
Date: 2025-11-19
"""

import re
import logging
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger(__name__)


@dataclass
class NextflowInclude:
    """Represents a Nextflow include statement."""
    items: List[str]  # What's being included (process/workflow names)
    source: str       # File path being included from
    alias: Optional[str] = None  # Optional alias


@dataclass
class NextflowChannel:
    """Represents a Nextflow channel declaration."""
    name: str
    type: str  # "input", "output", "intermediate"
    description: str = ""
    data_type: str = ""  # e.g., "val(meta), path(bam)"


@dataclass
class NextflowProcessCall:
    """Represents a process invocation in workflow."""
    process_name: str
    inputs: List[str]  # Input channel names
    outputs: List[str] = field(default_factory=list)  # Output assignments
    line_number: int = 0


@dataclass
class NextflowWorkflow:
    """Parsed Nextflow workflow structure."""
    name: str
    description: str = ""

    # Include statements
    includes: List[NextflowInclude] = field(default_factory=list)

    # Input declarations (from take: block)
    inputs: List[NextflowChannel] = field(default_factory=list)

    # Output declarations (from emit: block)
    outputs: List[NextflowChannel] = field(default_factory=list)

    # Process calls in main: block
    process_calls: List[NextflowProcessCall] = field(default_factory=list)

    # Channel operations
    channel_operations: List[Dict[str, Any]] = field(default_factory=list)

    # Raw sections
    raw_take: str = ""
    raw_main: str = ""
    raw_emit: str = ""

    # Metadata
    file_path: Optional[Path] = None


class NextflowParser:
    """
    Parser for Nextflow DSL2 workflow files.

    Handles:
    - Workflow definitions
    - Include statements
    - Take/main/emit blocks
    - Process invocations
    - Channel operations

    Limitations:
    - Regex-based, may not handle all edge cases
    - Designed for nf-core style workflows
    - May need refinement for complex workflows
    """

    def __init__(self):
        """Initialize parser with regex patterns."""

        # Pattern: include { PROCESS } from 'path'
        self.include_pattern = re.compile(
            r'include\s*\{\s*([^}]+)\}\s*from\s*[\'"]([^\'"]+)[\'"]',
            re.MULTILINE
        )

        # Pattern: workflow NAME {
        self.workflow_pattern = re.compile(
            r'workflow\s+(\w+)\s*\{',
            re.MULTILINE
        )

        # Pattern: process NAME {
        self.process_pattern = re.compile(
            r'process\s+(\w+)\s*\{',
            re.MULTILINE
        )

        # Pattern: PROCESS_NAME ( inputs )
        self.process_call_pattern = re.compile(
            r'(\w+)\s*\(\s*([^)]*)\s*\)',
            re.MULTILINE
        )

        # Pattern: channel comments (e.g., // channel: [ val(meta), path(bam) ])
        self.channel_comment_pattern = re.compile(
            r'//\s*channel:\s*(.+?)(?:\n|$)',
            re.MULTILINE
        )

    def parse_file(self, file_path: Path) -> NextflowWorkflow:
        """
        Parse Nextflow .nf file.

        Args:
            file_path: Path to .nf file

        Returns:
            NextflowWorkflow object
        """
        log.info(f"Parsing Nextflow file: {file_path}")

        content = file_path.read_text()

        # Extract workflow name
        workflow_match = self.workflow_pattern.search(content)
        if not workflow_match:
            raise ValueError(f"No workflow definition found in {file_path}")

        workflow_name = workflow_match.group(1)

        # Extract description from top comments
        description = self._extract_description(content)

        # Parse include statements
        includes = self._parse_includes(content)

        # Extract workflow block
        workflow_block = self._extract_workflow_block(content, workflow_name)

        # Parse workflow sections
        take_section = self._extract_section(workflow_block, "take")
        main_section = self._extract_section(workflow_block, "main")
        emit_section = self._extract_section(workflow_block, "emit")

        # Parse inputs from take section
        inputs = self._parse_take_section(take_section, content)

        # Parse outputs from emit section
        outputs = self._parse_emit_section(emit_section)

        # Parse process calls from main section
        process_calls = self._parse_main_section(main_section)

        # Build workflow object
        workflow = NextflowWorkflow(
            name=workflow_name,
            description=description,
            includes=includes,
            inputs=inputs,
            outputs=outputs,
            process_calls=process_calls,
            raw_take=take_section,
            raw_main=main_section,
            raw_emit=emit_section,
            file_path=file_path
        )

        log.info(f"Parsed workflow '{workflow_name}': "
                f"{len(inputs)} inputs, {len(outputs)} outputs, "
                f"{len(process_calls)} process calls")

        return workflow

    def _extract_description(self, content: str) -> str:
        """Extract description from top comments."""
        lines = content.split('\n')
        description_lines = []

        for line in lines:
            stripped = line.strip()
            if stripped.startswith('//'):
                # Remove comment marker
                desc = stripped[2:].strip()
                if desc:  # Skip empty comment lines
                    description_lines.append(desc)
            elif stripped and not stripped.startswith('include'):
                # Stop at first non-comment, non-empty line
                break

        return ' '.join(description_lines)

    def _parse_includes(self, content: str) -> List[NextflowInclude]:
        """Parse include statements."""
        includes = []

        for match in self.include_pattern.finditer(content):
            items_str = match.group(1)
            source = match.group(2)

            # Parse items (can be comma-separated)
            items = [item.strip() for item in items_str.split(',')]

            includes.append(NextflowInclude(
                items=items,
                source=source
            ))

        return includes

    def _extract_workflow_block(self, content: str, workflow_name: str) -> str:
        """Extract the workflow { ... } block."""
        # Find workflow start
        pattern = re.compile(
            rf'workflow\s+{re.escape(workflow_name)}\s*\{{',
            re.MULTILINE
        )

        match = pattern.search(content)
        if not match:
            return ""

        start = match.end()

        # Find matching closing brace
        brace_count = 1
        pos = start

        while pos < len(content) and brace_count > 0:
            if content[pos] == '{':
                brace_count += 1
            elif content[pos] == '}':
                brace_count -= 1
            pos += 1

        if brace_count == 0:
            return content[start:pos-1]
        else:
            log.warning(f"Unmatched braces in workflow {workflow_name}")
            return content[start:]

    def _extract_section(self, workflow_block: str, section_name: str) -> str:
        """
        Extract a section (take, main, emit) from workflow block.

        Args:
            workflow_block: Content of workflow { ... }
            section_name: "take", "main", or "emit"

        Returns:
            Section content
        """
        # Pattern: section_name:\n ... \n\n (until next section or end)
        pattern = re.compile(
            rf'{section_name}:\s*\n(.*?)(?=\n\s*(?:take|main|emit):|\n\s*\}})',
            re.DOTALL
        )

        match = pattern.search(workflow_block)
        if match:
            return match.group(1).strip()

        return ""

    def _parse_take_section(
        self,
        take_section: str,
        full_content: str
    ) -> List[NextflowChannel]:
        """
        Parse take: section to extract input channels.

        Format:
            take:
            ch_bam   // channel: [ val(meta), [ bam ] ]
            ch_fasta // channel: [ val(meta), path(fasta) ]
        """
        inputs = []

        lines = take_section.split('\n')
        for line in lines:
            line = line.strip()
            if not line or line.startswith('//'):
                continue

            # Extract channel name and comment
            parts = line.split('//', 1)
            channel_name = parts[0].strip()

            # Extract description from comment
            description = ""
            data_type = ""

            if len(parts) > 1:
                comment = parts[1].strip()
                # Look for channel: [ ... ] pattern
                channel_match = re.search(r'channel:\s*(.+)', comment)
                if channel_match:
                    data_type = channel_match.group(1).strip()
                else:
                    description = comment

            if channel_name:
                inputs.append(NextflowChannel(
                    name=channel_name,
                    type="input",
                    description=description,
                    data_type=data_type
                ))

        return inputs

    def _parse_emit_section(self, emit_section: str) -> List[NextflowChannel]:
        """
        Parse emit: section to extract output channels.

        Format:
            emit:
            bam      = SAMTOOLS_SORT.out.bam           // channel: [ val(meta), [ bam ] ]
            stats    = BAM_STATS_SAMTOOLS.out.stats    // channel: [ val(meta), [ stats ] ]
        """
        outputs = []

        lines = emit_section.split('\n')
        for line in lines:
            line = line.strip()
            if not line or line.startswith('//'):
                continue

            # Parse: output_name = SOURCE // comment
            parts = line.split('//', 1)
            assignment = parts[0].strip()

            # Extract output name and source
            if '=' in assignment:
                output_name, source = assignment.split('=', 1)
                output_name = output_name.strip()
                source = source.strip()
            else:
                # Sometimes just the name
                output_name = assignment
                source = ""

            # Extract description from comment
            description = ""
            data_type = ""

            if len(parts) > 1:
                comment = parts[1].strip()
                channel_match = re.search(r'channel:\s*(.+)', comment)
                if channel_match:
                    data_type = channel_match.group(1).strip()
                else:
                    description = comment

            if output_name:
                outputs.append(NextflowChannel(
                    name=output_name,
                    type="output",
                    description=description,
                    data_type=data_type
                ))

        return outputs

    def _parse_main_section(self, main_section: str) -> List[NextflowProcessCall]:
        """
        Parse main: section to extract process calls.

        Format:
            main:
            SAMTOOLS_SORT ( ch_bam, ch_fasta )
            SAMTOOLS_INDEX ( SAMTOOLS_SORT.out.bam )
        """
        process_calls = []

        lines = main_section.split('\n')
        line_number = 0

        for line in lines:
            line_number += 1
            line = line.strip()

            # Skip empty lines and comments
            if not line or line.startswith('//'):
                continue

            # Skip channel assignments (e.g., ch_versions = ...)
            if '=' in line and not line.strip().startswith('//'):
                # Check if this is a process call with output assignment
                # e.g., some_var = PROCESS(...)
                if '(' not in line:
                    continue

            # Look for process call pattern: PROCESS_NAME ( inputs )
            match = self.process_call_pattern.search(line)
            if match:
                process_name = match.group(1)
                inputs_str = match.group(2)

                # Skip if this looks like a method call (e.g., .map, .join)
                if line.strip().startswith('.'):
                    continue

                # Skip if process name is a keyword or operator
                keywords = {'if', 'else', 'for', 'while', 'def', 'return',
                           'map', 'filter', 'join', 'mix', 'set'}
                if process_name.lower() in keywords:
                    continue

                # Parse inputs
                inputs = []
                if inputs_str.strip():
                    # Split by comma, but be careful with nested parentheses
                    inputs = self._split_arguments(inputs_str)

                process_calls.append(NextflowProcessCall(
                    process_name=process_name,
                    inputs=inputs,
                    line_number=line_number
                ))

        return process_calls

    def _split_arguments(self, args_str: str) -> List[str]:
        """
        Split argument string by comma, respecting nested parentheses.

        Example: "ch_bam, ch_fasta" → ["ch_bam", "ch_fasta"]
                 "[ meta, bam ]" → ["[ meta, bam ]"]
        """
        args = []
        current = []
        paren_depth = 0
        bracket_depth = 0

        for char in args_str:
            if char == ',' and paren_depth == 0 and bracket_depth == 0:
                # End of argument
                arg = ''.join(current).strip()
                if arg:
                    args.append(arg)
                current = []
            else:
                if char == '(':
                    paren_depth += 1
                elif char == ')':
                    paren_depth -= 1
                elif char == '[':
                    bracket_depth += 1
                elif char == ']':
                    bracket_depth -= 1

                current.append(char)

        # Add last argument
        arg = ''.join(current).strip()
        if arg:
            args.append(arg)

        return args

    def parse_string(self, content: str, workflow_name: str = "UNKNOWN") -> NextflowWorkflow:
        """
        Parse Nextflow content from string.

        Args:
            content: Nextflow DSL content
            workflow_name: Name of workflow (if known)

        Returns:
            NextflowWorkflow object
        """
        # If workflow name not provided, try to extract it
        if workflow_name == "UNKNOWN":
            workflow_match = self.workflow_pattern.search(content)
            if workflow_match:
                workflow_name = workflow_match.group(1)

        # Extract description
        description = self._extract_description(content)

        # Parse includes
        includes = self._parse_includes(content)

        # Extract workflow block
        workflow_block = self._extract_workflow_block(content, workflow_name)

        # Parse sections
        take_section = self._extract_section(workflow_block, "take")
        main_section = self._extract_section(workflow_block, "main")
        emit_section = self._extract_section(workflow_block, "emit")

        # Parse components
        inputs = self._parse_take_section(take_section, content)
        outputs = self._parse_emit_section(emit_section)
        process_calls = self._parse_main_section(main_section)

        return NextflowWorkflow(
            name=workflow_name,
            description=description,
            includes=includes,
            inputs=inputs,
            outputs=outputs,
            process_calls=process_calls,
            raw_take=take_section,
            raw_main=main_section,
            raw_emit=emit_section
        )


# Convenience functions

def parse_nextflow_file(file_path: Path) -> NextflowWorkflow:
    """Parse Nextflow .nf file."""
    parser = NextflowParser()
    return parser.parse_file(file_path)


def parse_nextflow_string(content: str, workflow_name: str = "UNKNOWN") -> NextflowWorkflow:
    """Parse Nextflow content from string."""
    parser = NextflowParser()
    return parser.parse_string(content, workflow_name)
