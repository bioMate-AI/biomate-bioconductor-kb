# Visualization Tools Integration - Detailed Implementation Plan

**Date**: 2026-01-16
**Goal**: Integrate visualization tools into workflow phases following biological analysis steps

---

## Overview

Visualization tools should be embedded within workflow phases, not just at the end. Each analysis phase produces outputs that benefit from immediate visualization for QC and interpretation.

```
Phase 1: QC          → QC visualization (FastQC reports, MultiQC summary)
Phase 2: Preprocessing → QC after trimming (FastQC on trimmed reads)
Phase 3: Alignment   → Alignment QC (coverage plots, mapping stats)
Phase 4: Quantification → Count QC (PCA, correlation heatmap)
Phase 5: Analysis    → Results visualization (volcano, heatmap)
Phase 6: Enrichment  → Pathway plots (bar charts, network)
```

---

## Implementation Tasks

### Task 1: Update Domain Patterns with Visualization Tools

**File**: `lib/galaxy/ai/domain_workflow_patterns.py`

**Changes**: Add `visualization_tools` field to each phase with actual Galaxy tool IDs.

```python
# BEFORE:
WorkflowPhase(
    name="Quality Control",
    description="Assess raw read quality and adapter contamination",
    typical_tools=["FastQC", "MultiQC", "fastp"],
    position="early"
)

# AFTER:
WorkflowPhase(
    name="Quality Control",
    description="Assess raw read quality and adapter contamination",
    typical_tools=["FastQC", "MultiQC", "fastp"],
    visualization_tools=[
        {"id": "fastqc", "purpose": "Per-read quality plots", "auto_include": True},
        {"id": "multiqc", "purpose": "Aggregate QC summary", "auto_include": True},
    ],
    output_formats=["html", "zip"],
    position="early"
)
```

**Full Update for Transcriptomics Domain**:

```python
AnalysisDomain.TRANSCRIPTOMICS: DomainPattern(
    domain=AnalysisDomain.TRANSCRIPTOMICS,
    description="RNA sequencing and gene expression analysis",
    phases=[
        WorkflowPhase(
            name="Quality Control",
            description="Assess raw read quality",
            typical_tools=["fastqc", "multiqc"],
            visualization_tools=[
                {"id": "fastqc", "auto": True},
                {"id": "multiqc", "auto": True, "aggregates": True},
            ],
            output_formats=["html"],
            position="early"
        ),
        WorkflowPhase(
            name="Read Preprocessing",
            description="Trim adapters and filter low-quality reads",
            typical_tools=["cutadapt", "trimmomatic", "fastp"],
            visualization_tools=[
                {"id": "fastqc", "purpose": "Post-trim QC", "auto": True},
            ],
            output_formats=["fastq.gz"],
            position="early"
        ),
        WorkflowPhase(
            name="Alignment",
            description="Map reads to reference genome",
            typical_tools=["rna_star", "hisat2", "bwa_mem2"],
            visualization_tools=[
                {"id": "samtools_flagstat", "purpose": "Mapping statistics", "auto": True},
                {"id": "plotCoverage", "purpose": "Coverage distribution", "auto": False},
            ],
            output_formats=["bam"],
            interactive_tools=["interactive_tool_bam_iobio"],
            position="middle"
        ),
        WorkflowPhase(
            name="Count Generation",
            description="Generate gene count matrix",
            typical_tools=["featurecounts", "htseq-count", "salmon"],
            visualization_tools=[
                {"id": "plotPCA", "purpose": "Sample clustering", "auto": True},
                {"id": "plotCorrelation", "purpose": "Sample correlation", "auto": True},
            ],
            output_formats=["tsv", "tabular"],
            position="middle"
        ),
        WorkflowPhase(
            name="Differential Expression",
            description="Identify DE genes",
            typical_tools=["deseq2", "edger", "limma"],
            visualization_tools=[
                {"id": "volcanoplot", "purpose": "DE volcano plot", "auto": True},
                {"id": "plotHeatmap", "purpose": "Top genes heatmap", "auto": True},
                {"id": "ma_plot", "purpose": "MA plot", "auto": False},
            ],
            output_formats=["tsv", "tabular"],
            interactive_tools=["interactive_tool_rstudio"],
            position="late"
        ),
        WorkflowPhase(
            name="Functional Enrichment",
            description="GO/pathway analysis",
            typical_tools=["gprofiler", "david", "enrichr"],
            visualization_tools=[
                {"id": "barplot", "purpose": "Enrichment bar chart", "auto": True},
                {"id": "dotplot", "purpose": "Enrichment dot plot", "auto": False},
            ],
            output_formats=["tsv"],
            required=False,
            position="late"
        ),
    ],
    # ...
)
```

