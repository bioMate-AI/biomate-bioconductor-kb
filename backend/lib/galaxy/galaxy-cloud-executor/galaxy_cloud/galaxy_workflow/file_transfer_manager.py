"""
File Transfer Manager for Galaxy Cloud Execution.

Handles file uploads/downloads between local Galaxy storage and S3,
and rewrites commands to use container-appropriate paths.
"""
import os
import re
import logging
from pathlib import Path
from typing import Dict, List, Tuple, Optional
from dataclasses import dataclass, field

try:
    import boto3
    HAS_BOTO3 = True
except ImportError:
    HAS_BOTO3 = False


@dataclass
class FileMapping:
    """Maps a local file to its cloud storage location"""
    local_path: str
    s3_uri: str
    container_path: str
    is_input: bool
    is_output: bool
    is_directory: bool = False


class SimpleS3Storage:
    """Simple synchronous S3 storage wrapper using boto3."""

    def __init__(self, logger=None):
        """Initialize S3 storage with boto3 client."""
        if not HAS_BOTO3:
            raise ImportError("boto3 is required for S3 storage. Install with: pip install boto3")

        self.s3_client = boto3.client('s3')
        self.logger = logger or logging.getLogger(__name__)

    def upload_file(self, local_path: str, bucket: str, key: str):
        """Upload a file to S3."""
        self.logger.debug(f"S3: Uploading {local_path} to s3://{bucket}/{key}")
        self.s3_client.upload_file(local_path, bucket, key)

    def download_file(self, bucket: str, key: str, local_path: str):
        """Download a file from S3."""
        self.logger.debug(f"S3: Downloading s3://{bucket}/{key} to {local_path}")
        self.s3_client.download_file(bucket, key, local_path)

    def delete_prefix(self, bucket: str, prefix: str):
        """Delete all files under a prefix."""
        self.logger.debug(f"S3: Deleting s3://{bucket}/{prefix}/*")

        # List objects with prefix
        paginator = self.s3_client.get_paginator('list_objects_v2')
        pages = paginator.paginate(Bucket=bucket, Prefix=prefix)

        # Delete in batches
        for page in pages:
            if 'Contents' in page:
                objects = [{'Key': obj['Key']} for obj in page['Contents']]
                if objects:
                    self.s3_client.delete_objects(
                        Bucket=bucket,
                        Delete={'Objects': objects}
                    )


