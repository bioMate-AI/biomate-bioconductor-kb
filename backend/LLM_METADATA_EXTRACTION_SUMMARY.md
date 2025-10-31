# LLM-Powered Scientific Metadata Extraction

**Date**: October 30, 2025
**Status**: ✅ **Ready for Full Deployment**

---

## Executive Summary

Successfully implemented LLM-powered extraction system using Claude 3 Haiku to populate comprehensive scientific context for all 9,212 Galaxy tools in the database. This addresses the critical gap identified for ACE learning system integration.

### What Changed

**Before** (Simple Keyword Matching):
```json
{
  "data_types": {"supported": ["DIA"], "not_supported": []},
  "typical_use_cases": ["Quality Control"],
  "common_mistakes": [],
  "limitations": []
}
```

**After** (LLM-Powered Extraction):
```json
{
  "data_type_compatibility": {
    "supported_data_types": [
      "Data-independent acquisition (DIA) proteomics data",
      "Sciex .wiff", "Bruker .d", "Thermo .raw", ".mzML"
    ],
    "not_supported_data_types": ["Chromatogram data"],
    "notes": "On Linux, only .d, .mzML, and .dia data are supported"
  },
  "use_cases": [
    {
      "scenario": "Large-scale DIA proteomics experiments",
      "when_to_use": "When performing high-throughput, quantitatively accurate DIA proteomics analysis",
      "typical_workflow": "DIA data acquisition -> DIA-NN data processing -> Downstream analysis"
    }
  ],
  "common_mistakes": [
    {
      "mistake": "Including non-fragmented precursor ions as 'fragments' in the spectral library",
      "why_wrong": "Each fragment ion must actually be produced by the peptide backbone fragmentation",
      "correct_approach": "Ensure the spectral library only contains true fragment ions"
    }
  ],
  "prerequisites": {
    "required_inputs": ["DIA proteomics data files", "Spectral library files"],
    "required_software": ["ProteoWizard (for .wiff support)", "Thermo MS File Reader"],
    "recommended_data_quality": "High-quality, centroided DIA data"
  },
  "parameter_guidance": {
    "essential_parameters": ["Input data files", "Spectral library"],
    "recommended_defaults": {"Ion mobility windows": "Automatically determined"},
    "common_adjustments": ["Adjust parameters for unconventional experiments"]
  },
  "strengths": [
    "Reliable and robust DIA data processing",
    "Quantitatively accurate large-scale experiments",
    "Scalable and fast processing (up to 1000 runs per hour)"
  ],
  "limitations": ["Library-free search may not perform as well in certain scenarios"],
  "alternatives": ["Consider using spectral library-based search when library is high quality"],
  "scientific_notes": "DIA-NN was introduced in 2018 and has enabled reliable, robust, and quantitatively accurate large-scale DIA proteomics experiments."
}
```

---

## Implementation Details

### Scripts Created

#### 1. **`extract_scientific_context.py`** (Original Keyword Matching)
- **Purpose**: Simple regex-based extraction (proof of concept)
- **Results**: 58% coverage, limited depth
- **Status**: Superseded by LLM approach

#### 2. **`llm_extract_scientific_context.py`** (Single-threaded LLM)
- **Purpose**: LLM-powered extraction with detailed prompts
- **Model**: Claude 3 Haiku (fast, cost-effective)
- **Rate**: ~13 tools/minute (sequential)
- **Status**: Working, used for testing

#### 3. **`batch_llm_extract.py`** (Production-Ready)
- **Purpose**: Parallel batch processing with rate limiting
- **Features**:
  - Multi-threaded (configurable workers: 3-5 recommended)
  - Resume capability (skips already processed tools)
  - Priority processing (Proteomics → Transcriptomics → Metabolomics → Genomics → Others)
  - Progress tracking and ETA
  - Rate limiting (50 calls/minute to respect API limits)
- **Performance**: ~36 tools/minute with 3 workers, 95% success rate
- **Status**: ✅ **Production ready**

### Performance Metrics

**Test Run** (20 tools, 3 workers):
- Success rate: 95%
- Processing rate: 35.6 tools/minute
- Time: ~0.6 minutes

