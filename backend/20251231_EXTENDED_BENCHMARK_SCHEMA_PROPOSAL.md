# Extended Benchmark Schema: Domain Know-How + Performance

## Current State Analysis

### What We Have (benchmark_knowledge.db)
```
benchmark_studies     → Paper metadata
benchmark_tools       → Tools with strengths/weaknesses
benchmark_tasks       → Datasets, metrics
benchmark_results     → Scores, rankings (64 entries)
benchmark_decision_rules → When to use which tool
```

### What Claude Skills Provide (SKILL.md)
- Code examples and workflows
- Parameter guidelines by scenario
- Interpretation thresholds (e.g., pLDDT > 90 = high confidence)
- Common pitfalls and solutions
- Performance tips

### Gap Analysis
| Knowledge Type | benchmark_knowledge.db | Claude Skills | Gap |
|----------------|------------------------|---------------|-----|
| Which tool to use | ✅ decision_rules | ❌ | - |
| Performance rankings | ✅ results | ❌ | - |
| How to use tool | ❌ | ✅ | **Need to link** |
| Parameter by scenario | ❌ | Partial | **Need schema** |
| Interpretation guidelines | ❌ | ✅ | **Need schema** |
| Common pitfalls | ❌ | Partial | **Need schema** |

---

## Proposed Schema Extension

### Option A: Extend benchmark_knowledge.db (Recommended)

Add new tables for domain know-how:

```sql
-- Scenario-specific parameter recommendations
CREATE TABLE parameter_recommendations (
    id INTEGER PRIMARY KEY,
    tool_name TEXT NOT NULL,
    scenario TEXT NOT NULL,           -- "low_depth_rnaseq", "large_proteome", etc.
    scenario_conditions TEXT,          -- JSON: {"read_depth": "<10M", "sample_count": ">100"}
    recommended_parameters TEXT,       -- JSON: {"--alignIntronMax": 50000, "--outFilterMismatchNmax": 10}
    rationale TEXT,                    -- Why these parameters work for this scenario
    source TEXT,                       -- Paper DOI or "expert_knowledge"
    UNIQUE(tool_name, scenario)
);

-- Interpretation guidelines (thresholds, quality metrics)
CREATE TABLE interpretation_guidelines (
    id INTEGER PRIMARY KEY,
    tool_name TEXT NOT NULL,
    metric_name TEXT NOT NULL,         -- "pLDDT", "mapping_rate", "FDR"
    threshold_low REAL,
    threshold_medium REAL,
    threshold_high REAL,
    interpretation_low TEXT,           -- "Unreliable, likely disordered"
    interpretation_medium TEXT,        -- "Use with caution"
    interpretation_high TEXT,          -- "High confidence"
    source TEXT
);

-- Common pitfalls and solutions
CREATE TABLE pitfalls_solutions (
    id INTEGER PRIMARY KEY,
    tool_name TEXT,                    -- NULL for domain-wide pitfalls
    domain TEXT,                       -- "proteomics", "rnaseq", "structure"
    pitfall TEXT NOT NULL,             -- "Using wrong reference genome version"
    symptoms TEXT,                     -- "Low mapping rate, many unmapped reads"
    solution TEXT NOT NULL,            -- "Ensure reference matches sample species/assembly"
    severity TEXT,                     -- "critical", "warning", "info"
    source TEXT
);

-- Link to Claude skill documents
CREATE TABLE skill_document_links (
    id INTEGER PRIMARY KEY,
    tool_name TEXT NOT NULL,
    skill_path TEXT NOT NULL,          -- "scientific-databases/alphafold-database/SKILL.md"
    skill_type TEXT,                   -- "database", "tool", "workflow"
    last_synced TEXT
);
```

### Option B: Extend tool_knowledge table

Add fields to existing tool_knowledge in galaxy_ai_tools.db:

```sql
ALTER TABLE tool_knowledge ADD COLUMN parameter_scenarios TEXT;  -- JSON
ALTER TABLE tool_knowledge ADD COLUMN interpretation_guidelines TEXT;  -- JSON
ALTER TABLE tool_knowledge ADD COLUMN common_pitfalls TEXT;  -- JSON
ALTER TABLE tool_knowledge ADD COLUMN skill_document_path TEXT;
ALTER TABLE tool_knowledge ADD COLUMN domain_knowhow TEXT;  -- Free-form expert knowledge
```

---

## Example Data Structure