---

### Task 2: Create Tool ID Mapping Database

**File**: `lib/galaxy/ai/tool_id_mapping.py` (NEW)

**Purpose**: Map common tool names to actual Galaxy tool IDs in our database.

```python
"""
Tool ID Mapping for Galaxy AI Workflow Generator

Maps common bioinformatics tool names to actual Galaxy tool IDs.
"""

from typing import Dict, List, Optional
import sqlite3
from pathlib import Path

# Tool name to ID mapping (verified against galaxy_ai_tools.db)
TOOL_NAME_TO_ID: Dict[str, List[str]] = {
    # QC Tools
    "fastqc": ["fastqc", "FastQC"],
    "multiqc": ["multiqc", "MultiQC"],

    # Preprocessing
    "cutadapt": ["cutadapt", "Cutadapt"],
    "trimmomatic": ["trimmomatic", "Trimmomatic"],
    "fastp": ["fastp"],

    # Alignment - RNA-seq
    "star": ["rna_star", "rna_starsolo", "ctat_star_fusion"],
    "hisat2": ["hisat2"],
    "salmon": ["salmon", "salmon_quant"],
    "kallisto": ["kallisto_quant", "kallisto"],

    # Alignment - DNA
    "bwa": ["bwa_mem", "bwa_mem2", "Map with BWA-MEM"],
    "bowtie2": ["bowtie2"],
    "minimap2": ["minimap2"],

    # Quantification
    "featurecounts": ["featurecounts", "featureCounts"],
    "htseq_count": ["htseq_count", "htseq-count"],
    "stringtie": ["stringtie"],

    # Differential Expression
    "deseq2": ["deseq2", "aurora_deseq2", "bioconductor-deseq2"],
    "edger": ["edger", "bioconductor-edger"],
    "limma": ["limma", "limma-voom"],

    # Variant Calling
    "gatk_haplotypecaller": ["gatk4_haplotypecaller", "gatk_haplotypecaller"],
    "freebayes": ["freebayes"],
    "bcftools_call": ["bcftools_call"],

    # Variant Annotation
    "snpeff": ["snpeff", "SnpEff eff:"],
    "vep": ["vep", "ensembl_vep"],

    # Visualization Tools
    "plotpca": ["plotPCA"],
    "plotcorrelation": ["plotCorrelation"],
    "plotheatmap": ["plotHeatmap"],
    "plotprofile": ["plotProfile"],
    "plotcoverage": ["plotCoverage"],
    "volcanoplot": ["volcanoplot", "Volcano Plot"],
    "krona": ["krona_pie_chart", "krona"],

    # BAM Processing
    "samtools_flagstat": ["samtools_flagstat"],
    "samtools_stats": ["samtools_stats"],
    "picard_markduplicates": ["picard_MarkDuplicates"],

    # Peak Calling
    "macs2": ["macs2_callpeak", "MACS2 callpeak"],
    "homer": ["homer_findPeaks"],

    # Metagenomics
    "kraken2": ["kraken2"],
    "metaphlan": ["metaphlan"],
    "bracken": ["bracken"],
}

# Visualization tools by output type
VISUALIZATION_BY_OUTPUT: Dict[str, List[Dict]] = {
    "bam": [
        {"id": "samtools_flagstat", "purpose": "Mapping statistics", "auto": True},
        {"id": "samtools_stats", "purpose": "Detailed BAM stats", "auto": False},
        {"id": "plotCoverage", "purpose": "Coverage plot", "auto": False},
    ],
    "vcf": [
        {"id": "bcftools_stats", "purpose": "Variant statistics", "auto": True},
    ],
    "count_matrix": [
        {"id": "plotPCA", "purpose": "Sample PCA", "auto": True},
        {"id": "plotCorrelation", "purpose": "Sample correlation", "auto": True},
    ],
    "de_results": [
        {"id": "volcanoplot", "purpose": "Volcano plot", "auto": True},
        {"id": "plotHeatmap", "purpose": "Top genes heatmap", "auto": True},
    ],
    "peaks": [
        {"id": "plotProfile", "purpose": "Signal profile", "auto": True},
        {"id": "plotHeatmap", "purpose": "Peak heatmap", "auto": False},
    ],
    "kraken_report": [
        {"id": "krona_pie_chart", "purpose": "Taxonomy sunburst", "auto": True},
    ],
}

# Interactive tools by output type
INTERACTIVE_BY_OUTPUT: Dict[str, Dict] = {
    "bam": {
        "tool_id": "interactive_tool_bam_iobio",
        "name": "BAM iobio",
        "purpose": "Interactive alignment QC and inspection",
    },
    "vcf": {
        "tool_id": "interactive_tool_vcf_iobio",
        "name": "VCF iobio",
        "purpose": "Interactive variant filtering and QC",
    },
    "h5ad": {
        "tool_id": "interactive_tool_cellxgene",
        "name": "CellxGene",
        "purpose": "Interactive single-cell exploration",
    },
    "mcool": {
        "tool_id": "interactive_tool_higlass",
        "name": "HiGlass",
        "purpose": "Interactive Hi-C visualization",
    },
    "kraken_report": {
        "tool_id": "interactive_tool_pavian",
        "name": "Pavian",
        "purpose": "Interactive metagenomics explorer",
    },
    "biom": {
        "tool_id": "interactive_tool_phinch",
        "name": "Phinch",
        "purpose": "Interactive microbiome visualization",
    },
}


def resolve_tool_id(tool_name: str, db_path: Optional[Path] = None) -> Optional[str]:
    """
    Resolve a common tool name to an actual tool ID in the database.

    Args:
        tool_name: Common name like "deseq2", "fastqc"
        db_path: Path to galaxy_ai_tools.db

    Returns:
        Actual tool ID if found, None otherwise
    """
    if db_path is None:
        db_path = Path(__file__).parent.parent.parent.parent / "galaxy_ai_tools.db"

    # Get candidate IDs
    candidates = TOOL_NAME_TO_ID.get(tool_name.lower(), [tool_name])

    # Check which exists in database
    try:
        with sqlite3.connect(str(db_path)) as conn:
            for candidate in candidates:
                cursor = conn.execute(
                    "SELECT id FROM tools WHERE id = ? OR name LIKE ?",
                    (candidate, f"%{candidate}%")
                )
                row = cursor.fetchone()
                if row:
                    return row[0]
    except Exception:
        pass

    return None


def get_visualization_tools_for_output(output_type: str) -> List[Dict]:
    """Get visualization tools appropriate for an output type."""
    return VISUALIZATION_BY_OUTPUT.get(output_type, [])


def get_interactive_tool_for_output(output_type: str) -> Optional[Dict]:
    """Get interactive tool suggestion for an output type."""
    return INTERACTIVE_BY_OUTPUT.get(output_type)
```

