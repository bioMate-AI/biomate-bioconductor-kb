"""
Docker Daemon Fixer

检测和修复 Docker daemon 未运行错误

错误特征：
- Exit code: 125
- Error message: "Cannot connect to the Docker daemon"
- Error message: "Is the docker daemon running?"

修复策略：
1. 启动 Docker Desktop（手动操作）
2. 修改 executor 配置为 awsbatch（自动修复）
3. 使用 Conda 替代 Docker（自动修复）
"""

import logging
from typing import List, Dict, Any

from galaxy.ai.workflow_ops.models import RootCause, Action, ConfigChange

log = logging.getLogger(__name__)


class DockerDaemonFixer:
    """Docker Daemon 未运行错误修复器"""

    def __init__(self):
        self.name = "DockerDaemonFixer"

    def can_fix(self, root_cause: RootCause) -> bool:
        """
        检测是否是 Docker daemon 错误

        检测条件：
        1. error_type == 'docker_daemon_not_running'
        2. Exit code == '125'
        3. 错误消息包含 Docker daemon 关键词
        """
        # 检查 error_type
        if hasattr(root_cause, 'metadata') and root_cause.metadata:
            if root_cause.metadata.get('error_type') == 'docker_daemon_not_running':
                return True

        # 检查 exit code
        evidence_str = ' '.join(root_cause.evidence) if root_cause.evidence else ''
        if '125' in evidence_str or '125' in root_cause.description:
            return True

        # 检查错误消息
        keywords = [
            'cannot connect to the docker daemon',
            'docker daemon',
            'docker.sock',
            'is the docker daemon running'
        ]

        desc_lower = root_cause.description.lower()
        return any(kw in desc_lower for kw in keywords)

    async def suggest_fixes(
        self,
        root_cause: RootCause,
        context: Dict[str, Any],
        trans
    ) -> List[Action]:
        """
        生成修复建议

        Returns:
            List[Action]: 3 个修复动作
        """
        log.info(f"[DockerDaemonFixer] Analyzing root cause: {root_cause.type}")

        invocation_id = context.get('invocation_id', 'unknown')
        work_dir = context.get('work_dir', f'workflow_{invocation_id}')
        config_file = f"{work_dir}/nextflow.config"

        actions = []

        # Action 1: 启动 Docker Desktop（手动操作）
        actions.append(Action(
            action_id=f"docker_start_{root_cause.id}",
            title="启动 Docker Desktop",
            description=(
                "当前 workflow 配置使用 Docker 容器，但 Docker daemon 未运行。\n\n"
                "**手动操作步骤**：\n"
                "1. 打开 Docker Desktop 应用\n"
                "2. 等待 Docker daemon 启动完成（托盘图标变为绿色）\n"
                "3. 在终端运行 `docker ps` 验证（应该能看到容器列表）\n"
                "4. 返回 Galaxy 重新运行 workflow\n\n"
                "**注意**: 此操作需要手动完成，无法自动执行。"
            ),
            auto_apply=False,  # 需要用户手动操作
            risk_level="low",
            estimated_time_minutes=2,
            config_changes=[],
            validation_command="docker ps",
            rollback_possible=False
        ))

        # Action 2: 修改 executor 为 awsbatch（自动修复）
        actions.append(Action(
            action_id=f"executor_awsbatch_{root_cause.id}",
            title="修改 executor 为 AWS Batch",
            description=(
                "将 Nextflow executor 从 `local` 修改为 `awsbatch`，任务将在 AWS Batch 上运行。\n\n"
                "**优点**：\n"
                "• 无需本地 Docker daemon\n"
                "• 可扩展性更好（自动伸缩）\n"
                "• 自动资源管理\n"
                "• 适合生产环境\n\n"
                "**前提条件**：\n"
                "• 需要 AWS 账户和 Batch 配置\n"
                "• 需要配置 S3 存储桶\n\n"
                "**自动修复**: 点击下方按钮将自动修改配置并重新运行。"
            ),
            auto_apply=True,  # ⭐ 可以自动应用
            risk_level="low",
            estimated_time_minutes=1,
            config_changes=[
                ConfigChange(
                    file_path=config_file,
                    change_type="modify",
                    old_value="process.executor = 'local'",
                    new_value="process.executor = 'awsbatch'",
                    line_number=None,  # 自动查找
                    description="修改进程执行器为 AWS Batch"
                )
            ],
            validation_command=None,
            rollback_possible=True
        ))

        # Action 3: 使用 Conda 替代 Docker（自动修复）
        actions.append(Action(
            action_id=f"conda_instead_docker_{root_cause.id}",
            title="使用 Conda 替代 Docker",
            description=(
                "禁用 Docker，使用 Conda 管理软件环境。\n\n"
                "**优点**：\n"
                "• 无需 Docker daemon\n"
                "• 更轻量级\n"
                "• 适合本地开发\n\n"
                "**缺点**：\n"
                "• 需要安装 Conda/Mamba\n"
                "• 某些工具可能不可用\n"
                "• 首次运行需要下载环境（较慢）\n\n"
                "**前提条件**: 系统已安装 Conda 或 Mamba\n\n"
                "**自动修复**: 点击下方按钮将自动修改配置。"
            ),
            auto_apply=True,
            risk_level="medium",  # 风险稍高，因为需要 Conda
            estimated_time_minutes=1,
            config_changes=[
                ConfigChange(
                    file_path=config_file,
                    change_type="modify",
                    old_value="docker.enabled = true",
                    new_value="docker.enabled = false\nconda.enabled = true",
                    description="禁用 Docker，启用 Conda"
                )
            ],
            validation_command="conda --version || mamba --version",
            rollback_possible=True
        ))

        log.info(f"[DockerDaemonFixer] Generated {len(actions)} fix actions")
        return actions
