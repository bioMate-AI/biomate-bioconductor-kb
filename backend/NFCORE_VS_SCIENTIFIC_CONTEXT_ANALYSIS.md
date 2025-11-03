# nfcore_metadata vs scientific_context: Relationship Analysis

**Date**: October 31, 2025
**Question**: Why have two separate fields? Are they duplicative? Should they merge?

---

## TL;DR Answer

**NO, DO NOT MERGE.** They serve completely different purposes:

| Aspect | `nfcore_metadata` | `scientific_context` |
|--------|------------------|---------------------|
| **Source** | nf-core pipeline GitHub repos | Galaxy tool documentation (rawText, help_text) |
| **Coverage** | 1,841 tools (20%) - only tools used in nf-core | 9,212 tools (100%) - all Galaxy tools |
| **Content** | Workflow-level metadata (keywords, DOIs, I/O formats) | Scientific decision-making knowledge (when/why to use) |
| **Format** | Structured metadata from nf-core modules | LLM-extracted guidance with evidence URLs |
| **Use Case** | "What workflows use this tool?" | "When should I choose this tool?" |
| **Update Frequency** | Static snapshot from nf-core repos | Can be updated from tool documentation |

**Conclusion**: They are COMPLEMENTARY, not duplicative. Keep both.

---

## 1. Data Coverage Difference

### 1.1 Why Different Percentages?

```
nfcore_metadata:     1,841 tools (20%)
scientific_context:  9,212 tools (100%, in progress)
```

**Reason**: Different data sources

- **nfcore_metadata**: Only extracted for tools that exist in nf-core pipeline repositories
  - Source: https://github.com/nf-core/modules
  - Extraction: Crawled nf-core GitHub repos for module definitions
  - Limitation: Only covers tools adopted by nf-core community

- **scientific_context**: Extracted for ALL tools in Galaxy ToolShed
  - Source: Galaxy tool documentation (rawText, help_text)
  - Extraction: LLM-based extraction from tool docs
  - Coverage: Every tool with documentation

**Example**: A niche proteomics tool may be in Galaxy but not in nf-core pipelines.

---

## 2. Content Comparison

### 2.1 Side-by-Side: ABACAS Tool

#### nfcore_metadata Structure

```json
{
  "modules": [{
    "name": "abacas",
    "description": "Contiguate draft genome assembly",
    "keywords": ["genome", "assembly", "contiguate"],
    "tools": {
      "abacas": {
        "description": "ABACAS is intended to rapidly contiguate...",
        "homepage": "http://abacas.sourceforge.net/documentation.html",
        "documentation": "http://abacas.sourceforge.net/documentation.html",
        "doi": "10.1093/bioinformatics/btp347",
        "licence": ["GPL v2-or-later"],
        "identifier": "biotools:abacas"
      }
    },
    "edam_operations": ["http://edamontology.org/format_1929"]
  }],
  "subworkflows": [],
  "workflows": [],
  "related_tools": [],
  "dois": ["10.1093/bioinformatics/btp347"],
  "edam_operations": ["http://edamontology.org/format_1929"],
  "typical_inputs": ["*.{fasta,fa}"],
  "typical_outputs": []
}
```

**Content Type**: Structured metadata
- Tool identifiers (homepage, DOI, biotools ID)
- Workflow context (related tools, typical I/O formats)
- Ontology mappings (EDAM operations)
- Keywords for discovery

#### scientific_context Structure

```json
{
  "omics_applicability": {
    "primary_omics": ["genomics"],
    "suitable_designs": [
      "de novo genome assembly with reference-guided scaffolding",
      "bacterial genome finishing",
      "contig ordering and orientation against reference sequences"
    ],
    "not_suitable": [
      "Transcriptomics analysis",
      "Metagenomic assembly without clear reference"
    ],
    "data_requirements": {
      "min_samples": 1,
      "min_replicates": null,
      "notes": "Requires a reference sequence and query multifasta..."
    },
    "evidence": [{
      "claim": "ABACAS is intended to rapidly contiguate...",
      "source": "tool documentation",
      "url": "extracted from rawText",
      "quote": "ABACAS is intended to rapidly contiguate..."
    }]
  },
  "tool_selection": {
    "best_for": [
      "Ordering and orienting de novo assembled contigs",
      "Bacterial genome finishing and gap closure planning"
    ],
    "not_recommended_for": [
      "Reference-free de novo assembly",
      "Eukaryotic genome assembly (no evidence of suitability)"
    ],
    "alternatives": [...]
  },
  "scientific_guidance": {
    "common_pitfalls": [{
      "mistake": "Using ABACAS without a suitable reference",
      "consequence": "Poor contig ordering; many unaligned contigs",
      "recommendation": "Select closely related reference sequence"
    }],
    "key_parameters": [{
      "parameter": "reference_sequence",
      "scientific_meaning": "Reference genome for contig ordering",
      "typical_values": "Complete genome in FASTA format",
      "context_guidance": {
        "bacterial_genome": "Use reference from same/related species"
      }
    }]
  }
}
```

