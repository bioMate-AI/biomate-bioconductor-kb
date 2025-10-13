# Tool Generation Action Plan

**Date:** 2025-10-13
**Status:** Analysis Complete, Ready for Targeted Generation

---

## Current Status

### What We Have:
- **355 nfcore tools already generated** in backend/tools/nfcore_*
- **609 total tools** across all categories in backend/tools/

### Breakdown of 355 Generated nfcore Tools:
- **327 tools (92%) are NOT in Galaxy Toolshed** ✓ Good additions!
- **28 tools (8%) overlap with Galaxy** - Keep ours (have nf-core metadata)

### What We Need:
- **1,211 truly missing nfcore tools** to be generated
- Quality improvements for existing generated tools (fix container lines, better parameters)

---

## Key Findings

### 1. No Duplication Issue
- Out of 1,632 total nfcore modules
- Only **94 are in Galaxy Toolshed** (5.8%)
- **1,538 are NOT in Galaxy** (94.2%)
- We've generated 355, so 1,211 remaining

### 2. Quality Comparison

**Our Generated Tools (admixture.xml example):**
```xml
<description>ADMIXTURE is a program for estimating ancestry...</description>
<requirement type="package" version="1.3.0">admixture</requirement>
<container type="docker">${ workflow.containerEngine == </container> <!-- BROKEN -->
```

**Issues:**
- Broken container line (Nextflow syntax leaked through)
- Need proper Galaxy biocontainer reference
- Parameters could be more detailed

**Needed Improvements:**
```xml
<description>Estimate ancestry from SNP genotype data</description>
<requirement type="package" version="1.3.0">admixture</requirement>
<container type="docker">quay.io/biocontainers/admixture:1.3.0--h86a1fc2_5</container>
```

---

## Action Plan

### Phase 1: Add 355 Existing Tools to Galaxy (IMMEDIATE)
**Task:** Copy existing 355 generated tools to Galaxy tool directory

**Commands:**
```bash
# Copy tools to Galaxy
cp backend/tools/nfcore_generated/*.xml /path/to/galaxy/tools/nfcore/
cp backend/tools/nfcore_general/*.xml /path/to/galaxy/tools/nfcore/
cp backend/tools/nfcore_lcms/*.xml /path/to/galaxy/tools/nfcore/

# Update Galaxy tool_conf.xml
# Add <section id="nfcore" name="nf-core Tools">
```

**Result:** 355 tools instantly available (327 new + 28 improved versions)

---

### Phase 2: Fix Quality Issues in Existing Tools
**Priority:** High (before generating more)

**Issues to Fix:**
1. **Broken container lines** - Remove Nextflow syntax, use proper biocontainer references
2. **Better descriptions** - Extract from nf-core meta.yml
3. **Proper parameters** - Map nf-core inputs to Galaxy params
4. **Better help text** - Include tool homepage, documentation links

**Script:** `fix_existing_tool_quality.py`
- Parse existing 355 XMLs
- Fix container lines
- Enhance descriptions from nf-core meta.yml
- Add proper citations

---

###Phase 3: Generate 1,211 Missing Tools (HIGH QUALITY)
**Priority:** Medium (after fixing existing)

**Approach:**
1. Load list from `TOOL_COMPARISON_AND_MISSING_2025-10-13.json`
2. For each missing tool:
   - Extract complete metadata from nf-core repo (meta.yml + main.nf)
   - Parse proper biocontainer reference
   - Generate high-quality Galaxy XML with:
     * Clear description
     * Proper container reference
     * Well-defined parameters
     * Comprehensive help text
     * Citations

**Batching Strategy:**
- Generate 100 at a time
- Validate each batch
- Add to Galaxy incrementally

---

### Phase 4: Quality Comparison with Galaxy
**For 28 Overlapping Tools:**

Compare our version vs Galaxy version:
- Check description quality
- Check parameter completeness
- Check help text
- Recommend improvements

**Goal:** Ensure our versions are equal or better quality

---

## Detailed Steps

### Step 1: Immediate - Add Existing Tools to Galaxy

```bash
# 1. Create nfcore section in Galaxy
mkdir -p /path/to/galaxy/tools/nfcore

# 2. Copy all generated tools
find backend/tools/nfcore_* -name "*.xml" -exec cp {} /path/to/galaxy/tools/nfcore/ \;

# 3. Update tool_conf.xml
# Add: <section id="nfcore" name="nf-core Tools">

# 4. Restart Galaxy
```

**Time:** 10 minutes
**Result:** 355 tools available immediately

---

### Step 2: Fix Existing Tool Quality

**Script to create:** `fix_existing_tool_quality.py`

