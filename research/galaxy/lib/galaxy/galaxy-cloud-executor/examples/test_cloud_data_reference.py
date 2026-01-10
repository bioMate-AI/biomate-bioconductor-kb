#!/usr/bin/env python3
"""
测试云数据引用功能

演示如何使用云数据引用功能，跳过数据上传步骤。
"""

import asyncio
import sys
from pathlib import Path

# 添加模块路径
sys.path.insert(0, str(Path(__file__).parent.parent))

from galaxy_cloud.core.cloud_data_reference import (
    CloudDataReference,
    CloudProvider,
    CloudDataAccess,
    AccessMethod,
    create_s3_reference
)
from galaxy_cloud.core.cloud_data_validator import (
    CloudDataValidator,
    validate_s3_reference
)


async def test_create_cloud_reference():
    """测试创建云数据引用"""
    print("\n" + "=" * 80)
    print("测试 1: 创建云数据引用")
    print("=" * 80)

    # 创建公共数据引用
    public_ref = create_s3_reference(
        "s3://1000genomes/phase3/data/HG00096/alignment/HG00096.chrom20.ILLUMINA.bwa.GBR.low_coverage.20120522.bam",
        region="us-east-1",
        is_public=True,
        description="1000 Genomes Project - Sample BAM file"
    )

    print(f"\n公共数据引用:")
    print(f"  Provider: {public_ref.provider.value}")
    print(f"  Path: {public_ref.path}")
    print(f"  Bucket: {public_ref.bucket}")
    print(f"  Key: {public_ref.key}")
    print(f"  Filename: {public_ref.filename}")
    print(f"  Access Method: {public_ref.access.method.value}")

    # 创建私有数据引用
    try:
        private_ref = create_s3_reference(
            "s3://my-genomics-data/projects/cancer-study/sample-001.fastq",
            region="us-west-2",
            role_arn="arn:aws:iam::123456789012:role/GenomicsDataAccess",
            description="Cancer study sample data"
        )

        print(f"\n私有数据引用:")
        print(f"  Path: {private_ref.path}")
        print(f"  Access Method: {private_ref.access.method.value}")
        print(f"  IAM Role: {private_ref.access.role_arn}")
    except Exception as e:
        print(f"\n私有数据引用示例（需要实际的 IAM Role）: {e}")

    return public_ref


async def test_validate_cloud_reference(cloud_ref: CloudDataReference):
    """测试验证云数据引用"""
    print("\n" + "=" * 80)
    print("测试 2: 验证云数据引用")
    print("=" * 80)

    validator = CloudDataValidator(region=cloud_ref.region)

    print(f"\n正在验证: {cloud_ref.path}")
    print("请稍候...")

    result = await validator.validate(cloud_ref)

    print(f"\n验证结果:")
    print(f"  可访问: {result.accessible}")
    print(f"  文件存在: {result.file_exists}")
    print(f"  验证通过: {result.is_valid}")

    if result.file_size:
        print(f"  文件大小: {result.file_size:,} bytes ({result.file_size / (1024**3):.2f} GB)")

    if result.last_modified:
        print(f"  最后修改: {result.last_modified}")

    if result.error_message:
        print(f"  错误消息: {result.error_message}")

    if result.warnings:
        print(f"\n警告:")
        for warning in result.warnings:
            print(f"    - {warning}")

    return result


async def test_json_serialization(cloud_ref: CloudDataReference):
    """测试 JSON 序列化"""
    print("\n" + "=" * 80)
    print("测试 3: JSON 序列化")
    print("=" * 80)

    # 转换为 JSON
    json_str = cloud_ref.to_json()
    print(f"\nJSON 表示:")
    print(json_str)

    # 从 JSON 恢复
    restored_ref = CloudDataReference.from_json(json_str)
    print(f"\n从 JSON 恢复:")
    print(f"  Path: {restored_ref.path}")
    print(f"  Provider: {restored_ref.provider.value}")
    print(f"  Region: {restored_ref.region}")

    assert cloud_ref.path == restored_ref.path
    assert cloud_ref.provider == restored_ref.provider
    print(f"\n✅ JSON 序列化测试通过")


async def test_convenience_function():
    """测试便捷函数"""
    print("\n" + "=" * 80)
    print("测试 4: 便捷验证函数")
    print("=" * 80)

    # 使用便捷函数验证公共数据
    s3_uri = "s3://1000genomes/README.txt"
    print(f"\n正在验证: {s3_uri}")

    result = await validate_s3_reference(s3_uri, region="us-east-1")

    print(f"\n验证结果:")
    print(f"  验证通过: {result.is_valid}")
    print(f"  文件存在: {result.file_exists}")

    if result.file_size:
        print(f"  文件大小: {result.file_size:,} bytes")


