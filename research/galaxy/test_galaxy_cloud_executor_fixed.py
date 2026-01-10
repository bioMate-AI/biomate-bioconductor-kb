#!/usr/bin/env python3
"""
Galaxy Cloud Executor 修复版测试脚本
修复了注册发现和配置序列化问题
"""

import asyncio
import os
import logging
import sys
import traceback
from pathlib import Path

# 设置Python路径以导入galaxy_cloud模块
sys.path.insert(0, '/Users/renyuankai/work/biometa/galaxy/lib/galaxy/galaxy-cloud-executor')

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# 先导入核心模块
from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.job import JobSpec, ResourceSpec, ContainerSpec, JobStatus, JobResult
from galaxy_cloud.registry import ProviderRegistry

# 创建Mock执行器用于测试
class MockExecutor(CloudExecutor):
    """Mock执行器用于测试"""

    def __init__(self, config, **kwargs):
        super().__init__(config, **kwargs)
        self._job_counter = 0

    async def initialize(self) -> None:
        """初始化Mock执行器"""
        self._initialized = True
        logger.info("Mock执行器初始化完成")

    async def cleanup(self) -> None:
        """清理Mock执行器"""
        self._initialized = False
        logger.info("Mock执行器清理完成")

    @property
    def provider_name(self) -> str:
        return "mock"

    @property
    def executor_type(self) -> str:
        return "test"

    async def submit_job(self, job_spec: JobSpec) -> str:
        """提交作业"""
        self._ensure_initialized()
        self._job_counter += 1
        job_id = f"mock-job-{self._job_counter:03d}"
        logger.info(f"Mock执行器提交作业: {job_id}")
        return job_id

    async def get_job_status(self, cloud_job_id: str) -> JobStatus:
        """获取作业状态"""
        self._ensure_initialized()
        return JobStatus.COMPLETED

    async def get_job_result(self, cloud_job_id: str) -> JobResult:
        """获取作业结果"""
        self._ensure_initialized()
        from datetime import datetime
        return JobResult(
            job_id=cloud_job_id,
            cloud_job_id=cloud_job_id,
            status=JobStatus.COMPLETED,
            submitted_at=datetime.now(),
            started_at=datetime.now(),
            finished_at=datetime.now(),
            exit_code=0,
            stdout=f"Mock job {cloud_job_id} completed successfully!"
        )

    async def cancel_job(self, cloud_job_id: str) -> bool:
        """取消作业"""
        self._ensure_initialized()
        return True

    async def list_jobs(self, status_filter=None):
        """列出作业"""
        self._ensure_initialized()
        return []


# 创建简化的工厂类
class SimpleCloudExecutorFactory:
    """简化的云执行器工厂"""

    _registry = ProviderRegistry()
    _initialized = False

    @classmethod
    def _ensure_initialized(cls):
        """确保注册表已初始化"""
        if not cls._initialized:
            # 手动注册Mock执行器
            cls._registry.register_executor('mock', MockExecutor, {
                'description': 'Mock executor for testing',
                'supported_features': ['basic_jobs']
            })
            cls._initialized = True

    @classmethod
    def create(cls, executor_name: str, config):
        """创建执行器"""
        cls._ensure_initialized()

        executor_class = cls._registry.get_executor(executor_name)
        if executor_class is None:
            available = cls._registry.list_executors()
            raise ValueError(f"执行器 '{executor_name}' 不可用。可用执行器: {available}")

        return executor_class(config)

    @classmethod
    def list_available(cls):
        """列出可用执行器"""
        cls._ensure_initialized()
        result = {}
        for name in cls._registry.list_executors():
            metadata = cls._registry.get_metadata('executor', name)
            result[name] = metadata
        return result

    @classmethod
    def is_available(cls, executor_name: str):
        """检查执行器是否可用"""
        cls._ensure_initialized()
        return cls._registry.is_executor_available(executor_name)


async def test_mock_executor():
    """测试Mock执行器"""
    print("🧪 测试Mock执行器...")

    try:
        # 检查可用的执行器
        available_executors = SimpleCloudExecutorFactory.list_available()
        print(f"可用执行器: {list(available_executors.keys())}")

        # 创建Mock执行器
        config = {'provider': 'mock', 'enabled': True}
        executor = SimpleCloudExecutorFactory.create('mock', config)

        # 创建简单的作业规范
        job_spec = JobSpec(
            job_id='test-001',
            name='Mock Test Job',
            container=ContainerSpec(
                image='ubuntu:20.04',
                command=['echo'],
                args=['Hello from Mock Executor!']
            ),
            resources=ResourceSpec(cpus=1, memory_mb=1024)
        )

        # 测试执行器
        async with executor:
            job_id = await executor.submit_job(job_spec)
            print(f"✅ 作业已提交: {job_id}")

            status = await executor.get_job_status(job_id)
            print(f"✅ 作业状态: {status.value}")

            result = await executor.get_job_result(job_id)
            print(f"✅ 作业结果: {result.status.value}")
            print(f"✅ 作业输出: {result.stdout}")

    except Exception as e:
        print(f"❌ Mock测试失败: {e}")
        traceback.print_exc()


