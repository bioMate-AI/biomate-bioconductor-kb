#!/usr/bin/env python3
"""
自动安装测试所需的Galaxy工具
使用Galaxy API从Tool Shed安装工具
"""

import requests
import time
import sys
from typing import List, Dict

# Galaxy配置
GALAXY_URL = "http://localhost:8080"
# 你需要创建一个API key: Galaxy UI -> User -> API Keys
API_KEY = None  # 需要你在Galaxy UI中生成

# 简单的测试工具（小而快）
TEST_TOOLS = [
    {
        "name": "collection_element_identifiers",
        "owner": "iuc",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "d3c07d270a50"
    },
    {
        "name": "regex_find_replace",
        "owner": "galaxyp",
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "changeset_revision": "503bcd6ebe4b"
    }
]


def check_galaxy_admin():
    """检查Galaxy连接和管理员权限"""
    if not API_KEY:
        print("❌ 错误：需要API Key")
        print("\n请按以下步骤操作：")
        print("1. 访问 http://localhost:8080")
        print("2. 注册/登录账户")
        print("3. 点击 User -> Preferences -> Manage API Key")
        print("4. 创建新的API Key")
        print("5. 将API Key设置到此脚本的API_KEY变量中")
        return False

    headers = {"x-api-key": API_KEY}

    try:
        # 检查连接
        response = requests.get(f"{GALAXY_URL}/api/version", headers=headers)
        if response.status_code != 200:
            print(f"❌ 无法连接到Galaxy: {response.status_code}")
            return False

        print(f"✓ Galaxy版本: {response.json()['version_major']}")

        # 检查是否是管理员
        response = requests.get(f"{GALAXY_URL}/api/users/current", headers=headers)
        user_data = response.json()

        if not user_data.get("is_admin", False):
            print("❌ 当前用户不是管理员")
            print("\n需要设置管理员权限：")
            print(f"1. 编辑 config/galaxy.yml")
            print(f"2. 添加: admin_users: {user_data.get('email', 'your-email@example.com')}")
            print(f"3. 重启Galaxy")
            return False

        print(f"✓ 管理员用户: {user_data.get('email')}")
        return True

    except Exception as e:
        print(f"❌ 检查Galaxy时出错: {e}")
        return False


def install_tool(tool_info: Dict) -> bool:
    """安装单个工具"""
    headers = {"x-api-key": API_KEY}

    print(f"\n正在安装: {tool_info['owner']}/{tool_info['name']}")

    # 准备安装请求
    install_data = {
        "tool_shed_url": tool_info["tool_shed_url"],
        "name": tool_info["name"],
        "owner": tool_info["owner"],
        "changeset_revision": tool_info["changeset_revision"],
        "install_resolver_dependencies": True,
        "install_tool_dependencies": True
    }

    try:
        # 提交安装请求
        response = requests.post(
            f"{GALAXY_URL}/api/tool_shed_repositories",
            json=install_data,
            headers=headers
        )

        if response.status_code not in [200, 201]:
            print(f"  ❌ 安装失败: {response.text}")
            return False

        repo_data = response.json()
        print(f"  ⏳ 安装中... (repository_id: {repo_data.get('id')})")

        # 等待安装完成
        repo_id = repo_data.get("id")
        max_wait = 300  # 5分钟超时
        waited = 0

        while waited < max_wait:
            time.sleep(5)
            waited += 5

            # 检查安装状态
            status_response = requests.get(
                f"{GALAXY_URL}/api/tool_shed_repositories/{repo_id}",
                headers=headers
            )

            if status_response.status_code == 200:
                status = status_response.json().get("status", "unknown")
                print(f"  状态: {status} ({waited}s)")

                if status == "Installed":
                    print(f"  ✓ 安装成功！")
                    return True
                elif status in ["Error", "Failed"]:
                    print(f"  ❌ 安装失败")
                    return False

        print(f"  ⚠️  安装超时")
        return False

    except Exception as e:
        print(f"  ❌ 安装出错: {e}")
        return False


def main():
    print("=" * 60)
    print("Galaxy 测试工具自动安装器")
    print("=" * 60)

    # 检查Galaxy和权限
    if not check_galaxy_admin():
        sys.exit(1)

    print("\n" + "=" * 60)
    print(f"将安装 {len(TEST_TOOLS)} 个测试工具")
    print("=" * 60)

    # 安装所有工具
    success_count = 0
    for tool in TEST_TOOLS:
        if install_tool(tool):
            success_count += 1

    # 总结
    print("\n" + "=" * 60)
    print(f"安装完成: {success_count}/{len(TEST_TOOLS)} 成功")
    print("=" * 60)

    if success_count == len(TEST_TOOLS):
        print("\n✓ 所有工具安装成功！")
        print("\n现在可以测试云执行了：")
        print("1. 在Galaxy UI中导入workflow")
        print("2. 运行workflow")
        print("3. IUC工具将自动在AWS Batch上运行")
        return 0
    else:
        print("\n⚠️  部分工具安装失败")
        print("你可以在Galaxy UI中手动安装：")
        print("http://localhost:8080/admin/toolshed")
        return 1


if __name__ == "__main__":
    sys.exit(main())
