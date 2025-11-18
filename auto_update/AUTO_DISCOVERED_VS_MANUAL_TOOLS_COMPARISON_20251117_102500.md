# Auto-Discovered vs Manual Tools - Field Quality Comparison

**Created**: 2025-11-17 10:25:00
**Database**: `/home/yzhang/biomate/backend/database/galaxy_ai_tools.db`

---

## Executive Summary

### 🔴 **The issue is ONLY with the newly auto-discovered tools**

**Manual/Existing Tools**: ✅ **Excellent** - 96% have proper parameters
**Auto-Discovered Tools**: ❌ **Insufficient** - Only 0-42% have meaningful data

---

## Database Statistics

| Category | Manual/Existing Tools | Auto-Discovered Tools |
|----------|----------------------|----------------------|
| **Total Count** | 9,212 tools | 14 tools |
| **Parameters Populated** | 8,903 (96%) ✅ | 8 (57%) ⚠️ |
| **Parameters Empty/Invalid** | 309 (3%) | 6-14 (43-100%) ❌ |

---

## Detailed Comparison

### Manual/Existing Tools: ✅ HIGH QUALITY

**Example: "abacas contig ordering"**

```json
{
  "parameters": [
    {
      "name": "reference_sequence",
      "type": "text",
      "label": "Reference sequence",
      "optional": false
    },
    {
      "name": "sequence_query_file",
      "type": "data",
      "label": "Sequence query file",
      "optional": false
    },
    {
      "name": "generate_a_multifasta_file_of_the_unused_contigs",
      "type": "data",
      "label": "Generate a multifasta file of the unused contigs",
      "optional": false
    }
  ]
}
```

**Quality**: ✅ Excellent
- Real parameter names (reference_sequence, sequence_query_file)
- Proper types (text, data)
- Clear labels
- Optional flags

**Source**: Parsed from Galaxy XML wrapper files

---

### Auto-Discovered Tools: ❌ POOR QUALITY

#### Category 1: Empty Parameters (43% of auto-discovered)

**Tools**:
- auto_nextflow
- auto_htslib
- auto_biopython
- auto_foldseek ⚠️
- auto_mmseqs2 ⚠️
- auto_graphein

**Parameters Field**:
```json
[]
```

**Impact**: Cannot generate workflow forms at all

---

#### Category 2: Dummy/Placeholder Parameters (57% of auto-discovered)

**Tools**:
- auto_dash
- auto_scanpy
- auto_galaxy
- auto_rush
- auto_biotite
- auto_omicverse
- auto_colabfold
- auto_star

**Example (auto_dash)**:
```json
{
  "parameters": [
    {
      "name": "help",
      "label": "Help",
      "type": "text",
      "help": "Parameter for help",
      "optional": false,
      "source": "auto_discovered"
    },
    {
      "name": "m",
      "label": "M",
      "type": "text",
      "help": "Parameter for m",
      "optional": false,
      "source": "auto_discovered"
    }
  ]
}
```

**Quality**: ❌ Useless
- Generic names ("help", "m")
- No meaningful labels or descriptions
- All marked as "text" type (should be boolean, integer, select, etc.)
- Duplicates (two "help" parameters)
- Marked with `"source": "auto_discovered"` - indicating automated placeholder

**Impact**:
- Cannot generate useful workflow forms
- No validation possible
- No meaningful defaults
- User has no idea what parameters do

---

## What Auto-Discovered Tools DO Have

### ✅ Good Information (Present and Useful)

1. **Basic Metadata**: ✅ Excellent
   - tool_id, name, version, description
   - GitHub URL, stars, language
   - Discovery date, quality score

2. **Docker Containers**: ✅ Good
   ```json
   "requirements": [
     {
       "name": "quay.io/biocontainers/foldseek:10.941cd33--h5021889_1",
       "type": "docker",
       "version": "latest"
     }
   ]
   ```

3. **Citations**: ✅ Excellent
   - DOIs, paper titles, authors, journals, years

4. **Usage Guide**: ✅ Rich but unstructured
   - Installation instructions (3,000+ characters)
   - CPU/GPU requirements (in text)
   - Example commands (in text)

5. **Basic I/O**: ⚠️ Minimal but present
   ```json
   "inputs": ["fa", "fasta"],
   "outputs": ["fasta", "txt"]
   ```

---

### ❌ Missing/Poor Information

