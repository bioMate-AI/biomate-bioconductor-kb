"""
Workflow Optimizer for Galaxy AI Assistant

Optimizes workflow execution order, parallelization, and resource allocation.
"""

import json
import sqlite3
import logging
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple, Set
from dataclasses import dataclass
from enum import Enum
import networkx as nx

from .types import Task, Tool, WorkflowStep, WorkflowTemplate, TaskGraph
from .config import AIConfig

log = logging.getLogger(__name__)

# Database path for tool I/O type lookups
_DB_PATH = Path(__file__).parent.parent.parent.parent / "database" / "galaxy_ai_tools.db"


class OptimizationStrategy(Enum):
    """Workflow optimization strategies."""
    MINIMIZE_TIME = "minimize_time"
    MINIMIZE_RESOURCES = "minimize_resources"
    MAXIMIZE_THROUGHPUT = "maximize_throughput"
    BALANCED = "balanced"


@dataclass
class ResourceRequirement:
    """Resource requirements for a workflow step."""
    cores: int = 1
    memory_gb: float = 4.0
    disk_gb: float = 10.0
    runtime_minutes: int = 60
    gpu_required: bool = False


@dataclass
class OptimizationResult:
    """Result of workflow optimization."""
    optimized_steps: List[WorkflowStep]
    parallel_groups: List[List[int]]  # Groups of steps that can run in parallel
    estimated_total_runtime: int
    estimated_peak_resources: ResourceRequirement
    optimization_notes: List[str]


