# Galaxy Tool Count - Official Explanation
**Date:** 2025-10-09
**Galaxy Official Count:** 10,709 valid tools (as of today)

---

## What Does "Tool" Mean in Galaxy?

### Official Galaxy Definitions

**Repository:**
- A versioned code archive in the ToolShed
- Container for one or more tools
- Like a GitHub repository
- Example: `devteam/bedtools` is ONE repository

**Tool:**
- An individual Galaxy tool XML wrapper
- Each tool is a separate executable function
- Multiple tools can exist in one repository
- Example: `bedtools_intersect`, `bedtools_merge`, `bedtools_sort` are THREE separate tools

### Galaxy's Counting Method

**Galaxy counts INDIVIDUAL TOOLS, not repositories**

Example from our database:
```
Repository: devteam/emboss_5
Contains: 107 individual tools
  - emboss_antigenic
  - emboss_backtranseq
  - emboss_banana
  - emboss_biosed
  ... (103 more tools)

Galaxy counts this as 107 tools, not 1 repository
```

### More Examples

| Repository | Owner | Individual Tools |
|------------|-------|------------------|
| emboss_5 | devteam | 107 tools |
| gembassy | ktnyt | 98 tools |
| qiime | jjohnson | 89 tools |
| ball | luis | 62 tools |
| java_genomics_toolkit | timpalpant | 48 tools |
| met4j | metexplore | 45 tools |
| bedtools | iuc | 37 tools |
| picard | devteam | 31 tools |

**Total just from these 8 repositories: 517 tools**

---

## Our Crawl Data

### What We Downloaded

```
From: /Users/jingqiwang/lcms-platform/galaxy_tools/latest_tools_complete/
Largest file: progress_2025-10-08T03-05-31-905Z.json (68MB)

Crawled:
  - 4,493 repositories
  - 6,519 tool entries

After deduplication (latest version only):
  - 4,504 unique repositories
  - 6,295 unique tools
```

### Why We Have 6,295 Instead of 10,709

**We captured ~59% of Galaxy's tools**

**Possible reasons for the gap:**

1. **Partial crawl** - The crawler may not have completed
   - 40 categories crawled
   - Some categories may be incomplete

2. **Latest version only** - We kept only the latest version
   - Galaxy may count all versions as separate tools
   - If tool has 3 versions, Galaxy counts 3 tools, we count 1

3. **Crawl timestamp** - Data from Oct 8, 2025
   - Galaxy shows 10,709 as of Oct 9, 2025
   - ~4,000 tools added in one day seems unlikely
   - More likely: we didn't complete the full crawl

4. **Tool visibility** - Some tools may be hidden/deprecated
   - Galaxy counts "valid tools" (10,709)
   - May not all be visible in category listings

---

## What "Tool" Means in Our Database

### Our tool_id Format

```
toolshed.g2.bx.psu.edu/repos/{owner}/{repo_name}/{tool_xml_id}

Example:
toolshed.g2.bx.psu.edu/repos/devteam/bedtools/bedtools_intersectbed

This represents ONE specific tool (bedtools intersect)
```

### Our Counting

```sql
SELECT COUNT(*) FROM tools;
-- Returns: 6,295

SELECT COUNT(DISTINCT repo_owner, repo_name) FROM tools;
-- Returns: 4,504 repositories

SELECT COUNT(DISTINCT name) FROM tools;
-- Returns: 5,709 unique tool names (some names appear in multiple repos)
```

**We have 6,295 unique (repository + tool) combinations**

---

## Tool Dependencies - How Galaxy Determines Them

### From Galaxy Official Documentation

Galaxy tools can have dependencies defined in their XML:

```xml
<tool id="my_tool" name="My Tool">
  <requirements>
    <requirement type="package" version="1.70">biopython</requirement>
    <requirement type="package" version="2.7.10">python</requirement>
  </requirements>
</tool>
```

### Dependency Types

1. **Package dependencies** (requirements tag)
   - Software packages needed (conda, pip, etc.)
   - Example: biopython, samtools, R packages

2. **Repository dependencies** (tool_dependencies.xml)
   - Other Galaxy repositories this tool needs
   - Example: Tool A requires Tool B from another repository

3. **Tool dependencies** (within same repository)
   - Tools can depend on other tools in same repo
   - Usually implicit through workflow connections

