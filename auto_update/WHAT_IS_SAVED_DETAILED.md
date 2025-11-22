# What Is Saved to Database - Detailed Breakdown

**Date:** November 22, 2025
**Question:** "Is there also example code? How about directly save the readme file into the raw text field?"

## Quick Answer

| Content | Saved? | Field Name | How Much? |
|---------|--------|------------|-----------|
| **README file** | ✅ YES | `rawText` | ✅ **COMPLETE** (now fixed - was truncated) |
| **Code examples** | ✅ YES | `examples` (JSON array) | Up to 5 examples |
| **Usage examples** | ✅ YES | `usage_guide` (formatted text) | Up to 3 examples |

## 1. README File - Complete Content ✅

### Field: `rawText` (TEXT)

**Content Structure:**
```
Tool: [name]
ID: [tool_id]
Version: [version]
Description: [description]

## Help
[Help text from Galaxy wrapper XML]

## Documentation
[COMPLETE README FILE - NOT TRUNCATED] ← FIXED!

## GitHub Description
[GitHub repo description]

Topics: [topic1, topic2, topic3]
```

**Example:**
```sql
SELECT name, substr(rawText, 1, 500) FROM tools WHERE name = 'rush';
```

**Result:**
```
Tool: rush
ID: auto_rush
Version: 1.0.0
Description: A cross-platform command-line tool for executing jobs in parallel

## Help
[![Built with GoLang](https://img.shields.io/badge/powered_by-go-636)
...

## Documentation
# rush

`rush` - a cross-platform command-line tool for executing jobs in parallel

Table of Contents

* [Installation](#installation)
* [Features](#features)
* [Usage](#usage)
...
[COMPLETE README CONTINUES...]
```

**Source:** `documentation_fetcher.py` → `documentation['readme']`

**Recent Fix:** Was truncated to 2000 chars, now saves FULL README ✅

## 2. Code Examples - Structured JSON ✅

### Field: `examples` (TEXT/JSON)

**Format:** JSON array of strings
```json
[
  "example1 code",
  "example2 code",
  "example3 code",
  "example4 code",
  "example5 code"
]
```

**Source:** Extracted from README by `documentation_fetcher.py`
- Looks for code blocks in markdown (```...```)
- Looks for "Example", "Usage", "Quick Start" sections
- Saves up to 5 examples

**Real Example from rush tool:**
```json
[
  "1. Simple run, quoting is not necessary\n\n        # seq 1 3 | rush 'echo {}'\n        $ seq 1 3 | rush echo {}\n        3\n        1\n        2",

  "1. Read data from file (`-i`)\n\n        $ rush echo {} -i data.txt",

  "1. Keep order (`-k`)\n\n        $ seq 1 10 | rush 'sleep 1; echo {}' -k -j 10",

  "1. Timeout (`-t`)\n\n        $ time seq 1 | rush 'sleep 10; echo {}' -t 2\n        seq: write error: Broken pipe",

  "1. Retry (`-r`)\n\n        $ seq 1 | rush 'python unexisted_script.py' -r 1"
]
```

**Query:**
```sql
SELECT name, examples FROM tools WHERE name = 'rush';
```

## 3. Usage Guide - Formatted Text ✅

### Field: `usage_guide` (TEXT)

**Format:** Markdown-formatted text with sections
```
## Installation
[installation instructions from README]

## Usage
[usage instructions from help text]

## Examples
1. [example 1]
2. [example 2]
3. [example 3]
```

**Source:** Compiled from:
- `documentation['installation']`
- `documentation['help_text']`
- `documentation['usage_examples']` (first 3)

**Example:**
```sql
SELECT usage_guide FROM tools WHERE name = 'deepvariant';
```

## 4. Additional Code/Example Fields

### Field: `help_text` (TEXT/JSON)

**Contains:**
```json
{
  "wrapper_help": "Help from Galaxy XML <help> section",
  "readme_description": "Description extracted from README",
  "documentation_help": "Help text from documentation",
  "installation": "Installation instructions",
  "what_it_does": "What the tool does"
}
```