---

### Task 3: Update Workflow Generator Tool Retrieval

**File**: `lib/galaxy/ai/galaxy_workflow_generator.py`

**Change**: Modify `_retrieve_tools_from_index()` to include visualization tools for the detected domain.

```python
def _retrieve_tools_from_index(
    self,
    user_intent: str,
    limit: int = 30,
    domain: Optional[AnalysisDomain] = None
) -> List[Dict[str, Any]]:
    """
    Retrieve available tools including domain-appropriate visualization tools.
    """
    # Get analysis tools (70% of limit)
    analysis_limit = int(limit * 0.7)
    analysis_tools = self.tool_index.search(user_intent, limit=analysis_limit)

    # Get visualization tools for domain (30% of limit)
    viz_limit = limit - len(analysis_tools)
    viz_tools = self._get_visualization_tools_for_domain(domain, viz_limit)

    # Combine and deduplicate
    all_tools = analysis_tools + viz_tools
    seen_ids = set()
    unique_tools = []
    for tool in all_tools:
        if tool['tool_id'] not in seen_ids:
            seen_ids.add(tool['tool_id'])
            unique_tools.append(tool)

    return unique_tools[:limit]


def _get_visualization_tools_for_domain(
    self,
    domain: AnalysisDomain,
    limit: int = 10
) -> List[Dict[str, Any]]:
    """
    Get visualization tools appropriate for the detected domain.
    """
    from .tool_id_mapping import VISUALIZATION_BY_OUTPUT
    from .domain_workflow_patterns import get_domain_pattern

    pattern = get_domain_pattern(domain)

    # Collect visualization tool IDs from all phases
    viz_tool_ids = set()
    for phase in pattern.phases:
        if hasattr(phase, 'visualization_tools'):
            for viz in phase.visualization_tools:
                viz_tool_ids.add(viz.get('id'))

    # Also add tools based on expected outputs
    for output_fmt in pattern.common_outputs:
        for viz in VISUALIZATION_BY_OUTPUT.get(output_fmt, []):
            viz_tool_ids.add(viz.get('id'))

    # Look up tools in database
    viz_tools = []
    for tool_id in viz_tool_ids:
        if tool_id:
            tool_info = self._lookup_tool_by_id(tool_id)
            if tool_info:
                viz_tools.append(tool_info)

    return viz_tools[:limit]
```

