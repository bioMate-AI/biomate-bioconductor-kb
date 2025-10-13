# On-Demand Tool Installation Strategy

**Date:** 2025-10-13
**Approach:** Install tools automatically when workflows need them

---

## Overview

### ✅ Current Approach (CORRECT):
- Tools are **NOT pre-installed**
- Tools are **installed on-demand** when workflows execute
- Only install what's actually needed

### ❌ Previous Misunderstanding:
- ~~Install all 1,566 tools upfront~~
- ~~Heavy startup time~~
- ~~Large disk space requirement~~

---

## On-Demand Installation Flow

### Workflow Execution Trigger:

```
User runs workflow
    ↓
Workflow requires tool X
    ↓
Check: Is tool X installed?
    ↓
NO → Auto-install tool X
    ↓
Execute workflow with tool X
```

### Implementation:

From `backend/lib/galaxy/ai/tool_auto_installer.py`:

```python
def validate_workflow_tools(self, workflow_dict: Dict) -> Tuple[List, List, List]:
    """Check which tools are available, missing_custom, missing_toolshed"""
    available = []
    missing_custom = []
    missing_toolshed = []

    for step in workflow_dict['steps'].values():
        tool_id = step.get('tool_id')

        # Check if tool is installed
        if self.is_tool_installed(tool_id):
            available.append(tool_id)
        else:
            # Determine installation method
            if tool_id.startswith("toolshed"):
                missing_toolshed.append(tool_id)
            else:
                missing_custom.append(tool_id)

    return available, missing_custom, missing_toolshed

def install_missing_tools(self, workflow_dict: Dict):
    """Auto-install tools needed by workflow"""
    available, custom, toolshed = self.validate_workflow_tools(workflow_dict)

    # Install custom tools (our nfcore XMLs)
    for tool_id in custom:
        self.install_custom_tool(tool_id)

    # Install toolshed tools (via Galaxy Admin API)
    for tool_id in toolshed:
        self.install_toolshed_tool(tool_id)
```

---

## Tool Storage Structure

### Current Setup:
```
backend/tools/
├── nfcore_generated/     # 311 tools
├── nfcore_general/       # 35 tools
├── nfcore_lcms/          # 13 tools
├── biomni_generated/     # BioMni tools
└── [other categories]/   # Other tools

Total: 355 nfcore + ~250 other = ~600 tools ready
```

### On-Demand Access:
- Tools stored in `backend/tools/` (not in Galaxy)
- Copied to Galaxy **only when workflow needs them**
- Minimal Galaxy disk usage until used

---

## High-Priority Tools for Testing

### Category 1: Alignment Tools (Most Common)
```
1. bwa_mem              - DNA alignment
2. bowtie2_align        - RNA/DNA alignment
3. hisat2_align         - RNA-seq alignment
4. star_align           - RNA-seq alignment
5. samtools_sort        - SAM/BAM sorting
6. samtools_index       - BAM indexing
7. samtools_view        - SAM/BAM conversion
```

### Category 2: Quality Control
```
8. fastqc               - Read quality check
9. multiqc              - Aggregate QC reports
10. trimmomatic         - Read trimming
11. fastp               - Fast preprocessing
```

### Category 3: Variant Calling
```
12. gatk4_haplotypecaller  - Germline variants
13. bcftools_call          - Variant calling
14. bcftools_filter        - VCF filtering
15. vcftools               - VCF manipulation
```

### Category 4: Quantification
```
16. salmon_quant        - RNA-seq quantification
17. kallisto_quant      - RNA-seq quantification
18. featurecounts       - Gene counting
19. htseq_count         - Gene counting
```

### Category 5: Differential Expression
```
20. deseq2              - DE analysis
21. edger               - DE analysis
22. limma               - Microarray/RNA-seq DE
```

**Total: 22 high-priority tools for testing**

---

## Testing Strategy

### Phase 1: Test Auto-Installer with 5 Tools

**Objective:** Verify on-demand installation works

**Test Tools:**
1. `samtools_sort` (simple, commonly used)
2. `bwa_mem` (alignment, has container)
3. `fastqc` (QC, widely known)
4. `trimmomatic` (preprocessing)
5. `deseq2` (analysis, complex)