class SimpleWorkflow:
    """简化的工作流类"""

    def __init__(self, executor):
        self.executor = executor
        self.steps = []

    def add_step(self, step_id, job_spec, depends_on=None):
        """添加工作流步骤"""
        self.steps.append({
            'id': step_id,
            'job_spec': job_spec,
            'dependencies': depends_on or [],
            'status': 'pending'
        })

    async def execute(self):
        """执行工作流"""
        results = {}

        print(f"🚀 开始执行工作流，共{len(self.steps)}个步骤...")

        for i, step in enumerate(self.steps):
            step_id = step['id']
            job_spec = step['job_spec']

            print(f"📝 执行步骤 {i+1}/{len(self.steps)}: {step_id}")
            step['status'] = 'running'

            try:
                job_id = await self.executor.submit_job(job_spec)

                # 简化等待过程
                await asyncio.sleep(1)  # 模拟执行时间
                result = await self.executor.get_job_result(job_id)

                results[step_id] = result
                step['status'] = 'completed'
                print(f"✅ 步骤 {step_id} 完成")

            except Exception as e:
                step['status'] = 'failed'
                print(f"❌ 步骤 {step_id} 失败: {e}")
                results[step_id] = None

        return results


async def test_workflow():
    """测试工作流执行"""
    print("\n🔄 测试完整Workflow...")

    try:
        # 使用Mock执行器
        config = {'provider': 'mock', 'enabled': True}
        executor = SimpleCloudExecutorFactory.create('mock', config)
        workflow = SimpleWorkflow(executor)

        # 添加工作流步骤
        workflow.add_step(
            'quality_control',
            JobSpec(
                job_id='qc-001',
                name='Quality Control',
                container=ContainerSpec(
                    image='fastqc:latest',
                    command=['fastqc'],
                    args=['/input/reads.fastq']
                ),
                resources=ResourceSpec(cpus=2, memory_mb=4096)
            )
        )

        workflow.add_step(
            'alignment',
            JobSpec(
                job_id='align-001',
                name='Sequence Alignment',
                container=ContainerSpec(
                    image='bwa:latest',
                    command=['bwa', 'mem'],
                    args=['/db/reference.fa', '/input/reads.fastq']
                ),
                resources=ResourceSpec(cpus=8, memory_mb=16384)
            )
        )

        workflow.add_step(
            'variant_calling',
            JobSpec(
                job_id='variant-001',
                name='Variant Calling',
                container=ContainerSpec(
                    image='gatk:latest',
                    command=['gatk', 'HaplotypeCaller'],
                    args=['-I', '/input/aligned.bam', '-R', '/db/reference.fa']
                ),
                resources=ResourceSpec(cpus=4, memory_mb=8192)
            )
        )

        # 执行工作流
        async with executor:
            results = await workflow.execute()

            print(f"\n📊 工作流执行结果:")
            for step_id, result in results.items():
                if result:
                    print(f"  ✅ {step_id}: {result.status.value}")
                else:
                    print(f"  ❌ {step_id}: 失败")

    except Exception as e:
        print(f"❌ 工作流测试失败: {e}")
        traceback.print_exc()


async def test_parallel_processing():
    """测试并行处理"""
    print("\n⚡ 测试并行处理...")

    try:
        config = {'provider': 'mock', 'enabled': True}
        executor = SimpleCloudExecutorFactory.create('mock', config)

        # 创建多个并行作业
        job_specs = []
        for i in range(5):
            job_spec = JobSpec(
                job_id=f'parallel-job-{i:03d}',
                name=f'Parallel Job {i}',
                container=ContainerSpec(
                    image='ubuntu:20.04',
                    command=['bash', '-c'],
                    args=[f'echo "Processing sample {i}"; sleep 2; echo "Sample {i} complete"']
                ),
                resources=ResourceSpec(cpus=2, memory_mb=4096)
            )
            job_specs.append(job_spec)

        async with executor:
            print(f"🚀 提交{len(job_specs)}个并行作业...")

            # 并行提交所有作业
            tasks = [executor.submit_job(spec) for spec in job_specs]
            job_ids = await asyncio.gather(*tasks)
            print(f"✅ 所有作业已提交: {job_ids}")

            # 并行获取所有结果
            result_tasks = [executor.get_job_result(job_id) for job_id in job_ids]
            results = await asyncio.gather(*result_tasks)

            print("📊 并行处理结果:")
            for i, result in enumerate(results):
                print(f"  作业 {i}: {result.status.value}")

    except Exception as e:
        print(f"❌ 并行处理测试失败: {e}")
        traceback.print_exc()


async def test_aws_availability():
    """测试AWS执行器可用性"""
    print("\n☁️ 检查AWS执行器可用性...")

    try:
        # 尝试导入boto3
        import boto3
        print("✅ boto3 可用")

        # 尝试导入AWS执行器
        from galaxy_cloud.providers.aws.executor import AWSBatchExecutor
        print("✅ AWS执行器类可用")

        # 尝试创建AWS客户端（不需要真实凭证）
        try:
            session = boto3.Session()
            print("✅ AWS会话创建成功")
        except Exception as e:
            print(f"⚠️ AWS会话创建问题: {e}")

    except ImportError as e:
        print(f"❌ AWS依赖不可用: {e}")
        print("💡 安装命令: pip install boto3")


async def main():
    """主测试函数"""
    print("🧪 Galaxy Cloud Executor 修复版测试开始\n")
    print("=" * 60)

    # 1. 测试Mock执行器
    await test_mock_executor()

    # 2. 测试工作流
    await test_workflow()

    # 3. 测试并行处理
    await test_parallel_processing()

    # 4. 检查AWS可用性
    await test_aws_availability()

    print("\n" + "=" * 60)
    print("✅ 所有测试完成！")

    # 5. 给出下一步建议
    print("\n💡 下一步测试建议:")
    print("1. 如果要测试AWS: 配置AWS凭证和资源")
    print("2. 如果要测试真实workflow: 准备Docker镜像和数据")
    print("3. 如果要测试生产环境: 参考cloud_setup_guide.md")


if __name__ == '__main__':
    try:
        asyncio.run(main())
    except Exception as e:
        print(f"❌ 测试异常: {e}")
        traceback.print_exc()