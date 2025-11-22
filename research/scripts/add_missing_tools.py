#!/usr/bin/env python3
"""
Add missing tools to the Galaxy AI tools database.

Adds built-in Galaxy tools and custom tools that are referenced in workflows.
"""

import json
import sqlite3
from datetime import datetime

DB_PATH = "/home/yzhang/biomate/backend/database/galaxy_ai_tools.db"
OUTPUT_DIR = "/home/yzhang/biomate/research"


def get_missing_tools():
    """Define missing tools that need to be added."""

    # Galaxy built-in collection tools
    builtin_collection = [
        {
            'tool_id': '__APPLY_RULES__',
            'name': 'Apply Rules',
            'description': 'Apply rules to transform and restructure collections',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__BUILD_LIST__',
            'name': 'Build List',
            'description': 'Build a list collection from individual datasets',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__EXTRACT_DATASET__',
            'name': 'Extract Dataset',
            'description': 'Extract a dataset from a collection',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__FILTER_EMPTY_DATASETS__',
            'name': 'Filter Empty Datasets',
            'description': 'Remove empty datasets from a collection',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__FILTER_FAILED_DATASETS__',
            'name': 'Filter Failed Datasets',
            'description': 'Remove failed datasets from a collection',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__FILTER_FROM_FILE__',
            'name': 'Filter from File',
            'description': 'Filter collection elements based on a file',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__FLATTEN__',
            'name': 'Flatten Collection',
            'description': 'Flatten nested collections into a single list',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__HARMONIZELISTS__',
            'name': 'Harmonize Lists',
            'description': 'Ensure multiple lists have matching elements',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__MERGE_COLLECTION__',
            'name': 'Merge Collections',
            'description': 'Merge multiple collections into one',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__RELABEL_FROM_FILE__',
            'name': 'Relabel from File',
            'description': 'Relabel collection elements based on a mapping file',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__SORTLIST__',
            'name': 'Sort List',
            'description': 'Sort collection elements',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__UNZIP_COLLECTION__',
            'name': 'Unzip Collection',
            'description': 'Split paired collection into separate lists',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__ZIP_COLLECTION__',
            'name': 'Zip Collections',
            'description': 'Combine two lists into a paired collection',
            'category': 'Collection Operations'
        },
        {
            'tool_id': '__DUPLICATE_FILE_TO_COLLECTION__',
            'name': 'Duplicate to Collection',
            'description': 'Create collection by duplicating a dataset',
            'category': 'Collection Operations'
        },
    ]

    # Galaxy built-in text tools
    builtin_text = [
        {
            'tool_id': 'Convert characters1',
            'name': 'Convert Characters',
            'description': 'Convert delimiters and special characters in text files',
            'category': 'Text Manipulation'
        },
        {
            'tool_id': 'Grouping1',
            'name': 'Group',
            'description': 'Group data by a column and perform aggregate operations',
            'category': 'Text Manipulation'
        },
        {
            'tool_id': 'Remove beginning1',
            'name': 'Remove Beginning',
            'description': 'Remove lines from the beginning of a file',
            'category': 'Text Manipulation'
        },
        {
            'tool_id': 'Show beginning1',
            'name': 'Show Beginning',
            'description': 'Show the first lines of a file (head)',
            'category': 'Text Manipulation'
        },
        {
            'tool_id': 'Show tail1',
            'name': 'Show Tail',
            'description': 'Show the last lines of a file (tail)',
            'category': 'Text Manipulation'
        },
        {
            'tool_id': 'wc_gnu',
            'name': 'Word Count',
            'description': 'Count lines, words, and characters in text',
            'category': 'Text Manipulation'
        },
        {
            'tool_id': 'param_value_from_file',
            'name': 'Parameter from File',
            'description': 'Extract parameter value from a file',
            'category': 'Utilities'
        },
    ]

    # Converters
    converters = [
        {
            'tool_id': 'CONVERTER_gz_to_uncompressed',
            'name': 'Decompress GZ',
            'description': 'Decompress gzip compressed file',
            'category': 'Convert Formats'
        },
        {
            'tool_id': 'CONVERTER_uncompressed_to_gz',
            'name': 'Compress to GZ',
            'description': 'Compress file with gzip',
            'category': 'Convert Formats'
        },
    ]

    # nf-core custom tools
    nfcore_tools = [
        {
            'tool_id': 'nfcore_check_config',
            'name': 'nf-core Check Config',
            'description': 'Validate nf-core pipeline configuration',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nfcore_check_profile',
            'name': 'nf-core Check Profile',
            'description': 'Validate nf-core execution profile',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nf_schema_params_help',
            'name': 'nf-schema Params Help',
            'description': 'Display parameter help from nf-schema',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nf_schema_params_summary_log',
            'name': 'nf-schema Params Summary',
            'description': 'Generate parameter summary log',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nf_schema_validate_parameters',
            'name': 'nf-schema Validate Params',
            'description': 'Validate parameters against nf-schema',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nf_validation_dummy_emit',
            'name': 'nf-validation Dummy Emit',
            'description': 'Emit dummy output for validation',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nf_validation_params_help',
            'name': 'nf-validation Params Help',
            'description': 'Display validation parameter help',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nf_validation_params_summary_log',
            'name': 'nf-validation Summary',
            'description': 'Generate validation summary log',
            'category': 'nf-core Utilities'
        },
        {
            'tool_id': 'nf_validation_validate_parameters',
            'name': 'nf-validation Validate',
            'description': 'Validate pipeline parameters',
            'category': 'nf-core Utilities'
        },
    ]

    # Bioinformatics tools from various sources
    bio_tools = [
        {
            'tool_id': 'angsd_contamination',
            'name': 'ANGSD Contamination',
            'description': 'Estimate contamination in sequencing data',
            'category': 'Population Genetics'
        },
        {
            'tool_id': 'angsd_docounts',
            'name': 'ANGSD doCounts',
            'description': 'Count alleles at each position',
            'category': 'Population Genetics'
        },
        {
            'tool_id': 'bwamem2_mem',
            'name': 'BWA-MEM2',
            'description': 'Fast sequence aligner using BWA-MEM2 algorithm',
            'category': 'Mapping'
        },
        {
            'tool_id': 'deacon_filter',
            'name': 'DEACON Filter',
            'description': 'Filter deaminated sequences',
            'category': 'Ancient DNA'
        },
        {
            'tool_id': 'deacon_index',
            'name': 'DEACON Index',
            'description': 'Index reference for DEACON',
            'category': 'Ancient DNA'
        },
        {
            'tool_id': 'dragmap_align',
            'name': 'DRAGMAP Align',
            'description': 'Align reads using DRAGEN mapper',
            'category': 'Mapping'
        },
        {
            'tool_id': 'ensemblvep_filtervep',
            'name': 'VEP Filter',
            'description': 'Filter Ensembl VEP output',
            'category': 'Variant Annotation'
        },
        {
            'tool_id': 'ensemblvep_vep',
            'name': 'Ensembl VEP',
            'description': 'Annotate variants with Ensembl VEP',
            'category': 'Variant Annotation'
        },
        {
            'tool_id': 'mirtop_counts',
            'name': 'mirtop Counts',
            'description': 'Generate miRNA counts from GFF',
            'category': 'Small RNA'
        },
        {
            'tool_id': 'mirtop_export',
            'name': 'mirtop Export',
            'description': 'Export miRNA annotations',
            'category': 'Small RNA'
        },
        {
            'tool_id': 'mirtop_gff',
            'name': 'mirtop GFF',
            'description': 'Convert to mirtop GFF format',
            'category': 'Small RNA'
        },
        {
            'tool_id': 'mirtop_stats',
            'name': 'mirtop Stats',
            'description': 'Generate miRNA statistics',
            'category': 'Small RNA'
        },
        {
            'tool_id': 'ngscheckmate_fastq',
            'name': 'NGSCheckMate FASTQ',
            'description': 'Check sample identity from FASTQ',
            'category': 'Quality Control'
        },
        {
            'tool_id': 'ngscheckmate_vafncm',
            'name': 'NGSCheckMate VAF',
            'description': 'Check sample identity from VAF',
            'category': 'Quality Control'
        },
        {
            'tool_id': 'somalier_extract',
            'name': 'Somalier Extract',
            'description': 'Extract sites for sample comparison',
            'category': 'Quality Control'
        },
        {
            'tool_id': 'somalier_relate',
            'name': 'Somalier Relate',
            'description': 'Calculate relatedness between samples',
            'category': 'Quality Control'
        },
        {
            'tool_id': 'rastair_call',
            'name': 'RASTA-IR Call',
            'description': 'Call methylation from IR data',
            'category': 'Methylation'
        },
        {
            'tool_id': 'rastair_mbias',
            'name': 'RASTA-IR Mbias',
            'description': 'Calculate methylation bias',
            'category': 'Methylation'
        },
        {
            'tool_id': 'rastair_mbiasparser',
            'name': 'RASTA-IR Mbias Parser',
            'description': 'Parse methylation bias results',
            'category': 'Methylation'
        },
        {
            'tool_id': 'rastair_methylkit',
            'name': 'RASTA-IR MethylKit',
            'description': 'Convert to MethylKit format',
            'category': 'Methylation'
        },
        {
            'tool_id': 'quantmsutils_diann2mztab',
            'name': 'QuantMS DIA-NN to mzTab',
            'description': 'Convert DIA-NN output to mzTab',
            'category': 'Proteomics'
        },
        {
            'tool_id': 'quantmsutils_dianncfg',
            'name': 'QuantMS DIA-NN Config',
            'description': 'Configure DIA-NN parameters',
            'category': 'Proteomics'
        },
        {
            'tool_id': 'quantmsutils_mzmlstatistics',
            'name': 'QuantMS mzML Statistics',
            'description': 'Calculate mzML file statistics',
            'category': 'Proteomics'
        },
        {
            'tool_id': 'vizgenpostprocessing_compiletilesegmentation',
            'name': 'Vizgen Compile Segmentation',
            'description': 'Compile tile segmentation results',
            'category': 'Spatial Transcriptomics'
        },
        {
            'tool_id': 'vizgenpostprocessing_preparesegmentation',
            'name': 'Vizgen Prepare Segmentation',
            'description': 'Prepare data for segmentation',
            'category': 'Spatial Transcriptomics'
        },
        {
            'tool_id': 'vizgenpostprocessing_runsegmentationontile',
            'name': 'Vizgen Run Segmentation',
            'description': 'Run segmentation on tiles',
            'category': 'Spatial Transcriptomics'
        },
    ]

    # Galaxy workflow utilities
    workflow_utils = [
        {
            'tool_id': 'expression_tools',
            'name': 'Expression Tools',
            'description': 'Evaluate expressions in workflows',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_Merge_Collections',
            'name': 'Merge Collections',
            'description': 'Merge multiple collections',
            'category': 'Collection Operations'
        },
        {
            'tool_id': 'galaxy_merge_collections',
            'name': 'Merge Collections',
            'description': 'Merge multiple collections',
            'category': 'Collection Operations'
        },
        {
            'tool_id': 'galaxy_conditional_check_conda',
            'name': 'Check Conda',
            'description': 'Check Conda environment',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_conditional_dump_parameters',
            'name': 'Dump Parameters',
            'description': 'Dump workflow parameters',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_conditional_print_version',
            'name': 'Print Version',
            'description': 'Print tool version',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_get_references_file',
            'name': 'Get Reference File',
            'description': 'Get reference file path',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_get_references_value',
            'name': 'Get Reference Value',
            'description': 'Get reference value',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_tool_collect',
            'name': 'Collect Outputs',
            'description': 'Collect tool outputs',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_tool_combine',
            'name': 'Combine Outputs',
            'description': 'Combine multiple outputs',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_tool_id_placeholder_for_transpose',
            'name': 'Transpose Placeholder',
            'description': 'Placeholder for transpose operation',
            'category': 'Utilities'
        },
        {
            'tool_id': 'galaxy_workflow_output',
            'name': 'Workflow Output',
            'description': 'Mark workflow output',
            'category': 'Utilities'
        },
    ]

    # Combine all
    all_tools = (
        builtin_collection +
        builtin_text +
        converters +
        nfcore_tools +
        bio_tools +
        workflow_utils
    )

    return all_tools


