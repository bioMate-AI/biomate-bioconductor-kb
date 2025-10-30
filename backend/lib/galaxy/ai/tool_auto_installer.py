"""
Automatic Tool Installation System for BioMate

Similar to BioMni's environment setup, this automatically installs missing
Galaxy tools during workflow execution.
"""

import os
import json
import logging
import shutil
import subprocess
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime

log = logging.getLogger(__name__)


class ToolAutoInstaller:
    """Automatically install missing Galaxy tools during workflow execution."""

    def __init__(self, galaxy_root: str, biomate_tools_root: str = None,
                 galaxy_api_url: str = None, galaxy_api_key: str = None):
        """
        Initialize the tool auto-installer.

        Args:
            galaxy_root: Path to Galaxy installation root
            biomate_tools_root: Path to BioMate tools repository (defaults to backend/tools)
            galaxy_api_url: Galaxy API URL (e.g., http://localhost:8080) for Toolshed installs
            galaxy_api_key: Galaxy admin API key for Toolshed installs
        """
        self.galaxy_root = Path(galaxy_root)
        self.galaxy_tools_dir = self.galaxy_root / "tools" / "biomate_custom"
        self.tool_conf_file = self.galaxy_root / "config" / "tool_conf_biomate.xml"
        self.galaxy_api_url = galaxy_api_url
        self.galaxy_api_key = galaxy_api_key

        if biomate_tools_root is None:
            # Default to backend/tools relative to this file
            biomate_tools_root = Path(__file__).parent.parent.parent.parent.parent / "tools"
        self.biomate_tools_root = Path(biomate_tools_root)

        # Track installed tools
        self.installed_tools_cache = self._load_installed_tools_cache()

        # Tool source mapping (from our analysis)
        self.tool_source_mapping = self._load_tool_source_mapping()

    def _load_installed_tools_cache(self) -> Dict:
        """Load cache of already installed tools."""
        cache_file = self.galaxy_root / "database" / "biomate_installed_tools.json"

        if cache_file.exists():
            try:
                with open(cache_file) as f:
                    return json.load(f)
            except Exception as e:
                log.warning(f"Could not load installed tools cache: {e}")

        return {
            "installed_tools": [],
            "last_updated": None,
            "install_log": []
        }

    def _save_installed_tools_cache(self):
        """Save cache of installed tools."""
        cache_file = self.galaxy_root / "database" / "biomate_installed_tools.json"
        cache_file.parent.mkdir(parents=True, exist_ok=True)

        try:
            with open(cache_file, 'w') as f:
                json.dump(self.installed_tools_cache, f, indent=2)
        except Exception as e:
            log.error(f"Could not save installed tools cache: {e}")

    def _load_tool_source_mapping(self) -> Dict:
        """Load tool source mapping for installation priority."""
        mapping_file = Path(__file__).parent.parent.parent.parent.parent / "TOOL_SOURCE_MAPPING.json"

        if mapping_file.exists():
            try:
                with open(mapping_file) as f:
                    data = json.load(f)
                    return data.get("tools", {})
            except Exception as e:
                log.warning(f"Could not load tool source mapping: {e}")

        return {}

    def is_tool_installed(self, tool_id: str) -> bool:
        """
        Check if a tool is already installed.

        Args:
            tool_id: Galaxy tool ID

        Returns:
            True if tool is installed, False otherwise
        """
        # Check cache first
        if tool_id in self.installed_tools_cache["installed_tools"]:
            return True

        # Check if tool file exists
        tool_file = self._find_tool_file(tool_id)
        if tool_file and tool_file.exists():
            # Add to cache
            self.installed_tools_cache["installed_tools"].append(tool_id)
            self._save_installed_tools_cache()
            return True

        return False

    def _find_tool_file(self, tool_id: str) -> Optional[Path]:
        """Find the XML file for a tool ID."""
        # Tool ID might be like "nfcore_gatk4_haplotypecaller" or "gatk4_haplotypecaller"
        # Try to find corresponding XML file

        # Search in all tool directories
        for tool_dir in self.galaxy_tools_dir.glob("*"):
            if not tool_dir.is_dir():
                continue

            # Try exact match
            xml_file = tool_dir / f"{tool_id}.xml"
            if xml_file.exists():
                return xml_file

            # Try without prefix
            for prefix in ["nfcore_", "biomni_"]:
                if tool_id.startswith(prefix):
                    unprefixed_id = tool_id[len(prefix):]
                    xml_file = tool_dir / f"{unprefixed_id}.xml"
                    if xml_file.exists():
                        return xml_file

        return None

    def install_tool(self, tool_id: str, force: bool = False) -> Tuple[bool, str]:
        """
        Install a single tool.

        Args:
            tool_id: Galaxy tool ID to install
            force: Force reinstall even if already installed

        Returns:
            Tuple of (success, message)
        """
        if not force and self.is_tool_installed(tool_id):
            return True, f"Tool {tool_id} already installed"

        log.info(f"Installing tool: {tool_id}")

        # Find tool in BioMate repository
        source_file = self._find_tool_in_biomate_repo(tool_id)

        if not source_file:
            msg = f"Tool {tool_id} not found in BioMate repository"
            log.error(msg)
            return False, msg

        # Determine target directory based on tool category
        target_dir = self._get_target_directory(tool_id)
        target_dir.mkdir(parents=True, exist_ok=True)

        # Copy tool file
        target_file = target_dir / source_file.name

        try:
            shutil.copy2(source_file, target_file)
            log.info(f"Copied {source_file} to {target_file}")
        except Exception as e:
            msg = f"Failed to copy tool file: {e}"
            log.error(msg)
            return False, msg

        # Update tool configuration
        success, msg = self._update_tool_conf(tool_id, target_file)

        if not success:
            return False, msg

        # Add to installed tools cache
        self.installed_tools_cache["installed_tools"].append(tool_id)
        self.installed_tools_cache["last_updated"] = datetime.now().isoformat()
        self.installed_tools_cache["install_log"].append({
            "tool_id": tool_id,
            "installed_at": datetime.now().isoformat(),
            "source_file": str(source_file),
            "target_file": str(target_file)
        })
        self._save_installed_tools_cache()

        log.info(f"Successfully installed tool: {tool_id}")
        return True, f"Tool {tool_id} installed successfully"

    def _find_tool_in_biomate_repo(self, tool_id: str) -> Optional[Path]:
        """Find tool XML file in BioMate repository."""
        # Search in all subdirectories
        for tool_dir in self.biomate_tools_root.glob("*"):
            if not tool_dir.is_dir():
                continue

            # Try exact match
            xml_file = tool_dir / f"{tool_id}.xml"
            if xml_file.exists():
                return xml_file

            # Try with/without common prefixes
            for prefix in ["", "nfcore_", "biomni_"]:
                test_id = f"{prefix}{tool_id}" if prefix else tool_id
                xml_file = tool_dir / f"{test_id}.xml"
                if xml_file.exists():
                    return xml_file

                # Also try removing prefix
                if tool_id.startswith(prefix) and prefix:
                    unprefixed_id = tool_id[len(prefix):]
                    xml_file = tool_dir / f"{unprefixed_id}.xml"
                    if xml_file.exists():
                        return xml_file

        return None

    def _get_target_directory(self, tool_id: str) -> Path:
        """Determine target directory for a tool based on its category."""
        # Check tool source mapping for category
        if tool_id in self.tool_source_mapping:
            sources = self.tool_source_mapping[tool_id].get("sources", [])
            if "biomni" in sources:
                return self.galaxy_tools_dir / "biomni_missing"
            elif "nfcore" in sources:
                # Check if it's LC-MS related
                if any(term in tool_id.lower() for term in ["openms", "diann", "maxquant", "sage", "thermo"]):
                    return self.galaxy_tools_dir / "nfcore_lcms"
                else:
                    return self.galaxy_tools_dir / "nfcore_general"

        # Default categorization based on tool_id
        if any(term in tool_id.lower() for term in ["openms", "diann", "maxquant", "proteomics"]):
            return self.galaxy_tools_dir / "nfcore_lcms"
        elif any(term in tool_id.lower() for term in ["rdkit", "openmm", "cellpose", "python", "cobra"]):
            return self.galaxy_tools_dir / "biomni_missing"
        else:
            return self.galaxy_tools_dir / "nfcore_general"

    def _update_tool_conf(self, tool_id: str, tool_file: Path) -> Tuple[bool, str]:
        """Update tool_conf_biomate.xml to include newly installed tool."""
        try:
            # Get relative path from Galaxy root
            rel_path = tool_file.relative_to(self.galaxy_root / "tools")

            # Read existing config
            if self.tool_conf_file.exists():
                with open(self.tool_conf_file) as f:
                    config_lines = f.readlines()
            else:
                # Create new config file
                config_lines = [
                    '<?xml version="1.0" encoding="utf-8"?>\n',
                    '<toolbox>\n',
                    '  <!-- BioMate Custom Tools - Auto-generated -->\n',
                    '</toolbox>\n'
                ]

            # Check if tool already in config
            tool_entry = f'<tool file="{rel_path}"/>'
            if any(tool_entry in line for line in config_lines):
                return True, "Tool already in configuration"

            # Find appropriate section
            section_id = self._get_section_for_tool(tool_id)
            section_found = False
            insert_index = -1

            for i, line in enumerate(config_lines):
                if f'id="{section_id}"' in line:
                    section_found = True
                if section_found and '</section>' in line:
                    insert_index = i
                    break

            # If section not found, create it
            if not section_found:
                insert_index = len(config_lines) - 1  # Before </toolbox>
                section_name = self._get_section_name(section_id)
                config_lines.insert(insert_index, f'  <section id="{section_id}" name="{section_name}">\n')
                insert_index += 1
                config_lines.insert(insert_index, f'  </section>\n')

            # Insert tool entry
            config_lines.insert(insert_index, f'    <tool file="{rel_path}"/>\n')

            # Write updated config
            self.tool_conf_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.tool_conf_file, 'w') as f:
                f.writelines(config_lines)

            log.info(f"Updated tool configuration: {self.tool_conf_file}")
            return True, "Tool configuration updated"

        except Exception as e:
            msg = f"Failed to update tool configuration: {e}"
            log.error(msg)
            return False, msg

    def _get_section_for_tool(self, tool_id: str) -> str:
        """Get tool section ID based on tool_id."""
        if any(term in tool_id.lower() for term in ["openms", "diann", "maxquant", "proteomics"]):
            return "biomate_nfcore_lcms"
        elif any(term in tool_id.lower() for term in ["rdkit", "openmm", "cellpose", "cobra"]):
            return "biomate_biomni_missing"
        else:
            return "biomate_nfcore_general"

    def _get_section_name(self, section_id: str) -> str:
        """Get human-readable section name."""
        section_names = {
            "biomate_nfcore_lcms": "nf-core LC-MS Tools",
            "biomate_nfcore_general": "nf-core General Tools",
            "biomate_biomni_missing": "BioMni Python/R Tools",
            "biomate_nfcore_missing": "nf-core Additional Tools"
        }
        return section_names.get(section_id, "BioMate Custom Tools")

    def install_missing_tools(self, tool_ids: List[str]) -> Dict[str, Tuple[bool, str]]:
        """
        Install multiple tools.

        Args:
            tool_ids: List of tool IDs to install

        Returns:
            Dictionary mapping tool_id to (success, message)
        """
        results = {}

        for tool_id in tool_ids:
            success, msg = self.install_tool(tool_id)
            results[tool_id] = (success, msg)

            if not success:
                log.warning(f"Failed to install {tool_id}: {msg}")

        # Reload Galaxy tools (if possible)
        self._reload_galaxy_toolbox()

        return results

    def _reload_galaxy_toolbox(self):
        """Attempt to reload Galaxy's toolbox without full restart."""
        try:
            # This would require Galaxy API integration
            # For now, just log that a reload is needed
            log.info("Tools installed. Galaxy toolbox reload required.")
            log.info("To reload: Restart Galaxy or use Galaxy admin interface")

            # In production, could use Galaxy's API:
            # POST /api/configuration/toolbox with admin API key

        except Exception as e:
            log.warning(f"Could not reload Galaxy toolbox: {e}")

    def validate_workflow_tools(self, workflow_dict: Dict) -> Tuple[List[str], List[str], List[str]]:
        """
        Validate that all tools in a workflow are available.

        Args:
            workflow_dict: Galaxy workflow dictionary

        Returns:
            Tuple of (available_tools, missing_custom_tools, missing_toolshed_tools)
        """
        available = []
        missing_custom = []
        missing_toolshed = []

        for step in workflow_dict.get("steps", {}).values():
            tool_id = step.get("tool_id")

            if not tool_id:
                continue

            # Toolshed tools - use Galaxy's API to check/install
            if tool_id.startswith("toolshed.g2.bx.psu.edu"):
                if self._is_toolshed_tool_installed(tool_id):
                    available.append(tool_id)
                else:
                    missing_toolshed.append(tool_id)
                continue

            # Custom BioMate tools - use our installation system
            if self.is_tool_installed(tool_id):
                available.append(tool_id)
            else:
                missing_custom.append(tool_id)

        return available, missing_custom, missing_toolshed

    def _is_toolshed_tool_installed(self, tool_id: str) -> bool:
        """
        Check if a Toolshed tool is installed in Galaxy.

        Args:
            tool_id: Full Toolshed tool ID (e.g., toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73)

        Returns:
            True if installed, False otherwise
        """
        # If no API access, assume not installed
        if not self.galaxy_api_url or not self.galaxy_api_key:
            log.warning(f"No Galaxy API credentials available for tool check: {tool_id}")
            return False

        try:
            import requests

            # Parse tool_id: toolshed.g2.bx.psu.edu/repos/{owner}/{name}/{tool}/{version}
            parts = tool_id.split("/")
            if len(parts) < 5:
                log.warning(f"Invalid ToolShed tool ID format: {tool_id}")
                return False

            owner = parts[3]
            name = parts[4]

            # Check installed repositories via Galaxy API
            headers = {"x-api-key": self.galaxy_api_key}
            url = f"{self.galaxy_api_url}/api/tool_shed_repositories"

            log.debug(f"Checking if {owner}/{name} is installed via {url}")

            response = requests.get(url, headers=headers, timeout=5)

            if response.status_code != 200:
                log.warning(f"Galaxy API returned status {response.status_code} for repository check")
                return False

            installed_repos = response.json()

            # Check if this repo is installed
            for repo in installed_repos:
                if repo.get("owner") == owner and repo.get("name") == name:
                    status = repo.get("status", "")
                    if status == "Installed":
                        log.info(f"Tool {owner}/{name} is installed (status: {status})")
                        return True
                    else:
                        log.info(f"Tool {owner}/{name} found but not fully installed (status: {status})")
                        return False

            log.info(f"Tool {owner}/{name} not found in installed repositories")
            return False

        except Exception as e:
            log.warning(f"Could not check ToolShed tool installation for {tool_id}: {e}")
            return False

    def _install_toolshed_tools(self, tool_ids: List[str]) -> Dict[str, Tuple[bool, str]]:
        """
        Install tools from Galaxy Toolshed using Galaxy's API.

        Args:
            tool_ids: List of Toolshed tool IDs

        Returns:
            Dictionary mapping tool_id to (success, message)
        """
        results = {}

        # If Galaxy API is configured, use it for real installation
        if self.galaxy_api_url and self.galaxy_api_key:
            return self._install_toolshed_via_api(tool_ids)

        # Otherwise, mark for Galaxy to handle on first use
        for tool_id in tool_ids:
            try:
                # Parse Toolshed tool ID
                # Format: toolshed.g2.bx.psu.edu/repos/{owner}/{name}/{tool}/{version}
                parts = tool_id.split("/")
                if len(parts) < 5:
                    results[tool_id] = (False, "Invalid Toolshed tool ID format")
                    continue

                owner = parts[3]
                repo_name = parts[4]

                log.info(f"Toolshed tool detected: {owner}/{repo_name} (Galaxy will auto-install)")
                results[tool_id] = (True, "Toolshed tool - Galaxy will auto-install on first use")

            except Exception as e:
                log.error(f"Failed to process Toolshed tool {tool_id}: {e}")
                results[tool_id] = (False, str(e))

        return results

    def _install_toolshed_via_api(self, tool_ids: List[str]) -> Dict[str, Tuple[bool, str]]:
        """
        Install Toolshed tools via Galaxy Admin API.

        Args:
            tool_ids: List of Toolshed tool IDs

        Returns:
            Dictionary mapping tool_id to (success, message)
        """
        import requests

        results = {}
        headers = {"x-api-key": self.galaxy_api_key}

        for tool_id in tool_ids:
            try:
                # Parse tool ID
                parts = tool_id.split("/")
                if len(parts) < 5:
                    results[tool_id] = (False, "Invalid format")
                    continue

                toolshed_url = f"https://{parts[0]}"
                owner = parts[3]
                repo_name = parts[4]

                # Check if already installing/installed
                check_url = f"{self.galaxy_api_url}/api/tool_shed_repositories"
                response = requests.get(check_url, headers=headers)

                if response.status_code == 200:
                    repos = response.json()
                    if any(r["owner"] == owner and r["name"] == repo_name for r in repos):
                        results[tool_id] = (True, "Already installed or installing")
                        continue

                # Install repository
                install_url = f"{self.galaxy_api_url}/api/tool_shed_repositories"
                payload = {
                    "tool_shed_url": toolshed_url,
                    "name": repo_name,
                    "owner": owner,
                    "changeset_revision": "latest",  # Or parse from tool_id
                    "install_tool_dependencies": True,
                    "install_repository_dependencies": True,
                    "install_resolver_dependencies": True
                }

                log.info(f"Installing via API: {owner}/{repo_name}")
                response = requests.post(install_url, json=payload, headers=headers)

                if response.status_code in [200, 201]:
                    results[tool_id] = (True, f"Installation initiated for {owner}/{repo_name}")
                else:
                    msg = f"API error {response.status_code}: {response.text[:100]}"
                    results[tool_id] = (False, msg)

            except Exception as e:
                log.error(f"Failed to install {tool_id} via API: {e}")
                results[tool_id] = (False, str(e))

        return results

    def auto_install_workflow_tools(self, workflow_dict: Dict) -> Tuple[bool, str, List[str]]:
        """
        Automatically install all missing tools for a workflow.
        Handles both custom BioMate tools and Toolshed tools differently.

        Args:
            workflow_dict: Galaxy workflow dictionary

        Returns:
            Tuple of (all_success, message, failed_tools)
        """
        available, missing_custom, missing_toolshed = self.validate_workflow_tools(workflow_dict)

        if not missing_custom and not missing_toolshed:
            return True, "All tools already available", []

        log.info(f"Auto-installing tools: {len(missing_custom)} custom, {len(missing_toolshed)} Toolshed")

        failed = []

        # Install custom BioMate tools
        if missing_custom:
            log.info(f"Installing {len(missing_custom)} custom BioMate tools")
            custom_results = self.install_missing_tools(missing_custom)
            failed.extend([tool_id for tool_id, (success, _) in custom_results.items() if not success])

        # Install Toolshed tools
        if missing_toolshed:
            log.info(f"Installing {len(missing_toolshed)} Toolshed tools via Galaxy API")
            toolshed_results = self._install_toolshed_tools(missing_toolshed)
            # Note: Toolshed tools marked as "Galaxy will handle" are not failures
            # Only real errors are failures
            failed.extend([
                tool_id for tool_id, (success, msg) in toolshed_results.items()
                if not success and "Galaxy will auto-install" not in msg
            ])

        if failed:
            msg = f"Failed to install {len(failed)} tools: {', '.join(failed[:5])}"
            if len(failed) > 5:
                msg += f" and {len(failed) - 5} more"
            return False, msg, failed

        total_installed = len(missing_custom) + len(missing_toolshed)
        msg = f"Successfully processed {total_installed} tools ({len(missing_custom)} custom, {len(missing_toolshed)} Toolshed)"
        return True, msg, []


def install_tools_for_workflow(workflow_dict: Dict, galaxy_root: str) -> Tuple[bool, str]:
    """
    Convenience function to auto-install tools for a workflow.

    Args:
        workflow_dict: Galaxy workflow dictionary
        galaxy_root: Path to Galaxy installation

    Returns:
        Tuple of (success, message)
    """
    installer = ToolAutoInstaller(galaxy_root)
    success, msg, failed = installer.auto_install_workflow_tools(workflow_dict)

    if not success:
        log.error(f"Tool installation failed: {msg}")
        log.error(f"Failed tools: {failed}")

    return success, msg
