# Test Database Usage Guide

**Date:** November 22, 2025 13:00
**Purpose:** Prevent invalid entries in main AI tool index during development/testing

## Problem Solved

**Before:** Pipeline wrote directly to main database (`galaxy_ai_tools.db`)
- ❌ Invalid tools pollute production index
- ❌ Broken tools hard to remove
- ❌ No safe way to test new features

**After:** Separate test database for validation
- ✅ Test tools in isolation
- ✅ Verify enhanced metadata before merge
- ✅ Easy to discard/recreate test database
- ✅ Safe production index

## Quick Start

### 1. Create Test Database
```bash
python scripts/create_test_database.py
```

**Output:**
```
✓ Created test database with empty tables: ../backend/galaxy_ai_tools_test.db
✓ All enhanced metadata columns present
Tables: 23
Tools count: 0
```

### 2. Run Pipeline with Test Database
```bash
# Use --test-db flag
python scripts/run_pipeline.py \
    --mode full \
    --days 90 \
    --min-stars 50 \
    --limit 5 \
    --test-db
```

**You'll see:**
```
🧪 Using TEST database: /home/yzhang/biomate/backend/galaxy_ai_tools_test.db
```

### 3. Verify Tools in Test Database
```bash
python scripts/verify_enhanced_metadata.py ../backend/galaxy_ai_tools_test.db
```

**Output:**
```
✅ Found 5 recently auto-discovered tools

Tool: DeepVariant (auto_deepvariant)
  ✅ Dependencies: 3 packages
  ✅ Test Commands: 2 commands
  ✅ Install Commands: 1 commands
  ✅ Container: quay.io/biocontainers/...
  ✓ COMPLETE: Can install, implement, and execute
```

### 4. Merge to Main Database (When Ready)
```bash
# Dry run first
python scripts/merge_test_to_main.py --dry-run

# Actually merge
python scripts/merge_test_to_main.py
```

## Detailed Usage

### Create Test Database Options

```bash
# Default: Copy schema only (empty tables)
python scripts/create_test_database.py

# Copy schema AND data
python scripts/create_test_database.py --copy-data

# Custom paths
python scripts/create_test_database.py \
    --source-db ../backend/galaxy_ai_tools.db \
    --test-db ../backend/my_test.db
```

### Run Pipeline Options

```bash
# Full pipeline with test database
python scripts/run_pipeline.py --mode full --test-db

# Skip tests (faster)
python scripts/run_pipeline.py --mode full --test-db --no-test

# Process specific time range
python scripts/run_pipeline.py \
    --mode full \
    --days 30 \
    --min-stars 75 \
    --limit 10 \
    --test-db
```

### Merge Options

```bash
# Dry run (see what would be merged)
python scripts/merge_test_to_main.py --dry-run

# Merge all tools
python scripts/merge_test_to_main.py

# Merge specific tools only
python scripts/merge_test_to_main.py --tool-ids auto_tool1 auto_tool2 auto_tool3

# Custom database paths
python scripts/merge_test_to_main.py \
    --test-db ../backend/galaxy_ai_tools_test.db \
    --main-db ../backend/galaxy_ai_tools.db
```

## Workflow Examples

### Example 1: Test New Feature

```bash
# 1. Create fresh test database
rm -f ../backend/galaxy_ai_tools_test.db
python scripts/create_test_database.py

# 2. Run pipeline with new feature
python scripts/run_pipeline.py --mode full --days 30 --limit 3 --test-db

# 3. Verify results
python scripts/verify_enhanced_metadata.py ../backend/galaxy_ai_tools_test.db

# 4. If good, merge to main
python scripts/merge_test_to_main.py

# 5. If bad, just delete test database
rm ../backend/galaxy_ai_tools_test.db
```

### Example 2: Validate Batch of Tools

```bash
# 1. Process large batch in test database
python scripts/run_pipeline.py --mode full --days 90 --min-stars 50 --limit 20 --test-db

# 2. Review all tools
sqlite3 ../backend/galaxy_ai_tools_test.db "
SELECT tool_id, name, version,
       dependencies IS NOT NULL as has_deps,
       test_commands IS NOT NULL as has_tests
FROM tools
ORDER BY discovery_date DESC;
"

# 3. Merge only good ones
python scripts/merge_test_to_main.py --tool-ids auto_tool1 auto_tool2 --dry-run
python scripts/merge_test_to_main.py --tool-ids auto_tool1 auto_tool2
```