### Field: `usage_examples` (from enhanced metadata)

Stored in the discovery object and can be added to database:
- Test command examples
- Installation command examples
- Usage patterns from CI/CD configs

## Complete Data Flow

```
GitHub Repository
  ↓
documentation_fetcher.py
  ├─ Fetches README (complete file)
  ├─ Extracts code examples from README
  ├─ Extracts usage examples
  └─ Extracts installation instructions
  ↓
metadata_extractor_comprehensive.py
  ├─ Builds rawText with FULL README
  ├─ Saves examples as JSON array
  ├─ Builds usage_guide with formatted examples
  └─ Builds help_text JSON
  ↓
Database (galaxy_ai_tools.db)
  ├─ rawText: COMPLETE README + wrapper help + metadata
  ├─ examples: JSON array of code examples
  ├─ usage_guide: Formatted usage instructions
  └─ help_text: JSON with multiple help sources
```

## What's Saved: Summary Table

| Content Type | Field | Format | Limit | Example |
|--------------|-------|--------|-------|---------|
| **Full README** | rawText | Text | ∞ (no limit) ✅ | "# Tool\n\n## Installation\n..." |
| **Code examples** | examples | JSON array | 5 examples | ["example1", "example2", ...] |
| **Usage guide** | usage_guide | Markdown text | 3 examples | "## Installation\n..." |
| **Help text** | help_text | JSON object | Various | {"wrapper_help": "...", ...} |
| **HTML docs** | htmlContent | HTML | 5000 chars | "\<html>...</html>" |
| **Test commands** | test_commands | JSON array | All found | ["pytest", "make test"] |
| **Install commands** | install_commands | JSON array | All found | ["pip install ..."] |
| **Dependencies** | dependencies | JSON array | All found | [{"package_manager": "pip", ...}] |

## Real Database Query

```bash
# View complete README
sqlite3 backend/galaxy_ai_tools.db "
SELECT name, rawText
FROM tools
WHERE name = 'rush';
"

# View code examples
sqlite3 backend/galaxy_ai_tools.db "
SELECT name, examples
FROM tools
WHERE name = 'rush';
"

# View usage guide
sqlite3 backend/galaxy_ai_tools.db "
SELECT name, usage_guide
FROM tools
WHERE name = 'rush';
"
```

## Before vs After Fix

### Before (WRONG)
```python
# In _build_raw_text():
parts.append(f"\n## Documentation\n{documentation['readme'][:2000]}")
```
❌ Only first 2000 characters of README saved

### After (FIXED)
```python
# In _build_raw_text():
readme_full = documentation['readme']
parts.append(f"\n## Documentation\n{readme_full}")
```
✅ COMPLETE README saved

## How to Verify

```bash
# Check rawText length (should be > 2000 for most tools)
sqlite3 backend/galaxy_ai_tools.db "
SELECT name, length(rawText) as text_length
FROM tools
WHERE auto_discovered = 1
ORDER BY text_length DESC
LIMIT 5;
"

# Extract full README from database
sqlite3 backend/galaxy_ai_tools.db "
SELECT rawText FROM tools WHERE name = 'rush'
" > rush_complete_readme.txt

# Check examples are JSON arrays
sqlite3 backend/galaxy_ai_tools.db "
SELECT name, json_array_length(examples) as example_count
FROM tools
WHERE examples IS NOT NULL AND examples != '[]'
LIMIT 5;
"
```

## Summary

**Your Questions Answered:**

1. **"Is there also example code?"**
   - ✅ YES - Saved in `examples` (JSON array, up to 5)
   - ✅ YES - Saved in `usage_guide` (formatted text, up to 3)
   - ✅ YES - Saved in `rawText` (complete README with all examples)

2. **"How about directly save the readme file into the raw text field?"**
   - ✅ YES - COMPLETE README is saved in `rawText`
   - ✅ FIXED - Was truncated to 2000 chars, now saves FULL content
   - ✅ COMBINED - README + wrapper help + metadata all in one field

**All code examples and complete documentation are now saved!** 🎉
