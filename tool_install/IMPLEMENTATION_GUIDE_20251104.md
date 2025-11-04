# Security Fixes Implementation Guide
## Tool Installation System - November 4, 2025

---

## 🎯 Overview

This guide provides step-by-step instructions for implementing the security fixes identified in the audit.

### What's Been Delivered

✅ **XML Security Validator** - Detects vulnerabilities before installation
✅ **Secure Tool Installer** - Replacement for insecure auto-installer
✅ **XML Fixer Tool** - Automatically fixes vulnerable XML files
✅ **User Approval Patch** - Adds user confirmation before installation
✅ **Comprehensive Tests** - Validates all fixes work correctly

---

## 📂 Fix Components

### 1. XML Security Validator
**File:** `fixes/tool_xml_validator.py`

Validates tool XML files for security issues:
- Command injection detection
- Dangerous pattern scanning
- Parameter validation
- Network access checks
- File access validation

**Usage:**
```bash
# Validate single file
python3 tool_xml_validator.py path/to/tool.xml

# Lenient mode (warnings only)
python3 tool_xml_validator.py path/to/tool.xml --lenient
```

**Example Output:**
```
🔐 Security Validation Report
==================================================

🔴 CRITICAL (6 issues)
--------------------------------------------------
1. [parameter_injection] CRITICAL: Parameter 'advanced_options'
   with type='text' allows command injection
   Fix: Replace with 'select' type with enumerated safe options

⛔ FAILED: Critical security issues found
```

### 2. Secure Tool Installer
**File:** `fixes/secure_tool_installer.py`

Enhanced installer with security features:
- XML validation before installation
- User approval requirements
- Audit logging
- Rollback capability
- File integrity verification (SHA256 hashing)

**Usage:**
```python
from tool_install.fixes.secure_tool_installer import SecureToolInstaller

# Create secure installer
installer = SecureToolInstaller(
    galaxy_root="/path/to/galaxy",
    require_user_approval=True,  # Request user confirmation
    strict_validation=True        # Block high-severity issues
)

# Install tool (will validate and request approval)
success, message = installer.install_tool("fastqc")
```

**Features:**
- ✅ Validates XML before installation
- ✅ Shows security report to user
- ✅ Requests explicit approval
- ✅ Creates backups automatically
- ✅ Maintains audit trail
- ✅ Supports rollback

### 3. XML Vulnerability Fixer
**File:** `fixes/fix_advanced_options.py`

Automatically fixes command injection vulnerability:

**Usage:**
```bash
# Fix single file
python3 fix_advanced_options.py path/to/tool.xml

# Fix entire directory
python3 fix_advanced_options.py backend/tools/nfcore_generated/ --pattern "*.xml"

# Dry run (show what would be fixed)
python3 fix_advanced_options.py backend/tools/nfcore_generated/ --dry-run

# Verbose output
python3 fix_advanced_options.py path/to/tool.xml --verbose
```

**What it does:**
```xml
<!-- BEFORE (VULNERABLE) -->
<param name="advanced_options" type="text" value="" label="Advanced Options"/>
<command>tool_command $advanced_options</command>

<!-- AFTER (SAFE) -->
<param name="advanced_options" type="select" multiple="true" optional="true">
    <option value="--quiet">Quiet mode - minimal output</option>
    <option value="--verbose">Verbose mode - detailed output</option>
    <option value="--no-progress">Disable progress indicator</option>
    <option value="--no-color">Disable colored output</option>
</param>
<command>
    tool_command
    #if $advanced_options
        #for $option in $advanced_options
            $option
        #end for
    #end if
</command>
```

**Example Output:**
```
==================================================
Advanced Options Fix Report
==================================================
Files Processed: 1632
Files Fixed: 1632
Files Skipped: 0
Errors: 0
==================================================

✅ Successfully fixed 1632 files
📁 Backups saved to: ./backups
```

### 4. Workflow Generator User Approval Patch
**File:** `fixes/secure_workflow_generator_patch.py`

Adds user approval to automatic tool installation:

**Usage:**
```python
# Option 1: Monkey-patch existing class
from galaxy.ai.enhanced_workflow_generator import EnhancedWorkflowGenerator
from tool_install.fixes.secure_workflow_generator_patch import secure_auto_install_workflow_tools

EnhancedWorkflowGenerator.auto_install_workflow_tools = secure_auto_install_workflow_tools

# Option 2: Direct integration (recommended)
# Copy the secure_auto_install_workflow_tools method into
# backend/lib/galaxy/ai/enhanced_workflow_generator.py
```

**User Experience:**
```
==================================================
🔐 TOOL INSTALLATION APPROVAL REQUEST
==================================================

The workflow requires installation of 3 tool(s):
Source: local

1. 🟡 nfcore_fastqc (risk: medium)
2. 🟡 nfcore_multiqc (risk: medium)
3. 🟠 custom_processor (risk: high)

==================================================

What these tools can do:
  • Execute commands on your system
  • Access your data files
  • Make network requests (if not sandboxed)
  • Consume system resources

⚠️  WARNING: Local tools have NOT been verified by Galaxy ToolShed
   Please review tool source code before approving

==================================================

Approve installation of these tools? (yes/no/details):
```

---

## 🚀 Implementation Steps

### Phase 1: Immediate (Week 1) - CRITICAL

#### Step 1.1: Validate Current Tools
```bash
cd /home/yzhang/biomate

# Validate all nfcore_generated tools
python3 tool_install/fixes/tool_xml_validator.py \
    backend/tools/nfcore_generated/ \
    --pattern "*.xml" \
    > tool_validation_report.txt

# Review report
less tool_validation_report.txt
```

#### Step 1.2: Fix Vulnerable Tools
```bash
# Create backups directory
mkdir -p /home/yzhang/biomate/tool_backups_20251104

# Fix all vulnerable tools
python3 tool_install/fixes/fix_advanced_options.py \
    backend/tools/nfcore_generated/ \
    --backup-dir tool_backups_20251104 \
    --verbose

# Verify fixes
python3 tool_install/fixes/tool_xml_validator.py \
    backend/tools/nfcore_generated/fastqc.xml
```

#### Step 1.3: Replace Tool Installer
```bash
# Backup original installer
cp backend/lib/galaxy/ai/tool_auto_installer.py \
   backend/lib/galaxy/ai/tool_auto_installer.py.backup

# Copy secure installer dependencies
cp tool_install/fixes/tool_xml_validator.py \
   backend/lib/galaxy/ai/

cp tool_install/fixes/secure_tool_installer.py \
   backend/lib/galaxy/ai/
```

```python
# Update imports in enhanced_workflow_generator.py
# OLD:
from .tool_auto_installer import ToolAutoInstaller

# NEW:
from .secure_tool_installer import SecureToolInstaller as ToolAutoInstaller
```

#### Step 1.4: Add User Approval
```python
# Edit: backend/lib/galaxy/ai/enhanced_workflow_generator.py

# Add at top of file:
from .secure_workflow_generator_patch import request_tool_installation_approval

# Replace auto_install_workflow_tools method with secure version from:
# tool_install/fixes/secure_workflow_generator_patch.py
```

### Phase 2: Testing (Week 2)

#### Step 2.1: Run Security Tests
```bash
cd /home/yzhang/biomate/backend

# Run original security tests (should now FAIL as vulnerabilities are fixed)
.venv/bin/python -m pytest \
    ../tool_install/tests/test_tool_installation_security_20251104.py \
    -v

# Create new tests to verify fixes work
.venv/bin/python -m pytest \
    ../tool_install/tests/test_security_fixes_20251104.py \
    -v
```

#### Step 2.2: Manual Testing
```bash
# Test secure installer
cd /home/yzhang/biomate

python3 -c "
from tool_install.fixes.secure_tool_installer import SecureToolInstaller

installer = SecureToolInstaller(
    galaxy_root='backend/',
    require_user_approval=True,
    strict_validation=True
)

# This should request user approval and validate XML
success, msg = installer.install_tool('test_tool')
print(f'Result: {success}, {msg}')
"
```

#### Step 2.3: Integration Testing
```bash
# Test workflow generation with secure installer
cd /home/yzhang/biomate/backend

python3 << 'EOF'
from galaxy.ai.enhanced_workflow_generator import EnhancedWorkflowGenerator
from galaxy.ai.config import AIConfig
from galaxy.ai.types import UserRequest

config = AIConfig(
    anthropic_api_key="test",
    model="test"
)

generator = EnhancedWorkflowGenerator(
    config=config,
    galaxy_root="/home/yzhang/biomate/backend"
)

request = UserRequest(
    user_id="test_user",
    request_text="RNA-seq analysis"
)

# Should request user approval before installing any tools
result = generator.generate_workflow(request, auto_install_tools=True)
print("Workflow generated successfully!")
EOF
```

### Phase 3: Deployment (Week 3)

#### Step 3.1: Update Production Code
```bash
# Commit fixes to version control
git add tool_install/
git add backend/lib/galaxy/ai/tool_xml_validator.py
git add backend/lib/galaxy/ai/secure_tool_installer.py

git commit -m "fix(security): Add comprehensive security fixes for tool installation

- Add XML content validator with vulnerability detection
- Replace insecure tool installer with secure version
- Add user approval requirement for all installations
- Implement audit logging and rollback capability
- Fix command injection in all 1,632 nfcore_generated tools

Fixes: SECURITY-2025-001
See: tool_install/SECURITY_AUDIT_TOOL_INSTALLATION_20251104.md"
```

#### Step 3.2: Update Configuration
```yaml
# config/galaxy.yml

# Add security settings
tool_installation:
  require_user_approval: true
  strict_validation: true
  enable_audit_logging: true
  allow_local_tools: false  # Disable until reviewed
  allow_toolshed_only: true
```

#### Step 3.3: Deploy to Staging
```bash
# Deploy to staging environment
./deploy_staging.sh

# Run integration tests on staging
pytest test/integration/test_secure_tool_installation.py -v

# Monitor audit logs
tail -f database/tool_installation_audit.json
```

---

## 🧪 Testing Checklist

### Pre-Deployment Testing

- [ ] XML validator detects vulnerable tools
- [ ] XML validator passes safe tools
- [ ] XML fixer successfully repairs vulnerable tools
- [ ] Secure installer validates XML before installation
- [ ] Secure installer requests user approval
- [ ] Secure installer creates audit logs
- [ ] Secure installer creates backups
- [ ] Rollback capability works
- [ ] User can deny installation
- [ ] Workflow generator uses secure installer
- [ ] All original security tests now FAIL (vulnerabilities fixed)
- [ ] New tests verify fixes work correctly

### Performance Testing

- [ ] XML validation performance acceptable (<100ms per file)
- [ ] Batch fixing completes in reasonable time (~10 min for 1632 files)
- [ ] Installation with validation doesn't significantly slow workflow

### Security Testing

- [ ] Command injection no longer possible
- [ ] Malicious XML files are blocked
- [ ] User approval cannot be bypassed
- [ ] Audit logs are tamper-evident

---

## 📊 Verification

### Verify Fixes Are Applied

```bash
# Check that fastqc no longer has text-type advanced_options
grep -A 2 'name="advanced_options"' backend/tools/nfcore_generated/fastqc.xml

# Should show:
# <param name="advanced_options" type="select" multiple="true" optional="true">
#     <option value="--quiet">Quiet mode - minimal output</option>

# Count fixed files
grep -r 'name="advanced_options"' backend/tools/nfcore_generated/*.xml | \
    grep 'type="select"' | wc -l
# Should show: 1632

# Validate a fixed tool
python3 tool_install/fixes/tool_xml_validator.py \
    backend/tools/nfcore_generated/fastqc.xml
# Should show: ✅ PASSED or only minor warnings
```

### Verify Secure Installer Is Active

```bash
# Check that imports use secure version
grep -r "SecureToolInstaller" backend/lib/galaxy/ai/*.py

# Should show imports in:
# - enhanced_workflow_generator.py
# - or aliased as ToolAutoInstaller
```

### Verify Audit Logging Works

```bash
# Check audit log exists and has entries
ls -lh backend/database/tool_installation_audit.json

# View recent audit events
tail -50 backend/database/tool_installation_audit.json | jq '.'
```

---

## 🔧 Troubleshooting

### Issue: XML Validator Fails to Import

**Error:**
```
ModuleNotFoundError: No module named 'tool_xml_validator'
```

**Fix:**
```bash
# Ensure validator is in Python path
export PYTHONPATH="/home/yzhang/biomate/tool_install/fixes:$PYTHONPATH"

# Or copy to appropriate location
cp tool_install/fixes/tool_xml_validator.py backend/lib/galaxy/ai/
```

### Issue: User Approval Blocks Automated Tests

**Error:**
```
Tests hang waiting for user input
```

**Fix:**
```python
# For automated tests, skip approval:
installer = SecureToolInstaller(
    galaxy_root=galaxy_root,
    require_user_approval=False  # For tests only!
)

# Or use environment variable
if os.getenv('BIOMATE_TEST_MODE'):
    require_user_approval = False
```

### Issue: Too Many False Positives in Validator

**Error:**
```
Validator blocks legitimate tools
```

**Fix:**
```python
# Use lenient mode
validator = ToolXMLValidator(strict_mode=False)

# Or configure allowed patterns
validator.ALLOWED_PATTERNS = ['curl --safe-url-only']
```

---

## 📈 Metrics & Monitoring

### Key Metrics to Track

1. **Installation Success Rate**
   ```bash
   # From audit log
   jq '.events[] | select(.event_type=="install_success")' \
       database/tool_installation_audit.json | wc -l
   ```

2. **User Approval Rate**
   ```bash
   # From audit log
   jq '.events[] | select(.event_type=="user_approval") | .details.decision' \
       database/tool_installation_audit.json | sort | uniq -c
   ```

3. **Security Blocks**
   ```bash
   # From audit log
   jq '.events[] | select(.event_type=="install_blocked")' \
       database/tool_installation_audit.json | wc -l
   ```

4. **Validation Performance**
   ```bash
   # Time 100 validations
   time for i in {1..100}; do
       python3 tool_install/fixes/tool_xml_validator.py \
           backend/tools/nfcore_generated/fastqc.xml > /dev/null
   done
   ```

---

## 🎓 Training Materials

### For Developers

**Required Reading:**
- `docs/SECURITY_QUICK_REFERENCE_20251104.md`
- `docs/SECURITY_AUDIT_TOOL_INSTALLATION_20251104.md` (Sections 1-3)

**Training Topics:**
1. Secure coding practices for tool development
2. Input validation techniques
3. Using the XML validator
4. Security review process

### For Users

**User Guide:**
- What to look for when approving tool installation
- Understanding security warnings
- When to approve vs reject
- How to report suspicious tools

---

## 📞 Support

### Issues During Implementation

- **Technical Questions:** dev@biomate.ai
- **Security Concerns:** security@biomate.ai
- **Bug Reports:** GitHub Issues (private repo)

### Emergency Contacts

- **Security Incidents:** security-emergency@biomate.ai
- **Production Issues:** oncall@biomate.ai

---

## ✅ Sign-Off Checklist

Before marking implementation complete:

- [ ] All 1,632 vulnerable tools fixed
- [ ] XML validator integrated and working
- [ ] Secure installer deployed
- [ ] User approval system active
- [ ] Audit logging enabled
- [ ] All tests passing
- [ ] Security team review complete
- [ ] Documentation updated
- [ ] Training materials provided
- [ ] Rollback plan documented
- [ ] Monitoring dashboards configured

---

**Document Version:** 1.0
**Last Updated:** November 4, 2025
**Next Review:** After Phase 2 completion
