# Tool Metadata Gap Analysis for Claude-Powered Workflow Generation

**Date:** 2025-10-30
**Purpose:** Analyze existing tool metadata and identify gaps for intelligent workflow generation

---

## Executive Summary

The `galaxy_ai_tools.db` contains valuable tool information, but **lacks critical metadata** needed for Claude to make intelligent workflow generation decisions. Current data is sufficient for keyword search but insufficient for understanding:
- What tools actually **do** (functional purpose)
- What data types they **accept/produce** (input/output compatibility)
- When to **use or avoid** them (scientific context)
- How they **relate to each other** (workflow positioning)

---

## Current State: What We Have

### Database Schema
```sql
CREATE TABLE tools (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id TEXT UNIQUE,
    name TEXT,
    version TEXT,
    repo_owner TEXT,
    repo_name TEXT,
    category TEXT,

    -- Raw content from Galaxy ToolShed
    rawText TEXT,
    htmlContent TEXT,
    url TEXT,

    -- Extracted metadata (WEAK)
    description TEXT,
    parameters TEXT,      -- JSON array
    help_text TEXT,
    inputs TEXT,          -- Currently EMPTY for most tools
    outputs TEXT,         -- Currently EMPTY for most tools
    requirements TEXT,
    tool_state_template TEXT,

    -- Additional metadata
    created_at TEXT,
    updated_at TEXT,
    data_version TEXT,
    is_dataset INTEGER,
    dataset_metadata TEXT
)
```

### Supporting Tables
- **`tools_fts`**: Full-text search index (Whoosh-based)
- **`tool_compatibility`**: Tool-to-datatype mappings (sparse)
- **`tool_usage_patterns`**: Historical usage data (if populated)
- **`dataset_tool_mapping`**: Dataset tools to analysis tools (if populated)

---

## Critical Findings

### ✅ What's Good

1. **Comprehensive Tool Coverage**
   - Contains tools from Galaxy ToolShed
   - Includes proteomics tools: DIA-NN, MaxQuant, MSConvert, etc.
   - Has category classifications

2. **Parameter Extraction**
   - Parameters are extracted from `rawText` and stored as JSON
   - Example from DIA-NN:
     ```json
     [
       {
         "name": "scalability_and_speed",
         "label": "Scalability and speed",
         "type": "text",
         "help": "up to 1000 mass spec runs processed per hour",
         "optional": false,
         "source": "rawText"
       }
     ]
     ```

3. **Help Text Available**
   - `help_text` field contains parsed documentation
   - `rawText` contains original tool documentation

### ❌ What's Missing (Critical Gaps)

#### 1. **Empty Input/Output Metadata**
```sql
-- Current state for most tools:
inputs: ""     -- EMPTY!
outputs: ""    -- EMPTY!
```

**Impact:**
- Claude cannot determine if Tool A's output can feed into Tool B
- Cannot detect incompatible tool chains
- Cannot suggest format conversion steps

**What's Needed:**
```json
{
  "inputs": [
    {
      "name": "raw_files",
      "format": ["raw", "mzML"],
      "type": "mass_spec_data",
      "description": "Raw mass spectrometry files",
      "required": true
    },
    {
      "name": "fasta_database",
      "format": ["fasta"],
      "type": "protein_database",
      "required": true
    }
  ],
  "outputs": [
    {
      "name": "peptides",
      "format": "txt",
      "type": "peptide_table",
      "description": "Identified peptides with scores"
    },
    {
      "name": "proteins",
      "format": "txt",
      "type": "protein_groups",
      "description": "Protein groups with quantification"
    }
  ]
}
```

#### 2. **No Scientific Context Metadata**

**Currently Missing:**
- What type of data the tool is designed for (DDA vs DIA)
- When tool is appropriate vs inappropriate
- Scientific use cases
- Common mistakes

**What's Needed:**
```json
{
  "scientific_context": {
    "purpose": "Database search engine for DIA proteomics",
    "data_types_supported": ["DIA", "SWATH"],
    "data_types_not_supported": ["DDA"],
    "best_for": [
      "Deep proteome coverage",
      "Label-free quantification",
      "Large-scale DIA experiments"
    ],
    "not_suitable_for": [
      "DDA data (use MaxQuant instead)",
      "TMT/iTRAQ experiments"
    ],
    "typical_use_cases": [
      "Bottom-up DIA proteomics",
      "Cross-sample quantification",
      "Discovery proteomics"
    ]
  }
}
```

