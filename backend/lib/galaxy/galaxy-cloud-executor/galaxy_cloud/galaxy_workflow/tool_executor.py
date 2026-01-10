"""
Galaxy Tool Executor

Parses Galaxy tool XML and generates executable commands for cloud execution.
Handles Cheetah templates, configfiles, and command generation.
"""

import re
import logging
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional, Any
from pathlib import Path
import tempfile
import httpx

logger = logging.getLogger(__name__)


class GalaxyToolExecutor:
    """Executes Galaxy tools by parsing XML and generating commands"""

    def __init__(self, local_tool_dir: Optional[str] = None):
        """
        Initialize tool executor

        Args:
            local_tool_dir: Optional path to local Galaxy tool shed directory
                          If provided, will search for tools locally before trying GitHub
                          Format: /path/to/galaxy/shed_tools
        """
        self.http_client = httpx.AsyncClient(timeout=30.0)
        self.tool_cache: Dict[str, Dict] = {}
        self.local_tool_dir = Path(local_tool_dir) if local_tool_dir else None

        if self.local_tool_dir:
            logger.info(f"Using local tool directory: {self.local_tool_dir}")

    async def get_tool_xml(self, tool_id: str, tool_version: Optional[str] = None) -> Optional[str]:
        """
        Get Galaxy tool XML from local filesystem or GitHub

        Lookup order:
        1. Local tool directory (if configured)
        2. GitHub repositories (tools-iuc, etc.)
        """

        # Parse tool ID to get repository info
        # Format: toolshed.g2.bx.psu.edu/repos/owner/name/tool_name/version
        if tool_id.startswith('toolshed.g2.bx.psu.edu/repos/'):
            parts = tool_id.replace('toolshed.g2.bx.psu.edu/repos/', '').split('/')
            if len(parts) >= 3:
                owner = parts[0]
                repo_name = parts[1]
                tool_name = parts[2]

                # Try local filesystem first
                if self.local_tool_dir:
                    xml_path = await self._find_local_tool_xml(owner, repo_name, tool_name, tool_version)
                    if xml_path:
                        try:
                            with open(xml_path, 'r') as f:
                                logger.info(f"Loaded tool XML from local file: {xml_path}")
                                return f.read()
                        except Exception as e:
                            logger.warning(f"Failed to read local tool XML {xml_path}: {e}")

                # Try to fetch from GitHub
                # For IUC tools: https://raw.githubusercontent.com/galaxyproject/tools-iuc/main/tools/{tool_name}/{tool_name}.xml
                if owner == 'iuc':
                    url = f"https://raw.githubusercontent.com/galaxyproject/tools-iuc/main/tools/{tool_name}/{tool_name}.xml"
                    try:
                        response = await self.http_client.get(url)
                        if response.status_code == 200:
                            logger.info(f"Loaded tool XML from GitHub: {url}")
                            return response.text
                    except Exception as e:
                        logger.debug(f"Failed to fetch tool XML from {url}: {e}")

        return None

    async def _find_local_tool_xml(
        self,
        owner: str,
        repo_name: str,
        tool_name: str,
        tool_version: Optional[str] = None
    ) -> Optional[Path]:
        """
        Find tool XML in local Galaxy shed_tools directory

        Galaxy's shed_tools structure:
        shed_tools/
          toolshed.g2.bx.psu.edu/
            repos/
              owner/
                repo_name/
                  hash_or_version/
                    tool_name.xml
        """
        if not self.local_tool_dir:
            return None

        # Common patterns for Galaxy tool installation
        search_patterns = [
            # Standard Galaxy shed_tools structure
            self.local_tool_dir / "toolshed.g2.bx.psu.edu" / "repos" / owner / repo_name / "*" / f"{tool_name}.xml",
            # Alternative: flat structure
            self.local_tool_dir / owner / repo_name / "*" / f"{tool_name}.xml",
            # Alternative: tool name directory
            self.local_tool_dir / "toolshed.g2.bx.psu.edu" / "repos" / owner / repo_name / "*" / tool_name / f"{tool_name}.xml",
        ]

        for pattern in search_patterns:
            matches = list(self.local_tool_dir.glob(str(pattern.relative_to(self.local_tool_dir))))
            if matches:
                # Return the first match (or most recent if multiple)
                return sorted(matches)[-1]

        return None

    def parse_tool_xml(self, xml_content: str) -> Dict[str, Any]:
        """Parse Galaxy tool XML and extract relevant information"""
        try:
            root = ET.fromstring(xml_content)

            tool_info = {
                'id': root.get('id'),
                'name': root.get('name'),
                'version': root.get('version'),
                'command': None,
                'configfiles': {},
                'inputs': {},
                'outputs': {},
                'requirements': []
            }

            # Parse command
            command_elem = root.find('command')
            if command_elem is not None:
                tool_info['command'] = command_elem.text or ''

            # Parse configfiles
            configfiles = root.find('configfiles')
            if configfiles is not None:
                for configfile in configfiles.findall('configfile'):
                    name = configfile.get('name')
                    content = configfile.text or ''
                    tool_info['configfiles'][name] = content

            # Parse inputs
            inputs_elem = root.find('inputs')
            if inputs_elem is not None:
                for param in inputs_elem.findall('.//param'):
                    param_name = param.get('name')
                    param_type = param.get('type')
                    if param_name:
                        tool_info['inputs'][param_name] = {
                            'type': param_type,
                            'label': param.get('label'),
                            'optional': param.get('optional', 'false') == 'true'
                        }

            # Parse outputs
            outputs_elem = root.find('outputs')
            if outputs_elem is not None:
                for data in outputs_elem.findall('data'):
                    output_name = data.get('name')
                    if output_name:
                        tool_info['outputs'][output_name] = {
                            'format': data.get('format'),
                            'label': data.get('label')
                        }

            # Parse requirements (container/dependencies)
            requirements = root.find('requirements')
            if requirements is not None:
                for req in requirements.findall('requirement'):
                    tool_info['requirements'].append({
                        'type': req.get('type'),
                        'version': req.get('version'),
                        'name': req.text
                    })

            return tool_info

        except Exception as e:
            logger.error(f"Failed to parse tool XML: {e}")
            return {}

    def render_cheetah_template(self, template: str, context: Dict[str, Any]) -> str:
        """
        Simplified Cheetah template rendering for Galaxy tools.
        Handles basic #for loops and variable substitution.
        """
        result = template

        # Handle #for loops: #for $el in $collection: ... #end for
        for_pattern = r'#for\s+\$(\w+)\s+in\s+\$(\w+):\s*(.*?)\s*#end for'

        def replace_for_loop(match):
            var_name = match.group(1)  # e.g., 'el'
            collection_name = match.group(2)  # e.g., 'input_collection'
            loop_body = match.group(3)  # e.g., '${el.element_identifier}'

            collection = context.get(collection_name, [])
            if not isinstance(collection, list):
                collection = [collection]

            logger.debug(f"For loop: var={var_name}, collection={collection_name}, body={loop_body.strip()}")
            logger.debug(f"Collection items: {collection}")

            lines = []
            for item in collection:
                # Create context for this iteration
                loop_context = {var_name: item}
                logger.debug(f"Loop context: {loop_context}")
                # Render the loop body with this item
                line = self._substitute_variables(loop_body, loop_context)
                logger.debug(f"Rendered line: {line}")
                lines.append(line)

            result = '\n'.join(lines)
            logger.debug(f"Final result: {result}")
            return result

        result = re.sub(for_pattern, replace_for_loop, result, flags=re.DOTALL)

        # Handle simple variable substitution: $variable or ${variable}
        result = self._substitute_variables(result, context)

        return result

    def _substitute_variables(self, text: str, context: Dict[str, Any]) -> str:
        """Substitute $variable or ${variable} with values from context"""

        # ${variable.attribute} pattern
        def replace_complex(match):
            var_path = match.group(1)  # e.g., 'el.element_identifier'
            parts = var_path.split('.')

            # Start with the first variable from context
            value = context.get(parts[0])
            if value is None:
                return match.group(0)  # Return original if can't resolve

            # Navigate through remaining parts
            for part in parts[1:]:
                if isinstance(value, dict):
                    value = value.get(part, '')
                elif hasattr(value, part):
                    value = getattr(value, part)
                else:
                    return match.group(0)  # Return original if can't resolve
            return str(value)

        text = re.sub(r'\$\{([^}]+)\}', replace_complex, text)

        # $variable pattern (simple)
        def replace_simple(match):
            var_name = match.group(1)
            value = context.get(var_name, '')
            return str(value)

        text = re.sub(r'\$(\w+)', replace_simple, text)

        return text

    async def build_tool_command(
        self,
        tool_id: str,
        tool_state: Dict[str, Any],
        input_files: Dict[str, str],
        output_files: Dict[str, str]
    ) -> Optional[Dict[str, Any]]:
        """
        Build executable command for a Galaxy tool.

        Args:
            tool_id: Galaxy tool ID
            tool_state: Tool parameters and inputs
            input_files: Mapping of input names to file paths
            output_files: Mapping of output names to file paths

        Returns:
            Dict with:
                - command: Shell command to execute
                - configfiles: Dict of configfile names to their content
                - working_dir: Working directory for execution
        """

        # Get and parse tool XML
        xml_content = await self.get_tool_xml(tool_id)
        if not xml_content:
            logger.warning(f"Could not fetch XML for tool {tool_id}")
            return None

        tool_info = self.parse_tool_xml(xml_content)
        if not tool_info:
            logger.error(f"Failed to parse XML for tool {tool_id}")
            return None

        # Build context for template rendering
        context = {
            **tool_state,
            **input_files,
            **output_files
        }

        # Handle collections - create mock collection objects
        for key, value in input_files.items():
            if isinstance(value, list):
                # This is a collection - create objects with element_identifier
                collection_items = []
                for item in value:
                    if isinstance(item, CollectionElement):
                        # Already a CollectionElement
                        collection_items.append(item)
                    elif isinstance(item, dict):
                        # Dict with element_identifier
                        identifier = item.get('element_identifier', item.get('name', 'unknown'))
                        path = item.get('path', identifier)
                        collection_items.append(CollectionElement(identifier, path))
                    else:
                        # Simple string - use as both identifier and path
                        collection_items.append(CollectionElement(str(item), str(item)))
                context[key] = collection_items

        # Render configfiles
        rendered_configfiles = {}
        for name, template in tool_info['configfiles'].items():
            rendered = self.render_cheetah_template(template, context)
            rendered_configfiles[name] = rendered
            # Add to context so command can reference it
            context[name] = f'${name}'  # Will be replaced with actual file path

        # Render command
        command_template = tool_info['command']
        if command_template:
            command = self.render_cheetah_template(command_template, context)
            # Clean up the command
            command = command.strip()
            command = re.sub(r'\s+', ' ', command)  # Normalize whitespace
        else:
            command = None

        return {
            'command': command,
            'configfiles': rendered_configfiles,
            'working_dir': '/data',
            'tool_info': tool_info
        }


class CollectionElement:
    """Mock object for Galaxy collection elements"""
    def __init__(self, identifier: str, path: Optional[str] = None):
        self.element_identifier = identifier
        self.path = path or identifier
