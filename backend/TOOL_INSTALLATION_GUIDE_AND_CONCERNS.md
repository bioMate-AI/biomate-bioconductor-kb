# Tool Installation Guide and Concerns

**Date:** 2025-10-13
**Target:** Install 355 existing + 1,211 new nfcore tools into Galaxy

---

## Overview

### What We're Installing:
- **355 existing tools** (after quality fixes)
- **1,211 new tools** (to be generated)
- **Total: 1,566 nfcore tools**

### Installation Methods:
1. **Custom tools** (our generated XMLs) → File copy + tool_conf.xml update
2. **Toolshed tools** (if any overlap) → Galaxy Admin API

---

## Installation Process

### Method 1: Custom Tool Installation (Our Generated Tools)

#### Step 1: Fix Existing Tools
```bash
cd /Users/jingqiwang/biomate
python3 backend/scripts/fix_existing_tool_quality.py
```

**What this does:**
- Fixes broken container references
- Improves descriptions
- Adds proper biocontainer URLs
- Enhances help text

**Time:** ~5 minutes

---

#### Step 2: Copy Tools to Galaxy
```bash
# Create nfcore tools directory
mkdir -p $GALAXY_ROOT/tools/nfcore

# Copy all nfcore tools
find backend/tools/nfcore_* -name "*.xml" -exec cp {} $GALAXY_ROOT/tools/nfcore/ \;

# Verify
ls $GALAXY_ROOT/tools/nfcore/*.xml | wc -l  # Should show 355
```

**Time:** ~1 minute

---

#### Step 3: Update Galaxy tool_conf.xml

Add to `$GALAXY_ROOT/config/tool_conf.xml`:

```xml
<toolbox>
  <!-- Existing sections... -->

  <!-- nf-core Tools Section -->
  <section id="nfcore" name="nf-core Tools">
    <label text="Genomics" id="nfcore_genomics"/>
    <tool file="nfcore/samtools_sort.xml" />
    <tool file="nfcore/samtools_index.xml" />
    <tool file="nfcore/bwa_mem.xml" />
    <!-- ... all 355 tools ... -->
  </section>
</toolbox>
```

**OR use auto-discovery:**

```xml
<section id="nfcore" name="nf-core Tools">
  <tool_dir dir="tools/nfcore" />
</section>
```

**Time:** ~2 minutes (auto-discovery) or 10 minutes (manual listing)

---

#### Step 4: Restart Galaxy
```bash
# Stop Galaxy
$GALAXY_ROOT/run.sh --stop-daemon

# Start Galaxy
$GALAXY_ROOT/run.sh --daemon

# Check logs
tail -f $GALAXY_ROOT/galaxy.log
```

**Time:** ~2 minutes

---

### Method 2: Programmatic Installation (Using BioMate Auto-Installer)

Use the existing auto-installer from `backend/lib/galaxy/ai/tool_auto_installer.py`:

```python
from backend.lib.galaxy.ai.tool_auto_installer import GalaxyToolAutoInstaller

installer = GalaxyToolAutoInstaller(
    galaxy_root="/path/to/galaxy",
    tools_dir="/Users/jingqiwang/biomate/backend/tools",
    galaxy_api_url="http://localhost:8080"
)

# Install all nfcore tools
tool_files = [
    "backend/tools/nfcore_generated/*.xml",
    "backend/tools/nfcore_general/*.xml",
    "backend/tools/nfcore_lcms/*.xml",
]

for pattern in tool_files:
    installer.install_custom_tools(pattern)

print("✓ All tools installed")
```

**Time:** ~5 minutes

---

## Concerns and Difficulties

### 🔴 **CRITICAL CONCERNS**

#### 1. **Container Availability**
**Issue:** Tools require biocontainers to be available

**Current status:**
- Most containers: `quay.io/biocontainers/tool:version`
- Some broken references need fixing

**Difficulty:** ⚠️ **MEDIUM**

**Solution:**
```python
# In fix_existing_tool_quality.py, we:
# 1. Extract container from nf-core main.nf
# 2. Use proper quay.io/biocontainers/* URLs
# 3. Fall back to :latest if version not found
```

**Risk:**
- Some containers may not exist on quay.io
- Need fallback to build from Dockerfile

