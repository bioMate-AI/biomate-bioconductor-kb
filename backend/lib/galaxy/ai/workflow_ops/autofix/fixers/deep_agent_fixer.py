"""
Deep Agent Fixer - 基于 Deep Agent 的智能修复器

集成 Deep Agent 的强大诊断能力到 AutoFix 系统，
提供更准确的根因分析和更智能的修复方案。

优势:
1. 使用 Deep Agent 的专业诊断模型
2. 提供详细的"为什么错过"分析
3. 生成预防策略
4. 更高的诊断准确度
"""

import logging
import json
import sys
from pathlib import Path
from typing import Dict, List, Any, Optional

from ..base import (
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
    AutoFixResult,
)
from ...types import FixAction, ActionType, FixPlan, FixType

log = logging.getLogger(__name__)

# External Deep Agent project path. Configurable via env var.
# When unset (the default in BioMate), this fixer self-disables silently — the
# autofix3 path (DeepAnalysisAgent from agent.py) already provides the same
# capability in-process and is the preferred way to invoke Deep Agent here.
import os
DEEP_AGENT_PATH = Path(os.getenv("BIOMATE_AUTOTEST_AGENT_PATH", ""))


class DeepAgentFixer(BaseAutoFixer):
    """
    基于 Deep Agent 的智能修复器

    工作流程:
    1. 提取 workflow 错误日志和上下文
    2. 调用 Deep Agent 进行深度诊断
    3. 解析 Deep Agent 的诊断结果
    4. 将诊断转换为可执行的修复操作
    5. 生成修复计划

    Deep Agent 提供:
    - root_cause: 根本原因（比规则匹配更准确）
    - why_missed: 为什么之前的检测没发现
    - recommended_fix: 具体修复建议
    - prevention_strategy: 预防策略
    - confidence: 置信度评分
    """

    name = "DeepAgentFixer"
    description = "集成 Deep Agent 专业诊断能力的智能修复器，提供更准确的根因分析"

    def __init__(self):
        """初始化 Deep Agent Fixer"""
        super().__init__()
        self.deep_agent_available = False
        self.llm_client = None

        # If the external auto-test-agent project path is not configured, stay
        # silently disabled. BioMate prefers autofix3 (in-process DeepAnalysisAgent).
        if not str(DEEP_AGENT_PATH) or not DEEP_AGENT_PATH.exists():
            log.debug("DeepAgentFixer disabled (BIOMATE_AUTOTEST_AGENT_PATH not set)")
            return

        # 尝试导入 Deep Agent
        try:
            # 添加 Deep Agent 到 Python 路径
            if str(DEEP_AGENT_PATH / "src") not in sys.path:
                sys.path.insert(0, str(DEEP_AGENT_PATH / "src"))

            from core.llm_client import LLMClient

            # 获取 API key
            import os
            api_key = os.getenv('ANTHROPIC_API_KEY')
            if not api_key:
                raise ValueError("ANTHROPIC_API_KEY not set")

            # 创建 LLM 客户端（使用最新的 Claude Sonnet 4 模型）
            self.llm_client = LLMClient(
                api_key=api_key,
                model="claude-sonnet-4-20250514"
            )

            self.deep_agent_available = True
            log.info("✅ Deep Agent Fixer initialized successfully")

        except ImportError as e:
            log.warning(f"⚠️  Deep Agent not available: {e}")
            log.warning(f"   Deep Agent path: {DEEP_AGENT_PATH}")
            self.deep_agent_available = False
        except Exception as e:
            log.error(f"❌ Failed to initialize Deep Agent: {e}")
            self.deep_agent_available = False

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        使用 Deep Agent 检测和诊断问题

        Args:
            context: Fix context with workflow information

        Returns:
            List of detected issues with Deep Agent diagnosis
        """
        if not self.deep_agent_available:
            log.warning("⚠️  Deep Agent not available, skipping")
            return []

        log.info(f"🔍 Deep Agent analyzing workflow {context.invocation_id}...")

        try:
            # 1. 提取错误日志和上下文
            error_data = self._extract_error_context(context)

            if not error_data['error_log'] or error_data['error_log'] == "No error messages found":
                log.warning(f"⚠️  No error logs found for workflow {context.invocation_id}")
                return []

            # 2. 调用 Deep Agent 诊断
            diagnosis = self._call_deep_agent(
                error_log=error_data['error_log'],
                stack_trace=error_data['stack_trace'],
                container_features=error_data['container_features']
            )

            if not diagnosis or diagnosis.get('finish_reason') == 'error':
                log.warning(f"⚠️  Deep Agent diagnosis failed: {diagnosis.get('content', 'Unknown error')}")
                return []

            # 3. 解析诊断结果
            parsed = self._parse_diagnosis(diagnosis)

            if not parsed:
                log.warning("⚠️  Failed to parse Deep Agent diagnosis")
                return []

            # 4. 将诊断转换为问题报告
            issue = {
                'type': self._infer_error_type(parsed),
                'severity': self._assess_severity(parsed),
                'root_cause': parsed.get('root_cause', ''),
                'why_missed': parsed.get('why_missed', ''),
                'recommended_fix': parsed.get('fix', ''),
                'prevention': parsed.get('prevention', ''),
                'confidence': parsed.get('confidence', 0.7),
                'deep_agent_diagnosis': parsed,
                'original_error': error_data['error_log'][:500],
            }

            log.info(f"✅ Deep Agent detected issue: {issue['type']}")
            log.info(f"   Root cause: {issue['root_cause'][:100]}...")
            log.info(f"   Confidence: {issue['confidence']}")

            return [issue]

        except Exception as e:
            log.error(f"❌ Deep Agent detection failed: {e}")
            import traceback
            log.error(traceback.format_exc())
            return []

    def _extract_error_context(self, context: FixContext) -> Dict[str, Any]:
        """
        从 workflow invocation 中提取错误上下文

        Args:
            context: Fix context

        Returns:
            Error context dict with logs and metadata
        """
        from galaxy.model import WorkflowInvocation
        from sqlalchemy.orm import joinedload
        import glob

        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            return {
                'error_log': 'No database session available',
                'stack_trace': '',
                'container_features': {}
            }

        # 获取 invocation
        invocation = sa_session.query(WorkflowInvocation).options(
            joinedload(WorkflowInvocation.workflow),
            joinedload(WorkflowInvocation.history),
            joinedload(WorkflowInvocation.steps)
        ).filter_by(id=context.invocation_id).first()

        if not invocation:
            return {
                'error_log': f'Workflow invocation {context.invocation_id} not found',
                'stack_trace': '',
                'container_features': {}
            }

        error_messages = []
        stack_traces = []
        container_info = {
            'base_image': 'Unknown',
            'python_version': 'Unknown',
            'cuda_version': 'Unknown',
        }

        # 检测是否是 Nextflow workflow
        is_nextflow = hasattr(invocation, 'scheduler') and invocation.scheduler == 'nextflow'

        if is_nextflow:
            # 从文件系统读取 Nextflow 日志
            try:
                app_config = context.metadata.get('app_config')
                job_working_dir = getattr(app_config, 'job_working_directory', 'database/jobs_directory')

                work_dirs = [
                    Path(job_working_dir) / "nextflow_workflows" / f"workflow_{context.invocation_id}",
                    Path("database/jobs_directory/nextflow_workflows") / f"workflow_{context.invocation_id}",
                ]

                for work_dir in work_dirs:
                    if not work_dir.exists():
                        continue

                    # 读取 .nextflow.log
                    nextflow_log = work_dir / ".nextflow.log"
                    if nextflow_log.exists():
                        with open(nextflow_log, 'r') as f:
                            log_content = f.read()
                            error_lines = [line for line in log_content.split('\n')
                                         if 'ERROR' in line or 'WARN' in line]
                            if error_lines:
                                error_messages.append("\n".join(error_lines[-20:]))

                    # 读取 nextflow.err
                    nextflow_err = work_dir / "nextflow.err"
                    if nextflow_err.exists():
                        with open(nextflow_err, 'r') as f:
                            stderr_content = f.read()
                            if stderr_content.strip():
                                stack_traces.append(stderr_content[-2000:])

                    # 查找失败任务错误
                    work_subdirs = work_dir / "work"
                    if work_subdirs.exists():
                        command_err_files = glob.glob(str(work_subdirs / "**" / ".command.err"), recursive=True)
                        for err_file in command_err_files[:3]:
                            err_path = Path(err_file)
                            if err_path.stat().st_size > 0:
                                with open(err_path, 'r') as f:
                                    err_content = f.read()
                                    if err_content.strip():
                                        stack_traces.append(f"Task error:\n{err_content[:1000]}")

                    break

            except Exception as e:
                log.error(f"Error reading Nextflow logs: {e}")
                error_messages.append(f"Error accessing logs: {str(e)}")

        # 合并错误信息
        error_log = "\n\n".join(error_messages) if error_messages else "No error messages found"
        stack_trace = "\n\n".join(stack_traces) if stack_traces else ""

        return {
            'error_log': error_log,
            'stack_trace': stack_trace,
            'container_features': container_info,
        }

    def _call_deep_agent(
        self,
        error_log: str,
        stack_trace: str,
        container_features: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        调用 Deep Agent 进行诊断

        Args:
            error_log: Error messages
            stack_trace: Stack trace
            container_features: Container metadata

        Returns:
            Deep Agent diagnosis result
        """
        try:
            import time
            start_time = time.time()

            # 调用 Deep Agent 的 diagnose_failure 方法
            response = self.llm_client.diagnose_failure(
                error_log=error_log,
                stack_trace=stack_trace,
                container_features=container_features,
                temperature=0.3,
                max_tokens=2000
            )

            duration = time.time() - start_time

            log.info(f"🤖 Deep Agent diagnosis completed in {duration:.2f}s")
            log.info(f"   Model: {response.model}")
            log.info(f"   Tokens: {response.tokens_used}")
            log.info(f"   Finish reason: {response.finish_reason}")

            return {
                'content': response.content,
                'model': response.model,
                'tokens_used': response.tokens_used,
                'finish_reason': response.finish_reason,
                'duration': duration,
            }

        except Exception as e:
            log.error(f"Deep Agent call failed: {e}")
            return {
                'content': f"Error: {str(e)}",
                'finish_reason': 'error',
            }

    def _parse_diagnosis(self, diagnosis: Dict[str, Any]) -> Optional[Dict[str, Any]]:
        """
        解析 Deep Agent 诊断结果

        Deep Agent 返回结构化的诊断，包含:
        - ROOT CAUSE: 根本原因
        - WHY IT WAS MISSED: 为什么之前没检测到
        - RECOMMENDED FIX: 推荐的修复方案
        - PREVENTION: 预防策略

        Args:
            diagnosis: Raw diagnosis from Deep Agent

        Returns:
            Parsed structured diagnosis
        """
        try:
            # 使用 Deep Agent 的 parse_structured_diagnosis
            from core.llm_client import LLMClient

            # 创建临时客户端用于解析
            content = diagnosis.get('content', '')

            # 解析结构化诊断
            parsed = self.llm_client.parse_structured_diagnosis(diagnosis)

            return parsed

        except Exception as e:
            log.error(f"Failed to parse diagnosis: {e}")

            # 回退：简单文本解析
            content = diagnosis.get('content', '')
            return {
                'root_cause': content[:200] if content else 'Unknown',
                'why_missed': '',
                'fix': '',
                'prevention': '',
                'confidence': 0.5,
            }

    def _infer_error_type(self, diagnosis: Dict[str, Any]) -> str:
        """
        从诊断结果推断错误类型

        Args:
            diagnosis: Parsed diagnosis

        Returns:
            Error type string
        """
        root_cause = diagnosis.get('root_cause', '').lower()
        fix_text = diagnosis.get('fix', '').lower()

        # 关键词匹配
        if 'cpu' in root_cause or 'cpus' in root_cause:
            return 'cpu_resource'
        elif 'memory' in root_cause or 'ram' in root_cause:
            return 'memory_resource'
        elif 'gtf' in root_cause or 'gff' in root_cause:
            return 'file_format'
        elif 'genome' in root_cause or 'reference' in root_cause:
            return 'reference_genome'
        elif 'parameter' in root_cause or 'param' in root_cause:
            return 'parameter_validation'
        elif 'container' in root_cause or 'docker' in root_cause:
            return 'container_error'
        elif 's3' in root_cause or 'bucket' in root_cause:
            return 'aws_resource'
        else:
            return 'unknown'

    def _assess_severity(self, diagnosis: Dict[str, Any]) -> str:
        """
        评估错误严重程度

        Args:
            diagnosis: Parsed diagnosis

        Returns:
            Severity level: 'high', 'medium', 'low'
        """
        confidence = diagnosis.get('confidence', 0.5)
        root_cause = diagnosis.get('root_cause', '').lower()

        # 高置信度 + 明确原因 = 低严重性（容易修复）
        if confidence > 0.8 and len(root_cause) > 50:
            return 'low'
        elif confidence > 0.6:
            return 'medium'
        else:
            return 'high'

    def generate_fix_plan(self, issue: Dict[str, Any], context: FixContext) -> Optional[FixPlan]:
        """
        基于 Deep Agent 诊断生成修复计划

        Args:
            issue: Detected issue with Deep Agent diagnosis
            context: Fix context

        Returns:
            Fix plan with actions
        """
        try:
            diagnosis = issue.get('deep_agent_diagnosis', {})
            fix_text = diagnosis.get('fix', '')

            if not fix_text:
                log.warning("⚠️  No fix recommendation from Deep Agent")
                return None

            # 从修复建议中提取参数更新
            parameters = self._extract_parameters_from_fix(fix_text, issue['type'])

            if not parameters:
                log.warning(f"⚠️  Could not extract parameters from fix: {fix_text[:100]}")
                return None

            # 创建修复操作
            actions = [
                FixAction(
                    action=ActionType.UPDATE_PARAMETERS,
                    params=parameters,
                    description=f"Apply Deep Agent recommended fix: {fix_text[:100]}",
                )
            ]

            # 评估风险
            risk_level = self._assess_risk_level(issue, parameters)

            return FixPlan(
                fix_type=FixType.PARAMETER_FIX,
                actions=actions,
                estimated_success_rate=diagnosis.get('confidence', 0.7),
                risk_level=risk_level,
                requires_approval=(risk_level == RiskLevel.HIGH),
                rationale=f"Deep Agent diagnosis: {diagnosis.get('root_cause', '')[:200]}",
            )

        except Exception as e:
            log.error(f"Failed to generate fix plan: {e}")
            import traceback
            log.error(traceback.format_exc())
            return None

    def _extract_parameters_from_fix(self, fix_text: str, error_type: str) -> Dict[str, Any]:
        """
        从 Deep Agent 的修复建议中提取参数（增强版）

        支持多种格式:
        1. "Set max_cpus to 64"
        2. "--max_cpus 64"
        3. "max_cpus: 64"
        4. JSON 格式: {"max_cpus": 64}

        Args:
            fix_text: Fix recommendation text
            error_type: Type of error

        Returns:
            Parameters dict
        """
        import re
        import json

        parameters = {}
        log.info(f"🔍 Extracting parameters from fix text (error_type={error_type}):")
        log.info(f"   Fix text: {fix_text[:200]}...")

        # 尝试 1: 检查是否包含 JSON 格式的参数
        try:
            json_match = re.search(r'\{[^{}]*\}', fix_text)
            if json_match:
                json_str = json_match.group(0)
                parsed = json.loads(json_str)
                if isinstance(parsed, dict):
                    parameters.update(parsed)
                    log.info(f"   ✅ Extracted from JSON: {parameters}")
                    return parameters
        except:
            pass

        # 尝试 2: 根据错误类型使用专门的正则表达式
        if error_type == 'cpu_resource':
            patterns = [
                r'(?:set|increase|use)\s+(?:max_)?cpus?\s+(?:to\s+)?(\d+)',
                r'(?:max_)?cpus?\s*[:=]\s*(\d+)',
                r'--(?:max_)?cpus?\s+(\d+)',
            ]
            for pattern in patterns:
                match = re.search(pattern, fix_text, re.I)
                if match:
                    parameters['max_cpus'] = int(match.group(1))
                    log.info(f"   ✅ Extracted CPU: max_cpus={parameters['max_cpus']}")
                    break

        elif error_type == 'memory_resource':
            patterns = [
                r'(?:set|increase|use)\s+(?:max_)?memory\s+(?:to\s+)?(\d+)\s*(GB|MB|G|M)?',
                r'(?:max_)?memory\s*[:=]\s*["\']?(\d+)\s*(GB|MB|G|M)?',
                r'--(?:max_)?memory\s+["\']?(\d+)\s*(GB|MB|G|M)?',
            ]
            for pattern in patterns:
                match = re.search(pattern, fix_text, re.I)
                if match:
                    memory_val = int(match.group(1))
                    unit = match.group(2) if len(match.groups()) > 1 else 'GB'
                    unit = unit or 'GB'
                    if unit.upper() in ['G', 'GB']:
                        parameters['max_memory'] = f"{memory_val}.GB"
                    elif unit.upper() in ['M', 'MB']:
                        parameters['max_memory'] = f"{memory_val}.MB"
                    log.info(f"   ✅ Extracted memory: max_memory={parameters['max_memory']}")
                    break

        elif error_type == 'reference_genome':
            patterns = [
                r'genome\s*[:=]\s*["\']?([a-zA-Z0-9_.-]+)',
                r'--genome\s+["\']?([a-zA-Z0-9_.-]+)',
                r'(?:set|use)\s+genome\s+(?:to\s+)?["\']?([a-zA-Z0-9_.-]+)',
            ]
            for pattern in patterns:
                match = re.search(pattern, fix_text, re.I)
                if match:
                    parameters['genome'] = match.group(1).strip('"\'')
                    log.info(f"   ✅ Extracted genome: genome={parameters['genome']}")
                    break

        # 尝试 3: 通用参数提取（适用于所有错误类型）
        general_patterns = [
            r'--(\w+)\s+["\']?([^"\'\s,;]+)["\']?',
            r'(\w+)\s*[:=]\s*["\']?([^"\'\s,;]+)["\']?',
        ]

        skip_words = {'set', 'use', 'add', 'to', 'the', 'is', 'are', 'a', 'an', 'and', 'or'}

        for pattern in general_patterns:
            for match in re.finditer(pattern, fix_text, re.I):
                param_name = match.group(1)
                param_value = match.group(2)

                if param_name.lower() in skip_words or len(param_name) < 2:
                    continue

                # 类型推断
                try:
                    if '.' in param_value:
                        param_value = float(param_value)
                    else:
                        param_value = int(param_value)
                except:
                    param_value = param_value.strip('"\'')

                if param_name not in parameters:
                    parameters[param_name] = param_value
                    log.info(f"   ✅ Extracted: {param_name}={param_value}")

        if parameters:
            log.info(f"   📦 Total extracted: {len(parameters)} parameters")
        else:
            log.warning(f"   ⚠️  No parameters extracted!")

        return parameters

    def _assess_risk_level(self, issue: Dict[str, Any], parameters: Dict[str, Any]) -> RiskLevel:
        """
        评估修复操作的风险等级

        Args:
            issue: Detected issue
            parameters: Parameters to update

        Returns:
            Risk level
        """
        # 高置信度的简单参数修改 = 低风险
        if issue.get('confidence', 0) > 0.8 and len(parameters) <= 2:
            return RiskLevel.LOW

        # 多个参数修改或中等置信度 = 中等风险
        elif len(parameters) <= 5:
            return RiskLevel.MEDIUM

        # 大量参数修改或低置信度 = 高风险
        else:
            return RiskLevel.HIGH

    def apply_fix(
        self,
        context: FixContext,
        fix_plan: FixPlan,
        sa_session
    ) -> AutoFixResult:
        """
        应用修复计划

        Args:
            context: Fix context
            fix_plan: Fix plan to apply
            sa_session: SQLAlchemy session

        Returns:
            Fix result
        """
        try:
            log.info(f"🔧 Applying Deep Agent fix for workflow {context.invocation_id}")

            # 提取所有参数更新
            all_params = {}
            for action in fix_plan.actions:
                if action.action == ActionType.UPDATE_PARAMETERS:
                    all_params.update(action.params)

            log.info(f"   Updated parameters: {all_params}")

            return AutoFixResult(
                status=FixStatus.FIXED,
                message=f"Deep Agent fix applied: {len(all_params)} parameters updated",
                fix_actions=fix_plan.actions,
                metadata={
                    'fixer': self.name,
                    'parameters': all_params,
                    'confidence': fix_plan.estimated_success_rate,
                }
            )

        except Exception as e:
            log.error(f"Failed to apply fix: {e}")
            return AutoFixResult(
                status=FixStatus.FAILED,
                message=f"Failed to apply fix: {str(e)}",
                error_message=str(e),
            )
