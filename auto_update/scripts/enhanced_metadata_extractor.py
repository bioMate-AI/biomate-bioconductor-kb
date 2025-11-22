#!/usr/bin/env python3
"""
Enhanced Metadata Extractor - Comprehensive tool information collection

Extracts:
- Version information (for duplicate checking with version comparison)
- Dependencies (requirements.txt, setup.py, Cargo.toml, package.json, etc.)
- Test commands (from README, CI files, Makefile)
- Usage examples (from docs)
- Installation requirements

Usage:
    from enhanced_metadata_extractor import EnhancedMetadataExtractor
    extractor = EnhancedMetadataExtractor(github_token)
    metadata = extractor.extract(repo_url)
"""

import logging
import re
from typing import Dict, List, Optional, Tuple
from pathlib import Path
from github import Github
import toml
import yaml

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class EnhancedMetadataExtractor:
    """
    Extracts comprehensive metadata from tool repositories.
    """

    def __init__(self, github_token: Optional[str] = None):
        self.github_token = github_token
        if github_token:
            self.github = Github(github_token)
        else:
            self.github = None

    def extract(self, tool_metadata: Dict) -> Dict:
        """
        Extract comprehensive metadata including version, dependencies, tests.

        Returns:
            Dict with additional fields:
            - version: Tool version
            - dependencies: List of dependencies with package manager
            - test_commands: List of test commands found
            - usage_examples: List of usage examples
            - install_commands: Installation commands
        """
        enhanced = tool_metadata.copy()

        repo_url = tool_metadata.get('url', '')
        if not repo_url or 'github.com' not in repo_url:
            logger.warning("No valid GitHub URL")
            return enhanced

        # Parse owner/repo
        match = re.search(r'github\.com/([^/]+)/([^/]+)', repo_url)
        if not match:
            return enhanced

        owner, repo_name = match.groups()
        repo_name = repo_name.replace('.git', '')

        try:
            if not self.github:
                logger.warning("No GitHub token, limited extraction")
                return enhanced

            repo = self.github.get_repo(f"{owner}/{repo_name}")

            # Extract version
            enhanced['version'] = self._extract_version(repo, tool_metadata)

            # Extract dependencies
            enhanced['dependencies'] = self._extract_dependencies(repo)

            # Extract test commands
            enhanced['test_commands'] = self._extract_test_commands(repo, tool_metadata)

            # Extract usage examples
            enhanced['usage_examples'] = self._extract_usage_examples(tool_metadata)

            # Extract installation commands
            enhanced['install_commands'] = self._extract_install_commands(repo, tool_metadata)

            logger.info(f"Enhanced metadata extracted:")
            logger.info(f"  Version: {enhanced.get('version', 'unknown')}")
            logger.info(f"  Dependencies: {len(enhanced.get('dependencies', []))} found")
            logger.info(f"  Test commands: {len(enhanced.get('test_commands', []))} found")
            logger.info(f"  Examples: {len(enhanced.get('usage_examples', []))} found")

        except Exception as e:
            logger.error(f"Error extracting enhanced metadata: {e}")

        return enhanced

    def _extract_version(self, repo, tool_metadata: Dict) -> str:
        """
        Extract tool version from multiple sources.
        """
        # Try GitHub releases first
        try:
            releases = list(repo.get_releases())
            if releases:
                latest = releases[0]
                version = latest.tag_name.lstrip('v')
                logger.info(f"  Found version from releases: {version}")
                return version
        except:
            pass

        # Try tags
        try:
            tags = list(repo.get_tags())
            if tags:
                latest_tag = tags[0].name.lstrip('v')
                logger.info(f"  Found version from tags: {latest_tag}")
                return latest_tag
        except:
            pass

        # Try version files
        version_files = [
            'VERSION',
            'version.txt',
            '__version__.py',
            'setup.py',
            'pyproject.toml',
            'Cargo.toml',
            'package.json'
        ]

        for version_file in version_files:
            try:
                content = repo.get_contents(version_file)
                file_content = content.decoded_content.decode('utf-8')

                # Parse based on file type
                if version_file == 'package.json':
                    import json
                    data = json.loads(file_content)
                    if 'version' in data:
                        logger.info(f"  Found version from {version_file}: {data['version']}")
                        return data['version']

                elif version_file == 'Cargo.toml':
                    data = toml.loads(file_content)
                    if 'package' in data and 'version' in data['package']:
                        logger.info(f"  Found version from {version_file}: {data['package']['version']}")
                        return data['package']['version']

                elif version_file == 'pyproject.toml':
                    data = toml.loads(file_content)
                    if 'project' in data and 'version' in data['project']:
                        logger.info(f"  Found version from {version_file}: {data['project']['version']}")
                        return data['project']['version']

                else:
                    # Simple text search
                    version_match = re.search(r'version\s*=\s*["\']([^"\']+)["\']', file_content, re.IGNORECASE)
                    if version_match:
                        logger.info(f"  Found version from {version_file}: {version_match.group(1)}")
                        return version_match.group(1)

            except:
                continue

        # Fallback to commit date
        try:
            commits = list(repo.get_commits().get_page(0))
            if commits:
                latest_commit = commits[0]
                commit_date = latest_commit.commit.author.date.strftime('%Y%m%d')
                logger.info(f"  Using commit date as version: {commit_date}")
                return f"git.{commit_date}"
        except:
            pass

        return "unknown"

    def _extract_dependencies(self, repo) -> List[Dict]:
        """
        Extract dependencies from various package manager files.
        """
        dependencies = []

        # Python dependencies
        for dep_file in ['requirements.txt', 'setup.py', 'pyproject.toml', 'environment.yml']:
            try:
                content = repo.get_contents(dep_file)
                file_content = content.decoded_content.decode('utf-8')

                if dep_file == 'requirements.txt':
                    for line in file_content.split('\n'):
                        line = line.strip()
                        if line and not line.startswith('#'):
                            dependencies.append({
                                'package_manager': 'pip',
                                'dependency': line,
                                'source': dep_file
                            })

                elif dep_file == 'setup.py':
                    # Extract install_requires
                    install_requires = re.search(
                        r'install_requires\s*=\s*\[(.*?)\]',
                        file_content,
                        re.DOTALL
                    )
                    if install_requires:
                        deps_str = install_requires.group(1)
                        for dep in re.findall(r'["\']([^"\']+)["\']', deps_str):
                            dependencies.append({
                                'package_manager': 'pip',
                                'dependency': dep,
                                'source': dep_file
                            })

                elif dep_file == 'pyproject.toml':
                    data = toml.loads(file_content)
                    if 'project' in data and 'dependencies' in data['project']:
                        for dep in data['project']['dependencies']:
                            dependencies.append({
                                'package_manager': 'pip',
                                'dependency': dep,
                                'source': dep_file
                            })

                elif dep_file == 'environment.yml':
                    data = yaml.safe_load(file_content)
                    if 'dependencies' in data:
                        for dep in data['dependencies']:
                            if isinstance(dep, str):
                                dependencies.append({
                                    'package_manager': 'conda',
                                    'dependency': dep,
                                    'source': dep_file
                                })

            except:
                continue

        # Rust dependencies
        try:
            cargo_toml = repo.get_contents('Cargo.toml')
            data = toml.loads(cargo_toml.decoded_content.decode('utf-8'))
            if 'dependencies' in data:
                for dep_name, dep_info in data['dependencies'].items():
                    dependencies.append({
                        'package_manager': 'cargo',
                        'dependency': dep_name,
                        'source': 'Cargo.toml'
                    })
        except:
            pass

        # Node.js dependencies
        try:
            package_json = repo.get_contents('package.json')
            import json
            data = json.loads(package_json.decoded_content.decode('utf-8'))
            for dep_type in ['dependencies', 'devDependencies']:
                if dep_type in data:
                    for dep_name, dep_version in data[dep_type].items():
                        dependencies.append({
                            'package_manager': 'npm',
                            'dependency': f"{dep_name}@{dep_version}",
                            'source': 'package.json'
                        })
        except:
            pass

        logger.info(f"  Extracted {len(dependencies)} dependencies")
        return dependencies

    def _extract_test_commands(self, repo, tool_metadata: Dict) -> List[str]:
        """
        Extract test commands from CI configs, Makefile, README.
        """
        test_commands = []

        # Check CI files
        ci_files = [
            '.github/workflows/test.yml',
            '.github/workflows/ci.yml',
            '.github/workflows/main.yml',
            '.travis.yml',
            '.gitlab-ci.yml'
        ]

        for ci_file in ci_files:
            try:
                content = repo.get_contents(ci_file)
                file_content = content.decoded_content.decode('utf-8')

                # Extract commands after 'run:' in YAML
                for match in re.finditer(r'run:\s*(.+)', file_content):
                    command = match.group(1).strip()
                    if 'test' in command.lower() or 'pytest' in command or 'cargo test' in command:
                        test_commands.append(command)

            except:
                continue

        # Check Makefile
        try:
            makefile = repo.get_contents('Makefile')
            file_content = makefile.decoded_content.decode('utf-8')

            # Extract test targets
            for match in re.finditer(r'^test.*?:\s*\n\t(.+)', file_content, re.MULTILINE):
                test_commands.append(match.group(1).strip())

        except:
            pass

        # Check README for test commands
        readme = tool_metadata.get('readme', '')
        if readme:
            # Look for test command patterns
            patterns = [
                r'```\s*(?:bash|sh)\s*\n([^\n]*test[^\n]*)\n',
                r'\$\s+([^\n]*test[^\n]*)',
                r'`([^`]*test[^`]*)`',
            ]

            for pattern in patterns:
                for match in re.finditer(pattern, readme, re.IGNORECASE):
                    command = match.group(1).strip()
                    if command and not command.startswith('#'):
                        test_commands.append(command)

        # Deduplicate
        test_commands = list(set(test_commands))
        logger.info(f"  Extracted {len(test_commands)} test commands")

        return test_commands[:10]  # Limit to 10 most relevant

    def _extract_usage_examples(self, tool_metadata: Dict) -> List[str]:
        """
        Extract usage examples from README.
        """
        examples = []
        readme = tool_metadata.get('readme', '')

        if not readme:
            return examples

        # Look for code blocks with tool invocations
        code_blocks = re.findall(r'```(?:bash|sh|shell)?\s*\n(.*?)\n```', readme, re.DOTALL)

        for block in code_blocks:
            lines = block.split('\n')
            for line in lines:
                line = line.strip()
                # Skip comments and empty lines
                if line and not line.startswith('#'):
                    # Look for command-like patterns
                    if line.startswith('$'):
                        line = line[1:].strip()
                    if line and not line.startswith('sudo'):
                        examples.append(line)

        # Limit to 5 most relevant examples
        return examples[:5]

    def _extract_install_commands(self, repo, tool_metadata: Dict) -> List[str]:
        """
        Extract installation commands from README and docs.
        """
        install_commands = []
        readme = tool_metadata.get('readme', '')

        if not readme:
            return install_commands

        # Look for installation section
        install_section = re.search(
            r'##\s*Install.*?\n(.*?)(?=\n##|\Z)',
            readme,
            re.DOTALL | re.IGNORECASE
        )

        if install_section:
            section_text = install_section.group(1)

            # Extract commands from code blocks
            code_blocks = re.findall(r'```(?:bash|sh)?\s*\n(.*?)\n```', section_text, re.DOTALL)

            for block in code_blocks:
                for line in block.split('\n'):
                    line = line.strip()
                    if line and not line.startswith('#'):
                        if line.startswith('$'):
                            line = line[1:].strip()
                        # Filter to install commands
                        if any(cmd in line for cmd in ['pip install', 'conda install', 'cargo install', 'npm install', 'git clone']):
                            install_commands.append(line)

        return install_commands[:5]


if __name__ == '__main__':
    # Test
    import os

    token = os.getenv('GITHUB_TOKEN')
    if not token:
        print("ERROR: GITHUB_TOKEN not set")
        exit(1)

    extractor = EnhancedMetadataExtractor(token)

    test_metadata = {
        'name': 'seqtk',
        'url': 'https://github.com/lh3/seqtk',
        'description': 'Toolkit for processing sequences',
        'readme': 'Sample readme content'
    }

    enhanced = extractor.extract(test_metadata)

    print("\nEnhanced Metadata:")
    print(f"Version: {enhanced.get('version')}")
    print(f"Dependencies: {len(enhanced.get('dependencies', []))}")
    print(f"Test commands: {enhanced.get('test_commands', [])}")
    print(f"Install commands: {enhanced.get('install_commands', [])}")