**Mitigation:**
- Generate list of all required containers
- Pre-pull containers before installation
- Create Dockerfile for missing containers

---

#### 2. **Tool Parameter Validation**
**Issue:** Galaxy validates tool inputs/outputs at startup

**Difficulty:** ⚠️ **MEDIUM-HIGH**

**Potential problems:**
- Missing required parameters
- Invalid parameter types
- Broken file format specifications

**Solution:**
```bash
# Validate tools before installation
planemo test --galaxy_root $GALAXY_ROOT tools/nfcore/*.xml

# OR use Galaxy's built-in validation
galaxy-tool-util verify tools/nfcore/*.xml
```

**Risk:**
- Invalid tools will prevent Galaxy startup
- Need to fix or remove broken tools

**Mitigation:**
- Test tools in batches of 50-100
- Create backup of tool_conf.xml before changes
- Have rollback plan ready

---

#### 3. **Galaxy Startup Time**
**Issue:** 1,566 tools will significantly increase startup time

**Difficulty:** ⚠️ **LOW-MEDIUM**

**Expected impact:**
- Current startup: ~30 seconds
- With 1,566 tools: ~2-5 minutes
- Tool panel loading: ~10-30 seconds

**Solution:**
- Enable tool panel caching
- Use lazy loading for tool sections
- Consider tool panel views

**Config changes needed:**
```yaml
# galaxy.yml
galaxy:
  tool_cache_data_dir: database/tool_cache
  enable_tool_source_display: false
  toolbox_filter_base_modules: null
```

---

#### 4. **Disk Space**
**Issue:** Tool XMLs + containers require significant space

**Difficulty:** ⚠️ **LOW**

**Space requirements:**
- 1,566 XML files: ~50 MB
- Container images: ~50-100 GB (if all pulled)
- Tool data: Variable

**Recommendation:**
- Pull containers on-demand (not all at once)
- Use shared container cache
- Monitor disk usage

---

### 🟡 **MODERATE CONCERNS**

#### 5. **Tool Dependency Conflicts**
**Issue:** Some tools may have conflicting requirements

**Example:**
- Tool A requires `python=3.8`
- Tool B requires `python=3.11`

**Difficulty:** ⚠️ **MEDIUM**

**Galaxy's solution:**
- Each tool runs in isolated container
- No conflicts between tools
- ✓ Not a problem with containers

---

#### 6. **Tool Search Performance**
**Issue:** Large number of tools may slow down search

**Difficulty:** ⚠️ **LOW**

**Galaxy version matters:**
- Galaxy <21.05: Slower search
- Galaxy ≥21.05: Optimized search index
- Galaxy ≥22.01: Much faster with tool search cache

**Recommendation:**
- Use Galaxy ≥22.01
- Enable tool search indexing

---

#### 7. **Tool Testing**
**Issue:** Need to test 1,566 tools work correctly

**Difficulty:** ⚠️ **HIGH**

**Testing strategy:**
1. **Smoke test:** Does tool load? (All 1,566)
2. **Basic test:** Does tool execute? (Sample 100)
3. **Full test:** Correct results? (Sample 20)

**Time estimate:**
- Smoke test: ~30 minutes (automated)
- Basic test: ~2 hours (automated)
- Full test: ~4 hours (manual + automated)

---

### 🟢 **MINOR CONCERNS**

#### 8. **Tool Panel Organization**
**Issue:** 1,566 tools in one section is overwhelming

**Solution:** Organize by category

```xml
<section id="nfcore" name="nf-core Tools">
  <section id="nfcore_alignment" name="Alignment">
    <tool file="nfcore/bwa_mem.xml" />
    <tool file="nfcore/bowtie2_align.xml" />
  </section>

  <section id="nfcore_variant_calling" name="Variant Calling">
    <tool file="nfcore/gatk4_haplotypecaller.xml" />
    <tool file="nfcore/bcftools_call.xml" />
  </section>

  <!-- ... more categories ... -->
</section>
```

**Time to organize:** ~2 hours

---

#### 9. **Documentation**
**Issue:** Users need documentation for new tools

**Difficulty:** ⚠️ **LOW**

**Solution:**
- Each tool XML has help section (from nf-core)
- Link to nf-core documentation
- Create tool catalog markdown

---

#### 10. **Version Management**
**Issue:** nf-core tools get updated

