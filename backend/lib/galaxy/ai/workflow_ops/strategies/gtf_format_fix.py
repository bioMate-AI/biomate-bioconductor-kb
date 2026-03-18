"""
GTF 格式错误修复策略

自动检测和修复 nf-core/clipseq 等流程中的 GTF 格式问题
"""

import logging
import re
from typing import Dict, List, Optional, Any
from pathlib import Path

from ..types import (
    Issue,
    FixPlan,
    FixAction,
    FixType,
    ActionType,
    IssueType,
    IssueSeverity,
)

log = logging.getLogger(__name__)


class GTFFormatFixStrategy:
    """
    GTF 格式错误修复策略

    检测和修复场景：
    1. 缺少 transcript 条目 → 添加 --skip_filter_gtf 参数
    2. 缺少 exon_number 属性 → 建议使用标准 GTF 文件
    3. iCount 工具兼容性问题 → 跳过相关步骤
    """

    # GTF 错误模式
    GTF_ERROR_PATTERNS = {
        'missing_transcript': r'genes.*have no associated transcript entries',
        'missing_exon_number': r"KeyError.*exon_number",
        'icount_segment_error': r'iCount.*segment.*failed|iCount/genomes/segment\.py',
        'filter_gtf_error': r'FILTER_GTF_BY_TRANSCRIPT.*failed',
        'gtf_parse_error': r'GTF.*parse.*error|invalid GTF format',
    }

    def can_fix(self, issue: Issue, context: Dict[str, Any]) -> bool:
        """
        判断是否能处理该 issue

        检查条件：
        1. 错误消息匹配 GTF 相关模式
        2. 失败的进程是 FILTER_GTF 或 ICOUNT_SEG_GTF
        3. 工作流是 nf-core/clipseq 或其他使用 iCount 的流程
        """
        error_message = issue.message.lower()

        # 检查是否匹配 GTF 错误模式
        for pattern_name, pattern in self.GTF_ERROR_PATTERNS.items():
            if re.search(pattern, issue.message, re.IGNORECASE):
                log.info(f"检测到 GTF 格式错误: {pattern_name}")
                return True

        # 检查失败的进程名称
        if hasattr(issue, 'component') and issue.component:
            component = issue.component.lower()
            if 'filter_gtf' in component or 'icount_seg_gtf' in component:
                return True

        # 检查证据中是否包含 GTF 相关错误
        if hasattr(issue, 'evidence'):
            evidence_text = ' '.join(issue.evidence).lower()
            if 'gtf' in evidence_text and ('exon_number' in evidence_text or 'transcript' in evidence_text):
                return True

        return False

    def generate_fix(self, issue: Issue, context: Dict[str, Any]) -> Optional[FixPlan]:
        """
        生成 GTF 格式错误的修复方案

        修复策略：
        1. 添加 --skip_filter_gtf 参数（最快）
        2. 建议使用标准 GTF 文件（长期方案）
        """
        error_message = issue.message

        # 分析具体的错误类型
        error_type = self._classify_gtf_error(error_message)

        fix_actions = []
        explanation_parts = []
        confidence = 0.9

        # 策略 1: 添加 --skip_filter_gtf 参数（自动执行）
        if error_type in ['missing_transcript', 'missing_exon_number', 'icount_error']:
            fix_actions.append(FixAction(
                action=ActionType.UPDATE_PARAM,
                params={
                    'param_name': 'skip_filter_gtf',
                    'new_value': True,
                    'param_type': 'boolean',
                },
                description="添加 --skip_filter_gtf 参数跳过 GTF 过滤步骤",
                risk_level='low',  # 低风险，自动执行
            ))

            explanation_parts.append(
                "检测到 GTF 文件格式不兼容问题。"
                "将添加 --skip_filter_gtf 参数来跳过 GTF 过滤和 iCount 分段步骤。"
            )

        # 策略 2: 建议使用标准 GTF（需要用户确认）
        if error_type in ['missing_transcript', 'missing_exon_number']:
            # 识别物种
            species = self._detect_species(context)
            standard_gtf_url = self._get_standard_gtf_url(species)

            if standard_gtf_url:
                fix_actions.append(FixAction(
                    action=ActionType.REPLACE_INPUT,
                    params={
                        'input_name': 'gtf',
                        'suggested_source': standard_gtf_url,
                        'reason': f'当前 GTF 文件{self._get_missing_features(error_type)}，建议使用标准 Ensembl GTF',
                    },
                    description=f"建议使用标准 GTF 文件: {standard_gtf_url}",
                    risk_level='medium',  # 中等风险，需要用户确认
                ))

                explanation_parts.append(
                    f"长期建议：使用标准的 {species} GTF 文件。"
                    f"可从 Ensembl 下载：{standard_gtf_url}"
                )

        if not fix_actions:
            return None

        # 构建完整的修复计划
        fix_plan = FixPlan(
            fixable=True,
            fix_type=FixType.CONFIG_ADJUSTMENT,
            fix_actions=fix_actions,
            explanation='\n'.join(explanation_parts),
            confidence=confidence,
            estimated_success_rate=0.85,  # 85% 成功率
            requires_user_confirmation=False,  # --skip_filter_gtf 是低风险，自动执行
            pre_conditions=[
                "工作流支持 --skip_filter_gtf 参数",
                "后续分析步骤不强制依赖 GTF 过滤结果",
            ],
            post_actions=[
                "验证工作流能继续执行",
                "检查后续步骤是否正常",
            ],
        )

        # 添加详细的错误诊断信息
        fix_plan.diagnosis = {
            'error_type': error_type,
            'root_cause': self._get_root_cause_description(error_type),
            'affected_processes': self._extract_affected_processes(error_message),
            'gtf_issues': self._get_missing_features(error_type),
        }

        return fix_plan

    def apply_fix(self, fix_plan: FixPlan, context: Dict[str, Any]) -> bool:
        """
        应用 GTF 格式修复

        执行步骤：
        1. 更新 Nextflow 参数配置
        2. 重新提交工作流
        3. 监控执行状态
        """
        try:
            invocation_id = context.get('invocation_id')
            app = context.get('app')

            if not invocation_id or not app:
                log.error("缺少必要的上下文信息")
                return False

            # 应用每个修复动作
            for action in fix_plan.fix_actions:
                if action.action == ActionType.UPDATE_PARAM:
                    success = self._update_workflow_param(
                        invocation_id,
                        action.params,
                        app
                    )
                    if not success:
                        log.error(f"更新参数失败: {action.params}")
                        return False

                elif action.action == ActionType.REPLACE_INPUT:
                    # 替换输入文件需要用户手动操作，这里只记录建议
                    log.info(f"建议替换输入: {action.description}")
                    # 不阻止修复流程

            log.info(f"GTF 格式修复应用成功: {fix_plan.explanation}")
            return True

        except Exception as e:
            log.error(f"应用 GTF 修复失败: {e}", exc_info=True)
            return False

    # ========== 辅助方法 ==========

    def _classify_gtf_error(self, error_message: str) -> str:
        """分类 GTF 错误类型"""
        if re.search(r'no associated transcript', error_message, re.I):
            return 'missing_transcript'
        elif re.search(r'exon_number', error_message, re.I):
            return 'missing_exon_number'
        elif re.search(r'iCount', error_message, re.I):
            return 'icount_error'
        elif re.search(r'GTF.*parse', error_message, re.I):
            return 'gtf_parse_error'
        else:
            return 'unknown_gtf_error'

    def _get_root_cause_description(self, error_type: str) -> str:
        """获取根本原因描述"""
        descriptions = {
            'missing_transcript': (
                "GTF 文件缺少 transcript 层级。标准 GTF 应包含 gene → transcript → exon 的完整层级结构，"
                "但当前文件只有 gene → exon，导致 FILTER_GTF_BY_TRANSCRIPT 无法处理。"
            ),
            'missing_exon_number': (
                "GTF 文件的 exon 条目缺少 'exon_number' 属性。iCount 工具需要此属性来对 exons 排序，"
                "以便进行基因组分段注释。"
            ),
            'icount_error': (
                "iCount 工具在处理 GTF 文件时遇到格式兼容性问题。"
                "iCount 对 GTF 格式要求严格，需要完整的注释属性。"
            ),
            'gtf_parse_error': (
                "GTF 文件解析失败，可能是格式不标准、编码问题或文件损坏。"
            ),
        }
        return descriptions.get(error_type, "未知的 GTF 格式错误")

    def _get_missing_features(self, error_type: str) -> str:
        """获取缺失的特性描述"""
        features = {
            'missing_transcript': '缺少 transcript 条目',
            'missing_exon_number': '缺少 exon_number 属性',
            'icount_error': '格式不兼容',
            'gtf_parse_error': '解析失败',
        }
        return features.get(error_type, '格式问题')

    def _extract_affected_processes(self, error_message: str) -> List[str]:
        """提取受影响的进程"""
        processes = []

        if 'FILTER_GTF_BY_TRANSCRIPT' in error_message:
            processes.append('FILTER_GTF_BY_TRANSCRIPT')
        if 'ICOUNT_SEG_GTF' in error_message:
            processes.append('ICOUNT_SEG_GTF')

        return processes or ['Unknown']

    def _detect_species(self, context: Dict[str, Any]) -> str:
        """从上下文中检测物种"""
        # 尝试从工作流配置或输入文件名检测
        workflow_config = context.get('workflow_config', {})

        # 检查常见的物种标识
        config_str = str(workflow_config).lower()

        if 'homo_sapiens' in config_str or 'human' in config_str or 'hg38' in config_str or 'hg19' in config_str:
            return 'homo_sapiens'
        elif 'mus_musculus' in config_str or 'mouse' in config_str or 'mm10' in config_str or 'mm39' in config_str:
            return 'mus_musculus'
        elif 'drosophila' in config_str or 'dm6' in config_str:
            return 'drosophila_melanogaster'
        else:
            return 'homo_sapiens'  # 默认人类

    def _get_standard_gtf_url(self, species: str) -> Optional[str]:
        """获取标准 GTF 文件的下载链接"""
        urls = {
            'homo_sapiens': 'http://ftp.ensembl.org/pub/release-110/gtf/homo_sapiens/Homo_sapiens.GRCh38.110.gtf.gz',
            'mus_musculus': 'http://ftp.ensembl.org/pub/release-110/gtf/mus_musculus/Mus_musculus.GRCm39.110.gtf.gz',
            'drosophila_melanogaster': 'http://ftp.ensembl.org/pub/release-110/gtf/drosophila_melanogaster/Drosophila_melanogaster.BDGP6.32.110.gtf.gz',
        }
        return urls.get(species)

    def _update_workflow_param(
        self,
        invocation_id: int,
        param_config: Dict[str, Any],
        app
    ) -> bool:
        """
        更新工作流参数

        对于 Nextflow 工作流，这意味着修改 nextflow.config 或参数文件
        """
        try:
            from galaxy.model import WorkflowInvocation

            # 获取工作流调用
            invocation = app.model.session.query(WorkflowInvocation).get(invocation_id)
            if not invocation:
                log.error(f"未找到 workflow invocation: {invocation_id}")
                return False

            # 对于 Nextflow，需要更新配置并重新启动
            # 这里记录修复建议，实际重启由监控器处理
            param_name = param_config.get('param_name')
            new_value = param_config.get('new_value')

            log.info(f"准备更新 Nextflow 参数: {param_name}={new_value}")

            # 将修复信息保存到 invocation 的元数据中
            if not hasattr(invocation, 'ai_fix_metadata'):
                invocation.ai_fix_metadata = {}

            invocation.ai_fix_metadata['gtf_fix'] = {
                'param_name': param_name,
                'new_value': new_value,
                'timestamp': str(Path(__file__).stat().st_mtime),
                'status': 'pending_restart',
            }

            app.model.session.add(invocation)
            app.model.session.commit()

            log.info(f"GTF 修复参数已保存，等待工作流重启时应用")
            return True

        except Exception as e:
            log.error(f"更新工作流参数失败: {e}", exc_info=True)
            return False
