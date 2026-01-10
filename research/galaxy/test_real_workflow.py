#!/usr/bin/env python3
"""
真实的生物信息学Workflow测试示例
演示RNA-seq分析流程的云端执行
"""

import asyncio
import os
import sys
import tempfile
from pathlib import Path

# 设置Python路径
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor')

from galaxy_cloud import CloudExecutorFactory, CloudConfig
from galaxy_cloud.core.job import JobSpec, ResourceSpec, ContainerSpec


class RNASeqWorkflow:
    """RNA-seq分析工作流"""

    def __init__(self, executor):
        self.executor = executor
        self.results = {}

    async def step1_quality_control(self, input_files):
        """步骤1: 质量控制"""
        print("🔍 步骤1: 质量控制分析...")

        job_spec = JobSpec(
            job_id='rnaseq-fastqc-001',
            name='RNA-seq Quality Control',
            container=ContainerSpec(
                image='staphb/fastqc:latest',
                command=['fastqc'],
                args=[
                    '--outdir', '/output',
                    '--threads', '2',
                    '/input/reads_R1.fastq.gz',
                    '/input/reads_R2.fastq.gz'
                ],
                env={'FASTQC_THREADS': '2'}
            ),
            resources=ResourceSpec(
                cpus=2,
                memory_mb=4096,
                disk_gb=20
            ),
            input_files=input_files,
            output_files={
                'output/reads_R1_fastqc.html': '/tmp/qc_report_R1.html',
                'output/reads_R2_fastqc.html': '/tmp/qc_report_R2.html',
                'output/reads_R1_fastqc.zip': '/tmp/qc_data_R1.zip',
                'output/reads_R2_fastqc.zip': '/tmp/qc_data_R2.zip'
            },
            timeout_seconds=1800
        )

        job_id = await self.executor.submit_job(job_spec)
        result = await self.executor.wait_for_completion(job_id)

        self.results['quality_control'] = result
        return result

    async def step2_trimming(self, input_files):
        """步骤2: 序列修剪"""
        print("✂️ 步骤2: 序列质量修剪...")

        job_spec = JobSpec(
            job_id='rnaseq-trimmomatic-001',
            name='RNA-seq Read Trimming',
            container=ContainerSpec(
                image='staphb/trimmomatic:latest',
                command=['trimmomatic'],
                args=[
                    'PE',
                    '-phred33',
                    '-threads', '4',
                    '/input/reads_R1.fastq.gz',
                    '/input/reads_R2.fastq.gz',
                    '/output/trimmed_R1.fastq.gz',
                    '/output/unpaired_R1.fastq.gz',
                    '/output/trimmed_R2.fastq.gz',
                    '/output/unpaired_R2.fastq.gz',
                    'ILLUMINACLIP:TruSeq3-PE.fa:2:30:10',
                    'LEADING:3',
                    'TRAILING:3',
                    'SLIDINGWINDOW:4:15',
                    'MINLEN:36'
                ]
            ),
            resources=ResourceSpec(
                cpus=4,
                memory_mb=8192,
                disk_gb=50
            ),
            input_files=input_files,
            output_files={
                'output/trimmed_R1.fastq.gz': '/tmp/trimmed_R1.fastq.gz',
                'output/trimmed_R2.fastq.gz': '/tmp/trimmed_R2.fastq.gz'
            },
            timeout_seconds=3600
        )

        job_id = await self.executor.submit_job(job_spec)
        result = await self.executor.wait_for_completion(job_id)

        self.results['trimming'] = result
        return result

    async def step3_alignment(self, input_files, reference_genome):
        """步骤3: 序列比对"""
        print("🎯 步骤3: 序列比对到参考基因组...")

        job_spec = JobSpec(
            job_id='rnaseq-star-001',
            name='RNA-seq STAR Alignment',
            container=ContainerSpec(
                image='quay.io/biocontainers/star:2.7.10a--h9ee0642_0',
                command=['STAR'],
                args=[
                    '--runThreadN', '8',
                    '--genomeDir', '/reference/star_index',
                    '--readFilesIn',
                    '/input/trimmed_R1.fastq.gz',
                    '/input/trimmed_R2.fastq.gz',
                    '--readFilesCommand', 'zcat',
                    '--outFileNamePrefix', '/output/',
                    '--outSAMtype', 'BAM', 'SortedByCoordinate',
                    '--outSAMunmapped', 'Within',
                    '--quantMode', 'GeneCounts',
                    '--sjdbGTFfile', '/reference/annotations.gtf'
                ]
            ),
            resources=ResourceSpec(
                cpus=8,
                memory_mb=32768,
                disk_gb=100
            ),
            input_files={
                **input_files,
                **reference_genome
            },
            output_files={
                'output/Aligned.sortedByCoord.out.bam': '/tmp/aligned.bam',
                'output/ReadsPerGene.out.tab': '/tmp/gene_counts.tab',
                'output/Log.final.out': '/tmp/alignment_log.txt'
            },
            timeout_seconds=7200
        )

        job_id = await self.executor.submit_job(job_spec)
        result = await self.executor.wait_for_completion(job_id)

        self.results['alignment'] = result
        return result

    async def step4_quantification(self, input_files, reference_files):
        """步骤4: 基因表达定量"""
        print("📊 步骤4: 基因表达定量...")

        job_spec = JobSpec(
            job_id='rnaseq-featurecounts-001',
            name='RNA-seq Gene Quantification',
            container=ContainerSpec(
                image='quay.io/biocontainers/subread:2.0.1--hed695b0_0',
                command=['featureCounts'],
                args=[
                    '-T', '4',
                    '-p',  # paired-end
                    '-a', '/reference/annotations.gtf',
                    '-o', '/output/gene_counts.txt',
                    '-g', 'gene_id',
                    '-t', 'exon',
                    '/input/aligned.bam'
                ]
            ),
            resources=ResourceSpec(
                cpus=4,
                memory_mb=8192,
                disk_gb=30
            ),
            input_files={
                **input_files,
                **reference_files
            },
            output_files={
                'output/gene_counts.txt': '/tmp/final_gene_counts.txt',
                'output/gene_counts.txt.summary': '/tmp/count_summary.txt'
            },
            timeout_seconds=3600
        )

        job_id = await self.executor.submit_job(job_spec)
        result = await self.executor.wait_for_completion(job_id)

        self.results['quantification'] = result
        return result

    async def run_complete_workflow(self, sample_data, reference_data):
        """执行完整的RNA-seq分析流程"""
        print("🧬 开始RNA-seq完整分析流程...")
        print("=" * 60)

        try:
            # 步骤1: 质量控制
            qc_result = await self.step1_quality_control(sample_data)
            if qc_result.status.value != 'completed':
                raise Exception(f"质量控制失败: {qc_result.error_message}")

            # 步骤2: 序列修剪
            trimming_result = await self.step2_trimming(sample_data)
            if trimming_result.status.value != 'completed':
                raise Exception(f"序列修剪失败: {trimming_result.error_message}")

            # 更新输入文件为修剪后的序列
            trimmed_files = {
                '/tmp/trimmed_R1.fastq.gz': 'input/trimmed_R1.fastq.gz',
                '/tmp/trimmed_R2.fastq.gz': 'input/trimmed_R2.fastq.gz'
            }

            # 步骤3: 序列比对
            alignment_result = await self.step3_alignment(trimmed_files, reference_data)
            if alignment_result.status.value != 'completed':
                raise Exception(f"序列比对失败: {alignment_result.error_message}")

            # 更新输入文件为比对结果
            aligned_files = {
                '/tmp/aligned.bam': 'input/aligned.bam'
            }

            # 步骤4: 基因表达定量
            quantification_result = await self.step4_quantification(aligned_files, reference_data)
            if quantification_result.status.value != 'completed':
                raise Exception(f"基因定量失败: {quantification_result.error_message}")

            print("\n🎉 RNA-seq分析流程成功完成！")
            return True

        except Exception as e:
            print(f"\n❌ 工作流执行失败: {e}")
            return False

    def print_summary(self):
        """打印分析结果摘要"""
        print("\n📋 分析结果摘要:")
        print("-" * 40)

        for step_name, result in self.results.items():
            if result:
                print(f"{step_name:15} | {result.status.value:10} | 耗时: {self._calculate_duration(result)}")
                if result.cloud_metadata:
                    cpu_usage = result.cloud_metadata.get('cpu_usage', 'N/A')
                    memory_usage = result.cloud_metadata.get('memory_usage_mb', 'N/A')
                    print(f"                | CPU: {cpu_usage} | Memory: {memory_usage}MB")
            else:
                print(f"{step_name:15} | 未执行")

    def _calculate_duration(self, result):
        """计算作业执行时间"""
        if result.started_at and result.finished_at:
            duration = result.finished_at - result.started_at
            return f"{duration.total_seconds():.1f}s"
        return "N/A"


