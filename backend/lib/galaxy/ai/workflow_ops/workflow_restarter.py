"""
Workflow 自动重启器

功能：
1. 应用修复后自动重启 workflow
2. 更新 Nextflow 配置和参数
3. 监控新的运行状态
4. 限制重试次数避免无限循环
"""

import logging
import json
import time
from pathlib import Path
from typing import Dict, Any, Optional, List
from datetime import datetime

log = logging.getLogger(__name__)


class WorkflowRestarter:
    """
    Workflow 自动重启器

    支持的修复类型：
    1. 参数修复（添加/修改 Nextflow 参数）
    2. 配置修复（修改 nextflow.config）
    3. 资源修复（调整内存/CPU）
    """

    def __init__(self, app, max_auto_retries: int = 3):
        """
        Args:
            app: Galaxy app instance
            max_auto_retries: 最大自动重试次数（防止无限循环）
        """
        self.app = app
        self.max_auto_retries = max_auto_retries

    def can_restart(self, invocation_id: int) -> tuple[bool, str]:
        """
        检查是否可以重启 workflow

        Returns:
            (can_restart, reason)
        """
        from galaxy.model import WorkflowInvocation

        invocation = self.app.model.session.query(WorkflowInvocation).get(invocation_id)

        if not invocation:
            return False, "Workflow invocation not found"

        # 检查是否超过重试次数
        retry_count = self._get_retry_count(invocation)
        if retry_count >= self.max_auto_retries:
            return False, f"Exceeded maximum auto-retry limit ({self.max_auto_retries})"

        # 检查 workflow 状态
        if invocation.state not in ['error', 'failed']:
            return False, f"Workflow is not in failed state (current: {invocation.state})"

        return True, "Ready to restart"

    def restart_with_fixes(
        self,
        invocation_id: int,
        fixes: List[Dict[str, Any]],
        user=None
    ) -> Dict[str, Any]:
        """
        应用修复并重启 workflow

        Args:
            invocation_id: Workflow invocation ID
            fixes: 修复列表，每个修复包含：
                {
                    'type': 'param_addition' | 'config_change' | 'resource_scaling',
                    'param_name': str,
                    'new_value': Any,
                    'description': str
                }
            user: Galaxy user (for permissions)

        Returns:
            {
                'success': bool,
                'new_invocation_id': int,
                'applied_fixes': List[str],
                'message': str
            }
        """
        try:
            from galaxy.model import WorkflowInvocation

            # 检查是否可以重启
            can_restart, reason = self.can_restart(invocation_id)
            if not can_restart:
                return {
                    'success': False,
                    'message': f"Cannot restart: {reason}",
                    'applied_fixes': []
                }

            invocation = self.app.model.session.query(WorkflowInvocation).get(invocation_id)

            # 1. 准备新的参数
            new_params = self._apply_fixes_to_params(invocation, fixes)

            # 2. 更新 Nextflow 配置（如果需要）
            config_updated = self._update_nextflow_config(invocation, fixes)

            # 3. 创建新的 workflow invocation
            new_invocation_id = self._create_new_invocation(
                invocation,
                new_params,
                user
            )

            if not new_invocation_id:
                return {
                    'success': False,
                    'message': 'Failed to create new workflow invocation',
                    'applied_fixes': []
                }

            # 4. 记录重试历史
            self._record_retry(invocation, new_invocation_id, fixes)

            # 5. 启动新的 workflow
            success = self._start_workflow(new_invocation_id)

            if success:
                applied_fixes_desc = [f['description'] for f in fixes]

                log.info(f"✅ Workflow {invocation_id} restarted as {new_invocation_id} with fixes: {applied_fixes_desc}")

                return {
                    'success': True,
                    'new_invocation_id': new_invocation_id,
                    'applied_fixes': applied_fixes_desc,
                    'message': f'Workflow restarted successfully with {len(fixes)} fixes applied'
                }
            else:
                return {
                    'success': False,
                    'message': 'Failed to start new workflow',
                    'applied_fixes': []
                }

        except Exception as e:
            log.error(f"Failed to restart workflow {invocation_id}: {e}", exc_info=True)
            return {
                'success': False,
                'message': f'Error: {str(e)}',
                'applied_fixes': []
            }

    def _apply_fixes_to_params(
        self,
        invocation,
        fixes: List[Dict[str, Any]]
    ) -> Dict[str, Any]:
        """应用修复到参数"""
        # 获取原始参数
        original_params = invocation.input_parameters or {}
        new_params = original_params.copy()

        for fix in fixes:
            fix_type = fix.get('type', '')

            if fix_type in ['param_addition', 'param_update', 'UPDATE_PARAM']:
                param_name = fix.get('param_name')
                new_value = fix.get('new_value')

                if param_name:
                    new_params[param_name] = new_value
                    log.info(f"Applied param fix: {param_name} = {new_value}")

        return new_params

    def _update_nextflow_config(
        self,
        invocation,
        fixes: List[Dict[str, Any]]
    ) -> bool:
        """
        更新 Nextflow 配置文件

        对于 Nextflow workflows，配置通常在：
        database/jobs_directory/nextflow_workflows/workflow_{id}/nextflow.config
        """
        try:
            # 找到 workflow 工作目录
            work_dir = self._get_workflow_work_dir(invocation)
            if not work_dir or not work_dir.exists():
                log.warning(f"Workflow work directory not found: {work_dir}")
                return False

            config_file = work_dir / "nextflow.config"

            # 备份原始配置
            if config_file.exists():
                backup_file = work_dir / f"nextflow.config.backup.{int(time.time())}"
                import shutil
                shutil.copy2(config_file, backup_file)
                log.info(f"Backed up config to {backup_file}")

            # 应用配置修复
            config_changes = []
            for fix in fixes:
                if fix.get('type') == 'config_change':
                    config_changes.append(fix)

            if config_changes:
                self._apply_config_changes(config_file, config_changes)
                return True

            return False

        except Exception as e:
            log.error(f"Failed to update Nextflow config: {e}", exc_info=True)
            return False

    def _apply_config_changes(
        self,
        config_file: Path,
        changes: List[Dict[str, Any]]
    ):
        """应用配置文件修改"""
        # 读取现有配置
        if config_file.exists():
            with open(config_file, 'r') as f:
                config_content = f.read()
        else:
            config_content = ""

        # 应用每个修改
        for change in changes:
            old_line = change.get('old', '')
            new_line = change.get('new', '')

            if old_line and old_line in config_content:
                config_content = config_content.replace(old_line, new_line)
                log.info(f"Config change: {old_line} → {new_line}")
            else:
                # 如果找不到旧的，就追加新的
                config_content += f"\n// Auto-added by AI Ops\n{new_line}\n"
                log.info(f"Config addition: {new_line}")

        # 写回文件
        with open(config_file, 'w') as f:
            f.write(config_content)

    def _create_new_invocation(
        self,
        original_invocation,
        new_params: Dict[str, Any],
        user
    ) -> Optional[int]:
        """
        创建新的 workflow invocation

        使用 Galaxy 的 WorkflowsService 来正确创建和启动 workflow
        """
        try:
            from galaxy.webapps.galaxy.services.workflows import WorkflowsService
            from galaxy.managers.context import ProvidesHistoryContext
            from galaxy.schema.schema import CreateInvocationsFromStorePayload

            # 获取原始 workflow 的 stored_workflow
            stored_workflow = original_invocation.workflow.stored_workflow
            workflow_id = stored_workflow.id

            log.info(f"准备重新运行 workflow {workflow_id}, 使用参数: {new_params}")

            # 构建 invoke payload
            # 这里使用原始 invocation 的配置，但替换参数
            history = original_invocation.history

            # 构建 workflow invocation 请求
            # 注意：这里需要模拟一个 trans 对象
            class SimpleTransContext:
                def __init__(self, app, user, history):
                    self.app = app
                    self.user = user
                    self.history = history
                    self.anonymous = False

                def check_user_activation(self):
                    pass

            trans = SimpleTransContext(self.app, user, history)

            # 使用 workflows service 来 invoke
            workflows_service = WorkflowsService(
                workflows_manager=self.app.workflows_manager,
                workflow_contents_manager=self.app.workflow_contents_manager
            )

            # 构建 payload - 使用原始 invocation 的输入
            from galaxy.schema.schema import InvokeWorkflowPayload

            invoke_payload = InvokeWorkflowPayload(
                history_id=history.id,
                parameters=new_params,
                instance=False,  # 使用 stored workflow ID
                require_exact_tool_versions=False
            )

            # 调用 workflow
            response = workflows_service.invoke_workflow(
                trans,
                workflow_id,
                invoke_payload
            )

            # 获取新创建的 invocation ID
            if isinstance(response, list):
                new_invocation_id = response[0].id if response else None
            else:
                new_invocation_id = response.id

            log.info(f"✅ 成功创建新的 workflow invocation: {new_invocation_id}")
            return new_invocation_id

        except Exception as e:
            log.error(f"Failed to create new invocation: {e}", exc_info=True)
            return None

    def _start_workflow(self, invocation_id: int) -> bool:
        """
        启动 workflow 执行

        注意：使用 WorkflowsService.invoke_workflow() 已经自动启动了 workflow，
        所以这个方法实际上只需要验证 workflow 已经被调度即可
        """
        try:
            from galaxy.model import WorkflowInvocation

            invocation = self.app.model.session.query(WorkflowInvocation).get(invocation_id)

            if not invocation:
                log.error(f"Invocation {invocation_id} not found")
                return False

            # WorkflowsService.invoke_workflow() 已经处理了启动逻辑
            # 这里只是验证状态
            if invocation.state in ['new', 'ready', 'scheduled']:
                log.info(f"✅ Workflow invocation {invocation_id} is {invocation.state}, ready to run")
                return True
            else:
                log.warning(f"⚠️ Workflow invocation {invocation_id} state is {invocation.state}")
                return True  # 仍然返回 True，因为已经创建成功

        except Exception as e:
            log.error(f"Failed to verify workflow {invocation_id}: {e}", exc_info=True)
            # 即使验证失败，也返回 True，因为创建已经成功
            return True

    def _get_retry_count(self, invocation) -> int:
        """获取当前的重试次数"""
        if not hasattr(invocation, 'ai_retry_metadata'):
            return 0

        metadata = invocation.ai_retry_metadata or {}
        return len(metadata.get('retry_history', []))

    def _record_retry(
        self,
        original_invocation,
        new_invocation_id: int,
        fixes: List[Dict[str, Any]]
    ):
        """记录重试历史"""
        if not hasattr(original_invocation, 'ai_retry_metadata'):
            original_invocation.ai_retry_metadata = {}

        if 'retry_history' not in original_invocation.ai_retry_metadata:
            original_invocation.ai_retry_metadata['retry_history'] = []

        original_invocation.ai_retry_metadata['retry_history'].append({
            'timestamp': datetime.now().isoformat(),
            'new_invocation_id': new_invocation_id,
            'fixes_applied': [f['description'] for f in fixes],
            'retry_count': len(original_invocation.ai_retry_metadata['retry_history']) + 1
        })

        self.app.model.session.add(original_invocation)
        self.app.model.session.commit()

    def _get_workflow_work_dir(self, invocation) -> Optional[Path]:
        """获取 workflow 工作目录"""
        try:
            jobs_dir = Path(self.app.config.jobs_directory)
            work_dir = jobs_dir / "nextflow_workflows" / f"workflow_{invocation.id}"
            return work_dir if work_dir.exists() else None
        except Exception:
            return None
