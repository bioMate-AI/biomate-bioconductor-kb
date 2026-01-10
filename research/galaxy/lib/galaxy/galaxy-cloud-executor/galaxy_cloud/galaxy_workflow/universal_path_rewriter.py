"""
Universal Path Rewriter for Galaxy Cloud Execution

This module provides a tool-agnostic approach to rewriting Galaxy job commands
for execution in cloud containers. Instead of special-casing individual tools,
it creates a consistent execution environment that works for ANY Galaxy tool.

Core Principle:
    Environment Consistency > Command Rewriting

    Don't try to understand every tool's behavior.
    Create an environment where any tool naturally works.
"""

import os
import re
import logging
from pathlib import Path
from typing import Dict, List, Optional, Tuple


logger = logging.getLogger(__name__)


class UniversalPathRewriter:
    """
    Universal path rewriter that works for ANY Galaxy tool.

    Strategy:
    1. Create a consistent container directory structure
    2. Map Galaxy's local paths to container paths using simple patterns
    3. Let Galaxy commands run unmodified (or with minimal, generic changes)

    Container Structure:
        /galaxy_execution/
        ├── job/                    # Job root (maps to Galaxy job directory)
        │   ├── working/           # Working directory (where commands execute)
        │   ├── inputs/            # Input files
        │   ├── outputs/           # Output files
        │   ├── configs/           # Config files
        │   └── metadata/          # Metadata
        └── datasets/              # Dataset storage (maps to Galaxy object store)
            └── objects/           # Dataset objects by hash path

    Examples:
        Local:     /Users/xxx/galaxy/database/jobs/000/538/working/
        Container: /galaxy_execution/job/working/

        Local:     /Users/xxx/galaxy/database/objects/1/2/3/dataset_123.dat
        Container: /galaxy_execution/datasets/objects/1/2/3/dataset_123.dat
    """

    # Container paths (fixed, standard across all jobs)
    CONTAINER_EXECUTION_ROOT = "/galaxy_execution"
    CONTAINER_JOB_DIR = f"{CONTAINER_EXECUTION_ROOT}/job"
    CONTAINER_WORK_DIR = f"{CONTAINER_JOB_DIR}/working"
    CONTAINER_INPUT_DIR = f"{CONTAINER_JOB_DIR}/inputs"
    CONTAINER_OUTPUT_DIR = f"{CONTAINER_JOB_DIR}/outputs"
    CONTAINER_CONFIG_DIR = f"{CONTAINER_JOB_DIR}/configs"
    CONTAINER_METADATA_DIR = f"{CONTAINER_JOB_DIR}/metadata"
    CONTAINER_DATASETS_ROOT = f"{CONTAINER_EXECUTION_ROOT}/datasets"

    def __init__(self, job_wrapper, job_id: str):
        """
        Initialize path rewriter for a specific job.

        Args:
            job_wrapper: Galaxy JobWrapper instance
            job_id: Job ID string
        """
        self.job_wrapper = job_wrapper
        self.job_id = job_id
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Extract Galaxy local paths
        self.local_job_dir = job_wrapper.working_directory
        self.local_work_dir = os.path.join(self.local_job_dir, "working")

        # Get Galaxy's database root (where objects are stored)
        # Example: /Users/xxx/galaxy/database
        self.local_database_root = self._extract_database_root()

        # Build path mappings
        self.path_mappings = self._build_path_mappings()

        self.logger.info(f"[{job_id}] Initialized UniversalPathRewriter")
        self.logger.info(f"[{job_id}] Local job dir: {self.local_job_dir}")
        self.logger.info(f"[{job_id}] Container job dir: {self.CONTAINER_JOB_DIR}")

    def _extract_database_root(self) -> str:
        """
        Extract Galaxy database root from job working directory.

        Example:
            /Users/xxx/galaxy/database/jobs/000/538
            → /Users/xxx/galaxy/database
        """
        # Job directory pattern: .../database/jobs/NNN/job_id
        job_dir = self.local_job_dir

        # Find 'database' in the path
        parts = Path(job_dir).parts
        try:
            db_index = parts.index('database')
            # Rejoin parts from root (parts[0] is '/')
            database_root = str(Path(*parts[:db_index+1]))
            return database_root
        except ValueError:
            # Fallback: assume database is parent of parent of parent
            return str(Path(job_dir).parent.parent.parent)

    def _build_path_mappings(self) -> Dict[str, str]:
        """
        Build path mapping dictionary.

        Returns:
            Dict mapping local paths to container paths
        """
        mappings = {
            # Job directories
            self.local_job_dir: self.CONTAINER_JOB_DIR,
            self.local_work_dir: self.CONTAINER_WORK_DIR,

            # Database paths
            f"{self.local_database_root}/objects": f"{self.CONTAINER_DATASETS_ROOT}/objects",
        }

        # Add input/output specific mappings
        # These will be added dynamically as we process datasets

        return mappings

    def rewrite_command(self, command: str) -> str:
        """
        Rewrite a Galaxy command for container execution.

        This is the main entry point. It applies all rewriting rules
        in the correct order to transform a local Galaxy command into
        a container-compatible command.

        Args:
            command: Original Galaxy-generated command

        Returns:
            Rewritten command for container execution
        """
        self.logger.debug(f"[{self.job_id}] Original command: {command[:200]}...")

        rewritten = command

        # NOTE: Dataset paths (inputs) are NOT rewritten - they will be handled
        # by symlinks created in the job script. This is simpler and more reliable
        # than trying to reorganize the entire dataset object store structure.

        # Step 1: Rewrite job directory paths (outputs, working files, etc.)
        rewritten = self._rewrite_job_paths(rewritten)

        # Step 2: Normalize relative path operations (cd ../,  etc.)
        rewritten = self._normalize_relative_paths(rewritten)

        self.logger.debug(f"[{self.job_id}] Rewritten command: {rewritten[:200]}...")
        return rewritten

    def _rewrite_dataset_paths(self, command: str) -> str:
        """
        Rewrite dataset object paths.

        Galaxy stores datasets in an object store with hash-based paths:
        /galaxy/database/objects/1/2/3/dataset_123abc.dat

        We map these to container paths while preserving the structure.
        """
        rewritten = command

        # Get the local objects path
        local_objects = f"{self.local_database_root}/objects"
        container_objects = f"{self.CONTAINER_DATASETS_ROOT}/objects"

        # Replace all occurrences (simple string replacement works for paths)
        # This catches paths in any context: quotes, variables, etc.
        rewritten = rewritten.replace(local_objects, container_objects)

        return rewritten

    def _rewrite_job_paths(self, command: str) -> str:
        """
        Rewrite job directory paths.

        Galaxy generates commands with absolute paths to the job directory.
        We need to replace these with container paths.
        """
        rewritten = command

        # FIRST: Rewrite shed_tools paths
        # /Users/.../database/shed_tools/... → /galaxy/shed_tools/...
        import re
        shed_pattern = r'(["\']?)(/[^"\':\s]*shed_tools/)([^"\'\s]+)(["\']?)'
        def shed_replacer(match):
            quote_start = match.group(1)
            shed_prefix = match.group(2)  # Will be replaced
            path_after_shed = match.group(3)
            quote_end = match.group(4)
            return f'{quote_start}/galaxy/shed_tools/{path_after_shed}{quote_end}'

        rewritten = re.sub(shed_pattern, shed_replacer, rewritten)

        # THEN: Sort mappings by length (longest first) to avoid partial replacements
        sorted_mappings = sorted(
            self.path_mappings.items(),
            key=lambda x: len(x[0]),
            reverse=True
        )

        for local_path, container_path in sorted_mappings:
            # Replace in various quote contexts
            # In single quotes
            rewritten = rewritten.replace(f"'{local_path}", f"'{container_path}")
            # In double quotes
            rewritten = rewritten.replace(f'"{local_path}', f'"{container_path}')
            # Without quotes (space-separated)
            rewritten = rewritten.replace(f" {local_path} ", f" {container_path} ")
            rewritten = rewritten.replace(f" {local_path};", f" {container_path};")
            rewritten = rewritten.replace(f" {local_path}&&", f" {container_path}&&")

        return rewritten

    def _normalize_relative_paths(self, command: str) -> str:
        """
        Normalize relative path operations (cd ../, cd ../../, etc.)

        Galaxy commands often use relative paths assuming execution from
        the working directory. We convert these to absolute paths so they
        work correctly regardless of where the command starts.

        Default execution directory: /galaxy_execution/job/working/

        Examples:
            cd ../              → cd /galaxy_execution/job
            cd ../../           → cd /galaxy_execution
            cd ../configs       → cd /galaxy_execution/job/configs
            cd working          → cd /galaxy_execution/job/working
        """
        rewritten = command

        # Pattern 1: cd ../ (go to parent - job directory)
        rewritten = re.sub(
            r'\bcd\s+\.\./?\s*([;&|]|\|\||&&|$)',
            f'cd {self.CONTAINER_JOB_DIR}\\1',
            rewritten
        )

        # Pattern 2: cd ../../ (go to grandparent - execution root)
        rewritten = re.sub(
            r'\bcd\s+\.\./\.\./?\s*([;&|]|\|\||&&|$)',
            f'cd {self.CONTAINER_EXECUTION_ROOT}\\1',
            rewritten
        )

        # Pattern 3: cd ../something (go to parent then subdirectory)
        rewritten = re.sub(
            r'\bcd\s+\.\./(\w+)',
            f'cd {self.CONTAINER_JOB_DIR}/\\1',
            rewritten
        )

        return rewritten

    def _fix_quotes_for_variables(self, command: str) -> str:
        """
        Fix quote usage to allow variable expansion.

        Galaxy may generate paths in single quotes, but container paths
        often use variables like ${OUTPUT_DIR}. Single quotes prevent
        variable expansion, so we need to use double quotes.

        This is already handled by earlier replacements, but we can
        add specific fixes here if needed.
        """
        # This is mostly handled by _rewrite_job_paths already
        return command

    def get_s3_structure(self) -> Dict[str, str]:
        """
        Get the S3 directory structure mapping.

        Returns:
            Dict mapping S3 prefixes to container paths

        Example:
            {
                'jobs/538/inputs/': '/galaxy_execution/job/inputs/',
                'jobs/538/working/': '/galaxy_execution/job/working/',
                'jobs/538/outputs/': '/galaxy_execution/job/outputs/',
            }
        """
        return {
            f'jobs/{self.job_id}/inputs/': self.CONTAINER_INPUT_DIR + '/',
            f'jobs/{self.job_id}/working/': self.CONTAINER_WORK_DIR + '/',
            f'jobs/{self.job_id}/outputs/': self.CONTAINER_OUTPUT_DIR + '/',
            f'jobs/{self.job_id}/configs/': self.CONTAINER_CONFIG_DIR + '/',
        }

    def get_environment_variables(self) -> Dict[str, str]:
        """
        Get environment variables for the container execution.

        Returns:
            Dict of environment variables
        """
        return {
            'GALAXY_EXECUTION_ROOT': self.CONTAINER_EXECUTION_ROOT,
            'GALAXY_JOB_DIR': self.CONTAINER_JOB_DIR,
            'GALAXY_WORK_DIR': self.CONTAINER_WORK_DIR,
            'GALAXY_INPUT_DIR': self.CONTAINER_INPUT_DIR,
            'GALAXY_OUTPUT_DIR': self.CONTAINER_OUTPUT_DIR,
            'GALAXY_CONFIG_DIR': self.CONTAINER_CONFIG_DIR,
            'GALAXY_DATASETS_ROOT': self.CONTAINER_DATASETS_ROOT,
        }

    def create_symlink_script(self, input_datasets: List, output_datasets: List) -> str:
        """
        Create a bash script to set up symlinks for datasets.

        This allows Galaxy commands to reference datasets by their original
        paths, while the actual files are stored in the container's standard
        locations.

        Args:
            input_datasets: List of input dataset associations
            output_datasets: List of output dataset associations

        Returns:
            Bash script content
        """
        script_lines = [
            "#!/bin/bash",
            "# Auto-generated symlink setup script",
            "# This makes Galaxy's local paths available in the container",
            "",
            "set -e",
            "",
        ]

        # Create directories for dataset paths
        script_lines.append("# Create dataset object directories")
        script_lines.append(f"mkdir -p {self.CONTAINER_DATASETS_ROOT}/objects")
        script_lines.append("")

        # For inputs: create symlinks from container location to original path
        script_lines.append("# Symlink input datasets")
        for input_assoc in input_datasets:
            if input_assoc.dataset and input_assoc.dataset.dataset:
                try:
                    local_path = input_assoc.dataset.dataset.get_file_name()
                    # Extract the hash path (e.g., 1/2/3/dataset_123.dat)
                    hash_path = self._extract_hash_path(local_path)
                    if hash_path:
                        container_path = f"{self.CONTAINER_DATASETS_ROOT}/objects/{hash_path}"
                        # Source will be downloaded to inputs/
                        filename = Path(local_path).name
                        source = f"{self.CONTAINER_INPUT_DIR}/{filename}"

                        script_lines.append(f"# {filename}")
                        script_lines.append(f"mkdir -p $(dirname '{container_path}')")
                        script_lines.append(f"ln -sf '{source}' '{container_path}'")
                        script_lines.append("")
                except Exception as e:
                    self.logger.warning(f"Could not create symlink for input: {e}")

        # For outputs: create directories
        script_lines.append("# Create output dataset directories")
        for output_assoc in output_datasets:
            if output_assoc.dataset and output_assoc.dataset.dataset:
                try:
                    local_path = output_assoc.dataset.dataset.get_file_name()
                    hash_path = self._extract_hash_path(local_path)
                    if hash_path:
                        container_path = f"{self.CONTAINER_DATASETS_ROOT}/objects/{hash_path}"
                        script_lines.append(f"mkdir -p $(dirname '{container_path}')")
                except Exception as e:
                    self.logger.warning(f"Could not create directory for output: {e}")

        script_lines.append("")
        script_lines.append("echo 'Symlink setup complete'")

        return "\n".join(script_lines)

    def _extract_hash_path(self, full_path: str) -> Optional[str]:
        """
        Extract hash path from full dataset path.

        Example:
            /Users/xxx/database/objects/1/2/3/dataset_123.dat
            → 1/2/3/dataset_123.dat
        """
        try:
            # Find 'objects/' in the path and take everything after it
            parts = Path(full_path).parts
            objects_idx = parts.index('objects')
            hash_path = os.path.join(*parts[objects_idx+1:])
            return hash_path
        except (ValueError, IndexError):
            return None


