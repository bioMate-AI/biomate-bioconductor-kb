#!/usr/bin/env python3
"""
Fix the 6 broken XML tools identified by quality check.

Issues:
1. agat_spflagshortintrons - unescaped < in description
2. manta_convertinversion - broken description with <= operator
3. propr_propr - newline in description causing issues
4. pbbam_pbmerge - ampersand not escaped
5. msisensor_scan - ampersand not escaped
6. mitohifi_findmitoreference - mismatched tag
"""

from pathlib import Path
import xml.etree.ElementTree as ET
import html


def fix_tool(tool_path: Path) -> bool:
    """Fix XML issues in a tool file."""
    print(f"Fixing {tool_path.name}...")

    try:
        with open(tool_path, 'r') as f:
            content = f.read()

        # Fix 1: agat_spflagshortintrons - escape < in <pseudo>
        if 'agat_spflagshortintrons' in tool_path.name:
            content = content.replace(
                'attribute <pseudo>',
                'attribute &lt;pseudo&gt;'
            )

        # Fix 2: manta_convertinversion - escape <= in description
        if 'manta_convertinversion' in tool_path.name:
            content = content.replace(
                'versions <= 1.4.0.',
                'versions &lt;= 1.4.0.'
            )

        # Fix 3: propr_propr - escape special chars and clean description
        if 'propr_propr' in tool_path.name:
            # Replace problematic description
            old_desc = '''<description>Perform logratio-based correlation analysis -> get proportionality & basis shrinkage partial correlation coefficients.
One can also compute standard correlation coefficients, if required.
</description>'''
            new_desc = '''<description>Perform logratio-based correlation analysis to get proportionality and basis shrinkage partial correlation coefficients. One can also compute standard correlation coefficients, if required.</description>'''
            content = content.replace(old_desc, new_desc)

        # Fix 4: pbbam_pbmerge - escape & in description
        if 'pbbam_pbmerge' in tool_path.name:
            content = content.replace(
                'create, query, & edit',
                'create, query, and edit'
            )

        # Fix 5: msisensor_scan - escape & in description
        if 'msisensor_scan' in tool_path.name:
            content = content.replace(
                'microsatellite & homopolymer',
                'microsatellite and homopolymer'
            )

        # Fix 6: mitohifi_findmitoreference - fix mismatched tags or problematic content
        if 'mitohifi_findmitoreference' in tool_path.name:
            # The description has backticks which might cause issues - escape them
            content = content.replace(
                '`nextflow secrets set NCBI_API_KEY <key>`',
                'nextflow secrets set NCBI_API_KEY &lt;key&gt;'
            )

        # Validate the fixed XML
        try:
            ET.fromstring(content)
            print(f"  ✓ {tool_path.name} fixed and validated")
        except ET.ParseError as e:
            print(f"  ✗ {tool_path.name} still has errors: {e}")
            return False

        # Save fixed version
        with open(tool_path, 'w') as f:
            f.write(content)

        return True

    except Exception as e:
        print(f"  ✗ Error fixing {tool_path.name}: {e}")
        return False


def main():
    """Fix all broken tools."""
    print("=" * 80)
    print("FIXING BROKEN XML TOOLS")
    print("=" * 80)
    print()

    tools_dir = Path(__file__).parent.parent / "tools" / "nfcore_generated"

    broken_tools = [
        "agat_spflagshortintrons.xml",
        "manta_convertinversion.xml",
        "propr_propr.xml",
        "pbbam_pbmerge.xml",
        "msisensor_scan.xml",
        "mitohifi_findmitoreference.xml"
    ]

    fixed = 0
    failed = 0

    for tool_name in broken_tools:
        tool_path = tools_dir / tool_name
        if tool_path.exists():
            if fix_tool(tool_path):
                fixed += 1
            else:
                failed += 1
        else:
            print(f"⚠️  {tool_name} not found")
            failed += 1

    print()
    print("=" * 80)
    print(f"Fixed: {fixed}/{len(broken_tools)}")
    print(f"Failed: {failed}/{len(broken_tools)}")
    print("=" * 80)

    return 0 if failed == 0 else 1


if __name__ == "__main__":
    import sys
    sys.exit(main())