async def test_rnaseq_workflow():
    """测试完整的RNA-seq工作流"""
    print("🧬 RNA-seq工作流测试开始\n")

    # 模拟输入数据文件
    sample_data = {
        '/path/to/sample_R1.fastq.gz': 'input/reads_R1.fastq.gz',
        '/path/to/sample_R2.fastq.gz': 'input/reads_R2.fastq.gz'
    }

    # 模拟参考数据文件
    reference_data = {
        '/path/to/star_index/': 'reference/star_index/',
        '/path/to/annotations.gtf': 'reference/annotations.gtf'
    }

    # 选择执行器
    executor_type = os.getenv('EXECUTOR_TYPE', 'mock')  # 默认使用mock

    if executor_type == 'aws':
        config = {
            'enabled': True,
            'region': os.getenv('AWS_REGION', 'us-east-1'),
            'batch_queue': os.getenv('AWS_BATCH_QUEUE'),
            's3_bucket': os.getenv('AWS_S3_BUCKET'),
            'spot_allocation': 'spot'  # 使用Spot实例节省成本
        }
        executor_name = 'aws-batch'
    else:
        config = {'provider': 'mock', 'enabled': True}
        executor_name = 'mock'

    try:
        if CloudExecutorFactory.is_available(executor_name):
            executor = CloudExecutorFactory.create(executor_name, config)
            workflow = RNASeqWorkflow(executor)

            async with executor:
                success = await workflow.run_complete_workflow(sample_data, reference_data)

                if success:
                    workflow.print_summary()
                    print("\n✅ RNA-seq工作流测试成功！")
                else:
                    print("\n❌ RNA-seq工作流测试失败！")

        else:
            print(f"❌ 执行器 {executor_name} 不可用")

    except Exception as e:
        print(f"❌ 工作流测试异常: {e}")


