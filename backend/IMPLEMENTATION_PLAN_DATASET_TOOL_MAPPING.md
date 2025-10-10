# Dataset-Tool Compatibility Mapping Implementation Plan
**Date**: 2025-10-10
**Status**: Ready to Execute

---

## Summary

Automated system to build `compatible_tools` field for 115 datasets using:
- ✅ Code filtering (category + keyword matching)
- ✅ Web search validation (Brave Search API)
- ✅ LLM reasoning (GPT-4o-mini with search results)

---

## System Architecture

```
INPUT: reference_data_complete.json (115 datasets, 40 data tools)
    ↓
STEP 1: Code Filtering
    - Filter 6,295 Galaxy tools by category/keywords
    - Result: ~50-200 candidate tools per dataset
    ↓
STEP 2: Web Search (Brave API)
    - Search tool documentation on toolshed.g2.bx.psu.edu
    - Search usage examples and tutorials
    - Search format compatibility info
    - Result: 5-10 URLs with descriptions per tool
    ↓
STEP 3: LLM Analysis (GPT-4o-mini)
    - Analyze search results for compatibility evidence
    - Extract parameter names
    - Assign confidence scores (0-1)
    - Result: Compatible tools with reasoning
    ↓
OUTPUT: reference_data_with_compatible_tools.json
    Each dataset has:
    "compatible_tools": [
      {
        "tool_id": "...",
        "tool_name": "...",
        "confidence": 0.85,
        "parameter_name": "reference_database",
        "reasoning": "...",
        "evidence_urls": [...]
      }
    ]
```

---

## Files Created

### 1. Main Script
**`scripts/build_dataset_tool_compatibility_map.py`** (400+ lines)
- Code filtering using category/keyword matching
- Integrates web search validator
- Batch processes all 115 datasets
- Outputs JSON with compatible_tools

**Key Functions**:
- `filter_candidate_tools()` - Category + keyword filtering
- `process_dataset()` - Process single dataset
- `process_all_datasets()` - Batch process with progress logging

### 2. Web Search Validator
**`scripts/web_search_validator.py`** (250+ lines)
- Brave Search API integration
- LLM analysis of search results
- Fallback for no web search (LLM-only)

**Key Functions**:
- `search_web()` - Query Brave Search API
- `validate_compatibility()` - Full validation pipeline
- `_llm_validation_with_web()` - Analyze search results
- `_llm_validation_no_web()` - Fallback without search

### 3. Test Script
**`scripts/test_dataset_tool_matching.py`**
- Demonstrates why code-only is insufficient
- Shows semantic matching challenges
- Proposes hybrid approach (completed)

### 4. Documentation
**`scripts/README_COMPATIBILITY_MAPPING.md`**
- Complete usage guide
- API setup instructions
- Cost breakdown
- Example output

---

## Setup Instructions

### 1. Install Dependencies

```bash
pip install openai requests
```

### 2. Configure API Keys

```bash
# Required: OpenAI API
export OPENAI_API_KEY="sk-..."

# Optional but recommended: Brave Search API
export BRAVE_API_KEY="BSA..."  # Get from https://brave.com/search/api/
```

**Brave Search API**:
- Free tier: 2,000 queries/month
- Paid tier: $5/month for 15,000 queries
- Needed for ~6,900 queries (115 datasets × 20 tools × 3 searches)
- **Recommendation**: Use paid tier for one month

### 3. Verify Setup

```bash
python scripts/web_search_validator.py
```

Expected output: Validation test with sample dataset

---

## Execution Plan

### Phase 1: Test Run (15 minutes)

```bash
# Test with 3 datasets
python scripts/build_dataset_tool_compatibility_map.py --test
```

**Expected output**:
- `reference_data_with_compatible_tools.json` (partial)
- `logs/compatibility_mapping.log`
- Summary statistics for 3 datasets

**Validation**:
- Check log for web search results
- Verify compatible_tools array structure
- Review confidence scores and reasoning

### Phase 2: Small Batch (1 hour)

```bash
# Process 20 datasets
python scripts/build_dataset_tool_compatibility_map.py --limit 20
```

**Expected**:
- ~400 tool validations
- ~1,200 web searches
- Cost: ~$1.50

**Review**:
- Match rate (% datasets with compatible tools)
- Average confidence scores
- Common rejection reasons

### Phase 3: Full Processing (3-4 hours)

```bash
# Process all 115 datasets
python scripts/build_dataset_tool_compatibility_map.py
```

**Expected**:
- ~2,300 tool validations
- ~6,900 web searches
- Cost: ~$7-8
- Time: 3-4 hours (API rate limits)

**Monitoring**:
```bash
# Watch progress
tail -f logs/compatibility_mapping.log
```

---

## Output Specification

### Structure

```json
{
  "tools": { ... },  // Unchanged
  "datasets": {
    "biomni_data_lake_BindingDB_All_202409_tsv": {
      "name": "BindingDB_All_202409.tsv",
      "format": "tsv",
      "category": "drug_discovery",
      "description": "...",
      "use_cases": [...],
      "index_columns": [...],
      "schema": {...},

      "compatible_tools": [  // NEW FIELD
        {
          "tool_id": "toolshed.g2.bx.psu.edu/repos/.../similarity_search",
          "tool_name": "Molecular Similarity Search",
          "confidence": 0.85,
          "parameter_name": "reference_database",
          "reasoning": "Tool documentation at https://toolshed.g2.bx.psu.edu/... shows 'reference_database' parameter accepts TSV files with columns: ligand_id, target_id, affinity_score. BindingDB format matches exactly.",
          "evidence_urls": [
            "https://toolshed.g2.bx.psu.edu/repos/.../similarity_search",
            "https://galaxyproject.org/tutorials/similarity_search_tutorial"
          ],
          "caveats": null
        }
      ]
    }
  },
  "metaboanalyst_databases": { ... }  // Unchanged
}
```

