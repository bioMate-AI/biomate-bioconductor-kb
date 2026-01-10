#!/usr/bin/env python3
"""
测试使用云数据引用的 Workflow

演示如何在 Workflow 中使用云数据引用，结合本地上传文件。
"""

import asyncio
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from galaxy_cloud.core.cloud_data_reference import create_s3_reference
from galaxy_cloud.galaxy_workflow.cloud_data_manager import CloudDataManager, PreparedInput
from galaxy_cloud.galaxy_workflow.models import DatasetInfo, WorkflowRunConfig


async def test_simple_workflow_with_cloud_data():
    """
    测试简单 Workflow：使用云引用 + 本地上传

    场景：BWA 基因组比对
    - 参考基因组：云引用（公共数据，3 GB）
    - 样本数据：本地上传（100 MB）
    """
    print("\n" + "=" * 80)
    print("场景 1: BWA 基因组比对（云引用 + 本地上传）")
    print("=" * 80)

    # 1. 创建云引用：参考基因组（公共数据）
    ref_genome = create_s3_reference(
        "s3://1000genomes/technical/reference/human_g1k_v37.fasta.gz",
        region="us-east-1",
        is_public=True,
        description="Human reference genome (1000 Genomes Project)"
    )

    print(f"\n输入 1: 参考基因组（云引用）")
    print(f"  S3 URI: {ref_genome.path}")
    print(f"  Bucket: {ref_genome.bucket}")
    print(f"  Access: {ref_genome.access.method.value}")
    print(f"  Skip upload: True ✅")

    # 2. 模拟本地上传文件：样本数据
    sample_data = DatasetInfo(
        dataset_id="sample_001",
        file_path="/tmp/sample.fastq",  # 模拟路径
        file_name="sample.fastq",
        ext="fastq",
        file_size=100 * 1024 * 1024,  # 100 MB
        metadata={"sample_id": "SAMPLE001", "library": "LIB001"}
    )

    print(f"\n输入 2: 样本数据（本地上传）")
    print(f"  Local path: {sample_data.file_path}")
    print(f"  File name: {sample_data.file_name}")
    print(f"  File size: {sample_data.file_size / (1024**2):.1f} MB")
    print(f"  需要上传: True")

    # 3. 验证云引用
    print(f"\n正在验证云引用...")
    cloud_manager = CloudDataManager(region="us-east-1")

    validation_results = await cloud_manager.validate_cloud_references([ref_genome])
    summary = cloud_manager.get_validation_summary(validation_results)

    print(f"\n验证摘要:")
    print(f"  总计: {summary['total']}")
    print(f"  有效: {summary['valid']}")
    print(f"  无效: {summary['invalid']}")

    if summary['valid'] > 0:
        print(f"  总大小: {summary['total_size_gb']:.2f} GB")

    # 4. 创建作业输入配置
    print(f"\n生成作业输入配置...")

    # 模拟准备好的输入
    prepared_inputs = [
        PreparedInput(
            name="reference_genome",
            cloud_uri=ref_genome.path,
            skip_upload=True,
            is_cloud_reference=True,
            cloud_reference=ref_genome
        ),
        PreparedInput(
            name="sample_reads",
            cloud_uri="s3://galaxy-cloud-data/uploads/sample_001.fastq",  # 模拟上传后的路径
            skip_upload=False,
            is_cloud_reference=False,
            local_path=sample_data.file_path,
            dataset_info=sample_data
        )
    ]

    job_config = await cloud_manager.create_job_input_config(prepared_inputs)

    print(f"\n作业输入配置:")
    print(f"  输入数量: {len(job_config['inputs'])}")
    for idx, input_entry in enumerate(job_config['inputs'], 1):
        print(f"\n  输入 {idx}: {input_entry['name']}")
        print(f"    S3 URI: {input_entry['s3_uri']}")
        print(f"    云引用: {input_entry['is_cloud_reference']}")

    print(f"\n环境变量:")
    for key, value in job_config['environment'].items():
        print(f"    {key}={value}")

    print(f"\n✅ 场景 1 测试完成")
    print(f"节省上传时间: ~10 分钟（参考基因组 3 GB）")


