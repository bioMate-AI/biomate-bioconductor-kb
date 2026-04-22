"""
Workflow交互式查询Agent

支持用户通过自然语言查询workflow状态、历史、问题等
"""

import logging
import json
from typing import Dict, List, Optional, Any
from datetime import datetime

from .types import QueryResponse
from .llm_client import UnifiedLLMClient

log = logging.getLogger(__name__)


class WorkflowQueryAgent:
    """
    交互式查询Agent

    示例查询：
    - "为什么第3步失败了？"
    - "这个workflow大概还要跑多久？"
    - "为什么这次比上次慢？"
    - "可以跳过第2步吗？"
    """

    def __init__(
        self,
        llm_client: Optional[UnifiedLLMClient] = None,
        app=None
    ):
        """
        Args:
            llm_client: LLM客户端
            app: Galaxy app实例（用于查询数据库）
        """
        self.llm_client = llm_client or UnifiedLLMClient()
        self.app = app

    def query(
        self,
        user_question: str,
        invocation_id: int,
        context: Optional[Dict[str, Any]] = None
    ) -> QueryResponse:
        """
        处理用户查询

        Args:
            user_question: 用户的问题
            invocation_id: Workflow invocation ID
            context: 额外的上下文信息

        Returns:
            QueryResponse
        """
        context = context or {}

        # 1. 收集相关信息
        workflow_info = self._get_workflow_info(invocation_id)
        recent_logs = self._get_recent_logs(invocation_id, limit=100)
        historical_runs = self._get_historical_runs(workflow_info.get('workflow_id'))

        # 2. 构建prompt
        prompt = self._build_query_prompt(
            user_question,
            workflow_info,
            recent_logs,
            historical_runs
        )

        # 3. 调用LLM
        try:
            result = self.llm_client.call(
                messages=[
                    {"role": "system", "content": "你是Galaxy Nextflow workflow助手，帮助用户理解和调试workflow。回答要准确、简洁、实用。"},
                    {"role": "user", "content": prompt}
                ],
                model='gemini-2.5-flash',
                temperature=0.0,
            )

            content = result['content']

            # 4. 解析回答
            response = self._parse_llm_response(content, recent_logs)

            return response

        except Exception as e:
            log.error(f"Query failed: {e}")
            return QueryResponse(
                answer=f"抱歉，查询失败：{e}",
                sources=[],
                confidence=0.0,
            )

    def _get_workflow_info(self, invocation_id: int) -> Dict[str, Any]:
        """获取workflow基本信息"""
        if not self.app:
            return {}

        try:
            sa_session = self.app.model.context
            invocation = sa_session.query(self.app.model.WorkflowInvocation).get(invocation_id)

            if not invocation:
                return {}

            workflow = invocation.workflow

            return {
                'invocation_id': invocation_id,
                'workflow_id': workflow.id,
                'workflow_name': workflow.name,
                'state': invocation.state,
                'create_time': invocation.create_time.isoformat() if invocation.create_time else None,
                'update_time': invocation.update_time.isoformat() if invocation.update_time else None,
                'total_steps': len(workflow.steps),
            }

        except Exception as e:
            log.error(f"Failed to get workflow info: {e}")
            return {}

    def _get_recent_logs(self, invocation_id: int, limit: int = 100) -> List[str]:
        """获取最近的日志"""
        # TODO: 从NextflowMonitor或日志存储中读取
        # 暂时返回空列表
        return []

    def _get_historical_runs(self, workflow_id: Optional[int]) -> List[Dict[str, Any]]:
        """获取历史运行记录"""
        if not self.app or not workflow_id:
            return []

        try:
            sa_session = self.app.model.context
            invocations = sa_session.query(self.app.model.WorkflowInvocation).filter_by(
                workflow_id=workflow_id
            ).order_by(
                self.app.model.WorkflowInvocation.create_time.desc()
            ).limit(10).all()

            history = []
            for inv in invocations:
                history.append({
                    'invocation_id': inv.id,
                    'state': inv.state,
                    'create_time': inv.create_time.isoformat() if inv.create_time else None,
                    'update_time': inv.update_time.isoformat() if inv.update_time else None,
                })

            return history

        except Exception as e:
            log.error(f"Failed to get historical runs: {e}")
            return []

    def _build_query_prompt(
        self,
        question: str,
        workflow_info: Dict[str, Any],
        recent_logs: List[str],
        historical_runs: List[Dict[str, Any]]
    ) -> str:
        """构建查询prompt"""
        logs_text = "\n".join(recent_logs[-50:]) if recent_logs else "No logs available"
        history_json = json.dumps(historical_runs, indent=2)

        prompt = f"""用户问题：{question}

**Workflow信息：**
- Invocation ID: {workflow_info.get('invocation_id', 'N/A')}
- Workflow名称: {workflow_info.get('workflow_name', 'N/A')}
- 当前状态: {workflow_info.get('state', 'N/A')}
- 总步骤数: {workflow_info.get('total_steps', 'N/A')}
- 创建时间: {workflow_info.get('create_time', 'N/A')}
- 更新时间: {workflow_info.get('update_time', 'N/A')}

**最近的日志（最后50行）：**
```
{logs_text}
```

**历史运行记录（最近10次）：**
```json
{history_json}
```

**请根据以上信息回答用户问题。要求：**
1. 回答要准确、简洁、实用
2. 如果信息不足，明确说明
3. 提供可执行的建议（如果适用）
4. 引用具体的日志或数据（放在sources字段）
5. 提供后续可能的问题（follow_up_questions）
6. 评估回答的置信度（confidence, 0-1）

请以JSON格式返回：
```json
{{
  "answer": "对用户问题的回答（自然语言）",
  "sources": ["引用的日志片段或数据"],
  "confidence": 0.85,
  "follow_up_questions": ["相关的后续问题1", "相关的后续问题2"]
}}
```
"""

        return prompt

    def _parse_llm_response(self, content: str, logs: List[str]) -> QueryResponse:
        """解析LLM返回的JSON响应"""
        import re

        try:
            # 提取JSON
            json_match = re.search(r'```json\s*\n(.*?)\n```', content, re.DOTALL)
            if json_match:
                json_str = json_match.group(1)
            else:
                json_str = content

            parsed = json.loads(json_str)

            return QueryResponse(
                answer=parsed.get('answer', content),
                sources=parsed.get('sources', []),
                confidence=parsed.get('confidence', 0.5),
                follow_up_questions=parsed.get('follow_up_questions', []),
            )

        except json.JSONDecodeError:
            # 如果解析失败，返回原始内容
            return QueryResponse(
                answer=content,
                sources=[],
                confidence=0.5,
            )