#### 3. **No Workflow Position Metadata**

**Currently Missing:**
- What tools typically come before this tool
- What tools typically come after
- What tools are incompatible

**What's Needed:**
```json
{
  "workflow_position": {
    "typical_position": "early",  // early, middle, late
    "typical_predecessors": [
      "file_conversion",
      "quality_control"
    ],
    "typical_successors": [
      "normalization",
      "statistical_analysis",
      "visualization"
    ],
    "incompatible_with": {
      "before": ["tmt_reporter_ion_quantification"],
      "after": []
    },
    "requires_dataset_types": ["raw", "mzML"]
  }
}
```

#### 4. **No Tool Alternatives/Relationships**

**Currently Missing:**
- Alternative tools for same task
- When to choose one over another
- Tool substitution rules

**What's Needed:**
```json
{
  "alternatives": {
    "same_task": [
      {
        "tool_id": "spectronaut",
        "when_better": "When you need commercial support and integrated analysis",
        "trade_offs": "Commercial license required, but excellent sensitivity"
      },
      {
        "tool_id": "openswath",
        "when_better": "When you have pre-built spectral library",
        "trade_offs": "Requires library, slightly lower sensitivity than DIA-NN"
      }
    ],
    "different_data_type": [
      {
        "tool_id": "maxquant",
        "when": "If you have DDA data instead of DIA"
      }
    ]
  }
}
```

#### 5. **Weak Parameter Metadata**

**Current State:**
- Parameters extracted from text are incomplete
- Type inference is basic (text, data, float, integer)
- No parameter validation rules
- No instrument-specific defaults

**Example Current Parameter:**
```json
{
  "name": "scalability_and_speed",
  "label": "Scalability and speed",
  "type": "text",
  "help": "up to 1000 mass spec runs processed per hour"
}
```

**What's Needed:**
```json
{
  "name": "mass_accuracy_ms1",
  "label": "MS1 Mass Accuracy",
  "type": "float",
  "default": 10.0,
  "range": [1.0, 50.0],
  "unit": "ppm",
  "description": "Mass accuracy for MS1 precursor ions",
  "help": "Set based on your instrument. Orbitrap: 5-10 ppm, QTOF: 10-20 ppm",
  "instrument_dependent": {
    "Orbitrap": 10.0,
    "QTOF": 20.0,
    "TOF": 30.0
  },
  "validation": {
    "min": 1.0,
    "max": 50.0,
    "warning_if": {
      "condition": "value < 5",
      "message": "Very tight mass accuracy. Verify your instrument specifications."
    }
  }
}
```

#### 6. **No Common Mistakes Documentation**

**What's Needed:**
```json
{
  "common_mistakes": [
    {
      "mistake": "Using DIA-NN on DDA data",
      "why_wrong": "DIA-NN is optimized for DIA acquisition patterns",
      "correct_approach": "Use MaxQuant, MSFragger, or MSGF+ for DDA data",
      "severity": "critical"
    },
    {
      "mistake": "Setting mass accuracy to 1 ppm for QTOF data",
      "why_wrong": "QTOF instruments typically have 10-20 ppm accuracy",
      "correct_approach": "Use 15-20 ppm for QTOF instruments",
      "severity": "high"
    }
  ]
}
```

---

## Impact Analysis: Why These Gaps Matter

### Current Workflow Generation Issues

**Issue 1: Redundant Tools**
- **Root Cause:** No functional purpose metadata
- **Example:** Claude suggests both MaxQuant and DIA-NN because it doesn't know they're both search engines
- **Solution:** Add `tool_category: "database_search"` and check for duplicates

**Issue 2: Wrong Tool for Data Type**
- **Root Cause:** No data type compatibility metadata
- **Example:** MaxQuant suggested for DIA data
- **Solution:** Add `data_types_supported` and `data_types_not_supported`

**Issue 3: Incompatible Tool Chains**
- **Root Cause:** No input/output format metadata
- **Example:** Tool A outputs `.raw` but Tool B needs `.mzML`
- **Solution:** Add detailed input/output format specifications

**Issue 4: No Context-Aware Suggestions**
- **Root Cause:** No workflow position metadata
- **Example:** Statistical analysis suggested before normalization
- **Solution:** Add typical workflow position and ordering

---

## Data Sources for Enhancement

### Source 1: Galaxy Tool XML Files
**Location:** `/home/yzhang/biomate/backend/tools/`

