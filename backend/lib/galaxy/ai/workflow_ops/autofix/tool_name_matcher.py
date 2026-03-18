"""
Tool Name Matcher - 灵活的工具名称匹配策略

支持多层匹配：
1. 硬匹配映射表（快速精确）
2. 数据库模糊匹配（智能覆盖）
3. 正则表达式提取（动态灵活）
4. Fallback（兜底）
"""

import re
import logging
from typing import Optional, Dict, Any

log = logging.getLogger(__name__)


class ToolNameMatcher:
    """工具名称智能匹配器"""

    # Level 1: 硬匹配映射表（可以配置化，支持动态更新）
    HARD_MAPPING = {
        # nf-core workflows
        'nf-core-rnaseq': 'nfcore/rnaseq',
        'nf-core-clipseq': 'nfcore/clipseq',
        'nf-core-atacseq': 'nfcore/atacseq',
        'nf-core-chipseq': 'nfcore/chipseq',
        'nf-core-scrnaseq': 'nfcore/scrnaseq',
        'nf-core-sarek': 'nfcore/sarek',
        'nf-core-methylseq': 'nfcore/methylseq',
        'nf-core-nanoseq': 'nfcore/nanoseq',

        # 常见变体
        'nfcore-rnaseq': 'nfcore/rnaseq',
        'nfcore_rnaseq': 'nfcore/rnaseq',
        'nf_core_rnaseq': 'nfcore/rnaseq',

        # clipseq 带版本号的变体
        'clipseq': 'nfcore/clipseq',
        'clipseq_v2': 'nfcore/clipseq',
        'clipseq_v1': 'nfcore/clipseq',

        # 可以继续添加...
    }

    # Level 3: 正则表达式模式（动态提取）
    REGEX_PATTERNS = [
        # nf-core workflows: "nf-core-PIPELINE" or "nfcore-PIPELINE"
        (r'nf[-_]?core[-_](\w+)', r'nfcore/\1'),

        # Galaxy Tool Shed: "toolshed.g2.bx.psu.edu/repos/OWNER/TOOL"
        (r'toolshed\.g2\.bx\.psu\.edu/repos/\w+/(\w+)', r'\1'),

        # 直接的工具名: "tool_name_v1.2.3"
        (r'^(\w+)(?:_v?\d+\.?\d*\.?\d*)?$', r'\1'),
    ]

    def __init__(self, db_connection=None):
        """
        初始化匹配器

        Args:
            db_connection: SQLite 数据库连接（用于模糊匹配）
        """
        self.conn = db_connection

    def match(self, workflow_name: str) -> Dict[str, Any]:
        """
        多层匹配工具名称

        Args:
            workflow_name: Workflow 名称

        Returns:
            {
                'tool_id': str,           # 匹配到的工具 ID
                'confidence': float,      # 置信度 0-1
                'method': str,            # 匹配方法
                'original': str           # 原始名称
            }
        """
        original_name = workflow_name
        workflow_name_clean = self._normalize(workflow_name)

        log.info(f"🔍 Matching workflow: '{original_name}'")
        log.info(f"   Normalized: '{workflow_name_clean}'")

        # Level 1: 硬匹配
        result = self._hard_match(workflow_name_clean)
        if result:
            result['original'] = original_name
            return result

        # Level 2: 数据库模糊匹配
        if self.conn:
            result = self._fuzzy_match_db(workflow_name_clean)
            if result:
                result['original'] = original_name
                return result

        # Level 3: 正则表达式动态提取
        result = self._regex_extract(workflow_name_clean)
        if result:
            result['original'] = original_name
            return result

        # Level 4: Fallback
        log.info(f"   ℹ️  No match found, using original name")
        return {
            'tool_id': workflow_name_clean,
            'confidence': 0.3,
            'method': 'fallback',
            'original': original_name
        }

    def _normalize(self, name: str) -> str:
        """
        标准化名称（去除噪音）

        Examples:
            "nf-core-scrnaseq (Engine & Satellites) (imported...)" → "nf-core-scrnaseq"
            "My Workflow v1.2.3" → "my workflow v1.2.3"
        """
        # 转小写
        name = name.lower()

        # 移除括号内容
        name = re.sub(r'\([^)]*\)', '', name)

        # 移除多余空格
        name = name.strip()

        return name

    def _hard_match(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Level 1: 硬匹配映射表

        Returns:
            匹配结果或 None
        """
        # 精确匹配
        if name in self.HARD_MAPPING:
            tool_id = self.HARD_MAPPING[name]
            log.info(f"   ✅ Level 1 (Hard Match): '{name}' → '{tool_id}'")
            return {
                'tool_id': tool_id,
                'confidence': 1.0,
                'method': 'hard_mapping'
            }

        # 部分匹配（去掉空格、下划线等）
        name_normalized = name.replace(' ', '').replace('_', '-')
        if name_normalized in self.HARD_MAPPING:
            tool_id = self.HARD_MAPPING[name_normalized]
            log.info(f"   ✅ Level 1 (Hard Match - Normalized): '{name}' → '{tool_id}'")
            return {
                'tool_id': tool_id,
                'confidence': 0.95,
                'method': 'hard_mapping_normalized'
            }

        return None

    def _fuzzy_match_db(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Level 2: 数据库模糊匹配

        使用 SQL LIKE 在数据库中查找相似工具

        Returns:
            匹配结果或 None
        """
        try:
            # 提取关键词（去掉常见前缀和后缀）
            keywords = self._extract_keywords(name)

            if not keywords:
                return None

            # 在数据库中搜索
            for keyword in keywords:
                cursor = self.conn.execute("""
                    SELECT tool_id, name
                    FROM tools
                    WHERE LOWER(tool_id) LIKE ?
                       OR LOWER(name) LIKE ?
                    LIMIT 1
                """, (f'%{keyword}%', f'%{keyword}%'))

                row = cursor.fetchone()
                if row:
                    tool_id = row['tool_id']
                    log.info(f"   ✅ Level 2 (Fuzzy DB): '{name}' → '{tool_id}' (keyword: {keyword})")
                    return {
                        'tool_id': tool_id,
                        'confidence': 0.85,
                        'method': 'fuzzy_db_match',
                        'keyword': keyword
                    }

        except Exception as e:
            log.warning(f"   ⚠️  Level 2 failed: {e}")

        return None

    def _extract_keywords(self, name: str) -> list:
        """
        从名称中提取关键词

        Examples:
            "nf-core-scrnaseq" → ["scrnaseq", "nf-core-scrnaseq"]
            "chip-seq analysis" → ["chipseq", "chip"]
        """
        keywords = []

        # 移除常见前缀
        name_clean = name
        for prefix in ['nf-core-', 'nfcore-', 'nf_core_', 'galaxy-']:
            if name_clean.startswith(prefix):
                keyword = name_clean[len(prefix):]
                keywords.append(keyword.split()[0])  # 第一个词

        # 添加完整名称
        keywords.append(name_clean.split()[0])  # 第一个词

        # 去重
        keywords = list(set(keywords))

        return keywords

    def _regex_extract(self, name: str) -> Optional[Dict[str, Any]]:
        """
        Level 3: 正则表达式动态提取

        使用预定义的正则模式提取工具名

        Returns:
            匹配结果或 None
        """
        for pattern, replacement in self.REGEX_PATTERNS:
            match = re.search(pattern, name, re.IGNORECASE)
            if match:
                tool_id = re.sub(pattern, replacement, name, flags=re.IGNORECASE)
                log.info(f"   ✅ Level 3 (Regex): '{name}' → '{tool_id}' (pattern: {pattern})")
                return {
                    'tool_id': tool_id,
                    'confidence': 0.7,
                    'method': 'regex_extract',
                    'pattern': pattern
                }

        return None

    def add_mapping(self, workflow_name: str, tool_id: str):
        """
        动态添加硬匹配映射（运行时学习）

        Args:
            workflow_name: Workflow 名称
            tool_id: 对应的工具 ID
        """
        workflow_name_clean = self._normalize(workflow_name)
        self.HARD_MAPPING[workflow_name_clean] = tool_id
        log.info(f"📝 Added mapping: '{workflow_name_clean}' → '{tool_id}'")

    def get_stats(self) -> Dict[str, int]:
        """获取匹配器统计信息"""
        return {
            'hard_mappings': len(self.HARD_MAPPING),
            'regex_patterns': len(self.REGEX_PATTERNS),
            'db_available': self.conn is not None
        }


# 便捷函数
def match_tool_name(workflow_name: str, db_connection=None) -> str:
    """
    快速匹配工具名称

    Args:
        workflow_name: Workflow 名称
        db_connection: 数据库连接（可选）

    Returns:
        匹配到的工具 ID

    Example:
        >>> tool_id = match_tool_name("nf-core-scrnaseq (imported from...)")
        >>> print(tool_id)
        'nfcore/scrnaseq'
    """
    matcher = ToolNameMatcher(db_connection)
    result = matcher.match(workflow_name)
    return result['tool_id']
