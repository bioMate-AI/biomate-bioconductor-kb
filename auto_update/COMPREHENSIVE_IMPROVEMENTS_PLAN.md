# Comprehensive Improvements Plan: Complete Metadata & Testing

## Issues Identified

1. ❌ Not checking if tool already exists with version comparison
2. ❌ Not collecting dependency information
3. ❌ Not installing dependencies before testing
4. ❌ Not extracting test commands/examples from docs
5. ❌ Not collecting invocation requirements

## Implementation Status

### ✅ COMPLETED

#### 1. Version Checking with Database (integrate_tools.py)

**New Methods:**
- `get_tool_version(tool_id)` - Get existing tool version from database
- `is_newer_version(tool_id, new_version)` - Compare versions intelligently

**Version Formats Supported:**
- Semver: `1.2.3`, `v1.2.3`
- Git commits: `git.20251121`
- Unknown: `unknown`

**Logic:**
```python
existing_version = db.get_tool_version("auto_gget")
if existing_version:
    if not db.is_newer_version("auto_gget", new_version):
        # Skip - same or older version
        return
```

#### 2. Enhanced Metadata Extraction (enhanced_metadata_extractor.py)

**Extracts:**
- **Version**: From releases, tags, VERSION files, package.json, Cargo.toml, pyproject.toml
- **Dependencies**: From requirements.txt, setup.py, pyproject.toml, environment.yml, Cargo.toml, package.json
- **Test Commands**: From .github/workflows/, .travis.yml, Makefile, README
- **Usage Examples**: From README code blocks
- **Install Commands**: From README installation sections

**Example Output:**
```python
{
    'version': '1.2.3',
    'dependencies': [
        {'package_manager': 'pip', 'dependency': 'numpy>=1.20', 'source': 'requirements.txt'},
        {'package_manager': 'pip', 'dependency': 'pandas', 'source': 'setup.py'}
    ],
    'test_commands': ['pytest tests/', 'python -m pytest'],
    'usage_examples': ['gget ref homo_sapiens', 'gget blast ATCG...'],
    'install_commands': ['pip install gget', 'conda install -c bioconda gget']
}
```

### 🔄 IN PROGRESS (Need to Implement)

#### 3. Dependency Installer (NEW FILE NEEDED)

**File**: `dependency_installer.py`

**Features:**
- Install dependencies based on package manager
- Support: pip, conda, npm, cargo
- Create isolated environments
- Handle installation failures gracefully

**Pseudo-code:**
```python
class DependencyInstaller:
    def install_dependencies(self, dependencies: List[Dict], container_type: str):
        for dep in dependencies:
            if dep['package_manager'] == 'pip':
                self.install_pip(dep['dependency'])
            elif dep['package_manager'] == 'conda':
                self.install_conda(dep['dependency'])
            # ...
```

#### 4. Update Test Executor to Use Dependencies and Real Commands

**Changes Needed in `test_tool_execution.py`:**

1. Accept enhanced metadata (with dependencies, test_commands)
2. Install dependencies before testing
3. Use extracted test commands instead of generic `--help`
4. Use extracted usage examples for realistic tests

**Flow:**
```
1. Extract enhanced metadata (version, dependencies, test_commands)
2. Check if newer version exists
   → If not newer: SKIP
3. Pull container
4. Install dependencies IN container
5. Fetch real test data
6. Execute test commands from metadata
7. Verify outputs
```

#### 5. Update Pipeline Integration (run_pipeline.py)

**Changes:**

```python
# Stage 1.4: Extract enhanced metadata
from enhanced_metadata_extractor import EnhancedMetadataExtractor

enhanced_extractor = EnhancedMetadataExtractor(github_token)
enhanced_metadata = enhanced_extractor.extract(discovery)

# Stage 1.5: Check version (NEW - before feasibility)
tool_id = f"auto_{tool_name.lower().replace('-', '_')}"
db_integrator = DatabaseIntegrator(self.db_path)
db_integrator.connect()

if db_integrator.tool_exists(tool_id):
    new_version = enhanced_metadata.get('version', 'unknown')

    if not db_integrator.is_newer_version(tool_id, new_version):
        logger.info(f"  [SKIP] Same or older version: {new_version}")
        self.stats.add('skipped_old_version')
        db_integrator.close()
        return

db_integrator.close()

# Continue with feasibility, wrapper generation, etc.
```

### 📋 NEW PIPELINE FLOW

```
┌─────────────────────────────────────────────┐
│ STAGE 1: Detection (Parallel)              │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ STAGE 1.4: Enhanced Metadata Extraction ✨ │
│ ├─ Version from releases/tags/files        │
│ ├─ Dependencies from all package files     │
│ ├─ Test commands from CI/Makefile/README   │
│ ├─ Usage examples from docs                │
│ └─ Install commands                         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ STAGE 1.5: Version Check ✨ NEW             │
│ ├─ Check if tool exists in database        │
│ ├─ Compare versions (existing vs new)      │
│ └─ SKIP if same or older version           │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ STAGE 1.6: LLM Feasibility Check           │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ STAGE 2-3: Documentation & Wrapper         │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ STAGE 4: Validation                        │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ STAGE 5: Testing ✨ ENHANCED                │
│ ├─ Install dependencies in container       │
│ ├─ Fetch real test data from repo          │
│ ├─ Use extracted test commands             │
│ ├─ Use usage examples for tests            │
│ └─ Verify actual functionality             │
└─────────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────────┐
│ STAGE 6: Integration                       │
│ └─ Only if tests pass with real data       │
└─────────────────────────────────────────────┘
```

### 🎯 EXPECTED IMPROVEMENTS

**Before:**
- Tools tested with dummy `--help` commands
- No version checking → waste time on old versions
- No dependency installation → all tests fail
- Generic test data → not realistic

**After:**
- ✅ Skip old versions automatically
- ✅ Install all dependencies before testing
- ✅ Use real test commands from CI/README
- ✅ Use real test data from repo
- ✅ Verify actual tool functionality

### 📊 NEW STATISTICS

```python
self.stats = {
    'detected': 0,
    'enhanced_metadata_extracted': 0,  # NEW
    'skipped_old_version': 0,           # NEW
    'dependencies_installed': 0,        # NEW
    'real_test_commands_used': 0,       # NEW
    'feasibility_passed': 0,
    'wrappers_generated': 0,
    'tests_passed': 0,
    'tests_failed': 0,
    'integrated': 0,
}
```

### 🚀 NEXT STEPS

1. **Create dependency_installer.py** (HIGH PRIORITY)
2. **Update test_tool_execution.py** to use dependencies and test commands
3. **Update run_pipeline.py** to integrate enhanced metadata and version checking
4. **Test with September 2025 tools again** to verify improvements
5. **Run full-year 2025 data load** after verification

## TESTING STRATEGY

**Phase 1: Unit Tests**
- Test version comparison logic
- Test dependency extraction
- Test dependency installation

**Phase 2: Integration Test**
- Run pipeline on 1-2 known tools with real dependencies
- Verify dependencies are installed
- Verify test commands execute correctly

**Phase 3: Production Run**
- Process September 2025 (5 tools)
- Process Q3 2025 (3 months in batches)
- Process full year 2025 if successful
