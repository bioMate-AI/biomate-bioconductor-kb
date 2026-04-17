#!/usr/bin/env nextflow
/*
 * immunology/analyze_ebv_antibody_titers
 * Analyze ELISA data to quantify EBV antibody titers in plasma/serum samples.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: ELISA OD readings for EBV antibodies
params.raw_od_data = '{"sample1": {"VCA_IgG": 0.85, "VCA_IgM": 0.12, "EA_IgG": 0.45, "EA_IgM": 0.08, "EBNA1_IgG": 0.72, "EBNA1_IgM": 0.05}, "sample2": {"VCA_IgG": 1.2, "VCA_IgM": 0.65, "EA_IgG": 0.78, "EA_IgM": 0.42, "EBNA1_IgG": 0.35, "EBNA1_IgM": 0.15}, "sample3": {"VCA_IgG": 0.25, "VCA_IgM": 0.08, "EA_IgG": 0.15, "EA_IgM": 0.05, "EBNA1_IgG": 0.18, "EBNA1_IgM": 0.03}}'
// Standard curves for IgG and IgM quantification
params.standard_curve_data = '{"IgG": [[10, 0.15], [50, 0.45], [100, 0.72], [200, 1.1], [400, 1.8]], "IgM": [[5, 0.08], [25, 0.25], [50, 0.42], [100, 0.68], [200, 1.2]]}'
// Sample metadata
params.sample_metadata = '{"sample1": {"group": "EBV_positive", "collection_date": "2024-01-15"}, "sample2": {"group": "EBV_active", "collection_date": "2024-01-15"}, "sample3": {"group": "EBV_negative", "collection_date": "2024-01-15"}}'
params.output_dir = './'

process ANALYZE_EBV_ANTIBODY_TITERS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_ebv_antibody_titers_results.json"), emit: results
    tuple val(meta), path("analyze_ebv_antibody_titers_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_RAW_OD_DATA="${params.raw_od_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_STANDARD_CURVE_DATA="${params.standard_curve_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAMPLE_METADATA="${params.sample_metadata?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_ebv_antibody_titers(raw_od_data, standard_curve_data, sample_metadata, output_dir="./"):
    '''Analyze ELISA data to quantify EBV antibody titers in plasma/serum samples.

    Parameters
    ----------
    raw_od_data : dict
        Dictionary containing optical density (OD) readings for each sample.
        Format: {sample_id: {'VCA_IgG': float, 'VCA_IgM': float, 'EA_IgG': float, 'EA_IgM': float, 'EBNA1_IgG': float, 'EBNA1_IgM': float}}
    standard_curve_data : dict
        Dictionary containing standard curve data for each antibody type.
        Format: {antibody_type: [(concentration, OD), ...]}
    sample_metadata : dict
        Dictionary containing metadata for each sample.
        Format: {sample_id: {'group': str, 'collection_date': str}}
    output_dir : str, optional
        Directory to save output files. Default is current directory.

    Returns
    -------
    str
        Research log summarizing the analysis process and results.

    '''
    import os
    from datetime import datetime

    import numpy as np
    import pandas as pd

    # Initialize log
    log = [
        "## EBV Antibody Titer Quantification Analysis",
        f"Analysis Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"Number of samples: {len(raw_od_data)}",
        "",
    ]

    # Create dataframe for results
    results_df = pd.DataFrame(
        columns=[
            "Sample_ID",
            "Group",
            "Collection_Date",
            "VCA_IgG",
            "VCA_IgM",
            "EA_IgG",
            "EA_IgM",
            "EBNA1_IgG",
            "EBNA1_IgM",
        ]
    )

    log.append("### 1. Data Preprocessing")
    log.append("- Checking for missing values and outliers in OD readings")

    # Check for missing values
    missing_values = False
    for sample_id, readings in raw_od_data.items():
        for antibody_type in [
            "VCA_IgG",
            "VCA_IgM",
            "EA_IgG",
            "EA_IgM",
            "EBNA1_IgG",
            "EBNA1_IgM",
        ]:
            if antibody_type not in readings:
                missing_values = True
                log.append(f"  - Warning: Missing {antibody_type} reading for sample {sample_id}")

    if not missing_values:
        log.append("  - No missing values detected")

    log.append("")
    log.append("### 2. Standard Curve Fitting")
    log.append("- Fitting standard curves for antibody quantification")

    # Fit standard curves (simple linear regression)
    standard_curves = {}
    for antibody_type, curve_data in standard_curve_data.items():
        concentrations, ods = zip(*curve_data, strict=False)
        # Simple linear regression for standard curve
        slope, intercept = np.polyfit(ods, concentrations, 1)
        standard_curves[antibody_type] = (slope, intercept)
        log.append(f"  - {antibody_type}: Fitted curve with slope={slope:.4f}, intercept={intercept:.4f}")

    log.append("")
    log.append("### 3. Antibody Titer Quantification")
    log.append("- Calculating antibody concentrations using standard curves")

    # Calculate antibody titers for each sample
    for sample_id, readings in raw_od_data.items():
        sample_data = {"Sample_ID": sample_id}

        # Add metadata
        if sample_id in sample_metadata:
            sample_data["Group"] = sample_metadata[sample_id].get("group", "Unknown")
            sample_data["Collection_Date"] = sample_metadata[sample_id].get("collection_date", "Unknown")
        else:
            sample_data["Group"] = "Unknown"
            sample_data["Collection_Date"] = "Unknown"

        # Calculate antibody titers
        for antibody_type in [
            "VCA_IgG",
            "VCA_IgM",
            "EA_IgG",
            "EA_IgM",
            "EBNA1_IgG",
            "EBNA1_IgM",
        ]:
            if antibody_type in readings:
                od = readings[antibody_type]
                # Get the appropriate standard curve
                curve_type = "IgG" if antibody_type.endswith("IgG") else "IgM"

                slope, intercept = standard_curves[curve_type]
                # Calculate concentration
                concentration = slope * od + intercept
                sample_data[antibody_type] = concentration
            else:
                sample_data[antibody_type] = np.nan

        # Add to results dataframe
        results_df = pd.concat([results_df, pd.DataFrame([sample_data])], ignore_index=True)

    log.append("")
    log.append("### 4. Results Summary")

    # Calculate summary statistics
    summary_stats = results_df.groupby("Group")[
        ["VCA_IgG", "VCA_IgM", "EA_IgG", "EA_IgM", "EBNA1_IgG", "EBNA1_IgM"]
    ].agg(["mean", "std"])

    # Log summary statistics
    for group in summary_stats.index:
        log.append(f"#### Group: {group}")
        for antibody in [
            "VCA_IgG",
            "VCA_IgM",
            "EA_IgG",
            "EA_IgM",
            "EBNA1_IgG",
            "EBNA1_IgM",
        ]:
            mean = summary_stats.loc[group, (antibody, "mean")]
            std = summary_stats.loc[group, (antibody, "std")]
            log.append(f"- {antibody}: {mean:.2f} ± {std:.2f} U/mL")
        log.append("")

    # Save results to CSV
    os.makedirs(output_dir, exist_ok=True)
    results_file = os.path.join(output_dir, "ebv_antibody_titers_results.csv")
    results_df.to_csv(results_file, index=False)
    log.append(f"Full results saved to: {results_file}")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_ebv_antibody_titers(
        raw_od_data=auto_convert(os.environ.get("PARAM_RAW_OD_DATA", "")),
        standard_curve_data=auto_convert(os.environ.get("PARAM_STANDARD_CURVE_DATA", "")),
        sample_metadata=auto_convert(os.environ.get("PARAM_SAMPLE_METADATA", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./")),
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
    "function": "analyze_ebv_antibody_titers",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_ebv_antibody_titers_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_ebv_antibody_titers_output.txt", "w") as f:
    f.write("Biomni: Analyze Ebv Antibody Titers" + NL)
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
        biomni_function: "analyze_ebv_antibody_titers"
    END_VERSIONS
    """
}

workflow ANALYZE_EBV_ANTIBODY_TITERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_EBV_ANTIBODY_TITERS(ch_input)

    emit:
    results = ANALYZE_EBV_ANTIBODY_TITERS.out.results
    output = ANALYZE_EBV_ANTIBODY_TITERS.out.output
    versions = ANALYZE_EBV_ANTIBODY_TITERS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_EBV_ANTIBODY_TITERS_WORKFLOW(ch_input)

    ANALYZE_EBV_ANTIBODY_TITERS_WORKFLOW.out.output.view { "Output: $it" }
}
