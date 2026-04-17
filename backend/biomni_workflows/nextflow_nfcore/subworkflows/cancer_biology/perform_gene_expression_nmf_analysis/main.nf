#!/usr/bin/env nextflow
/*
 * cancer_biology/perform_gene_expression_nmf_analysis
 * Performs Non-negative Matrix Factorization (NMF) on gene expression data to extract
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Use inline mock CSV data for NMF analysis
// Expression data: genes (rows) x samples (columns) with non-negative values
params.expression_data_path = 'INLINE_MOCK_NMF'
params.n_components = '5'
params.normalize = 'True'
params.output_dir = 'nmf_results'
params.random_state = '42'

process PERFORM_GENE_EXPRESSION_NMF_ANALYSIS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_gene_expression_nmf_analysis_results.json"), emit: results
    tuple val(meta), path("perform_gene_expression_nmf_analysis_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_EXPRESSION_DATA_PATH="${params.expression_data_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N_COMPONENTS="${params.n_components?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NORMALIZE="${params.normalize?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RANDOM_STATE="${params.random_state?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def perform_gene_expression_nmf_analysis(
    expression_data_path,
    n_components=10,
    normalize=True,
    output_dir="nmf_results",
    random_state=42,
):
    '''Performs Non-negative Matrix Factorization (NMF) on gene expression data to extract
    metagenes and their associated sample weights for tumor subtype identification.

    Parameters
    ----------
    expression_data_path : str
        Path to a CSV or TSV file containing gene expression data with genes as rows and samples as columns.
        Values should be non-negative (e.g., normalized counts or expression values).
    n_components : int, default=10
        Number of metagenes (components) to extract.
    normalize : bool, default=True
        Whether to normalize the expression data before applying NMF.
    output_dir : str, default="nmf_results"
        Directory to save the output files.
    random_state : int, default=42
        Random seed for reproducibility.

    Returns
    -------
    str
        Research log summarizing the analysis steps and results.

    '''
    import os
    from datetime import datetime

    import numpy as np
    import pandas as pd
    from sklearn.decomposition import NMF

    # Start research log
    log = []
    log.append(f"NMF GENE EXPRESSION ANALYSIS - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append(f"Parameters: n_components={n_components}, normalize={normalize}")

    # Load expression data from file
    try:
        # Check for inline mock data mode
        if expression_data_path == 'INLINE_MOCK_NMF':
            # Generate mock expression data for NMF demonstration
            np.random.seed(random_state if random_state else 42)

            # Create mock gene expression data with cancer-related genes
            cancer_genes = [
                "TP53", "BRCA1", "BRCA2", "KRAS", "EGFR", "MYC", "PTEN", "RB1",
                "APC", "VHL", "NF1", "NF2", "WT1", "RET", "CDH1", "STK11",
                "SMAD4", "CDKN2A", "MLH1", "MSH2", "PIK3CA", "BRAF", "NRAS",
                "KIT", "PDGFRA", "FGFR1", "FGFR2", "FGFR3", "ALK", "ROS1",
                "MET", "HER2", "AR", "ESR1", "PGR", "BCL2", "BCL6", "MYD88",
                "NOTCH1", "NOTCH2", "JAK2", "MPL", "CALR", "NPM1", "FLT3",
                "DNMT3A", "TET2", "IDH1", "IDH2", "EZH2"
            ]
            samples = ["Sample_" + str(i) for i in range(1, 31)]  # 30 samples

            # Create 5 distinct expression patterns (metagenes)
            n_genes = len(cancer_genes)
            n_samples = len(samples)

            # Base expression with some structure
            W_true = np.random.exponential(1.0, size=(n_genes, 5))
            H_true = np.random.exponential(1.0, size=(5, n_samples))
            X = np.dot(W_true, H_true) + np.random.exponential(0.5, size=(n_genes, n_samples))

            expression_data = pd.DataFrame(X, index=cancer_genes, columns=samples)
            log.append("Using inline mock expression data for demonstration")
            log.append(f"Generated {n_genes} genes x {n_samples} samples")
        elif expression_data_path.endswith(".csv"):
            expression_data = pd.read_csv(expression_data_path, index_col=0)
        elif expression_data_path.endswith((".tsv", ".txt")):
            expression_data = pd.read_csv(expression_data_path, sep="\\t", index_col=0)
        else:
            log.append("ERROR: Unsupported file format. Please provide a CSV or TSV file.")
            return "\\n".join(log)

        if expression_data_path != 'INLINE_MOCK_NMF':
            log.append(f"Successfully loaded expression data from {expression_data_path}")
    except Exception as e:
        log.append(f"ERROR: Failed to load expression data from {expression_data_path}. Error: {str(e)}")
        return "\\n".join(log)

    # Extract gene and sample information
    genes = expression_data.index.tolist()
    samples = expression_data.columns.tolist()
    X = expression_data.values
    log.append(f"Input data: {len(genes)} genes × {len(samples)} samples")

    # Check for non-negative values
    if np.any(X < 0):
        log.append("WARNING: Negative values found in expression data. Converting to absolute values.")
        X = np.abs(X)

    # Normalize data if requested
    if normalize:
        log.append("Normalizing expression data...")
        X = X / np.sum(X, axis=0, keepdims=True) * 1000  # TPM-like normalization

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        log.append(f"Created output directory: {output_dir}")

    # Apply NMF
    log.append(f"Applying NMF to extract {n_components} metagenes...")
    model = NMF(
        n_components=n_components,
        init="random",
        random_state=random_state,
        max_iter=1000,
    )

    try:
        # W: metagenes (genes × components)
        # H: sample weights (components × samples)
        W = model.fit_transform(X)
        H = model.components_

        log.append(f"NMF completed successfully in {model.n_iter_} iterations")
        log.append(f"Explained variance: {model.reconstruction_err_:.4f}")

        # Save metagenes (W matrix)
        metagenes_file = os.path.join(output_dir, "metagenes.csv")
        pd.DataFrame(W, index=genes, columns=[f"Metagene_{i + 1}" for i in range(n_components)]).to_csv(metagenes_file)
        log.append(f"Saved metagenes to {metagenes_file}")

        # Save sample weights (H matrix)
        weights_file = os.path.join(output_dir, "sample_weights.csv")
        pd.DataFrame(H, index=[f"Metagene_{i + 1}" for i in range(n_components)], columns=samples).to_csv(weights_file)
        log.append(f"Saved sample weights to {weights_file}")

        top_genes_file = os.path.join(output_dir, "top_genes_per_metagene.csv")
        top_genes = {}
        for i in range(n_components):
            # Get indices of top 20 genes for this metagene
            top_indices = np.argsort(W[:, i])[::-1][:20]
            top_genes[f"Metagene_{i + 1}"] = [genes[idx] for idx in top_indices]

        pd.DataFrame(top_genes).to_csv(top_genes_file)
        log.append(f"Saved top genes per metagene to {top_genes_file}")

    except Exception as e:
        log.append(f"ERROR: NMF failed with error: {str(e)}")
        return "\\n".join(log)

    log.append("\\nSUMMARY:")
    log.append(f"- Successfully extracted {n_components} metagenes from {X.shape[0]} genes across {X.shape[1]} samples")
    log.append(f"- Results saved to: {output_dir}")
    log.append("- Files generated: metagenes.csv, sample_weights.csv, top_genes_per_metagene.csv")
    log.append("\\nNEXT STEPS:")
    log.append("- Analyze the metagenes to identify biological pathways")
    log.append("- Cluster samples based on metagene weights to identify potential tumor subtypes")
    log.append("- Correlate subtypes with clinical outcomes if available")

    return "\\n".join(log)

# Execute the function
try:
    result = perform_gene_expression_nmf_analysis(
        expression_data_path=auto_convert(os.environ.get("PARAM_EXPRESSION_DATA_PATH", "")),
        n_components=auto_convert(os.environ.get("PARAM_N_COMPONENTS", "10")),
        normalize=auto_convert(os.environ.get("PARAM_NORMALIZE", "True")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "nmf_results")),
        random_state=auto_convert(os.environ.get("PARAM_RANDOM_STATE", "42")),
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
    "function": "perform_gene_expression_nmf_analysis",
    "domain": "cancer_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_gene_expression_nmf_analysis_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_gene_expression_nmf_analysis_output.txt", "w") as f:
    f.write("Biomni: Perform Gene Expression Nmf Analysis" + NL)
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
        biomni_function: "perform_gene_expression_nmf_analysis"
    END_VERSIONS
    """
}

workflow PERFORM_GENE_EXPRESSION_NMF_ANALYSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_GENE_EXPRESSION_NMF_ANALYSIS(ch_input)

    emit:
    results = PERFORM_GENE_EXPRESSION_NMF_ANALYSIS.out.results
    output = PERFORM_GENE_EXPRESSION_NMF_ANALYSIS.out.output
    versions = PERFORM_GENE_EXPRESSION_NMF_ANALYSIS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_GENE_EXPRESSION_NMF_ANALYSIS_WORKFLOW(ch_input)

    PERFORM_GENE_EXPRESSION_NMF_ANALYSIS_WORKFLOW.out.output.view { "Output: $it" }
}
