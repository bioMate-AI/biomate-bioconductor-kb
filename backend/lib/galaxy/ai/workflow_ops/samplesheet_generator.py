"""
Samplesheet Generator for nf-core Pipelines
自动生成和验证 nf-core pipeline 的 samplesheet 文件
"""
import csv
import os
from pathlib import Path
from typing import List, Dict, Tuple, Optional


class SamplesheetGenerator:
    """生成符合 nf-core 标准的 samplesheet"""

    # 不同 pipeline 的 samplesheet 格式定义
    PIPELINE_FORMATS = {
        'clipseq': {
            'columns': ['sample', 'fastq'],
            'description': 'CLIP-seq samplesheet: sample name and path to FastQ file',
            'example': [
                ['sample', 'fastq'],
                ['exp1_rep1', '/path/to/clip0001_01.fastq.gz'],
                ['exp1_rep2', '/path/to/clip0001_02.fastq.gz'],
            ],
            'requirements': [
                'FastQ files must be gzipped (.fastq.gz or .fq.gz)',
                'Only single-end reads are supported',
                'Sample names must be unique'
            ]
        },
        'smrnaseq': {
            'columns': ['sample', 'fastq'],
            'description': 'smRNA-seq samplesheet: sample name and path to FastQ file',
            'example': [
                ['sample', 'fastq'],
                ['sample1', '/path/to/sample1.fastq.gz'],
                ['sample2', '/path/to/sample2.fastq.gz'],
            ],
            'requirements': [
                'FastQ files must be gzipped',
                'Sample names must be unique'
            ]
        },
        'rnaseq': {
            'columns': ['sample', 'fastq_1', 'fastq_2', 'strandedness'],
            'description': 'RNA-seq samplesheet: sample, paired-end FASTQs, and strandedness',
            'example': [
                ['sample', 'fastq_1', 'fastq_2', 'strandedness'],
                ['sample1', '/path/to/sample1_R1.fastq.gz', '/path/to/sample1_R2.fastq.gz', 'auto'],
                ['sample2', '/path/to/sample2_R1.fastq.gz', '/path/to/sample2_R2.fastq.gz', 'auto'],
            ],
            'requirements': [
                'FastQ files must be gzipped',
                'strandedness can be: auto, forward, reverse, or unstranded'
            ]
        }
    }

    @classmethod
    def get_pipeline_format(cls, pipeline_name: str) -> Optional[Dict]:
        """获取指定 pipeline 的 samplesheet 格式"""
        # 从完整名称中提取 pipeline 核心名称
        # 例如: nf-core/clipseq, nf_core_clipseq, clipseq_1766498042
        for key in cls.PIPELINE_FORMATS.keys():
            if key in pipeline_name.lower():
                return cls.PIPELINE_FORMATS[key]
        return None

    @classmethod
    def generate_samplesheet(
        cls,
        pipeline_name: str,
        fastq_files: List[str],
        output_path: str,
        sample_prefix: str = "sample"
    ) -> Tuple[bool, str]:
        """
        生成 samplesheet 文件

        Args:
            pipeline_name: Pipeline 名称 (如 'clipseq', 'smrnaseq')
            fastq_files: FastQ 文件路径列表
            output_path: 输出的 samplesheet 文件路径
            sample_prefix: 样本名称前缀

        Returns:
            (success, message): 成功标志和消息
        """
        format_info = cls.get_pipeline_format(pipeline_name)
        if not format_info:
            return False, f"Unknown pipeline: {pipeline_name}"

        try:
            # 验证 FastQ 文件
            valid_files = []
            for fq in fastq_files:
                if not fq.endswith(('.fastq.gz', '.fq.gz', '.fastq', '.fq')):
                    continue
                valid_files.append(fq)

            if not valid_files:
                return False, "No valid FastQ files found"

            # 生成 samplesheet
            with open(output_path, 'w', newline='') as f:
                writer = csv.writer(f)

                # 写入表头
                writer.writerow(format_info['columns'])

                # 写入数据行
                for idx, fq_path in enumerate(valid_files, 1):
                    sample_name = f"{sample_prefix}{idx}"

                    if pipeline_name in ['clipseq', 'smrnaseq']:
                        writer.writerow([sample_name, fq_path])
                    elif pipeline_name == 'rnaseq':
                        # RNA-seq 需要处理 paired-end
                        # 这里简化处理，假设是 single-end 或只有 R1
                        writer.writerow([sample_name, fq_path, '', 'auto'])

            return True, f"Samplesheet generated: {output_path}"

        except Exception as e:
            return False, f"Error generating samplesheet: {str(e)}"

    @classmethod
    def validate_samplesheet(
        cls,
        samplesheet_path: str,
        pipeline_name: str
    ) -> Tuple[bool, List[str]]:
        """
        验证 samplesheet 格式是否正确

        Returns:
            (is_valid, errors): 是否有效和错误列表
        """
        format_info = cls.get_pipeline_format(pipeline_name)
        if not format_info:
            return False, [f"Unknown pipeline: {pipeline_name}"]

        errors = []

        # 检查文件是否存在
        if not os.path.exists(samplesheet_path):
            return False, [f"Samplesheet file not found: {samplesheet_path}"]

        try:
            with open(samplesheet_path, 'r') as f:
                reader = csv.reader(f)
                rows = list(reader)

            # 检查是否有数据
            if len(rows) < 2:
                errors.append("Samplesheet has no data rows")
                return False, errors

            # 检查表头
            header = rows[0]
            expected_columns = format_info['columns']

            if header != expected_columns:
                errors.append(f"Invalid header. Expected: {expected_columns}, Got: {header}")

            # 检查数据行
            sample_names = set()
            for row_idx, row in enumerate(rows[1:], 2):
                # 检查列数
                if len(row) != len(expected_columns):
                    errors.append(f"Row {row_idx}: Expected {len(expected_columns)} columns, got {len(row)}")
                    continue

                # 检查样本名称唯一性
                sample_name = row[0]
                if sample_name in sample_names:
                    errors.append(f"Row {row_idx}: Duplicate sample name: {sample_name}")
                sample_names.add(sample_name)

                # 检查 FastQ 文件路径
                fastq_col_idx = expected_columns.index('fastq') if 'fastq' in expected_columns else 1
                fastq_path = row[fastq_col_idx]

                if not fastq_path:
                    errors.append(f"Row {row_idx}: Empty FastQ path")
                elif not fastq_path.endswith(('.fastq.gz', '.fq.gz', '.fastq', '.fq')):
                    errors.append(f"Row {row_idx}: Invalid FastQ file extension: {fastq_path}")

            return len(errors) == 0, errors

        except Exception as e:
            return False, [f"Error reading samplesheet: {str(e)}"]

    @classmethod
    def get_example_samplesheet(cls, pipeline_name: str) -> Optional[str]:
        """获取 samplesheet 示例内容"""
        format_info = cls.get_pipeline_format(pipeline_name)
        if not format_info:
            return None

        lines = []
        for row in format_info['example']:
            lines.append(','.join(row))

        return '\n'.join(lines)

    @classmethod
    def get_format_help(cls, pipeline_name: str) -> str:
        """获取 samplesheet 格式帮助信息"""
        format_info = cls.get_pipeline_format(pipeline_name)
        if not format_info:
            return f"No format information available for pipeline: {pipeline_name}"

        help_text = []
        help_text.append(f"=== {pipeline_name.upper()} Samplesheet Format ===\n")
        help_text.append(f"Description: {format_info['description']}\n")
        help_text.append(f"Columns: {', '.join(format_info['columns'])}\n")
        help_text.append("\nRequirements:")
        for req in format_info['requirements']:
            help_text.append(f"  • {req}")
        help_text.append("\n\nExample:")
        help_text.append(cls.get_example_samplesheet(pipeline_name))

        return '\n'.join(help_text)


if __name__ == '__main__':
    # 测试代码
    print("Testing SamplesheetGenerator...")

    # 打印 clipseq 格式帮助
    print("\n" + "="*60)
    print(SamplesheetGenerator.get_format_help('clipseq'))

    # 打印 smrnaseq 格式帮助
    print("\n" + "="*60)
    print(SamplesheetGenerator.get_format_help('smrnaseq'))

    # 生成示例 samplesheet
    print("\n" + "="*60)
    print("\nGenerating example samplesheet...")

    test_files = [
        '/path/to/sample1.fastq.gz',
        '/path/to/sample2.fastq.gz',
        '/path/to/sample3.fastq.gz'
    ]

    success, msg = SamplesheetGenerator.generate_samplesheet(
        pipeline_name='clipseq',
        fastq_files=test_files,
        output_path='/tmp/test_samplesheet.csv',
        sample_prefix='exp_'
    )

    print(f"Generation result: {msg}")

    if success:
        with open('/tmp/test_samplesheet.csv', 'r') as f:
            print("\nGenerated samplesheet content:")
            print(f.read())
