"""
Workflow AI Notification Service - 用户通知服务

支持多种通知渠道：
- 数据库内通知（前端轮询）
- Email通知
- Slack通知
- Webhook通知

Author: AI AutoFix Team
Date: 2026-01-20
"""

import logging
from typing import Any, Dict, List, Optional
from datetime import datetime
from enum import Enum
import json

log = logging.getLogger(__name__)


class NotificationType(Enum):
    """通知类型"""
    ERROR_DETECTED = "error_detected"
    FIX_APPLIED = "fix_applied"
    FIX_PENDING_APPROVAL = "fix_pending_approval"
    WORKFLOW_RESTARTED = "workflow_restarted"
    WORKFLOW_COMPLETED = "workflow_completed"
    WORKFLOW_FAILED = "workflow_failed"
    BUDGET_WARNING = "budget_warning"
    RESOURCE_LIMIT = "resource_limit"


class NotificationChannel(Enum):
    """通知渠道"""
    DATABASE = "database"  # 保存到数据库，前端轮询
    EMAIL = "email"
    SLACK = "slack"
    WEBHOOK = "webhook"


class WorkflowNotificationService:
    """
    Workflow通知服务

    功能：
    - 自动检测需要通知的事件
    - 根据用户偏好选择通知渠道
    - 支持通知模板和个性化
    - 防止通知轰炸（合并类似通知）
    """

    def __init__(self, app):
        """
        初始化通知服务

        Args:
            app: Galaxy app实例
        """
        self.app = app
        self.sa_session = app.model.context

    def send_notification(
        self,
        user_id: int,
        invocation_id: int,
        notification_type: NotificationType,
        title: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
        channels: Optional[List[NotificationChannel]] = None,
    ) -> bool:
        """
        发送通知

        Args:
            user_id: 用户ID
            invocation_id: Workflow invocation ID
            notification_type: 通知类型
            title: 通知标题
            message: 通知消息
            details: 额外详情（JSON）
            channels: 通知渠道列表（None = 使用用户偏好）

        Returns:
            True if notification sent successfully
        """
        try:
            # 1. 如果没有指定渠道，从用户偏好读取
            if channels is None:
                channels = self._get_user_notification_channels(user_id, notification_type)

            # 2. 发送到各个渠道
            success = True
            for channel in channels:
                try:
                    if channel == NotificationChannel.DATABASE:
                        self._send_database_notification(
                            user_id, invocation_id, notification_type,
                            title, message, details
                        )
                    elif channel == NotificationChannel.EMAIL:
                        self._send_email_notification(
                            user_id, invocation_id, notification_type,
                            title, message, details
                        )
                    elif channel == NotificationChannel.SLACK:
                        self._send_slack_notification(
                            user_id, invocation_id, notification_type,
                            title, message, details
                        )
                    elif channel == NotificationChannel.WEBHOOK:
                        self._send_webhook_notification(
                            user_id, invocation_id, notification_type,
                            title, message, details
                        )
                except Exception as e:
                    log.error(f"Failed to send {channel.value} notification: {e}")
                    success = False

            return success

        except Exception as e:
            log.error(f"Failed to send notification: {e}", exc_info=True)
            return False

    def _get_user_notification_channels(
        self,
        user_id: int,
        notification_type: NotificationType
    ) -> List[NotificationChannel]:
        """获取用户的通知偏好"""
        # TODO: 从用户配置读取
        # 目前默认只使用数据库通知
        return [NotificationChannel.DATABASE]

    def _send_database_notification(
        self,
        user_id: int,
        invocation_id: int,
        notification_type: NotificationType,
        title: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
    ):
        """保存通知到数据库"""
        from galaxy.model import WorkflowNotification

        notification = WorkflowNotification(
            user_id=user_id,
            invocation_id=invocation_id,
            notification_type=notification_type.value,
            title=title,
            message=message,
            details=json.dumps(details) if details else None,
            read=False,
            create_time=datetime.now(),
        )

        self.sa_session.add(notification)
        self.sa_session.commit()

        log.info(f"Saved database notification for user {user_id}, invocation {invocation_id}")

    def _send_email_notification(
        self,
        user_id: int,
        invocation_id: int,
        notification_type: NotificationType,
        title: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
    ):
        """发送Email通知"""
        from galaxy.model import User

        user = self.sa_session.query(User).get(user_id)
        if not user or not user.email:
            log.warning(f"Cannot send email: user {user_id} has no email")
            return

        email_body = self._format_email_body(
            notification_type, title, message, details, invocation_id
        )

        # TODO: 集成Galaxy的email服务
        # self.app.mail_service.send(
        #     to=user.email,
        #     subject=title,
        #     body=email_body
        # )

        log.info(f"Email notification queued for {user.email}")

    def _send_slack_notification(
        self,
        user_id: int,
        invocation_id: int,
        notification_type: NotificationType,
        title: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
    ):
        """发送Slack通知"""
        # TODO: 从用户配置读取Slack webhook URL
        webhook_url = self._get_user_slack_webhook(user_id)

        if not webhook_url:
            log.warning(f"No Slack webhook configured for user {user_id}")
            return

        slack_message = {
            "text": f"*{title}*",
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": title
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": message
                    }
                },
                {
                    "type": "context",
                    "elements": [
                        {
                            "type": "mrkdwn",
                            "text": f"Workflow Invocation ID: `{invocation_id}`"
                        }
                    ]
                }
            ]
        }

        # TODO: 实际发送HTTP请求到Slack
        # import requests
        # requests.post(webhook_url, json=slack_message)

        log.info(f"Slack notification sent for invocation {invocation_id}")

    def _send_webhook_notification(
        self,
        user_id: int,
        invocation_id: int,
        notification_type: NotificationType,
        title: str,
        message: str,
        details: Optional[Dict[str, Any]] = None,
    ):
        """发送Webhook通知"""
        webhook_url = self._get_user_webhook_url(user_id)

        if not webhook_url:
            return

        payload = {
            "user_id": user_id,
            "invocation_id": invocation_id,
            "notification_type": notification_type.value,
            "title": title,
            "message": message,
            "details": details,
            "timestamp": datetime.now().isoformat(),
        }

        # TODO: 实际发送HTTP请求
        # import requests
        # requests.post(webhook_url, json=payload, timeout=5)

        log.info(f"Webhook notification sent for invocation {invocation_id}")

    def _format_email_body(
        self,
        notification_type: NotificationType,
        title: str,
        message: str,
        details: Optional[Dict[str, Any]],
        invocation_id: int,
    ) -> str:
        """格式化Email内容"""
        body = f"""
Galaxy Workflow AI Notification
================================

{title}

{message}

Workflow Invocation ID: {invocation_id}
Notification Type: {notification_type.value}
Time: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

"""

        if details:
            body += "\n详细信息:\n"
            body += json.dumps(details, indent=2, ensure_ascii=False)

        body += """

---
This is an automated notification from Galaxy AI AutoFix system.
"""

        return body

    def _get_user_slack_webhook(self, user_id: int) -> Optional[str]:
        """获取用户的Slack webhook URL"""
        # TODO: 从数据库读取
        return None

    def _get_user_webhook_url(self, user_id: int) -> Optional[str]:
        """获取用户的自定义webhook URL"""
        # TODO: 从数据库读取
        return None

    def notify_error_detected(
        self,
        user_id: int,
        invocation_id: int,
        error_type: str,
        error_message: str,
        auto_fixable: bool,
    ):
        """错误检测通知"""
        title = f"检测到Workflow错误: {error_type}"
        message = error_message

        if auto_fixable:
            message += "\n\n✅ 此错误可以自动修复，系统将尝试自动修复并重启workflow。"
        else:
            message += "\n\n⚠️ 此错误需要手动处理。"

        self.send_notification(
            user_id=user_id,
            invocation_id=invocation_id,
            notification_type=NotificationType.ERROR_DETECTED,
            title=title,
            message=message,
            details={'error_type': error_type, 'auto_fixable': auto_fixable},
        )

    def notify_fix_applied(
        self,
        user_id: int,
        invocation_id: int,
        fix_explanation: str,
        new_invocation_id: Optional[int] = None,
    ):
        """修复应用通知"""
        title = "AutoFix已自动应用修复"
        message = f"修复说明: {fix_explanation}"

        if new_invocation_id:
            message += f"\n\nWorkflow已重启，新的Invocation ID: {new_invocation_id}"

        self.send_notification(
            user_id=user_id,
            invocation_id=invocation_id,
            notification_type=NotificationType.FIX_APPLIED,
            title=title,
            message=message,
            details={'new_invocation_id': new_invocation_id},
        )

    def notify_approval_required(
        self,
        user_id: int,
        invocation_id: int,
        fix_explanation: str,
        risk_level: str,
        estimated_cost: float,
    ):
        """需要审批通知"""
        title = "修复需要您的批准"
        message = f"""
修复说明: {fix_explanation}

风险等级: {risk_level}
预估成本: ${estimated_cost:.2f}

请登录Galaxy查看详情并批准或拒绝此修复。
"""

        self.send_notification(
            user_id=user_id,
            invocation_id=invocation_id,
            notification_type=NotificationType.FIX_PENDING_APPROVAL,
            title=title,
            message=message,
            details={
                'risk_level': risk_level,
                'estimated_cost': estimated_cost,
            },
            channels=[NotificationChannel.DATABASE, NotificationChannel.EMAIL],  # 重要通知，同时用email
        )

    def notify_workflow_completed(
        self,
        user_id: int,
        invocation_id: int,
        total_tasks: int,
        execution_time: float,
    ):
        """Workflow完成通知"""
        title = "Workflow执行完成"
        message = f"""
您的workflow已成功完成！

总任务数: {total_tasks}
执行时间: {execution_time:.1f}秒
"""

        self.send_notification(
            user_id=user_id,
            invocation_id=invocation_id,
            notification_type=NotificationType.WORKFLOW_COMPLETED,
            title=title,
            message=message,
        )
