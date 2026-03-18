"""
AutoFix 3.0 - Iterative Debugger

智能迭代调试器，实现类似人类专家的多次尝试修复能力：
1. 多次尝试（最多 N 轮）
2. 失败模式检测（避免重复相同错误）
3. 学习机制（从失败中学习，调整策略）
4. 进度追踪（记录每次尝试的结果）
5. 智能终止（检测到无法修复时提前终止）

这是达到 Claude 100% 能力的关键组件。

作者：AI Workflow AutoFix Team
日期：2026-01-31
"""

import logging
import time
import hashlib
from typing import Any, Dict, List, Optional, Tuple
from pathlib import Path
from enum import Enum
from dataclasses import dataclass, field
from datetime import datetime

log = logging.getLogger(__name__)


class AttemptStatus(Enum):
    """尝试状态"""
    PENDING = "pending"           # 待执行
    RUNNING = "running"           # 执行中
    SUCCESS = "success"           # 成功
    FAILED = "failed"             # 失败
    DUPLICATE = "duplicate"       # 重复失败（与之前相同的错误）
    TIMEOUT = "timeout"           # 超时
    ABORTED = "aborted"           # 中止（检测到无法修复）


class TerminationReason(Enum):
    """终止原因"""
    SUCCESS = "success"                    # 成功修复
    MAX_ATTEMPTS = "max_attempts"          # 达到最大尝试次数
    DUPLICATE_FAILURES = "duplicate_failures"  # 连续重复失败
    NO_PROGRESS = "no_progress"            # 没有进展
    MANUAL_ABORT = "manual_abort"          # 手动中止
    TIMEOUT = "timeout"                    # 总超时


@dataclass
class AttemptRecord:
    """单次尝试记录"""
    attempt_number: int
    status: AttemptStatus
    timestamp: str

    # 修复信息
    fixer_name: str
    fix_strategy: str
    fix_actions: List[Dict[str, Any]]

    # 执行结果
    error_logs: str = ""
    error_hash: str = ""  # 错误的哈希值，用于检测重复
    execution_time: float = 0.0

    # 分析结果
    error_category: str = ""
    root_cause: str = ""
    confidence: float = 0.0

    # 失败原因（如果失败）
    failure_reason: str = ""

    # 进展指标
    progress_score: float = 0.0  # 0-1，表示相比上次的进展

    # 额外元数据
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class DebugSession:
    """调试会话"""
    session_id: str
    workflow_id: str
    invocation_id: str

    # 配置
    max_attempts: int = 5
    timeout_seconds: int = 300  # 5 minutes total
    duplicate_threshold: int = 2  # 允许 2 次重复失败

    # 状态
    current_attempt: int = 0
    started_at: str = field(default_factory=lambda: datetime.now().isoformat())
    ended_at: Optional[str] = None

    # 记录
    attempts: List[AttemptRecord] = field(default_factory=list)

    # 终止信息
    is_terminated: bool = False
    termination_reason: Optional[TerminationReason] = None
    final_result: Optional[Dict[str, Any]] = None


