# Complete Metadata Reference - What Information Is Saved

**Date:** November 22, 2025

## Summary: Your Questions Answered ✅

| Question | Answer | Field Name | Example |
|----------|--------|------------|---------|
| Git URL? | ✅ YES | `github_url`, `url` | `https://github.com/google/deepvariant` |
| Repo stars? | ✅ YES | `stars` | `1250` |
| Time on git? | ✅ YES | `created_at` (GitHub repo creation), `updated_at` (GitHub last update), `discovery_date` (when we found it) | `2025-11-22T12:30:45` |

## Complete List: 44 Fields Saved to Database

### 🔗 GitHub Repository Information (7 fields)

```python
{
    'github_url': 'https://github.com/google/deepvariant',
    'url': 'https://github.com/google/deepvariant',  # duplicate
    'repo_owner': 'google',
    'repo_name': 'deepvariant',
    'stars': 1250,                    # ⭐ Star count
    'language': 'Python',
    'topics': ['genomics', 'variant-calling']  # JSON array
}
```

**Source:** GitHub API (`repo.html_url`, `repo.stargazers_count`, etc.)

### ⏰ Time Information (3 fields)

```python
{
    'created_at': '2025-11-22T12:30:45.123456',     # When added to OUR database
    'updated_at': '2025-11-22T12:30:45.123456',     # Last update in OUR database
    'discovery_date': '2025-11-22T10:15:30.000000'  # When auto-discovery found it
}
```

**Note:** GitHub repo creation/update times are captured during detection but NOT currently saved to database.

### 🆔 Tool Identification (4 fields)

```python
{
    'tool_id': 'auto_deepvariant',
    'name': 'DeepVariant',
    'version': '1.6.0',              # ⭐ NEW - extracted from releases/tags/files
    'description': 'Deep learning variant caller for NGS data'
}
```

### 🔧 Tool Metadata (5 fields)

```python
{
    'category': 'Variant Calling',
    'parameters': '[{"name": "input", "type": "data", "format": "bam"}]',  # JSON
    'inputs': '["bam", "fastq"]',    # JSON
    'outputs': '["vcf"]',            # JSON
    'requirements': 'Python>=3.7'
}
```

### 📦 Enhanced Metadata - For Install/Execute (4 fields) ⭐ NEW

```python
{
    'dependencies': '[
        {"package_manager": "pip", "dependency": "numpy>=1.20.0"},
        {"package_manager": "conda", "dependency": "bioconda::samtools"}
    ]',  # JSON

    'test_commands': '["pytest tests/", "make test"]',  # JSON

    'install_commands': '["pip install -r requirements.txt"]',  # JSON

    'container_info': '{
        "type": "docker",
        "image": "quay.io/biocontainers/deepvariant:1.6.0--py39_0",
        "tested": true
    }'  # JSON
}
```

**Sources:**
- Dependencies: `requirements.txt`, `setup.py`, `environment.yml`, `package.json`, `Cargo.toml`
- Test commands: `.github/workflows/`, `.travis.yml`, `Makefile`, README
- Install commands: README, INSTALL.md, docs
- Container: Galaxy wrapper XML, BioContainers

### 📚 Documentation (6 fields)

```python
{
    'rawText': 'Complete README and documentation...',
    'htmlContent': '<html>...</html>',
    'help_text': '{"usage": "...", "options": [...]}',  # JSON
    'examples': '["example1", "example2"]',  # JSON
    'usage_guide': 'Step-by-step usage instructions',
    'citations': '[{"title": "DeepVariant paper", "doi": "..."}]'  # JSON
}
```

### 🔬 Scientific Information (3 fields)

```python
{
    'scientific_context': '{
        "methods": ["deep learning", "variant calling"],
        "use_cases": ["germline variant calling"],
        "biological_domain": "genomics"
    }',  # JSON

    'edam_operations': '["Variant calling", "Sequence analysis"]',  # JSON
    'edam_topics': '["Genomics", "DNA polymorphism"]'  # JSON
}
```

### 📊 Quality & Tracking (4 fields)

```python
{
    'quality_score': 0.85,           # 0.0-1.0 based on multiple factors
    'auto_discovered': 1,            # Boolean: was auto-discovered?
    'wrapper_path': '/path/to/deepvariant.xml',
    'usage_frequency': 42            # How often used
}
```