### Confidence Levels

- **0.9-1.0**: High confidence (explicit documentation found)
- **0.7-0.9**: Medium-high (good evidence)
- **0.6-0.7**: Medium (indirect evidence)
- **<0.6**: Excluded (insufficient evidence)

---

## Cost & Time Breakdown

### API Costs

**Brave Search**:
- Queries: ~6,900
- Free tier: 2,000/month (insufficient)
- Paid tier: $5/month for 15,000 queries
- **Cost**: $5

**OpenAI GPT-4o-mini**:
- API calls: ~2,300
- Input: ~500 tokens/call × 2,300 = 1.15M tokens
- Output: ~100 tokens/call × 2,300 = 0.23M tokens
- Rate: $0.15/1M input, $0.60/1M output
- **Cost**: (1.15 × $0.15) + (0.23 × $0.60) = $0.31

**Total Cost**: ~$5-8

### Time Breakdown

- Setup: 15 minutes
- Test run (3 datasets): 15 minutes
- Small batch (20 datasets): 1 hour
- Full processing (115 datasets): 3-4 hours
- Review & validation: 30 minutes

**Total Time**: ~5 hours (mostly automated)

---

## Expected Results

### Success Metrics

**Match Rate**: 80-90% of datasets get compatible tools
- Metabolomics datasets: ~90% (many specialized tools)
- Drug discovery datasets: ~85% (cheminformatics tools)
- Genomics datasets: ~80% (many tools)
- Rare categories: ~50% (fewer tools)

**Tools per Dataset**: 5-10 on average
- High: BindingDB (12 tools), PubChem (11 tools)
- Medium: Most datasets (5-8 tools)
- Low: Niche datasets (1-3 tools)

**Confidence Distribution**:
- High (0.9+): 20-30% of matches
- Medium-high (0.7-0.9): 50-60% of matches
- Medium (0.6-0.7): 10-20% of matches

### Validation

Post-processing validation (manual sampling):
1. Pick 10 random dataset-tool pairs
2. Test in actual Galaxy workflows
3. Verify parameter names are correct
4. Check format compatibility

**Expected accuracy**: 85-95% (based on confidence scores)

---

## Next Steps After Completion

### 1. Replace Main Reference File

```bash
# Backup original
cp reference_data_complete.json reference_data_complete.backup.json

# Replace with new version
cp reference_data_with_compatible_tools.json reference_data_complete.json
```

### 2. Build Unified Search Index

Create SQLite FTS5 database combining:
- 6,295 Galaxy tools
- 115 datasets with compatible_tools
- 40 data source tools

Enable AI workflow generator to discover both tools and datasets.

### 3. Update Workflow Generator

Modify `lib/galaxy/ai/galaxy_workflow_generator.py`:
- Search unified index (tools + datasets)
- For each workflow step, check if dataset needed
- Inject dataset as tool parameter if compatible

### 4. Test End-to-End

```
User: "Find kinase inhibitors similar to imatinib in BindingDB"
    ↓
AI searches unified index
    ↓
Finds: PubChem query tool + similarity search tool + BindingDB dataset
    ↓
Generates workflow:
  Step 1: PubChem query (get imatinib structure)
  Step 2: Similarity search (database=/path/to/BindingDB.tsv)
  Step 3: Filter for kinases
```

---

## Troubleshooting

### Issue: Low match rate

**Solutions**:
- Review log for common rejection reasons
- Adjust keyword mapping in `CATEGORY_MAPPING`
- Lower confidence threshold (0.6 → 0.5)
- Add more specific search queries

### Issue: Brave Search rate limits

**Solutions**:
- Use paid tier ($5/month)
- Add delays between requests (auto-implemented)
- Process in smaller batches

### Issue: High LLM costs

**Solutions**:
- Use GPT-4o-mini instead of GPT-4 (already doing)
- Reduce candidates per dataset (20 → 10)
- Cache results to avoid re-processing

### Issue: False positives

**Solutions**:
- Increase confidence threshold (0.6 → 0.7)
- Require evidence_urls to be non-empty
- Manual review of low-confidence matches

---

## Success Criteria

✅ **System is successful if**:
1. ≥80% of datasets get compatible tools
2. Average 5+ tools per dataset
3. Confidence scores align with manual validation
4. Processing completes in <5 hours
5. Total cost <$10

---

## Timeline

**Day 1** (Today):
- ✅ Scripts completed
- ⏳ Test run (3 datasets)
- ⏳ Review results

**Day 2**:
- Small batch (20 datasets)
- Review and adjust
- Full processing (115 datasets)

**Day 3**:
- Manual validation sampling
- Replace main reference file
- Build unified search index

**Total**: 3 days to production-ready system

---

**Status**: Ready to execute
**Approval needed**: Confirm API keys are set and budget approved (~$8)
**Next action**: Run test with `--test` flag
