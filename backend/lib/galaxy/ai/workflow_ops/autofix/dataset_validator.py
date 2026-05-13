"""
数据集验证器
Dataset Validator

用于检测和验证 workflow 输入数据集的质量和大小
"""

import logging
import os
import gzip
import re
from pathlib import Path
from typing import Dict, List, Optional, Tuple

log = logging.getLogger(__name__)


class DatasetIssue:
    """数据集问题"""

    def __init__(self, severity: str, message: str, recommendation: str):
        self.severity = severity  # 'critical', 'warning', 'info'
        self.message = message
        self.recommendation = recommendation


class DatasetValidator:
    """数据集验证器"""

    # 最小文件大小阈值
    MIN_GENOME_SIZE = 1_000_000  # 1MB - 基因组应该至少 1MB
    MIN_GTF_SIZE = 10_000  # 10KB - GTF 文件应该至少 10KB
    MIN_FASTQ_READS = 1_000  # FASTQ 至少应该有 1000 条 reads

    # 超小数据集阈值（用于测试）
    TINY_GENOME_SIZE = 100_000  # 100KB
    TINY_GTF_SIZE = 1_000  # 1KB
    TINY_FASTQ_READS = 100  # 100 reads

    @staticmethod
    def validate_dataset(parameters: Dict[str, any]) -> List[DatasetIssue]:
        """
        验证数据集质量

        检查：
        1. 基因组文件大小
        2. GTF 文件大小
        3. FASTQ reads 数量
        4. 是否是超小测试数据

        Args:
            parameters: Workflow 参数字典

        Returns:
            数据集问题列表
        """
        issues = []

        log.info("🔍 Validating dataset quality...")

        # 1. 检查基因组文件
        fasta_path = parameters.get('fasta')
        if fasta_path and os.path.exists(fasta_path):
            genome_issues = DatasetValidator._check_genome_file(fasta_path)
            issues.extend(genome_issues)

        # 2. 检查 GTF 文件
        gtf_path = parameters.get('gtf')
        if gtf_path and os.path.exists(gtf_path):
            gtf_issues = DatasetValidator._check_gtf_file(gtf_path)
            issues.extend(gtf_issues)

        # 3. 检查 FASTQ 文件
        input_path = parameters.get('input')  # samplesheet
        if input_path and os.path.exists(input_path):
            fastq_issues = DatasetValidator._check_fastq_files(input_path)
            issues.extend(fastq_issues)

        # 4. 综合判断是否是测试数据集
        if DatasetValidator._is_test_dataset(parameters, issues):
            issues.append(DatasetIssue(
                severity='warning',
                message='检测到超小测试数据集',
                recommendation='这些数据仅适用于快速测试，建议使用真实数据或 nf-core test profile 进行完整测试'
            ))

        log.info(f"  Found {len(issues)} dataset issues")
        return issues

    @staticmethod
    def _check_genome_file(fasta_path: str) -> List[DatasetIssue]:
        """检查基因组文件"""
        issues = []

        file_size = os.path.getsize(fasta_path)

        # 检查是否是压缩文件
        is_compressed = fasta_path.endswith('.gz')

        # 估算解压后大小（压缩比约 1:4）
        estimated_size = file_size * 4 if is_compressed else file_size

        log.info(f"  Genome file size: {file_size:,} bytes (estimated uncompressed: {estimated_size:,})")

        if estimated_size < DatasetValidator.TINY_GENOME_SIZE:
            issues.append(DatasetIssue(
                severity='critical',
                message=f'基因组文件太小（{estimated_size:,} bytes < 100KB）',
                recommendation='这可能是一个测试文件，不足以进行真实分析。建议使用完整的染色体或基因组文件'
            ))
        elif estimated_size < DatasetValidator.MIN_GENOME_SIZE:
            issues.append(DatasetIssue(
                severity='warning',
                message=f'基因组文件较小（{estimated_size:,} bytes < 1MB）',
                recommendation='建议使用完整的基因组文件以获得更准确的结果'
            ))

        # 尝试读取序列数量
        try:
            seq_count = DatasetValidator._count_fasta_sequences(fasta_path)
            log.info(f"  Genome sequences: {seq_count}")

            if seq_count == 1:
                issues.append(DatasetIssue(
                    severity='info',
                    message='基因组只包含 1 条序列',
                    recommendation='如果这是完整基因组，这可能是病毒或质粒；如果是测试数据，建议使用更多序列'
                ))
        except Exception as e:
            log.warning(f"Failed to count sequences: {e}")

        return issues

    @staticmethod
    def _check_gtf_file(gtf_path: str) -> List[DatasetIssue]:
        """检查 GTF 文件"""
        issues = []

        file_size = os.path.getsize(gtf_path)
        is_compressed = gtf_path.endswith('.gz')
        estimated_size = file_size * 4 if is_compressed else file_size

        log.info(f"  GTF file size: {file_size:,} bytes (estimated uncompressed: {estimated_size:,})")

        if estimated_size < DatasetValidator.TINY_GTF_SIZE:
            issues.append(DatasetIssue(
                severity='critical',
                message=f'GTF 文件太小（{estimated_size:,} bytes < 1KB）',
                recommendation='GTF 文件过小，可能缺少必要的基因注释。建议使用完整的 GTF 文件'
            ))
        elif estimated_size < DatasetValidator.MIN_GTF_SIZE:
            issues.append(DatasetIssue(
                severity='warning',
                message=f'GTF 文件较小（{estimated_size:,} bytes < 10KB）',
                recommendation='GTF 文件可能不完整，建议使用标准的基因组注释文件（如 Ensembl GTF）'
            ))

        # 尝试统计 GTF 特征数量
        try:
            feature_count = DatasetValidator._count_gtf_features(gtf_path)
            log.info(f"  GTF features: {feature_count}")

            if feature_count < 10:
                issues.append(DatasetIssue(
                    severity='warning',
                    message=f'GTF 只包含 {feature_count} 个特征',
                    recommendation='特征数量太少，可能无法进行有效的基因注释分析'
                ))
        except Exception as e:
            log.warning(f"Failed to count GTF features: {e}")

        return issues

    @staticmethod
    def _check_fastq_files(samplesheet_path: str) -> List[DatasetIssue]:
        """检查 FASTQ 文件（通过 samplesheet）"""
        issues = []

        try:
            # 解析 samplesheet 获取 FASTQ 文件路径
            fastq_files = DatasetValidator._parse_samplesheet(samplesheet_path)

            log.info(f"  Found {len(fastq_files)} FASTQ files in samplesheet")

            for fastq_path in fastq_files[:3]:  # 只检查前 3 个
                if os.path.exists(fastq_path):
                    reads_count = DatasetValidator._count_fastq_reads(fastq_path)
                    log.info(f"  FASTQ {os.path.basename(fastq_path)}: {reads_count} reads")

                    if reads_count < DatasetValidator.TINY_FASTQ_READS:
                        issues.append(DatasetIssue(
                            severity='critical',
                            message=f'FASTQ 文件 {os.path.basename(fastq_path)} 只有 {reads_count} 条 reads',
                            recommendation='reads 数量太少（< 100），建议使用更多测序数据'
                        ))
                    elif reads_count < DatasetValidator.MIN_FASTQ_READS:
                        issues.append(DatasetIssue(
                            severity='warning',
                            message=f'FASTQ 文件 {os.path.basename(fastq_path)} 只有 {reads_count} 条 reads',
                            recommendation='reads 数量较少（< 1000），可能影响分析结果的可靠性'
                        ))

        except Exception as e:
            log.warning(f"Failed to check FASTQ files: {e}")

        return issues

    @staticmethod
    def _is_test_dataset(parameters: Dict, issues: List[DatasetIssue]) -> bool:
        """判断是否是测试数据集"""

        # 检查是否有多个 critical 或 warning 问题
        critical_count = sum(1 for issue in issues if issue.severity == 'critical')
        warning_count = sum(1 for issue in issues if issue.severity == 'warning')

        if critical_count >= 2 or (critical_count >= 1 and warning_count >= 2):
            return True

        # 检查文件名是否包含 test/tiny/demo 等关键字
        for key in ['fasta', 'gtf', 'input']:
            value = parameters.get(key, '')
            if any(keyword in value.lower() for keyword in ['test', 'tiny', 'demo', 'example']):
                return True

        return False

    @staticmethod
    def _count_fasta_sequences(fasta_path: str) -> int:
        """统计 FASTA 文件中的序列数量"""
        count = 0
        open_func = gzip.open if fasta_path.endswith('.gz') else open

        with open_func(fasta_path, 'rt') as f:
            for line in f:
                if line.startswith('>'):
                    count += 1
                    if count >= 100:  # 限制最多统计 100 条
                        break

        return count

    @staticmethod
    def _count_gtf_features(gtf_path: str) -> int:
        """统计 GTF 文件中的特征数量"""
        count = 0
        open_func = gzip.open if gtf_path.endswith('.gz') else open

        with open_func(gtf_path, 'rt') as f:
            for line in f:
                if not line.startswith('#'):
                    count += 1
                    if count >= 1000:  # 限制最多统计 1000 行
                        break

        return count

    @staticmethod
    def _count_fastq_reads(fastq_path: str, sample_size: int = 1000) -> int:
        """
        统计 FASTQ 文件中的 reads 数量（采样估算）

        Args:
            fastq_path: FASTQ 文件路径
            sample_size: 采样行数（FASTQ 每 4 行是一条 read）

        Returns:
            reads 数量（估算值）
        """
        try:
            open_func = gzip.open if fastq_path.endswith('.gz') else open

            with open_func(fastq_path, 'rt') as f:
                lines_count = 0
                for _ in f:
                    lines_count += 1
                    if lines_count >= sample_size * 4:  # 采样 sample_size 条 reads
                        break

            # 估算总 reads 数量
            sampled_reads = lines_count // 4
            return sampled_reads

        except Exception as e:
            log.warning(f"Failed to count FASTQ reads: {e}")
            return 0

    @staticmethod
    def _parse_samplesheet(samplesheet_path: str) -> List[str]:
        """解析 samplesheet 获取 FASTQ 文件路径"""
        fastq_files = []

        try:
            with open(samplesheet_path, 'r') as f:
                lines = f.readlines()

            # 跳过 header
            for line in lines[1:]:
                fields = line.strip().split(',')
                # 通常 fastq_1 在第 2 列，fastq_2 在第 3 列
                if len(fields) >= 2:
                    fastq1 = fields[1].strip()
                    if fastq1 and os.path.exists(fastq1):
                        fastq_files.append(fastq1)

                if len(fields) >= 3:
                    fastq2 = fields[2].strip()
                    if fastq2 and os.path.exists(fastq2):
                        fastq_files.append(fastq2)

        except Exception as e:
            log.warning(f"Failed to parse samplesheet: {e}")

        return fastq_files
