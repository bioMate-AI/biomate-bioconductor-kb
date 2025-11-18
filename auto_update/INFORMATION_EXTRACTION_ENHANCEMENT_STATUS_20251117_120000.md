# Information Extraction Enhancement - Implementation Status

**Created**: 2025-11-17 12:00:00
**Goal**: Improve QA pass rate from 0% to 80%+ for auto-discovered tools

---

## Current Quality Status

### Baseline (Before Enhancement)

```
Total auto-discovered tools: 14
Workflow ready (≥0.85): 0 (0%)
Has blocking issues: 11 (79%)
Average score: 0.55 (Grade: D)
```

### Quality Breakdown by Category

| Category | Weight | Avg Score | Status | Impact |
|----------|--------|-----------|--------|--------|
| **Parameters** | 35% | 0.14 | 🔴 Critical | 11 tools completely blocked |
| **Requirements** | 20% | 0.80 | 🟡 Partial | Have Docker, missing CPU/GPU structure |
| **Inputs/Outputs** | 15% | 0.60 | 🟡 Minimal | Only extensions, need descriptions |
| **Basic Metadata** | 15% | 1.00 | ✅ Good | Complete |
| **Usage Docs** | 10% | 0.90 | ✅ Good | Rich text available |
| **Sci Context** | 5% | 0.50 | 🟡 Empty | Could extract from README |

---

## Enhancement Strategy

### Priority 1: Parameter Extraction (35% impact)

**Status**: 🟡 Tool created, needs refinement

**Approach Options**:

1. **Docker Help Parsing** (Created - has issues)
   - ✅ Runs `docker run tool --help`
   - ✅ Parses with regex + LLM
   - ❌ Docker timeout issues
   - ❌ Entry points vary by container

2. **Usage Guide Parsing** (RECOMMENDED)
   - ✅ Already in database
   - ✅ Contains example commands
   - ✅ Shows actual parameter usage
   - Example from foldseek:
     ```
     foldseek easy-search input output --gpu 1 --threads 4
     ```
   - Can extract: `--gpu`, `--threads` with context

3. **README Documentation Parsing**
   - ✅ Available in `usage_guide` field
   - ✅ Often has parameter tables
   - Use Claude to extract structured data

**Recommended Implementation**:
- Parse `usage_guide` + `examples` fields with Claude
- Extract parameters from command examples
- Match with descriptions in README
- Higher success rate than Docker approach

**Expected Impact**:
- Current: 0% tools have real parameters
- Target: 80% tools have 5+ parameters
- Quality score improvement: +0.20 to +0.30

---

### Priority 2: Resource Requirements Parsing (20% impact)

**Status**: 🔴 Not started

**Data Available** (in `usage_guide`):
```markdown
# From foldseek usage_guide:
# Linux AVX2 build (check using: cat /proc/cpuinfo | grep avx2)
# Linux AVX2 & GPU build (req. glibc >= 2.17 and nvidia driver >=525.60.13)
# GPU: NVIDIA Ampere generation or newer for full speed
# 4x faster on 4090 GPU vs 64-core CPU
```

**Extraction Strategy**:
1. Parse `usage_guide` with regex patterns:
   - CPU: `/AVX2|SSE4.1|SSE2|ARM64/`
   - GPU: `/NVIDIA|CUDA|Ampere|Turing|RTX \d{4}/`
   - Driver: `/driver.*>=\s*[\d.]+/`
   - Memory: `/\d+\s*GB.*(?:RAM|memory)/i`
   - glibc: `/glibc.*>=\s*[\d.]+/`

2. Structure into JSON:
   ```json
   {
     "cpu": {
       "instruction_set": ["AVX2"],
       "architectures": ["x86_64"]
     },
     "gpu": {
       "optional": true,
       "provider": "NVIDIA",
       "generations": ["Ampere", "Turing"],
       "driver_min": "525.60.13",
       "performance_boost": "4x vs 64-core CPU"
     },
     "memory": {
       "minimum_gb": 4,
       "recommended_gb": 8
     },
     "system": {
       "glibc_min": "2.17"
     }
   }
   ```

**Expected Impact**:
- Current: 0.60 score (Docker only)
- Target: 1.00 score (full specs)
- Quality score improvement: +0.08

---

### Priority 3: Input/Output Enhancement (15% impact)

**Status**: 🔴 Not started

**Current State**:
```json
{
  "inputs": ["fa", "fasta"],
  "outputs": ["fasta", "txt"]
}
```

