# Tool Metadata Status & ACE Integration Roadmap
**Date**: October 30, 2025
**Status**: Tool Metadata Foundation Complete ✅ | ACE Integration Ready to Start

---

## Executive Summary

The tool metadata enhancement is **COMPLETE** at the foundation level. All 9,212 Galaxy tools now have structured metadata (inputs, outputs, parameters, citations, EDAM). The next phase is to add **scientific context** and integrate the **ACE learning system** to enable self-improving workflow generation.

**Current State**: Static metadata foundation ✅
**Next Phase**: Scientific context + ACE learning system

---

## Current Tool Database Status

### Database: `galaxy_ai_tools.db` (164MB)

#### Quantitative Metrics
```
Total Tools: 9,212 (up from ~2,177 in gap analysis)
Proteomics Tools: 397
With Inputs/Outputs: 9,212 (100%) ✅
With Parameters: 9,212 (100%) ✅
With Citations: 9,212 (100%) ✅
With EDAM Operations: 9,212 (100%) ✅
```

#### Schema (Enhanced)
```sql
CREATE TABLE tools (
    -- Core identifiers
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id TEXT UNIQUE,
    name TEXT,
    version TEXT,

    -- Metadata (from Galaxy ToolShed)
    repo_owner TEXT,
    repo_name TEXT,
    category TEXT,

    -- Raw data sources
    rawText TEXT,
    htmlContent TEXT,
    url TEXT,

    -- 🔥 NEWLY POPULATED FIELDS
    description TEXT,              -- ✅ All tools
    parameters TEXT,               -- ✅ JSON, all tools
    help_text TEXT,               -- ✅ All tools
    inputs TEXT,                  -- ✅ JSON array, all tools
    outputs TEXT,                 -- ✅ JSON array, all tools
    requirements TEXT,            -- ✅ All tools
    tool_state_template TEXT,     -- ✅ All tools
    citations TEXT,               -- ✅ All tools
    edam_operations TEXT,         -- ✅ All tools (some empty arrays)
    edam_topics TEXT,             -- ✅ All tools
    tags TEXT,                    -- ✅ All tools
    examples TEXT,                -- ✅ All tools
    usage_guide TEXT,             -- ✅ All tools

    -- Timestamps
    created_at TEXT,
    updated_at TEXT,
    data_version TEXT,

    -- Dataset flags
    is_dataset INTEGER,
    dataset_metadata TEXT
);
```

#### Supporting Tables
```sql
-- Tool compatibility (partially populated)
CREATE TABLE tool_compatibility (
    tool_id TEXT,
    data_type TEXT,              -- e.g., "DIA", "DDA", "mzML"
    compatibility_type TEXT,     -- 'input' or 'output'
    confidence REAL,
    FOREIGN KEY (tool_id) REFERENCES tools (id)
);
-- Current: ~5 entries (minimal data)
-- 🎯 ACE WILL POPULATE: This table will be filled by ACE learning

-- Tool usage patterns (EMPTY - ready for ACE)
CREATE TABLE tool_usage_patterns (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_sequence TEXT,          -- JSON array of tool IDs
    frequency INTEGER DEFAULT 1,
    context TEXT,
    task_type TEXT,
    success_rate REAL DEFAULT 1.0,
    last_used TIMESTAMP
);
-- Current: 0 entries
-- 🎯 ACE WILL POPULATE: Successful tool chains from workflow executions

-- Dataset tool mapping (exists)
CREATE TABLE dataset_tool_mapping (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    dataset_tool_id TEXT,
    target_tool_id TEXT,
    parameter_name TEXT,
    confidence REAL,
    reasoning TEXT,
    created_at TEXT,
    FOREIGN KEY (dataset_tool_id) REFERENCES tools (tool_id),
    FOREIGN KEY (target_tool_id) REFERENCES tools (tool_id)
);

-- Full-text search (operational)
CREATE VIRTUAL TABLE tools_fts USING fts5(
    tool_id, name, description, category, parameters, help_text
);
```

---

## Sample Data Quality

### DIA-NN (Proteomics Tool)

