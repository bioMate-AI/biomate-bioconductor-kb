#!/usr/bin/env python3
"""
Documentation Fetcher - Extract comprehensive documentation from repositories

Fetches:
- README (markdown converted to text)
- Installation instructions
- Usage examples
- API documentation
- Container information
- Dependencies

Usage:
    python documentation_fetcher.py --repo user/repo-name
"""

import argparse
import json
import logging
import re
from pathlib import Path
from typing import Dict, List, Optional

import requests
import yaml
from github import Github

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DocumentationFetcher:
    """
    Fetches and processes documentation from GitHub repositories.
    """

    def __init__(self, github_token: str):
        self.github = Github(github_token)

    def fetch_documentation(self, repo_full_name: str) -> Dict:
        """
        Fetch comprehensive documentation for a repository.

        Returns:
            {
                'readme': str,
                'installation': str,
                'usage_examples': List[str],
                'api_docs': str,
                'container_info': Dict,
                'dependencies': Dict,
                'help_text': str
            }
        """
        logger.info(f"Fetching documentation for {repo_full_name}")

        repo = self.github.get_repo(repo_full_name)

        docs = {
            'readme': self._fetch_readme(repo),
            'installation': self._extract_installation(repo),
            'usage_examples': self._extract_examples(repo),
            'api_docs': self._fetch_api_docs(repo),
            'container_info': self._fetch_container_info(repo),
            'dependencies': self._fetch_dependencies(repo),
            'help_text': self._generate_help_text(repo)
        }

        return docs

    def _fetch_readme(self, repo) -> str:
        """Fetch and clean README content"""
        try:
            readme = repo.get_readme()
            content = readme.decoded_content.decode('utf-8')

            # Convert markdown to plain text (basic conversion)
            content = self._markdown_to_text(content)

            return content
        except Exception as e:
            logger.warning(f"Could not fetch README: {e}")
            return ""

    def _markdown_to_text(self, markdown: str) -> str:
        """Basic markdown to text conversion"""
        # Remove code blocks but keep the content
        text = re.sub(r'```[\w]*\n(.*?)\n```', r'\1', markdown, flags=re.DOTALL)

        # Remove inline code
        text = re.sub(r'`([^`]+)`', r'\1', text)

        # Remove images
        text = re.sub(r'!\[.*?\]\(.*?\)', '', text)

        # Remove links but keep text
        text = re.sub(r'\[(.*?)\]\(.*?\)', r'\1', text)

        # Remove headers markers
        text = re.sub(r'^#+\s+', '', text, flags=re.MULTILINE)

        # Remove bold/italic
        text = re.sub(r'[\*_]{1,2}([^\*_]+)[\*_]{1,2}', r'\1', text)

        return text.strip()

    def _extract_installation(self, repo) -> str:
        """Extract installation instructions from README"""
        try:
            readme = repo.get_readme().decoded_content.decode('utf-8')

            # Look for installation section
            patterns = [
                r'##\s*Installation\s*\n(.*?)(?=\n##|\Z)',
                r'##\s*Install\s*\n(.*?)(?=\n##|\Z)',
                r'##\s*Setup\s*\n(.*?)(?=\n##|\Z)',
                r'##\s*Getting Started\s*\n(.*?)(?=\n##|\Z)'
            ]

            for pattern in patterns:
                match = re.search(pattern, readme, re.DOTALL | re.IGNORECASE)
                if match:
                    return match.group(1).strip()

            # Fallback: look for common installation commands
            install_commands = []
            if 'pip install' in readme:
                install_commands.append("pip install (see README)")
            if 'conda install' in readme:
                install_commands.append("conda install (see README)")
            if 'npm install' in readme:
                install_commands.append("npm install (see README)")

            return '\n'.join(install_commands) if install_commands else "See README for installation"

        except Exception as e:
            logger.warning(f"Could not extract installation: {e}")
            return ""

    def _extract_examples(self, repo) -> List[str]:
        """Extract usage examples from README and examples directory"""
        examples = []

        try:
            # Check README for examples
            readme = repo.get_readme().decoded_content.decode('utf-8')

            # Look for example section
            patterns = [
                r'##\s*Examples?\s*\n(.*?)(?=\n##|\Z)',
                r'##\s*Usage\s*\n(.*?)(?=\n##|\Z)',
                r'##\s*Quick\s*Start\s*\n(.*?)(?=\n##|\Z)'
            ]

            for pattern in patterns:
                match = re.search(pattern, readme, re.DOTALL | re.IGNORECASE)
                if match:
                    examples.append(match.group(1).strip())

            # Check for examples/ directory
            try:
                contents = repo.get_contents("examples")
                if isinstance(contents, list):
                    for content in contents[:5]:  # First 5 examples
                        if content.type == "file" and content.name.endswith(('.py', '.sh', '.R')):
                            try:
                                file_content = content.decoded_content.decode('utf-8')
                                examples.append(f"# {content.name}\n{file_content[:500]}")
                            except:
                                pass
            except:
                pass

        except Exception as e:
            logger.warning(f"Could not extract examples: {e}")

        return examples

    def _fetch_api_docs(self, repo) -> str:
        """Fetch API documentation if available"""
        docs_paths = ['docs/', 'documentation/', 'doc/']

        for docs_path in docs_paths:
            try:
                contents = repo.get_contents(docs_path)
                # Found docs directory
                return f"API documentation available at: {docs_path}"
            except:
                continue

        return ""

    def _fetch_container_info(self, repo) -> Dict:
        """Extract container/Docker information"""
        container_info = {}

        try:
            # Check for Dockerfile
            try:
                dockerfile = repo.get_contents("Dockerfile")
                content = dockerfile.decoded_content.decode('utf-8')

                # Extract base image
                base_match = re.search(r'FROM\s+(\S+)', content)
                if base_match:
                    container_info['base_image'] = base_match.group(1)

                container_info['has_dockerfile'] = True
                container_info['dockerfile_path'] = "Dockerfile"
            except:
                pass

            # Check for docker-compose.yml
            try:
                compose = repo.get_contents("docker-compose.yml")
                container_info['has_compose'] = True
            except:
                pass

            # Check for Singularity
            try:
                singularity = repo.get_contents("Singularity")
                container_info['has_singularity'] = True
            except:
                pass

        except Exception as e:
            logger.warning(f"Could not fetch container info: {e}")

        return container_info

    def _fetch_dependencies(self, repo) -> Dict:
        """Extract dependencies from various files"""
        dependencies = {}

        # Python dependencies
        for req_file in ['requirements.txt', 'setup.py', 'pyproject.toml']:
            try:
                content = repo.get_contents(req_file)
                dependencies['python'] = content.decoded_content.decode('utf-8')
                break
            except:
                continue

        # R dependencies
        try:
            content = repo.get_contents("DESCRIPTION")
            dependencies['r'] = content.decoded_content.decode('utf-8')
        except:
            pass

        # Node dependencies
        try:
            content = repo.get_contents("package.json")
            dependencies['node'] = content.decoded_content.decode('utf-8')
        except:
            pass

        # Conda
        for conda_file in ['environment.yml', 'conda.yml']:
            try:
                content = repo.get_contents(conda_file)
                dependencies['conda'] = content.decoded_content.decode('utf-8')
                break
            except:
                continue

        return dependencies

    def _generate_help_text(self, repo) -> str:
        """Generate consolidated help text for Galaxy tool"""
        try:
            readme = repo.get_readme().decoded_content.decode('utf-8')

            # Extract description (first paragraph after title)
            lines = readme.split('\n')
            description = []
            found_title = False

            for line in lines:
                line = line.strip()
                if line.startswith('#'):
                    found_title = True
                    continue
                if found_title and line and not line.startswith('#'):
                    description.append(line)
                    if len(description) >= 3:  # First 3 paragraphs
                        break

            help_text = '\n\n'.join(description)

            # Add repository link
            help_text += f"\n\nRepository: {repo.html_url}"

            return help_text[:2000]  # Limit size

        except Exception as e:
            logger.warning(f"Could not generate help text: {e}")
            return f"See repository: {repo.html_url}"


def main():
    parser = argparse.ArgumentParser(
        description='Fetch documentation from GitHub repository'
    )
    parser.add_argument(
        '--repo',
        required=True,
        help='Repository in format: owner/name'
    )
    parser.add_argument(
        '--token',
        help='GitHub token (or set GITHUB_TOKEN env var)'
    )
    parser.add_argument(
        '--output',
        default='documentation.json',
        help='Output file (default: documentation.json)'
    )

    args = parser.parse_args()

    import os
    token = args.token or os.environ.get('GITHUB_TOKEN')
    if not token:
        print("Error: GitHub token required")
        print("Set via --token or GITHUB_TOKEN environment variable")
        return 1

    fetcher = DocumentationFetcher(token)
    docs = fetcher.fetch_documentation(args.repo)

    # Save to file
    with open(args.output, 'w') as f:
        json.dump(docs, f, indent=2)

    print(f"Documentation saved to: {args.output}")
    print(f"README length: {len(docs['readme'])} chars")
    print(f"Examples found: {len(docs['usage_examples'])}")
    print(f"Container info: {docs['container_info']}")

    return 0


if __name__ == '__main__':
    exit(main())
