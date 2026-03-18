"""
Base classes for AutoFix Tool System
"""

import logging
from abc import ABC, abstractmethod
from typing import Dict, Any, List, Optional
from dataclasses import dataclass

log = logging.getLogger(__name__)


class ToolExecutionError(Exception):
    """工具执行错误"""
    pass


@dataclass
class ToolResult:
    """工具执行结果"""
    success: bool
    output: str
    error: Optional[str] = None
    metadata: Optional[Dict[str, Any]] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            'success': self.success,
            'output': self.output,
            'error': self.error,
            'metadata': self.metadata or {}
        }


class BaseTool(ABC):
    """
    工具基类

    所有工具都需要实现：
    1. name: 工具名称
    2. description: 工具描述（给LLM看）
    3. parameters_schema: 参数定义（JSON Schema格式）
    4. execute(): 执行逻辑
    """

    name: str = "base_tool"
    description: str = "Base tool"

    @abstractmethod
    def get_parameters_schema(self) -> Dict[str, Any]:
        """
        返回工具参数的JSON Schema

        Example:
        {
            "type": "object",
            "properties": {
                "file_path": {
                    "type": "string",
                    "description": "Path to the file"
                }
            },
            "required": ["file_path"]
        }
        """
        pass

    @abstractmethod
    def execute(self, **kwargs) -> ToolResult:
        """
        执行工具

        Args:
            **kwargs: 工具参数（根据parameters_schema定义）

        Returns:
            ToolResult: 执行结果
        """
        pass

    def to_anthropic_tool(self) -> Dict[str, Any]:
        """
        转换为Anthropic Tool Use API格式

        https://docs.anthropic.com/en/docs/tool-use
        """
        return {
            "name": self.name,
            "description": self.description,
            "input_schema": self.get_parameters_schema()
        }

    def validate_parameters(self, params: Dict[str, Any]) -> bool:
        """验证参数（简单版本）"""
        schema = self.get_parameters_schema()
        required = schema.get('required', [])

        for req_param in required:
            if req_param not in params:
                raise ToolExecutionError(f"Missing required parameter: {req_param}")

        return True
