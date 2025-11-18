# Tool Quality Gate System - Implementation Guide

**Created**: 2025-11-17 11:43:00
**Purpose**: Ensure only production-ready tools with sufficient metadata are added to the tool index

---

## Executive Summary

### Problem Statement
Auto-discovered tools are being added to the index with insufficient structured data, making them unusable for workflow configuration and implementation.

**Current Status**:
- ✅ 9,212 manual tools: 96% workflow-ready
- ❌ 14 auto-discovered tools: 0% workflow-ready
  - 11 tools (79%) have blocking issues
  - 3 tools (21%) have dummy parameters
  - **0 tools ready for production workflows**

###Solution: Quality Gate System

A validation system that:
1. **Validates** tool metadata before adding to index
2. **Scores** quality on 0.0-1.0 scale with letter grades
3. **Blocks** tools that don't meet minimum requirements
4. **Reports** what's missing and how to fix it
5. **Integrates** into auto-discovery pipeline

---

## Quality Validation Results

### Current Auto-Discovered Tools Report

```
Total tools: 14
✅ Workflow ready: 0
⚠️  Needs improvement: 3  (auto_rush, auto_biotite, auto_colabfold)
🔴 Has blocking issues: 11

📊 Grade Distribution:
  B+: 3 tools   (have some data but dummy parameters)
  D:  7 tools   (missing critical data)
  F:  4 tools   (severely deficient)

🔴 Most Common Issue:
  11x - Missing or dummy parameters (cannot generate workflow forms)
```

### Individual Tool Scores

| Tool ID | Score | Grade | Workflow Ready | Blocking Issues |
|---------|-------|-------|----------------|-----------------|
| auto_biotite | 0.84 | B+ | ❌ No | 0 (but has dummy params) |
| auto_rush | 0.82 | B+ | ❌ No | 0 (but has dummy params) |
| auto_colabfold | 0.81 | B+ | ❌ No | 0 (but has dummy params) |
| auto_foldseek | 0.57 | D | ❌ No | 1 (no parameters) |
| auto_mmseqs2 | 0.56 | D | ❌ No | 1 (no parameters) |
| auto_omicverse | 0.54 | D | ❌ No | 1 (dummy parameters) |
| auto_graphein | 0.53 | D | ❌ No | 1 (no parameters) |
| auto_scanpy | 0.52 | D | ❌ No | 1 (dummy parameters) |
| auto_dash | 0.51 | D | ❌ No | 1 (dummy parameters) |
| auto_galaxy | 0.51 | D | ❌ No | 1 (dummy parameters) |
| auto_nextflow | 0.47 | F | ❌ No | 1 (no parameters) |
| auto_htslib | 0.47 | F | ❌ No | 1 (no parameters) |
| auto_seqkit | 0.47 | F | ❌ No | 1 (no parameters) |
| auto_biopython | 0.45 | F | ❌ No | 1 (no parameters) |

---

## Quality Criteria

### Scoring Categories (Weighted)

1. **Parameters (35%)** - MOST CRITICAL
   - 1.0 = Real parameters with types, labels, defaults
   - 0.2 = Dummy/placeholder parameters
   - 0.0 = No parameters

2. **Requirements (20%)** - CRITICAL
   - 1.0 = Docker + structured CPU/GPU/memory
   - 0.8 = Docker + CPU/GPU info in text
   - 0.6 = Docker only
   - 0.3 = Packages only
   - 0.0 = Nothing

3. **Basic Metadata (15%)**
   - tool_id, name, description, github_url
   - 0.25 penalty per missing field

4. **Inputs/Outputs (15%)**
   - 1.0 = Detailed specs with descriptions
   - 0.6 = File extensions only
   - 0.0 = Nothing

5. **Usage Documentation (10%)**
   - usage_guide, examples, citations
   - Bonus for length and detail

6. **Scientific Context (5%)**
   - use_cases, typical workflows
   - Nice to have but not critical

### Thresholds

| Score Range | Grade | Meaning | Action |
|-------------|-------|---------|--------|
| 0.95-1.00 | A+ | Exceptional | Auto-approve |
| 0.90-0.94 | A | Excellent | Auto-approve |
| **0.85-0.89** | **A-** | **Workflow Ready** | **Minimum for production** |
| 0.80-0.84 | B+ | Good but needs work | Block until enhanced |
| 0.70-0.79 | B/B- | Acceptable for preview | Preview mode only |
| 0.60-0.69 | C | Needs improvement | Block |
| 0.50-0.59 | D | Poor | Block |
| 0.00-0.49 | F | Severely deficient | Block |

