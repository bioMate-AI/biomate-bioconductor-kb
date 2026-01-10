"""
Galaxy Cloud Job Runner

A Galaxy job runner implementation that integrates with the cloud execution system.
This allows Galaxy to use our cloud executor as a native job runner.
"""

import asyncio
import logging
import threading
from typing import Dict, List, Optional, Any, Tuple
from pathlib import Path

from galaxy.jobs.runners import BaseJobRunner, AsynchronousJobRunner, AsynchronousJobState
from galaxy.jobs import JobDestination
from galaxy import model
from galaxy.model import Job

from galaxy_cloud.factory import CloudExecutorFactory
from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.job import JobSpec, ResourceSpec, ContainerSpec, JobStatus

from .tool_registry import GalaxyToolRegistry
from .enhanced_tool_registry import EnhancedToolRegistry
from .data_manager import GalaxyDataManager
from .file_transfer_manager import FileTransferManager
from .nextflow_executor import NextflowExecutor
from .job_config_parser import GalaxyJobConfigParser
from .models import WorkflowRunConfig
from .universal_path_rewriter import UniversalPathRewriter


logger = logging.getLogger(__name__)


class GalaxyCloudJobRunner(AsynchronousJobRunner):
    """
    Galaxy job runner that executes jobs using the cloud executor framework.

    This runner can be configured in job_conf.xml to route specific tools
    to cloud platforms while maintaining Galaxy's native job management.
    """

    runner_name = "GalaxyCloudJobRunner"

    def __init__(self, app, nworkers, **kwargs):
        """Initialize the cloud job runner"""
        super().__init__(app, nworkers)

        self.app = app
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Initialize cloud components
        self._init_cloud_components()

        # Job tracking
        self.active_jobs: Dict[str, 'CloudJobState'] = {}

        # Nextflow executor (optional)
        self.nextflow_executor: Optional[NextflowExecutor] = None
        self.use_nextflow = False  # Can be configured per job destination

        # Event loop for async operations
        # NOTE: Delayed initialization to avoid issues with forked workers
        self._loop = None
        self._loop_thread = None
        # Don't start event loop in __init__ to avoid fork() issues
        # It will be lazily initialized when needed

    def _init_cloud_components(self):
        """Initialize cloud execution components"""
        try:
            # Load configuration from Galaxy config or job_conf
            config = self._load_cloud_config()

            # Initialize enhanced tool registry with Galaxy app access
            tool_registry_config = config.get('tool_registry', {})
            # Add static mappings file path
            tool_registry_config['static_mappings_file'] = 'config/tool_containers.json'
            self.tool_registry = EnhancedToolRegistry(tool_registry_config, galaxy_app=self.app)

            # Initialize data manager
            self.data_manager = GalaxyDataManager(config.get('storage', {}))

            # Cloud executors for different providers
            self.cloud_executors: Dict[str, CloudExecutor] = {}

            # Parse Galaxy job configuration for cloud mappings
            # Note: This parser is for XML format. Galaxy now uses YAML which is parsed by Galaxy itself.
            # We only need this for standalone/independent mode.
            self.job_config_parser = GalaxyJobConfigParser()
            if hasattr(self.app.config, 'job_config_file'):
                job_conf_path = Path(self.app.config.job_config_file)
                # Only parse if it's an XML file
                if job_conf_path.suffix in ['.xml', '.xml.sample']:
                    try:
                        self.job_config_parser.parse_job_conf_file(job_conf_path)
                    except Exception as e:
                        self.logger.warning(f"Could not parse job config file: {e}")
                else:
                    self.logger.info(f"Job config is YAML format ({job_conf_path}), skipping XML parsing")

            self.logger.info("Galaxy Cloud Job Runner initialized successfully")

        except Exception as e:
            self.logger.error(f"Failed to initialize Galaxy Cloud Job Runner: {e}")
            # Don't raise - allow Galaxy to continue even if cloud runner has issues
            self.logger.warning("Galaxy Cloud Job Runner initialization failed, but continuing...")

    def _build_provider_config(self, job_destination: JobDestination) -> Dict[str, Any]:
        """Build cloud provider config from job destination parameters"""
        # Galaxy's JobDestination.params only contains a subset of parameters.
        # We need to read the full configuration directly from job_conf.yml

        params = job_destination.params.copy()  # Start with what Galaxy provides

        # Read additional parameters directly from job_conf.yml
        # Galaxy reorganizes the YAML structure when loading, so we need to read the raw file
        try:
            import yaml
            job_conf_path = Path(self.app.config.job_config_file)
            self.logger.info(f"DEBUG: Attempting to read job_conf from: {job_conf_path}")

            if job_conf_path.exists():
                self.logger.info(f"DEBUG: job_conf file exists, reading...")
                with open(job_conf_path, 'r') as f:
                    raw_job_conf = yaml.safe_load(f)

                # Get our destination config from RAW YAML (before Galaxy processes it)
                dest_id = job_destination.id
                self.logger.info(f"DEBUG: dest_id = {dest_id}")
                if dest_id and 'execution' in raw_job_conf and 'environments' in raw_job_conf['execution']:
                    raw_env_config = raw_job_conf['execution']['environments'].get(dest_id, {})
                    self.logger.info(f"DEBUG: raw_env_config keys = {list(raw_env_config.keys())}")

                    # Check if params are nested (job_conf_cloud.yml style) or flat (job_conf.yml style)
                    if 'params' in raw_env_config:
                        # Nested structure: cloud_small: { runner: ..., params: { ... } }
                        params_config = raw_env_config['params']
                        self.logger.info(f"DEBUG: Found nested params structure")
                    else:
                        # Flat structure: cloud_small: { runner: ..., provider: ..., ... }
                        params_config = raw_env_config
                        self.logger.info(f"DEBUG: Found flat params structure")

                    # Add IAM role parameters if they exist in RAW YAML
                    if 'job_role_arn' in params_config:
                        params['job_role_arn'] = params_config['job_role_arn']
                        self.logger.info(f"Added job_role_arn: {params_config['job_role_arn']}")
                    if 'execute_role_arn' in params_config:
                        params['execute_role_arn'] = params_config['execute_role_arn']
                        self.logger.info(f"Added execute_role_arn: {params_config['execute_role_arn']}")
                    elif 'execution_role_arn' in params_config:
                        params['execute_role_arn'] = params_config['execution_role_arn']
                        self.logger.info(f"Added execution_role_arn: {params_config['execution_role_arn']}")

                    if 'job_role_arn' in params or 'execute_role_arn' in params:
                        self.logger.info(f"Successfully loaded IAM roles from job_conf.yml for destination '{dest_id}'")
        except Exception as e:
            self.logger.warning(f"Could not read job_conf.yml for IAM roles: {e}")

        self.logger.info(f"DEBUG: Final params with IAM roles: {params}")

        # Extract AWS-specific parameters
        # Use the exact keys that AWSBatchExecutor expects
        config = {}

        if 'aws_region' in params:
            config['region'] = params['aws_region']
        if 'aws_batch_queue' in params:
            config['batch_queue'] = params['aws_batch_queue']  # Changed from 'queue_name'
        if 'aws_s3_bucket' in params:
            config['s3_bucket'] = params['aws_s3_bucket']

        # IAM Roles for AWS Batch jobs
        # Support both 'execute_role_arn' (Galaxy standard) and 'execution_role_arn' (AWS standard)
        if 'job_role_arn' in params:
            config['job_role_arn'] = params['job_role_arn']
        if 'execute_role_arn' in params:
            config['execution_role_arn'] = params['execute_role_arn']
        elif 'execution_role_arn' in params:
            config['execution_role_arn'] = params['execution_role_arn']

        self.logger.info(f"Built provider config from job destination: {config}")

        return config

    def _load_cloud_config(self) -> Dict[str, Any]:
        """Load cloud configuration from Galaxy config"""
        # This would typically load from Galaxy's configuration
        # For now, we'll use a default configuration
        return {
            'tool_registry': {
                'biocontainers_api_url': 'https://biocontainers.pro/api/ga4gh/trs/v2/tools',
                'default_image': 'quay.io/biocontainers/galaxy-minimal:latest'
            },
            'storage': {
                'kubernetes': {
                    'namespace': 'galaxy-jobs',
                    'storage_class': 'fast-ssd'
                }
            },
            'cloud_providers': {
                'kubernetes': {
                    'namespace': 'galaxy-jobs',
                    'kubeconfig': None  # Use in-cluster config
                },
                'aws-batch': {
                    'region': 'us-west-2',
                    'batch_queue': 'galaxy-cloud-queue',  # Changed from 'queue_name'
                    's3_bucket': 'galaxy-cloud-data-1760241377'
                }
            }
        }

    def _ensure_event_loop(self):
        """Ensure event loop is started (lazy initialization to avoid fork issues)"""
        if self._loop is None or not self._loop.is_running():
            def run_loop():
                self._loop = asyncio.new_event_loop()
                asyncio.set_event_loop(self._loop)
                self._loop.run_forever()

            self._loop_thread = threading.Thread(target=run_loop, daemon=True)
            self._loop_thread.start()

            # Wait for loop to be ready
            max_wait = 50  # 0.5 seconds max
            for _ in range(max_wait):
                if self._loop is not None:
                    break
                threading.Event().wait(0.01)

            if self._loop is None:
                raise RuntimeError("Failed to start event loop")

    def queue_job(self, job_wrapper):
        """
        Queue a job for execution.

        Note: Galaxy's job handler already checks input dataset readiness before calling
        this method, so we don't need to duplicate that check here. The handler ensures
        that workflow dependencies are respected by only queueing jobs when their inputs
        are ready (i.e., when previous jobs have completed and marked outputs as OK).
        """
        try:
            # Ensure event loop is running (lazy init)
            self._ensure_event_loop()

            # Log input dataset states for debugging workflow dependencies
            job = job_wrapper.get_job()
            input_info = []
            has_empty_inputs = False

            for dataset_assoc in job.input_datasets:
                if dataset_assoc.dataset:
                    input_info.append(
                        f"{dataset_assoc.dataset.hid}:{dataset_assoc.dataset.state}"
                    )

                    # CRITICAL: Check if input file actually exists and has content
                    # This prevents submitting jobs with incomplete inputs from previous workflow steps
                    if dataset_assoc.dataset.dataset:
                        try:
                            file_path = dataset_assoc.dataset.dataset.get_file_name()
                            from pathlib import Path
                            if Path(file_path).exists():
                                file_size = Path(file_path).stat().st_size
                                if file_size == 0:
                                    self.logger.warning(
                                        f"Job {job_wrapper.get_id_tag()} has empty input file: {file_path} "
                                        f"(dataset {dataset_assoc.dataset.hid})"
                                    )
                                    has_empty_inputs = True
                            else:
                                self.logger.warning(
                                    f"Job {job_wrapper.get_id_tag()} input file does not exist: {file_path}"
                                )
                                has_empty_inputs = True
                        except Exception as e:
                            self.logger.warning(
                                f"Could not check input file for job {job_wrapper.get_id_tag()}: {e}"
                            )

            self.logger.info(
                f"Queueing job {job_wrapper.get_id_tag()} with input datasets: "
                f"{', '.join(input_info) if input_info else 'none'}"
            )

            # If inputs are empty, delay this job
            # This allows previous workflow steps to complete and download their outputs
            if has_empty_inputs:
                self.logger.warning(
                    f"Job {job_wrapper.get_id_tag()} has empty/missing input files - "
                    f"requeuing to wait for dependencies"
                )
                # Mark as waiting and let Galaxy's handler retry later
                job_wrapper.change_state(model.Job.states.QUEUED)
                return

            # Get job destination
            job_destination = job_wrapper.job_destination

            # Check execution mode
            # Handle both string ('true'/'false') and boolean (True/False) values
            use_nextflow_param = job_destination.params.get('use_nextflow', 'false')
            use_nextflow = use_nextflow_param if isinstance(use_nextflow_param, bool) else use_nextflow_param.lower() == 'true'

            use_fetch_and_run_param = job_destination.params.get('use_fetch_and_run', 'true')
            use_fetch_and_run = use_fetch_and_run_param if isinstance(use_fetch_and_run_param, bool) else use_fetch_and_run_param.lower() == 'true'

            if use_nextflow:
                # Use Nextflow execution path
                self.logger.info(f"Job {job_wrapper.get_id_tag()} will use Nextflow execution")
                future = asyncio.run_coroutine_threadsafe(
                    self._submit_nextflow_job(job_wrapper, job_destination),
                    self._loop
                )
            elif use_fetch_and_run:
                # Use Fetch-and-Run execution path (recommended)
                self.logger.info(f"Job {job_wrapper.get_id_tag()} will use Fetch-and-Run execution")
                future = asyncio.run_coroutine_threadsafe(
                    self._submit_fetch_and_run_job(job_wrapper, job_destination),
                    self._loop
                )
            else:
                # Use direct AWS Batch execution path (legacy)
                self.logger.info(f"Job {job_wrapper.get_id_tag()} will use direct AWS Batch execution")

                # Get cloud provider from destination params
                cloud_provider = self._get_cloud_provider(job_destination)

                # Create cloud job specification
                job_spec = self._create_job_spec(job_wrapper, job_destination)

                # Submit job asynchronously
                future = asyncio.run_coroutine_threadsafe(
                    self._submit_cloud_job(job_wrapper, job_spec, cloud_provider, job_destination),
                    self._loop
                )

            # Create job state
            job_state = CloudJobState(job_wrapper, future)
            self.active_jobs[job_wrapper.get_id_tag()] = job_state

            self.logger.info(f"Submitted job {job_wrapper.get_id_tag()} to cloud for execution")

        except Exception as e:
            import traceback
            self.logger.error(f"Failed to queue job {job_wrapper.get_id_tag()}: {e}")
            self.logger.error(f"Traceback: {traceback.format_exc()}")
            job_wrapper.fail("Failed to submit job to cloud executor")

    def _get_cloud_provider(self, job_destination: JobDestination) -> str:
        """Get cloud provider from job destination"""
        # Check destination parameters for cloud provider
        # Try both 'cloud_provider' and 'provider' keys
        if 'cloud_provider' in job_destination.params:
            provider = job_destination.params['cloud_provider']
        elif 'provider' in job_destination.params:
            provider = job_destination.params['provider']
        else:
            # Get from job config parser
            destination_config = self.job_config_parser.get_destination_config(job_destination.id)
            if destination_config:
                # Map runner to provider
                runner_mapping = {
                    'kubernetes': 'kubernetes',
                    'aws': 'aws-batch',
                    'gcp': 'gcp-batch',
                    'azure': 'azure-batch'
                }
                provider = runner_mapping.get(destination_config.runner, 'aws-batch')
            else:
                # Default to aws-batch (not kubernetes, since we're using AWS)
                provider = 'aws-batch'

        # Normalize provider names to match CloudExecutorFactory
        provider_mapping = {
            'aws': 'aws-batch',
            'gcp': 'gcp-batch',
            'azure': 'azure-batch',
            'kubernetes': 'kubernetes'
        }

        return provider_mapping.get(provider, provider)

    def _rewrite_command_line_paths(self, command_line: str, job, job_id: str) -> str:
        """
        Rewrite Galaxy command line paths for cloud execution (Fix 12 + Fix 16).

        Strategy (CRITICAL - DO NOT change input handling):
        - INPUT paths: KEEP original absolute paths (will be symlinked by Fix 7 in script)
        - OUTPUT paths: Rewrite to ${OUTPUT_DIR}/ (writable directory in container)

        Why this approach:
        1. Fix 7 will create symlinks: ln -s "${INPUT_DIR}/file.dat" original_path
        2. This way tool commands can still reference original paths
        3. Output paths must be rewritten to container-writable locations
        4. Fix 16: Use ${OUTPUT_DIR} variable instead of hardcoded /tmp/outputs/

        Example:
        Before: mkdir -p '/Users/.../dataset_xxx_files' && fastqc --outdir '/Users/.../dataset_xxx_files'
        After:  mkdir -p '${OUTPUT_DIR}/dataset_xxx_files' && fastqc --outdir '${OUTPUT_DIR}/dataset_xxx_files'

        The ${OUTPUT_DIR} variable is set by job script to point to the mounted output directory.
        """
        import re
        from pathlib import Path

        rewritten = command_line

        # Special handling for expression tools (Fix #5)
        # Expression tools use "cd ../; python _evaluate_expression_.py"
        # We need to remove the "cd ../" part since files are in working directory
        if '_evaluate_expression_.py' in command_line:
            self.logger.info(f"[{job_id}] Detected expression tool command, rewriting...")
            # Remove "cd ../;" or "cd ..;" or any variation
            rewritten = re.sub(r'cd\s+\.\./?\s*;?\s*', '', rewritten)
            # Ensure we're using the working directory path
            rewritten = rewritten.strip()
            self.logger.info(f"[{job_id}] Rewritten expression command: {rewritten}")
            return rewritten

        # Build path mapping - ONLY FOR OUTPUTS (Fix 12)
        path_mapping = {}

        # DON'T map input paths - they will be handled by symlinks (Fix 7)
        # Input paths stay as original absolute paths, Fix 7 will create symlinks for them

        # Debug: Check what output datasets we have
        self.logger.debug(f"[{job_id}] Number of output_datasets: {len(job.output_datasets)}")

        # ONLY map output paths to ${OUTPUT_DIR}/ (Fix 16: use variable, not hardcoded path)
        for output_assoc in job.output_datasets:
            if output_assoc.dataset and output_assoc.dataset.dataset:
                try:
                    original_path = output_assoc.dataset.dataset.get_file_name()
                    filename = Path(original_path).name
                    # Map absolute path to ${OUTPUT_DIR}/ (variable will be expanded at runtime)
                    path_mapping[original_path] = f"${{OUTPUT_DIR}}/{filename}"
                    # Also map _files directories
                    path_mapping[f"{original_path}_files"] = f"${{OUTPUT_DIR}}/{filename}_files"
                    self.logger.debug(f"[{job_id}] Output mapping: {original_path} → ${{OUTPUT_DIR}}/{filename}")
                except Exception as e:
                    self.logger.warning(f"[{job_id}] Could not map output path: {e}")
                    import traceback
                    self.logger.debug(f"[{job_id}] Traceback: {traceback.format_exc()}")

        if not path_mapping:
            self.logger.warning(f"[{job_id}] No output paths to rewrite in command line")
            self.logger.debug(f"[{job_id}] Command line preview: {command_line[:500]}...")
            return rewritten

        # Replace all OUTPUT paths in command line
        # Fix 17: Use double quotes for paths containing ${OUTPUT_DIR} variable
        replacements = 0
        for old_path, new_path in sorted(path_mapping.items(), key=lambda x: len(x[0]), reverse=True):
            # Replace in single quotes - CHANGE TO DOUBLE QUOTES (Fix 17)
            # Single quotes prevent variable expansion, so we must use double quotes
            if f"'{old_path}'" in rewritten:
                rewritten = rewritten.replace(f"'{old_path}'", f'"{new_path}"')
                replacements += 1
                self.logger.debug(f"[{job_id}] Rewrote: '{old_path}' → \"{new_path}\" (Fix 17: single→double quotes)")
            # Replace in double quotes (already correct)
            if f'"{old_path}"' in rewritten:
                rewritten = rewritten.replace(f'"{old_path}"', f'"{new_path}"')
                replacements += 1
                self.logger.debug(f"[{job_id}] Rewrote: \"{old_path}\" → \"{new_path}\"")
            # Replace without quotes (less common but possible)
            if f" {old_path} " in rewritten:
                rewritten = rewritten.replace(f" {old_path} ", f" {new_path} ")
                replacements += 1

        if replacements > 0:
            self.logger.info(f"[{job_id}] Rewrote {replacements} OUTPUT path(s) in command line (Fix 12)")
            self.logger.debug(f"[{job_id}] Rewritten command preview: {rewritten[:300]}...")
        else:
            self.logger.warning(f"[{job_id}] No paths were rewritten - this may indicate a problem!")

        return rewritten

    def _rewrite_script_for_cloud(self, script_content: str, job_wrapper) -> str:
        """
        Rewrite Galaxy-generated script for cloud container execution.

        This is a CRITICAL function that ensures ANY Galaxy workflow can run in cloud
        containers without manual modification. It handles:

        1. BusyBox compatibility (readlink -e → readlink -f)
        2. Path rewriting (local absolute paths → container paths)
        3. Environment variable fixes
        4. Tool-specific compatibility fixes (Trimmomatic JAR path, etc.)

        This makes the solution STANDARD and REUSABLE across all workflows.

        Args:
            script_content: Original Galaxy-generated bash script
            job_wrapper: Galaxy job wrapper object

        Returns:
            Rewritten script that works in any cloud container
        """
        import re

        job_id = job_wrapper.get_id_tag()
        self.logger.info(f"[{job_id}] Rewriting script for cloud execution (making it container-compatible)")

        rewritten = script_content

        # ========================================
        # Fix 1: BusyBox readlink compatibility
        # ========================================
        # Problem: GNU readlink supports -e flag, but BusyBox readlink doesn't
        # Solution: Replace all readlink -e with readlink -f (works on both)

        if 'readlink -e' in rewritten:
            count = rewritten.count('readlink -e')
            rewritten = rewritten.replace('readlink -e', 'readlink -f')
            self.logger.info(f"[{job_id}] Fixed {count} occurrences of 'readlink -e' → 'readlink -f' for BusyBox compatibility")

        # ========================================
        # Fix 2: Trimmomatic JAR path resolution
        # ========================================
        # Problem: Trimmomatic container might have JAR in different locations
        # Solution: Add fallback logic to find trimmomatic.jar

        if 'TRIMMOMATIC_JAR_PATH' in rewritten:
            self.logger.info(f"[{job_id}] Adding Trimmomatic JAR path fallback logic")

            # Insert Trimmomatic JAR finder before the tool command
            trimmomatic_finder = '''
# Trimmomatic JAR path finder (works in any container layout)
if [ -z "$TRIMMOMATIC_JAR_PATH" ]; then
    # Try standard locations
    for jar_path in \
        /usr/local/share/trimmomatic-*/trimmomatic-*.jar \
        /usr/share/java/trimmomatic-*.jar \
        /opt/trimmomatic/trimmomatic-*.jar \
        /trimmomatic-*.jar \
        /trimmomatic.jar; do
        if [ -f $jar_path ] || ls $jar_path 2>/dev/null | grep -q .; then
            export TRIMMOMATIC_JAR_PATH=$(dirname $(ls $jar_path 2>/dev/null | head -1))
            echo "Found Trimmomatic JAR at: $TRIMMOMATIC_JAR_PATH"
            break
        fi
    done
fi

# Also try to find adapters directory
if [ -z "$TRIMMOMATIC_ADAPTERS_PATH" ]; then
    for adapters in \
        /usr/local/share/trimmomatic-*/adapters \
        /usr/share/trimmomatic/adapters \
        /opt/trimmomatic/adapters \
        /adapters; do
        if [ -d "$adapters" ]; then
            export TRIMMOMATIC_ADAPTERS_PATH="$adapters"
            echo "Found Trimmomatic adapters at: $TRIMMOMATIC_ADAPTERS_PATH"
            break
        fi
    done
fi
'''

            # Insert before "echo "Executing tool command...""
            rewritten = rewritten.replace(
                'echo "Executing tool command..."',
                trimmomatic_finder + '\necho "Executing tool command..."'
            )

        # ========================================
        # Fix 3: Make symlink creation more robust
        # ========================================
        # Problem: mkdir -p "$(dirname "/absolute/path")" might fail in containers
        # Solution: Add error handling and ensure parent directories exist

        # Replace mkdir commands to be more robust
        rewritten = re.sub(
            r'mkdir -p "\$\(dirname "([^"]+)"\)"',
            r'mkdir -p "$(dirname "\1")" 2>/dev/null || mkdir -p "/tmp/$(dirname "\1")"',
            rewritten
        )

        # ========================================
        # Fix 4: Add working directory setup
        # ========================================
        # Ensure we have a working directory for temp files

        if 'cd ' not in rewritten and 'GALAXY_WORK_DIR' not in rewritten:
            # Add working directory setup after the shebang
            work_dir_setup = '''
# Set up working directory
if [ -n "$GALAXY_WORK_DIR" ]; then
    cd "$GALAXY_WORK_DIR" || cd /tmp/work
else
    mkdir -p /tmp/work && cd /tmp/work
fi
'''
            # Insert after "set -o pipefail"
            rewritten = rewritten.replace(
                'set -o pipefail',
                'set -o pipefail' + work_dir_setup
            )

        # ========================================
        # Fix 5: Add error logging
        # ========================================
        # Add better error reporting for debugging

        if 'trap' not in rewritten:
            error_handler = '''
# Error handler for better debugging
handle_error() {
    echo "ERROR: Script failed at line $1" >&2
    echo "Working directory: $(pwd)" >&2
    echo "Directory contents:" >&2
    ls -la 2>&1 || echo "Cannot list directory" >&2
    exit 1
}
trap 'handle_error $LINENO' ERR
'''
            # Insert after the working directory setup
            rewritten = rewritten.replace(
                'echo "Starting Galaxy tool execution..."',
                error_handler + '\necho "Starting Galaxy tool execution..."'
            )

        # ========================================
        # Fix 6: Ensure output directory exists
        # ========================================
        # Make sure OUTPUT_DIR is accessible and writable

        if 'OUTPUT_DIR=' in rewritten and 'mkdir -p "$OUTPUT_DIR"' not in rewritten:
            rewritten = rewritten.replace(
                'OUTPUT_DIR="${GALAXY_OUTPUT_DIR}"',
                'OUTPUT_DIR="${GALAXY_OUTPUT_DIR}"\nmkdir -p "$OUTPUT_DIR" 2>/dev/null || true'
            )

        # ========================================
        # Fix 7: Rewrite symlink commands in tool command line
        # ========================================
        # Problem: Galaxy tool commands create symlinks like:
        #   ln -s '/local/absolute/path/dataset_xxx.dat' fastq_in.fastqsanger.gz
        # These absolute paths don't exist in containers.
        # Solution: Replace absolute paths in ln -s commands with ${INPUT_DIR}/filename

        # Get job to extract dataset filenames
        try:
            job = job_wrapper.get_job()
            dataset_mapping = {}

            # Build mapping of absolute paths to filenames
            for input_assoc in job.input_datasets:
                dataset = input_assoc.dataset
                if dataset and dataset.dataset:
                    try:
                        from pathlib import Path
                        original_path = dataset.dataset.get_file_name()
                        filename = Path(original_path).name
                        dataset_mapping[original_path] = filename
                    except Exception as e:
                        self.logger.warning(f"[{job_id}] Could not map dataset path: {e}")

            # Replace ln -s commands in the tool command line
            # Pattern: ln -s '/absolute/path/dataset_xxx.dat' target_name
            if dataset_mapping:
                self.logger.info(f"[{job_id}] Rewriting {len(dataset_mapping)} symlink path(s) in tool command")

                for abs_path, filename in dataset_mapping.items():
                    # Replace in ln -s commands
                    # Match: ln -s '/abs/path' or ln -s "/abs/path"
                    old_pattern_single = f"ln -s '{abs_path}'"
                    new_pattern_single = f"ln -s \"${{INPUT_DIR}}/{filename}\""

                    old_pattern_double = f'ln -s "{abs_path}"'
                    new_pattern_double = f"ln -s \"${{INPUT_DIR}}/{filename}\""

                    if old_pattern_single in rewritten:
                        rewritten = rewritten.replace(old_pattern_single, new_pattern_single)
                        self.logger.debug(f"[{job_id}] Rewrote symlink: {abs_path} → ${{INPUT_DIR}}/{filename}")
                    elif old_pattern_double in rewritten:
                        rewritten = rewritten.replace(old_pattern_double, new_pattern_double)
                        self.logger.debug(f"[{job_id}] Rewrote symlink: {abs_path} → ${{INPUT_DIR}}/{filename}")

        except Exception as e:
            self.logger.warning(f"[{job_id}] Could not rewrite symlink paths: {e}")
            import traceback
            self.logger.debug(f"[{job_id}] Symlink rewrite error traceback: {traceback.format_exc()}")

        self.logger.info(f"[{job_id}] Script rewriting completed - now compatible with any cloud container")
        self.logger.debug(f"[{job_id}] Rewritten script preview (first 500 chars):\n{rewritten[:500]}")

        return rewritten

    async def _universal_upload_job_files(
        self,
        job_wrapper,
        job_id: str,
        s3_bucket: str,
        s3_client,
        path_rewriter: UniversalPathRewriter
    ):
        """
        Upload ALL job files using universal structure.

        No special handling needed - just organize by type.
        """
        self.logger.info(f"[{job_id}] Uploading job files (universal structure)")

        # 1. Upload input datasets
        input_count = 0
        job = job_wrapper.get_job()

        self.logger.info(f"[{job_id}] Total input_datasets associations: {len(job.input_datasets)}")

        for idx, input_assoc in enumerate(job.input_datasets):
            self.logger.debug(f"[{job_id}] Processing input #{idx}: {input_assoc}")
            self.logger.debug(f"[{job_id}]   has dataset: {input_assoc.dataset is not None}")

            if input_assoc.dataset:
                self.logger.debug(f"[{job_id}]   has dataset.dataset: {input_assoc.dataset.dataset is not None}")

                if input_assoc.dataset.dataset:
                    try:
                        file_path = input_assoc.dataset.dataset.get_file_name()
                        self.logger.info(f"[{job_id}] Input #{idx} file_path: {file_path}")

                        if not Path(file_path).exists():
                            self.logger.warning(f"[{job_id}] Input file does not exist: {file_path}")
                            continue

                        file_size = Path(file_path).stat().st_size
                        self.logger.info(f"[{job_id}] Input file size: {file_size} bytes")

                        # CRITICAL FIX: If input file is empty, try to download from S3
                        # This handles workflow dependencies where previous job output hasn't been downloaded yet
                        if file_size == 0:
                            self.logger.warning(f"[{job_id}] Input file is empty (0 bytes): {file_path}")
                            self.logger.info(f"[{job_id}] Attempting to download from S3 (previous job output)...")

                            # Try to find the previous job's output in S3
                            # Extract dataset filename from path
                            dataset_filename = file_path_obj.name
                            # Extract object store path structure (e.g., objects/3/8/4/dataset_xxx.dat)
                            if '/objects/' in file_path:
                                objects_index = file_path.find('/objects/')
                                relative_path = file_path[objects_index + 1:]  # objects/3/8/4/dataset_xxx.dat

                                # Search for this file in recent job outputs
                                # Try the most likely source: previous job in this workflow
                                try:
                                    current_job_num = int(job_id)
                                    for prev_job_num in range(current_job_num - 1, max(current_job_num - 10, 0), -1):
                                        s3_key = f"jobs/{prev_job_num}/datasets/{relative_path}"
                                        self.logger.info(f"[{job_id}] Trying S3: s3://{s3_bucket}/{s3_key}")

                                        try:
                                            # Check if file exists in S3
                                            s3_client.head_object(Bucket=s3_bucket, Key=s3_key)
                                            # File exists! Download it
                                            self.logger.info(f"[{job_id}] Found in S3, downloading...")
                                            s3_client.download_file(s3_bucket, s3_key, file_path)

                                            # Verify download
                                            new_size = Path(file_path).stat().st_size
                                            if new_size > 0:
                                                self.logger.info(f"[{job_id}] ✅ Successfully downloaded {new_size} bytes from S3")
                                                file_size = new_size
                                                break  # Success!
                                            else:
                                                self.logger.warning(f"[{job_id}] Downloaded file is still empty")
                                        except s3_client.exceptions.NoSuchKey:
                                            continue  # Try next job
                                        except Exception as e:
                                            self.logger.debug(f"[{job_id}] Error checking {s3_key}: {e}")
                                            continue
                                except Exception as e:
                                    self.logger.warning(f"[{job_id}] Could not download from S3: {e}")

                            # If still empty after S3 download attempt, skip this input
                            if file_size == 0:
                                self.logger.error(f"[{job_id}] Input file is still empty after S3 download attempt, skipping")
                                continue

                        # CRITICAL: Preserve Galaxy's object store path structure
                        # Command expects: /galaxy_execution/datasets/objects/e/2/2/dataset_xxx.dat
                        # So we must upload with the same structure under datasets/
                        file_path_obj = Path(file_path)

                        # Extract the path relative to the object store root
                        # e.g., /path/to/database/objects/e/2/2/dataset_xxx.dat → objects/e/2/2/dataset_xxx.dat
                        if '/objects/' in file_path:
                            # Find the objects/ part and everything after it
                            objects_index = file_path.find('/objects/')
                            relative_path = file_path[objects_index + 1:]  # Skip the leading /
                            s3_key = f"jobs/{job_id}/datasets/{relative_path}"
                        else:
                            # Fallback: use simple filename
                            filename = file_path_obj.name
                            s3_key = f"jobs/{job_id}/datasets/objects/{filename}"

                        self.logger.info(f"[{job_id}] Uploading: {file_path} → s3://{s3_bucket}/{s3_key}")
                        s3_client.upload_file(file_path, s3_bucket, s3_key)
                        self.logger.info(f"[{job_id}] ✅ Successfully uploaded input: {s3_key}")
                        input_count += 1
                    except Exception as e:
                        self.logger.error(f"[{job_id}] Failed to upload input: {e}")
                        import traceback
                        self.logger.error(f"[{job_id}] Traceback: {traceback.format_exc()}")

        self.logger.info(f"[{job_id}] Uploaded {input_count} input file(s)")

        # 2. Upload working directory files (if job was prepared)
        self.logger.info(f"[{job_id}] Checking for working files...")
        self.logger.info(f"[{job_id}] hasattr(job_wrapper, 'extra_filenames'): {hasattr(job_wrapper, 'extra_filenames')}")
        if hasattr(job_wrapper, 'extra_filenames'):
            self.logger.info(f"[{job_id}] extra_filenames value: {job_wrapper.extra_filenames}")
            self.logger.info(f"[{job_id}] extra_filenames length: {len(job_wrapper.extra_filenames) if job_wrapper.extra_filenames else 0}")

        if hasattr(job_wrapper, 'extra_filenames') and job_wrapper.extra_filenames:
            working_count = 0
            for extra_file in job_wrapper.extra_filenames:
                try:
                    self.logger.info(f"[{job_id}] Processing extra file: {extra_file}")
                    if Path(extra_file).exists():
                        # 100% Universal approach: use job_id to find the split point
                        # NO assumptions about directory structure or depth
                        extra_file_path = Path(extra_file)
                        parts = extra_file_path.parts

                        # Strategy: Find 'jobs*directory' anchor, then find job_id after it
                        # Everything after job_id is the relative path we want to preserve
                        relative_path = None
                        anchor_idx = None

                        # Step 1: Find the jobs directory anchor
                        for i, part in enumerate(parts):
                            if 'jobs' in part.lower() and 'directory' in part.lower():
                                anchor_idx = i
                                break

                        # Step 2: Find job_id after the anchor
                        if anchor_idx is not None:
                            for j in range(anchor_idx + 1, len(parts)):
                                if parts[j] == job_id or parts[j] == str(job_id):
                                    # Found job_id! Capture everything after it
                                    if j + 1 < len(parts):
                                        relative_path = '/'.join(parts[j + 1:])
                                    break

                        # Fallback: if no structure found, use working/
                        if not relative_path:
                            filename = extra_file_path.name
                            s3_key = f"jobs/{job_id}/working/{filename}"
                        else:
                            s3_key = f"jobs/{job_id}/{relative_path}"

                        s3_client.upload_file(extra_file, s3_bucket, s3_key)
                        self.logger.info(f"[{job_id}] ✅ Uploaded extra file: {extra_file_path.name} to {s3_key}")
                        working_count += 1
                    else:
                        self.logger.warning(f"[{job_id}] Extra file does not exist: {extra_file}")
                except Exception as e:
                    self.logger.warning(f"[{job_id}] Failed to upload working file: {e}")
                    import traceback
                    self.logger.warning(f"[{job_id}] Traceback: {traceback.format_exc()}")

            if working_count > 0:
                self.logger.info(f"[{job_id}] Uploaded {working_count} working file(s)")
            else:
                self.logger.warning(f"[{job_id}] No working files were uploaded (all files missing or failed)")
        else:
            self.logger.warning(f"[{job_id}] No extra_filenames found - working files will not be uploaded")

        # 3. Upload tool scripts/files from shed_tools if referenced in command
        # Tool shed files are not in working directory, need special handling
        # UNIVERSAL APPROACH: Upload entire tool directory, not just specific files
        self.logger.info(f"[{job_id}] Checking for tool files in command...")
        command_line = job_wrapper.runner_command_line or job_wrapper.command_line
        if command_line:
            import re
            import os
            # Find all references to shed_tools paths (ANY file, not just scripts)
            # This regex captures the full path to any file under shed_tools/
            shed_pattern = r'["\']?(/[^"\':\s]*shed_tools/[^"\':\s]+)["\']?'
            shed_matches = re.findall(shed_pattern, command_line)

            if shed_matches:
                # Collect unique tool directories (not individual files)
                # This ensures we upload ALL supporting files, not just what's in the command
                tool_dirs = set()
                for shed_path in shed_matches:
                    if '/shed_tools/' in shed_path:
                        # Find the tool directory (usually the directory containing the main script)
                        # e.g., /Users/.../shed_tools/toolshed.../repos/iuc/deg_annotate/abc123/deg_annotate/
                        # We want to upload the whole version directory (abc123/)

                        shed_index = shed_path.find('/shed_tools/')
                        path_after_shed = shed_path[shed_index + len('/shed_tools/'):]

                        # Extract up to version hash (usually 4-5 levels deep)
                        # toolshed.g2.bx.psu.edu/repos/iuc/deg_annotate/abc123/...
                        parts = path_after_shed.split('/')
                        if len(parts) >= 4:
                            # Take first 4 parts (server/repos/owner/tool/version)
                            tool_version_dir = '/'.join(parts[:5]) if len(parts) >= 5 else '/'.join(parts[:4])
                            shed_base = shed_path[:shed_index + len('/shed_tools/')]
                            full_tool_dir = shed_base + tool_version_dir
                            if Path(full_tool_dir).is_dir():
                                tool_dirs.add(full_tool_dir)

                # Upload entire tool directories (includes scripts, data files, configs, etc.)
                tool_count = 0
                file_count = 0
                for tool_dir in tool_dirs:
                    try:
                        # Extract relative path for S3
                        if '/shed_tools/' in tool_dir:
                            shed_index = tool_dir.find('/shed_tools/')
                            relative_dir = tool_dir[shed_index + len('/shed_tools/'):]

                            self.logger.info(f"[{job_id}] Uploading tool directory: {tool_dir}")

                            # Walk through directory and upload all files
                            for root, dirs, files in os.walk(tool_dir):
                                for file in files:
                                    file_path = os.path.join(root, file)
                                    # Calculate relative path from tool_dir
                                    rel_file_path = os.path.relpath(file_path, tool_dir)
                                    s3_key = f"jobs/{job_id}/tools/{relative_dir}/{rel_file_path}"

                                    try:
                                        s3_client.upload_file(file_path, s3_bucket, s3_key)
                                        file_count += 1
                                    except Exception as e:
                                        self.logger.warning(f"[{job_id}] Failed to upload {file_path}: {e}")

                            tool_count += 1
                    except Exception as e:
                        self.logger.warning(f"[{job_id}] Failed to process tool directory {tool_dir}: {e}")

                if tool_count > 0:
                    self.logger.info(f"[{job_id}] Uploaded {tool_count} tool director(ies) with {file_count} file(s)")
                else:
                    self.logger.info(f"[{job_id}] No tool directories were uploaded (missing or failed)")
            else:
                self.logger.info(f"[{job_id}] No shed_tools paths found in command")

        # 4. Upload configs (if any)
        # Galaxy may generate config files in the working directory
        # These are automatically handled by extra_filenames

        self.logger.info(f"[{job_id}] File upload complete")

    def _generate_universal_job_script(
        self,
        command: str,
        path_rewriter: UniversalPathRewriter,
        job_wrapper
    ) -> str:
        """
        Generate job script using universal approach.

        Creates symlinks for input files so Galaxy's original absolute paths work.
        """
        env_vars = path_rewriter.get_environment_variables()

        script = f"""#!/bin/bash
# Universal Galaxy Cloud Execution Script
# Auto-generated - works for ANY Galaxy tool

set -e  # Exit on error
# NOTE: pipefail NOT used - breaks legitimate pipes (yes | head, etc.)

# Environment (set by fetch-and-run)
{chr(10).join(f'export {k}="${k}"' for k in env_vars.keys())}

# Create symlinks for tool shed scripts (if any)
# Tool scripts are downloaded to /host-tmp/galaxy_shed_tools/
# Create symlinks to match Galaxy's expected paths
if [ -d "/host-tmp/galaxy_shed_tools" ]; then
    echo "Setting up tool script symlinks..."
    # Find the local shed_tools path from command (if any)
    # This will create symlinks so tool scripts can be found at their original paths
    mkdir -p /tmp/galaxy_shed_tools_symlinks
    for tool_file in $(find /host-tmp/galaxy_shed_tools -type f 2>/dev/null); do
        # Get relative path after galaxy_shed_tools/
        rel_path="${{tool_file#/host-tmp/galaxy_shed_tools/}}"
        # Create any local path reference that might be in command
        # We'll create a generic /galaxy/shed_tools/ path
        target_path="/galaxy/shed_tools/${{rel_path}}"
        mkdir -p "$(dirname "${{target_path}}")"
        ln -sf "${{tool_file}}" "${{target_path}}" 2>/dev/null || true
    done
    echo "Tool script symlinks created"
fi

# Create symlinks for input datasets (so original absolute paths work)
"""

        # Add symlink commands for each input dataset
        job = job_wrapper.get_job()
        from pathlib import Path

        for input_assoc in job.input_datasets:
            if input_assoc.dataset and input_assoc.dataset.dataset:
                try:
                    local_input_path = input_assoc.dataset.dataset.get_file_name()
                    # Rewrite local path to container path
                    container_input_path = path_rewriter.rewrite_command(local_input_path)
                    filename = Path(local_input_path).name
                    script += f'mkdir -p "$(dirname "{container_input_path}")"\n'
                    script += f'ln -sf "${{GALAXY_INPUT_DIR}}/{filename}" "{container_input_path}"\n'
                except Exception as e:
                    self.logger.warning(f"Could not create symlink command for input: {e}")

        script += """
# Create directories for all absolute paths used in command
# This is universal - extracts paths from the command itself, not from tool metadata
"""

        # Extract all absolute paths from the rewritten command
        # Pattern matches: /xxx/yyy/zzz (absolute paths starting with /)
        import re
        # Match quoted absolute paths (most common)
        path_pattern = r'["\']([/][^"\']+)["\']'
        paths_in_command = set(re.findall(path_pattern, command))

        # Also match unquoted absolute paths followed by space, semicolon, or end of line
        unquoted_pattern = r'\s(/[^\s;|&<>]+)(?:\s|;|$)'
        paths_in_command.update(re.findall(unquoted_pattern, command))

        # Create parent directories for all paths that might be output files
        # (paths under /galaxy_execution/datasets/ are likely outputs)
        for path in sorted(paths_in_command):
            # Only create directories for paths that look like dataset files
            if '/datasets/' in path and path.endswith('.dat'):
                script += f'mkdir -p "$(dirname "{path}")"\n'

        script += f"""
# Change to working directory (standard execution location)
cd "$GALAXY_WORK_DIR"

echo "Executing tool command..."
echo "Working directory: $(pwd)"

# Execute the rewritten command
{command}

echo "Tool execution complete"
"""

        return script

    def _create_job_spec(self, job_wrapper, job_destination: JobDestination) -> JobSpec:
        """Create cloud job specification from Galaxy job"""

        # Get tool information
        tool = job_wrapper.tool
        tool_id = tool.id if tool else 'unknown'

        # Get container information from tool registry
        future = asyncio.run_coroutine_threadsafe(
            self.tool_registry.get_tool_container(tool_id),
            self._loop
        )
        container_info = future.result(timeout=30)

        if not container_info:
            # get_default_container() returns a dict
            default_container = self.tool_registry.get_default_container()
            # Convert to object-like access for consistency
            image = default_container['image']
            tag = default_container.get('tag', 'latest')
            command = default_container.get('command')
            working_dir = default_container.get('working_dir', '/galaxy-central')
            env_vars = default_container.get('env', {})
            resources = default_container.get('resources', {})
        else:
            # container_info is a ToolContainerInfo dataclass - use attribute access
            image = container_info.image
            tag = container_info.tag
            command = container_info.command
            working_dir = container_info.working_dir
            env_vars = container_info.env
            resources = container_info.resources

        # Build full image URI with tag
        full_image = f"{image}:{tag}" if tag else image

        self.logger.info(f"Using Docker image for tool {tool_id}: {full_image}")

        # Build container specification with file transfers
        command_args, file_transfer_manager = self._build_command_args(job_wrapper, job_destination)

        container_spec = ContainerSpec(
            image=full_image,
            command=command,
            args=command_args,
            env=self._build_environment(job_wrapper, job_destination, env_vars),
            working_dir=working_dir
        )

        # Store file transfer manager for later use in monitoring
        if file_transfer_manager:
            job_wrapper._cloud_file_transfer_manager = file_transfer_manager

        # Determine resource requirements
        resource_spec = self._determine_resources(job_wrapper, job_destination, resources)

        # Get user ID safely - job_wrapper.user might be an object or a string
        if job_wrapper.user:
            if isinstance(job_wrapper.user, str):
                user_id = job_wrapper.user
            elif hasattr(job_wrapper.user, 'id'):
                user_id = str(job_wrapper.user.id)
            else:
                user_id = str(job_wrapper.user)
        else:
            user_id = 'anonymous'

        # Create job specification
        job_spec = JobSpec(
            job_id=f"galaxy-{job_wrapper.get_id_tag()}",
            name=f"Galaxy Job: {tool_id}",
            container=container_spec,
            resources=resource_spec,
            timeout_seconds=self._get_job_timeout(job_wrapper, job_destination),
            retry_attempts=2,
            labels={
                'galaxy_job_id': str(job_wrapper.job_id),
                'galaxy_tool_id': tool_id,
                'galaxy_user': user_id
            }
        )

        return job_spec

    def _build_command_args(self, job_wrapper, job_destination: JobDestination) -> Tuple[List[str], Optional[FileTransferManager]]:
        """
        Build command arguments for the job with file transfer support.

        Returns:
            Tuple of (command_args, file_transfer_manager)
        """
        # DEBUG: Log all job destination params
        self.logger.info(f"Job {job_wrapper.get_id_tag()} destination params: {dict(job_destination.params)}")

        # Get S3 bucket from job destination params
        # Try both 's3_bucket' and 'aws_s3_bucket' for compatibility
        s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
        if not s3_bucket:
            self.logger.warning(f"No S3 bucket configured in job destination params: {list(job_destination.params.keys())}")
            self.logger.warning(f"File transfers will not work for job {job_wrapper.get_id_tag()}")

        # Get or generate command line
        command_line = job_wrapper.runner_command_line

        self.logger.info(f"Job {job_wrapper.get_id_tag()} runner_command_line: {command_line}")

        # If runner_command_line is not set, try command_line
        if not command_line and hasattr(job_wrapper, 'command_line'):
            command_line = job_wrapper.command_line
            self.logger.info(f"Job {job_wrapper.get_id_tag()} using command_line: {command_line}")

        # If still no command, try to prepare the job to generate command
        if not command_line:
            self.logger.info(f"Job {job_wrapper.get_id_tag()} attempting to prepare job to generate command")
            try:
                if hasattr(job_wrapper, 'prepare'):
                    job_wrapper.prepare()
                    command_line = job_wrapper.command_line
                    self.logger.info(f"Job {job_wrapper.get_id_tag()} command_line after prepare: {command_line}")
            except Exception as e:
                self.logger.error(f"Failed to prepare job {job_wrapper.get_id_tag()}: {e}")

        if not command_line:
            self.logger.error(f"Job {job_wrapper.get_id_tag()} has no command line after all attempts!")
            return [], None

        # Initialize file transfer manager if S3 bucket is available
        file_transfer_manager = None
        if s3_bucket:
            try:
                # Create file transfer manager (will use boto3 directly)
                file_transfer_manager = FileTransferManager(
                    s3_bucket=s3_bucket,
                    job_id=job_wrapper.get_id_tag(),
                    storage_provider=None,  # Let it create its own SimpleS3Storage
                    logger=self.logger
                )

                # Prepare job: upload inputs, rewrite command, prepare outputs
                final_command, input_s3_uris, output_s3_uris = file_transfer_manager.prepare_job(
                    job_wrapper, command_line
                )

                self.logger.info(f"Job {job_wrapper.get_id_tag()} prepared with file transfers")
                self.logger.info(f"Uploaded {len(input_s3_uris)} input files")
                self.logger.info(f"Expecting {len(output_s3_uris)} output files")
                self.logger.info(f"Final command (first 150 chars): {final_command[:150]}...")

                # Wrap in shell for execution
                return ["/bin/sh", "-c", final_command], file_transfer_manager

            except Exception as e:
                self.logger.error(f"Failed to prepare file transfers for job {job_wrapper.get_id_tag()}: {e}")
                import traceback
                self.logger.error(traceback.format_exc())
                # Fall back to original command without file transfers
                self.logger.warning("Falling back to command without file transfers")

        # Fallback: use original command wrapped in shell
        self.logger.info(f"Job {job_wrapper.get_id_tag()} using command without file transfers: {command_line[:100]}...")
        return ["/bin/sh", "-c", command_line], None

    def _build_environment(self, job_wrapper, job_destination: JobDestination, env_vars: Dict) -> Dict[str, str]:
        """Build environment variables for the job"""
        env = {}

        # Add container-specific environment
        env.update(env_vars)

        # Add Galaxy-specific environment
        env.update({
            'GALAXY_SLOTS': str(job_destination.params.get('slots', 1)),
            'GALAXY_MEMORY_MB': str(job_destination.params.get('memory', 2048)),
            'GALAXY_JOB_ID': str(job_wrapper.job_id),
            'GALAXY_TOOL_ID': job_wrapper.tool.id if job_wrapper.tool else 'unknown'
        })

        # Add destination environment
        destination_config = self.job_config_parser.get_destination_config(job_destination.id)
        if destination_config:
            env.update(destination_config.env)

        return env

    def _determine_resources(self, job_wrapper, job_destination: JobDestination, resources: Dict) -> ResourceSpec:
        """Determine resource requirements for the job"""

        # Start with container defaults (resources already extracted above)

        # Override with destination parameters
        cpus = int(job_destination.params.get('cpus', resources.get('cpus', 1)))
        memory_mb = int(job_destination.params.get('memory', resources.get('memory_mb', 2048)))
        disk_gb = int(job_destination.params.get('disk', resources.get('disk_gb', 20)))

        # Check for GPU requirements
        gpu = None
        gpu_type = None
        if job_destination.params.get('gpu'):
            gpu = int(job_destination.params.get('gpu', 1))
            gpu_type = job_destination.params.get('gpu_type', 'nvidia.com/gpu')

        return ResourceSpec(
            cpus=cpus,
            memory_mb=memory_mb,
            disk_gb=disk_gb,
            gpu=gpu,
            gpu_type=gpu_type
        )

    def _get_job_timeout(self, job_wrapper, job_destination: JobDestination) -> int:
        """Get job timeout in seconds"""
        # Check destination parameters
        if 'timeout' in job_destination.params:
            return int(job_destination.params['timeout'])

        # Check tool configuration
        if job_wrapper.tool and hasattr(job_wrapper.tool, 'timeout'):
            return job_wrapper.tool.timeout

        # Default timeout
        return 3600  # 1 hour

    async def _submit_fetch_and_run_job(self, job_wrapper, job_destination: JobDestination) -> str:
        """
        Submit job using universal Fetch-and-Run approach.

        This method now uses UniversalPathRewriter for ALL tools,
        eliminating the need for tool-specific logic.
        """
        try:
            import boto3

            job_id = job_wrapper.get_id_tag()
            job = job_wrapper.get_job()

            # Get S3 configuration
            s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
            aws_region = job_destination.params.get('aws_region', 'us-west-2')

            if not s3_bucket:
                raise ValueError("S3 bucket not configured")

            # Get fetch-and-run image
            # Using digest to force AWS Batch to pull the latest version (bypasses cache)
            # IMPORTANT: Image must be linux/amd64 (x86_64) for AWS Batch EC2 instances
            # Updated: 2025-10-31 v2 - Fixed R package detection logic (check .log on first run)
            # Use hardcoded account ID to avoid STS timeout issues
            fetch_and_run_image = job_destination.params.get(
                'fetch_and_run_image',
                f"399683337364.dkr.ecr.{aws_region}.amazonaws.com/galaxy-fetch-and-run@sha256:8e77e3c97c309ef8b71511171928125242555f00bdee7ea7b77d1beb06bbc014"
            )

            # Step 1: ALWAYS prepare job first (generates extra_filenames like _evaluate_expression_.py)
            # Even if command_line exists, prepare() is needed for extra_filenames
            self.logger.info(f"[{job_id}] Preparing job (generates command + extra files)...")
            try:
                job_wrapper.prepare()
            except Exception as e:
                self.logger.warning(f"[{job_id}] Job prepare() raised exception (may be already prepared): {e}")

            command_line = job_wrapper.runner_command_line or job_wrapper.command_line
            if not command_line:
                raise ValueError(f"No command line available for job {job_id}")

            # Step 2: Create universal path rewriter
            path_rewriter = UniversalPathRewriter(job_wrapper, job_id)

            # Step 3: Upload files (AFTER prepare, so extra_filenames exist)
            s3_client = boto3.client('s3', region_name=aws_region)
            await self._universal_upload_job_files(
                job_wrapper,
                job_id,
                s3_bucket,
                s3_client,
                path_rewriter
            )

            # Rewrite command using universal path rewriter
            rewritten_command = path_rewriter.rewrite_command(command_line)

            # ✅ NEW: Generate universal job script
            job_script = self._generate_universal_job_script(
                rewritten_command,
                path_rewriter,
                job_wrapper
            )

            # Upload job script to S3
            script_s3_key = f"jobs/{job_id}/job_script.sh"
            self.logger.debug(f"[{job_id}] Uploading job script to s3://{s3_bucket}/{script_s3_key}")
            s3_client.put_object(
                Bucket=s3_bucket,
                Key=script_s3_key,
                Body=job_script.encode('utf-8'),
                ContentType='text/x-shellscript'
            )

            # Get tool container image (optional - for Docker-in-Docker)
            self.logger.info(f"[{job_id}] Getting tool container image...")
            try:
                import asyncio
                tool_container_image = await asyncio.wait_for(
                    self._get_tool_container_image(job_wrapper),
                    timeout=30.0
                )
                self.logger.info(f"[{job_id}] Tool container image: {tool_container_image or 'none (will run in fetch-and-run container)'}")
            except asyncio.TimeoutError:
                self.logger.warning(f"[{job_id}] Timeout getting tool container image, using none")
                tool_container_image = None
            except Exception as e:
                self.logger.warning(f"[{job_id}] Error getting tool container image: {e}, using none")
                tool_container_image = None

            # Create job spec for fetch-and-run container
            self.logger.info(f"[{job_id}] Creating job specification...")
            job_spec = JobSpec(
                job_id=f"galaxy-{job_id}",
                name=f"Galaxy Job: {job_wrapper.tool.id if job_wrapper.tool else 'unknown'}",
                container=ContainerSpec(
                    image=fetch_and_run_image,
                    command=None,  # Uses ENTRYPOINT from Dockerfile
                    args=None,
                    env={
                        'JOB_SCRIPT_S3_URL': f"s3://{s3_bucket}/{script_s3_key}",
                        'S3_BUCKET': s3_bucket,
                        'JOB_ID': job_id,
                        'AWS_REGION': aws_region,
                        'AWS_DEFAULT_REGION': aws_region,
                        'TOOL_CONTAINER_IMAGE': tool_container_image or '',
                        #'FETCH_AND_RUN_SCRIPT_OVERRIDE': f"s3://{s3_bucket}/scripts/fetch_and_run_biocfix.sh"  # Use fixed script from S3
                    }
                ),
                resources=ResourceSpec(
                    cpus=int(job_destination.params.get('cpus', 2)),
                    memory_mb=int(job_destination.params.get('memory', 4)) * 1024,
                    disk_gb=int(job_destination.params.get('disk', 20))
                ),
                timeout_seconds=self._get_job_timeout(job_wrapper, job_destination),
                retry_attempts=2,
                labels={
                    'galaxy_job_id': str(job_wrapper.job_id),
                    'galaxy_tool_id': job_wrapper.tool.id if job_wrapper.tool else 'unknown',
                    'execution_mode': 'fetch-and-run-universal'
                }
            )

            # Submit to AWS Batch
            self.logger.info(f"[{job_id}] Getting cloud provider and executor...")
            cloud_provider = self._get_cloud_provider(job_destination)
            self.logger.info(f"[{job_id}] Cloud provider: {cloud_provider}")

            import asyncio
            try:
                cloud_executor = await asyncio.wait_for(
                    self._get_cloud_executor(cloud_provider, job_destination),
                    timeout=30.0
                )
                self.logger.info(f"[{job_id}] Got cloud executor, submitting job to AWS Batch...")

                cloud_job_id = await asyncio.wait_for(
                    cloud_executor.submit_job(job_spec),
                    timeout=120.0  # 2 minutes for AWS Batch submission
                )
                self.logger.info(f"[{job_id}] Submitted as cloud job {cloud_job_id} (universal fetch-and-run)")
            except asyncio.TimeoutError as e:
                self.logger.error(f"[{job_id}] Timeout during AWS Batch submission")
                raise RuntimeError(f"Job submission timed out") from e

            # Store S3 info for later download
            job_wrapper._fetch_and_run_s3_bucket = s3_bucket
            job_wrapper._fetch_and_run_job_id = job_id
            job_wrapper._fetch_and_run_aws_region = aws_region

            return cloud_job_id

        except Exception as e:
            self.logger.error(f"Failed to submit fetch-and-run job for {job_wrapper.get_id_tag()}: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
            raise

    async def _get_tool_container_image(self, job_wrapper) -> Optional[str]:
        """
        Get tool-specific container image (if needed).

        Returns None for tools that run in fetch-and-run container.
        """
        if not job_wrapper.tool:
            return None

        tool_id = job_wrapper.tool.id
        tool_version = getattr(job_wrapper.tool, 'version', None)

        # Check if tool explicitly requests a container
        if hasattr(job_wrapper.tool, 'requirements') and job_wrapper.tool.requirements:
            packages = getattr(job_wrapper.tool.requirements, 'packages', [])
            if packages:
                # Get from tool registry
                primary_req = packages[0]
                package_name = getattr(primary_req, 'name', None)
                package_version = getattr(primary_req, 'version', None)

                if package_name:
                    # Look up container
                    try:
                        container_info = await self.tool_registry.get_tool_container(
                            package_name,
                            package_version
                        )
                        if container_info and container_info.image:
                            tag = container_info.tag or 'latest'
                            return f"{container_info.image}:{tag}"
                    except Exception as e:
                        self.logger.warning(f"Could not get container for {package_name}: {e}")
                        # Fallback: use quay.io with version as tag
                        if package_version:
                            fallback_image = f"quay.io/biocontainers/{package_name}:{package_version}"
                            self.logger.info(f"Using fallback image: {fallback_image}")
                            return fallback_image

        # Default: no tool-specific container
        return None

    async def _submit_nextflow_job(self, job_wrapper, job_destination: JobDestination) -> str:
        """Submit job using Nextflow execution."""
        try:
            # Initialize Nextflow executor if not already done
            if self.nextflow_executor is None:
                s3_bucket = job_destination.params.get('s3_bucket') or job_destination.params.get('aws_s3_bucket')
                aws_region = job_destination.params.get('aws_region', 'us-west-2')
                aws_batch_queue = job_destination.params.get('aws_batch_queue', 'galaxy-cloud-queue')
                nextflow_bin = job_destination.params.get('nextflow_bin', 'nextflow')

                self.nextflow_executor = NextflowExecutor(
                    s3_bucket=s3_bucket,
                    aws_region=aws_region,
                    aws_batch_queue=aws_batch_queue,
                    nextflow_bin=nextflow_bin
                )

                # Check if Nextflow is available
                if not self.nextflow_executor.check_nextflow_available():
                    raise RuntimeError("Nextflow is not available. Please install Nextflow first.")

                self.logger.info("Nextflow executor initialized successfully")

            # Extract job information
            job = job_wrapper.get_job()
            command_line = job_wrapper.runner_command_line or job_wrapper.command_line

            # Get input and output paths
            input_paths = []
            for input_assoc in job.input_datasets:
                dataset = input_assoc.dataset
                if dataset and dataset.dataset:
                    try:
                        file_path = dataset.dataset.get_file_name()
                        if file_path and Path(file_path).exists():
                            input_paths.append(file_path)
                    except Exception as e:
                        self.logger.warning(f"Could not get input file path: {e}")

            output_paths = []
            for output_assoc in job.output_datasets:
                dataset = output_assoc.dataset
                if dataset and dataset.dataset:
                    try:
                        file_path = dataset.dataset.get_file_name()
                        if file_path:
                            output_paths.append(file_path)
                    except Exception as e:
                        self.logger.warning(f"Could not get output file path: {e}")

            # Get container image
            container_image = "ubuntu:20.04"  # Default
            if job_wrapper.tool:
                tool_id = job_wrapper.tool.id
                try:
                    container_info = self.tool_registry.get_container_for_tool(tool_id)
                    if container_info and 'image' in container_info:
                        container_image = container_info['image']
                        self.logger.info(f"Using container {container_image} for tool {tool_id}")
                except Exception as e:
                    self.logger.warning(f"Could not get container for tool {tool_id}: {e}")

            # Get resource requirements
            cpu = int(job_destination.params.get('cpus', 2))
            memory_gb = int(job_destination.params.get('memory', 4))

            # Execute via Nextflow
            self.logger.info(f"Executing job {job_wrapper.get_id_tag()} via Nextflow")
            success, message = await self.nextflow_executor.execute_job(
                job_wrapper=job_wrapper,
                command_line=command_line,
                input_paths=input_paths,
                output_paths=output_paths,
                container_image=container_image,
                cpu=cpu,
                memory_gb=memory_gb
            )

            if success:
                return f"nextflow-{job_wrapper.get_id_tag()}"
            else:
                raise RuntimeError(f"Nextflow execution failed: {message}")

        except Exception as e:
            self.logger.error(f"Failed to submit Nextflow job for {job_wrapper.get_id_tag()}: {e}")
            raise

    async def _submit_cloud_job(self, job_wrapper, job_spec: JobSpec, cloud_provider: str, job_destination: JobDestination) -> str:
        """Submit job to cloud executor"""
        try:
            # Get or create cloud executor
            cloud_executor = await self._get_cloud_executor(cloud_provider, job_destination)

            # Submit job
            cloud_job_id = await cloud_executor.submit_job(job_spec)

            self.logger.info(f"Submitted Galaxy job {job_wrapper.get_id_tag()} as cloud job {cloud_job_id}")
            return cloud_job_id

        except Exception as e:
            self.logger.error(f"Failed to submit cloud job for {job_wrapper.get_id_tag()}: {e}")
            raise

    async def _get_cloud_executor(self, provider: str, job_destination: JobDestination = None) -> CloudExecutor:
        """Get or create cloud executor for provider"""
        # Build provider configuration from job destination or default config
        if job_destination:
            provider_config = self._build_provider_config(job_destination)
        else:
            provider_config = self._load_cloud_config().get('cloud_providers', {}).get(provider, {})

        # Create a cache key based on provider and critical config parameters
        # This ensures different IAM roles get different executors
        import hashlib
        import json
        config_key = json.dumps({
            'provider': provider,
            'region': provider_config.get('region'),
            'batch_queue': provider_config.get('batch_queue'),
            'job_role_arn': provider_config.get('job_role_arn'),
            'execution_role_arn': provider_config.get('execution_role_arn')
        }, sort_keys=True)
        cache_key = f"{provider}:{hashlib.md5(config_key.encode()).hexdigest()[:8]}"

        if cache_key not in self.cloud_executors:
            # Map provider to executor type
            # Provider should already be normalized to executor type (e.g., 'aws-batch')
            # But keep mapping for backward compatibility
            executor_type_map = {
                'aws': 'aws-batch',
                'aws-batch': 'aws-batch',
                'azure': 'azure-batch',
                'azure-batch': 'azure-batch',
                'gcp': 'gcp-batch',
                'gcp-batch': 'gcp-batch',
                'kubernetes': 'kubernetes'
            }

            executor_type = executor_type_map.get(provider, 'aws-batch')
            executor = CloudExecutorFactory.create(executor_type, provider_config)

            await executor.__aenter__()
            self.cloud_executors[cache_key] = executor
            self.logger.info(f"Created new cloud executor with cache key: {cache_key}, config: {provider_config}")

        return self.cloud_executors[cache_key]

    def check_watched_items(self):
        """Check status of active jobs"""
        try:
            # Check each active job
            for job_id, job_state in list(self.active_jobs.items()):
                if job_state.future.done() and not job_state.monitoring_started:
                    try:
                        cloud_job_id = job_state.future.result()
                        # Mark monitoring as started to prevent duplicate monitoring
                        job_state.monitoring_started = True
                        # Start monitoring this job
                        asyncio.run_coroutine_threadsafe(
                            self._monitor_cloud_job(job_state, cloud_job_id),
                            self._loop
                        )
                    except Exception as e:
                        self.logger.error(f"Job {job_id} submission failed: {e}")
                        job_state.job_wrapper.fail(f"Cloud job submission failed: {e}")
                        del self.active_jobs[job_id]

        except Exception as e:
            self.logger.error(f"Error checking watched items: {e}")

    async def _monitor_cloud_job(self, job_state: 'CloudJobState', cloud_job_id: str):
        """Monitor a cloud job and update Galaxy job status"""
        try:
            from galaxy.model import Job

            job_wrapper = job_state.job_wrapper
            cloud_provider = self._get_cloud_provider(job_wrapper.job_destination)
            cloud_executor = await self._get_cloud_executor(cloud_provider, job_wrapper.job_destination)

            # Wait for job completion
            result = await cloud_executor.wait_for_completion(cloud_job_id)

            # Update Galaxy job based on result
            if result.status == JobStatus.COMPLETED:
                # Download output files from S3 if file transfer manager was used
                if hasattr(job_wrapper, '_cloud_file_transfer_manager'):
                    file_transfer_manager = job_wrapper._cloud_file_transfer_manager
                    try:
                        self.logger.info(f"Downloading output files for job {cloud_job_id}")
                        downloaded_files = file_transfer_manager.download_outputs()
                        self.logger.info(f"Downloaded {len(downloaded_files)} output files")

                        # Cleanup S3 staging area
                        file_transfer_manager.cleanup_s3_staging()

                    except Exception as e:
                        self.logger.error(f"Failed to download outputs for job {cloud_job_id}: {e}")
                        import traceback
                        self.logger.error(traceback.format_exc())
                        # Don't fail the job, just log the error
                        # The tool may have still completed successfully
                else:
                    # Fetch-and-run mode: Download datasets from S3
                    try:
                        job_id = job_wrapper.get_id_tag()

                        # Get S3 configuration - try multiple sources
                        s3_bucket = None
                        aws_region = 'us-west-2'

                        # Try 1: object_store_config (if using S3 object store)
                        if hasattr(self.app.config, 'object_store_config') and self.app.config.object_store_config:
                            object_store_cfg = self.app.config.object_store_config
                            if isinstance(object_store_cfg, dict):
                                config_section = object_store_cfg.get('config', {})
                                s3_bucket = config_section.get('s3_bucket')
                                aws_region = config_section.get('s3_region', aws_region)

                        # Try 2: job destination params (fallback)
                        if not s3_bucket:
                            job_dest = job_wrapper.job_destination
                            s3_bucket = job_dest.params.get('s3_bucket') or job_dest.params.get('aws_s3_bucket')
                            aws_region = job_dest.params.get('aws_region', aws_region)

                        # Try 3: Use the stored bucket from job submission
                        if not s3_bucket and hasattr(job_wrapper, '_fetch_and_run_s3_bucket'):
                            s3_bucket = job_wrapper._fetch_and_run_s3_bucket
                            aws_region = job_wrapper._fetch_and_run_aws_region

                        if s3_bucket:
                            self.logger.info(f"[{job_id}] Found S3 bucket: {s3_bucket} in region {aws_region}")

                            import boto3
                            from pathlib import Path
                            s3_client = boto3.client('s3', region_name=aws_region)

                            # Download datasets from S3 to local Galaxy database
                            s3_prefix = f"jobs/{job_id}/datasets/"
                            self.logger.info(f"[{job_id}] Downloading datasets from s3://{s3_bucket}/{s3_prefix}")

                            # List all files in datasets/
                            response = s3_client.list_objects_v2(Bucket=s3_bucket, Prefix=s3_prefix)
                            if 'Contents' in response:
                                download_count = 0
                                for obj in response['Contents']:
                                    s3_key = obj['Key']
                                    # Extract relative path: jobs/853/datasets/objects/b/0/5/file.dat → objects/b/0/5/file.dat
                                    relative_path = s3_key.replace(s3_prefix, '')

                                    # Construct local path in Galaxy database
                                    local_path = Path(self.app.config.file_path) / relative_path

                                    # Create parent directories
                                    local_path.parent.mkdir(parents=True, exist_ok=True)

                                    # Download file
                                    self.logger.info(f"[{job_id}] Downloading: s3://{s3_bucket}/{s3_key} → {local_path}")
                                    s3_client.download_file(s3_bucket, s3_key, str(local_path))
                                    download_count += 1

                                self.logger.info(f"[{job_id}] Downloaded {download_count} dataset file(s)")

                                # CRITICAL: Also copy downloaded files to this job's output dataset paths
                                # This handles cases where S3 has old dataset UUIDs but job expects new ones
                                self.logger.info(f"[{job_id}] Copying downloads to output dataset paths...")
                                job = job_wrapper.get_job()
                                for output_assoc in job.output_datasets:
                                    if output_assoc.dataset and output_assoc.dataset.dataset:
                                        try:
                                            # Get the expected output file path for this dataset
                                            expected_path = output_assoc.dataset.dataset.get_file_name()
                                            expected_path_obj = Path(expected_path)

                                            # Check if file is empty (needs data from S3)
                                            if expected_path_obj.exists():
                                                file_size = expected_path_obj.stat().st_size
                                                if file_size == 0:
                                                    # File is empty, try to find matching downloaded file
                                                    # Match by filename pattern or order
                                                    for obj in response['Contents']:
                                                        s3_key = obj['Key']
                                                        relative_path = s3_key.replace(s3_prefix, '')
                                                        downloaded_path = Path(self.app.config.file_path) / relative_path

                                                        if downloaded_path.exists() and downloaded_path.stat().st_size > 0:
                                                            # Copy downloaded file to expected output path
                                                            import shutil
                                                            self.logger.info(f"[{job_id}] Copying {downloaded_path} → {expected_path}")
                                                            shutil.copy2(str(downloaded_path), expected_path)
                                                            # Only copy first non-empty file to this output
                                                            break
                                        except Exception as e:
                                            self.logger.warning(f"[{job_id}] Could not copy to output dataset: {e}")
                            else:
                                self.logger.info(f"[{job_id}] No datasets found in S3")
                        else:
                            self.logger.warning(f"[{job_id}] No S3 bucket configured - cannot download datasets from cloud")
                    except Exception as e:
                        self.logger.error(f"[{job_id}] Failed to download datasets from S3: {e}")
                        import traceback
                        self.logger.error(traceback.format_exc())
                        # Don't fail the job, just log the error

                job_wrapper.change_state(Job.states.OK)
                # Pass tool output logs to Galaxy for display in WebUI
                job_wrapper.finish(result.stdout or "", result.stderr or "")
            else:
                error_msg = result.error_message or f"Cloud job failed with status: {result.status}"
                job_wrapper.fail(error_msg)

            # Remove from active jobs
            job_id = job_wrapper.get_id_tag()
            if job_id in self.active_jobs:
                del self.active_jobs[job_id]

        except Exception as e:
            self.logger.error(f"Error monitoring cloud job {cloud_job_id}: {e}")
            job_state.job_wrapper.fail(f"Cloud job monitoring failed: {e}")

            # Remove from active jobs to prevent infinite retry
            job_id = job_state.job_wrapper.get_id_tag()
            if job_id in self.active_jobs:
                del self.active_jobs[job_id]
                self.logger.info(f"Removed failed job {job_id} from active jobs")

    def stop_job(self, job_wrapper):
        """Stop a running job"""
        job_id = job_wrapper.get_id_tag()

        if job_id in self.active_jobs:
            job_state = self.active_jobs[job_id]

            # Cancel the job if it's still submitting
            if not job_state.future.done():
                job_state.future.cancel()

            # If it's already submitted, cancel on cloud
            elif job_state.future.done() and not job_state.future.cancelled():
                try:
                    cloud_job_id = job_state.future.result()
                    # Cancel cloud job asynchronously
                    asyncio.run_coroutine_threadsafe(
                        self._cancel_cloud_job(cloud_job_id, job_wrapper),
                        self._loop
                    )
                except Exception as e:
                    self.logger.error(f"Failed to cancel cloud job for {job_id}: {e}")

            del self.active_jobs[job_id]

    async def _cancel_cloud_job(self, cloud_job_id: str, job_wrapper):
        """Cancel a cloud job"""
        try:
            cloud_provider = self._get_cloud_provider(job_wrapper.job_destination)
            cloud_executor = await self._get_cloud_executor(cloud_provider, job_wrapper.job_destination)
            await cloud_executor.cancel_job(cloud_job_id)
            self.logger.info(f"Cancelled cloud job {cloud_job_id}")
        except Exception as e:
            self.logger.error(f"Failed to cancel cloud job {cloud_job_id}: {e}")

    def recover(self, job, job_wrapper):
        """Recover a job after Galaxy restart"""
        # For cloud jobs, we would need to query the cloud executor
        # to get the current status of the job
        self.logger.info(f"Attempting to recover job {job.id}")

        # For now, mark as failed since we don't have persistent job tracking
        job_wrapper.fail("Job recovery not implemented for cloud executor")

    def shutdown(self):
        """Shutdown the job runner"""
        self.logger.info("Shutting down Galaxy Cloud Job Runner")

        # Cancel all active jobs
        for job_state in self.active_jobs.values():
            if not job_state.future.done():
                job_state.future.cancel()

        # Close cloud executors
        if self._loop and not self._loop.is_closed():
            for executor in self.cloud_executors.values():
                asyncio.run_coroutine_threadsafe(
                    executor.__aexit__(None, None, None),
                    self._loop
                )

        # Stop event loop
        if self._loop and not self._loop.is_closed():
            self._loop.call_soon_threadsafe(self._loop.stop)

        # Close tool registry and data manager
        if hasattr(self, 'tool_registry'):
            asyncio.run_coroutine_threadsafe(
                self.tool_registry.close(),
                self._loop
            )

        if hasattr(self, 'data_manager'):
            asyncio.run_coroutine_threadsafe(
                self.data_manager.close(),
                self._loop
            )

        super().shutdown()


class CloudJobState(AsynchronousJobState):
    """State for a cloud job"""

    def __init__(self, job_wrapper, future):
        super().__init__(
            files_dir=None,
            job_wrapper=job_wrapper,
            job_id=None,
            job_file=None,
            output_file=None,
            error_file=None
        )
        self.future = future  # Future for job submission
        self.monitoring_started = False  # Flag to prevent duplicate monitoring