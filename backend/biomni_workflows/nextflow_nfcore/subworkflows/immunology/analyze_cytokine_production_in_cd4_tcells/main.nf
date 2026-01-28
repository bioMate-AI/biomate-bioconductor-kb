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
// Demo: Accuri C6 flow cytometer FCS file from Galaxy test data
params.fcs_files_dict = '{"unstimulated": "/home/yzhang/biomate/backend/lib/galaxy/datatypes/test/Accuri_C6_A01_H2O.fcs", "stimulated": "/home/yzhang/biomate/backend/lib/galaxy/datatypes/test/Accuri_C6_A01_H2O.fcs"}'
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

# Python 3.10+ compatibility fix for collections.MutableMapping
import collections
import collections.abc
if not hasattr(collections, 'MutableMapping'):
    collections.MutableMapping = collections.abc.MutableMapping
if not hasattr(collections, 'Mapping'):
    collections.Mapping = collections.abc.Mapping
if not hasattr(collections, 'MutableSet'):
    collections.MutableSet = collections.abc.MutableSet
if not hasattr(collections, 'Iterable'):
    collections.Iterable = collections.abc.Iterable
if not hasattr(collections, 'Sequence'):
    collections.Sequence = collections.abc.Sequence

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

    import numpy as np
    import pandas as pd
    import flowio

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

        # Load FCS file using flowio (numpy 2.x compatible)
        try:
            fd = flowio.FlowData(fcs_file, ignore_offset_error=True, ignore_offset_discrepancy=True)
            channels = [fd.channels[k]['pnn'] for k in sorted(fd.channels.keys())]
            sample = pd.DataFrame(
                np.reshape(fd.events, (-1, fd.channel_count)),
                columns=channels
            )
            log += f"- Loaded {len(sample)} events, channels: {', '.join(channels)}\\n"
        except Exception as e:
            log += f"ERROR loading file: {str(e)}\\n"
            continue

        # Find cytokine and CD4 channels
        cytokine_channels = [ch for ch in channels if "IFN" in ch.upper() or "IL-17" in ch.upper() or "IL17" in ch.upper()]
        cd4_channel = next((ch for ch in channels if "CD4" in ch.upper()), None)

        # If no specific channels found, use placeholder fluorescence channels
        if not cd4_channel:
            cd4_channel = next((ch for ch in channels if "FL" in ch.upper() and "A" in ch), None)
            if cd4_channel:
                log += f"- WARNING: Using {cd4_channel} as CD4 placeholder\\n"
            else:
                log += "ERROR: No suitable channel for CD4 analysis\\n"
                continue

        if not cytokine_channels:
            # Use FL channels as placeholders
            fl_channels = [ch for ch in channels if ch.startswith("FL") and "-A" in ch]
            if len(fl_channels) >= 2:
                cytokine_channels = fl_channels[1:3]
                log += f"- WARNING: Using {', '.join(cytokine_channels)} as cytokine placeholders\\n"

        log += f"- Analysis channels: CD4={cd4_channel}, Cytokines={', '.join(cytokine_channels) if cytokine_channels else 'none'}\\n"

        # Apply gates to identify CD4+ T cells using adaptive thresholding
        try:
            cd4_threshold = np.percentile(sample[cd4_channel], 50)  # Use median as threshold
            cd4_positive_mask = sample[cd4_channel] > cd4_threshold
            cd4_positive = sample[cd4_positive_mask]
            log += f"- Applied CD4+ gating (>{cd4_threshold:.0f}): {len(cd4_positive)} cells (from {len(sample)} total)\\n"

            # Extract cytokine data for CD4+ cells
            cytokine_data = {}
            for cytokine_channel in cytokine_channels:
                # Determine cytokine name from channel
                if "IFN" in cytokine_channel.upper():
                    cytokine_name = "IFN-gamma"
                elif "IL-17" in cytokine_channel.upper() or "IL17" in cytokine_channel.upper():
                    cytokine_name = "IL-17"
                else:
                    cytokine_name = cytokine_channel

                # Gate for cytokine positive cells using adaptive threshold
                cytokine_threshold = np.percentile(cd4_positive[cytokine_channel], 80)
                cytokine_positive_mask = cd4_positive[cytokine_channel] > cytokine_threshold

                # Calculate frequency of cytokine-producing cells within CD4+ population
                frequency = (cytokine_positive_mask.sum() / len(cd4_positive) * 100) if len(cd4_positive) > 0 else 0

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
