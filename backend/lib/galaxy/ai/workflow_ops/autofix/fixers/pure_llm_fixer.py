"""
Pure LLM AutoFixer - 零规则，纯 LLM 驱动

让 LLM 像 Claude 一样自主工作，不依赖任何硬编码规则
"""

import logging
import json
from typing import Dict, List, Any, Optional
from pathlib import Path
from datetime import datetime

log = logging.getLogger(__name__)


class PureLLMAutoFixer:
    """
    纯 LLM 驱动的 AutoFix

    核心理念：
    - 零 if-else 规则
    - 让 LLM 像 Claude 一样自主决策
    - LLM 直接调用工具执行修复
    - 支持多轮迭代和自我纠正
    """

    def __init__(self, llm_client, sa_session, app_config):
        """
        Args:
            llm_client: Anthropic client
            sa_session: SQLAlchemy session
            app_config: Galaxy app config
        """
        self.llm_client = llm_client
        self.sa_session = sa_session
        self.app_config = app_config
        self._pending_updates = {}  # 待应用的参数更新
        self._conversation_history = []  # 对话历史

    def fix_workflow(self, workflow_id: str, error_summary: Optional[str] = None) -> Dict[str, Any]:
        """
        让 LLM 自主修复 workflow

        Args:
            workflow_id: Workflow invocation ID
            error_summary: 可选的错误摘要（如果已有分析结果）

        Returns:
            修复结果，包含：
            - success: bool
            - llm_summary: LLM 的修复报告
            - parameter_changes: 参数修改列表
            - new_workflow_id: 重启后的新 workflow ID（如果有）
            - conversation: 完整对话历史
        """
        log.info(f"[PureLLM] 🤖 开始纯 LLM 驱动的自动修复: workflow {workflow_id}")

        try:
            # 重置状态
            self._pending_updates = {}
            self._conversation_history = []

            # 构建工具定义
            tools = self._build_tools()

            # 构建初始 prompt
            initial_prompt = self._build_initial_prompt(workflow_id, error_summary)

            # 启动 LLM Agent（支持多轮工具调用）
            messages = [{"role": "user", "content": initial_prompt}]
            iteration = 0
            max_iterations = 15  # 允许 LLM 多次尝试

            while iteration < max_iterations:
                iteration += 1
                log.info(f"[PureLLM] 🔄 Iteration {iteration}/{max_iterations}")

                try:
                    # 调用 LLM
                    response = self.llm_client.messages.create(
                        model="claude-sonnet-4-20250514",
                        max_tokens=4096,
                        tools=tools,
                        messages=messages
                    )

                    log.info(f"[PureLLM] LLM 响应 - stop_reason: {response.stop_reason}")

                    # 检查是否完成
                    if response.stop_reason == "end_turn":
                        # LLM 完成工作
                        log.info(f"[PureLLM] ✅ LLM 完成工作")
                        return self._extract_final_result(response, messages)

                    # 执行工具调用
                    if response.stop_reason == "tool_use":
                        log.info(f"[PureLLM] 🔧 LLM 正在调用工具")
                        messages = self._execute_tools(response, messages)
                        # 继续下一轮
                        continue

                    # 其他情况
                    log.warning(f"[PureLLM] ⚠️ Unexpected stop_reason: {response.stop_reason}")
                    break

                except Exception as e:
                    log.error(f"[PureLLM] ❌ LLM 调用失败: {e}", exc_info=True)
                    return {
                        "success": False,
                        "error": f"LLM 调用失败: {str(e)}",
                        "iteration": iteration
                    }

            log.warning(f"[PureLLM] ⏱️ 达到最大迭代次数 {max_iterations}")
            return {
                "success": False,
                "error": "max_iterations_reached",
                "llm_summary": "LLM 达到最大迭代次数，但未完成修复",
                "conversation": messages
            }

        except Exception as e:
            log.error(f"[PureLLM] ❌ AutoFix 失败: {e}", exc_info=True)
            return {
                "success": False,
                "error": str(e)
            }

    def _build_initial_prompt(self, workflow_id: str, error_summary: Optional[str] = None) -> str:
        """构建给 LLM 的初始 prompt"""

        error_context = ""
        if error_summary:
            error_context = f"""
初步错误信息：
{error_summary}
"""

        return f"""你是一个 Nextflow Workflow 修复专家。

用户的 Workflow {workflow_id} 运行失败了。

{error_context}

**你的任务**：
1. 读取 workflow 的错误日志和配置
2. 分析失败的根本原因
3. 决定修复方案
4. 执行修复（更新参数）
5. 重启 workflow
6. 验证修复是否成功

**工作方式**：
- 像 Claude 帮用户调试代码一样工作
- 你可以多次调用工具，逐步诊断问题
- 如果一个方案不行，可以尝试其他方案
- 最后给出详细的修复报告

**可用工具**：
- read_workflow_logs: 读取日志、配置、trace 等文件
- update_parameter: 更新 workflow 参数
- restart_workflow: 重启 workflow
- verify_fix: 验证修复结果

**重要提示**：
- 先调用 read_workflow_logs 读取 error_log，看具体错误
- 常见问题：内存不足、CPU不足、参数缺失、文件路径错误
- 内存/CPU 不足：调整 max_memory、max_cpus
- 参数缺失：检查 schema，补充必需参数
- 文件路径错误：检查 fasta、gtf 等文件路径是否正确

**开始工作吧！**
"""

    def _build_tools(self) -> List[Dict]:
        """构建工具定义"""
        return [
            {
                "name": "read_workflow_logs",
                "description": """读取 workflow 的各种文件。

支持的文件类型：
- error_log: nextflow.out（错误日志）
- config: nextflow.config（配置文件）
- trace: workflow-trace.txt（任务执行追踪）
- parameters: 用户提供的参数
""",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "workflow_id": {
                            "type": "string",
                            "description": "Workflow invocation ID"
                        },
                        "file_type": {
                            "type": "string",
                            "enum": ["error_log", "config", "trace", "parameters"],
                            "description": "要读取的文件类型"
                        },
                        "max_lines": {
                            "type": "integer",
                            "description": "最多读取多少行（可选，默认 500）"
                        }
                    },
                    "required": ["workflow_id", "file_type"]
                }
            },
            {
                "name": "update_parameter",
                "description": """更新 workflow 的参数。

注意：
- 参数名要准确（如 max_memory, max_cpus）
- 值的格式要正确（如 '64.GB', '8'）
- 可以多次调用以更新多个参数
- 参数会在 restart_workflow 时应用
""",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "workflow_id": {
                            "type": "string",
                            "description": "Workflow invocation ID"
                        },
                        "parameter_name": {
                            "type": "string",
                            "description": "参数名（如 max_memory, max_cpus）"
                        },
                        "new_value": {
                            "type": "string",
                            "description": "新值（如 '64.GB', '8'）"
                        },
                        "reason": {
                            "type": "string",
                            "description": "修改原因（给用户看的）"
                        }
                    },
                    "required": ["workflow_id", "parameter_name", "new_value", "reason"]
                }
            },
            {
                "name": "restart_workflow",
                "description": """用修复后的参数重启 workflow。

这会：
1. 使用更新后的参数创建新的 workflow invocation
2. 返回新的 workflow ID
3. 原 workflow 保持失败状态（用于对比）
""",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "workflow_id": {
                            "type": "string",
                            "description": "原 workflow ID"
                        },
                        "summary": {
                            "type": "string",
                            "description": "修复摘要（给用户看的）"
                        }
                    },
                    "required": ["workflow_id", "summary"]
                }
            },
            {
                "name": "verify_fix",
                "description": """验证修复是否成功。

这会检查：
1. 新 workflow 是否正在运行
2. 是否出现新的错误
3. 任务完成进度
""",
                "input_schema": {
                    "type": "object",
                    "properties": {
                        "new_workflow_id": {
                            "type": "string",
                            "description": "重启后的新 workflow ID"
                        }
                    },
                    "required": ["new_workflow_id"]
                }
            }
        ]

    def _execute_tools(self, response, messages: List[Dict]) -> List[Dict]:
        """执行 LLM 调用的工具"""

        # 将 LLM 的响应添加到消息历史
        assistant_message = {
            "role": "assistant",
            "content": response.content
        }
        messages.append(assistant_message)

        # 执行所有工具调用
        tool_results = []
        for content_block in response.content:
            if content_block.type == "tool_use":
                tool_name = content_block.name
                tool_input = content_block.input

                log.info(f"[PureLLM] 🔧 执行工具: {tool_name}")
                log.debug(f"[PureLLM] 工具输入: {json.dumps(tool_input, ensure_ascii=False)}")

                # 执行工具
                try:
                    result = self._execute_single_tool(tool_name, tool_input)
                    log.debug(f"[PureLLM] 工具结果: {str(result)[:200]}...")
                except Exception as e:
                    log.error(f"[PureLLM] ❌ 工具执行失败: {e}", exc_info=True)
                    result = {"error": str(e)}

                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": content_block.id,
                    "content": str(result)
                })

        # 将工具结果添加到消息历史
        messages.append({
            "role": "user",
            "content": tool_results
        })

        return messages

    def _execute_single_tool(self, tool_name: str, tool_input: Dict) -> Any:
        """执行单个工具"""

        if tool_name == "read_workflow_logs":
            return self._read_workflow_logs(
                tool_input['workflow_id'],
                tool_input['file_type'],
                tool_input.get('max_lines', 500)
            )

        elif tool_name == "update_parameter":
            return self._update_parameter(
                tool_input['workflow_id'],
                tool_input['parameter_name'],
                tool_input['new_value'],
                tool_input['reason']
            )

        elif tool_name == "restart_workflow":
            return self._restart_workflow(
                tool_input['workflow_id'],
                tool_input['summary']
            )

        elif tool_name == "verify_fix":
            return self._verify_fix(
                tool_input['new_workflow_id']
            )

        else:
            return {"error": f"Unknown tool: {tool_name}"}

    def _read_workflow_logs(self, workflow_id: str, file_type: str, max_lines: int) -> str:
        """读取 workflow 文件"""
        try:
            workflow_dir = Path(self.app_config.jobs_directory) / f"nextflow_workflows/workflow_{workflow_id}"

            if file_type == "error_log":
                file_path = workflow_dir / "nextflow.out"
            elif file_type == "config":
                file_path = workflow_dir / "nextflow.config"
            elif file_type == "trace":
                file_path = workflow_dir / "workflow-trace.txt"
            elif file_type == "parameters":
                # 从数据库读取参数
                invocation = self._get_invocation(workflow_id)
                if invocation:
                    params = json.dumps(invocation.input_parameters or {}, ensure_ascii=False, indent=2)
                    return f"用户提供的参数：\n{params}"
                else:
                    return "错误：找不到 workflow invocation"
            else:
                return f"错误：不支持的文件类型 {file_type}"

            if not file_path.exists():
                return f"文件不存在: {file_path}"

            # 读取文件（最后 N 行）
            with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
                lines = f.readlines()
                if len(lines) > max_lines:
                    lines = lines[-max_lines:]
                return ''.join(lines)

        except Exception as e:
            log.error(f"[PureLLM] 读取文件失败: {e}", exc_info=True)
            return f"读取文件失败: {str(e)}"

    def _update_parameter(self, workflow_id: str, param_name: str, new_value: str, reason: str) -> Dict:
        """更新参数（暂存，在 restart_workflow 时应用）"""
        log.info(f"[PureLLM] 📝 标记参数更新: {param_name} = {new_value}")

        self._pending_updates[param_name] = {
            'value': new_value,
            'reason': reason,
            'timestamp': datetime.now().isoformat()
        }

        return {
            "success": True,
            "message": f"参数 {param_name} 已标记为更新到 {new_value}",
            "note": "参数将在 restart_workflow 时应用",
            "pending_updates_count": len(self._pending_updates)
        }

    def _restart_workflow(self, workflow_id: str, summary: str) -> Dict:
        """重启 workflow"""
        try:
            log.info(f"[PureLLM] 🔄 重启 workflow {workflow_id}")

            # 获取原 invocation
            invocation = self._get_invocation(workflow_id)
            if not invocation:
                return {"error": f"找不到 workflow {workflow_id}"}

            # 合并参数更新
            new_params = (invocation.input_parameters or {}).copy()
            changes = []

            if self._pending_updates:
                log.info(f"[PureLLM] 应用 {len(self._pending_updates)} 个参数更新")
                for param_name, update in self._pending_updates.items():
                    old_value = new_params.get(param_name, '(未设置)')
                    new_params[param_name] = update['value']
                    changes.append({
                        'parameter': param_name,
                        'old_value': old_value,
                        'new_value': update['value'],
                        'reason': update['reason']
                    })
                    log.info(f"[PureLLM]   {param_name}: {old_value} → {update['value']}")

            # 创建新的 invocation
            new_invocation_id = self._create_new_invocation(
                workflow=invocation.workflow,
                params=new_params,
                history_id=invocation.history_id
            )

            if not new_invocation_id:
                return {"error": "创建新 invocation 失败"}

            log.info(f"[PureLLM] ✅ Workflow 重启成功，新 ID: {new_invocation_id}")

            return {
                "success": True,
                "new_workflow_id": new_invocation_id,
                "message": f"Workflow 已重启，新 ID: {new_invocation_id}",
                "parameter_changes": changes,
                "summary": summary
            }

        except Exception as e:
            log.error(f"[PureLLM] 重启 workflow 失败: {e}", exc_info=True)
            return {"error": f"重启失败: {str(e)}"}

    def _verify_fix(self, new_workflow_id: str) -> Dict:
        """验证修复结果"""
        try:
            log.info(f"[PureLLM] 🔍 验证修复结果: workflow {new_workflow_id}")

            invocation = self._get_invocation(new_workflow_id)
            if not invocation:
                return {"error": f"找不到 workflow {new_workflow_id}"}

            # 检查状态
            state = invocation.state

            # 读取最新的错误日志（如果有）
            workflow_dir = Path(self.app_config.jobs_directory) / f"nextflow_workflows/workflow_{new_workflow_id}"
            error_log_path = workflow_dir / "nextflow.out"

            recent_errors = []
            if error_log_path.exists():
                with open(error_log_path, 'r', encoding='utf-8', errors='ignore') as f:
                    lines = f.readlines()
                    # 查找最近的错误
                    for line in lines[-50:]:  # 检查最后 50 行
                        if 'ERROR' in line or 'FATAL' in line or 'Failed' in line:
                            recent_errors.append(line.strip())

            return {
                "status": state,
                "has_errors": bool(recent_errors),
                "recent_errors": recent_errors[:5],  # 最多返回 5 个错误
                "message": f"Workflow 状态: {state}"
            }

        except Exception as e:
            log.error(f"[PureLLM] 验证失败: {e}", exc_info=True)
            return {"error": f"验证失败: {str(e)}"}

    def _extract_final_result(self, response, messages: List[Dict]) -> Dict:
        """提取 LLM 的最终结果"""
        # 提取 LLM 的最后一段文本内容
        final_text = ""
        for content_block in response.content:
            if content_block.type == "text":
                final_text += content_block.text

        log.info(f"[PureLLM] 📋 LLM 最终报告:\n{final_text}")

        # 提取参数修改
        parameter_changes = []
        for param_name, update in self._pending_updates.items():
            parameter_changes.append({
                'parameter': param_name,
                'new_value': update['value'],
                'reason': update['reason']
            })

        return {
            "success": True,
            "llm_summary": final_text,
            "parameter_changes": parameter_changes,
            "conversation": messages,
            "fixer_type": "PureLLMAutoFixer"
        }

    def _get_invocation(self, workflow_id: str):
        """获取 workflow invocation"""
        from galaxy.model import WorkflowInvocation

        try:
            invocation = (
                self.sa_session.query(WorkflowInvocation)
                .filter(WorkflowInvocation.id == workflow_id)
                .first()
            )
            return invocation
        except Exception as e:
            log.error(f"[PureLLM] 查询 invocation 失败: {e}", exc_info=True)
            return None

    def _create_new_invocation(self, workflow, params: Dict, history_id: str) -> Optional[str]:
        """创建新的 workflow invocation"""
        # TODO: 实现实际的 workflow 重启逻辑
        # 这里需要调用 Galaxy 的 workflow invocation API

        log.warning(f"[PureLLM] _create_new_invocation 尚未完全实现")

        # 临时返回：记录参数但不实际创建
        log.info(f"[PureLLM] 将创建新 invocation，参数: {json.dumps(params, ensure_ascii=False)}")

        # 实际实现应该调用类似这样的代码：
        # from galaxy.managers.workflows import WorkflowsManager
        # workflow_manager = WorkflowsManager(app)
        # new_invocation = workflow_manager.invoke(
        #     workflow=workflow,
        #     history=history,
        #     inputs=params
        # )
        # return new_invocation.id

        return None  # 返回 None 表示未实现