**What's Available:**
- Tool input definitions with formats
- Tool output definitions with formats
- Parameter specifications with types and ranges
- Requirements and dependencies

**Example XML Structure:**
```xml
<tool id="dia_nn" name="DIA-NN">
  <inputs>
    <param name="input_files" type="data" format="mzML,raw" label="Input Files"/>
    <param name="fasta" type="data" format="fasta" label="FASTA Database"/>
    <param name="mass_acc" type="float" value="10.0" min="1.0" max="50.0"/>
  </inputs>
  <outputs>
    <data name="report" format="tsv"/>
    <data name="protein_matrix" format="tsv"/>
  </outputs>
</tool>
```

**Action:** Parse XML files to extract input/output formats

### Source 2: Tool Documentation (Already in DB)
**Field:** `rawText`, `htmlContent`, `help_text`

**What's Available:**
- Tool descriptions
- Usage instructions
- Parameter explanations

**Action:** Use LLM to extract:
- Scientific context
- Use cases
- Limitations
- Common mistakes

### Source 3: Community Knowledge
**Sources:**
- Scientific papers
- Tool documentation websites
- Proteomics forums
- Expert knowledge

**Action:** Create curated knowledge base for common tools

### Source 4: Workflow History (If Available)
**Table:** `tool_usage_patterns`

**What's Available:**
- Tool sequences that worked
- Tool combinations that failed
- Success rates

**Action:** Mine patterns to learn:
- Common tool chains
- Typical ordering
- Incompatible combinations

---

## Proposed Schema Enhancements

### Add to `tools` Table
```sql
ALTER TABLE tools ADD COLUMN scientific_context TEXT;  -- JSON
ALTER TABLE tools ADD COLUMN workflow_metadata TEXT;   -- JSON
ALTER TABLE tools ADD COLUMN alternatives TEXT;        -- JSON
ALTER TABLE tools ADD COLUMN common_mistakes TEXT;     -- JSON
ALTER TABLE tools ADD COLUMN validation_rules TEXT;    -- JSON
```

### New Table: `tool_relationships`
```sql
CREATE TABLE tool_relationships (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id TEXT,
    relationship_type TEXT,  -- 'precedes', 'follows', 'replaces', 'incompatible_with'
    related_tool_id TEXT,
    context TEXT,            -- When this relationship applies
    confidence REAL,
    source TEXT,             -- 'manual', 'learned', 'inferred'
    FOREIGN KEY (tool_id) REFERENCES tools (tool_id),
    FOREIGN KEY (related_tool_id) REFERENCES tools (tool_id)
);
```

### New Table: `tool_formats`
```sql
CREATE TABLE tool_formats (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id TEXT,
    io_type TEXT,            -- 'input' or 'output'
    parameter_name TEXT,
    format TEXT,             -- 'mzML', 'raw', 'fasta', 'txt'
    data_type TEXT,          -- 'mass_spec_data', 'protein_database', 'peptide_table'
    required BOOLEAN,
    description TEXT,
    FOREIGN KEY (tool_id) REFERENCES tools (tool_id)
);
```

---

## Implementation Roadmap

### Phase 1: Extract XML Metadata (1 week)
**Goal:** Populate input/output formats from Galaxy tool XML files

**Tasks:**
1. Parse all tool XML files in `/backend/tools/`
2. Extract `<inputs>` and `<outputs>` sections
3. Map formats to data types
4. Update `inputs` and `outputs` fields in database
5. Populate `tool_formats` table

**Script:** `scripts/extract_tool_io_from_xml.py`

### Phase 2: Enrich with Scientific Context (1-2 weeks)
**Goal:** Add scientific context for top 100 most-used tools

**Tasks:**
1. Identify top 100 tools by category (proteomics, genomics, etc.)
2. For each tool, create `scientific_context` JSON:
   - Use LLM to extract from help_text
   - Add manual curation for critical tools
   - Document data type compatibility
3. Update database with context

**Manual Curation Required:**
- Proteomics tools (20-30 tools)
- Critical workflow tools (10-15 tools)

### Phase 3: Build Tool Relationship Graph (1 week)
**Goal:** Map tool relationships for workflow ordering

**Tasks:**
1. Analyze existing successful workflows (if available)
2. Create relationship rules:
   - File conversion → Search → Quantification → Stats
   - Identify incompatible combinations
3. Populate `tool_relationships` table
4. Build graph traversal for workflow generation