**Content Type**: Decision-making knowledge
- When to use vs not use this tool
- Data requirements and experimental design constraints
- Common mistakes and how to avoid them
- Scientific meaning of parameters
- Tool alternatives with comparison criteria

### 2.2 What Each Field Tells You

#### nfcore_metadata Answers:
- "What is this tool's homepage and documentation?"
- "What DOI should I cite?"
- "What file formats does this tool typically work with?"
- "What EDAM operations does it perform?"
- "Is this tool used in nf-core workflows?"
- "What related tools are often used together?"

#### scientific_context Answers:
- "When should I choose this tool vs alternatives?"
- "What are the minimum data requirements?"
- "What experimental designs is this suitable for?"
- "What are common mistakes users make?"
- "What do the key parameters scientifically mean?"
- "How should I interpret the outputs?"

---

## 3. Format Comparison

### 3.1 Is nfcore_metadata Unstructured Text?

**NO** - It's highly structured JSON with:
- Module definitions
- Tool metadata (homepage, DOI, licence)
- Workflow relationships
- Ontology mappings (EDAM)
- I/O format specifications

### 3.2 Is scientific_context Unstructured Text?

**NO** - It's structured JSON with:
- Evidence-backed claims (with URLs)
- Categorical guidance (omics_applicability, tool_selection, etc.)
- Explicit confidence levels
- "needs_verification" markers for incomplete evidence

**Both are structured JSON**, but with different schemas serving different purposes.

---

## 4. Use Cases: How They Work Together

### 4.1 Scenario 1: Tool Discovery

**User query**: "I need to scaffold bacterial genome contigs"

#### Step 1: nfcore_metadata helps FIND relevant tools
```python
# Search by keywords
tools = search_by_keywords("assembly", "contiguate", "genome")
# Returns: ABACAS (keywords match)
```

#### Step 2: scientific_context helps CHOOSE the right tool
```python
# Check applicability
suitable = check_applicability(
    omics="genomics",
    design="reference-guided scaffolding",
    data="bacterial contigs"
)
# scientific_context confirms: "suitable_designs includes bacterial genome finishing"
```

**Result**: nfcore_metadata helps discovery, scientific_context validates suitability.

### 4.2 Scenario 2: Workflow Generation

**User query**: "Create a workflow for de novo bacterial genome assembly"

#### Step 1: Use nfcore_metadata to understand workflow patterns
```python
# Check how nf-core uses this tool
workflow_context = tool['nfcore_metadata']
# Shows: typical_inputs ["*.{fasta,fa}"], related_tools, workflows
```

#### Step 2: Use scientific_context to make informed decisions
```python
# Check data requirements
if user_data.coverage < 20:
    warning = tool['scientific_context']['omics_applicability']['data_requirements']
    # "Requires 30x-60x coverage recommended"

# Check common pitfalls
pitfalls = tool['scientific_context']['scientific_guidance']['common_pitfalls']
# "Using ABACAS without suitable reference → poor ordering"
```

**Result**: nfcore_metadata shows HOW it's used, scientific_context explains WHY and WHEN.

### 4.3 Scenario 3: Parameter Configuration

**User query**: "What should I set for the reference_sequence parameter?"

#### nfcore_metadata provides:
- Parameter type from module definition
- Default values if specified
- I/O format expectations

#### scientific_context provides:
```json
{
  "parameter": "reference_sequence",
  "scientific_meaning": "Reference genome for contig ordering",
  "typical_values": "Complete genome in FASTA format",
  "context_guidance": {
    "bacterial_genome": "Use reference from same/related species",
    "draft_assembly": "Use best available, preferably same genus"
  },
  "evidence_url": "needs_verification"
}
```

**Result**: nfcore_metadata gives technical specs, scientific_context gives biological guidance.

---

## 5. Complementary Value Proposition

### 5.1 What nfcore_metadata Provides That scientific_context Doesn't