**Difficulty:** ⚠️ **LOW**

**Strategy:**
- Pin container versions in XML
- Create update script to regenerate from new nf-core releases
- Test before deploying updates

---

## Installation Checklist

### Pre-Installation:
- [ ] Backup Galaxy database
- [ ] Backup tool_conf.xml
- [ ] Check disk space (>100 GB available)
- [ ] Verify Galaxy version ≥21.05
- [ ] Test with 10 sample tools first

### Installation:
- [ ] Fix existing 355 tools (run fix_existing_tool_quality.py)
- [ ] Copy tools to Galaxy tools directory
- [ ] Update tool_conf.xml (use auto-discovery)
- [ ] Validate tool XMLs
- [ ] Restart Galaxy
- [ ] Check logs for errors

### Post-Installation:
- [ ] Smoke test all tools (load in UI)
- [ ] Basic test sample tools (execute with test data)
- [ ] Check tool search performance
- [ ] Monitor Galaxy startup time
- [ ] Document any issues

---

## Rollback Plan

If installation fails:

```bash
# 1. Stop Galaxy
$GALAXY_ROOT/run.sh --stop-daemon

# 2. Restore tool_conf.xml backup
cp tool_conf.xml.backup $GALAXY_ROOT/config/tool_conf.xml

# 3. Remove nfcore tools
rm -rf $GALAXY_ROOT/tools/nfcore/

# 4. Start Galaxy
$GALAXY_ROOT/run.sh --daemon
```

**Time to rollback:** ~2 minutes

---

## Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Broken container refs | HIGH | MEDIUM | Fix before install (done by script) |
| Invalid tool XMLs | HIGH | LOW | Validate before install |
| Galaxy won't start | HIGH | LOW | Batch install + test |
| Slow startup | MEDIUM | HIGH | Enable caching |
| Disk space | MEDIUM | MEDIUM | Monitor + pull on-demand |
| Tool conflicts | LOW | LOW | Containers isolate |
| Search performance | LOW | MEDIUM | Use Galaxy ≥22.01 |

**Overall Risk:** 🟡 **MODERATE** (with proper testing and validation)

---

## Recommended Installation Strategy

### Phase 1: Fix + Test (Day 1)
1. Fix existing 355 tools
2. Install 50 sample tools
3. Test thoroughly
4. Document any issues

### Phase 2: Batch Install (Day 2)
1. Install remaining 305 existing tools (batches of 100)
2. Test each batch
3. Monitor Galaxy performance

### Phase 3: Generate Missing (Day 3-4)
1. Generate 1,211 missing tools (batches of 200)
2. Install each batch after generation
3. Test each batch

### Phase 4: Full Validation (Day 5)
1. Full smoke test (all 1,566 tools)
2. Performance testing
3. User documentation
4. Production deployment

**Total estimated time:** 5 days

---

## Key Success Factors

### ✅ **Will Work Well:**
1. Container isolation (no dependency conflicts)
2. Auto-installer already exists
3. nf-core metadata is high quality
4. Tools are well-tested in nf-core

### ⚠️ **Need Attention:**
1. Container availability (validate all exist)
2. Tool XML validation (test before deploy)
3. Galaxy startup time (enable caching)
4. Disk space management (pull on-demand)

### ❌ **Potential Blockers:**
1. Galaxy version <21.05 (upgrade required)
2. Insufficient disk space (need >100 GB)
3. Broken container references (fixed by script)

---

## Conclusion

**Installation Difficulty:** 🟡 **MODERATE**

**Key Concerns:**
1. **Container availability** - Can be fixed by script
2. **Tool validation** - Need batch testing
3. **Startup time** - Acceptable with caching

**Recommendation:**
- **Proceed with phased installation**
- **Test 50 tools first** to validate approach
- **Monitor each phase carefully**
- **Have rollback plan ready**

**Estimated success rate:** 95% with proper testing

**Blocker probability:** LOW (all issues have solutions)

---

## Next Steps

1. **Immediate:** Run fix_existing_tool_quality.py
2. **Day 1:** Install + test 50 sample tools
3. **Day 2-3:** Batch install all 355 existing tools
4. **Day 4-5:** Generate + install 1,211 missing tools
5. **Day 6:** Full validation + documentation

**Total time to full deployment:** ~5-6 days with proper testing
