"""
统一的LLM客户端抽象层

支持多种LLM提供商：
- Anthropic Claude (claude-3-5-sonnet, claude-3-haiku)
- OpenAI GPT (gpt-4o, gpt-4o-mini)
- Local models (via Ollama)

统一接口，自动处理：
- 成本计算
- 重试逻辑
- 预算控制
- 调用统计
"""

import logging
import time
import os
from typing import Dict, List, Optional, Any, Literal
from datetime import datetime, timedelta
from abc import ABC, abstractmethod

from .types import LLMUsageStats

log = logging.getLogger(__name__)


# 模型定价（每百万tokens，美元）
MODEL_PRICING = {
    # Claude
    'claude-3-5-sonnet-20241022': {'input': 3.0, 'output': 15.0},
    'claude-3-haiku-20240307': {'input': 0.25, 'output': 1.25},
    'gemini-3-flash-preview': {'input': 0.075, 'output': 0.30},

    # OpenAI
    'gpt-4o': {'input': 2.5, 'output': 10.0},
    'gpt-4o-mini': {'input': 0.15, 'output': 0.6},

    # Local (free)
    'ollama': {'input': 0.0, 'output': 0.0},
}


class LLMProvider(ABC):
    """LLM提供商抽象基类"""

    @abstractmethod
    def call(
        self,
        messages: List[Dict[str, str]],
        model: str,
        temperature: float = 0.0,
        max_tokens: int = 4000,
        **kwargs
    ) -> Dict[str, Any]:
        """
        调用LLM

        Returns:
            {
                'content': '生成的文本',
                'input_tokens': 100,
                'output_tokens': 200,
                'model': 'gpt-4o'
            }
        """
        pass


class AnthropicProvider(LLMProvider):
    """Anthropic Claude提供商"""

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.environ.get('ANTHROPIC_API_KEY')
        if not self.api_key:
            raise ValueError("ANTHROPIC_API_KEY not set")

        try:
            import anthropic
            self.client = anthropic.Anthropic(api_key=self.api_key)
        except ImportError:
            raise ImportError("anthropic package not installed. Run: pip install anthropic")

    def call(
        self,
        messages: List[Dict[str, str]],
        model: str = 'claude-sonnet-4-6',
        temperature: float = 0.0,
        max_tokens: int = 4000,
        **kwargs
    ) -> Dict[str, Any]:
        """调用Claude API"""
        try:
            # Extract system message if present
            # Anthropic API requires system messages as top-level parameter
            system_message = None
            api_messages = []

            for msg in messages:
                if msg.get('role') == 'system':
                    # Take the last system message if multiple exist
                    system_message = msg['content']
                else:
                    api_messages.append(msg)

            # Build API call parameters
            api_params = {
                'model': model,
                'messages': api_messages,
                'max_tokens': max_tokens,
                'temperature': temperature,
            }

            # Add system parameter if system message exists
            if system_message:
                api_params['system'] = system_message

            # Add any additional kwargs
            api_params.update(kwargs)

            response = self.client.messages.create(**api_params)

            # 🔥 支持Tool Use API
            # 返回完整的content blocks（可能包含tool_use）
            content_blocks = []
            for block in response.content:
                if hasattr(block, 'type'):
                    if block.type == 'text':
                        content_blocks.append({
                            'type': 'text',
                            'text': block.text
                        })
                    elif block.type == 'tool_use':
                        content_blocks.append({
                            'type': 'tool_use',
                            'id': block.id,
                            'name': block.name,
                            'input': block.input
                        })
                else:
                    # 兼容旧版本（单纯文本）
                    content_blocks.append({
                        'type': 'text',
                        'text': block.text if hasattr(block, 'text') else str(block)
                    })

            return {
                'content': content_blocks,  # 返回content blocks数组
                'stop_reason': response.stop_reason,  # 🔥 关键：返回stop_reason
                'input_tokens': response.usage.input_tokens,
                'output_tokens': response.usage.output_tokens,
                'model': model,
            }
        except Exception as e:
            log.error(f"Anthropic API call failed: {e}")
            raise


class OpenAIProvider(LLMProvider):
    """OpenAI GPT提供商"""

    def __init__(self, api_key: Optional[str] = None):
        self.api_key = api_key or os.environ.get('OPENAI_API_KEY')
        if not self.api_key:
            raise ValueError("OPENAI_API_KEY not set")

        try:
            import openai
            self.client = openai.OpenAI(api_key=self.api_key)
        except ImportError:
            raise ImportError("openai package not installed. Run: pip install openai")

    def call(
        self,
        messages: List[Dict[str, str]],
        model: str = 'gpt-4o-mini',
        temperature: float = 0.0,
        max_tokens: int = 4000,
        **kwargs
    ) -> Dict[str, Any]:
        """调用OpenAI API"""
        try:
            response = self.client.chat.completions.create(
                model=model,
                messages=messages,
                max_tokens=max_tokens,
                temperature=temperature,
                **kwargs
            )

            return {
                'content': response.choices[0].message.content,
                'input_tokens': response.usage.prompt_tokens,
                'output_tokens': response.usage.completion_tokens,
                'model': model,
            }
        except Exception as e:
            log.error(f"OpenAI API call failed: {e}")
            raise