### 🏷️ Additional Fields (8 fields)

```python
{
    'tags': '["genomics", "ngs"]',   # JSON
    'nfcore_metadata': '',
    'best_practice_domains': '',
    'best_practice_functions': '',
    'is_dataset': 0,
    'dataset_metadata': '',
    'tool_state_template': '',
    'data_version': '1.0'
}
```

## What GitHub Information Is Available But NOT Saved?

During detection, we collect these fields that are **NOT currently saved** to database:

```python
# Available during detection but not persisted:
{
    'forks': 450,                           # Fork count
    'days_since_update': 5,                 # Days since last GitHub update
    'has_readme': True,
    'has_license': True,
    'has_ci_cd': True,
    'has_tests': True,
    'has_docs': True,
    'has_container': True,
    'has_linter': True,
    'has_examples': True,
    'has_releases': True,
    'has_paper': True,
    'classification': 'high_quality',       # Quality classification
    'detected_at': '2025-11-22T10:00:00',  # When detected

    # GitHub repo timestamps (from GitHub API):
    'repo.created_at': '2020-01-15T...',   # When repo created on GitHub
    'repo.updated_at': '2025-11-20T...',   # Last update on GitHub
    'repo.pushed_at': '2025-11-21T...'     # Last git push
}
```

## Adding More Fields

If you want to save additional GitHub information, you can:

### Option 1: Add to Database Schema

```python
# In add_enhanced_metadata_columns.py
columns_to_add = {
    'github_created_at': 'TIMESTAMP',  # When repo was created on GitHub
    'github_updated_at': 'TIMESTAMP',  # Last update on GitHub
    'github_forks': 'INTEGER',         # Fork count
    'has_tests': 'BOOLEAN',            # Has test suite
    'has_ci_cd': 'BOOLEAN',            # Has CI/CD
}
```

### Option 2: Store in Existing JSON Fields

```python
# In metadata_extractor_comprehensive.py
'scientific_context': json.dumps({
    ...existing fields...,
    'github_meta': {
        'forks': metadata.get('forks', 0),
        'created_at': metadata.get('created_at'),
        'has_tests': metadata.get('has_tests', False)
    }
})
```

## Real Example: DeepVariant

```sql
SELECT
    name,
    version,
    github_url,
    stars,
    created_at,
    discovery_date,
    dependencies,
    test_commands
FROM tools
WHERE name = 'DeepVariant';
```

**Result:**
```
name: DeepVariant
version: 1.6.0
github_url: https://github.com/google/deepvariant
stars: 1250
created_at: 2025-11-22T12:30:45.123456      (when added to our DB)
discovery_date: 2025-11-22T10:15:30.000000  (when we found it)
dependencies: [
    {"package_manager": "pip", "dependency": "tensorflow>=2.0"},
    {"package_manager": "conda", "dependency": "bioconda::bcftools"}
]
test_commands: ["bazel test //...", "python -m pytest"]
```

## Summary

**Currently Saved:** 44 fields including:
- ✅ GitHub URL
- ✅ Star count
- ✅ Discovery time (when we found it)
- ✅ Database entry time (when we saved it)
- ✅ Version (extracted from repo)
- ✅ Dependencies (for installation)
- ✅ Test commands (for execution)
- ✅ Container info (for running)

**NOT Currently Saved (but available):**
- ❌ GitHub repo creation time
- ❌ GitHub last push time
- ❌ Fork count
- ❌ Boolean flags (has_tests, has_ci_cd, etc.)

**Can Be Added:** Yes, easily! Just modify the database schema and integration code.

## Verification

Check what's actually saved:

```bash
# Verify enhanced metadata
python3 auto_update/scripts/verify_enhanced_metadata.py

# Query specific tool
sqlite3 backend/galaxy_ai_tools.db "
SELECT name, github_url, stars, discovery_date, version
FROM tools
WHERE auto_discovered = 1
LIMIT 5;
"
```

## Documentation Files

- `METADATA_COMPLETE_REFERENCE.md` - This file
- `20251122_ENHANCED_METADATA_PERSISTENCE_FIX.md` - How we fixed metadata saving
- `20251121_FINAL_STATUS.md` - Overall implementation status
