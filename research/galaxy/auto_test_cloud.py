#!/usr/bin/env python3
"""
自动化测试Galaxy云执行
- 自动上传文件
- 自动创建collection
- 自动导入并运行workflow
- 自动验证云执行
"""

import requests
import json
import time
import sys
from pathlib import Path

# 配置
GALAXY_URL = "http://localhost:8080"
API_KEY = None  # 需要你设置API Key

# 文件路径
TEST_FILES = [
    "test_collection_data/sample1.txt",
    "test_collection_data/sample2.txt",
    "test_collection_data/sample3.txt"
]
WORKFLOW_FILE = "test_cloud_workflow.ga"


def check_api_key():
    """检查API Key"""
    if not API_KEY:
        print("❌ 需要API Key")
        print("\n请按以下步骤获取：")
        print("1. 访问 http://localhost:8080")
        print("2. User → Preferences → Manage API Key")
        print("3. Create New Key")
        print("4. 将Key设置到此脚本的 API_KEY 变量")
        sys.exit(1)


def test_connection():
    """测试Galaxy连接"""
    try:
        headers = {"x-api-key": API_KEY}
        response = requests.get(f"{GALAXY_URL}/api/version", headers=headers)
        if response.status_code == 200:
            version = response.json()
            print(f"✅ Galaxy连接成功: v{version['version_major']}")
            return True
        else:
            print(f"❌ 连接失败: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ 连接错误: {e}")
        return False


def get_or_create_history():
    """获取或创建历史记录"""
    headers = {"x-api-key": API_KEY}

    # 获取当前历史
    response = requests.get(f"{GALAXY_URL}/api/histories", headers=headers)
    histories = response.json()

    if histories:
        history_id = histories[0]["id"]
        print(f"✅ 使用历史记录: {histories[0]['name']}")
        return history_id

    # 创建新历史
    response = requests.post(
        f"{GALAXY_URL}/api/histories",
        json={"name": "Cloud Test History"},
        headers=headers
    )
    history_id = response.json()["id"]
    print(f"✅ 创建新历史记录: {history_id}")
    return history_id


def upload_files(history_id):
    """上传测试文件"""
    headers = {"x-api-key": API_KEY}
    dataset_ids = []

    print("\n📤 上传测试文件...")
    for file_path in TEST_FILES:
        if not Path(file_path).exists():
            print(f"  ⚠️  文件不存在: {file_path}")
            continue

        with open(file_path, 'rb') as f:
            files = {'file': f}
            data = {
                'history_id': history_id,
                'file_type': 'txt'
            }

            response = requests.post(
                f"{GALAXY_URL}/api/tools",
                data=data,
                files=files,
                headers=headers
            )

            if response.status_code in [200, 201]:
                result = response.json()
                if 'outputs' in result:
                    dataset_id = result['outputs'][0]['id']
                    dataset_ids.append(dataset_id)
                    print(f"  ✅ 上传: {Path(file_path).name} → {dataset_id}")
            else:
                print(f"  ❌ 上传失败: {file_path}")

    return dataset_ids


def create_collection(history_id, dataset_ids):
    """创建dataset collection"""
    headers = {"x-api-key": API_KEY, "Content-Type": "application/json"}

    print("\n📁 创建Collection...")

    elements = []
    for i, dataset_id in enumerate(dataset_ids, 1):
        elements.append({
            "name": f"sample{i}",
            "src": "hda",
            "id": dataset_id
        })

    data = {
        "collection_type": "list",
        "name": "test_collection",
        "element_identifiers": elements,
        "history_id": history_id
    }

    response = requests.post(
        f"{GALAXY_URL}/api/dataset_collections",
        json=data,
        headers=headers
    )

    if response.status_code in [200, 201]:
        collection = response.json()
        print(f"  ✅ Collection创建成功: {collection['id']}")
        return collection['id']
    else:
        print(f"  ❌ Collection创建失败: {response.status_code}")
        print(f"  错误: {response.text}")
        return None


