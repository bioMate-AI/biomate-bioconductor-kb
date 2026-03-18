"""
Workflow Fix Applier - 真正应用修复方案

负责实际修改Galaxy数据库、Nextflow配置和AWS资源
"""

import json
import logging
import os
import subprocess
from pathlib import Path
from typing import Dict, Any, Optional, List
import boto3
from botocore.exceptions import ClientError

from galaxy.ai.workflow_ops.types import FixPlan, FixAction, ActionType

log = logging.getLogger(__name__)


class WorkflowFixApplier:
    """
    Workflow修复应用器

    将AI生成的修复方案真正应用到系统中
    """

    def __init__(self, app, user=None):
        """
        Args:
            app: Galaxy app instance
            user: 当前用户 (用于权限检查和资源隔离)
        """
        self.app = app
        self.sa_session = app.model.context
        self.user = user  # ← 保存用户信息供权限检查

        # AWS配置 (系统默认配置)
        self.aws_profile = os.environ.get('AWS_PROFILE')
        self.aws_region = os.environ.get('AWS_REGION', 'us-east-1')
        self.s3_bucket = os.environ.get('AWS_S3_BUCKET')
        self.batch_queue = os.environ.get('AWS_BATCH_QUEUE')

        # Nextflow工作目录
        self.nextflow_work_dir = Path(app.config.jobs_directory) / "nextflow_workflows"
        self.nextflow_work_dir.mkdir(parents=True, exist_ok=True)

        # 加载用户配置（配额、预算等）
        self.user_prefs = None
        if self.user:
            self.user_prefs = self._get_or_create_user_preferences(self.user)

    def _check_user_permission(self, invocation) -> bool:
        """
        检查当前用户是否有权限修改这个 invocation

        Returns:
            True if user has permission, False otherwise
        """
        if not self.user:
            log.warning("⚠️ 没有提供用户信息,跳过权限检查 (开发环境)")
            return True

        # 检查1: invocation是否属于这个用户的history
        if invocation.history:
            if invocation.history.user_id == self.user.id:
                return True  # 用户拥有这个workflow

        # 检查2: 用户是否是管理员
        if hasattr(self.user, 'is_admin') and self.user.is_admin:
            log.info(f"✓ 管理员 {self.user.email} 有权限修改 invocation {invocation.id}")
            return True

        # 拒绝访问
        log.error(f"❌ 用户 {self.user.email if self.user else 'Unknown'} 无权修改 invocation {invocation.id}")
        return False

    def _get_or_create_user_preferences(self, user):
        """
        获取或创建用户配置

        Returns:
            UserCloudPreferences instance or None
        """
        try:
            from galaxy.model import UserCloudPreferences

            prefs = self.sa_session.query(UserCloudPreferences).filter_by(
                user_id=user.id
            ).first()

            if not prefs:
                log.info(f"📝 为用户 {user.email} 创建默认配置")
                prefs = UserCloudPreferences(user_id=user.id)
                self.sa_session.add(prefs)
                self.sa_session.commit()

            return prefs

        except Exception as e:
            log.warning(f"⚠️ 无法加载用户配置: {e}")
            return None

    def _check_resource_quota(self, memory_gb: float = 0, cpus: int = 0, disk_gb: float = 0) -> tuple:
        """
        检查资源请求是否在用户配额内

        Args:
            memory_gb: 请求的内存(GB)
            cpus: 请求的CPU核心数
            disk_gb: 请求的磁盘(GB)

        Returns:
            (is_allowed, warning_message, is_admin_override)
            - is_allowed: 是否允许
            - warning_message: 警告消息（如果有）
            - is_admin_override: 是否是管理员豁免
        """
        # 如果没有用户或用户配置，使用默认限制
        if not self.user:
            log.warning("⚠️ 没有用户信息，跳过配额检查")
            return True, "", False

        # 检查是否是管理员
        is_admin = hasattr(self.user, 'is_admin') and self.user.is_admin

        # 如果没有用户配置，使用系统默认值
        if not self.user_prefs:
            log.warning(f"⚠️ 用户 {self.user.email} 没有配置，使用系统默认限制")
            max_memory = 64
            max_cpus = 16
            max_disk = 500
        else:
            max_memory = self.user_prefs.max_memory_gb
            max_cpus = self.user_prefs.max_cpus
            max_disk = self.user_prefs.max_disk_gb

        # 收集超限信息
        violations = []
        warnings = []

        # 检查内存配额
        if memory_gb > 0:
            if memory_gb > max_memory:
                violations.append(f"内存 {memory_gb}GB 超过限制 {max_memory}GB")
            # 大额度警告（超过512GB）
            if memory_gb > 512:
                warnings.append(f"⚠️ 内存用量极高: {memory_gb}GB！请确认是否正确")

        # 检查CPU配额
        if cpus > 0:
            if cpus > max_cpus:
                violations.append(f"CPU {cpus} cores 超过限制 {max_cpus} cores")
            # 大额度警告（超过64核）
            if cpus > 64:
                warnings.append(f"⚠️ CPU用量极高: {cpus} cores！请确认是否正确")

        # 检查磁盘配额
        if disk_gb > 0:
            if disk_gb > max_disk:
                violations.append(f"磁盘 {disk_gb}GB 超过限制 {max_disk}GB")
            # 大额度警告（超过5TB）
            if disk_gb > 5000:
                warnings.append(f"⚠️ 磁盘用量极高: {disk_gb}GB！请确认是否正确")

        # 如果有超限情况
        if violations:
            violation_msg = "; ".join(violations)

            # 管理员：豁免但警告
            if is_admin:
                warning_msg = f"🔓 管理员豁免 - {violation_msg}"
                if warnings:
                    warning_msg += " | " + " ".join(warnings)
                log.warning(f"{warning_msg} - 用户: {self.user.email}")
                return True, warning_msg, True  # 允许，但有警告，是管理员豁免

            # 普通用户：拒绝
            else:
                error_msg = f"❌ 配额超限 - {violation_msg}"
                log.error(f"{error_msg} - 用户: {self.user.email}")
                return False, error_msg, False  # 拒绝

        # 没有超限，但有大额度警告
        if warnings:
            warning_msg = " ".join(warnings)
            log.warning(f"{warning_msg} - 用户: {self.user.email}")
            return True, warning_msg, False  # 允许，但有警告

        # 一切正常
        return True, "", False

    def _create_audit_log(self, invocation_id: int, fix_plan: FixPlan, auto_approved: bool = True) -> Optional[Any]:
        """
        创建审计日志记录

        Args:
            invocation_id: Workflow invocation ID
            fix_plan: 修复计划
            auto_approved: 是否自动批准

        Returns:
            AIFixAuditLog instance or None
        """
        if not self.user:
            log.warning("⚠️ 没有用户信息，跳过审计日志")
            return None

        try:
            from galaxy.model import AIFixAuditLog
            from datetime import datetime

            # 确定风险等级
            risk_level = "low"
            fix_type = "unknown"

            if hasattr(fix_plan, 'fix_type'):
                fix_type = str(fix_plan.fix_type.value if hasattr(fix_plan.fix_type, 'value') else fix_plan.fix_type)

            # 简单的风险评估
            if fix_plan.fix_actions:
                for action in fix_plan.fix_actions:
                    if action.action == ActionType.INCREASE_MEMORY:
                        memory = action.params.get('new', 0)
                        if memory > 128:
                            risk_level = "medium"
                        if memory > 512:
                            risk_level = "high"
                    elif action.action == ActionType.INCREASE_CPU:
                        cpus = action.params.get('new', 0)
                        if cpus > 32:
                            risk_level = "medium"
                        if cpus > 64:
                            risk_level = "high"

            # 创建审计日志
            audit_log = AIFixAuditLog(
                user_id=self.user.id,
                invocation_id=invocation_id,
                create_time=datetime.now(),
                fix_type=fix_type,
                fix_details={
                    'actions': [
                        {
                            'action': str(action.action.value if hasattr(action.action, 'value') else action.action),
                            'params': action.params
                        }
                        for action in fix_plan.fix_actions
                    ]
                },
                fix_reason=fix_plan.reason if hasattr(fix_plan, 'reason') else None,
                risk_level=risk_level,
                auto_approved=auto_approved,
                user_approved=False,  # 目前都是自动批准
                approval_time=datetime.now() if auto_approved else None,
                execution_start_time=datetime.now(),
            )

            self.sa_session.add(audit_log)
            self.sa_session.flush()  # 获取ID但不提交

            return audit_log

        except Exception as e:
            log.error(f"❌ 创建审计日志失败: {e}", exc_info=True)
            return None

    def _update_audit_log(self, audit_log, success: bool, error_message: str = None, duration: float = None):
        """
        更新审计日志执行结果

        Args:
            audit_log: AIFixAuditLog instance
            success: 是否成功
            error_message: 错误消息
            duration: 执行时长（秒）
        """
        if not audit_log:
            return

        try:
            from datetime import datetime

            audit_log.execution_end_time = datetime.now()
            audit_log.success = success
            audit_log.error_message = error_message

            # 计算执行时长
            if audit_log.execution_start_time and audit_log.execution_end_time:
                duration = (audit_log.execution_end_time - audit_log.execution_start_time).total_seconds()

            self.sa_session.add(audit_log)
            # 注意：不在这里commit，由调用方决定

        except Exception as e:
            log.error(f"❌ 更新审计日志失败: {e}", exc_info=True)

    def apply_parameter_fix(
        self,
        invocation_id: int,
        fix_plan: FixPlan,
        context: Dict[str, Any]
    ) -> bool:
        """
        应用参数修复

        实际修改WorkflowInvocation的input_step_parameters
        """
        # ✅ 创建审计日志
        audit_log = self._create_audit_log(invocation_id, fix_plan, auto_approved=True)

        try:
            # 获取invocation
            invocation = self.sa_session.query(
                self.app.model.WorkflowInvocation
            ).get(invocation_id)

            if not invocation:
                error_msg = f"Workflow invocation {invocation_id} not found"
                log.error(error_msg)
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()  # 提交审计日志
                return False

            # ✅ 权限检查 - 防止用户修改他人的workflow
            if not self._check_user_permission(invocation):
                error_msg = f"User {self.user.email if self.user else 'Unknown'} does not have permission"
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()  # 提交审计日志
                raise PermissionError(error_msg)

            log.info(f"✓ 权限检查通过: 用户 {self.user.email if self.user else 'System'} "
                    f"可以修改 invocation {invocation_id}")

            # 应用每个参数修改
            param_changes = []
            for action in fix_plan.fix_actions:
                if action.action == ActionType.UPDATE_PARAM:
                    param_name = action.params['param_name']
                    new_value = action.params['new_value']

                    # 找到对应的step parameter
                    for step_param in invocation.input_step_parameters:
                        if step_param.parameter_name == param_name:
                            old_value = step_param.parameter_value
                            step_param.parameter_value = new_value
                            param_changes.append({
                                'param': param_name,
                                'old': old_value,
                                'new': new_value
                            })
                            log.info(f"✓ 参数已修改: {param_name} = {old_value} → {new_value}")
                            break
                    else:
                        # 如果参数不存在，创建新的
                        from galaxy.model import WorkflowRequestInputStepParameter
                        new_param = WorkflowRequestInputStepParameter()
                        new_param.workflow_invocation_id = invocation_id
                        new_param.parameter_name = param_name
                        new_param.parameter_value = new_value
                        invocation.input_step_parameters.append(new_param)
                        self.sa_session.add(new_param)
                        param_changes.append({
                            'param': param_name,
                            'old': None,
                            'new': new_value
                        })
                        log.info(f"✓ 新参数已添加: {param_name} = {new_value}")

            # 提交到数据库
            self.sa_session.add(invocation)

            # ✅ 更新审计日志 - 成功
            self._update_audit_log(audit_log, success=True)
            self.sa_session.commit()  # 同时提交修复和审计日志

            log.info(f"✅ 参数修复已应用到 invocation {invocation_id}: {param_changes}")
            return True

        except Exception as e:
            error_msg = str(e)
            log.error(f"❌ 参数修复失败: {e}", exc_info=True)

            # ✅ 更新审计日志 - 失败
            self._update_audit_log(audit_log, success=False, error_message=error_msg)

            self.sa_session.rollback()
            return False

    def apply_resource_scaling_fix(
        self,
        invocation_id: int,
        fix_plan: FixPlan,
        context: Dict[str, Any]
    ) -> bool:
        """
        应用资源扩容修复

        步骤:
        1. 更新Nextflow配置文件（增加内存/CPU）
        2. 如果使用AWS Batch，更新Job Definition
        3. 重新提交workflow
        """
        # ✅ 创建审计日志
        audit_log = self._create_audit_log(invocation_id, fix_plan, auto_approved=True)

        try:
            invocation = self.sa_session.query(
                self.app.model.WorkflowInvocation
            ).get(invocation_id)

            if not invocation:
                error_msg = f"Workflow invocation {invocation_id} not found"
                log.error(error_msg)
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()
                return False

            # ✅ 权限检查
            if not self._check_user_permission(invocation):
                error_msg = f"User {self.user.email if self.user else 'Unknown'} does not have permission"
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()
                raise PermissionError(error_msg)

            log.info(f"✓ 权限检查通过")

            # 收集资源变更
            resource_changes = {}
            requested_memory_gb = 0
            requested_cpus = 0
            requested_disk_gb = 0

            for action in fix_plan.fix_actions:
                if action.action == ActionType.INCREASE_MEMORY:
                    new_memory = action.params['new']
                    resource_changes['memory'] = f"{new_memory}GB"
                    requested_memory_gb = float(new_memory)
                    log.info(f"✓ 内存将扩容至: {new_memory}GB")

                elif action.action == ActionType.INCREASE_DISK:
                    new_disk = action.params['new']
                    resource_changes['disk'] = f"{new_disk}GB"
                    requested_disk_gb = float(new_disk)
                    log.info(f"✓ 磁盘将扩容至: {new_disk}GB")

                elif action.action == ActionType.INCREASE_CPU:
                    new_cpus = action.params['new']
                    resource_changes['cpus'] = new_cpus
                    requested_cpus = int(new_cpus)
                    log.info(f"✓ CPU将扩容至: {new_cpus} cores")

            # ✅ 配额检查 - 管理员豁免但有警告
            is_allowed, quota_msg, is_admin_override = self._check_resource_quota(
                memory_gb=requested_memory_gb,
                cpus=requested_cpus,
                disk_gb=requested_disk_gb
            )

            if not is_allowed:
                # 普通用户超配额 - 拒绝
                error_msg = f"资源配额检查失败: {quota_msg}"
                log.error(f"❌ {error_msg}")
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()
                raise ValueError(error_msg)

            if quota_msg:
                # 有警告消息（管理员豁免或大额度警告）
                log.warning(f"⚠️ 配额检查警告: {quota_msg}")
                if is_admin_override:
                    log.warning(f"🔓 管理员 {self.user.email} 使用豁免权限继续执行")
                # 将警告信息记录到审计日志
                if audit_log:
                    if not audit_log.fix_reason:
                        audit_log.fix_reason = ""
                    audit_log.fix_reason += f"\n配额警告: {quota_msg}"

            # 更新Nextflow配置
            success = self._update_nextflow_config(invocation_id, resource_changes)
            if not success:
                error_msg = "Nextflow配置更新失败"
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()
                return False

            # 如果使用AWS Batch，更新Job Definition
            if self.batch_queue and resource_changes.get('memory'):
                success = self._update_aws_batch_job_definition(
                    invocation_id,
                    resource_changes
                )
                if not success:
                    log.warning("AWS Batch Job Definition更新失败，但Nextflow配置已更新")

            # ✅ 更新审计日志 - 成功
            self._update_audit_log(audit_log, success=True)
            self.sa_session.commit()

            log.info(f"✅ 资源扩容修复已应用: {resource_changes}")
            return True

        except Exception as e:
            error_msg = str(e)
            log.error(f"❌ 资源扩容修复失败: {e}", exc_info=True)

            # ✅ 更新审计日志 - 失败
            self._update_audit_log(audit_log, success=False, error_message=error_msg)
            self.sa_session.commit()

            return False

    def apply_retry_fix(
        self,
        invocation_id: int,
        fix_plan: FixPlan,
        context: Dict[str, Any]
    ) -> bool:
        """
        应用重试修复

        重新调度失败的workflow
        """
        # ✅ 创建审计日志
        audit_log = self._create_audit_log(invocation_id, fix_plan, auto_approved=True)

        try:
            invocation = self.sa_session.query(
                self.app.model.WorkflowInvocation
            ).get(invocation_id)

            if not invocation:
                error_msg = f"Workflow invocation {invocation_id} not found"
                log.error(error_msg)
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()
                return False

            # 检查重试次数
            retry_count = context.get('retry_count', 0)
            max_retries = context.get('max_retries', 3)

            if retry_count >= max_retries:
                error_msg = f"已达到最大重试次数 {max_retries}"
                log.error(f"❌ {error_msg}")
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()
                return False

            # 重新提交workflow
            log.info(f"🔄 准备重新提交 workflow (第 {retry_count + 1} 次重试)...")

            # 方案1: 如果是Nextflow workflow，直接重新执行Nextflow命令
            success = self._resubmit_nextflow_workflow(invocation_id, retry_count + 1)

            if success:
                # 更新invocation状态
                invocation.state = 'new'  # 重置为新状态
                self.sa_session.add(invocation)

                # ✅ 更新审计日志 - 成功
                self._update_audit_log(audit_log, success=True)
                self.sa_session.commit()

                log.info(f"✅ Workflow已重新提交 (重试 {retry_count + 1}/{max_retries})")
                return True
            else:
                error_msg = "Workflow重新提交失败"
                log.error(f"❌ {error_msg}")
                self._update_audit_log(audit_log, success=False, error_message=error_msg)
                self.sa_session.commit()
                return False

        except Exception as e:
            error_msg = str(e)
            log.error(f"❌ 重试修复失败: {e}", exc_info=True)

            # ✅ 更新审计日志 - 失败
            self._update_audit_log(audit_log, success=False, error_message=error_msg)

            self.sa_session.rollback()
            return False

    def _update_nextflow_config(
        self,
        invocation_id: int,
        resource_changes: Dict[str, Any]
    ) -> bool:
        """更新Nextflow配置文件"""
        try:
            config_file = self.nextflow_work_dir / f"workflow_{invocation_id}" / "nextflow.config"

            if not config_file.exists():
                log.warning(f"Nextflow配置文件不存在: {config_file}")
                # 创建新的配置
                config_file.parent.mkdir(parents=True, exist_ok=True)
                config_content = self._generate_nextflow_config(resource_changes)
            else:
                # 读取现有配置并更新
                with open(config_file, 'r') as f:
                    config_content = f.read()

                # 更新资源配置
                if 'memory' in resource_changes:
                    # 简单的字符串替换（实际应该用配置解析器）
                    config_content = self._update_config_value(
                        config_content,
                        'memory',
                        resource_changes['memory']
                    )

                if 'cpus' in resource_changes:
                    config_content = self._update_config_value(
                        config_content,
                        'cpus',
                        resource_changes['cpus']
                    )

            # 写回配置文件
            with open(config_file, 'w') as f:
                f.write(config_content)

            log.info(f"✓ Nextflow配置已更新: {config_file}")
            return True

        except Exception as e:
            log.error(f"更新Nextflow配置失败: {e}")
            return False

    def _generate_nextflow_config(self, resource_changes: Dict[str, Any]) -> str:
        """生成Nextflow配置"""
        memory = resource_changes.get('memory', '8GB')
        cpus = resource_changes.get('cpus', 4)

        config = f"""
process {{
    executor = 'awsbatch'
    queue = '{self.batch_queue}'
    memory = '{memory}'
    cpus = {cpus}
}}

aws {{
    region = '{self.aws_region}'
    batch {{
        maxParallelTransfers = 4
    }}
}}
"""
        return config

    def _update_config_value(
        self,
        config_content: str,
        key: str,
        value: Any
    ) -> str:
        """更新配置文件中的某个值"""
        # 简化实现：使用正则替换
        import re

        # 匹配 key = 'value' 或 key = value
        pattern = rf"({key}\s*=\s*)['\"]*[^'\"\n]+['\"]*"
        if isinstance(value, str):
            replacement = rf"\1'{value}'"
        else:
            replacement = rf"\1{value}"

        updated = re.sub(pattern, replacement, config_content)
        return updated

    def _update_aws_batch_job_definition(
        self,
        invocation_id: int,
        resource_changes: Dict[str, Any]
    ) -> bool:
        """更新AWS Batch Job Definition"""
        try:
            # 创建Batch客户端
            session = boto3.Session(
                profile_name=self.aws_profile,
                region_name=self.aws_region
            )
            batch_client = session.client('batch')

            # ✅ 修复: 使用用户ID隔离Job Definition,防止命名冲突
            # 格式: galaxy-user{user_id}-inv{invocation_id}
            user_id = self.user.id if self.user else 0
            job_def_name = f"galaxy-user{user_id}-inv{invocation_id}"
            log.info(f"✓ 使用用户隔离的Job Definition名称: {job_def_name}")

            # 解析内存值（如"16GB" -> 16384）
            memory_mb = 8192  # 默认8GB
            if 'memory' in resource_changes:
                mem_str = resource_changes['memory']
                if 'GB' in mem_str:
                    memory_gb = int(mem_str.replace('GB', ''))
                    memory_mb = memory_gb * 1024

            cpus = resource_changes.get('cpus', 4)

            # ✅ 添加用户标签用于成本追踪和审计
            user_email = self.user.email if self.user else 'system'
            tags = {
                'galaxy_user_id': str(user_id),
                'galaxy_user_email': user_email,
                'galaxy_invocation_id': str(invocation_id),
                'created_by': 'galaxy_ai_ops',
                'managed_by': 'galaxy',
            }

            # 注册新版本的Job Definition
            response = batch_client.register_job_definition(
                jobDefinitionName=job_def_name,
                type='container',
                tags=tags,  # ← 添加标签
                containerProperties={
                    'image': 'nextflow/nextflow:latest',
                    'vcpus': cpus,
                    'memory': memory_mb,
                    'jobRoleArn': os.environ.get('AWS_BATCH_JOB_ROLE_ARN', ''),
                    'executionRoleArn': os.environ.get('AWS_BATCH_EXECUTION_ROLE_ARN', ''),
                }
            )

            log.info(f"✓ AWS Batch Job Definition已更新并添加用户标签: {tags}")

            log.info(f"✓ AWS Batch Job Definition已更新: {response['jobDefinitionArn']}")
            return True

        except ClientError as e:
            log.error(f"AWS Batch更新失败: {e}")
            return False
        except Exception as e:
            log.error(f"更新Job Definition失败: {e}")
            return False

    def _resubmit_nextflow_workflow(
        self,
        invocation_id: int,
        retry_attempt: int
    ) -> bool:
        """重新提交Nextflow workflow"""
        try:
            work_dir = self.nextflow_work_dir / f"workflow_{invocation_id}"

            if not work_dir.exists():
                log.error(f"Workflow目录不存在: {work_dir}")
                return False

            # Nextflow命令
            nf_script = work_dir / "main.nf"
            if not nf_script.exists():
                log.error(f"Nextflow脚本不存在: {nf_script}")
                return False

            # 使用-resume参数重新运行
            cmd = [
                'nextflow',
                'run',
                str(nf_script),
                '-resume',
                '-work-dir', str(work_dir / 'work'),
                '-config', str(work_dir / 'nextflow.config'),
            ]

            if self.s3_bucket:
                cmd.extend([
                    '-bucket-dir', f's3://{self.s3_bucket}/nextflow-work'
                ])

            log.info(f"🚀 执行命令: {' '.join(cmd)}")

            # 异步执行（不等待完成）
            process = subprocess.Popen(
                cmd,
                cwd=str(work_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True
            )

            log.info(f"✓ Nextflow已重新启动, PID: {process.pid}")

            # 保存进程信息供后续监控
            self._save_process_info(invocation_id, process.pid, retry_attempt)

            return True

        except Exception as e:
            log.error(f"重新提交Nextflow失败: {e}", exc_info=True)
            return False

    def _save_process_info(
        self,
        invocation_id: int,
        pid: int,
        retry_attempt: int
    ):
        """保存进程信息"""
        info_file = self.nextflow_work_dir / f"workflow_{invocation_id}" / "process_info.json"

        info = {
            'invocation_id': invocation_id,
            'pid': pid,
            'retry_attempt': retry_attempt,
            'timestamp': str(datetime.now())
        }

        with open(info_file, 'w') as f:
            json.dump(info, f, indent=2)

        log.info(f"✓ 进程信息已保存: {info_file}")


# 需要导入datetime
from datetime import datetime