### Parameter Recommendations
```json
{
  "tool_name": "STAR",
  "scenarios": [
    {
      "name": "low_depth_rnaseq",
      "conditions": {"read_depth": "<10M reads"},
      "parameters": {
        "--outFilterMismatchNmax": 10,
        "--outFilterMultimapNmax": 20,
        "--alignIntronMax": 50000
      },
      "rationale": "More permissive filters for low-depth samples to retain reads"
    },
    {
      "name": "long_read_rnaseq",
      "conditions": {"read_length": ">150bp"},
      "parameters": {
        "--alignIntronMax": 100000,
        "--outFilterMismatchNoverLmax": 0.1
      },
      "rationale": "Extended intron sizes for long-read alignment"
    }
  ]
}
```

### Interpretation Guidelines
```json
{
  "tool_name": "AlphaFold 3",
  "metrics": [
    {
      "name": "pLDDT",
      "type": "per_residue_confidence",
      "thresholds": {
        "very_high": {"min": 90, "interpretation": "Suitable for detailed analysis, drug binding sites"},
        "high": {"min": 70, "max": 90, "interpretation": "Reliable backbone, use for general structure"},
        "low": {"min": 50, "max": 70, "interpretation": "Flexible regions, use with caution"},
        "very_low": {"max": 50, "interpretation": "Likely disordered, do not use for structure analysis"}
      }
    },
    {
      "name": "PAE",
      "type": "domain_confidence",
      "thresholds": {
        "confident": {"max": 5, "interpretation": "Reliable domain-domain positioning"},
        "moderate": {"min": 5, "max": 15, "interpretation": "Some uncertainty in relative positions"},
        "uncertain": {"min": 15, "interpretation": "Domains may be mobile or incorrectly placed"}
      }
    }
  ]
}
```

### Common Pitfalls
```json
{
  "domain": "proteomics",
  "tool_name": "DIA-NN",
  "pitfalls": [
    {
      "issue": "Using library-free mode for first analysis",
      "symptoms": "Low protein identification rate, many missing values",
      "solution": "For new sample types, first build a spectral library from DDA data or use a published library",
      "severity": "warning"
    },
    {
      "issue": "Not matching MaxLFQ normalization to sample type",
      "symptoms": "Batch effects, inflated fold changes",
      "solution": "Use 'Robust LC (high precision)' for label-free, 'Robust LC (high accuracy)' for TMT",
      "severity": "critical"
    }
  ]
}
```

---

## Integration Strategy

### 1. Database + Skills Hybrid

```
User Query: "How do I analyze DIA proteomics data?"

Step 1: Query benchmark_knowledge.db
  → Best tool: DIA-NN (based on decision_rules)
  → Benchmark evidence: "DIA-NN achieves 20% more protein IDs" (from benchmark_results)

Step 2: Query parameter_recommendations
  → For "clinical_samples": {"--mass-acc": 10, "--window-width": 12}
  → For "low_abundance": {"--min-precursor-charge": 1}

Step 3: Load Claude skill document (if available)
  → Full usage guide, code examples

Step 4: Query pitfalls_solutions
  → "Warning: Ensure spectral library matches your instrument type"
```

### 2. Skill Document Sync

When skill documents exist, sync key info to DB:
```python
def sync_skill_to_db(skill_path: str, tool_name: str):
    """Extract structured info from SKILL.md to DB tables"""
    skill_content = read_skill_document(skill_path)

    # Extract interpretation guidelines
    guidelines = extract_thresholds(skill_content)
    save_to_interpretation_guidelines(tool_name, guidelines)

    # Extract common pitfalls from "Important Notes" section
    pitfalls = extract_pitfalls(skill_content)
    save_to_pitfalls_solutions(tool_name, pitfalls)

    # Link the document
    save_skill_link(tool_name, skill_path)
```

---

## Recommendation

**Use Option A (extend benchmark_knowledge.db)** because:

1. **Separation of concerns**: Performance benchmarks + domain know-how in one focused DB
2. **Query efficiency**: Structured tables for scenario lookup
3. **Complementary to skills**: DB for quick lookup, skills for deep dive
4. **LLM-friendly**: Both can feed context to the LLM

**Workflow**:
```
1. benchmark_knowledge.db → WHICH tool (rankings, evidence)
2. parameter_recommendations → HOW to configure (scenario-specific)
3. interpretation_guidelines → HOW to interpret results
4. pitfalls_solutions → WHAT to avoid
5. skill_document_links → WHERE to learn more
```

**Claude Skills Usage**:
- Keep as reference documents for detailed walkthroughs
- Sync critical info (thresholds, pitfalls) to DB for structured queries
- Load full skill when user asks "How do I use X?"

---

## Next Steps

1. Add new tables to benchmark_knowledge.db
2. Populate with proteomics data (DIA-NN, MaxQuant, Spectronaut)
3. Populate with structure prediction data (AlphaFold 3, ESMFold)
4. Sync existing Claude skills to DB where applicable
5. Update ResearchAgent to query new tables

---

*Prepared: 2024-12-31*
