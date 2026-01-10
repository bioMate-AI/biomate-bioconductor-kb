"""
Enhanced Tool Registry with Three-Layer Container Discovery

This module implements intelligent container discovery for Galaxy tools:
1. Layer 1: Extract from tool's own container declaration (tool.xml)
2. Layer 2: Query BioContainers registry
3. Layer 3: Auto-build from conda dependencies
"""

import logging
import re
from typing import Optional, Dict, Any
from pathlib import Path

from .models import ToolContainerInfo
from .tool_registry import GalaxyToolRegistry


class EnhancedToolRegistry(GalaxyToolRegistry):
    """
    Enhanced tool registry with intelligent container discovery.

    Implements a three-layer fallback strategy:
    1. Tool XML container declaration
    2. BioContainers registry lookup
    3. Auto-build from conda requirements
    """

    def __init__(self, config: Dict[str, Any], galaxy_app=None):
        super().__init__(config)
        self.galaxy_app = galaxy_app
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Cache for resolved containers
        self.resolved_cache: Dict[str, ToolContainerInfo] = {}

    async def get_tool_container(self, tool_id: str, tool_version: Optional[str] = None) -> Optional[ToolContainerInfo]:
        """
        Get container information using three-layer strategy.

        Args:
            tool_id: Galaxy tool ID (e.g., 'toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.74+galaxy0')
            tool_version: Optional tool version

        Returns:
            ToolContainerInfo object or None if no container found
        """

        # Check cache first
        cache_key = f"{tool_id}:{tool_version or 'latest'}"
        if cache_key in self.resolved_cache:
            self.logger.debug(f"Container found in cache for {tool_id}")
            return self.resolved_cache[cache_key]

        # Layer 1: Check tool's own container declaration
        container_info = await self._get_from_tool_xml(tool_id)
        if container_info:
            self.logger.info(f"✓ Layer 1: Found container in tool XML for {tool_id}: {container_info.image}:{container_info.tag}")
            self.resolved_cache[cache_key] = container_info
            return container_info

        # Layer 2: Query BioContainers (using parent class method)
        container_info = await self._get_from_biocontainers(tool_id, tool_version)
        if container_info:
            self.logger.info(f"✓ Layer 2: Found container in BioContainers for {tool_id}: {container_info.image}:{container_info.tag}")
            self.resolved_cache[cache_key] = container_info
            return container_info

        # Layer 3: Auto-build from conda
        container_info = await self._auto_build_from_conda(tool_id, tool_version)
        if container_info:
            self.logger.info(f"✓ Layer 3: Auto-built container for {tool_id}: {container_info.image}:{container_info.tag}")
            self.resolved_cache[cache_key] = container_info
            return container_info

        # Fallback: Use parent class logic (static mappings, etc.)
        container_info = await super().get_tool_container(tool_id, tool_version)
        if container_info:
            self.logger.info(f"✓ Fallback: Using parent class container for {tool_id}")
            return container_info

        self.logger.warning(f"✗ No container found for tool: {tool_id}")
        return None

    async def _get_from_tool_xml(self, tool_id: str) -> Optional[ToolContainerInfo]:
        """
        Layer 1: Extract container info from tool's XML declaration.

        Many Galaxy tools already declare their containers in tool.xml:
        <container type="docker">quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0</container>
        """

        if not self.galaxy_app:
            self.logger.debug("No Galaxy app available, skipping tool XML lookup")
            return None

        try:
            # Get tool from Galaxy toolbox
            tool = self.galaxy_app.toolbox.get_tool(tool_id)
            if not tool:
                self.logger.debug(f"Tool {tool_id} not found in Galaxy toolbox")
                return None

            # Check if tool has container requirements
            if hasattr(tool, 'containers'):
                containers = tool.containers
                if containers:
                    # Usually the first container is the primary one
                    container = containers[0] if isinstance(containers, list) else containers

                    # Parse container identifier
                    # Format: quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
                    container_id = str(container.identifier) if hasattr(container, 'identifier') else str(container)

                    return self._parse_container_identifier(tool_id, container_id)

            # Alternative: check tool's requirements for container hints
            if hasattr(tool, 'requirements') and tool.requirements:
                for req in tool.requirements:
                    if hasattr(req, 'container') and req.container:
                        container_id = req.container
                        return self._parse_container_identifier(tool_id, container_id)

        except Exception as e:
            self.logger.debug(f"Error extracting container from tool XML for {tool_id}: {e}")

        return None

    def _parse_container_identifier(self, tool_id: str, container_id: str) -> ToolContainerInfo:
        """
        Parse container identifier string into ToolContainerInfo.

        Handles formats like:
        - quay.io/biocontainers/fastqc:0.12.1--hdfd78af_0
        - biocontainers/fastqc:0.12.1
        - fastqc:0.12.1
        """

        # Split registry, image, and tag
        if '/' in container_id:
            parts = container_id.split('/')
            if len(parts) >= 3:  # quay.io/biocontainers/image:tag
                registry = f"{parts[0]}/{parts[1]}"
                image_tag = parts[2]
            elif len(parts) == 2:  # biocontainers/image:tag
                registry = "quay.io/biocontainers"
                image_tag = parts[1]
            else:
                registry = "quay.io/biocontainers"
                image_tag = parts[0]
        else:
            registry = "quay.io/biocontainers"
            image_tag = container_id

        # Split image and tag
        if ':' in image_tag:
            image, tag = image_tag.rsplit(':', 1)
        else:
            image = image_tag
            tag = 'latest'

        # Get full image path (without tag)
        if '/' not in image:
            # If image doesn't have registry prefix, add it
            full_image = f"{registry}/{image}"
        else:
            full_image = image

        return ToolContainerInfo(
            tool_id=tool_id,
            image=full_image,
            tag=tag,
            registry=registry,
            command=None,
            env={},
            working_dir='/data',
            resources={}
        )

    async def _get_from_biocontainers(self, tool_id: str, tool_version: Optional[str] = None) -> Optional[ToolContainerInfo]:
        """
        Layer 2: Query BioContainers registry.

        This uses the parent class's BioContainers lookup logic.
        """
        try:
            # Use parent class's resolution logic
            container_info = await self._resolve_from_biocontainers(tool_id, tool_version)
            return container_info
        except Exception as e:
            self.logger.debug(f"BioContainers lookup failed for {tool_id}: {e}")
            return None

    async def _auto_build_from_conda(self, tool_id: str, tool_version: Optional[str] = None) -> Optional[ToolContainerInfo]:
        """
        Layer 3: Auto-build container from conda requirements.

        Steps:
        1. Extract tool's conda dependencies from tool XML
        2. Generate Dockerfile with conda environment
        3. Trigger AWS CodeBuild to build image
        4. Push to AWS ECR (Elastic Container Registry)
        5. Return ECR image URL

        For now, this is a placeholder that returns None.
        Future implementation will integrate with AWS CodeBuild.
        """

        if not self.galaxy_app:
            return None

        try:
            # Get tool from Galaxy toolbox
            tool = self.galaxy_app.toolbox.get_tool(tool_id)
            if not tool or not hasattr(tool, 'requirements'):
                return None

            # Extract conda packages
            conda_packages = []
            for req in tool.requirements:
                if hasattr(req, 'type') and req.type == 'package':
                    package_name = req.name
                    package_version = req.version if hasattr(req, 'version') else None

                    if package_version:
                        conda_packages.append(f"{package_name}=={package_version}")
                    else:
                        conda_packages.append(package_name)

            if not conda_packages:
                self.logger.debug(f"No conda packages found for {tool_id}")
                return None

            self.logger.info(f"Tool {tool_id} has conda dependencies: {conda_packages}")

            # TODO: Implement auto-build logic
            # For now, log the packages and return None
            # Future: Call AWS CodeBuild to build and push image

            self.logger.warning(f"Auto-build not yet implemented for {tool_id} (requires: {', '.join(conda_packages)})")

            return None

        except Exception as e:
            self.logger.error(f"Error in auto-build for {tool_id}: {e}")
            return None

    def get_build_status(self, tool_id: str) -> Dict[str, Any]:
        """
        Get status of auto-build for a tool.

        Returns:
            Dictionary with build status information
        """
        # TODO: Implement build status tracking
        return {
            'tool_id': tool_id,
            'status': 'not_started',
            'message': 'Auto-build not yet implemented'
        }
