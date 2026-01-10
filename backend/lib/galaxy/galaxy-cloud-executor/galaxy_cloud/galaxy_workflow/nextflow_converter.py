"""
Convert Galaxy workflows to Nextflow DSL for cloud execution.
"""

import logging
import json
from typing import Dict, List, Any, Tuple
from pathlib import Path


logger = logging.getLogger(__name__)


class GalaxyToNextflowConverter:
    """Convert Galaxy workflow to Nextflow pipeline."""

    def __init__(self, s3_bucket: str, s3_prefix: str = "galaxy-workflows"):
        """
        Initialize converter.

        Args:
            s3_bucket: S3 bucket for storing data
            s3_prefix: Prefix for S3 paths
        """
        self.s3_bucket = s3_bucket
        self.s3_prefix = s3_prefix
        self.logger = logging.getLogger(__name__)

    def convert_job_to_nextflow(
        self,
        job_wrapper,
        command_line: str,
        input_paths: List[str],
        output_paths: List[str],
        container_image: str
    ) -> str:
        """
        Convert a Galaxy job to Nextflow process.

        Args:
            job_wrapper: Galaxy job wrapper
            command_line: Tool command line
            input_paths: List of input file paths
            output_paths: List of output file paths
            container_image: Docker container image

        Returns:
            Nextflow DSL script content
        """
        job_id = job_wrapper.get_id_tag()
        tool_id = job_wrapper.tool.id if job_wrapper.tool else 'unknown'

        # Generate Nextflow script
        nf_script = self._generate_nextflow_process(
            job_id=job_id,
            tool_id=tool_id,
            command_line=command_line,
            input_paths=input_paths,
            output_paths=output_paths,
            container_image=container_image
        )

        return nf_script

    def _generate_nextflow_process(
        self,
        job_id: str,
        tool_id: str,
        command_line: str,
        input_paths: List[str],
        output_paths: List[str],
        container_image: str
    ) -> str:
        """Generate Nextflow process definition."""

        # Create input channel definitions
        input_declarations = []
        input_params = []
        for i, path in enumerate(input_paths):
            input_name = f"input_file_{i}"
            input_declarations.append(f"    path {input_name}")
            input_params.append(input_name)

        # Create output declarations
        output_declarations = []
        output_patterns = []
        for i, path in enumerate(output_paths):
            output_name = f"output_file_{i}"
            # Extract filename pattern
            filename = Path(path).name
            output_declarations.append(f"    path '{filename}', emit: {output_name}")
            output_patterns.append(filename)

        # Build Nextflow script
        nf_script = f"""
#!/usr/bin/env nextflow

nextflow.enable.dsl=2

// Parameters
params.outdir = "s3://{self.s3_bucket}/{self.s3_prefix}/{job_id}/results"
params.workdir = "s3://{self.s3_bucket}/{self.s3_prefix}/{job_id}/work"

// Process definition
process {tool_id.replace('-', '_').replace('.', '_')} {{
    container '{container_image}'
    publishDir params.outdir, mode: 'copy'

    input:
{chr(10).join(input_declarations) if input_declarations else '    val ready'}

    output:
{chr(10).join(output_declarations) if output_declarations else '    path "*.out"'}

    script:
    \"\"\"
    {self._adapt_command_for_nextflow(command_line, input_params, output_patterns)}
    \"\"\"
}}

// Workflow
workflow {{
    // Create input channels
"""

        # Add input channel creation
        if input_paths:
            nf_script += "    // Input files\n"
            for i, path in enumerate(input_paths):
                input_name = f"input_file_{i}"
                # Nextflow will stage these from S3 automatically
                nf_script += f"    {input_name}_ch = Channel.fromPath('s3://{self.s3_bucket}/{self.s3_prefix}/{job_id}/inputs/{Path(path).name}')\n"

            # Combine inputs if multiple
            if len(input_paths) > 1:
                combined_inputs = ", ".join([f"input_file_{i}_ch" for i in range(len(input_paths))])
                nf_script += f"    \n    // Run process\n"
                nf_script += f"    {tool_id.replace('-', '_').replace('.', '_')}({combined_inputs})\n"
            else:
                nf_script += f"    \n    // Run process\n"
                nf_script += f"    {tool_id.replace('-', '_').replace('.', '_')}(input_file_0_ch)\n"
        else:
            nf_script += "    // No inputs\n"
            nf_script += f"    ready_ch = Channel.of(true)\n"
            nf_script += f"    {tool_id.replace('-', '_').replace('.', '_')}(ready_ch)\n"

        nf_script += "}\n"

        return nf_script

    def _adapt_command_for_nextflow(
        self,
        command_line: str,
        input_params: List[str],
        output_patterns: List[str]
    ) -> str:
        """
        Adapt Galaxy command line for Nextflow execution.

        Nextflow automatically stages input files and handles outputs,
        so we just need to adjust paths.
        """
        # Nextflow stages files in the work directory
        # Input files are available by their parameter names
        adapted_command = command_line

        # Note: Nextflow will handle file staging automatically
        # We don't need to rewrite paths - Nextflow uses symlinks

        return adapted_command

    def generate_nextflow_config(
        self,
        aws_region: str = "us-west-2",
        aws_batch_queue: str = None,
        cpu: int = 2,
        memory_gb: int = 4
    ) -> str:
        """
        Generate Nextflow configuration for AWS Batch.

        Args:
            aws_region: AWS region
            aws_batch_queue: AWS Batch queue name
            cpu: Default CPU count
            memory_gb: Default memory in GB

        Returns:
            Nextflow config content
        """
        config = f"""
// Nextflow configuration for AWS Batch execution

params {{
    outdir = "s3://{self.s3_bucket}/{self.s3_prefix}/results"
}}

process {{
    executor = 'awsbatch'
    queue = '{aws_batch_queue or "galaxy-cloud-queue"}'
    cpus = {cpu}
    memory = '{memory_gb} GB'

    // Error strategy
    errorStrategy = 'retry'
    maxRetries = 2
}}

aws {{
    region = '{aws_region}'
    batch {{
        cliPath = '/home/ec2-user/miniconda/bin/aws'
        jobRole = 'arn:aws:iam::YOUR_ACCOUNT:role/BatchJobRole'
        volumes = '/tmp'
    }}
}}

// S3 work directory
workDir = "s3://{self.s3_bucket}/{self.s3_prefix}/work"

// Docker settings
docker {{
    enabled = true
}}

// Trace and reporting
trace {{
    enabled = true
    file = "s3://{self.s3_bucket}/{self.s3_prefix}/trace.txt"
}}

report {{
    enabled = true
    file = "s3://{self.s3_bucket}/{self.s3_prefix}/report.html"
}}

timeline {{
    enabled = true
    file = "s3://{self.s3_bucket}/{self.s3_prefix}/timeline.html"
}}
"""
        return config