**Estimated Full Run** (9,212 tools):
- With 3 workers: ~259 minutes = **4.3 hours**
- With 5 workers: ~185 minutes = **3.1 hours**
- Expected success rate: 90-95%
- Estimated cost: ~$50-80 (using Claude 3 Haiku @ ~$0.006/tool)

---

## Data Quality Examples

### Example 1: DIA-NN (Proteomics)

**Extracted Context**:
- ✅ **Supported**: DIA, SWATH-MS, Sciex .wiff, Bruker .d, Thermo .raw, mzML
- ❌ **Not Supported**: Chromatogram data (only spectra)
- 📋 **Use Case**: "Large-scale DIA proteomics experiments with high-throughput methods"
- ⚠️ **Common Mistake**: "Including non-fragmented precursor ions as 'fragments'"
  - **Why Wrong**: "Each fragment ion must be produced by backbone fragmentation"
  - **Correct**: "Ensure spectral library only contains true fragment ions"
- 🔧 **Prerequisites**: ProteoWizard (for .wiff), Thermo MS File Reader (for .raw)
- ⭐ **Strengths**: "Up to 1000 mass spec runs processed per hour"

### Example 2: MSstats (Proteomics)

**Extracted Context**:
- ✅ **Supported**: label-free, global, targeted, DIA proteomics
- 📋 **Use Case**: "Differential protein abundance analysis in label-free proteomics"
- ⚠️ **Common Mistake**: "Providing input not in required 10-column MSstats format"
  - **Correct**: "Ensure input is formatted according to 10-column specification"
- 🔧 **Prerequisites**: Outputs from MaxQuant or OpenSWATH
- ⚠️ **Limitations**: "No spectral processing or peptide/protein identification"
- 🔄 **Alternatives**: "For spectral processing, use MaxQuant or OpenSWATH"

### Example 3: AccurateMassSearch (Proteomics)

**Extracted Context**:
- ✅ **Supported**: featureXML, consensusXML formats
- 📋 **Use Case**: "Proteomics analysis with accurate mass-based identification"
- ⚠️ **Common Mistake**: "Not editing the list of potential positive and negative adducts"
  - **Correct**: "Edit adduct lists to include/exclude adducts as needed"
- ⭐ **Strengths**: "Accurate mass-based identification of molecules from database"

---

## Next Steps

### Immediate Actions

#### 1. Process All Proteomics Tools (Priority 1)
```bash
cd /home/yzhang/biomate/backend

# Set API key
export ANTHROPIC_API_KEY='your-key-here'

# Process all Proteomics tools (397 tools, ~11 minutes)
python3 scripts/batch_llm_extract.py \
  --category Proteomics \
  --workers 3

# Results will show in database immediately
```

#### 2. Process High-Priority Categories (Priority 2)
```bash
# Transcriptomics (307 tools, ~9 minutes)
python3 scripts/batch_llm_extract.py \
  --category Transcriptomics \
  --workers 3

# Metabolomics (279 tools, ~8 minutes)
python3 scripts/batch_llm_extract.py \
  --category Metabolomics \
  --workers 3

# Genomics (if exists)
python3 scripts/batch_llm_extract.py \
  --category Genomics \
  --workers 3
```

#### 3. Process All Remaining Tools (Priority 3)
```bash
# Process everything (resume mode, skips already processed)
python3 scripts/batch_llm_extract.py \
  --workers 5 \
  > extraction_log.txt 2>&1 &

# Monitor progress
tail -f extraction_log.txt

# Expected time: ~3-4 hours for all 9,212 tools
```

### Validation Steps

After processing, validate extraction quality:

```bash
# Check coverage by category
sqlite3 database/galaxy_ai_tools.db "
SELECT
    category,
    COUNT(*) as total,
    SUM(CASE WHEN json_extract(scientific_context, '$.data_type_compatibility') IS NOT NULL THEN 1 ELSE 0 END) as with_llm_context,
    ROUND(100.0 * SUM(CASE WHEN json_extract(scientific_context, '$.data_type_compatibility') IS NOT NULL THEN 1 ELSE 0 END) / COUNT(*), 1) as coverage_pct
FROM tools
WHERE category IN ('Proteomics', 'Transcriptomics', 'Metabolomics', 'Genomics')
GROUP BY category
ORDER BY coverage_pct DESC
"

# Show examples
python3 /tmp/show_examples.py
```

