#!/usr/bin/env nextflow
/*
 * cancer_biology/analyze_ddr_network_in_cancer
 * Analyze DNA Damage Response (DDR) network alterations and dependencies in cancer samples.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Expression data: genes (rows) x samples (columns) with DDR pathway genes
params.expression_data_path = null
// Mutation data: genes (rows) x samples (columns) with mutation status (0/1)
params.mutation_data_path = null
params.output_dir = './results'

process ANALYZE_DDR_NETWORK_IN_CANCER {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_ddr_network_in_cancer_results.json"), emit: results
    tuple val(meta), path("analyze_ddr_network_in_cancer_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_EXPRESSION_DATA_PATH="${params.expression_data_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MUTATION_DATA_PATH="${params.mutation_data_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

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



def analyze_ddr_network_in_cancer(expression_data_path, mutation_data_path, output_dir="./results"):
    '''Analyze DNA Damage Response (DDR) network alterations and dependencies in cancer samples.

    This function reconstructs the DDR network from genomic data, identifies disruptions
    in the network, and analyzes dependencies between DDR pathway components in cancer.

    Parameters
    ----------
    expression_data_path : str
        Path to gene expression data file (CSV format with genes as rows, samples as columns)
    mutation_data_path : str
        Path to mutation data file (CSV format with genes as rows, samples as columns,
        values indicating mutation status)
    output_dir : str, optional
        Directory to save output files (default: "./results")

    Returns
    -------
    str
        Research log summarizing the DDR network analysis, findings about disruptions,
        and potential therapeutic vulnerabilities

    '''
    import os
    from datetime import datetime

    import gseapy as gp
    import networkx as nx
    import pandas as pd
    from scipy.stats import pearsonr

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    research_log = f"DDR Network Analysis Research Log - {datetime.now().strftime('%Y-%m-%d %H:%M')}\\n"
    research_log += "=" * 80 + "\\n\\n"

    # Step 1: Load and preprocess genomic data
    research_log += "STEP 1: Loading and preprocessing genomic data\\n"

    try:
        if not expression_data_path:
            raise ValueError("expression_data_path is required: path to gene expression CSV (genes x samples)")
        if not mutation_data_path:
            raise ValueError("mutation_data_path is required: path to mutation status CSV (genes x samples, values 0/1)")

        expr_data = pd.read_csv(expression_data_path, index_col=0)
        mut_data = pd.read_csv(mutation_data_path, index_col=0)

        research_log += f"- Loaded expression data: {expr_data.shape[0]} genes × {expr_data.shape[1]} samples\\n"
        research_log += f"- Loaded mutation data: {mut_data.shape[0]} genes × {mut_data.shape[1]} samples\\n"

        # Define core DDR genes (based on literature)
        ddr_genes = [
            # DNA damage sensors
            "ATM",
            "ATR",
            "PRKDC",
            "RAD50",
            "MRE11",
            "NBN",
            # Signal transducers
            "CHEK1",
            "CHEK2",
            "TP53",
            "BRCA1",
            "BRCA2",
            "MDC1",
            "H2AX",
            # Effectors - Homologous Recombination
            "RAD51",
            "RAD52",
            "PALB2",
            "RAD54L",
            # Effectors - Non-Homologous End Joining
            "XRCC4",
            "LIG4",
            "XRCC5",
            "XRCC6",
            # Effectors - Base Excision Repair
            "PARP1",
            "APEX1",
            "OGG1",
            "XRCC1",
            # Effectors - Nucleotide Excision Repair
            "XPA",
            "XPC",
            "ERCC1",
            "ERCC2",
            "ERCC3",
            "ERCC4",
            "ERCC5",
            # Effectors - Mismatch Repair
            "MLH1",
            "MSH2",
            "MSH6",
            "PMS2",
        ]

        # Filter expression and mutation data for DDR genes
        ddr_expr = expr_data.loc[expr_data.index.isin(ddr_genes)]
        ddr_mut = mut_data.loc[mut_data.index.isin(ddr_genes)]

        research_log += f"- Filtered data for {len(ddr_genes)} DDR pathway genes\\n"
        research_log += f"- Found {ddr_expr.shape[0]} DDR genes in expression data\\n"
        research_log += f"- Found {ddr_mut.shape[0]} DDR genes in mutation data\\n\\n"

    except Exception as e:
        research_log += f"Error in data loading: {str(e)}\\n\\n"
        return research_log

    # Step 2: Network reconstruction
    research_log += "STEP 2: Reconstructing DDR gene network\\n"

    # Create correlation-based network
    G = nx.Graph()

    # Add nodes (genes)
    for gene in ddr_expr.index:
        # Add node with mutation frequency information
        mutation_freq = ddr_mut.loc[gene].mean() if gene in ddr_mut.index else 0

        G.add_node(gene, mutation_freq=mutation_freq)

    # Add edges based on gene expression correlation
    for i, gene1 in enumerate(ddr_expr.index):
        for gene2 in ddr_expr.index[i + 1 :]:
            corr, p_value = pearsonr(ddr_expr.loc[gene1], ddr_expr.loc[gene2])
            if abs(corr) > 0.4 and p_value < 0.05:  # Significant correlation threshold
                G.add_edge(gene1, gene2, weight=abs(corr), correlation=corr)

    research_log += f"- Constructed network with {G.number_of_nodes()} nodes and {G.number_of_edges()} edges\\n"

    # Save network for visualization
    network_file = os.path.join(output_dir, "ddr_network.graphml")
    nx.write_graphml(G, network_file)
    research_log += f"- Network saved to: {network_file}\\n\\n"

    # Step 3: Network analysis
    research_log += "STEP 3: Analyzing DDR network properties\\n"

    # Calculate network centrality measures
    degree_centrality = nx.degree_centrality(G)
    betweenness_centrality = nx.betweenness_centrality(G)

    # Identify hub genes (high degree centrality)
    hub_genes = sorted(degree_centrality.items(), key=lambda x: x[1], reverse=True)[:5]

    research_log += "- Top 5 hub genes (highest connectivity):\\n"
    for gene, centrality in hub_genes:
        research_log += f"  * {gene}: {centrality:.4f}\\n"

    # Identify bottleneck genes (high betweenness centrality)
    bottleneck_genes = sorted(betweenness_centrality.items(), key=lambda x: x[1], reverse=True)[:5]

    research_log += "- Top 5 bottleneck genes (critical for information flow):\\n"
    for gene, centrality in bottleneck_genes:
        research_log += f"  * {gene}: {centrality:.4f}\\n"

    # Identify frequently mutated DDR genes
    mutation_freq = {node: G.nodes[node]["mutation_freq"] for node in G.nodes()}
    frequently_mutated = sorted(mutation_freq.items(), key=lambda x: x[1], reverse=True)[:5]

    research_log += "- Top 5 frequently mutated DDR genes:\\n"
    for gene, freq in frequently_mutated:
        research_log += f"  * {gene}: {freq:.4f}\\n\\n"

    # Step 4: Community detection to identify DDR sub-pathways
    research_log += "STEP 4: Identifying DDR sub-pathways through community detection\\n"

    # Use Louvain method for community detection
    try:
        from community import best_partition

        partition = best_partition(G)
        communities = {}
        for node, community_id in partition.items():
            if community_id not in communities:
                communities[community_id] = []
            communities[community_id].append(node)

        research_log += f"- Identified {len(communities)} DDR sub-pathways\\n"

        for i, (_, genes) in enumerate(communities.items()):
            research_log += f"  * Sub-pathway {i + 1}: {', '.join(genes)}\\n"

    except ImportError:
        research_log += "- Community detection skipped (python-louvain package not installed)\\n"

    # Step 5: Identify disrupted DDR pathways using GSEA
    research_log += "\\nSTEP 5: Pathway enrichment analysis of DDR genes\\n"

    try:
        # Create gene list for GSEA
        gene_list = ddr_expr.mean(axis=1).sort_values(ascending=False)

        # Run GSEA with GO Biological Process
        enrichr_results = gp.enrichr(
            gene_list=gene_list.index.tolist(),
            gene_sets=["GO_Biological_Process_2021"],
            outdir=os.path.join(output_dir, "enrichr_output"),
            cutoff=0.5,
        )

        # Filter for DNA repair related terms
        ddr_terms = [
            term
            for term in enrichr_results.results["Term"]
            if any(x in term.lower() for x in ["dna repair", "damage", "recombination", "checkpoint"])
        ]

        if ddr_terms:
            research_log += "- Enriched DDR-related pathways:\\n"
            for term in ddr_terms[:5]:  # Top 5 DDR-related terms
                research_log += f"  * {term}\\n"
        else:
            research_log += "- No significant DDR pathway enrichment found\\n"

        # Save full enrichment results
        enrichment_file = os.path.join(output_dir, "ddr_pathway_enrichment.csv")
        enrichr_results.results.to_csv(enrichment_file)
        research_log += f"- Full enrichment results saved to: {enrichment_file}\\n\\n"

    except Exception as e:
        research_log += f"- Pathway enrichment analysis error: {str(e)}\\n\\n"

    # Step 6: Summary of findings
    research_log += "SUMMARY OF FINDINGS\\n"
    research_log += "=" * 80 + "\\n"

    # Key hub genes (potential therapeutic targets)
    research_log += "1. Key DDR hub genes that may serve as potential therapeutic targets:\\n"
    for gene, _ in hub_genes[:3]:
        research_log += f"   - {gene}\\n"

    # Frequently mutated genes
    research_log += "\\n2. Frequently mutated DDR genes in the samples:\\n"
    for gene, freq in frequently_mutated[:3]:
        research_log += f"   - {gene} (mutation frequency: {freq:.2%})\\n"

    # Network structure insights
    research_log += "\\n3. DDR network structure insights:\\n"
    research_log += f"   - Network density: {nx.density(G):.4f}\\n"

    try:
        avg_clustering = nx.average_clustering(G)
        research_log += f"   - Average clustering coefficient: {avg_clustering:.4f}\\n"
    except Exception:
        pass

    research_log += "\\n4. Potential DDR dependencies and synthetic lethality targets:\\n"
    # Identify potential synthetic lethality pairs (genes with high correlation and one is frequently mutated)
    synthetic_lethality_candidates = []
    for gene1, gene2, data in G.edges(data=True):
        if abs(data["correlation"]) > 0.6:  # Strong correlation
            mut_freq1 = G.nodes[gene1]["mutation_freq"]
            mut_freq2 = G.nodes[gene2]["mutation_freq"]
            if (mut_freq1 > 0.1 and mut_freq2 < 0.05) or (mut_freq2 > 0.1 and mut_freq1 < 0.05):
                if mut_freq1 > mut_freq2:
                    synthetic_lethality_candidates.append((gene1, gene2, data["correlation"], mut_freq1))
                else:
                    synthetic_lethality_candidates.append((gene2, gene1, data["correlation"], mut_freq2))

    if synthetic_lethality_candidates:
        for mutated, target, _, _ in sorted(synthetic_lethality_candidates, key=lambda x: x[3], reverse=True)[:3]:
            research_log += f"   - {mutated} (frequently mutated) and {target} (potential dependency)\\n"
    else:
        research_log += "   - No strong synthetic lethality candidates identified\\n"

    return research_log

# Execute the function
try:
    result = analyze_ddr_network_in_cancer(
        expression_data_path=auto_convert(os.environ.get("PARAM_EXPRESSION_DATA_PATH", "")),
        mutation_data_path=auto_convert(os.environ.get("PARAM_MUTATION_DATA_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
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
    "function": "analyze_ddr_network_in_cancer",
    "domain": "cancer_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_ddr_network_in_cancer_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_ddr_network_in_cancer_output.txt", "w") as f:
    f.write("Biomni: Analyze Ddr Network In Cancer" + NL)
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
        biomni_function: "analyze_ddr_network_in_cancer"
    END_VERSIONS
    """
}

workflow ANALYZE_DDR_NETWORK_IN_CANCER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_DDR_NETWORK_IN_CANCER(ch_input)

    emit:
    results = ANALYZE_DDR_NETWORK_IN_CANCER.out.results
    output = ANALYZE_DDR_NETWORK_IN_CANCER.out.output
    versions = ANALYZE_DDR_NETWORK_IN_CANCER.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_DDR_NETWORK_IN_CANCER_WORKFLOW(ch_input)

    ANALYZE_DDR_NETWORK_IN_CANCER_WORKFLOW.out.output.view { "Output: $it" }
}
