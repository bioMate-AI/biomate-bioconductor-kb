#!/usr/bin/env nextflow
/*
 * physiology/analyze_fatty_acid_composition_by_gc
 * Analyzes fatty acid composition in tissue samples using gas chromatography data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.gc_data_file = null
params.tissue_type = null
params.sample_id = null
params.output_directory = './results'

process ANALYZE_FATTY_ACID_COMPOSITION_BY_GC {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_fatty_acid_composition_by_gc_results.json"), emit: results
    tuple val(meta), path("analyze_fatty_acid_composition_by_gc_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_GC_DATA_FILE="${params.gc_data_file?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TISSUE_TYPE="${params.tissue_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAMPLE_ID="${params.sample_id?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIRECTORY="${params.output_directory?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_fatty_acid_composition_by_gc(gc_data_file, tissue_type, sample_id, output_directory="./results"):
    '''Analyzes fatty acid composition in tissue samples using gas chromatography data.

    Parameters
    ----------
    gc_data_file : str
        Path to the CSV file containing gas chromatography data with columns 'retention_time' and 'peak_area'.
    tissue_type : str
        Type of tissue sample (e.g., liver, kidney, heart, muscle, adipose).
    sample_id : str
        Identifier for the sample being analyzed.
    output_directory : str, optional
        Directory where result files will be saved (default: "./results").

    Returns
    -------
    str
        Research log summarizing the analysis steps and results.

    '''
    import os
    from datetime import datetime

    import pandas as pd

    os.makedirs(output_directory, exist_ok=True)

    log = "FATTY ACID COMPOSITION ANALYSIS LOG\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += f"Sample ID: {sample_id}\\n"
    log += f"Tissue Type: {tissue_type}\\n\\n"

    log += "Step 1: Loading gas chromatography data\\n"
    try:
        gc_data = pd.read_csv(gc_data_file)
        expected_cols = {"retention_time", "peak_area"}
        if not expected_cols.issubset(gc_data.columns):
            missing_cols = expected_cols - set(gc_data.columns)
            log += f"  - Error: Missing columns: {', '.join(missing_cols)}\\n"
            return log
        log += f"  - Successfully loaded data from {gc_data_file}\\n"
        log += f"  - Data contains {len(gc_data)} data points\\n\\n"
    except Exception as e:
        log += f"  - Error loading data: {str(e)}\\n"
        return log

    log += "Step 2: Identifying fatty acid peaks\\n"

    fatty_acid_standards = {
        (2.1, 2.3): "Myristic acid (C14:0)",
        (2.8, 3.0): "Palmitic acid (C16:0)",
        (3.1, 3.3): "Palmitoleic acid (C16:1)",
        (3.7, 3.9): "Stearic acid (C18:0)",
        (4.0, 4.2): "Oleic acid (C18:1)",
        (4.4, 4.6): "Linoleic acid (C18:2)",
        (4.7, 4.9): "α-Linolenic acid (C18:3)",
        (5.1, 5.3): "Arachidonic acid (C20:4)",
        (5.5, 5.7): "EPA (C20:5)",
        (6.3, 6.5): "DHA (C22:6)",
        (5.8, 6.0): "t10c12-CLA",
    }

    total_area = gc_data["peak_area"].sum()
    if total_area == 0:
        log += "  - Error: Total peak area is zero, cannot calculate percentages.\\n"
        return log

    identified_peaks = {}
    for (rt_min, rt_max), fatty_acid in fatty_acid_standards.items():
        peaks_in_range = gc_data[(gc_data["retention_time"] >= rt_min) & (gc_data["retention_time"] <= rt_max)]
        area = peaks_in_range["peak_area"].sum()
        percentage = (area / total_area) * 100 if area > 0 else 0.0
        identified_peaks[fatty_acid] = {"area": area, "percentage": percentage}
        log += f"  - {fatty_acid}: {percentage:.2f}% ({'Detected' if area > 0 else 'Not Detected'})\\n"

    detected_count = sum(1 for fa in identified_peaks.values() if fa["area"] > 0)
    log += f"  - Total detected fatty acids: {detected_count}/{len(fatty_acid_standards)}\\n\\n"

    log += "Step 3: Generating fatty acid composition results\\n"
    results = (
        pd.DataFrame(
            {
                "Fatty Acid": list(identified_peaks),
                "Peak Area": [identified_peaks[fa]["area"] for fa in identified_peaks],
                "Percentage (%)": [identified_peaks[fa]["percentage"] for fa in identified_peaks],
            }
        )
        .sort_values("Percentage (%)", ascending=False)
        .reset_index(drop=True)
    )

    output_file = os.path.join(output_directory, f"{sample_id}_{tissue_type}_fatty_acid_composition.csv")
    results.to_csv(output_file, index=False)
    log += f"  - Results saved to: {output_file}\\n\\n"

    log += "Step 4: Summary of fatty acid composition\\n"
    detected_results = results[results["Peak Area"] > 0]
    if not detected_results.empty:
        top_fatty_acids = detected_results.head(3)
        log += "  - Most abundant fatty acids:\\n"
        for _, row in top_fatty_acids.iterrows():
            log += f"    * {row['Fatty Acid']}: {row['Percentage (%)']:.2f}%\\n"

        saturated = [
            "Myristic acid (C14:0)",
            "Palmitic acid (C16:0)",
            "Stearic acid (C18:0)",
        ]
        unsaturated = [fa for fa in identified_peaks if fa not in saturated]

        saturated_total = sum(identified_peaks[fa]["percentage"] for fa in saturated)
        unsaturated_total = sum(identified_peaks[fa]["percentage"] for fa in unsaturated)

        if unsaturated_total > 0:
            sat_unsat_ratio = saturated_total / unsaturated_total
            log += f"  - Saturated to unsaturated fatty acid ratio: {sat_unsat_ratio:.2f}\\n"
        else:
            log += "  - Unsaturated fatty acids not detected; cannot calculate ratio.\\n"
    else:
        log += "  - No fatty acids detected; please verify input data.\\n"

    log += "\\nAnalysis completed successfully."

    return log

# Execute the function
try:
    result = analyze_fatty_acid_composition_by_gc(
        gc_data_file=auto_convert(os.environ.get("PARAM_GC_DATA_FILE", "")),
        tissue_type=auto_convert(os.environ.get("PARAM_TISSUE_TYPE", "")),
        sample_id=auto_convert(os.environ.get("PARAM_SAMPLE_ID", "")),
        output_directory=auto_convert(os.environ.get("PARAM_OUTPUT_DIRECTORY", "./results")),
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
    "function": "analyze_fatty_acid_composition_by_gc",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_fatty_acid_composition_by_gc_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_fatty_acid_composition_by_gc_output.txt", "w") as f:
    f.write("Biomni: Analyze Fatty Acid Composition By Gc" + NL)
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
        biomni_function: "analyze_fatty_acid_composition_by_gc"
    END_VERSIONS
    """
}

workflow ANALYZE_FATTY_ACID_COMPOSITION_BY_GC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_FATTY_ACID_COMPOSITION_BY_GC(ch_input)

    emit:
    results = ANALYZE_FATTY_ACID_COMPOSITION_BY_GC.out.results
    output = ANALYZE_FATTY_ACID_COMPOSITION_BY_GC.out.output
    versions = ANALYZE_FATTY_ACID_COMPOSITION_BY_GC.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_FATTY_ACID_COMPOSITION_BY_GC_WORKFLOW(ch_input)

    ANALYZE_FATTY_ACID_COMPOSITION_BY_GC_WORKFLOW.out.output.view { "Output: $it" }
}
