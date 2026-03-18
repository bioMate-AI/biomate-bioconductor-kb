"""
AutoFix 3.0 - Enhanced Tool System

新增工具，让 AutoFix 能够像 Claude 一样：
- 读取本地文件（代码、日志、配置）
- 修改文件（修复 Bug）
- 运行调试命令
- 搜索文件和代码

目标：帮助用户成功运行 workflow，0 人工干预

作者：AI Workflow AutoFix Team
日期：2026-01-31
"""

import logging
import os
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Any, Dict, List, Optional

log = logging.getLogger(__name__)


# ========== 基础工具类 ==========

class Tool:
    """工具基类"""

    def __init__(self, name: str, description: str):
        self.name = name
        self.description = description

    def execute(self, **kwargs) -> Dict[str, Any]:
        """执行工具，返回结果"""
        raise NotImplementedError


# ========== Critical Tools（核心工具）==========

class ReadFileTool(Tool):
    """
    读取本地文件

    用途：
    - 查看 Nextflow 脚本 (main.nf)
    - 查看 Python 脚本 (bin/*.py)
    - 查看配置文件 (nextflow.config)
    - 查看完整日志 (nextflow.out)

    安全机制：
    - 只允许访问 workflow 目录和 Galaxy 代码目录
    - 禁止读取敏感文件 (.env, credentials)
    """

    def __init__(self, workflow_dir: Path, galaxy_root: Optional[Path] = None):
        super().__init__(
            name="read_file",
            description="Read content of a local file (code, config, logs, scripts)"
        )
        self.workflow_dir = workflow_dir
        self.galaxy_root = galaxy_root or Path('/Users/renyuankai/work/biometa/galaxy')

        # 敏感文件黑名单
        self.blacklist_patterns = [
            '.env', 'credentials', 'secrets', '.ssh', '.aws/credentials',
            'id_rsa', 'api_key', 'password', '.git/config'
        ]

    def execute(
        self,
        file_path: str,
        offset: int = 0,
        limit: int = 2000
    ) -> Dict[str, Any]:
        """
        读取文件

        Args:
            file_path: 文件路径（相对于 workflow_dir 或绝对路径）
            offset: 起始行号（0-based）
            limit: 最多读取行数（默认 2000 行）

        Returns:
            {
                'success': bool,
                'content': str,
                'lines': int,
                'displayed_lines': int,
                'file_path': str,
                'error': str  # 如果失败
            }
        """
        try:
            # 解析路径
            abs_path = Path(file_path)
            if not abs_path.is_absolute():
                abs_path = self.workflow_dir / file_path

            # 安全检查 1: 路径白名单
            allowed_dirs = [self.workflow_dir, self.galaxy_root]
            is_allowed = False

            for allowed_dir in allowed_dirs:
                try:
                    abs_path.relative_to(allowed_dir)
                    is_allowed = True
                    break
                except ValueError:
                    continue

            if not is_allowed:
                return {
                    'success': False,
                    'error': f"Access denied: {file_path} is outside allowed directories"
                }

            # 安全检查 2: 敏感文件黑名单
            path_str = str(abs_path).lower()
            for pattern in self.blacklist_patterns:
                if pattern in path_str:
                    return {
                        'success': False,
                        'error': f"Access denied: Cannot read sensitive file containing '{pattern}'"
                    }

            # 检查文件是否存在
            if not abs_path.exists():
                return {
                    'success': False,
                    'error': f"File not found: {file_path}"
                }

            # 检查是否是文件（不是目录）
            if abs_path.is_dir():
                return {
                    'success': False,
                    'error': f"Path is a directory, not a file: {file_path}"
                }

            # 读取文件
            with open(abs_path, 'r', encoding='utf-8', errors='replace') as f:
                lines = f.readlines()

            # 分页读取
            total_lines = len(lines)
            content_lines = lines[offset:offset + limit]
            content = ''.join(content_lines)

            log.info(f"✅ Read file: {abs_path} ({len(content_lines)}/{total_lines} lines)")

            return {
                'success': True,
                'content': content,
                'lines': total_lines,
                'displayed_lines': len(content_lines),
                'offset': offset,
                'file_path': str(abs_path),
                'is_truncated': (offset + limit) < total_lines
            }

        except UnicodeDecodeError:
            return {
                'success': False,
                'error': f"File is binary or has encoding issues: {file_path}"
            }
        except PermissionError:
            return {
                'success': False,
                'error': f"Permission denied: {file_path}"
            }
        except Exception as e:
            log.error(f"Failed to read file {file_path}: {e}")
            return {
                'success': False,
                'error': str(e)
            }


