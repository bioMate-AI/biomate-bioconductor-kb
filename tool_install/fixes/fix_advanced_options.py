"""
Fix Advanced Options Vulnerability

Automatically fixes the command injection vulnerability in tool XML files
by replacing free-text advanced_options with safe select-based options.
"""

import xml.etree.ElementTree as ET
from pathlib import Path
from typing import List, Tuple, Dict
import argparse
import logging
from datetime import datetime

log = logging.getLogger(__name__)


class AdvancedOptionsFixer:
    """
    Fixes command injection vulnerability in tool XML files.

    Replaces:
        <param name="advanced_options" type="text" .../>
        $advanced_options

    With:
        <param name="advanced_options" type="select" multiple="true" ...>
            <option value="--quiet">Quiet mode</option>
            <option value="--verbose">Verbose mode</option>
            ...
        </param>
        #for $option in $advanced_options
            $option
        #end for
    """

    # Common safe options for bioinformatics tools
    SAFE_OPTIONS = [
        ("--quiet", "Quiet mode - minimal output"),
        ("--verbose", "Verbose mode - detailed output"),
        ("--no-progress", "Disable progress indicator"),
        ("--no-color", "Disable colored output"),
        ("--help", "Show help message"),
    ]

    def __init__(self, backup_dir: Path = None):
        """
        Initialize fixer.

        Args:
            backup_dir: Directory to store backups (default: ./backups)
        """
        self.backup_dir = backup_dir or Path("./backups")
        self.backup_dir.mkdir(parents=True, exist_ok=True)

        self.stats = {
            "files_processed": 0,
            "files_fixed": 0,
            "files_skipped": 0,
            "errors": 0
        }

    def fix_file(self, xml_path: Path, dry_run: bool = False) -> Tuple[bool, str]:
        """
        Fix a single XML file.

        Args:
            xml_path: Path to tool XML file
            dry_run: If True, don't actually modify file

        Returns:
            Tuple of (was_modified, message)
        """
        self.stats["files_processed"] += 1

        try:
            tree = ET.parse(xml_path)
            root = tree.getroot()
        except ET.ParseError as e:
            self.stats["errors"] += 1
            return False, f"XML parsing error: {e}"

        # Check if file has vulnerable advanced_options
        has_vulnerability = False
        params = root.findall('.//param[@name="advanced_options"][@type="text"]')

        if not params:
            self.stats["files_skipped"] += 1
            return False, "No vulnerable advanced_options found"

        has_vulnerability = True

        if dry_run:
            return True, "Would fix (dry run)"

        # Create backup
        backup_file = self.backup_dir / f"{xml_path.stem}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xml"
        tree.write(backup_file, encoding='unicode', xml_declaration=True)
        log.info(f"Backed up to: {backup_file}")

        # Fix each vulnerable parameter
        for param in params:
            self._fix_parameter(param)

        # Fix command section to use safe iteration
        command = root.find('.//command')
        if command is not None:
            self._fix_command(command)

        # Write fixed file
        # Preserve formatting
        self._indent(root)

        tree.write(xml_path, encoding='unicode', xml_declaration=True)

        self.stats["files_fixed"] += 1
        log.info(f"✅ Fixed: {xml_path}")

        return True, "Fixed successfully"

    def _fix_parameter(self, param: ET.Element):
        """Convert text parameter to safe select parameter."""
        # Change type to select
        param.set('type', 'select')
        param.set('multiple', 'true')
        param.set('optional', 'true')

        # Update help text
        original_help = param.get('help', '')
        new_help = "Select safe command-line options (multiple allowed)"
        param.set('help', new_help)

        # Remove value attribute if present
        if 'value' in param.attrib:
            del param.attrib['value']

        # Clear existing children
        for child in list(param):
            param.remove(child)

        # Add safe option elements
        for value, label in self.SAFE_OPTIONS:
            option = ET.SubElement(param, 'option')
            option.set('value', value)
            option.text = label

        log.debug(f"Converted parameter to safe select type")

    def _fix_command(self, command: ET.Element):
        """Fix command section to safely use advanced_options."""
        cmd_text = command.text or ""

        # Replace direct variable substitution with safe iteration
        # Old: $advanced_options
        # New: #for $option in $advanced_options\n    $option\n#end for

        replacements = [
            ('$advanced_options', '''
        #if $advanced_options
            #for $option in $advanced_options
                $option
            #end for
        #end if'''),
            ('${advanced_options}', '''
        #if $advanced_options
            #for $option in $advanced_options
                $option
            #end for
        #end if'''),
        ]

        for old, new in replacements:
            if old in cmd_text:
                cmd_text = cmd_text.replace(old, new)
                log.debug(f"Fixed command substitution")

        command.text = cmd_text

    def _indent(self, elem: ET.Element, level: int = 0):
        """Add proper indentation to XML for readability."""
        i = "\n" + level * "    "
        if len(elem):
            if not elem.text or not elem.text.strip():
                elem.text = i + "    "
            if not elem.tail or not elem.tail.strip():
                elem.tail = i
            for child in elem:
                self._indent(child, level + 1)
            if not child.tail or not child.tail.strip():
                child.tail = i
        else:
            if level and (not elem.tail or not elem.tail.strip()):
                elem.tail = i

    def fix_directory(self, directory: Path, pattern: str = "*.xml",
                     dry_run: bool = False) -> Dict:
        """
        Fix all XML files in a directory.

        Args:
            directory: Directory containing XML files
            pattern: File pattern to match
            dry_run: If True, don't actually modify files

        Returns:
            Statistics dictionary
        """
        xml_files = list(directory.glob(pattern))

        log.info(f"Found {len(xml_files)} XML files in {directory}")

        for xml_file in xml_files:
            modified, message = self.fix_file(xml_file, dry_run=dry_run)

            if modified:
                log.info(f"✅ {xml_file.name}: {message}")
            else:
                log.debug(f"⏭️  {xml_file.name}: {message}")

        return self.stats

    def generate_report(self) -> str:
        """Generate fix report."""
        report = [
            "\n" + "=" * 70,
            "Advanced Options Fix Report",
            "=" * 70,
            f"Files Processed: {self.stats['files_processed']}",
            f"Files Fixed: {self.stats['files_fixed']}",
            f"Files Skipped: {self.stats['files_skipped']}",
            f"Errors: {self.stats['errors']}",
            "=" * 70,
        ]

        if self.stats['files_fixed'] > 0:
            report.append(f"\n✅ Successfully fixed {self.stats['files_fixed']} files")
            report.append(f"📁 Backups saved to: {self.backup_dir}")
        else:
            report.append("\nℹ️  No files needed fixing")

        return "\n".join(report)


