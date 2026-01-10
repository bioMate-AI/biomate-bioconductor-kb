"""
Galaxy Tool Registry

Manages mapping between Galaxy tools and their container implementations.
Integrates with BioContainers and other container registries.
"""

import json
import logging
import re
from typing import Dict, List, Optional, Set, Any
from pathlib import Path
from dataclasses import dataclass
import httpx
import yaml

from .models import ToolContainerInfo


logger = logging.getLogger(__name__)


@dataclass
class BioContainerInfo:
    """Information from BioContainers registry"""
    tool_id: str
    name: str
    version: str
    image: str
    registry: str
    description: str = ""
    homepage: str = ""
    license: str = ""


class GalaxyToolRegistry:
    """
    Registry for Galaxy tool container mappings.

    This class handles:
    - Loading tool-to-container mappings
    - Querying BioContainers registry
    - Resolving tool versions and dependencies
    - Providing default containers for unknown tools
    """

    def __init__(self, config: Dict[str, Any]):
        self.config = config
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Tool container mappings
        self.tool_mappings: Dict[str, ToolContainerInfo] = {}
        self.biocontainers_cache: Dict[str, BioContainerInfo] = {}

        # Load static mappings
        self._load_static_mappings()

        # Initialize HTTP client for API requests
        self.http_client = httpx.AsyncClient(timeout=30.0)

    def _load_static_mappings(self):
        """Load static tool-to-container mappings"""
        mappings_file = self.config.get('static_mappings_file')
        if mappings_file and Path(mappings_file).exists():
            try:
                with open(mappings_file, 'r') as f:
                    if mappings_file.endswith('.yaml') or mappings_file.endswith('.yml'):
                        data = yaml.safe_load(f)
                    else:
                        data = json.load(f)

                for tool_id, container_info in data.get('tools', {}).items():
                    self.tool_mappings[tool_id] = ToolContainerInfo(
                        tool_id=tool_id,
                        image=container_info['image'],
                        tag=container_info.get('tag', 'latest'),
                        registry=container_info.get('registry', 'quay.io/biocontainers'),
                        command=container_info.get('command'),
                        env=container_info.get('env', {}),
                        working_dir=container_info.get('working_dir', '/galaxy-central'),
                        resources=container_info.get('resources', {})
                    )

                self.logger.info(f"Loaded {len(self.tool_mappings)} static tool mappings")

            except Exception as e:
                self.logger.error(f"Failed to load static mappings from {mappings_file}: {e}")

    async def get_tool_container(self, tool_id: str, tool_version: Optional[str] = None) -> Optional[ToolContainerInfo]:
        """Get container information for a Galaxy tool"""

        # Check static mappings first
        if tool_id in self.tool_mappings:
            return self.tool_mappings[tool_id]

        # Try to resolve from BioContainers
        container_info = await self._resolve_from_biocontainers(tool_id, tool_version)
        if container_info:
            # Cache the result
            self.tool_mappings[tool_id] = container_info
            return container_info

        # Try pattern-based resolution
        container_info = self._resolve_by_pattern(tool_id, tool_version)
        if container_info:
            self.tool_mappings[tool_id] = container_info
            return container_info

        self.logger.warning(f"No container found for tool: {tool_id}")
        return None

    async def _resolve_from_biocontainers(self, tool_id: str, tool_version: Optional[str] = None) -> Optional[ToolContainerInfo]:
        """Resolve tool container from BioContainers registry"""
        try:
            # Clean tool ID for BioContainers lookup
            clean_tool_id = self._clean_tool_id_for_biocontainers(tool_id)

            # Check cache first
            cache_key = f"{clean_tool_id}:{tool_version or 'latest'}"
            if cache_key in self.biocontainers_cache:
                bio_info = self.biocontainers_cache[cache_key]
                return self._biocontainer_to_tool_container(bio_info)

            # Query BioContainers API
            biocontainer_info = await self._query_biocontainers_api(clean_tool_id, tool_version)
            if biocontainer_info:
                self.biocontainers_cache[cache_key] = biocontainer_info
                return self._biocontainer_to_tool_container(biocontainer_info)

        except Exception as e:
            self.logger.debug(f"Failed to resolve {tool_id} from BioContainers: {e}")

        return None

    def _clean_tool_id_for_biocontainers(self, tool_id: str) -> str:
        """Clean Galaxy tool ID for BioContainers lookup"""
        # Remove Galaxy-specific prefixes
        cleaned = tool_id.replace('toolshed.g2.bx.psu.edu/repos/', '')
        cleaned = re.sub(r'^[^/]+/[^/]+/', '', cleaned)  # Remove owner/name parts

        # Extract tool name
        if '/' in cleaned:
            parts = cleaned.split('/')
            # Usually the tool name is the last part before version
            cleaned = parts[-2] if len(parts) > 2 else parts[0]

        # Convert to lowercase but keep hyphens and underscores
        # BioContainers package names use these characters
        cleaned = cleaned.lower()

        return cleaned

    async def _query_biocontainers_api(self, tool_name: str, version: Optional[str] = None) -> Optional[BioContainerInfo]:
        """Query BioContainers registry API"""
        try:
            # BioContainers API endpoint
            base_url = self.config.get('biocontainers_api_url', 'https://api.biocontainers.pro/ga4gh/trs/v2/tools')

            # Search for the tool
            search_url = f"{base_url}?name={tool_name}"
            response = await self.http_client.get(search_url)
            response.raise_for_status()

            tools = response.json()
            if not tools:
                return None

            # Find the best match
            for tool in tools:
                if tool['name'].lower() == tool_name.lower():
                    # Get tool versions
                    tool_id = tool['id']
                    versions_url = f"{base_url}/{tool_id}/versions"
                    versions_response = await self.http_client.get(versions_url)
                    versions_response.raise_for_status()

                    versions = versions_response.json()
                    if not versions:
                        continue

                    # Find appropriate version
                    selected_version = self._select_version(versions, version)
                    if selected_version:
                        # Need to fetch FULL version details to get images array
                        version_id = selected_version.get('id')
                        version_detail_url = f"{base_url}/{tool_id}/versions/{version_id}"

                        self.logger.debug(f"Fetching version details from: {version_detail_url}")
                        detail_response = await self.http_client.get(version_detail_url)
                        detail_response.raise_for_status()
                        version_detail = detail_response.json()

                        # Get the FULL Docker image tag from the version's images array
                        # BioContainers format: <version>--<build> (e.g., 1.40.2--r43hf17093f_0)
                        docker_tag = None
                        if 'images' in version_detail:
                            for img in version_detail['images']:
                                if img.get('image_type') == 'Docker':
                                    # Extract full image with tag
                                    full_image = img.get('image_name', '')
                                    # Format: quay.io/biocontainers/tool:tag
                                    if ':' in full_image:
                                        # Split to get just the tag part
                                        docker_tag = full_image.split(':')[-1]
                                        self.logger.debug(f"Found Docker tag: {docker_tag}")
                                    break

                        # Fallback to meta_version if no Docker image found
                        if not docker_tag:
                            docker_tag = version_detail.get('meta_version', selected_version.get('name', 'latest'))
                            self.logger.warning(f"No Docker image found for {tool_name} {version}, using fallback tag: {docker_tag}")

                        # Build image path (without tag - tag stored separately)
                        actual_image_name = tool['name']  # Use the API-returned name
                        image_path = f"quay.io/biocontainers/{actual_image_name}"
                        full_image_uri = f"{image_path}:{docker_tag}"

                        self.logger.info(f"Resolved BioContainer image for {tool_name}: {full_image_uri}")

                        return BioContainerInfo(
                            tool_id=tool_id,
                            name=tool['name'],
                            version=docker_tag,  # Store FULL tag with build info
                            image=image_path,  # Store path without tag
                            registry="quay.io/biocontainers",
                            description=tool.get('description', ''),
                            homepage=tool.get('url', ''),
                            license=tool.get('license', '')
                        )

        except Exception as e:
            self.logger.debug(f"BioContainers API query failed for {tool_name}: {e}")

        return None

    def _select_version(self, versions: List[Dict], requested_version: Optional[str] = None) -> Optional[Dict]:
        """
        Select the best version from available versions.

        BioContainers API returns version entries with 'id' like 'tool-1.40.2'
        but we need to match against the version part and get full version metadata.
        """
        if not versions:
            return None

        if requested_version:
            # Clean requested version (remove any +galaxy suffixes for matching)
            clean_requested = requested_version.split('+')[0] if '+' in requested_version else requested_version

            # Look for exact match in version ID
            for version in versions:
                version_id = version.get('id', '')
                # Extract version number from ID (format: tool-1.40.2)
                if '-' in version_id:
                    version_num = version_id.split('-')[-1]
                    if version_num == clean_requested:
                        self.logger.debug(f"Found exact version match: {version_id} for requested {requested_version}")
                        return version

            # Look for partial match (e.g., 1.40 matches 1.40.2)
            for version in versions:
                version_id = version.get('id', '')
                if clean_requested in version_id:
                    self.logger.debug(f"Found partial version match: {version_id} for requested {requested_version}")
                    return version

        # Default to first available (usually latest)
        # BioContainers usually orders versions with latest first
        self.logger.debug(f"Using default version: {versions[0].get('id', 'unknown')}")
        return versions[0]

    def _normalize_docker_tag(self, tag: str) -> str:
        """
        Normalize a tag for Docker compatibility.

        Docker tags only support: [a-zA-Z0-9_.-]
        BioContainers uses '--' instead of '+' for version metadata.

        Examples:
            '9.3+galaxy1' -> '9.3--galaxy1'
            '2.11.40.8+galaxy0' -> '2.11.40.8--galaxy0'
        """
        if not tag:
            return tag

        # Replace '+' with '--' for BioContainers convention
        # This maintains compatibility with Conda/Galaxy version strings
        normalized = tag.replace('+', '--')

        return normalized

    def _biocontainer_to_tool_container(self, bio_info: BioContainerInfo) -> ToolContainerInfo:
        """Convert BioContainerInfo to ToolContainerInfo"""
        # Normalize the tag for Docker compatibility
        normalized_tag = self._normalize_docker_tag(bio_info.version)

        return ToolContainerInfo(
            tool_id=bio_info.tool_id,
            image=bio_info.image,
            tag=normalized_tag,
            registry=bio_info.registry,
            command=None,  # Will be determined from Galaxy tool XML
            env={},
            working_dir="/galaxy-central",
            resources={}
        )

    def _resolve_by_pattern(self, tool_id: str, tool_version: Optional[str] = None) -> Optional[ToolContainerInfo]:
        """Resolve tool container using pattern matching"""

        # Common patterns for tool ID to container mapping
        # Note: Patterns should only extract tool name, not include tag
        patterns = [
            # ToolShed tools
            (r'toolshed\.g2\.bx\.psu\.edu/repos/[^/]+/([^/]+)/.*', r'quay.io/biocontainers/\1'),

            # Built-in tools
            (r'__([A-Z_]+)__', r'quay.io/biocontainers/\1'),

            # Simple tool names
            (r'^([a-zA-Z0-9_-]+)$', r'quay.io/biocontainers/\1'),
        ]

        for pattern, template in patterns:
            match = re.match(pattern, tool_id)
            if match:
                tool_name = match.group(1).lower()
                # Build image path WITHOUT tag - tag is stored separately
                image = template.replace(r'\1', tool_name)

                # Normalize the tag for Docker compatibility
                normalized_version = self._normalize_docker_tag(tool_version) if tool_version else 'latest'

                return ToolContainerInfo(
                    tool_id=tool_id,
                    image=image,  # Image path without tag
                    tag=normalized_version,  # Normalized tag
                    registry='quay.io/biocontainers',
                    command=None,
                    env={},
                    working_dir="/galaxy-central",
                    resources={}
                )

        return None

    def get_tool_resources(self, tool_id: str) -> Optional[Dict[str, Any]]:
        """Get resource requirements for a tool"""
        container_info = self.tool_mappings.get(tool_id)
        if container_info and container_info.resources:
            return container_info.resources

        # Default resource requirements based on tool patterns
        return self._get_default_resources_for_tool(tool_id)

    def _get_default_resources_for_tool(self, tool_id: str) -> Dict[str, Any]:
        """Get default resource requirements based on tool type"""

        # High-memory tools
        high_memory_tools = [
            'spades', 'megahit', 'trinity', 'velvet', 'soap',
            'bowtie2', 'bwa', 'hisat2', 'star', 'minimap2'
        ]

        # GPU tools
        gpu_tools = [
            'alphafold', 'mmseqs2', 'deepvariant'
        ]

        # Long-running tools
        long_running_tools = [
            'blast', 'diamond', 'hmmer', 'interproscan'
        ]

        tool_name = tool_id.lower()

        if any(pattern in tool_name for pattern in high_memory_tools):
            return {
                'cpus': 8,
                'memory_mb': 32768,  # 32GB
                'disk_gb': 100,
                'timeout': 14400  # 4 hours
            }
        elif any(pattern in tool_name for pattern in gpu_tools):
            return {
                'cpus': 4,
                'memory_mb': 16384,  # 16GB
                'disk_gb': 50,
                'gpu': 1,
                'gpu_type': 'nvidia.com/gpu',
                'timeout': 7200  # 2 hours
            }
        elif any(pattern in tool_name for pattern in long_running_tools):
            return {
                'cpus': 4,
                'memory_mb': 8192,  # 8GB
                'disk_gb': 50,
                'timeout': 10800  # 3 hours
            }
        else:
            return {
                'cpus': 2,
                'memory_mb': 4096,  # 4GB
                'disk_gb': 20,
                'timeout': 3600  # 1 hour
            }

    def get_tool_config(self, tool_id: str) -> Optional[Dict[str, Any]]:
        """Get full tool configuration"""
        container_info = self.tool_mappings.get(tool_id)
        if container_info:
            return {
                'image': container_info.image,
                'tag': container_info.tag,
                'registry': container_info.registry,
                'command': container_info.command,
                'env': container_info.env,
                'working_dir': container_info.working_dir,
                'resources': container_info.resources,
                'timeout': container_info.resources.get('timeout', 3600)
            }
        return None

    def get_default_container(self) -> Dict[str, Any]:
        """Get default container for unknown tools"""
        return {
            'image': self.config.get('default_image', 'quay.io/biocontainers/galaxy-minimal:latest'),
            'registry': 'quay.io/biocontainers',
            'command': ['/bin/bash', '-c'],
            'env': {
                'GALAXY_SLOTS': '1',
                'GALAXY_MEMORY_MB': '4096'
            },
            'working_dir': '/galaxy-central',
            'resources': {
                'cpus': 1,
                'memory_mb': 4096,
                'disk_gb': 20,
                'timeout': 3600
            }
        }

    async def refresh_biocontainers_cache(self):
        """Refresh the BioContainers cache"""
        self.biocontainers_cache.clear()
        self.logger.info("BioContainers cache cleared")

    async def close(self):
        """Close HTTP client"""
        await self.http_client.aclose()

    def add_tool_mapping(self, tool_id: str, container_info: ToolContainerInfo):
        """Add a new tool mapping"""
        self.tool_mappings[tool_id] = container_info
        self.logger.info(f"Added mapping for tool {tool_id}")

    def remove_tool_mapping(self, tool_id: str):
        """Remove a tool mapping"""
        if tool_id in self.tool_mappings:
            del self.tool_mappings[tool_id]
            self.logger.info(f"Removed mapping for tool {tool_id}")

    def list_mapped_tools(self) -> List[str]:
        """List all tools with container mappings"""
        return list(self.tool_mappings.keys())

    def export_mappings(self, output_file: Path, format: str = 'yaml'):
        """Export tool mappings to file"""
        data = {
            'tools': {}
        }

        for tool_id, container_info in self.tool_mappings.items():
            data['tools'][tool_id] = {
                'image': container_info.image,
                'tag': container_info.tag,
                'registry': container_info.registry,
                'command': container_info.command,
                'env': container_info.env,
                'working_dir': container_info.working_dir,
                'resources': container_info.resources
            }

        with open(output_file, 'w') as f:
            if format.lower() == 'yaml':
                yaml.dump(data, f, default_flow_style=False, sort_keys=True)
            else:
                json.dump(data, f, indent=2, sort_keys=True)

        self.logger.info(f"Exported {len(self.tool_mappings)} tool mappings to {output_file}")