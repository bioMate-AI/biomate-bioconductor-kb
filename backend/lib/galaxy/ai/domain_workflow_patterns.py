"""
Domain-Specific Workflow Patterns for Galaxy AI Assistant

Defines biologically meaningful workflow phases for each analysis domain,
replacing generic phases with domain-specific best practices.

Derived from analysis of 914 community workflows in the BioMate database.
"""

from typing import Dict, List, Any, Optional, Tuple
from dataclasses import dataclass
from enum import Enum
import logging

log = logging.getLogger(__name__)


class AnalysisDomain(Enum):
    """Supported analysis domains."""
    TRANSCRIPTOMICS = "transcriptomics"
    GENOMICS = "genomics"
    PROTEOMICS = "proteomics"
    EPIGENOMICS = "epigenomics"
    METAGENOMICS = "metagenomics"
    METABOLOMICS = "metabolomics"
    DATA_QUERY = "data_query"  # Database queries
    GENERAL = "general"


@dataclass
class WorkflowPhase:
    """Represents a phase in a domain-specific workflow."""
    name: str
    description: str
    typical_tools: List[str]
    required: bool = True
    position: str = "middle"  # early, middle, late


@dataclass
class DomainPattern:
    """Complete pattern for a specific analysis domain."""
    domain: AnalysisDomain
    description: str
    phases: List[WorkflowPhase]
    common_inputs: List[str]
    common_outputs: List[str]
    keywords: List[str]


# =============================================================================
# DOMAIN-SPECIFIC PATTERNS
# =============================================================================

