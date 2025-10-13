# Tool Installation Strategy for Missing Tools

**Date**: 2025-10-13
**Issue**: Tools not in Galaxy Toolshed cannot be auto-installed

---

## 🎯 **The Problem**

Galaxy's auto-install mechanism works like this:

```python
# In workflow execution, Galaxy checks:
if tool_id.startswith("toolshed.g2.bx.psu.edu"):
    # Tool from Toolshed - can auto-install
    install_from_toolshed(tool_id)
else:
    # Local tool - must already be present
    if not tool_exists_locally(tool_id):
        raise ToolNotFoundError
```

**Our 602 missing tools are NOT in Toolshed** → Cannot auto-install

---

## ✅ **Solution Options**

### **Option 1: Local Tool Directory (Immediate)**

**How it works**:
1. Install tools directly into Galaxy's local tool directory
2. Register in `tool_conf.xml`
3. Galaxy loads them on startup

**Implementation**:

```bash
# Directory structure
/path/to/galaxy/
├── config/
│   └── tool_conf.xml          # Register tools here
└── tools/
    └── biomate_custom/         # Our custom tools
        ├── nfcore_missing/
        │   ├── gatk4_haplotypecaller.xml
        │   ├── bcftools_annotate.xml
        │   └── ...
        └── biomni_missing/
            ├── rdkit.xml
            ├── openmm.xml
            └── ...
```

**tool_conf.xml**:
```xml
<?xml version='1.0' encoding='utf-8'?>
<toolbox>
    <!-- Existing Toolshed tools -->
    <tool_dir dir="shed_tools"/>

    <!-- Our custom BioMate tools -->
    <section id="biomate_custom" name="BioMate Custom Tools">
        <tool file="biomate_custom/nfcore_missing/gatk4_haplotypecaller.xml"/>
        <tool file="biomate_custom/nfcore_missing/bcftools_annotate.xml"/>
        <!-- ... all 602 tools ... -->
    </section>
</toolbox>
```

**Pros**:
- ✅ Works immediately
- ✅ No Toolshed submission required
- ✅ Full control over tool versions

**Cons**:
- ❌ Manual installation required
- ❌ Not portable across Galaxy instances
- ❌ No auto-update mechanism

---

### **Option 2: Private Tool Repository (Better)**

**How it works**:
1. Create Git repository with our tools
2. Galaxy can install from Git using Ephemeris
3. Semi-automated deployment

**Implementation**:

```bash
# Create tool repository
mkdir -p biomate-galaxy-tools
cd biomate-galaxy-tools

# Organize tools
tools/
├── gatk4_haplotypecaller/
│   ├── gatk4_haplotypecaller.xml
│   ├── test-data/
│   └── .shed.yml
├── bcftools_annotate/
│   ├── bcftools_annotate.xml
│   ├── test-data/
│   └── .shed.yml
└── ...

# Push to GitHub
git init
git add .
git commit -m "BioMate custom Galaxy tools"
git remote add origin https://github.com/biomate/galaxy-tools.git
git push -u origin main
```

**Install via Ephemeris**:
```yaml
# tools.yml
tools:
  - name: gatk4_haplotypecaller
    owner: biomate
    revisions:
      - latest
    tool_panel_section_label: "BioMate Custom Tools"
    install_repository_dependencies: true
    install_resolver_dependencies: true
```

```bash
# Install all tools from YAML
shed-tools install -t tools.yml -g http://localhost:8080 -a <api-key>
```

**Pros**:
- ✅ Version controlled
- ✅ Semi-automated installation
- ✅ Shareable across instances

**Cons**:
- ❌ Still requires manual trigger
- ❌ Not as seamless as Toolshed

---

### **Option 3: Publish to Main Galaxy Toolshed (Best Long-term)**

**How it works**:
1. Submit tools to official Galaxy Toolshed
2. They become available for auto-install like any other tool
3. Full Galaxy ecosystem integration

**Requirements**:
- Tool must pass quality checks
- Test data required
- Documentation complete
- Container available

**Process**:
```bash
# 1. Prepare tool for submission
tools/gatk4_haplotypecaller/
├── gatk4_haplotypecaller.xml     # Tool definition
├── .shed.yml                      # Repository metadata
├── test-data/                     # Test input/output files
├── tool_dependencies.xml          # (optional, use containers)
└── README.md                      # Documentation

# 2. Create Toolshed account
# Visit: https://toolshed.g2.bx.psu.edu/

# 3. Submit tool via planemo
planemo shed_init --name=gatk4_haplotypecaller \
                  --owner=biomate \
                  --description="GATK4 HaplotypeCaller" \
                  --category=Variant_Calling

planemo shed_create --shed_target=toolshed

# 4. Update tool
planemo shed_update --shed_target=toolshed
```

**Pros**:
- ✅ Full auto-install support
- ✅ Discoverable by all Galaxy users
- ✅ Official ecosystem integration
- ✅ Community visibility

**Cons**:
- ❌ Time-consuming (review process)
- ❌ Must meet quality standards
- ❌ 602 tools = 602 submissions