class EditFileTool(Tool):
    """
    修改本地文件（精确字符串替换）

    用途：
    - 修复 Python 脚本中的 Bug
    - 更新 Nextflow 配置
    - 修改依赖文件（requirements.txt）

    安全机制：
    - 必须精确匹配 old_string（防止误改）
    - 自动备份原文件
    - 限制修改范围（只能修改 workflow 目录）
    """

    def __init__(self, workflow_dir: Path):
        super().__init__(
            name="edit_file",
            description="Edit a file by replacing exact string matches (for bug fixes, config updates)"
        )
        self.workflow_dir = workflow_dir

    def execute(
        self,
        file_path: str,
        old_string: str,
        new_string: str,
        replace_all: bool = False
    ) -> Dict[str, Any]:
        """
        编辑文件

        Args:
            file_path: 文件路径
            old_string: 要替换的字符串（必须精确匹配）
            new_string: 新字符串
            replace_all: 是否替换所有出现（默认只替换第一个）

        Returns:
            {
                'success': bool,
                'replacements': int,
                'file_path': str,
                'backup_path': str,  # 备份文件路径
                'error': str
            }
        """
        try:
            # 解析路径
            abs_path = Path(file_path)
            if not abs_path.is_absolute():
                abs_path = self.workflow_dir / file_path

            # 安全检查：只允许修改 workflow 目录
            try:
                abs_path.relative_to(self.workflow_dir)
            except ValueError:
                return {
                    'success': False,
                    'error': f"Access denied: Can only edit files in workflow directory"
                }

            # 检查文件是否存在
            if not abs_path.exists():
                return {
                    'success': False,
                    'error': f"File not found: {file_path}"
                }

            # 读取原始内容
            with open(abs_path, 'r', encoding='utf-8') as f:
                original_content = f.read()

            # 检查 old_string 是否存在
            if old_string not in original_content:
                return {
                    'success': False,
                    'error': f"String not found in file. Expected:\n{old_string[:200]}..."
                }

            # 创建备份
            backup_path = abs_path.with_suffix(abs_path.suffix + '.autofix_backup')
            with open(backup_path, 'w', encoding='utf-8') as f:
                f.write(original_content)

            # 执行替换
            if replace_all:
                new_content = original_content.replace(old_string, new_string)
                count = original_content.count(old_string)
            else:
                new_content = original_content.replace(old_string, new_string, 1)
                count = 1

            # 写回文件
            with open(abs_path, 'w', encoding='utf-8') as f:
                f.write(new_content)

            log.info(f"✅ Edited file: {abs_path} ({count} replacement(s), backup: {backup_path})")

            return {
                'success': True,
                'replacements': count,
                'file_path': str(abs_path),
                'backup_path': str(backup_path),
                'old_string_preview': old_string[:100],
                'new_string_preview': new_string[:100]
            }

        except Exception as e:
            log.error(f"Failed to edit file {file_path}: {e}")
            return {
                'success': False,
                'error': str(e)
            }