**Minimum Production Threshold**: 0.85 (A-) + No blocking issues

---

## Tool Quality Validator

### Script: `scripts/tool_quality_validator.py`

**Features**:
- Validates all 6 quality categories
- Detects blocking issues (empty or dummy parameters)
- Generates detailed reports with recommendations
- Can block on minimum score or blocking issues
- Outputs JSON reports for automation

### Usage Examples

#### 1. Validate Single Tool
```bash
python3 scripts/tool_quality_validator.py --tool-id auto_foldseek

# Output:
# Overall Score: 0.57 (Grade: D)
# Workflow Ready: ❌ NO
# Blocking Issues: No parameters defined
```

#### 2. Validate All Auto-Discovered Tools
```bash
python3 scripts/tool_quality_validator.py --all-auto-discovered
```

#### 3. Generate JSON Report
```bash
python3 scripts/tool_quality_validator.py \
  --all-auto-discovered \
  --report quality_report.json
```

#### 4. Block on Minimum Score (CI/CD Integration)
```bash
python3 scripts/tool_quality_validator.py \
  --tool-id auto_foldseek \
  --min-score 0.85 \
  --block-on-issues

# Exits with code 1 if score < 0.85 or blocking issues found
```

#### 5. Preview Mode Check
```bash
# Allow score 0.60-0.84 for preview, block below 0.60
python3 scripts/tool_quality_validator.py \
  --tool-id auto_foldseek \
  --min-score 0.60
```

---

## Integration with Auto-Discovery Pipeline

### Current Pipeline
```
GitHub Discovery → Metadata Extraction → Wrapper Generation → Database Insert
```

### Enhanced Pipeline with Quality Gate
```
GitHub Discovery
   ↓
Metadata Extraction
   ↓
Quality Validation ←--[GATE]--→ Score < 0.85 → BLOCK/Preview Mode
   ↓                                                ↓
Score ≥ 0.85                                   Enhancement Queue
   ↓                                                ↓
Wrapper Generation                          Parameter Extraction
   ↓                                                ↓
Database Insert (Production)               Re-validate → Insert
```

### Implementation

#### Step 1: Add Validation to Pipeline Script

Modify `scripts/run_pipeline.py`:

```python
from tool_quality_validator import ToolQualityValidator

class AutoDiscoveryPipeline:
    def __init__(self, ...):
        self.validator = ToolQualityValidator(db_path)

    def process_tool(self, tool_id, ...):
        # ... existing metadata extraction ...

        # Quality validation
        tool_data = self.get_tool_metadata(tool_id)
        validation_result = self.validator.validate_tool(tool_data)

        # Decision logic
        if validation_result['overall_score'] >= 0.85 and not validation_result['blocking_issues']:
            # Production-ready: proceed with full integration
            logger.info(f"✅ {tool_id}: Production ready (score: {validation_result['overall_score']:.2f})")
            self.insert_to_production(tool_id, tool_data)

        elif validation_result['overall_score'] >= 0.60:
            # Preview mode: mark as beta
            logger.warning(f"⚠️  {tool_id}: Preview mode (score: {validation_result['overall_score']:.2f})")
            tool_data['beta'] = True
            tool_data['quality_issues'] = validation_result['issues']
            self.insert_to_preview(tool_id, tool_data)

        else:
            # Block: add to enhancement queue
            logger.error(f"❌ {tool_id}: Blocked (score: {validation_result['overall_score']:.2f})")
            self.add_to_enhancement_queue(tool_id, validation_result)
            return False

        return True
```

#### Step 2: Create Enhancement Queue Table

```sql
CREATE TABLE tool_enhancement_queue (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    tool_id TEXT UNIQUE,
    github_url TEXT,
    quality_score REAL,
    grade TEXT,
    blocking_issues TEXT,  -- JSON array
    validation_result TEXT,  -- Full JSON
    added_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status TEXT DEFAULT 'pending',  -- pending, processing, enhanced, failed
    priority INTEGER DEFAULT 0
);
```

#### Step 3: Database Schema Updates

Add quality tracking fields to `tools` table:

```sql
ALTER TABLE tools ADD COLUMN validated_at TIMESTAMP;
ALTER TABLE tools ADD COLUMN validation_score REAL;
ALTER TABLE tools ADD COLUMN validation_grade TEXT;
ALTER TABLE tools ADD COLUMN workflow_ready BOOLEAN DEFAULT 0;
ALTER TABLE tools ADD COLUMN beta_mode BOOLEAN DEFAULT 0;
```

---

## Quality Gate Policies

### Policy 1: Production Requirement

**Rule**: Tool must score ≥ 0.85 with no blocking issues

**Blocking Issues**:
- Missing parameters (`parameters = []`)
- Dummy/placeholder parameters
- No Docker container in requirements
- Missing basic metadata (name, description, url)

**Action**: Block tool from production index, add to enhancement queue

### Policy 2: Preview/Beta Mode

**Rule**: Tool scores 0.60-0.84 OR has blocking issues but good metadata

**Conditions**:
- Has good documentation (usage_guide, examples)
- Has Docker container
- Missing only parameters or detailed I/O specs

**Action**:
- Mark as `beta: true` in database
- Show "Preview" badge in UI
- Warn users: "Limited workflow support"
- Display usage_guide for manual reference

### Policy 3: Auto-Reject

**Rule**: Tool scores < 0.60

**Conditions**:
- Missing multiple critical fields
- Severely incomplete metadata
- No deployment method (no Docker, no packages)

**Action**:
- Block from all indexes
- Log for manual review
- Do not add to enhancement queue (not worth it)

---

## Enhancement Queue Workflow

### Automatic Enhancement

When tool is blocked, system attempts to auto-enhance:

```python
def auto_enhance_tool(tool_id):
    """Attempt automatic enhancement."""

    # 1. Extract parameters from help text
    if missing_parameters:
        params = extract_parameters_from_help(tool_id)
        if params:
            update_tool_parameters(tool_id, params)

    # 2. Parse usage guide for requirements
    if missing_requirements:
        reqs = parse_resource_requirements(tool_id)
        if reqs:
            update_tool_requirements(tool_id, reqs)

    # 3. Re-validate
    validation = validator.validate_tool(get_tool(tool_id))

    if validation['overall_score'] >= 0.85:
        move_to_production(tool_id)
    else:
        mark_for_manual_review(tool_id)
```

### Manual Review Queue

Tools that can't be auto-enhanced are flagged for manual review:

```bash
# List tools needing manual review
python3 scripts/tool_quality_validator.py \
  --all-auto-discovered \
  --block-on-issues \
  | grep "FAILED"

# Generate enhancement tasks
python3 scripts/generate_enhancement_tasks.py \
  --from-validation-report quality_report.json \
  --output enhancement_tasks.md
```

---

## Monitoring and Reporting

### Daily Quality Report

Cron job to track quality trends:

```bash
#!/bin/bash
# scripts/daily_quality_report.sh

python3 scripts/tool_quality_validator.py \
  --all-auto-discovered \
  --report /var/reports/quality_$(date +%Y%m%d).json

# Send summary email
python3 scripts/send_quality_summary.py \
  --report /var/reports/quality_$(date +%Y%m%d).json \
  --to team@example.com
```

### Quality Dashboard Metrics

Track over time:
- Average quality score
- % workflow-ready tools
- Most common blocking issues
- Enhancement queue size
- Time to production (discovery → ready)

### Example Dashboard

```
📊 Tool Quality Dashboard (2025-11-17)

Overall Metrics:
  Total Tools: 9,226
  Workflow Ready: 9,212 (99.8%)
  In Enhancement Queue: 11
  Auto-discovered (production): 3
  Auto-discovered (beta): 0
  Auto-discovered (blocked): 11

Quality Distribution:
  A/A+: 8,903 (96%)
  B: 309 (3%)
  C-F: 11 (0.1%)

Enhancement Queue:
  Pending: 11
  Processing: 0
  Average wait time: 0 days (no processor yet)

Most Common Issues:
  1. Missing parameters: 11 tools
  2. Unstructured requirements: 11 tools
  3. Minimal I/O specs: 7 tools
```

---

## Deployment Guide

### Phase 1: Implement Validator (✅ DONE)

- [x] Create `tool_quality_validator.py`
- [x] Test on existing tools
- [x] Generate baseline report

### Phase 2: Integrate into Pipeline (IN PROGRESS)

