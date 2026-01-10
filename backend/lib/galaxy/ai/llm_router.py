"""
Hybrid LLM Router for Galaxy AI Assistant

Routes tasks to appropriate LLM providers based on task complexity,
cost considerations, and availability. Supports automatic fallback.
"""

import logging
import os
import re
from dataclasses import dataclass
from enum import Enum
from typing import Dict, Any, Optional, List

from .config import AIConfig
from .llm_client import LLMClient

log = logging.getLogger(__name__)


class TaskComplexity(Enum):
    """Task complexity levels for routing decisions."""
    TRIVIAL = "trivial"      # Simple formatting, yes/no, classification
    SIMPLE = "simple"        # Basic Q&A, simple extraction
    MODERATE = "moderate"    # Multi-step reasoning, summarization
    COMPLEX = "complex"      # Workflow generation, scientific analysis
    EXPERT = "expert"        # Deep reasoning, novel problem solving


class TaskType(Enum):
    """Types of tasks for specialized routing."""
    ROUTING = "routing"              # Intent classification, tool selection
    FORMATTING = "formatting"        # Text formatting, JSON structuring
    EXTRACTION = "extraction"        # Entity extraction, parsing
    SUMMARIZATION = "summarization"  # Document/result summarization
    REASONING = "reasoning"          # Multi-step logical reasoning
    WORKFLOW = "workflow"            # Workflow generation
    CODING = "coding"                # Code generation/analysis
    SCIENTIFIC = "scientific"        # Domain-specific scientific analysis
    CONVERSATION = "conversation"    # General chat, clarification
    VISION = "vision"                # Image/document understanding


@dataclass
class RoutingConfig:
    """Configuration for a single LLM provider in the routing table."""
    provider: str
    model: str
    api_key: Optional[str] = None
    base_url: Optional[str] = None
    priority: int = 0  # Lower = higher priority
    max_tokens: int = 4000
    supports_vision: bool = False
    supports_tools: bool = True
    cost_per_1m_input: float = 0.0  # $ per 1M input tokens
    cost_per_1m_output: float = 0.0  # $ per 1M output tokens


@dataclass
class RoutingDecision:
    """Result of routing decision."""
    provider: str
    model: str
    reason: str
    complexity: TaskComplexity
    task_type: TaskType
    fallback_chain: List[str]


# Default routing configurations
DEFAULT_ROUTING_TABLE: Dict[str, RoutingConfig] = {
    # Tier 1: Frontier models for complex tasks
    'claude-sonnet': RoutingConfig(
        provider='anthropic',
        model='claude-sonnet-4-5',
        priority=1,
        max_tokens=8192,
        supports_vision=True,
        supports_tools=True,
        cost_per_1m_input=3.0,
        cost_per_1m_output=15.0,
    ),
    'gemini-pro': RoutingConfig(
        provider='gemini',
        model='gemini-2.0-flash-exp',
        priority=1,
        max_tokens=8192,
        supports_vision=True,
        supports_tools=True,
        cost_per_1m_input=0.075,
        cost_per_1m_output=0.30,
    ),
    'glm-flagship': RoutingConfig(
        provider='zhipu',
        model='glm-4.7',
        priority=1,
        max_tokens=8192,
        supports_vision=False,
        supports_tools=True,
        cost_per_1m_input=0.60,
        cost_per_1m_output=2.20,
    ),

    # Tier 2: Strong local models - Qwen3-32B on ARM supercomputer (128GB memory)
    'qwen3-32b': RoutingConfig(
        provider='ollama',
        model='qwen3:32b',
        priority=1,  # Elevated to Tier 1 - powerful local model
        max_tokens=32768,  # Full 32K context with 128GB memory
        supports_vision=False,
        supports_tools=True,
        cost_per_1m_input=0.0,  # Local = free
        cost_per_1m_output=0.0,
    ),
    # FP16 variant for maximum quality
    'qwen3-32b-fp16': RoutingConfig(
        provider='ollama',
        model='qwen3:32b-fp16',
        priority=1,
        max_tokens=32768,
        supports_vision=False,
        supports_tools=True,
        cost_per_1m_input=0.0,
        cost_per_1m_output=0.0,
    ),
}