---

### Task 4: Update LLM Prompt to Include Visualization Guidance

**File**: `lib/galaxy/ai/galaxy_workflow_generator.py`

**Change**: Update `_generate_workflow_structure()` to include visualization tools in the prompt.

```python
def _generate_workflow_structure(
    self,
    user_intent: str,
    available_tools: List[Dict[str, Any]],
    detected_domain: Optional[AnalysisDomain] = None
) -> Dict[str, Any]:
    """Generate workflow with integrated visualization steps."""

    # ... existing domain detection code ...

    # Build visualization guidance
    viz_guidance = self._build_visualization_guidance(detected_domain)

    system_prompt = f"""You are an expert bioinformatics workflow architect for the Galaxy platform.

## DETECTED ANALYSIS DOMAIN: {detected_domain.value.upper()}

## AVAILABLE TOOLS (Use ONLY these exact tool_ids):

{tool_catalog}

## WORKFLOW DESIGN PRINCIPLES:

### Phase Structure with Integrated Visualization:

Each analysis phase should include appropriate visualization:

1. **DATA VALIDATION** (early)
   - QC tools: FastQC, MultiQC
   - Visualization: QC reports (auto-generated)

2. **PREPROCESSING** (early)
   - Trimming/filtering tools
   - Visualization: Post-trim QC

3. **CORE ANALYSIS** (middle)
   - Main analysis tools (alignment, quantification, etc.)
   - Visualization: Intermediate QC (mapping stats, PCA)

4. **RESULTS ANALYSIS** (late)
   - Statistical analysis tools (DE, variant calling)
   - Visualization: Results plots (volcano, heatmap, variant stats)

5. **INTERPRETATION** (late, optional)
   - Enrichment, annotation tools
   - Visualization: Pathway plots, annotation summaries

## VISUALIZATION TOOLS BY PHASE:

{viz_guidance}

## IMPORTANT: For each analysis step, consider adding the appropriate visualization tool IMMEDIATELY AFTER to enable QC and interpretation.

Example pattern:
- Step N: featureCounts (count generation)
- Step N+1: plotPCA (visualize sample relationships)
- Step N+2: plotCorrelation (verify sample quality)
- Step N+3: DESeq2 (differential expression)
- Step N+4: volcanoplot (visualize DE results)
- Step N+5: plotHeatmap (show top genes)

## OUTPUT FORMAT (JSON):
...
"""
```

**New method to build visualization guidance**:

```python
def _build_visualization_guidance(self, domain: AnalysisDomain) -> str:
    """Build visualization guidance for LLM prompt."""
    from .domain_workflow_patterns import get_domain_pattern
    from .tool_id_mapping import VISUALIZATION_BY_OUTPUT

    pattern = get_domain_pattern(domain)

    lines = []
    for phase in pattern.phases:
        phase_viz = []

        # Get phase-specific visualization tools
        if hasattr(phase, 'visualization_tools'):
            for viz in phase.visualization_tools:
                if viz.get('auto', False):
                    phase_viz.append(f"  - {viz['id']}: {viz.get('purpose', 'Visualization')}")

        if phase_viz:
            lines.append(f"### {phase.name}:")
            lines.extend(phase_viz)
            lines.append("")

    return '\n'.join(lines)
```

---

