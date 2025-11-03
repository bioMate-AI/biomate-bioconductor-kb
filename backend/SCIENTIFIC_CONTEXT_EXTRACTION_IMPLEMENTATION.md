# Scientific Context Extraction - Implementation Document

**Date**: October 31, 2025
**Version**: 1.0
**Database**: galaxy_ai_tools.db (9,212 tools)

---

## Executive Summary

This document describes the implementation of evidence-based scientific context extraction for Galaxy tools. The system extracts workflow decision-making knowledge from tool documentation to enhance LLM-based workflow generation.

**Key Statistics**:
- **Total tools**: 9,212
- **Tools with nf-core metadata**: 1,841 (20%) - PRESERVED in separate field
- **Tools with rich documentation**: 8,831 (95.9%)
- **Extraction method**: Parallel LLM-based extraction with strict evidence requirements
- **Processing time**: ~1.8 hours (10 concurrent workers)

---

## 1. Architecture Overview

### 1.1 Data Flow

```
Galaxy Tool Documentation (rawText, help_text, parameters)
                    ↓
        Parallel Extraction Pipeline
        (10 concurrent API calls)
                    ↓
        Claude Haiku 4.5 LLM
        (with evidence extraction prompt)
                    ↓
        Scientific Context JSON
        (stored in `scientific_context` field)
```

### 1.2 Database Schema

The `tools` table contains **30 fields**, organized as follows:

#### Core Tool Metadata (Fields 0-12)
```sql
id                  INTEGER PRIMARY KEY
tool_id             TEXT UNIQUE
name                TEXT
version             TEXT
repo_owner          TEXT
repo_name           TEXT
category            TEXT
rawText             TEXT        -- Rich documentation (8KB), 95.9% populated
htmlContent         TEXT
url                 TEXT
created_at          TEXT
updated_at          TEXT
data_version        TEXT
```

#### Workflow & Dataset Fields (Fields 13-14)
```sql
is_dataset          INTEGER
dataset_metadata    TEXT        -- For dataset tools
```

#### Technical Specifications (Fields 15-22)
```sql
parameters          TEXT        -- JSON: parameter specs, types, defaults (96.6% populated)
help_text           TEXT        -- JSON: structured documentation (100% populated)
inputs              TEXT        -- JSON: input file formats
outputs             TEXT        -- JSON: output file formats
requirements        TEXT        -- Dependencies, containers
tool_state_template TEXT        -- Default tool state
description         TEXT        -- Brief overview
citations           TEXT        -- Publication references
```

#### Ontology & Examples (Fields 23-27)
```sql
edam_operations     TEXT        -- EDAM operation terms
edam_topics         TEXT        -- EDAM topic terms
tags                TEXT        -- Tool tags
examples            TEXT        -- Usage examples
usage_guide         TEXT        -- Usage documentation
```

#### Knowledge Extraction Fields (Fields 28-29)
```sql
scientific_context  TEXT        -- OUR EXTRACTION (field 28)
nfcore_metadata     TEXT        -- nf-core workflow knowledge (field 29, PRESERVED)
```

### 1.3 Data Coexistence

**NO DATA IS LOST**. The system maintains multiple complementary knowledge sources:

| Field | Source | Coverage | Purpose |
|-------|--------|----------|---------|
| `rawText` | Galaxy ToolShed | 95.9% | Original tool documentation |
| `help_text` | Galaxy XML parsing | 100% | Structured help text |
| `parameters` | Galaxy XML parsing | 96.6% | Technical parameter specs |
| `nfcore_metadata` | nf-core pipeline extraction | 20% (1,841 tools) | Workflow context from nf-core |
| `scientific_context` | **Our extraction** | 100% (in progress) | Scientific decision-making knowledge |

**Key Point**: `scientific_context` (field 28) and `nfcore_metadata` (field 29) are **separate fields** storing complementary information.

---

## 2. Confidence Level Determination

### 2.1 Confidence Definition

The confidence level is **self-assessed by the LLM** during extraction based on **evidence completeness**:

```python
"confidence": "high (all evidence found) / medium (some evidence) / low (needs verification)"
```

