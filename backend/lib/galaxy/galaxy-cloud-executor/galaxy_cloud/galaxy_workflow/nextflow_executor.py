"""
Nextflow executor for running Galaxy jobs via Nextflow on AWS Batch.
"""

import asyncio
import logging
import os
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from .nextflow_converter import GalaxyToNextflowConverter


logger = logging.getLogger(__name__)


class NextflowExecutor:
    """Execute Galaxy jobs using Nextflow."""

    def __init__(
        self,
        s3_bucket: str,
        aws_region: str = "us-west-2",
        aws_batch_queue: str = None,
        nextflow_bin: str = "nextflow",
        work_dir: str = None
    ):
        """
        Initialize Nextflow executor.

        Args:
            s3_bucket: S3 bucket for data storage
            aws_region: AWS region
            aws_batch_queue: AWS Batch queue name
            nextflow_bin: Path to nextflow binary
            work_dir: Local work directory for Nextflow scripts
        """
        self.s3_bucket = s3_bucket
        self.aws_region = aws_region
        self.aws_batch_queue = aws_batch_queue or "galaxy-cloud-queue"
        self.nextflow_bin = nextflow_bin
        self.work_dir = work_dir or tempfile.mkdtemp(prefix="galaxy_nextflow_")
        self.converter = GalaxyToNextflowConverter(s3_bucket)
        self.logger = logging.getLogger(__name__)

        # Ensure work directory exists
        Path(self.work_dir).mkdir(parents=True, exist_ok=True)

    async def execute_job(
        self,
        job_wrapper,
        command_line: str,
        input_paths: List[str],
        output_paths: List[str],
        container_image: str,
        cpu: int = 2,
        memory_gb: int = 4
    ) -> Tuple[bool, str]:
        """
        Execute a Galaxy job using Nextflow.

        Args:
            job_wrapper: Galaxy job wrapper
            command_line: Tool command line
            input_paths: List of input file paths
            output_paths: List of output file paths
            container_image: Docker container image
            cpu: CPU count
            memory_gb: Memory in GB

        Returns:
            Tuple of (success, message)
        """
        job_id = job_wrapper.get_id_tag()

        try:
            # Step 1: Upload inputs to S3
            self.logger.info(f"[{job_id}] Uploading {len(input_paths)} input files to S3")
            await self._upload_inputs(job_id, input_paths)

            # Step 2: Generate Nextflow script
            self.logger.info(f"[{job_id}] Generating Nextflow script")
            nf_script = self.converter.convert_job_to_nextflow(
                job_wrapper=job_wrapper,
                command_line=command_line,
                input_paths=input_paths,
                output_paths=output_paths,
                container_image=container_image
            )

            # Step 3: Write Nextflow script to file
            script_path = Path(self.work_dir) / f"{job_id}.nf"
            script_path.write_text(nf_script)
            self.logger.info(f"[{job_id}] Nextflow script written to {script_path}")

            # Step 4: Generate Nextflow config
            config_content = self.converter.generate_nextflow_config(
                aws_region=self.aws_region,
                aws_batch_queue=self.aws_batch_queue,
                cpu=cpu,
                memory_gb=memory_gb
            )
            config_path = Path(self.work_dir) / f"{job_id}.config"
            config_path.write_text(config_content)

            # Step 5: Run Nextflow
            self.logger.info(f"[{job_id}] Launching Nextflow execution")
            success = await self._run_nextflow(job_id, script_path, config_path)

            if success:
                # Step 6: Download outputs from S3
                self.logger.info(f"[{job_id}] Downloading {len(output_paths)} output files from S3")
                await self._download_outputs(job_id, output_paths)
                return True, "Nextflow execution completed successfully"
            else:
                return False, "Nextflow execution failed"

        except Exception as e:
            self.logger.error(f"[{job_id}] Nextflow execution error: {e}", exc_info=True)
            return False, str(e)

    async def _upload_inputs(self, job_id: str, input_paths: List[str]):
        """Upload input files to S3."""
        import boto3

        s3_client = boto3.client('s3', region_name=self.aws_region)

        for input_path in input_paths:
            if not os.path.exists(input_path):
                self.logger.warning(f"Input file not found: {input_path}")
                continue

            filename = Path(input_path).name
            s3_key = f"{self.converter.s3_prefix}/{job_id}/inputs/{filename}"

            self.logger.debug(f"Uploading {input_path} to s3://{self.s3_bucket}/{s3_key}")
            s3_client.upload_file(input_path, self.s3_bucket, s3_key)

    async def _download_outputs(self, job_id: str, output_paths: List[str]):
        """Download output files from S3."""
        import boto3

        s3_client = boto3.client('s3', region_name=self.aws_region)

        for output_path in output_paths:
            filename = Path(output_path).name
            s3_key = f"{self.converter.s3_prefix}/{job_id}/results/{filename}"

            self.logger.debug(f"Downloading s3://{self.s3_bucket}/{s3_key} to {output_path}")

            try:
                # Ensure parent directory exists
                os.makedirs(os.path.dirname(output_path), exist_ok=True)
                s3_client.download_file(self.s3_bucket, s3_key, output_path)
            except Exception as e:
                self.logger.warning(f"Failed to download {s3_key}: {e}")

    async def _run_nextflow(
        self,
        job_id: str,
        script_path: Path,
        config_path: Path
    ) -> bool:
        """
        Run Nextflow pipeline.

        Args:
            job_id: Job identifier
            script_path: Path to Nextflow script
            config_path: Path to Nextflow config

        Returns:
            True if successful
        """
        # Build Nextflow command
        cmd = [
            self.nextflow_bin,
            'run',
            str(script_path),
            '-c', str(config_path),
            '-with-report',
            '-with-trace',
            '-with-timeline',
            '-ansi-log', 'false',
            '-name', job_id
        ]

        self.logger.info(f"[{job_id}] Running: {' '.join(cmd)}")

        # Run Nextflow
        log_file = Path(self.work_dir) / f"{job_id}.log"

        try:
            with open(log_file, 'w') as log_fh:
                process = await asyncio.create_subprocess_exec(
                    *cmd,
                    stdout=log_fh,
                    stderr=asyncio.subprocess.STDOUT,
                    cwd=self.work_dir
                )

                # Wait for completion
                returncode = await process.wait()

                # Read log
                log_content = log_file.read_text()
                self.logger.debug(f"[{job_id}] Nextflow log:\n{log_content}")

                if returncode == 0:
                    self.logger.info(f"[{job_id}] Nextflow completed successfully")
                    return True
                else:
                    self.logger.error(f"[{job_id}] Nextflow failed with code {returncode}")
                    self.logger.error(f"[{job_id}] Log: {log_content[-1000:]}")  # Last 1000 chars
                    return False

        except Exception as e:
            self.logger.error(f"[{job_id}] Failed to run Nextflow: {e}")
            return False

    def check_nextflow_available(self) -> bool:
        """Check if Nextflow is available."""
        try:
            result = subprocess.run(
                [self.nextflow_bin, '-version'],
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode == 0:
                self.logger.info(f"Nextflow version: {result.stdout.strip()}")
                return True
            else:
                self.logger.error(f"Nextflow check failed: {result.stderr}")
                return False
        except Exception as e:
            self.logger.error(f"Nextflow not found: {e}")
            return False