### Task 5: Update Domain Patterns Structure

**File**: `lib/galaxy/ai/domain_workflow_patterns.py`

**Change**: Update `WorkflowPhase` dataclass to include visualization and interactive tools.

```python
@dataclass
class WorkflowPhase:
    """Represents a phase in a domain-specific workflow."""
    name: str
    description: str
    typical_tools: List[str]
    required: bool = True
    position: str = "middle"  # early, middle, late

    # NEW FIELDS:
    visualization_tools: List[Dict[str, Any]] = field(default_factory=list)
    # Format: [{"id": "plotPCA", "purpose": "Sample clustering", "auto": True}]

    output_formats: List[str] = field(default_factory=list)
    # Format: ["bam", "tsv", "vcf"]

    interactive_tools: List[str] = field(default_factory=list)
    # Format: ["interactive_tool_bam_iobio"]
```

**Update each domain with visualization tools**:

```python
# TRANSCRIPTOMICS - Full update
AnalysisDomain.TRANSCRIPTOMICS: DomainPattern(
    domain=AnalysisDomain.TRANSCRIPTOMICS,
    description="RNA sequencing and gene expression analysis",
    phases=[
        WorkflowPhase(
            name="Quality Control",
            description="Assess raw read quality and adapter contamination",
            typical_tools=["fastqc", "multiqc"],
            visualization_tools=[
                {"id": "fastqc", "purpose": "Per-sample QC plots", "auto": True},
                {"id": "multiqc", "purpose": "Aggregated QC report", "auto": True},
            ],
            output_formats=["html", "txt"],
            position="early"
        ),
        WorkflowPhase(
            name="Read Preprocessing",
            description="Trim adapters and filter low-quality reads",
            typical_tools=["cutadapt", "trimmomatic", "fastp"],
            visualization_tools=[
                {"id": "fastqc", "purpose": "Post-trim QC", "auto": True},
            ],
            output_formats=["fastq.gz", "fastq"],
            position="early"
        ),
        WorkflowPhase(
            name="Alignment",
            description="Map reads to reference genome",
            typical_tools=["rna_star", "hisat2"],
            visualization_tools=[
                {"id": "samtools_flagstat", "purpose": "Mapping statistics", "auto": True},
                {"id": "rseqc_read_distribution", "purpose": "Read distribution", "auto": False},
            ],
            output_formats=["bam"],
            interactive_tools=["interactive_tool_bam_iobio"],
            position="middle"
        ),
        WorkflowPhase(
            name="Quantification",
            description="Generate gene/transcript counts",
            typical_tools=["featurecounts", "htseq_count", "salmon"],
            visualization_tools=[
                {"id": "plotPCA", "purpose": "Sample PCA", "auto": True},
                {"id": "plotCorrelation", "purpose": "Sample correlation heatmap", "auto": True},
            ],
            output_formats=["tsv", "tabular"],
            position="middle"
        ),
        WorkflowPhase(
            name="Differential Expression",
            description="Identify differentially expressed genes",
            typical_tools=["deseq2", "edger", "limma"],
            visualization_tools=[
                {"id": "volcanoplot", "purpose": "Volcano plot of DE genes", "auto": True},
                {"id": "plotHeatmap", "purpose": "Top DE genes heatmap", "auto": True},
            ],
            output_formats=["tsv", "tabular"],
            interactive_tools=["interactive_tool_rstudio", "interactive_tool_jupyter_notebook"],
            position="late"
        ),
        WorkflowPhase(
            name="Functional Enrichment",
            description="Gene ontology and pathway analysis",
            typical_tools=["gprofiler", "goseq"],
            visualization_tools=[
                {"id": "barplot", "purpose": "Enrichment bar chart", "auto": True},
            ],
            output_formats=["tsv"],
            required=False,
            position="late"
        ),
    ],
    common_inputs=["fastq", "fastq.gz"],
    common_outputs=["count_matrix", "de_results", "html"],
    keywords=["rna-seq", "rnaseq", "expression", "transcriptome", "differential"]
),

# GENOMICS - Full update
AnalysisDomain.GENOMICS: DomainPattern(
    domain=AnalysisDomain.GENOMICS,
    description="DNA sequencing, variant calling, and genome analysis",
    phases=[
        WorkflowPhase(
            name="Quality Control",
            description="Assess raw read quality",
            typical_tools=["fastqc", "multiqc"],
            visualization_tools=[
                {"id": "fastqc", "purpose": "Read quality plots", "auto": True},
                {"id": "multiqc", "purpose": "Aggregated QC", "auto": True},
            ],
            output_formats=["html"],
            position="early"
        ),
        WorkflowPhase(
            name="Read Preprocessing",
            description="Trim and filter reads",
            typical_tools=["cutadapt", "trimmomatic"],
            visualization_tools=[
                {"id": "fastqc", "purpose": "Post-trim QC", "auto": True},
            ],
            output_formats=["fastq.gz"],
            position="early"
        ),
        WorkflowPhase(
            name="Alignment",
            description="Map reads to reference genome",
            typical_tools=["bwa_mem2", "bowtie2"],
            visualization_tools=[
                {"id": "samtools_flagstat", "purpose": "Mapping statistics", "auto": True},
                {"id": "plotCoverage", "purpose": "Coverage distribution", "auto": False},
            ],
            output_formats=["bam"],
            interactive_tools=["interactive_tool_bam_iobio"],
            position="middle"
        ),
        WorkflowPhase(
            name="BAM Processing",
            description="Sort, mark duplicates, index",
            typical_tools=["samtools_sort", "picard_markduplicates"],
            visualization_tools=[
                {"id": "picard_collectmetrics", "purpose": "Duplication metrics", "auto": False},
            ],
            output_formats=["bam"],
            position="middle"
        ),
        WorkflowPhase(
            name="Variant Calling",
            description="Identify SNPs and indels",
            typical_tools=["gatk_haplotypecaller", "freebayes", "bcftools_call"],
            visualization_tools=[
                {"id": "bcftools_stats", "purpose": "Variant statistics", "auto": True},
            ],
            output_formats=["vcf"],
            interactive_tools=["interactive_tool_vcf_iobio"],
            position="late"
        ),
        WorkflowPhase(
            name="Variant Annotation",
            description="Annotate variant effects",
            typical_tools=["snpeff", "vep"],
            visualization_tools=[
                {"id": "snpeff_stats", "purpose": "Annotation summary", "auto": True},
            ],
            output_formats=["vcf", "html"],
            required=False,
            position="late"
        ),
    ],
    common_inputs=["fastq", "fastq.gz", "bam"],
    common_outputs=["vcf", "bam", "html"],
    keywords=["variant", "snp", "mutation", "dna-seq", "wgs", "exome"]
),

# Continue for other domains...
```

