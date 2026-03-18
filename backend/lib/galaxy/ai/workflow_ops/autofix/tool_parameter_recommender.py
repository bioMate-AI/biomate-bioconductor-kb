"""
Tool Parameter Recommender

基于 galaxy_ai_tools.db 数据库提供智能参数推荐

数据来源：
- S3: s3://galaxy-cloud-data-1760241377/biomate/galaxy_ai_tools.db
- 包含: 7000+ Galaxy 工具的参数信息、使用模式、兼容性数据

作者：AI Workflow AutoFix Team
日期：2026-01-31
"""

import logging
import sqlite3
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple
from dataclasses import dataclass

log = logging.getLogger(__name__)


@dataclass
class ToolInfo:
    """工具信息"""
    tool_id: str
    name: str
    category: str
    description: str
    raw_text: str
    version: Optional[str] = None


@dataclass
class ParameterRecommendation:
    """参数推荐"""
    parameter_name: str
    recommended_value: Any
    confidence: float  # 0-1
    reasoning: str
    alternative_values: List[Any] = None


class ToolParameterRecommender:
    """
    工具参数推荐器

    基于以下数据源提供智能推荐：
    1. galaxy_ai_tools.db 中的工具信息（7000+ 工具）
    2. 工具兼容性数据（tool_compatibility）
    3. 工具使用模式（tool_usage_patterns）
    4. 数据集-工具映射（dataset_tool_mapping）

    使用方法：
        recommender = ToolParameterRecommender(db_path='galaxy_ai_tools.db')
        recommendations = recommender.recommend_parameters(
            tool_name='nfcore/clipseq',
            error_context='GTF file format error',
            workflow_params={'genome': 'GRCh38'}
        )
    """

    def __init__(self, db_path: str = None):
        """
        初始化推荐器

        Args:
            db_path: galaxy_ai_tools.db 的路径
                    如果为 None，尝试以下位置：
                    1. backend/galaxy_ai_tools.db
                    2. /path/to/galaxy/backend/galaxy_ai_tools.db
        """
        if db_path is None:
            # 尝试默认路径
            possible_paths = [
                Path('backend/galaxy_ai_tools.db'),
                Path(__file__).parent.parent.parent.parent.parent.parent / 'backend/galaxy_ai_tools.db',
            ]

            for path in possible_paths:
                if path.exists():
                    db_path = str(path)
                    break

        if db_path is None or not Path(db_path).exists():
            log.warning(f"galaxy_ai_tools.db not found. Parameter recommendations will be limited.")
            self.db_path = None
            self.conn = None
        else:
            self.db_path = db_path
            self.conn = sqlite3.connect(db_path)
            self.conn.row_factory = sqlite3.Row
            log.info(f"✅ ToolParameterRecommender initialized with DB: {db_path}")

    def __del__(self):
        """关闭数据库连接"""
        if self.conn:
            self.conn.close()

    def search_tools(self, query: str, limit: int = 10) -> List[ToolInfo]:
        """
        搜索工具

        Args:
            query: 搜索关键词（工具名称、描述等）
            limit: 返回结果数量

        Returns:
            匹配的工具列表
        """
        if not self.conn:
            return []

        try:
            # 使用 FTS5 全文搜索
            cursor = self.conn.execute("""
                SELECT t.tool_id, t.name, t.category, t.description, t.rawText, t.version
                FROM tools t
                JOIN tools_fts fts ON t.tool_id = fts.tool_id
                WHERE tools_fts MATCH ?
                LIMIT ?
            """, (query, limit))

            results = []
            for row in cursor:
                results.append(ToolInfo(
                    tool_id=row['tool_id'],
                    name=row['name'],
                    category=row['category'],
                    description=row['description'] or '',
                    raw_text=row['rawText'] or '',
                    version=row['version'],
                ))

            return results

        except Exception as e:
            log.error(f"Failed to search tools: {e}")
            return []

    def get_tool_by_name(self, tool_name: str) -> Optional[ToolInfo]:
        """
        根据工具名称获取工具信息

        Args:
            tool_name: 工具名称（如 'nfcore/clipseq', 'fastqc' 等）

        Returns:
            工具信息，如果找不到返回 None
        """
        if not self.conn:
            return None

        try:
            # 尝试精确匹配
            cursor = self.conn.execute("""
                SELECT tool_id, name, category, description, rawText, version
                FROM tools
                WHERE name LIKE ? OR tool_id LIKE ?
                LIMIT 1
            """, (f'%{tool_name}%', f'%{tool_name}%'))

            row = cursor.fetchone()
            if row:
                return ToolInfo(
                    tool_id=row['tool_id'],
                    name=row['name'],
                    category=row['category'],
                    description=row['description'] or '',
                    raw_text=row['rawText'] or '',
                    version=row['version'],
                )

            return None

        except Exception as e:
            log.error(f"Failed to get tool by name: {e}")
            return None

    def recommend_parameters(
        self,
        tool_name: str,
        error_context: Optional[str] = None,
        workflow_params: Optional[Dict[str, Any]] = None,
    ) -> List[ParameterRecommendation]:
        """
        推荐工具参数

        Args:
            tool_name: 工具名称
            error_context: 错误上下文（可选，用于更精准的推荐）
            workflow_params: 当前 workflow 参数（可选）

        Returns:
            参数推荐列表
        """
        recommendations = []

        # 1. 获取工具信息
        tool_info = self.get_tool_by_name(tool_name)
        if not tool_info:
            log.warning(f"Tool '{tool_name}' not found in database")
            return self._get_fallback_recommendations(tool_name, error_context, workflow_params)

        log.info(f"Found tool: {tool_info.name} (category: {tool_info.category})")

        # 🆕 2. 从 dataset_tool_mapping 表获取数据库推荐（优先级最高）
        db_based = self._get_database_recommendations(tool_info.tool_id)
        if db_based:
            log.info(f"✅ Found {len(db_based)} recommendations from dataset_tool_mapping table")
            recommendations.extend(db_based)

        # 3. 从工具的 rawText 提取参数信息
        params_from_raw = self._extract_parameters_from_raw_text(tool_info.raw_text)

        # 4. 根据错误上下文推荐参数
        if error_context:
            context_based = self._get_context_based_recommendations(
                tool_info, error_context, workflow_params
            )
            recommendations.extend(context_based)

        # 5. 根据工具类别推荐常见参数
        category_based = self._get_category_based_recommendations(
            tool_info.category, workflow_params
        )
        recommendations.extend(category_based)

        # 6. 去重和排序
        recommendations = self._deduplicate_and_sort(recommendations)

        return recommendations

    def _get_database_recommendations(self, tool_id: str) -> List[ParameterRecommendation]:
        """
        🆕 从 dataset_tool_mapping 表获取数据库推荐

        这是核心方法，使用 AWS S3 数据库中存储的 282 条真实推荐数据

        Args:
            tool_id: 工具 ID

        Returns:
            推荐列表
        """
        if not self.conn:
            return []

        try:
            # 🔑 关键改进：JOIN dataset_metadata 获取实际 S3 路径
            cursor = self.conn.execute("""
                SELECT
                    d.dataset_tool_id,
                    d.parameter_name,
                    d.confidence,
                    d.reasoning,
                    m.s3_path,
                    m.dataset_name,
                    m.file_type,
                    m.description
                FROM dataset_tool_mapping d
                LEFT JOIN dataset_metadata m ON d.dataset_tool_id = m.dataset_id
                WHERE d.target_tool_id = ?
                ORDER BY d.confidence DESC
                LIMIT 10
            """, (tool_id,))

            recommendations = []
            for row in cursor.fetchall():
                # 🆕 优先使用 S3 路径，如果没有则使用 dataset_id
                recommended_value = row['s3_path'] if row['s3_path'] else row['dataset_tool_id']

                # 🆕 增强推荐理由
                reasoning = f"[数据库推荐] {row['reasoning'] or 'No reasoning provided'}"
                if row['dataset_name']:
                    reasoning += f"\n📦 数据集: {row['dataset_name']}"
                if row['description']:
                    reasoning += f"\n📝 描述: {row['description']}"
                if row['file_type']:
                    reasoning += f"\n📄 文件类型: {row['file_type']}"

                recommendations.append(ParameterRecommendation(
                    parameter_name=row['parameter_name'],
                    recommended_value=recommended_value,  # ✅ 现在是可用的 S3 路径
                    confidence=row['confidence'] or 0.7,
                    reasoning=reasoning,
                    alternative_values=[]
                ))

            return recommendations

        except Exception as e:
            log.error(f"Failed to get database recommendations: {e}")
            return []

    def _extract_parameters_from_raw_text(self, raw_text: str) -> Dict[str, Any]:
        """
        从 rawText 中提取参数信息

        Args:
            raw_text: 工具的原始文本描述

        Returns:
            参数字典
        """
        # TODO: 使用 LLM 或正则表达式提取参数
        # 目前返回空字典，后续可以增强
        return {}

    def _get_context_based_recommendations(
        self,
        tool_info: ToolInfo,
        error_context: str,
        workflow_params: Optional[Dict[str, Any]],
    ) -> List[ParameterRecommendation]:
        """
        基于错误上下文推荐参数

        Args:
            tool_info: 工具信息
            error_context: 错误上下文
            workflow_params: 当前 workflow 参数

        Returns:
            推荐列表
        """
        recommendations = []

        # GTF 文件相关错误
        if 'gtf' in error_context.lower() or 'gff' in error_context.lower():
            recommendations.append(ParameterRecommendation(
                parameter_name='gtf',
                recommended_value='s3://galaxy-cloud-data-1760241377/reference/Homo_sapiens.GRCh38.110.gtf.gz',
                confidence=0.8,
                reasoning='推荐使用完整的 Ensembl GRCh38 GTF 文件（包含所有必需属性）',
                alternative_values=[
                    's3://galaxy-cloud-data-1760241377/reference/Homo_sapiens.GRCh38.110.chr.gtf.gz',
                ]
            ))

        # Genome/FASTA 相关错误
        if 'genome' in error_context.lower() or 'fasta' in error_context.lower():
            genome = workflow_params.get('genome', 'GRCh38') if workflow_params else 'GRCh38'

            recommendations.append(ParameterRecommendation(
                parameter_name='fasta',
                recommended_value=f's3://galaxy-cloud-data-1760241377/reference/{genome}/genome.fa.gz',
                confidence=0.85,
                reasoning=f'推荐使用 {genome} 基因组参考序列',
                alternative_values=[]
            ))

        # Samplesheet 相关错误
        if 'samplesheet' in error_context.lower() or 'sample' in error_context.lower():
            recommendations.append(ParameterRecommendation(
                parameter_name='input',
                recommended_value='需要修复的 samplesheet（由 SamplesheetFixer 生成）',
                confidence=0.9,
                reasoning='检测到 samplesheet 格式问题，建议使用自动修复后的版本',
                alternative_values=[]
            ))

        # Skip 参数相关（常见于 nf-core pipeline）
        if 'skip' in error_context.lower():
            recommendations.append(ParameterRecommendation(
                parameter_name='skip_multiqc',
                recommended_value=False,
                confidence=0.7,
                reasoning='建议保留 MultiQC 报告',
                alternative_values=[True]
            ))

        return recommendations

    def _get_category_based_recommendations(
        self,
        category: str,
        workflow_params: Optional[Dict[str, Any]],
    ) -> List[ParameterRecommendation]:
        """
        基于工具类别推荐通用参数

        Args:
            category: 工具类别（如 'RNA-Seq', 'Assembly' 等）
            workflow_params: 当前 workflow 参数

        Returns:
            推荐列表
        """
        recommendations = []

        # RNA-Seq 相关工具
        if category and 'rna' in category.lower():
            recommendations.append(ParameterRecommendation(
                parameter_name='stranded',
                recommended_value='auto',
                confidence=0.75,
                reasoning='自动检测链特异性',
                alternative_values=['yes', 'no', 'reverse']
            ))

        # Assembly 相关工具
        elif category and 'assembly' in category.lower():
            recommendations.append(ParameterRecommendation(
                parameter_name='kmer_size',
                recommended_value=31,
                confidence=0.7,
                reasoning='常用的 k-mer 大小',
                alternative_values=[21, 25, 41, 51]
            ))

        return recommendations

    def _get_fallback_recommendations(
        self,
        tool_name: str,
        error_context: Optional[str],
        workflow_params: Optional[Dict[str, Any]],
    ) -> List[ParameterRecommendation]:
        """
        当数据库不可用或找不到工具时的备用推荐

        Args:
            tool_name: 工具名称
            error_context: 错误上下文
            workflow_params: workflow 参数

        Returns:
            备用推荐列表
        """
        recommendations = []

        # 通用推荐：基于常见错误模式
        if error_context:
            if 'memory' in error_context.lower() or 'oom' in error_context.lower():
                recommendations.append(ParameterRecommendation(
                    parameter_name='max_memory',
                    recommended_value='16.GB',
                    confidence=0.6,
                    reasoning='检测到内存不足，建议增加内存限制',
                    alternative_values=['32.GB', '64.GB']
                ))

            if 'cpu' in error_context.lower() or 'cores' in error_context.lower():
                recommendations.append(ParameterRecommendation(
                    parameter_name='max_cpus',
                    recommended_value=8,
                    confidence=0.6,
                    reasoning='建议使用更多 CPU 核心',
                    alternative_values=[4, 16, 32]
                ))

        return recommendations

    def _deduplicate_and_sort(
        self,
        recommendations: List[ParameterRecommendation]
    ) -> List[ParameterRecommendation]:
        """
        去重并按置信度排序

        Args:
            recommendations: 原始推荐列表

        Returns:
            去重排序后的推荐列表
        """
        # 去重（保留置信度最高的）
        seen = {}
        for rec in recommendations:
            if rec.parameter_name not in seen or rec.confidence > seen[rec.parameter_name].confidence:
                seen[rec.parameter_name] = rec

        # 按置信度排序
        result = list(seen.values())
        result.sort(key=lambda x: x.confidence, reverse=True)

        return result

    def get_compatible_tools(
        self,
        data_type: str,
        compatibility_type: str = 'input'
    ) -> List[Tuple[str, str, float]]:
        """
        获取兼容特定数据类型的工具

        Args:
            data_type: 数据类型（如 'fastq', 'bam', 'gtf' 等）
            compatibility_type: 兼容性类型（'input' 或 'output'）

        Returns:
            (tool_id, tool_name, confidence) 的列表
        """
        if not self.conn:
            return []

        try:
            cursor = self.conn.execute("""
                SELECT tc.tool_id, t.name, tc.confidence
                FROM tool_compatibility tc
                JOIN tools t ON tc.tool_id = t.tool_id
                WHERE tc.data_type = ? AND tc.compatibility_type = ?
                ORDER BY tc.confidence DESC
                LIMIT 20
            """, (data_type, compatibility_type))

            return [(row['tool_id'], row['name'], row['confidence']) for row in cursor]

        except Exception as e:
            log.error(f"Failed to get compatible tools: {e}")
            return []

    def get_tool_usage_patterns(
        self,
        tool_id: str
    ) -> List[Dict[str, Any]]:
        """
        获取工具的使用模式

        Args:
            tool_id: 工具 ID

        Returns:
            使用模式列表
        """
        if not self.conn:
            return []

        try:
            cursor = self.conn.execute("""
                SELECT tool_sequence, frequency, context, task_type, success_rate
                FROM tool_usage_patterns
                WHERE tool_sequence LIKE ?
                ORDER BY frequency DESC, success_rate DESC
                LIMIT 10
            """, (f'%{tool_id}%',))

            return [dict(row) for row in cursor]

        except Exception as e:
            log.error(f"Failed to get usage patterns: {e}")
            return []

    def get_total_tools(self) -> int:
        """获取数据库中的工具总数"""
        if not self.conn:
            return 0

        try:
            cursor = self.conn.execute("SELECT COUNT(*) as count FROM tools")
            row = cursor.fetchone()
            return row['count'] if row else 0
        except Exception as e:
            log.warning(f"Failed to get total tools: {e}")
            return 0

    def get_total_recommendations(self) -> int:
        """获取数据库中的推荐总数"""
        if not self.conn:
            return 0

        try:
            cursor = self.conn.execute("SELECT COUNT(*) as count FROM dataset_tool_mapping")
            row = cursor.fetchone()
            return row['count'] if row else 0
        except Exception as e:
            log.warning(f"Failed to get total recommendations: {e}")
            return 0


# 便捷函数
def recommend_parameters_for_workflow(
    workflow_name: str,
    error_logs: str,
    current_params: Optional[Dict[str, Any]] = None,
    db_path: Optional[str] = None,
) -> List[ParameterRecommendation]:
    """
    为 workflow 推荐参数

    Args:
        workflow_name: Workflow 名称（如 'nfcore/clipseq'）
        error_logs: 错误日志
        current_params: 当前参数
        db_path: 数据库路径

    Returns:
        参数推荐列表

    Example:
        >>> recommendations = recommend_parameters_for_workflow(
        ...     workflow_name='nfcore/clipseq',
        ...     error_logs='GTF file format error: missing exon_number',
        ...     current_params={'genome': 'GRCh38'}
        ... )
        >>> for rec in recommendations:
        ...     print(f"{rec.parameter_name}: {rec.recommended_value} (confidence: {rec.confidence})")
    """
    recommender = ToolParameterRecommender(db_path=db_path)

    return recommender.recommend_parameters(
        tool_name=workflow_name,
        error_context=error_logs,
        workflow_params=current_params,
    )