class FileTransferManager:
    """
    Manages file transfers and path translation for cloud workflow execution.

    Responsibilities:
    1. Upload input files to S3
    2. Rewrite command paths from local to container paths
    3. Download output files from S3 back to local storage
    """

    def __init__(self, s3_bucket: str, job_id: str, storage_provider=None, logger=None):
        """
        Initialize the file transfer manager.

        Args:
            s3_bucket: S3 bucket name for staging files
            job_id: Unique job identifier for this execution
            storage_provider: Optional cloud storage provider instance.
                            If None, creates a SimpleS3Storage instance.
            logger: Logger instance
        """
        self.s3_bucket = s3_bucket
        self.job_id = job_id
        self.logger = logger or logging.getLogger(__name__)

        # Create storage provider if not provided
        if storage_provider is None:
            self.logger.debug("Creating SimpleS3Storage for file transfers")
            self.storage = SimpleS3Storage(logger=self.logger)
        else:
            self.storage = storage_provider

        # Track file mappings
        self.file_mappings: Dict[str, FileMapping] = {}

        # S3 staging paths
        self.s3_staging_prefix = f"workflows/{job_id}"
        self.s3_inputs_prefix = f"{self.s3_staging_prefix}/inputs"
        self.s3_outputs_prefix = f"{self.s3_staging_prefix}/outputs"

        # Container working directory
        self.container_workdir = "/galaxy/work"
        self.container_inputs_dir = f"{self.container_workdir}/inputs"
        self.container_outputs_dir = f"{self.container_workdir}/outputs"

    def prepare_job(self, job_wrapper, command_line: str) -> Tuple[str, List[str], List[str]]:
        """
        Prepare a job for cloud execution.

        Args:
            job_wrapper: Galaxy job wrapper
            command_line: Original Galaxy command line with local paths

        Returns:
            Tuple of:
            - Rewritten command line with container paths
            - List of S3 URIs for input files
            - List of S3 URIs for expected output files
        """
        self.logger.info(f"Preparing job {self.job_id} for cloud execution")

        # Step 1: Extract file paths from command and job wrapper
        input_paths, output_paths = self._extract_paths_from_job(command_line, job_wrapper)

        self.logger.info(f"Found {len(input_paths)} input files and {len(output_paths)} output paths")

        # Step 2: Upload input files to S3 and create mappings
        input_s3_uris = self._upload_input_files(input_paths)

        # Step 3: Create output file mappings (not uploaded yet)
        output_s3_uris = self._prepare_output_mappings(output_paths)

        # Step 4: Rewrite command with container paths
        rewritten_command = self._rewrite_command_paths(command_line)

        # Step 5: Wrap command with setup and cleanup
        final_command = self._wrap_command_with_transfers(rewritten_command)

        self.logger.info(f"Job preparation complete. Command rewritten with {len(self.file_mappings)} file mappings")

        return final_command, input_s3_uris, output_s3_uris

    def _extract_paths_from_job(self, command_line: str, job_wrapper) -> Tuple[List[str], List[str]]:
        """
        Extract input and output file paths from the Galaxy job.

        Args:
            command_line: The command line to parse
            job_wrapper: Galaxy job wrapper with input/output info

        Returns:
            Tuple of (input_paths, output_paths)
        """
        input_paths = []
        output_paths = []

        # Get job object
        job = job_wrapper.get_job()

        # Extract input file paths from input datasets
        for input_assoc in job.input_datasets:
            dataset = input_assoc.dataset
            if dataset and dataset.dataset:
                try:
                    file_path = dataset.dataset.get_file_name()
                    if file_path and os.path.exists(file_path):
                        input_paths.append(file_path)
                        self.logger.debug(f"Found input file: {file_path}")
                except Exception as e:
                    self.logger.warning(f"Could not get file path for input dataset: {e}")

        # Extract output file paths from output datasets
        for output_assoc in job.output_datasets:
            dataset = output_assoc.dataset
            if dataset and dataset.dataset:
                try:
                    file_path = dataset.dataset.get_file_name()
                    if file_path:
                        output_paths.append(file_path)
                        self.logger.debug(f"Found output file: {file_path}")

                        # Also check for extra files directory (e.g., FastQC _files)
                        extra_files_path = dataset.dataset.extra_files_path
                        if extra_files_path:
                            output_paths.append(extra_files_path)
                            self.logger.debug(f"Found output directory: {extra_files_path}")
                except Exception as e:
                    self.logger.warning(f"Could not get file path for output dataset: {e}")

        return input_paths, output_paths

    def _upload_input_files(self, input_paths: List[str]) -> List[str]:
        """
        Upload input files to S3 and create file mappings.

        Args:
            input_paths: List of local file paths to upload

        Returns:
            List of S3 URIs for uploaded files
        """
        s3_uris = []

        for i, local_path in enumerate(input_paths):
            if not os.path.exists(local_path):
                self.logger.warning(f"Input file does not exist: {local_path}")
                continue

            # Generate S3 key and paths
            filename = os.path.basename(local_path)
            s3_key = f"{self.s3_inputs_prefix}/input_{i}_{filename}"
            s3_uri = f"s3://{self.s3_bucket}/{s3_key}"
            container_path = f"{self.container_inputs_dir}/{filename}"

            # Upload file to S3
            self.logger.info(f"Uploading: {local_path} -> {s3_uri}")
            try:
                self.storage.upload_file(local_path, self.s3_bucket, s3_key)

                # Create mapping
                self.file_mappings[local_path] = FileMapping(
                    local_path=local_path,
                    s3_uri=s3_uri,
                    container_path=container_path,
                    is_input=True,
                    is_output=False,
                    is_directory=False
                )

                s3_uris.append(s3_uri)
                self.logger.info(f"Uploaded successfully")

            except Exception as e:
                self.logger.error(f"Failed to upload {local_path}: {e}")
                raise

        return s3_uris

    def _prepare_output_mappings(self, output_paths: List[str]) -> List[str]:
        """
        Create file mappings for output files (not uploaded yet).

        Args:
            output_paths: List of expected output file paths

        Returns:
            List of S3 URIs where outputs will be stored
        """
        s3_uris = []

        for i, local_path in enumerate(output_paths):
            # Determine if it's a directory or file
            is_directory = local_path.endswith('_files') or os.path.isdir(local_path)

            # Generate S3 key and paths
            basename = os.path.basename(local_path)
            s3_key = f"{self.s3_outputs_prefix}/output_{i}_{basename}"
            s3_uri = f"s3://{self.s3_bucket}/{s3_key}"
            container_path = f"{self.container_outputs_dir}/{basename}"

            # Create mapping
            self.file_mappings[local_path] = FileMapping(
                local_path=local_path,
                s3_uri=s3_uri,
                container_path=container_path,
                is_input=False,
                is_output=True,
                is_directory=is_directory
            )

            s3_uris.append(s3_uri)
            self.logger.debug(f"Prepared output mapping: {local_path} -> {s3_uri}")

        return s3_uris

    def _rewrite_command_paths(self, command_line: str) -> str:
        """
        Rewrite file paths in the command from local paths to container paths.

        Args:
            command_line: Original command with local paths

        Returns:
            Rewritten command with container paths
        """
        rewritten = command_line

        # Sort mappings by path length (longest first) to avoid partial replacements
        sorted_mappings = sorted(
            self.file_mappings.items(),
            key=lambda x: len(x[0]),
            reverse=True
        )

        for local_path, mapping in sorted_mappings:
            # Escape special regex characters in the path
            escaped_path = re.escape(local_path)

            # Replace with different quote styles
            # Single quotes
            rewritten = rewritten.replace(f"'{local_path}'", f"'{mapping.container_path}'")
            # Double quotes
            rewritten = rewritten.replace(f'"{local_path}"', f'"{mapping.container_path}"')
            # Unquoted (with word boundaries)
            rewritten = re.sub(rf'\b{escaped_path}\b', mapping.container_path, rewritten)

        self.logger.debug(f"Rewritten command (first 200 chars): {rewritten[:200]}...")

        return rewritten

    def _wrap_command_with_transfers(self, command: str) -> str:
        """
        Wrap the command with S3 download/upload commands.

        Args:
            command: The rewritten command with container paths

        Returns:
            Full command including setup and cleanup
        """
        # Generate S3 transfer commands that work with minimal containers
        # All commands are in a single shell to preserve PYCMD variable

        # Step 1: Create helper script (supports both python3 and python)
        s3_helper_script = self._generate_s3_helper_script()

        # Step 2: Generate setup commands (download inputs)
        setup = self._generate_setup_commands_python()

        # Step 3: Generate cleanup commands (upload outputs)
        cleanup = self._generate_cleanup_commands_python()

        # Combine all steps in a single command sequence
        # Export PYCMD so it's available in the entire shell session
        full_command = (
            f"{s3_helper_script} && "
            f"export PYCMD && "
            f"{setup} && "
            f"{command} && "
            f"{cleanup}"
        )

        return full_command

    def _generate_s3_helper_script(self) -> str:
        """Generate a Python script for S3 file transfers (works in minimal containers)."""
        # Use printf to write the script - avoids quote escaping issues
        # Detect python3 or python, create script, and add execute permissions
        script = r"""(command -v python3 >/dev/null 2>&1 && PYCMD=python3 || PYCMD=python) && printf 'import sys,os\ntry:\n import boto3\nexcept:\n import subprocess;subprocess.check_call([sys.executable,"-m","pip","install","-q","boto3"]);import boto3\ndef dl(b,k,p):\n os.makedirs(os.path.dirname(p)or".",exist_ok=True);boto3.client("s3").download_file(b,k,p);print(f"DL s3://{b}/{k}")\ndef ul(p,b,k):\n boto3.client("s3").upload_file(p,b,k);print(f"UL s3://{b}/{k}")\nif __name__=="__main__":\n a=sys.argv[1]\n if a=="download":dl(sys.argv[2],sys.argv[3],sys.argv[4])\n elif a=="upload":ul(sys.argv[2],sys.argv[3],sys.argv[4])\n' > /tmp/s3_transfer.py && chmod +x /tmp/s3_transfer.py && echo "S3 helper created with $PYCMD" """

        return script

    def _generate_setup_commands_python(self) -> str:
        """Generate Python-based commands to download input files."""
        commands = []

        # Create directories
        commands.append(f"mkdir -p {self.container_inputs_dir}")
        commands.append(f"mkdir -p {self.container_outputs_dir}")

        # Download input files using Python helper (use detected PYCMD variable)
        for mapping in self.file_mappings.values():
            if mapping.is_input:
                # Parse S3 URI to get bucket and key
                s3_uri = mapping.s3_uri
                if s3_uri.startswith('s3://'):
                    s3_path = s3_uri[5:]  # Remove 's3://' prefix
                    # Split into bucket and key
                    parts = s3_path.split('/', 1)
                    bucket = parts[0]
                    key = parts[1] if len(parts) > 1 else ''

                    # Ensure parent directory exists
                    parent_dir = os.path.dirname(mapping.container_path)
                    if parent_dir and parent_dir != self.container_inputs_dir:
                        commands.append(f"mkdir -p {parent_dir}")

                    # Download using Python helper (use PYCMD variable set in helper script)
                    commands.append(
                        f"$PYCMD /tmp/s3_transfer.py download {bucket} {key} {mapping.container_path}"
                    )
                    self.logger.debug(f"Setup: download {s3_uri} to {mapping.container_path}")

        return " && ".join(commands) if commands else "true"

    def _generate_cleanup_commands_python(self) -> str:
        """Generate Python-based commands to upload output files."""
        commands = []

        # Upload output files using Python helper (use PYCMD variable set in helper script)
        for mapping in self.file_mappings.values():
            if mapping.is_output and os.path.exists(mapping.local_path):
                # Parse S3 URI to get bucket and key
                s3_uri = mapping.s3_uri
                if s3_uri.startswith('s3://'):
                    s3_path = s3_uri[5:]  # Remove 's3://' prefix
                    parts = s3_path.split('/', 1)
                    bucket = parts[0]
                    key = parts[1] if len(parts) > 1 else ''

                    # Upload using Python helper (use PYCMD variable set in helper script)
                    commands.append(
                        f"$PYCMD /tmp/s3_transfer.py upload {mapping.container_path} {bucket} {key}"
                    )
                    self.logger.debug(f"Cleanup: upload {mapping.container_path} to {s3_uri}")

        return " && ".join(commands) if commands else "true"

    def download_outputs(self, output_s3_uris: List[str] = None) -> Dict[str, str]:
        """
        Download output files from S3 back to local storage.

        Args:
            output_s3_uris: Optional list of specific S3 URIs to download.
                           If None, downloads all output mappings.

        Returns:
            Dictionary mapping S3 URI to local path
        """
        downloaded = {}

        for mapping in self.file_mappings.values():
            if not mapping.is_output:
                continue

            # Skip if specific URIs requested and this isn't one of them
            if output_s3_uris and mapping.s3_uri not in output_s3_uris:
                continue

            self.logger.info(f"Downloading: {mapping.s3_uri} -> {mapping.local_path}")

            try:
                # Extract bucket and key from S3 URI
                s3_parts = mapping.s3_uri.replace('s3://', '').split('/', 1)
                bucket = s3_parts[0]
                key = s3_parts[1] if len(s3_parts) > 1 else ''

                # Ensure parent directory exists
                os.makedirs(os.path.dirname(mapping.local_path), exist_ok=True)

                if mapping.is_directory:
                    # Download directory recursively
                    self._download_directory(bucket, key, mapping.local_path)
                else:
                    # Download single file
                    self.storage.download_file(bucket, key, mapping.local_path)

                downloaded[mapping.s3_uri] = mapping.local_path
                self.logger.info(f"Downloaded successfully")

            except Exception as e:
                self.logger.error(f"Failed to download {mapping.s3_uri}: {e}")
                # Continue with other files

        return downloaded

    def _download_directory(self, bucket: str, s3_prefix: str, local_dir: str):
        """Download a directory from S3."""
        # Use AWS CLI for recursive download (more efficient)
        import subprocess

        s3_uri = f"s3://{bucket}/{s3_prefix}/"
        os.makedirs(local_dir, exist_ok=True)

        cmd = ["aws", "s3", "cp", s3_uri, local_dir, "--recursive"]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"Failed to download directory: {result.stderr}")

    def cleanup_s3_staging(self):
        """Clean up S3 staging area for this job."""
        self.logger.info(f"Cleaning up S3 staging: s3://{self.s3_bucket}/{self.s3_staging_prefix}")

        try:
            # Delete all files under the staging prefix
            self.storage.delete_prefix(self.s3_bucket, self.s3_staging_prefix)
            self.logger.info("S3 staging cleaned up successfully")
        except Exception as e:
            self.logger.warning(f"Failed to clean up S3 staging: {e}")