### Example 3: Daily Development Workflow

```bash
# Morning: Fresh test database
python scripts/create_test_database.py

# Development: Test changes
python scripts/run_pipeline.py --mode full --limit 5 --test-db

# Evening: If satisfied, merge to main
python scripts/merge_test_to_main.py

# Or: Discard if not satisfied
rm ../backend/galaxy_ai_tools_test.db
```

## Database Comparison

| Feature | Main Database | Test Database |
|---------|--------------|---------------|
| **Path** | `backend/galaxy_ai_tools.db` | `backend/galaxy_ai_tools_test.db` |
| **Purpose** | Production AI tool index | Development/testing |
| **Used by** | Galaxy AI Assistant | Auto-update pipeline (with --test-db) |
| **Safety** | Protected | Disposable |
| **Tools** | ~50+ production tools | 0 (or testing tools) |
| **Schema** | Full schema | Same as main |
| **Merge** | N/A | Can merge to main |

## Safety Features

### In create_test_database.py:
- ✅ Warns before overwriting existing test database
- ✅ Skips internal SQLite tables (sqlite_sequence)
- ✅ Handles FTS (Full Text Search) tables correctly
- ✅ Verifies enhanced metadata columns exist

### In merge_test_to_main.py:
- ✅ Verifies each tool has enhanced metadata
- ✅ Checks for duplicates before merging
- ✅ Asks confirmation before overwriting
- ✅ Supports dry-run mode
- ✅ Transactions (rollback on error)

### In run_pipeline.py:
- ✅ Clear indicator of which database is being used
- ✅ Uses --test-db flag (explicit opt-in)
- ✅ All database paths use same configuration

## Verification Queries

### Check Tool Count
```bash
sqlite3 ../backend/galaxy_ai_tools_test.db "SELECT COUNT(*) FROM tools"
```

### List All Tools
```bash
sqlite3 ../backend/galaxy_ai_tools_test.db "
SELECT tool_id, name, version, discovery_date
FROM tools
ORDER BY discovery_date DESC
LIMIT 10;
"
```

### Check Enhanced Metadata Coverage
```bash
sqlite3 ../backend/galaxy_ai_tools_test.db "
SELECT
  COUNT(*) as total,
  SUM(CASE WHEN dependencies IS NOT NULL THEN 1 ELSE 0 END) as has_deps,
  SUM(CASE WHEN test_commands IS NOT NULL THEN 1 ELSE 0 END) as has_tests,
  SUM(CASE WHEN install_commands IS NOT NULL THEN 1 ELSE 0 END) as has_install
FROM tools;
"
```

## Troubleshooting

### Test database already exists
```bash
rm -f ../backend/galaxy_ai_tools_test.db
python scripts/create_test_database.py
```

### Pipeline using wrong database
Check for `🧪 Using TEST database` message. If missing, add `--test-db` flag.

### Merge fails with duplicate error
Tool already exists in main database. Use `--dry-run` first, or delete from main DB.

### Enhanced metadata columns missing
```bash
python scripts/add_enhanced_metadata_columns.py ../backend/galaxy_ai_tools_test.db
```

## Files

**Created:**
- `scripts/create_test_database.py` - Creates test database
- `scripts/merge_test_to_main.py` - Merges validated tools to main
- `scripts/run_pipeline.py` (modified) - Added --test-db support
- `20251122_1300_TEST_DATABASE_USAGE_GUIDE.md` - This file

**Databases:**
- `backend/galaxy_ai_tools.db` - Main production database
- `backend/galaxy_ai_tools_test.db` - Test database (created on demand)

## Summary

✅ **Test database created and ready**
✅ **Pipeline supports --test-db flag**
✅ **Merge script validates before merging**
✅ **Main database protected from invalid entries**

**Recommendation:** Always use `--test-db` during development and testing. Only merge to main database after thorough verification.