DOMAIN_PATTERNS: Dict[AnalysisDomain, DomainPattern] = {

    AnalysisDomain.TRANSCRIPTOMICS: DomainPattern(
        domain=AnalysisDomain.TRANSCRIPTOMICS,
        description="RNA sequencing and gene expression analysis",
        phases=[
            WorkflowPhase(
                name="Quality Control",
                description="Assess raw read quality and adapter contamination",
                typical_tools=["FastQC", "MultiQC", "fastp"],
                position="early"
            ),
            WorkflowPhase(
                name="Read Preprocessing",
                description="Trim adapters and filter low-quality reads",
                typical_tools=["Cutadapt", "Trimmomatic", "fastp"],
                position="early"
            ),
            WorkflowPhase(
                name="Alignment/Quantification",
                description="Map reads to reference or pseudo-align for quantification",
                typical_tools=["STAR", "HISAT2", "Salmon", "Kallisto", "StringTie"],
                position="middle"
            ),
            WorkflowPhase(
                name="Count Generation",
                description="Generate gene/transcript count matrices",
                typical_tools=["featureCounts", "HTSeq-count", "StringTie"],
                position="middle"
            ),
            WorkflowPhase(
                name="Differential Expression",
                description="Identify differentially expressed genes",
                typical_tools=["DESeq2", "edgeR", "limma"],
                position="late"
            ),
            WorkflowPhase(
                name="Functional Enrichment",
                description="Gene ontology and pathway analysis",
                typical_tools=["gProfiler", "DAVID", "clusterProfiler"],
                required=False,
                position="late"
            ),
            WorkflowPhase(
                name="Visualization",
                description="Generate plots (volcano, MA, heatmap)",
                typical_tools=["ggplot2", "Plotly", "heatmap"],
                required=False,
                position="late"
            )
        ],
        common_inputs=["fastq", "fastq.gz", "reference_genome", "gtf"],
        common_outputs=["count_matrix", "differential_expression_table", "plots"],
        keywords=["rna-seq", "rnaseq", "expression", "transcriptome", "differential",
                  "deseq", "salmon", "star", "hisat", "gene expression"]
    ),

    AnalysisDomain.GENOMICS: DomainPattern(
        domain=AnalysisDomain.GENOMICS,
        description="DNA sequencing, variant calling, and genome analysis",
        phases=[
            WorkflowPhase(
                name="Quality Control",
                description="Assess raw read quality",
                typical_tools=["FastQC", "NanoPlot", "MultiQC"],
                position="early"
            ),
            WorkflowPhase(
                name="Read Preprocessing",
                description="Trim and filter reads",
                typical_tools=["Cutadapt", "Trimmomatic", "Filtlong"],
                position="early"
            ),
            WorkflowPhase(
                name="Alignment",
                description="Map reads to reference genome",
                typical_tools=["BWA", "Bowtie2", "minimap2"],
                position="middle"
            ),
            WorkflowPhase(
                name="BAM Processing",
                description="Sort, mark duplicates, index BAM files",
                typical_tools=["samtools", "Picard", "sambamba"],
                position="middle"
            ),
            WorkflowPhase(
                name="Variant Calling",
                description="Identify SNPs and indels",
                typical_tools=["GATK HaplotypeCaller", "FreeBayes", "bcftools"],
                position="late"
            ),
            WorkflowPhase(
                name="Variant Filtering",
                description="Quality filter variants",
                typical_tools=["GATK VariantFiltration", "bcftools filter", "VCFfilter"],
                position="late"
            ),
            WorkflowPhase(
                name="Variant Annotation",
                description="Annotate variant effects",
                typical_tools=["SnpEff", "VEP", "ANNOVAR"],
                required=False,
                position="late"
            )
        ],
        common_inputs=["fastq", "fastq.gz", "reference_genome", "known_variants"],
        common_outputs=["vcf", "annotated_vcf", "bam"],
        keywords=["variant", "snp", "indel", "mutation", "gatk", "bwa", "vcf",
                  "dna-seq", "whole genome", "exome", "wgs", "wes"]
    ),

    AnalysisDomain.PROTEOMICS: DomainPattern(
        domain=AnalysisDomain.PROTEOMICS,
        description="Mass spectrometry-based protein analysis",
        phases=[
            WorkflowPhase(
                name="Database Preparation",
                description="Download and prepare protein sequence database",
                typical_tools=["Protein Database Downloader", "FASTA Merge"],
                position="early"
            ),
            WorkflowPhase(
                name="Raw Data Conversion",
                description="Convert vendor format to open format",
                typical_tools=["msconvert", "ThermoRawFileParser"],
                position="early"
            ),
            WorkflowPhase(
                name="Peptide Identification",
                description="Search spectra against protein database",
                typical_tools=["SearchGUI", "MaxQuant", "MSGFPlus", "Comet"],
                position="middle"
            ),
            WorkflowPhase(
                name="Validation",
                description="Validate peptide-spectrum matches",
                typical_tools=["PeptideShaker", "Percolator"],
                position="middle"
            ),
            WorkflowPhase(
                name="Protein Quantification",
                description="Quantify protein abundances",
                typical_tools=["MaxQuant", "Progenesis", "DIA-NN"],
                position="late"
            ),
            WorkflowPhase(
                name="Statistical Analysis",
                description="Differential abundance and statistical testing",
                typical_tools=["MSstats", "limma", "Query Tabular"],
                position="late"
            ),
            WorkflowPhase(
                name="Functional Analysis",
                description="Pathway and enrichment analysis",
                typical_tools=["gProfiler", "STRING", "DAVID"],
                required=False,
                position="late"
            )
        ],
        common_inputs=["raw", "mzML", "mzXML", "fasta"],
        common_outputs=["protein_groups", "peptides", "quantification_table"],
        keywords=["proteomics", "mass spec", "protein", "peptide", "lc-ms",
                  "dia", "dda", "maxquant", "tmt", "silac"]
    ),

    AnalysisDomain.EPIGENOMICS: DomainPattern(
        domain=AnalysisDomain.EPIGENOMICS,
        description="ChIP-seq, ATAC-seq, and chromatin accessibility analysis",
        phases=[
            WorkflowPhase(
                name="Quality Control",
                description="Assess read quality and library complexity",
                typical_tools=["FastQC", "MultiQC", "ATACseqQC"],
                position="early"
            ),
            WorkflowPhase(
                name="Read Preprocessing",
                description="Trim adapters (critical for ATAC-seq)",
                typical_tools=["Cutadapt", "Trimmomatic"],
                position="early"
            ),
            WorkflowPhase(
                name="Alignment",
                description="Map reads to reference genome",
                typical_tools=["Bowtie2", "BWA"],
                position="middle"
            ),
            WorkflowPhase(
                name="BAM Filtering",
                description="Remove duplicates, filter by MAPQ, remove mitochondrial",
                typical_tools=["samtools", "MACS2 filterdup", "Picard"],
                position="middle"
            ),
            WorkflowPhase(
                name="Peak Calling",
                description="Identify enriched regions/peaks",
                typical_tools=["MACS2", "HOMER", "Genrich"],
                position="late"
            ),
            WorkflowPhase(
                name="Peak Annotation",
                description="Annotate peaks to genes/features",
                typical_tools=["ChIPseeker", "HOMER annotatePeaks", "bedtools"],
                position="late"
            ),
            WorkflowPhase(
                name="Signal Track Generation",
                description="Create bigWig for visualization",
                typical_tools=["bamCoverage", "wigToBigWig"],
                required=False,
                position="late"
            ),
            WorkflowPhase(
                name="Differential Analysis",
                description="Compare peaks between conditions",
                typical_tools=["DiffBind", "THOR", "MAnorm"],
                required=False,
                position="late"
            )
        ],
        common_inputs=["fastq", "fastq.gz", "reference_genome"],
        common_outputs=["narrowPeak", "broadPeak", "bigWig", "bed"],
        keywords=["chip-seq", "chipseq", "atac", "atac-seq", "peak", "chromatin",
                  "histone", "transcription factor", "macs", "epigenetic"]
    ),

    AnalysisDomain.METAGENOMICS: DomainPattern(
        domain=AnalysisDomain.METAGENOMICS,
        description="Microbiome and metagenomic analysis",
        phases=[
            WorkflowPhase(
                name="Quality Control",
                description="Assess read quality",
                typical_tools=["FastQC", "NanoPlot", "MultiQC"],
                position="early"
            ),
            WorkflowPhase(
                name="Read Preprocessing",
                description="Quality filter and remove host contamination",
                typical_tools=["fastp", "Trimmomatic", "Bowtie2"],
                position="early"
            ),
            WorkflowPhase(
                name="Taxonomic Classification",
                description="Identify microbial species composition",
                typical_tools=["Kraken2", "MetaPhlAn", "Centrifuge"],
                position="middle"
            ),
            WorkflowPhase(
                name="Community Profiling",
                description="Generate abundance profiles and diversity metrics",
                typical_tools=["Bracken", "MetaPhlAn", "phyloseq"],
                position="middle"
            ),
            WorkflowPhase(
                name="Assembly",
                description="Assemble metagenome contigs",
                typical_tools=["MEGAHIT", "metaSPAdes", "Flye"],
                required=False,
                position="middle"
            ),
            WorkflowPhase(
                name="Functional Annotation",
                description="Predict gene functions and metabolic pathways",
                typical_tools=["HUMAnN", "eggNOG-mapper", "KEGG"],
                required=False,
                position="late"
            ),
            WorkflowPhase(
                name="Statistical Analysis",
                description="Compare communities and identify differential features",
                typical_tools=["LEfSe", "ANCOM", "DESeq2"],
                required=False,
                position="late"
            )
        ],
        common_inputs=["fastq", "fastq.gz"],
        common_outputs=["taxonomy_profile", "abundance_table", "diversity_metrics"],
        keywords=["metagenomics", "microbiome", "16s", "shotgun", "kraken",
                  "metaphlan", "taxonomic", "community", "bacteria"]
    ),

    AnalysisDomain.DATA_QUERY: DomainPattern(
        domain=AnalysisDomain.DATA_QUERY,
        description="Database queries and data retrieval",
        phases=[
            WorkflowPhase(
                name="Query Execution",
                description="Execute database query to retrieve data",
                typical_tools=["biomate_ds_api_*", "Query UniProt", "Query PDB"],
                position="early"
            ),
            WorkflowPhase(
                name="Data Parsing",
                description="Parse and extract relevant fields from results",
                typical_tools=["jq", "Query Tabular", "Text Processing"],
                required=False,
                position="middle"
            ),
            WorkflowPhase(
                name="Data Transformation",
                description="Convert to desired format",
                typical_tools=["Convert", "Text Manipulation"],
                required=False,
                position="middle"
            ),
            WorkflowPhase(
                name="Output",
                description="Format and export results",
                typical_tools=["Text Processing", "Export"],
                required=False,
                position="late"
            )
        ],
        common_inputs=["query_parameters", "identifiers"],
        common_outputs=["json", "tabular", "fasta", "pdb"],
        keywords=["query", "search", "database", "uniprot", "pdb", "kegg",
                  "ensembl", "ncbi", "retrieve", "fetch", "download"]
    ),

    AnalysisDomain.GENERAL: DomainPattern(
        domain=AnalysisDomain.GENERAL,
        description="General bioinformatics analysis",
        phases=[
            WorkflowPhase(
                name="Data Input",
                description="Load and validate input data",
                typical_tools=["Upload", "Import"],
                position="early"
            ),
            WorkflowPhase(
                name="Quality Assessment",
                description="Check data quality",
                typical_tools=["FastQC", "MultiQC"],
                required=False,
                position="early"
            ),
            WorkflowPhase(
                name="Processing",
                description="Main analysis steps",
                typical_tools=[],
                position="middle"
            ),
            WorkflowPhase(
                name="Output Generation",
                description="Generate results and reports",
                typical_tools=["MultiQC", "Report"],
                position="late"
            )
        ],
        common_inputs=["various"],
        common_outputs=["various"],
        keywords=[]
    )
}