---

### Task 6: Add Interactive Tool Suggestion to Workflow Output

**File**: `lib/galaxy/ai/galaxy_workflow_generator.py`

**Change**: Add interactive tool suggestions to the workflow result based on output formats.

```python
def generate_workflow(self, user_intent: str, ...) -> Dict[str, Any]:
    """Generate workflow with interactive tool suggestions."""

    # ... existing workflow generation ...

    # After workflow generation, analyze outputs and suggest interactive tools
    interactive_suggestions = self._generate_interactive_suggestions(
        workflow_structure,
        detected_domain
    )

    return {
        "success": True,
        "workflow_ga": galaxy_workflow,
        "workflow_structure": workflow_structure,
        "detected_domain": detected_domain.value,
        # ... other fields ...

        # NEW: Interactive tool suggestions
        "interactive_suggestions": interactive_suggestions,
    }


def _generate_interactive_suggestions(
    self,
    workflow_structure: Dict[str, Any],
    domain: AnalysisDomain
) -> List[Dict[str, Any]]:
    """Generate interactive tool suggestions based on workflow outputs."""
    from .tool_id_mapping import INTERACTIVE_BY_OUTPUT
    from .domain_workflow_patterns import get_domain_pattern

    suggestions = []
    pattern = get_domain_pattern(domain)

    # Check each phase for interactive tool opportunities
    for phase in pattern.phases:
        if hasattr(phase, 'interactive_tools') and phase.interactive_tools:
            for tool_id in phase.interactive_tools:
                tool_info = INTERACTIVE_BY_OUTPUT.get(
                    phase.output_formats[0] if phase.output_formats else None
                )
                if tool_info:
                    suggestions.append({
                        "phase": phase.name,
                        "tool_id": tool_id,
                        "tool_name": tool_info.get("name", tool_id),
                        "purpose": tool_info.get("purpose", "Interactive exploration"),
                        "output_format": phase.output_formats[0] if phase.output_formats else "unknown",
                        "when_to_use": f"After {phase.name} to explore results interactively"
                    })

    return suggestions
```

