#!/usr/bin/env python3
"""
Test script for biomate/biotools:arm64 Docker container execution.

This tests that:
1. Docker container can be executed
2. All critical bioinformatics tools are available
3. Tools execute correctly with test data
4. The container can be used for Galaxy job execution

Run: python3 test_docker_biotools.py
"""

import subprocess
import tempfile
import os
import sys

DOCKER_IMAGE = "biomate/biotools:arm64"
CONDA_ACTIVATE = 'eval "$(micromamba shell hook --shell bash)" && micromamba activate biotools'


def run_in_container(command: str, workdir: str = None, capture_output: bool = True) -> subprocess.CompletedProcess:
    """Execute a command inside the biomate/biotools:arm64 container."""
    docker_cmd = [
        "docker", "run", "--rm",
        "--entrypoint", "/bin/bash",
    ]

    if workdir:
        docker_cmd.extend(["-v", f"{workdir}:{workdir}", "-w", workdir])

    docker_cmd.extend([
        DOCKER_IMAGE,
        "-c", f'{CONDA_ACTIVATE} && {command}'
    ])

    return subprocess.run(docker_cmd, capture_output=capture_output, text=True)


def test_container_exists():
    """Test 1: Verify the Docker container exists."""
    print("Test 1: Checking Docker container exists...")
    result = subprocess.run(["docker", "images", "-q", DOCKER_IMAGE], capture_output=True, text=True)
    if result.stdout.strip():
        print(f"  ✓ Container {DOCKER_IMAGE} exists (ID: {result.stdout.strip()[:12]})")
        return True
    else:
        print(f"  ✗ Container {DOCKER_IMAGE} NOT FOUND")
        return False


def test_tool_availability():
    """Test 2: Verify critical bioinformatics tools are available."""
    print("\nTest 2: Checking tool availability...")

    tools = [
        ("STAR", "STAR --version"),
        ("hisat2", "hisat2 --version 2>&1 | head -1"),
        ("salmon", "salmon --version"),
        ("kallisto", "kallisto version"),
        ("minimap2", "minimap2 --version"),
        ("samtools", "samtools --version | head -1"),
        ("bwa", "bwa 2>&1 | head -3 | tail -1"),
        ("bowtie2", "bowtie2 --version | head -1"),
        ("fastqc", "fastqc --version"),
        ("fastp", "fastp --version 2>&1 | head -1"),
        ("seqkit", "seqkit version"),
        ("bedtools", "bedtools --version"),
        ("mafft", "mafft --version 2>&1 | head -1"),
    ]

    results = []
    for tool_name, cmd in tools:
        result = run_in_container(cmd)
        if result.returncode == 0:
            version = result.stdout.strip() or result.stderr.strip()
            print(f"  ✓ {tool_name}: {version[:50]}")
            results.append(True)
        else:
            print(f"  ✗ {tool_name}: FAILED")
            results.append(False)

    return all(results)


def test_python_packages():
    """Test 3: Verify Python packages are importable."""
    print("\nTest 3: Checking Python packages...")

    packages = [
        ("scanpy", "import scanpy; print(scanpy.__version__)"),
        ("pysam", "import pysam; print(pysam.__version__)"),
        ("pandas", "import pandas; print(pandas.__version__)"),
        ("numpy", "import numpy; print(numpy.__version__)"),
        ("torch", "import torch; print(torch.__version__)"),
        ("biopython", "import Bio; print(Bio.__version__)"),
    ]

    results = []
    for pkg_name, cmd in packages:
        result = run_in_container(f'python -c "{cmd}"')
        if result.returncode == 0:
            version = result.stdout.strip()
            print(f"  ✓ {pkg_name}: {version}")
            results.append(True)
        else:
            print(f"  ✗ {pkg_name}: FAILED")
            results.append(False)

    return all(results)


def test_tool_execution():
    """Test 4: Actually execute tools with test data."""
    print("\nTest 4: Testing tool execution with sample data...")

    with tempfile.TemporaryDirectory() as tmpdir:
        # Create test FASTA file
        fasta_file = os.path.join(tmpdir, "test.fasta")
        with open(fasta_file, "w") as f:
            f.write(">seq1\nACGTACGTACGTACGT\n")
            f.write(">seq2\nGGGGAAAATTTTCCCC\n")

        # Create test FASTQ file
        fastq_file = os.path.join(tmpdir, "test.fastq")
        with open(fastq_file, "w") as f:
            f.write("@read1\nACGTACGTACGTACGT\n+\nIIIIIIIIIIIIIIII\n")
            f.write("@read2\nGGGGAAAATTTTCCCC\n+\nIIIIIIIIIIIIIIII\n")

        tests = [
            ("seqkit stats", f"seqkit stats {fasta_file}"),
            ("samtools faidx", f"samtools faidx {fasta_file} && ls -la {fasta_file}.fai"),
        ]

        results = []
        for test_name, cmd in tests:
            result = run_in_container(cmd, workdir=tmpdir)
            if result.returncode == 0:
                print(f"  ✓ {test_name}: SUCCESS")
                results.append(True)
            else:
                print(f"  ✗ {test_name}: FAILED")
                print(f"    stderr: {result.stderr[:200] if result.stderr else 'none'}")
                results.append(False)

        return all(results)


def test_galaxy_style_execution():
    """Test 5: Simulate Galaxy-style job execution."""
    print("\nTest 5: Testing Galaxy-style job execution...")

    with tempfile.TemporaryDirectory() as tmpdir:
        # Create input file
        input_file = os.path.join(tmpdir, "input.fasta")
        output_file = os.path.join(tmpdir, "output.txt")

        with open(input_file, "w") as f:
            f.write(">BRCA1\nMDALSSLSLPLELSMTAEENKSKAL\n")

        # Simulate Galaxy job: run a command that reads input and writes output
        cmd = f"seqkit seq --name {input_file} > {output_file}"
        result = run_in_container(cmd, workdir=tmpdir)

        if result.returncode == 0 and os.path.exists(output_file):
            with open(output_file) as f:
                content = f.read()
            if "BRCA1" in content:
                print(f"  ✓ Galaxy-style execution: SUCCESS")
                print(f"    Output: {content.strip()}")
                return True

        print(f"  ✗ Galaxy-style execution: FAILED")
        return False


def main():
    print("=" * 60)
    print("BioMate Docker Container Test Suite")
    print(f"Testing: {DOCKER_IMAGE}")
    print("=" * 60)

    tests = [
        ("Container Exists", test_container_exists),
        ("Tool Availability", test_tool_availability),
        ("Python Packages", test_python_packages),
        ("Tool Execution", test_tool_execution),
        ("Galaxy-style Execution", test_galaxy_style_execution),
    ]

    results = []
    for name, test_func in tests:
        try:
            results.append(test_func())
        except Exception as e:
            print(f"\n  ✗ {name}: EXCEPTION - {e}")
            results.append(False)

    print("\n" + "=" * 60)
    print("SUMMARY")
    print("=" * 60)

    passed = sum(results)
    total = len(results)

    for (name, _), result in zip(tests, results):
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"  {status}: {name}")

    print(f"\nTotal: {passed}/{total} tests passed")

    if all(results):
        print("\n✓ All tests passed! Container is ready for Galaxy integration.")
        return 0
    else:
        print("\n✗ Some tests failed. Check the output above.")
        return 1


if __name__ == "__main__":
    sys.exit(main())