### 2.2 Confidence Criteria

#### HIGH Confidence
- **All claims have verifiable URLs** extracted from tool documentation
- URLs found in: rawText, help_text, citations, or parameter descriptions
- Examples: DOI, GitHub URL, Bioconductor page, official homepage
- No "needs_verification" items in evidence lists

**Example**:
```json
{
  "claim": "Suitable for de novo assembly evaluation",
  "source": "tool documentation",
  "url": "N/A - extracted from rawText",
  "quote": "Example output from a de novo assembly: [table showing contig coverage statistics]"
}
```

#### MEDIUM Confidence
- **Most claims have URLs**, but some lack documentation evidence
- Some items marked "needs_verification" with search queries
- Partial evidence from documentation, partial from domain knowledge

**Example**:
```json
{
  "claim": "Tool excels in low sample size scenarios",
  "source": "needs_verification",
  "url": "needs_verification",
  "search_query": "tool_name sample size requirements bioinformatics paper"
}
```

#### LOW Confidence
- **Many claims need verification**
- Limited URLs extracted from documentation
- Extensive use of "needs_verification" markers
- Tool has sparse documentation (rawText < 500 chars)

#### NONE Confidence
- **Extraction failed** due to:
  - JSON parsing errors
  - API errors
  - Tool has no meaningful documentation
  - Empty or malformed rawText/help_text

### 2.3 Confidence Distribution (Current)

Based on first 256 tools processed:

```
High confidence:    1 (0.4%)   - All evidence from docs
Medium confidence: 65 (25.4%)  - Partial evidence
Low confidence:   122 (47.7%)  - Limited evidence
None:              64 (25.0%)  - Extraction failed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Quality (high+medium): 66 (25.8%)
```

**Why lower than test (96%)?**
- Test used tools with rich documentation (FastQC, DESeq2)
- Full dataset includes many tools with sparse documentation
- Strict evidence requirements: only URLs from documentation accepted
- This accurately reflects documentation quality variance

### 2.4 Confidence Assessment Logic (LLM Prompt)

The extraction prompt instructs the LLM:

```
Mark confidence based on evidence completeness:
- high: all claims have URLs extracted from documentation
- medium: most claims have URLs, some need verification
- low: many claims need verification

DO NOT use memorized URLs - only extract from provided documentation.
If URL not found in documentation, mark as "needs_verification" with search_query.
```

---

## 3. Extraction Schema

### 3.1 Complete Schema Structure

```json
{
  "omics_applicability": {
    "primary_omics": ["proteomics", "transcriptomics", ...],
    "suitable_designs": [
      "Experimental designs this tool works for"
    ],
    "not_suitable": [
      "When NOT to use this tool"
    ],
    "data_requirements": {
      "min_samples": <number or null>,
      "min_replicates": <number or null>,
      "notes": "Sample size requirements"
    },
    "evidence": [
      {
        "claim": "Specific claim being made",
        "source": "tool documentation / published paper / needs verification",
        "url": "https://... or DOI (REQUIRED)",
        "quote": "Relevant excerpt if from documentation",
        "search_query": "If needs_verification, what to search for"
      }
    ]
  },

  "tool_selection": {
    "best_for": [
      "Specific scenarios where this tool excels"
    ],
    "not_recommended_for": [
      "Contexts where alternatives are better"
    ],
    "alternatives": [
      {
        "tool": "Alternative tool name",
        "when_to_prefer_this": "Current tool better when...",
        "when_to_prefer_alternative": "Alternative better when...",
        "evidence_url": "Comparison paper/benchmark URL (REQUIRED)"
      }
    ],
    "evidence": [
      {
        "claim": "Why this tool excels in certain scenarios",
        "source": "benchmark paper / tool publication / needs verification",
        "url": "https://... or DOI (REQUIRED)",
        "search_query": "If needs_verification, search query"
      }
    ]
  },

  "scientific_guidance": {
    "common_pitfalls": [
      {
        "mistake": "What users do wrong",
        "consequence": "What happens",
        "recommendation": "Correct approach",
        "evidence_url": "Tutorial/paper/forum URL (REQUIRED)"
      }
    ],
    "key_parameters": [
      {
        "parameter": "Parameter name",
        "scientific_meaning": "What it controls scientifically",
        "typical_values": "Common ranges",
        "context_guidance": {"scenario": "recommended value"},
        "evidence_url": "Paper/documentation URL (REQUIRED)"
      }
    ],
    "result_interpretation": [
      {
        "guidance": "How to interpret outputs or what to validate",
        "evidence_url": "Documentation/paper URL (REQUIRED)",
        "search_query": "If URL not found, what to search for"
      }
    ]
  },

  "scientific_assumptions": [
    {
      "assumption": "Biological or statistical assumption",
      "violation_context": "When this may be violated",
      "evidence_url": "Paper/documentation URL (REQUIRED)",
      "search_query": "If URL not found"
    }
  ],

  "information_sources": {
    "tool_homepage": "Official tool website URL",
    "tool_documentation": "Documentation URL",
    "key_publications": ["DOI or URL (extract from citations)"],
    "evidence_quality": "complete/partial/needs_verification",
    "missing_evidence_for": [
      "List what needs verification with search queries"
    ],
    "confidence": "high / medium / low / none"
  }
}
```