```json
{
  "tool_id": "toolshed.g2.bx.psu.edu/repos/galaxyp/diann/Repository_Actions_DIA-NN",
  "name": "DIA-NN",
  "category": "Proteomics",
  "description": "DIA-NN - a universal software for data-independent acquisition (DIA) proteomics data processing by Demichev, Ralser and Lilley labs.",

  "inputs": ["csv", "mzml", "tab", "tsv", "txt"],
  "outputs": ["csv", "mzml", "tab", "tsv", "txt"],

  "parameters": [
    {
      "name": "dia_nn_is_built_on_the_following_principles",
      "label": "DIA-NN is built on the following principles",
      "type": "text",
      "help": "",
      "optional": false,
      "source": "rawText"
    },
    {
      "name": "scalability_and_speed",
      "label": "Scalability and speed",
      "type": "text",
      "help": "up to 1000 mass spec runs processed per hour",
      "optional": false,
      "source": "rawText"
    }
  ],

  "edam_operations": [],  // ⚠️ Empty - needs enrichment
  "citations": [...],     // ✅ Populated
  "tags": [...]          // ✅ Populated
}
```

**Quality Assessment**:
- ✅ **Good**: Inputs/outputs extracted, description present
- ⚠️ **Generic**: Formats are basic (csv, mzml, txt)
- ❌ **Missing**: No scientific context (DDA vs DIA compatibility)
- ❌ **Missing**: No structured parameter validation
- ❌ **Missing**: No common mistakes documentation

---

## Gap Analysis: What's Still Needed

### Critical Gaps (Blocks ACE Effectiveness)

#### 1. ❌ Scientific Context Metadata

**Current State**: None
**What's Needed**:
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
      "Cross-sample quantification"
    ]
  }
}
```

**Impact**: Without this, ACE cannot learn "DIA-NN works for DIA but not DDA"
**Priority**: 🔥 **CRITICAL** - Blocks ACE learning effectiveness
**Effort**: 3-5 days for top 30 proteomics tools

---

#### 2. ⚠️ Structured Parameter Validation

**Current State**: Parameters are extracted but not validated
**Example Current**:
```json
{
  "name": "scalability_and_speed",
  "type": "text",
  "help": "up to 1000 mass spec runs processed per hour"
}
```

**What's Needed**:
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
    "QTOF": 20.0
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

**Impact**: Cannot catch parameter errors before execution
**Priority**: ⚡ **HIGH** - Improves user experience
**Effort**: 1 week for parameter extraction enhancement

---

#### 3. ❌ Common Mistakes Documentation

**Current State**: None
**What's Needed**:
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

**Impact**: ACE cannot learn from documented knowledge, only from failures
**Priority**: ⚡ **HIGH** - Provides initial playbook seeds
**Effort**: 1-2 days for top 20 tools

---

#### 4. ⚠️ Workflow Position Metadata

**Current State**: None
**What's Needed**:
```json
{
  "workflow_position": {
    "typical_position": "early",  // early, middle, late
    "typical_predecessors": ["file_conversion", "quality_control"],
    "typical_successors": ["normalization", "statistical_analysis"],
    "incompatible_with": {
      "before": ["tmt_reporter_ion_quantification"],
      "after": []
    }
  }
}
```

**Impact**: Cannot detect out-of-order workflow steps
**Priority**: 🔧 **MEDIUM** - Nice to have, ACE can learn this
**Effort**: 2-3 days for graph construction

---

## Integration with ACE Learning System

### Current State: Foundation Ready ✅

```
┌──────────────────────────────────────────────────────────┐
│         CURRENT TOOL DATABASE (9,212 tools)              │
│  ✅ Inputs/Outputs extracted                             │
│  ✅ Parameters extracted                                 │
│  ✅ Citations populated                                  │
│  ✅ EDAM operations (some populated)                     │
│  ✅ Full-text search operational                         │
│  ❌ Scientific context MISSING                           │
│  ❌ Common mistakes MISSING                              │
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│              PHASE 1: ADD SCIENTIFIC CONTEXT             │
│  🔥 Priority: Top 30 proteomics tools                    │
│  📝 Manually curate for critical tools                   │
│  🤖 LLM-assisted extraction from help_text               │
│  ⏱️ Effort: 3-5 days                                     │
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│         PHASE 2: INTEGRATE ACE LEARNING SYSTEM           │
│  🧠 ACE Reflector: Analyze workflow failures             │
│  🧠 ACE Curator: Update playbook from failures           │
│  🧠 ACE Playbook DB: Store learned rules                 │
│  📊 Populate tool_usage_patterns table                   │
│  📊 Populate tool_compatibility table                    │
│  ⏱️ Effort: 8-12 weeks (from ACE integration plan)       │
└──────────────────────────────────────────────────────────┘
                          ↓
