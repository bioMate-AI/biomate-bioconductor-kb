#!/usr/bin/env python3
"""
Install Top 20 LC-MS Tools for Local Testing

This script installs the top 20 LC-MS/Metabolomics tools from the ToolShed
into the local Galaxy instance for workflow testing.

Usage:
    cd /private/tmp/lcms-platform-galaxy
    python3 scripts/install_top_20_tools.py

Requirements:
    - Galaxy must be running
    - Must be run from Galaxy root directory
    - Admin privileges required
"""

import os
import sys
import yaml
import time
import logging
from pathlib import Path

# Add Galaxy lib to path
GALAXY_ROOT = Path(__file__).parent.parent
sys.path.insert(1, str(GALAXY_ROOT / "lib"))

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
log = logging.getLogger(__name__)


def load_tools_config(config_path: str) -> dict:
    """Load tool configuration from YAML file"""
    with open(config_path, 'r') as f:
        return yaml.safe_load(f)


def install_tools_direct(config_path: str):
    """
    Install tools using Galaxy's internal API (direct mode)
    This approach doesn't require REST API or authentication
    """
    try:
        from galaxy.tool_shed.galaxy_install.install_manager import (
            InstallRepositoryManager,
            get_install_info_from_tool_shed
        )
        from galaxy.util.tool_shed.tool_shed_registry import Registry
        from galaxy.model.base import transaction
        from galaxy.app import UniverseApplication
        from galaxy.config import GalaxyAppConfiguration

        log.info("=" * 70)
        log.info("Galaxy Top 20 LC-MS Tools Installation")
        log.info("=" * 70)

        # Load configuration
        config_file = GALAXY_ROOT / "config" / "galaxy.yml"
        if not config_file.exists():
            config_file = GALAXY_ROOT / "config" / "galaxy.yml.sample"

        log.info(f"Loading Galaxy configuration from: {config_file}")
        config = GalaxyAppConfiguration(config_file=str(config_file))

        log.info("Initializing Galaxy application...")
        app = UniverseApplication(config=config)

        log.info("Loading tool configuration...")
        tool_config = load_tools_config(config_path)
        tools = tool_config['tools']

        log.info(f"Found {len(tools)} tools to install\n")

        # Get ToolShed registry
        tool_shed_registry = Registry(app.config.tool_sheds_config_file)

        # Create installation manager
        irm = InstallRepositoryManager(app)

        installed_count = 0
        failed_count = 0
        skipped_count = 0

        for i, tool in enumerate(tools, 1):
            tool_name = tool['name']
            owner = tool['owner']
            repo_name = tool['repo_name']
            changeset = tool['changeset_revision']
            tool_shed_url = tool['tool_shed_url']

            log.info(f"[{i}/{len(tools)}] Installing: {tool_name}")
            log.info(f"  Repository: {owner}/{repo_name}")
            log.info(f"  Changeset: {changeset}")

            try:
                # Check if already installed
                existing = app.install_model.context.query(app.install_model.ToolShedRepository).filter(
                    app.install_model.ToolShedRepository.name == repo_name,
                    app.install_model.ToolShedRepository.owner == owner,
                    app.install_model.ToolShedRepository.changeset_revision == changeset
                ).first()

                if existing:
                    log.info(f"  ✅ Already installed - skipping\n")
                    skipped_count += 1
                    continue

                # Get installation info from ToolShed
                log.info(f"  📦 Fetching from ToolShed...")
                repo_info_dict, extra_info = get_install_info_from_tool_shed(
                    tool_shed_url=tool_shed_url,
                    tool_shed_registry=tool_shed_registry,
                    name=repo_name,
                    owner=owner,
                    changeset_revision=changeset
                )

                # Create installation dict
                installation_dict = {
                    'install_repository_dependencies': tool_config.get('install_repository_dependencies', True),
                    'install_resolver_dependencies': tool_config.get('install_resolver_dependencies', True),
                    'install_tool_dependencies': False,  # Use Conda instead
                    'new_tool_panel_section_label': tool.get('tool_panel_section_label', 'LC-MS Metabolomics'),
                    'tool_panel_section_id': '',
                    'shed_tool_conf': app.config.shed_tool_config_file,
                    'tool_path': app.config.tool_path,
                    'tool_shed_url': tool_shed_url,
                    'repo_info_dicts': [extra_info],
                    'no_changes_checked': False,
                    'has_repository_dependencies': False,
                    'includes_tool_dependencies': False,
                    'includes_tools': True,
                    'includes_tools_for_display_in_tool_panel': True,
                    'message': '',
                    'status': 'ok'
                }

                # Install via InstallRepositoryManager
                log.info(f"  🔧 Installing repository...")
                created_repos, tool_panel_section_keys, repo_info_dicts, filtered_repo_info_dicts = \
                    irm.handle_tool_shed_repositories(installation_dict)

                if not created_repos:
                    log.error(f"  ❌ Failed to create repository record\n")
                    failed_count += 1
                    continue

                # Update installation dict
                installation_dict.update({
                    'created_or_updated_tool_shed_repositories': created_repos,
                    'tool_panel_section_keys': tool_panel_section_keys,
                    'filtered_repo_info_dicts': filtered_repo_info_dicts,
                    'tool_panel_section_mapping': {}
                })

                # Initiate installation
                log.info(f"  ⏳ Installing (this may take 5-30 minutes)...")
                encoded_repo_ids = irm.initiate_repository_installation(installation_dict)

                # Wait for toolbox reload
                log.info(f"  🔄 Reloading toolbox...")
                old_toolbox = app.toolbox
                app.wait_for_toolbox_reload(old_toolbox)

                log.info(f"  ✅ Successfully installed!\n")
                installed_count += 1

                # Add small delay between installations
                time.sleep(2)

            except Exception as e:
                log.error(f"  ❌ Installation failed: {e}\n")
                failed_count += 1
                continue

        # Print summary
        log.info("=" * 70)
        log.info("Installation Summary")
        log.info("=" * 70)
        log.info(f"✅ Successfully installed: {installed_count}")
        log.info(f"⏭️  Already installed (skipped): {skipped_count}")
        log.info(f"❌ Failed: {failed_count}")
        log.info(f"📊 Total tools processed: {len(tools)}")
        log.info("=" * 70)

        return installed_count, skipped_count, failed_count

    except ImportError as e:
        log.error(f"Failed to import Galaxy modules: {e}")
        log.error("Make sure you're running this script from the Galaxy root directory")
        log.error("and that Galaxy is properly installed.")
        sys.exit(1)
    except Exception as e:
        log.error(f"Unexpected error: {e}", exc_info=True)
        sys.exit(1)


