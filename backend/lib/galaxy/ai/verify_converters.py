#!/usr/bin/env python3
"""
Quick verification script for multi-source dependency converter and resource resolver.
Tests core functionality without full workflow conversion.
"""

from multi_source_dependency_converter import MultiSourceDependencyConverter, InstallationMethods
from resource_resolver import ResourceResolver, ResourceRequirement
from pathlib import Path

def test_dependency_converter():
    """Test multi-source dependency converter."""
    print("=" * 80)
    print("TESTING: MultiSourceDependencyConverter")
    print("=" * 80)

    converter = MultiSourceDependencyConverter()

    # Test 1: Simple tool requirement
    print("\n1. Testing simple tool conversion (salmon)...")
    requirements = [
        {'name': 'salmon', 'version': '1.10.3', 'type': 'package'}
    ]

    result = converter.convert(requirements, tool_name='salmon')

    print(f"   Conda: {result.conda}")
    print(f"   Docker: {result.docker}")
    print(f"   Singularity: {result.singularity}")
    print(f"   Module: {result.module}")
    print(f"   Source: {result.source}")
    print(f"   Confidence: {result.confidence}")

    assert result.conda is not None, "❌ Conda spec should be generated"
    assert result.docker is not None, "❌ Docker spec should be generated"
    assert result.singularity is not None, "❌ Singularity spec should be generated"
    print("   ✅ All installation methods generated")

    # Test 2: Generate Nextflow directives
    print("\n2. Testing Nextflow directive generation...")
    directives = converter.generate_nextflow_directives(result)
    print(f"   Generated directives:")
    for line in directives.split('\n'):
        print(f"     {line}")

    assert 'conda' in directives, "❌ Conda directive missing"
    assert 'container' in directives, "❌ Container directive missing"
    print("   ✅ Directives generated correctly")

    # Test 3: Generate environment.yml
    print("\n3. Testing environment.yml generation...")
    env_yml = converter.generate_environment_yml(result)
    print(f"   Generated environment.yml:")
    for line in env_yml.split('\n'):
        print(f"     {line}")

    assert 'channels:' in env_yml, "❌ Channels section missing"
    assert 'dependencies:' in env_yml, "❌ Dependencies section missing"
    assert 'bioconda' in env_yml or 'conda-forge' in env_yml, "❌ Channel missing"
    print("   ✅ environment.yml generated correctly")

    print("\n✅ MultiSourceDependencyConverter: ALL TESTS PASSED")
    return True


def test_resource_resolver():
    """Test resource resolver."""
    print("\n" + "=" * 80)
    print("TESTING: ResourceResolver")
    print("=" * 80)

    resolver = ResourceResolver()

    # Test 1: Category-based inference
    print("\n1. Testing category-based inference (alignment)...")
    result = resolver.resolve(
        tool_name='bwa',
        category='alignment'
    )

    print(f"   CPUs: {result.cpus}")
    print(f"   Memory: {result.memory_gb}GB")
    print(f"   Time: {result.time_hours}h")
    print(f"   Label: {result.label}")
    print(f"   Source: {result.source}")
    print(f"   Confidence: {result.confidence}")

    assert result.label == 'process_high', f"❌ Expected process_high for alignment, got {result.label}"
    assert result.cpus == 12, f"❌ Expected 12 CPUs for process_high, got {result.cpus}"
    assert result.memory_gb == 72, f"❌ Expected 72GB for process_high, got {result.memory_gb}"
    print("   ✅ Category inference correct")

    # Test 2: QC tools should be low
    print("\n2. Testing category-based inference (qc)...")
    result = resolver.resolve(
        tool_name='fastqc',
        category='qc'
    )

    print(f"   Label: {result.label}")
    print(f"   CPUs: {result.cpus}")
    print(f"   Memory: {result.memory_gb}GB")

    assert result.label == 'process_low', f"❌ Expected process_low for QC, got {result.label}"
    assert result.cpus == 2, f"❌ Expected 2 CPUs for process_low, got {result.cpus}"
    print("   ✅ QC tools get process_low")

    # Test 3: Default fallback
    print("\n3. Testing default fallback (unknown tool)...")
    result = resolver.resolve(
        tool_name='unknown_tool_xyz'
    )

    print(f"   Label: {result.label}")
    print(f"   Source: {result.source}")
    print(f"   Confidence: {result.confidence}")

    assert result.label == 'process_medium', f"❌ Expected process_medium for default, got {result.label}"
    assert result.source == 'default', f"❌ Expected 'default' source, got {result.source}"
    assert result.confidence == 0.3, f"❌ Expected 0.3 confidence for default, got {result.confidence}"
    print("   ✅ Default fallback works")

    # Test 4: CPU to label mapping
    print("\n4. Testing CPU to label mapping...")
    test_cases = [
        (1, 'process_single'),
        (2, 'process_low'),
        (4, 'process_medium'),
        (6, 'process_medium'),
        (8, 'process_high'),
        (12, 'process_high'),
    ]

    for cpus, expected_label in test_cases:
        label = resolver._cpus_to_label(cpus)
        print(f"   {cpus} CPUs → {label}")
        assert label == expected_label, f"❌ Expected {expected_label} for {cpus} CPUs, got {label}"

    print("   ✅ CPU to label mapping correct")

    print("\n✅ ResourceResolver: ALL TESTS PASSED")
    return True