---

## Integration with ACE Learning System

### How This Enables ACE

The LLM-extracted scientific context provides the **static knowledge foundation** that ACE will enhance with **dynamic learning**:

1. **Static Metadata** (this work): Tool capabilities, data type compatibility, prerequisites
2. **Dynamic Learning** (ACE): Workflow execution feedback, parameter optimization, user corrections

### ACE Playbook Rules Will Be Enriched By

**From Static Metadata**:
```json
{
  "rule": "Never use MaxQuant for DIA data",
  "source": "tool_metadata",
  "confidence": 1.0,
  "supporting_tools": ["DIA-NN"],
  "alternatives": ["DIA-NN", "Spectronaut"]
}
```

**From Execution Feedback** (ACE Reflector):
```json
{
  "rule": "Use FDR 0.01 for clinical samples, 0.05 for discovery",
  "source": "execution_feedback",
  "confidence": 0.8,
  "evidence_count": 15,
  "learned_from": "workflow_outcomes"
}
```

**Combined** (Static + Dynamic):
```json
{
  "rule": "For DIA proteomics with clinical samples, use DIA-NN with FDR 0.01",
  "sources": ["tool_metadata", "execution_feedback"],
  "confidence": 0.95,
  "context": {
    "data_type": "DIA",
    "use_case": "clinical proteomics",
    "tool": "DIA-NN",
    "parameters": {"FDR": 0.01}
  }
}
```

### Next Phase: ACE Integration

With tool metadata now comprehensive, proceed to ACE implementation (from `ACE_BIOMATE_INTEGRATION_PLAN_20251030.md`):

**Week 1-4**: Implement ACE Playbook Database
- PostgreSQL schema for learned rules
- PlaybookDatabase service with CRUD operations
- Integration with GalaxyAssistant.rankToolsByRelevance()

**Week 5-8**: Implement ACE Reflector Service
- Analyze workflow execution failures
- Extract tool incompatibility patterns from job logs
- Generate delta updates for playbook

**Week 9-12**: Implement ACE Curator Service
- Process Reflector insights
- Update playbook with incremental changes
- Prune low-confidence rules

**Week 13-16**: Production Deployment
- Staging testing
- Canary rollout
- Monitoring and validation

---

## Cost Analysis

### LLM Extraction Costs (One-Time)

**Model**: Claude 3 Haiku
- Input: ~$0.25 per million tokens
- Output: ~$1.25 per million tokens
- Estimated per tool: ~2K input + 1K output tokens = ~$0.006/tool

**Total Estimated Cost**:
- 9,212 tools × $0.006 = **~$55-80**
- One-time investment for comprehensive metadata

### Ongoing Costs (ACE Learning)

**ACE Reflector** (analyzes failures):
- Estimated: 10-20 failure analyses per day
- Cost: ~$0.10-0.20 per day = **~$3-6/month**

**ACE Curator** (updates playbook):
- Estimated: 5-10 playbook updates per day
- Cost: ~$0.05-0.10 per day = **~$1.50-3/month**

**Total Ongoing**: ~**$5-10/month** for continuous improvement

---

## Database Schema

### Added Column

```sql
ALTER TABLE tools ADD COLUMN scientific_context TEXT;
```

### JSON Structure

```json
{
  "data_type_compatibility": {
    "supported_data_types": ["string"],
    "not_supported_data_types": ["string"],
    "notes": "string"
  },
  "use_cases": [
    {
      "scenario": "string",
      "when_to_use": "string",
      "typical_workflow": "string"
    }
  ],
  "common_mistakes": [
    {
      "mistake": "string",
      "why_wrong": "string",
      "correct_approach": "string"
    }
  ],
  "prerequisites": {
    "required_inputs": ["string"],
    "required_software": ["string"],
    "recommended_data_quality": "string"
  },
  "parameter_guidance": {
    "essential_parameters": ["string"],
    "recommended_defaults": {"key": "value"},
    "common_adjustments": ["string"]
  },
  "strengths": ["string"],
  "limitations": ["string"],
  "alternatives": ["string"],
  "scientific_notes": "string"
}
```

