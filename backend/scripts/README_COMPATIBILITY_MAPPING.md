# Dataset-Tool Compatibility Mapping System

## Overview

Automated system to build `compatible_tools` mapping for 115 datasets using:
1. **Code filtering** (category + keyword matching)
2. **Web search validation** (Brave Search API)
3. **LLM reasoning** (GPT-4o-mini analysis)

## Architecture

```
Dataset (115 total)
    ↓
Step 1: CODE FILTERING
    Filter 6,295 tools by:
    - Category match (drug_discovery → Computational chemistry)
    - Keyword overlap (binding, affinity, compound)
    - Format hints (csv, tsv, tabular)
    ↓
Candidates: ~50-200 tools per dataset
    ↓
Step 2: WEB SEARCH VALIDATION
    For each candidate (top 20):
    - Search: "galaxy {tool_name} documentation parameters"
    - Search: "galaxy {tool_name} database reference example"
    - Search: "galaxy {tool_name} {format} input"
    ↓
Search Results: 5-10 URLs with descriptions
    ↓
Step 3: LLM ANALYSIS
    Analyze search results:
    - Does tool accept database parameters?
    - Is format compatible?
    - Is scientific domain aligned?
    - Extract parameter name if compatible
    ↓
Output: compatible_tools list with confidence scores
```

## Setup

### 1. Install Dependencies

```bash
pip install openai requests
```

### 2. Set API Keys

```bash
export OPENAI_API_KEY="your-openai-api-key"
export BRAVE_API_KEY="your-brave-search-api-key"  # Get from https://brave.com/search/api/
```

**Note**: Brave Search API is free for 2,000 queries/month. For 115 datasets × 20 tools × 3 searches = 6,900 queries, you'll need the paid tier ($5/month for 15k queries).

**Alternative**: If you don't have Brave API, the script falls back to LLM-only validation (lower confidence).

## Usage

### Test Mode (3 datasets)

```bash
python scripts/build_dataset_tool_compatibility_map.py --test
```

### Process First 10 Datasets

```bash
python scripts/build_dataset_tool_compatibility_map.py --limit 10
```

### Process All 115 Datasets

```bash
python scripts/build_dataset_tool_compatibility_map.py
```

**Estimated time**:
- With web search: ~3-4 hours (API rate limits)
- Without web search: ~1 hour

**Cost**:
- Brave Search: ~$5 (if using paid tier)
- OpenAI GPT-4o-mini: ~$2-3 (2,300 API calls × $0.15/1M input tokens)
- **Total**: ~$7-8

## Output

### Output File

`reference_data_with_compatible_tools.json`

Structure:
```json
{
  "tools": {...},
  "datasets": {
    "biomni_data_lake_BindingDB_All_202409_tsv": {
      "name": "BindingDB_All_202409.tsv",
      "format": "tsv",
      "category": "drug_discovery",
      ...
      "compatible_tools": [
        {
          "tool_id": "toolshed.g2.bx.psu.edu/repos/.../similarity_search",
          "tool_name": "Molecular Similarity Search",
          "confidence": 0.85,
          "parameter_name": "reference_database",
          "reasoning": "Tool documentation shows it accepts TSV files with ligand, target, affinity columns...",
          "evidence_urls": ["https://toolshed.g2.bx.psu.edu/..."]
        },
        {
          "tool_id": "...",
          "tool_name": "Compound Screening",
          "confidence": 0.75,
          ...
        }
      ]
    }
  },
  "metaboanalyst_databases": {...}
}
```

### Log File

`logs/compatibility_mapping.log`

Contains detailed processing log with:
- Candidate filtering results
- Web search queries and results
- LLM validation reasoning for each tool
- Summary statistics

## Validation Strategy

### Confidence Scoring

- **0.9-1.0**: High confidence
  - Clear documentation found
  - Exact parameter name identified
  - Format explicitly supported
  - Multiple evidence sources

- **0.7-0.9**: Medium-high confidence
  - Good documentation found
  - Parameter likely identified
  - Format probably supported
  - Some evidence sources

- **0.5-0.7**: Medium confidence
  - Indirect evidence
  - Similar tools documented
  - Format compatibility unclear
  - Limited sources

