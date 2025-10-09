"""
On-Demand Tool Installer for Galaxy
Automatically installs tools from ToolShed when needed by workflows
"""

import time
import logging
from typing import Dict, Optional, Any
from enum import Enum

log = logging.getLogger(__name__)


class InstallStatus(Enum):
    """Installation status states"""
    NOT_INSTALLED = "not_installed"
    QUEUED = "queued"
    INSTALLING = "installing"
    INSTALLED = "installed"
    FAILED = "failed"
    ERROR = "error"


class InstallationError(Exception):
    """Raised when tool installation fails"""
    pass


class OnDemandToolInstaller:
    """
    Handles on-demand installation of Galaxy tools from ToolShed
    """

    def __init__(self, app, search_index=None):
        self.app = app
        self.search_index = search_index
        self.install_model = app.install_model
        self.toolbox = app.toolbox

    def is_tool_installed(self, tool_id: str) -> bool:
        """
        Check if a tool is installed in Galaxy

        Args:
            tool_id: Tool identifier

        Returns:
            True if installed, False otherwise
        """
        try:
            # Check in toolbox
            tool = self.toolbox.get_tool(tool_id)
            return tool is not None
        except Exception:
            return False

    def get_tool_from_index(self, tool_id: str) -> Optional[Dict[str, Any]]:
        """Get tool metadata from search index"""
        if self.search_index:
            return self.search_index.get_by_id(tool_id)
        return None

    def install_tool_sync(
        self,
        tool_id: str = None,
        owner: str = None,
        name: str = None,
        changeset_revision: str = None,
        tool_shed_url: str = "https://toolshed.g2.bx.psu.edu",
        tool_panel_section_id: str = "lcms_metabolomics",
        timeout: int = 600,
        retry_count: int = 3
    ) -> Dict[str, Any]:
        """
        Synchronously install a tool from ToolShed

        Args:
            tool_id: Tool ID (can be used to lookup in index)
            owner: Repository owner
            name: Repository name
            changeset_revision: Specific changeset (or 'latest')
            tool_shed_url: ToolShed URL
            tool_panel_section_id: Where to place tool in panel
            timeout: Max wait time in seconds
            retry_count: Number of retry attempts

        Returns:
            Dict with installation results
        """
        # If only tool_id provided, lookup in index
        if tool_id and not (owner and name):
            tool_meta = self.get_tool_from_index(tool_id)
            if tool_meta:
                owner = tool_meta['repo_owner']
                name = tool_meta['repo_name']
                changeset_revision = tool_meta.get('changeset_revision') or changeset_revision
            else:
                return {
                    'success': False,
                    'error': 'ToolNotFound',
                    'message': f'Tool {tool_id} not found in index'
                }

        if not (owner and name):
            return {
                'success': False,
                'error': 'MissingParameters',
                'message': 'Must provide either tool_id or (owner, name)'
            }

        log.info(f"Installing tool: {owner}/{name} (changeset: {changeset_revision})")

        # Check if already installed
        if tool_id and self.is_tool_installed(tool_id):
            log.info(f"Tool {tool_id} already installed")
            return {
                'success': True,
                'already_installed': True,
                'tool_id': tool_id
            }

        # Mark as installing BEFORE first attempt (prevents race condition)
        if self.search_index and tool_id:
            try:
                self.search_index.mark_installed(tool_id, 'installing')
            except Exception as e:
                log.warning(f"Failed to mark tool as installing: {e}")

        # Attempt installation with retries
        last_error = None
        for attempt in range(retry_count):
            try:
                result = self._install_from_toolshed(
                    owner=owner,
                    name=name,
                    changeset_revision=changeset_revision,
                    tool_shed_url=tool_shed_url,
                    tool_panel_section_id=tool_panel_section_id,
                    timeout=timeout
                )

                if result['success']:
                    # Update search index to installed (atomic update)
                    if self.search_index and tool_id:
                        try:
                            self.search_index.mark_installed(tool_id, 'installed')
                        except Exception as e:
                            log.error(f"Failed to mark tool as installed: {e}")
                    return result
                else:
                    last_error = result.get('error', 'Unknown error')

            except Exception as e:
                last_error = str(e)
                log.error(f"Installation attempt {attempt + 1} failed: {e}")

                if attempt < retry_count - 1:
                    wait_time = 2 ** attempt  # Exponential backoff
                    log.info(f"Retrying in {wait_time} seconds...")
                    time.sleep(wait_time)

        # All attempts failed - mark as failed (atomic update)
        if self.search_index and tool_id:
            try:
                self.search_index.mark_installed(tool_id, 'failed')
            except Exception as e:
                log.error(f"Failed to mark tool as failed: {e}")

        return {
            'success': False,
            'error': 'InstallationFailed',
            'message': f'Failed after {retry_count} attempts: {last_error}'
        }

    def _install_from_toolshed(
        self,
        owner: str,
        name: str,
        changeset_revision: str,
        tool_shed_url: str,
        tool_panel_section_id: str,
        timeout: int
    ) -> Dict[str, Any]:
        """
        Internal method to install tool via Galaxy's install manager

        Returns:
            Dict with installation result
        """
        from galaxy.tool_shed.galaxy_install.install_manager import (
            InstallRepositoryManager,
            get_install_info_from_tool_shed
        )
        from galaxy.util.tool_shed.tool_shed_registry import Registry

        try:
            # Get ToolShed registry
            tool_shed_registry = Registry(self.app.config.tool_sheds_config_file)

            # Get installation info from ToolShed
            log.info(f"Fetching install info from {tool_shed_url}")
            repo_info_dict, extra_info = get_install_info_from_tool_shed(
                tool_shed_url=tool_shed_url,
                tool_shed_registry=tool_shed_registry,
                name=name,
                owner=owner,
                changeset_revision=changeset_revision
            )

            # Create installation dict
            installation_dict = {
                'install_repository_dependencies': True,
                'install_resolver_dependencies': True,
                'install_tool_dependencies': False,  # Use Conda instead
                'new_tool_panel_section_label': '',
                'tool_panel_section_id': tool_panel_section_id,
                'shed_tool_conf': self.app.config.shed_tool_config_file,
                'tool_path': self.app.config.tool_path,
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
            irm = InstallRepositoryManager(self.app)

            # Create/update repository
            created_repos, tool_panel_section_keys, repo_info_dicts, filtered_repo_info_dicts = \
                irm.handle_tool_shed_repositories(installation_dict)

            if not created_repos:
                return {
                    'success': False,
                    'error': 'RepositoryCreationFailed',
                    'message': 'Failed to create repository record'
                }

            # Update installation dict with created repos
            installation_dict.update({
                'created_or_updated_tool_shed_repositories': created_repos,
                'tool_panel_section_keys': tool_panel_section_keys,
                'filtered_repo_info_dicts': filtered_repo_info_dicts,
                'tool_panel_section_mapping': {}
            })

            # Initiate installation
            encoded_repo_ids = irm.initiate_repository_installation(installation_dict)

            # Wait for toolbox reload
            log.info("Waiting for toolbox reload...")
            old_toolbox = self.app.toolbox
            self.app.wait_for_toolbox_reload(old_toolbox)

            log.info(f"✓ Successfully installed {owner}/{name}")

            return {
                'success': True,
                'repository_ids': encoded_repo_ids,
                'owner': owner,
                'name': name,
                'changeset': changeset_revision
            }

        except Exception as e:
            log.error(f"Installation error: {e}", exc_info=True)
            return {
                'success': False,
                'error': type(e).__name__,
                'message': str(e)
            }

    def check_and_install(self, tool_id: str, **kwargs) -> Dict[str, Any]:
        """
        Check if tool is installed, install if not

        Convenience method combining check + install

        Args:
            tool_id: Tool identifier
            **kwargs: Additional arguments for install_tool_sync

        Returns:
            Dict with status and results
        """
        if self.is_tool_installed(tool_id):
            return {
                'success': True,
                'already_installed': True,
                'tool_id': tool_id
            }

        return self.install_tool_sync(tool_id=tool_id, **kwargs)