┌──────────────────────────────────────────────────────────┐
│           RESULT: SELF-IMPROVING SYSTEM                  │
│  ✅ Static metadata (from tool database)                │
│  ✅ Learned rules (from ACE playbook)                    │
│  ✅ Usage patterns (from workflow history)               │
│  🎯 Expected: +5-10% workflow success rate               │
└──────────────────────────────────────────────────────────┘
```

---

## ACE Playbook Database vs. Tool Database

**Key Distinction**:
- **Tool Database** (`galaxy_ai_tools.db`): **Static** metadata about tools
- **ACE Playbook** (PostgreSQL): **Dynamic** learned rules about tool usage

### How They Work Together

```python
# In GalaxyAssistant.rankToolsByRelevance()

async def rankToolsByRelevance(userMessage, tools, intent):
    # 1. Get static metadata from tool database
    tool_metadata = await toolDB.getToolMetadata(tool.tool_id)

    # 2. Get learned rules from ACE playbook
    playbook_rules = await playbookDB.getRelevantRules(intent.keywords)

    # 3. Combine static + learned knowledge
    system_prompt = f"""
    You are a bioinformatics tool expert.

    TOOL METADATA (static):
    - {tool.name}: {tool_metadata.description}
    - Inputs: {tool_metadata.inputs}
    - Outputs: {tool_metadata.outputs}
    - Scientific context: {tool_metadata.scientific_context}

    LEARNED RULES (dynamic):
    {format_playbook_rules(playbook_rules)}

    Rank tools by relevance...
    """

    # 4. Apply playbook penalties/bonuses
    for tool in tools:
        score = base_score

        # Check learned rules
        for rule in playbook_rules:
            if tool.name in rule.harmful_tools:
                score *= (1 - rule.confidence * 0.5)  # Penalty
            if tool.name in rule.recommended_tools:
                score += rule.confidence * 0.2  # Bonus

        # Check static scientific context
        if tool_metadata.scientific_context:
            if userIntent.data_type in tool_metadata.data_types_not_supported:
                score *= 0.1  # Strong penalty

    return ranked_tools