def add_tools_to_database(tools):
    """Add tools to the database."""

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    added = 0
    skipped = 0

    for tool in tools:
        try:
            # Check if already exists
            cursor.execute("SELECT id FROM tools WHERE tool_id = ?", (tool['tool_id'],))
            if cursor.fetchone():
                skipped += 1
                continue

            # Insert new tool
            cursor.execute("""
                INSERT INTO tools (tool_id, name, description, category, created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, (
                tool['tool_id'],
                tool['name'],
                tool['description'],
                tool['category'],
                datetime.now().isoformat(),
                datetime.now().isoformat()
            ))
            added += 1

        except Exception as e:
            print(f"Error adding {tool['tool_id']}: {e}")

    conn.commit()
    conn.close()

    return added, skipped


def main():
    print("=" * 60)
    print("Adding Missing Tools to Database")
    print("=" * 60)
    print()

    # Get missing tools
    tools = get_missing_tools()
    print(f"Defined {len(tools)} tools to add")

    # Add to database
    added, skipped = add_tools_to_database(tools)

    print(f"\nResults:")
    print(f"  Added: {added}")
    print(f"  Skipped (already exist): {skipped}")

    # Generate report
    timestamp = datetime.now().strftime("%Y%m%d_%H%M")
    report_path = f"{OUTPUT_DIR}/{timestamp}_TOOLS_ADDED_REPORT.md"

    with open(report_path, 'w') as f:
        f.write("# Missing Tools Added to Database\n\n")
        f.write(f"**Date:** {datetime.now().strftime('%Y-%m-%d %H:%M')}\n")
        f.write(f"**Total defined:** {len(tools)}\n")
        f.write(f"**Added:** {added}\n")
        f.write(f"**Skipped:** {skipped}\n\n")

        f.write("## Tools by Category\n\n")

        # Group by category
        by_category = {}
        for tool in tools:
            cat = tool['category']
            if cat not in by_category:
                by_category[cat] = []
            by_category[cat].append(tool)

        for category in sorted(by_category.keys()):
            f.write(f"### {category}\n\n")
            for tool in by_category[category]:
                f.write(f"- `{tool['tool_id']}` - {tool['name']}\n")
            f.write("\n")

    print(f"\nReport saved to: {report_path}")


if __name__ == "__main__":
    main()
