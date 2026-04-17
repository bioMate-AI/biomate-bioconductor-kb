#!/usr/bin/env nextflow
/*
 * genetics/fit_genomic_prediction_model
 * Fit a linear mixed model for genomic prediction using genotype and phenotype data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Small genotype matrix (5 individuals x 10 SNPs) with phenotypes
params.genotypes = '[[0, 1, 2, 0, 1, 0, 2, 1, 0, 1], [1, 0, 1, 2, 0, 1, 1, 0, 2, 0], [2, 1, 0, 1, 2, 0, 0, 1, 1, 2], [0, 2, 1, 0, 1, 2, 1, 2, 0, 1], [1, 1, 2, 1, 0, 1, 2, 0, 1, 0]]'
params.phenotypes = '[15.2, 18.7, 12.3, 20.1, 16.5]'
params.fixed_effects = null
params.model_type = 'additive'
params.output_file = 'genomic_prediction_results.csv'

process FIT_GENOMIC_PREDICTION_MODEL {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("fit_genomic_prediction_model_results.json"), emit: results
    tuple val(meta), path("fit_genomic_prediction_model_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GENOTYPES="${params.genotypes?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PHENOTYPES="${params.phenotypes?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FIXED_EFFECTS="${params.fixed_effects?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
import numpy as np
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



def fit_genomic_prediction_model(
    genotypes,
    phenotypes,
    fixed_effects=None,
    model_type="additive",
    output_file="genomic_prediction_results.csv",
):
    '''Fit a linear mixed model for genomic prediction using genotype and phenotype data.

    Parameters
    ----------
    genotypes : numpy.ndarray
        Matrix of genotype data, with individuals in rows and markers in columns.
        Values are typically coded as 0, 1, 2 for additive models or with specific
        encoding for dominance effects.
    phenotypes : numpy.ndarray
        Vector or matrix of phenotype data, with individuals in rows and traits in columns.
    fixed_effects : numpy.ndarray, optional
        Matrix of fixed effects (e.g., environment, management), with individuals in rows
        and effects in columns.
    model_type : str, optional
        Type of genetic model to fit: "additive" or "additive_dominance".
    output_file : str, optional
        File name to save the results.

    Returns
    -------
    str
        Research log summarizing the genomic prediction analysis, including model parameters,
        variance components, breeding values, and prediction accuracy metrics.

    '''
    import pandas as pd
    from scipy import linalg

    # Convert inputs to numpy arrays if they are lists
    genotypes = np.array(genotypes)
    phenotypes = np.array(phenotypes)
    if fixed_effects is not None:
        fixed_effects = np.array(fixed_effects)

    # Initialize research log
    log = "# Multi-trait Genomic Prediction Analysis\\n\\n"
    log += f"Model type: {model_type}\\n"

    # Basic validation
    n_individuals, n_markers = genotypes.shape
    n_pheno, n_traits = (phenotypes.shape[0], 1) if phenotypes.ndim == 1 else phenotypes.shape

    if n_individuals != n_pheno:
        raise ValueError(f"Number of individuals in genotypes ({n_individuals}) and phenotypes ({n_pheno}) don't match")

    log += f"Number of individuals: {n_individuals}\\n"
    log += f"Number of markers: {n_markers}\\n"
    log += f"Number of traits: {n_traits}\\n\\n"

    # Ensure phenotypes is 2D
    if phenotypes.ndim == 1:
        phenotypes = phenotypes.reshape(-1, 1)

    # Center genotypes (common preprocessing step)
    genotypes_centered = genotypes - np.mean(genotypes, axis=0)

    # Create genomic relationship matrix (G)
    if model_type == "additive":
        # Additive genomic relationship matrix
        G = np.dot(genotypes_centered, genotypes_centered.T) / n_markers
        log += "Constructed additive genomic relationship matrix (G)\\n\\n"
    elif model_type == "additive_dominance":
        # For additive-dominance model, we need both A (additive) and D (dominance) matrices
        # Assuming genotypes are coded as {0,1,2} for {aa,Aa,AA}
        # Create dominance matrix - simple implementation assuming standard coding
        dom_genotypes = np.zeros_like(genotypes)
        # Code heterozygotes (1) as 1, homozygotes (0,2) as 0 for dominance effects
        dom_genotypes[genotypes == 1] = 1
        dom_genotypes_centered = dom_genotypes - np.mean(dom_genotypes, axis=0)

        # Additive and dominance matrices
        G_a = np.dot(genotypes_centered, genotypes_centered.T) / n_markers
        G_d = np.dot(dom_genotypes_centered, dom_genotypes_centered.T) / n_markers
        log += "Constructed additive (G_a) and dominance (G_d) genomic relationship matrices\\n\\n"
    else:
        raise ValueError(f"Unknown model type: {model_type}")

    # Initialize results storage
    trait_results = []

    # Fit model for each trait
    for trait_idx in range(n_traits):
        trait_phenotypes = phenotypes[:, trait_idx]
        log += f"## Trait {trait_idx + 1} Analysis\\n\\n"

        # Handle fixed effects if provided
        if fixed_effects is not None:
            # Simple fixed effects adjustment - more complex models would use proper mixed model fitting
            X = fixed_effects
            # Fit fixed effects model
            beta = np.linalg.lstsq(X, trait_phenotypes, rcond=None)[0]
            # Adjust phenotypes for fixed effects
            y_adj = trait_phenotypes - X @ beta
            log += f"Applied adjustment for {X.shape[1]} fixed effects\\n"
        else:
            y_adj = trait_phenotypes
            log += "No fixed effects provided\\n"

        # Fit mixed model
        if model_type == "additive":
            # Simplified REML estimation for variance components
            # In practice, specialized libraries like pyGWAS, GCTA or R's ASReml would be used

            # Initial variance component estimates
            var_g_init = np.var(y_adj) * 0.5  # genetic variance
            var_e_init = np.var(y_adj) * 0.5  # residual variance

            # Simple EM-like algorithm for variance component estimation
            # (In practice, use dedicated software for proper REML)
            for _ in range(5):  # Few iterations for demonstration
                # Construct mixed model equations
                V = var_g_init * G + var_e_init * np.eye(n_individuals)
                V_inv = linalg.inv(V)

                # Update variance components
                P = V_inv - V_inv @ np.ones((n_individuals, 1)) @ np.ones((1, n_individuals)) @ V_inv / (
                    np.ones((1, n_individuals)) @ V_inv @ np.ones((n_individuals, 1))
                )
                var_g_new = (y_adj.T @ P @ G @ P @ y_adj) / np.trace(P @ G)
                var_e_new = (y_adj.T @ P @ P @ y_adj) / np.trace(P)

                # Update estimates
                var_g_init = max(0.01, var_g_new)
                var_e_init = max(0.01, var_e_new)

            # Final variance components
            var_g = var_g_init
            var_e = var_e_init

            # Calculate heritability
            heritability = var_g / (var_g + var_e)

            # BLUP solutions for breeding values
            V = var_g * G + var_e * np.eye(n_individuals)
            V_inv = linalg.inv(V)
            breeding_values = var_g * G @ V_inv @ y_adj

            # Predicted phenotypes
            predicted_phenotypes = breeding_values

            # Calculate accuracy
            accuracy = np.corrcoef(trait_phenotypes, predicted_phenotypes)[0, 1]

            # Log results
            log += f"Estimated additive genetic variance: {var_g:.4f}\\n"
            log += f"Estimated residual variance: {var_e:.4f}\\n"
            log += f"Estimated heritability: {heritability:.4f}\\n"
            log += f"Prediction accuracy (correlation): {accuracy:.4f}\\n\\n"

            # Store results
            trait_result = {
                "trait": trait_idx + 1,
                "var_g": var_g,
                "var_e": var_e,
                "heritability": heritability,
                "accuracy": accuracy,
                "breeding_values": breeding_values,
                "predicted_phenotypes": predicted_phenotypes,
            }
            trait_results.append(trait_result)

        elif model_type == "additive_dominance":
            # Similar approach but with both additive and dominance effects
            # Initial variance component estimates
            var_a_init = np.var(y_adj) * 0.4  # additive variance
            var_d_init = np.var(y_adj) * 0.1  # dominance variance
            var_e_init = np.var(y_adj) * 0.5  # residual variance

            # Simple estimation iterations
            for _ in range(5):  # Few iterations for demonstration
                # Construct mixed model equations
                V = var_a_init * G_a + var_d_init * G_d + var_e_init * np.eye(n_individuals)
                V_inv = linalg.inv(V)

                # Update variance components (simplified)
                P = V_inv - V_inv @ np.ones((n_individuals, 1)) @ np.ones((1, n_individuals)) @ V_inv / (
                    np.ones((1, n_individuals)) @ V_inv @ np.ones((n_individuals, 1))
                )
                var_a_new = (y_adj.T @ P @ G_a @ P @ y_adj) / np.trace(P @ G_a)
                var_d_new = (y_adj.T @ P @ G_d @ P @ y_adj) / np.trace(P @ G_d)
                var_e_new = (y_adj.T @ P @ P @ y_adj) / np.trace(P)

                # Update estimates
                var_a_init = max(0.01, var_a_new)
                var_d_init = max(0.01, var_d_new)
                var_e_init = max(0.01, var_e_new)

            # Final variance components
            var_a = var_a_init
            var_d = var_d_init
            var_e = var_e_init

            # Calculate heritabilities
            narrow_heritability = var_a / (var_a + var_d + var_e)
            broad_heritability = (var_a + var_d) / (var_a + var_d + var_e)

            # BLUP solutions for breeding values and dominance deviations
            V = var_a * G_a + var_d * G_d + var_e * np.eye(n_individuals)
            V_inv = linalg.inv(V)
            breeding_values = var_a * G_a @ V_inv @ y_adj
            dominance_deviations = var_d * G_d @ V_inv @ y_adj

            # Predicted phenotypes
            predicted_phenotypes = breeding_values + dominance_deviations

            # Calculate accuracy
            accuracy = np.corrcoef(trait_phenotypes, predicted_phenotypes)[0, 1]

            # Log results
            log += f"Estimated additive genetic variance: {var_a:.4f}\\n"
            log += f"Estimated dominance genetic variance: {var_d:.4f}\\n"
            log += f"Estimated residual variance: {var_e:.4f}\\n"
            log += f"Estimated narrow-sense heritability: {narrow_heritability:.4f}\\n"
            log += f"Estimated broad-sense heritability: {broad_heritability:.4f}\\n"
            log += f"Prediction accuracy (correlation): {accuracy:.4f}\\n\\n"

            # Store results
            trait_result = {
                "trait": trait_idx + 1,
                "var_a": var_a,
                "var_d": var_d,
                "var_e": var_e,
                "narrow_heritability": narrow_heritability,
                "broad_heritability": broad_heritability,
                "accuracy": accuracy,
                "breeding_values": breeding_values,
                "dominance_deviations": dominance_deviations,
                "predicted_phenotypes": predicted_phenotypes,
            }
            trait_results.append(trait_result)

    # Save results to file
    results_df = pd.DataFrame()

    for i, trait_result in enumerate(trait_results):
        # Create individual-level results
        ind_data = {
            "individual": np.arange(1, n_individuals + 1),
            f"trait_{i + 1}_observed": phenotypes[:, i],
            f"trait_{i + 1}_predicted": trait_result["predicted_phenotypes"],
            f"trait_{i + 1}_breeding_value": trait_result["breeding_values"],
        }

        if model_type == "additive_dominance":
            ind_data[f"trait_{i + 1}_dominance_deviation"] = trait_result["dominance_deviations"]

        # Create or append to dataframe
        if i == 0:
            results_df = pd.DataFrame(ind_data)
        else:
            for key, value in ind_data.items():
                if key != "individual":  # Skip duplicating individual column
                    results_df[key] = value

    # Save to CSV
    results_df.to_csv(output_file, index=False)
    log += f"Results saved to {output_file}\\n"

    return log

# Execute the function
try:
    result = fit_genomic_prediction_model(
        genotypes=auto_convert(os.environ.get("PARAM_GENOTYPES", "")),
        phenotypes=auto_convert(os.environ.get("PARAM_PHENOTYPES", "")),
        fixed_effects=auto_convert(os.environ.get("PARAM_FIXED_EFFECTS", "")),
        model_type=auto_convert(os.environ.get("PARAM_MODEL_TYPE", "additive")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "genomic_prediction_results.csv")),
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
    "function": "fit_genomic_prediction_model",
    "domain": "genetics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("fit_genomic_prediction_model_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("fit_genomic_prediction_model_output.txt", "w") as f:
    f.write("Biomni: Fit Genomic Prediction Model" + NL)
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
        biomni_function: "fit_genomic_prediction_model"
    END_VERSIONS
    """
}

workflow FIT_GENOMIC_PREDICTION_MODEL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    FIT_GENOMIC_PREDICTION_MODEL(ch_input)

    emit:
    results = FIT_GENOMIC_PREDICTION_MODEL.out.results
    output = FIT_GENOMIC_PREDICTION_MODEL.out.output
    versions = FIT_GENOMIC_PREDICTION_MODEL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    FIT_GENOMIC_PREDICTION_MODEL_WORKFLOW(ch_input)

    FIT_GENOMIC_PREDICTION_MODEL_WORKFLOW.out.output.view { "Output: $it" }
}