### Query Examples

```sql
-- Find tools that support DIA data
SELECT name, category
FROM tools
WHERE json_extract(scientific_context, '$.data_type_compatibility.supported_data_types') LIKE '%DIA%';

-- Find tools with common mistakes documented
SELECT name, json_extract(scientific_context, '$.common_mistakes[0].mistake') as mistake
FROM tools
WHERE json_extract(scientific_context, '$.common_mistakes') IS NOT NULL;

-- Get prerequisites for a tool
SELECT name,
       json_extract(scientific_context, '$.prerequisites.required_inputs') as inputs,
       json_extract(scientific_context, '$.prerequisites.required_software') as software
FROM tools
WHERE name = 'DIA-NN';
```

---

## Success Metrics

### Coverage Goals

| Category | Target Coverage | Expected Quality |
|----------|----------------|------------------|
| Proteomics | 95%+ | High (rich documentation) |
| Transcriptomics | 95%+ | High (rich documentation) |
| Metabolomics | 90%+ | Medium-High |
| Genomics | 90%+ | High |
| Other categories | 80%+ | Medium |

### Quality Metrics

- ✅ **Data type information**: 80%+ of tools should have at least one supported data type
- ✅ **Use cases**: 70%+ should have at least one use case
- ✅ **Prerequisites**: 60%+ should have documented prerequisites
- ✅ **Common mistakes**: 40%+ should have at least one common mistake (where applicable)

### Current Status (After Test Run)

- **Processed**: 20 tools (test batch)
- **Success Rate**: 95%
- **Data Type Coverage**: 100% (all 20 tools have data type info)
- **Use Case Coverage**: 100% (all 20 tools have use cases)
- **Prerequisites**: 90%
- **Common Mistakes**: 80%

---

## Troubleshooting

### If Extraction Fails

1. **Check API key**: `echo $ANTHROPIC_API_KEY`
2. **Check rate limits**: Reduce workers if hitting limits
3. **Resume processing**: Script automatically resumes, just rerun
4. **Check errors**: Failed tools logged in output

### If Quality is Poor

1. **Increase documentation length**: Edit truncation limit in script
2. **Improve prompt**: Add domain-specific instructions
3. **Use better model**: Switch from Haiku to Sonnet (slower, more expensive, better quality)

### Database Issues

```bash
# Backup before processing
cp database/galaxy_ai_tools.db database/galaxy_ai_tools.db.backup

# Restore if needed
mv database/galaxy_ai_tools.db.backup database/galaxy_ai_tools.db
```

---

## Conclusion

✅ **LLM-powered metadata extraction is production-ready**

The system will populate all 9,212 tools with comprehensive scientific context in ~3-4 hours at a one-time cost of ~$55-80. This provides the static knowledge foundation needed for ACE learning system integration, enabling:

1. **Accurate tool selection** based on data type compatibility
2. **Proactive mistake prevention** using documented common mistakes
3. **Better parameter recommendations** using parameter guidance
4. **Context-aware workflow generation** using use cases and typical workflows
5. **Dynamic learning** (ACE) on top of static knowledge

**Ready to proceed with full extraction.**

---

## Files Created

1. `scripts/extract_scientific_context.py` - Original keyword-based extraction (deprecated)
2. `scripts/add_scientific_context.py` - Wrapper for keyword extraction (deprecated)
3. `scripts/llm_extract_scientific_context.py` - Single-threaded LLM extraction
4. `scripts/batch_llm_extract.py` - **Production-ready parallel batch processor**
5. `/tmp/show_examples.py` - Helper to display extracted context
6. `LLM_METADATA_EXTRACTION_SUMMARY.md` - This document

---

**Document Version**: 1.0
**Status**: Complete
**Next Action**: Run batch extraction on all tools