1. **Workflow integration patterns**
   - Which tools are typically used together in nf-core
   - Standard I/O formats from production pipelines
   - Related tools and subworkflows

2. **Community validation**
   - Tools vetted by nf-core community
   - Standard ontology mappings (EDAM)
   - Official identifiers (biotools, DOIs)

3. **Provenance**
   - Exact nf-core module version
   - Licence information
   - Official documentation URLs

### 5.2 What scientific_context Provides That nfcore_metadata Doesn't

1. **Decision-making criteria**
   - When to use vs NOT use this tool
   - Experimental design constraints
   - Data quality requirements

2. **Practical guidance**
   - Common mistakes and how to avoid them
   - Parameter interpretation in biological context
   - Output interpretation guidance

3. **Tool comparison**
   - Alternatives with evidence-based comparison
   - When to prefer this tool vs alternatives
   - Benchmark references (when available)

4. **Evidence tracking**
   - URLs supporting each claim
   - Confidence levels
   - "needs_verification" for future curation

---

## 6. Should They Merge?

### 6.1 Arguments FOR Merging

1. Both are JSON metadata
2. Some overlapping information (descriptions, DOIs)
3. Could reduce database storage

### 6.2 Arguments AGAINST Merging (STRONGER)

1. **Different data sources**
   - nfcore_metadata: nf-core GitHub repos (static snapshot)
   - scientific_context: Galaxy tool docs (updatable)

2. **Different coverage**
   - nfcore_metadata: 20% of tools (nf-core-specific)
   - scientific_context: 100% of tools (all Galaxy tools)

3. **Different update cycles**
   - nfcore_metadata: Update when re-scraping nf-core repos
   - scientific_context: Update when tool documentation changes

4. **Different schemas**
   - nfcore_metadata: Workflow-centric (modules, I/O, workflows)
   - scientific_context: Decision-centric (applicability, guidance, alternatives)

5. **Different use cases**
   - nfcore_metadata: "How is this used in production workflows?"
   - scientific_context: "Should I use this for my specific experiment?"

6. **Provenance tracking**
   - Keeping separate allows tracking which claims come from which source
   - Important for ACE feedback loop (which knowledge source was most useful?)

### 6.3 Recommendation: KEEP SEPARATE

**Rationale**:
- They serve different questions at different stages of workflow generation
- Different update schedules and data sources
- 80% of tools will have ONLY scientific_context (not in nf-core)
- ACE system needs to track knowledge source effectiveness

**Better approach**: Create a UNIFIED API that combines both:

```python
def get_tool_knowledge(tool_name):
    """Get comprehensive tool knowledge from all sources."""
    return {
        "technical_metadata": load_field(tool_name, "help_text"),
        "workflow_patterns": load_field(tool_name, "nfcore_metadata"),
        "scientific_guidance": load_field(tool_name, "scientific_context"),
        "community_usage": load_field(tool_name, "tool_usage_patterns")
    }
```

---

## 7. Integration Strategy for Workflow Generation

### 7.1 Prompt Construction Example

```python
def build_tool_selection_prompt(user_query, tool):
    """Build comprehensive prompt using both metadata sources."""

    # Extract all available knowledge
    nfcore = json.loads(tool.get('nfcore_metadata') or '{}')
    sci_ctx = json.loads(tool.get('scientific_context') or '{}')
    help_txt = json.loads(tool.get('help_text') or '{}')

    prompt = f"""
Tool: {tool['name']}

## Technical Overview
{help_txt.get('what_it_does', 'N/A')}

## Workflow Context (from nf-core)
"""
    if nfcore.get('modules'):
        module = nfcore['modules'][0]
        prompt += f"""
- Used in nf-core pipelines: {module.get('name')}
- Keywords: {', '.join(module.get('keywords', []))}
- Typical inputs: {nfcore.get('typical_inputs', [])}
- Typical outputs: {nfcore.get('typical_outputs', [])}
- Documentation: {module.get('tools', {}).get(tool['name'], {}).get('homepage', 'N/A')}
"""

    prompt += f"""

## Scientific Guidance
"""
    if sci_ctx.get('omics_applicability'):
        prompt += f"""
- Primary omics: {sci_ctx['omics_applicability'].get('primary_omics', [])}
- Suitable for: {sci_ctx['omics_applicability'].get('suitable_designs', [])}
- NOT suitable for: {sci_ctx['omics_applicability'].get('not_suitable', [])}
- Data requirements: {sci_ctx['omics_applicability'].get('data_requirements', {})}
"""

    if sci_ctx.get('tool_selection'):
        prompt += f"""
- Best for: {sci_ctx['tool_selection'].get('best_for', [])}
- Alternatives: {[alt['tool'] for alt in sci_ctx['tool_selection'].get('alternatives', [])]}
"""

    if sci_ctx.get('scientific_guidance'):
        pitfalls = sci_ctx['scientific_guidance'].get('common_pitfalls', [])
        if pitfalls:
            prompt += f"""
- Common pitfalls to avoid:
"""
            for pitfall in pitfalls[:2]:
                prompt += f"  - {pitfall.get('mistake')}: {pitfall.get('recommendation')}\n"

    return prompt
```

