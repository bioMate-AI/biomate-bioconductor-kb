"""
Interactive Tool Mapping Configuration

Maps workflow outputs to appropriate visualization tools and templates.

Two types of tools:
1. Specialized Tools: Direct file-type mapping (CellxGene, Pavian, HiGlass, iSEE)
2. Template-Based Tools: Domain/output-type to Jupyter/RStudio templates
"""

from typing import Dict, List, Optional, Any
from dataclasses import dataclass, field


@dataclass
class InteractiveTool:
    """Definition of an interactive visualization tool."""
    tool_id: str
    name: str
    description: str
    input_formats: List[str]  # File extensions/formats accepted
    container_image: str
    port: int
    url_path: str
    category: str  # specialized | template-based
    domain: Optional[str] = None  # genomics, transcriptomics, etc.


@dataclass
class NotebookTemplate:
    """Definition of a notebook template for Jupyter/RStudio."""
    template_id: str
    name: str
    description: str
    path: str  # Path within container
    domain: str
    input_formats: List[str]
    expected_inputs: List[Dict[str, str]]  # name, type, description
    outputs: List[str]
    parameters: Dict[str, Any] = field(default_factory=dict)


class InteractiveToolRegistry:
    """Registry of interactive tools and templates with output mapping."""

    def __init__(self):
        self.specialized_tools = self._load_specialized_tools()
        self.templates = self._load_templates()
        self.format_to_tool = self._build_format_mapping()
        self.domain_to_templates = self._build_domain_mapping()

    def _load_specialized_tools(self) -> Dict[str, InteractiveTool]:
        """Load specialized visualization tools."""
        return {
            "cellxgene": InteractiveTool(
                tool_id="interactive_tool_cellxgene",
                name="CellxGene",
                description="Interactive single-cell data explorer for UMAP visualization and cell annotation",
                input_formats=["h5ad"],
                container_image="biomate/interactive:latest",
                port=5005,
                url_path="/cellxgene/",
                category="specialized",
                domain="single_cell"
            ),
            "pavian": InteractiveTool(
                tool_id="interactive_tool_pavian",
                name="Pavian",
                description="Metagenomics classification browser for Kraken/Bracken results",
                input_formats=["kreport", "kraken", "bracken", "centrifuge"],
                container_image="biomate/interactive:latest",
                port=3838,
                url_path="/shiny/",
                category="specialized",
                domain="metagenomics"
            ),
            "higlass": InteractiveTool(
                tool_id="interactive_tool_higlass",
                name="HiGlass",
                description="Multi-scale Hi-C contact map visualization",
                input_formats=["cool", "mcool", "hic"],
                container_image="biomate/interactive:latest",
                port=8989,
                url_path="/higlass/",
                category="specialized",
                domain="epigenomics"
            ),
            "isee": InteractiveTool(
                tool_id="interactive_tool_isee",
                name="iSEE",
                description="Interactive SummarizedExperiment Explorer for R objects",
                input_formats=["rds", "RDS", "rda"],
                container_image="biomate/interactive:latest",
                port=7777,
                url_path="/isee/",
                category="specialized",
                domain="single_cell"
            ),
            "openrefine": InteractiveTool(
                tool_id="interactive_tool_openrefine",
                name="OpenRefine",
                description="Data cleaning and transformation tool",
                input_formats=["csv", "tsv", "json", "xml", "xlsx"],
                container_image="biomate/interactive:latest",
                port=3333,
                url_path="/openrefine/",
                category="specialized",
                domain="data_wrangling"
            ),
            "ethercalc": InteractiveTool(
                tool_id="interactive_tool_ethercalc",
                name="EtherCalc",
                description="Collaborative spreadsheet editor",
                input_formats=["csv", "tsv", "xlsx"],
                container_image="biomate/interactive:latest",
                port=8000,
                url_path="/ethercalc/",
                category="specialized",
                domain="data_wrangling"
            ),
        }

    def _load_templates(self) -> Dict[str, NotebookTemplate]:
        """Load Jupyter/RStudio notebook templates."""
        return {
            # Transcriptomics templates
            "deseq2_visualization": NotebookTemplate(
                template_id="deseq2_visualization",
                name="DESeq2 Visualization",
                description="Volcano plots, MA plots, and heatmaps for differential expression results",
                path="templates/transcriptomics/deseq2_visualization.ipynb",
                domain="transcriptomics",
                input_formats=["tsv", "csv", "tabular"],
                expected_inputs=[
                    {"name": "de_results", "type": "tabular", "description": "DESeq2 results with log2FC and pvalue columns"}
                ],
                outputs=["volcano_plot.png", "ma_plot.png", "heatmap.png", "summary.md"],
                parameters={"pvalue_threshold": 0.05, "log2fc_threshold": 1.0}
            ),
            "pathway_enrichment": NotebookTemplate(
                template_id="pathway_enrichment",
                name="Pathway Enrichment Analysis",
                description="GO and KEGG pathway enrichment analysis",
                path="templates/transcriptomics/pathway_enrichment.ipynb",
                domain="transcriptomics",
                input_formats=["tsv", "csv", "txt"],
                expected_inputs=[
                    {"name": "gene_list", "type": "text", "description": "List of significant genes"}
                ],
                outputs=["go_enrichment.png", "kegg_pathways.png", "enrichment_table.tsv"],
                parameters={"organism": "human", "pvalue_cutoff": 0.05}
            ),
            "pca_analysis": NotebookTemplate(
                template_id="pca_analysis",
                name="PCA Analysis",
                description="Principal component analysis and sample clustering",
                path="templates/transcriptomics/pca_analysis.ipynb",
                domain="transcriptomics",
                input_formats=["tsv", "csv", "tabular"],
                expected_inputs=[
                    {"name": "count_matrix", "type": "tabular", "description": "Gene count matrix (genes x samples)"}
                ],
                outputs=["pca_plot.png", "variance_explained.png", "sample_distances.png"],
                parameters={"n_components": 10}
            ),

            # Single-cell templates
            "scanpy_qc": NotebookTemplate(
                template_id="scanpy_qc",
                name="Single-Cell QC",
                description="Quality control and UMAP visualization for scRNA-seq",
                path="templates/single_cell/scanpy_qc.ipynb",
                domain="single_cell",
                input_formats=["h5ad"],
                expected_inputs=[
                    {"name": "adata", "type": "h5ad", "description": "AnnData object from scanpy/cellranger"}
                ],
                outputs=["qc_metrics.png", "umap_clusters.png", "marker_expression.png"],
                parameters={"min_genes": 200, "max_mito_pct": 20}
            ),
            "clustering_analysis": NotebookTemplate(
                template_id="clustering_analysis",
                name="Clustering Analysis",
                description="Cell clustering and marker gene identification",
                path="templates/single_cell/clustering_analysis.ipynb",
                domain="single_cell",
                input_formats=["h5ad"],
                expected_inputs=[
                    {"name": "adata", "type": "h5ad", "description": "Preprocessed AnnData object"}
                ],
                outputs=["clusters.png", "markers.tsv", "dotplot.png"],
                parameters={"resolution": 0.5, "n_markers": 10}
            ),

            # Genomics templates
            "variant_summary": NotebookTemplate(
                template_id="variant_summary",
                name="Variant Summary",
                description="Summary statistics and visualizations for VCF files",
                path="templates/genomics/variant_summary.ipynb",
                domain="genomics",
                input_formats=["vcf", "vcf.gz", "bcf"],
                expected_inputs=[
                    {"name": "variants", "type": "vcf", "description": "VCF file with variant calls"}
                ],
                outputs=["variant_stats.png", "quality_distribution.png", "summary.md"],
                parameters={}
            ),
            "coverage_analysis": NotebookTemplate(
                template_id="coverage_analysis",
                name="Coverage Analysis",
                description="Sequencing coverage depth analysis",
                path="templates/genomics/coverage_analysis.ipynb",
                domain="genomics",
                input_formats=["bam", "bed", "bedgraph"],
                expected_inputs=[
                    {"name": "coverage", "type": "bed", "description": "Coverage depth file"}
                ],
                outputs=["coverage_histogram.png", "genome_coverage.png"],
                parameters={}
            ),

            # Metagenomics templates
            "diversity_analysis": NotebookTemplate(
                template_id="diversity_analysis",
                name="Diversity Analysis",
                description="Alpha and beta diversity analysis for microbiome data",
                path="templates/metagenomics/diversity_analysis.ipynb",
                domain="metagenomics",
                input_formats=["biom", "tsv", "csv"],
                expected_inputs=[
                    {"name": "otu_table", "type": "biom", "description": "OTU/ASV abundance table"}
                ],
                outputs=["alpha_diversity.png", "beta_diversity.png", "taxonomy_barplot.png"],
                parameters={}
            ),

            # Epigenomics templates
            "peak_annotation": NotebookTemplate(
                template_id="peak_annotation",
                name="Peak Annotation",
                description="Annotate ChIP-seq/ATAC-seq peaks with genomic features",
                path="templates/epigenomics/peak_annotation.ipynb",
                domain="epigenomics",
                input_formats=["bed", "narrowPeak", "broadPeak"],
                expected_inputs=[
                    {"name": "peaks", "type": "bed", "description": "Peak file from peak calling"}
                ],
                outputs=["peak_annotation.png", "feature_distribution.png", "annotated_peaks.tsv"],
                parameters={}
            ),
        }

    def _build_format_mapping(self) -> Dict[str, List[str]]:
        """Build mapping from file format to tool IDs."""
        mapping = {}
        for tool_id, tool in self.specialized_tools.items():
            for fmt in tool.input_formats:
                if fmt not in mapping:
                    mapping[fmt] = []
                mapping[fmt].append(tool_id)
        return mapping

    def _build_domain_mapping(self) -> Dict[str, List[str]]:
        """Build mapping from domain to template IDs."""
        mapping = {}
        for template_id, template in self.templates.items():
            domain = template.domain
            if domain not in mapping:
                mapping[domain] = []
            mapping[domain].append(template_id)
        return mapping

    def suggest_tools_for_file(self, filename: str, file_format: Optional[str] = None) -> List[Dict[str, Any]]:
        """
        Suggest interactive tools based on file name/format.

        Returns list of suggestions with tool info and confidence.
        """
        suggestions = []

        # Determine format from filename if not provided
        if not file_format:
            file_format = self._detect_format(filename)

        # Check specialized tools
        if file_format in self.format_to_tool:
            for tool_id in self.format_to_tool[file_format]:
                tool = self.specialized_tools[tool_id]
                suggestions.append({
                    "type": "specialized",
                    "tool_id": tool.tool_id,
                    "name": tool.name,
                    "description": tool.description,
                    "url_path": tool.url_path,
                    "confidence": 0.95,  # High confidence for direct format match
                    "reason": f"Direct visualization for {file_format} files"
                })

        # Check templates that accept this format
        for template_id, template in self.templates.items():
            if file_format in template.input_formats:
                suggestions.append({
                    "type": "template",
                    "template_id": template_id,
                    "name": template.name,
                    "description": template.description,
                    "path": template.path,
                    "domain": template.domain,
                    "confidence": 0.8,
                    "reason": f"Analysis template for {template.domain}"
                })

        # Sort by confidence
        suggestions.sort(key=lambda x: x["confidence"], reverse=True)
        return suggestions

    def suggest_tools_for_workflow(self, workflow_domain: str, output_types: List[str]) -> List[Dict[str, Any]]:
        """
        Suggest interactive tools based on workflow domain and outputs.

        Args:
            workflow_domain: Domain like 'transcriptomics', 'single_cell', etc.
            output_types: List of output file formats from the workflow

        Returns:
            List of tool/template suggestions
        """
        suggestions = []
        seen = set()

        # First, suggest specialized tools based on output types
        for output_type in output_types:
            for suggestion in self.suggest_tools_for_file("", output_type):
                key = suggestion.get("tool_id") or suggestion.get("template_id")
                if key not in seen:
                    seen.add(key)
                    suggestions.append(suggestion)

        # Then, add domain-specific templates
        if workflow_domain in self.domain_to_templates:
            for template_id in self.domain_to_templates[workflow_domain]:
                if template_id not in seen:
                    template = self.templates[template_id]
                    suggestions.append({
                        "type": "template",
                        "template_id": template_id,
                        "name": template.name,
                        "description": template.description,
                        "path": template.path,
                        "domain": template.domain,
                        "confidence": 0.7,
                        "reason": f"Recommended for {workflow_domain} workflows"
                    })
                    seen.add(template_id)

        suggestions.sort(key=lambda x: x["confidence"], reverse=True)
        return suggestions

    def _detect_format(self, filename: str) -> str:
        """Detect file format from filename."""
        filename_lower = filename.lower()

        # Check compound extensions first
        if filename_lower.endswith('.vcf.gz'):
            return 'vcf.gz'

        # Common bioinformatics formats
        format_map = {
            '.h5ad': 'h5ad',
            '.rds': 'rds',
            '.rda': 'rda',
            '.cool': 'cool',
            '.mcool': 'mcool',
            '.hic': 'hic',
            '.kreport': 'kreport',
            '.biom': 'biom',
            '.vcf': 'vcf',
            '.bcf': 'bcf',
            '.bam': 'bam',
            '.bed': 'bed',
            '.narrowpeak': 'narrowPeak',
            '.broadpeak': 'broadPeak',
            '.bedgraph': 'bedgraph',
            '.csv': 'csv',
            '.tsv': 'tsv',
            '.json': 'json',
            '.xlsx': 'xlsx',
        }

        for ext, fmt in format_map.items():
            if filename_lower.endswith(ext):
                return fmt

        # Check for patterns in filename
        if 'kraken' in filename_lower or 'bracken' in filename_lower:
            return 'kreport'

        return 'unknown'

    def get_tool(self, tool_id: str) -> Optional[InteractiveTool]:
        """Get a specialized tool by ID."""
        return self.specialized_tools.get(tool_id)

    def get_template(self, template_id: str) -> Optional[NotebookTemplate]:
        """Get a notebook template by ID."""
        return self.templates.get(template_id)

    def list_all_tools(self) -> List[Dict[str, Any]]:
        """List all available interactive tools and templates."""
        result = []

        for tool_id, tool in self.specialized_tools.items():
            result.append({
                "id": tool_id,
                "type": "specialized",
                "name": tool.name,
                "description": tool.description,
                "domain": tool.domain,
                "input_formats": tool.input_formats
            })

        for template_id, template in self.templates.items():
            result.append({
                "id": template_id,
                "type": "template",
                "name": template.name,
                "description": template.description,
                "domain": template.domain,
                "input_formats": template.input_formats
            })

        return result