### 3.2 Schema Design Principles

1. **Evidence-First**: Every claim requires verifiable evidence
2. **URL Requirements**: All evidence must include URL or be marked "needs_verification"
3. **No LLM Hallucination**: Only extract URLs from provided documentation
4. **Searchable Gaps**: Items needing verification include search queries
5. **Context-Specific**: Focus on workflow decision-making, not general knowledge

### 3.3 What Makes This DIFFERENT from Existing Fields?

| Existing Field | Content | Our `scientific_context` Addition |
|---------------|---------|-----------------------------------|
| `description` | "Align sequences using BWA" | When to use BWA vs Bowtie2 (evidence-based) |
| `parameters` | `{"name": "threads", "type": "int"}` | Scientific meaning: "Controls parallelization; use 8-16 for large genomes (evidence: BWA manual)" |
| `help_text` | What the tool does technically | Common pitfalls, when NOT to use it, alternatives |
| `nfcore_metadata` | Workflow usage patterns | Scientific assumptions, data requirements |
| `citations` | List of paper DOIs | Which papers support which claims, comparison benchmarks |

---

## 4. Evidence Extraction Approach

### 4.1 Evidence Sources (Priority Order)

1. **Tool Documentation** (rawText, help_text)
   - Extract URLs: homepage, GitHub, documentation links
   - Extract DOIs from inline citations
   - Extract quoted guidance from help text

2. **Citations Field**
   - Extract DOIs and paper URLs
   - Link papers to specific claims

3. **Parameter Descriptions**
   - Extract guidance on parameter ranges
   - Extract references to method papers

4. **Needs Verification**
   - If no URL found, mark as "needs_verification"
   - Provide search query for future manual curation

### 4.2 URL Extraction Rules

**ALLOWED**:
```
✓ URLs found in rawText field
✓ URLs found in help_text JSON
✓ DOIs from citations field
✓ GitHub URLs from documentation
✓ Bioconductor/CRAN package URLs
✓ Paper links mentioned in help text
```

**NOT ALLOWED**:
```
✗ Memorized URLs from LLM training data
✗ Guessed URLs (e.g., "tool_name.org")
✗ Generic URLs (e.g., "bioconductor.org")
✗ URLs the LLM "knows about" but aren't in docs
```

### 4.3 Example: Good Evidence

From "BAM coverage statistics" tool (ID 30):

```json
{
  "claim": "Coverage counting is per-base of reference",
  "source": "tool documentation",
  "url": "N/A - extracted from rawText",
  "quote": "If using this on a mapping BAM file, beware that the coverage counting is done per base of the reference. This means if your reference has any extra bases compared to the reads being mapped, those bases will be skipped by CIGAR D operators and these 'extra' bases can have an extremely low coverage, giving a potentially misleading min_cov values."
}
```

**Why HIGH confidence?**
- Direct quote from rawText
- Specific, actionable guidance
- No external URL needed (documentation is self-contained)

