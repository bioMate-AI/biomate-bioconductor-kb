"""
Galaxy Workflow Parser for BioMate Integration

Parses Galaxy .ga workflow files and AI workflow JSON files.
Extracts workflow structure, tools, and dependencies for BioMate integration.

Usage:
    parser = GalaxyWorkflowParser()

    # Parse .ga file
    workflow = parser.parse_ga_file("/path/to/workflow.ga")

    # Parse AI workflow JSON
    ai_workflow = parser.parse_ai_workflow("/path/to/workflow.json")

    # Convert to BioMate format
    biomate_workflow = parser.to_biomate_format(workflow)
"""

import json
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass, field


@dataclass
class WorkflowStep:
    """Represents a single step in a workflow."""
    step_id: str
    step_type: str  # 'data_input', 'tool', 'subworkflow', etc.
    label: Optional[str] = None
    annotation: Optional[str] = None
    tool_id: Optional[str] = None
    tool_version: Optional[str] = None
    tool_name: Optional[str] = None
    dependencies: List[Tuple[str, str]] = field(default_factory=list)  # (step_id, output_name)
    tool_state: Dict[str, Any] = field(default_factory=dict)
    position: Dict[str, int] = field(default_factory=dict)  # {left, top}
    outputs: List[Dict[str, str]] = field(default_factory=list)


@dataclass
class ParsedWorkflow:
    """Represents a parsed Galaxy workflow."""
    name: str
    annotation: str = ""
    format_version: str = "0.1"
    steps: List[WorkflowStep] = field(default_factory=list)
    tags: List[str] = field(default_factory=list)
    uuid: Optional[str] = None
    version: int = 1

    # AI workflow specific fields
    workflow_id: Optional[str] = None
    owner: Optional[str] = None
    create_time: Optional[str] = None
    update_time: Optional[str] = None
    published: bool = False
    importable: bool = False
    number_of_steps: int = 0
    report_template: Optional[str] = None


