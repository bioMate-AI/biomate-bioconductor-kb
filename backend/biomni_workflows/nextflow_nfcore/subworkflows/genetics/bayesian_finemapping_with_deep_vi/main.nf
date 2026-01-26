#!/usr/bin/env nextflow
/*
 * genetics/bayesian_finemapping_with_deep_vi
 * Performs Bayesian fine-mapping from GWAS summary statistics using deep variational inference.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gwas_summary_path = null
params.ld_matrix = null
params.n_iterations = '5000'
params.learning_rate = '0.01'
params.hidden_dim = '64'
params.credible_threshold = '0.95'

process BAYESIAN_FINEMAPPING_WITH_DEEP_VI {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("bayesian_finemapping_with_deep_vi_results.json"), emit: results
    tuple val(meta), path("bayesian_finemapping_with_deep_vi_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GWAS_SUMMARY_PATH="${params.gwas_summary_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LD_MATRIX="${params.ld_matrix?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N_ITERATIONS="${params.n_iterations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LEARNING_RATE="${params.learning_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_HIDDEN_DIM="${params.hidden_dim?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CREDIBLE_THRESHOLD="${params.credible_threshold?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
from datetime import datetime
from torch import optim
import torch
from torch import nn
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



def bayesian_finemapping_with_deep_vi(
    gwas_summary_path,
    ld_matrix,
    n_iterations=5000,
    learning_rate=0.01,
    hidden_dim=64,
    credible_threshold=0.95,
):
    '''Performs Bayesian fine-mapping from GWAS summary statistics using deep variational inference.

    This function implements a deep neural network-based variational inference approach to compute
    posterior inclusion probabilities (PIPs) and credible sets for putative causal variants from
    GWAS summary statistics and linkage disequilibrium (LD) information.

    Parameters
    ----------
    gwas_summary_path : str
        Path to CSV or TSV file containing GWAS summary statistics. Expected columns:
        - 'variant_id': Identifier for each variant
        - 'effect_size': Effect size (beta) for each variant
        - 'pvalue': P-value for each variant
        - 'se': Standard error for each variant (optional)

    ld_matrix : numpy.ndarray
        Linkage disequilibrium matrix with pairwise correlations between variants.

    n_iterations : int, optional
        Number of training iterations for the variational inference algorithm.
        Default is 5000.

    learning_rate : float, optional
        Learning rate for the optimization algorithm. Default is 0.01.

    hidden_dim : int, optional
        Hidden dimension size for the neural network. Default is 64.

    credible_threshold : float, optional
        Threshold for defining the credible set (e.g., 0.95 for a 95% credible set).
        Default is 0.95.

    Returns
    -------
    str
        A detailed research log of the fine-mapping analysis including:
        - Number of variants analyzed
        - Top variants ranked by posterior inclusion probability
        - Credible set variants
        - Visualizations of the posterior distributions

    '''
    import matplotlib.pyplot as plt
    import pandas as pd

    # Initialize the research log
    log = []
    log.append(
        f"# Bayesian Fine-mapping Analysis with Deep Variational Inference - {datetime.now().strftime('%Y-%m-%d %H:%M')}"
    )
    log.append("\\n## Data Preprocessing")

    # Load data from file
    try:
        if gwas_summary_path.endswith(".csv"):
            gwas_summary = pd.read_csv(gwas_summary_path)
        elif gwas_summary_path.endswith((".tsv", ".txt")):
            gwas_summary = pd.read_csv(gwas_summary_path, sep="\\t")
        else:
            log.append("Error: Unsupported file format. Please provide a CSV or TSV file.")
            return "\\n".join(log)
        log.append(f"Successfully loaded GWAS summary data from {gwas_summary_path}")
    except Exception as e:
        log.append(f"Error loading GWAS summary data: {str(e)}")
        return "\\n".join(log)

    # Check input data
    if gwas_summary is None:
        log.append("Error: Failed to load GWAS summary data.")
        return "\\n".join(log)

    if ld_matrix is None:
        log.append("Error: LD matrix is required for fine-mapping analysis.")
        return "\\n".join(log)

    n_variants = len(gwas_summary)
    log.append(f"Analyzing {n_variants} genetic variants")

    # Check if LD matrix dimensions match the number of variants
    if ld_matrix.shape[0] != n_variants or ld_matrix.shape[1] != n_variants:
        log.append(f"Error: LD matrix dimensions ({ld_matrix.shape}) do not match number of variants ({n_variants})")
        return "\\n".join(log)

    # Prepare data for analysis
    log.append("\\nPreparing data for analysis...")

    # Compute Z-scores if not already present
    if "z_score" not in gwas_summary.columns:
        log.append("Computing Z-scores from effect sizes and standard errors...")
        if "se" in gwas_summary.columns:
            gwas_summary["z_score"] = gwas_summary["effect_size"] / gwas_summary["se"]
        else:
            # Approximate Z-scores from p-values
            log.append("Standard errors not available, approximating Z-scores from p-values...")
            # Convert p-values to Z-scores (two-sided test)
            from scipy.stats import norm

            gwas_summary["z_score"] = (
                gwas_summary["effect_size"].abs()
                / gwas_summary["effect_size"]
                * norm.ppf(1 - gwas_summary["pvalue"] / 2)
            )

    # Convert data to tensors
    z_scores = torch.FloatTensor(gwas_summary["z_score"].values)
    ld_tensor = torch.FloatTensor(ld_matrix)

    log.append(f"Processed {len(z_scores)} z-scores from GWAS summary")
    log.append("LD matrix shape: " + str(ld_matrix.shape))

    # Define the variational inference model
    class VariationalFineMapping(nn.Module):
        def __init__(self, n_variants, hidden_dim):
            super().__init__()
            self.encoder = nn.Sequential(
                nn.Linear(n_variants, hidden_dim),
                nn.ReLU(),
                nn.Linear(hidden_dim, hidden_dim),
                nn.ReLU(),
            )
            # Output log alpha parameters for the Bernoulli variables
            self.log_alpha = nn.Linear(hidden_dim, n_variants)

        def forward(self, x):
            h = self.encoder(x)
            log_alpha = self.log_alpha(h)
            # Apply sigmoid to get inclusion probabilities
            return torch.sigmoid(log_alpha)

        def elbo_loss(self, z_scores, ld_matrix, pips, n_samples=10):
            # Sample from approximate posterior
            samples = torch.bernoulli(pips.unsqueeze(0).repeat(n_samples, 1))

            # Prior term (sparsity prior)
            prior_term = -0.01 * torch.sum(pips)

            # Likelihood term
            likelihood_term = 0
            for s in samples:
                # Compute expected z-scores under the model
                expected_z = torch.matmul(ld_matrix, s * z_scores)
                # Compute likelihood
                likelihood_term += -torch.sum((z_scores - expected_z) ** 2)

            likelihood_term /= n_samples

            return -(prior_term + likelihood_term)

    # Initialize model, optimizer and training
    log.append("\\n## Initializing deep variational inference model")
    model = VariationalFineMapping(n_variants, hidden_dim)
    optimizer = optim.Adam(model.parameters(), lr=learning_rate)

    # Training loop
    log.append("\\n## Training variational inference model")
    losses = []

    for i in range(n_iterations):
        optimizer.zero_grad()
        pips = model(z_scores)
        loss = model.elbo_loss(z_scores, ld_tensor, pips)
        loss.backward()
        optimizer.step()

        losses.append(loss.item())

        if (i + 1) % (n_iterations // 5) == 0:
            log.append(f"  Iteration {i + 1}/{n_iterations}, Loss: {loss.item():.4f}")

    # Get final posterior inclusion probabilities
    with torch.no_grad():
        final_pips = model(z_scores).numpy()

    # Create DataFrame with results
    results_df = gwas_summary.copy()
    results_df["pip"] = final_pips
    results_df = results_df.sort_values("pip", ascending=False)

    # Generate credible sets
    log.append("\\n## Generating credible sets")

    # Sort variants by PIP
    sorted_variants = results_df.sort_values("pip", ascending=False)

    # Calculate cumulative sum of PIPs
    sorted_variants["cumulative_pip"] = sorted_variants["pip"].cumsum()

    # Identify variants in the credible set
    credible_set = sorted_variants[sorted_variants["cumulative_pip"] <= credible_threshold]

    if len(credible_set) == 0:
        # If no variants meet the threshold, include at least the top variant
        credible_set = sorted_variants.iloc[:1]

    log.append(f"Identified {len(credible_set)} variants in the {credible_threshold * 100}% credible set")

    # Save results to files
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = f"finemapping_results_{timestamp}.csv"
    credible_set_file = f"credible_set_{timestamp}.csv"

    results_df.to_csv(results_file, index=False)
    credible_set.to_csv(credible_set_file, index=False)

    log.append(f"\\nFull results saved to: {results_file}")
    log.append(f"Credible set saved to: {credible_set_file}")

    # Summary of top variants
    log.append("\\n## Top variants by posterior inclusion probability (PIP)")
    for i, (_, row) in enumerate(results_df.head(10).iterrows()):
        log.append(f"  {i + 1}. Variant: {row['variant_id']}, PIP: {row['pip']:.4f}, P-value: {row['pvalue']:.2e}")

    log.append("\\n## Variants in the credible set")
    for i, (_, row) in enumerate(credible_set.iterrows()):
        log.append(f"  {i + 1}. Variant: {row['variant_id']}, PIP: {row['pip']:.4f}")

    # Create a simple visualization
    try:
        plt.figure(figsize=(10, 6))
        plt.bar(range(len(results_df[:50])), results_df["pip"][:50])
        plt.xlabel("Variant index (sorted by PIP)")
        plt.ylabel("Posterior Inclusion Probability")
        plt.title("Top 50 variants by PIP")
        plot_file = f"pip_plot_{timestamp}.png"
        plt.savefig(plot_file)
        plt.close()
        log.append(f"\\nPlot of PIPs saved to: {plot_file}")
    except Exception as e:
        log.append(f"\\nCould not create visualization: {str(e)}")

    log.append("\\n## Analysis complete")

    return "\\n".join(log)

# Execute the function
try:
    result = bayesian_finemapping_with_deep_vi(
        gwas_summary_path=auto_convert(os.environ.get("PARAM_GWAS_SUMMARY_PATH", "")),
        ld_matrix=auto_convert(os.environ.get("PARAM_LD_MATRIX", "")),
        n_iterations=auto_convert(os.environ.get("PARAM_N_ITERATIONS", "5000")),
        learning_rate=auto_convert(os.environ.get("PARAM_LEARNING_RATE", "0.01")),
        hidden_dim=auto_convert(os.environ.get("PARAM_HIDDEN_DIM", "64")),
        credible_threshold=auto_convert(os.environ.get("PARAM_CREDIBLE_THRESHOLD", "0.95")),
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
    "function": "bayesian_finemapping_with_deep_vi",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("bayesian_finemapping_with_deep_vi_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("bayesian_finemapping_with_deep_vi_output.txt", "w") as f:
    f.write("Biomni: Bayesian Finemapping With Deep Vi" + NL)
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
        biomni_function: "bayesian_finemapping_with_deep_vi"
    END_VERSIONS
    """
}

workflow BAYESIAN_FINEMAPPING_WITH_DEEP_VI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    BAYESIAN_FINEMAPPING_WITH_DEEP_VI(ch_input)

    emit:
    results = BAYESIAN_FINEMAPPING_WITH_DEEP_VI.out.results
    output = BAYESIAN_FINEMAPPING_WITH_DEEP_VI.out.output
    versions = BAYESIAN_FINEMAPPING_WITH_DEEP_VI.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    BAYESIAN_FINEMAPPING_WITH_DEEP_VI_WORKFLOW(ch_input)

    BAYESIAN_FINEMAPPING_WITH_DEEP_VI_WORKFLOW.out.output.view { "Output: $it" }
}
