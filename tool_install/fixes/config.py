"""
Configuration for Secure Tool Installation

Centralized configuration to easily toggle security features.
"""

import os
from dataclasses import dataclass
from typing import Optional


@dataclass
class ToolInstallationConfig:
    """Configuration for tool installation security settings."""

    # XML Validation
    enable_xml_validation: bool = True
    strict_validation: bool = True  # Block high-severity issues

    # User Approval
    require_user_approval: bool = False  # Default: automatic installation
    require_approval_for_local_tools: bool = False
    require_approval_for_toolshed: bool = False

    # Audit Logging
    enable_audit_logging: bool = True
    audit_log_path: Optional[str] = None

    # Backups
    create_backups: bool = True
    backup_retention_days: int = 30

    # File Integrity
    verify_file_integrity: bool = True  # SHA256 hashing

    # Rollback
    enable_rollback: bool = True

    @classmethod
    def from_env(cls) -> 'ToolInstallationConfig':
        """
        Load configuration from environment variables.

        Environment variables:
        - BIOMATE_REQUIRE_TOOL_APPROVAL: Set to 'true' to require user approval
        - BIOMATE_STRICT_VALIDATION: Set to 'false' to allow warnings
        - BIOMATE_ENABLE_AUDIT_LOG: Set to 'false' to disable audit logging
        """
        return cls(
            enable_xml_validation=os.getenv('BIOMATE_ENABLE_XML_VALIDATION', 'true').lower() == 'true',
            strict_validation=os.getenv('BIOMATE_STRICT_VALIDATION', 'true').lower() == 'true',
            require_user_approval=os.getenv('BIOMATE_REQUIRE_TOOL_APPROVAL', 'false').lower() == 'true',
            enable_audit_logging=os.getenv('BIOMATE_ENABLE_AUDIT_LOG', 'true').lower() == 'true',
            create_backups=os.getenv('BIOMATE_CREATE_BACKUPS', 'true').lower() == 'true',
            verify_file_integrity=os.getenv('BIOMATE_VERIFY_INTEGRITY', 'true').lower() == 'true',
            enable_rollback=os.getenv('BIOMATE_ENABLE_ROLLBACK', 'true').lower() == 'true',
            audit_log_path=os.getenv('BIOMATE_AUDIT_LOG_PATH'),
        )

    @classmethod
    def production(cls) -> 'ToolInstallationConfig':
        """Production configuration with maximum security."""
        return cls(
            enable_xml_validation=True,
            strict_validation=True,
            require_user_approval=True,  # Require approval in production
            require_approval_for_local_tools=True,
            enable_audit_logging=True,
            create_backups=True,
            verify_file_integrity=True,
            enable_rollback=True,
        )

    @classmethod
    def development(cls) -> 'ToolInstallationConfig':
        """Development configuration with automatic installation."""
        return cls(
            enable_xml_validation=True,
            strict_validation=True,
            require_user_approval=False,  # Automatic in dev
            enable_audit_logging=True,
            create_backups=True,
            verify_file_integrity=True,
            enable_rollback=True,
        )

    @classmethod
    def testing(cls) -> 'ToolInstallationConfig':
        """Testing configuration with minimal friction."""
        return cls(
            enable_xml_validation=True,
            strict_validation=False,  # Allow warnings in tests
            require_user_approval=False,
            enable_audit_logging=False,  # Reduce noise in tests
            create_backups=False,
            verify_file_integrity=False,
            enable_rollback=True,
        )


# Default configuration (development mode - automatic installation)
DEFAULT_CONFIG = ToolInstallationConfig.development()


# Quick access functions
def enable_user_approval():
    """Enable user approval for tool installation."""
    DEFAULT_CONFIG.require_user_approval = True
    print("✅ User approval enabled for tool installation")


def disable_user_approval():
    """Disable user approval for tool installation (automatic mode)."""
    DEFAULT_CONFIG.require_user_approval = False
    print("✅ Automatic tool installation enabled (no approval required)")


def use_production_config():
    """Switch to production configuration."""
    global DEFAULT_CONFIG
    DEFAULT_CONFIG = ToolInstallationConfig.production()
    print("✅ Using production configuration (approval required)")


def use_development_config():
    """Switch to development configuration."""
    global DEFAULT_CONFIG
    DEFAULT_CONFIG = ToolInstallationConfig.development()
    print("✅ Using development configuration (automatic installation)")


# Example usage in code:
"""
from tool_install.fixes.config import ToolInstallationConfig, enable_user_approval

# Use default (automatic installation)
installer = SecureToolInstaller(galaxy_root="/path")

# Enable approval when needed
enable_user_approval()

# Or use specific config
config = ToolInstallationConfig.production()
installer = SecureToolInstaller(
    galaxy_root="/path",
    require_user_approval=config.require_user_approval
)

# Or from environment variables
config = ToolInstallationConfig.from_env()
"""


# Example environment variable configuration:
"""
# .env file for production
BIOMATE_REQUIRE_TOOL_APPROVAL=true
BIOMATE_STRICT_VALIDATION=true
BIOMATE_ENABLE_AUDIT_LOG=true

# .env file for development
BIOMATE_REQUIRE_TOOL_APPROVAL=false
BIOMATE_STRICT_VALIDATION=true
BIOMATE_ENABLE_AUDIT_LOG=true

# .env file for testing
BIOMATE_REQUIRE_TOOL_APPROVAL=false
BIOMATE_STRICT_VALIDATION=false
BIOMATE_ENABLE_AUDIT_LOG=false
"""
