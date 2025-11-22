#!/usr/bin/env python3
"""
Tool Execution Tester - Test Galaxy tools in isolated environment

Tests:
- Container pull and startup
- Tool execution with sample data
- Output file generation
- Error handling

Usage:
    python test_tool_execution.py --wrapper data/wrappers/tool.xml
    python test_tool_execution.py --wrapper tool.xml --test-data test_input.txt
"""

import argparse
import json
import logging
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Dict, List, Optional, Tuple
import json as json_module
from xml.etree import ElementTree as ET

try:
    from real_test_data_fetcher import RealTestDataFetcher
    HAS_REAL_TEST_DATA = True
except ImportError:
    HAS_REAL_TEST_DATA = False
    logger.warning("RealTestDataFetcher not available, using dummy test data only")

try:
    from dependency_installer import DependencyInstaller
    HAS_DEPENDENCY_INSTALLER = True
except ImportError:
    HAS_DEPENDENCY_INSTALLER = False
    logger.warning("DependencyInstaller not available, skipping dependency installation")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class TestResult:
    """
    Stores test execution results.
    """

    def __init__(self):
        self.success = False
        self.container_pulled = False
        self.tool_executed = False
        self.outputs_generated = False
        self.exit_code = None
        self.stdout = ""
        self.stderr = ""
        self.outputs = []
        self.errors = []
        self.execution_time = 0.0

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization"""
        return {
            'success': self.success,
            'container_pulled': self.container_pulled,
            'tool_executed': self.tool_executed,
            'outputs_generated': self.outputs_generated,
            'exit_code': self.exit_code,
            'stdout': self.stdout[:1000],  # Limit size
            'stderr': self.stderr[:1000],
            'outputs': self.outputs,
            'errors': self.errors,
            'execution_time': self.execution_time
        }

    def summary(self) -> str:
        """Generate summary report"""
        lines = [
            "="*60,
            "Test Execution Summary",
            "="*60,
            f"Status: {'PASS' if self.success else 'FAIL'}",
            f"Container pulled: {self.container_pulled}",
            f"Tool executed: {self.tool_executed}",
            f"Outputs generated: {self.outputs_generated}",
            f"Exit code: {self.exit_code}",
            f"Execution time: {self.execution_time:.2f}s",
            ""
        ]

        if self.outputs:
            lines.append("Generated outputs:")
            for output in self.outputs:
                lines.append(f"  - {output}")
            lines.append("")

        if self.errors:
            lines.append("ERRORS:")
            for error in self.errors:
                lines.append(f"  - {error}")
            lines.append("")

        if self.stderr:
            lines.append("STDERR (last 500 chars):")
            lines.append(self.stderr[-500:])
            lines.append("")

        lines.append("="*60)
        return "\n".join(lines)


class ContainerManager:
    """
    Manages container operations (Docker/Singularity).
    """

    # Maximum image size in MB (skip images larger than this)
    MAX_IMAGE_SIZE_MB = 2000  # 2GB limit

    def get_image_size(self, image: str) -> Optional[int]:
        """
        Get Docker image size in MB without pulling.

        Returns:
            Size in MB, or None if cannot determine
        """
        try:
            # Try to get size using docker manifest inspect
            result = subprocess.run(
                ['docker', 'manifest', 'inspect', image, '--verbose'],
                capture_output=True,
                timeout=30
            )

            if result.returncode == 0:
                import json
                manifest = json.loads(result.stdout.decode())

                # Calculate total size from layers
                total_size = 0
                if isinstance(manifest, list):
                    for item in manifest:
                        if 'SchemaV2Manifest' in item:
                            layers = item['SchemaV2Manifest'].get('layers', [])
                            for layer in layers:
                                total_size += layer.get('size', 0)

                size_mb = total_size / (1024 * 1024)
                return int(size_mb)

            # Alternative: check if image exists locally and get its size
            result = subprocess.run(
                ['docker', 'images', '--format', '{{.Size}}', image],
                capture_output=True,
                timeout=10
            )

            if result.returncode == 0 and result.stdout.strip():
                size_str = result.stdout.decode().strip()
                # Parse size string like "1.5GB" or "500MB"
                if 'GB' in size_str:
                    return int(float(size_str.replace('GB', '')) * 1024)
                elif 'MB' in size_str:
                    return int(float(size_str.replace('MB', '')))

            return None

        except Exception as e:
            logger.debug(f"Could not get image size: {e}")
            return None

    def pull_container(self, container_type: str, image: str, check_size: bool = True) -> Tuple[bool, str]:
        """
        Pull container image.

        Returns:
            Tuple of (success, message)
        """
        logger.info(f"Pulling {container_type} container: {image}")

        try:
            if container_type == 'docker':
                # Check size first if requested
                if check_size:
                    size_mb = self.get_image_size(image)
                    if size_mb and size_mb > self.MAX_IMAGE_SIZE_MB:
                        msg = f"Image too large ({size_mb}MB > {self.MAX_IMAGE_SIZE_MB}MB limit)"
                        logger.warning(msg)
                        return False, msg
                    elif size_mb:
                        logger.info(f"Image size: {size_mb}MB")

                success = self._pull_docker(image)
                return success, "OK" if success else "Pull failed"
            elif container_type == 'singularity':
                success = self._pull_singularity(image)
                return success, "OK" if success else "Pull failed"
            else:
                return False, f"Unknown container type: {container_type}"
        except Exception as e:
            logger.error(f"Error pulling container: {e}")
            return False, str(e)

    def _pull_docker(self, image: str) -> bool:
        """Pull Docker image"""
        try:
            # Check if Docker is available
            subprocess.run(
                ['docker', '--version'],
                capture_output=True,
                check=True,
                timeout=5
            )

            # Pull image
            result = subprocess.run(
                ['docker', 'pull', image],
                capture_output=True,
                timeout=300  # 5 minutes
            )

            if result.returncode == 0:
                logger.info(f"Successfully pulled Docker image: {image}")
                return True
            else:
                logger.error(f"Failed to pull Docker image: {result.stderr.decode()}")
                return False

        except subprocess.TimeoutExpired:
            logger.error("Docker pull timed out")
            return False
        except subprocess.CalledProcessError as e:
            logger.error(f"Docker not available: {e}")
            return False
        except FileNotFoundError:
            logger.error("Docker not installed")
            return False

    def _pull_singularity(self, image: str) -> bool:
        """Pull Singularity image"""
        try:
            # Check if Singularity is available
            subprocess.run(
                ['singularity', '--version'],
                capture_output=True,
                check=True,
                timeout=5
            )

            # Pull image
            result = subprocess.run(
                ['singularity', 'pull', image],
                capture_output=True,
                timeout=300  # 5 minutes
            )

            if result.returncode == 0:
                logger.info(f"Successfully pulled Singularity image: {image}")
                return True
            else:
                logger.error(f"Failed to pull Singularity image: {result.stderr.decode()}")
                return False

        except subprocess.TimeoutExpired:
            logger.error("Singularity pull timed out")
            return False
        except subprocess.CalledProcessError as e:
            logger.error(f"Singularity not available: {e}")
            return False
        except FileNotFoundError:
            logger.error("Singularity not installed")
            return False


class TestDataGenerator:
    """
    Generates minimal test data for tools.
    """

    def generate_test_data(self, param_type: str, param_name: str) -> Path:
        """
        Generate test data based on parameter type.

        Returns:
            Path to generated test file
        """
        tmpdir = Path(tempfile.mkdtemp())

        if param_type == 'data':
            # Generate based on parameter name
            if 'fastq' in param_name.lower():
                return self._generate_fastq(tmpdir)
            elif 'fasta' in param_name.lower():
                return self._generate_fasta(tmpdir)
            elif 'bam' in param_name.lower():
                return self._generate_bam(tmpdir)
            elif 'vcf' in param_name.lower():
                return self._generate_vcf(tmpdir)
            else:
                return self._generate_generic_text(tmpdir)
        else:
            return self._generate_generic_text(tmpdir)

    def _generate_fastq(self, tmpdir: Path) -> Path:
        """Generate minimal FASTQ file"""
        fastq_file = tmpdir / "test_input.fastq"
        with open(fastq_file, 'w') as f:
            f.write("@SEQ_ID\n")
            f.write("GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT\n")
            f.write("+\n")
            f.write("!''*((((***+))%%%++)(%%%%).1***-+*''))**55CCF>>>>>>CCCCCCC65\n")
        return fastq_file

    def _generate_fasta(self, tmpdir: Path) -> Path:
        """Generate minimal FASTA file"""
        fasta_file = tmpdir / "test_input.fasta"
        with open(fasta_file, 'w') as f:
            f.write(">SEQ_ID Test sequence\n")
            f.write("GATTTGGGGTTCAAAGCAGTATCGATCAAATAGTAAATCCATTTGTTCAACTCACAGTTT\n")
            f.write("ACGTTACCGTATGCATGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTAGCTA\n")
        return fasta_file

    def _generate_bam(self, tmpdir: Path) -> Path:
        """Generate minimal BAM file (placeholder - requires samtools)"""
        # Note: This is a stub. Real implementation would need samtools
        bam_file = tmpdir / "test_input.bam"
        logger.warning("BAM file generation not implemented, using empty file")
        bam_file.touch()
        return bam_file

    def _generate_vcf(self, tmpdir: Path) -> Path:
        """Generate minimal VCF file"""
        vcf_file = tmpdir / "test_input.vcf"
        with open(vcf_file, 'w') as f:
            f.write("##fileformat=VCFv4.2\n")
            f.write("##source=TestDataGenerator\n")
            f.write("#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\n")
            f.write("chr1\t100\t.\tA\tG\t30\tPASS\t.\n")
        return vcf_file

    def _generate_generic_text(self, tmpdir: Path) -> Path:
        """Generate generic text file"""
        txt_file = tmpdir / "test_input.txt"
        with open(txt_file, 'w') as f:
            f.write("This is a test input file.\n")
            f.write("It contains some sample data for testing.\n")
        return txt_file


class ToolExecutor:
    """
    Executes tools in containers.
    """

    def __init__(self, github_token: Optional[str] = None, tool_metadata: Optional[Dict] = None):
        self.container_manager = ContainerManager()
        self.test_data_generator = TestDataGenerator()
        self.tool_metadata = tool_metadata
        self.real_test_data_fetcher = None

        # Initialize real test data fetcher if available
        if HAS_REAL_TEST_DATA and github_token:
            self.real_test_data_fetcher = RealTestDataFetcher(github_token)
            logger.info("Real test data fetcher enabled")
        else:
            logger.warning("Real test data fetcher disabled - will use dummy test data")

    def execute_tool(
        self,
        wrapper_path: Path,
        test_data: Optional[Dict[str, Path]] = None
    ) -> TestResult:
        """
        Execute tool with test data.

        Args:
            wrapper_path: Path to Galaxy XML wrapper
            test_data: Dictionary mapping parameter names to test data files

        Returns:
            TestResult object
        """
        result = TestResult()
        start_time = time.time()

        try:
            # Parse wrapper
            tree = ET.parse(wrapper_path)
            root = tree.getroot()

            # Extract container info
            container_type, container_image = self._extract_container(root)
            if not container_type or not container_image:
                result.errors.append("No container specified in wrapper")
                return result

            # Pull container
            pull_success, pull_message = self.container_manager.pull_container(
                container_type,
                container_image
            )
            result.container_pulled = pull_success

            if not result.container_pulled:
                result.errors.append(f"Failed to pull container: {pull_message}")
                return result

            # Install dependencies if available
            if HAS_DEPENDENCY_INSTALLER and self.tool_metadata:
                dependencies = self.tool_metadata.get('dependencies', [])

                if dependencies:
                    logger.info(f"Installing {len(dependencies)} dependencies in container...")
                    installer = DependencyInstaller()
                    install_success, install_msg = installer.install_in_container(
                        container_type,
                        container_image,
                        dependencies
                    )

                    if not install_success:
                        logger.warning(f"Dependency installation had issues: {install_msg}")
                        # Don't fail the test, just warn - some tools might work without all deps
                    else:
                        logger.info(f"✓ Dependencies installed successfully: {install_msg}")
                else:
                    logger.info("No dependencies to install")

            # Generate test data if not provided
            if not test_data:
                # Try to fetch real test data from repository first
                if self.real_test_data_fetcher and self.tool_metadata:
                    logger.info("Attempting to fetch real test data from repository...")
                    real_test_data = self.real_test_data_fetcher.fetch_test_data(
                        self.tool_metadata,
                        file_types=['fastq', 'fasta', 'bam', 'vcf', 'sam', 'bed'],
                        max_files=3
                    )

                    if real_test_data:
                        logger.info(f"✓ Found {len(real_test_data)} real test files")
                        test_data = real_test_data
                    else:
                        logger.warning("No real test data found, falling back to dummy data")
                        test_data = self._generate_test_data_for_wrapper(root)
                else:
                    # Fall back to dummy test data
                    logger.warning("Using dummy test data (no real test data fetcher available)")
                    test_data = self._generate_test_data_for_wrapper(root)

            # Build command
            command = self._build_command(root, test_data, container_type, container_image)

            # Execute command
            logger.info(f"Executing: {' '.join(command[:5])}...")
            exec_result = subprocess.run(
                command,
                capture_output=True,
                timeout=300  # 5 minutes
            )

            result.exit_code = exec_result.returncode
            result.stdout = exec_result.stdout.decode('utf-8', errors='ignore')
            result.stderr = exec_result.stderr.decode('utf-8', errors='ignore')
            result.tool_executed = True

            # Check outputs
            outputs = self._check_outputs(root, test_data.get('workdir', Path('/tmp')))
            result.outputs = outputs
            result.outputs_generated = len(outputs) > 0

            # Determine success
            result.success = (
                result.container_pulled and
                result.tool_executed and
                result.exit_code == 0 and
                result.outputs_generated
            )

        except subprocess.TimeoutExpired:
            result.errors.append("Tool execution timed out")
        except Exception as e:
            result.errors.append(f"Execution error: {e}")
            logger.error(f"Execution error: {e}")

        result.execution_time = time.time() - start_time
        return result

    def _extract_container(self, root: ET.Element) -> Tuple[Optional[str], Optional[str]]:
        """Extract container type and image from wrapper"""
        requirements = root.find('requirements')
        if requirements is None:
            return None, None

        container = requirements.find('container')
        if container is None:
            return None, None

        container_type = container.get('type')
        container_image = container.text

        return container_type, container_image

    def _generate_test_data_for_wrapper(self, root: ET.Element) -> Dict[str, Path]:
        """Generate test data for all inputs"""
        test_data = {}
        workdir = Path(tempfile.mkdtemp())
        test_data['workdir'] = workdir

        inputs = root.find('inputs')
        if inputs is None:
            return test_data

        for param in inputs.findall('param'):
            name = param.get('name')
            param_type = param.get('type')

            if param_type == 'data':
                test_file = self.test_data_generator.generate_test_data(param_type, name)
                test_data[name] = test_file
            elif param_type == 'integer':
                test_data[name] = '10'
            elif param_type == 'float':
                test_data[name] = '0.5'
            elif param_type == 'boolean':
                test_data[name] = 'true'
            else:
                test_data[name] = 'test_value'

        return test_data

    def _build_command(
        self,
        root: ET.Element,
        test_data: Dict[str, Path],
        container_type: str,
        container_image: str
    ) -> List[str]:
        """Build command to execute tool in container"""
        # Extract command from wrapper
        command_elem = root.find('command')
        if command_elem is None:
            raise ValueError("No command element in wrapper")

        cmd_text = command_elem.text or ''

        # Replace variables with test data
        for param_name, param_value in test_data.items():
            if param_name == 'workdir':
                continue
            cmd_text = cmd_text.replace(f'${{{param_name}}}', str(param_value))
            cmd_text = cmd_text.replace(f'${param_name}', str(param_value))

        # Remove CDATA markers
        cmd_text = cmd_text.replace('<![CDATA[', '').replace(']]>', '')
        cmd_text = cmd_text.strip()

        # Build container command
        if container_type == 'docker':
            workdir = test_data.get('workdir', Path('/tmp'))
            command = [
                'docker', 'run', '--rm',
                '-v', f'{workdir}:/data',
                '-w', '/data',
                container_image,
                'sh', '-c', cmd_text
            ]
        elif container_type == 'singularity':
            command = [
                'singularity', 'exec',
                container_image,
                'sh', '-c', cmd_text
            ]
        else:
            raise ValueError(f"Unsupported container type: {container_type}")

        return command

    def _check_outputs(self, root: ET.Element, workdir: Path) -> List[str]:
        """Check if expected output files were generated"""
        outputs = []

        outputs_elem = root.find('outputs')
        if outputs_elem is None:
            return outputs

        for data in outputs_elem.findall('data'):
            name = data.get('name')
            # Look for output file
            output_file = workdir / name
            if output_file.exists() and output_file.stat().st_size > 0:
                outputs.append(str(output_file))
                logger.info(f"Found output: {output_file} ({output_file.stat().st_size} bytes)")

        return outputs


def main():
    parser = argparse.ArgumentParser(
        description='Test Galaxy tool execution'
    )
    parser.add_argument(
        '--wrapper',
        type=str,
        required=True,
        help='Path to wrapper XML file'
    )
    parser.add_argument(
        '--test-data',
        type=str,
        help='Path to test data file (optional)'
    )
    parser.add_argument(
        '--output',
        type=str,
        default='test_results.json',
        help='Output file for test results (default: test_results.json)'
    )

    args = parser.parse_args()

    wrapper_path = Path(args.wrapper)
    if not wrapper_path.exists():
        logger.error(f"Wrapper file not found: {wrapper_path}")
        return 1

    # Prepare test data
    test_data = {}
    if args.test_data:
        # Parse test data JSON
        with open(args.test_data) as f:
            test_data = json.load(f)

    # Execute test
    executor = ToolExecutor()
    result = executor.execute_tool(wrapper_path, test_data)

    # Print summary
    print(result.summary())

    # Save results
    with open(args.output, 'w') as f:
        json.dump(result.to_dict(), f, indent=2)

    logger.info(f"Test results saved to: {args.output}")

    return 0 if result.success else 1


if __name__ == '__main__':
    exit(main())
