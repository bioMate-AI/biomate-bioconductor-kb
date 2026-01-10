# Learning from the Community: Automatic Use Case Extraction from Bioconductor, Literature, and Beyond

**Category**: Platform Updates | AI Learning | Use Case Discovery

**Published**: December 2024

## The Knowledge Gap

A tool's documentation tells you *what* it does. But researchers need to know *when* and *how* to use it:

- "When should I use Tool A vs Tool B?"
- "What's the typical workflow for this analysis?"
- "How do experts in my field approach this problem?"

This contextual knowledge - **use cases** - traditionally requires years of domain expertise or hours of reading papers and tutorials. BioMate is changing that through automatic use case extraction.

## Three Sources of Use Case Knowledge

### 1. Bioconductor Vignettes

Bioconductor packages include rich, curated vignettes - step-by-step tutorials demonstrating real analysis workflows. These represent **expert-validated** use cases.

**What We Extract:**
- Complete analysis workflows with code
- Recommended parameter settings
- Typical input/output data types
- Integration with other packages
- Quality control checkpoints

**Example: DESeq2 Vignette Extraction**
```
USE CASE: Differential Expression Analysis
WORKFLOW:
  1. Load count matrix from featureCounts/HTSeq
  2. Create DESeqDataSet with design formula
  3. Run DESeq() for normalization and testing
  4. Extract results with adjusted p-values
  5. Visualize with MA plots and volcano plots

TYPICAL PARAMETERS:
  - alpha = 0.05 (FDR threshold)
  - lfcThreshold = 1 (log fold change)
  - fitType = "parametric" (dispersion estimation)

CONNECTS TO:
  - Upstream: STAR, HISAT2, featureCounts
  - Downstream: clusterProfiler, enrichplot
```

**Scale:**
- 2,000+ Bioconductor packages
- 3,000+ vignettes available
- Structured R Markdown format enables precise extraction

### 2. Scientific Literature

Published papers demonstrate tools in real research contexts, often with novel applications the original authors didn't anticipate.

**What We Extract:**
- Methods section tool mentions
- Parameter configurations used
- Integration with other tools
- Novel applications and adaptations
- Performance comparisons

**Extraction Pipeline:**
```
Paper PDF/HTML
      ↓
Full-text parsing (GROBID)
      ↓
Methods section identification
      ↓
Tool mention extraction
      ↓
Parameter parsing
      ↓
Workflow reconstruction
      ↓
Use case generation
```

**Example: Mining a Nature Methods Paper**
```
SOURCE: "Single-cell RNA-seq reveals new types of human
        blood dendritic cells" (Villani et al., 2017)

EXTRACTED USE CASES:

Tool: Seurat
Context: Human PBMC single-cell analysis
Workflow:
  - 10X Chromium data input
  - Quality filtering: nGene 200-2500, mito < 5%
  - Variable gene selection: 2000 genes
  - PCA: 20 components
  - Clustering: resolution 0.8-1.2
  - Marker identification: Wilcoxon test

Tool: Monocle
Context: Trajectory analysis of dendritic cell development
Workflow:
  - DDRTree dimensionality reduction
  - Pseudotime ordering
  - Branching analysis for DC subtypes
```

### 3. Community Resources

Beyond formal publications, valuable use cases exist in:

**Protocol Repositories**
- protocols.io step-by-step guides
- Nature Protocols supplementary materials
- Bio-protocol methods papers

**Community Forums**
- Biostars Q&A discussions
- Stack Overflow bioinformatics tags
- GitHub Issues and Discussions

**Tutorial Websites**
- Tool-specific documentation sites
- University course materials
- Training workshop resources

## Our Extraction Technology

### AI-Powered Understanding

We use large language models trained on scientific text to:

1. **Identify Tool Mentions**
   - Distinguish tool names from general terms
   - Handle aliases and version numbers
   - Link mentions to canonical tool IDs

2. **Extract Workflow Context**
   - What came before this tool?
   - What comes after?
   - What alternatives were considered?

3. **Parse Parameters**
   - Default vs recommended values
   - Context-dependent settings
   - Quality thresholds

4. **Generate Structured Use Cases**
   - Standardized format for storage
   - Semantic tags for retrieval
   - Confidence scores

### Quality Assurance

Not all extracted use cases are equal. We validate through:

- **Source Authority**: Peer-reviewed > preprint > forum post
- **Reproducibility**: Code available > description only
- **Recency**: Recent papers weighted higher
- **Citation Impact**: Highly-cited methods prioritized
- **Community Validation**: Cross-reference multiple sources

## How Use Cases Power BioMate

### Smarter Recommendations

When you describe your analysis goal, our AI considers:
- Your data type
- Your scientific domain
- **Relevant use cases from similar analyses**

This provides recommendations grounded in community practice, not just tool capabilities.

### Workflow Templates

Use cases become workflow templates:

```
USE CASE: "ATAC-seq peak calling and annotation"
          (from ENCODE consortium pipelines)

TEMPLATE WORKFLOW:
┌─────────────────────────────────┐
│ 1. Alignment (Bowtie2)          │
│    • Parameters from ENCODE     │
├─────────────────────────────────┤
│ 2. Filtering (SAMtools)         │
│    • Remove duplicates          │
│    • Remove mitochondrial       │
├─────────────────────────────────┤
│ 3. Peak Calling (MACS2)         │
│    • --nomodel --shift -100     │
│    • --extsize 200              │
├─────────────────────────────────┤
│ 4. Annotation (HOMER)           │
│    • Genomic feature assignment │
└─────────────────────────────────┘
```

### Contextual Help

When you use a tool, we show:
- "In similar analyses, researchers typically..."
- "Common next steps include..."
- "Consider adjusting X parameter when..."

### Parameter Suggestions

Default parameters aren't always optimal. Use case extraction reveals:
- Domain-specific best practices
- Data-type dependent settings
- Quality vs speed tradeoffs

## Current Progress and Roadmap

### Completed
- Bioconductor vignette parser (structural extraction)
- Literature PDF processing pipeline
- Tool mention extraction from text
- Basic use case generation

### In Development
- Deep semantic understanding of workflows
- Cross-source use case merging
- Parameter recommendation engine
- Real-time literature monitoring

### Future Plans
- Community contribution system
- Use case quality ratings
- Domain expert curation interface
- Integration with protocol registries

## Impact on Research

**Before**: Researchers spend hours reading papers and tutorials to understand best practices.

**After**: BioMate surfaces community-validated use cases automatically, enabling researchers to:
- Start analyses faster with proven workflows
- Avoid common pitfalls and parameter mistakes
- Discover novel applications of familiar tools
- Stay current with evolving best practices

## Try It Out

Our use case extraction powers recommendations throughout BioMate:

1. **Describe your analysis** in natural language
2. **Receive recommendations** grounded in community practice
3. **View use cases** that informed the suggestion
4. **Customize** the workflow for your specific needs

[Start Analysis](/workflow) | [Explore Use Cases](/use-cases) | [View Tool Index](/tools)

---

*BioMate learns from thousands of analyses to provide recommendations grounded in community practice - not just documentation.*

*Last Updated: December 2024*
*Status: Core extraction implemented, advanced features in development*
