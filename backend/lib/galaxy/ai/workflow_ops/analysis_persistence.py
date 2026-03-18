"""
AI Workflow Operations - Analysis Result Persistence

持久化AI分析结果，支持历史记录查询和恢复
"""

import json
import logging
from pathlib import Path
from typing import Dict, Any, List, Optional
from datetime import datetime

log = logging.getLogger(__name__)


class AnalysisResultPersistence:
    """
    AI分析结果持久化管理器

    存储结构:
    {workflow_ops_directory}/
        analysis_results/
            workflow_{invocation_id}/
                analysis_{timestamp}.json
                latest.json -> 最新分析的软链接
    """

    def __init__(self, base_dir: Path):
        """
        初始化持久化管理器

        Args:
            base_dir: Galaxy的数据目录 (通常是 database/)
        """
        self.base_dir = Path(base_dir)
        self.analysis_dir = self.base_dir / "ai_workflow_ops" / "analysis_results"
        self.analysis_dir.mkdir(parents=True, exist_ok=True)

    def get_workflow_dir(self, workflow_invocation_id: int) -> Path:
        """获取特定workflow的存储目录"""
        workflow_dir = self.analysis_dir / f"workflow_{workflow_invocation_id}"
        workflow_dir.mkdir(parents=True, exist_ok=True)
        return workflow_dir

    def save_analysis(
        self,
        workflow_invocation_id: int,
        analysis_data: Dict[str, Any],
        is_final: bool = False
    ) -> str:
        """
        保存分析结果

        Args:
            workflow_invocation_id: Workflow调用ID
            analysis_data: 分析数据（包含logs, issues, fixes等）
            is_final: 是否为最终结果（会更新latest.json）

        Returns:
            保存的文件路径
        """
        workflow_dir = self.get_workflow_dir(workflow_invocation_id)

        # 添加元数据
        analysis_data['metadata'] = {
            'workflow_invocation_id': workflow_invocation_id,
            'saved_at': datetime.now().isoformat(),
            'is_final': is_final,
            'version': '1.0'
        }

        # 保存到时间戳文件
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        result_file = workflow_dir / f"analysis_{timestamp}.json"

        try:
            with open(result_file, 'w', encoding='utf-8') as f:
                json.dump(analysis_data, f, indent=2, ensure_ascii=False)

            log.info(f"Saved analysis result to {result_file}")

            # 如果是最终结果，更新latest.json
            if is_final:
                latest_file = workflow_dir / "latest.json"
                with open(latest_file, 'w', encoding='utf-8') as f:
                    json.dump(analysis_data, f, indent=2, ensure_ascii=False)
                log.info(f"Updated latest analysis: {latest_file}")

            return str(result_file)

        except Exception as e:
            log.error(f"Failed to save analysis result: {e}")
            raise

    def load_latest_analysis(self, workflow_invocation_id: int) -> Optional[Dict[str, Any]]:
        """
        加载最新的分析结果

        Args:
            workflow_invocation_id: Workflow调用ID

        Returns:
            分析数据，如果不存在返回None
        """
        workflow_dir = self.get_workflow_dir(workflow_invocation_id)
        latest_file = workflow_dir / "latest.json"

        if not latest_file.exists():
            log.debug(f"No latest analysis found for workflow {workflow_invocation_id}")
            return None

        try:
            with open(latest_file, 'r', encoding='utf-8') as f:
                data = json.load(f)
            log.info(f"Loaded latest analysis for workflow {workflow_invocation_id}")
            return data
        except Exception as e:
            log.error(f"Failed to load latest analysis: {e}")
            return None

    def load_analysis_by_timestamp(
        self,
        workflow_invocation_id: int,
        timestamp: str
    ) -> Optional[Dict[str, Any]]:
        """
        加载特定时间点的分析结果

        Args:
            workflow_invocation_id: Workflow调用ID
            timestamp: 时间戳 (格式: YYYYMMDD_HHMMSS)

        Returns:
            分析数据，如果不存在返回None
        """
        workflow_dir = self.get_workflow_dir(workflow_invocation_id)
        result_file = workflow_dir / f"analysis_{timestamp}.json"

        if not result_file.exists():
            return None

        try:
            with open(result_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            log.error(f"Failed to load analysis: {e}")
            return None

    def list_analyses(self, workflow_invocation_id: int) -> List[Dict[str, Any]]:
        """
        列出某个workflow的所有分析历史

        Args:
            workflow_invocation_id: Workflow调用ID

        Returns:
            分析历史列表，每项包含timestamp和metadata
        """
        workflow_dir = self.get_workflow_dir(workflow_invocation_id)

        if not workflow_dir.exists():
            return []

        analyses = []
        for result_file in sorted(workflow_dir.glob("analysis_*.json"), reverse=True):
            try:
                with open(result_file, 'r', encoding='utf-8') as f:
                    data = json.load(f)

                # 提取摘要信息
                summary = {
                    'filename': result_file.name,
                    'timestamp': result_file.stem.replace('analysis_', ''),
                    'saved_at': data.get('metadata', {}).get('saved_at'),
                    'is_final': data.get('metadata', {}).get('is_final', False),
                    'total_issues': len(data.get('detectedIssues', [])),
                    'total_fixes': len(data.get('fixSuggestions', [])),
                    'status': data.get('currentStatus', 'unknown'),
                }
                analyses.append(summary)
            except Exception as e:
                log.warning(f"Failed to read {result_file}: {e}")
                continue

        return analyses

    def delete_analysis(self, workflow_invocation_id: int, timestamp: str) -> bool:
        """
        删除特定的分析记录

        Args:
            workflow_invocation_id: Workflow调用ID
            timestamp: 时间戳

        Returns:
            是否成功删除
        """
        workflow_dir = self.get_workflow_dir(workflow_invocation_id)
        result_file = workflow_dir / f"analysis_{timestamp}.json"

        if result_file.exists():
            try:
                result_file.unlink()
                log.info(f"Deleted analysis: {result_file}")
                return True
            except Exception as e:
                log.error(f"Failed to delete analysis: {e}")
                return False
        return False

    def cleanup_old_analyses(
        self,
        workflow_invocation_id: int,
        keep_count: int = 10
    ) -> int:
        """
        清理旧的分析记录，只保留最新的N个

        Args:
            workflow_invocation_id: Workflow调用ID
            keep_count: 保留的记录数量

        Returns:
            删除的记录数量
        """
        workflow_dir = self.get_workflow_dir(workflow_invocation_id)

        if not workflow_dir.exists():
            return 0

        # 获取所有分析文件（排除latest.json）
        analysis_files = sorted(
            [f for f in workflow_dir.glob("analysis_*.json")],
            key=lambda x: x.stat().st_mtime,
            reverse=True
        )

        # 删除超出保留数量的文件
        deleted_count = 0
        for old_file in analysis_files[keep_count:]:
            try:
                old_file.unlink()
                deleted_count += 1
                log.debug(f"Cleaned up old analysis: {old_file}")
            except Exception as e:
                log.warning(f"Failed to cleanup {old_file}: {e}")

        if deleted_count > 0:
            log.info(f"Cleaned up {deleted_count} old analyses for workflow {workflow_invocation_id}")

        return deleted_count


# 全局实例（延迟初始化）
_persistence_instance: Optional[AnalysisResultPersistence] = None


def get_persistence(app) -> AnalysisResultPersistence:
    """
    获取全局持久化实例

    Args:
        app: Galaxy应用实例

    Returns:
        AnalysisResultPersistence实例
    """
    global _persistence_instance

    if _persistence_instance is None:
        # 使用Galaxy的database目录
        base_dir = Path(app.config.data_dir if hasattr(app.config, 'data_dir') else 'database')
        _persistence_instance = AnalysisResultPersistence(base_dir)
        log.info(f"Initialized AnalysisResultPersistence at {base_dir}")

    return _persistence_instance
