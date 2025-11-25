#!/usr/bin/env python3
"""
Workflow Hierarchy Detector

Detects logical subworkflow groups in flat Galaxy workflows by analyzing:
1. Dependency graphs (DAG structure)
2. Tool categories and biological patterns
3. Input/output signatures

Author: BioMate Team
Date: 2025-11-24
"""

from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass
import networkx as nx


@dataclass
class SubworkflowGroup:
    """Represents a detected subworkflow group."""
    group_id: str
    steps: List[str]  # Step IDs in this group
    category: str  # alignment, qc, assembly, etc.
    description: str
    inputs: List[str]  # External inputs needed
    outputs: List[str]  # Outputs produced


class WorkflowHierarchyDetector:
    """
    Detects logical subworkflow groups in flat Galaxy workflows.

    Strategy:
    1. Build dependency graph
    2. Find strongly connected components
    3. Detect linear chains
    4. Classify by tool categories
    5. Group by biological patterns
    """

    def __init__(self):
        # Tool category patterns
        self.tool_categories = {
            'alignment': ['bwa', 'bowtie', 'hisat', 'star', 'minimap', 'dragmap'],
            'qc': ['fastqc', 'multiqc', 'qualimap', 'rseqc'],
            'trimming': ['cutadapt', 'trimmomatic', 'fastp', 'trim_galore'],
            'quantification': ['featurecounts', 'htseq', 'salmon', 'kallisto', 'rsem'],
            'assembly': ['spades', 'megahit', 'unicycler', 'flye'],
            'variant_calling': ['bcftools', 'freebayes', 'gatk', 'varscan'],
            'umi': ['fgbio', 'umi_tools', 'umitools'],
            'sorting': ['samtools_sort', 'picard_sort'],
            'indexing': ['samtools_index', 'bwa_index'],
            'conversion': ['samtools_view', 'samtools_fastq', 'bam2fastq'],
            'filtering': ['samtools_filter', 'bcftools_filter', 'filter'],
        }

    def detect_subworkflows(self, galaxy_wf: Dict) -> List[SubworkflowGroup]:
        """
        Detect logical subworkflow groups.

        Args:
            galaxy_wf: Galaxy workflow definition

        Returns:
            List of detected subworkflow groups
        """

        steps = galaxy_wf.get('steps', {})

        # Build dependency graph
        graph = self.build_dependency_graph(steps)

        # Find logical groups
        groups = self.find_logical_groups(graph, steps)

        return groups

    def build_dependency_graph(self, steps: Dict) -> nx.DiGraph:
        """
        Build directed acyclic graph from workflow steps.

        Args:
            steps: Galaxy workflow steps

        Returns:
            Directed graph where edges represent data dependencies
        """

        G = nx.DiGraph()

        # Add all tool steps as nodes
        for step_id, step in steps.items():
            if step.get('type') == 'tool':
                G.add_node(step_id, **step)

        # Add edges based on input connections
        for step_id, step in steps.items():
            if step.get('type') != 'tool':
                continue

            connections = step.get('input_connections', {})
            for input_name, connection in connections.items():
                if isinstance(connection, dict):
                    source_id = str(connection.get('id'))
                    if source_id in G.nodes:
                        G.add_edge(source_id, step_id)
                elif isinstance(connection, list):
                    # Multiple inputs
                    for conn in connection:
                        source_id = str(conn.get('id'))
                        if source_id in G.nodes:
                            G.add_edge(source_id, step_id)

        return G

    def find_logical_groups(self, graph: nx.DiGraph, steps: Dict) -> List[SubworkflowGroup]:
        """
        Find logical groups of steps that form cohesive units.

        Strategy:
        1. Find linear chains (sequences without branching)
        2. Group by tool category
        3. Respect dependency boundaries

        Args:
            graph: Dependency graph
            steps: Galaxy workflow steps

        Returns:
            List of subworkflow groups
        """

        groups = []
        visited = set()

        # Try to find linear chains first
        for node in nx.topological_sort(graph):
            if node in visited:
                continue

            # Start a potential chain
            chain = self._find_chain_from_node(graph, node, visited, steps)

            if len(chain) >= 2:  # At least 2 steps to form a group
                # Classify the chain
                category = self._classify_group(chain, steps)

                # Create subworkflow group
                group = SubworkflowGroup(
                    group_id=f"{category}_{len(groups)}",
                    steps=chain,
                    category=category,
                    description=self._generate_description(chain, steps),
                    inputs=self._find_group_inputs(chain, graph, steps),
                    outputs=self._find_group_outputs(chain, graph, steps)
                )
                groups.append(group)
                visited.update(chain)

        # Add remaining single steps as individual groups
        for node in graph.nodes:
            if node not in visited:
                step = steps[node]
                tool_id = step.get('tool_id', '')
                category = self._get_tool_category(tool_id)

                group = SubworkflowGroup(
                    group_id=f"{category}_{len(groups)}",
                    steps=[node],
                    category=category,
                    description=step.get('name', tool_id),
                    inputs=self._find_group_inputs([node], graph, steps),
                    outputs=self._find_group_outputs([node], graph, steps)
                )
                groups.append(group)
                visited.add(node)

        return groups

    def _find_chain_from_node(self,
                             graph: nx.DiGraph,
                             start_node: str,
                             visited: Set[str],
                             steps: Dict) -> List[str]:
        """
        Find a linear chain starting from a node.

        A chain continues if:
        - Current node has exactly one successor
        - Successor has exactly one predecessor (current node)
        - Nodes belong to same category
        """

        chain = [start_node]
        current = start_node
        start_category = self._get_tool_category(steps[start_node].get('tool_id', ''))

        while True:
            successors = list(graph.successors(current))

            # Check if we can extend the chain
            if len(successors) != 1:
                break  # Branching or end

            next_node = successors[0]

            # Check if next_node has only one predecessor
            predecessors = list(graph.predecessors(next_node))
            if len(predecessors) != 1:
                break  # Next node has multiple inputs

            # Check if next_node is same category
            next_category = self._get_tool_category(steps[next_node].get('tool_id', ''))
            if next_category != start_category and start_category != 'unknown':
                break  # Different category

            # Check if already visited
            if next_node in visited:
                break

            # Extend chain
            chain.append(next_node)
            current = next_node

        return chain

    def _get_tool_category(self, tool_id: str) -> str:
        """Get category for a tool."""
        tool_id_lower = tool_id.lower()

        for category, keywords in self.tool_categories.items():
            for keyword in keywords:
                if keyword in tool_id_lower:
                    return category

        return 'unknown'

    def _classify_group(self, chain: List[str], steps: Dict) -> str:
        """Classify a group of steps by their predominant category."""
        categories = []
        for step_id in chain:
            tool_id = steps[step_id].get('tool_id', '')
            category = self._get_tool_category(tool_id)
            if category != 'unknown':
                categories.append(category)

        if not categories:
            return 'unknown'

        # Return most common category
        return max(set(categories), key=categories.count)

    def _generate_description(self, chain: List[str], steps: Dict) -> str:
        """Generate description for a group."""
        tool_names = []
        for step_id in chain:
            name = steps[step_id].get('name', steps[step_id].get('tool_id', ''))
            tool_names.append(name)

        if len(tool_names) <= 3:
            return ' → '.join(tool_names)
        else:
            return f"{tool_names[0]} → ... → {tool_names[-1]} ({len(tool_names)} steps)"

    def _find_group_inputs(self,
                          chain: List[str],
                          graph: nx.DiGraph,
                          steps: Dict) -> List[str]:
        """Find external inputs needed by this group."""
        inputs = []
        chain_set = set(chain)

        for step_id in chain:
            # Find predecessors not in this chain
            for pred in graph.predecessors(step_id):
                if pred not in chain_set:
                    # This is an external input
                    pred_step = steps[pred]
                    inputs.append(f"{pred}:{pred_step.get('name', pred)}")

        return inputs

    def _find_group_outputs(self,
                           chain: List[str],
                           graph: nx.DiGraph,
                           steps: Dict) -> List[str]:
        """Find outputs produced by this group."""
        outputs = []
        chain_set = set(chain)

        # Last step in chain typically produces the main output
        last_step = chain[-1]
        step_outputs = steps[last_step].get('outputs', [])

        for output in step_outputs:
            output_name = output.get('name', 'output')
            outputs.append(output_name)

        # Also check if any step in chain has successors outside chain
        for step_id in chain:
            for succ in graph.successors(step_id):
                if succ not in chain_set:
                    # This step produces output used externally
                    if step_id not in [s.split(':')[0] for s in outputs]:
                        outputs.append(f"{step_id}:output")

        return outputs if outputs else ['output']


# ==============================================================================
# CLI for testing
# ==============================================================================

def main():
    """Test the hierarchy detector."""
    import json
    import sys

    if len(sys.argv) < 2:
        print("Usage: python workflow_hierarchy_detector.py <workflow.ga>")
        sys.exit(1)

    workflow_path = sys.argv[1]

    # Load workflow
    with open(workflow_path) as f:
        workflow = json.load(f)

    # Detect hierarchies
    detector = WorkflowHierarchyDetector()
    groups = detector.detect_subworkflows(workflow)

    # Print results
    print(f"\n{'='*80}")
    print(f"Workflow: {workflow.get('name', 'UNNAMED')}")
    print(f"Total steps: {len(workflow.get('steps', {}))}")
    print(f"Detected subworkflows: {len(groups)}")
    print(f"{'='*80}\n")

    for i, group in enumerate(groups, 1):
        print(f"{i}. {group.group_id} ({group.category})")
        print(f"   Steps: {len(group.steps)} - {', '.join(group.steps)}")
        print(f"   Description: {group.description}")
        print(f"   Inputs: {', '.join(group.inputs) if group.inputs else 'None'}")
        print(f"   Outputs: {', '.join(group.outputs)}")
        print()


if __name__ == '__main__':
    main()
