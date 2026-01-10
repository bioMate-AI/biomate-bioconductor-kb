#!/bin/bash

echo "========================================="
echo "Galaxy Cloud Execution 诊断"
echo "========================================="
echo ""

echo "1. 检查 Galaxy 进程状态"
echo "---"
if ps aux | grep -q "[g]unicorn.*galaxy"; then
    echo "✅ Galaxy 正在运行"
    ps aux | grep "[g]unicorn.*galaxy" | head -2
else
    echo "❌ Galaxy 未运行"
fi
echo ""

echo "2. 检查 Python 代码是否包含修复"
echo "---"
if grep -q "SimpleS3Storage" lib/galaxy_cloud/galaxy_workflow/file_transfer_manager.py; then
    echo "✅ SimpleS3Storage 类存在于代码中"
else
    echo "❌ SimpleS3Storage 类不存在"
fi

if grep -q "storage_provider=None" lib/galaxy_cloud/galaxy_workflow/file_transfer_manager.py; then
    echo "✅ storage_provider 参数为可选"
else
    echo "❌ storage_provider 参数不是可选的"
fi
echo ""

echo "3. 检查最近的 AWS Batch 任务"
echo "---"
echo "Job ID: 836f2452-3c5d-4e19-87d0-2665465962d9"
aws batch describe-jobs --jobs 836f2452-3c5d-4e19-87d0-2665465962d9 \
    --query 'jobs[0].{Status:status,Container:container.command,ExitCode:container.exitCode}' 2>/dev/null || echo "Job not found"
echo ""

echo "4. 检查 S3 中是否有上传的文件"
echo "---"
echo "检查 workflow 137 和 139:"
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/137/ --recursive 2>/dev/null | head -5 || echo "没有找到文件"
aws s3 ls s3://galaxy-cloud-data-1760241377/workflows/139/ --recursive 2>/dev/null | head -5 || echo "没有找到文件"
echo ""

echo "5. 测试 SimpleS3Storage 导入"
echo "---"
python3 << 'PYTHON'
import sys
sys.path.insert(0, 'lib')
try:
    from galaxy_cloud.galaxy_workflow.file_transfer_manager import SimpleS3Storage, FileTransferManager
    print("✅ SimpleS3Storage 可以导入")
    ftm = FileTransferManager(s3_bucket="test", job_id="test")
    print(f"✅ FileTransferManager storage type: {type(ftm.storage).__name__}")
    if type(ftm.storage).__name__ == "SimpleS3Storage":
        print("✅ 自动创建了 SimpleS3Storage")
    else:
        print(f"❌ Storage 类型错误: {type(ftm.storage)}")
except Exception as e:
    print(f"❌ 导入失败: {e}")
PYTHON
echo ""

echo "6. 检查日志文件"
echo "---"
echo "gunicorn.log 最后修改时间:"
ls -lh database/gravity/log/gunicorn.log
echo ""
echo "最后20行:"
tail -20 database/gravity/log/gunicorn.log | grep -E "Job|S3|SimpleS3"
echo ""

echo "========================================="
echo "诊断完成"
echo "========================================="