async def test_batch_validation():
    """测试批量验证"""
    print("\n" + "=" * 80)
    print("测试 5: 批量验证")
    print("=" * 80)

    # 创建多个云引用
    cloud_refs = [
        create_s3_reference(
            "s3://1000genomes/README.txt",
            region="us-east-1",
            is_public=True,
            description="README file"
        ),
        create_s3_reference(
            "s3://1000genomes/changelog_details.txt",
            region="us-east-1",
            is_public=True,
            description="Changelog"
        ),
        # 这个文件不存在（用于测试错误处理）
        create_s3_reference(
            "s3://1000genomes/nonexistent_file.txt",
            region="us-east-1",
            is_public=True,
            description="Non-existent file (for testing)"
        ),
    ]

    validator = CloudDataValidator(region="us-east-1")

    print(f"\n批量验证 {len(cloud_refs)} 个云引用...")

    results = await validator.batch_validate(cloud_refs)

    print(f"\n验证摘要:")
    print(f"  总计: {len(results)}")
    print(f"  有效: {sum(1 for r in results if r.is_valid)}")
    print(f"  无效: {sum(1 for r in results if not r.is_valid)}")

    print(f"\n详细结果:")
    for cloud_ref, result in zip(cloud_refs, results):
        status = "✅ 有效" if result.is_valid else "❌ 无效"
        print(f"  {status}: {cloud_ref.filename}")
        if result.error_message:
            print(f"    错误: {result.error_message}")


async def test_mixed_inputs_example():
    """测试混合输入示例"""
    print("\n" + "=" * 80)
    print("测试 6: 混合输入示例（真实使用场景）")
    print("=" * 80)

    print("\n场景: RNA-Seq 分析")
    print("  - 参考基因组：使用云上公共数据（3 GB）")
    print("  - 基因注释：使用云上公共数据（500 MB）")
    print("  - 样本数据：用户上传本地文件（100 MB）")

    # 公共数据：参考基因组
    ref_genome = create_s3_reference(
        "s3://public-genomes/hg38/genome.fa",  # 示例路径
        region="us-west-2",
        is_public=True,
        description="Human reference genome GRCh38"
    )

    # 公共数据：基因注释
    gene_annotation = create_s3_reference(
        "s3://public-genomes/hg38/genes.gtf",  # 示例路径
        region="us-west-2",
        is_public=True,
        description="Gene annotations"
    )

    print(f"\n输入配置:")
    print(f"  1. 参考基因组 (云引用):")
    print(f"     - Path: {ref_genome.path}")
    print(f"     - Skip upload: True ✅")
    print(f"     - 节省上传时间: ~10 分钟")

    print(f"\n  2. 基因注释 (云引用):")
    print(f"     - Path: {gene_annotation.path}")
    print(f"     - Skip upload: True ✅")
    print(f"     - 节省上传时间: ~2 分钟")

    print(f"\n  3. 样本数据 (本地上传):")
    print(f"     - Path: /local/data/sample.fastq")
    print(f"     - 需要上传: True")
    print(f"     - 上传时间: ~1 分钟")

    print(f"\n总节省时间: ~12 分钟 / 分析 🎉")


async def main():
    """主函数"""
    print("\n")
    print("╔" + "=" * 78 + "╗")
    print("║" + " " * 20 + "云数据引用功能测试" + " " * 38 + "║")
    print("╚" + "=" * 78 + "╝")

    try:
        # 测试 1: 创建云引用
        cloud_ref = await test_create_cloud_reference()

        # 测试 2: 验证云引用
        validation_result = await test_validate_cloud_reference(cloud_ref)

        # 测试 3: JSON 序列化
        await test_json_serialization(cloud_ref)

        # 测试 4: 便捷函数
        await test_convenience_function()

        # 测试 5: 批量验证
        await test_batch_validation()

        # 测试 6: 混合输入示例
        await test_mixed_inputs_example()

        print("\n" + "=" * 80)
        print("✅ 所有测试完成！")
        print("=" * 80)

        print("\n💡 提示:")
        print("  - 云数据引用功能已就绪")
        print("  - 可以跳过大文件上传，节省时间和带宽")
        print("  - 支持混合输入（云引用 + 本地上传）")
        print("  - 适用于公共数据集和团队共享数据")

    except Exception as e:
        print(f"\n❌ 测试失败: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    asyncio.run(main())
