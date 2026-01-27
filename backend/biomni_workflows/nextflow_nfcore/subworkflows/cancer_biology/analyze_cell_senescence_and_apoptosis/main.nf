#!/usr/bin/env nextflow
/*
 * cancer_biology/analyze_cell_senescence_and_apoptosis
 * Analyze flow cytometry data to quantify senescent and apoptotic cell populations.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fcs_file_path = null

process ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_cell_senescence_and_apoptosis_results.json"), emit: results
    tuple val(meta), path("analyze_cell_senescence_and_apoptosis_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FCS_FILE_PATH="${params.fcs_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_cell_senescence_and_apoptosis(fcs_file_path):
    '''Analyze flow cytometry data to quantify senescent and apoptotic cell populations.

    Parameters
    ----------
    fcs_file_path : str
        Path to the FCS file containing flow cytometry data with measurements for
        senescence-associated β-galactosidase (SA-β-Gal) and Annexin V/7-AAD staining

    Returns
    -------
    str
        A research log summarizing the analysis steps and results, including percentages
        of senescent and apoptotic cell populations

    '''
    import os

    import numpy as np
    from FlowCytometryTools import FCMeasurement

    log = "# Flow Cytometry Analysis of Cell Senescence and Apoptosis\\n\\n"

    try:
        # Step 1: Load the FCS file
        log += "## Step 1: Loading Flow Cytometry Data\\n"
        log += f"- Loading FCS file from: {fcs_file_path}\\n"

        sample = FCMeasurement(ID="Sample", datafile=fcs_file_path)
        log += f"- Successfully loaded data with {len(sample)} events\\n"
        log += f"- Available channels: {', '.join(sample.channel_names)}\\n\\n"

        # Step 2: Apply compensation if needed (assuming pre-compensated data)
        log += "## Step 2: Data Preprocessing\\n"
        log += "- Checking for outliers and debris based on forward/side scatter\\n"

        # Basic filtering to remove debris based on FSC and SSC
        # Assuming FSC-A and SSC-A are the channel names (adjust if different)
        fsc_channel = "FSC-A" if "FSC-A" in sample.channel_names else sample.channel_names[0]
        ssc_channel = "SSC-A" if "SSC-A" in sample.channel_names else sample.channel_names[1]

        # Filter out debris (low FSC and SSC)
        sample_filtered = sample.gate(f"{fsc_channel} > 10000 and {ssc_channel} > 5000")

        log += f"- Filtered out debris: {len(sample)} → {len(sample_filtered)} events ({len(sample_filtered) / len(sample) * 100:.1f}%)\\n\\n"

        # Step 3: Identify senescent cells (SA-β-Gal positive)
        log += "## Step 3: Identifying Senescent Cells (SA-β-Gal+)\\n"

        # Find SA-β-Gal channel (adjust based on actual channel name)
        sa_bgal_channel = None
        for channel in sample_filtered.channel_names:
            if "GAL" in channel.upper() or "FITC" in channel.upper():
                sa_bgal_channel = channel
                break

        if not sa_bgal_channel:
            log += "- WARNING: Could not identify SA-β-Gal channel. Using first fluorescence channel as placeholder.\\n"
            # Use the first fluorescence channel as a fallback
            for channel in sample_filtered.channel_names:
                if any(x in channel.upper() for x in ["FL", "BL", "FITC", "PE", "APC"]):
                    sa_bgal_channel = channel
                    break

        log += f"- Using {sa_bgal_channel} as SA-β-Gal activity indicator\\n"

        # Determine threshold for SA-β-Gal positivity (using a simple percentile approach)
        # In practice, this would be based on controls or known thresholds
        sa_bgal_threshold = np.percentile(sample_filtered.data[sa_bgal_channel], 80)
        senescent_cells = sample_filtered.gate(f"{sa_bgal_channel} > {sa_bgal_threshold}")

        senescent_percentage = (len(senescent_cells) / len(sample_filtered)) * 100
        log += f"- Applied threshold at {sa_bgal_threshold:.1f} fluorescence intensity\\n"
        log += f"- Identified {len(senescent_cells)} senescent cells ({senescent_percentage:.2f}%)\\n\\n"

        # Step 4: Identify apoptotic cells (Annexin V+/7-AAD+)
        log += "## Step 4: Identifying Apoptotic Cells (Annexin V/7-AAD)\\n"

        # Find Annexin V and 7-AAD channels (adjust based on actual channel names)
        annexin_channel = None
        aad_channel = None

        for channel in sample_filtered.channel_names:
            if "ANNEXIN" in channel.upper() or "PE" in channel.upper():
                annexin_channel = channel
            if "7AAD" in channel.upper() or "AAD" in channel.upper() or "PerCP" in channel.upper():
                aad_channel = channel

        if not annexin_channel or not aad_channel:
            log += "- WARNING: Could not identify Annexin V and/or 7-AAD channels. Using placeholder channels.\\n"
            # Use fallback channels
            fluorescence_channels = [
                ch
                for ch in sample_filtered.channel_names
                if any(x in ch.upper() for x in ["FL", "BL", "FITC", "PE", "APC", "PerCP"])
            ]
            if len(fluorescence_channels) >= 2:
                if not annexin_channel:
                    annexin_channel = fluorescence_channels[0]
                if not aad_channel:
                    aad_channel = fluorescence_channels[1]

        log += f"- Using {annexin_channel} as Annexin V indicator\\n"
        log += f"- Using {aad_channel} as 7-AAD indicator\\n"

        # Determine thresholds for Annexin V and 7-AAD (using simple percentile approach)
        annexin_threshold = np.percentile(sample_filtered.data[annexin_channel], 90)
        aad_threshold = np.percentile(sample_filtered.data[aad_channel], 90)

        # Early apoptotic: Annexin V+ / 7-AAD-
        early_apoptotic = sample_filtered.gate(
            f"{annexin_channel} > {annexin_threshold} and {aad_channel} < {aad_threshold}"
        )
        early_apoptotic_percentage = (len(early_apoptotic) / len(sample_filtered)) * 100

        # Late apoptotic/necrotic: Annexin V+ / 7-AAD+
        late_apoptotic = sample_filtered.gate(
            f"{annexin_channel} > {annexin_threshold} and {aad_channel} > {aad_threshold}"
        )
        late_apoptotic_percentage = (len(late_apoptotic) / len(sample_filtered)) * 100

        # Total apoptotic (early + late)
        total_apoptotic_percentage = early_apoptotic_percentage + late_apoptotic_percentage

        log += f"- Early apoptotic cells (Annexin V+/7-AAD-): {early_apoptotic_percentage:.2f}%\\n"
        log += f"- Late apoptotic cells (Annexin V+/7-AAD+): {late_apoptotic_percentage:.2f}%\\n"
        log += f"- Total apoptotic cells: {total_apoptotic_percentage:.2f}%\\n\\n"

        # Step 5: Summary of results
        log += "## Summary of Results\\n"
        log += f"- Total events analyzed: {len(sample_filtered)}\\n"
        log += f"- Senescent cells (SA-β-Gal+): {senescent_percentage:.2f}%\\n"
        log += f"- Early apoptotic cells (Annexin V+/7-AAD-): {early_apoptotic_percentage:.2f}%\\n"
        log += f"- Late apoptotic cells (Annexin V+/7-AAD+): {late_apoptotic_percentage:.2f}%\\n"
        log += f"- Total apoptotic cells: {total_apoptotic_percentage:.2f}%\\n"

        # Save results to CSV file
        results_file = os.path.splitext(os.path.basename(fcs_file_path))[0] + "_results.csv"
        with open(results_file, "w") as f:
            f.write("Cell Population,Percentage\\n")
            f.write(f"Senescent cells,{senescent_percentage:.2f}\\n")
            f.write(f"Early apoptotic cells,{early_apoptotic_percentage:.2f}\\n")
            f.write(f"Late apoptotic cells,{late_apoptotic_percentage:.2f}\\n")
            f.write(f"Total apoptotic cells,{total_apoptotic_percentage:.2f}\\n")

        log += f"\\nResults saved to: {results_file}\\n"

    except Exception as e:
        log += "\\n## ERROR: An error occurred during analysis\\n"
        log += f"- Error message: {str(e)}\\n"

    return log

# Execute the function
try:
    result = analyze_cell_senescence_and_apoptosis(
        fcs_file_path=auto_convert(os.environ.get("PARAM_FCS_FILE_PATH", "")),
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
    "function": "analyze_cell_senescence_and_apoptosis",
    "domain": "cancer_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_cell_senescence_and_apoptosis_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_cell_senescence_and_apoptosis_output.txt", "w") as f:
    f.write("Biomni: Analyze Cell Senescence And Apoptosis" + NL)
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
        biomni_function: "analyze_cell_senescence_and_apoptosis"
    END_VERSIONS
    """
}

workflow ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS(ch_input)

    emit:
    results = ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS.out.results
    output = ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS.out.output
    versions = ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS_WORKFLOW(ch_input)

    ANALYZE_CELL_SENESCENCE_AND_APOPTOSIS_WORKFLOW.out.output.view { "Output: $it" }
}