class GalaxyWorkflowParser:
    """Parser for Galaxy workflow files (.ga and AI JSON formats)."""

    def __init__(self):
        self.tool_mapping = self._load_tool_mapping()

    def parse_ga_file(self, ga_path: Path) -> ParsedWorkflow:
        """
        Parse a .ga workflow file.

        Args:
            ga_path: Path to .ga file

        Returns:
            ParsedWorkflow object
        """
        with open(ga_path, 'r', encoding='utf-8') as f:
            workflow_data = json.load(f)

        return self._parse_workflow_json(workflow_data)

    def parse_ai_workflow(self, json_path: Path) -> ParsedWorkflow:
        """
        Parse an AI workflow JSON file.

        Args:
            json_path: Path to AI workflow JSON file

        Returns:
            ParsedWorkflow object with enhanced metadata
        """
        with open(json_path, 'r', encoding='utf-8') as f:
            ai_workflow = json.load(f)

        # Extract metadata
        metadata = ai_workflow.get('metadata', {})
        workflow_json = ai_workflow.get('workflow_json', {})

        # Parse the workflow
        parsed = self._parse_workflow_json(workflow_json)

        # Add AI-specific metadata
        parsed.workflow_id = ai_workflow.get('workflow_id')
        parsed.owner = metadata.get('owner')
        parsed.create_time = metadata.get('create_time')
        parsed.update_time = metadata.get('update_time')
        parsed.published = metadata.get('published', False)
        parsed.importable = metadata.get('importable', False)
        parsed.number_of_steps = metadata.get('number_of_steps', len(parsed.steps))

        # Extract report template
        report = workflow_json.get('report', {})
        parsed.report_template = report.get('markdown')

        return parsed

    def _parse_workflow_json(self, workflow_data: Dict[str, Any]) -> ParsedWorkflow:
        """Parse workflow JSON structure (common to both .ga and AI formats)."""
        workflow = ParsedWorkflow(
            name=workflow_data.get('name', 'Untitled Workflow'),
            annotation=workflow_data.get('annotation', ''),
            format_version=workflow_data.get('format-version', '0.1'),
            tags=workflow_data.get('tags', []),
            uuid=workflow_data.get('uuid'),
            version=workflow_data.get('version', 1)
        )

        # Parse steps
        steps_data = workflow_data.get('steps', {})
        for step_id, step_data in steps_data.items():
            step = self._parse_step(step_id, step_data)
            workflow.steps.append(step)

        return workflow

    def _parse_step(self, step_id: str, step_data: Dict[str, Any]) -> WorkflowStep:
        """Parse a single workflow step."""
        step = WorkflowStep(
            step_id=step_id,
            step_type=step_data.get('type', 'unknown'),
            label=step_data.get('label'),
            annotation=step_data.get('annotation', ''),
            tool_id=step_data.get('tool_id'),
            tool_version=step_data.get('tool_version'),
            tool_name=step_data.get('name'),
            position=step_data.get('position', {}),
            outputs=step_data.get('outputs', [])
        )

        # Parse tool state
        tool_state_str = step_data.get('tool_state', '{}')
        try:
            step.tool_state = json.loads(tool_state_str) if isinstance(tool_state_str, str) else tool_state_str
        except json.JSONDecodeError:
            step.tool_state = {}

        # Parse input connections (dependencies)
        input_connections = step_data.get('input_connections', {})
        step.dependencies = self._extract_dependencies(input_connections)

        return step

    def _extract_dependencies(self, input_connections: Dict[str, Any]) -> List[Tuple[str, str]]:
        """
        Extract step dependencies from input_connections.

        Returns:
            List of (step_id, output_name) tuples
        """
        dependencies = []

        for input_name, connection in input_connections.items():
            if isinstance(connection, dict):
                step_id = str(connection.get('id', ''))
                output_name = connection.get('output_name', 'output')
                dependencies.append((step_id, output_name))
            elif isinstance(connection, list):
                # Multiple connections for this input
                for conn in connection:
                    step_id = str(conn.get('id', ''))
                    output_name = conn.get('output_name', 'output')
                    dependencies.append((step_id, output_name))

        return dependencies

    def _load_tool_mapping(self) -> Dict[str, str]:
        """
        Load Galaxy tool ID to BioMate tool ID mapping.

        Returns:
            Dictionary mapping Galaxy tool IDs to BioMate tool IDs
        """
        # TODO: Load from configuration file or database
        # For now, return basic mapping
        return {
            'fastqc': 'fastqc',
            'trimmomatic': 'trimmomatic',
            'bwa': 'bwa',
            'samtools': 'samtools',
            # Add more mappings as needed
        }

    def extract_tool_name_from_galaxy_id(self, galaxy_tool_id: str) -> str:
        """
        Extract tool name from Galaxy Tool Shed ID.

        Example:
            toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy0
            -> fastqc

        Args:
            galaxy_tool_id: Full Galaxy tool ID

        Returns:
            Tool name
        """
        if not galaxy_tool_id:
            return ''

        # Split by '/'
        parts = galaxy_tool_id.split('/')

        if len(parts) >= 4:
            # Format: toolshed.../repos/owner/tool_name/...
            tool_name = parts[3]
            return tool_name

        # Fallback: return last part
        return parts[-1].split(':')[0]

    def map_galaxy_tool_to_biomate(self, galaxy_tool_id: str) -> Optional[str]:
        """
        Map Galaxy tool ID to BioMate tool ID.

        Args:
            galaxy_tool_id: Galaxy Tool Shed ID

        Returns:
            BioMate tool ID or None if no mapping found
        """
        tool_name = self.extract_tool_name_from_galaxy_id(galaxy_tool_id)
        return self.tool_mapping.get(tool_name)

    def build_dependency_graph(self, workflow: ParsedWorkflow) -> Dict[str, List[str]]:
        """
        Build dependency graph from workflow steps.

        Returns:
            Dictionary mapping step_id to list of dependent step_ids
        """
        graph = {}

        for step in workflow.steps:
            graph[step.step_id] = []
            for dep_step_id, _ in step.dependencies:
                graph[step.step_id].append(dep_step_id)

        return graph

    def get_execution_order(self, workflow: ParsedWorkflow) -> List[str]:
        """
        Determine step execution order using topological sort.

        Returns:
            List of step IDs in execution order
        """
        graph = self.build_dependency_graph(workflow)
        visited = set()
        order = []

        def visit(step_id):
            if step_id in visited:
                return
            visited.add(step_id)

            # Visit dependencies first
            for dep_id in graph.get(step_id, []):
                visit(dep_id)

            order.append(step_id)

        # Visit all steps
        for step_id in graph.keys():
            visit(step_id)

        return order

    def to_biomate_format(self, workflow: ParsedWorkflow) -> Dict[str, Any]:
        """
        Convert parsed workflow to BioMate format.

        Args:
            workflow: ParsedWorkflow object

        Returns:
            Dictionary in BioMate workflow format
        """
        biomate_steps = []

        for step in workflow.steps:
            biomate_step = {
                'id': step.step_id,
                'type': step.step_type,
                'name': step.label or step.tool_name or f"Step {step.step_id}",
                'annotation': step.annotation,
            }

            # Map Galaxy tool to BioMate tool
            if step.tool_id:
                biomate_tool_id = self.map_galaxy_tool_to_biomate(step.tool_id)
                if biomate_tool_id:
                    biomate_step['tool_id'] = biomate_tool_id
                else:
                    biomate_step['tool_id'] = step.tool_id
                    biomate_step['unmapped_tool'] = True

            # Add dependencies
            if step.dependencies:
                biomate_step['dependencies'] = [
                    {'step_id': dep_id, 'output': output_name}
                    for dep_id, output_name in step.dependencies
                ]

            # Add parameters
            if step.tool_state:
                biomate_step['parameters'] = step.tool_state

            biomate_steps.append(biomate_step)

        return {
            'name': workflow.name,
            'description': workflow.annotation,
            'steps': biomate_steps,
            'tags': workflow.tags,
            'metadata': {
                'source': 'galaxy',
                'galaxy_uuid': workflow.uuid,
                'galaxy_workflow_id': workflow.workflow_id,
                'owner': workflow.owner,
                'published': workflow.published
            }
        }

    def get_workflow_summary(self, workflow: ParsedWorkflow) -> Dict[str, Any]:
        """
        Generate workflow summary statistics.

        Returns:
            Dictionary with workflow statistics
        """
        tool_steps = [s for s in workflow.steps if s.step_type == 'tool']
        input_steps = [s for s in workflow.steps if s.step_type == 'data_input']

        tool_ids = [s.tool_id for s in tool_steps if s.tool_id]
        unique_tools = set(self.extract_tool_name_from_galaxy_id(tid) for tid in tool_ids)

        return {
            'name': workflow.name,
            'total_steps': len(workflow.steps),
            'tool_steps': len(tool_steps),
            'input_steps': len(input_steps),
            'unique_tools': len(unique_tools),
            'tools_used': list(unique_tools),
            'tags': workflow.tags,
            'has_annotation': bool(workflow.annotation),
            'published': workflow.published
        }


