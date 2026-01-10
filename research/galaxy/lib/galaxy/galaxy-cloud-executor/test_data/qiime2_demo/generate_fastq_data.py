#!/usr/bin/env python3
"""
生成QIIME2 workflow测试用的FASTQ数据
"""
import gzip
import random
from pathlib import Path

# DNA碱基
BASES = ['A', 'C', 'G', 'T']

def generate_quality_scores(length):
    """生成质量分数（Phred+33格式）"""
    # 质量分数范围: 20-40 (对应ASCII字符)
    return ''.join(chr(random.randint(53, 73)) for _ in range(length))

def generate_read(read_id, length=150):
    """生成一条测序read"""
    # 生成随机DNA序列
    sequence = ''.join(random.choice(BASES) for _ in range(length))
    # 生成质量分数
    quality = generate_quality_scores(length)

    return f"@{read_id}\n{sequence}\n+\n{quality}\n"

def generate_sample_fastq(sample_name, num_reads=1000, output_dir='.'):
    """生成一个样本的FASTQ文件"""
    output_path = Path(output_dir) / f"{sample_name}_R1.fastq.gz"

    print(f"生成 {sample_name} ({num_reads} reads)...")

    with gzip.open(output_path, 'wt') as f:
        for i in range(num_reads):
            read_id = f"{sample_name}.{i+1}"
            f.write(generate_read(read_id))

    print(f"  ✓ {output_path}")
    return output_path

def main():
    """生成测试数据集"""
    output_dir = Path(__file__).parent

    print("\n🧬 生成QIIME2测试序列数据...\n")

    # 生成3个样本,模拟微生物组测序数据
    samples = [
        ("sample1", 500),   # 样本1: 500条reads
        ("sample2", 500),   # 样本2: 500条reads
        ("sample3", 500),   # 样本3: 500条reads
    ]

    generated_files = []
    for sample_name, num_reads in samples:
        file_path = generate_sample_fastq(sample_name, num_reads, output_dir)
        generated_files.append(file_path)

    print(f"\n✅ 成功生成 {len(generated_files)} 个FASTQ文件")
    print("\n📁 文件列表:")
    for f in generated_files:
        size_kb = f.stat().st_size / 1024
        print(f"  - {f.name} ({size_kb:.1f} KB)")

    print("\n💡 使用说明:")
    print("  这些文件可以作为QIIME2 workflow的输入数据")
    print("  格式: fastqsanger.gz (Illumina 1.8+ 质量编码)")
    print("  类型: 单端测序数据 (single-end)")

if __name__ == '__main__':
    main()