def import_workflow():
    """导入workflow"""
    headers = {"x-api-key": API_KEY}

    print("\n📥 导入Workflow...")

    if not Path(WORKFLOW_FILE).exists():
        print(f"  ❌ Workflow文件不存在: {WORKFLOW_FILE}")
        return None

    with open(WORKFLOW_FILE) as f:
        workflow_data = json.load(f)

    response = requests.post(
        f"{GALAXY_URL}/api/workflows",
        json={"workflow": workflow_data},
        headers=headers
    )

    if response.status_code in [200, 201]:
        workflow = response.json()
        print(f"  ✅ Workflow导入成功: {workflow['name']}")
        return workflow['id']
    else:
        print(f"  ❌ Workflow导入失败: {response.status_code}")
        print(f"  错误: {response.text}")
        return None


def run_workflow(workflow_id, history_id, collection_id):
    """运行workflow"""
    headers = {"x-api-key": API_KEY, "Content-Type": "application/json"}

    print("\n▶️  运行Workflow...")

    data = {
        "workflow_id": workflow_id,
        "history": f"hist_id={history_id}",
        "inputs": {
            "0": {
                "id": collection_id,
                "src": "hdca"  # history dataset collection association
            }
        }
    }

    response = requests.post(
        f"{GALAXY_URL}/api/workflows/{workflow_id}/invocations",
        json=data,
        headers=headers
    )

    if response.status_code in [200, 201]:
        invocation = response.json()
        print(f"  ✅ Workflow已启动")
        print(f"  Invocation ID: {invocation['id']}")
        return invocation['id']
    else:
        print(f"  ❌ Workflow启动失败: {response.status_code}")
        print(f"  错误: {response.text}")
        return None


def monitor_workflow(workflow_id, invocation_id):
    """监控workflow执行"""
    headers = {"x-api-key": API_KEY}

    print("\n⏳ 监控Workflow执行...")

    max_wait = 300  # 5分钟超时
    waited = 0

    while waited < max_wait:
        response = requests.get(
            f"{GALAXY_URL}/api/workflows/{workflow_id}/invocations/{invocation_id}",
            headers=headers
        )

        if response.status_code == 200:
            invocation = response.json()
            state = invocation.get('state', 'unknown')

            print(f"  状态: {state} ({waited}s)")

            if state == 'scheduled':
                print("  ✅ Workflow完成！")
                return True
            elif state in ['failed', 'error']:
                print("  ❌ Workflow失败")
                return False

        time.sleep(5)
        waited += 5

    print("  ⚠️  监控超时")
    return False


def verify_cloud_execution(history_id):
    """验证是否在云端执行"""
    print("\n🔍 验证云执行...")

    # 这里需要检查作业详情
    # 简化版本：提示用户手动检查
    print("  请在Galaxy UI查看作业详情:")
    print(f"  → http://localhost:8080/histories/{history_id}")
    print("  → 查找 destination: cloud_small")
    print("  → 或运行: aws batch list-jobs --job-queue galaxy-cloud-queue")


def main():
    print("=" * 60)
    print("Galaxy 云执行自动化测试")
    print("=" * 60)

    # 1. 检查配置
    check_api_key()

    # 2. 测试连接
    if not test_connection():
        sys.exit(1)

    # 3. 获取历史记录
    history_id = get_or_create_history()

    # 4. 上传文件
    dataset_ids = upload_files(history_id)
    if not dataset_ids:
        print("❌ 没有文件被上传")
        sys.exit(1)

    # 5. 创建collection
    collection_id = create_collection(history_id, dataset_ids)
    if not collection_id:
        sys.exit(1)

    # 6. 导入workflow
    workflow_id = import_workflow()
    if not workflow_id:
        sys.exit(1)

    # 7. 运行workflow
    invocation_id = run_workflow(workflow_id, history_id, collection_id)
    if not invocation_id:
        sys.exit(1)

    # 8. 监控执行
    success = monitor_workflow(workflow_id, invocation_id)

    # 9. 验证云执行
    verify_cloud_execution(history_id)

    print("\n" + "=" * 60)
    if success:
        print("✅ 测试完成！")
        print("\n下一步:")
        print("1. 在Galaxy UI查看历史记录")
        print("2. 点击作业详情查看 destination")
        print("3. 运行: aws batch list-jobs --job-queue galaxy-cloud-queue")
    else:
        print("⚠️  测试未完全成功，请检查日志")
    print("=" * 60)


if __name__ == "__main__":
    main()