def test_rewriter():
    """Test the UniversalPathRewriter with sample commands."""

    class MockJobWrapper:
        def __init__(self):
            self.working_directory = "/Users/test/galaxy/database/jobs/000/538"

    job_wrapper = MockJobWrapper()
    rewriter = UniversalPathRewriter(job_wrapper, "538")

    # Test cases
    test_commands = [
        # Dataset path
        "cat '/Users/test/galaxy/database/objects/1/2/3/dataset_123.dat' > output.txt",

        # Job directory path
        "cd '/Users/test/galaxy/database/jobs/000/538/working' && run_tool.sh",

        # Relative paths
        "cd ../; python script.py",
        "cd ../../; ls",
        "cd ../configs; cat config.ini",

        # Complex command
        "mkdir -p '/Users/test/galaxy/database/jobs/000/538/outputs' && cd ../ && python tool.py",
    ]

    print("=" * 80)
    print("UniversalPathRewriter Test Results")
    print("=" * 80)

    for i, cmd in enumerate(test_commands, 1):
        print(f"\nTest {i}:")
        print(f"  Original:  {cmd}")
        rewritten = rewriter.rewrite_command(cmd)
        print(f"  Rewritten: {rewritten}")

    print("\n" + "=" * 80)
    print("Environment Variables:")
    print("=" * 80)
    for k, v in rewriter.get_environment_variables().items():
        print(f"  {k} = {v}")


if __name__ == "__main__":
    # Run tests
    test_rewriter()