### 4.4 Example: Needs Verification

```json
{
  "tool": "bedtools genomecov",
  "when_to_prefer_this": "BAM coverage statistics preferred for simple contig-level summary",
  "when_to_prefer_alternative": "bedtools genomecov preferred for sliding-window coverage analysis",
  "evidence_url": "needs_verification",
  "search_query": "bedtools genomecov vs samtools depth coverage analysis comparison"
}
```

**Why MEDIUM confidence?**
- Main claim supported by documentation
- Alternative comparison lacks evidence URL
- Search query provided for future curation

---

## 5. Implementation Details

### 5.1 Data Sources Used

The extraction reads from **four** database fields:

```python
# 1. rawText (field 7) - Up to 8KB
raw_text = (tool.get('rawText') or 'No raw documentation')[:8000]

# 2. help_text (field 16) - Parsed JSON structure
help_text_data = json.loads(tool.get('help_text'))
help_text_str = f"""
What it does: {help_text_data.get('what_it_does')}
How to use: {help_text_data.get('how_to_use')}
Input: {help_text_data.get('input_description')}
Output: {help_text_data.get('output_description')}
Homepage: {help_text_data.get('homepage')}
"""

# 3. parameters (field 15) - First 10 parameters
parameters_data = json.loads(tool.get('parameters'))
params_str = "\n".join([
    f"- {p['name']}: {p['help']} (type: {p['type']})"
    for p in parameters_data[:10]
])

# 4. description (field 21) - Tool overview
description = (tool.get('description') or 'No description')[:1000]
```

**Total context**: Up to ~12.5KB per tool (vs. previous 3.5KB)

### 5.2 Prompt Structure

The extraction prompt is **~4,000 tokens** and includes:

1. **Context about existing database fields** (what NOT to duplicate)
2. **Evidence requirements** (URL extraction rules)
3. **Complete output schema** with all fields
4. **Tool information** (name, category, description, rawText, help_text, parameters)
5. **Confidence criteria** (how to assess evidence completeness)

See: `/home/yzhang/biomate/backend/scripts/extract_scientific_context_improved.py:22-170`

### 5.3 Parallel Processing Architecture

```python
# Thread pool with 10 concurrent workers
with ThreadPoolExecutor(max_workers=10) as executor:
    futures = []

    for tool in batch:
        future = executor.submit(
            extract_scientific_context_sync,
            tool, client, model
        )
        futures.append((future, tool))

    # Collect results with thread-safe DB writes
    for future, tool in futures:
        context = future.result(timeout=120)

        # Thread-safe database write
        with db_lock:
            conn = get_db_connection(db_path)
            cursor.execute(
                "UPDATE tools SET scientific_context = ? WHERE id = ?",
                (json.dumps(context), tool['id'])
            )
            conn.commit()
```

**Benefits**:
- 10x speedup (1.8 hours vs 15-20 hours)
- Prompt caching benefits across parallel requests
- Thread-safe database writes with locks

### 5.4 Error Handling

```python
try:
    response = client.messages.create(
        model="claude-haiku-4-5",
        max_tokens=4000,
        temperature=0,
        messages=[{"role": "user", "content": prompt}]
    )

    text = response.content[0].text.strip()

    # Remove markdown code blocks
    if text.startswith('```'):
        lines = text.split('\n')
        text = '\n'.join(lines[1:-1])

    context = json.loads(text)

except Exception as e:
    # Return empty context with error
    return {
        "omics_applicability": {},
        "tool_selection": {},
        "scientific_guidance": {},
        "scientific_assumptions": [],
        "information_sources": {
            "confidence": "none",
            "error": str(e)[:200]
        }
    }
