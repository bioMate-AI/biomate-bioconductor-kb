#!/usr/bin/env python3
"""
Real Test Data Fetcher - Downloads actual test data from tool repositories

Instead of using dummy test files, this fetches real test data from:
1. Tool repository's test/ or test_data/ directories
2. Tool repository's examples/ directory
3. Publicly available sample datasets referenced in docs

Usage:
    from real_test_data_fetcher import RealTestDataFetcher
    fetcher = RealTestDataFetcher(github_token)
    test_files = fetcher.fetch_test_data(tool_metadata, file_types=['fastq', 'bam'])
"""

import logging
import re
import subprocess
import tempfile
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from github import Github
import requests

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class RealTestDataFetcher:
    """
    Fetches real test data from tool repositories.
    """

    # Common test data directory patterns
    TEST_DIR_PATTERNS = [
        'test',
        'tests',
        'test_data',
        'testdata',
        'test-data',
        'examples',
        'example',
        'sample_data',
        'samples',
        'data',
    ]

    # File type extensions to look for
    FILE_TYPE_EXTENSIONS = {
        'fastq': ['.fastq', '.fq', '.fastq.gz', '.fq.gz'],
        'fasta': ['.fasta', '.fa', '.fna', '.faa', '.fas', '.fasta.gz', '.fa.gz'],
        'bam': ['.bam'],
        'sam': ['.sam'],
        'vcf': ['.vcf', '.vcf.gz'],
        'gff': ['.gff', '.gff3', '.gtf'],
        'bed': ['.bed'],
        'csv': ['.csv'],
        'tsv': ['.tsv', '.txt'],
        'json': ['.json'],
        'xml': ['.xml'],
    }

    # Maximum file size to download (10MB)
    MAX_FILE_SIZE = 10 * 1024 * 1024

    def __init__(self, github_token: Optional[str] = None):
        """
        Initialize fetcher with GitHub token.

        Args:
            github_token: GitHub API token for authentication
        """
        self.github_token = github_token
        if github_token:
            self.github = Github(github_token)
        else:
            self.github = None

    def fetch_test_data(
        self,
        tool_metadata: Dict,
        file_types: Optional[List[str]] = None,
        max_files: int = 3
    ) -> Dict[str, Path]:
        """
        Fetch real test data from tool repository.

        Args:
            tool_metadata: Tool metadata including repo URL
            file_types: List of file types to fetch (e.g., ['fastq', 'bam'])
            max_files: Maximum number of files to download per type

        Returns:
            Dict mapping parameter names to downloaded file paths
        """
        if not file_types:
            file_types = ['fastq', 'fasta', 'bam', 'vcf']

        logger.info(f"Fetching real test data for {tool_metadata.get('name')}")
        logger.info(f"  Looking for file types: {file_types}")

        test_files = {}

        # Extract repo info
        repo_url = tool_metadata.get('url', '')
        if not repo_url or 'github.com' not in repo_url:
            logger.warning("No GitHub repository URL found")
            return test_files

        # Parse owner/repo from URL
        match = re.search(r'github\.com/([^/]+)/([^/]+)', repo_url)
        if not match:
            logger.warning(f"Could not parse repository from URL: {repo_url}")
            return test_files

        owner, repo_name = match.groups()
        repo_name = repo_name.replace('.git', '')

        logger.info(f"  Repository: {owner}/{repo_name}")

        try:
            # Get repository
            if self.github:
                repo = self.github.get_repo(f"{owner}/{repo_name}")
            else:
                logger.warning("No GitHub token provided, using public API")
                return test_files

            # Search for test directories
            test_dirs = self._find_test_directories(repo)

            if not test_dirs:
                logger.warning("No test directories found in repository")
                return test_files

            logger.info(f"  Found {len(test_dirs)} test directories")

            # Download test files
            for file_type in file_types:
                files = self._find_files_in_dirs(repo, test_dirs, file_type, max_files)

                if files:
                    logger.info(f"  Found {len(files)} {file_type} test files")

                    for file_info in files[:max_files]:
                        downloaded_path = self._download_file(repo, file_info)
                        if downloaded_path:
                            # Use file type as parameter name
                            param_name = f"input_{file_type}"
                            test_files[param_name] = downloaded_path
                            logger.info(f"    ✓ Downloaded: {file_info['path']}")
                        if len(test_files) >= max_files:
                            break

        except Exception as e:
            logger.error(f"Error fetching test data: {e}")

        return test_files

    def _find_test_directories(self, repo) -> List[Dict]:
        """
        Find test data directories in repository.

        Returns:
            List of directory info dicts
        """
        test_dirs = []

        try:
            # Get repository contents
            contents = repo.get_contents("")

            # Search for test directories
            for content in contents:
                if content.type == "dir":
                    dir_name = content.name.lower()

                    # Check if directory name matches test patterns
                    for pattern in self.TEST_DIR_PATTERNS:
                        if pattern in dir_name:
                            test_dirs.append({
                                'path': content.path,
                                'name': content.name
                            })
                            break

            # Also check subdirectories one level deep
            for content in contents:
                if content.type == "dir" and content.name.lower() not in ['node_modules', '.git', 'build', 'dist']:
                    try:
                        subcontents = repo.get_contents(content.path)
                        for subcontent in subcontents:
                            if subcontent.type == "dir":
                                subdir_name = subcontent.name.lower()
                                for pattern in self.TEST_DIR_PATTERNS:
                                    if pattern in subdir_name:
                                        test_dirs.append({
                                            'path': subcontent.path,
                                            'name': subcontent.name
                                        })
                                        break
                    except:
                        pass

        except Exception as e:
            logger.error(f"Error finding test directories: {e}")

        return test_dirs

    def _find_files_in_dirs(
        self,
        repo,
        directories: List[Dict],
        file_type: str,
        max_files: int
    ) -> List[Dict]:
        """
        Find files of specific type in test directories.

        Returns:
            List of file info dicts
        """
        files = []
        extensions = self.FILE_TYPE_EXTENSIONS.get(file_type, [])

        for directory in directories:
            if len(files) >= max_files:
                break

            try:
                contents = repo.get_contents(directory['path'])

                for content in contents:
                    if content.type == "file":
                        # Check if file extension matches
                        file_name = content.name.lower()
                        for ext in extensions:
                            if file_name.endswith(ext):
                                # Check file size
                                if content.size > self.MAX_FILE_SIZE:
                                    logger.warning(f"  Skipping large file: {content.path} ({content.size} bytes)")
                                    continue

                                files.append({
                                    'path': content.path,
                                    'name': content.name,
                                    'size': content.size,
                                    'download_url': content.download_url
                                })
                                break

                    if len(files) >= max_files:
                        break

            except Exception as e:
                logger.error(f"Error searching directory {directory['path']}: {e}")

        return files

    def _download_file(self, repo, file_info: Dict) -> Optional[Path]:
        """
        Download file from repository.

        Returns:
            Path to downloaded file
        """
        try:
            # Create temporary directory
            tmpdir = Path(tempfile.mkdtemp(prefix='biomate_test_'))

            # Download file
            file_path = tmpdir / file_info['name']

            response = requests.get(file_info['download_url'], timeout=60)
            response.raise_for_status()

            with open(file_path, 'wb') as f:
                f.write(response.content)

            logger.info(f"    Downloaded {file_info['size']} bytes to {file_path}")
            return file_path

        except Exception as e:
            logger.error(f"Error downloading file {file_info['path']}: {e}")
            return None

    def find_test_command_in_readme(self, tool_metadata: Dict) -> Optional[str]:
        """
        Extract test command from README or documentation.

        Returns:
            Test command string if found
        """
        readme = tool_metadata.get('readme', '')

        if not readme:
            return None

        # Look for common test command patterns
        patterns = [
            r'```\s*bash\s*\n([^\n]+test[^\n]+)\n',
            r'```\s*sh\s*\n([^\n]+test[^\n]+)\n',
            r'\$\s+([^\n]+test[^\n]+)',
            r'#\s+Test\n\s*([^\n]+)',
        ]

        for pattern in patterns:
            matches = re.finditer(pattern, readme, re.IGNORECASE | re.MULTILINE)
            for match in matches:
                command = match.group(1).strip()
                if command and not command.startswith('#'):
                    logger.info(f"Found test command in README: {command}")
                    return command

        return None


if __name__ == '__main__':
    # Test
    import os

    token = os.getenv('GITHUB_TOKEN')
    if not token:
        print("ERROR: GITHUB_TOKEN not set")
        exit(1)

    fetcher = RealTestDataFetcher(token)

    # Test with a known bioinformatics tool
    test_metadata = {
        'name': 'seqtk',
        'url': 'https://github.com/lh3/seqtk',
        'description': 'Toolkit for processing sequences in FASTA/Q formats'
    }

    test_files = fetcher.fetch_test_data(
        test_metadata,
        file_types=['fastq', 'fasta'],
        max_files=2
    )

    print("\nFetched test files:")
    for param, path in test_files.items():
        print(f"  {param}: {path} ({path.stat().st_size} bytes)")
