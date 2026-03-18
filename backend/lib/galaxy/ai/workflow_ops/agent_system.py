"""
Galaxy AI Agent System

核心理念: "用到才调用，发现问题才调用" - Agent-based Architecture

This module provides a complete AI agent ecosystem for workflow operations,
including agent registry, orchestration, and specialized agents for different
problem domains.
"""

from abc import ABC, abstractmethod
from enum import Enum
from typing import Dict, List, Optional, Any, Callable
import logging
import time
import asyncio
from datetime import datetime

log = logging.getLogger(__name__)


class AgentCapability(Enum):
    """Agent 能力类型"""
    PARAMETER_CONFIG = "parameter_config"
    RESOURCE_OPTIMIZATION = "resource_optimization"
    NETWORK_DIAGNOSTIC = "network_diagnostic"
    STORAGE_MANAGEMENT = "storage_management"
    PIPELINE_VERSION = "pipeline_version"
    CONTAINER_IMAGE = "container_image"
    WORKFLOW_DEBUG = "workflow_debug"
    DATA_VALIDATION = "data_validation"
    LOG_ANALYSIS = "log_analysis"
    METRICS_COLLECTOR = "metrics_collector"
    COST_OPTIMIZATION = "cost_optimization"
    COMPLIANCE_AUDIT = "compliance_audit"
    ROOT_CAUSE_ANALYSIS = "root_cause_analysis"
    PREDICTIVE_MAINTENANCE = "predictive_maintenance"
    AUTO_SCALING = "auto_scaling"


class AgentTriggerCondition(Enum):
    """Agent 触发条件"""
    ON_ERROR = "on_error"              # 发生错误时
    ON_WARNING = "on_warning"          # 发生警告时
    ON_COMPLETION = "on_completion"    # 完成时
    ON_SCHEDULE = "on_schedule"        # 定时触发
    ON_DEMAND = "on_demand"            # 按需触发
    ALWAYS = "always"                  # 始终运行


class AgentPriority(Enum):
    """Agent 优先级"""
    CRITICAL = 1   # 关键问题（数据丢失、安全漏洞）
    HIGH = 2       # 高优先级（服务中断）
    MEDIUM = 3     # 中优先级（性能问题）
    LOW = 4        # 低优先级（优化建议）


class BaseAgent(ABC):
    """
    Agent 基类

    所有专项 Agent 必须继承此类并实现抽象方法
    """

    def __init__(self, app, llm_client=None):
        self.app = app
        self.llm_client = llm_client
        self.logger = log
        self._enabled = True

    @property
    @abstractmethod
    def name(self) -> str:
        """Agent 名称"""
        pass

    @property
    @abstractmethod
    def capability(self) -> AgentCapability:
        """Agent 能力"""
        pass

    @property
    @abstractmethod
    def trigger_conditions(self) -> List[AgentTriggerCondition]:
        """触发条件列表"""
        pass

    @property
    def priority(self) -> AgentPriority:
        """优先级（默认 MEDIUM）"""
        return AgentPriority.MEDIUM

    @property
    def requires_llm(self) -> bool:
        """是否需要 LLM（默认 False）"""
        return False

    @abstractmethod
    def can_handle(self, issue: Dict[str, Any]) -> bool:
        """
        判断是否能处理该问题

        Args:
            issue: 问题描述，包含 type, message, severity 等字段

        Returns:
            True 如果能处理，False 否则
        """
        pass

    @abstractmethod
    async def analyze(self, context: Dict[str, Any]) -> Dict[str, Any]:
        """
        分析问题

        Args:
            context: 上下文信息（workflow, invocation, logs等）

        Returns:
            分析结果字典
        """
        pass

    @abstractmethod
    async def suggest_fix(self, context: Dict[str, Any]) -> List[Dict[str, Any]]:
        """
        提供修复建议

        Args:
            context: 上下文信息

        Returns:
            修复建议列表，每个建议包含 action, description, risk_level 等
        """
        pass

    @abstractmethod
    async def apply_fix(self, fix_plan: Dict[str, Any], context: Dict[str, Any]) -> bool:
        """
        应用修复

        Args:
            fix_plan: 修复计划
            context: 上下文信息

        Returns:
            True 如果修复成功，False 否则
        """
        pass

    def get_cost_estimate(self) -> float:
        """估算 LLM 调用成本（美元）"""
        if self.requires_llm:
            return 0.01  # 默认 $0.01
        return 0.0

    def enable(self):
        """启用 Agent"""
        self._enabled = True
        log.info(f"Agent {self.name} enabled")

    def disable(self):
        """禁用 Agent"""
        self._enabled = False
        log.info(f"Agent {self.name} disabled")

    @property
    def is_enabled(self) -> bool:
        """是否已启用"""
        return self._enabled