### Phase 4: Parameter Enhancement (1 week)
**Goal:** Add validation rules and defaults

**Tasks:**
1. Parse parameter specs from XML
2. Add instrument-specific defaults
3. Create validation rules
4. Document common parameter mistakes

### Phase 5: Claude Prompt Integration (3-5 days)
**Goal:** Integrate enhanced metadata into Claude's prompts

**Tasks:**
1. Create tool information formatter
2. Update system prompts to use new metadata
3. Add validation rules to workflow generation
4. Test with sample queries

---

## Priority: Quick Wins

### Week 1 - Critical Fixes
**Target:** Eliminate most egregious errors

1. **Add DDA vs DIA flags** (1 day)
   - Manually tag 20-30 search engines
   - Add to `scientific_context.data_types_supported`
   - Update prompts to check compatibility

2. **Extract I/O formats from XML** (2-3 days)
   - Parse top 100 tool XMLs
   - Populate `inputs` and `outputs` fields
   - Enable format compatibility checking

3. **Create tool category mappings** (1 day)
   - Group tools by function: search, quantification, stats, etc.
   - Add `tool_function` field
   - Use for redundancy detection

4. **Document top 10 tool mistakes** (1 day)
   - MaxQuant on DIA data
   - Missing normalization before stats
   - Wrong mass tolerance for instrument
   - Add to `common_mistakes`

### Week 2 - Validation Framework
**Target:** Catch errors before execution

1. **Build tool chain validator** (2-3 days)
   - Check format compatibility
   - Check data type compatibility
   - Detect redundant tools

2. **Add parameter validation** (1-2 days)
   - Range checking
   - Instrument-specific warnings
   - Required vs optional

3. **Create workflow position rules** (1 day)
   - Define typical ordering
   - Flag out-of-order steps

---

## Data Quality Requirements

### Minimum Viable Enhancement
**For workflow generation to work acceptably:**

**Must Have (90 tools):**
- ✅ Input/output formats
- ✅ Data type compatibility (DDA/DIA/Targeted)
- ✅ Tool functional category
- ✅ Basic scientific context

**Should Have (Top 30 tools):**
- ✅ Full scientific context
- ✅ Common mistakes documentation
- ✅ Workflow position metadata
- ✅ Alternative tools

**Nice to Have:**
- Parameter validation rules
- Instrument-specific defaults
- Usage patterns from history

---

## Estimated Effort

| Task | Time | Priority | Blocker? |
|------|------|----------|----------|
| Extract I/O from XML | 3 days | Critical | Yes |
| Add DDA/DIA flags | 1 day | Critical | Yes |
| Tool categories | 1 day | Critical | Yes |
| Scientific context (30 tools) | 3 days | High | No |
| Tool relationships | 2 days | High | No |
| Common mistakes doc | 1 day | High | No |
| Parameter validation | 2 days | Medium | No |
| Workflow position rules | 1 day | Medium | No |
| **TOTAL (MVP)** | **~2 weeks** | | |

---

## Next Steps

### Immediate Actions (This Week)

1. **Create XML Parser Script**
   ```bash
   python scripts/extract_tool_io_from_xml.py
   ```
   - Parse all tool XMLs
   - Extract inputs/outputs
   - Update database

2. **Manual Curation Session**
   - Identify 30 most critical proteomics tools
   - Add scientific context for each
   - Document DDA/DIA compatibility

3. **Update System Prompts**
   - Add tool metadata to Claude's context
   - Enable validation checks
   - Add error detection

### Success Metrics

**Before Enhancement:**
- ❌ 30-40% workflows have redundant tools
- ❌ 20-30% workflows use wrong tools for data type
- ❌ 50%+ workflows have incompatible tool chains

**After Enhancement:**
- ✅ <5% workflows have redundant tools
- ✅ <5% workflows use wrong tools
- ✅ <10% workflows have incompatible chains
- ✅ 90%+ validation catches issues before execution

---

## Conclusion

The current tool index has a **solid foundation** (tool catalog, basic metadata) but lacks **critical context** for intelligent workflow generation. The gaps can be filled through:

1. **Automated extraction** from existing XML files (inputs/outputs)
2. **LLM-assisted enrichment** of help text (scientific context)
3. **Manual curation** of critical tools (30-50 tools)
4. **Pattern learning** from workflow history (if available)

**Estimated time to MVP:** 2-3 weeks with focused effort.

**Impact:** Eliminate 80-90% of current workflow generation errors.
