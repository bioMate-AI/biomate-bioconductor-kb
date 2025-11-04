# Security Quick Reference - Tool Installation

## 🚨 CRITICAL SECURITY ALERTS

### ⛔ DO NOT USE IN PRODUCTION
The automatic tool installation system has **CRITICAL vulnerabilities**:

1. **Command Injection** - ALL 1,632 nfcore_generated tools
2. **No XML Validation** - Local tools not scanned for malicious code
3. **Auto-Install** - Tools installed without user approval

---

## ✅ SAFE: Galaxy ToolShed Tools

**Status:** Relatively safe (has validation + review process)

```python
# Safe approach - ToolShed only
installer = ToolAutoInstaller(
    galaxy_root="/path/to/galaxy",
    galaxy_api_url="http://localhost:8080",
    galaxy_api_key="your_api_key"
)

# Install ToolShed tool (safer)
tool_id = "toolshed.g2.bx.psu.edu/repos/devteam/fastqc/fastqc/0.73"
result = installer._install_toolshed_via_api([tool_id])
```

**Why safer:**
- Manual code review by Galaxy team
- Automated validation checks
- Community vetting
- Update mechanism

---

## ⚠️ UNSAFE: Local BioMate Tools

**Status:** CRITICAL VULNERABILITIES

```python
# UNSAFE - DO NOT USE IN PRODUCTION
installer = ToolAutoInstaller(galaxy_root="/path/to/galaxy")
installer.install_tool("local_tool_id")  # NO VALIDATION!
```

**Vulnerabilities:**
- ❌ Command injection via advanced_options
- ❌ No XML content validation
- ❌ No digital signatures
- ❌ No user approval required

---

## 🛡️ Temporary Mitigations (Until Fixed)

### Option 1: Disable Auto-Install
```python
# Disable automatic installation
generator = EnhancedWorkflowGenerator(
    config=config,
    galaxy_root=galaxy_root
)

# Set auto_install_tools=False
workflow = generator.generate_workflow(
    user_request=request,
    auto_install_tools=False  # DISABLE
)
```

### Option 2: Manual Review Only
```bash
# Manually review EVERY tool before installation
cat backend/tools/tool_name.xml | less

# Check for dangerous patterns:
grep -E "curl|wget|rm -rf|eval|exec|system\(|subprocess" tool.xml

# If safe, install manually (not via auto-installer)
```

### Option 3: ToolShed Only Mode
```python
# Only allow ToolShed installations
def is_toolshed_tool(tool_id: str) -> bool:
    return tool_id.startswith("toolshed.g2.bx.psu.edu")

# Before installing:
if not is_toolshed_tool(tool_id):
    raise SecurityError("Only ToolShed tools allowed")
```

---

## 🔍 How to Check if a Tool is Vulnerable

### Quick Check Script
```bash
#!/bin/bash
# check_tool_security.sh

TOOL_FILE="$1"

echo "Checking: $TOOL_FILE"

# Check for command injection vulnerability
if grep -q 'type="text".*advanced_options' "$TOOL_FILE" && \
   grep -q '\$advanced_options' "$TOOL_FILE"; then
    echo "❌ VULNERABLE: Command injection possible"
    exit 1
fi

# Check for dangerous commands
if grep -qE 'curl|wget|rm -rf|eval|exec' "$TOOL_FILE"; then
    echo "⚠️  WARNING: Dangerous commands detected"
    grep -n -E 'curl|wget|rm -rf|eval|exec' "$TOOL_FILE"
fi

echo "✅ Basic checks passed (manual review still required)"
```

### Usage
```bash
chmod +x check_tool_security.sh
./check_tool_security.sh backend/tools/nfcore_generated/fastqc.xml
```

---

## 📋 Security Checklist Before Tool Installation

- [ ] Tool is from Galaxy ToolShed (verified source)
- [ ] Tool XML has been manually reviewed
- [ ] No `advanced_options` with type="text"
- [ ] No dangerous commands (curl, wget, rm, eval, exec)
- [ ] No arbitrary code execution patterns
- [ ] User has explicitly approved installation
- [ ] Tool is logged in audit trail
- [ ] Rollback plan exists if issues found

---

## 🔧 Quick Fixes for Developers

### Fix 1: Remove advanced_options from Tool
```xml
<!-- BEFORE (VULNERABLE) -->
<param name="advanced_options" type="text" value="" label="Advanced Options"/>
<command>tool_command $advanced_options</command>

<!-- AFTER (SAFE) -->
<param name="quiet_mode" type="boolean" checked="false" label="Quiet Mode"/>
<param name="verbose_mode" type="boolean" checked="false" label="Verbose Mode"/>
<command>
    tool_command
    #if $quiet_mode
        --quiet
    #end if
    #if $verbose_mode
        --verbose
    #end if
</command>
```

### Fix 2: Add Input Validation
```python
def validate_tool_xml(xml_path: Path) -> Tuple[bool, List[str]]:
    """Validate tool XML for security issues."""
    issues = []

    tree = ET.parse(xml_path)
    command = tree.find('.//command')

    if command is not None:
        cmd_text = command.text or ""

        # Check for unsanitized variables
        if re.search(r'\$[a-zA-Z_]+(?!\{)', cmd_text):
            issues.append("Unsanitized variable substitution")

        # Check for dangerous patterns
        dangerous = ['rm -rf', 'curl', 'wget', 'eval', 'exec']
        for pattern in dangerous:
            if pattern in cmd_text:
                issues.append(f"Dangerous pattern: {pattern}")

    return len(issues) == 0, issues
```

### Fix 3: Require User Approval
```python
def install_with_approval(self, tool_ids: List[str]) -> Dict:
    """Install tools with user approval."""

    # Show what will be installed
    print("\n⚠️  The following tools will be installed:")
    for tool_id in tool_ids:
        print(f"  - {tool_id}")

    # Get approval
    response = input("\nProceed with installation? (yes/no): ")

    if response.lower() != "yes":
        return {"success": False, "message": "User declined"}

    # Proceed with installation
    return self.install_missing_tools(tool_ids)
```

---

## 📞 Who to Contact

### Security Issues
- Report vulnerabilities: `security@biomate.ai`
- Do NOT post security issues publicly on GitHub

### Questions
- Development team: `dev@biomate.ai`
- System admin: `admin@biomate.ai`

---

## 📚 Full Documentation

- **Complete Audit:** `SECURITY_AUDIT_TOOL_INSTALLATION.md`
- **Executive Summary:** `SECURITY_AUDIT_SUMMARY_20251104.md`
- **Security Tests:** `backend/test/security/test_tool_installation_security.py`

---

## 🚀 Roadmap to Production

1. ✅ Security audit complete
2. ⏳ Fix command injection (regenerate all tools)
3. ⏳ Implement XML validation
4. ⏳ Add user approval
5. ⏳ Security testing
6. ⏳ Code review
7. ⏳ Penetration testing
8. ⏳ Production deployment

**ETA:** 2-3 months for complete remediation

---

## 🎓 Learn More

### Recommended Reading
- [OWASP Command Injection](https://owasp.org/www-community/attacks/Command_Injection)
- [CWE-78: OS Command Injection](https://cwe.mitre.org/data/definitions/78.html)
- [Galaxy Tool Development Best Practices](https://docs.galaxyproject.org/en/latest/dev/schema.html)

### Training
- Secure coding practices
- Input validation techniques
- Container security

---

**Last Updated:** 2025-11-04
**Version:** 1.0