class AgentRegistry:
    """
    Agent 注册中心

    负责管理所有 Agent 的注册、查找和统计
    """

    def __init__(self):
        self._agents: Dict[AgentCapability, BaseAgent] = {}
        self._agent_stats: Dict[str, Dict] = {}
        self._trigger_hooks: Dict[AgentTriggerCondition, List[BaseAgent]] = {
            condition: [] for condition in AgentTriggerCondition
        }

    def register(self, agent: BaseAgent):
        """注册 Agent"""
        self._agents[agent.capability] = agent
        self._agent_stats[agent.name] = {
            'total_calls': 0,
            'successful_fixes': 0,
            'failed_fixes': 0,
            'total_cost': 0.0,
            'avg_response_time': 0.0,
            'last_called': None,
            'status': 'idle'
        }

        # 注册触发钩子
        for condition in agent.trigger_conditions:
            self._trigger_hooks[condition].append(agent)

        log.info(f"Registered agent: {agent.name} with capability {agent.capability.value}")

    def unregister(self, capability: AgentCapability):
        """注销 Agent"""
        if capability in self._agents:
            agent = self._agents[capability]
            del self._agents[capability]
            del self._agent_stats[agent.name]

            # 移除触发钩子
            for condition in agent.trigger_conditions:
                if agent in self._trigger_hooks[condition]:
                    self._trigger_hooks[condition].remove(agent)

            log.info(f"Unregistered agent: {agent.name}")

    def get_agent(self, capability: AgentCapability) -> Optional[BaseAgent]:
        """获取指定能力的 Agent"""
        return self._agents.get(capability)

    def get_all_agents(self) -> List[BaseAgent]:
        """获取所有 Agent"""
        return list(self._agents.values())

    def get_agents_by_trigger(self, condition: AgentTriggerCondition) -> List[BaseAgent]:
        """获取指定触发条件的所有 Agent"""
        return self._trigger_hooks.get(condition, [])

    def find_capable_agents(self, issue: Dict[str, Any]) -> List[BaseAgent]:
        """
        找到所有能处理该问题的 Agent

        Args:
            issue: 问题描述

        Returns:
            能处理该问题的 Agent 列表，按优先级排序
        """
        capable_agents = []
        for agent in self._agents.values():
            if agent.is_enabled and agent.can_handle(issue):
                capable_agents.append(agent)

        # 按优先级排序（CRITICAL > HIGH > MEDIUM > LOW）
        capable_agents.sort(key=lambda a: a.priority.value)
        return capable_agents

    def get_stats(self) -> Dict[str, Dict]:
        """获取所有 Agent 的统计信息"""
        return self._agent_stats.copy()

    def get_agent_stats(self, agent_name: str) -> Optional[Dict]:
        """获取指定 Agent 的统计信息"""
        return self._agent_stats.get(agent_name)

    def update_stats(self, agent_name: str, success: bool, cost: float, response_time: float):
        """更新 Agent 统计信息"""
        if agent_name in self._agent_stats:
            stats = self._agent_stats[agent_name]
            stats['total_calls'] += 1
            if success:
                stats['successful_fixes'] += 1
            else:
                stats['failed_fixes'] += 1
            stats['total_cost'] += cost
            # 滑动平均响应时间（指数加权移动平均）
            alpha = 0.1  # 平滑系数
            if stats['avg_response_time'] == 0:
                stats['avg_response_time'] = response_time
            else:
                stats['avg_response_time'] = (
                    stats['avg_response_time'] * (1 - alpha) + response_time * alpha
                )
            stats['last_called'] = datetime.now().isoformat()
            stats['status'] = 'idle'

    def set_agent_status(self, agent_name: str, status: str):
        """设置 Agent 状态"""
        if agent_name in self._agent_stats:
            self._agent_stats[agent_name]['status'] = status


