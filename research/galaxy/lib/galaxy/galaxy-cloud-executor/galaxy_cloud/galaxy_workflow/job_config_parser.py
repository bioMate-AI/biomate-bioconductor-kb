"""
Galaxy Job Configuration Parser

Parses Galaxy job_conf.xml files and provides mapping between tools and job runners.
This integrates Galaxy's native job configuration with cloud execution.
"""

import logging
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional, Any
from pathlib import Path
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass
class JobPlugin:
    """Galaxy job plugin configuration"""
    id: str
    type: str
    load: str
    params: Dict[str, str]


@dataclass
class JobDestination:
    """Galaxy job destination configuration"""
    id: str
    runner: str
    tags: List[str]
    params: Dict[str, str]
    env: Dict[str, str]
    resubmit: List[Dict[str, str]]


@dataclass
class ToolMapping:
    """Tool to destination mapping"""
    tool_id: str
    destination: str
    params: Dict[str, str]


class GalaxyJobConfigParser:
    """
    Parser for Galaxy job_conf.xml files.

    This class extracts job runner configurations and tool mappings
    to integrate with the cloud execution system.
    """

    def __init__(self):
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")

        # Parsed configuration
        self.plugins: Dict[str, JobPlugin] = {}
        self.destinations: Dict[str, JobDestination] = {}
        self.tool_mappings: Dict[str, ToolMapping] = {}
        self.default_destination: Optional[str] = None

    def parse_job_conf_file(self, job_conf_path: Path) -> None:
        """Parse Galaxy job_conf.xml file"""

        if not job_conf_path.exists():
            raise FileNotFoundError(f"Job configuration file not found: {job_conf_path}")

        try:
            tree = ET.parse(job_conf_path)
            root = tree.getroot()

            # Parse plugins
            self._parse_plugins(root)

            # Parse destinations
            self._parse_destinations(root)

            # Parse tool mappings
            self._parse_tool_mappings(root)

            # Parse limits and other configurations
            self._parse_limits(root)

            self.logger.info(f"Parsed job configuration from {job_conf_path}")
            self.logger.info(f"Found {len(self.plugins)} plugins, {len(self.destinations)} destinations, {len(self.tool_mappings)} tool mappings")

        except ET.ParseError as e:
            self.logger.error(f"Failed to parse job configuration XML: {e}")
            raise
        except Exception as e:
            self.logger.error(f"Error parsing job configuration: {e}")
            raise

    def _parse_plugins(self, root: ET.Element) -> None:
        """Parse job plugins section"""
        plugins_elem = root.find('plugins')
        if plugins_elem is None:
            return

        for plugin_elem in plugins_elem.findall('plugin'):
            plugin_id = plugin_elem.get('id')
            plugin_type = plugin_elem.get('type')
            plugin_load = plugin_elem.get('load')

            if not all([plugin_id, plugin_type, plugin_load]):
                self.logger.warning(f"Incomplete plugin definition: {ET.tostring(plugin_elem, encoding='unicode')}")
                continue

            # Parse plugin parameters
            params = {}
            for param_elem in plugin_elem.findall('param'):
                param_id = param_elem.get('id')
                param_value = param_elem.text or param_elem.get('value', '')
                if param_id:
                    params[param_id] = param_value

            plugin = JobPlugin(
                id=plugin_id,
                type=plugin_type,
                load=plugin_load,
                params=params
            )

            self.plugins[plugin_id] = plugin
            self.logger.debug(f"Parsed plugin: {plugin_id} -> {plugin_load}")

    def _parse_destinations(self, root: ET.Element) -> None:
        """Parse job destinations section"""
        destinations_elem = root.find('destinations')
        if destinations_elem is None:
            return

        # Get default destination
        self.default_destination = destinations_elem.get('default')

        for dest_elem in destinations_elem.findall('destination'):
            dest_id = dest_elem.get('id')
            dest_runner = dest_elem.get('runner')

            if not all([dest_id, dest_runner]):
                self.logger.warning(f"Incomplete destination definition: {ET.tostring(dest_elem, encoding='unicode')}")
                continue

            # Parse destination tags
            tags = []
            if dest_elem.get('tags'):
                tags = [tag.strip() for tag in dest_elem.get('tags').split(',')]

            # Parse destination parameters
            params = {}
            env = {}
            resubmit = []

            for param_elem in dest_elem.findall('param'):
                param_id = param_elem.get('id')
                param_value = param_elem.text or param_elem.get('value', '')
                if param_id:
                    params[param_id] = param_value

            for env_elem in dest_elem.findall('env'):
                env_id = env_elem.get('id')
                env_value = env_elem.text or env_elem.get('value', '')
                if env_id:
                    env[env_id] = env_value

            for resubmit_elem in dest_elem.findall('resubmit'):
                resubmit_condition = resubmit_elem.get('condition')
                resubmit_destination = resubmit_elem.get('destination')
                if resubmit_condition and resubmit_destination:
                    resubmit.append({
                        'condition': resubmit_condition,
                        'destination': resubmit_destination
                    })

            destination = JobDestination(
                id=dest_id,
                runner=dest_runner,
                tags=tags,
                params=params,
                env=env,
                resubmit=resubmit
            )

            self.destinations[dest_id] = destination
            self.logger.debug(f"Parsed destination: {dest_id} -> {dest_runner}")

    def _parse_tool_mappings(self, root: ET.Element) -> None:
        """Parse tool mappings section"""
        tools_elem = root.find('tools')
        if tools_elem is None:
            return

        for tool_elem in tools_elem.findall('tool'):
            tool_id = tool_elem.get('id')
            tool_destination = tool_elem.get('destination')

            if not all([tool_id, tool_destination]):
                self.logger.warning(f"Incomplete tool mapping: {ET.tostring(tool_elem, encoding='unicode')}")
                continue

            # Parse tool-specific parameters
            params = {}
            for param_elem in tool_elem.findall('param'):
                param_id = param_elem.get('id')
                param_value = param_elem.text or param_elem.get('value', '')
                if param_id:
                    params[param_id] = param_value

            mapping = ToolMapping(
                tool_id=tool_id,
                destination=tool_destination,
                params=params
            )

            self.tool_mappings[tool_id] = mapping
            self.logger.debug(f"Parsed tool mapping: {tool_id} -> {tool_destination}")

    def _parse_limits(self, root: ET.Element) -> None:
        """Parse limits and other configurations"""
        # This could be extended to parse limits, handlers, etc.
        pass

    def get_tool_destination(self, tool_id: str) -> Optional[str]:
        """Get destination for a specific tool"""
        if tool_id in self.tool_mappings:
            return self.tool_mappings[tool_id].destination
        return self.default_destination

    def get_destination_config(self, destination_id: str) -> Optional[JobDestination]:
        """Get configuration for a destination"""
        return self.destinations.get(destination_id)

    def get_tool_runner(self, tool_id: str) -> Optional[str]:
        """Get the runner for a specific tool"""
        destination_id = self.get_tool_destination(tool_id)
        if destination_id:
            destination = self.get_destination_config(destination_id)
            if destination:
                return destination.runner
        return None

    def is_cloud_runner(self, runner_id: str) -> bool:
        """Check if a runner is a cloud runner"""
        cloud_runners = ['kubernetes', 'aws', 'gcp', 'azure']

        if runner_id in cloud_runners:
            return True

        # Check plugin load path for cloud runners
        if runner_id in self.plugins:
            plugin = self.plugins[runner_id]
            load_path = plugin.load.lower()
            return any(cloud in load_path for cloud in cloud_runners)

        return False

    def get_cloud_tools(self) -> List[str]:
        """Get list of tools configured for cloud execution"""
        cloud_tools = []

        for tool_id, mapping in self.tool_mappings.items():
            destination = self.get_destination_config(mapping.destination)
            if destination and self.is_cloud_runner(destination.runner):
                cloud_tools.append(tool_id)

        return cloud_tools

    def get_runner_destinations(self, runner_id: str) -> List[str]:
        """Get all destinations using a specific runner"""
        return [
            dest_id for dest_id, dest in self.destinations.items()
            if dest.runner == runner_id
        ]

    def convert_to_cloud_config(self) -> Dict[str, Any]:
        """Convert Galaxy job configuration to cloud executor configuration"""
        cloud_config = {
            'destinations': {},
            'tool_mappings': {},
            'runners': {}
        }

        # Convert destinations
        for dest_id, dest in self.destinations.items():
            if self.is_cloud_runner(dest.runner):
                cloud_config['destinations'][dest_id] = {
                    'runner': dest.runner,
                    'params': dest.params,
                    'env': dest.env,
                    'tags': dest.tags
                }

        # Convert tool mappings for cloud tools
        for tool_id, mapping in self.tool_mappings.items():
            destination = self.get_destination_config(mapping.destination)
            if destination and self.is_cloud_runner(destination.runner):
                cloud_config['tool_mappings'][tool_id] = {
                    'destination': mapping.destination,
                    'runner': destination.runner,
                    'params': {**destination.params, **mapping.params},
                    'env': destination.env
                }

        # Convert runners
        for plugin_id, plugin in self.plugins.items():
            if self.is_cloud_runner(plugin_id):
                cloud_config['runners'][plugin_id] = {
                    'type': plugin.type,
                    'load': plugin.load,
                    'params': plugin.params
                }

        return cloud_config

    def generate_sample_config(self) -> str:
        """Generate a sample job_conf.xml with cloud runners"""
        return '''<?xml version="1.0"?>
<job_conf>
    <plugins>
        <plugin id="local" type="runner" load="galaxy.jobs.runners.local:LocalJobRunner"/>
        <plugin id="kubernetes" type="runner" load="galaxy.jobs.runners.kubernetes:KubernetesJobRunner"/>
        <plugin id="aws" type="runner" load="galaxy.jobs.runners.aws:AWSBatchJobRunner"/>
        <plugin id="gcp" type="runner" load="galaxy.jobs.runners.gcp:GCPBatchJobRunner"/>
        <plugin id="galaxy_cloud" type="runner" load="galaxy_cloud.galaxy_workflow.galaxy_job_runner:GalaxyCloudJobRunner"/>
    </plugins>

    <destinations default="local">
        <destination id="local" runner="local"/>

        <!-- Kubernetes destinations -->
        <destination id="k8s_small" runner="kubernetes">
            <param id="k8s_namespace">galaxy-jobs</param>
            <param id="k8s_cpu_request">1</param>
            <param id="k8s_memory_request">2Gi</param>
        </destination>

        <destination id="k8s_large" runner="kubernetes">
            <param id="k8s_namespace">galaxy-jobs</param>
            <param id="k8s_cpu_request">8</param>
            <param id="k8s_memory_request">32Gi</param>
        </destination>

        <!-- Cloud executor destinations -->
        <destination id="cloud_aws" runner="galaxy_cloud">
            <param id="cloud_provider">aws</param>
            <param id="compute_environment">galaxy-batch-compute</param>
            <param id="job_queue">galaxy-job-queue</param>
        </destination>

        <destination id="cloud_gcp" runner="galaxy_cloud">
            <param id="cloud_provider">gcp</param>
            <param id="project_id">my-galaxy-project</param>
            <param id="region">us-central1</param>
        </destination>
    </destinations>

    <tools>
        <!-- Small tools on local -->
        <tool id="upload1" destination="local"/>

        <!-- Medium tools on Kubernetes -->
        <tool id="fastqc" destination="k8s_small"/>
        <tool id="trimmomatic" destination="k8s_small"/>

        <!-- Large tools on cloud -->
        <tool id="bwa" destination="cloud_aws"/>
        <tool id="spades" destination="cloud_gcp"/>
        <tool id="blast" destination="k8s_large"/>
    </tools>
</job_conf>'''

    def export_config(self, output_path: Path, format: str = 'xml') -> None:
        """Export configuration to file"""
        if format == 'xml':
            self._export_xml(output_path)
        elif format == 'yaml':
            self._export_yaml(output_path)
        else:
            raise ValueError(f"Unsupported export format: {format}")

    def _export_xml(self, output_path: Path) -> None:
        """Export configuration as XML"""
        # This would reconstruct the XML from parsed data
        # Implementation would build ET tree and write to file
        pass

    def _export_yaml(self, output_path: Path) -> None:
        """Export configuration as YAML for cloud executor"""
        import yaml

        config = self.convert_to_cloud_config()
        with open(output_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=True)