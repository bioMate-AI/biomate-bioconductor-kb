#!/usr/bin/env nextflow
/*
 * cell_biology/analyze_flow_cytometry_immunophenotyping
 * Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fcs_file_path = null
params.gating_strategy = null
params.compensation_matrix = null
params.output_dir = './results'

process ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_flow_cytometry_immunophenotyping_results.json"), emit: results
    tuple val(meta), path("analyze_flow_cytometry_immunophenotyping_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FCS_FILE_PATH="${params.fcs_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GATING_STRATEGY="${params.gating_strategy?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_COMPENSATION_MATRIX="${params.compensation_matrix?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_flow_cytometry_immunophenotyping(
    fcs_file_path, gating_strategy, compensation_matrix=None, output_dir="./results"
):
    '''Analyze flow cytometry data to identify and quantify specific cell populations based on surface markers.

    Parameters
    ----------
    fcs_file_path : str
        Path to the FCS file containing flow cytometry data
    gating_strategy : dict
        Dictionary defining the gating strategy. Each key is a population name, and each value is a list of tuples
        (marker, operator, threshold). For example: {'HSCs': [('Lin', '<', 100), ('Sca1', '>', 1000), ...]}
    compensation_matrix : numpy.ndarray, optional
        Spillover/compensation matrix to correct for fluorescence overlap
    output_dir : str, optional
        Directory to save the results

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

    # Load the FCS file
    sample = FCMeasurement(ID="Sample", datafile=fcs_file_path)

    # Apply compensation if provided
    if compensation_matrix is not None:
        sample = sample.compensate(compensation_matrix)

    # Initialize log
    log = "Flow Cytometry Analysis Log\\n"
    log += "==========================\\n"
    log += f"File analyzed: {os.path.basename(fcs_file_path)}\\n"
    log += f"Total events: {len(sample)}\\n\\n"

    # Create a dictionary to store population counts
    populations = {}

    # Apply gating strategy to identify cell populations
    for pop_name, gates in gating_strategy.items():
        # Start with all events
        current_population = sample.copy()

        log += f"Identifying {pop_name} population:\\n"

        # Apply each gate sequentially
        for marker, operator, threshold in gates:
            initial_count = len(current_population)

            if operator == ">":
                current_population = current_population.gate(f"{marker} > {threshold}")
            elif operator == "<":
                current_population = current_population.gate(f"{marker} < {threshold}")
            elif operator == "between":
                # For 'between', threshold should be a tuple (lower, upper)
                lower, upper = threshold
                current_population = current_population.gate(f"{marker} > {lower} and {marker} < {upper}")

            final_count = len(current_population)
            log += f"  Gate {marker} {operator} {threshold}: {initial_count} → {final_count} events\\n"

        # Store the final population
        populations[pop_name] = current_population

        # Calculate percentage of original sample
        percentage = (len(current_population) / len(sample)) * 100
        log += f"  Final {pop_name} count: {len(current_population)} events ({percentage:.2f}% of total)\\n\\n"

    # Create a summary dataframe
    summary_data = {"Population": [], "Count": [], "Percentage": []}

    for pop_name, population in populations.items():
        summary_data["Population"].append(pop_name)
        summary_data["Count"].append(len(population))
        summary_data["Percentage"].append((len(population) / len(sample)) * 100)

    summary_df = pd.DataFrame(summary_data)

    # Save the summary to a CSV file
    summary_file = os.path.join(output_dir, "population_summary.csv")
    summary_df.to_csv(summary_file, index=False)

    log += "Summary of identified populations:\\n"
    for _, row in summary_df.iterrows():
        log += f"  {row['Population']}: {row['Count']} events ({row['Percentage']:.2f}%)\\n"

    log += f"\\nDetailed results saved to: {summary_file}\\n"

    return log

# Execute the function
try:
    result = analyze_flow_cytometry_immunophenotyping(
        fcs_file_path=auto_convert(os.environ.get("PARAM_FCS_FILE_PATH", "")),
        gating_strategy=auto_convert(os.environ.get("PARAM_GATING_STRATEGY", "")),
        compensation_matrix=auto_convert(os.environ.get("PARAM_COMPENSATION_MATRIX", "")),
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
    "function": "analyze_flow_cytometry_immunophenotyping",
    "domain": "cell_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_flow_cytometry_immunophenotyping_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_flow_cytometry_immunophenotyping_output.txt", "w") as f:
    f.write("Biomni: Analyze Flow Cytometry Immunophenotyping" + NL)
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
        biomni_function: "analyze_flow_cytometry_immunophenotyping"
    END_VERSIONS
    """
}

workflow ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING(ch_input)

    emit:
    results = ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.results
    output = ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.output
    versions = ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING_WORKFLOW(ch_input)

    ANALYZE_FLOW_CYTOMETRY_IMMUNOPHENOTYPING_WORKFLOW.out.output.view { "Output: $it" }
}