def test_integration():
    """Test that both work together."""
    print("\n" + "=" * 80)
    print("TESTING: Integration")
    print("=" * 80)

    dependency_converter = MultiSourceDependencyConverter()
    resource_resolver = ResourceResolver()

    # Simulate converting a tool
    print("\n1. Converting tool: trim-galore...")

    requirements = [
        {'name': 'trim-galore', 'version': '0.6.7', 'type': 'package'}
    ]

    install_methods = dependency_converter.convert(
        requirements,
        tool_name='trim-galore'
    )

    resource_req = resource_resolver.resolve(
        tool_name='trim-galore',
        category='trimming'
    )

    print(f"\n   Installation Methods:")
    print(f"     Conda: {install_methods.conda}")
    print(f"     Docker: {install_methods.docker}")
    print(f"\n   Resource Requirements:")
    print(f"     Label: {resource_req.label}")
    print(f"     CPUs: {resource_req.cpus}")
    print(f"     Memory: {resource_req.memory_gb}GB")

    # Generate complete process definition components
    print("\n2. Generating Nextflow components...")

    # Override conda to use moduleDir (as done in actual converter)
    install_methods.conda = "${moduleDir}/environment.yml"

    directives = dependency_converter.generate_nextflow_directives(install_methods)
    env_yml = dependency_converter.generate_environment_yml(install_methods)

    print(f"\n   Process directives:")
    print(f"     label '{resource_req.label}'")
    for line in directives.split('\n'):
        print(f"     {line}")

    print(f"\n   environment.yml would contain:")
    for line in env_yml.split('\n')[:5]:  # First 5 lines
        print(f"     {line}")

    assert 'conda' in directives, "❌ Conda directive missing"
    assert 'container' in directives, "❌ Container directive missing"
    assert resource_req.label in ['process_single', 'process_low', 'process_medium', 'process_high'], "❌ Invalid label"

    print("\n   ✅ Integration works correctly")

    print("\n✅ Integration: ALL TESTS PASSED")
    return True


if __name__ == "__main__":
    print("Starting verification tests...\n")

    try:
        success = True
        success = success and test_dependency_converter()
        success = success and test_resource_resolver()
        success = success and test_integration()

        print("\n" + "=" * 80)
        if success:
            print("✅✅✅ ALL VERIFICATION TESTS PASSED ✅✅✅")
        else:
            print("❌ SOME TESTS FAILED")
        print("=" * 80)

    except Exception as e:
        print(f"\n❌ ERROR: {e}")
        import traceback
        traceback.print_exc()