### How Dependencies Are Resolved

**When installing a Galaxy tool:**

1. Galaxy reads the `<requirements>` section
2. Uses conda/bioconda to install packages
3. Creates isolated environment for the tool
4. Installs any repository dependencies from ToolShed

**Example: Our bedtools tools**

```
Repository: iuc/bedtools (37 tools)
Each tool has requirements:
  <requirement type="package" version="2.30.0">bedtools</requirement>

When installed, Galaxy:
  1. Creates conda environment
  2. Installs bedtools v2.30.0 from bioconda
  3. Makes it available to all 37 tools in the repository
```

---

## Implications for Our Tool Index

### What We Actually Have

**6,295 tools = 6,295 distinct Galaxy tool wrappers**

Each represents:
- A specific XML tool definition
- A specific version
- In a specific repository
- With specific parameters and help text

### What This Means for Biomni/nfcore Integration

**When checking "is X in Galaxy":**

We should check:
1. ✅ Tool name match (e.g., "fastqc")
2. ✅ Functional match (does it do the same thing?)
3. ❓ Version match (is it recent enough?)

**Example: FastQC**
```
Biomni has: fastqc (CLI tool)
Galaxy has: 6 different FastQC wrappers
  - devteam/fastqc v0.74
  - mingchen0919/aurora_fastqc v2.1.2
  - etc.

Answer: FastQC IS in Galaxy (multiple times)
```

**Example: cellpose**
```
Biomni has: cellpose (Python package)
Galaxy has: 0 results

Answer: cellpose is NOT in Galaxy
```

---

## The Honest Truth About Our Data

### What We Know For Sure

1. ✅ We have 6,295 unique Galaxy tools in our database
2. ✅ These come from 4,504 unique repositories
3. ✅ Galaxy officially has 10,709 tools (as of today)
4. ✅ We captured ~59% of Galaxy's tools

### What We Don't Know

1. ❓ Why we only have 6,295 instead of 10,709
   - Incomplete crawl?
   - Version filtering?
   - Category limitations?

2. ❓ Whether the missing 4,414 tools include critical ones
   - Could be specialized/niche tools
   - Could be deprecated tools
   - Could be alternative wrappers

3. ❓ How Galaxy counts versions
   - Do they count each version separately?
   - Or just unique tool IDs?

---

## Recommendations

### For Tool Integration Analysis

1. **Use our 6,295 tools as the baseline**
   - This is what we actually have
   - It's a substantial subset (59%)
   - Sufficient for overlap analysis

2. **When we say "X is in Galaxy"**
   - We mean: X appears in our 6,295 tool database
   - We should note: "in our Galaxy database (6,295/10,709 tools)"

3. **For missing tools from biomni/nfcore**
   - Check our database first (6,295 tools)
   - If not found, tool is likely not in our index
   - May or may not be in the other 4,414 tools on Galaxy

4. **Consider re-crawling**
   - To get closer to the 10,709 count
   - Or accept 6,295 as a good representative sample

### For Database Description

**Accurate statement:**
> "Our Galaxy tool database contains 6,295 tools from 4,504 repositories,
> representing approximately 59% of the 10,709 tools in Galaxy ToolShed
> (as of Oct 2025). Each tool is a unique Galaxy XML wrapper for a
> bioinformatics software package."

**Avoid saying:**
> "Galaxy has 6,295 tools" ← WRONG (Galaxy has 10,709)
> "We have all Galaxy tools" ← WRONG (we have 59%)

---

## Questions to Resolve

1. **Should we complete the crawl to get all 10,709 tools?**
   - Pro: More comprehensive coverage
   - Con: May include many deprecated/alternative versions

2. **Do the missing 4,414 tools matter for our use case?**
   - If we have the major tools (bedtools, bwa, etc.), we're good
   - Missing tools may be niche/specialized

3. **How should we handle this in the workflow generator?**
   - Search our 6,295 tools first
   - If not found, warn user: "may exist in Galaxy but not in our index"

---

**Bottom Line:**
- Galaxy counts individual tool wrappers (10,709 total)
- One repository can contain many tools (e.g., emboss_5 has 107)
- We have 6,295 tools from 4,504 repositories (~59% of Galaxy)
- This is sufficient for meaningful overlap analysis with biomni/nfcore
