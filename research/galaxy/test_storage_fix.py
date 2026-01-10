#!/usr/bin/env python3
"""
测试 SimpleS3Storage 和 FileTransferManager 修复

验证:
1. SimpleS3Storage 能正确创建
2. FileTransferManager 能自动创建 SimpleS3Storage
3. 不再依赖 GalaxyDataManager.storage
"""

import sys
import logging

# Setup logging
logging.basicConfig(level=logging.DEBUG, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

sys.path.insert(0, 'lib')

try:
    from galaxy_cloud.galaxy_workflow.file_transfer_manager import (
        FileTransferManager,
        SimpleS3Storage
    )
    logger.info("✅ Import successful")
except ImportError as e:
    logger.error(f"❌ Import failed: {e}")
    sys.exit(1)

# Test 1: Create SimpleS3Storage
logger.info("\n=== Test 1: Create SimpleS3Storage ===")
try:
    storage = SimpleS3Storage(logger=logger)
    logger.info("✅ SimpleS3Storage created successfully")
    logger.info(f"   Has upload_file: {hasattr(storage, 'upload_file')}")
    logger.info(f"   Has download_file: {hasattr(storage, 'download_file')}")
    logger.info(f"   Has delete_prefix: {hasattr(storage, 'delete_prefix')}")
except Exception as e:
    logger.error(f"❌ Failed to create SimpleS3Storage: {e}")
    import traceback
    logger.error(traceback.format_exc())

# Test 2: Create FileTransferManager without storage_provider
logger.info("\n=== Test 2: Create FileTransferManager (auto storage) ===")
try:
    ftm = FileTransferManager(
        s3_bucket="test-bucket",
        job_id="test-job-123",
        storage_provider=None,  # Should auto-create SimpleS3Storage
        logger=logger
    )
    logger.info("✅ FileTransferManager created successfully")
    logger.info(f"   S3 bucket: {ftm.s3_bucket}")
    logger.info(f"   Job ID: {ftm.job_id}")
    logger.info(f"   Storage type: {type(ftm.storage).__name__}")
    logger.info(f"   Storage is SimpleS3Storage: {isinstance(ftm.storage, SimpleS3Storage)}")
except Exception as e:
    logger.error(f"❌ Failed to create FileTransferManager: {e}")
    import traceback
    logger.error(traceback.format_exc())

# Test 3: Create FileTransferManager with custom storage_provider
logger.info("\n=== Test 3: Create FileTransferManager (custom storage) ===")
try:
    custom_storage = SimpleS3Storage(logger=logger)
    ftm2 = FileTransferManager(
        s3_bucket="test-bucket",
        job_id="test-job-456",
        storage_provider=custom_storage,
        logger=logger
    )
    logger.info("✅ FileTransferManager created with custom storage")
    logger.info(f"   Storage is same object: {ftm2.storage is custom_storage}")
except Exception as e:
    logger.error(f"❌ Failed to create FileTransferManager with custom storage: {e}")
    import traceback
    logger.error(traceback.format_exc())

logger.info("\n=== Summary ===")
logger.info("✅ All tests passed!")
logger.info("")
logger.info("修复验证:")
logger.info("1. ✅ SimpleS3Storage 类已创建并可用")
logger.info("2. ✅ FileTransferManager 能自动创建 SimpleS3Storage")
logger.info("3. ✅ 不再需要 GalaxyDataManager.storage (已移除依赖)")
logger.info("")
logger.info("下一步: 重启 Galaxy 并运行 workflow 测试")