def detect_domain(user_intent: str, tools: List[str] = None) -> AnalysisDomain:
    """
    Detect the analysis domain from user intent and/or tool list.

    Args:
        user_intent: User's natural language description
        tools: Optional list of tool IDs/names

    Returns:
        Detected AnalysisDomain
    """
    intent_lower = user_intent.lower()

    # Score each domain by keyword matches
    scores = {}
    for domain, pattern in DOMAIN_PATTERNS.items():
        score = 0
        for keyword in pattern.keywords:
            if keyword in intent_lower:
                score += 2

        # Check tool list if provided
        if tools:
            tools_lower = ' '.join(tools).lower()
            for keyword in pattern.keywords:
                if keyword in tools_lower:
                    score += 1

        scores[domain] = score

    # Return highest scoring domain
    best_domain = max(scores, key=scores.get)

    # If no significant match, return GENERAL
    if scores[best_domain] < 2:
        return AnalysisDomain.GENERAL

    return best_domain


def get_domain_pattern(domain: AnalysisDomain) -> DomainPattern:
    """Get the workflow pattern for a domain."""
    return DOMAIN_PATTERNS.get(domain, DOMAIN_PATTERNS[AnalysisDomain.GENERAL])


def get_phases_for_domain(domain: AnalysisDomain, required_only: bool = False) -> List[WorkflowPhase]:
    """
    Get workflow phases for a domain.

    Args:
        domain: Analysis domain
        required_only: If True, return only required phases

    Returns:
        List of WorkflowPhase objects
    """
    pattern = get_domain_pattern(domain)
    if required_only:
        return [p for p in pattern.phases if p.required]
    return pattern.phases