1. **Tool Parameters**: ❌ Empty or dummy placeholders
   - 43% completely empty `[]`
   - 57% have meaningless placeholders

2. **Structured Resource Requirements**: ❌ Unstructured
   - CPU/GPU info exists in text, not structured JSON
   - Memory requirements not captured
   - System prerequisites in text only

3. **Detailed Input/Output Specs**: ⚠️ Too minimal
   - Only file extensions, no descriptions
   - No parameter mapping
   - No optional vs required distinction

4. **Scientific Context**: ❌ Empty
   ```json
   "scientific_context": {
     "use_cases": [],
     "typical_inputs": [],
     "typical_outputs": [],
     "workflow_position": "standalone"
   }
   ```

5. **Installation Methods**: ⚠️ Unstructured
   - Exists in `usage_guide` as markdown text
   - Not in structured JSON format

---

## Root Cause Analysis

### Why Manual Tools Have Good Data

**Source**: Galaxy Tool Shed XML wrappers
- Hand-written XML files with `<param>` tags
- Example:
  ```xml
  <param name="reference_sequence" type="text"
         label="Reference sequence" optional="false"/>
  ```
- Parsed by Galaxy XML parser
- Structured data from structured source ✅

### Why Auto-Discovered Tools Have Poor Data

**Source**: GitHub README files
- Unstructured markdown text
- Parameter information scattered in:
  - Help text output (`tool --help`)
  - README examples
  - Man pages
  - Documentation websites

**Current Auto-Discovery Process**:
1. ✅ Fetches README markdown
2. ✅ Extracts text into `usage_guide`
3. ❌ Does NOT parse command-line parameters
4. ❌ Creates dummy placeholders instead
5. ❌ Does NOT structure CPU/GPU requirements

**What's Needed**: Parameter extraction module (see recommendations below)

---

## Impact on Workflow Configuration

### Manual Tools: ✅ Fully Functional

**Can Do**:
- ✅ Auto-generate workflow forms with proper inputs
- ✅ Validate user inputs against types/constraints
- ✅ Provide parameter documentation
- ✅ Set reasonable defaults
- ✅ Show/hide optional parameters
- ✅ Handle conditional parameters

**Example Workflow Form** (from parameters):
```
┌─────────────────────────────────────────┐
│ Reference Sequence: [_____________]     │
│ Sequence Query File: [Choose File]     │
│ Generate Unused Contigs: [Choose File] │
│                                         │
│ [Submit] [Cancel]                       │
└─────────────────────────────────────────┘
```

---

### Auto-Discovered Tools: ❌ Cannot Configure

**Cannot Do**:
- ❌ Generate meaningful workflow forms
- ❌ Know what parameters exist
- ❌ Validate inputs
- ❌ Provide help text
- ❌ Set defaults
- ❌ Schedule on appropriate hardware (no structured GPU/CPU info)

**Current "Form"** (from dummy parameters):
```
┌─────────────────────────────────────────┐
│ Help: [_____________]                   │
│ M: [_____________]                      │
│ Help: [_____________]  (duplicate???)   │
│                                         │
│ ⚠️  User has no idea what these mean   │
│ [Submit] [Cancel]                       │
└─────────────────────────────────────────┘
```

---

## Specific Tool Status

### Auto-Discovered Tools - Detailed Breakdown

| Tool ID | Name | Parameters | Requirements | Usage Guide | Status |
|---------|------|------------|--------------|-------------|---------|
| auto_foldseek | foldseek | ❌ Empty [] | ⚠️ Docker only | ✅ 3,282 chars | 🔴 Needs params |
| auto_mmseqs2 | MMseqs2 | ❌ Empty [] | ⚠️ Docker only | ✅ 4,050 chars | 🔴 Needs params |
| auto_nextflow | nextflow | ❌ Empty [] | ⚠️ Docker only | ✅ 2,000+ chars | 🔴 Needs params |
| auto_htslib | htslib | ❌ Empty [] | ⚠️ Docker only | ✅ 1,000+ chars | 🔴 Needs params |
| auto_biopython | BioPython | ❌ Empty [] | ⚠️ Docker only | ✅ 1,000+ chars | 🔴 Needs params |
| auto_graphein | graphein | ❌ Empty [] | ⚠️ Docker only | ✅ 1,774 chars | 🔴 Needs params |
| auto_dash | dash | ⚠️ Dummy | ⚠️ Docker only | ✅ Rich | 🟡 Needs real params |
| auto_scanpy | scanpy | ⚠️ Dummy | ⚠️ Docker only | ✅ Rich | 🟡 Needs real params |
| auto_rush | rush | ⚠️ Dummy | ⚠️ Docker only | ✅ 17,576 chars | 🟡 Needs real params |
| auto_colabfold | ColabFold | ⚠️ Dummy | ⚠️ Docker only | ✅ Rich | 🟡 Needs real params |