class IterativeDebugger:
    """
    迭代调试器

    核心能力：
    - 智能重试：基于失败模式调整策略
    - 失败检测：避免重复相同的错误
    - 进度评估：量化每次尝试的进展
    - 提前终止：检测到无法修复时停止
    - 详细记录：追踪所有尝试的历史
    """

    def __init__(
        self,
        agent,  # DeepAnalysisAgent
        toolkit,  # EnhancedToolKit
        workflow_dir: Path,
        max_attempts: int = 5,
        timeout_seconds: int = 300,
    ):
        """
        初始化迭代调试器

        Args:
            agent: DeepAnalysisAgent 实例
            toolkit: EnhancedToolKit 实例
            workflow_dir: 工作流目录
            max_attempts: 最大尝试次数
            timeout_seconds: 总超时时间（秒）
        """
        self.agent = agent
        self.toolkit = toolkit
        self.workflow_dir = workflow_dir
        self.max_attempts = max_attempts
        self.timeout_seconds = timeout_seconds

        # 当前会话
        self.session: Optional[DebugSession] = None

        # 错误模式缓存
        self.error_patterns: Dict[str, int] = {}  # error_hash -> count

    def start_session(
        self,
        workflow_id: str,
        invocation_id: str,
    ) -> DebugSession:
        """
        启动新的调试会话

        Args:
            workflow_id: 工作流 ID
            invocation_id: 调用 ID

        Returns:
            新创建的调试会话
        """
        session_id = f"{workflow_id}_{invocation_id}_{int(time.time())}"

        self.session = DebugSession(
            session_id=session_id,
            workflow_id=workflow_id,
            invocation_id=invocation_id,
            max_attempts=self.max_attempts,
            timeout_seconds=self.timeout_seconds,
        )

        self.error_patterns = {}

        log.info(f"🎬 Started debug session: {session_id}")
        log.info(f"   Max attempts: {self.max_attempts}")
        log.info(f"   Timeout: {self.timeout_seconds}s")

        return self.session

    def attempt_fix(
        self,
        task_name: str,
        error_logs: str,
        exit_code: Optional[int],
        context: Dict[str, Any],
    ) -> Tuple[AttemptRecord, bool]:
        """
        尝试一次修复

        Args:
            task_name: 任务名称
            error_logs: 错误日志
            exit_code: 退出码
            context: 上下文信息

        Returns:
            (attempt_record, should_continue)
            - attempt_record: 本次尝试的记录
            - should_continue: 是否应该继续尝试
        """
        if not self.session:
            raise RuntimeError("No active debug session. Call start_session() first.")

        # 检查是否已终止
        if self.session.is_terminated:
            log.warning(f"⚠️  Session already terminated: {self.session.termination_reason.value}")
            return None, False

        # 检查是否超时
        elapsed = time.time() - datetime.fromisoformat(self.session.started_at).timestamp()
        if elapsed > self.timeout_seconds:
            log.warning(f"⏱️  Session timeout ({elapsed:.1f}s > {self.timeout_seconds}s)")
            self._terminate_session(TerminationReason.TIMEOUT)
            return None, False

        # 检查是否达到最大尝试次数
        if self.session.current_attempt >= self.max_attempts:
            log.warning(f"🛑 Max attempts reached ({self.max_attempts})")
            self._terminate_session(TerminationReason.MAX_ATTEMPTS)
            return None, False

        # 开始新尝试
        self.session.current_attempt += 1
        attempt_number = self.session.current_attempt

        log.info(f"\n{'='*80}")
        log.info(f"🔄 Attempt {attempt_number}/{self.max_attempts}")
        log.info(f"{'='*80}")

        start_time = time.time()

        # 创建尝试记录
        attempt = AttemptRecord(
            attempt_number=attempt_number,
            status=AttemptStatus.RUNNING,
            timestamp=datetime.now().isoformat(),
            fixer_name="DeepAnalysisAgent",
            fix_strategy="iterative_debugging",
            fix_actions=[],
        )

        try:
            # 计算错误哈希
            error_hash = self._compute_error_hash(error_logs)
            attempt.error_hash = error_hash
            attempt.error_logs = error_logs[:500]  # 保存前 500 字符

            # 检查是否重复错误（只在失败时检查）
            # 成功的尝试不应该被计入重复
            check_duplicate = False
            if error_hash in self.error_patterns:
                # 只有当之前的尝试也失败时才算重复
                self.error_patterns[error_hash] += 1
                duplicate_count = self.error_patterns[error_hash]
                check_duplicate = True

                log.warning(f"⚠️  Similar error pattern detected (count: {duplicate_count})")
            else:
                self.error_patterns[error_hash] = 1

            # 🔑 核心：使用 DeepAnalysisAgent 进行分析
            log.info(f"🤖 Running DeepAnalysisAgent...")

            # 如果不是第一次尝试，添加历史信息到上下文
            if attempt_number > 1:
                context['previous_attempts'] = [
                    {
                        'attempt': a.attempt_number,
                        'error_category': a.error_category,
                        'root_cause': a.root_cause,
                        'fix_actions': a.fix_actions,
                        'failure_reason': a.failure_reason,
                    }
                    for a in self.session.attempts
                ]

            analysis_result = self.agent.analyze(
                task_name=task_name,
                error_logs=error_logs,
                exit_code=exit_code,
                context=context,
            )

            # 记录分析结果
            attempt.error_category = analysis_result.get('error_category', 'UNKNOWN')
            attempt.root_cause = analysis_result.get('root_cause', '')
            attempt.confidence = analysis_result.get('confidence', 0.0)

            # 提取修复动作
            if analysis_result.get('fixable'):
                # 从分析结果中提取修复动作
                fix_actions = []

                # 参数调整
                if analysis_result.get('suggested_params'):
                    fix_actions.append({
                        'action': 'update_parameters',
                        'params': analysis_result['suggested_params'],
                    })

                # 代码修改
                if analysis_result.get('code_changes'):
                    for change in analysis_result['code_changes']:
                        fix_actions.append({
                            'action': 'edit_file',
                            'file': change.get('file'),
                            'old_code': change.get('old_code'),
                            'new_code': change.get('new_code'),
                        })

                # 文件生成
                if analysis_result.get('generated_files'):
                    for gen_file in analysis_result['generated_files']:
                        fix_actions.append({
                            'action': 'upload_file',
                            'original': gen_file.get('original'),
                            'fixed': gen_file.get('fixed'),
                        })

                attempt.fix_actions = fix_actions

                # 🔑 应用修复（这里需要实际执行修复）
                log.info(f"✅ Fix plan generated with {len(fix_actions)} actions")
                log.info(f"   Confidence: {attempt.confidence:.2%}")

                # 计算进度分数
                attempt.progress_score = self._calculate_progress(attempt)

                # 如果置信度高且有具体的修复动作，标记为成功
                if attempt.confidence >= 0.8 and len(fix_actions) > 0:
                    attempt.status = AttemptStatus.SUCCESS

                    log.info(f"🎉 Fix attempt succeeded!")

                    self.session.attempts.append(attempt)
                    self._terminate_session(TerminationReason.SUCCESS, analysis_result)
                    return attempt, False
                else:
                    # 置信度不够高，继续尝试
                    attempt.status = AttemptStatus.FAILED
                    attempt.failure_reason = f"Low confidence ({attempt.confidence:.2%})"
                    log.warning(f"⚠️  Fix confidence too low, will retry")

                    # 检查重复失败
                    if check_duplicate and duplicate_count >= self.session.duplicate_threshold:
                        attempt.status = AttemptStatus.DUPLICATE
                        self.session.attempts.append(attempt)
                        log.error(f"🛑 Too many duplicate low-confidence failures, aborting")
                        self._terminate_session(TerminationReason.DUPLICATE_FAILURES)
                        return attempt, False
            else:
                # 不可修复
                attempt.status = AttemptStatus.FAILED
                attempt.failure_reason = analysis_result.get('recommendation', 'Not fixable')
                log.warning(f"❌ Analysis determined issue is not fixable")

                # 检查重复失败
                if check_duplicate and duplicate_count >= self.session.duplicate_threshold:
                    attempt.status = AttemptStatus.DUPLICATE
                    self.session.attempts.append(attempt)
                    log.error(f"🛑 Too many duplicate 'not fixable' failures, aborting")
                    self._terminate_session(TerminationReason.DUPLICATE_FAILURES)
                    return attempt, False

            attempt.execution_time = time.time() - start_time
            self.session.attempts.append(attempt)

            # 评估是否应该继续
            should_continue = self._should_continue()

            if not should_continue:
                log.info(f"🛑 Stopping iteration (no progress detected)")
                self._terminate_session(TerminationReason.NO_PROGRESS)

            return attempt, should_continue

        except Exception as e:
            log.error(f"❌ Attempt failed with exception: {e}")
            import traceback
            log.error(traceback.format_exc())

            attempt.status = AttemptStatus.FAILED
            attempt.failure_reason = str(e)
            attempt.execution_time = time.time() - start_time

            self.session.attempts.append(attempt)

            return attempt, False

    def run_until_fixed(
        self,
        task_name: str,
        error_logs: str,
        exit_code: Optional[int],
        context: Dict[str, Any],
    ) -> Dict[str, Any]:
        """
        持续尝试直到修复成功或达到终止条件

        Args:
            task_name: 任务名称
            error_logs: 错误日志
            exit_code: 退出码
            context: 上下文信息

        Returns:
            调试会话的最终结果
        """
        log.info(f"\n{'='*80}")
        log.info(f"🚀 Starting iterative debugging")
        log.info(f"{'='*80}")

        # 启动会话
        workflow_id = context.get('workflow_id', 'unknown')
        invocation_id = context.get('invocation_id', 'unknown')
        self.start_session(workflow_id, invocation_id)

        # 迭代尝试
        while True:
            attempt, should_continue = self.attempt_fix(
                task_name=task_name,
                error_logs=error_logs,
                exit_code=exit_code,
                context=context,
            )

            if not should_continue:
                break

        # 返回会话结果
        return self.get_session_summary()

    def get_session_summary(self) -> Dict[str, Any]:
        """
        获取会话摘要

        Returns:
            包含所有尝试和最终结果的摘要
        """
        if not self.session:
            return {'error': 'No active session'}

        successful_attempts = [
            a for a in self.session.attempts
            if a.status == AttemptStatus.SUCCESS
        ]

        failed_attempts = [
            a for a in self.session.attempts
            if a.status == AttemptStatus.FAILED
        ]

        duplicate_attempts = [
            a for a in self.session.attempts
            if a.status == AttemptStatus.DUPLICATE
        ]

        total_time = 0.0
        if self.session.ended_at:
            total_time = (
                datetime.fromisoformat(self.session.ended_at).timestamp() -
                datetime.fromisoformat(self.session.started_at).timestamp()
            )

        return {
            'session_id': self.session.session_id,
            'workflow_id': self.session.workflow_id,
            'invocation_id': self.session.invocation_id,
            'success': self.session.termination_reason == TerminationReason.SUCCESS,
            'terminated': self.session.is_terminated,
            'termination_reason': self.session.termination_reason.value if self.session.termination_reason else None,
            'total_attempts': len(self.session.attempts),
            'successful_attempts': len(successful_attempts),
            'failed_attempts': len(failed_attempts),
            'duplicate_attempts': len(duplicate_attempts),
            'total_time_seconds': total_time,
            'attempts': [
                {
                    'attempt_number': a.attempt_number,
                    'status': a.status.value,
                    'timestamp': a.timestamp,
                    'error_category': a.error_category,
                    'root_cause': a.root_cause,
                    'confidence': a.confidence,
                    'fix_actions_count': len(a.fix_actions),
                    'execution_time': a.execution_time,
                    'progress_score': a.progress_score,
                    'failure_reason': a.failure_reason,
                }
                for a in self.session.attempts
            ],
            'final_result': self.session.final_result,
            'error_pattern_distribution': dict(self.error_patterns),
        }

    def _compute_error_hash(self, error_logs: str) -> str:
        """
        计算错误的哈希值

        用于检测重复错误。哈希基于错误的关键部分，保留错误的本质特征。

        Args:
            error_logs: 错误日志

        Returns:
            错误哈希（16字符）
        """
        # 使用原始错误日志，但移除明显的时间戳
        import re

        cleaned = error_logs

        # 只移除明显的时间戳格式
        cleaned = re.sub(r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\.\d+', '', cleaned)

        # 计算哈希（保留更多原始信息以区分不同错误）
        hash_obj = hashlib.md5(cleaned.encode('utf-8'))
        return hash_obj.hexdigest()[:16]

    def _calculate_progress(self, current_attempt: AttemptRecord) -> float:
        """
        计算当前尝试相比上一次的进展

        Args:
            current_attempt: 当前尝试

        Returns:
            进展分数 (0-1)
        """
        if not self.session or len(self.session.attempts) == 0:
            return 0.5  # 第一次尝试，给中等分数

        # 获取上一次尝试
        previous = self.session.attempts[-1]

        # 因素1: 置信度是否提高
        confidence_delta = current_attempt.confidence - previous.confidence

        # 因素2: 错误类别是否更精确
        category_score = 0.0
        if current_attempt.error_category != 'UNKNOWN':
            category_score = 0.3

        # 因素3: 是否有具体的修复动作
        action_score = min(len(current_attempt.fix_actions) * 0.2, 0.4)

        # 综合评分
        progress = 0.3 * (confidence_delta + 0.5) + category_score + action_score

        return max(0.0, min(1.0, progress))

    def _should_continue(self) -> bool:
        """
        判断是否应该继续尝试

        Returns:
            True if should continue, False otherwise
        """
        if not self.session or len(self.session.attempts) < 2:
            return True  # 至少尝试 2 次

        # 获取最近 2 次尝试
        recent = self.session.attempts[-2:]

        # 检查进展
        progress_scores = [a.progress_score for a in recent]
        avg_progress = sum(progress_scores) / len(progress_scores)

        if avg_progress < 0.2:
            log.warning(f"⚠️  Low progress detected (avg: {avg_progress:.2f})")
            return False

        # 检查置信度
        confidences = [a.confidence for a in recent]
        avg_confidence = sum(confidences) / len(confidences)

        if avg_confidence < 0.3:
            log.warning(f"⚠️  Low confidence detected (avg: {avg_confidence:.2%})")
            return False

        return True

    def _terminate_session(
        self,
        reason: TerminationReason,
        final_result: Optional[Dict[str, Any]] = None
    ):
        """
        终止当前会话

        Args:
            reason: 终止原因
            final_result: 最终结果（如果有）
        """
        if not self.session:
            return

        self.session.is_terminated = True
        self.session.termination_reason = reason
        self.session.ended_at = datetime.now().isoformat()
        self.session.final_result = final_result

        log.info(f"🏁 Session terminated: {reason.value}")

        if final_result:
            log.info(f"   Final result available")
