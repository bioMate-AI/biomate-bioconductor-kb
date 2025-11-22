#!/usr/bin/env python3
"""
Add missing ToolShed tools to the database.
"""

import json
import sqlite3
import re
from datetime import datetime

DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"

# Missing ToolShed tools from the validation report
MISSING_TOOLS = [
    "toolshed.g2.bx.psu.edu/repos/bgruening/mgnify_seqprep/mgnify_seqprep/1.2+galaxy0",
    "toolshed.g2.bx.psu.edu/repos/devteam/bwa_index/bwa_index",
    "toolshed.g2.bx.psu.edu/repos/devteam/bwamem2/bwamem2_index",
    "toolshed.g2.bx.psu.edu/repos/devteam/fasta_compute_length/fasta_compute_length/1.0.4",
    "toolshed.g2.bx.psu.edu/repos/devteam/fasta_filter_by_length/fasta_filter_by_length/1.2",
    "toolshed.g2.bx.psu.edu/repos/devteam/samtools_index/samtools_index",
    "toolshed.g2.bx.psu.edu/repos/devteam/tabular_to_fasta/tab2fasta/1.1.1",
    "toolshed.g2.bx.psu.edu/repos/galaxy-australia/tidk/tidk_explore",
    "toolshed.g2.bx.psu.edu/repos/galaxy-australia/tidk/tidk_plot",
    "toolshed.g2.bx.psu.edu/repos/galaxy-australia/tidk/tidk_search",
    "toolshed.g2.bx.psu.edu/repos/galaxy-iuc/join/join1",
    "toolshed.g2.bx.psu.edu/repos/iuc/bcftools_annotate/bcftools_annotate/1.10",
    "toolshed.g2.bx.psu.edu/repos/iuc/bcftools_annotate/bcftools_annotate/1.15.1+galaxy4",
    "toolshed.g2.bx.psu.edu/repos/iuc/bcftools_consensus/bcftools_consensus/1.15.1+galaxy4",
    "toolshed.g2.bx.psu.edu/repos/iuc/bcftools_index/bcftools_index",
    "toolshed.g2.bx.psu.edu/repos/iuc/bcftools_norm/bcftools_norm/1.15.1+galaxy4",
    "toolshed.g2.bx.psu.edu/repos/iuc/bwamem2_index/bwamem2_index",
    "toolshed.g2.bx.psu.edu/repos/iuc/cellbender_removebackground/cellbender_removebackground",
    "toolshed.g2.bx.psu.edu/repos/iuc/dragmap/dragmap_hashtable",
    "toolshed.g2.bx.psu.edu/repos/iuc/glimpse2_chunk/glimpse2_chunk",
    "toolshed.g2.bx.psu.edu/repos/iuc/glimpse2_ligate/glimpse2_ligate",
    "toolshed.g2.bx.psu.edu/repos/iuc/glimpse2_phase/glimpse2_phase",
    "toolshed.g2.bx.psu.edu/repos/iuc/glimpse2_splitreference/glimpse2_splitreference",
    "toolshed.g2.bx.psu.edu/repos/iuc/glimpse_chunk/glimpse_chunk",
    "toolshed.g2.bx.psu.edu/repos/iuc/glimpse_ligate/glimpse_ligate",
    "toolshed.g2.bx.psu.edu/repos/iuc/glimpse_phase/glimpse_phase",
    "toolshed.g2.bx.psu.edu/repos/iuc/gprofiler2_gost/gprofiler2_gost",
    "toolshed.g2.bx.psu.edu/repos/iuc/propr/Repository_Actions_propr",
    "toolshed.g2.bx.psu.edu/repos/iuc/propr_grea/propr_grea",
    "toolshed.g2.bx.psu.edu/repos/iuc/samtools_fastq/samtools_fastq",
    "toolshed.g2.bx.psu.edu/repos/iuc/sratools_fasterqdump/sratools_fasterqdump",
    "toolshed.g2.bx.psu.edu/repos/iuc/sratools_prefetch/sratools_prefetch",
    "toolshed.g2.bx.psu.edu/repos/iuc/umitools_dedup/umitools_dedup",
    "toolshed.g2.bx.psu.edu/repos/iuc/umitools_extract/Repository_Actions_umitools_extract",
    "toolshed.g2.bx.psu.edu/repos/iuc/variancepartition/Repository_Actions_variancepartition",
    "toolshed.g2.bx.psu.edu/repos/jjohnson/fgbio_call_duplex_consensus_reads/Repository_Actions_fgbio_CallDuplexConsensusReads",
    "toolshed.g2.bx.psu.edu/repos/jjohnson/fgbio_filter_consensus_reads/Repository_Actions_fgbio_FilterConsensusReads",
    "toolshed.g2.bx.psu.edu/repos/jjohnson/fgbio_zip_bams/Repository_Actions_fgbio_ZipperBams",
    "toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_fillpeaks/abims_xcms_fillPeaks/3.12.0+galaxy3",
    "toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_group/abims_xcms_group/3.12.0+galaxy3",
    "toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_retcor/abims_xcms_retcor/3.12.0+galaxy3",
    "toolshed.g2.bx.psu.edu/repos/lecorguille/xcms_xcmsset/abims_xcms_xcmsSet/3.12.0+galaxy3",
    "toolshed.g2.bx.psu.edu/repos/nf-core/chromap/chromap",
    "toolshed.g2.bx.psu.edu/repos/nf-core/fcs/fcsadaptor/main",
    "toolshed.g2.bx.psu.edu/repos/nf-core/fcsgx/rungx/main",
    "toolshed.g2.bx.psu.edu/repos/nf-core/nf_core_utils/combine_and_map_metadata",
    "toolshed.g2.bx.psu.edu/repos/nf-core/nf_schema/nf_schema_samplesheet_to_list/0.1.0",
    "toolshed.g2.bx.psu.edu/repos/nf-core/ngscheckmate_ncm/ngscheckmate_ncm",
    "toolshed.g2.bx.psu.edu/repos/nvidia/parabricks/parabricks_fq2bammeth",
    "toolshed.g2.bx.psu.edu/repos/shapeit/shapeit5/shapeit5_ligate",
    "toolshed.g2.bx.psu.edu/repos/shapeit/shapeit5/shapeit5_phasecommon",
]

