#!/usr/bin/env nextflow
/*
 * microbiology/quantify_biofilm_biomass_crystal_violet
 * Quantifies biofilm biomass using crystal violet staining assay data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Crystal violet OD measurements for biofilm quantification
params.od_values = '[0.05, 0.35, 0.42, 0.68, 0.72, 0.88, 0.95, 1.12]'
params.sample_names = '["Negative Control", "Wild Type 1", "Wild Type 2", "Mutant A 1", "Mutant A 2", "Mutant B 1", "Mutant B 2", "Positive Control"]'
params.control_index = '0'
params.save_path = null

process QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("quantify_biofilm_biomass_crystal_violet_results.json"), emit: results
    tuple val(meta), path("quantify_biofilm_biomass_crystal_violet_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_OD_VALUES="${params.od_values?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAMPLE_NAMES="${params.sample_names?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONTROL_INDEX="${params.control_index?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAVE_PATH="${params.save_path?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def quantify_biofilm_biomass_crystal_violet(od_values, sample_names=None, control_index=0, save_path=None):
    '''Quantifies biofilm biomass using crystal violet staining assay data.

    Parameters
    ----------
    od_values : list or numpy.ndarray
        Optical density measurements from crystal violet staining.
        Each value represents the absorbance reading for a sample.
    sample_names : list, optional
        Names of the biofilm samples corresponding to od_values.
        If None, samples will be labeled as Sample 1, Sample 2, etc.
    control_index : int, optional
        Index of the negative control sample in od_values. Default is 0.
    save_path : str, optional
        Path to save the results. If None, results won't be saved to a file.

    Returns
    -------
    str
        Research log detailing the quantification process and results.

    '''
    import os
    from datetime import datetime

    import numpy as np
    import pandas as pd
    from scipy import stats

    # Initialize research log
    log = "## Biofilm Biomass Quantification using Crystal Violet Staining\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Convert input to numpy array for processing
    od_values = np.array(od_values, dtype=float)

    # Generate sample names if not provided
    if sample_names is None:
        sample_names = [f"Sample {i + 1}" for i in range(len(od_values))]

    log += "### Samples Analyzed:\\n"
    for i, name in enumerate(sample_names):
        log += f"- {name}: OD = {od_values[i]:.4f}\\n"

    # Calculate normalized values (subtract control)
    control_value = od_values[control_index]
    normalized_values = od_values - control_value

    log += "\\n### Normalization:\\n"
    log += f"- Control sample: {sample_names[control_index]} (OD = {control_value:.4f})\\n"
    log += "- Normalized values (Control subtracted):\\n"

    for i, name in enumerate(sample_names):
        if i != control_index:
            log += f"  - {name}: {normalized_values[i]:.4f}\\n"

    # Basic statistical analysis
    mean_biomass = np.mean(normalized_values[normalized_values > 0])
    std_biomass = np.std(normalized_values[normalized_values > 0])

    log += "\\n### Statistical Analysis:\\n"
    log += f"- Mean normalized biomass: {mean_biomass:.4f}\\n"
    log += f"- Standard deviation: {std_biomass:.4f}\\n"

    # Perform t-test for samples against control
    p_values = []
    log += "\\n### Statistical Significance:\\n"

    for i, name in enumerate(sample_names):
        if i != control_index:
            # Using one-sample t-test against 0 (normalized control value)
            t_stat, p_val = stats.ttest_1samp([normalized_values[i]], 0)
            p_values.append(p_val)
            significance = "significant" if p_val < 0.05 else "not significant"
            log += f"- {name} vs Control: p-value = {p_val:.4f} ({significance})\\n"

    # Create a summary dataframe
    results_df = pd.DataFrame(
        {
            "Sample": sample_names,
            "OD_Value": od_values,
            "Normalized_Value": normalized_values,
        }
    )

    # Save results if path is provided
    if save_path:
        results_file = os.path.join(
            save_path,
            f"biofilm_biomass_results_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv",
        )
        results_df.to_csv(results_file, index=False)
        log += "\\n### Results Saved:\\n"
        log += f"- Data saved to: {results_file}\\n"

    log += "\\n### Conclusion:\\n"
    log += "- Crystal violet staining assay successfully quantified biofilm biomass.\\n"
    log += f"- Samples showed varying levels of biofilm formation with mean biomass of {mean_biomass:.4f} ± {std_biomass:.4f}.\\n"

    return log

# Execute the function
try:
    result = quantify_biofilm_biomass_crystal_violet(
        od_values=auto_convert(os.environ.get("PARAM_OD_VALUES", "")),
        sample_names=auto_convert(os.environ.get("PARAM_SAMPLE_NAMES", "")),
        control_index=auto_convert(os.environ.get("PARAM_CONTROL_INDEX", "0")),
        save_path=auto_convert(os.environ.get("PARAM_SAVE_PATH", "")),
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
    "function": "quantify_biofilm_biomass_crystal_violet",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("quantify_biofilm_biomass_crystal_violet_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("quantify_biofilm_biomass_crystal_violet_output.txt", "w") as f:
    f.write("Biomni: Quantify Biofilm Biomass Crystal Violet" + NL)
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
        biomni_function: "quantify_biofilm_biomass_crystal_violet"
    END_VERSIONS
    """
}

workflow QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET(ch_input)

    emit:
    results = QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET.out.results
    output = QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET.out.output
    versions = QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET_WORKFLOW(ch_input)

    QUANTIFY_BIOFILM_BIOMASS_CRYSTAL_VIOLET_WORKFLOW.out.output.view { "Output: $it" }
}