**Target State**:
```json
{
  "inputs": [
    {
      "name": "query_structure",
      "formats": ["pdb", "cif", "mmcif"],
      "description": "Protein structure in PDB or mmCIF format",
      "required": true,
      "multiple": true
    }
  ],
  "outputs": [
    {
      "name": "alignments",
      "format": "m8",
      "description": "Tab-separated alignment results",
      "mime_type": "text/tab-separated-values"
    }
  ]
}
```

**Extraction Strategy**:
1. Parse `examples` field for file patterns
2. Extract from `usage_guide` documentation
3. Use Claude to infer from tool description

**Expected Impact**:
- Current: 0.60 score
- Target: 0.90 score
- Quality score improvement: +0.045

---

### Priority 4: Scientific Context (5% impact)

**Status**: 🔴 Not started

**Extraction Strategy**:
- Parse README for use cases
- Extract from `description` and `scientific_context`
- Use Claude to generate typical workflows

**Expected Impact**:
- Current: 0.50 score
- Target: 0.80 score
- Quality score improvement: +0.015

---

## Revised Implementation Plan

### Phase 1: Parse Existing Text Fields (Week 1)

**No Docker needed - everything in database!**

#### 1A. Parameter Extraction from Usage Guide (Days 1-3)

Create `parse_parameters_from_guide.py`:

```python
def extract_parameters_from_usage_guide(usage_guide, examples):
    """
    Parse usage_guide and examples to extract parameters.

    Strategy:
    1. Find all --flag patterns in examples
    2. Match with descriptions in usage_guide
    3. Use Claude API to structure
    """

    # Collect all flags from examples
    flags = re.findall(r'--[\w-]+', examples)

    # Build context for Claude
    prompt = f"""
    Extract parameters from this tool documentation.

    Example commands:
    {examples}

    Documentation:
    {usage_guide[:2000]}

    For each --flag found, provide:
    - name, type, label, help, default, required

    Return JSON array.
    """

    # Call Claude API
    response = client.messages.create(...)
    return parse_response(response)
```

**Test on**: foldseek, mmseqs2 (have rich examples)

#### 1B. Resource Requirements Parser (Days 4-5)

Create `parse_resource_requirements.py`:

```python
def extract_resource_requirements(usage_guide):
    """Extract CPU/GPU/memory from usage_guide text."""

    requirements = {
        "cpu": extract_cpu_info(usage_guide),
        "gpu": extract_gpu_info(usage_guide),
        "memory": extract_memory_info(usage_guide),
        "system": extract_system_info(usage_guide)
    }

    return requirements
```

**Test on**: All 14 tools (all have usage_guide)

#### 1C. Integration (Days 6-7)

- Run parsers on all 14 tools
- Update database
- Re-validate with quality validator
- Measure improvement

### Phase 2: Refinement (Week 2)

- Handle edge cases
- Improve extraction accuracy
- Add manual fallbacks
- Comprehensive testing

### Phase 3: Production Integration (Week 3)

- Integrate into auto-discovery pipeline
- Add to quality gate
- Enable for new tools
- Monitor quality trends

---

## Expected Quality Improvements

### Conservative Estimates

| Tool | Current | After Params | After Reqs | After I/O | Final |
|------|---------|--------------|------------|-----------|-------|
| auto_foldseek | 0.57 (D) | 0.77 (B-) | 0.81 (B+) | 0.85 (A-) | ✅ Ready |
| auto_mmseqs2 | 0.56 (D) | 0.76 (B-) | 0.80 (B+) | 0.84 (B+) | ⚠️ Close |
| auto_rush | 0.82 (B+) | 0.90 (A) | 0.94 (A) | 0.96 (A+) | ✅ Ready |
| auto_biotite | 0.84 (B+) | 0.92 (A) | 0.96 (A+) | 0.98 (A+) | ✅ Ready |
| auto_colabfold | 0.81 (B+) | 0.89 (A-) | 0.93 (A) | 0.95 (A+) | ✅ Ready |

**Summary**:
- Current: 0/14 ready (0%)
- After parameters: 3/14 ready (21%)
- After requirements: 8/14 ready (57%)
- After I/O: 11/14 ready (79%)

**Target**: 80% ready ✅ Achievable

---

## Alternative Approach: README-First Extraction

Since usage_guide already contains most information:

### Unified Extractor with Claude

Create `unified_metadata_extractor.py`:

