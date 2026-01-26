#!/usr/bin/env nextflow
/*
 * immunology/analyze_cytokine_production_in_cd4_tcells
 * Analyze cytokine production (IFN-γ, IL-17) in CD4+ T cells after antigen stimulation.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fcs_files_dict = null
params.output_dir = './results'

process ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_cytokine_production_in_cd4_tcells_results.json"), emit: results
    tuple val(meta), path("analyze_cytokine_production_in_cd4_tcells_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FCS_FILES_DICT="${params.fcs_files_dict?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_cytokine_production_in_cd4_tcells(fcs_files_dict, output_dir="./results"):
    '''Analyze cytokine production (IFN-γ, IL-17) in CD4+ T cells after antigen stimulation.

    Parameters
    ----------
    fcs_files_dict : dict
        Dictionary mapping stimulation conditions to FCS file paths.
        Expected keys: 'unstimulated', 'Mtb300', 'CMV', 'SEB'
        Example: {'unstimulated': 'path/to/unstim.fcs', 'Mtb300': 'path/to/mtb.fcs'}

    output_dir : str, optional
        Directory to save the results file (default: './results')

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os

    import pandas as pd
    from FlowCytometryTools import FCMeasurement

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    log = "# Cytokine Production Analysis by Flow Cytometry\\n\\n"
    log += "## Data Loading and Preprocessing\\n"

    results = {}

    # Check required stimulation conditions
    required_conditions = ["unstimulated", "Mtb300", "CMV", "SEB"]
    missing_conditions = [cond for cond in required_conditions if cond not in fcs_files_dict]
    if missing_conditions:
        log += f"WARNING: Missing data for conditions: {', '.join(missing_conditions)}\\n"

    # Process each stimulation condition
    for condition, fcs_file in fcs_files_dict.items():
        log += f"\\nProcessing {condition} condition from file: {os.path.basename(fcs_file)}\\n"

        # Load FCS file
        sample = FCMeasurement(ID=condition, datafile=fcs_file)

        # Apply compensation (if compensation matrix is available in the FCS file)
        try:
            sample = sample.compensate()
            log += "- Applied compensation matrix\\n"
        except Exception:
            log += "- No compensation matrix found, using uncompensated data\\n"

        # Transform data (typically logicle transformation for cytometry data)
        channels = sample.channel_names
        cytokine_channels = [ch for ch in channels if "IFN" in ch or "IL-17" in ch]
        cd4_channel = next((ch for ch in channels if "CD4" in ch), None)

        if not cd4_channel:
            log += "ERROR: CD4 channel not found in data\\n"
            continue

        if not cytokine_channels:
            log += "ERROR: Cytokine channels (IFN-γ, IL-17) not found in data\\n"
            continue

        log += f"- Identified channels: CD4={cd4_channel}, Cytokines={', '.join(cytokine_channels)}\\n"

        # Apply gates to identify CD4+ T cells
        try:
            # Create a threshold gate for CD4+ cells (adjust threshold as needed)
            cd4_positive = sample.gate(f"{cd4_channel} > 1000")  # Threshold value should be adjusted based on data
            log += f"- Applied CD4+ gating: {len(cd4_positive.data)} cells (from {len(sample.data)} total)\\n"

            # Extract cytokine data for CD4+ cells
            cytokine_data = {}
            for cytokine_channel in cytokine_channels:
                # Determine cytokine name from channel
                if "IFN" in cytokine_channel:
                    cytokine_name = "IFN-γ"
                elif "IL-17" in cytokine_channel:
                    cytokine_name = "IL-17"
                else:
                    continue

                # Gate for cytokine positive cells (threshold to be adjusted based on data)
                cytokine_positive = cd4_positive.gate(f"{cytokine_channel} > 500")  # Threshold value should be adjusted

                # Calculate frequency of cytokine-producing cells within CD4+ population
                frequency = (
                    len(cytokine_positive.data) / len(cd4_positive.data) * 100 if len(cd4_positive.data) > 0 else 0
                )

                log += f"- {cytokine_name}+ frequency: {frequency:.2f}% of CD4+ T cells\\n"
                cytokine_data[cytokine_name] = frequency

            results[condition] = cytokine_data

        except Exception as e:
            log += f"ERROR during analysis: {str(e)}\\n"

    # Summarize results across conditions
    if results:
        log += "\\n## Results Summary\\n"

        # Create DataFrame for results
        df_results = pd.DataFrame()

        for condition in results:
            for cytokine, frequency in results[condition].items():
                df_results.loc[condition, cytokine] = frequency

        # Calculate background (unstimulated)
        if "unstimulated" in results:
            log += "\\n### Background-subtracted frequencies\\n"
            background = results["unstimulated"]

            for condition in [c for c in results if c != "unstimulated"]:
                for cytokine in results[condition]:
                    if cytokine in background:
                        background_subtracted = results[condition][cytokine] - background[cytokine]
                        background_subtracted = max(0, background_subtracted)  # Ensure non-negative
                        df_results.loc[condition, f"{cytokine} (background-subtracted)"] = background_subtracted

        # Save results to CSV
        results_file = os.path.join(output_dir, "cytokine_frequencies.csv")
        df_results.to_csv(results_file)
        log += f"\\nResults saved to: {results_file}\\n"

        # Add results table to log
        log += "\\n### Frequencies of cytokine-producing CD4+ T cells (%)\\n"
        log += df_results.to_string()

        # Interpret results
        log += "\\n\\n## Interpretation\\n"

        # Compare responses to different stimuli
        if "Mtb300" in results and "CMV" in results and "SEB" in results:
            log += "\\nComparison of responses to different stimuli:\\n"

            for cytokine in ["IFN-γ", "IL-17"]:
                if cytokine in results["Mtb300"] and cytokine in results["CMV"] and cytokine in results["SEB"]:
                    mtb_response = results["Mtb300"][cytokine]
                    cmv_response = results["CMV"][cytokine]
                    seb_response = results["SEB"][cytokine]

                    log += f"- {cytokine}: Mtb300 ({mtb_response:.2f}%), CMV ({cmv_response:.2f}%), SEB ({seb_response:.2f}%)\\n"
    else:
        log += "\\nNo valid results were generated for any condition.\\n"

    return log

# Execute the function
try:
    result = analyze_cytokine_production_in_cd4_tcells(
        fcs_files_dict=auto_convert(os.environ.get("PARAM_FCS_FILES_DICT", "")),
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
    "function": "analyze_cytokine_production_in_cd4_tcells",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_cytokine_production_in_cd4_tcells_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_cytokine_production_in_cd4_tcells_output.txt", "w") as f:
    f.write("Biomni: Analyze Cytokine Production In Cd4 Tcells" + NL)
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
        biomni_function: "analyze_cytokine_production_in_cd4_tcells"
    END_VERSIONS
    """
}

workflow ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS(ch_input)

    emit:
    results = ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS.out.results
    output = ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS.out.output
    versions = ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS_WORKFLOW(ch_input)

    ANALYZE_CYTOKINE_PRODUCTION_IN_CD4_TCELLS_WORKFLOW.out.output.view { "Output: $it" }
}
