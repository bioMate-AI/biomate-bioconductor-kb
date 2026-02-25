"""
Nextflow Remote Executor

在远程 EC2/服务器上执行 Nextflow 主进程，解决本地网络不稳定问题。
"""

import logging
import os
import subprocess
import time
from pathlib import Path
from typing import Dict, Optional, Any
import re

log = logging.getLogger(__name__)


class NextflowRemoteExecutor:
    """
    远程 Nextflow 执行器

    核心功能：
    1. 通过 SSH 连接到远程服务器（EC2）
    2. 同步必要文件到远程
    3. 在远程启动 nextflow（使用 screen 后台会话）
    4. 异步监控执行状态
    5. 收集执行结果
    """

    def __init__(self, config: Dict[str, Any]):
        """
        初始化远程执行器

        Args:
            config: 远程执行配置
                {
                    'enabled': bool,               # 是否启用远程执行
                    'host': str,                   # 远程主机地址
                    'user': str,                   # SSH 用户名
                    'ssh_key': str,                # SSH 私钥路径
                    'workspace_dir': str,          # 远程工作目录
                    'use_screen': bool,            # 是否使用 screen
                    'nextflow_bin': str,           # 远程 Nextflow 路径（默认 /usr/local/bin/nextflow）
                    'sync_method': str,            # 文件同步方式: 'scp', 'rsync', 's3' (默认 rsync)
                }
        """
        self.config = config
        self.logger = logging.getLogger(__name__)

        self.enabled = config.get('enabled', False)
        if not self.enabled:
            self.logger.info("Remote execution is DISABLED")
            return

        # 验证必需配置
        required_keys = ['host', 'user', 'workspace_dir']
        missing = [k for k in required_keys if not config.get(k)]
        if missing:
            raise ValueError(f"Remote execution config missing: {', '.join(missing)}")

        self.host = config['host']
        self.user = config['user']
        self.ssh_key = config.get('ssh_key', '')
        self.workspace_dir = config['workspace_dir']
        self.use_screen = config.get('use_screen', True)
        self.nextflow_bin = config.get('nextflow_bin', '/usr/local/bin/nextflow')
        self.sync_method = config.get('sync_method', 'rsync')

        # 构建 SSH 基础命令
        self.ssh_base = ['ssh']
        if self.ssh_key:
            self.ssh_base.extend(['-i', self.ssh_key])
        self.ssh_base.extend([
            '-o', 'StrictHostKeyChecking=no',
            '-o', 'UserKnownHostsFile=/dev/null',
            '-o', 'LogLevel=ERROR',
            f'{self.user}@{self.host}'
        ])

        self.logger.info(f"Remote execution ENABLED: {self.user}@{self.host}:{self.workspace_dir}")
        self.logger.info(f"  Sync method: {self.sync_method}")
        self.logger.info(f"  Use screen: {self.use_screen}")

        # 测试连接
        self._test_connection()

    def _test_connection(self):
        """测试 SSH 连接"""
        try:
            result = self._ssh_exec('echo "connection_test_ok"', timeout=10)
            if 'connection_test_ok' in result:
                self.logger.info(f"✅ SSH connection to {self.host} successful")
            else:
                raise Exception("Connection test failed: unexpected output")
        except Exception as e:
            self.logger.error(f"❌ SSH connection to {self.host} failed: {e}")
            raise

    def _ssh_exec(self, command: str, timeout: int = 30) -> str:
        """
        执行 SSH 命令

        Args:
            command: 要执行的命令
            timeout: 超时时间（秒）

        Returns:
            命令输出
        """
        cmd = self.ssh_base + [command]

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=timeout
            )

            if result.returncode != 0:
                self.logger.warning(f"SSH command failed (exit {result.returncode}): {command}")
                self.logger.warning(f"  stderr: {result.stderr}")

            return result.stdout

        except subprocess.TimeoutExpired:
            self.logger.error(f"SSH command timeout after {timeout}s: {command}")
            raise
        except Exception as e:
            self.logger.error(f"SSH command failed: {command}")
            self.logger.error(f"  Error: {e}")
            raise

    def _sync_to_remote(self, local_dir: Path, remote_path: str):
        """
        同步文件到远程

        Args:
            local_dir: 本地目录
            remote_path: 远程路径
        """
        if not local_dir.exists():
            raise FileNotFoundError(f"Local directory not found: {local_dir}")

        # 创建远程目录
        self._ssh_exec(f'mkdir -p {remote_path}')

        if self.sync_method == 'rsync':
            # 使用 rsync（推荐，增量同步，更快）
            cmd = ['rsync', '-avz', '--delete']
            if self.ssh_key:
                cmd.extend(['-e', f'ssh -i {self.ssh_key} -o StrictHostKeyChecking=no'])
            else:
                cmd.extend(['-e', 'ssh -o StrictHostKeyChecking=no'])

            cmd.extend([
                str(local_dir) + '/',  # 注意：末尾 / 表示同步目录内容而不是目录本身
                f'{self.user}@{self.host}:{remote_path}/'
            ])

            self.logger.info(f"Syncing {local_dir} to {self.host}:{remote_path} using rsync...")

        elif self.sync_method == 'scp':
            # 使用 scp（简单但慢）
            cmd = ['scp', '-r']
            if self.ssh_key:
                cmd.extend(['-i', self.ssh_key])
            cmd.extend([
                '-o', 'StrictHostKeyChecking=no',
                str(local_dir) + '/*',
                f'{self.user}@{self.host}:{remote_path}/'
            ])

            self.logger.info(f"Syncing {local_dir} to {self.host}:{remote_path} using scp...")

        elif self.sync_method == 's3':
            # 使用 S3 作为中转（适合大文件）
            # 这里假设远程和本地都能访问 S3
            self.logger.warning("S3 sync method not yet implemented, falling back to rsync")
            return self._sync_to_remote(local_dir, remote_path)

        else:
            raise ValueError(f"Unknown sync method: {self.sync_method}")

        try:
            result = subprocess.run(cmd, capture_output=True, text=True, timeout=300)
            if result.returncode != 0:
                self.logger.error(f"Sync failed: {result.stderr}")
                raise Exception(f"Sync failed: {result.stderr}")

            self.logger.info(f"✅ Sync completed successfully")

        except subprocess.TimeoutExpired:
            self.logger.error("Sync timeout after 5 minutes")
            raise

    def start_workflow(
        self,
        invocation_id: int,
        local_work_dir: Path,
        nextflow_cmd: list
    ) -> Dict[str, Any]:
        """
        在远程启动 Nextflow workflow

        Args:
            invocation_id: Workflow invocation ID
            local_work_dir: 本地工作目录
            nextflow_cmd: Nextflow 命令（列表形式）

        Returns:
            执行信息字典：
            {
                'remote_workspace': str,     # 远程工作目录
                'screen_name': str,          # screen 会话名（如果使用）
                'status': 'running',         # 初始状态
                'pid': int,                  # 远程进程 PID（如果可获取）
            }
        """
        if not self.enabled:
            raise RuntimeError("Remote execution is not enabled")

        self.logger.info(f"[Workflow {invocation_id}] Starting remote execution on {self.host}")

        # 1. 准备远程工作目录
        remote_workspace = f"{self.workspace_dir}/workflow_{invocation_id}"
        self.logger.info(f"[Workflow {invocation_id}] Remote workspace: {remote_workspace}")

        # 2. 同步文件到远程
        self.logger.info(f"[Workflow {invocation_id}] Syncing files to remote...")
        self._sync_to_remote(local_work_dir, remote_workspace)

        # 3. 构建远程执行命令
        # 将命令列表转换为 shell 命令字符串
        cmd_str = ' '.join([f'"{arg}"' if ' ' in str(arg) else str(arg) for arg in nextflow_cmd])

        # 替换本地路径为远程路径
        # 例如：/Users/.../nextflow_workflows/workflow_714 -> /home/ec2-user/nextflow_workspaces/workflow_714
        cmd_str = cmd_str.replace(str(local_work_dir), remote_workspace)

        self.logger.info(f"[Workflow {invocation_id}] Remote command: {cmd_str}")

        # 4. 启动远程执行
        if self.use_screen:
            # 使用 screen 后台会话
            screen_name = f"nf_{invocation_id}"

            # screen 命令：
            # -dmS: 创建 detached 会话并命名
            # bash -c: 在新 shell 中执行命令
            # &> nextflow.out: 重定向所有输出
            # echo $? > exit_code: 保存退出码
            remote_cmd = f"""
                cd {remote_workspace} && \\
                screen -dmS {screen_name} bash -c '
                    {cmd_str} &> nextflow.out
                    echo $? > exit_code
                    date "+%Y-%m-%d %H:%M:%S" > completion_time
                '
            """

            self._ssh_exec(remote_cmd.strip(), timeout=30)

            # 等待一下确保进程启动
            time.sleep(2)

            # 获取 screen 会话信息
            screen_info = self._ssh_exec(f'screen -ls | grep {screen_name}', timeout=10)

            self.logger.info(f"[Workflow {invocation_id}] ✅ Started in screen session: {screen_name}")
            self.logger.debug(f"  Screen info: {screen_info}")

            return {
                'remote_workspace': remote_workspace,
                'screen_name': screen_name,
                'status': 'running',
                'start_time': time.time()
            }

        else:
            # 不使用 screen，直接后台运行（nohup）
            remote_cmd = f"""
                cd {remote_workspace} && \\
                nohup {cmd_str} &> nextflow.out &
                echo $! > nextflow.pid
            """

            self._ssh_exec(remote_cmd.strip(), timeout=30)

            # 获取 PID
            time.sleep(1)
            pid_str = self._ssh_exec(f'cat {remote_workspace}/nextflow.pid', timeout=10).strip()

            try:
                pid = int(pid_str)
            except ValueError:
                pid = None
                self.logger.warning(f"[Workflow {invocation_id}] Could not parse PID: {pid_str}")

            self.logger.info(f"[Workflow {invocation_id}] ✅ Started with PID: {pid}")

            return {
                'remote_workspace': remote_workspace,
                'pid': pid,
                'status': 'running',
                'start_time': time.time()
            }

    def check_status(self, invocation_id: int, exec_info: Dict[str, Any]) -> Dict[str, Any]:
        """
        检查远程 workflow 状态

        Args:
            invocation_id: Workflow invocation ID
            exec_info: start_workflow 返回的执行信息

        Returns:
            状态信息：
            {
                'status': 'running'|'completed'|'failed',
                'progress': str,           # 进度信息（可选）
                'error_message': str,      # 错误信息（如果失败）
                'exit_code': int,          # 退出码（如果完成）
            }
        """
        if not self.enabled:
            raise RuntimeError("Remote execution is not enabled")

        remote_workspace = exec_info['remote_workspace']

        # 检查日志文件
        check_cmd = f"""
            cd {remote_workspace} && {{
                # 检查是否完成
                if [ -f exit_code ]; then
                    echo "EXIT_CODE=$(cat exit_code)"
                    echo "COMPLETION_TIME=$(cat completion_time 2>/dev/null || echo 'unknown')"
                fi

                # 检查 .nextflow.log 最后几行（查找状态关键词）
                if [ -f .nextflow.log ]; then
                    echo "LOG_TAIL_START"
                    tail -50 .nextflow.log | grep -E "completed|failed|ERROR|succeededCount" || echo "no_status_found"
                    echo "LOG_TAIL_END"
                fi

                # 如果使用 screen，检查会话是否还在运行
                if command -v screen &> /dev/null; then
                    echo "SCREEN_CHECK_START"
                    screen -ls | grep "{exec_info.get('screen_name', 'NOT_USING_SCREEN')}" || echo "screen_not_found"
                    echo "SCREEN_CHECK_END"
                fi

                # 如果使用 PID，检查进程是否还在运行
                if [ -f nextflow.pid ]; then
                    PID=$(cat nextflow.pid)
                    if ps -p $PID > /dev/null 2>&1; then
                        echo "PROCESS_RUNNING=yes"
                    else
                        echo "PROCESS_RUNNING=no"
                    fi
                fi
            }}
        """

        output = self._ssh_exec(check_cmd.strip(), timeout=30)

        # 解析输出
        status_info = {
            'status': 'running',  # 默认假设还在运行
            'raw_output': output  # 保留原始输出用于调试
        }

        # 检查是否有退出码
        exit_code_match = re.search(r'EXIT_CODE=(\d+)', output)
        if exit_code_match:
            exit_code = int(exit_code_match.group(1))
            status_info['exit_code'] = exit_code

            if exit_code == 0:
                status_info['status'] = 'completed'
                self.logger.info(f"[Workflow {invocation_id}] ✅ Completed successfully")
            else:
                status_info['status'] = 'failed'
                status_info['error_message'] = f"Nextflow exited with code {exit_code}"
                self.logger.error(f"[Workflow {invocation_id}] ❌ Failed with exit code {exit_code}")

        # 从日志提取进度信息
        if 'LOG_TAIL_START' in output:
            log_section = output.split('LOG_TAIL_START')[1].split('LOG_TAIL_END')[0]

            # 查找关键状态信息
            if 'completed successfully' in log_section.lower():
                status_info['status'] = 'completed'
                status_info['exit_code'] = 0
            elif 'pipeline failed' in log_section.lower() or 'workflow failed' in log_section.lower():
                status_info['status'] = 'failed'
                # 提取错误信息
                error_lines = [line for line in log_section.split('\n') if 'ERROR' in line]
                if error_lines:
                    status_info['error_message'] = '\n'.join(error_lines[:5])  # 只取前5行

            # 提取成功任务数（进度信息）
            succeeded_match = re.search(r'succeededCount[=:](\d+)', log_section)
            if succeeded_match:
                status_info['succeeded_count'] = int(succeeded_match.group(1))

        # 检查进程是否还在运行
        if 'PROCESS_RUNNING=no' in output and status_info.get('exit_code') is None:
            # 进程已结束但没有找到 exit_code 文件 - 可能崩溃了
            status_info['status'] = 'failed'
            status_info['error_message'] = 'Process terminated unexpectedly (no exit code found)'

        return status_info

    def get_logs(self, invocation_id: int, exec_info: Dict[str, Any], lines: int = 100) -> str:
        """
        获取远程执行日志

        Args:
            invocation_id: Workflow invocation ID
            exec_info: 执行信息
            lines: 获取最后多少行（默认 100）

        Returns:
            日志内容
        """
        if not self.enabled:
            raise RuntimeError("Remote execution is not enabled")

        remote_workspace = exec_info['remote_workspace']

        cmd = f"""
            cd {remote_workspace} && {{
                echo "=== nextflow.out (last {lines} lines) ==="
                tail -{lines} nextflow.out 2>/dev/null || echo "File not found"
                echo ""
                echo "=== .nextflow.log (last {lines} lines) ==="
                tail -{lines} .nextflow.log 2>/dev/null || echo "File not found"
            }}
        """

        return self._ssh_exec(cmd.strip(), timeout=60)

    def cleanup(self, invocation_id: int, exec_info: Dict[str, Any], remove_files: bool = False):
        """
        清理远程资源

        Args:
            invocation_id: Workflow invocation ID
            exec_info: 执行信息
            remove_files: 是否删除工作目录（默认 False，只终止进程）
        """
        if not self.enabled:
            return

        self.logger.info(f"[Workflow {invocation_id}] Cleaning up remote resources...")

        remote_workspace = exec_info['remote_workspace']

        # 终止 screen 会话（如果使用）
        if 'screen_name' in exec_info:
            screen_name = exec_info['screen_name']
            self._ssh_exec(f'screen -S {screen_name} -X quit', timeout=10)
            self.logger.info(f"  Terminated screen session: {screen_name}")

        # 终止进程（如果使用 PID）
        if 'pid' in exec_info and exec_info['pid']:
            pid = exec_info['pid']
            self._ssh_exec(f'kill {pid} 2>/dev/null || true', timeout=10)
            self.logger.info(f"  Terminated process: {pid}")

        # 删除工作目录（如果请求）
        if remove_files:
            self._ssh_exec(f'rm -rf {remote_workspace}', timeout=30)
            self.logger.info(f"  Removed workspace: {remote_workspace}")
        else:
            self.logger.info(f"  Workspace preserved: {remote_workspace}")