---

### Task 7: Verify Tool IDs in Database

**Script**: Run once to verify all tool IDs exist.

```python
# verify_tool_ids.py
import sqlite3
from pathlib import Path

# Tool IDs we plan to use
VISUALIZATION_TOOLS = [
    "fastqc", "multiqc", "samtools_flagstat", "samtools_stats",
    "plotPCA", "plotCorrelation", "plotHeatmap", "plotProfile",
    "plotCoverage", "volcanoplot", "bcftools_stats", "krona_pie_chart"
]

INTERACTIVE_TOOLS = [
    "interactive_tool_jupyter_notebook", "interactive_tool_rstudio",
    "interactive_tool_cellxgene", "interactive_tool_bam_iobio",
    "interactive_tool_vcf_iobio", "interactive_tool_pavian",
    "interactive_tool_phinch", "interactive_tool_higlass"
]

db_path = Path("galaxy_ai_tools.db")
conn = sqlite3.connect(str(db_path))

print("=== Verification Results ===\n")

print("Visualization Tools:")
for tool_id in VISUALIZATION_TOOLS:
    cursor = conn.execute(
        "SELECT id, name FROM tools WHERE id LIKE ? OR name LIKE ?",
        (f"%{tool_id}%", f"%{tool_id}%")
    )
    rows = cursor.fetchall()
    if rows:
        print(f"  [FOUND] {tool_id} -> {rows[0]}")
    else:
        print(f"  [MISSING] {tool_id}")

print("\nInteractive Tools:")
for tool_id in INTERACTIVE_TOOLS:
    cursor = conn.execute(
        "SELECT id, name FROM tools WHERE id LIKE ?",
        (f"%{tool_id}%",)
    )
    rows = cursor.fetchall()
    if rows:
        print(f"  [FOUND] {tool_id} -> {rows[0]}")
    else:
        print(f"  [NOT IN DB - OK if Galaxy has it] {tool_id}")

conn.close()
```

---

## Implementation Order

| Order | Task | Files | Effort |
|-------|------|-------|--------|
| 1 | Create tool_id_mapping.py | NEW file | 1 hour |
| 2 | Update WorkflowPhase dataclass | domain_workflow_patterns.py | 30 min |
| 3 | Update Transcriptomics patterns | domain_workflow_patterns.py | 1 hour |
| 4 | Update Genomics patterns | domain_workflow_patterns.py | 1 hour |
| 5 | Update other domain patterns | domain_workflow_patterns.py | 2 hours |
| 6 | Update tool retrieval | galaxy_workflow_generator.py | 1 hour |
| 7 | Update LLM prompt | galaxy_workflow_generator.py | 1 hour |
| 8 | Add interactive suggestions | galaxy_workflow_generator.py | 1 hour |
| 9 | Verify tool IDs | Run verification script | 30 min |
| 10 | Test with real workflows | Manual testing | 2 hours |

**Total estimated effort**: ~12 hours

---

## Expected Outcome

After implementation, a workflow generation request like:

> "Analyze RNA-seq data to find differentially expressed genes"

Will produce a workflow like:

```
Step 1: [QC] FastQC - Raw read quality
Step 2: [QC] MultiQC - Aggregate QC report
Step 3: [Preprocessing] Cutadapt - Trim adapters
Step 4: [Preprocessing QC] FastQC - Post-trim quality
Step 5: [Alignment] STAR - Map to genome
Step 6: [Alignment QC] samtools_flagstat - Mapping statistics
Step 7: [Quantification] featureCounts - Generate counts
Step 8: [Quantification QC] plotPCA - Sample clustering
Step 9: [Quantification QC] plotCorrelation - Sample correlation
Step 10: [DE Analysis] DESeq2 - Differential expression
Step 11: [DE Visualization] volcanoplot - DE volcano plot
Step 12: [DE Visualization] plotHeatmap - Top genes heatmap

Interactive suggestions:
- BAM iobio: Inspect alignment quality (after Step 5)
- RStudio/Jupyter: Custom visualization (after Step 10)
```
