"""
Nextflow Workflow Converter

Bidirectional conversion between Nextflow .nf format and BioMate Unified Workflow Format.

Functions:
- NextflowToUnifiedConverter: Nextflow .nf → BUWF
- UnifiedToNextflowConverter: BUWF → Nextflow .nf

Author: BioMate Team
Date: 2025-11-19
"""

import logging
from typing import Dict, List, Any, Optional
from pathlib import Path

from .base_converter import BaseConverter
from .nextflow_parser import NextflowParser, NextflowWorkflow, parse_nextflow_file
from ..workflow_abstraction import (
    UnifiedWorkflow, HighLevelStep, DetailedStep,
    DataInput, DataOutput, Parameter,
    WorkflowFormat, ExecutionEngine, ParameterType, StepCategory,
    generate_step_id, generate_workflow_id
)
from ..multi_source_dependency_converter import (
    MultiSourceDependencyConverter, InstallationMethods
)
from ..resource_resolver import ResourceResolver, ResourceRequirement

log = logging.getLogger(__name__)


class NextflowToUnifiedConverter(BaseConverter):
    """
    Convert Nextflow .nf workflow to BioMate Unified Workflow Format.

    Strategy:
    1. Parse Nextflow .nf file using NextflowParser
    2. Extract workflow metadata
    3. Convert process calls to DetailedStep objects
    4. Create high-level steps (one per process for now)
    5. Build unified workflow structure

    Note: For now, treats each process call as a separate high-level step.
    Future enhancement: Group related processes into logical steps.
    """

    def __init__(self, tool_database=None):
        """
        Initialize converter.

        Args:
            tool_database: Optional tool database for tool metadata
        """
        self.tool_database = tool_database
        self.parser = NextflowParser()

    def convert(self, nextflow_file: Path) -> UnifiedWorkflow:
        """
        Convert Nextflow .nf workflow to UnifiedWorkflow.

        Args:
            nextflow_file: Path to .nf file or NextflowWorkflow object

        Returns:
            UnifiedWorkflow instance
        """

        # Parse Nextflow file
        if isinstance(nextflow_file, Path):
            nf_workflow = self.parser.parse_file(nextflow_file)
        elif isinstance(nextflow_file, NextflowWorkflow):
            nf_workflow = nextflow_file
        else:
            raise ValueError(f"Expected Path or NextflowWorkflow, got {type(nextflow_file)}")

        # Validate
        is_valid, errors = self.validate(nf_workflow)
        if not is_valid:
            raise ValueError(f"Invalid Nextflow workflow: {', '.join(errors)}")

        # Extract metadata
        metadata = self._extract_metadata(nf_workflow)

        # Convert process calls to detailed steps
        detailed_steps = self._convert_process_calls(nf_workflow)

        # Create high-level steps (simple: one per process)
        high_level_steps = self._create_high_level_steps(
            detailed_steps,
            nf_workflow
        )

        # Build unified workflow
        workflow = UnifiedWorkflow(
            workflow_id=generate_workflow_id(),
            name=metadata["name"],
            description=metadata["description"],
            high_level_steps=high_level_steps,
            source_format=WorkflowFormat.NEXTFLOW,
            execution_engine=ExecutionEngine.NEXTFLOW,
            creator=metadata.get("creator", []),
            license=metadata.get("license", "MIT"),
            tags=metadata.get("tags", ["nextflow", "nf-core"]),
            version=metadata.get("version", "1.0"),
            source_workflow=self._nf_workflow_to_dict(nf_workflow)
        )

        # Log conversion stats
        self._log_conversion_stats(workflow)

        return workflow

    def validate(self, nf_workflow: NextflowWorkflow) -> tuple[bool, list[str]]:
        """
        Validate Nextflow workflow structure.

        Args:
            nf_workflow: NextflowWorkflow object

        Returns:
            (is_valid, error_messages)
        """
        errors = []

        if not nf_workflow.name:
            errors.append("Workflow has no name")

        if not nf_workflow.process_calls:
            errors.append("Workflow has no process calls")

        return (len(errors) == 0, errors)

    def _extract_metadata(self, nf_workflow: NextflowWorkflow) -> Dict[str, Any]:
        """Extract workflow metadata."""
        return {
            "name": nf_workflow.name,
            "description": nf_workflow.description,
            "creator": [{
                "class": "Organization",
                "name": "nf-core",
                "url": "https://nf-co.re"
            }],
            "license": "MIT",
            "tags": ["nextflow", "nf-core"],
            "version": "1.0"
        }

    def _convert_process_calls(
        self,
        nf_workflow: NextflowWorkflow
    ) -> List[DetailedStep]:
        """
        Convert Nextflow process calls to DetailedStep objects.

        Args:
            nf_workflow: Parsed Nextflow workflow

        Returns:
            List of DetailedStep objects
        """
        detailed_steps = []

        for idx, process_call in enumerate(nf_workflow.process_calls):
            # Create detailed step
            detailed_step = DetailedStep(
                step_id=generate_step_id("nf_step"),
                tool_id=f"nfcore_{process_call.process_name.lower()}",
                tool_name=self._format_process_name(process_call.process_name),
                tool_version="",
                description=f"{process_call.process_name} process",
                inputs=self._convert_inputs(process_call.inputs, nf_workflow),
                outputs=[],  # Outputs inferred from emit section
                source_step_id=str(idx),
                source_format=WorkflowFormat.NEXTFLOW,
                annotation=f"Process: {process_call.process_name}",
                label=process_call.process_name
            )

            detailed_steps.append(detailed_step)

        return detailed_steps

    def _convert_inputs(
        self,
        input_names: List[str],
        nf_workflow: NextflowWorkflow
    ) -> List[DataInput]:
        """
        Convert Nextflow process inputs to DataInput objects.

        Args:
            input_names: List of input channel/variable names
            nf_workflow: Nextflow workflow (for context)

        Returns:
            List of DataInput objects
        """
        inputs = []

        for input_name in input_names:
            # Clean up input name
            clean_name = input_name.strip()

            # Check if this is a workflow input or process output
            is_workflow_input = any(
                inp.name == clean_name for inp in nf_workflow.inputs
            )

            if is_workflow_input:
                # Find the input definition
                inp_def = next(
                    (inp for inp in nf_workflow.inputs if inp.name == clean_name),
                    None
                )
                description = inp_def.description if inp_def else ""
                data_type = inp_def.data_type if inp_def else ""
            else:
                # This is an output from a previous process
                description = f"Output from previous step"
                data_type = ""

                # Try to infer source from pattern like "PROCESS.out.name"
                if '.out.' in clean_name:
                    parts = clean_name.split('.out.')
                    source_process = parts[0]
                    output_name = parts[1] if len(parts) > 1 else ""
                    description = f"Output '{output_name}' from {source_process}"

            inputs.append(DataInput(
                name=clean_name,
                description=description,
                data_type=data_type,
                source=clean_name if not is_workflow_input else ""
            ))

        return inputs

    def _create_high_level_steps(
        self,
        detailed_steps: List[DetailedStep],
        nf_workflow: NextflowWorkflow
    ) -> List[HighLevelStep]:
        """
        Create high-level steps from detailed steps.

        For now, creates one high-level step per process.
        Future enhancement: Group related processes.

        Args:
            detailed_steps: List of DetailedStep objects
            nf_workflow: Nextflow workflow (for context)

        Returns:
            List of HighLevelStep objects
        """
        high_level_steps = []

        for idx, detailed_step in enumerate(detailed_steps):
            high_level_step = HighLevelStep(
                step_id=generate_step_id("nf_hl"),
                name=detailed_step.tool_name,
                description=detailed_step.description,
                detailed_steps=[detailed_step],
                inputs=detailed_step.inputs,
                outputs=detailed_step.outputs,
                category=self._infer_category(detailed_step.tool_name),
                icon=self._get_category_icon(
                    self._infer_category(detailed_step.tool_name)
                ),
                color=self._get_category_color(
                    self._infer_category(detailed_step.tool_name)
                ),
                order=idx
            )

            high_level_steps.append(high_level_step)

        return high_level_steps

    def _format_process_name(self, process_name: str) -> str:
        """
        Format Nextflow process name for display.

        Examples:
        - SAMTOOLS_SORT → Samtools Sort
        - BAM_STATS_SAMTOOLS → BAM Stats Samtools
        """
        # Replace underscores with spaces
        formatted = process_name.replace('_', ' ')

        # Title case
        formatted = formatted.title()

        return formatted

    def _infer_category(self, tool_name: str) -> StepCategory:
        """Infer step category from tool name."""
        name_lower = tool_name.lower()

        if any(kw in name_lower for kw in ['qc', 'quality', 'fastqc', 'multiqc']):
            return StepCategory.QC
        elif any(kw in name_lower for kw in ['align', 'map', 'bwa', 'bowtie', 'star']):
            return StepCategory.ALIGNMENT
        elif any(kw in name_lower for kw in ['count', 'quant', 'salmon', 'kallisto']):
            return StepCategory.QUANTIFICATION
        elif any(kw in name_lower for kw in ['sort', 'index', 'stats', 'samtools']):
            return StepCategory.ALIGNMENT  # Post-alignment processing
        elif any(kw in name_lower for kw in ['variant', 'call', 'vcf']):
            return StepCategory.VARIANT_CALLING
        elif any(kw in name_lower for kw in ['peak', 'macs', 'chip']):
            return StepCategory.PEAK_CALLING
        elif any(kw in name_lower for kw in ['filter', 'trim']):
            return StepCategory.FILTERING
        else:
            return StepCategory.OTHER

    def _get_category_icon(self, category: StepCategory) -> str:
        """Get icon for category."""
        icon_map = {
            StepCategory.QC: "🔍",
            StepCategory.ALIGNMENT: "🧬",
            StepCategory.QUANTIFICATION: "📊",
            StepCategory.DIFFERENTIAL_EXPRESSION: "📈",
            StepCategory.VARIANT_CALLING: "🔬",
            StepCategory.PEAK_CALLING: "⛰️",
            StepCategory.ASSEMBLY: "🧩",
            StepCategory.ANNOTATION: "📝",
            StepCategory.FILTERING: "🔧",
            StepCategory.NORMALIZATION: "📐",
            StepCategory.VISUALIZATION: "📊",
            StepCategory.OTHER: "🔧"
        }
        return icon_map.get(category, "🔧")

    def _get_category_color(self, category: StepCategory) -> str:
        """Get color for category."""
        color_map = {
            StepCategory.QC: "#3498db",
            StepCategory.ALIGNMENT: "#2ecc71",
            StepCategory.QUANTIFICATION: "#9b59b6",
            StepCategory.DIFFERENTIAL_EXPRESSION: "#e74c3c",
            StepCategory.VARIANT_CALLING: "#f39c12",
            StepCategory.PEAK_CALLING: "#1abc9c",
            StepCategory.ASSEMBLY: "#34495e",
            StepCategory.ANNOTATION: "#16a085",
            StepCategory.FILTERING: "#27ae60",
            StepCategory.NORMALIZATION: "#2980b9",
            StepCategory.VISUALIZATION: "#8e44ad",
            StepCategory.OTHER: "#6c757d"
        }
        return color_map.get(category, "#6c757d")

    def _nf_workflow_to_dict(self, nf_workflow: NextflowWorkflow) -> Dict[str, Any]:
        """Convert NextflowWorkflow to dict for storage."""
        return {
            "name": nf_workflow.name,
            "description": nf_workflow.description,
            "inputs": [
                {
                    "name": inp.name,
                    "type": inp.type,
                    "description": inp.description,
                    "data_type": inp.data_type
                }
                for inp in nf_workflow.inputs
            ],
            "outputs": [
                {
                    "name": out.name,
                    "type": out.type,
                    "description": out.description,
                    "data_type": out.data_type
                }
                for out in nf_workflow.outputs
            ],
            "process_calls": [
                {
                    "process_name": pc.process_name,
                    "inputs": pc.inputs,
                    "outputs": pc.outputs,
                    "line_number": pc.line_number
                }
                for pc in nf_workflow.process_calls
            ],
            "includes": [
                {
                    "items": inc.items,
                    "source": inc.source
                }
                for inc in nf_workflow.includes
            ]
        }