class AgentOrchestrator:
    """
    Agent 调度中心

    负责问题路由、Agent 调度、结果汇总
    """

    def __init__(self, app, llm_client=None):
        self.app = app
        self.llm_client = llm_client
        self.registry = AgentRegistry()
        self.logger = log
        self._dispatch_history: List[Dict] = []

    def register_agent(self, agent: BaseAgent):
        """注册 Agent"""
        self.registry.register(agent)

    async def dispatch(
        self,
        issue: Dict[str, Any],
        context: Dict[str, Any],
        max_agents: int = 3
    ) -> Dict[str, Any]:
        """
        调度 Agent 处理问题

        核心逻辑：
        1. 找到所有能处理该问题的 Agent
        2. 按优先级排序
        3. 依次调用 Agent，直到问题解决或达到最大尝试次数
        4. 如果所有 Agent 都无法解决，调用 RootCauseAnalysisAgent

        Args:
            issue: 问题描述
            context: 上下文信息
            max_agents: 最多尝试多少个 Agent（防止无限循环）

        Returns:
            调度结果
        """
        start_time = time.time()

        # 1. 找到能处理该问题的 Agent
        capable_agents = self.registry.find_capable_agents(issue)

        if not capable_agents:
            log.warning(f"No agent can handle issue: {issue.get('type')}")
            return {
                'success': False,
                'message': 'No agent available to handle this issue',
                'issue': issue,
                'agents_tried': []
            }

        # 限制尝试次数
        capable_agents = capable_agents[:max_agents]

        # 2. 依次尝试每个 Agent
        agents_tried = []
        for agent in capable_agents:
            agent_start_time = time.time()

            try:
                log.info(f"Dispatching to agent: {agent.name}")
                self.registry.set_agent_status(agent.name, 'analyzing')

                # 分析问题
                analysis = await agent.analyze(context)

                self.registry.set_agent_status(agent.name, 'suggesting_fixes')

                # 生成修复建议
                suggestions = await agent.suggest_fix(context)

                if suggestions:
                    # 选择最佳建议并应用
                    best_suggestion = suggestions[0]  # 简化：选第一个

                    self.registry.set_agent_status(agent.name, 'applying_fix')

                    success = await agent.apply_fix(best_suggestion, context)

                    agent_response_time = time.time() - agent_start_time
                    agent_cost = agent.get_cost_estimate()

                    # 更新统计
                    self.registry.update_stats(
                        agent.name,
                        success,
                        agent_cost,
                        agent_response_time
                    )

                    agents_tried.append({
                        'agent': agent.name,
                        'success': success,
                        'response_time': agent_response_time,
                        'cost': agent_cost
                    })

                    if success:
                        total_time = time.time() - start_time
                        result = {
                            'success': True,
                            'agent': agent.name,
                            'capability': agent.capability.value,
                            'analysis': analysis,
                            'fix_applied': best_suggestion,
                            'cost': agent_cost,
                            'response_time': agent_response_time,
                            'total_time': total_time,
                            'agents_tried': agents_tried
                        }

                        # 记录到历史
                        self._dispatch_history.append({
                            'timestamp': datetime.now().isoformat(),
                            'issue': issue,
                            'result': result
                        })

                        log.info(f"Issue resolved by {agent.name} in {total_time:.2f}s")
                        return result

                else:
                    log.warning(f"Agent {agent.name} provided no suggestions")

            except Exception as e:
                log.error(f"Agent {agent.name} failed: {e}", exc_info=True)
                self.registry.set_agent_status(agent.name, 'error')
                agents_tried.append({
                    'agent': agent.name,
                    'success': False,
                    'error': str(e)
                })
                continue

        # 3. 如果所有专项 Agent 都失败，调用根因分析 Agent
        root_cause_agent = self.registry.get_agent(AgentCapability.ROOT_CAUSE_ANALYSIS)
        if root_cause_agent and root_cause_agent.is_enabled:
            log.info("Escalating to RootCauseAnalysisAgent")
            try:
                analysis = await root_cause_agent.analyze(context)
                total_time = time.time() - start_time

                result = {
                    'success': False,
                    'agent': 'RootCauseAnalysisAgent',
                    'capability': AgentCapability.ROOT_CAUSE_ANALYSIS.value,
                    'analysis': analysis,
                    'message': 'Root cause analysis completed, manual intervention may be required',
                    'total_time': total_time,
                    'agents_tried': agents_tried
                }

                self._dispatch_history.append({
                    'timestamp': datetime.now().isoformat(),
                    'issue': issue,
                    'result': result
                })

                return result

            except Exception as e:
                log.error(f"RootCauseAnalysisAgent failed: {e}")

        # 4. 所有 Agent 都失败
        total_time = time.time() - start_time
        return {
            'success': False,
            'message': 'All agents failed to resolve the issue',
            'total_time': total_time,
            'agents_tried': agents_tried
        }

    async def trigger_scheduled_agents(self):
        """触发定时 Agent（用于后台任务）"""
        scheduled_agents = self.registry.get_agents_by_trigger(AgentTriggerCondition.ON_SCHEDULE)

        tasks = []
        for agent in scheduled_agents:
            if agent.is_enabled:
                task = asyncio.create_task(self._run_scheduled_agent(agent))
                tasks.append(task)

        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)

    async def _run_scheduled_agent(self, agent: BaseAgent):
        """运行定时 Agent"""
        try:
            log.info(f"Running scheduled agent: {agent.name}")
            context = {'trigger': 'scheduled'}
            analysis = await agent.analyze(context)
            log.info(f"Scheduled agent {agent.name} completed: {analysis}")
        except Exception as e:
            log.error(f"Scheduled agent {agent.name} failed: {e}")

    def get_dashboard_data(self) -> Dict[str, Any]:
        """获取 Agent 监控面板数据"""
        stats = self.registry.get_stats()

        total_calls = sum(s['total_calls'] for s in stats.values())
        total_cost = sum(s['total_cost'] for s in stats.values())
        total_success = sum(s['successful_fixes'] for s in stats.values())
        total_failed = sum(s['failed_fixes'] for s in stats.values())

        return {
            'total_agents': len(stats),
            'total_calls': total_calls,
            'total_cost': total_cost,
            'total_success': total_success,
            'total_failed': total_failed,
            'success_rate': total_success / total_calls if total_calls > 0 else 0,
            'agent_stats': stats,
            'recent_dispatches': self._dispatch_history[-20:]  # 最近20次调度
        }

    def get_dispatch_history(self, limit: int = 100) -> List[Dict]:
        """获取调度历史"""
        return self._dispatch_history[-limit:]

    def clear_history(self):
        """清空历史记录"""
        self._dispatch_history.clear()
        log.info("Dispatch history cleared")
