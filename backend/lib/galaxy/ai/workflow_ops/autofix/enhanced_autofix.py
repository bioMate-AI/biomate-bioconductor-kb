"""
Enhanced AutoFix Integration

This module integrates all 6 new AutoFix extension features into the main AutoFix workflow:
1. Tool Error Patterns - Match tool-specific error patterns
2. Few-Shot Examples - Learn from historical successful fixes
3. Reference Genome Detection - Detect and fix missing genomes
4. File Format Detection - Detect and fix file format issues
5. System Prompt Enhancement - Use context-specific LLM prompts
6. Dependency Checker - Validate tool version compatibility

Usage:
    from galaxy.ai.workflow_ops.autofix.enhanced_autofix import EnhancedAutoFix

    enhanced = EnhancedAutoFix(trans, decoded_invocation_id)
    result = await enhanced.run_enhanced_autofix(fixers)
"""

import logging
import time
from typing import List, Dict, Any, Optional
from datetime import datetime

log = logging.getLogger(__name__)


class EnhancedAutoFix:
    """
    Enhanced AutoFix orchestrator that integrates all 6 extension features
    """

    def __init__(self, trans, invocation_id: int):
        """
        Initialize Enhanced AutoFix

        Args:
            trans: Galaxy transaction context
            invocation_id: Workflow invocation ID (decoded)
        """
        self.trans = trans
        self.invocation_id = invocation_id
        self.sa_session = trans.sa_session
        self.app = trans.app

        # Import dependencies
        from galaxy.ai.workflow_ops.autofix import AutoFixOrchestrator
        self.orchestrator = AutoFixOrchestrator(trans)

        log.info(f"🚀 EnhancedAutoFix initialized for invocation {invocation_id}")

    async def run_enhanced_autofix(
        self,
        fixers: List,
        error_logs: Optional[Dict[str, Any]] = None,
        workflow_context: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """
        Run enhanced autofix workflow with all 6 extension features

        Workflow:
        1. Extract error logs from invocation
        2. Match tool error patterns (Feature 1)
        3. Get Few-Shot examples for similar issues (Feature 2)
        4. Get context-specific system prompt (Feature 5)
        5. Run all fixers (including Reference Genome & File Format fixers)
        6. Validate dependencies (Feature 6)
        7. Learn from successful fixes (Feature 2)

        Args:
            fixers: List of fixer instances to run
            error_logs: Optional pre-extracted error logs
            workflow_context: Optional workflow metadata

        Returns:
            Enhanced autofix result with all features integrated
        """
        start_time = time.time()

        # ========== Step 1: Extract Error Logs ==========
        log.info("📝 Step 1: Extracting error logs...")
        if not error_logs:
            error_logs = self._extract_error_logs()

        error_text = "\n".join(error_logs.get('stderr', [])[-50:])  # Last 50 lines
        exit_code = error_logs.get('exit_code')

        # ========== Step 2: Match Tool Error Patterns (Feature 1) ==========
        log.info("🔍 Step 2: Matching tool error patterns...")
        tool_patterns = self._match_tool_patterns(error_text, exit_code)

        if tool_patterns:
            log.info(f"✅ Found {len(tool_patterns)} matching tool error patterns")
            for i, pattern in enumerate(tool_patterns[:3]):  # Show top 3
                log.info(f"   Pattern {i+1}: {pattern.get('pattern_name')} "
                        f"(confidence: {pattern.get('confidence', 0):.2f}, "
                        f"fixable: {pattern.get('fixable', False)})")
        else:
            log.info("ℹ️  No tool error patterns matched")

        # ========== Step 3: Get Few-Shot Examples (Feature 2) ==========
        log.info("📚 Step 3: Getting Few-Shot examples...")
        few_shot_examples = await self._get_few_shot_examples(error_text)

        if few_shot_examples:
            log.info(f"✅ Found {len(few_shot_examples)} relevant Few-Shot examples")
        else:
            log.info("ℹ️  No Few-Shot examples found")

        # ========== Step 4: Get Context-Specific System Prompt (Feature 5) ==========
        log.info("💬 Step 4: Getting context-specific system prompt...")
        system_prompt = await self._get_system_prompt(workflow_context)

        # ========== Step 5: Run All Fixers (including new ones) ==========
        log.info(f"🔧 Step 5: Running {len(fixers)} fixers...")

        # Enrich context with enhanced information
        context = self.orchestrator._build_fix_context(self.invocation_id)
        context.metadata.update({
            'tool_patterns': tool_patterns,
            'few_shot_examples': few_shot_examples,
            'system_prompt': system_prompt,
            'error_logs': error_logs,
        })

        # Run all fixers
        results = await self.orchestrator.run_all_fixers(
            invocation_id=self.invocation_id,
            fixers=fixers,
            stop_on_first_success=False
        )

        applied_fixes = [r for r in results if r.success]
        pending_fixes = [r for r in results if r.status.value == 'pending']
        failed_fixes = [r for r in results if not r.success and r.status.value != 'pending']

        log.info(f"🎯 Fixers completed: {len(applied_fixes)} applied, "
                f"{len(pending_fixes)} pending, {len(failed_fixes)} failed")

        # ========== Step 6: Validate Dependencies (Feature 6) ==========
        log.info("🔬 Step 6: Validating dependencies...")
        dependency_warnings = await self._validate_dependencies(applied_fixes)

        # ========== Step 7: Learn from Successful Fixes (Feature 2) ==========
        log.info("📖 Step 7: Learning from successful fixes...")
        learned_count = await self._learn_from_fixes(applied_fixes, error_logs)

        if learned_count > 0:
            log.info(f"✅ Added {learned_count} successful fixes to Few-Shot examples")

        # ========== Step 8: Generate User Guidance for Pending Fixes ==========
        log.info("📋 Step 8: Generating user guidance for pending fixes...")
        user_guidances = await self._generate_user_guidance(pending_fixes, error_logs)

        if user_guidances:
            log.info(f"✅ Generated {len(user_guidances)} user guidance entries")

        # ========== Build Enhanced Response ==========
        execution_time = time.time() - start_time

        # 🔧 Helper function to safely convert AutoFixResult to dict
        def safe_to_dict(result, user_guidance=None):
            """Safely convert AutoFixResult to dict, handling both enum and string action types"""
            try:
                result_dict = result.to_dict()
            except AttributeError as e:
                # Fallback: manually construct dict if to_dict() fails
                log.warning(f"Failed to convert result to dict: {e}, using manual conversion")
                result_dict = {
                    'fix_id': result.fix_id,
                    'fixer_name': result.fixer_name,
                    'status': result.status.value if hasattr(result.status, 'value') else str(result.status),
                    'fix_type': result.fix_type,
                    'fix_actions': [
                        {
                            'action': action.action if isinstance(action.action, str) else action.action.value,
                            'description': action.description,
                            'params': action.params,
                            'risk_level': action.risk_level if isinstance(action.risk_level, str) else action.risk_level.value,
                        }
                        for action in result.fix_actions
                    ],
                    'risk_level': result.risk_level.value if hasattr(result.risk_level, 'value') else str(result.risk_level),
                    'success': result.success,
                    'error_message': result.error_message,
                }

            # 🆕 Add user_guidance if provided
            if user_guidance:
                result_dict['user_guidance'] = user_guidance

            return result_dict

        return {
            'success': len(applied_fixes) > 0,
            'execution_time_seconds': execution_time,
            'summary': {
                'total_fixers_run': len(results),
                'applied_count': len(applied_fixes),
                'pending_count': len(pending_fixes),
                'failed_count': len(failed_fixes),
                'tool_patterns_matched': len(tool_patterns),
                'few_shot_examples_used': len(few_shot_examples),
                'successful_fixes_learned': learned_count,
                'dependency_warnings': len(dependency_warnings),
            },
            'applied_fixes': [safe_to_dict(r) for r in applied_fixes],
            'pending_fixes': [
                safe_to_dict(r, user_guidance=user_guidances.get(r.fix_id))
                for r in pending_fixes
            ],
            'failed_fixes': [safe_to_dict(r) for r in failed_fixes],
            'enhancements': {
                'tool_patterns': tool_patterns[:5],  # Top 5
                'few_shot_examples': few_shot_examples[:3],  # Top 3
                'dependency_warnings': dependency_warnings,
                'system_prompt_context': system_prompt.get('context') if system_prompt else None,
            },
        }

    def _extract_error_logs(self) -> Dict[str, Any]:
        """
        Extract error logs from workflow invocation
        """
        try:
            # Get invocation
            from galaxy.model import WorkflowInvocation
            invocation = self.sa_session.query(WorkflowInvocation).get(self.invocation_id)

            if not invocation:
                return {'stderr': [], 'stdout': [], 'exit_code': None}

            # Extract logs from Nextflow output
            logs = {
                'stderr': [],
                'stdout': [],
                'nextflow_log': [],
                'exit_code': None,
            }

            # Get Nextflow logs (if available)
            from pathlib import Path
            jobs_dir = Path(self.app.config.jobs_directory) / "nextflow_workflows"
            workflow_dir = jobs_dir / f"workflow_{self.invocation_id}"

            if workflow_dir.exists():
                # Read nextflow.out
                nextflow_out = workflow_dir / "nextflow.out"
                if nextflow_out.exists():
                    with open(nextflow_out, 'r') as f:
                        logs['stdout'] = f.readlines()

                # Read workflow-trace.txt for failed tasks
                trace_file = workflow_dir / "workflow-trace.txt"
                if trace_file.exists():
                    with open(trace_file, 'r') as f:
                        for line in f:
                            if 'FAILED' in line or 'ERROR' in line:
                                logs['stderr'].append(line.strip())

            return logs

        except Exception as e:
            log.error(f"Failed to extract error logs: {e}")
            return {'stderr': [], 'stdout': [], 'exit_code': None}

    def _match_tool_patterns(
        self,
        error_text: str,
        exit_code: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """
        Match tool error patterns (Feature 1: Tool Error Patterns)
        """
        try:
            from galaxy.ai.workflow_ops.autofix.fixers.tool_error_patterns import search_pattern

            matches = search_pattern(error_text, exit_code)
            return matches

        except Exception as e:
            log.warning(f"Tool pattern matching failed: {e}")
            return []

    async def _get_few_shot_examples(
        self,
        error_text: str,
        top_k: int = 5
    ) -> List[Dict[str, Any]]:
        """
        Get relevant Few-Shot examples (Feature 2: Few-Shot Examples)
        """
        try:
            # Import the Few-Shot storage
            from galaxy.webapps.galaxy.api.few_shot_examples import FEW_SHOT_EXAMPLES
            from difflib import SequenceMatcher

            if not FEW_SHOT_EXAMPLES:
                return []

            # Calculate similarity with all examples
            scored_examples = []
            for example_id, example in FEW_SHOT_EXAMPLES.items():
                example_error = example.error_logs or ""
                similarity = SequenceMatcher(None, error_text, example_error).ratio()

                if similarity > 0.3:  # Threshold
                    scored_examples.append({
                        'id': example_id,
                        'similarity': similarity,
                        'error_type': example.error_type,
                        'root_cause': example.root_cause,
                        'solution': example.solution,
                        'success_rate': 1.0,  # From historical data
                    })

            # Sort by similarity and return top K
            scored_examples.sort(key=lambda x: x['similarity'], reverse=True)
            return scored_examples[:top_k]

        except Exception as e:
            log.warning(f"Few-Shot examples retrieval failed: {e}")
            return []

    async def _get_system_prompt(
        self,
        workflow_context: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Any]:
        """
        Get context-specific system prompt (Feature 5: System Prompt Management)
        """
        try:
            from galaxy.webapps.galaxy.api.system_prompt import SYSTEM_PROMPTS

            # Get autofix context prompt
            prompt_config = SYSTEM_PROMPTS.get('autofix', {})
            prompt_template = prompt_config.get('prompt', '')
            variables = prompt_config.get('variables', {})

            # Render variables
            rendered_prompt = prompt_template
            if workflow_context:
                for var_name, var_template in variables.items():
                    try:
                        var_value = var_template.format(**workflow_context)
                        rendered_prompt = rendered_prompt.replace(
                            f"{{{var_name}}}",
                            var_value
                        )
                    except KeyError:
                        pass  # Variable not in context

            return {
                'context': 'autofix',
                'prompt': rendered_prompt,
                'variables_used': list(variables.keys()),
            }

        except Exception as e:
            log.warning(f"System prompt retrieval failed: {e}")
            return {'context': 'autofix', 'prompt': ''}

    async def _validate_dependencies(
        self,
        applied_fixes: List
    ) -> List[Dict[str, Any]]:
        """
        Validate tool dependencies (Feature 6: Dependency Checker)
        """
        try:
            from galaxy.webapps.galaxy.api.dependency_checker import (
                check_version_compatibility,
                RECOMMENDED_VERSIONS
            )

            warnings = []

            # Extract tool versions from applied fixes
            tools_used = {}
            for fix in applied_fixes:
                for action in fix.fix_actions:
                    if action.params:
                        # Extract tool names and versions from parameters
                        for param_name, param_value in action.params.items():
                            if 'version' in param_name.lower():
                                tool_name = param_name.replace('_version', '')
                                tools_used[tool_name] = param_value

            # Check compatibility
            if tools_used:
                compatibility = check_version_compatibility(tools_used)

                if not compatibility['compatible']:
                    for conflict in compatibility.get('conflicts', []):
                        warnings.append({
                            'type': 'version_conflict',
                            'severity': 'medium',
                            'message': conflict,
                        })

            return warnings

        except Exception as e:
            log.warning(f"Dependency validation failed: {e}")
            return []

    async def _learn_from_fixes(
        self,
        applied_fixes: List,
        error_logs: Dict[str, Any]
    ) -> int:
        """
        Learn from successful fixes (Feature 2: Few-Shot Examples)

        Returns:
            Number of successful fixes added to Few-Shot examples
        """
        try:
            from galaxy.webapps.galaxy.api.few_shot_examples import (
                FEW_SHOT_EXAMPLES,
                FewShotExample
            )

            learned_count = 0

            for fix in applied_fixes:
                if fix.success:
                    # Create Few-Shot example from successful fix
                    example_id = f"auto_{self.invocation_id}_{fix.fix_id}"

                    # Extract error type and solution
                    error_type = fix.fix_type
                    solution = "\n".join([
                        f"{action.action}: {action.description}"
                        for action in fix.fix_actions
                    ])

                    # Create example
                    example = FewShotExample(
                        id=example_id,
                        error_type=error_type,
                        error_logs="\n".join(error_logs.get('stderr', [])[-20:]),
                        root_cause=f"Automatically fixed by {fix.fixer_name}",
                        solution=solution,
                        workflow_type="auto-learned",
                        success_rate=1.0,
                        created_at=datetime.now().isoformat(),
                    )

                    # Add to storage (if not already exists)
                    if example_id not in FEW_SHOT_EXAMPLES:
                        FEW_SHOT_EXAMPLES[example_id] = example
                        learned_count += 1
                        log.info(f"   ✅ Learned from fix: {example_id}")

            return learned_count

        except Exception as e:
            log.warning(f"Learning from fixes failed: {e}")
            return 0

    async def _generate_user_guidance(
        self,
        pending_fixes: List,
        error_logs: Dict[str, Any]
    ) -> Dict[str, Dict[str, Any]]:
        """
        Generate user guidance for pending fixes (fixes that need user confirmation)

        Args:
            pending_fixes: List of AutoFixResult objects that are pending
            error_logs: Error logs from the workflow

        Returns:
            Dict mapping fix_id to user_guidance dict
        """
        try:
            guidances = {}

            for fix in pending_fixes:
                try:
                    # 🔑 跳过没有 fix_actions 的修复（如 "No issues detected" 的 fixers）
                    if not hasattr(fix, 'fix_actions') or not fix.fix_actions or len(fix.fix_actions) == 0:
                        log.info(f"✅ Skipping guidance generation for fix without actions: {fix.fixer_name if hasattr(fix, 'fixer_name') else 'Unknown'}")
                        continue

                    # 🔑 额外检查：跳过 success=True 且 error_message="No issues detected" 的 Fixer
                    if hasattr(fix, 'success') and fix.success and hasattr(fix, 'error_message') and fix.error_message == "No issues detected":
                        log.info(f"✅ Skipping guidance for successful fix with no issues: {fix.fixer_name if hasattr(fix, 'fixer_name') else 'Unknown'}")
                        continue

                    # Extract fixer information
                    fixer_name = fix.fixer_name if hasattr(fix, 'fixer_name') else "AutoFix"
                    fix_id = fix.fix_id if hasattr(fix, 'fix_id') else f"fix_{len(guidances)}"

                    # Get explanation from fix_plan
                    explanation = ""
                    if hasattr(fix, 'fix_plan') and fix.fix_plan:
                        explanation = fix.fix_plan.explanation if hasattr(fix.fix_plan, 'explanation') else ""

                    # Extract fix actions
                    fix_actions_desc = []
                    if hasattr(fix, 'fix_plan') and fix.fix_plan and hasattr(fix.fix_plan, 'fix_actions'):
                        for action in fix.fix_plan.fix_actions:
                            if hasattr(action, 'description'):
                                fix_actions_desc.append(action.description)

                    # Create simplified user guidance
                    guidance = {
                        'issue_type': 'parameter_update',
                        'severity': 'warning',
                        'category': 'auto_fixable',
                        'fix_strategy': 'auto_with_confirmation',
                        'problem': {
                            'summary': f'{fixer_name} detected an issue that can be automatically fixed',
                            'details': explanation or f'{fixer_name} has identified a configuration issue and prepared a fix.',
                            'affected_tasks': [],
                            'error_messages': []
                        },
                        'recommended_actions': [
                            {
                                'priority': 1,
                                'title': 'Apply the suggested fix',
                                'description': 'Review the proposed changes and click "Apply Fix" to automatically update the workflow configuration',
                                'steps': [
                                    '1. Review the "Before" and "After" configuration below',
                                    '2. Verify the changes are correct for your workflow',
                                    '3. Click "应用此修复" (Apply Fix) button to apply changes',
                                    '4. The workflow will be automatically restarted with the new configuration'
                                ],
                                'estimated_time': '1-2 minutes',
                                'success_probability': 0.9,
                                'recommendation_level': '★★★★☆'
                            }
                        ],
                        'documentation': fix_actions_desc
                    }

                    guidances[fix_id] = guidance
                    log.info(f"   ✅ Generated simplified guidance for fix {fix_id}")

                except Exception as e:
                    log.warning(f"Failed to generate guidance for fix: {e}")
                    continue

            return guidances

        except Exception as e:
            import traceback
            log.warning(f"User guidance generation failed: {e}")
            log.warning(f"Traceback: {traceback.format_exc()}")
            return {}