class UnifiedToNextflowConverter(BaseConverter):
    """
    Convert BioMate Unified Workflow to Nextflow .nf format.

    Strategy:
    1. Generate workflow header and includes
    2. Create process definitions for each detailed step
    3. Generate workflow body (take, main, emit sections)
    4. Output .nf script and config files

    Returns:
    - Dict with "main.nf", "nextflow.config", and module files
    """

    def __init__(self, nfcore_base_dir: Optional[Path] = None,
                 galaxy_tools_dir: Optional[Path] = None,
                 tool_database=None):
        """
        Initialize converter with dependency and resource resolvers.

        Args:
            nfcore_base_dir: Path to nf-core workflows for enrichment
            galaxy_tools_dir: Path to Galaxy shed_tools for resource hints
            tool_database: Optional tool database for tool metadata
        """
        self.tool_database = tool_database
        self.dependency_converter = MultiSourceDependencyConverter(
            nfcore_base_dir=nfcore_base_dir
        )
        self.resource_resolver = ResourceResolver(
            nfcore_base_dir=nfcore_base_dir,
            galaxy_tools_dir=galaxy_tools_dir
        )

    def convert(self, unified_workflow: UnifiedWorkflow) -> Dict[str, str]:
        """
        Convert UnifiedWorkflow to Nextflow .nf format.

        Args:
            unified_workflow: UnifiedWorkflow instance

        Returns:
            Dict with file names and contents:
            {
                "main.nf": "workflow content",
                "nextflow.config": "config content",
                "modules/process1.nf": "process def",
                ...
            }
        """

        # Validate
        is_valid, errors = unified_workflow.validate()
        if not is_valid:
            raise ValueError(f"Invalid unified workflow: {', '.join(errors)}")

        # Generate main workflow file
        main_nf = self._generate_main_workflow(unified_workflow)

        # Generate config file
        config_nf = self._generate_config(unified_workflow)

        # Generate process modules (optional, for modularity)
        modules = self._generate_process_modules(unified_workflow)

        result = {
            "main.nf": main_nf,
            "nextflow.config": config_nf,
            **modules
        }

        log.info(f"Generated Nextflow workflow: {len(result)} files")

        return result

    def validate(self, unified_workflow: UnifiedWorkflow) -> tuple[bool, list[str]]:
        """Validate unified workflow before conversion."""
        return unified_workflow.validate()

    def _generate_main_workflow(self, workflow: UnifiedWorkflow) -> str:
        """
        Generate main Nextflow workflow file.

        Template:
        ```
        //
        // Workflow description
        //

        include { PROCESS1 } from './modules/process1'
        include { PROCESS2 } from './modules/process2'

        workflow WORKFLOW_NAME {
            take:
            input1
            input2

            main:
            ch_versions = Channel.empty()

            PROCESS1 ( input1 )
            PROCESS2 ( PROCESS1.out.output1, input2 )

            emit:
            output1 = PROCESS2.out.result
            versions = ch_versions
        }
        ```
        """

        # Header
        header = f"//\n// {workflow.description}\n//\n\n"

        # Generate includes
        includes = self._generate_includes(workflow)

        # Generate workflow block
        workflow_name = workflow.name.upper().replace(' ', '_').replace('-', '_')
        take_section = self._generate_take_section(workflow)
        main_section = self._generate_main_section(workflow)
        emit_section = self._generate_emit_section(workflow)

        workflow_block = f"""
workflow {workflow_name} {{
    take:
{take_section}

    main:
    ch_versions = Channel.empty()

{main_section}

    emit:
{emit_section}
}}
"""

        return header + includes + workflow_block

    def _generate_includes(self, workflow: UnifiedWorkflow) -> str:
        """Generate include statements for all processes."""
        includes = []

        # Get all detailed steps
        for hl_step in workflow.high_level_steps:
            for detailed_step in hl_step.detailed_steps:
                process_name = detailed_step.tool_name.upper().replace(' ', '_')
                module_path = f"./modules/{detailed_step.tool_id}"

                includes.append(
                    f"include {{ {process_name} }} from '{module_path}'"
                )

        return '\n'.join(includes) + '\n\n' if includes else ''

    def _generate_take_section(self, workflow: UnifiedWorkflow) -> str:
        """Generate take: section with workflow inputs."""
        inputs = []

        # Collect all unique inputs from first high-level step
        if workflow.high_level_steps:
            first_step = workflow.high_level_steps[0]
            for inp in first_step.inputs:
                inputs.append(f"    {inp.name}  // {inp.description}")

        return '\n'.join(inputs) if inputs else '    // No inputs'

    def _generate_main_section(self, workflow: UnifiedWorkflow) -> str:
        """Generate main: section with process calls."""
        calls = []

        for hl_step in workflow.high_level_steps:
            for detailed_step in hl_step.detailed_steps:
                # Generate process call
                process_name = detailed_step.tool_name.upper().replace(' ', '_')

                # Get input names
                input_names = [inp.name for inp in detailed_step.inputs]
                inputs_str = ', '.join(input_names)

                # Generate call
                call = f"    {process_name} ( {inputs_str} )"
                calls.append(call)

                # Mix versions
                calls.append(
                    f"    ch_versions = ch_versions.mix({process_name}.out.versions.first())"
                )
                calls.append("")  # Empty line

        return '\n'.join(calls) if calls else '    // No process calls'

    def _generate_emit_section(self, workflow: UnifiedWorkflow) -> str:
        """Generate emit: section with workflow outputs."""
        emits = []

        # Get outputs from last high-level step
        if workflow.high_level_steps:
            last_step = workflow.high_level_steps[-1]
            if last_step.detailed_steps:
                last_tool = last_step.detailed_steps[-1]
                process_name = last_tool.tool_name.upper().replace(' ', '_')

                # Generate output emits
                for out in last_tool.outputs:
                    emits.append(
                        f"    {out.name} = {process_name}.out.{out.name}"
                    )

        # Always emit versions
        emits.append("    versions = ch_versions")

        return '\n'.join(emits) if emits else '    versions = ch_versions'

    def _generate_config(self, workflow: UnifiedWorkflow) -> str:
        """
        Generate nextflow.config file with resource selectors.

        Includes nf-core style resource labels:
        - process_single: 1 CPU, 6GB RAM
        - process_low: 2 CPUs, 12GB RAM
        - process_medium: 6 CPUs, 36GB RAM
        - process_high: 12 CPUs, 72GB RAM
        - process_high_memory: 12 CPUs, 200GB RAM
        """

        config = f"""
// Nextflow configuration for {workflow.name}

params {{
    // Workflow parameters
    outdir = 'results'

    // Resource limits (can be overridden)
    max_cpus = 16
    max_memory = '128.GB'
    max_time = '240.h'
}}

process {{
    // Default resource requirements
    cpus = 2
    memory = '4.GB'
    time = '2.h'

    // Error strategy
    errorStrategy = 'retry'
    maxRetries = 2

    // Resource selectors (nf-core style)
    withLabel: process_single {{
        cpus = 1
        memory = 6.GB
        time = 4.h
    }}

    withLabel: process_low {{
        cpus = 2
        memory = 12.GB
        time = 4.h
    }}

    withLabel: process_medium {{
        cpus = 6
        memory = 36.GB
        time = 8.h
    }}

    withLabel: process_high {{
        cpus = 12
        memory = 72.GB
        time = 16.h
    }}

    withLabel: process_high_memory {{
        cpus = 12
        memory = 200.GB
        time = 16.h
    }}
}}

profiles {{
    conda {{
        conda.enabled = true
        conda.useMamba = true
    }}

    docker {{
        docker.enabled = true
        docker.runOptions = '-u $(id -u):$(id -g)'
    }}

    singularity {{
        singularity.enabled = true
        singularity.autoMounts = true
    }}

    aws_batch {{
        process.executor = 'awsbatch'
        process.queue = 'galaxy-cloud-queue'
        aws.region = 'us-west-2'
        workDir = 's3://galaxy-cloud-data/nextflow-work'
    }}
}}
"""
        return config

    def _generate_process_modules(
        self,
        workflow: UnifiedWorkflow
    ) -> Dict[str, str]:
        """
        Generate process module files for each tool.

        Returns dict of:
        {
            "modules/tool_id/main.nf": "process definition",
            "modules/tool_id/environment.yml": "conda environment"
        }
        """
        modules = {}

        for hl_step in workflow.high_level_steps:
            for detailed_step in hl_step.detailed_steps:
                # Generate process definition
                module_path = f"modules/{detailed_step.tool_id}/main.nf"
                module_content = self._generate_process_definition(detailed_step)
                modules[module_path] = module_content

                # Generate environment.yml for conda
                env_path = f"modules/{detailed_step.tool_id}/environment.yml"
                env_content = self._generate_environment_yml(detailed_step)
                if env_content:
                    modules[env_path] = env_content

        return modules

    def _generate_environment_yml(self, detailed_step: DetailedStep) -> str:
        """
        Generate environment.yml file for a tool's conda environment.

        Returns empty string if no conda spec available.
        """
        # Get tool requirements
        requirements = []
        if detailed_step.tool_name:
            req = {
                'name': detailed_step.tool_name.lower().replace(' ', '-'),
                'type': 'package'
            }
            if detailed_step.tool_version:
                req['version'] = detailed_step.tool_version
            requirements.append(req)

        # Get installation methods
        install_methods = self.dependency_converter.convert(
            galaxy_requirements=requirements,
            tool_name=detailed_step.tool_name,
            tool_id=detailed_step.tool_id
        )

        # Generate environment.yml
        if install_methods.conda:
            return self.dependency_converter.generate_environment_yml(install_methods)

        return ""

    def _generate_process_definition(self, detailed_step: DetailedStep) -> str:
        """
        Generate Nextflow process definition for a tool using multi-source approach.

        Uses MultiSourceDependencyConverter to generate all installation methods:
        - Conda (primary, default)
        - Containers (Docker/Singularity)
        - Modules (environment modules)

        Uses ResourceResolver to determine proper resource requirements:
        - From nf-core modules (highest confidence)
        - From Galaxy XML (GALAXY_SLOTS hints)
        - From category inference
        - Default fallback
        """

        process_name = detailed_step.tool_name.upper().replace(' ', '_')

        # 1. Get tool requirements from detailed_step
        # Try to construct Galaxy-style requirements from available info
        requirements = []
        if detailed_step.tool_name:
            req = {
                'name': detailed_step.tool_name.lower().replace(' ', '-'),
                'type': 'package'
            }
            if detailed_step.tool_version:
                req['version'] = detailed_step.tool_version
            requirements.append(req)

        # 2. Get all installation methods using MultiSourceDependencyConverter
        install_methods = self.dependency_converter.convert(
            galaxy_requirements=requirements,
            tool_name=detailed_step.tool_name,
            tool_id=detailed_step.tool_id
        )

        # 3. Get resource requirements using ResourceResolver
        # Try to infer category from step category or tool name
        category = None
        if hasattr(detailed_step, 'category'):
            category = str(detailed_step.category).lower()

        resource_req = self.resource_resolver.resolve(
            tool_name=detailed_step.tool_name,
            tool_id=detailed_step.tool_id,
            category=category
        )

        # 4. Generate installation directives (conda + container)
        # Override conda path to use moduleDir
        if install_methods.conda:
            # Use environment.yml in module directory
            install_methods.conda = "${moduleDir}/environment.yml"

        directives = self.dependency_converter.generate_nextflow_directives(
            install_methods,
            prefer='conda'
        )

        # 5. Generate input spec
        input_lines = []
        for inp in detailed_step.inputs:
            input_lines.append(f"    tuple val(meta), path({inp.name})")

        # 6. Generate output spec
        output_lines = []
        for out in detailed_step.outputs:
            output_lines.append(
                f"    tuple val(meta), path('*.{out.name}'), emit: {out.name}"
            )
        output_lines.append("    path 'versions.yml', emit: versions")

        # 7. Build process definition with all directives
        process_def = f'''
process {process_name} {{
    tag "$meta.id"
    label '{resource_req.label}'

{directives}

    input:
{chr(10).join(input_lines) if input_lines else "    // No inputs"}

    output:
{chr(10).join(output_lines)}

    script:
    """
    # Tool execution would go here
    # Resource: {resource_req.cpus} CPUs, {resource_req.memory_gb}GB RAM
    # Confidence: {resource_req.confidence:.2f} ({resource_req.source})
    echo "Running {detailed_step.tool_name}" > output.txt

    cat <<-END_VERSIONS > versions.yml
    "${{task.process}}":
        {detailed_step.tool_name.lower()}: \\$(echo "{detailed_step.tool_version or "1.0.0"}")
    END_VERSIONS
    """
}}
'''

        return process_def