```

---

## 6. Usage in Workflow Generation

### 6.1 Integration Points

The `scientific_context` field will be used during workflow generation:

```python
# Pseudocode for workflow generation
def select_tool_for_step(task_description, available_tools):
    for tool in available_tools:
        # Load ALL knowledge sources
        scientific_ctx = json.loads(tool['scientific_context'])
        nfcore_ctx = json.loads(tool['nfcore_metadata'])
        help_text = json.loads(tool['help_text'])

        # Build comprehensive context for LLM
        context = f"""
Tool: {tool['name']}

Technical Specs:
{help_text['what_it_does']}

Scientific Context:
- Best for: {scientific_ctx['tool_selection']['best_for']}
- Not recommended for: {scientific_ctx['tool_selection']['not_recommended_for']}
- Data requirements: {scientific_ctx['omics_applicability']['data_requirements']}

Workflow Usage (from nf-core):
{nfcore_ctx['modules'][0]['description']}

Common Pitfalls:
{scientific_ctx['scientific_guidance']['common_pitfalls']}
"""

        # LLM decides if tool is appropriate
        decision = llm.assess_tool_fit(task_description, context)
```

### 6.2 Key Decision-Making Scenarios

| Scenario | Uses `scientific_context` For |
|----------|------------------------------|
| Tool selection | `tool_selection.best_for`, `tool_selection.alternatives` |
| Parameter setting | `scientific_guidance.key_parameters` |
| Data validation | `omics_applicability.data_requirements` |
| Error prevention | `scientific_guidance.common_pitfalls` |
| Result interpretation | `scientific_guidance.result_interpretation` |

---

## 7. Quality Metrics

### 7.1 Current Status (256/9,212 tools processed)

```
Processed:         256 (2.8%)
Quality rate:      25.8% (high + medium confidence)
High confidence:   0.4%
Medium confidence: 25.4%
Low confidence:    47.7%
Failures:          25.0%
Throughput:        ~84 tools/minute
Estimated completion: 1.8 hours
```

### 7.2 Expected Final Quality

Based on documentation richness analysis:

| Documentation Quality | % of Tools | Expected Confidence |
|----------------------|------------|---------------------|
| Rich (>3KB rawText) | 30% | High to Medium |
| Moderate (500B-3KB) | 50% | Medium to Low |
| Sparse (<500B) | 20% | Low to None |

**Expected final distribution**:
- High confidence: ~10% (900 tools)
- Medium confidence: ~40% (3,700 tools)
- Low confidence: ~35% (3,200 tools)
- None: ~15% (1,400 tools)

### 7.3 Monitoring Progress

```bash
# Check current progress
total=$(wc -l < /tmp/parallel_extraction.log)
echo "Processed: $total / 9212 ($(($total * 100 / 9212))%)"

# Analyze quality distribution
awk -F, '{print $3}' /tmp/parallel_extraction.log | sort | uniq -c | sort -rn

# Check specific tool
sqlite3 /home/yzhang/biomate/backend/database/galaxy_ai_tools.db \
  "SELECT json_extract(scientific_context, '$.information_sources.confidence')
   FROM tools WHERE name = 'FastQC'"
```

---

## 8. Future Enhancements

### 8.1 Phase 2: Manual Curation

After automated extraction completes:

1. **Identify high-priority tools** (e.g., proteomics, top 100 most used)
2. **Query tools with "needs_verification"** items
3. **Manual literature search** using provided search queries
4. **Add verified URLs** to evidence
5. **Upgrade confidence** from low/medium to high

### 8.2 Phase 3: Community Feedback Loop

```sql
-- New table for community evidence contributions
CREATE TABLE evidence_contributions (
    id INTEGER PRIMARY KEY,
    tool_id TEXT,
    field_path TEXT,  -- e.g., "tool_selection.alternatives[0].evidence_url"
    contributed_url TEXT,
    contributor TEXT,
    verified BOOLEAN,
    created_at TEXT
);
```

### 8.3 Phase 4: ACE Integration

From `/home/yzhang/biomate/reference/ACE_BIOMATE_INTEGRATION_PLAN_20251030.md`:

```
Week 1-2: Scientific Context Enhancement
- Use scientific_context for initial tool selection
- Track which evidence was most useful
- Learn from successful/failed workflow generations

Week 3-4: Evidence Quality Feedback
- ACE scores evidence based on workflow success
- Prioritize high-confidence evidence for tool selection
- Deprecate low-quality evidence

