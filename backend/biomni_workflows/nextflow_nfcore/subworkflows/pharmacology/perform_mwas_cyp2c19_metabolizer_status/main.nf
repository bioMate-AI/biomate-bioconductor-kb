#!/usr/bin/env nextflow
/*
 * pharmacology/perform_mwas_cyp2c19_metabolizer_status
 * Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Uses inline-generated mock methylation data (created in script)
params.methylation_data_path = 'mock_methylation_data.csv'
params.metabolizer_status_path = 'mock_metabolizer_status.csv'
params.covariates_path = 'mock_covariates.csv'
params.pvalue_threshold = '0.05'
params.output_file = 'significant_cpg_sites.csv'

process PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_mwas_cyp2c19_metabolizer_status_results.json"), emit: results
    tuple val(meta), path("perform_mwas_cyp2c19_metabolizer_status_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_METHYLATION_DATA_PATH="${params.methylation_data_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_METABOLIZER_STATUS_PATH="${params.metabolizer_status_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COVARIATES_PATH="${params.covariates_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PVALUE_THRESHOLD="${params.pvalue_threshold?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Create mock MWAS data for CYP2C19 metabolizer status testing
    python3 << 'MOCKEOF'
import pandas as pd
import numpy as np

np.random.seed(42)

# Sample IDs
n_samples = 100
sample_ids = [f'SAMPLE_{i:03d}' for i in range(1, n_samples + 1)]

# Create mock methylation data (beta values for CpG sites)
n_cpg_sites = 50
cpg_ids = [f'cg{i:08d}' for i in range(1, n_cpg_sites + 1)]

# Generate methylation beta values (0-1)
methylation_data = pd.DataFrame(
    np.random.beta(2, 5, size=(n_samples, n_cpg_sites)),
    index=sample_ids,
    columns=cpg_ids
)
methylation_data.to_csv('mock_methylation_data.csv')

# Create mock metabolizer status
# CYP2C19 metabolizer status categories
status_options = ['poor', 'intermediate', 'normal', 'rapid', 'ultrarapid']
status_probs = [0.1, 0.2, 0.4, 0.2, 0.1]  # Approximate population frequencies

metabolizer_status = pd.DataFrame({
    'status': np.random.choice(status_options, n_samples, p=status_probs)
}, index=sample_ids)
metabolizer_status.to_csv('mock_metabolizer_status.csv')

# Create mock covariates (age, sex)
covariates = pd.DataFrame({
    'age': np.random.randint(20, 80, n_samples),
    'sex': np.random.choice([0, 1], n_samples)  # 0=female, 1=male
}, index=sample_ids)
covariates.to_csv('mock_covariates.csv')

print(f"Created mock MWAS data: {n_samples} samples, {n_cpg_sites} CpG sites")
MOCKEOF

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
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



def perform_mwas_cyp2c19_metabolizer_status(
    methylation_data_path,
    metabolizer_status_path,
    covariates_path=None,
    pvalue_threshold=0.05,
    output_file="significant_cpg_sites.csv",
):
    '''Perform a Methylome-wide Association Study (MWAS) to identify CpG sites significantly associated with CYP2C19 metabolizer status.

    Parameters
    ----------
    methylation_data_path : str
        Path to CSV or TSV file containing DNA methylation beta values.
        Rows should be samples, columns should be CpG sites.
    metabolizer_status_path : str
        Path to CSV or TSV file containing CYP2C19 metabolizer status for each sample.
        Should have a sample ID column and a status column (e.g., poor, intermediate, normal, rapid, ultrarapid).
    covariates_path : str, optional
        Path to CSV or TSV file containing covariates to adjust for in the regression model
        (e.g., age, sex, smoking status).
    pvalue_threshold : float, optional
        P-value threshold for significance after multiple testing correction. Default is 0.05.
    output_file : str, optional
        Filename to save significant CpG sites. Default is "significant_cpg_sites.csv".

    Returns
    -------
    str
        A research log summarizing the MWAS analysis and results.

    '''
    import time

    import pandas as pd
    from scipy.stats import linregress
    from statsmodels.formula.api import ols

    start_time = time.time()
    log = ["## Methylome-wide Association Study (MWAS) of CYP2C19 Metabolizer Status"]

    # Load data from files
    log.append("\\n### Loading Data")
    try:
        # Load methylation data
        if methylation_data_path.endswith(".csv"):
            methylation_data = pd.read_csv(methylation_data_path, index_col=0)
        elif methylation_data_path.endswith((".tsv", ".txt")):
            methylation_data = pd.read_csv(methylation_data_path, sep="\\t", index_col=0)
        else:
            log.append("Error: Unsupported file format for methylation data. Please provide a CSV or TSV file.")
            return "\\n".join(log)
        log.append(f"- Successfully loaded methylation data from {methylation_data_path}")

        # Load metabolizer status data
        if metabolizer_status_path.endswith(".csv"):
            metabolizer_status_df = pd.read_csv(metabolizer_status_path, index_col=0)
        elif metabolizer_status_path.endswith((".tsv", ".txt")):
            metabolizer_status_df = pd.read_csv(metabolizer_status_path, sep="\\t", index_col=0)
        else:
            log.append("Error: Unsupported file format for metabolizer status. Please provide a CSV or TSV file.")
            return "\\n".join(log)
        log.append(f"- Successfully loaded metabolizer status data from {metabolizer_status_path}")

        # Convert DataFrame to Series if necessary
        if metabolizer_status_df.shape[1] == 1:
            metabolizer_status = metabolizer_status_df.iloc[:, 0]
        else:
            log.append("Error: Metabolizer status file should contain a single column with status values.")
            return "\\n".join(log)

        # Load covariates if provided
        covariates = None
        if covariates_path is not None:
            if covariates_path.endswith(".csv"):
                covariates = pd.read_csv(covariates_path, index_col=0)
            elif covariates_path.endswith((".tsv", ".txt")):
                covariates = pd.read_csv(covariates_path, sep="\\t", index_col=0)
            else:
                log.append("Error: Unsupported file format for covariates. Please provide a CSV or TSV file.")
                return "\\n".join(log)
            log.append(f"- Successfully loaded covariates data from {covariates_path}")
    except Exception as e:
        log.append(f"Error loading data: {str(e)}")
        return "\\n".join(log)

    # Step 1: Data preprocessing
    log.append("\\n### Data Preprocessing")
    log.append(f"- Methylation data shape: {methylation_data.shape} (samples × CpG sites)")
    log.append(f"- Number of samples with metabolizer status: {len(metabolizer_status)}")

    # Ensure sample IDs match between methylation data and metabolizer status
    common_samples = methylation_data.index.intersection(metabolizer_status.index)
    methylation_data = methylation_data.loc[common_samples]
    metabolizer_status = metabolizer_status.loc[common_samples]

    log.append(f"- Number of samples after matching: {len(common_samples)}")

    # Check for covariates
    if covariates is not None:
        log.append(f"- Covariates provided: {', '.join(covariates.columns)}")
        covariates = covariates.loc[common_samples]

    # Step 2: Perform regression for each CpG site
    log.append("\\n### Association Analysis")
    log.append(f"- Total CpG sites to analyze: {methylation_data.shape[1]}")

    results = []
    cpg_sites = methylation_data.columns

    # Convert metabolizer status to numeric if it's categorical
    if metabolizer_status.dtype == "object":
        # Create a mapping dictionary for metabolizer status
        # Assuming order: poor < intermediate < normal < rapid < ultrarapid
        status_order = {
            "poor": 1,
            "intermediate": 2,
            "normal": 3,
            "rapid": 4,
            "ultrarapid": 5,
        }

        # Try to map using the dictionary, or keep as is if already numeric
        try:
            metabolizer_status_numeric = metabolizer_status.map(status_order)
            log.append("- Converted metabolizer status to numeric values")
        except Exception:
            metabolizer_status_numeric = metabolizer_status
            log.append("- Using metabolizer status as provided (assuming numeric)")
    else:
        metabolizer_status_numeric = metabolizer_status

    # Perform regression for each CpG site
    for cpg in cpg_sites:
        methylation_values = methylation_data[cpg]

        # Basic model without covariates
        if covariates is None:
            model = linregress(metabolizer_status_numeric, methylation_values)
            pvalue = model.pvalue
            coefficient = model.slope
        else:
            # Create DataFrame for regression with covariates
            data_for_regression = pd.DataFrame(
                {
                    "methylation": methylation_values,
                    "metabolizer": metabolizer_status_numeric,
                }
            )

            # Add covariates
            for col in covariates.columns:
                data_for_regression[col] = covariates[col]

            # Formula for regression with covariates
            formula = "methylation ~ metabolizer + " + " + ".join(covariates.columns)
            model = ols(formula, data=data_for_regression).fit()

            pvalue = model.pvalues["metabolizer"]
            coefficient = model.params["metabolizer"]

        results.append({"CpG_site": cpg, "coefficient": coefficient, "pvalue": pvalue})

    # Convert results to DataFrame
    results_df = pd.DataFrame(results)

    # Step 3: Multiple testing correction
    log.append("\\n### Multiple Testing Correction")
    log.append("- Applying Bonferroni correction")

    # Bonferroni correction
    results_df["adjusted_pvalue"] = results_df["pvalue"] * len(results_df)
    results_df["adjusted_pvalue"] = results_df["adjusted_pvalue"].clip(upper=1.0)  # Ensure p-values don't exceed 1

    # Step 4: Identify significant CpG sites
    significant_sites = results_df[results_df["adjusted_pvalue"] < pvalue_threshold]
    significant_sites = significant_sites.sort_values("adjusted_pvalue")

    log.append("\\n### Results")
    log.append(f"- Number of significant CpG sites (adjusted p < {pvalue_threshold}): {len(significant_sites)}")

    if len(significant_sites) > 0:
        # Save significant sites to file
        significant_sites.to_csv(output_file, index=False)
        log.append("- Top 5 significant CpG sites:")

        for _, row in significant_sites.head(5).iterrows():
            log.append(
                f"  * {row['CpG_site']}: coefficient = {row['coefficient']:.4f}, adj. p-value = {row['adjusted_pvalue']:.6f}"
            )

        log.append(f"- Full results saved to: {output_file}")
    else:
        log.append("- No significant CpG sites found after multiple testing correction")

    # Execution time
    execution_time = time.time() - start_time
    log.append("\\n### Summary")
    log.append(f"- Analysis completed in {execution_time:.2f} seconds")

    return "\\n".join(log)

# Execute the function
try:
    result = perform_mwas_cyp2c19_metabolizer_status(
        methylation_data_path=auto_convert(os.environ.get("PARAM_METHYLATION_DATA_PATH", "")),
        metabolizer_status_path=auto_convert(os.environ.get("PARAM_METABOLIZER_STATUS_PATH", "")),
        covariates_path=auto_convert(os.environ.get("PARAM_COVARIATES_PATH", "")),
        pvalue_threshold=auto_convert(os.environ.get("PARAM_PVALUE_THRESHOLD", "0.05")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "significant_cpg_sites.csv")),
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
    "function": "perform_mwas_cyp2c19_metabolizer_status",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_mwas_cyp2c19_metabolizer_status_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_mwas_cyp2c19_metabolizer_status_output.txt", "w") as f:
    f.write("Biomni: Perform Mwas Cyp2C19 Metabolizer Status" + NL)
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
        biomni_function: "perform_mwas_cyp2c19_metabolizer_status"
    END_VERSIONS
    """
}

workflow PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS(ch_input)

    emit:
    results = PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS.out.results
    output = PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS.out.output
    versions = PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS_WORKFLOW(ch_input)

    PERFORM_MWAS_CYP2C19_METABOLIZER_STATUS_WORKFLOW.out.output.view { "Output: $it" }
}
