"""
AutoFix 持久化层

负责保存和恢复 AutoFix 修复历史，确保服务重启后数据不丢失
"""

import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Any, Optional, Union

log = logging.getLogger(__name__)


class AutoFixPersistence:
    """AutoFix 修复历史持久化管理"""

    def __init__(self, data_dir: Path):
        """
        初始化持久化管理器

        Args:
            data_dir: Galaxy data 目录路径
        """
        self.data_dir = Path(data_dir)
        self.history_dir = self.data_dir / 'ai_workflow_ops' / 'autofix_history'
        self.history_dir.mkdir(parents=True, exist_ok=True)

        log.info(f"📂 AutoFix 历史目录: {self.history_dir}")

    def _get_workflow_file(self, workflow_invocation_id: Union[int, str]) -> Path:
        """
        获取 workflow 的 AutoFix 历史文件路径

        Args:
            workflow_invocation_id: 可以是整数 ID 或编码字符串 ID
        """
        # 统一转换为字符串
        wf_id = str(workflow_invocation_id)
        return self.history_dir / f"workflow_{wf_id}_autofix.json"

    def save_autofix_result(
        self,
        workflow_invocation_id: Union[int, str],
        autofix_result: Dict[str, Any]
    ) -> bool:
        """
        保存 AutoFix 修复结果

        Args:
            workflow_invocation_id: Workflow Invocation ID (可以是整数或编码字符串)
            autofix_result: AutoFix 运行结果（包括 applied_fixes, pending_fixes, failed_fixes 等）

        Returns:
            bool: 是否保存成功
        """
        try:
            wf_id = str(workflow_invocation_id)  # 统一转换为字符串
            file_path = self._get_workflow_file(wf_id)

            # 读取现有历史（如果存在）
            history = self._load_history(wf_id)

            # 添加新的执行记录
            execution_record = {
                'timestamp': datetime.now().isoformat(),
                'summary': autofix_result.get('summary', {}),
                'applied_fixes': autofix_result.get('applied_fixes', []),
                'pending_fixes': autofix_result.get('pending_fixes', []),
                'failed_fixes': autofix_result.get('failed_fixes', []),
                'user_action_required': autofix_result.get('user_action_required', []),
                'workflow_restarted': autofix_result.get('workflow_restarted', False),
                'restart_details': autofix_result.get('restart_details'),
            }

            history['executions'].append(execution_record)
            history['last_updated'] = datetime.now().isoformat()
            history['total_executions'] = len(history['executions'])

            # 保存到文件
            with open(file_path, 'w', encoding='utf-8') as f:
                json.dump(history, f, indent=2, ensure_ascii=False)

            log.info(f"✅ Saved AutoFix result for workflow {wf_id} to {file_path}")
            log.info(f"   Applied: {len(execution_record['applied_fixes'])}, "
                    f"Pending: {len(execution_record['pending_fixes'])}, "
                    f"Failed: {len(execution_record['failed_fixes'])}")

            return True

        except Exception as e:
            log.error(f"Failed to save AutoFix result for workflow {workflow_invocation_id}: {e}")
            import traceback
            traceback.print_exc()
            return False

    def _load_history(self, workflow_invocation_id: Union[int, str]) -> Dict[str, Any]:
        """
        加载 workflow 的 AutoFix 历史

        Args:
            workflow_invocation_id: Workflow Invocation ID (可以是整数或编码字符串)

        Returns:
            历史记录（如果不存在则返回空结构）
        """
        wf_id = str(workflow_invocation_id)  # 统一转换为字符串
        file_path = self._get_workflow_file(wf_id)

        if not file_path.exists():
            return {
                'workflow_invocation_id': wf_id,
                'created_at': datetime.now().isoformat(),
                'last_updated': datetime.now().isoformat(),
                'total_executions': 0,
                'executions': []
            }

        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            log.error(f"Failed to load history from {file_path}: {e}")
            return {
                'workflow_invocation_id': wf_id,
                'created_at': datetime.now().isoformat(),
                'last_updated': datetime.now().isoformat(),
                'total_executions': 0,
                'executions': [],
                'load_error': str(e)
            }

    def get_latest_autofix_result(self, workflow_invocation_id: Union[int, str]) -> Optional[Dict[str, Any]]:
        """
        获取 workflow 的最新 AutoFix 结果

        Args:
            workflow_invocation_id: Workflow Invocation ID (可以是整数或编码字符串)

        Returns:
            最新的 AutoFix 结果，如果不存在则返回 None
        """
        try:
            wf_id = str(workflow_invocation_id)
            history = self._load_history(wf_id)

            if not history['executions']:
                log.debug(f"No AutoFix history found for workflow {wf_id}")
                return None

            latest = history['executions'][-1]
            log.info(f"📋 Loaded latest AutoFix result for workflow {wf_id}")
            log.info(f"   Timestamp: {latest['timestamp']}")
            log.info(f"   Applied: {len(latest.get('applied_fixes', []))}, "
                    f"Pending: {len(latest.get('pending_fixes', []))}, "
                    f"Failed: {len(latest.get('failed_fixes', []))}")

            return latest

        except Exception as e:
            log.error(f"Failed to get latest AutoFix result for workflow {wf_id}: {e}")
            return None

    def get_all_autofix_history(self, workflow_invocation_id: Union[int, str]) -> Dict[str, Any]:
        """
        获取 workflow 的完整 AutoFix 历史

        Args:
            workflow_invocation_id: Workflow Invocation ID

        Returns:
            完整的历史记录
        """
        return self._load_history(workflow_invocation_id)

    def list_workflows_with_autofix(self) -> List[int]:
        """
        列出所有有 AutoFix 历史的 workflow IDs

        Returns:
            Workflow Invocation IDs 列表
        """
        try:
            workflow_ids = []
            for file_path in self.history_dir.glob("workflow_*_autofix.json"):
                # 从文件名提取 workflow ID
                # 格式: workflow_{id}_autofix.json
                parts = file_path.stem.split('_')
                if len(parts) >= 2:
                    try:
                        workflow_id = int(parts[1])
                        workflow_ids.append(workflow_id)
                    except ValueError:
                        continue

            log.info(f"Found {len(workflow_ids)} workflows with AutoFix history")
            return sorted(workflow_ids)

        except Exception as e:
            log.error(f"Failed to list workflows with AutoFix: {e}")
            return []

    def delete_workflow_history(self, workflow_invocation_id: Union[int, str]) -> bool:
        """
        删除 workflow 的 AutoFix 历史

        Args:
            workflow_invocation_id: Workflow Invocation ID

        Returns:
            bool: 是否删除成功
        """
        try:
            file_path = self._get_workflow_file(workflow_invocation_id)

            if not file_path.exists():
                log.warning(f"No history file found for workflow {workflow_invocation_id}")
                return True

            file_path.unlink()
            log.info(f"✅ Deleted AutoFix history for workflow {workflow_invocation_id}")
            return True

        except Exception as e:
            log.error(f"Failed to delete history for workflow {workflow_invocation_id}: {e}")
            return False

    def get_statistics(self) -> Dict[str, Any]:
        """
        获取 AutoFix 持久化统计信息

        Returns:
            统计信息字典
        """
        try:
            workflow_ids = self.list_workflows_with_autofix()

            total_executions = 0
            total_applied_fixes = 0
            total_pending_fixes = 0
            total_failed_fixes = 0

            for workflow_id in workflow_ids:
                history = self._load_history(workflow_id)
                total_executions += len(history['executions'])

                for execution in history['executions']:
                    total_applied_fixes += len(execution.get('applied_fixes', []))
                    total_pending_fixes += len(execution.get('pending_fixes', []))
                    total_failed_fixes += len(execution.get('failed_fixes', []))

            return {
                'total_workflows': len(workflow_ids),
                'total_executions': total_executions,
                'total_applied_fixes': total_applied_fixes,
                'total_pending_fixes': total_pending_fixes,
                'total_failed_fixes': total_failed_fixes,
                'history_dir': str(self.history_dir),
                'workflows': workflow_ids
            }

        except Exception as e:
            log.error(f"Failed to get statistics: {e}")
            return {
                'error': str(e)
            }


# 全局单例（由 API 初始化）
_persistence_instance: Optional[AutoFixPersistence] = None


def get_persistence(data_dir: Optional[Path] = None) -> AutoFixPersistence:
    """
    获取 AutoFix 持久化管理器的全局单例

    Args:
        data_dir: Galaxy data 目录路径（首次调用时需要提供）

    Returns:
        AutoFixPersistence 实例
    """
    global _persistence_instance

    if _persistence_instance is None:
        if data_dir is None:
            raise ValueError("data_dir is required for first-time initialization")
        _persistence_instance = AutoFixPersistence(data_dir)

    return _persistence_instance
