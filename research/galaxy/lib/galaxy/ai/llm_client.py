"""
LLM Client for Galaxy AI Assistant

Supports multiple LLM providers: OpenAI, Anthropic Claude, and local models.
"""

import json
import logging
import httpx
from typing import Dict, Any, Optional
from .config import AIConfig

log = logging.getLogger(__name__)


class LLMClient:
    """Universal LLM client supporting multiple providers."""
    
    def __init__(self, config: AIConfig):
        self.config = config
        self.provider = config.llm_provider.lower()
        self.model = config.llm_model
        self.api_key = config.llm_api_key
        self.base_url = config.llm_base_url
        
        # Initialize provider-specific settings
        self._setup_provider()
        
    def _setup_provider(self):
        """Setup provider-specific configurations."""
        if self.provider == 'openai':
            self.api_base = self.base_url or "https://api.openai.com/v1"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
        elif self.provider == 'anthropic':
            self.api_base = self.base_url or "https://api.anthropic.com"
            self.headers = {
                "x-api-key": self.api_key,
                "Content-Type": "application/json",
                "anthropic-version": "2023-06-01"
            }
            
        elif self.provider == 'qwen':  # 通义千问
            self.api_base = self.base_url or "https://dashscope.aliyuncs.com/compatible-mode/v1"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
        elif self.provider == 'zhipu':  # 智谱AI (GLM)
            self.api_base = self.base_url or "https://open.bigmodel.cn/api/paas/v4"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
        elif self.provider == 'baichuan':  # 百川
            self.api_base = self.base_url or "https://api.baichuan-ai.com/v1"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
        elif self.provider == 'moonshot':  # 月之暗面 Kimi
            self.api_base = self.base_url or "https://api.moonshot.cn/v1"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
        elif self.provider == 'deepseek':  # 深度求索
            self.api_base = self.base_url or "https://api.deepseek.com/v1"
            self.headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            
        elif self.provider == 'local':
            # For local models (e.g., Ollama, LM Studio)
            self.api_base = self.base_url or "http://localhost:1234/v1"
            self.headers = {
                "Content-Type": "application/json"
            }
            if self.api_key:
                self.headers["Authorization"] = f"Bearer {self.api_key}"
                
        else:
            raise ValueError(f"Unsupported LLM provider: {self.provider}")
    
    async def generate_async(self, prompt: str, **kwargs) -> str:
        """Generate response asynchronously."""
        try:
            if self.provider == 'openai':
                return await self._generate_openai(prompt, **kwargs)
            elif self.provider == 'anthropic':
                return await self._generate_anthropic(prompt, **kwargs)
            elif self.provider in ['qwen', 'zhipu', 'baichuan', 'moonshot', 'deepseek']:
                # 国内模型大多使用OpenAI兼容API
                return await self._generate_openai_compatible(prompt, **kwargs)
            elif self.provider == 'local':
                return await self._generate_local(prompt, **kwargs)
            else:
                raise ValueError(f"Unsupported provider: {self.provider}")
                
        except Exception as e:
            log.error(f"LLM generation failed: {e}")
            raise
    
    def generate(self, prompt: str, **kwargs) -> str:
        """Synchronous wrapper for generate_async."""
        import asyncio
        
        try:
            # Check if we're already in an event loop
            loop = asyncio.get_event_loop()
            if loop.is_running():
                # Create a new thread for the async call
                import threading
                import concurrent.futures
                
                def run_async():
                    new_loop = asyncio.new_event_loop()
                    asyncio.set_event_loop(new_loop)
                    try:
                        return new_loop.run_until_complete(self.generate_async(prompt, **kwargs))
                    finally:
                        new_loop.close()
                
                with concurrent.futures.ThreadPoolExecutor() as executor:
                    future = executor.submit(run_async)
                    return future.result(timeout=600)
            else:
                return loop.run_until_complete(self.generate_async(prompt, **kwargs))
        except:
            # Fallback: create new event loop
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            try:
                return loop.run_until_complete(self.generate_async(prompt, **kwargs))
            finally:
                loop.close()
    
    async def _generate_openai(self, prompt: str, **kwargs) -> str:
        """Generate using OpenAI API."""
        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": kwargs.get('max_tokens', 1000),
            "temperature": kwargs.get('temperature', 0.3)
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=30.0
            )
            
            if response.status_code == 200:
                result = response.json()
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"OpenAI API error: {response.status_code} {response.text}")
    
    async def _generate_anthropic(self, prompt: str, **kwargs) -> str:
        """Generate using Anthropic Claude API."""
        data = {
            "model": self.model,
            "max_tokens": kwargs.get('max_tokens', 1000),
            "messages": [
                {
                    "role": "user", 
                    "content": f"You are a helpful bioinformatics assistant. {prompt}"
                }
            ]
        }
        
        # Add temperature if provided
        temperature = kwargs.get('temperature', 0.3)
        if temperature:
            data["temperature"] = temperature
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/v1/messages",
                headers=self.headers,
                json=data,
                timeout=30.0
            )
            
            if response.status_code == 200:
                result = response.json()
                return result['content'][0]['text'].strip()
            else:
                raise Exception(f"Anthropic API error: {response.status_code} {response.text}")
    
    async def _generate_openai_compatible(self, prompt: str, **kwargs) -> str:
        """Generate using OpenAI-compatible APIs (for Chinese models)."""
        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant. Please respond in Chinese when appropriate."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": kwargs.get('max_tokens', 1000),
            "temperature": kwargs.get('temperature', 0.3)
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=30.0
            )
            
            if response.status_code == 200:
                result = response.json()
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"{self.provider.upper()} API error: {response.status_code} {response.text}")

    async def _generate_local(self, prompt: str, **kwargs) -> str:
        """Generate using local model API (compatible with OpenAI format)."""
        data = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": "You are a helpful bioinformatics assistant."},
                {"role": "user", "content": prompt}
            ],
            "max_tokens": kwargs.get('max_tokens', 1000),
            "temperature": kwargs.get('temperature', 0.3)
        }
        
        async with httpx.AsyncClient() as client:
            response = await client.post(
                f"{self.api_base}/chat/completions",
                headers=self.headers,
                json=data,
                timeout=30.0
            )
            
            if response.status_code == 200:
                result = response.json()
                return result['choices'][0]['message']['content'].strip()
            else:
                raise Exception(f"Local model API error: {response.status_code} {response.text}")
    
    def generate_structured(self, prompt: str, schema: Optional[Dict[str, Any]] = None, **kwargs) -> str:
        """Generate structured response for tool recommendation and workflow generation."""
        try:
            # Add structured output instruction to the prompt
            structured_prompt = prompt
            if schema:
                structured_prompt += f"\n\nPlease format your response as JSON according to this schema: {json.dumps(schema)}"
            else:
                structured_prompt += "\n\nPlease provide a clear, structured response."
            
            return self.generate(structured_prompt, **kwargs)
        except Exception as e:
            log.error(f"Structured generation failed: {e}")
            # Fallback to regular generation
            return self.generate(prompt, **kwargs)
    
    async def generate_structured_async(self, prompt: str, schema: Optional[Dict[str, Any]] = None, **kwargs) -> str:
        """Generate structured response asynchronously."""
        try:
            # Add structured output instruction to the prompt
            structured_prompt = prompt
            if schema:
                structured_prompt += f"\n\nPlease format your response as JSON according to this schema: {json.dumps(schema)}"
            else:
                structured_prompt += "\n\nPlease provide a clear, structured response."
            
            return await self.generate_async(structured_prompt, **kwargs)
        except Exception as e:
            log.error(f"Structured generation failed: {e}")
            # Fallback to regular generation
            return await self.generate_async(prompt, **kwargs)

    def test_connection(self) -> Dict[str, Any]:
        """Test connection to the LLM provider."""
        try:
            test_prompt = "Hello! Please respond with 'Connection successful' if you receive this message."
            response = self.generate(test_prompt)
            
            return {
                "success": True,
                "provider": self.provider,
                "model": self.model,
                "response": response[:100] + "..." if len(response) > 100 else response
            }
        except Exception as e:
            return {
                "success": False,
                "provider": self.provider,
                "model": self.model,
                "error": str(e)
            }


