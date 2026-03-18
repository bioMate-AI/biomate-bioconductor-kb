"""
Reference Genome Fixer

自动检测缺失的参考基因组，并提供下载和构建索引的能力
"""

import logging
import json
import re
import os
from pathlib import Path
from typing import Dict, List, Any, Optional, Tuple
from datetime import datetime

from ..base import (
    BaseAutoFixer,
    FixContext,
    FixStatus,
    RiskLevel,
    AutoFixResult,
)
from ...types import FixAction, ActionType

log = logging.getLogger(__name__)


class ReferenceGenomeFixer(BaseAutoFixer):
    """
    参考基因组修复器

    自动检测缺失的参考基因组并提供修复方案：
    1. 检测缺失的基因组文件
    2. 提供下载源（iGenomes, Ensembl, UCSC）
    3. 自动下载基因组数据
    4. 自动构建索引（STAR, Bowtie2, etc.）
    """

    name = "ReferenceGenomeFixer"
    description = "自动检测和修复缺失的参考基因组"

    # 支持的基因组源
    GENOME_SOURCES = {
        "igenomes": {
            "name": "iGenomes",
            "base_url": "s3://ngi-igenomes/igenomes/",
            "description": "Illumina iGenomes - 包含预构建的索引",
        },
        "ensembl": {
            "name": "Ensembl",
            "base_url": "ftp://ftp.ensembl.org/pub/",
            "description": "Ensembl - 官方基因组注释",
        },
        "ucsc": {
            "name": "UCSC",
            "base_url": "https://hgdownload.soe.ucsc.edu/goldenPath/",
            "description": "UCSC Genome Browser - 标准基因组数据",
        },
    }

    # 常见基因组配置
    COMMON_GENOMES = {
        "GRCh38": {
            "species": "Homo sapiens",
            "assembly": "GRCh38",
            "size_gb": 30,
            "sources": ["igenomes", "ensembl", "ucsc"],
        },
        "GRCh37": {
            "species": "Homo sapiens",
            "assembly": "GRCh37",
            "size_gb": 28,
            "sources": ["igenomes", "ensembl", "ucsc"],
        },
        "GRCm39": {
            "species": "Mus musculus",
            "assembly": "GRCm39",
            "size_gb": 25,
            "sources": ["igenomes", "ensembl", "ucsc"],
        },
        "GRCm38": {
            "species": "Mus musculus",
            "assembly": "GRCm38",
            "size_gb": 24,
            "sources": ["igenomes", "ensembl", "ucsc"],
        },
    }

    # 索引构建工具
    INDEX_BUILDERS = {
        "star": {
            "name": "STAR",
            "command": "STAR --runMode genomeGenerate",
            "time_estimate_hours": 2,
        },
        "bowtie2": {
            "name": "Bowtie2",
            "command": "bowtie2-build",
            "time_estimate_hours": 1,
        },
        "hisat2": {
            "name": "HISAT2",
            "command": "hisat2-build",
            "time_estimate_hours": 1.5,
        },
        "bwa": {
            "name": "BWA",
            "command": "bwa index",
            "time_estimate_hours": 0.5,
        },
    }

    def __init__(self, genome_base_path: Optional[str] = None):
        """
        初始化 Reference Genome Fixer

        Args:
            genome_base_path: 基因组数据存储的基础路径
        """
        super().__init__()
        self.genome_base_path = genome_base_path or os.getenv(
            "GALAXY_GENOME_PATH",
            "/data/genomes"
        )

    def detect_issues(self, context: FixContext) -> List[Dict[str, Any]]:
        """
        检测缺失的参考基因组和格式不匹配问题

        通过分析错误日志，识别是否因为缺失基因组文件或GTF/FASTA格式不匹配导致失败
        """
        from pathlib import Path

        issues = []
        invocation_id = context.invocation_id

        # 从文件系统读取错误日志（与 ContainerErrorFixer 相同）
        sa_session = context.metadata.get('sa_session')
        if not sa_session:
            log.error("No sa_session in context metadata")
            return []

        from galaxy.model import WorkflowInvocation
        invocation = sa_session.query(WorkflowInvocation).get(context.invocation_id)
        if not invocation:
            log.error(f"Invocation {context.invocation_id} not found")
            return []

        # 获取 Nextflow 工作目录
        config = context.metadata.get('app_config')
        if not config:
            log.warning("No app_config in metadata, cannot locate workflow directory")
            return []

        jobs_dir = Path(config.jobs_directory)
        workflow_dir = jobs_dir / f"nextflow_workflows/workflow_{context.invocation_id}"

        # 读取 nextflow.out 错误日志
        nextflow_out = workflow_dir / "nextflow.out"
        error_logs = ""
        if nextflow_out.exists():
            try:
                with open(nextflow_out, 'r') as f:
                    error_logs = f.read()
                log.info(f"[{invocation_id}] Read error log from {nextflow_out} ({len(error_logs)} chars)")
            except Exception as e:
                log.warning(f"[{invocation_id}] Failed to read {nextflow_out}: {e}")

        # 读取 nextflow.config 获取 workflow 配置
        nextflow_config = workflow_dir / "nextflow.config"
        workflow_config = {}
        if nextflow_config.exists():
            try:
                with open(nextflow_config, 'r') as f:
                    config_content = f.read()
                    # 简单解析 nextflow.config 中的参数
                    import re
                    for line in config_content.split('\n'):
                        # 匹配 key = value 格式
                        match = re.match(r'\s*(\w+)\s*=\s*[\'"]?([^\'"]+)[\'"]?', line)
                        if match:
                            key, value = match.groups()
                            workflow_config[key] = value.strip('\'"')
                log.info(f"[{invocation_id}] Parsed workflow config: {list(workflow_config.keys())}")
            except Exception as e:
                log.warning(f"[{invocation_id}] Failed to parse {nextflow_config}: {e}")

        # 🆕 首先检测 GTF/FASTA 染色体命名不匹配（优先级更高）
        gtf_fasta_mismatch_patterns = [
            r"no valid exon lines in the GTF file",
            r"difference in chromosome naming between GTF and FASTA",
            r"Fatal INPUT FILE error.*GTF",
            r"chromosome.*(?:not found|mismatch).*(?:GTF|FASTA)",
        ]

        for pattern in gtf_fasta_mismatch_patterns:
            if re.search(pattern, error_logs, re.IGNORECASE):
                log.info(f"[{invocation_id}] Detected GTF/FASTA chromosome naming mismatch")

                # 检查当前配置
                gtf_param = workflow_config.get('gtf', '')
                fasta_param = workflow_config.get('fasta', '')
                genome_param = workflow_config.get('genome', '')
                igenomes_ignore = workflow_config.get('igenomes_ignore', False)

                # 判断是否使用了 Ensembl GTF + iGenomes FASTA
                is_ensembl_gtf = 'ensembl.org' in str(gtf_param).lower()
                is_igenomes_fasta = not fasta_param and not igenomes_ignore  # 使用默认 iGenomes

                fix_actions = []
                description = "GTF 和 FASTA 文件的染色体命名不一致（Ensembl vs NCBI 格式）"

                if is_ensembl_gtf and is_igenomes_fasta:
                    # 场景1: Ensembl GTF + iGenomes FASTA → 添加 Ensembl FASTA
                    fix_actions = [
                        {
                            "action": "add_parameter",
                            "parameter_name": "fasta",
                            "new_value": "https://ftp.ensembl.org/pub/release-110/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz",
                            "reason": "添加 Ensembl FASTA 文件以匹配 Ensembl GTF 的染色体命名（1,2,X 而非 chr1,chr2,chrX）"
                        },
                        {
                            "action": "add_parameter",
                            "parameter_name": "igenomes_ignore",
                            "new_value": "true",
                            "reason": "禁用 iGenomes 以避免混用不同格式的参考文件"
                        }
                    ]
                    description += "。检测到使用了 Ensembl GTF 但 FASTA 来自 iGenomes（NCBI 格式），需要同时指定 Ensembl FASTA"
                else:
                    # 通用修复建议
                    fix_actions = [
                        {
                            "action": "add_parameter",
                            "parameter_name": "fasta",
                            "new_value": "https://ftp.ensembl.org/pub/release-110/fasta/homo_sapiens/dna/Homo_sapiens.GRCh38.dna.primary_assembly.fa.gz",
                            "reason": "确保 GTF 和 FASTA 文件来自同一来源（推荐使用 Ensembl）"
                        }
                    ]

                issue = {
                    "type": "gtf_fasta_chromosome_mismatch",
                    "severity": "high",
                    "message": description,
                    "root_cause": "STAR 无法在 GTF 文件中找到有效的 exon 行，通常是因为 GTF 和 FASTA 的染色体命名不一致",
                    "fixable": True,
                    "fix_actions": fix_actions,
                    "confidence": 0.95,
                    "error_logs": error_logs[:500],  # 只保留前500字符
                    "detected_config": {
                        "gtf": gtf_param,
                        "fasta": fasta_param or "(using iGenomes default)",
                        "genome": genome_param,
                        "igenomes_ignore": igenomes_ignore
                    }
                }
                issues.append(issue)
                # 找到这个问题后继续检查其他问题（不break）

        # 检测缺失基因组的常见模式
        missing_genome_patterns = [
            r"(?:genome|reference).*(?:not found|missing|files|not available)",
            r"(?:fasta|gtf|gff).*(?:missing|does not exist)",
            r"(?:STAR|bowtie2|hisat2).*index.*not found",
            r"genome_id.*(?:invalid|not available)",
        ]

        for pattern in missing_genome_patterns:
            if re.search(pattern, error_logs, re.IGNORECASE):
                # 尝试提取基因组 ID
                genome_id = self._extract_genome_id(error_logs)

                issue = {
                    "type": "missing_reference_genome",
                    "severity": "high",
                    "genome_id": genome_id,
                    "message": f"缺失参考基因组: {genome_id or 'unknown'}",
                    "error_logs": error_logs[:500],
                    "fixable": True,
                }
                issues.append(issue)
                break

        return issues

    def _extract_genome_id(self, error_logs: str) -> Optional[str]:
        """
        从错误日志中提取基因组 ID

        Args:
            error_logs: 错误日志

        Returns:
            提取到的基因组 ID，如果无法提取则返回 None
        """
        # 常见的基因组 ID 模式
        genome_patterns = [
            r"genome[_\s]+(?:id|name)[:\s]+([A-Za-z0-9_\-\.]+)",
            r"(GRCh\d+|GRCm\d+|hg\d+|mm\d+)",
            r"--genome[=\s]+([A-Za-z0-9_\-\.]+)",
        ]

        for pattern in genome_patterns:
            match = re.search(pattern, error_logs, re.IGNORECASE)
            if match:
                return match.group(1)

        return None

    def generate_fix_plan(
        self,
        context: FixContext,
        issues: List[Dict[str, Any]]
    ) -> Optional[Any]:
        """
        生成修复计划

        为缺失的基因组生成下载和构建索引的计划
        """
        from ...types import FixPlan

        if not issues:
            return None

        # 只处理第一个 missing_reference_genome issue
        issue = next((i for i in issues if i["type"] == "missing_reference_genome"), None)
        if not issue:
            return None

        genome_id = issue.get("genome_id", "unknown")

        # 检查是否是已知的基因组
        genome_info = self.COMMON_GENOMES.get(genome_id)

        if not genome_info:
            # 未知基因组，提供通用建议
            fix_actions = [
                FixAction(
                    type=ActionType.USER_ACTION_REQUIRED,
                    description=f"未知的基因组 ID: {genome_id}",
                    details={
                        "genome_id": genome_id,
                        "message": "该基因组不在预定义列表中，需要手动配置",
                        "available_genomes": list(self.COMMON_GENOMES.keys()),
                    },
                    risk_level="low",
                )
            ]
        else:
            # 已知基因组，生成下载和构建索引的计划
            fix_actions = [
                FixAction(
                    type=ActionType.DOWNLOAD_REFERENCE_GENOME,
                    description=f"下载参考基因组 {genome_id}",
                    details={
                        "genome_id": genome_id,
                        "species": genome_info["species"],
                        "assembly": genome_info["assembly"],
                        "size_gb": genome_info["size_gb"],
                        "available_sources": genome_info["sources"],
                        "recommended_source": "igenomes",  # 默认推荐 iGenomes
                    },
                    risk_level="low",
                ),
                FixAction(
                    type=ActionType.BUILD_GENOME_INDEX,
                    description=f"构建基因组索引",
                    details={
                        "genome_id": genome_id,
                        "index_types": ["star", "bowtie2"],  # 根据 pipeline 类型确定
                        "estimated_time_hours": 3,
                    },
                    risk_level="low",
                ),
            ]

        return FixPlan(
            fixer_name=self.name,
            issue_type="missing_reference_genome",
            description=f"修复缺失的参考基因组: {genome_id}",
            fix_actions=fix_actions,
            risk_level=RiskLevel.LOW,
            estimated_cost=0.0,  # 不涉及云资源费用
            confidence_score=0.9,
        )

    async def apply_fix(
        self,
        context: FixContext,
        fix_plan: Any,
        sa_session: Any,
    ) -> AutoFixResult:
        """
        应用修复

        由于下载和构建索引是耗时操作，这里不直接执行，
        而是创建异步任务并返回任务 ID
        """
        start_time = datetime.now()

        try:
            # 检查权限
            allowed, error_msg = self.check_permissions(context, sa_session)
            if not allowed:
                return AutoFixResult(
                    fix_id=None,
                    status=FixStatus.FAILED,
                    fixer_name=self.name,
                    fix_type="missing_reference_genome",
                    fix_actions=fix_plan.fix_actions,
                    risk_level=fix_plan.risk_level,
                    success=False,
                    error_message=error_msg,
                )

            # 对于参考基因组修复，我们不自动执行下载
            # 而是标记为需要用户确认
            return AutoFixResult(
                fix_id=None,
                status=FixStatus.PENDING,
                fixer_name=self.name,
                fix_type="missing_reference_genome",
                fix_actions=fix_plan.fix_actions,
                risk_level=fix_plan.risk_level,
                success=False,
                error_message="需要用户确认后通过 API 执行下载操作",
                auto_approved=False,
                user_approved=False,
                execution_time_seconds=(datetime.now() - start_time).total_seconds(),
            )

        except Exception as e:
            log.error(f"Error applying reference genome fix: {e}")
            return AutoFixResult(
                fix_id=None,
                status=FixStatus.FAILED,
                fixer_name=self.name,
                fix_type="missing_reference_genome",
                fix_actions=fix_plan.fix_actions,
                risk_level=fix_plan.risk_level,
                success=False,
                error_message=str(e),
                execution_time_seconds=(datetime.now() - start_time).total_seconds(),
            )

    # ========== API Methods (供 REST API 调用) ==========

    def list_available_genomes(
        self,
        species: Optional[str] = None,
        source: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        列出可用的参考基因组

        Args:
            species: 物种名称（可选）
            source: 数据源（可选）

        Returns:
            可用基因组列表
        """
        genomes = []

        for genome_id, info in self.COMMON_GENOMES.items():
            # 过滤条件
            if species and info["species"] != species:
                continue
            if source and source not in info["sources"]:
                continue

            # 检查本地是否已存在
            genome_path = Path(self.genome_base_path) / genome_id
            available_locally = genome_path.exists()

            # 检查索引是否存在
            has_star_index = (genome_path / "STAR").exists() if available_locally else False
            has_bowtie2_index = (genome_path / "Bowtie2").exists() if available_locally else False

            genomes.append({
                "genome_id": genome_id,
                "species": info["species"],
                "assembly": info["assembly"],
                "available_locally": available_locally,
                "has_star_index": has_star_index,
                "has_bowtie2_index": has_bowtie2_index,
                "path": str(genome_path) if available_locally else None,
                "size_gb": info["size_gb"],
                "available_sources": info["sources"],
            })

        return {
            "genomes": genomes,
            "total": len(genomes),
        }

    def get_genome_sources(self, genome_id: str) -> Dict[str, Any]:
        """
        获取指定基因组的可用下载源

        Args:
            genome_id: 基因组 ID

        Returns:
            下载源列表
        """
        genome_info = self.COMMON_GENOMES.get(genome_id)
        if not genome_info:
            raise ValueError(f"Unknown genome ID: {genome_id}")

        sources = []
        for source_key in genome_info["sources"]:
            source_info = self.GENOME_SOURCES.get(source_key)
            if source_info:
                sources.append({
                    "source": source_info["name"],
                    "url": self._get_download_url(genome_id, source_key),
                    "description": source_info["description"],
                    "size_gb": genome_info["size_gb"],
                })

        return {
            "genome_id": genome_id,
            "species": genome_info["species"],
            "assembly": genome_info["assembly"],
            "available_sources": sources,
        }

    def _get_download_url(self, genome_id: str, source: str) -> str:
        """
        构建下载 URL

        Args:
            genome_id: 基因组 ID
            source: 数据源

        Returns:
            下载 URL
        """
        source_info = self.GENOME_SOURCES.get(source)
        if not source_info:
            return ""

        base_url = source_info["base_url"]

        # 根据不同的源构建 URL
        if source == "igenomes":
            # iGenomes 格式: s3://ngi-igenomes/igenomes/Homo_sapiens/NCBI/GRCh38/
            genome_info = self.COMMON_GENOMES.get(genome_id, {})
            species = genome_info.get("species", "").replace(" ", "_")
            return f"{base_url}{species}/NCBI/{genome_id}/"

        elif source == "ensembl":
            # Ensembl 格式: ftp://ftp.ensembl.org/pub/release-110/fasta/homo_sapiens/
            return f"{base_url}current/fasta/"

        elif source == "ucsc":
            # UCSC 格式: https://hgdownload.soe.ucsc.edu/goldenPath/hg38/
            return f"{base_url}{genome_id}/"

        return base_url