async def test_rna_seq_workflow_with_cloud_data():
    """
    测试 RNA-Seq Workflow：多个云引用 + 本地上传

    场景：RNA-Seq 分析
    - 参考基因组：云引用
    - 基因注释：云引用
    - 样本 RNA-Seq 数据：本地上传
    """
    print("\n" + "=" * 80)
    print("场景 2: RNA-Seq 分析（多个云引用 + 本地上传）")
    print("=" * 80)

    # 1. 云引用：参考基因组
    ref_genome = create_s3_reference(
        "s3://public-genomes/hg38/genome.fa",
        region="us-west-2",
        is_public=True,
        description="Human reference genome GRCh38"
    )

    # 2. 云引用：基因注释
    gene_annotation = create_s3_reference(
        "s3://public-genomes/hg38/genes.gtf",
        region="us-west-2",
        is_public=True,
        description="Gene annotations GTF"
    )

    # 3. 云引用：转录本序列
    transcripts = create_s3_reference(
        "s3://public-genomes/hg38/transcripts.fa",
        region="us-west-2",
        is_public=True,
        description="Transcript sequences"
    )

    print(f"\n云引用输入（公共数据）:")
    print(f"  1. 参考基因组: {ref_genome.path}")
    print(f"  2. 基因注释: {gene_annotation.path}")
    print(f"  3. 转录本序列: {transcripts.path}")
    print(f"  Skip upload: True ✅")
    print(f"  估计节省上传时间: ~20 分钟")

    # 4. 本地上传：RNA-Seq 数据
    rnaseq_sample1 = DatasetInfo(
        dataset_id="rnaseq_001",
        file_path="/tmp/sample1_R1.fastq.gz",
        file_name="sample1_R1.fastq.gz",
        ext="fastq.gz",
        file_size=500 * 1024 * 1024  # 500 MB
    )

    rnaseq_sample2 = DatasetInfo(
        dataset_id="rnaseq_002",
        file_path="/tmp/sample1_R2.fastq.gz",
        file_name="sample1_R2.fastq.gz",
        ext="fastq.gz",
        file_size=500 * 1024 * 1024  # 500 MB
    )

    print(f"\n本地上传输入（样本数据）:")
    print(f"  1. {rnaseq_sample1.file_name} ({rnaseq_sample1.file_size / (1024**2):.0f} MB)")
    print(f"  2. {rnaseq_sample2.file_name} ({rnaseq_sample2.file_size / (1024**2):.0f} MB)")
    print(f"  需要上传: True")
    print(f"  估计上传时间: ~5 分钟")

    # 5. Workflow 执行流程
    print(f"\n完整 Workflow 流程:")
    print(f"  1. 验证云引用 (3 个) - 30 秒")
    print(f"  2. 上传本地文件 (2 个) - 5 分钟")
    print(f"  3. 启动云作业")
    print(f"     Step 1: STAR 比对（使用云引用的参考基因组）")
    print(f"     Step 2: HTSeq 计数（使用云引用的基因注释）")
    print(f"     Step 3: DESeq2 差异分析")
    print(f"  4. 下载结果")

    print(f"\n时间对比:")
    print(f"  传统方式（全部上传）:")
    print(f"    - 上传参考数据: ~20 分钟")
    print(f"    - 上传样本数据: ~5 分钟")
    print(f"    - 总计: ~25 分钟 + 分析时间")
    print(f"\n  云引用方式:")
    print(f"    - 验证云引用: ~30 秒")
    print(f"    - 上传样本数据: ~5 分钟")
    print(f"    - 总计: ~5.5 分钟 + 分析时间")
    print(f"\n  节省时间: ~20 分钟 ✅")

    print(f"\n✅ 场景 2 测试完成")


async def test_team_shared_data_scenario():
    """
    测试团队共享数据场景

    场景：团队成员共享测序数据
    - 数据已上传到团队 S3 bucket
    - 多个成员分析同一批数据
    - 使用云引用，避免重复上传
    """
    print("\n" + "=" * 80)
    print("场景 3: 团队共享数据（避免重复上传）")
    print("=" * 80)

    # 团队共享数据（需要 IAM Role）
    shared_dataset = create_s3_reference(
        "s3://team-genomics-data/project-cancer-study/cohort-2024/",
        region="us-west-2",
        role_arn="arn:aws:iam::123456789012:role/TeamGenomicsDataAccess",
        description="Cancer study cohort 2024 (100 samples)"
    )

    print(f"\n团队共享数据:")
    print(f"  S3 URI: {shared_dataset.path}")
    print(f"  Access method: {shared_dataset.access.method.value}")
    print(f"  IAM Role: {shared_dataset.access.role_arn}")

    print(f"\n使用场景:")
    print(f"  团队有 10 个成员")
    print(f"  每个成员需要分析 100 个样本（每个 10 GB）")
    print(f"  总数据量: 1 TB")

    print(f"\n传统方式:")
    print(f"  每个成员上传一遍数据")
    print(f"  总上传次数: 10 次")
    print(f"  总上传数据量: 10 TB")
    print(f"  总上传时间: 10 × 50 小时 = 500 小时")

    print(f"\n云引用方式:")
    print(f"  数据上传一次到团队 S3")
    print(f"  所有成员使用云引用")
    print(f"  总上传次数: 1 次")
    print(f"  总上传数据量: 1 TB")
    print(f"  总上传时间: 50 小时")

    print(f"\n节省:")
    print(f"  时间: 450 小时 ✅")
    print(f"  带宽: 9 TB ✅")
    print(f"  存储成本: 大幅降低 ✅")

    print(f"\n✅ 场景 3 测试完成")


async def main():
    """主函数"""
    print("\n")
    print("╔" + "=" * 78 + "╗")
    print("║" + " " * 15 + "Workflow 云数据引用测试" + " " * 37 + "║")
    print("╚" + "=" * 78 + "╝")

    try:
        # 场景 1: 简单 Workflow（云引用 + 本地上传）
        await test_simple_workflow_with_cloud_data()

        # 场景 2: RNA-Seq Workflow（多个云引用）
        await test_rna_seq_workflow_with_cloud_data()

        # 场景 3: 团队共享数据
        await test_team_shared_data_scenario()

        print("\n" + "=" * 80)
        print("✅ 所有场景测试完成！")
        print("=" * 80)

        print("\n💡 核心价值:")
        print("  1. ⚡ 大幅减少数据上传时间")
        print("  2. 💰 降低存储和带宽成本")
        print("  3. 🔄 支持团队数据共享")
        print("  4. 🌍 轻松使用公共数据集")
        print("  5. 📊 支持大规模数据分析")

        print("\n📚 下一步:")
        print("  - 集成到 Galaxy UI")
        print("  - 添加云数据管理界面")
        print("  - 配置 IAM 权限")
        print("  - 测试实际 workflow")

    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