def demo():
    """Demo usage of the parser."""
    parser = GalaxyWorkflowParser()

    # Parse a .ga file
    ga_path = Path("/home/yzhang/biomate/research/galaxy/enhanced_cloud_workflow.ga")
    if ga_path.exists():
        print("Parsing .ga workflow...")
        workflow = parser.parse_ga_file(ga_path)
        print(f"Workflow: {workflow.name}")
        print(f"Steps: {len(workflow.steps)}")
        print(f"Tags: {workflow.tags}")

        # Get summary
        summary = parser.get_workflow_summary(workflow)
        print(f"\nSummary:")
        print(f"  Total steps: {summary['total_steps']}")
        print(f"  Tool steps: {summary['tool_steps']}")
        print(f"  Input steps: {summary['input_steps']}")
        print(f"  Unique tools: {summary['unique_tools']}")
        print(f"  Tools used: {', '.join(summary['tools_used'])}")

        # Get execution order
        order = parser.get_execution_order(workflow)
        print(f"\nExecution order: {' -> '.join(order)}")

        # Convert to BioMate format
        biomate = parser.to_biomate_format(workflow)
        print(f"\nBioMate format preview:")
        print(json.dumps(biomate, indent=2)[:500] + "...")

    # Parse AI workflow
    ai_path = Path("/home/yzhang/biomate/research/galaxy/lib/galaxy/ai/data/workflows/workflow_00381bbae3fd7e78.json")
    if ai_path.exists():
        print("\n\n" + "="*70)
        print("Parsing AI workflow...")
        ai_workflow = parser.parse_ai_workflow(ai_path)
        print(f"Workflow: {ai_workflow.name}")
        print(f"Owner: {ai_workflow.owner}")
        print(f"Created: {ai_workflow.create_time}")
        print(f"Steps: {len(ai_workflow.steps)}")
        print(f"Published: {ai_workflow.published}")

        summary = parser.get_workflow_summary(ai_workflow)
        print(f"\nTools used: {', '.join(summary['tools_used'])}")


if __name__ == '__main__':
    demo()