### 7.2 Usage in Tool Selection

```python
def select_best_tool(user_requirements, candidate_tools):
    """Select best tool using both nfcore and scientific context."""

    scored_tools = []

    for tool in candidate_tools:
        score = 0

        # Score from nfcore_metadata (workflow patterns)
        nfcore = json.loads(tool.get('nfcore_metadata') or '{}')
        if nfcore.get('modules'):
            # Boost score if used in production workflows
            score += 10

        # Score from scientific_context (applicability)
        sci_ctx = json.loads(tool.get('scientific_context') or '{}')

        # Check omics match
        if user_requirements.omics in sci_ctx.get('omics_applicability', {}).get('primary_omics', []):
            score += 20

        # Check experimental design match
        user_design = user_requirements.design
        suitable = sci_ctx.get('omics_applicability', {}).get('suitable_designs', [])
        if any(user_design.lower() in s.lower() for s in suitable):
            score += 30

        # Check NOT suitable
        not_suitable = sci_ctx.get('omics_applicability', {}).get('not_suitable', [])
        if any(user_design.lower() in ns.lower() for ns in not_suitable):
            score -= 50  # Strong penalty for known unsuitable scenarios

        # Check confidence level (prefer high confidence tools)
        confidence = sci_ctx.get('information_sources', {}).get('confidence', 'none')
        if confidence == 'high':
            score += 15
        elif confidence == 'medium':
            score += 5

        scored_tools.append((tool, score))

    # Sort by score
    scored_tools.sort(key=lambda x: x[1], reverse=True)

    return scored_tools[0][0]  # Return top-scored tool
```

---

## 8. Summary Table

| Aspect | nfcore_metadata | scientific_context |
|--------|----------------|-------------------|
| **Primary Question** | "How is this used in workflows?" | "Should I use this for my experiment?" |
| **Data Source** | nf-core GitHub repos | Galaxy tool documentation |
| **Coverage** | 1,841 tools (20%) | 9,212 tools (100%) |
| **Content Focus** | Workflow patterns, I/O formats, identifiers | Decision criteria, pitfalls, alternatives |
| **Update Mechanism** | Re-scrape nf-core repos | Re-extract from tool docs |
| **Structure** | modules, workflows, I/O, identifiers | applicability, guidance, evidence |
| **Evidence** | Production workflow usage | URLs from documentation + needs_verification |
| **Use in Tool Selection** | Initial filtering, format validation | Final decision, parameter guidance |
| **Use in Workflow Gen** | Standard patterns, related tools | Scientific validation, error prevention |

---

## 9. Conclusion

**DO NOT MERGE**. The two fields are:

1. **Complementary**: Answer different questions at different stages
2. **Non-overlapping coverage**: 80% of tools have ONLY scientific_context
3. **Different provenance**: Tracking knowledge source is critical for ACE
4. **Different lifecycles**: Independent update schedules

**Recommended Architecture**:
```
Database Layer:
├─ nfcore_metadata (field 29) - Workflow patterns from nf-core
├─ scientific_context (field 28) - Decision guidance from tool docs
└─ [Other fields: help_text, parameters, etc.]

API Layer (NEW):
└─ get_tool_knowledge() - Combines all sources into unified view

Application Layer:
├─ Tool Discovery: Use nfcore keywords + categories
├─ Tool Selection: Use scientific_context applicability
├─ Parameter Config: Use scientific_context guidance + help_text
└─ Validation: Use nfcore I/O formats + scientific_context requirements
```

**Future Work**:
1. Create unified API for knowledge access
2. Track which knowledge source is most useful (ACE feedback)
3. Identify gaps where nfcore and scientific_context conflict
4. Use nfcore patterns to validate scientific_context claims

---

**END OF ANALYSIS**
