"""
Agent Factory

负责创建和初始化所有 Agent
"""

import logging
from typing import List
from ..agent_system import BaseAgent, AgentOrchestrator

# Import all agents
from .parameter_config_agent import ParameterConfigAgent
from .resource_optimization_agent import ResourceOptimizationAgent
from .network_diagnostic_agent import NetworkDiagnosticAgent
from .log_analysis_agent import LogAnalysisAgent
from .root_cause_analysis_agent import RootCauseAnalysisAgent

log = logging.getLogger(__name__)


def create_all_agents(app, llm_client=None) -> List[BaseAgent]:
    """
    创建所有可用的 Agent

    Args:
        app: Galaxy app instance
        llm_client: LLM client (可选)

    Returns:
        Agent 列表
    """
    agents = [
        # 基础设施层
        ParameterConfigAgent(app, llm_client),
        ResourceOptimizationAgent(app, llm_client),
        NetworkDiagnosticAgent(app, llm_client),

        # 数据层
        LogAnalysisAgent(app, llm_client),

        # 智能决策层
        RootCauseAnalysisAgent(app, llm_client),
    ]

    log.info(f"Created {len(agents)} agents")
    return agents


def initialize_agent_system(app, llm_client=None) -> AgentOrchestrator:
    """
    初始化完整的 Agent 系统

    Args:
        app: Galaxy app instance
        llm_client: LLM client (可选)

    Returns:
        AgentOrchestrator 实例
    """
    # 创建调度中心
    orchestrator = AgentOrchestrator(app, llm_client)

    # 创建并注册所有 Agent
    agents = create_all_agents(app, llm_client)

    for agent in agents:
        orchestrator.register_agent(agent)

    log.info("Agent system initialized successfully")
    return orchestrator
