"""
AutoFix 2.0 - Tool System for Deep Analysis

这个模块提供了一套工具，让 LLM 能够主动调查错误：
- 下载和查看 S3 文件
- 生成修复后的文件
- 查看 workflow 参数
- 执行安全的命令

作者：AI Workflow AutoFix Team
日期：2026-01-30
"""

import logging
import json
import tempfile
import os
from typing import Any, Dict, List, Optional
from pathlib import Path

log = logging.getLogger(__name__)


class Tool:
    """工具基类"""

    def __init__(self, name: str, description: str):
        self.name = name
        self.description = description

    def execute(self, **kwargs) -> Dict[str, Any]:
        """执行工具，返回结果"""
        raise NotImplementedError


class DownloadS3FileTool(Tool):
    """
    下载 S3 文件并查看内容

    用途：当错误涉及输入文件（如 samplesheet）时，
    下载文件查看实际内容，以便给出精确的修复建议
    """

    def __init__(self, app_config):
        super().__init__(
            name="download_s3_file",
            description="Download and inspect an S3 file to understand its format and content"
        )
        self.app_config = app_config

    def execute(self, s3_path: str, max_size_mb: int = 10) -> Dict[str, Any]:
        """
        下载 S3 文件并返回内容

        Args:
            s3_path: S3 路径 (e.g., s3://bucket/key)
            max_size_mb: 最大文件大小限制（MB）

        Returns:
            {
                'success': bool,
                'content': str,  # 文件内容（文本文件）
                'size_bytes': int,
                'lines': int,
                'preview': str,  # 前几行预览
                'error': str     # 如果失败
            }
        """
        try:
            import boto3
            from botocore.exceptions import ClientError

            # 解析 S3 路径
            if not s3_path.startswith('s3://'):
                return {
                    'success': False,
                    'error': f"Invalid S3 path: {s3_path}"
                }

            parts = s3_path[5:].split('/', 1)
            bucket = parts[0]
            key = parts[1] if len(parts) > 1 else ''

            # 创建 S3 客户端
            s3_client = boto3.client('s3')

            # 检查文件大小
            try:
                head = s3_client.head_object(Bucket=bucket, Key=key)
                size_bytes = head['ContentLength']

                if size_bytes > max_size_mb * 1024 * 1024:
                    return {
                        'success': False,
                        'error': f"File too large: {size_bytes / 1024 / 1024:.2f} MB (limit: {max_size_mb} MB)"
                    }
            except ClientError as e:
                return {
                    'success': False,
                    'error': f"Failed to access file: {str(e)}"
                }

            # 下载文件到临时目录
            with tempfile.NamedTemporaryFile(mode='w+b', delete=False, suffix='_s3download') as tmp:
                tmp_path = tmp.name
                s3_client.download_fileobj(
                    Bucket=bucket,
                    Key=key,
                    Fileobj=tmp
                )

            # 读取内容
            try:
                with open(tmp_path, 'r', encoding='utf-8') as f:
                    content = f.read()

                lines = content.split('\n')
                preview = '\n'.join(lines[:10])  # 前 10 行预览

                log.info(f"✅ Successfully downloaded {s3_path} ({size_bytes} bytes, {len(lines)} lines)")

                return {
                    'success': True,
                    'content': content,
                    'size_bytes': size_bytes,
                    'lines': len(lines),
                    'preview': preview,
                    's3_path': s3_path,
                }
            except UnicodeDecodeError:
                # 二进制文件
                return {
                    'success': False,
                    'error': f"File is binary, cannot display as text"
                }
            finally:
                # 清理临时文件
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)

        except Exception as e:
            log.error(f"Failed to download {s3_path}: {e}")
            return {
                'success': False,
                'error': str(e)
            }


class UploadS3FileTool(Tool):
    """
    生成并上传修复后的文件到 S3

    用途：当 LLM 生成了修复后的文件内容时，
    自动上传到 S3 并返回新的 S3 路径
    """

    def __init__(self, app_config):
        super().__init__(
            name="upload_s3_file",
            description="Upload a generated/fixed file to S3"
        )
        self.app_config = app_config

    def execute(
        self,
        content: str,
        original_s3_path: str,
        suffix: str = "_autofix",
        user_id: str = "",
        workflow_id: str = "",
    ) -> Dict[str, Any]:
        """
        上传文件到 S3

        Args:
            content: 文件内容
            original_s3_path: 原始 S3 路径（用于推断上传位置）
            suffix: 文件名后缀
            user_id: User ID for S3 cost-attribution tagging
            workflow_id: Workflow ID for S3 cost-attribution tagging

        Returns:
            {
                'success': bool,
                'new_s3_path': str,
                'size_bytes': int,
                'error': str
            }
        """
        try:
            import boto3

            # 解析原始路径
            if not original_s3_path.startswith('s3://'):
                return {
                    'success': False,
                    'error': f"Invalid S3 path: {original_s3_path}"
                }

            parts = original_s3_path[5:].split('/', 1)
            bucket = parts[0]
            original_key = parts[1] if len(parts) > 1 else ''

            # 生成新的 key（添加后缀）
            key_parts = original_key.rsplit('.', 1)
            if len(key_parts) == 2:
                new_key = f"{key_parts[0]}{suffix}.{key_parts[1]}"
            else:
                new_key = f"{original_key}{suffix}"

            new_s3_path = f"s3://{bucket}/{new_key}"

            # 写入临时文件
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='_upload') as tmp:
                tmp.write(content)
                tmp_path = tmp.name

            try:
                # 上传到 S3，附加 billing 标签
                s3_client = boto3.client('s3')
                extra_args: Dict[str, Any] = {}
                if user_id:
                    extra_args["Tagging"] = f"user_id={user_id}&workflow_id={workflow_id}"
                s3_client.upload_file(tmp_path, bucket, new_key,
                                      ExtraArgs=extra_args if extra_args else None)

                size_bytes = len(content.encode('utf-8'))

                log.info(f"✅ Successfully uploaded to {new_s3_path} ({size_bytes} bytes)")

                return {
                    'success': True,
                    'new_s3_path': new_s3_path,
                    'size_bytes': size_bytes,
                }
            finally:
                # 清理临时文件
                if os.path.exists(tmp_path):
                    os.remove(tmp_path)

        except Exception as e:
            log.error(f"Failed to upload file: {e}")
            return {
                'success': False,
                'error': str(e)
            }