- **0.0-0.5**: Low confidence (excluded)
  - No clear evidence
  - Only speculation
  - Format mismatch
  - No documentation found

### Decision Threshold

Only tools with `confidence >= 0.6` are included in `compatible_tools`.

## Example Output

```
======================================================================
DATASET-TO-TOOL COMPATIBILITY MAPPING
======================================================================

Processing 115 datasets

======================================================================
DATASET 1/115
======================================================================

Filtering candidates for: BindingDB_All_202409.tsv
Category: drug_discovery
Format: tsv
Found 47 candidate tools

Top 5 candidates:
  - Molecular Similarity Search (Computational chemistry) - Score: 5
  - Compound Screening Tool (Computational chemistry) - Score: 4
  - Drug Target Prediction (Drug Discovery) - Score: 4
  - ChEMBL Search (Computational chemistry) - Score: 3
  - Ligand Docking (Computational chemistry) - Score: 3

Validating top 20 candidates with LLM...

  [1/20] Validating: Molecular Similarity Search
    Web search: "galaxy Molecular Similarity Search documentation parameters"
    Found 5 results
    ✅ COMPATIBLE (confidence: 0.85)
    Reasoning: Tool documentation specifies 'reference_database' parameter accepting TSV files with ligand_id, target_id, and affinity_score columns...

  [2/20] Validating: Compound Screening Tool
    Web search: "galaxy Compound Screening Tool documentation parameters"
    Found 3 results
    ✅ COMPATIBLE (confidence: 0.75)
    Reasoning: Examples show usage with BindingDB-format files...

  [3/20] Validating: Drug Target Prediction
    Web search: "galaxy Drug Target Prediction documentation parameters"
    Found 2 results
    ❌ Not compatible (confidence: 0.45)
    Reasoning: No evidence of database parameter in documentation...

...

✅ Found 8 compatible tools for BindingDB_All_202409.tsv

======================================================================
COMPLETED
======================================================================

Output saved to: reference_data_with_compatible_tools.json
Log saved to: logs/compatibility_mapping.log

======================================================================
SUMMARY
======================================================================
Total datasets processed: 115
Datasets with compatible tools: 97 (84.3%)
Total tool-dataset matches: 612
Average tools per dataset: 5.3

Top 10 datasets by compatible tool count:
  1. BindingDB_All_202409.tsv: 12 tools
  2. PubChem_Compound_props.parquet: 11 tools
  3. ChEMBL_activities.parquet: 10 tools
  4. MetaboAnalyst MS2ID databases: 9 tools
  5. STRING_protein_links.csv: 8 tools
  ...
```

## Troubleshooting

### "BRAVE_API_KEY not set"
- Sign up at https://brave.com/search/api/
- Get API key from dashboard
- Export: `export BRAVE_API_KEY="your-key"`

### "Rate limit exceeded"
- Brave free tier: 2,000 queries/month
- Add delays between requests (auto-implemented)
- Upgrade to paid tier if needed

### "OpenAI API error"
- Check API key: `echo $OPENAI_API_KEY`
- Verify account has credits
- Check API quota

### Low match rate
- Review log file for common rejection reasons
- Adjust confidence threshold in script
- Improve keyword mapping in CATEGORY_MAPPING dict

## Next Steps

After running this script:

1. **Review results**: Check `reference_data_with_compatible_tools.json`
2. **Validate sample**: Test 5-10 tool-dataset pairs in actual Galaxy workflows
3. **Update main reference**: Replace `reference_data_complete.json` with validated output
4. **Build unified index**: Run script to combine tools + datasets in FTS5 database
5. **Update workflow generator**: Enable dataset-aware workflow generation

## Cost-Benefit Analysis

**Investment**:
- Time: 3-4 hours (mostly automated)
- Money: ~$7-8 (API costs)
- Setup: 15 minutes

**Benefit**:
- 115 datasets × 5 tools = 575+ tool-dataset mappings
- Enables dataset-aware workflow generation
- Improves AI workflow quality significantly
- One-time investment with long-term value

**ROI**: High - Saves hours of manual documentation review per dataset