**Test Workflow:**
```python
# Create minimal test workflow
test_workflow = {
    "name": "Test Workflow",
    "steps": {
        "1": {"tool_id": "nfcore_samtools_sort"},
        "2": {"tool_id": "nfcore_bwa_mem"},
        "3": {"tool_id": "nfcore_fastqc"}
    }
}

# Test auto-installer
from backend.lib.galaxy.ai.tool_auto_installer import GalaxyToolAutoInstaller

installer = GalaxyToolAutoInstaller(
    galaxy_root="/path/to/galaxy",
    tools_dir="/Users/jingqiwang/biomate/backend/tools"
)

# Should auto-install 3 tools
installer.install_missing_tools(test_workflow)
```

**Expected Result:**
- 3 tools copied to Galaxy on-demand
- Workflow executes successfully
- No manual installation needed

---

### Phase 2: Test with Real Workflow

**Use Case:** RNA-seq analysis workflow

**Required Tools:**
1. hisat2_align
2. samtools_sort
3. featurecounts
4. deseq2

**Test:**
```python
rna_seq_workflow = load_workflow("rna_seq_analysis.ga")
installer.install_missing_tools(rna_seq_workflow)
# Should install only these 4 tools
```

**Validation:**
- Only 4 tools installed (not all 355)
- Tools available in Galaxy UI
- Workflow executes without errors

---

### Phase 3: Stress Test with Complex Workflow

**Use Case:** Multi-omics analysis

**Required Tools:** ~15 tools from various categories

**Validation:**
- All required tools installed
- No unnecessary tools installed
- Installation time: <1 minute
- Workflow executes successfully

---

## Installation Method Implementation

### Method 1: Custom Tool Installation (Our nfcore Tools)

```python
def install_custom_tool(self, tool_id: str):
    """Install custom tool from backend/tools/"""

    # 1. Find tool XML
    tool_xml = self._find_tool_xml(tool_id)
    if not tool_xml:
        raise ToolNotFoundError(f"Tool {tool_id} not found")

    # 2. Copy to Galaxy tools directory
    galaxy_tool_dir = Path(self.galaxy_root) / "tools" / "nfcore"
    galaxy_tool_dir.mkdir(parents=True, exist_ok=True)

    dest = galaxy_tool_dir / tool_xml.name
    shutil.copy(tool_xml, dest)

    # 3. Update tool_conf.xml (if not using auto-discovery)
    self._update_tool_conf(tool_id, dest)

    # 4. Reload Galaxy tools (optional - may require restart)
    self._reload_galaxy_tools()

    return dest

def _find_tool_xml(self, tool_id: str) -> Optional[Path]:
    """Find tool XML in backend/tools/"""
    tool_name = tool_id.replace("nfcore_", "")

    # Search in nfcore directories
    for subdir in ["nfcore_generated", "nfcore_general", "nfcore_lcms"]:
        tool_path = Path(self.tools_dir) / subdir / f"{tool_name}.xml"
        if tool_path.exists():
            return tool_path

    return None
```

### Method 2: Toolshed Tool Installation (Galaxy Official Tools)

```python
def install_toolshed_tool(self, tool_id: str):
    """Install tool from Galaxy Toolshed via Admin API"""

    # Parse toolshed URL
    # Example: toolshed.g2.bx.psu.edu/repos/iuc/samtools_sort/1.0
    parts = tool_id.split("/")
    owner = parts[-3]
    name = parts[-2]

    # Use Galaxy Admin API
    payload = {
        "tool_shed_url": "https://toolshed.g2.bx.psu.edu",
        "name": name,
        "owner": owner,
        "install_tool_dependencies": True,
        "install_repository_dependencies": True
    }

    response = requests.post(
        f"{self.galaxy_api_url}/api/tool_shed_repositories",
        json=payload,
        headers={"x-api-key": self.api_key}
    )

    return response.json()
```

---

## Tool Configuration for Galaxy

### Option 1: Auto-Discovery (Recommended)

Add to `config/tool_conf.xml`:

```xml
<toolbox>
  <!-- Enable auto-discovery for on-demand tools -->
  <section id="nfcore" name="nf-core Tools">
    <tool_dir dir="tools/nfcore" />
  </section>
</toolbox>
```

**Advantages:**
- No manual tool registration
- New tools automatically discovered
- Minimal configuration

**Galaxy Configuration:**
```yaml
# config/galaxy.yml
galaxy:
  watch_tool_data_dir: true
  tool_config_file: config/tool_conf.xml
  tool_data_table_config_path: config/tool_data_table_conf.xml
```