class WorkflowChatSession:
    """
    对话会话管理

    支持多轮对话，维护上下文
    """

    def __init__(
        self,
        invocation_id: int,
        query_agent: WorkflowQueryAgent
    ):
        """
        Args:
            invocation_id: Workflow invocation ID
            query_agent: 查询agent
        """
        self.invocation_id = invocation_id
        self.query_agent = query_agent

        # 对话历史
        self.chat_history: List[Dict[str, str]] = []
        self.created_at = datetime.now()

    def ask(self, question: str) -> QueryResponse:
        """
        提问（支持多轮对话）

        Args:
            question: 用户问题

        Returns:
            QueryResponse
        """
        # 构建上下文（包含历史对话）
        context = {
            'chat_history': self.chat_history,
        }

        # 查询
        response = self.query_agent.query(
            user_question=question,
            invocation_id=self.invocation_id,
            context=context
        )

        # 记录到历史
        self.chat_history.append({
            'role': 'user',
            'content': question,
            'timestamp': datetime.now().isoformat(),
        })
        self.chat_history.append({
            'role': 'assistant',
            'content': response.answer,
            'timestamp': datetime.now().isoformat(),
        })

        return response

    def clear_history(self):
        """清除对话历史"""
        self.chat_history.clear()

    def get_history(self) -> List[Dict[str, str]]:
        """获取对话历史"""
        return self.chat_history
