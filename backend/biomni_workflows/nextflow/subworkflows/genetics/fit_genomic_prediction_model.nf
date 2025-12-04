#!/usr/bin/env nextflow
/*
 * biomni_genetics_fit_genomic_prediction_model
 * Fit a linear mixed model for genomic prediction using genotype and phenotype data.
 * Runs in Docker: biomate/biotools:arm64
 */

nextflow.enable.dsl = 2

params.outdir = "./results"
params.input = "input.txt"


process fit_genomic_prediction_model {
    container 'biomate/biotools:arm64'
    publishDir "${params.outdir}/fit_genomic_prediction_model", mode: 'copy'
    
    input:
    path input_file
    
    output:
    path "*_result.txt", emit: results
    path "*.png", emit: plots, optional: true
    
    script:
    '''
    cat > run_tool.py << 'PYTHON_EOF'

import json
import sys
from pathlib import Path

def fit_genomic_prediction_model(
    genotypes,
    phenotypes,
    fixed_effects=None,
    model_type="additive",
    output_file="genomic_prediction_results.csv",
):
    """Fit a linear mixed model for genomic prediction using genotype and phenotype data.

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

    """
    import pandas as pd
    from scipy import linalg

    # Initialize research log
    log = "# Multi-trait Genomic Prediction Analysis\n\n"
    log += f"Model type: {model_type}\n"

    # Basic validation
    n_individuals, n_markers = genotypes.shape
    n_pheno, n_traits = (phenotypes.shape[0], 1) if phenotypes.ndim == 1 else phenotypes.shape

    if n_individuals != n_pheno:
        raise ValueError(f"Number of individuals in genotypes ({n_individuals}) and phenotypes ({n_pheno}) don't match")

    log += f"Number of individuals: {n_individuals}\n"
    log += f"Number of markers: {n_markers}\n"
    log += f"Number of traits: {n_traits}\n\n"

    # Ensure phenotypes is 2D
    if phenotypes.ndim == 1:
        phenotypes = phenotypes.reshape(-1, 1)

    # Center genotypes (common preprocessing step)
    genotypes_centered = genotypes - np.mean(genotypes, axis=0)

    # Create genomic relationship matrix (G)
    if model_type == "additive":
        # Additive genomic relationship matrix
        G = np.dot(genotypes_centered, genotypes_centered.T) / n_markers
        log += "Constructed additive genomic relationship matrix (G)\n\n"
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
        log += "Constructed additive (G_a) and dominance (G_d) genomic relationship matrices\n\n"
    else:
        raise ValueError(f"Unknown model type: {model_type}")

    # Initialize results storage
    trait_results = []

    # Fit model for each trait
    for trait_idx in range(n_traits):
        trait_phenotypes = phenotypes[:, trait_idx]
        log += f"## Trait {trait_idx + 1} Analysis\n\n"

        # Handle fixed effects if provided
        if fixed_effects is not None:
            # Simple fixed effects adjustment - more complex models would use proper mixed model fitting
            X = fixed_effects
            # Fit fixed effects model
            beta = np.linalg.lstsq(X, trait_phenotypes, rcond=None)[0]
            # Adjust phenotypes for fixed effects
            y_adj = trait_phenotypes - X @ beta
            log += f"Applied adjustment for {X.shape[1]} fixed effects\n"
        else:
            y_adj = trait_phenotypes
            log += "No fixed effects provided\n"

        # Fit mixed model
    # ... (truncated)

if __name__ == "__main__":
    input_file = sys.argv[1] if len(sys.argv) > 1 else "input.txt"
    try:
        result = fit_genomic_prediction_model(input_file)
        with open("fit_genomic_prediction_model_result.txt", "w") as f:
            f.write(str(result))
    except Exception as e:
        with open("fit_genomic_prediction_model_result.txt", "w") as f:
            f.write(f"Error: {e}")

PYTHON_EOF
    python3 run_tool.py !{input_file}
    '''
}

process output {
    container 'biomate/biotools:arm64'
    publishDir "${params.outdir}/output", mode: 'copy'
    
    input:
    path input_file
    
    output:
    path "*_result.txt", emit: results
    path "*.png", emit: plots, optional: true
    
    script:
    '''
    cat > run_tool.py << 'PYTHON_EOF'

import sys
print("Running output")
with open("output_result.txt", "w") as f:
    f.write("Completed")

PYTHON_EOF
    python3 run_tool.py !{input_file}
    '''
}

workflow {
    input_ch = Channel.fromPath(params.input)
    
    fit_genomic_prediction_model(input_ch)
    output(fit_genomic_prediction_model.out.results)
}
