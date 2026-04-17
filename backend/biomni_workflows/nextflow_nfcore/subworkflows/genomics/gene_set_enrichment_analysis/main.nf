#!/usr/bin/env nextflow
/*
 * genomics/gene_set_enrichment_analysis
 * Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: List of cell cycle related genes
params.genes = '["CCNA2", "CCNB1", "CDK1", "CDK2", "TP53", "RB1", "E2F1", "PCNA", "MCM2", "CDC6"]'
params.top_k = 10
params.database = 'ontology'
params.background_list = null
params.plot = 'false'

process GENE_SET_ENRICHMENT_ANALYSIS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("gene_set_enrichment_analysis_results.json"), emit: results
    tuple val(meta), path("gene_set_enrichment_analysis_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENES="${params.genes?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TOP_K="${params.top_k?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATABASE="${params.database?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BACKGROUND_LIST="${params.background_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PLOT="${params.plot?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import gget
import json
import os

def auto_convert(val):
    # Auto-convert string to appropriate type
    if val is None or val == '' or val == 'null':
        return None
    # Try bool
    if isinstance(val, str) and val.lower() in ('true', 'false'):
        return val.lower() == 'true'
    # Try JSON for lists and dicts
    if isinstance(val, str) and val.strip().startswith(('[', '{')):
        try:
            return json.loads(val)
        except json.JSONDecodeError:
            pass
    # Try int
    try:
        if isinstance(val, str) and '.' not in val:
            return int(val)
    except ValueError:
        pass
    # Try float
    try:
        return float(val)
    except ValueError:
        pass
    # Return as string
    return val



def gene_set_enrichment_analysis(
    genes: list,
    top_k: int = 10,
    database: str = "ontology",
    background_list: list = None,
    plot: bool = False,
) -> str:
    '''Perform enrichment analysis for a list of genes, with optional background gene set and plotting functionality.

    Parameters
    ----------
    - genes (list): List of gene symbols to analyze.
    - top_k (int): Number of top pathways to return. Default is 10.
    - database (str): User-friendly name of the database to use for enrichment analysis.
        Popular options include:
        - 'pathway'      (KEGG_2021_Human)
        - 'transcription'   (ChEA_2016)
        - 'ontology'     (GO_Biological_Process_2021)
        - 'diseases_drugs'  (GWAS_Catalog_2019)
        - 'celltypes'     (PanglaoDB_Augmented_2021)
        - 'kinase_interactions' (KEA_2015)
        You can use get_gene_set_enrichment_analysis_supported_database_list tool to get the list of supported databases.

    - background_list (list, optional): List of background genes to use for enrichment analysis.
    - plot (bool, optional): If True, generates a bar plot of the top K enrichment results.

    Returns
    -------
    - str: The steps performed and the top K enrichment results.

    '''
    steps_log = (
        f"Starting enrichment analysis for genes: {', '.join(genes)} using {database} database and top_k: {top_k}\\n"
    )

    if background_list:
        steps_log += f"Using background list with {len(background_list)} genes.\\n"

    try:
        # Perform enrichment analysis with or without background list
        steps_log += f"Performing enrichment analysis using gget.enrichr with the {database} database...\\n"
        df = gget.enrichr(genes, database=database, background_list=background_list, plot=plot)

        # Limit to top K results
        steps_log += f"Filtering the top {top_k} enrichment results...\\n"
        df = df.head(top_k)

        # Format the result
        output_str = ""
        for _idx, row in df.iterrows():
            output_str += (
                f"Rank: {row['rank']}\\n"
                f"Path Name: {row['path_name']}\\n"
                f"P-value: {row['p_val']:.2e}\\n"
                f"Z-score: {row['z_score']:.6f}\\n"
                f"Combined Score: {row['combined_score']:.6f}\\n"
                f"Overlapping Genes: {', '.join(row['overlapping_genes'])}\\n"
                f"Adjusted P-value: {row['adj_p_val']:.2e}\\n"
                f"Database: {row['database']}\\n"
                "----------------------------------------\\n"
            )

        steps_log += output_str

        return steps_log

    except Exception as e:
        return f"An error occurred: {e}"

# Execute the function
try:
    result = gene_set_enrichment_analysis(
        genes=auto_convert(os.environ.get("PARAM_GENES", "")),
        top_k=auto_convert(os.environ.get("PARAM_TOP_K", "10")),
        database=auto_convert(os.environ.get("PARAM_DATABASE", "ontology")),
        background_list=auto_convert(os.environ.get("PARAM_BACKGROUND_LIST", "")),
        plot=auto_convert(os.environ.get("PARAM_PLOT", "")),
    )
    success = True
    error_msg = None
except Exception as e:
    result = None
    success = False
    error_msg = str(e)

# Save results
output_data = {
    "success": success,
    "function": "gene_set_enrichment_analysis",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("gene_set_enrichment_analysis_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("gene_set_enrichment_analysis_output.txt", "w") as f:
    f.write("Biomni: Gene Set Enrichment Analysis" + NL)
    f.write("=" * 60 + NL + NL)
    if success:
        if isinstance(result, str):
            f.write(result)
        elif isinstance(result, dict):
            for key, value in result.items():
                f.write(f"{key}: {value}" + NL)
        else:
            f.write(str(result))
    else:
        f.write(f"ERROR: {error_msg}" + NL)

if not success:
    exit(1)
PYEOF

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        python: \$(python3 --version | cut -d' ' -f2)
        biomni_function: "gene_set_enrichment_analysis"
    END_VERSIONS
    """
}

workflow GENE_SET_ENRICHMENT_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GENE_SET_ENRICHMENT_ANALYSIS(ch_input)

    emit:
    results = GENE_SET_ENRICHMENT_ANALYSIS.out.results
    output = GENE_SET_ENRICHMENT_ANALYSIS.out.output
    versions = GENE_SET_ENRICHMENT_ANALYSIS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GENE_SET_ENRICHMENT_ANALYSIS_WORKFLOW(ch_input)

    GENE_SET_ENRICHMENT_ANALYSIS_WORKFLOW.out.output.view { "Output: $it" }
}