def format_phases_for_llm(domain: AnalysisDomain) -> str:
    """
    Format domain phases for LLM prompt.

    Returns a structured string describing the phases for workflow generation.
    """
    pattern = get_domain_pattern(domain)

    lines = [
        f"## {pattern.description.upper()} WORKFLOW PHASES",
        "",
        f"Domain: {domain.value}",
        f"Expected inputs: {', '.join(pattern.common_inputs)}",
        f"Expected outputs: {', '.join(pattern.common_outputs)}",
        "",
        "### Required Phases (in order):",
    ]

    for i, phase in enumerate(pattern.phases, 1):
        if phase.required:
            tools_str = ', '.join(phase.typical_tools[:3])
            lines.append(f"{i}. **{phase.name}** ({phase.position})")
            lines.append(f"   - Purpose: {phase.description}")
            lines.append(f"   - Typical tools: {tools_str}")

    optional_phases = [p for p in pattern.phases if not p.required]
    if optional_phases:
        lines.append("")
        lines.append("### Optional Phases:")
        for phase in optional_phases:
            tools_str = ', '.join(phase.typical_tools[:3])
            lines.append(f"- **{phase.name}**: {phase.description}")
            lines.append(f"  Typical tools: {tools_str}")

    return '\n'.join(lines)


# CLI test
if __name__ == "__main__":
    # Test domain detection
    test_intents = [
        "Analyze RNA-seq data to find differentially expressed genes",
        "Call variants from whole genome sequencing data",
        "Identify proteins from mass spectrometry data",
        "Find peaks in ChIP-seq experiment",
        "Query UniProt for BRCA1 protein information",
        "Profile the microbiome composition",
    ]

    print("Domain Detection Tests:")
    print("=" * 60)
    for intent in test_intents:
        domain = detect_domain(intent)
        print(f"\nIntent: {intent}")
        print(f"Detected: {domain.value}")
        print(f"Phases: {[p.name for p in get_phases_for_domain(domain, required_only=True)]}")
