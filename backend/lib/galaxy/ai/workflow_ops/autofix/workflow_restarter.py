"""
Workflow Restarter - Restarts workflows after AutoFix applies fixes

This module provides functionality to restart a workflow invocation
with updated parameters after AutoFix has applied corrections.

IMPORTANT: This uses Galaxy's official workflow invocation API to ensure
proper workflow execution, parameter handling, and job scheduling.
"""

import logging
from typing import Dict, Any, Optional
import json

try:
    from galaxy.model import WorkflowInvocation
    from galaxy.exceptions import RequestParameterInvalidException
    from galaxy.workflow.run_request import build_workflow_run_configs
    from galaxy.workflow.run import queue_invoke
    _GALAXY_MODEL_AVAILABLE = True
except ImportError:
    WorkflowInvocation = None  # type: ignore[assignment,misc]
    RequestParameterInvalidException = Exception  # type: ignore[assignment,misc]
    build_workflow_run_configs = None  # type: ignore[assignment]
    queue_invoke = None  # type: ignore[assignment]
    _GALAXY_MODEL_AVAILABLE = False

log = logging.getLogger(__name__)


class WorkflowRestarter:
    """
    Service for restarting workflows after AutoFix

    Key features:
    - Uses Galaxy's official workflow invocation API
    - Properly handles parameter conversion and validation
    - Preserves original input files and datasets
    - Ensures correct job scheduling through workflow_scheduling_manager
    """

    def __init__(self, app):
        """
        Initialize workflow restarter

        Args:
            app: Galaxy app instance
        """
        self.app = app
        self.sa_session = app.model.context

        # Initialize LLM-driven parameter mapper for AutoFix parameter translation
        from .llm_parameter_mapper import LLMParameterMapper
        from .parameter_mapper import UniversalParameterMapper
        try:
            # Try to get LLM client from app for intelligent mapping
            from galaxy.ai.workflow_ops.llm_client import UnifiedLLMClient
            llm_client = UnifiedLLMClient(app.config)
            self.parameter_mapper = LLMParameterMapper(llm_client=llm_client, enable_learning=True)
            log.info("✅ LLMParameterMapper initialized (LLM-first mode with learning)")
        except Exception as e:
            log.warning(f"Failed to initialize LLM mapper: {e}, falling back to config-based mapper")
            self.parameter_mapper = UniversalParameterMapper(llm_client=None)

    def restart_workflow(
        self,
        original_invocation_id: int,
        updated_parameters: Optional[Dict[str, Any]] = None,
        auto_start: bool = True,
        trans=None,
    ) -> Dict[str, Any]:
        """
        Restart a workflow with updated parameters using Galaxy's official API

        Args:
            original_invocation_id: ID of the failed workflow invocation
            updated_parameters: Updated parameters to use (will be merged with original)
            auto_start: Whether to automatically start the workflow (default: True)
            trans: Galaxy transaction context (required for proper workflow execution)

        Returns:
            Dictionary with:
                - success: bool
                - new_invocation_id: int (if successful)
                - message: str
                - original_invocation_id: int
                - updated_parameters: list of parameter names that were updated

        Raises:
            ValueError: If original invocation not found or invalid
        """
        # 1. Get original invocation
        original_invocation = self.sa_session.query(WorkflowInvocation).get(original_invocation_id)
        if not original_invocation:
            raise ValueError(f"Workflow invocation {original_invocation_id} not found")

        # 2. Get workflow
        workflow = original_invocation.workflow
        if not workflow:
            raise ValueError(f"Workflow not found for invocation {original_invocation_id}")

        # 3. Get history
        history = original_invocation.history
        if not history:
            raise ValueError(f"History not found for invocation {original_invocation_id}")

        log.info(f"🔄 Restarting workflow '{workflow.name}' (invocation {original_invocation_id})")
        log.info(f"   User: {history.user_id}")
        log.info(f"   History: {history.id}")

        try:
            # 4. Map AutoFix parameters to pipeline-specific parameters
            mapped_parameters = updated_parameters
            if updated_parameters:
                pipeline_name = self._detect_pipeline_name(workflow, original_invocation)
                if pipeline_name:
                    log.info(f"🔍 Detected pipeline: {pipeline_name}")
                    log.info(f"📋 Mapping {len(updated_parameters)} AutoFix parameters...")
                    log.info(f"   Input: {updated_parameters}")

                    try:
                        # 🆕 Extract pipeline schema and config for LLM context
                        pipeline_schema = self._extract_pipeline_schema(workflow, original_invocation)
                        workflow_config = self._extract_workflow_config(original_invocation)

                        # Map parameters using appropriate mapper
                        if isinstance(self.parameter_mapper, LLMParameterMapper):
                            # LLM mapper accepts rich context
                            mapped_parameters = self.parameter_mapper.map_fix_params(
                                pipeline_name=pipeline_name,
                                fix_params=updated_parameters,
                                pipeline_schema=pipeline_schema,
                                workflow_config=workflow_config
                            )
                        else:
                            # UniversalParameterMapper fallback (config-based)
                            mapped_parameters = self.parameter_mapper.map_fix_params(
                                pipeline_name=pipeline_name,
                                fix_params=updated_parameters,
                                pipeline_config=pipeline_schema  # Use schema as config
                            )
                        log.info(f"   ✅ Mapped to {len(mapped_parameters)} pipeline parameters:")
                        for key, value in mapped_parameters.items():
                            log.info(f"      {key} = {value}")
                    except Exception as e:
                        log.error(f"   ❌ Parameter mapping failed: {e}, using original parameters")
                        mapped_parameters = updated_parameters
                else:
                    log.warning("Could not detect pipeline name, using direct parameter mapping")

            # 5. Build payload from original invocation
            payload = self._build_invoke_payload(
                original_invocation,
                mapped_parameters
            )

            # Log parameter updates
            if updated_parameters:
                log.info(f"📝 Applying {len(updated_parameters)} parameter updates:")
                for key, value in updated_parameters.items():
                    log.info(f"   {key} = {value}")

            # 5. Create transaction context if not provided
            if trans is None:
                trans = self._create_trans_context(history.user)

            # 6. Build workflow run configuration
            # This handles all parameter conversion, validation, and input dataset mapping
            run_configs = build_workflow_run_configs(trans, workflow, payload)

            if not run_configs or len(run_configs) == 0:
                raise ValueError("Failed to build workflow run configuration")

            # Use first config (non-batch mode)
            run_config = run_configs[0]

            log.info(f"🚀 Invoking workflow using Galaxy's queue_invoke API...")

            # 7. Queue workflow using Galaxy's official API
            # This is the KEY fix - using Galaxy's proper workflow invocation mechanism
            request_params = {
                'scheduler': original_invocation.scheduler or 'default',
            }

            new_invocation = queue_invoke(
                trans=trans,
                workflow=workflow,
                workflow_run_config=run_config,
                request_params=request_params,
                populate_state=True,
                flush=True,
            )

            new_invocation_id = new_invocation.id
            log.info(f"✅ Successfully created and queued new workflow invocation {new_invocation_id}")
            log.info(f"   State: {new_invocation.state}")
            log.info(f"   Scheduler: {new_invocation.scheduler}")

            # Commit transaction
            self.sa_session.commit()

            return {
                'success': True,
                'new_invocation_id': new_invocation_id,
                'message': f'Workflow restarted successfully. New invocation ID: {new_invocation_id}',
                'original_invocation_id': original_invocation_id,
                'updated_parameters': list(updated_parameters.keys()) if updated_parameters else [],
            }

        except Exception as e:
            log.error(f"❌ Failed to restart workflow: {e}")
            import traceback
            traceback.print_exc()

            self.sa_session.rollback()

            return {
                'success': False,
                'message': f'Failed to restart workflow: {str(e)}',
                'error': str(e),
            }

    def _detect_pipeline_name(self, workflow, invocation) -> Optional[str]:
        """
        Detect the pipeline name from workflow metadata

        Tries multiple strategies:
        1. Check workflow tags for nf-core pipeline names
        2. Check tool IDs in workflow steps
        3. Check workflow name

        Args:
            workflow: Workflow object
            invocation: WorkflowInvocation object

        Returns:
            Pipeline name (e.g., 'clipseq', 'rnaseq') or None
        """
        # Strategy 1: Check workflow tags
        if hasattr(workflow, 'tags'):
            for tag in workflow.tags:
                tag_name = tag.user_tname if hasattr(tag, 'user_tname') else str(tag)
                # Common nf-core pipeline names
                known_pipelines = ['clipseq', 'rnaseq', 'smrnaseq', 'atacseq', 'chipseq',
                                 'methylseq', 'sarek', 'viralrecon', 'mag', 'ampliseq']
                if tag_name.lower() in known_pipelines:
                    return tag_name.lower()

        # Strategy 2: Check tool IDs in workflow steps
        if hasattr(workflow, 'steps'):
            for step in workflow.steps:
                if step.tool_id:
                    # Extract pipeline name from tool ID
                    # e.g., 'clipseq_v2' -> 'clipseq'
                    tool_id = step.tool_id
                    for pipeline in ['clipseq', 'rnaseq', 'smrnaseq', 'atacseq']:
                        if pipeline in tool_id.lower():
                            return pipeline

        # Strategy 3: Check workflow name
        if hasattr(workflow, 'name'):
            name_lower = workflow.name.lower()
            for pipeline in ['clipseq', 'rnaseq', 'smrnaseq', 'atacseq']:
                if pipeline in name_lower:
                    return pipeline

        log.warning(f"Could not detect pipeline name for workflow '{workflow.name}'")
        return None

    def _extract_pipeline_schema(self, workflow, invocation) -> Optional[Dict[str, Any]]:
        """
        Extract pipeline schema from Nextflow package

        Returns nextflow_schema.json if available
        """
        try:
            # Find the engine step (Nextflow tool)
            for step in workflow.steps:
                if step.tool_id and ('nextflow' in step.tool_id.lower() or step.type == 'tool'):
                    # Try to extract tool path
                    tool = step.tool
                    if hasattr(tool, 'tool_dir'):
                        tool_dir = Path(tool.tool_dir)
                        schema_file = tool_dir / 'nextflow_schema.json'

                        if schema_file.exists():
                            with open(schema_file, 'r') as f:
                                schema = json.load(f)
                            log.info(f"   📄 Loaded pipeline schema from {schema_file}")
                            return schema

            # Fallback: Try to find from jobs directory
            from galaxy.config import Configuration
            config = self.app.config
            if hasattr(config, 'jobs_directory'):
                jobs_dir = Path(config.jobs_directory)
                workflow_dir = jobs_dir / f"nextflow_workflows/workflow_{invocation.id}"

                # Check if there's a nextflow package reference
                if workflow_dir.exists():
                    # Look for nextflow_schema.json in common locations
                    for pattern in ['nextflow_schema.json', '*/nextflow_schema.json']:
                        schema_files = list(workflow_dir.glob(pattern))
                        if schema_files:
                            with open(schema_files[0], 'r') as f:
                                schema = json.load(f)
                            log.info(f"   📄 Loaded pipeline schema from {schema_files[0]}")
                            return schema

        except Exception as e:
            log.debug(f"Could not extract pipeline schema: {e}")

        log.debug("No pipeline schema found, LLM will work without it")
        return None

    def _extract_workflow_config(self, invocation) -> Optional[Dict[str, Any]]:
        """
        Extract current workflow configuration parameters

        This helps LLM understand what parameters are currently in use
        """
        try:
            config = {}

            # Extract from input_parameters
            if invocation.input_parameters:
                for param in invocation.input_parameters:
                    if hasattr(param, 'name') and hasattr(param, 'value'):
                        value = param.value
                        if isinstance(value, str):
                            try:
                                value = json.loads(value)
                            except (json.JSONDecodeError, TypeError):
                                pass
                        config[param.name] = value

            if config:
                log.info(f"   📋 Extracted {len(config)} config parameters from invocation")
                return config

        except Exception as e:
            log.debug(f"Could not extract workflow config: {e}")

        return None

    def _build_invoke_payload(
        self,
        original_invocation: WorkflowInvocation,
        updated_parameters: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Build workflow invocation payload from original invocation

        This reconstructs the payload in the same format that Galaxy's workflow
        API expects, ensuring proper parameter handling.

        Args:
            original_invocation: Original workflow invocation
            updated_parameters: Parameters to update (merged with original)

        Returns:
            Payload dictionary suitable for build_workflow_run_configs
        """
        payload = {}

        # 1. Copy history target
        # IMPORTANT: Must use encoded history ID, not raw integer
        history = original_invocation.history
        if hasattr(self.app, 'security') and self.app.security:
            payload['history_id'] = self.app.security.encode_id(history.id)
        else:
            # Fallback: create encoder if app.security not available
            from galaxy.security.idencoding import IdEncodingHelper
            id_secret = "USING THE DEFAULT IS NOT SECURE!"
            security = IdEncodingHelper(id_secret=id_secret)
            payload['history_id'] = security.encode_id(history.id)

        # 2. Rebuild parameters from original invocation
        # Galaxy stores parameters in a specific format in workflow_request_input_parameters
        # When parameters_normalized=True, Galaxy expects keys to be step.order_index (not step.id)
        params_dict = {}

        # Build a mapping from step ID to order_index
        workflow = original_invocation.workflow
        step_id_to_order_index = {}
        for step in workflow.steps:
            step_id_to_order_index[str(step.id)] = str(step.order_index)
            log.info(f"   Step mapping: step_id {step.id} -> order_index {step.order_index} (type: {step.type}, tool: {step.tool_id})")

        if original_invocation.input_parameters:
            for param in original_invocation.input_parameters:
                if hasattr(param, 'name') and hasattr(param, 'value'):
                    # Parse JSON value if it's a string
                    value = param.value
                    if isinstance(value, str):
                        try:
                            value = json.loads(value)
                        except (json.JSONDecodeError, TypeError):
                            pass  # Keep as string if not JSON

                    # Convert step ID to order_index if the parameter name is a step ID
                    param_name = param.name
                    if param_name in step_id_to_order_index:
                        # This parameter is for a specific step - use order_index instead of step ID
                        param_name = step_id_to_order_index[param_name]
                        log.info(f"   Converted param key: {param.name} -> {param_name}")

                    params_dict[param_name] = value
                    log.info(f"   Original param: {param_name} = {value if len(str(value)) < 100 else str(value)[:100] + '...'}")

        # 3. Apply parameter updates
        if updated_parameters:
            log.info(f"🔧 Applying {len(updated_parameters)} parameter updates from AutoFix...")

            # For Nextflow workflows, parameters are stored in a large JSON blob
            # in the step parameter (order_index=1 for tool step)
            # We need to find this blob and merge the updates into it

            # Find the tool step parameter (usually order_index=1, containing tool form data)
            tool_step_param_key = None
            for param_name, param_value in params_dict.items():
                # Look for the parameter that contains the tool form data
                # It's a dict with keys like 'section_*|param_*' or 'use_test_profile'
                if isinstance(param_value, dict) and ('use_test_profile' in param_value or
                                                       any(k.startswith('section_') for k in param_value.keys())):
                    tool_step_param_key = param_name
                    log.info(f"   Found tool step parameter at key: {param_name}")
                    break

            # Apply updates
            for key, value in updated_parameters.items():
                log.info(f"   Applying update: {key} = {value}")

                if key in params_dict:
                    # Direct top-level parameter (like 'params.outdir')
                    params_dict[key] = value
                    log.info(f"     ✅ Updated top-level parameter: {key}")
                elif tool_step_param_key and isinstance(params_dict[tool_step_param_key], dict):
                    # Merge into tool step parameters
                    # Convert parameter name to Galaxy tool form format
                    # e.g., 'skip_filter_gtf' -> 'section_logic_options|param_skip_filter_gtf'

                    # First, try to find if the parameter already exists in the tool form
                    found = False
                    for form_key in params_dict[tool_step_param_key].keys():
                        if form_key.endswith(f'param_{key}') or form_key == key:
                            params_dict[tool_step_param_key][form_key] = value
                            log.info(f"     ✅ Updated existing tool param: {form_key}")
                            found = True
                            break

                    if not found:
                        # Add as a new parameter (try common section names)
                        # For Nextflow parameters, common sections are:
                        # - section_logic_options
                        # - section_reference_genome_options
                        # - section_generic_options

                        # Default: add to logic_options section
                        form_key = f'section_logic_options|param_{key}'
                        params_dict[tool_step_param_key][form_key] = value
                        log.info(f"     ✅ Added new tool param: {form_key}")
                else:
                    # Fallback: add as top-level parameter
                    params_dict[key] = value
                    log.info(f"     ⚠️  Added as top-level parameter: {key} (no tool step found)")

        # 4. Add all parameters to payload
        payload['parameters'] = params_dict
        payload['parameters_normalized'] = True

        # 5. Copy input datasets
        # IMPORTANT: Must use workflow step ID as key, not label
        inputs = {}
        if hasattr(original_invocation, 'input_datasets'):
            for input_assoc in original_invocation.input_datasets:
                if hasattr(input_assoc, 'workflow_step_id') and hasattr(input_assoc, 'dataset'):
                    step_id = str(input_assoc.workflow_step_id)
                    dataset_id = input_assoc.dataset.id

                    # Encode dataset ID for Galaxy API
                    if hasattr(self.app, 'security') and self.app.security:
                        encoded_dataset_id = self.app.security.encode_id(dataset_id)
                    else:
                        from galaxy.security.idencoding import IdEncodingHelper
                        id_secret = "USING THE DEFAULT IS NOT SECURE!"
                        security = IdEncodingHelper(id_secret=id_secret)
                        encoded_dataset_id = security.encode_id(dataset_id)

                    inputs[step_id] = {
                        'id': encoded_dataset_id,
                        'src': 'hda',  # history dataset
                    }
                    log.info(f"   Mapped input: step {step_id} -> dataset {encoded_dataset_id}")

        if inputs:
            payload['inputs'] = inputs
            # IMPORTANT: Must specify how inputs are keyed
            payload['inputs_by'] = 'step_id'  # We're using workflow step IDs as keys
        else:
            log.warning("⚠️  No input datasets found in original invocation!")

        # 6. Set other required fields
        payload['allow_tool_state_corrections'] = True
        payload['use_cached_job'] = False

        log.info(f"📦 Built payload with {len(params_dict)} parameters and {len(inputs)} inputs")

        return payload

    def _create_trans_context(self, user):
        """
        Create a minimal transaction context for workflow invocation

        This creates a transaction context with the necessary attributes
        for Galaxy's workflow invocation system.

        Args:
            user: Galaxy user model

        Returns:
            Transaction context object
        """
        # Create a simple transaction context
        # We don't need to import GalaxyWebTransaction - just create a compatible object
        class TransactionContext:
            def __init__(self, app, user):
                self.app = app
                self.user = user
                self.sa_session = app.model.context
                self.security = app.security
                self.history = None  # Will be set by workflow invocation

                # For anonymous user check
                self.anonymous = (user is None)

                # Workflow building mode (not in building mode for AutoFix)
                self.workflow_building_mode = False

                # Short-term cache for workflow invocation
                self._short_term_cache = {}

                # Galaxy session (optional)
                self.galaxy_session = None

                # URL builder (optional, not needed for AutoFix)
                self.url_builder = None

            def check_user_activation(self):
                """Check if user account is activated"""
                if self.user and hasattr(self.user, 'active') and not self.user.active:
                    from galaxy.exceptions import UserActivationRequiredException
                    raise UserActivationRequiredException("User activation required")

            def get_history(self):
                """Get user's current history"""
                return self.history

            @property
            def user_is_admin(self) -> bool:
                """Check if user is an admin"""
                return self.app.config.is_admin_user(self.user)

            @property
            def user_is_bootstrap_admin(self) -> bool:
                """Check if user is a bootstrap admin"""
                return not self.anonymous and self.user.bootstrap_admin_user

            @property
            def user_can_do_run_as(self) -> bool:
                """Check if user can run as another user"""
                return self.app.user_manager.user_can_do_run_as(self.user)

            @property
            def user_is_active(self) -> bool:
                """Check if user is active"""
                return not self.app.config.user_activation_on or self.user is None or self.user.active

            def set_cache_value(self, args: tuple, value):
                """Set a cache value"""
                self._short_term_cache[args] = value

            def get_cache_value(self, args: tuple, default=None):
                """Get a cache value"""
                return self._short_term_cache.get(args, default)

        trans = TransactionContext(self.app, user)
        return trans

    def get_restart_status(self, new_invocation_id: int) -> Dict[str, Any]:
        """
        Check the status of a restarted workflow

        Args:
            new_invocation_id: ID of the new workflow invocation

        Returns:
            Dictionary with status information
        """
        invocation = self.sa_session.query(WorkflowInvocation).get(new_invocation_id)
        if not invocation:
            return {
                'found': False,
                'message': f'Invocation {new_invocation_id} not found',
            }

        return {
            'found': True,
            'invocation_id': new_invocation_id,
            'state': invocation.state,
            'workflow_name': invocation.workflow.name if invocation.workflow else 'Unknown',
            'create_time': invocation.create_time.isoformat() if invocation.create_time else None,
            'update_time': invocation.update_time.isoformat() if invocation.update_time else None,
        }
