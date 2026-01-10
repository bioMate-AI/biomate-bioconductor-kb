#!/usr/bin/env python3
"""
批量安装真实复杂workflow所需的所有工具
"""

import requests
import time
import sys
import json

GALAXY_URL = "http://localhost:8080"
API_KEY = "cf77c3d29b11d3fe1389600995adad8d"  # 需要设置

# Workflow所需的所有工具
REQUIRED_TOOLS = [
    {
        "name": "fastqc",
        "owner": "devteam",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "5ec9f6bceaee",
        "description": "FastQC - 测序质量评估"
    },
    {
        "name": "trimmomatic",
        "owner": "pjbriggs",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "d94aff5ee623",
        "description": "Trimmomatic - 质量修剪"
    },
    {
        "name": "bowtie2",
        "owner": "devteam",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "0d9b2c3a7fb1",
        "description": "Bowtie2 - 序列比对"
    },
    {
        "name": "bamtools_stats",
        "owner": "devteam",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "fa845c75ac00",
        "description": "BAM Stats - 比对统计"
    }
]


def check_api_key():
    if not API_KEY:
        print("❌ 需要API Key")
        print("\n获取方法：")
        print("1. 访问 http://localhost:8080")
        print("2. User → Preferences → Manage API Key")
        print("3. Create → 复制Key")
        print("4. 设置: API_KEY = 'your-key'")
        sys.exit(1)


def install_tool(tool_info):
    """安装单个工具"""
    headers = {"x-api-key": API_KEY}

    print(f"\n{'='*60}")
    print(f"安装: {tool_info['description']}")
    print(f"  名称: {tool_info['name']}")
    print(f"  所有者: {tool_info['owner']}")
    print(f"{'='*60}")

    # 检查是否已安装
    response = requests.get(f"{GALAXY_URL}/api/tool_shed_repositories", headers=headers)
    if response.status_code == 200:
        installed = response.json()
        for repo in installed:
            if (repo.get('name') == tool_info['name'] and
                repo.get('owner') == tool_info['owner'] and
                repo.get('status') in ['Installed', 'installed']):
                print(f"  ✅ 已安装，跳过")
                return True

    # 安装工具
    install_data = {
        "tool_shed_url": tool_info["tool_shed_url"],
        "name": tool_info["name"],
        "owner": tool_info["owner"],
        "changeset_revision": tool_info["changeset_revision"],
        "install_resolver_dependencies": True,
        "install_tool_dependencies": True,
        "install_repository_dependencies": True
    }

    print(f"  ⏳ 开始安装...")

    response = requests.post(
        f"{GALAXY_URL}/api/tool_shed_repositories",
        json=install_data,
        headers=headers
    )

    if response.status_code not in [200, 201]:
        print(f"  ❌ 安装请求失败: {response.status_code}")
        print(f"  错误: {response.text}")
        return False

    repo_data = response.json()
    repo_id = repo_data.get("id")

    # 监控安装进度
    max_wait = 600  # 10分钟
    waited = 0

    while waited < max_wait:
        time.sleep(10)
        waited += 10

        status_response = requests.get(
            f"{GALAXY_URL}/api/tool_shed_repositories/{repo_id}",
            headers=headers
        )

        if status_response.status_code == 200:
            status = status_response.json().get("status", "unknown")
            print(f"  状态: {status} ({waited}s)")

            if status in ["Installed", "installed"]:
                print(f"  ✅ 安装成功！")
                return True
            elif status in ["Error", "error", "Failed", "failed"]:
                error_msg = status_response.json().get("error_message", "未知错误")
                print(f"  ❌ 安装失败: {error_msg}")
                return False

    print(f"  ⚠️  安装超时")
    return False


def main():
    print("╔" + "="*58 + "╗")
    print("║  批量安装真实复杂workflow所需的所有工具                   ║")
    print("╚" + "="*58 + "╝")
    print()

    check_api_key()

    print(f"将安装 {len(REQUIRED_TOOLS)} 个工具:")
    for i, tool in enumerate(REQUIRED_TOOLS, 1):
        print(f"  {i}. {tool['description']}")
    print()

    success_count = 0
    failed_tools = []

    for tool in REQUIRED_TOOLS:
        if install_tool(tool):
            success_count += 1
        else:
            failed_tools.append(tool['name'])

    print("\n" + "="*60)
    print(f"安装完成: {success_count}/{len(REQUIRED_TOOLS)} 成功")
    print("="*60)

    if failed_tools:
        print(f"\n⚠️  失败的工具: {', '.join(failed_tools)}")
        print("可以在Galaxy UI手动安装:")
        print(f"  {GALAXY_URL}/admin/toolshed")
    else:
        print("\n✅ 所有工具安装成功！")
        print("\n下一步:")
        print("  1. 配置工具云端执行规则")
        print("  2. 准备测试数据")
        print("  3. 运行workflow测试")


if __name__ == "__main__":
    main()