class WorkflowOptimizer:
    """Optimizes Galaxy workflows for efficient execution."""
    
    def __init__(self, config: AIConfig):
        self.config = config
    
    def optimize_workflow(
        self,
        workflow_template: WorkflowTemplate,
        strategy: OptimizationStrategy = OptimizationStrategy.BALANCED,
        resource_constraints: Optional[ResourceRequirement] = None
    ) -> OptimizationResult:
        """Optimize a workflow for execution."""
        
        # Build dependency graph
        dependency_graph = self._build_dependency_graph(workflow_template.steps)
        
        # Analyze parallelization opportunities
        parallel_groups = self._identify_parallel_groups(dependency_graph)
        
        # Optimize step order
        optimized_steps = self._optimize_step_order(
            workflow_template.steps, dependency_graph, strategy
        )
        
        # Estimate resources and runtime
        total_runtime = self._estimate_total_runtime(optimized_steps, parallel_groups)
        peak_resources = self._estimate_peak_resources(optimized_steps, parallel_groups)
        
        # Generate optimization notes
        notes = self._generate_optimization_notes(
            workflow_template, optimized_steps, parallel_groups, strategy
        )
        
        return OptimizationResult(
            optimized_steps=optimized_steps,
            parallel_groups=parallel_groups,
            estimated_total_runtime=total_runtime,
            estimated_peak_resources=peak_resources,
            optimization_notes=notes
        )
    
    def _build_dependency_graph(self, steps: List[WorkflowStep]) -> nx.DiGraph:
        """Build a networkx dependency graph from workflow steps."""
        graph = nx.DiGraph()
        
        # Add all steps as nodes
        for step in steps:
            graph.add_node(step.step_id, step=step)
        
        # Add edges based on input connections
        for step in steps:
            for input_name, connection in step.input_connections.items():
                source_step_id = connection.get('id')
                if source_step_id is not None:
                    # Add edge from source to current step
                    graph.add_edge(source_step_id, step.step_id)
        
        return graph
    
    def _identify_parallel_groups(self, graph: nx.DiGraph) -> List[List[int]]:
        """Identify groups of steps that can execute in parallel."""
        
        # Find all nodes with no dependencies (can start immediately)
        no_deps = [node for node in graph.nodes() if graph.in_degree(node) == 0]
        
        parallel_groups = []
        processed = set()
        
        # Use topological levels to group parallel steps
        while no_deps:
            current_group = []
            next_candidates = set()
            
            # Process all nodes that can run now
            for node in no_deps:
                if node not in processed:
                    current_group.append(node)
                    processed.add(node)
                    
                    # Find nodes that might be ready after this group completes
                    for successor in graph.successors(node):
                        # Check if all dependencies of successor are satisfied
                        if all(pred in processed for pred in graph.predecessors(successor)):
                            next_candidates.add(successor)
            
            if current_group:
                parallel_groups.append(current_group)
            
            no_deps = list(next_candidates)
        
        return parallel_groups
    
    def _optimize_step_order(
        self,
        steps: List[WorkflowStep],
        graph: nx.DiGraph,
        strategy: OptimizationStrategy
    ) -> List[WorkflowStep]:
        """Optimize the order of workflow steps."""
        
        step_map = {step.step_id: step for step in steps}
        
        if strategy == OptimizationStrategy.MINIMIZE_TIME:
            # Prioritize critical path
            ordered_ids = self._order_by_critical_path(graph)
        elif strategy == OptimizationStrategy.MINIMIZE_RESOURCES:
            # Order to minimize peak resource usage
            ordered_ids = self._order_by_resource_efficiency(graph, step_map)
        elif strategy == OptimizationStrategy.MAXIMIZE_THROUGHPUT:
            # Order to maximize parallel execution
            ordered_ids = self._order_by_parallelism(graph)
        else:  # BALANCED
            # Use topological sort with priority weights
            ordered_ids = self._order_balanced(graph, step_map)
        
        return [step_map[step_id] for step_id in ordered_ids]
    
    def _order_by_critical_path(self, graph: nx.DiGraph) -> List[int]:
        """Order steps to minimize critical path."""
        
        # Calculate longest path to each node
        def longest_path_to_node(node):
            if graph.in_degree(node) == 0:
                return 0
            
            max_path = 0
            for pred in graph.predecessors(node):
                path_length = longest_path_to_node(pred) + 1
                max_path = max(max_path, path_length)
            
            return max_path
        
        # Sort by critical path length (longest first)
        nodes_with_path = [(node, longest_path_to_node(node)) for node in graph.nodes()]
        nodes_with_path.sort(key=lambda x: x[1], reverse=True)
        
        return [node for node, _ in nodes_with_path]
    
    def _order_by_resource_efficiency(
        self,
        graph: nx.DiGraph,
        step_map: Dict[int, WorkflowStep]
    ) -> List[int]:
        """Order steps to minimize peak resource usage."""
        
        # Estimate resource requirements for each step
        def get_step_resources(step_id):
            step = step_map[step_id]
            # Simplified resource estimation
            return self._estimate_step_resources(step)
        
        # Use topological sort but prefer lower resource steps when possible
        ordered = []
        available = [node for node in graph.nodes() if graph.in_degree(node) == 0]
        
        while available:
            # Sort available nodes by resource requirements
            available.sort(key=lambda x: get_step_resources(x).memory_gb)
            
            # Take the least resource-intensive step
            current = available.pop(0)
            ordered.append(current)
            
            # Add newly available steps
            for successor in graph.successors(current):
                if all(pred in ordered for pred in graph.predecessors(successor)):
                    if successor not in available:
                        available.append(successor)
        
        return ordered
    
    def _order_by_parallelism(self, graph: nx.DiGraph) -> List[int]:
        """Order steps to maximize parallel execution opportunities."""
        
        # Use a modified topological sort that prioritizes steps with many successors
        def successor_count(node):
            return len(list(graph.successors(node)))
        
        ordered = []
        available = [node for node in graph.nodes() if graph.in_degree(node) == 0]
        
        while available:
            # Sort by number of successors (more successors first)
            available.sort(key=successor_count, reverse=True)
            
            current = available.pop(0)
            ordered.append(current)
            
            # Add newly available steps
            for successor in graph.successors(current):
                if all(pred in ordered for pred in graph.predecessors(successor)):
                    if successor not in available:
                        available.append(successor)
        
        return ordered
    
    def _order_balanced(
        self,
        graph: nx.DiGraph,
        step_map: Dict[int, WorkflowStep]
    ) -> List[int]:
        """Balanced ordering considering multiple factors."""
        
        def priority_score(node):
            # Combine multiple factors
            step = step_map[node]
            resources = self._estimate_step_resources(step)
            
            score = 0
            
            # Favor steps with more successors (enables more parallelism)
            score += len(list(graph.successors(node))) * 2
            
            # Penalize high resource requirements
            score -= resources.memory_gb * 0.5
            score -= resources.cores * 0.3
            
            # Favor steps on critical path
            if self._is_on_critical_path(graph, node):
                score += 5
            
            return score
        
        ordered = []
        available = [node for node in graph.nodes() if graph.in_degree(node) == 0]
        
        while available:
            # Sort by priority score
            available.sort(key=priority_score, reverse=True)
            
            current = available.pop(0)
            ordered.append(current)
            
            # Add newly available steps
            for successor in graph.successors(current):
                if all(pred in ordered for pred in graph.predecessors(successor)):
                    if successor not in available:
                        available.append(successor)
        
        return ordered
    
    def _is_on_critical_path(self, graph: nx.DiGraph, node: int) -> bool:
        """Check if a node is on the critical path."""
        # Simplified check - assume nodes with no successors are critical
        return graph.out_degree(node) == 0
    
    def _estimate_step_resources(self, step: WorkflowStep) -> ResourceRequirement:
        """Estimate resource requirements for a workflow step."""
        
        # Base requirements
        resources = ResourceRequirement()
        
        # Tool-specific adjustments
        tool_id = step.tool_id.lower()
        
        if any(aligner in tool_id for aligner in ['bwa', 'bowtie', 'hisat2', 'star']):
            resources.cores = 4
            resources.memory_gb = 8.0
            resources.runtime_minutes = 90
        elif any(assembler in tool_id for assembler in ['spades', 'velvet', 'canu']):
            resources.cores = 8
            resources.memory_gb = 16.0
            resources.runtime_minutes = 240
            resources.disk_gb = 50.0
        elif 'fastqc' in tool_id:
            resources.cores = 1
            resources.memory_gb = 2.0
            resources.runtime_minutes = 15
        elif any(caller in tool_id for caller in ['gatk', 'freebayes', 'bcftools']):
            resources.cores = 2
            resources.memory_gb = 8.0
            resources.runtime_minutes = 120
        elif any(rna_tool in tool_id for rna_tool in ['deseq2', 'edger', 'cufflinks']):
            resources.cores = 2
            resources.memory_gb = 8.0
            resources.runtime_minutes = 60
        
        # Parameter-based adjustments
        params = step.parameters
        if isinstance(params, dict):
            if params.get('threads'):
                resources.cores = max(resources.cores, int(params['threads']))
            if params.get('memory'):
                resources.memory_gb = max(resources.memory_gb, float(params['memory']))
        
        return resources
    
    def _estimate_total_runtime(
        self,
        steps: List[WorkflowStep],
        parallel_groups: List[List[int]]
    ) -> int:
        """Estimate total workflow runtime considering parallelization."""
        
        total_time = 0
        step_resources = {
            step.step_id: self._estimate_step_resources(step)
            for step in steps
        }
        
        for group in parallel_groups:
            # In a parallel group, runtime is the maximum of all steps in the group
            group_time = max(
                step_resources[step_id].runtime_minutes
                for step_id in group
            )
            total_time += group_time
        
        return total_time
    
    def _estimate_peak_resources(
        self,
        steps: List[WorkflowStep],
        parallel_groups: List[List[int]]
    ) -> ResourceRequirement:
        """Estimate peak resource requirements."""
        
        step_resources = {
            step.step_id: self._estimate_step_resources(step)
            for step in steps
        }
        
        peak_resources = ResourceRequirement()
        
        for group in parallel_groups:
            # Calculate total resources needed for this parallel group
            group_cores = sum(step_resources[step_id].cores for step_id in group)
            group_memory = sum(step_resources[step_id].memory_gb for step_id in group)
            group_disk = sum(step_resources[step_id].disk_gb for step_id in group)
            
            # Update peak if this group requires more
            peak_resources.cores = max(peak_resources.cores, group_cores)
            peak_resources.memory_gb = max(peak_resources.memory_gb, group_memory)
            peak_resources.disk_gb = max(peak_resources.disk_gb, group_disk)
        
        return peak_resources
    
    def _generate_optimization_notes(
        self,
        original_workflow: WorkflowTemplate,
        optimized_steps: List[WorkflowStep],
        parallel_groups: List[List[int]],
        strategy: OptimizationStrategy
    ) -> List[str]:
        """Generate human-readable optimization notes."""
        
        notes = []
        
        notes.append(f"Optimization strategy: {strategy.value}")
        notes.append(f"Total workflow steps: {len(optimized_steps)}")
        notes.append(f"Parallel execution groups: {len(parallel_groups)}")
        
        # Calculate parallelization efficiency
        total_steps = len(optimized_steps)
        sequential_steps = len(parallel_groups)
        if total_steps > sequential_steps:
            parallel_efficiency = (total_steps - sequential_steps) / total_steps * 100
            notes.append(f"Parallelization efficiency: {parallel_efficiency:.1f}%")
        
        # Identify bottlenecks
        group_sizes = [len(group) for group in parallel_groups]
        if max(group_sizes) > 1:
            max_parallel = max(group_sizes)
            notes.append(f"Maximum parallel steps in a group: {max_parallel}")
        
        # Resource recommendations
        peak_resources = self._estimate_peak_resources(optimized_steps, parallel_groups)
        notes.append(f"Recommended resources: {peak_resources.cores} cores, "
                    f"{peak_resources.memory_gb:.1f}GB memory, "
                    f"{peak_resources.disk_gb:.1f}GB disk")
        
        # Optimization opportunities
        if len(parallel_groups) == len(optimized_steps):
            notes.append("Note: This workflow is fully sequential - consider data parallelization")
        
        single_core_steps = [
            step for step in optimized_steps
            if self._estimate_step_resources(step).cores == 1
        ]
        if len(single_core_steps) > len(optimized_steps) * 0.5:
            notes.append("Note: Many single-core steps detected - consider multi-threading options")
        
        return notes


