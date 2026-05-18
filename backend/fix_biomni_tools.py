#!/usr/bin/env python3
"""
Fix Biomni tool XMLs by converting inline Python code to wrapper scripts.
This fixes the issue where Galaxy collapses newlines in inline Python code.
"""
import os
import re
import glob
from pathlib import Path

_HERE = Path(__file__).resolve().parent
TOOLS_DIR = os.environ.get(
    "BIOMNI_TOOLS_DIR",
    str(_HERE / "biomni_workflows" / "galaxy" / "tools" / "biomni"),
)

def extract_inline_python(xml_content):
    """Extract inline Python code from XML command section."""
    # Match python -c "..." pattern
    pattern = r'python -c "(.*?)"(\s*--output)'
    match = re.search(pattern, xml_content, re.DOTALL)
    if match:
        return match.group(1).strip()
    return None

def extract_function_import(python_code):
    """Extract the biomni function import from Python code."""
    # Match: from biomni.tool.X import Y
    pattern = r'from (biomni\.tool\.\w+) import (\w+)'
    match = re.search(pattern, python_code)
    if match:
        return match.group(1), match.group(2)
    return None, None

def create_wrapper_script(module_path, function_name):
    """Create a wrapper script for the biomni function."""
    return f'''#!/usr/bin/env python3
"""
Wrapper script for Biomni {function_name} tool.
Auto-generated to fix inline Python code issues in Galaxy.
"""
import sys
import json
from {module_path} import {function_name}

def main():
    # Parse arguments
    args = {{}}
    i = 1
    while i < len(sys.argv):
        if sys.argv[i].startswith('--'):
            key = sys.argv[i][2:]
            if i + 1 < len(sys.argv) and not sys.argv[i + 1].startswith('--'):
                val = sys.argv[i + 1]
                # Type conversion
                if val.lower() == 'true':
                    val = True
                elif val.lower() == 'false':
                    val = False
                else:
                    try:
                        val = int(val)
                    except ValueError:
                        try:
                            val = float(val)
                        except ValueError:
                            pass
                args[key] = val
                i += 2
            else:
                args[key] = True
                i += 1
        else:
            i += 1

    # Get output path and remove from args
    output_path = args.pop('output', '/dev/stdout')

    # Call function
    result = {function_name}(**args)

    # Write output
    with open(output_path, 'w') as f:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, (dict, list)):
            json.dump(result, f, indent=2, default=str)
        else:
            f.write(str(result))

if __name__ == '__main__':
    main()
'''

def update_xml_command(xml_content, wrapper_name):
    """Update XML to use wrapper script instead of inline Python."""
    # Pattern to match the entire command section with inline Python
    pattern = r'(<command detect_errors="exit_code"><!\[CDATA\[\s*)python -c ".*?"(\s*--output.*?]]></command>)'

    replacement = rf'\1python \'$__tool_directory__/{wrapper_name}\'\2'

    new_content = re.sub(pattern, replacement, xml_content, flags=re.DOTALL)
    return new_content

def fix_tool(xml_path):
    """Fix a single tool XML file."""
    with open(xml_path, 'r') as f:
        xml_content = f.read()

    # Check if it has inline Python
    if 'python -c "' not in xml_content:
        return False, "No inline Python found"

    # Extract inline Python code
    python_code = extract_inline_python(xml_content)
    if not python_code:
        return False, "Could not extract Python code"

    # Extract function import
    module_path, function_name = extract_function_import(python_code)
    if not module_path or not function_name:
        return False, "Could not extract function import"

    # Create wrapper script
    wrapper_content = create_wrapper_script(module_path, function_name)
    wrapper_name = f"{function_name}_wrapper.py"
    wrapper_path = os.path.join(os.path.dirname(xml_path), wrapper_name)

    # Write wrapper script
    with open(wrapper_path, 'w') as f:
        f.write(wrapper_content)
    os.chmod(wrapper_path, 0o755)

    # Update XML
    new_xml = update_xml_command(xml_content, wrapper_name)

    if new_xml == xml_content:
        return False, "XML update failed"

    # Write updated XML
    with open(xml_path, 'w') as f:
        f.write(new_xml)

    return True, f"Created {wrapper_name}"

def main():
    """Fix all Biomni tool XMLs."""
    xml_files = glob.glob(f"{TOOLS_DIR}/*/*.xml")

    fixed = 0
    skipped = 0
    errors = []

    for xml_path in xml_files:
        success, msg = fix_tool(xml_path)
        if success:
            fixed += 1
            print(f"[FIXED] {os.path.basename(xml_path)}: {msg}")
        else:
            if "No inline Python" in msg:
                skipped += 1
            else:
                errors.append((xml_path, msg))
                print(f"[ERROR] {os.path.basename(xml_path)}: {msg}")

    print(f"\n=== Summary ===")
    print(f"Fixed: {fixed}")
    print(f"Skipped (no inline Python): {skipped}")
    print(f"Errors: {len(errors)}")

    if errors:
        print("\nErrors:")
        for path, msg in errors:
            print(f"  {path}: {msg}")

if __name__ == '__main__':
    main()
