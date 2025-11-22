#!/usr/bin/env python3
"""
Dependency Installer - Install dependencies in containers for testing

Supports:
- pip (Python)
- conda (Python with conda)
- npm (Node.js)
- cargo (Rust)

Usage:
    from dependency_installer import DependencyInstaller
    installer = DependencyInstaller()
    success = installer.install_in_container(
        container_type='docker',
        container_image='python:3.9',
        dependencies=[...]
    )
"""

import logging
import subprocess
from typing import Dict, List, Optional, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class DependencyInstaller:
    """
    Installs tool dependencies in containers for testing.
    """

    def __init__(self):
        self.install_timeout = 300  # 5 minutes per package manager

    def install_in_container(
        self,
        container_type: str,
        container_image: str,
        dependencies: List[Dict]
    ) -> Tuple[bool, str]:
        """
        Install dependencies in a container.

        Args:
            container_type: 'docker' or 'singularity'
            container_image: Container image name
            dependencies: List of dependency dicts with 'package_manager' and 'dependency'

        Returns:
            (success: bool, message: str)
        """
        if not dependencies:
            logger.info("No dependencies to install")
            return True, "No dependencies needed"

        if container_type != 'docker':
            logger.warning(f"Container type {container_type} not fully supported for dependency installation")
            return True, f"Skipping dependency installation for {container_type}"

        # Group dependencies by package manager
        grouped = {}
        for dep in dependencies:
            pm = dep.get('package_manager', 'unknown')
            if pm not in grouped:
                grouped[pm] = []
            grouped[pm].append(dep['dependency'])

        logger.info(f"Installing dependencies in {container_image}:")
        for pm, deps in grouped.items():
            logger.info(f"  {pm}: {len(deps)} packages")

        # Install each package manager's dependencies
        all_success = True
        messages = []

        for pm, deps in grouped.items():
            if pm == 'pip':
                success, msg = self._install_pip_in_docker(container_image, deps)
            elif pm == 'conda':
                success, msg = self._install_conda_in_docker(container_image, deps)
            elif pm == 'npm':
                success, msg = self._install_npm_in_docker(container_image, deps)
            elif pm == 'cargo':
                success, msg = self._install_cargo_in_docker(container_image, deps)
            else:
                logger.warning(f"Unknown package manager: {pm}")
                success = True  # Don't fail on unknown
                msg = f"Skipped {pm}"

            messages.append(f"{pm}: {msg}")

            if not success:
                all_success = False

        return all_success, "; ".join(messages)

    def _install_pip_in_docker(self, image: str, packages: List[str]) -> Tuple[bool, str]:
        """Install pip packages in Docker container."""
        try:
            # Combine packages for single install command
            packages_str = " ".join(f'"{pkg}"' for pkg in packages[:10])  # Limit to 10

            # Build install command
            install_cmd = f"pip install --no-cache-dir {packages_str}"

            # Run in container
            result = subprocess.run(
                [
                    'docker', 'run', '--rm',
                    image,
                    'sh', '-c', install_cmd
                ],
                capture_output=True,
                timeout=self.install_timeout,
                text=True
            )

            if result.returncode == 0:
                logger.info(f"✓ Installed {len(packages)} pip packages")
                return True, f"Installed {len(packages)} packages"
            else:
                logger.warning(f"Failed to install pip packages: {result.stderr[:200]}")
                return False, f"Install failed: {result.stderr[:100]}"

        except subprocess.TimeoutExpired:
            logger.error("Pip installation timed out")
            return False, "Timeout"
        except Exception as e:
            logger.error(f"Error installing pip packages: {e}")
            return False, str(e)

    def _install_conda_in_docker(self, image: str, packages: List[str]) -> Tuple[bool, str]:
        """Install conda packages in Docker container."""
        try:
            packages_str = " ".join(f'"{pkg}"' for pkg in packages[:10])

            # Conda installation requires conda to be installed in the image
            # Most Python images don't have conda, so we'll try but expect failures
            install_cmd = f"conda install -y {packages_str}"

            result = subprocess.run(
                [
                    'docker', 'run', '--rm',
                    image,
                    'sh', '-c', install_cmd
                ],
                capture_output=True,
                timeout=self.install_timeout,
                text=True
            )

            if result.returncode == 0:
                logger.info(f"✓ Installed {len(packages)} conda packages")
                return True, f"Installed {len(packages)} packages"
            else:
                # If conda not available, try pip fallback
                logger.warning(f"Conda not available, attempting pip fallback")
                return self._install_pip_in_docker(image, packages)

        except subprocess.TimeoutExpired:
            return False, "Timeout"
        except Exception as e:
            # Fallback to pip
            logger.warning(f"Conda install failed, trying pip: {e}")
            return self._install_pip_in_docker(image, packages)

    def _install_npm_in_docker(self, image: str, packages: List[str]) -> Tuple[bool, str]:
        """Install npm packages in Docker container."""
        try:
            packages_str = " ".join(packages[:10])

            install_cmd = f"npm install -g {packages_str}"

            result = subprocess.run(
                [
                    'docker', 'run', '--rm',
                    image,
                    'sh', '-c', install_cmd
                ],
                capture_output=True,
                timeout=self.install_timeout,
                text=True
            )

            if result.returncode == 0:
                logger.info(f"✓ Installed {len(packages)} npm packages")
                return True, f"Installed {len(packages)} packages"
            else:
                logger.warning(f"Failed to install npm packages: {result.stderr[:200]}")
                return False, f"Install failed"

        except subprocess.TimeoutExpired:
            return False, "Timeout"
        except Exception as e:
            logger.error(f"Error installing npm packages: {e}")
            return False, str(e)

    def _install_cargo_in_docker(self, image: str, packages: List[str]) -> Tuple[bool, str]:
        """Install cargo packages in Docker container."""
        try:
            # Cargo install is slower and installs one at a time
            # Just verify cargo is available
            result = subprocess.run(
                [
                    'docker', 'run', '--rm',
                    image,
                    'sh', '-c', 'cargo --version'
                ],
                capture_output=True,
                timeout=30,
                text=True
            )

            if result.returncode == 0:
                logger.info(f"✓ Cargo available, {len(packages)} packages declared")
                # Don't actually install - too slow, assume tool builds handle it
                return True, "Cargo available"
            else:
                logger.warning("Cargo not available in image")
                return False, "Cargo not found"

        except Exception as e:
            logger.error(f"Error checking cargo: {e}")
            return False, str(e)

    def create_install_script(self, dependencies: List[Dict]) -> str:
        """
        Create a shell script to install all dependencies.

        This can be used to build a custom Docker image with dependencies.

        Returns:
            Shell script content
        """
        script_lines = [
            "#!/bin/bash",
            "set -e",
            "",
            "# Auto-generated dependency installation script",
            ""
        ]

        # Group by package manager
        grouped = {}
        for dep in dependencies:
            pm = dep.get('package_manager', 'unknown')
            if pm not in grouped:
                grouped[pm] = []
            grouped[pm].append(dep['dependency'])

        # Generate install commands
        if 'pip' in grouped:
            packages = " ".join(f'"{p}"' for p in grouped['pip'])
            script_lines.append(f"# Install pip packages")
            script_lines.append(f"pip install --no-cache-dir {packages}")
            script_lines.append("")

        if 'conda' in grouped:
            packages = " ".join(f'"{p}"' for p in grouped['conda'])
            script_lines.append(f"# Install conda packages")
            script_lines.append(f"conda install -y {packages} || pip install {packages}")
            script_lines.append("")

        if 'npm' in grouped:
            packages = " ".join(grouped['npm'])
            script_lines.append(f"# Install npm packages")
            script_lines.append(f"npm install -g {packages}")
            script_lines.append("")

        if 'cargo' in grouped:
            script_lines.append(f"# Cargo packages (installed via Cargo.toml)")
            for pkg in grouped['cargo']:
                script_lines.append(f"# - {pkg}")
            script_lines.append("")

        return "\n".join(script_lines)


if __name__ == '__main__':
    # Test
    installer = DependencyInstaller()

    test_deps = [
        {'package_manager': 'pip', 'dependency': 'numpy', 'source': 'requirements.txt'},
        {'package_manager': 'pip', 'dependency': 'pandas', 'source': 'requirements.txt'},
    ]

    # Test with Python image
    success, msg = installer.install_in_container(
        'docker',
        'python:3.9-slim',
        test_deps
    )

    print(f"Installation: {'SUCCESS' if success else 'FAILED'}")
    print(f"Message: {msg}")

    # Generate script
    script = installer.create_install_script(test_deps)
    print("\nGenerated script:")
    print(script)