---

### Option 2: Dynamic Tool Registration (Advanced)

Use Galaxy's tool reloading API:

```python
def reload_galaxy_tools(self):
    """Trigger Galaxy to reload tool panel"""
    response = requests.post(
        f"{self.galaxy_api_url}/api/tools/reload",
        headers={"x-api-key": self.admin_api_key}
    )
    return response.status_code == 200
```

**Note:** May require Galaxy restart for some configurations

---

## Disk Space Management

### On-Demand Advantage:

| Scenario | Tools Installed | Disk Usage |
|----------|----------------|------------|
| Pre-install all | 1,566 tools | ~100 GB |
| On-demand (typical user) | ~20 tools | ~5 GB |
| On-demand (power user) | ~100 tools | ~20 GB |

**Savings:** 80-95% disk space reduction

### Container Pull Strategy:

**On first tool use:**
```
1. Copy tool XML to Galaxy
2. User executes tool
3. Galaxy pulls container (if not cached)
4. Container cached for future use
5. Total time: 2-10 minutes first use
6. Future uses: <5 seconds
```

---

## Code Testing Strategy

### Unit Tests:

```python
# test_auto_installer.py

def test_find_tool_xml():
    """Test tool XML discovery"""
    installer = GalaxyToolAutoInstaller(
        tools_dir="backend/tools"
    )

    # Should find tool
    tool = installer._find_tool_xml("nfcore_samtools_sort")
    assert tool is not None
    assert tool.name == "samtools_sort.xml"

    # Should not find non-existent tool
    tool = installer._find_tool_xml("nfcore_nonexistent")
    assert tool is None

def test_workflow_validation():
    """Test workflow tool validation"""
    workflow = {
        "steps": {
            "1": {"tool_id": "nfcore_bwa_mem"},
            "2": {"tool_id": "nfcore_samtools_sort"}
        }
    }

    available, custom, toolshed = installer.validate_workflow_tools(workflow)
    assert len(custom) == 2  # Both are custom tools

def test_install_custom_tool():
    """Test installing a custom tool"""
    installer.install_custom_tool("nfcore_samtools_sort")

    # Verify tool was copied
    galaxy_tool = Path(installer.galaxy_root) / "tools/nfcore/samtools_sort.xml"
    assert galaxy_tool.exists()
```

### Integration Tests:

```python
def test_workflow_execution_with_auto_install():
    """Test full workflow with auto-installation"""

    # 1. Create test workflow
    workflow = create_test_workflow()

    # 2. Upload test data
    test_data = upload_test_data()

    # 3. Execute workflow (should auto-install tools)
    result = execute_workflow(workflow, test_data)

    # 4. Verify execution succeeded
    assert result.state == "ok"
    assert all(step.state == "ok" for step in result.steps)
```

---

## Documentation for Users

### User Guide:

```markdown
# Using nf-core Tools in BioMate

## Automatic Installation

All nf-core tools are installed automatically when you run workflows.

### Example:

1. Create or import a workflow
2. Add nf-core tools (e.g., "BWA-MEM alignment")
3. Run the workflow
4. BioMate automatically installs required tools
5. Workflow executes

**No manual installation needed!**

### First Use:

- First time using a tool: 2-10 minutes (downloading container)
- Subsequent uses: <5 seconds (container cached)

### Available Tools:

- 355 nf-core tools ready now
- 1,211 more tools available on-demand
- Total: 1,566 nf-core tools
```

---

## Summary

### ✅ On-Demand Approach Benefits:

1. **Minimal disk usage** - Only install what's needed (~95% savings)
2. **Faster Galaxy startup** - No 1,566 tools to load
3. **Better UX** - Tools appear when needed
4. **Automatic** - No user intervention required
5. **Scalable** - Can add 1,211 more tools without impact

### 🎯 Testing Focus:

1. **Unit tests** - Tool discovery, XML parsing
2. **Integration tests** - 22 high-priority tools
3. **Workflow tests** - Real RNA-seq workflow
4. **Performance tests** - Installation time, concurrency

### 📋 Next Steps:

1. Test auto-installer with 5 sample tools
2. Validate with real RNA-seq workflow
3. Generate remaining 1,211 tools (for completeness)
4. Document for end users

**Estimated testing time:** 2-3 hours (much faster than installing all tools!)