class HybridLLMRouter:
    """
    Intelligent router that selects the best LLM for each task.

    Routing strategy (optimized for ARM supercomputer with 128GB + Ollama):
    - TRIVIAL/SIMPLE/MODERATE → qwen3:32b local (free, fast)
    - COMPLEX → qwen3:32b with /think mode, fallback to Claude
    - EXPERT → Claude/Gemini for edge cases
    - VISION → Gemini or Claude (qwen3:32b doesn't support vision)
    - CODING → qwen3:32b (strong coding capabilities)
    """

    def __init__(
        self,
        routing_table: Optional[Dict[str, RoutingConfig]] = None,
        prefer_local: bool = True,
        cost_sensitive: bool = True,
    ):
        self.routing_table = routing_table or DEFAULT_ROUTING_TABLE
        self.prefer_local = prefer_local
        self.cost_sensitive = cost_sensitive
        self._clients: Dict[str, LLMClient] = {}
        self._available_providers: set = set()

        # Initialize and check available providers
        self._init_providers()

    def _init_providers(self):
        """Initialize LLM clients and check availability."""
        for name, config in self.routing_table.items():
            try:
                api_key = config.api_key or self._get_api_key(config.provider)

                # Skip if API key required but not available
                if config.provider not in ['ollama', 'local'] and not api_key:
                    log.debug(f"Skipping {name}: no API key for {config.provider}")
                    continue

                ai_config = AIConfig({
                    'llm_provider': config.provider,
                    'llm_model': config.model,
                    'llm_api_key': api_key,
                    'llm_base_url': config.base_url,
                })

                client = LLMClient(ai_config)
                self._clients[name] = client
                self._available_providers.add(name)
                log.info(f"Initialized LLM provider: {name} ({config.provider}/{config.model})")

            except Exception as e:
                log.warning(f"Failed to initialize {name}: {e}")

    def _get_api_key(self, provider: str) -> Optional[str]:
        """Get API key from environment for provider."""
        key_map = {
            'anthropic': 'ANTHROPIC_API_KEY',
            'gemini': 'GOOGLE_API_KEY',
            'google': 'GOOGLE_API_KEY',
            'openai': 'OPENAI_API_KEY',
            'deepseek': 'DEEPSEEK_API_KEY',
            'zhipu': 'ZHIPU_API_KEY',
        }
        env_var = key_map.get(provider)
        return os.getenv(env_var) if env_var else None

    def classify_task(self, prompt: str, context: Optional[Dict] = None) -> tuple[TaskComplexity, TaskType]:
        """
        Classify task complexity and type from prompt.

        Uses heuristics for fast classification without LLM call.
        """
        prompt_lower = prompt.lower()
        prompt_len = len(prompt)

        # Detect task type
        task_type = TaskType.CONVERSATION  # Default

        if any(kw in prompt_lower for kw in ['classify', 'which tool', 'select', 'route', 'choose']):
            task_type = TaskType.ROUTING
        elif any(kw in prompt_lower for kw in ['format', 'convert to json', 'structure', 'reformat']):
            task_type = TaskType.FORMATTING
        elif any(kw in prompt_lower for kw in ['extract', 'parse', 'find all', 'list the']):
            task_type = TaskType.EXTRACTION
        elif any(kw in prompt_lower for kw in ['summarize', 'summary', 'tldr', 'brief']):
            task_type = TaskType.SUMMARIZATION
        elif any(kw in prompt_lower for kw in ['workflow', 'pipeline', 'steps to', 'process for']):
            task_type = TaskType.WORKFLOW
        elif any(kw in prompt_lower for kw in ['code', 'function', 'implement', 'script', 'program']):
            task_type = TaskType.CODING
        elif any(kw in prompt_lower for kw in [
            'analyze', 'gene', 'protein', 'sequence', 'alignment', 'expression',
            'pathway', 'mutation', 'variant', 'genome', 'transcriptome'
        ]):
            task_type = TaskType.SCIENTIFIC
        elif any(kw in prompt_lower for kw in ['image', 'picture', 'figure', 'plot', 'visual']):
            task_type = TaskType.VISION
        elif any(kw in prompt_lower for kw in ['reason', 'explain why', 'because', 'therefore', 'conclude']):
            task_type = TaskType.REASONING

        # Detect complexity
        complexity = TaskComplexity.SIMPLE  # Default

        # Trivial: Very short, simple classification
        if prompt_len < 100 and task_type in [TaskType.ROUTING, TaskType.FORMATTING]:
            complexity = TaskComplexity.TRIVIAL

        # Simple: Short prompts, basic tasks
        elif prompt_len < 300 and task_type in [TaskType.EXTRACTION, TaskType.FORMATTING, TaskType.CONVERSATION]:
            complexity = TaskComplexity.SIMPLE

        # Moderate: Medium length, summarization, basic reasoning
        elif prompt_len < 1000 and task_type in [TaskType.SUMMARIZATION, TaskType.REASONING]:
            complexity = TaskComplexity.MODERATE

        # Complex: Workflow, coding, scientific analysis
        elif task_type in [TaskType.WORKFLOW, TaskType.CODING, TaskType.SCIENTIFIC]:
            complexity = TaskComplexity.COMPLEX

        # Expert: Long prompts with complex scientific tasks
        elif prompt_len > 2000 and task_type == TaskType.SCIENTIFIC:
            complexity = TaskComplexity.EXPERT

        # Vision tasks are at least moderate
        elif task_type == TaskType.VISION:
            complexity = TaskComplexity.MODERATE

        # Long prompts generally need more capable models
        elif prompt_len > 1500:
            complexity = TaskComplexity.MODERATE

        return complexity, task_type

    def route(
        self,
        prompt: str,
        context: Optional[Dict] = None,
        require_vision: bool = False,
        require_tools: bool = False,
        force_provider: Optional[str] = None,
    ) -> RoutingDecision:
        """
        Route task to the most appropriate LLM.

        Args:
            prompt: The task prompt
            context: Optional context (e.g., conversation history)
            require_vision: If True, only consider vision-capable models
            require_tools: If True, only consider tool-capable models
            force_provider: Force a specific provider (bypasses routing)

        Returns:
            RoutingDecision with selected provider and reasoning
        """
        complexity, task_type = self.classify_task(prompt, context)

        # If forced, use that provider
        if force_provider and force_provider in self._available_providers:
            config = self.routing_table[force_provider]
            return RoutingDecision(
                provider=config.provider,
                model=config.model,
                reason=f"Forced provider: {force_provider}",
                complexity=complexity,
                task_type=task_type,
                fallback_chain=self._build_fallback_chain(force_provider),
            )

        # Filter available providers by requirements
        candidates = []
        for name in self._available_providers:
            config = self.routing_table[name]

            if require_vision and not config.supports_vision:
                continue
            if require_tools and not config.supports_tools:
                continue

            candidates.append((name, config))

        if not candidates:
            raise ValueError("No available LLM providers match requirements")

        # Select based on complexity and preferences
        selected = self._select_provider(candidates, complexity, task_type)
        config = self.routing_table[selected]

        return RoutingDecision(
            provider=config.provider,
            model=config.model,
            reason=self._explain_routing(selected, complexity, task_type),
            complexity=complexity,
            task_type=task_type,
            fallback_chain=self._build_fallback_chain(selected),
        )

    def _select_provider(
        self,
        candidates: List[tuple[str, RoutingConfig]],
        complexity: TaskComplexity,
        task_type: TaskType,
    ) -> str:
        """Select the best provider from candidates.

        Optimized for ARM supercomputer with local Ollama qwen3:32b.
        Local model is preferred for most tasks due to zero cost and low latency.
        """

        # Score each candidate
        scores = []
        for name, config in candidates:
            score = 0

            # Strong preference for local Ollama (qwen3:32b)
            is_local_qwen = config.provider == 'ollama' and 'qwen3' in config.model

            # Complexity matching - favor local for most cases
            if complexity == TaskComplexity.TRIVIAL:
                if is_local_qwen:
                    score += 100  # Strongly prefer local
                elif config.cost_per_1m_input == 0:
                    score += 50
                elif config.cost_per_1m_input < 1.0:
                    score += 30

            elif complexity == TaskComplexity.SIMPLE:
                if is_local_qwen:
                    score += 100  # Strongly prefer local
                elif config.cost_per_1m_input == 0:
                    score += 40
                elif config.cost_per_1m_input < 1.0:
                    score += 25

            elif complexity == TaskComplexity.MODERATE:
                if is_local_qwen:
                    score += 80  # Still prefer local
                elif config.priority == 1:
                    score += 30

            elif complexity == TaskComplexity.COMPLEX:
                # Complex tasks: local qwen3 with /think, or frontier models
                if is_local_qwen:
                    score += 60  # Local qwen3 with /think mode is powerful
                elif config.priority == 1:
                    score += 50

            elif complexity == TaskComplexity.EXPERT:
                # Expert tasks: prefer frontier models, but local is still good
                if is_local_qwen:
                    score += 40  # Still viable with /think mode
                elif config.provider == 'anthropic':
                    score += 60  # Claude for expert scientific reasoning
                elif config.priority == 1:
                    score += 50

            # Task type bonuses
            if task_type == TaskType.CODING:
                if is_local_qwen:
                    score += 30  # Qwen3-32B is excellent at coding
                elif 'glm' in config.model.lower():
                    score += 25  # GLM-4.7 also excels at coding

            if task_type == TaskType.SCIENTIFIC:
                if is_local_qwen:
                    score += 20  # Good for most scientific tasks
                elif config.provider == 'anthropic':
                    score += 25  # Claude for complex scientific reasoning

            if task_type == TaskType.WORKFLOW:
                if is_local_qwen:
                    score += 20  # Can handle workflow generation
                elif config.provider in ['anthropic', 'gemini']:
                    score += 30  # Frontier models for complex workflows

            # Local preference bonus
            if self.prefer_local and config.cost_per_1m_input == 0:
                score += 25  # Strong preference for local

            # Cost sensitivity
            if self.cost_sensitive:
                # Penalize expensive models for non-expert tasks
                if complexity != TaskComplexity.EXPERT:
                    score -= int(config.cost_per_1m_input * 3)

            scores.append((name, score))

        # Sort by score (highest first)
        scores.sort(key=lambda x: x[1], reverse=True)
        return scores[0][0]

    def _build_fallback_chain(self, primary: str) -> List[str]:
        """Build fallback chain for a primary provider."""
        chain = []
        primary_config = self.routing_table[primary]

        # Add providers in priority order, excluding primary
        sorted_providers = sorted(
            [(n, c) for n, c in self.routing_table.items() if n != primary and n in self._available_providers],
            key=lambda x: x[1].priority
        )

        for name, config in sorted_providers:
            # Ensure fallbacks have similar capabilities
            if primary_config.supports_vision and not config.supports_vision:
                continue
            chain.append(name)
            if len(chain) >= 3:
                break

        return chain

    def _explain_routing(self, selected: str, complexity: TaskComplexity, task_type: TaskType) -> str:
        """Generate human-readable explanation for routing decision."""
        config = self.routing_table[selected]

        reasons = []

        if complexity in [TaskComplexity.TRIVIAL, TaskComplexity.SIMPLE]:
            if config.cost_per_1m_input == 0:
                reasons.append("using local model for cost efficiency")
            else:
                reasons.append("using fast model for simple task")
        elif complexity == TaskComplexity.EXPERT:
            reasons.append("using frontier model for expert-level reasoning")
        else:
            reasons.append(f"matched {complexity.value} complexity")

        reasons.append(f"task type: {task_type.value}")

        if config.cost_per_1m_input == 0:
            reasons.append("zero API cost")

        return f"Selected {config.provider}/{config.model}: " + ", ".join(reasons)

    async def generate(
        self,
        prompt: str,
        context: Optional[Dict] = None,
        require_vision: bool = False,
        require_tools: bool = False,
        force_provider: Optional[str] = None,
        **kwargs
    ) -> tuple[str, RoutingDecision]:
        """
        Route and generate response.

        Returns:
            Tuple of (response_text, routing_decision)
        """
        decision = self.route(
            prompt=prompt,
            context=context,
            require_vision=require_vision,
            require_tools=require_tools,
            force_provider=force_provider,
        )

        # Find the client
        client_key = None
        for name, config in self.routing_table.items():
            if config.provider == decision.provider and config.model == decision.model:
                client_key = name
                break

        if not client_key or client_key not in self._clients:
            raise ValueError(f"No client for {decision.provider}/{decision.model}")

        client = self._clients[client_key]

        # Try primary, then fallbacks
        last_error = None
        tried = [client_key]

        try:
            # Enable thinking mode for complex tasks with Qwen3
            if decision.complexity in [TaskComplexity.COMPLEX, TaskComplexity.EXPERT]:
                kwargs['use_thinking'] = True

            response = await client.generate_async(prompt, **kwargs)
            log.info(f"Generated response using {decision.provider}/{decision.model}")
            return response, decision

        except Exception as e:
            last_error = e
            log.warning(f"Primary provider {client_key} failed: {e}")

        # Try fallbacks
        for fallback_name in decision.fallback_chain:
            if fallback_name in tried:
                continue
            tried.append(fallback_name)

            try:
                fallback_client = self._clients.get(fallback_name)
                if not fallback_client:
                    continue

                response = await fallback_client.generate_async(prompt, **kwargs)
                fallback_config = self.routing_table[fallback_name]
                log.info(f"Fallback succeeded using {fallback_config.provider}/{fallback_config.model}")

                # Update decision to reflect actual provider used
                decision.provider = fallback_config.provider
                decision.model = fallback_config.model
                decision.reason += f" (fallback from {client_key})"

                return response, decision

            except Exception as e:
                log.warning(f"Fallback {fallback_name} failed: {e}")
                last_error = e

        raise RuntimeError(f"All providers failed. Last error: {last_error}")

    def get_available_providers(self) -> Dict[str, Dict[str, Any]]:
        """Get information about available providers."""
        result = {}
        for name in self._available_providers:
            config = self.routing_table[name]
            result[name] = {
                'provider': config.provider,
                'model': config.model,
                'priority': config.priority,
                'supports_vision': config.supports_vision,
                'supports_tools': config.supports_tools,
                'cost_per_1m_input': config.cost_per_1m_input,
                'cost_per_1m_output': config.cost_per_1m_output,
                'local': config.cost_per_1m_input == 0,
            }
        return result


# Convenience function for quick routing
def create_hybrid_router(
    prefer_local: bool = True,
    cost_sensitive: bool = True,
    custom_routing: Optional[Dict[str, RoutingConfig]] = None,
) -> HybridLLMRouter:
    """
    Create a hybrid LLM router with default or custom configuration.

    Args:
        prefer_local: Prefer local models when appropriate
        cost_sensitive: Consider API costs in routing
        custom_routing: Custom routing table to merge with defaults

    Returns:
        Configured HybridLLMRouter instance
    """
    routing_table = DEFAULT_ROUTING_TABLE.copy()
    if custom_routing:
        routing_table.update(custom_routing)

    return HybridLLMRouter(
        routing_table=routing_table,
        prefer_local=prefer_local,
        cost_sensitive=cost_sensitive,
    )