---

## 🚀 **Recommended Hybrid Approach**

### **Phase 1: Local Installation (Now)**
Install our 602 tools locally for immediate use:

```bash
# Copy tools to Galaxy
cp -r backend/tools/nfcore_lcms /path/to/galaxy/tools/biomate_custom/
cp -r backend/tools/nfcore_general /path/to/galaxy/tools/biomate_custom/

# Auto-generate tool_conf.xml section
python3 scripts/generate_tool_conf_section.py > tool_conf_biomate.xml

# Add to Galaxy config
# In galaxy.yml:
tool_config_file: tool_conf.xml,tool_conf_biomate.xml

# Restart Galaxy
./run.sh
```

### **Phase 2: Detect and Install Missing Tools**
Modify workflow execution to detect missing tools and offer installation:

```python
# In workflow validator/executor
def validate_workflow_tools(workflow):
    missing_tools = []

    for step in workflow['steps']:
        tool_id = step['tool_id']

        # Check if tool exists
        if not self.toolbox.get_tool(tool_id):
            # Check if it's a BioMate custom tool
            if tool_id in BIOMATE_CUSTOM_TOOLS:
                missing_tools.append({
                    'tool_id': tool_id,
                    'install_method': 'biomate_custom',
                    'install_command': f'cp {tool_id}.xml to tools/biomate_custom/'
                })
            elif tool_id.startswith('toolshed.g2.bx.psu.edu'):
                missing_tools.append({
                    'tool_id': tool_id,
                    'install_method': 'toolshed',
                    'install_command': f'install_from_toolshed({tool_id})'
                })

    if missing_tools:
        # Show user installation instructions
        raise ToolInstallationRequiredError(missing_tools)
```

### **Phase 3: Selective Toolshed Submission (Future)**
Submit high-priority tools to Toolshed:

**Priority for Toolshed submission**:
1. Most frequently used tools (top 50)
2. Tools with unique functionality
3. Tools requested by community

**Batch submission**:
- Batch 1: Top 20 most-used tools → Toolshed
- Batch 2: Next 50 high-priority → Toolshed
- Remaining: Keep as local tools for now

---

## 📋 **Implementation Script**

Let me create a script to generate the tool_conf.xml section:

```python
# scripts/generate_tool_conf_section.py
import os
from pathlib import Path

def generate_tool_conf_section():
    """Generate tool_conf.xml section for BioMate custom tools."""

    tool_dirs = [
        Path(__file__).parent.parent / 'tools' / 'nfcore_lcms',
        Path(__file__).parent.parent / 'tools' / 'nfcore_general',
        # Add more as we implement them
    ]

    xml = ['<?xml version="1.0" encoding="utf-8"?>']
    xml.append('<toolbox>')
    xml.append('    <section id="biomate_custom" name="BioMate Custom Tools">')

    for tool_dir in tool_dirs:
        if tool_dir.exists():
            for xml_file in sorted(tool_dir.glob('*.xml')):
                rel_path = xml_file.relative_to(Path(__file__).parent.parent)
                xml.append(f'        <tool file="{rel_path}"/>')

    xml.append('    </section>')
    xml.append('</toolbox>')

    return '\n'.join(xml)

if __name__ == '__main__':
    print(generate_tool_conf_section())
```

---

## 🎯 **Immediate Action Plan**

### **For Development/Testing** (Local Installation):

1. **Copy tools to Galaxy**:
```bash
cd /path/to/galaxy
mkdir -p tools/biomate_custom
cp -r /path/to/biomate/backend/tools/* tools/biomate_custom/
```

2. **Generate tool config**:
```bash
cd /path/to/biomate/backend
python3 scripts/generate_tool_conf_section.py > /path/to/galaxy/config/tool_conf_biomate.xml
```

3. **Update Galaxy config**:
```yaml
# galaxy.yml or galaxy.ini
tool_config_file: config/tool_conf.xml,config/tool_conf_biomate.xml
```

4. **Restart Galaxy**:
```bash
cd /path/to/galaxy
./run.sh restart
```

5. **Verify tools loaded**:
```bash
# Check Galaxy log for:
# "Loaded tool biomate_custom/gatk4_haplotypecaller"
```

### **For Production** (Repository + Toolshed):

1. **Create tool repository**: GitHub repo with all tools
2. **Install via Ephemeris**: Automated installation script
3. **Submit high-priority to Toolshed**: Top 50 tools for wider use
4. **Monitor usage**: Track which tools are most used
5. **Batch Toolshed submission**: Submit popular tools over time

---

## ✅ **Summary**

**Short Answer**: Tools not in Toolshed **cannot** be auto-installed like Toolshed tools.

**Solutions**:
1. **Now**: Install locally in Galaxy's tool directory (manual but immediate)
2. **Soon**: Git repository + Ephemeris (semi-automated)
3. **Future**: Submit to Toolshed (full auto-install, but time-consuming for 602 tools)

**Recommended**: Hybrid approach - local installation now, selective Toolshed submission for high-priority tools later.

Would you like me to create the tool configuration generation script?