class OllamaProvider(LLMProvider):
    """本地Ollama提供商"""

    def __init__(self, base_url: str = "http://localhost:11434"):
        self.base_url = base_url

        try:
            import requests
            self.requests = requests
        except ImportError:
            raise ImportError("requests package not installed")

    def call(
        self,
        messages: List[Dict[str, str]],
        model: str = 'llama3',
        temperature: float = 0.0,
        max_tokens: int = 4000,
        **kwargs
    ) -> Dict[str, Any]:
        """调用Ollama本地API"""
        try:
            # 转换消息格式
            prompt = "\n".join([f"{msg['role']}: {msg['content']}" for msg in messages])

            response = self.requests.post(
                f"{self.base_url}/api/generate",
                json={
                    'model': model,
                    'prompt': prompt,
                    'temperature': temperature,
                    'stream': False,
                }
            )
            response.raise_for_status()

            result = response.json()

            return {
                'content': result.get('response', ''),
                'input_tokens': 0,  # Ollama不返回token统计
                'output_tokens': 0,
                'model': model,
            }
        except Exception as e:
            log.error(f"Ollama API call failed: {e}")
            raise


class LLMBudgetManager:
    """LLM预算管理器"""

    def __init__(self, daily_budget: float = 50.0):
        """
        Args:
            daily_budget: 每日预算（美元）
        """
        self.daily_budget = daily_budget
        self.spending_log: List[LLMUsageStats] = []
        self.today_spent = 0.0
        self.last_reset = datetime.now().date()

    def _reset_if_new_day(self):
        """如果是新的一天，重置计数"""
        today = datetime.now().date()
        if today > self.last_reset:
            log.info(f"Daily budget reset. Yesterday's spending: ${self.today_spent:.4f}")
            self.today_spent = 0.0
            self.last_reset = today
            # 清理旧日志（只保留7天）
            cutoff = datetime.now() - timedelta(days=7)
            self.spending_log = [s for s in self.spending_log if s.timestamp > cutoff]

    def can_afford(self, estimated_cost: float) -> bool:
        """
        检查是否在预算内

        Args:
            estimated_cost: 预估成本（美元）

        Returns:
            True if within budget
        """
        self._reset_if_new_day()
        return (self.today_spent + estimated_cost) <= self.daily_budget

    def record_usage(self, stats: LLMUsageStats):
        """记录使用情况"""
        self._reset_if_new_day()
        self.today_spent += stats.cost
        self.spending_log.append(stats)
        log.info(f"LLM call recorded: ${stats.cost:.4f} (today: ${self.today_spent:.4f}/{self.daily_budget})")

    def get_remaining_budget(self) -> float:
        """获取剩余预算"""
        self._reset_if_new_day()
        return max(0, self.daily_budget - self.today_spent)

    def get_today_stats(self) -> Dict[str, Any]:
        """获取今日统计"""
        self._reset_if_new_day()
        today_logs = [s for s in self.spending_log if s.timestamp.date() == self.last_reset]

        total_calls = len(today_logs)
        total_input_tokens = sum(s.input_tokens for s in today_logs)
        total_output_tokens = sum(s.output_tokens for s in today_logs)

        return {
            'date': self.last_reset.isoformat(),
            'total_calls': total_calls,
            'total_cost': self.today_spent,
            'budget': self.daily_budget,
            'remaining': self.get_remaining_budget(),
            'total_input_tokens': total_input_tokens,
            'total_output_tokens': total_output_tokens,
        }