async def test_parallel_samples():
    """测试多样本并行处理"""
    print("\n🔄 测试多样本并行处理...")

    samples = [
        {'id': 'sample1', 'r1': '/data/sample1_R1.fastq.gz', 'r2': '/data/sample1_R2.fastq.gz'},
        {'id': 'sample2', 'r1': '/data/sample2_R1.fastq.gz', 'r2': '/data/sample2_R2.fastq.gz'},
        {'id': 'sample3', 'r1': '/data/sample3_R1.fastq.gz', 'r2': '/data/sample3_R2.fastq.gz'}
    ]

    config = {'provider': 'mock', 'enabled': True}

    try:
        if CloudExecutorFactory.is_available('mock'):
            executor = CloudExecutorFactory.create('mock', config)

            # 创建并行作业
            job_specs = []
            for sample in samples:
                job_spec = JobSpec(
                    job_id=f'parallel-{sample["id"]}',
                    name=f'Parallel Analysis {sample["id"]}',
                    container=ContainerSpec(
                        image='rnaseq-pipeline:latest',
                        command=['python'],
                        args=['/pipeline/run_analysis.py', '--sample', sample['id']]
                    ),
                    resources=ResourceSpec(cpus=4, memory_mb=16384),
                    input_files={
                        sample['r1']: f'input/{sample["id"]}_R1.fastq.gz',
                        sample['r2']: f'input/{sample["id"]}_R2.fastq.gz'
                    }
                )
                job_specs.append(job_spec)

            async with executor:
                # 批量提交
                print(f"🚀 提交{len(job_specs)}个并行作业...")
                job_ids = await executor.bulk_submit(job_specs)
                print(f"✅ 作业已提交: {job_ids}")

                # 批量监控
                completed = 0
                while completed < len(job_ids):
                    await asyncio.sleep(5)
                    statuses = await executor.bulk_status(job_ids)

                    completed = sum(1 for status in statuses.values()
                                  if status.value in ['completed', 'failed', 'cancelled'])

                    print(f"📊 进度: {completed}/{len(job_ids)} 完成")

                    if completed == len(job_ids):
                        break

                print("✅ 所有并行作业完成！")

        else:
            print("❌ Mock执行器不可用")

    except Exception as e:
        print(f"❌ 并行测试失败: {e}")


async def main():
    """主测试函数"""
    # 1. 完整RNA-seq工作流测试
    await test_rnaseq_workflow()

    # 2. 并行样本处理测试
    await test_parallel_samples()


if __name__ == '__main__':
    asyncio.run(main())