```python
# For each existing tool XML:
# 1. Parse with ElementTree
# 2. Fix container line:
#    - Read nf-core main.nf for container
#    - Convert to proper biocontainer format
# 3. Enhance description from meta.yml
# 4. Add proper citations
# 5. Save fixed version
```

**Time:** 2 hours development + 10 minutes execution
**Result:** 355 high-quality tools

---

### Step 3: Generate Missing 1,211 Tools

**High-Quality Generator:**

```python
class HighQualityNfcoreGenerator:
    def parse_nfcore_metadata(self, module_path):
        """Extract complete metadata from nf-core repo."""
        meta_yml = parse_yaml(module_path / "meta.yml")
        main_nf = parse_nextflow(module_path / "main.nf")

        return {
            'name': meta_yml['name'],
            'description': meta_yml['description'],
            'container': extract_container_from_nf(main_nf),
            'inputs': parse_inputs(meta_yml),
            'outputs': parse_outputs(meta_yml),
            'homepage': meta_yml.get('tools', [{}])[0].get('homepage'),
            'documentation': meta_yml.get('tools', [{}])[0].get('documentation'),
        }

    def generate_galaxy_xml(self, metadata):
        """Generate high-quality Galaxy tool XML."""
        # Proper container reference
        # Clear descriptions
        # Well-defined parameters
        # Comprehensive help
        # Citations
```

**Time:** 4 hours development + 2 hours generation (100/batch × 13 batches)
**Result:** 1,211 high-quality tools

---

## Priority Recommendations

### Immediate (Today):
1. ✅ Analysis complete
2. ⏳ Add existing 355 tools to Galaxy
3. ⏳ Test auto-installation system

### Short-term (This Week):
1. Fix quality issues in existing 355 tools
2. Generate first batch of 100 missing tools
3. Compare quality with Galaxy's versions

### Medium-term (Next Week):
1. Generate remaining 1,111 tools (11 batches of 100)
2. Validate all tools work with workflows
3. Document tool catalog

---

## Files Reference

### Analysis Files:
- `ALL_NFCORE_MODULES_2025-10-13.json` - Complete list of 1,632 modules
- `TOOL_COMPARISON_AND_MISSING_2025-10-13.json` - Comparison analysis
- `OVERLAP_ANALYSIS_CORRUPTION_REPORT_2025-10-13.md` - Corruption analysis
- `COMPLETE_ANALYSIS_SUMMARY_2025-10-13.md` - Complete summary

### Generated Tools:
- `backend/tools/nfcore_generated/` - 271 tools
- `backend/tools/nfcore_general/` - 54 tools
- `backend/tools/nfcore_lcms/` - 30 tools
- **Total:** 355 tools

### Missing Tools List:
```json
{
  "truly_missing_list": [
    "abricate/run",
    "abricate/summary",
    ...1,211 tools total
  ]
}
```

---

## Success Metrics

### Quality Metrics:
- ✓ Proper biocontainer references (not broken Nextflow syntax)
- ✓ Clear, concise descriptions
- ✓ Well-defined parameters with help text
- ✓ Comprehensive help sections
- ✓ Proper citations

### Coverage Metrics:
- Current: 355 tools (21.8% of nfcore)
- After missing generation: 1,566 tools (96.0% of nfcore)
- In Galaxy Toolshed: 94 tools (5.8% of nfcore)

**Our Contribution:** +1,472 high-quality nfcore tools for Galaxy!

---

## Next Commands

```bash
# 1. Add existing tools to Galaxy
./scripts/add_tools_to_galaxy.sh

# 2. Fix quality issues
python3 backend/scripts/fix_existing_tool_quality.py

# 3. Generate first batch of missing tools
python3 backend/scripts/generate_production_tools.py \
  --missing-list backend/TOOL_COMPARISON_AND_MISSING_2025-10-13.json \
  --batch-size 100 \
  --output-dir backend/tools/nfcore_batch1

# 4. Validate and add to Galaxy
./scripts/validate_and_add_batch.sh batch1
```

---

## Summary

**Current State:**
- 355 nfcore tools generated (327 new, 28 improved)
- Quality issues in existing tools (broken containers)
- 1,211 truly missing tools identified

**Action Required:**
1. **Immediate:** Add 355 existing tools to Galaxy (10 min)
2. **High Priority:** Fix quality issues (2-3 hours)
3. **Medium Priority:** Generate 1,211 missing tools (6-8 hours total)

**Expected Result:**
- 1,566 high-quality nfcore tools in Galaxy
- 96% coverage of nfcore modules
- +1,472 more than Galaxy Toolshed currently has