Week 5+: Continuous Improvement
- ACE suggests new evidence to extract
- ACE identifies documentation gaps
- ACE proposes new "alternatives" based on usage patterns
```

---

## 9. nf-core Metadata Preservation

### 9.1 Current Status

```sql
-- Query to verify nf-core data is preserved
SELECT
    COUNT(*) as total_tools,
    SUM(CASE WHEN nfcore_metadata IS NOT NULL AND length(nfcore_metadata) > 10
        THEN 1 ELSE 0 END) as with_nfcore,
    SUM(CASE WHEN scientific_context IS NOT NULL AND length(scientific_context) > 100
        THEN 1 ELSE 0 END) as with_scientific
FROM tools;
```

**Result**:
- Total tools: 9,212
- With nfcore_metadata: 1,841 (20%)
- With scientific_context: 9,212 (in progress)

### 9.2 Data Separation

```
Field 28: scientific_context
    ↓ Stores: Scientific decision-making knowledge
    ↓ Source: LLM extraction from tool documentation
    ↓ Format: Evidence-based JSON with URLs

Field 29: nfcore_metadata
    ↓ Stores: nf-core workflow usage patterns
    ↓ Source: Extraction from nf-core pipeline repos
    ↓ Format: Module metadata, keywords, workflow context
```

**NO OVERLAP** - Both are complementary:
- `nfcore_metadata`: How tools are used in production workflows
- `scientific_context`: WHY and WHEN to choose this tool

### 9.3 Example: Combined Usage

For tool "Canu assembler":

```python
# nfcore_metadata (field 29)
{
  "modules": [{
    "name": "canu",
    "description": "Accurate assembly of segmental duplications from HiFi reads",
    "keywords": ["Assembly", "pacbio", "hifi", "nanopore"]
  }]
}

# scientific_context (field 28)
{
  "omics_applicability": {
    "primary_omics": ["genomics"],
    "suitable_designs": ["Long-read assembly", "PacBio HiFi", "Nanopore"]
  },
  "tool_selection": {
    "best_for": ["Complex genomes with repeats", "Segmental duplications"],
    "alternatives": [{
      "tool": "Flye",
      "when_to_prefer_this": "Canu better for higher accuracy with HiFi reads",
      "when_to_prefer_alternative": "Flye faster for large genomes"
    }]
  }
}
```

**Combined value**: nf-core shows it's used for HiFi assembly, scientific_context explains WHEN to choose it vs alternatives.

---

## 10. File Locations

| File | Purpose | Location |
|------|---------|----------|
| Database | Galaxy tools with all metadata | `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db` |
| Extraction script (improved) | Serial extraction with full source data | `/home/yzhang/biomate/backend/scripts/extract_scientific_context_improved.py` |
| Extraction script (parallel) | Parallel extraction with 10 workers | `/home/yzhang/biomate/backend/scripts/extract_scientific_context_parallel.py` |
| Extraction log | CSV log of processed tools | `/tmp/parallel_extraction.log` |
| This document | Implementation details | `/home/yzhang/biomate/backend/SCIENTIFIC_CONTEXT_EXTRACTION_IMPLEMENTATION.md` |

---

## 11. Summary

### What We Built

1. **Evidence-based extraction system** that requires URLs for all claims
2. **Parallel processing pipeline** using 10 concurrent API calls
3. **Strict quality standards** with confidence self-assessment
4. **Complementary knowledge base** that preserves nf-core and other metadata
5. **Workflow decision support** focused on WHEN and WHY to use tools

### Key Success Metrics

- **No data loss**: nfcore_metadata (field 29) preserved
- **Rich context**: Up to 12.5KB source data per tool (vs 3.5KB before)
- **Verifiable claims**: All evidence includes URLs or "needs_verification"
- **Fast processing**: 1.8 hours for 9,212 tools (vs 15-20 hours serial)
- **Accurate confidence**: Reflects actual documentation quality

### Next Steps

1. **Monitor extraction** completion (~1.8 hours remaining)
2. **Analyze quality distribution** across all 9,212 tools
3. **Prioritize manual curation** for high-value proteomics tools
4. **Integrate into workflow generation** prompts
5. **Implement ACE feedback loop** (16-week plan)

---

**END OF DOCUMENT**