# Provider-specific model mappings

# OpenAI 模型
OPENAI_MODELS = [
    "gpt-4o",                        # 最新多模态模型
    "gpt-4",                         # 高性能通用模型  
    "gpt-4-turbo",                   # 优化版GPT-4
    "gpt-3.5-turbo"                  # 经济实用选择
]

# Anthropic Claude 模型
CLAUDE_MODELS = [
    "claude-3-5-sonnet-20241022",    # 最新且最强大
    "claude-3-5-haiku-20241022",     # 最快
    "claude-3-opus-20240229",        # 最智能但较慢
    "claude-3-sonnet-20240229",      # 平衡性能
    "claude-3-haiku-20240307"        # 快速且经济
]

# 通义千问模型 (阿里巴巴)
QWEN_MODELS = [
    "qwen-max",                      # 最强模型 (推荐)
    "qwen-max-1201",                 # 12月最新版本
    "qwen-plus",                     # 平衡性价比
    "qwen-turbo",                    # 快速响应
    "qwen-long",                     # 长文本处理
]

# 智谱AI GLM模型
ZHIPU_MODELS = [
    "glm-4-plus",                    # 最强版本
    "glm-4",                         # 标准版本 (推荐)
    "glm-4-air",                     # 轻量版本
    "glm-4-airx",                    # 超快版本
    "glm-4-flash",                   # 闪电版本
]

