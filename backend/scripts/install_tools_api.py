#!/usr/bin/env python3
"""
Install Galaxy tools via Admin API
Simple script using only requests library
"""

import json
import time
import sys
import yaml
import requests
from pathlib import Path

# Galaxy configuration
GALAXY_URL = "http://127.0.0.1:8080"
# TODO: Set admin API key - for now we'll try without auth for bootstrap
ADMIN_API_KEY = None  # Will be set if available

def load_tools_config(config_file):
    """Load tools from YAML configuration"""
    with open(config_file, 'r') as f:
        config = yaml.safe_load(f)
    return config.get('tools', [])

def install_tool(tool, session):
    """Install a single tool via API"""

    install_data = {
        'tool_shed_url': tool['tool_shed_url'],
        'name': tool['repo_name'],
        'owner': tool['owner'],
        'changeset_revision': tool.get('changeset_revision', 'latest'),
        'install_tool_dependencies': True,
        'install_repository_dependencies': True,
        'install_resolver_dependencies': True,
    }

    print(f"📦 Installing: {tool['name']}")
    print(f"   Repository: {tool['repo_name']} (owner: {tool['owner']})")

    # Try to install via API
    url = f"{GALAXY_URL}/api/tool_shed_repositories/new/install_repository_revision"
    headers = {'Content-Type': 'application/json'}

    if ADMIN_API_KEY:
        headers['X-API-KEY'] = ADMIN_API_KEY

    try:
        response = session.post(url, json=install_data, headers=headers, timeout=10)

        if response.status_code == 200:
            print(f"✅ Installation started for {tool['name']}")
            return True
        elif response.status_code == 401:
            print(f"⚠️  Authentication required - need admin API key")
            return False
        else:
            print(f"❌ Failed to install {tool['name']}: HTTP {response.status_code}")
            print(f"   Response: {response.text[:200]}")
            return False

    except requests.exceptions.RequestException as e:
        print(f"❌ Network error installing {tool['name']}: {e}")
        return False

def check_galaxy_connection():
    """Check if Galaxy is accessible"""
    try:
        response = requests.get(f"{GALAXY_URL}/api/version", timeout=5)
        if response.status_code == 200:
            version = response.json()
            print(f"✅ Connected to Galaxy version: {version.get('version_major', 'unknown')}")
            return True
        else:
            print(f"❌ Galaxy returned HTTP {response.status_code}")
            return False
    except requests.exceptions.RequestException as e:
        print(f"❌ Cannot connect to Galaxy: {e}")
        return False

def main():
    """Main entry point"""

    # Configuration
    config_file = Path('/private/tmp/lcms-platform-galaxy/config/top_20_lcms_tools.yml')

    if not config_file.exists():
        print(f"❌ Configuration file not found: {config_file}")
        sys.exit(1)

    print("="*80)
    print("GALAXY TOOL INSTALLATION VIA ADMIN API")
    print("="*80)

    # Check Galaxy connection
    if not check_galaxy_connection():
        print("\n❌ Cannot connect to Galaxy. Make sure it's running on http://127.0.0.1:8080")
        sys.exit(1)

    # Load tools
    tools = load_tools_config(config_file)
    print(f"\n📋 Loaded {len(tools)} tools from configuration")

    # Create session
    session = requests.Session()

    # Try to install tools
    print("\n🚀 Starting tool installation...\n")

    installed = 0
    failed = 0

    for i, tool in enumerate(tools, 1):
        print(f"\n[{i}/{len(tools)}]", end=" ")

        if install_tool(tool, session):
            installed += 1
        else:
            failed += 1

        # Small delay between installations
        time.sleep(2)

    # Summary
    print("\n" + "="*80)
    print("INSTALLATION SUMMARY")
    print("="*80)
    print(f"Total tools: {len(tools)}")
    print(f"Started: {installed}")
    print(f"Failed: {failed}")

    if failed > 0 and installed == 0:
        print("\n⚠️  All installations failed!")
        print("   This likely means:")
        print("   1. Admin API key is required (set ADMIN_API_KEY variable)")
        print("   2. Or Galaxy Admin UI needs to be used instead")
        print("\n   Please use the Galaxy web interface at:")
        print(f"   {GALAXY_URL}/admin/toolshed")
        sys.exit(1)

if __name__ == '__main__':
    main()
