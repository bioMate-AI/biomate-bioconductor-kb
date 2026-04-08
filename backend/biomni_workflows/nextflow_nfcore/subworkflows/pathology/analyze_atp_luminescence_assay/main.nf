#!/usr/bin/env nextflow
/*
 * pathology/analyze_atp_luminescence_assay
 * Analyze luminescence-based ATP assay data to determine intracellular ATP concentration.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.data_file = null
params.standard_curve_file = null
params.normalization_method = 'cell_count'
params.normalization_data = null

process ANALYZE_ATP_LUMINESCENCE_ASSAY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_atp_luminescence_assay_results.json"), emit: results
    tuple val(meta), path("analyze_atp_luminescence_assay_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DATA_FILE="${params.data_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_STANDARD_CURVE_FILE="${params.standard_curve_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NORMALIZATION_METHOD="${params.normalization_method?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NORMALIZATION_DATA="${params.normalization_data?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_atp_luminescence_assay(
    data_file,
    standard_curve_file,
    normalization_method="cell_count",
    normalization_data=None,
):
    '''Analyze luminescence-based ATP assay data to determine intracellular ATP concentration.

    Parameters
    ----------
    data_file : str
        Path to CSV file containing luminescence readings from samples.
        Expected format: columns for 'Sample_ID' and 'Luminescence_Value'.

    standard_curve_file : str
        Path to CSV file containing standard curve data.
        Expected format: columns for 'ATP_Concentration' (in nM) and 'Luminescence_Value'.

    normalization_method : str, optional
        Method used to normalize ATP values, either 'cell_count' or 'protein_content'.
        Default is 'cell_count'.

    normalization_data : str or dict, optional
        Either path to CSV file with normalization data or dictionary with sample IDs as keys.
        For 'cell_count': values should be cell counts per sample.
        For 'protein_content': values should be protein concentration (μg/mL).

    Returns
    -------
    str
        Research log summarizing the ATP content measurement process and results.

    '''
    from datetime import datetime

    import numpy as np
    import pandas as pd

    log = []
    log.append(f"ATP Content Measurement Analysis - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append("=" * 50)

    # Step 1: Load the raw luminescence data
    log.append("Step 1: Loading raw luminescence data")
    try:
        sample_data = pd.read_csv(data_file)
        log.append(f"Successfully loaded data from {data_file}")
        log.append(f"Number of samples: {len(sample_data)}")
    except Exception as e:
        log.append(f"Error loading sample data: {str(e)}")
        return "\\n".join(log)

    # Step 2: Load the standard curve data
    log.append("\\nStep 2: Loading ATP standard curve data")
    try:
        std_curve_data = pd.read_csv(standard_curve_file)
        log.append(f"Successfully loaded standard curve from {standard_curve_file}")
    except Exception as e:
        log.append(f"Error loading standard curve data: {str(e)}")
        return "\\n".join(log)

    # Step 3: Generate standard curve equation (linear regression)
    log.append("\\nStep 3: Generating ATP standard curve")
    try:
        x = std_curve_data["Luminescence_Value"]
        y = std_curve_data["ATP_Concentration"]
        slope, intercept = np.polyfit(x, y, 1)
        log.append(f"Standard curve equation: ATP_Concentration = {slope:.6f} × Luminescence + {intercept:.6f}")
    except Exception as e:
        log.append(f"Error generating standard curve: {str(e)}")
        return "\\n".join(log)

    # Step 4: Calculate ATP concentrations for samples
    log.append("\\nStep 4: Calculating ATP concentrations for samples")
    try:
        sample_data["ATP_Concentration_nM"] = slope * sample_data["Luminescence_Value"] + intercept
        log.append("ATP concentrations calculated for all samples")
    except Exception as e:
        log.append(f"Error calculating ATP concentrations: {str(e)}")
        return "\\n".join(log)

    # Step 5: Normalize ATP concentrations
    log.append(f"\\nStep 5: Normalizing ATP concentrations by {normalization_method}")

    # Load normalization data
    if normalization_data:
        try:
            if isinstance(normalization_data, str):
                norm_data = pd.read_csv(normalization_data)
                norm_dict = dict(zip(norm_data["Sample_ID"], norm_data[normalization_method], strict=False))
            else:
                norm_dict = normalization_data

            # Apply normalization
            for idx, row in sample_data.iterrows():
                sample_id = row["Sample_ID"]
                if sample_id in norm_dict:
                    if normalization_method == "cell_count":
                        sample_data.at[idx, "ATP_pmol_per_million_cells"] = (
                            row["ATP_Concentration_nM"] / norm_dict[sample_id] * 1000
                        )
                    elif normalization_method == "protein_content":
                        sample_data.at[idx, "ATP_nmol_per_mg_protein"] = (
                            row["ATP_Concentration_nM"] / norm_dict[sample_id]
                        )

            log.append(f"Successfully normalized ATP concentrations by {normalization_method}")
        except Exception as e:
            log.append(f"Error during normalization: {str(e)}")
            log.append("Continuing with unnormalized ATP concentrations")
    else:
        log.append("No normalization data provided. Reporting unnormalized ATP concentrations.")

    # Step 6: Save results
    output_file = "atp_measurement_results.csv"
    try:
        sample_data.to_csv(output_file, index=False)
        log.append(f"\\nStep 6: Results saved to {output_file}")
    except Exception as e:
        log.append(f"\\nStep 6: Error saving results: {str(e)}")

    # Step 7: Summary statistics
    log.append("\\nStep 7: Summary of ATP measurement results")
    try:
        log.append("ATP Concentration Summary (nM):")
        log.append(f"  Mean: {sample_data['ATP_Concentration_nM'].mean():.2f}")
        log.append(f"  Median: {sample_data['ATP_Concentration_nM'].median():.2f}")
        log.append(f"  Min: {sample_data['ATP_Concentration_nM'].min():.2f}")
        log.append(f"  Max: {sample_data['ATP_Concentration_nM'].max():.2f}")

        if normalization_method == "cell_count" and "ATP_pmol_per_million_cells" in sample_data.columns:
            log.append("\\nATP per Million Cells (pmol):")
            log.append(f"  Mean: {sample_data['ATP_pmol_per_million_cells'].mean():.2f}")
            log.append(f"  Median: {sample_data['ATP_pmol_per_million_cells'].median():.2f}")
        elif normalization_method == "protein_content" and "ATP_nmol_per_mg_protein" in sample_data.columns:
            log.append("\\nATP per mg Protein (nmol):")
            log.append(f"  Mean: {sample_data['ATP_nmol_per_mg_protein'].mean():.2f}")
            log.append(f"  Median: {sample_data['ATP_nmol_per_mg_protein'].median():.2f}")
    except Exception as e:
        log.append(f"Error generating summary statistics: {str(e)}")

    log.append("\\nATP Content Measurement Analysis Complete")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_atp_luminescence_assay(
        data_file=auto_convert(os.environ.get("PARAM_DATA_FILE", "")),
        standard_curve_file=auto_convert(os.environ.get("PARAM_STANDARD_CURVE_FILE", "")),
        normalization_method=auto_convert(os.environ.get("PARAM_NORMALIZATION_METHOD", "cell_count")),
        normalization_data=auto_convert(os.environ.get("PARAM_NORMALIZATION_DATA", "")),
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
    "function": "analyze_atp_luminescence_assay",
    "domain": "pathology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_atp_luminescence_assay_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_atp_luminescence_assay_output.txt", "w") as f:
    f.write("Biomni: Analyze Atp Luminescence Assay" + NL)
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
        biomni_function: "analyze_atp_luminescence_assay"
    END_VERSIONS
    """
}

workflow ANALYZE_ATP_LUMINESCENCE_ASSAY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ATP_LUMINESCENCE_ASSAY(ch_input)

    emit:
    results = ANALYZE_ATP_LUMINESCENCE_ASSAY.out.results
    output = ANALYZE_ATP_LUMINESCENCE_ASSAY.out.output
    versions = ANALYZE_ATP_LUMINESCENCE_ASSAY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ATP_LUMINESCENCE_ASSAY_WORKFLOW(ch_input)

    ANALYZE_ATP_LUMINESCENCE_ASSAY_WORKFLOW.out.output.view { "Output: $it" }
}