# Tool metadata
TOOL_INFO = {
    'mgnify_seqprep': ('SeqPrep', 'Merge paired-end reads', 'Read Processing'),
    'bwa_index': ('BWA Index', 'Build BWA index for reference genome', 'Mapping'),
    'bwamem2_index': ('BWA-MEM2 Index', 'Build BWA-MEM2 index', 'Mapping'),
    'fasta_compute_length': ('FASTA Length', 'Compute length of sequences', 'FASTA/FASTQ'),
    'fasta_filter_by_length': ('FASTA Filter', 'Filter sequences by length', 'FASTA/FASTQ'),
    'samtools_index': ('SAMtools Index', 'Index BAM/SAM file', 'SAM/BAM'),
    'tab2fasta': ('Tabular to FASTA', 'Convert tabular to FASTA format', 'Convert Formats'),
    'tidk_explore': ('TIDK Explore', 'Explore telomere sequences', 'Genome Assembly'),
    'tidk_plot': ('TIDK Plot', 'Plot telomere distribution', 'Genome Assembly'),
    'tidk_search': ('TIDK Search', 'Search for telomere motifs', 'Genome Assembly'),
    'join1': ('Join', 'Join two datasets on a common column', 'Text Manipulation'),
    'bcftools_annotate': ('BCFtools Annotate', 'Annotate VCF/BCF files', 'Variant Calling'),
    'bcftools_consensus': ('BCFtools Consensus', 'Generate consensus sequence', 'Variant Calling'),
    'bcftools_index': ('BCFtools Index', 'Index VCF/BCF files', 'Variant Calling'),
    'bcftools_norm': ('BCFtools Norm', 'Normalize VCF/BCF files', 'Variant Calling'),
    'cellbender_removebackground': ('CellBender', 'Remove ambient RNA background', 'Single-cell'),
    'dragmap_hashtable': ('DRAGMAP Hashtable', 'Build DRAGMAP hash table', 'Mapping'),
    'glimpse_chunk': ('GLIMPSE Chunk', 'Chunk regions for imputation', 'Imputation'),
    'glimpse_ligate': ('GLIMPSE Ligate', 'Ligate imputed chunks', 'Imputation'),
    'glimpse_phase': ('GLIMPSE Phase', 'Phase and impute genotypes', 'Imputation'),
    'glimpse2_chunk': ('GLIMPSE2 Chunk', 'Chunk regions for imputation', 'Imputation'),
    'glimpse2_ligate': ('GLIMPSE2 Ligate', 'Ligate imputed chunks', 'Imputation'),
    'glimpse2_phase': ('GLIMPSE2 Phase', 'Phase and impute genotypes', 'Imputation'),
    'glimpse2_splitreference': ('GLIMPSE2 Split Reference', 'Split reference panel', 'Imputation'),
    'gprofiler2_gost': ('g:Profiler', 'Gene ontology enrichment analysis', 'Functional Analysis'),
    'propr': ('propr', 'Calculate proportionality', 'Statistics'),
    'propr_grea': ('propr GREA', 'Gene ratio enrichment analysis', 'Functional Analysis'),
    'samtools_fastq': ('SAMtools FASTQ', 'Convert BAM to FASTQ', 'SAM/BAM'),
    'sratools_fasterqdump': ('fasterq-dump', 'Download SRA data (fast)', 'Data Source'),
    'sratools_prefetch': ('prefetch', 'Prefetch SRA data', 'Data Source'),
    'umitools_dedup': ('UMI-tools Dedup', 'Deduplicate by UMI', 'UMI Processing'),
    'umitools_extract': ('UMI-tools Extract', 'Extract UMI from reads', 'UMI Processing'),
    'variancepartition': ('variancePartition', 'Partition variance in expression', 'RNA-seq'),
    'fgbio_CallDuplexConsensusReads': ('fgbio Call Duplex', 'Call duplex consensus reads', 'UMI Processing'),
    'fgbio_FilterConsensusReads': ('fgbio Filter Consensus', 'Filter consensus reads', 'UMI Processing'),
    'fgbio_ZipperBams': ('fgbio ZipperBams', 'Interleave BAM files', 'SAM/BAM'),
    'xcms_fillPeaks': ('XCMS fillPeaks', 'Fill missing peaks', 'Metabolomics'),
    'xcms_group': ('XCMS Group', 'Group peaks across samples', 'Metabolomics'),
    'xcms_retcor': ('XCMS Retention Correction', 'Correct retention time', 'Metabolomics'),
    'xcms_xcmsSet': ('XCMS Peak Detection', 'Detect peaks in MS data', 'Metabolomics'),
    'chromap': ('Chromap', 'Fast chromatin mapping', 'Epigenetics'),
    'fcsadaptor': ('FCS Adaptor', 'FCS adaptor detection', 'Genome Assembly'),
    'rungx': ('FCS-GX', 'Contamination detection', 'Genome Assembly'),
    'combine_and_map_metadata': ('Combine Metadata', 'Combine and map metadata', 'Utilities'),
    'nf_schema_samplesheet_to_list': ('Samplesheet to List', 'Convert samplesheet to list', 'Utilities'),
    'ngscheckmate_ncm': ('NGSCheckMate NCM', 'Sample identity check', 'Quality Control'),
    'parabricks_fq2bammeth': ('Parabricks Methylation', 'GPU-accelerated methylation calling', 'Methylation'),
    'shapeit5_ligate': ('SHAPEIT5 Ligate', 'Ligate phased segments', 'Phasing'),
    'shapeit5_phasecommon': ('SHAPEIT5 Phase Common', 'Phase common variants', 'Phasing'),
}