- [ ] Modify `run_pipeline.py` to call validator
- [ ] Add quality gate decision logic
- [ ] Create enhancement queue table
- [ ] Update database schema

### Phase 3: Build Enhancement Tools

- [ ] Create parameter extraction tool
- [ ] Create requirements parser
- [ ] Create I/O spec enhancer
- [ ] Test enhancement workflow

### Phase 4: Production Rollout

- [ ] Enable quality gate for new tools only
- [ ] Monitor for 1 week
- [ ] Adjust thresholds based on results
- [ ] Enable for all tools

### Phase 5: Continuous Improvement

- [ ] Auto-enhance blocked tools
- [ ] Manual review queue
- [ ] Quality monitoring dashboard
- [ ] Monthly quality audits

---

## Testing the Quality Gate

### Test 1: Block Low-Quality Tool

```bash
# Validate foldseek (should block - score 0.57)
python3 scripts/tool_quality_validator.py \
  --tool-id auto_foldseek \
  --min-score 0.85 \
  --block-on-issues

# Expected: Exit code 1, blocking message
```

### Test 2: Preview Mode Tool

```bash
# Check biotite (score 0.84, no blocking issues)
python3 scripts/tool_quality_validator.py \
  --tool-id auto_biotite \
  --min-score 0.60

# Expected: Pass (score ≥ 0.60), could go to preview mode
```

### Test 3: Batch Validation

```bash
# Validate all, block any below threshold
python3 scripts/tool_quality_validator.py \
  --all-auto-discovered \
  --min-score 0.85 \
  --block-on-issues

# Expected: 14 failures (none meet threshold)
```

---

## Recommendations

### Immediate Actions (This Week)

1. **Integrate validator into auto-discovery pipeline**
   - Add validation step before database insert
   - Implement blocking logic
   - Create enhancement queue

2. **Set initial policy**: Block all tools < 0.70
   - Prevents severely deficient tools
   - Allows preview mode for 0.70-0.84 tools

3. **Start parameter extraction project**
   - Most critical gap (11/14 tools blocked)
   - High impact on quality scores
   - Relatively straightforward to implement

### Short-term (This Month)

4. **Build enhancement queue processor**
   - Automatically extract parameters from help text
   - Parse requirements from usage_guide
   - Re-validate after enhancement

5. **Create preview/beta mode in UI**
   - Mark tools with quality score 0.60-0.84
   - Show limitations to users
   - Provide usage guide for manual setup

### Medium-term (Next Quarter)

6. **Implement quality monitoring**
   - Daily quality reports
   - Track improvement trends
   - Alert on quality regressions

7. **Manual review workflow**
   - Queue for tools that can't be auto-enhanced
   - Assign to team members
   - Track time to production

---

## Success Metrics

### Target Goals (3 Months)

| Metric | Current | Target | How |
|--------|---------|--------|-----|
| % Workflow Ready | 0% (auto) | 80% | Parameter extraction |
| Avg Quality Score | 0.55 | 0.85 | Auto-enhancement |
| Blocking Issues | 11/14 (79%) | 0/N (0%) | Enhancement queue |
| Time to Production | N/A | < 7 days | Automation |
| Manual Review Queue | 0 | < 5 tools | Auto-enhance most |

### Monthly Milestones

**Month 1**:
- Quality gate integrated ✅
- Parameter extraction working
- 50% auto-discovered tools ready

**Month 2**:
- Requirements parsing working
- 80% tools ready
- Preview mode operational

**Month 3**:
- I/O enhancement working
- 90% tools ready
- Full automation

---

## Conclusion

The Quality Gate System ensures only production-ready tools with sufficient metadata enter the tool index. This protects users from incomplete tools while providing a clear path to enhancement.

### Current Status
- ✅ Validator implemented and tested
- ✅ Baseline quality report generated
- ❌ 0/14 auto-discovered tools ready for production

### Next Steps
1. Integrate validator into pipeline (1-2 days)
2. Build parameter extraction tool (1-2 weeks)
3. Enable quality gate for new tools (immediate)

**With this system, we ensure smooth workflow implementation and prevent the addition of unusable tools to the production index.**

---

**Document Version**: 1.0
**Last Updated**: 2025-11-17 11:43:00
**Validator Script**: `scripts/tool_quality_validator.py`
**Quality Report**: `quality_report_20251117_114226.json`