class WorkflowValidator:
    """Validates workflow correctness and feasibility."""
    
    def __init__(self, config: AIConfig):
        self.config = config
    
    def validate_workflow(self, workflow_template: WorkflowTemplate) -> Tuple[bool, List[str]]:
        """Validate a workflow template for correctness."""
        
        errors = []
        warnings = []
        
        # Check for circular dependencies
        if self._has_circular_dependencies(workflow_template.steps):
            errors.append("Circular dependencies detected in workflow")
        
        # Check data type compatibility
        compatibility_errors = self._check_data_type_compatibility(workflow_template.steps)
        errors.extend(compatibility_errors)
        
        # Check for missing inputs
        missing_inputs = self._check_missing_inputs(workflow_template)
        if missing_inputs:
            errors.extend([f"Missing input: {inp}" for inp in missing_inputs])
        
        # Check for orphaned steps
        orphaned_steps = self._find_orphaned_steps(workflow_template.steps)
        if orphaned_steps:
            warnings.extend([f"Orphaned step: {step}" for step in orphaned_steps])
        
        # Check resource feasibility
        resource_warnings = self._check_resource_feasibility(workflow_template.steps)
        warnings.extend(resource_warnings)
        
        is_valid = len(errors) == 0
        all_messages = errors + warnings
        
        return is_valid, all_messages
    
    def _has_circular_dependencies(self, steps: List[WorkflowStep]) -> bool:
        """Check for circular dependencies in workflow steps."""
        
        graph = nx.DiGraph()
        
        # Add nodes
        for step in steps:
            graph.add_node(step.step_id)
        
        # Add edges
        for step in steps:
            for connection in step.input_connections.values():
                source_step = connection.get('id')
                if source_step is not None:
                    graph.add_edge(source_step, step.step_id)
        
        return not nx.is_directed_acyclic_graph(graph)
    
    def _check_data_type_compatibility(self, steps: List[WorkflowStep]) -> List[str]:
        """
        Check data type compatibility between connected steps.

        Uses the tool database to validate that output formats from source steps
        are compatible with input formats expected by target steps.
        """
        errors = []
        step_map = {step.step_id: step for step in steps}

        # Cache for tool I/O types to avoid repeated DB queries
        tool_io_cache: Dict[str, Dict[str, List[str]]] = {}

        for step in steps:
            for input_name, connection in step.input_connections.items():
                source_step_id = connection.get('id')
                if source_step_id and source_step_id in step_map:
                    source_step = step_map[source_step_id]

                    # Get output types from source tool
                    source_outputs = self._get_tool_io_types(source_step.tool_id, 'outputs', tool_io_cache)

                    # Get input types expected by target tool
                    target_inputs = self._get_tool_io_types(step.tool_id, 'inputs', tool_io_cache)

                    # Check compatibility
                    if source_outputs and target_inputs:
                        if not self._types_compatible(source_outputs, target_inputs):
                            errors.append(
                                f"Type mismatch: '{source_step.tool_id}' outputs {source_outputs} "
                                f"but '{step.tool_id}' expects {target_inputs} "
                                f"(connection: step {source_step_id} → step {step.step_id})"
                            )

        return errors

    def _get_tool_io_types(
        self,
        tool_id: str,
        io_type: str,
        cache: Dict[str, Dict[str, List[str]]]
    ) -> List[str]:
        """
        Get input or output types for a tool from the database.

        Args:
            tool_id: Galaxy tool ID
            io_type: 'inputs' or 'outputs'
            cache: Cache dict to store results

        Returns:
            List of format types (e.g., ['fastq', 'fastq.gz'])
        """
        # Check cache first
        if tool_id in cache:
            return cache[tool_id].get(io_type, [])

        # Query database
        try:
            if not _DB_PATH.exists():
                log.warning(f"Tool database not found: {_DB_PATH}")
                return []

            conn = sqlite3.connect(str(_DB_PATH))
            cursor = conn.cursor()

            # Try exact match first
            cursor.execute(
                f"SELECT inputs, outputs FROM tools WHERE tool_id = ?",
                (tool_id,)
            )
            row = cursor.fetchone()

            # If not found, try partial match (for toolshed IDs)
            if not row and '/' in tool_id:
                short_id = tool_id.split('/')[-1]
                cursor.execute(
                    f"SELECT inputs, outputs FROM tools WHERE tool_id LIKE ?",
                    (f'%{short_id}%',)
                )
                row = cursor.fetchone()

            conn.close()

            if row:
                inputs_json, outputs_json = row
                inputs = json.loads(inputs_json) if inputs_json else []
                outputs = json.loads(outputs_json) if outputs_json else []

                cache[tool_id] = {'inputs': inputs, 'outputs': outputs}
                return cache[tool_id].get(io_type, [])

        except Exception as e:
            log.warning(f"Error getting I/O types for {tool_id}: {e}")

        return []

    def _types_compatible(self, source_outputs: List[str], target_inputs: List[str]) -> bool:
        """
        Check if source output types are compatible with target input types.

        Compatibility rules:
        1. Exact match (fastq == fastq)
        2. Compressed variants (fastq.gz compatible with fastq)
        3. Format families (fa, fasta are compatible)
        """
        if not source_outputs or not target_inputs:
            # If we don't have type info, assume compatible (avoid false positives)
            return True

        # Normalize types for comparison
        source_normalized = set(self._normalize_format(t) for t in source_outputs)
        target_normalized = set(self._normalize_format(t) for t in target_inputs)

        # Check for any overlap
        return bool(source_normalized.intersection(target_normalized))

    def _normalize_format(self, format_type: str) -> str:
        """
        Normalize format types for comparison.

        Examples:
            fastq.gz → fastq
            fasta → fa
            sam → sam
        """
        # Remove compression extensions
        normalized = format_type.lower()
        for ext in ['.gz', '.bz2', '.zip', '.xz']:
            if normalized.endswith(ext):
                normalized = normalized[:-len(ext)]

        # Normalize common format aliases
        format_aliases = {
            'fasta': 'fa',
            'fastq': 'fq',
            'tabular': 'tsv',
            'txt': 'text',
        }

        return format_aliases.get(normalized, normalized)
    
    def _check_missing_inputs(self, workflow_template: WorkflowTemplate) -> List[str]:
        """Check for missing workflow inputs."""
        
        missing = []
        
        # Find steps that need external inputs
        for step in workflow_template.steps:
            for input_name, connection in step.input_connections.items():
                if connection.get('id') is None:
                    # This is a workflow input
                    input_label = connection.get('output_name', input_name)
                    
                    # Check if this input is defined in workflow inputs
                    input_defined = any(
                        inp.get('name') == input_label
                        for inp in workflow_template.inputs
                    )
                    
                    if not input_defined:
                        missing.append(input_label)
        
        return missing
    
    def _find_orphaned_steps(self, steps: List[WorkflowStep]) -> List[str]:
        """Find steps that don't contribute to any workflow output."""
        
        # Build reverse dependency graph
        graph = nx.DiGraph()
        
        for step in steps:
            graph.add_node(step.step_id)
        
        for step in steps:
            for connection in step.input_connections.values():
                source_step = connection.get('id')
                if source_step is not None:
                    graph.add_edge(source_step, step.step_id)
        
        # Find nodes with no outgoing edges (potential outputs)
        output_steps = [node for node in graph.nodes() if graph.out_degree(node) == 0]
        
        # Find all steps reachable from workflow inputs
        input_steps = [node for node in graph.nodes() if graph.in_degree(node) == 0]
        
        reachable = set()
        for input_step in input_steps:
            reachable.update(nx.descendants(graph, input_step))
            reachable.add(input_step)
        
        # Steps not reachable from inputs are orphaned
        orphaned = [str(step_id) for step_id in graph.nodes() if step_id not in reachable]
        
        return orphaned
    
    def _check_resource_feasibility(self, steps: List[WorkflowStep]) -> List[str]:
        """Check if resource requirements are feasible."""
        
        warnings = []
        
        optimizer = WorkflowOptimizer(self.config)
        
        total_cores = 0
        total_memory = 0
        
        for step in steps:
            resources = optimizer._estimate_step_resources(step)
            total_cores += resources.cores
            total_memory += resources.memory_gb
            
            # Check for unusually high requirements
            if resources.cores > 16:
                warnings.append(f"Step {step.step_id} requires {resources.cores} cores")
            if resources.memory_gb > 64:
                warnings.append(f"Step {step.step_id} requires {resources.memory_gb}GB memory")
            if resources.runtime_minutes > 480:  # 8 hours
                warnings.append(f"Step {step.step_id} estimated runtime: {resources.runtime_minutes} minutes")
        
        return warnings