def parse_tool_id(tool_id):
    """Parse ToolShed tool ID to extract components."""
    match = re.match(
        r'toolshed\.g2\.bx\.psu\.edu/repos/([^/]+)/([^/]+)/([^/]+)(?:/(.+))?',
        tool_id
    )
    if match:
        owner, repo, tool_name, version = match.groups()
        return owner, repo, tool_name, version
    return None, None, None, None


def get_tool_info(tool_id):
    """Get tool metadata based on tool name."""
    _, _, tool_name, version = parse_tool_id(tool_id)

    if not tool_name:
        return None

    # Check if we have info for this tool
    for key, (name, desc, category) in TOOL_INFO.items():
        if key in tool_name.lower() or tool_name.lower() in key:
            return name, desc, category, version

    # Default
    return tool_name, f"Galaxy ToolShed tool: {tool_name}", "ToolShed Tools", version


def main():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    added = 0
    skipped = 0

    for tool_id in MISSING_TOOLS:
        # Check if exists
        cursor.execute("SELECT id FROM tools WHERE tool_id = ?", (tool_id,))
        if cursor.fetchone():
            skipped += 1
            continue

        info = get_tool_info(tool_id)
        if not info:
            print(f"Could not parse: {tool_id}")
            continue

        name, description, category, version = info

        try:
            cursor.execute("""
                INSERT INTO tools (tool_id, name, description, category, version, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """, (
                tool_id,
                name,
                description,
                category,
                version or '',
                datetime.now().isoformat(),
                datetime.now().isoformat()
            ))
            added += 1
        except Exception as e:
            print(f"Error adding {tool_id}: {e}")

    conn.commit()
    conn.close()

    print(f"Added: {added}")
    print(f"Skipped: {skipped}")
    print(f"Total tools now in database: {9289 + added}")


if __name__ == "__main__":
    main()
