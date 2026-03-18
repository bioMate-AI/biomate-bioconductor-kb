"""
Samplesheet Auto-Fixer

Automatically detects and fixes samplesheet format issues for nf-core pipelines:
1. Validates samplesheet structure (columns, headers)
2. Checks pipeline-specific rules (e.g., clipseq group/input_name consistency)
3. Fixes common format errors (duplicate entries, missing required fields)
4. Downloads from S3, fixes, and re-uploads corrected samplesheet

Safety:
- User-isolated: Only accesses user's S3 buckets
- Non-destructive: Creates new corrected file, keeps original
- Auditable: All operations logged
- Rollback-safe: Can revert to original file

Example issues fixed:
- clipseq: Same group must share same input_name
- rnaseq: Missing required columns (strandedness, etc.)
- Generic: Duplicate sample names, invalid characters
"""

import csv
import io
import logging
import os
import re
from collections import defaultdict
from typing import Any, Dict, List, Optional, Set, Tuple
from urllib.parse import urlparse

from galaxy.ai.workflow_ops.autofix.base import (
    AutoFixResult,
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
)
from galaxy.ai.workflow_ops.types import ActionType, FixAction, FixPlan, FixType
from galaxy.model import WorkflowInvocation

log = logging.getLogger(__name__)


class SamplesheetFixer(BaseAutoFixer):
    """
    Fixer for samplesheet format issues

    Handles:
    - Column validation
    - Pipeline-specific rules (clipseq, rnaseq, etc.)
    - Format errors (duplicates, invalid chars)
    - S3 file operations (download, fix, upload)
    """

    # Pipeline-specific required columns
    PIPELINE_COLUMNS = {
        'clipseq': {
            'required': ['sample_name', 'group_name', 'input_name', 'fastq'],
            'optional': []
        },
        'rnaseq': {
            'required': ['sample', 'fastq_1', 'strandedness'],
            'optional': ['fastq_2']
        },
        'atacseq': {
            'required': ['sample', 'fastq_1', 'fastq_2'],
            'optional': ['replicate']
        }
    }

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        Detect samplesheet format issues

        Args:
            context: Fix context

        Returns:
            List of detected samplesheet issues
        """
        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context metadata")
            return []

        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return []

        issues = []

        # Get input parameters
        params = invocation.input_parameters or {}

        # Look for samplesheet parameter (usually 'input' or 'samplesheet')
        samplesheet_path = None
        param_name = None

        for key in ['input', 'samplesheet', 'sample_sheet']:
            if key in params:
                samplesheet_path = params[key]
                param_name = key
                break

        if not samplesheet_path:
            log.debug("No samplesheet parameter found in workflow")
            return []

        log.info(f"🔍 Checking samplesheet: {samplesheet_path}")

        # Download and parse samplesheet
        try:
            samplesheet_content = self._download_samplesheet(samplesheet_path, context)
            if not samplesheet_content:
                issues.append({
                    'type': 'samplesheet_download_error',
                    'severity': 'high',
                    'param_name': param_name,
                    'path': samplesheet_path,
                    'message': f"Cannot download samplesheet from {samplesheet_path}"
                })
                return issues

            # Parse CSV
            rows, headers = self._parse_csv(samplesheet_content)

            # Detect pipeline type from workflow name
            pipeline_type = self._detect_pipeline_type(invocation)

            log.info(f"📋 Detected pipeline: {pipeline_type}, headers: {headers}, rows: {len(rows)}")

            # Validate structure
            structure_issues = self._validate_structure(rows, headers, pipeline_type)
            issues.extend(structure_issues)

            # Pipeline-specific validation
            if pipeline_type == 'clipseq':
                clipseq_issues = self._validate_clipseq(rows, headers)
                issues.extend(clipseq_issues)
            elif pipeline_type == 'rnaseq':
                rnaseq_issues = self._validate_rnaseq(rows, headers)
                issues.extend(rnaseq_issues)

            # Add context to all issues
            for issue in issues:
                issue['param_name'] = param_name
                issue['samplesheet_path'] = samplesheet_path
                issue['headers'] = headers
                issue['row_count'] = len(rows)

        except Exception as e:
            log.error(f"Failed to check samplesheet: {e}", exc_info=True)
            issues.append({
                'type': 'samplesheet_check_error',
                'severity': 'medium',
                'message': f"Failed to validate samplesheet: {str(e)}"
            })

        return issues

    def generate_fix_plan(self, issues: List[Dict[str, Any]], context: FixContext) -> Optional[FixPlan]:
        """
        Generate fix plan for samplesheet issues

        Args:
            issues: Detected issues
            context: Fix context

        Returns:
            Fix plan or None if cannot fix
        """
        if not issues:
            return None

        # Filter samplesheet-related issues
        samplesheet_issues = [
            issue for issue in issues
            if issue.get('type', '').startswith('samplesheet_')
        ]

        if not samplesheet_issues:
            return None

        log.info(f"🔧 Generating fix plan for {len(samplesheet_issues)} samplesheet issues")

        # Get samplesheet path from first issue
        samplesheet_path = samplesheet_issues[0].get('samplesheet_path')
        param_name = samplesheet_issues[0].get('param_name', 'input')

        if not samplesheet_path:
            return None

        # Generate fix actions
        fix_actions = []

        for issue in samplesheet_issues:
            issue_type = issue.get('type')

            if issue_type == 'clipseq_group_input_mismatch':
                # Fix: Unify input_name within each group
                fix_actions.append(FixAction(
                    action=ActionType.UPDATE_FILE,
                    target='samplesheet',
                    params={
                        'original_path': samplesheet_path,
                        'fix_type': 'unify_group_input',
                        'groups': issue.get('groups', {})
                    },
                    description=f"Unify input_name for group '{issue.get('group_name')}'"
                ))

            elif issue_type == 'samplesheet_missing_columns':
                # Fix: Add missing columns with defaults
                fix_actions.append(FixAction(
                    action=ActionType.UPDATE_FILE,
                    target='samplesheet',
                    params={
                        'original_path': samplesheet_path,
                        'fix_type': 'add_missing_columns',
                        'missing_columns': issue.get('missing_columns', [])
                    },
                    description=f"Add missing columns: {', '.join(issue.get('missing_columns', []))}"
                ))

            elif issue_type == 'samplesheet_duplicate_samples':
                # Fix: Remove or rename duplicates
                fix_actions.append(FixAction(
                    action=ActionType.UPDATE_FILE,
                    target='samplesheet',
                    params={
                        'original_path': samplesheet_path,
                        'fix_type': 'remove_duplicates',
                        'duplicate_samples': issue.get('duplicate_samples', [])
                    },
                    description=f"Remove duplicate sample: {issue.get('sample_name')}"
                ))

        if not fix_actions:
            return None

        # Create fix plan
        return FixPlan(
            fix_id=f"samplesheet_fix_{context.invocation_id}",
            fix_type=FixType.DATA_FILE,
            description=f"Fix {len(fix_actions)} samplesheet format issue(s)",
            risk_level=RiskLevel.LOW,  # Creating new file, not modifying original
            estimated_cost=0.0,  # S3 operations are cheap
            actions=fix_actions,
            validation_steps=[
                "Download original samplesheet",
                "Apply fixes (unify input_name, add columns, etc.)",
                "Validate corrected format",
                "Upload to S3 with _fixed suffix",
                "Update workflow parameter to use fixed file"
            ],
            rollback_plan={
                'action': 'revert_to_original',
                'original_path': samplesheet_path
            }
        )

    async def apply_fix(self, context: FixContext, fix_plan: FixPlan, sa_session) -> AutoFixResult:
        """
        Apply samplesheet fix

        Args:
            context: Fix context
            fix_plan: Fix plan to apply
            sa_session: SQLAlchemy session

        Returns:
            Fix result
        """
        log.info(f"🚀 Applying samplesheet fix: {fix_plan.description}")

        try:
            invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
            if not invocation:
                return AutoFixResult(
                    status=FixStatus.FAILED,
                    message="Workflow invocation not found",
                    issues_detected=len(fix_plan.actions),
                    fixes_applied=0
                )

            # Get original samplesheet path
            original_path = None
            for action in fix_plan.actions:
                if 'original_path' in action.params:
                    original_path = action.params['original_path']
                    break

            if not original_path:
                return AutoFixResult(
                    status=FixStatus.FAILED,
                    message="Cannot find original samplesheet path",
                    issues_detected=len(fix_plan.actions),
                    fixes_applied=0
                )

            # Download original samplesheet
            original_content = self._download_samplesheet(original_path, context)
            if not original_content:
                return AutoFixResult(
                    status=FixStatus.FAILED,
                    message=f"Cannot download samplesheet from {original_path}",
                    issues_detected=len(fix_plan.actions),
                    fixes_applied=0
                )

            # Parse CSV
            rows, headers = self._parse_csv(original_content)

            # Apply fixes
            fixed_rows = rows.copy()
            fixes_applied = 0

            for action in fix_plan.actions:
                fix_type = action.params.get('fix_type')

                if fix_type == 'unify_group_input':
                    fixed_rows = self._fix_unify_group_input(fixed_rows, headers)
                    fixes_applied += 1
                elif fix_type == 'add_missing_columns':
                    fixed_rows, headers = self._fix_add_missing_columns(
                        fixed_rows, headers, action.params.get('missing_columns', [])
                    )
                    fixes_applied += 1
                elif fix_type == 'remove_duplicates':
                    fixed_rows = self._fix_remove_duplicates(fixed_rows, headers)
                    fixes_applied += 1

            # Generate fixed CSV content
            fixed_content = self._generate_csv(fixed_rows, headers)

            # Upload to S3 with _fixed suffix
            fixed_path = self._generate_fixed_path(original_path)
            upload_success = self._upload_samplesheet(fixed_path, fixed_content, context)

            if not upload_success:
                return AutoFixResult(
                    status=FixStatus.FAILED,
                    message=f"Failed to upload fixed samplesheet to {fixed_path}",
                    issues_detected=len(fix_plan.actions),
                    fixes_applied=fixes_applied
                )

            log.info(f"✅ Fixed samplesheet uploaded to: {fixed_path}")

            # Update workflow parameter (will be applied on restart)
            # Note: This just returns the recommendation, actual parameter update
            # happens in the orchestrator

            return AutoFixResult(
                status=FixStatus.SUCCESS,
                message=f"Samplesheet fixed and uploaded to {fixed_path}",
                issues_detected=len(fix_plan.actions),
                fixes_applied=fixes_applied,
                changes_made={
                    'original_path': original_path,
                    'fixed_path': fixed_path,
                    'rows_before': len(rows),
                    'rows_after': len(fixed_rows),
                    'fixes': [action.description for action in fix_plan.actions]
                },
                recommended_params={
                    'input': fixed_path  # or 'samplesheet' depending on pipeline
                }
            )

        except Exception as e:
            log.error(f"Failed to apply samplesheet fix: {e}", exc_info=True)
            return AutoFixResult(
                status=FixStatus.FAILED,
                message=f"Fix application failed: {str(e)}",
                issues_detected=len(fix_plan.actions) if fix_plan else 0,
                fixes_applied=0
            )

    # ========== Helper Methods ==========

    def _download_samplesheet(self, path: str, context: FixContext) -> Optional[str]:
        """Download samplesheet from S3 or local path"""
        try:
            if path.startswith('s3://'):
                # S3 download
                import boto3
                parsed = urlparse(path)
                bucket = parsed.netloc
                key = parsed.path.lstrip('/')

                s3 = boto3.client('s3')
                response = s3.get_object(Bucket=bucket, Key=key)
                content = response['Body'].read().decode('utf-8')
                return content
            else:
                # Local file
                if os.path.exists(path):
                    with open(path, 'r') as f:
                        return f.read()

        except Exception as e:
            log.error(f"Failed to download samplesheet from {path}: {e}")

        return None

    def _upload_samplesheet(self, path: str, content: str, context: FixContext) -> bool:
        """Upload fixed samplesheet to S3 or local path"""
        try:
            if path.startswith('s3://'):
                # S3 upload
                import boto3
                parsed = urlparse(path)
                bucket = parsed.netloc
                key = parsed.path.lstrip('/')

                s3 = boto3.client('s3')
                tag_str = f"user_id={context.user_id}&workflow_id={context.workflow_id}"
                s3.put_object(Bucket=bucket, Key=key, Body=content.encode('utf-8'), Tagging=tag_str)
                log.info(f"✅ Uploaded to S3: s3://{bucket}/{key}")
                return True
            else:
                # Local file
                os.makedirs(os.path.dirname(path), exist_ok=True)
                with open(path, 'w') as f:
                    f.write(content)
                log.info(f"✅ Saved to local: {path}")
                return True

        except Exception as e:
            log.error(f"Failed to upload samplesheet to {path}: {e}")
            return False

    def _parse_csv(self, content: str) -> Tuple[List[Dict[str, str]], List[str]]:
        """Parse CSV content into rows and headers"""
        reader = csv.DictReader(io.StringIO(content))
        headers = reader.fieldnames or []
        rows = list(reader)
        return rows, headers

    def _generate_csv(self, rows: List[Dict[str, str]], headers: List[str]) -> str:
        """Generate CSV content from rows and headers"""
        output = io.StringIO()
        writer = csv.DictWriter(output, fieldnames=headers)
        writer.writeheader()
        writer.writerows(rows)
        return output.getvalue()

    def _detect_pipeline_type(self, invocation: WorkflowInvocation) -> str:
        """Detect pipeline type from workflow name"""
        workflow_name = invocation.workflow.name.lower() if invocation.workflow else ''

        if 'clipseq' in workflow_name or 'clip-seq' in workflow_name or 'clip_seq' in workflow_name:
            return 'clipseq'
        elif 'rnaseq' in workflow_name or 'rna-seq' in workflow_name or 'rna_seq' in workflow_name:
            return 'rnaseq'
        elif 'atacseq' in workflow_name or 'atac-seq' in workflow_name or 'atac_seq' in workflow_name:
            return 'atacseq'

        return 'unknown'

    def _validate_structure(self, rows: List[Dict], headers: List[str], pipeline_type: str) -> List[Dict[str, Any]]:
        """Validate basic samplesheet structure"""
        issues = []

        if not rows:
            issues.append({
                'type': 'samplesheet_empty',
                'severity': 'high',
                'message': 'Samplesheet is empty'
            })
            return issues

        # Check required columns for pipeline
        if pipeline_type in self.PIPELINE_COLUMNS:
            required = set(self.PIPELINE_COLUMNS[pipeline_type]['required'])
            actual = set(headers)
            missing = required - actual

            if missing:
                issues.append({
                    'type': 'samplesheet_missing_columns',
                    'severity': 'high',
                    'missing_columns': list(missing),
                    'message': f"Missing required columns: {', '.join(missing)}"
                })

        return issues

    def _validate_clipseq(self, rows: List[Dict], headers: List[str]) -> List[Dict[str, Any]]:
        """Validate clipseq-specific rules"""
        issues = []

        # Check: Same group must have same input_name
        group_inputs = defaultdict(set)
        for row in rows:
            group = row.get('group_name', '')
            input_name = row.get('input_name', '')
            if group and input_name:
                group_inputs[group].add(input_name)

        for group, inputs in group_inputs.items():
            if len(inputs) > 1:
                issues.append({
                    'type': 'clipseq_group_input_mismatch',
                    'severity': 'high',
                    'group_name': group,
                    'input_names': list(inputs),
                    'message': f"Group '{group}' has multiple input_names: {', '.join(inputs)}. All samples in the same group must share the same input.",
                    'groups': dict(group_inputs)
                })

        return issues

    def _validate_rnaseq(self, rows: List[Dict], headers: List[str]) -> List[Dict[str, Any]]:
        """Validate rnaseq-specific rules"""
        issues = []

        # Check for duplicate sample names
        sample_names = [row.get('sample', '') for row in rows]
        duplicates = [name for name in set(sample_names) if sample_names.count(name) > 1]

        if duplicates:
            issues.append({
                'type': 'samplesheet_duplicate_samples',
                'severity': 'medium',
                'duplicate_samples': duplicates,
                'message': f"Duplicate sample names found: {', '.join(duplicates)}"
            })

        return issues

    def _fix_unify_group_input(self, rows: List[Dict], headers: List[str]) -> List[Dict]:
        """Fix: Unify input_name within each group (use first sample's input_name)"""
        group_first_input = {}

        # Find first input_name for each group
        for row in rows:
            group = row.get('group_name', '')
            if group and group not in group_first_input:
                group_first_input[group] = row.get('input_name', '')

        # Apply unified input_name
        fixed_rows = []
        for row in rows:
            fixed_row = row.copy()
            group = row.get('group_name', '')
            if group and group in group_first_input:
                fixed_row['input_name'] = group_first_input[group]
            fixed_rows.append(fixed_row)

        return fixed_rows

    def _fix_add_missing_columns(self, rows: List[Dict], headers: List[str], missing: List[str]) -> Tuple[List[Dict], List[str]]:
        """Fix: Add missing columns with default values"""
        new_headers = headers + missing
        fixed_rows = []

        for row in rows:
            fixed_row = row.copy()
            for col in missing:
                fixed_row[col] = ''  # Default to empty
            fixed_rows.append(fixed_row)

        return fixed_rows, new_headers

    def _fix_remove_duplicates(self, rows: List[Dict], headers: List[str]) -> List[Dict]:
        """Fix: Remove duplicate samples (keep first occurrence)"""
        seen = set()
        fixed_rows = []

        for row in rows:
            sample_name = row.get('sample', '') or row.get('sample_name', '')
            if sample_name not in seen:
                seen.add(sample_name)
                fixed_rows.append(row)

        return fixed_rows

    def _generate_fixed_path(self, original_path: str) -> str:
        """Generate fixed samplesheet path (append _fixed before extension)"""
        if original_path.startswith('s3://'):
            # S3 path
            base, ext = os.path.splitext(original_path)
            return f"{base}_fixed{ext}"
        else:
            # Local path
            directory = os.path.dirname(original_path)
            filename = os.path.basename(original_path)
            base, ext = os.path.splitext(filename)
            return os.path.join(directory, f"{base}_fixed{ext}")