def main():
    """Main entry point"""
    # Check we're in Galaxy root
    if not (GALAXY_ROOT / "lib" / "galaxy").exists():
        log.error("Error: Must be run from Galaxy root directory")
        log.error(f"Current path: {GALAXY_ROOT}")
        log.error("Expected: /private/tmp/lcms-platform-galaxy")
        sys.exit(1)

    # Load tool configuration
    config_path = GALAXY_ROOT / "config" / "top_20_lcms_tools.yml"
    if not config_path.exists():
        log.error(f"Error: Configuration file not found: {config_path}")
        sys.exit(1)

    log.info(f"Configuration file: {config_path}")

    # Note about requirements
    log.info("\n⚠️  IMPORTANT NOTES:")
    log.info("  - Galaxy must be RUNNING (./run.sh in another terminal)")
    log.info("  - This script requires admin privileges")
    log.info("  - Installation may take 1-2 hours for all 20 tools")
    log.info("  - Each tool takes 5-30 minutes to install")
    log.info("\nPress Ctrl+C now to cancel, or wait 5 seconds to continue...")

    try:
        time.sleep(5)
    except KeyboardInterrupt:
        log.info("\nInstallation cancelled by user")
        sys.exit(0)

    # Run installation
    install_tools_direct(str(config_path))


if __name__ == '__main__':
    main()