def main():
    """Command-line interface for fixing vulnerable XML files."""
    parser = argparse.ArgumentParser(
        description="Fix command injection vulnerability in Galaxy tool XML files"
    )
    parser.add_argument(
        'path',
        type=Path,
        help="Path to XML file or directory containing XML files"
    )
    parser.add_argument(
        '--pattern',
        default='*.xml',
        help="File pattern to match (default: *.xml)"
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help="Show what would be fixed without actually modifying files"
    )
    parser.add_argument(
        '--backup-dir',
        type=Path,
        default=Path('./backups'),
        help="Directory to store backups (default: ./backups)"
    )
    parser.add_argument(
        '--verbose',
        action='store_true',
        help="Enable verbose logging"
    )

    args = parser.parse_args()

    # Setup logging
    log_level = logging.DEBUG if args.verbose else logging.INFO
    logging.basicConfig(
        level=log_level,
        format='%(levelname)s: %(message)s'
    )

    # Create fixer
    fixer = AdvancedOptionsFixer(backup_dir=args.backup_dir)

    # Process path
    if args.path.is_file():
        modified, message = fixer.fix_file(args.path, dry_run=args.dry_run)
        print(f"{'✅ Fixed' if modified else '⏭️  Skipped'}: {args.path}")
        print(f"   {message}")
    elif args.path.is_dir():
        stats = fixer.fix_directory(args.path, pattern=args.pattern, dry_run=args.dry_run)
        print(fixer.generate_report())
    else:
        print(f"❌ Error: Path not found: {args.path}")
        return 1

    return 0


if __name__ == "__main__":
    import sys
    sys.exit(main())
