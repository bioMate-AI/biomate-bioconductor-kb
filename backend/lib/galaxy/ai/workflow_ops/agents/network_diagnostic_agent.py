"""
Network Diagnostic Agent

专门处理网络相关问题：
- S3 下载/上传失败
- 网络超时
- 连接错误
- DNS 解析失败
"""

import re
import logging
from typing import Dict, List, Any
from ..agent_system import (
    BaseAgent,
    AgentCapability,
    AgentTriggerCondition,
    AgentPriority
)

log = logging.getLogger(__name__)


class NetworkDiagnosticAgent(BaseAgent):
    """网络诊断专家 Agent"""

    @property
    def name(self) -> str:
        return "NetworkDiagnosticAgent"

    @property
    def capability(self) -> AgentCapability:
        return AgentCapability.NETWORK_DIAGNOSTIC

    @property
    def trigger_conditions(self) -> List[AgentTriggerCondition]:
        return [AgentTriggerCondition.ON_ERROR]

    @property
    def priority(self) -> AgentPriority:
        return AgentPriority.HIGH

    @property
    def requires_llm(self) -> bool:
        return False

    def can_handle(self, issue: Dict[str, Any]) -> bool:
        """判断是否能处理该问题"""
        message = issue.get('message', '').lower()

        network_keywords = [
            'timeout', 'connection', 'network', 'http', 'https',
            's3://', 'download', 'upload', 'failed to fetch',
            'unable to get', 'access denied', 'permission denied',
            'socket', 'dns', 'resolve'
        ]

        return any(keyword in message for keyword in network_keywords)

    async def analyze(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """分析网络问题"""
        issue = context.get('issue', {})
        message = issue.get('message', '')
        logs = context.get('logs', '')
        full_text = message + '\n' + logs

        analysis = {
            'issue_type': None,
            'failed_resources': [],
            'error_codes': [],
            'suggestions': []
        }

        # 1. S3 访问问题
        if 's3://' in full_text or 's3.amazonaws.com' in full_text:
            analysis['issue_type'] = 's3_access_error'

            # 提取 S3 URL
            s3_urls = re.findall(r's3://[^\s\'"]+', full_text)
            analysis['failed_resources'] = s3_urls[:5]

            # 检测具体错误
            if 'access denied' in full_text.lower() or '403' in full_text:
                analysis['error_codes'].append('403_FORBIDDEN')
                analysis['suggestions'].append({
                    'type': 'fix_s3_permissions',
                    'priority': 'high',
                    'description': 'IAM 权限不足，无法访问 S3 资源'
                })

            elif 'not found' in full_text.lower() or '404' in full_text:
                analysis['error_codes'].append('404_NOT_FOUND')
                analysis['suggestions'].append({
                    'type': 'check_s3_path',
                    'priority': 'medium',
                    'description': 'S3 文件不存在或路径错误'
                })

            else:
                analysis['suggestions'].append({
                    'type': 'general_s3_issue',
                    'priority': 'medium',
                    'description': 'S3 访问失败，请检查网络和权限'
                })

        # 2. 超时问题
        elif 'timeout' in full_text.lower():
            analysis['issue_type'] = 'network_timeout'
            analysis['suggestions'].append({
                'type': 'increase_timeout',
                'priority': 'medium',
                'description': '网络请求超时，可能是网络延迟或资源响应慢'
            })

        # 3. 连接失败
        elif 'connection' in full_text.lower() and 'refused' in full_text.lower():
            analysis['issue_type'] = 'connection_refused'
            analysis['suggestions'].append({
                'type': 'check_service_status',
                'priority': 'high',
                'description': '目标服务不可达或未启动'
            })

        # 4. DNS 解析失败
        elif 'dns' in full_text.lower() or 'resolve' in full_text.lower():
            analysis['issue_type'] = 'dns_resolution_error'
            analysis['suggestions'].append({
                'type': 'check_dns',
                'priority': 'high',
                'description': 'DNS 解析失败，无法解析主机名'
            })

        else:
            analysis['issue_type'] = 'general_network_error'
            analysis['suggestions'].append({
                'type': 'check_network',
                'priority': 'medium',
                'description': '网络连接异常'
            })

        log.info(f"Network diagnostic: {analysis['issue_type']}")
        return analysis

    async def suggest_fix(self, context: Dict[str, Any]) -> List[Dict[str, Any]]:
        """提供修复建议"""
        analysis = await self.analyze(context)
        suggestions = []

        for suggestion in analysis['suggestions']:
            if suggestion['type'] == 'fix_s3_permissions':
                bucket_name = 'your-bucket'
                # 尝试从 failed_resources 提取 bucket 名称
                if analysis['failed_resources']:
                    match = re.match(r's3://([^/]+)', analysis['failed_resources'][0])
                    if match:
                        bucket_name = match.group(1)

                suggestions.append({
                    'action': 'fix_s3_permissions',
                    'description': '修复 S3 访问权限',
                    'risk_level': 'medium',
                    'bucket_name': bucket_name,
                    'failed_urls': analysis['failed_resources'][:3],
                    'guidance': f"""
✅ S3 权限问题修复指南

📋 问题：无法访问 S3 文件（403 Forbidden）
💡 Bucket: {bucket_name}

🔧 修复步骤：

方法1: 配置 IAM Role（推荐）
  1. AWS Console → IAM → Roles
  2. 找到 AWS Batch Job Role
  3. 添加 S3 访问策略：
     ```json
     {{
         "Version": "2012-10-17",
         "Statement": [{{
             "Effect": "Allow",
             "Action": [
                 "s3:GetObject",
                 "s3:PutObject",
                 "s3:ListBucket"
             ],
             "Resource": [
                 "arn:aws:s3:::{bucket_name}/*",
                 "arn:aws:s3:::{bucket_name}"
             ]
         }}]
     }}
     ```

方法2: 更新 Bucket Policy
  1. S3 Console → Buckets → {bucket_name}
  2. Permissions → Bucket Policy
  3. 添加允许 Batch Role 访问的策略

方法3: 检查 S3 Block Public Access 设置
  确保未阻止 IAM Role 访问

失败的文件：
{chr(10).join([f'  • {url}' for url in analysis['failed_resources'][:3]])}
"""
                })

            elif suggestion['type'] == 'check_s3_path':
                suggestions.append({
                    'action': 'verify_s3_path',
                    'description': '验证 S3 文件路径',
                    'risk_level': 'low',
                    'failed_urls': analysis['failed_resources'][:3],
                    'guidance': f"""
⚠️ S3 文件不存在

📋 问题：S3 路径错误或文件不存在（404 Not Found）

🔧 检查步骤：
  1. 使用 AWS CLI 验证文件是否存在：
     ```bash
     aws s3 ls {analysis['failed_resources'][0] if analysis['failed_resources'] else 's3://your-bucket/path'}
     ```

  2. 检查文件路径拼写

  3. 确认文件已上传

  4. 检查 S3 bucket 名称是否正确
"""
                })

            elif suggestion['type'] == 'increase_timeout':
                suggestions.append({
                    'action': 'increase_network_timeout',
                    'description': '增加网络超时时间',
                    'risk_level': 'low',
                    'guidance': """
⏱️ 网络超时问题

📋 问题：网络请求超时

🔧 修复步骤：

方法1: 增加 Nextflow 超时配置
  在 nextflow.config 中添加：
  ```groovy
  aws {
      client {
          uploadMaxAttempts = 5
          uploadRetrySleep = 100
          connectionTimeout = 300000  // 5分钟
          socketTimeout = 300000
      }
  }
  ```

方法2: 使用更快的网络环境
  • 考虑使用 CloudFront CDN
  • 选择离数据源更近的 AWS Region

方法3: 检查网络带宽
  确保网络连接稳定
"""
                })

            elif suggestion['type'] == 'check_service_status':
                suggestions.append({
                    'action': 'diagnose_connection_refused',
                    'description': '诊断服务连接失败',
                    'risk_level': 'high',
                    'guidance': """
🔴 服务连接被拒绝

📋 问题：无法连接到目标服务

🔧 检查步骤：
  1. 确认服务是否运行
  2. 检查防火墙规则
  3. 验证端口是否正确
  4. 检查网络安全组（Security Group）设置
  5. 确认 VPC 配置正确
"""
                })

        return suggestions

    async def apply_fix(self, fix_plan: Dict[str, Any], context: Dict[str, Any]) -> bool:
        """应用修复（生成指导）"""
        try:
            guidance = fix_plan.get('guidance', '')

            if guidance:
                if 'fix_guidance' not in context:
                    context['fix_guidance'] = []
                context['fix_guidance'].append(guidance)

                log.info(f"Network diagnostic guidance generated: {fix_plan.get('action')}")
                return True

            return False

        except Exception as e:
            log.error(f"Failed to apply network fix: {e}")
            return False

    def get_cost_estimate(self) -> float:
        """无 LLM 成本"""
        return 0.0
