1. 获取最终输出文件
GET /api/workflows/{workflow_invocation_id}/output_files
返回数据:
{
  "workflow_id": 1200,
  "output_dir": "s3://bucket/workflows/1200/outputs/...",
  "files": {
    "vcf": ["file1.vcf", "file2.vcf"],
    "bam": ["sample.bam"],
    "reports": ["multiqc_report.html"]
  },
  "download_commands": {
    "all_outputs": "aws s3 sync s3://bucket/.../outputs/ ./outputs/",
    "vcf_only": "aws s3 sync s3://.../ --exclude '*' --include '*.vcf'",
    "multiqc_report": "aws s3 cp s3://.../multiqc_report.html ."
  }
}
2. 获取中间文件（⭐ 这个就是你要的！）
GET /api/workflows/{workflow_invocation_id}/intermediate_files
返回数据:
{
  "workflow_id": 1200,
  "work_dir": "s3://bucket/workflows/1200/work",
  "tasks": {
    "PARABRICKS_FQ2BAM": {
      "work_dir": "s3://bucket/workflows/1200/work/01/abc123...",
      "files": ["output.bam", "output.bai"],
      "logs": [".command.log", ".command.err"]
    },
    "DEEPVARIANT": {
      "work_dir": "s3://bucket/workflows/1200/work/02/def456...",
      "files": ["variants.vcf"],
      "logs": [".command.log"]
    }
  },
  "download_commands": {
    "PARABRICKS_FQ2BAM": "aws s3 sync s3://bucket/.../01/abc123.../ ./PARABRICKS_FQ2BAM/",
    "DEEPVARIANT": "aws s3 sync s3://bucket/.../02/def456.../ ./DEEPVARIANT/"
  }
}
3. 获取所有下载命令（整合接口）
GET /api/workflows/{workflow_invocation_id}/download_commands
返回数据:
{
  "workflow_id": 1200,
  "commands": {
    "all_outputs": "aws s3 sync ...",
    "vcf_only": "aws s3 sync ...",
    "intermediate_files": {
      "PARABRICKS_FQ2BAM": "aws s3 sync ...",
      "DEEPVARIANT": "aws s3 sync ...",
      "FREEBAYES": "aws s3 sync ..."
    }
  },
  "usage": "Copy and paste these commands in your terminal to download results"
}
使用示例
# 1. 获取中间文件信息
curl http://localhost:8080/api/workflows/1200/intermediate_files

# 2. 获取最终输出文件
curl http://localhost:8080/api/workflows/1200/output_files

# 3. 获取所有下载命令
curl http://localhost:8080/api/workflows/1200/download_commands

# 4. 使用返回的命令下载中间结果
aws s3 sync s3://bucket/workflows/1200/work/01/abc123.../ ./PARABRICKS_FQ2BAM/
中间文件的存储位置
如果启用了 S3 workDir（Resume 功能），所有中间文件都在：
s3://galaxy-cloud-data-1760241377/workflows/{workflow_id}/work/
├── 01/abc123.../          # Task 1 的工作目录
│   ├── output.bam         # 中间结果文件
│   ├── .command.sh        # 执行脚本
│   ├── .command.log       # 执行日志
│   └── .exitcode          # 退出码
├── 02/def456.../          # Task 2 的工作目录
│   └── ...
└── ...