class GetWorkflowParamsTool(Tool):
    """
    获取 workflow 的当前参数

    用途：查看用户提供的参数，以便理解上下文
    """

    def __init__(self, context):
        super().__init__(
            name="get_workflow_params",
            description="Get current workflow parameters"
        )
        self.context = context

    def execute(self) -> Dict[str, Any]:
        """
        获取 workflow 参数

        Returns:
            {
                'success': bool,
                'params': dict,
                'invocation_id': int
            }
        """
        try:
            from galaxy.model import WorkflowInvocation

            sa_session = self.context.metadata.get('sa_session')
            if not sa_session:
                return {
                    'success': False,
                    'error': "No database session available"
                }

            invocation = sa_session.query(WorkflowInvocation).get(self.context.invocation_id)
            if not invocation:
                return {
                    'success': False,
                    'error': f"Invocation {self.context.invocation_id} not found"
                }

            # 获取输入参数
            input_params = {}
            if invocation.input_parameters:
                input_params = json.loads(invocation.input_parameters) if isinstance(invocation.input_parameters, str) else invocation.input_parameters

            return {
                'success': True,
                'params': input_params,
                'invocation_id': self.context.invocation_id,
                'workflow_id': self.context.workflow_id,
            }

        except Exception as e:
            log.error(f"Failed to get workflow params: {e}")
            return {
                'success': False,
                'error': str(e)
            }


class InspectTraceTool(Tool):
    """
    检查 Nextflow trace 文件获取任务详情

    用途：查看失败任务的详细信息（退出码、运行时间等）
    """

    def __init__(self, workflow_dir: Path):
        super().__init__(
            name="inspect_trace",
            description="Inspect Nextflow trace file for task details"
        )
        self.workflow_dir = workflow_dir

    def execute(self, task_name: Optional[str] = None) -> Dict[str, Any]:
        """
        检查 trace 文件

        Args:
            task_name: 可选，只查看特定任务

        Returns:
            {
                'success': bool,
                'total_tasks': int,
                'failed_tasks': list,
                'task_details': dict
            }
        """
        try:
            trace_file = self.workflow_dir / 'workflow-trace.txt'

            if not trace_file.exists():
                return {
                    'success': False,
                    'error': "Trace file not found"
                }

            import csv

            failed_tasks = []
            total_tasks = 0

            with open(trace_file, 'r') as f:
                reader = csv.DictReader(f, delimiter='\t')
                for row in reader:
                    total_tasks += 1

                    if row.get('status') == 'FAILED':
                        task_info = {
                            'name': row.get('name'),
                            'exit': row.get('exit'),
                            'status': row.get('status'),
                            'duration': row.get('duration'),
                            'realtime': row.get('realtime'),
                            'hash': row.get('hash'),
                        }

                        # 如果指定了 task_name，只返回匹配的
                        if task_name:
                            if task_name in row.get('name', ''):
                                failed_tasks.append(task_info)
                        else:
                            failed_tasks.append(task_info)

            return {
                'success': True,
                'total_tasks': total_tasks,
                'failed_tasks': failed_tasks,
                'failed_count': len(failed_tasks),
            }

        except Exception as e:
            log.error(f"Failed to inspect trace file: {e}")
            return {
                'success': False,
                'error': str(e)
            }


class ToolKit:
    """
    工具集合管理器

    负责注册和调用所有可用工具
    """

    def __init__(self, app_config, context, workflow_dir: Path):
        self.tools: Dict[str, Tool] = {}

        # 注册所有工具
        self.register_tool(DownloadS3FileTool(app_config))
        self.register_tool(UploadS3FileTool(app_config))
        self.register_tool(GetWorkflowParamsTool(context))
        self.register_tool(InspectTraceTool(workflow_dir))

        log.info(f"ToolKit initialized with {len(self.tools)} tools: {list(self.tools.keys())}")

    def register_tool(self, tool: Tool):
        """注册工具"""
        self.tools[tool.name] = tool
        log.debug(f"Registered tool: {tool.name}")

    def get_tool(self, name: str) -> Optional[Tool]:
        """获取工具"""
        return self.tools.get(name)

    def list_tools(self) -> List[Dict[str, str]]:
        """列出所有工具及其描述"""
        return [
            {
                'name': name,
                'description': tool.description
            }
            for name, tool in self.tools.items()
        ]

    def execute_tool(self, name: str, **kwargs) -> Dict[str, Any]:
        """执行工具"""
        tool = self.get_tool(name)
        if not tool:
            return {
                'success': False,
                'error': f"Tool '{name}' not found"
            }

        try:
            result = tool.execute(**kwargs)
            log.info(f"Tool '{name}' executed: success={result.get('success', False)}")
            return result
        except Exception as e:
            log.error(f"Tool '{name}' execution failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }
