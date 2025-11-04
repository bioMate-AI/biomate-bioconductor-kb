# Tool Installation Configuration Guide

## Quick Start

By default, tools are installed **automatically without user approval**. This is ideal for:
- Development workflows
- Automated testing
- CI/CD pipelines
- Batch processing

User approval can be easily enabled when needed (e.g., production, manual reviews).

---

## Configuration Methods

### Method 1: Direct Parameter (Recommended)

```python
from tool_install.fixes.secure_tool_installer import SecureToolInstaller

# Automatic installation (default)
installer = SecureToolInstaller(
    galaxy_root="/path/to/galaxy",
    require_user_approval=False  # Default, can omit
)

# With user approval (for production)
installer = SecureToolInstaller(
    galaxy_root="/path/to/galaxy",
    require_user_approval=True   # Enable when needed
)
```

### Method 2: Configuration Object

```python
from tool_install.fixes.config import ToolInstallationConfig
from tool_install.fixes.secure_tool_installer import SecureToolInstaller

# Development mode (automatic)
config = ToolInstallationConfig.development()

# Production mode (requires approval)
config = ToolInstallationConfig.production()

# Use config
installer = SecureToolInstaller(
    galaxy_root="/path/to/galaxy",
    require_user_approval=config.require_user_approval
)
```

### Method 3: Environment Variables

```bash
# Enable user approval via environment variable
export BIOMATE_REQUIRE_TOOL_APPROVAL=true

# In production .env file
BIOMATE_REQUIRE_TOOL_APPROVAL=true
BIOMATE_STRICT_VALIDATION=true
```

```python
from tool_install.fixes.config import ToolInstallationConfig

config = ToolInstallationConfig.from_env()
installer = SecureToolInstaller(
    galaxy_root="/path/to/galaxy",
    require_user_approval=config.require_user_approval
)
```

### Method 4: Runtime Toggle

```python
from tool_install.fixes.config import enable_user_approval, disable_user_approval

# Start with automatic installation
installer = SecureToolInstaller(galaxy_root="/path")

# Later, enable approval for specific operations
enable_user_approval()
installer.install_tool("sensitive_tool")  # Will request approval

# Disable again
disable_user_approval()
installer.install_tool("regular_tool")  # Automatic
```

---

## Configuration Options

### Full Configuration

```python
from tool_install.fixes.config import ToolInstallationConfig

config = ToolInstallationConfig(
    # XML Validation
    enable_xml_validation=True,      # Validate XML before install
    strict_validation=True,           # Block high-severity issues

    # User Approval
    require_user_approval=False,      # Require manual approval (default: False)
    require_approval_for_local_tools=False,
    require_approval_for_toolshed=False,

    # Audit Logging
    enable_audit_logging=True,        # Log all installations
    audit_log_path=None,              # Custom log path

    # Backups
    create_backups=True,              # Backup before install
    backup_retention_days=30,

    # File Integrity
    verify_file_integrity=True,       # SHA256 verification

    # Rollback
    enable_rollback=True,             # Enable rollback capability
)
```

---

## Preset Configurations

### Development (Default)
**Best for:** Local development, automated workflows

```python
config = ToolInstallationConfig.development()
```

- ✅ XML validation enabled
- ✅ Strict validation
- ❌ User approval disabled (automatic)
- ✅ Audit logging enabled
- ✅ Backups enabled

### Production
**Best for:** Production environments, manual reviews

```python
config = ToolInstallationConfig.production()
```

- ✅ XML validation enabled
- ✅ Strict validation
- ✅ User approval **REQUIRED**
- ✅ Audit logging enabled
- ✅ Backups enabled
- ✅ All security features maximized

### Testing
**Best for:** Automated tests, CI/CD

```python
config = ToolInstallationConfig.testing()
```

- ✅ XML validation enabled
- ⚠️ Lenient validation (warnings allowed)
- ❌ User approval disabled
- ❌ Audit logging disabled (reduce noise)
- ❌ Backups disabled (faster)

---

## Usage Examples

### Example 1: Development Workflow (Default)

```python
# Automatic installation - no approval needed
from tool_install.fixes.secure_tool_installer import SecureToolInstaller

installer = SecureToolInstaller(galaxy_root="/home/yzhang/biomate/backend")

# Install multiple tools automatically
for tool_id in ["fastqc", "multiqc", "samtools"]:
    success, msg = installer.install_tool(tool_id)
    print(f"{tool_id}: {msg}")

# Output:
# fastqc: Tool fastqc installed successfully
# multiqc: Tool multiqc installed successfully
# samtools: Tool samtools installed successfully
```

### Example 2: Production with Approval

```python
# Require approval for production
installer = SecureToolInstaller(
    galaxy_root="/production/galaxy",
    require_user_approval=True  # Enable approval
)

# User will be prompted
success, msg = installer.install_tool("new_tool")

# Output:
# ==================================================
# 🔐 TOOL INSTALLATION APPROVAL REQUEST
# ==================================================
#
# Tool ID: new_tool
# Source: /path/to/new_tool.xml
#
# Security Report:
# ✅ PASSED: No critical issues
#
# Approve installation? (yes/no/details): _
```

### Example 3: Automated Workflow with Selective Approval

```python
installer = SecureToolInstaller(galaxy_root="/path")

# Install trusted tools automatically
trusted_tools = ["fastqc", "multiqc"]
for tool in trusted_tools:
    installer.install_tool(tool, skip_approval=True)

# Request approval for new/untrusted tools
untrusted_tools = ["custom_analyzer"]
installer.require_user_approval = True  # Enable approval
for tool in untrusted_tools:
    installer.install_tool(tool)
installer.require_user_approval = False  # Disable again
```

### Example 4: Environment-Based Configuration

```bash
# .env.production
BIOMATE_REQUIRE_TOOL_APPROVAL=true
BIOMATE_STRICT_VALIDATION=true

# .env.development
BIOMATE_REQUIRE_TOOL_APPROVAL=false
BIOMATE_STRICT_VALIDATION=true

# .env.testing
BIOMATE_REQUIRE_TOOL_APPROVAL=false
BIOMATE_STRICT_VALIDATION=false
BIOMATE_ENABLE_AUDIT_LOG=false
```

```python
# Load from environment
from tool_install.fixes.config import ToolInstallationConfig

config = ToolInstallationConfig.from_env()

installer = SecureToolInstaller(
    galaxy_root="/path",
    require_user_approval=config.require_user_approval,
    strict_validation=config.strict_validation
)
```

---

## When to Enable User Approval

### Enable Approval For:
- ✅ Production environments
- ✅ Installing untrusted/new tools
- ✅ Manual security reviews
- ✅ Compliance requirements
- ✅ Tools with high-risk patterns
- ✅ First-time tool installation

### Keep Automatic For:
- ✅ Development workflows
- ✅ Automated testing
- ✅ CI/CD pipelines
- ✅ Trusted tools
- ✅ Batch processing
- ✅ Tools from Galaxy ToolShed

---

## Security Features (Always Active)

These security features are **always active** regardless of approval settings:

1. ✅ **XML Validation** - All tools validated before installation
2. ✅ **Dangerous Pattern Detection** - curl, wget, rm -rf, etc. detected
3. ✅ **Audit Logging** - All installations logged
4. ✅ **Automatic Backups** - Files backed up before modification
5. ✅ **File Integrity** - SHA256 hashing
6. ✅ **Rollback Capability** - Can undo installations

**User approval is just an optional additional layer for extra security.**

---

## Environment Variables Reference

| Variable | Default | Description |
|----------|---------|-------------|
| `BIOMATE_REQUIRE_TOOL_APPROVAL` | `false` | Require user approval before installation |
| `BIOMATE_STRICT_VALIDATION` | `true` | Block tools with high-severity issues |
| `BIOMATE_ENABLE_XML_VALIDATION` | `true` | Validate XML before installation |
| `BIOMATE_ENABLE_AUDIT_LOG` | `true` | Enable audit logging |
| `BIOMATE_CREATE_BACKUPS` | `true` | Create backups before installation |
| `BIOMATE_VERIFY_INTEGRITY` | `true` | Verify file integrity (SHA256) |
| `BIOMATE_ENABLE_ROLLBACK` | `true` | Enable rollback capability |
| `BIOMATE_AUDIT_LOG_PATH` | `None` | Custom audit log path |

---

## Migration from Old Code

### Before (Insecure)
```python
from galaxy.ai.tool_auto_installer import ToolAutoInstaller

# Old insecure installer
installer = ToolAutoInstaller(galaxy_root="/path")
installer.install_tool("tool_id")  # No validation, no approval
```

### After (Secure, Automatic)
```python
from tool_install.fixes.secure_tool_installer import SecureToolInstaller

# New secure installer (automatic mode)
installer = SecureToolInstaller(galaxy_root="/path")
installer.install_tool("tool_id")  # Validated, automatic, logged
```

### After (Secure, with Approval)
```python
from tool_install.fixes.secure_tool_installer import SecureToolInstaller

# New secure installer (approval mode)
installer = SecureToolInstaller(
    galaxy_root="/path",
    require_user_approval=True  # Add this line when needed
)
installer.install_tool("tool_id")  # Validated, requires approval, logged
```

---

## Summary

**Default Behavior:** Automatic installation with comprehensive security validation
- ✅ XML validation always active
- ✅ Audit logging always active
- ✅ Backups always created
- ❌ User approval disabled (can be enabled anytime)

**To Enable Approval:**
```python
# Option 1: Constructor parameter
installer = SecureToolInstaller(galaxy_root="/path", require_user_approval=True)

# Option 2: Runtime toggle
from tool_install.fixes.config import enable_user_approval
enable_user_approval()

# Option 3: Environment variable
export BIOMATE_REQUIRE_TOOL_APPROVAL=true

# Option 4: Use production config
from tool_install.fixes.config import ToolInstallationConfig
config = ToolInstallationConfig.production()
```

**Best Practice:**
- Use automatic mode for development and testing
- Enable approval for production and manual reviews
- All security features remain active regardless of approval setting

---

**Document Version:** 1.0
**Last Updated:** November 4, 2025