```

---

## Immediate Next Steps (Week 1-2)

### Option A: Quick Scientific Context Enhancement (Recommended)

**Goal**: Add scientific context for top 30 proteomics tools to unlock ACE potential

**Tasks**:
1. **Identify Critical Tools** (2 hours)
   ```sql
   SELECT tool_id, name, category, description
   FROM tools
   WHERE category = 'Proteomics'
   ORDER BY name
   LIMIT 30;
   ```
   Priority: DIA-NN, MaxQuant, MSFragger, Proteome Discoverer, Spectronaut, etc.

2. **Manual Curation** (3-4 days)
   - Create `scientific_context` JSON for each tool
   - Document DDA/DIA compatibility
   - List typical use cases
   - Document common mistakes

   Template:
   ```json
   {
     "tool_id": "diann",
     "scientific_context": {
       "purpose": "DIA proteomics database search",
       "data_types_supported": ["DIA", "SWATH"],
       "data_types_not_supported": ["DDA"],
       "best_for": ["Deep proteome coverage", "Label-free quantification"],
       "not_suitable_for": ["DDA data", "TMT/iTRAQ experiments"],
       "typical_use_cases": ["Bottom-up DIA proteomics"],
       "common_mistakes": [
         {
           "mistake": "Using DIA-NN on DDA data",
           "why_wrong": "DIA-NN optimized for DIA patterns",
           "correct_approach": "Use MaxQuant for DDA data"
         }
       ]
     }
   }
   ```

3. **Schema Migration** (1 day)
   ```sql
   ALTER TABLE tools ADD COLUMN scientific_context TEXT;
   ALTER TABLE tools ADD COLUMN workflow_metadata TEXT;
   ALTER TABLE tools ADD COLUMN common_mistakes TEXT;

   -- Update tools with curated data
   UPDATE tools
   SET scientific_context = '{...}'
   WHERE tool_id = 'diann';
   ```

4. **Integrate with GalaxyAssistant** (1 day)
   - Modify `rankToolsByRelevance()` to check scientific_context
   - Add validation before workflow generation
   - Test with sample queries

**Deliverable**: Top 30 proteomics tools with scientific context, integrated into workflow generation

---

### Option B: Start ACE Integration Immediately

**Goal**: Begin ACE learning system while metadata is being enhanced

**Parallel Tracks**:

**Track 1: Metadata Enhancement** (Person A)
- Add scientific context for tools
- Continue manual curation

**Track 2: ACE Infrastructure** (Person B)
- Set up ACE Playbook database (PostgreSQL)
- Implement ACE Reflector service
- Implement ACE Curator service

**Sync Point (Week 2)**:
- Merge enhanced metadata with ACE system
- Test end-to-end learning loop

**Risk**: ACE system won't be as effective without scientific context metadata

---

## Comparison: Tool Metadata vs. ACE Playbook

| Aspect | Tool Database (Current) | ACE Playbook (To Build) |
|--------|------------------------|-------------------------|
| **Data Source** | Galaxy ToolShed, manual curation | Workflow execution feedback |
| **Knowledge Type** | Static tool properties | Dynamic learned rules |
| **Update Frequency** | Weekly (from ToolShed) | Real-time (after each workflow) |
| **Coverage** | All 9,212 tools | Only tools used in workflows |
| **Confidence** | 100% (curated) | Variable (evidence-based) |
| **Example** | "DIA-NN supports mzML input" | "For DIA data, DIA-NN works, MaxQuant fails (6 failures)" |
| **Maintenance** | Manual updates needed | Self-updating from usage |
| **Storage** | SQLite (164MB) | PostgreSQL (growing) |

**Synergy**:
- Tool DB provides **initial knowledge** (what tool CAN do)
- ACE Playbook provides **experience** (what tool SHOULD do in practice)

---

## Success Metrics

### Phase 1: Enhanced Metadata (Weeks 1-2)
- ✅ 30 proteomics tools with scientific context
- ✅ DDA/DIA compatibility documented
- ✅ Common mistakes documented
- ✅ GalaxyAssistant integration complete
- 🎯 Target: 80% reduction in "wrong tool for data type" errors

### Phase 2: ACE Integration (Weeks 3-10)
- ✅ ACE Playbook database operational
- ✅ Reflector analyzing failures
- ✅ Curator updating playbook
- ✅ 50+ learned rules in playbook
- 🎯 Target: +5-10% workflow success rate improvement

### Phase 3: Full System (Weeks 11-16)
- ✅ tool_usage_patterns populated
- ✅ tool_compatibility populated from ACE
- ✅ 90%+ workflow success rate
- ✅ Self-improving system demonstrable
- 🎯 Target: User satisfaction >85%

---

## Recommended Approach: Hybrid

**Week 1-2**: Quick scientific context enhancement (Option A)
- Focus on top 30 proteomics tools
- Manual curation + LLM-assisted extraction
- Immediate integration with GalaxyAssistant

**Week 3-10**: ACE infrastructure build-out
- Implement ACE Playbook database
- Implement Reflector + Curator services
- Integrate with workflow execution monitoring

**Week 11-16**: Full deployment
- ACE learning from real workflows
- Continuous playbook updates
- Measure improvement metrics

**Rationale**: Get quick wins with static metadata (Week 1-2), then build long-term learning system (Weeks 3-16). This approach delivers immediate value while building toward self-improvement.

---

## Questions for Discussion

1. **Metadata Priority**: Should we enhance ALL 9,212 tools or focus on top 30-50 critical tools first?
2. **ACE Start Date**: Begin ACE implementation now (parallel) or after metadata enhancement (sequential)?
3. **Validation**: How do we validate that scientific context metadata is correct?
4. **Common Mistakes**: Should we seed ACE playbook with manually documented mistakes, or let it learn from scratch?
5. **Integration Timeline**: Full 16-week ACE plan or MVP (4 weeks) first?

---

## Resources

### Current Files
- Tool Database: `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db` (164MB, 9,212 tools)
- Schema: See above SQL
- Gap Analysis: `/home/yzhang/biomate/reference/TOOL_METADATA_GAP_ANALYSIS_20251030.md`
- ToolUniverse Plan: `/home/yzhang/biomate/reference/TOOLUNIVERSE_INTEGRATION_ARCHITECTURE_20251028.md`

### Integration Documents
- ACE Integration Plan: `/home/yzhang/biomate/reference/ACE_BIOMATE_INTEGRATION_PLAN_20251030.md`
- Integration Summary: `/home/yzhang/biomate/reference/INTEGRATION_WORK_SUMMARY_20251030.md`

---

**Document Version**: 1.0
**Status**: Ready for Implementation Decision
**Next Action**: Choose Option A (metadata first) or Option B (parallel tracks)
