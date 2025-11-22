"""
Multi-Source Dependency Converter: Generate installation directives for multiple methods.

Supports:
- Conda (bioconda/conda-forge packages)
- Containers (Docker/Singularity)
- Modules (Environment modules/Lmod)
- ToolShed (Galaxy ToolShed packages)
"""

import re
import logging
from pathlib import Path
from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field
import xml.etree.ElementTree as ET

log = logging.getLogger(__name__)


@dataclass
class DependencySpec:
    """Dependency specification from Galaxy tool."""
    name: str
    version: Optional[str] = None
    type: str = "package"  # package, set_environment, etc.


@dataclass
class InstallationMethods:
    """All available installation methods for a tool."""
    conda: Optional[str] = None
    conda_channels: List[str] = field(default_factory=lambda: ['conda-forge', 'bioconda'])
    docker: Optional[str] = None
    singularity: Optional[str] = None
    module: Optional[str] = None
    toolshed: Optional[str] = None
    source: str = "unknown"
    confidence: Dict[str, float] = field(default_factory=dict)


class MultiSourceDependencyConverter:
    """Convert Galaxy requirements to multiple installation methods."""

    # Common conda channel mapping
    CONDA_CHANNELS = {
        'default': 'bioconda',
        'r_packages': 'conda-forge',
        'python_packages': 'conda-forge',
    }

    # Known tool name variations
    TOOL_NAME_MAPPING = {
        'trim-galore': 'trim-galore',
        'trimgalore': 'trim-galore',
        'trim_galore': 'trim-galore',
        'salmon': 'salmon',
        'kallisto': 'kallisto',
        'star': 'star',
        'hisat2': 'hisat2',
        'bowtie2': 'bowtie2',
        'fastqc': 'fastqc',
        'multiqc': 'multiqc',
    }

    def __init__(self, nfcore_base_dir: Optional[Path] = None):
        """Initialize converter."""
        self.nfcore_base_dir = nfcore_base_dir

    def convert(self, galaxy_requirements: List[Dict[str, Any]],
                tool_name: Optional[str] = None,
                tool_id: Optional[str] = None) -> InstallationMethods:
        """Convert Galaxy requirements to all installation methods."""

        if not galaxy_requirements:
            log.warning(f"No requirements for tool: {tool_name or tool_id}")
            return InstallationMethods(source='none')

        # Parse Galaxy requirements
        deps = [DependencySpec(**req) for req in galaxy_requirements
                if req.get('type') == 'package']

        if not deps:
            return InstallationMethods(source='none')

        # Get primary dependency (usually the tool itself)
        primary_dep = self._identify_primary_dependency(deps, tool_name)

        # Generate all installation methods
        methods = InstallationMethods()

        # 1. Conda
        methods.conda, methods.conda_channels = self._to_conda(primary_dep, deps)
        methods.confidence['conda'] = 0.95  # High confidence - most biotools in bioconda

        # 2. Containers (from conda or direct lookup)
        methods.docker, methods.singularity = self._to_containers(primary_dep)
        methods.confidence['container'] = 0.8

        # 3. Module (if known)
        methods.module = self._to_module(primary_dep)
        methods.confidence['module'] = 0.5 if methods.module else 0.0

        # 4. ToolShed (from tool_id)
        methods.toolshed = self._to_toolshed(tool_id)
        methods.confidence['toolshed'] = 1.0 if tool_id else 0.0

        # 5. Check nf-core for better specs
        self._enrich_from_nfcore(methods, tool_name or primary_dep.name)

        methods.source = 'multi_source_converter'
        return methods

    def _identify_primary_dependency(self, deps: List[DependencySpec],
                                     tool_name: Optional[str]) -> DependencySpec:
        """Identify the primary dependency (the tool itself)."""
        if tool_name:
            # Try to match tool_name to a dependency
            tool_name_lower = tool_name.lower().replace('_', '-')
            for dep in deps:
                dep_name_lower = dep.name.lower().replace('_', '-')
                if dep_name_lower == tool_name_lower:
                    return dep

        # Return first non-common dependency
        common_deps = {'samtools', 'bcftools', 'bedtools', 'python', 'r-base', 'perl'}
        for dep in deps:
            if dep.name.lower() not in common_deps:
                return dep

        # Fallback to first dependency
        return deps[0]

    def _to_conda(self, primary: DependencySpec,
                  all_deps: List[DependencySpec]) -> tuple[str, List[str]]:
        """Generate Conda specification."""
        # Normalize tool name
        tool_name = self._normalize_tool_name(primary.name)

        # Determine channel
        channel = self._infer_conda_channel(tool_name)

        # Build conda spec
        if primary.version:
            conda_spec = f"{channel}::{tool_name}={primary.version}"
        else:
            conda_spec = f"{channel}::{tool_name}"

        channels = ['conda-forge', channel] if channel != 'conda-forge' else ['conda-forge']

        return conda_spec, channels

    def _infer_conda_channel(self, tool_name: str) -> str:
        """Infer appropriate conda channel for a tool."""
        # R packages
        if tool_name.startswith('r-') or tool_name.startswith('bioconductor-'):
            return 'bioconda'  # R packages are also in bioconda

        # Python packages (but most biotools are in bioconda anyway)
        if tool_name.startswith('python-') or tool_name.startswith('py-'):
            return 'conda-forge'

        # Default: bioconda (99% of biotools)
        return 'bioconda'

    def _to_containers(self, primary: DependencySpec) -> tuple[Optional[str], Optional[str]]:
        """Generate container specifications from conda package."""
        tool_name = self._normalize_tool_name(primary.name)

        # BioContainers naming convention
        if primary.version:
            # Full version with build hash (we don't know hash, use pattern)
            docker = f"biocontainers/{tool_name}:{primary.version}"
            singularity = f"https://depot.galaxyproject.org/singularity/{tool_name}:{primary.version}"
        else:
            # Latest
            docker = f"biocontainers/{tool_name}:latest"
            singularity = f"https://depot.galaxyproject.org/singularity/{tool_name}:latest"

        return docker, singularity

    def _to_module(self, primary: DependencySpec) -> Optional[str]:
        """Generate environment module specification."""
        # Module naming: tool/version
        if primary.version:
            return f"{primary.name}/{primary.version}"
        else:
            return f"{primary.name}"

    def _to_toolshed(self, tool_id: Optional[str]) -> Optional[str]:
        """Extract ToolShed reference from tool_id."""
        if not tool_id:
            return None

        # Format: toolshed.g2.bx.psu.edu/repos/owner/name/tool_name
        if 'toolshed' in tool_id:
            return tool_id

        return None

    def _normalize_tool_name(self, name: str) -> str:
        """Normalize tool name for conda/containers."""
        # Use mapping if available
        name_lower = name.lower().replace('_', '-')
        return self.TOOL_NAME_MAPPING.get(name_lower, name_lower)

    def _enrich_from_nfcore(self, methods: InstallationMethods, tool_name: str):
        """Enrich with actual container specs from nf-core modules."""
        if not self.nfcore_base_dir:
            return

        # Search for nf-core module
        tool_name_norm = self._normalize_tool_name(tool_name)
        module_paths = list(self.nfcore_base_dir.glob(f"**/modules/nf-core/{tool_name_norm}/main.nf"))
        module_paths.extend(list(self.nfcore_base_dir.glob(f"**/modules/nf-core/*/{tool_name_norm}/main.nf")))

        for module_path in module_paths:
            try:
                with open(module_path) as f:
                    content = f.read()

                # Extract actual container specs
                docker_match = re.search(r"'(biocontainers/[^']+)'", content)
                if docker_match:
                    methods.docker = docker_match.group(1)
                    methods.confidence['container'] = 1.0

                singularity_match = re.search(r"'(https://depot\.galaxyproject\.org/singularity/[^']+)'", content)
                if singularity_match:
                    methods.singularity = singularity_match.group(1)

                # Check environment.yml for conda
                env_yml = module_path.parent / "environment.yml"
                if env_yml.exists():
                    with open(env_yml) as f:
                        env_content = f.read()
                        conda_match = re.search(r'- (bioconda::\S+|conda-forge::\S+)', env_content)
                        if conda_match:
                            methods.conda = conda_match.group(1)
                            methods.confidence['conda'] = 1.0

                        # Extract channels
                        channels = re.findall(r'^  - (\w+(?:-\w+)*)$', env_content, re.MULTILINE)
                        if channels:
                            methods.conda_channels = channels

                log.info(f"Enriched {tool_name} from nf-core module")
                break

            except Exception as e:
                log.warning(f"Error reading nf-core module {module_path}: {e}")

    def convert_from_xml(self, xml_path: Path) -> InstallationMethods:
        """Extract and convert requirements directly from Galaxy tool XML."""
        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()

            # Extract requirements
            requirements = []
            for req_elem in root.findall('.//requirements/requirement'):
                req_type = req_elem.get('type', 'package')
                req_version = req_elem.get('version', None)
                req_name = req_elem.text.strip() if req_elem.text else None

                if req_name:
                    requirements.append({
                        'name': req_name,
                        'version': req_version,
                        'type': req_type
                    })

            # Get tool info
            tool_name = root.get('name', '')
            tool_id = root.get('id', '')

            return self.convert(requirements, tool_name=tool_name, tool_id=tool_id)

        except Exception as e:
            log.error(f"Error parsing XML {xml_path}: {e}")
            return InstallationMethods(source='error')

    def generate_nextflow_directives(self, methods: InstallationMethods,
                                     prefer: str = 'conda') -> str:
        """Generate Nextflow process directives for all methods."""
        lines = []

        # Conda (primary by default)
        if methods.conda:
            if '/' in methods.conda or '::' not in methods.conda:
                # Assume it's a path to environment.yml
                lines.append(f'    conda "{methods.conda}"')
            else:
                # Generate environment.yml content
                lines.append(f'    conda "{methods.conda}"')

        # Container
        if methods.docker and methods.singularity:
            lines.append(f"    container \"${{workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container")
            lines.append(f"        ? '{methods.singularity}'")
            lines.append(f"        : '{methods.docker}'}}\"")
        elif methods.docker:
            lines.append(f"    container '{methods.docker}'")

        # Module (commented out, user can enable)
        if methods.module:
            lines.append(f"    // module '{methods.module}'  // Uncomment to use environment modules")

        return '\n'.join(lines)

    def generate_environment_yml(self, methods: InstallationMethods) -> str:
        """Generate environment.yml content for conda."""
        if not methods.conda:
            return ""

        channels = '\n'.join(f'  - {ch}' for ch in methods.conda_channels)

        # Extract package spec
        if '::' in methods.conda:
            package_spec = methods.conda.split('::', 1)[1]
        else:
            package_spec = methods.conda

        return f"""channels:
{channels}
dependencies:
  - {package_spec}
"""


def convert_galaxy_requirements(galaxy_requirements: List[Dict[str, Any]],
                                tool_name: Optional[str] = None,
                                tool_id: Optional[str] = None,
                                nfcore_base: Optional[Path] = None) -> InstallationMethods:
    """Convenience function to convert Galaxy requirements."""
    converter = MultiSourceDependencyConverter(nfcore_base_dir=nfcore_base)
    return converter.convert(galaxy_requirements, tool_name=tool_name, tool_id=tool_id)
