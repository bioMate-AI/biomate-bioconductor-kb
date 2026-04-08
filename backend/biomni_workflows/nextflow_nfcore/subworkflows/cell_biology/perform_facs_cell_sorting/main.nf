#!/usr/bin/env nextflow
/*
 * cell_biology/perform_facs_cell_sorting
 * Performs Fluorescence-Activated Cell Sorting (FACS) to enrich cell populations based on fluorescence characteristics.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo FCS file from Galaxy test data
params.cell_suspension_data = "${projectDir}/../../../../lib/galaxy/datatypes/test/Accuri_C6_A01_H2O.fcs"
// Fluorescence parameter to sort on (FSC-A = forward scatter area)
params.fluorescence_parameter = 'FSC-A'
// Threshold range for sorting (null = no filtering)
params.threshold_min = 50000
params.threshold_max = 200000
params.output_file = 'sorted_cells.csv'

process PERFORM_FACS_CELL_SORTING {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("perform_facs_cell_sorting_results.json"), emit: results
    tuple val(meta), path("perform_facs_cell_sorting_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CELL_SUSPENSION_DATA="${params.cell_suspension_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FLUORESCENCE_PARAMETER="${params.fluorescence_parameter?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD_MIN="${params.threshold_min?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD_MAX="${params.threshold_max?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def perform_facs_cell_sorting(
    cell_suspension_data,
    fluorescence_parameter,
    threshold_min=None,
    threshold_max=None,
    output_file="sorted_cells.csv",
):
    '''Performs Fluorescence-Activated Cell Sorting (FACS) to enrich cell populations based on fluorescence characteristics.

    Parameters
    ----------
    cell_suspension_data : str
        Path to the FCS file containing flow cytometry data
    fluorescence_parameter : str
        The fluorescence parameter to use for sorting (e.g., 'GFP', 'FITC', 'PE')
    threshold_min : float, optional
        Minimum threshold for the fluorescence parameter. Cells below this value will be excluded
    threshold_max : float, optional
        Maximum threshold for the fluorescence parameter. Cells above this value will be excluded
    output_file : str, optional
        Filename to save the sorted cell population data

    Returns
    -------
    str
        Research log detailing the FACS cell sorting process

    '''
    import os

    import pandas as pd

    # Initialize research log
    log = "# FACS-based Cell Sorting and Enrichment Research Log\\n\\n"

    try:
        import numpy as np
        import flowio

        # Load cell suspension data
        log += "## Loading Cell Suspension Data\\n"
        if isinstance(cell_suspension_data, str):
            # If data is provided as a file path
            if cell_suspension_data.lower().endswith(".fcs"):
                # Use flowio for numpy 2.x compatibility
                fd = flowio.FlowData(cell_suspension_data, ignore_offset_error=True, ignore_offset_discrepancy=True)
                cell_df = pd.DataFrame(
                    np.reshape(fd.events, (-1, fd.channel_count)),
                    columns=[fd.channels[k]['pnn'] for k in sorted(fd.channels.keys())]
                )
                log += f"Successfully loaded FCS file containing {len(cell_df)} cells\\n"
                log += f"Available channels: {list(cell_df.columns)}\\n"
            else:
                # Assume CSV or other tabular format
                cell_df = pd.read_csv(cell_suspension_data)
                log += f"Loaded data file containing {len(cell_df)} cells\\n"
        else:
            # Assume data is already a DataFrame
            cell_df = cell_suspension_data.copy()
            log += f"Using provided DataFrame containing {len(cell_df)} cells\\n"

        # Validate fluorescence parameter exists in data
        if fluorescence_parameter not in cell_df.columns:
            raise ValueError(f"Fluorescence parameter '{fluorescence_parameter}' not found in data")

        # Apply gating strategy based on fluorescence thresholds
        log += f"\\n## Applying Gating Strategy for {fluorescence_parameter}\\n"
        original_count = len(cell_df)

        # Filter cells based on min/max thresholds
        if threshold_min is not None:
            cell_df = cell_df[cell_df[fluorescence_parameter] >= threshold_min]
            log += f"Applied minimum threshold of {threshold_min}: {len(cell_df)} cells remaining\\n"

        if threshold_max is not None:
            cell_df = cell_df[cell_df[fluorescence_parameter] <= threshold_max]
            log += f"Applied maximum threshold of {threshold_max}: {len(cell_df)} cells remaining\\n"

        # Calculate enrichment statistics
        enrichment_percent = (len(cell_df) / original_count) * 100 if original_count > 0 else 0
        log += "\\n## Enrichment Results\\n"
        log += f"Original population: {original_count} cells\\n"
        log += f"Sorted population: {len(cell_df)} cells\\n"
        log += f"Enrichment percentage: {enrichment_percent:.2f}%\\n"

        # Calculate statistics of sorted population
        mean_fluorescence = cell_df[fluorescence_parameter].mean()
        median_fluorescence = cell_df[fluorescence_parameter].median()

        log += f"Mean {fluorescence_parameter}: {mean_fluorescence:.2f}\\n"
        log += f"Median {fluorescence_parameter}: {median_fluorescence:.2f}\\n"

        # Save sorted population to file
        cell_df.to_csv(output_file, index=False)
        log += "\\n## Output\\n"
        log += f"Sorted cell population saved to: {os.path.abspath(output_file)}\\n"

        return log

    except Exception as e:
        log += "\\n## Error\\n"
        log += f"An error occurred during cell sorting: {str(e)}\\n"
        return log

# Execute the function
try:
    result = perform_facs_cell_sorting(
        cell_suspension_data=auto_convert(os.environ.get("PARAM_CELL_SUSPENSION_DATA", "")),
        fluorescence_parameter=auto_convert(os.environ.get("PARAM_FLUORESCENCE_PARAMETER", "")),
        threshold_min=auto_convert(os.environ.get("PARAM_THRESHOLD_MIN", "")),
        threshold_max=auto_convert(os.environ.get("PARAM_THRESHOLD_MAX", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "sorted_cells.csv")),
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
    "function": "perform_facs_cell_sorting",
    "domain": "cell_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("perform_facs_cell_sorting_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("perform_facs_cell_sorting_output.txt", "w") as f:
    f.write("Biomni: Perform Facs Cell Sorting" + NL)
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
        biomni_function: "perform_facs_cell_sorting"
    END_VERSIONS
    """
}

workflow PERFORM_FACS_CELL_SORTING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PERFORM_FACS_CELL_SORTING(ch_input)

    emit:
    results = PERFORM_FACS_CELL_SORTING.out.results
    output = PERFORM_FACS_CELL_SORTING.out.output
    versions = PERFORM_FACS_CELL_SORTING.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PERFORM_FACS_CELL_SORTING_WORKFLOW(ch_input)

    PERFORM_FACS_CELL_SORTING_WORKFLOW.out.output.view { "Output: $it" }
}