class UnifiedLLMClient:
    """
    统一的LLM客户端

    自动处理：
    - 多提供商支持
    - 成本计算
    - 预算控制
    - 重试逻辑
    - 使用统计
    """

    def __init__(
        self,
        default_provider: Literal['anthropic', 'openai', 'ollama'] = 'anthropic',
        daily_budget: float = 50.0,
        enable_budget_control: bool = True
    ):
        """
        Args:
            default_provider: 默认提供商
            daily_budget: 每日预算（美元）
            enable_budget_control: 是否启用预算控制
        """
        self.default_provider = default_provider
        self.providers: Dict[str, LLMProvider] = {}
        self.budget_manager = LLMBudgetManager(daily_budget)
        self.enable_budget_control = enable_budget_control

        # 初始化提供商
        self._init_providers()

    def _init_providers(self):
        """初始化可用的提供商"""
        # 尝试初始化Anthropic
        try:
            self.providers['anthropic'] = AnthropicProvider()
            log.info("Anthropic provider initialized")
        except Exception as e:
            log.warning(f"Failed to initialize Anthropic: {e}")

        # 尝试初始化OpenAI
        try:
            self.providers['openai'] = OpenAIProvider()
            log.info("OpenAI provider initialized")
        except Exception as e:
            log.warning(f"Failed to initialize OpenAI: {e}")

        # 尝试初始化Ollama
        try:
            self.providers['ollama'] = OllamaProvider()
            log.info("Ollama provider initialized")
        except Exception as e:
            log.warning(f"Failed to initialize Ollama: {e}")

        if not self.providers:
            raise RuntimeError("No LLM providers available")

    def _estimate_cost(self, model: str, input_tokens: int, output_tokens: int) -> float:
        """估算成本"""
        if model not in MODEL_PRICING:
            log.warning(f"Unknown model {model}, using default pricing")
            pricing = {'input': 1.0, 'output': 5.0}
        else:
            pricing = MODEL_PRICING[model]

        input_cost = (input_tokens / 1_000_000) * pricing['input']
        output_cost = (output_tokens / 1_000_000) * pricing['output']

        return input_cost + output_cost

    def _count_tokens_rough(self, text: str) -> int:
        """粗略估算token数（用于预算检查）"""
        # 简单估算：1 token ≈ 4 characters
        return len(text) // 4

    def call(
        self,
        messages: List[Dict[str, str]],
        model: str = 'claude-sonnet-4-6',
        temperature: float = 0.0,
        max_tokens: int = 4000,
        provider: Optional[str] = None,
        retry: int = 3,
        **kwargs
    ) -> Dict[str, Any]:
        """
        调用LLM（统一接口）

        Args:
            messages: 对话消息列表
            model: 模型名称
            temperature: 温度参数
            max_tokens: 最大输出tokens
            provider: 指定提供商（默认自动选择）
            retry: 重试次数

        Returns:
            {
                'content': '生成的文本',
                'usage_stats': LLMUsageStats对象,
            }
        """
        start_time = time.time()

        # 选择提供商
        if provider is None:
            if 'claude' in model:
                provider = 'anthropic'
            elif 'gpt' in model:
                provider = 'openai'
            else:
                provider = self.default_provider

        if provider not in self.providers:
            raise ValueError(f"Provider {provider} not available")

        # 预算检查
        if self.enable_budget_control:
            # 粗略估算成本
            input_text = "\n".join([m['content'] for m in messages])
            estimated_input_tokens = self._count_tokens_rough(input_text)
            estimated_output_tokens = max_tokens // 2  # 假设输出一半
            estimated_cost = self._estimate_cost(model, estimated_input_tokens, estimated_output_tokens)

            if not self.budget_manager.can_afford(estimated_cost):
                remaining = self.budget_manager.get_remaining_budget()
                raise RuntimeError(
                    f"Budget exceeded! Remaining: ${remaining:.4f}, "
                    f"Estimated cost: ${estimated_cost:.4f}"
                )

        # 调用LLM（带重试）
        last_error = None
        for attempt in range(retry):
            try:
                result = self.providers[provider].call(
                    messages=messages,
                    model=model,
                    temperature=temperature,
                    max_tokens=max_tokens,
                    **kwargs
                )

                # 计算成本和统计
                duration = time.time() - start_time
                cost = self._estimate_cost(
                    result['model'],
                    result['input_tokens'],
                    result['output_tokens']
                )

                usage_stats = LLMUsageStats(
                    model=result['model'],
                    input_tokens=result['input_tokens'],
                    output_tokens=result['output_tokens'],
                    cost=cost,
                    duration=duration,
                )

                # 记录使用
                if self.enable_budget_control:
                    self.budget_manager.record_usage(usage_stats)

                return {
                    'content': result['content'],
                    'usage_stats': usage_stats,
                }

            except Exception as e:
                last_error = e
                log.warning(f"LLM call attempt {attempt + 1}/{retry} failed: {e}")
                if attempt < retry - 1:
                    time.sleep(2 ** attempt)  # 指数退避

        raise RuntimeError(f"LLM call failed after {retry} attempts: {last_error}")

    def get_budget_stats(self) -> Dict[str, Any]:
        """获取预算统计"""
        return self.budget_manager.get_today_stats()