# Singleton instance
_registry = None

def get_interactive_tool_registry() -> InteractiveToolRegistry:
    """Get the singleton interactive tool registry."""
    global _registry
    if _registry is None:
        _registry = InteractiveToolRegistry()
    return _registry


# Convenience functions
def suggest_visualization(filename: str) -> List[Dict[str, Any]]:
    """Suggest visualization tools for a file."""
    return get_interactive_tool_registry().suggest_tools_for_file(filename)


def suggest_post_workflow_tools(domain: str, outputs: List[str]) -> List[Dict[str, Any]]:
    """Suggest post-workflow visualization tools."""
    return get_interactive_tool_registry().suggest_tools_for_workflow(domain, outputs)


# ============================================
# Tool Execution Mode Classification
# For AWS Batch vs Interactive Container split
# ============================================

class ToolExecutionMode:
    """Classification of tools by execution mode for workflow splitting."""

    # Tools that can run in AWS Batch (headless, no web server)
    BATCH_COMPATIBLE = {
        # Read processing
        'cutadapt', 'trimmomatic', 'fastp', 'trim_galore',
        # Alignment
        'bowtie2', 'bwa', 'bwa_mem', 'bwa_mem2', 'star', 'hisat2',
        'minimap2', 'star_solo', 'cellranger',
        # Quantification
        'featurecounts', 'htseq_count', 'salmon', 'kallisto',
        'rsem', 'stringtie',
        # Variant calling
        'gatk_haplotypecaller', 'gatk_mutect2', 'freebayes',
        'deepvariant', 'bcftools_call', 'varscan',
        # Assembly
        'spades', 'megahit', 'flye', 'canu', 'hifiasm',
        'trinity', 'rnaspades',
        # Annotation
        'prokka', 'bakta', 'snpeff', 'vep', 'annovar',
        # Metagenomics
        'kraken2', 'bracken', 'metaphlan', 'humann',
        'diamond', 'kaiju', 'centrifuge',
        # Differential expression (core computation)
        'deseq2', 'edger', 'limma', 'sleuth',
        # Single-cell (computation)
        'scanpy_filter', 'scanpy_normalize', 'scanpy_pca',
        'scanpy_neighbors', 'scanpy_cluster', 'seurat',
        # File manipulation
        'samtools_view', 'samtools_sort', 'samtools_index',
        'samtools_merge', 'samtools_markdup', 'samtools_stats',
        'bcftools_view', 'bcftools_filter', 'bcftools_norm',
        'bedtools_intersect', 'bedtools_merge', 'bedtools_getfasta',
        'bedtools_bamtobed', 'bedtools_coverage',
        'picard_markduplicates', 'picard_sortsam',
        # Peak calling
        'macs2_callpeak', 'homer_findpeaks', 'genrich',
        # Format conversion
        'bamtofastq', 'bedtobigbed', 'bedgraphtobigwig',
    }

    # Tools that require interactive environment (web server, display)
    INTERACTIVE_REQUIRED = {
        # QC reporting (generate interactive HTML)
        'multiqc', 'fastqc',
        # R Shiny apps
        'pavian', 'isee', 'shiny_app',
        # Specialized viewers
        'cellxgene', 'higlass', 'igv', 'jbrowse',
        # Notebooks
        'jupyter', 'jupyterlab', 'rstudio',
        # Plotting tools (interactive output)
        'ggplot2_point', 'ggplot2_heatmap', 'ggplot2_violin',
        'plotly_', 'bokeh_', 'altair_',
        'scatterplot', 'volcano_plot', 'heatmap2',
        'complexheatmap', 'pheatmap',
        # Data exploration
        'openrefine', 'ethercalc', 'spreadsheet',
    }

    # Tools that can run either way (batch generates files, interactive for exploration)
    HYBRID_TOOLS = {
        # QC tools - generate static HTML but viewing is interactive
        'busco': {'batch_output': 'summary.txt', 'interactive_output': 'html_report'},
        'quast': {'batch_output': 'report.tsv', 'interactive_output': 'report.html'},
        # Plotting - can generate static images or interactive
        'matplotlib': {'batch_output': 'png/pdf', 'interactive_output': 'show()'},
    }

    @classmethod
    def classify_tool(cls, tool_id: str) -> str:
        """
        Classify a tool by its execution mode.

        Returns:
            'batch': Can run in AWS Batch
            'interactive': Requires interactive container
            'hybrid': Can run either way
            'unknown': Not classified
        """
        tool_lower = tool_id.lower()

        # Check exact matches first
        if tool_lower in cls.BATCH_COMPATIBLE:
            return 'batch'
        if tool_lower in cls.INTERACTIVE_REQUIRED:
            return 'interactive'
        if tool_lower in cls.HYBRID_TOOLS:
            return 'hybrid'

        # Check prefix matches
        for batch_tool in cls.BATCH_COMPATIBLE:
            if tool_lower.startswith(batch_tool) or batch_tool.startswith(tool_lower.split('_')[0]):
                return 'batch'

        for interactive_tool in cls.INTERACTIVE_REQUIRED:
            if tool_lower.startswith(interactive_tool):
                return 'interactive'

        return 'unknown'

    @classmethod
    def find_split_point(cls, tool_sequence: List[str]) -> Optional[int]:
        """
        Find the optimal split point in a workflow tool sequence.

        Returns the index where the workflow should be split,
        or None if no split is needed.

        The split point is BEFORE the first interactive tool.
        """
        for i, tool_id in enumerate(tool_sequence):
            mode = cls.classify_tool(tool_id)
            if mode == 'interactive':
                return i

        return None  # All batch-compatible, no split needed

    @classmethod
    def analyze_workflow(cls, tool_sequence: List[str]) -> Dict[str, Any]:
        """
        Analyze a workflow for computation/visualization split.

        Returns:
            {
                'needs_split': bool,
                'split_point': int or None,
                'batch_tools': List[str],
                'interactive_tools': List[str],
                'hybrid_tools': List[str],
                'unknown_tools': List[str],
                'recommendation': str
            }
        """
        batch_tools = []
        interactive_tools = []
        hybrid_tools = []
        unknown_tools = []

        for tool_id in tool_sequence:
            mode = cls.classify_tool(tool_id)
            if mode == 'batch':
                batch_tools.append(tool_id)
            elif mode == 'interactive':
                interactive_tools.append(tool_id)
            elif mode == 'hybrid':
                hybrid_tools.append(tool_id)
            else:
                unknown_tools.append(tool_id)

        split_point = cls.find_split_point(tool_sequence)

        # Generate recommendation
        if not interactive_tools:
            recommendation = "No split needed - all tools are batch-compatible"
        elif not batch_tools:
            recommendation = "No split needed - workflow is purely interactive"
        elif split_point == 0:
            recommendation = "Consider restructuring - workflow starts with interactive tool"
        else:
            recommendation = f"Split at position {split_point} - {split_point} batch tools, {len(tool_sequence) - split_point} interactive tools"

        return {
            'needs_split': bool(batch_tools and interactive_tools),
            'split_point': split_point,
            'batch_tools': batch_tools,
            'interactive_tools': interactive_tools,
            'hybrid_tools': hybrid_tools,
            'unknown_tools': unknown_tools,
            'recommendation': recommendation
        }


# Convenience function
def analyze_workflow_for_split(tool_ids: List[str]) -> Dict[str, Any]:
    """Analyze a workflow to determine if it needs computation/visualization split."""
    return ToolExecutionMode.analyze_workflow(tool_ids)
