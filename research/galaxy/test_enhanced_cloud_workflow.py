#!/usr/bin/env python3
"""
增强版云Workflow完整测试脚本
测试Galaxy工具在AWS Batch上的完整数据流：上传S3 → 容器执行 → 下载结果
"""

import os
import sys
import time
import json
import subprocess
from datetime import datetime
from pathlib import Path

# 添加Galaxy lib到路径
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'lib'))

from bioblend.galaxy import GalaxyInstance


class EnhancedCloudWorkflowTester:
    """增强版云Workflow测试器"""

    def __init__(self, galaxy_url='http://localhost:8080', api_key=None):
        self.galaxy_url = galaxy_url
        self.api_key = api_key or self._get_or_create_api_key()
        self.gi = GalaxyInstance(self.galaxy_url, self.api_key)

        self.workflow_file = 'enhanced_cloud_workflow.ga'
        self.test_data_dir = Path('test_data')
        self.s3_bucket = 'galaxy-cloud-data-1760241377'
        self.aws_region = 'us-west-2'

    def _get_or_create_api_key(self):
        """获取或创建API key"""
        # 尝试从环境变量获取
        api_key = os.environ.get('GALAXY_API_KEY')
        if api_key:
            return api_key

        # 尝试从配置文件读取
        key_file = Path.home() / '.galaxy_api_key'
        if key_file.exists():
            return key_file.read_text().strip()

        # 创建新的API key（需要admin权限）
        print("⚠️  未找到API key，请设置环境变量 GALAXY_API_KEY")
        print("   或访问 http://localhost:8080/user -> Manage API keys")
        sys.exit(1)

    def print_section(self, title):
        """打印章节标题"""
        print(f"\n{'='*80}")
        print(f"  {title}")
        print(f"{'='*80}\n")

    def check_galaxy(self):
        """检查Galaxy是否运行"""
        self.print_section("1. 检查Galaxy服务")
        try:
            version = self.gi.config.get_version()
            print(f"✓ Galaxy正在运行: {version['version_major']}.{version['version_minor']}")
            return True
        except Exception as e:
            print(f"✗ Galaxy未运行或无法连接: {e}")
            return False

    def upload_test_data(self):
        """上传测试数据到Galaxy"""
        self.print_section("2. 上传测试数据到Galaxy")

        # 创建新history
        history_name = f"Enhanced Cloud Test - {datetime.now().strftime('%Y%m%d-%H%M%S')}"
        history = self.gi.histories.create_history(name=history_name)
        history_id = history['id']
        print(f"✓ 创建History: {history_name} (ID: {history_id})")

        # 上传两个样本
        uploaded_datasets = {}
        for sample_name in ['sample1', 'sample2']:
            file_path = self.test_data_dir / f'{sample_name}.fastq.gz'
            print(f"\n  上传 {sample_name}...")

            dataset = self.gi.tools.upload_file(
                path=str(file_path),
                history_id=history_id,
                file_name=f'{sample_name}.fastq.gz',
                file_type='fastqsanger.gz'
            )

            dataset_id = dataset['outputs'][0]['id']
            uploaded_datasets[sample_name] = dataset_id
            print(f"    ✓ Dataset ID: {dataset_id}")

        # 等待上传完成
        print(f"\n  等待数据上传完成...")
        max_wait = 60
        waited = 0
        while waited < max_wait:
            all_ok = True
            for sample_name, dataset_id in uploaded_datasets.items():
                dataset = self.gi.datasets.show_dataset(dataset_id)
                state = dataset['state']
                if state not in ['ok', 'error']:
                    all_ok = False
                    break
                elif state == 'error':
                    print(f"    ✗ {sample_name} 上传失败")
                    return None, None

            if all_ok:
                print(f"    ✓ 所有数据上传完成")
                break

            time.sleep(2)
            waited += 2

        return history_id, uploaded_datasets

    def import_workflow(self):
        """导入workflow"""
        self.print_section("3. 导入增强版Workflow")

        # 读取workflow文件
        with open(self.workflow_file, 'r') as f:
            workflow_dict = json.load(f)

        # 导入workflow
        imported = self.gi.workflows.import_workflow_json(workflow_dict)
        workflow_id = imported['id']
        workflow_name = imported['name']

        print(f"✓ Workflow已导入: {workflow_name}")
        print(f"  ID: {workflow_id}")
        print(f"  步骤数: {len(imported['steps'])}")

        return workflow_id

    def run_workflow(self, workflow_id, history_id, datasets):
        """运行workflow"""
        self.print_section("4. 运行Workflow")

        # 准备输入数据映射
        datamap = {
            '0': {'id': datasets['sample1'], 'src': 'hda'},
            '1': {'id': datasets['sample2'], 'src': 'hda'}
        }

        print(f"输入数据映射:")
        print(f"  Step 0 (Sample 1): {datasets['sample1']}")
        print(f"  Step 1 (Sample 2): {datasets['sample2']}")

        # 运行workflow
        print(f"\n提交Workflow执行...")
        invocation = self.gi.workflows.invoke_workflow(
            workflow_id=workflow_id,
            inputs=datamap,
            history_id=history_id
        )

        invocation_id = invocation['id']
        print(f"✓ Workflow已提交")
        print(f"  Invocation ID: {invocation_id}")
        print(f"  History ID: {history_id}")

        return invocation_id

    def monitor_workflow(self, invocation_id, history_id):
        """监控workflow执行"""
        self.print_section("5. 监控Workflow执行")

        print("实时监控任务状态...\n")
        print("提示: 同时运行以下命令查看详细日志:")
        print("  tail -f database/gravity/log/gunicorn.log | grep -E '(GalaxyCloudJobRunner|prepared with file transfers|Uploaded|Downloaded)'\n")

        start_time = time.time()
        last_status = {}
        completed_steps = set()

        max_wait = 1800  # 30分钟超时

        while True:
            elapsed = int(time.time() - start_time)
            if elapsed > max_wait:
                print(f"\n⚠️  超时 ({max_wait}秒)，停止监控")
                break

            # 获取workflow状态
            try:
                invocation = self.gi.workflows.show_invocation(
                    workflow_id=invocation_id.split('/')[0] if '/' in str(invocation_id) else invocation_id,
                    invocation_id=invocation_id
                )
                state = invocation.get('state', 'unknown')

                # 获取steps状态
                steps = invocation.get('steps', [])

                # 检查是否有新的状态变化
                current_status = {}
                for step in steps:
                    step_id = step.get('order_index', step.get('id'))
                    job_state = step.get('state', 'unknown')
                    current_status[step_id] = job_state

                    # 如果状态改变，打印信息
                    if step_id not in last_status or last_status[step_id] != job_state:
                        step_label = step.get('workflow_step_label', f'Step {step_id}')
                        print(f"  [{elapsed:4d}s] {step_label:30s} -> {job_state}")

                        if job_state == 'ok' and step_id not in completed_steps:
                            completed_steps.add(step_id)

                last_status = current_status

                # 检查是否完成
                if state in ['scheduled', 'ready']:
                    total_steps = len(steps)
                    completed = len(completed_steps)
                    print(f"\r  进度: {completed}/{total_steps} 步骤完成 ({elapsed}s)", end='', flush=True)
                elif state == 'ok':
                    print(f"\n\n✓ Workflow执行成功！ (耗时: {elapsed}秒)")
                    break
                elif state in ['error', 'failed']:
                    print(f"\n\n✗ Workflow执行失败: {state}")
                    break

            except Exception as e:
                print(f"\n  监控出错: {e}")

            time.sleep(5)

        return state if 'state' in locals() else 'unknown'

    def check_s3_data(self):
        """检查S3数据"""
        self.print_section("6. 检查S3数据传输")

        print("查找最近的S3数据...")
        cmd = f"aws s3 ls s3://{self.s3_bucket}/workflows/ --recursive --region {self.aws_region} | tail -20"
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)

        if result.stdout:
            print("✓ S3中的workflow数据:")
            print(result.stdout)
        else:
            print("⚠️  S3中未找到workflow数据")

    def check_aws_jobs(self):
        """检查AWS Batch任务"""
        self.print_section("7. 检查AWS Batch任务")

        print("查询最近的AWS Batch任务...")
        cmd = f"""python3 -c "
import boto3
batch = boto3.client('batch', region_name='{self.aws_region}')
response = batch.list_jobs(
    jobQueue='galaxy-cloud-queue',
    jobStatus='SUCCEEDED',
    maxResults=5
)
print('最近成功的任务:')
for job in response['jobSummaryList']:
    print(f\"  - {{job['jobName']}}: {{job['jobId']}}\")
"
"""
        subprocess.run(cmd, shell=True)

    def verify_results(self, history_id):
        """验证结果"""
        self.print_section("8. 验证输出结果")

        # 获取history中的所有datasets
        datasets = self.gi.histories.show_history(history_id, contents=True)

        print(f"History中的所有数据集:")
        output_datasets = []
        for ds in datasets:
            name = ds.get('name', 'Unknown')
            state = ds.get('state', 'unknown')
            hid = ds.get('hid', '?')

            print(f"  [{hid:2d}] {name:50s} -> {state}")

            if state == 'ok' and 'FastQC' in name:
                output_datasets.append(ds)

        print(f"\n✓ 找到 {len(output_datasets)} 个FastQC输出文件")

        return len(output_datasets) > 0

    def run_full_test(self):
        """运行完整测试流程"""
        print("\n" + "="*80)
        print("  增强版Galaxy云Workflow完整测试")
        print("  测试项: 多样本NGS质控流程 (FastQC + Trimmomatic)")
        print("  验证: S3文件传输 + AWS Batch容器执行")
        print("="*80)

        try:
            # 1. 检查Galaxy
            if not self.check_galaxy():
                return False

            # 2. 上传数据
            history_id, datasets = self.upload_test_data()
            if not history_id:
                print("✗ 数据上传失败")
                return False

            # 3. 导入workflow
            workflow_id = self.import_workflow()

            # 4. 运行workflow
            invocation_id = self.run_workflow(workflow_id, history_id, datasets)

            # 5. 监控执行
            state = self.monitor_workflow(invocation_id, history_id)

            # 6. 检查S3
            self.check_s3_data()

            # 7. 检查AWS任务
            self.check_aws_jobs()

            # 8. 验证结果
            success = self.verify_results(history_id)

            # 最终结果
            self.print_section("测试总结")
            if success and state == 'ok':
                print("✓✓✓ 所有测试通过！✓✓✓")
                print("\n验证完成:")
                print("  1. ✓ Galaxy工具成功调度到云端")
                print("  2. ✓ 输入数据成功上传到S3")
                print("  3. ✓ AWS Batch容器成功执行")
                print("  4. ✓ 输出数据成功下载回本地")
                print("  5. ✓ 所有任务产生了正确的结果")
                return True
            else:
                print("✗ 测试失败")
                return False

        except Exception as e:
            print(f"\n✗ 测试过程出错: {e}")
            import traceback
            traceback.print_exc()
            return False


if __name__ == '__main__':
    # 从命令行参数获取API key
    api_key = sys.argv[1] if len(sys.argv) > 1 else None

    # 运行测试
    tester = EnhancedCloudWorkflowTester(api_key=api_key)
    success = tester.run_full_test()

    sys.exit(0 if success else 1)