class BashTool(Tool):
    """
    运行安全的 Bash 命令

    用途：
    - 调试：python script.py --help
    - 测试：python -c "import pandas"
    - 验证：ls -lh data/input.fastq.gz
    - 检查：aws s3 ls s3://bucket/

    安全机制：
    - 命令白名单（只允许安全的只读命令）
    - 禁止危险操作（rm、dd、管道符、重定向）
    - 超时保护（默认 30 秒）
    """

    def __init__(self, workflow_dir: Path):
        super().__init__(
            name="bash",
            description="Execute safe bash commands for debugging, testing, and validation"
        )
        self.workflow_dir = workflow_dir

        # 命令白名单（只允许这些命令）
        self.safe_commands = {
            # 文件查看
            'ls', 'cat', 'head', 'tail', 'wc', 'file', 'stat',
            # 搜索
            'grep', 'find', 'which',
            # 系统信息
            'echo', 'pwd', 'date', 'whoami', 'hostname',
            # Python
            'python', 'python3', 'pip', 'pip3',
            # 工具
            'aws', 'git', 'docker', 'nextflow',
            'curl', 'wget',
            # 测试
            'test', 'true', 'false'
        }

        # 危险操作模式（禁止）
        self.dangerous_patterns = [
            'rm ', 'rm\t', 'rmdir',  # 删除
            'mv ', 'dd ',  # 移动/写入
            '> ', '>>', '2>', '&>',  # 重定向
            '|', ';', '&&', '||',  # 管道和命令链
            'chmod', 'chown',  # 权限修改
            'kill', 'killall', 'pkill',  # 进程管理
            'sudo', 'su ',  # 权限提升
            'export ', 'unset ',  # 环境变量
            '$(', '`',  # 命令替换
        ]

    def execute(
        self,
        command: str,
        timeout: int = 30,
        allow_failure: bool = True
    ) -> Dict[str, Any]:
        """
        执行 Bash 命令

        Args:
            command: 要执行的命令
            timeout: 超时时间（秒），默认 30 秒
            allow_failure: 是否允许命令失败（默认 True）

        Returns:
            {
                'success': bool,
                'stdout': str,
                'stderr': str,
                'exit_code': int,
                'command': str,
                'error': str
            }
        """
        try:
            # 安全检查 1: 提取基础命令
            tokens = command.split()
            if not tokens:
                return {
                    'success': False,
                    'error': "Empty command"
                }

            # 提取命令名（去除路径）
            base_cmd = tokens[0].split('/')[-1]

            # 安全检查 2: 命令白名单
            if base_cmd not in self.safe_commands:
                return {
                    'success': False,
                    'error': f"Command '{base_cmd}' not in whitelist. Allowed: {', '.join(sorted(self.safe_commands))}"
                }

            # 安全检查 3: 禁止危险操作
            for pattern in self.dangerous_patterns:
                if pattern in command:
                    return {
                        'success': False,
                        'error': f"Dangerous operation detected: '{pattern}' is not allowed"
                    }

            # 执行命令
            log.info(f"🔧 Executing command: {command}")

            result = subprocess.run(
                command,
                shell=True,
                cwd=str(self.workflow_dir),
                capture_output=True,
                text=True,
                timeout=timeout,
                env={**os.environ}  # 继承环境变量
            )

            success = (result.returncode == 0) or allow_failure

            if success:
                log.info(f"✅ Command completed: exit_code={result.returncode}")
            else:
                log.warning(f"⚠️ Command failed: exit_code={result.returncode}")

            return {
                'success': success,
                'stdout': result.stdout,
                'stderr': result.stderr,
                'exit_code': result.returncode,
                'command': command
            }

        except subprocess.TimeoutExpired:
            log.error(f"Command timed out after {timeout} seconds")
            return {
                'success': False,
                'error': f"Command timed out after {timeout} seconds",
                'command': command
            }
        except Exception as e:
            log.error(f"Failed to execute command: {e}")
            return {
                'success': False,
                'error': str(e),
                'command': command
            }


# ========== Search Tools（搜索工具）==========

class GlobTool(Tool):
    """
    搜索文件（glob 模式）

    用途：
    - 查找 Python 脚本：*.py
    - 查找配置文件：*.config
    - 查找日志：*.log, *.out
    """

    def __init__(self, workflow_dir: Path):
        super().__init__(
            name="glob",
            description="Search for files using glob patterns (e.g., '*.py', 'bin/**/*.sh')"
        )
        self.workflow_dir = workflow_dir

    def execute(
        self,
        pattern: str,
        path: Optional[str] = None,
        max_results: int = 100
    ) -> Dict[str, Any]:
        """
        搜索文件

        Args:
            pattern: glob 模式 (e.g., "*.py", "bin/**/*.sh")
            path: 搜索路径（默认为 workflow_dir）
            max_results: 最多返回结果数（默认 100）

        Returns:
            {
                'success': bool,
                'files': List[str],
                'count': int,
                'pattern': str,
                'truncated': bool
            }
        """
        try:
            search_path = Path(path) if path else self.workflow_dir

            # 执行搜索
            matches = list(search_path.glob(pattern))

            # 限制结果数量
            truncated = len(matches) > max_results
            files = [str(f) for f in matches[:max_results]]

            log.info(f"🔍 Found {len(matches)} files matching '{pattern}' (showing {len(files)})")

            return {
                'success': True,
                'files': files,
                'count': len(matches),
                'pattern': pattern,
                'truncated': truncated
            }

        except Exception as e:
            log.error(f"Failed to search files: {e}")
            return {
                'success': False,
                'error': str(e)
            }