# 百川模型
BAICHUAN_MODELS = [
    "baichuan2-turbo",               # Turbo版本 (推荐)
    "baichuan2-turbo-192k",          # 长上下文版本
    "baichuan2-53b",                 # 53B参数版本
]

# 月之暗面 Kimi 模型
MOONSHOT_MODELS = [
    "moonshot-v1-128k",              # 128K上下文 (推荐)
    "moonshot-v1-32k",               # 32K上下文
    "moonshot-v1-8k",                # 8K上下文
]

# 深度求索模型
DEEPSEEK_MODELS = [
    "deepseek-chat",                 # 通用对话模型 (推荐)
    "deepseek-coder",                # 代码专用模型
]

# 本地模型
LOCAL_MODELS = [
    "llama3",                        # Llama 3
    "llama3.1",                      # Llama 3.1
    "qwen2",                         # 通义千问本地版
    "chatglm3",                      # ChatGLM3
    "baichuan2",                     # 百川2本地版
]


def get_recommended_model(provider: str) -> str:
    """Get recommended model for provider."""
    recommendations = {
        'openai': 'gpt-4o',
        'anthropic': 'claude-3-5-sonnet-20241022', 
        'qwen': 'qwen-max',                        # 通义千问推荐
        'zhipu': 'glm-4',                          # 智谱AI推荐  
        'baichuan': 'baichuan2-turbo',             # 百川推荐
        'moonshot': 'moonshot-v1-128k',            # Kimi推荐
        'deepseek': 'deepseek-chat',               # DeepSeek推荐
        'local': 'llama3.1'                       # 本地模型推荐
    }
    
    return recommendations.get(provider.lower(), 'gpt-4')


def get_provider_models(provider: str) -> list:
    """Get available models for a specific provider."""
    model_maps = {
        'openai': OPENAI_MODELS,
        'anthropic': CLAUDE_MODELS,
        'qwen': QWEN_MODELS,
        'zhipu': ZHIPU_MODELS, 
        'baichuan': BAICHUAN_MODELS,
        'moonshot': MOONSHOT_MODELS,
        'deepseek': DEEPSEEK_MODELS,
        'local': LOCAL_MODELS
    }
    
    return model_maps.get(provider.lower(), [])


def get_all_providers() -> Dict[str, Dict[str, Any]]:
    """Get information about all supported providers."""
    return {
        'openai': {
            'name': 'OpenAI',
            'models': OPENAI_MODELS,
            'recommended': 'gpt-4o',
            'api_key_required': True,
            'description': '国际领先的AI模型，功能强大'
        },
        'anthropic': {
            'name': 'Anthropic Claude', 
            'models': CLAUDE_MODELS,
            'recommended': 'claude-3-5-sonnet-20241022',
            'api_key_required': True,
            'description': '安全可靠的AI助手，理解能力强'
        },
        'qwen': {
            'name': '通义千问 (阿里巴巴)',
            'models': QWEN_MODELS, 
            'recommended': 'qwen-max',
            'api_key_required': True,
            'description': '阿里云出品，中文理解优秀，性价比高'
        },
        'zhipu': {
            'name': '智谱AI GLM',
            'models': ZHIPU_MODELS,
            'recommended': 'glm-4', 
            'api_key_required': True,
            'description': '清华系AI公司，中英文双语能力强'
        },
        'baichuan': {
            'name': '百川智能',
            'models': BAICHUAN_MODELS,
            'recommended': 'baichuan2-turbo',
            'api_key_required': True, 
            'description': '搜狗创始人创立，中文NLP技术领先'
        },
        'moonshot': {
            'name': '月之暗面 Kimi',
            'models': MOONSHOT_MODELS,
            'recommended': 'moonshot-v1-128k',
            'api_key_required': True,
            'description': '长文本处理能力出众，上下文理解强'
        },
        'deepseek': {
            'name': '深度求索 DeepSeek',
            'models': DEEPSEEK_MODELS,
            'recommended': 'deepseek-chat',
            'api_key_required': True,
            'description': '深度学习专家团队，推理能力强'
        },
        'local': {
            'name': '本地模型',
            'models': LOCAL_MODELS,
            'recommended': 'llama3.1',
            'api_key_required': False,
            'description': '本地部署，数据安全，无网络依赖'
        }
    }