**Legend**:
- 🔴 = Completely empty, blocking workflow config
- 🟡 = Has placeholders but useless
- ✅ = Good data present

---

## Recommendations

### Priority 1: Parameter Extraction (CRITICAL)

**Create**: `scripts/parameter_extractor.py`

**Method**:
1. Run tool with `--help` flag inside Docker container
2. Parse help output with regex/LLM
3. Extract:
   - Parameter names (--gpu, --threads, -s)
   - Types (boolean, integer, string, select)
   - Descriptions
   - Defaults
   - Required vs optional
4. Generate structured JSON
5. Update database

**Example**:
```bash
# Run in Docker
docker run quay.io/biocontainers/foldseek:10.941cd33--h5021889_1 foldseek --help

# Output contains:
#   --gpu <int>         Enable GPU acceleration (default: 0)
#   --threads <int>     Number of threads (default: 1)
#   -s <int>            Sensitivity (default: 9.5)

# Parse to:
{
  "parameters": [
    {
      "name": "gpu",
      "type": "boolean",
      "label": "Enable GPU Acceleration",
      "flag": "--gpu",
      "default": false,
      "optional": true
    },
    {
      "name": "threads",
      "type": "integer",
      "label": "Number of Threads",
      "flag": "--threads",
      "default": 1,
      "min": 1,
      "max": 64,
      "optional": true
    }
  ]
}
```

**Estimated Effort**: 1-2 weeks
- Week 1: Build parser, test on 3-5 tools
- Week 2: Run on all 14 tools, validate, update DB

---

### Priority 2: Resource Requirements Parsing

**Create**: `scripts/resource_requirements_parser.py`

**Method**:
1. Parse `usage_guide` text with regex + LLM
2. Extract:
   - CPU: instruction sets (AVX2, SSE4.1)
   - GPU: vendor, generation, driver versions
   - Memory: minimum/recommended GB
   - System: library versions (glibc)
3. Structure into JSON
4. Add to `requirements` field or new `compute_requirements` field

**Estimated Effort**: 1 week

---

### Priority 3: Input/Output Enhancement

**Create**: `scripts/io_enhancer.py`

**Method**:
1. Parse `examples` field for command patterns
2. Map inputs to command positions
3. Infer required vs optional
4. Add descriptions from usage guide
5. Generate enhanced I/O specs

**Estimated Effort**: 3-5 days

---

## Conclusion

### ✅ **Manual Tools**: Ready for Production
- 9,212 tools with excellent structured data
- Full workflow configuration possible
- 96% parameter coverage

### ❌ **Auto-Discovered Tools**: Not Ready for Production
- 14 tools with insufficient structured data
- Cannot generate workflow forms
- 0-57% meaningful parameter coverage (rest are placeholders)

### 🔧 **Solution**: Enhance Auto-Discovery Pipeline
- Add parameter extraction module (1-2 weeks)
- Add resource requirements parsing (1 week)
- Add input/output enhancement (3-5 days)

**Total Effort**: 3-4 weeks to bring auto-discovered tools to manual quality

---

## Immediate Action Items

1. **Stop Using Dummy Parameters**
   - Remove placeholder generation code
   - Leave empty [] if parameters can't be extracted
   - Prevents confusion

2. **Prioritize Parameter Extraction**
   - Start with high-value tools (foldseek, mmseqs2)
   - Test extraction on 3 tools first
   - Validate before bulk processing

3. **Document Limitations**
   - Mark auto-discovered tools as "Preview" or "Beta"
   - Warn users about limited workflow configuration
   - Show manual parameter input form instead

4. **Leverage Existing Data**
   - Use Docker containers for now (they work)
   - Display `usage_guide` to users for manual reference
   - Show `examples` as templates

---

**Document Version**: 1.0
**Next Update**: After parameter extraction implementation