```python
def extract_all_metadata(tool):
    """Single Claude API call to extract all missing metadata."""

    prompt = f"""
    Extract structured metadata from this bioinformatics tool documentation.

    Tool: {tool['name']}
    Description: {tool['description']}

    Usage Guide:
    {tool['usage_guide'][:4000]}

    Examples:
    {tool['examples']}

    Extract and return JSON with:

    1. parameters: [
         {{name, type, flag, label, help, default, required}}
       ]

    2. compute_requirements: {{
         cpu: {{instruction_set, cores, architectures}},
         gpu: {{optional, provider, generations, driver_min}},
         memory: {{minimum_gb, recommended_gb}},
         system: {{glibc_min, other_prereqs}}
       }}

    3. inputs: [
         {{name, formats, description, required, multiple}}
       ]

    4. outputs: [
         {{name, format, description, mime_type}}
       ]

    5. use_cases: [
         {{name, description, typical_scale}}
       ]

    Return only valid JSON.
    """

    response = client.messages.create(
        model="claude-3-5-sonnet-20241022",  # More capable for complex extraction
        max_tokens=8000,
        messages=[{"role": "user", "content": prompt}]
    )

    return json.loads(response.content[0].text)
```

**Advantages**:
- Single API call per tool
- No Docker complications
- Leverages Claude's understanding
- Handles all categories at once

**Disadvantages**:
- Costs more per tool (~$0.02-0.05)
- Dependent on API availability
- Need good prompt engineering

**Recommendation**: Start with this approach for fastest results

---

## Cost Analysis

### Claude API Costs

**Model**: claude-3-5-haiku-20241022
- Input: $1 per million tokens
- Output: $5 per million tokens

**Per Tool**:
- Input: ~4,000 tokens (usage_guide + prompt)
- Output: ~1,000 tokens (structured JSON)
- Cost: ~$0.009 per tool

**For 14 tools**: ~$0.13 total

**Model**: claude-3-5-sonnet-20241022 (more accurate)
- Input: $3 per million tokens
- Output: $15 per million tokens
- Cost per tool: ~$0.027
- For 14 tools: ~$0.38 total

**Recommendation**: Use Sonnet for better accuracy (<$1 total cost)

---

## Testing Plan

### Test Suite

1. **Unit Tests**:
   - Test parameter parsing on known examples
   - Test regex patterns for requirements
   - Test I/O inference

2. **Integration Tests**:
   - Run on 3 sample tools (foldseek, rush, colabfold)
   - Validate extracted vs manual review
   - Check database updates

3. **Quality Gate Tests**:
   - Re-run quality validator
   - Verify score improvements
   - Check workflow readiness

4. **End-to-End Test**:
   - Full pipeline run with enhancement
   - Measure before/after quality
   - Validate all 14 tools

---

## Implementation Decision

### Recommended Path: Unified Claude Extractor

**Rationale**:
1. Fastest to implement (1-2 days)
2. Highest accuracy (Claude understands context)
3. No Docker complications
4. Low cost (<$1 for all tools)
5. Single code path to maintain

**Next Steps**:
1. Create `unified_metadata_extractor.py` (Day 1)
2. Test on foldseek, mmseqs2, rush (Day 1)
3. Refine prompts based on results (Day 2)
4. Run on all 14 tools (Day 2)
5. Update database and re-validate (Day 2)
6. Measure quality improvement (Day 2)
7. Integrate into pipeline (Day 3)

**Expected Outcome**:
- 11/14 tools (79%) workflow-ready
- Average score: 0.55 → 0.87
- Grade distribution: D/F → A-/B+
- Time to implement: 3 days
- Cost: <$1 in API fees

---

## Files Created

1. ✅ `scripts/tool_quality_validator.py` - Quality gate system
2. ✅ `scripts/parameter_extractor.py` - Docker-based extraction (has issues)
3. 🔴 `scripts/unified_metadata_extractor.py` - NEXT (recommended approach)
4. 🔴 `scripts/resource_requirements_parser.py` - Can be part of unified
5. 🔴 `scripts/io_spec_enhancer.py` - Can be part of unified

---

## Conclusion

**Current Status**:
- Quality gate system: ✅ Complete
- Enhancement tools: 🟡 In progress
- Production integration: 🔴 Pending

**Recommended Next Step**:
Create unified metadata extractor using Claude API to parse existing `usage_guide` and `examples` fields. This is faster, more accurate, and cheaper than Docker-based approaches.

**Timeline**:
- Day 1-2: Build unified extractor
- Day 3: Test and refine
- Week 2: Integrate into pipeline
- Week 3: Production rollout

**Expected Result**:
- QA pass rate: 0% → 79% (11/14 tools)
- Average quality: 0.55 (D) → 0.87 (B+)
- Workflow-ready tools: 0 → 11

---

**Document Version**: 1.0
**Next Update**: After unified extractor implementation
