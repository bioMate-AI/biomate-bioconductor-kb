# Lessons Learned: Creating Galaxy Tool Wrappers

This document captures lessons learned, common pitfalls, and best practices from developing 238 Galaxy tool wrappers for the Biomni bioinformatics platform.

---

## Table of Contents

1. [Galaxy Tool XML Structure](#1-galaxy-tool-xml-structure)
2. [Command Block Best Practices](#2-command-block-best-practices)
3. [Parameter Types and Validation](#3-parameter-types-and-validation)
4. [Python Wrapper Patterns](#4-python-wrapper-patterns)
5. [Docker Container Integration](#5-docker-container-integration)
6. [Common XML Errors](#6-common-xml-errors)
7. [Testing Galaxy Tools](#7-testing-galaxy-tools)

---

## 1. Galaxy Tool XML Structure

### Basic Template

```xml
<?xml version="1.0"?>
<tool id="biomni_domain_function_name" name="Biomni: Function Name" version="1.0.0">
    <description>Brief description of what the tool does.</description>
    <requirements>
        <container type="docker">biomate/biomni-tools:latest</container>
    </requirements>
    <command detect_errors="exit_code"><![CDATA[
python '$__tool_directory__/function_name_wrapper.py' --output '$output'
    --param1 '$param1'
    --param2 '$param2'
#if $optional_param
    --optional_param '$optional_param'
#end if
]]></command>
    <inputs>
        <param name="param1" type="text" label="Parameter 1" help="Description of param1" />
        <param name="param2" type="float" label="Parameter 2" help="Description of param2" value="0.5" />
        <param name="optional_param" type="text" label="Optional Param" help="Description" optional="true"/>
    </inputs>
    <outputs>
        <data name="output" format="txt" label="${tool.name} on ${on_string}"/>
    </outputs>
    <help><![CDATA[
**Biomni: Function Name**

Detailed help text here.

**Domain**: domain_name
**Function**: function_name
]]></help>
</tool>
```

### Key Elements

| Element | Purpose |
|---------|---------|
| `id` | Unique identifier, format: `biomni_domain_functionname` |
| `name` | Display name with "Biomni:" prefix |
| `description` | Short one-line description |
| `requirements` | Docker container specification |
| `command` | Shell command to execute |
| `inputs` | Parameter definitions |
| `outputs` | Output file definitions |
| `help` | User documentation |

---

## 2. Command Block Best Practices

### Use CDATA Sections

Always wrap command content in CDATA to avoid XML escaping issues:

```xml
<command detect_errors="exit_code"><![CDATA[
python '$__tool_directory__/wrapper.py' --output '$output'
]]></command>
```

### Conditional Parameters

Use Cheetah templating for optional parameters:

```xml
#if $optional_param
    --optional_param '$optional_param'
#end if
```

### Multiple Conditionals

```xml
#if $advanced.use_advanced == "yes"
    --threshold '$advanced.threshold'
    --iterations '$advanced.iterations'
#end if
```

### Boolean Parameters

```xml
#if $enable_feature
    --enable_feature
#end if
```

---

## 3. Parameter Types and Validation

### Common Parameter Types

| Type | Usage | Example |
|------|-------|---------|
| `text` | String input | Gene names, file paths |
| `integer` | Whole numbers | Iterations, counts |
| `float` | Decimal numbers | Thresholds, rates |
| `boolean` | True/False | Feature flags |
| `select` | Dropdown | Algorithm choice |
| `data` | File input | Upload files |

### Example Definitions

```xml
<!-- Text with validation -->
<param name="gene_name" type="text" label="Gene Name" help="HGNC gene symbol">
    <validator type="regex" message="Gene name must be alphanumeric">[A-Za-z0-9]+</validator>
</param>

<!-- Float with range -->
<param name="threshold" type="float" label="Threshold" value="0.5" min="0" max="1" help="Value between 0 and 1"/>

<!-- Select dropdown -->
<param name="algorithm" type="select" label="Algorithm">
    <option value="fast" selected="true">Fast</option>
    <option value="accurate">Accurate</option>
</param>

<!-- Boolean checkbox -->
<param name="verbose" type="boolean" label="Verbose output" checked="false"/>

<!-- File input -->
<param name="input_file" type="data" format="fasta" label="Input FASTA file"/>
```

### Optional Parameters

Add `optional="true"` for non-required parameters:

```xml
<param name="optional_param" type="text" label="Optional" optional="true"/>
```

---

## 4. Python Wrapper Patterns

### Standard Wrapper Template

```python
#!/usr/bin/env python
"""Galaxy wrapper for biomni function."""

import argparse
import json
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', required=True)
    parser.add_argument('--param1', required=True)
    parser.add_argument('--param2', type=float, default=0.5)
    parser.add_argument('--optional_param', default=None)
    args = parser.parse_args()

    # Import the actual function
    from biomni.tool.domain import function_name

    # Parse complex parameters
    if args.optional_param:
        optional_param = json.loads(args.optional_param)
    else:
        optional_param = None

    # Execute function
    try:
        result = function_name(
            param1=args.param1,
            param2=args.param2,
            optional_param=optional_param
        )
        success = True
        error = None
    except Exception as e:
        result = None
        success = False
        error = str(e)

    # Write output
    with open(args.output, 'w') as f:
        if success:
            f.write(str(result))
        else:
            f.write(f"ERROR: {error}")

    sys.exit(0 if success else 1)

if __name__ == '__main__':
    main()
```

### Parsing JSON Parameters

For list/dict parameters passed as JSON strings:

```python
import json

def parse_json_param(value):
    """Parse JSON string to Python object."""
    if value is None or value == '' or value == 'None':
        return None
    try:
        return json.loads(value)
    except json.JSONDecodeError:
        return value  # Return as string if not valid JSON
```

---

## 5. Docker Container Integration

### Specifying Container

```xml
<requirements>
    <container type="docker">biomate/biomni-tools:latest</container>
</requirements>
```

### Multiple Container Options

```xml
<requirements>
    <container type="docker">biomate/biomni-tools:latest</container>
    <container type="singularity">docker://biomate/biomni-tools:latest</container>
</requirements>
```

### Container with Dependencies

For tools needing specific packages:

```xml
<requirements>
    <container type="docker">biomate/biomni-docking:latest</container>
</requirements>
```

---

## 6. Common XML Errors

### Error: Unescaped Quotes in help Attribute

**Problem:**
```xml
<param help="Default is "value""/>  <!-- WRONG: unescaped quotes -->
```

**Solution:**
```xml
<param help="Default is 'value'"/>  <!-- Use single quotes -->
<!-- OR -->
<param help="Default is &quot;value&quot;"/>  <!-- Use XML entities -->
```

### Specific Patterns Fixed (2026-01-30)

We identified and fixed 51 XML files with the following patterns:

**Pattern 1: `(default: "value")`**
```xml
<!-- WRONG -->
<param help="Threshold for analysis (default: "0.5")"/>
<!-- FIXED -->
<param help="Threshold for analysis (default: '0.5')"/>
```

**Pattern 2: `(default="value")`**
```xml
<!-- WRONG -->
<param help="Output directory (default="./output")"/>
<!-- FIXED -->
<param help="Output directory (default='./output')"/>
```

**Pattern 3: `default is "value"`**
```xml
<!-- WRONG -->
<param help="Filename to save results, default is "results.csv""/>
<!-- FIXED -->
<param help="Filename to save results, default is 'results.csv'"/>
```

**Pattern 4: Options with internal quotes**
```xml
<!-- WRONG -->
<param help="Type of model: "fast" or "accurate""/>
<!-- FIXED -->
<param help="Type of model: 'fast' or 'accurate'"/>
```

**Pattern 5: Unescaped ampersands**
```xml
<!-- WRONG -->
<param help="Staining type (default: H&E)"/>
<!-- FIXED -->
<param help="Staining type (default: H&amp;E)"/>
```

**Pattern 6: Raw JSON arrays in help text**
```xml
<!-- WRONG -->
<param help="Gene list defaults to ["MYC","ERBB2","CDKN2A"]"/>
<!-- FIXED -->
<param help="Gene list defaults to ['MYC','ERBB2','CDKN2A']"/>
```

### Error: Missing CDATA in Command

**Problem:**
```xml
<command>
python script.py --param "value"  <!-- Quotes break XML -->
</command>
```

**Solution:**
```xml
<command><![CDATA[
python script.py --param "value"
]]></command>
```

### Error: Invalid XML Characters

**Problem:**
```xml
<help>Use < or > for comparison</help>  <!-- < and > are special -->
```

**Solution:**
```xml
<help><![CDATA[Use < or > for comparison]]></help>
```

Note: Characters like `<` and `>` inside help attributes (not CDATA) must be escaped:
```xml
<param help="Filter values &lt; 100"/>  <!-- Use &lt; for < -->
<param help="Filter values &gt; 100"/>  <!-- Use &gt; for > -->
```

### Error: Mismatched Tags

Always verify opening and closing tags match:

```xml
<param name="x">  <!-- Opening tag -->
</param>          <!-- Closing tag must match -->
```

### Automated Validation Script

Use Python's XML parser for validation (faster than xmllint):

```python
import xml.etree.ElementTree as ET
import os

errors = []
for root, dirs, files in os.walk('.'):
    for f in files:
        if f.endswith('.xml'):
            path = os.path.join(root, f)
            try:
                ET.parse(path)
            except Exception as e:
                errors.append((path, str(e)))

print(f'Passed: {238 - len(errors)}, Failed: {len(errors)}')
```

---

## 7. Testing Galaxy Tools

### XML Validation

```bash
# Validate XML syntax
xmllint --noout tool.xml

# Check all tools in directory
for f in $(find . -name "*.xml"); do
    xmllint --noout "$f" || echo "ERROR: $f"
done
```

### Galaxy Tool Shed Linting

```bash
# Using planemo
planemo lint tool.xml
```

### Functional Testing

1. Install tool in Galaxy instance
2. Run with test inputs
3. Verify output format and content
4. Check error handling

### Test Data Location

```
galaxy/tools/biomni/
├── domain/
│   ├── function_name.xml
│   ├── function_name_wrapper.py
│   └── test-data/
│       ├── input.txt
│       └── expected_output.txt
```

---

## 8. Synchronization with Nextflow Workflows

### Maintaining Parity

Each Galaxy tool should have a corresponding Nextflow workflow:

| Galaxy | Nextflow |
|--------|----------|
| `domain/function.xml` | `subworkflows/domain/function/main.nf` |
| `domain/function_wrapper.py` | (embedded in main.nf) |

### Shared Logic

The core function logic should be identical. Consider:

1. Extracting shared logic to a common Python module
2. Using the same Docker container
3. Matching parameter names and types

---

## Current Status (2026-01-30)

| Metric | Value |
|--------|-------|
| Total Galaxy tools | 238 |
| XML files validated | 238 (100%) |
| Wrapper files | 238 |
| XML files fixed | 51 |

### Validation Complete

All 238 Galaxy XML files now pass XML validation. The main issues fixed were:
- Internal double quotes in help attributes (replaced with single quotes)
- Unescaped ampersands in description/help text
- Raw JSON arrays in help text with double quotes

### Remaining Work

1. Functional testing with Galaxy instance
2. Test data generation for tools
3. Parameter type alignment with Nextflow versions

---

*Document created: 2026-01-29*
*Updated: 2026-01-30 - All XML files validated and fixed*
