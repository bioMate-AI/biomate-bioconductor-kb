"""
Secure Tool Auto-Installer with Validation

Enhanced version of ToolAutoInstaller with security validations:
- XML content validation before installation
- User approval requirements
- Digital signature verification (placeholder for future)
- Comprehensive audit logging
- Rollback capability
"""

import os
import json
import logging
import shutil
import hashlib
from pathlib import Path
from typing import Dict, List, Optional, Tuple
from datetime import datetime
from dataclasses import dataclass, asdict

from tool_xml_validator import ToolXMLValidator, SecurityLevel

log = logging.getLogger(__name__)


@dataclass
class InstallationRecord:
    """Record of a tool installation for audit trail."""
    tool_id: str
    installed_at: str
    source_file: str
    target_file: str
    file_hash: str
    validation_passed: bool
    security_issues: List[Dict]
    installed_by: str = "system"
    user_approved: bool = False


class SecureToolInstaller:
    """
    Secure tool installer with comprehensive security validations.

    Features:
    - XML security validation before installation
    - User approval requirement
    - Audit logging
    - Rollback capability
    - Digital signature verification (future)
    """

    def __init__(self, galaxy_root: str, biomate_tools_root: str = None,
                 require_user_approval: bool = False, strict_validation: bool = True):
        """
        Initialize secure tool installer.

        Args:
            galaxy_root: Path to Galaxy installation root
            biomate_tools_root: Path to BioMate tools repository
            require_user_approval: If True, require user confirmation before install (default: False)
                                   Set to True for production or when manually reviewing tools
            strict_validation: If True, block tools with high severity issues (default: True)
        """
        self.galaxy_root = Path(galaxy_root)
        self.galaxy_tools_dir = self.galaxy_root / "tools" / "biomate_custom"
        self.tool_conf_file = self.galaxy_root / "config" / "tool_conf_biomate.xml"

        if biomate_tools_root is None:
            biomate_tools_root = Path(__file__).parent.parent.parent / "backend" / "tools"
        self.biomate_tools_root = Path(biomate_tools_root)

        self.require_user_approval = require_user_approval
        self.strict_validation = strict_validation

        # Security validator
        self.validator = ToolXMLValidator(strict_mode=strict_validation)

        # Audit log
        self.audit_log_file = self.galaxy_root / "database" / "tool_installation_audit.json"
        self.audit_log_file.parent.mkdir(parents=True, exist_ok=True)

        # Installation cache
        self.installed_tools_cache = self._load_installed_tools_cache()

    def _load_installed_tools_cache(self) -> Dict:
        """Load cache of already installed tools."""
        cache_file = self.galaxy_root / "database" / "biomate_installed_tools.json"

        if cache_file.exists():
            try:
                with open(cache_file) as f:
                    return json.load(f)
            except Exception as e:
                log.warning(f"Could not load installed tools cache: {e}")

        return {
            "installed_tools": [],
            "last_updated": None,
            "install_log": []
        }

    def _save_installed_tools_cache(self):
        """Save cache of installed tools."""
        cache_file = self.galaxy_root / "database" / "biomate_installed_tools.json"
        cache_file.parent.mkdir(parents=True, exist_ok=True)

        try:
            with open(cache_file, 'w') as f:
                json.dump(self.installed_tools_cache, f, indent=2)
        except Exception as e:
            log.error(f"Could not save installed tools cache: {e}")

    def _log_audit_event(self, event_type: str, details: Dict):
        """Log security audit event."""
        audit_entry = {
            "timestamp": datetime.now().isoformat(),
            "event_type": event_type,
            "details": details
        }

        try:
            # Load existing audit log
            if self.audit_log_file.exists():
                with open(self.audit_log_file) as f:
                    audit_log = json.load(f)
            else:
                audit_log = {"events": []}

            # Append new event
            audit_log["events"].append(audit_entry)

            # Save updated log
            with open(self.audit_log_file, 'w') as f:
                json.dump(audit_log, f, indent=2)

            log.info(f"Audit event logged: {event_type}")
        except Exception as e:
            log.error(f"Failed to log audit event: {e}")

    def _calculate_file_hash(self, file_path: Path) -> str:
        """Calculate SHA256 hash of file for integrity verification."""
        sha256 = hashlib.sha256()
        with open(file_path, 'rb') as f:
            for chunk in iter(lambda: f.read(4096), b''):
                sha256.update(chunk)
        return sha256.hexdigest()

    def validate_tool_xml(self, xml_path: Path) -> Tuple[bool, List, str]:
        """
        Validate tool XML for security issues.

        Args:
            xml_path: Path to tool XML file

        Returns:
            Tuple of (is_safe, issues, report)
        """
        is_safe, issues = self.validator.validate_file(xml_path)
        report = self.validator.generate_report(issues)

        # Log validation event
        self._log_audit_event("xml_validation", {
            "file": str(xml_path),
            "is_safe": is_safe,
            "issue_count": len(issues),
            "critical_count": sum(1 for i in issues if i.level == SecurityLevel.CRITICAL),
            "high_count": sum(1 for i in issues if i.level == SecurityLevel.HIGH)
        })

        return is_safe, issues, report

    def request_user_approval(self, tool_id: str, xml_path: Path, validation_report: str) -> bool:
        """
        Request user approval for tool installation.

        Args:
            tool_id: Tool ID to install
            xml_path: Path to tool XML
            validation_report: Security validation report

        Returns:
            True if user approves, False otherwise

        Note: Approval is optional and disabled by default.
              Enable with require_user_approval=True when:
              - Installing tools manually
              - In production environments
              - When reviewing new/untrusted tools
        """
        if not self.require_user_approval:
            log.debug(f"User approval not required for {tool_id} (automatic mode)")
            return True

        print("\n" + "=" * 70)
        print("🔐 TOOL INSTALLATION APPROVAL REQUEST")
        print("=" * 70)
        print(f"\nTool ID: {tool_id}")
        print(f"Source: {xml_path}")
        print(f"\n{validation_report}\n")
        print("=" * 70)

        while True:
            response = input("\nApprove installation? (yes/no/details): ").strip().lower()

            if response == "yes":
                log.info(f"User approved installation of {tool_id}")
                self._log_audit_event("user_approval", {
                    "tool_id": tool_id,
                    "decision": "approved",
                    "xml_path": str(xml_path)
                })
                return True

            elif response == "no":
                log.info(f"User rejected installation of {tool_id}")
                self._log_audit_event("user_approval", {
                    "tool_id": tool_id,
                    "decision": "rejected",
                    "xml_path": str(xml_path)
                })
                return False

            elif response == "details":
                # Show more details
                print(f"\n📄 Tool XML content preview:")
                try:
                    with open(xml_path) as f:
                        lines = f.readlines()[:50]  # First 50 lines
                        print("".join(lines))
                        if len(f.readlines()) > 50:
                            print(f"\n... ({len(f.readlines())} more lines)")
                except Exception as e:
                    print(f"Error reading file: {e}")
                print()

            else:
                print("Please enter 'yes', 'no', or 'details'")

    def install_tool(self, tool_id: str, force: bool = False,
                    skip_approval: bool = False) -> Tuple[bool, str]:
        """
        Install a single tool with security validation.

        Args:
            tool_id: Galaxy tool ID to install
            force: Force reinstall even if already installed
            skip_approval: Skip user approval (use with caution!)

        Returns:
            Tuple of (success, message)
        """
        # Check if already installed
        if not force and tool_id in self.installed_tools_cache["installed_tools"]:
            return True, f"Tool {tool_id} already installed"

        log.info(f"🔐 Secure installation initiated for: {tool_id}")

        # Find tool in BioMate repository
        source_file = self._find_tool_in_biomate_repo(tool_id)

        if not source_file:
            msg = f"Tool {tool_id} not found in BioMate repository"
            log.error(msg)
            self._log_audit_event("install_failed", {
                "tool_id": tool_id,
                "reason": "not_found"
            })
            return False, msg

        # SECURITY: Validate XML content
        log.info(f"Validating XML security for {tool_id}...")
        is_safe, issues, report = self.validate_tool_xml(source_file)

        # Log validation event
        self._log_audit_event("xml_validation_complete", {
            "tool_id": tool_id,
            "source_file": str(source_file),
            "is_safe": is_safe,
            "issue_count": len(issues),
            "critical_count": sum(1 for i in issues if i.level == SecurityLevel.CRITICAL),
            "high_count": sum(1 for i in issues if i.level == SecurityLevel.HIGH)
        })

        if not is_safe:
            msg = f"Security validation FAILED for {tool_id}"
            log.error(msg)
            log.error(report)

            self._log_audit_event("install_blocked", {
                "tool_id": tool_id,
                "reason": "security_validation_failed",
                "source_file": str(source_file),
                "issues": [asdict(issue) for issue in issues]
            })

            return False, f"{msg}\n\nSecurity Report:\n{report}"

        # Calculate file hash for integrity
        file_hash = self._calculate_file_hash(source_file)

        # SECURITY: Request user approval
        if not skip_approval:
            user_approved = self.request_user_approval(tool_id, source_file, report)

            if not user_approved:
                msg = f"Installation of {tool_id} rejected by user"
                log.info(msg)
                return False, msg
        else:
            user_approved = False  # Mark as not explicitly approved

        # Determine target directory
        target_dir = self._get_target_directory(tool_id)
        target_dir.mkdir(parents=True, exist_ok=True)

        # Create backup directory
        backup_dir = self.galaxy_root / "database" / "tool_backups"
        backup_dir.mkdir(parents=True, exist_ok=True)

        # Copy tool file
        target_file = target_dir / source_file.name

        # Backup existing file if it exists
        if target_file.exists():
            backup_file = backup_dir / f"{tool_id}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xml"
            shutil.copy2(target_file, backup_file)
            log.info(f"Backed up existing tool to {backup_file}")

        try:
            shutil.copy2(source_file, target_file)
            log.info(f"✅ Copied {source_file} to {target_file}")
        except Exception as e:
            msg = f"Failed to copy tool file: {e}"
            log.error(msg)

            self._log_audit_event("install_failed", {
                "tool_id": tool_id,
                "reason": "copy_failed",
                "error": str(e)
            })

            return False, msg

        # Update tool configuration
        success, msg = self._update_tool_conf(tool_id, target_file)

        if not success:
            # Rollback: delete copied file
            target_file.unlink()
            log.warning(f"Rolled back installation due to config update failure")
            return False, msg

        # Create installation record
        install_record = InstallationRecord(
            tool_id=tool_id,
            installed_at=datetime.now().isoformat(),
            source_file=str(source_file),
            target_file=str(target_file),
            file_hash=file_hash,
            validation_passed=is_safe,
            security_issues=[asdict(issue) for issue in issues],
            user_approved=user_approved
        )

        # Update cache
        self.installed_tools_cache["installed_tools"].append(tool_id)
        self.installed_tools_cache["last_updated"] = datetime.now().isoformat()
        self.installed_tools_cache["install_log"].append(asdict(install_record))
        self._save_installed_tools_cache()

        # Log successful installation
        self._log_audit_event("install_success", asdict(install_record))

        log.info(f"✅ Successfully installed tool: {tool_id}")
        return True, f"Tool {tool_id} installed successfully"

    def is_tool_installed(self, tool_id: str) -> bool:
        """
        Check if a tool is already installed.

        Args:
            tool_id: Galaxy tool ID

        Returns:
            True if tool is installed, False otherwise
        """
        # Check cache first
        if tool_id in self.installed_tools_cache["installed_tools"]:
            return True

        # Check if tool file exists
        tool_file = self._find_tool_file(tool_id)
        if tool_file and tool_file.exists():
            # Add to cache
            self.installed_tools_cache["installed_tools"].append(tool_id)
            self._save_installed_tools_cache()
            return True

        return False

    def _find_tool_file(self, tool_id: str) -> Optional[Path]:
        """Find the XML file for an installed tool ID."""
        # Search in all tool directories
        if not self.galaxy_tools_dir.exists():
            return None

        for tool_dir in self.galaxy_tools_dir.glob("*"):
            if not tool_dir.is_dir():
                continue

            # Try exact match
            xml_file = tool_dir / f"{tool_id}.xml"
            if xml_file.exists():
                return xml_file

            # Try without prefix
            for prefix in ["nfcore_", "biomni_"]:
                if tool_id.startswith(prefix):
                    unprefixed_id = tool_id[len(prefix):]
                    xml_file = tool_dir / f"{unprefixed_id}.xml"
                    if xml_file.exists():
                        return xml_file

        return None

    def _find_tool_in_biomate_repo(self, tool_id: str) -> Optional[Path]:
        """Find tool XML file in BioMate repository."""
        if not self.biomate_tools_root.exists():
            return None

        # First try direct file in root
        xml_file = self.biomate_tools_root / f"{tool_id}.xml"
        if xml_file.exists():
            return xml_file

        # Search in all subdirectories
        for tool_dir in self.biomate_tools_root.glob("*"):
            if not tool_dir.is_dir():
                continue

            # Try exact match
            xml_file = tool_dir / f"{tool_id}.xml"
            if xml_file.exists():
                return xml_file

            # Try with/without common prefixes
            for prefix in ["", "nfcore_", "biomni_"]:
                test_id = f"{prefix}{tool_id}" if prefix else tool_id
                xml_file = tool_dir / f"{test_id}.xml"
                if xml_file.exists():
                    return xml_file

                # Also try removing prefix
                if tool_id.startswith(prefix) and prefix:
                    unprefixed_id = tool_id[len(prefix):]
                    xml_file = tool_dir / f"{unprefixed_id}.xml"
                    if xml_file.exists():
                        return xml_file

        return None

    def _get_target_directory(self, tool_id: str) -> Path:
        """Determine target directory for a tool based on its category."""
        # Default categorization based on tool_id
        if any(term in tool_id.lower() for term in ["openms", "diann", "maxquant", "proteomics"]):
            return self.galaxy_tools_dir / "nfcore_lcms"
        elif any(term in tool_id.lower() for term in ["rdkit", "openmm", "cellpose", "python", "cobra"]):
            return self.galaxy_tools_dir / "biomni_missing"
        else:
            return self.galaxy_tools_dir / "nfcore_general"

    def _update_tool_conf(self, tool_id: str, tool_file: Path) -> Tuple[bool, str]:
        """Update tool_conf_biomate.xml to include newly installed tool."""
        try:
            # Get relative path from Galaxy root
            rel_path = tool_file.relative_to(self.galaxy_root / "tools")

            # Read existing config
            if self.tool_conf_file.exists():
                with open(self.tool_conf_file) as f:
                    config_lines = f.readlines()
            else:
                # Create new config file
                config_lines = [
                    '<?xml version="1.0" encoding="utf-8"?>\n',
                    '<toolbox>\n',
                    '  <!-- BioMate Custom Tools - Auto-generated -->\n',
                    '</toolbox>\n'
                ]

            # Check if tool already in config
            tool_entry = f'<tool file="{rel_path}"/>'
            if any(tool_entry in line for line in config_lines):
                return True, "Tool already in configuration"

            # Find appropriate section
            section_id = self._get_section_for_tool(tool_id)
            section_found = False
            insert_index = -1

            for i, line in enumerate(config_lines):
                if f'id="{section_id}"' in line:
                    section_found = True
                if section_found and '</section>' in line:
                    insert_index = i
                    break

            # If section not found, create it
            if not section_found:
                insert_index = len(config_lines) - 1  # Before </toolbox>
                section_name = self._get_section_name(section_id)
                config_lines.insert(insert_index, f'  <section id="{section_id}" name="{section_name}">\n')
                insert_index += 1
                config_lines.insert(insert_index, f'  </section>\n')

            # Insert tool entry
            config_lines.insert(insert_index, f'    <tool file="{rel_path}"/>\n')

            # Write updated config
            self.tool_conf_file.parent.mkdir(parents=True, exist_ok=True)
            with open(self.tool_conf_file, 'w') as f:
                f.writelines(config_lines)

            log.info(f"Updated tool configuration: {self.tool_conf_file}")
            return True, "Tool configuration updated"

        except Exception as e:
            msg = f"Failed to update tool configuration: {e}"
            log.error(msg)
            return False, msg

    def _get_section_for_tool(self, tool_id: str) -> str:
        """Get tool section ID based on tool_id."""
        if any(term in tool_id.lower() for term in ["openms", "diann", "maxquant", "proteomics"]):
            return "biomate_nfcore_lcms"
        elif any(term in tool_id.lower() for term in ["rdkit", "openmm", "cellpose", "cobra"]):
            return "biomate_biomni_missing"
        else:
            return "biomate_nfcore_general"

    def _get_section_name(self, section_id: str) -> str:
        """Get human-readable section name."""
        section_names = {
            "biomate_nfcore_lcms": "nf-core LC-MS Tools (Secure)",
            "biomate_nfcore_general": "nf-core General Tools (Secure)",
            "biomate_biomni_missing": "BioMni Python/R Tools (Secure)",
        }
        return section_names.get(section_id, "BioMate Custom Tools (Secure)")

    def get_installation_history(self) -> List[InstallationRecord]:
        """Get history of all tool installations."""
        records = []
        for record_dict in self.installed_tools_cache.get("install_log", []):
            try:
                record = InstallationRecord(**record_dict)
                records.append(record)
            except Exception as e:
                log.warning(f"Could not parse installation record: {e}")
        return records

    def rollback_installation(self, tool_id: str) -> Tuple[bool, str]:
        """
        Rollback a tool installation.

        Args:
            tool_id: Tool ID to rollback

        Returns:
            Tuple of (success, message)
        """
        # Find installation record
        install_log = self.installed_tools_cache.get("install_log", [])
        record = None

        for rec in install_log:
            if rec.get("tool_id") == tool_id:
                record = rec
                break

        if not record:
            return False, f"No installation record found for {tool_id}"

        target_file = Path(record["target_file"])

        if not target_file.exists():
            return False, f"Tool file not found: {target_file}"

        try:
            # Delete tool file
            target_file.unlink()
            log.info(f"Deleted tool file: {target_file}")

            # Remove from cache
            if tool_id in self.installed_tools_cache["installed_tools"]:
                self.installed_tools_cache["installed_tools"].remove(tool_id)

            # Remove from install log
            self.installed_tools_cache["install_log"] = [
                r for r in install_log if r.get("tool_id") != tool_id
            ]

            self._save_installed_tools_cache()

            # Log rollback
            self._log_audit_event("rollback", {
                "tool_id": tool_id,
                "target_file": str(target_file)
            })

            msg = f"Successfully rolled back installation of {tool_id}"
            log.info(msg)
            return True, msg

        except Exception as e:
            msg = f"Failed to rollback {tool_id}: {e}"
            log.error(msg)
            return False, msg


if __name__ == "__main__":
    import sys

    # Example usage
    if len(sys.argv) < 3:
        print("Usage: python secure_tool_installer.py <galaxy_root> <tool_id>")
        sys.exit(1)

    galaxy_root = sys.argv[1]
    tool_id = sys.argv[2]

    installer = SecureToolInstaller(
        galaxy_root=galaxy_root,
        require_user_approval=True,
        strict_validation=True
    )

    success, message = installer.install_tool(tool_id)

    print(f"\n{'✅ SUCCESS' if success else '❌ FAILED'}: {message}")

    sys.exit(0 if success else 1)
