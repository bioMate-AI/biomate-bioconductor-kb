#!/usr/bin/env python3
"""
Galaxy Cloud Executor 测试脚本
演示如何测试云执行器的完整流程
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
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# 先导入核心模块
from galaxy_cloud.core.executor import CloudExecutor
from galaxy_cloud.core.job import JobSpec, ResourceSpec, ContainerSpec, JobStatus, JobResult
from galaxy_cloud.registry import registry


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


# 修复的CloudExecutorFactory
class FixedCloudExecutorFactory:
    """修复的云执行器工厂"""

    _initialized = False

    @classmethod
    def _ensure_initialized(cls):
        """确保注册表已初始化"""
        if not cls._initialized:
            # 手动注册Mock执行器
            registry.register_executor('mock', MockExecutor, {
                'description': 'Mock executor for testing',
                'supported_features': ['basic_jobs']
            })

            # 尝试初始化真实的提供商
            try:
                registry.initialize()
            except Exception as e:
                logger.debug(f"自动注册失败，使用手动注册: {e}")

            cls._initialized = True

    @classmethod
    def create(cls, executor_name: str, config):
        """创建执行器"""
        cls._ensure_initialized()
        executor_class = registry.get_executor(executor_name)
        if executor_class is None:
            available = registry.list_executors()
            raise ValueError(f"执行器 '{executor_name}' 不可用。可用执行器: {available}")
        return executor_class(config)

    @classmethod
    def list_available(cls):
        """列出可用执行器"""
        cls._ensure_initialized()
        result = {}
        for name in registry.list_executors():
            metadata = registry.get_metadata('executor', name)
            result[name] = metadata
        return result

    @classmethod
    def is_available(cls, executor_name: str):
        """检查执行器是否可用"""
        cls._ensure_initialized()
        return registry.is_executor_available(executor_name)


# 使用修复的工厂替代原始工厂
CloudExecutorFactory = FixedCloudExecutorFactory


async def test_mock_executor():
    """测试Mock执行器（不需要真实云资源）"""
    print("🧪 测试Mock执行器...")

    # 创建Mock配置
    config = {
        'provider': 'mock',
        'enabled': True
    }

    try:
        # 检查可用的执行器
        available_executors = CloudExecutorFactory.list_available()
        print(f"可用执行器: {list(available_executors.keys())}")

        # 如果有mock执行器，进行测试
        if 'mock' in available_executors:
            executor = CloudExecutorFactory.create('mock', config)

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

            async with executor:
                job_id = await executor.submit_job(job_spec)
                print(f"✅ 作业已提交: {job_id}")

                status = await executor.get_job_status(job_id)
                print(f"✅ 作业状态: {status}")

                result = await executor.get_job_result(job_id)
                print(f"✅ 作业结果: {result.status}")
        else:
            print("❌ 未找到Mock执行器")

    except Exception as e:
        print(f"❌ Mock测试失败: {e}")


async def test_aws_executor_basic():
    """测试AWS执行器基础功能（需要AWS配置）"""
    print("\n☁️ 测试AWS执行器基础功能...")

    # AWS配置（使用环境变量或默认配置）
    aws_config = {
        'enabled': True,
        'region': os.getenv('AWS_REGION', 'us-east-1'),
        'batch_queue': os.getenv('AWS_BATCH_QUEUE', 'test-queue'),
        's3_bucket': os.getenv('AWS_S3_BUCKET', 'test-bucket'),
    }

    # 检查AWS执行器是否可用
    if not CloudExecutorFactory.is_available('aws-batch'):
        print("❌ AWS Batch执行器不可用（可能缺少boto3依赖）")
        print("💡 安装命令: pip install boto3")
        return

    try:
        executor = CloudExecutorFactory.create('aws-batch', aws_config)

        # 健康检查
        health = await executor.health_check()
        print(f"AWS执行器健康检查: {health}")

        if health['status'] == 'healthy':
            # 创建测试作业
            job_spec = JobSpec(
                job_id='aws-test-001',
                name='AWS Test Job',
                container=ContainerSpec(
                    image='ubuntu:20.04',
                    command=['/bin/bash', '-c'],
                    args=['echo "Hello from AWS Batch!"; sleep 30; echo "Job completed"']
                ),
                resources=ResourceSpec(cpus=1, memory_mb=512),
                timeout_seconds=300
            )

            async with executor:
                job_id = await executor.submit_job(job_spec)
                print(f"✅ AWS作业已提交: {job_id}")

                # 监控作业进展
                print("⏳ 监控作业进展...")
                async with executor.job_monitor(job_id, poll_interval=10.0) as monitor:
                    async for event in monitor:
                        print(f"📊 事件: {event.event_type} - {event.message}")
                        if event.event_type == 'status_change':
                            if event.details['new_status'] in ['completed', 'failed']:
                                break

                # 获取最终结果
                result = await executor.get_job_result(job_id)
                print(f"✅ 最终结果: {result.status}")
                if result.stdout:
                    print(f"📝 输出: {result.stdout}")
        else:
            print(f"❌ AWS执行器健康检查失败: {health.get('error', 'Unknown error')}")

    except Exception as e:
        print(f"❌ AWS测试失败: {e}")
        print("💡 请检查AWS凭证和配置")


async def test_workflow_creation():
    """测试完整的Workflow创建和执行"""
    print("\n🔄 测试完整Workflow...")

    class SimpleWorkflow:
        def __init__(self, executor):
            self.executor = executor
            self.steps = []

        def add_step(self, step_id, job_spec, depends_on=None):
            self.steps.append({
                'id': step_id,
                'job_spec': job_spec,
                'dependencies': depends_on or [],
                'status': 'pending'
            })

        async def execute(self):
            """简单的顺序执行（实际应该实现依赖解析）"""
            results = {}

            for step in self.steps:
                step_id = step['id']
                job_spec = step['job_spec']

                print(f"🚀 执行步骤: {step_id}")
                step['status'] = 'running'

                try:
                    job_id = await self.executor.submit_job(job_spec)
                    result = await self.executor.wait_for_completion(job_id)

                    results[step_id] = result
                    step['status'] = 'completed'
                    print(f"✅ 步骤 {step_id} 完成")

                except Exception as e:
                    step['status'] = 'failed'
                    print(f"❌ 步骤 {step_id} 失败: {e}")
                    results[step_id] = None

            return results

    # 使用Mock执行器进行Workflow测试
    config = {'provider': 'mock', 'enabled': True}

    try:
        if CloudExecutorFactory.is_available('mock'):
            executor = CloudExecutorFactory.create('mock', config)
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
                ),
                depends_on=['quality_control']
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
                ),
                depends_on=['alignment']
            )

            # 执行工作流
            async with executor:
                results = await workflow.execute()

                print(f"\n📊 工作流执行结果:")
                for step_id, result in results.items():
                    if result:
                        print(f"  {step_id}: {result.status}")
                    else:
                        print(f"  {step_id}: 失败")
        else:
            print("❌ Mock执行器不可用，无法测试工作流")

    except Exception as e:
        print(f"❌ 工作流测试失败: {e}")


async def test_config_management():
    """测试配置管理"""
    print("\n⚙️ 测试配置管理...")

    try:
        # 创建简化的测试配置，避免复杂的对象序列化
        import yaml

        simple_config = {
            'aws': {
                'enabled': True,
                'region': 'us-east-1',
                'batch_queue': 'test-queue',
                's3_bucket': 'test-bucket'
            },
            'azure': {
                'enabled': False
            },
            'default_provider': 'aws'
        }

        # 保存配置
        config_path = '/tmp/test_cloud_config.yaml'
        with open(config_path, 'w') as f:
            yaml.dump(simple_config, f, default_flow_style=False)
        print(f"✅ 配置已保存到: {config_path}")

        # 加载配置
        with open(config_path, 'r') as f:
            loaded_config = yaml.safe_load(f)
        print(f"✅ 配置已加载")
        print(f"  默认提供商: {loaded_config['default_provider']}")
        print(f"  AWS区域: {loaded_config['aws']['region']}")
        print(f"  AWS启用: {loaded_config['aws']['enabled']}")

    except Exception as e:
        print(f"❌ 配置管理测试失败: {e}")
        traceback.print_exc()


async def main():
    """主测试函数"""
    print("🧪 Galaxy Cloud Executor 测试开始\n")
    print("=" * 60)

    # 1. 测试Mock执行器
    await test_mock_executor()

    # 2. 测试配置管理
    await test_config_management()

    # 3. 测试工作流创建
    await test_workflow_creation()

    # 4. 测试AWS执行器（如果有配置）
    if os.getenv('AWS_BATCH_QUEUE') and os.getenv('AWS_S3_BUCKET'):
        await test_aws_executor_basic()
    else:
        print("\n💡 跳过AWS测试 - 请设置环境变量:")
        print("   export AWS_BATCH_QUEUE=your-queue-name")
        print("   export AWS_S3_BUCKET=your-bucket-name")
        print("   export AWS_REGION=us-east-1")

    print("\n" + "=" * 60)
    print("✅ 测试完成！")


if __name__ == '__main__':
    asyncio.run(main())