class GrepTool(Tool):
    """
    搜索文件内容（grep）

    用途：
    - 查找错误关键词：grep "ImportError" bin/*.py
    - 查找配置项：grep "max_memory" *.config
    """

    def __init__(self, workflow_dir: Path):
        super().__init__(
            name="grep",
            description="Search file contents using regex patterns"
        )
        self.workflow_dir = workflow_dir

    def execute(
        self,
        pattern: str,
        path: Optional[str] = None,
        file_pattern: str = "*",
        max_results: int = 50,
        context_lines: int = 0
    ) -> Dict[str, Any]:
        """
        搜索文件内容

        Args:
            pattern: 正则表达式或字符串
            path: 搜索路径（默认为 workflow_dir）
            file_pattern: 文件过滤 (e.g., "*.py")
            max_results: 最多返回结果数
            context_lines: 显示上下文行数（-C 参数）

        Returns:
            {
                'success': bool,
                'matches': List[{
                    'file': str,
                    'line_number': int,
                    'line': str
                }],
                'count': int
            }
        """
        try:
            search_path = Path(path) if path else self.workflow_dir

            # 构建 grep 命令
            context_flag = f"-C {context_lines}" if context_lines > 0 else ""
            cmd = f"grep -rn {context_flag} -E '{pattern}' --include='{file_pattern}' {search_path} 2>/dev/null"

            # 执行搜索
            result = subprocess.run(
                cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=10
            )

            # 解析输出
            matches = []
            for line in result.stdout.split('\n')[:max_results]:
                if ':' in line:
                    parts = line.split(':', 2)
                    if len(parts) >= 3:
                        matches.append({
                            'file': parts[0],
                            'line_number': parts[1],
                            'line': parts[2]
                        })

            log.info(f"🔍 Found {len(matches)} matches for pattern '{pattern}'")

            return {
                'success': True,
                'matches': matches,
                'count': len(matches),
                'pattern': pattern
            }

        except Exception as e:
            log.error(f"Failed to grep: {e}")
            return {
                'success': False,
                'error': str(e)
            }


# ========== Additional Tools（辅助工具）==========

class WriteTool(Tool):
    """
    创建新文件

    用途：
    - 生成修复脚本
    - 创建配置文件
    - 生成测试数据
    """

    def __init__(self, workflow_dir: Path):
        super().__init__(
            name="write_file",
            description="Create a new file with given content"
        )
        self.workflow_dir = workflow_dir

    def execute(
        self,
        file_path: str,
        content: str
    ) -> Dict[str, Any]:
        """
        创建新文件

        Args:
            file_path: 文件路径
            content: 文件内容

        Returns:
            {
                'success': bool,
                'file_path': str,
                'size_bytes': int
            }
        """
        try:
            abs_path = Path(file_path)
            if not abs_path.is_absolute():
                abs_path = self.workflow_dir / file_path

            # 安全检查
            try:
                abs_path.relative_to(self.workflow_dir)
            except ValueError:
                return {
                    'success': False,
                    'error': "Can only create files in workflow directory"
                }

            # 创建父目录
            abs_path.parent.mkdir(parents=True, exist_ok=True)

            # 写入文件
            with open(abs_path, 'w', encoding='utf-8') as f:
                f.write(content)

            size_bytes = len(content.encode('utf-8'))

            log.info(f"✅ Created file: {abs_path} ({size_bytes} bytes)")

            return {
                'success': True,
                'file_path': str(abs_path),
                'size_bytes': size_bytes
            }

        except Exception as e:
            log.error(f"Failed to create file: {e}")
            return {
                'success': False,
                'error': str(e)
            }


# ========== Enhanced ToolKit（增强的工具集）==========

class EnhancedToolKit:
    """
    增强的工具集合管理器

    包含所有 AutoFix 2.0 工具 + AutoFix 3.0 新增工具
    """

    def __init__(self, app_config, context, workflow_dir: Path):
        self.tools: Dict[str, Tool] = {}
        self.workflow_dir = workflow_dir

        # 从 AutoFix 2.0 导入现有工具
        try:
            from .toolkit import (
                DownloadS3FileTool,
                UploadS3FileTool,
                GetWorkflowParamsTool,
                InspectTraceTool
            )

            # 注册 AutoFix 2.0 工具
            self.register_tool(DownloadS3FileTool(app_config))
            self.register_tool(UploadS3FileTool(app_config))
            self.register_tool(GetWorkflowParamsTool(context))
            self.register_tool(InspectTraceTool(workflow_dir))

        except ImportError as e:
            log.warning(f"Failed to import AutoFix 2.0 tools: {e}")

        # 注册 AutoFix 3.0 新增工具
        self.register_tool(ReadFileTool(workflow_dir))
        self.register_tool(EditFileTool(workflow_dir))
        self.register_tool(BashTool(workflow_dir))
        self.register_tool(GlobTool(workflow_dir))
        self.register_tool(GrepTool(workflow_dir))
        self.register_tool(WriteTool(workflow_dir))

        log.info(f"🛠️  EnhancedToolKit initialized with {len(self.tools)} tools: {list(self.tools.keys())}")

    def register_tool(self, tool: Tool):
        """注册工具"""
        self.tools[tool.name] = tool
        log.debug(f"  ✅ Registered: {tool.name} - {tool.description}")

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
                'error': f"Tool '{name}' not found. Available: {', '.join(self.tools.keys())}"
            }

        try:
            result = tool.execute(**kwargs)
            log.info(f"🔧 Tool '{name}' executed: success={result.get('success', False)}")
            return result
        except Exception as e:
            log.error(f"Tool '{name}' execution failed: {e}")
            return {
                'success': False,
                'error': str(e)
            }
