#!/usr/bin/env nextflow
/*
 * microbiology/enumerate_bacterial_cfu_by_serial_dilution
 * Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.initial_sample_volume_ml = '1.0'
params.estimated_concentration = '100000000.0'
params.dilution_factor = '10'
params.num_dilutions = '8'
params.spots_per_dilution = '3'
params.output_file = 'cfu_enumeration_results.csv'

process ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("enumerate_bacterial_cfu_by_serial_dilution_results.json"), emit: results
    tuple val(meta), path("enumerate_bacterial_cfu_by_serial_dilution_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INITIAL_SAMPLE_VOLUME_ML="${params.initial_sample_volume_ml?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ESTIMATED_CONCENTRATION="${params.estimated_concentration?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DILUTION_FACTOR="${params.dilution_factor?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_DILUTIONS="${params.num_dilutions?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SPOTS_PER_DILUTION="${params.spots_per_dilution?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def enumerate_bacterial_cfu_by_serial_dilution(
    initial_sample_volume_ml=1.0,
    estimated_concentration=1e8,
    dilution_factor=10,
    num_dilutions=8,
    spots_per_dilution=3,
    output_file="cfu_enumeration_results.csv",
):
    '''Quantify bacterial concentration (CFU/mL) using serial dilutions and spot plating.

    Parameters
    ----------
    initial_sample_volume_ml : float
        Volume of the initial bacterial sample in milliliters
    estimated_concentration : float
        Estimated concentration of bacteria in the initial sample (CFU/mL)
    dilution_factor : int
        Factor by which each dilution reduces the concentration (typically 10)
    num_dilutions : int
        Number of serial dilutions to perform
    spots_per_dilution : int
        Number of replicate spots to plate for each dilution
    output_file : str
        Filename to save the CFU enumeration results

    Returns
    -------
    str
        Research log summarizing the CFU enumeration process

    '''
    import numpy as np
    import pandas as pd

    # Generate log
    log = "# Bacterial CFU Enumeration via Serial Dilutions and Spot Plating\\n\\n"

    # Step 1: Prepare serial dilutions
    log += "## Step 1: Serial Dilution Preparation\\n"
    log += f"- Initial sample volume: {initial_sample_volume_ml} mL\\n"
    log += f"- Estimated concentration: {estimated_concentration:.2e} CFU/mL\\n"
    log += f"- Dilution factor: {dilution_factor}\\n"
    log += f"- Number of dilutions: {num_dilutions}\\n\\n"

    # Calculate theoretical concentrations at each dilution
    dilution_concentrations = []
    for i in range(num_dilutions + 1):  # +1 to include the undiluted sample
        conc = estimated_concentration / (dilution_factor**i)
        dilution_concentrations.append(conc)
        dilution_name = "Undiluted" if i == 0 else f"10^-{i}"
        log += f"  {dilution_name}: {conc:.2e} CFU/mL\\n"

    # Step 2: Spot plating
    log += "\\n## Step 2: Spot Plating\\n"
    log += f"- Spots per dilution: {spots_per_dilution}\\n"
    log += "- Spotting 10 μL from each dilution onto agar plates\\n\\n"

    # Simulate bacterial growth with some randomness to mimic real-world variation
    np.random.seed(42)  # For reproducibility

    # Create dataframe to store results
    results = []

    # For each dilution, simulate spotting and counting
    for i in range(num_dilutions + 1):
        dilution_name = "Undiluted" if i == 0 else f"10^-{i}"
        expected_cfu_per_spot = dilution_concentrations[i] * 0.01  # 10 μL = 0.01 mL

        # Simulate multiple spots per dilution
        spot_counts = []
        for spot in range(spots_per_dilution):
            # Add some randomness to the counts (Poisson distribution for bacterial counts)
            if expected_cfu_per_spot > 300:
                # Too many to count (TMTC)
                count = "TMTC"
                spot_counts.append(count)
            elif expected_cfu_per_spot < 1:
                # Simulate low probability events
                count = np.random.poisson(expected_cfu_per_spot)
                spot_counts.append(count)
            else:
                # Normal counting range
                count = np.random.poisson(expected_cfu_per_spot)
                spot_counts.append(count)

            results.append(
                {
                    "Dilution": dilution_name,
                    "Dilution_Factor": dilution_factor**i,
                    "Spot": spot + 1,
                    "CFU_Count": count,
                }
            )

    # Convert results to dataframe
    df = pd.DataFrame(results)

    # Step 3: Colony counting and CFU calculation
    log += "## Step 3: Colony Counting and CFU Calculation\\n\\n"

    # Find the first dilution with countable colonies (between 3 and 300 CFU)
    countable_dilutions = []

    for i in range(num_dilutions + 1):
        dilution_name = "Undiluted" if i == 0 else f"10^-{i}"
        dilution_data = df[df["Dilution"] == dilution_name]

        # Check if counts are numeric (not TMTC)
        numeric_counts = [c for c in dilution_data["CFU_Count"] if isinstance(c, int | float)]

        if numeric_counts:
            avg_count = sum(numeric_counts) / len(numeric_counts)
            if 3 <= avg_count <= 300:
                countable_dilutions.append(
                    {
                        "Dilution": dilution_name,
                        "Dilution_Factor": dilution_factor**i,
                        "Average_CFU": avg_count,
                        "CFU_per_mL": avg_count * 100 * (dilution_factor**i),  # × 100 to convert 10 μL to mL
                    }
                )

    # Calculate final CFU/mL based on countable dilutions
    if countable_dilutions:
        countable_df = pd.DataFrame(countable_dilutions)

        # Log the counts for each countable dilution
        for _, row in countable_df.iterrows():
            log += f"Dilution {row['Dilution']}: Average CFU per spot = {row['Average_CFU']:.1f}\\n"
            log += f"  Calculated concentration: {row['CFU_per_mL']:.2e} CFU/mL\\n\\n"

        # Calculate the final CFU/mL as the average of all countable dilutions
        final_cfu = countable_df["CFU_per_mL"].mean()
        log += "## Final Result\\n"
        log += f"Original sample concentration: {final_cfu:.2e} CFU/mL\\n"
    else:
        log += "No countable dilutions found. Consider adjusting the dilution series.\\n"
        final_cfu = None

    # Save results to CSV
    df.to_csv(output_file, index=False)
    log += f"\\nDetailed results saved to: {output_file}\\n"

    return log

# Execute the function
try:
    result = enumerate_bacterial_cfu_by_serial_dilution(
        initial_sample_volume_ml=auto_convert(os.environ.get("PARAM_INITIAL_SAMPLE_VOLUME_ML", "1.0")),
        estimated_concentration=auto_convert(os.environ.get("PARAM_ESTIMATED_CONCENTRATION", "100000000.0")),
        dilution_factor=auto_convert(os.environ.get("PARAM_DILUTION_FACTOR", "10")),
        num_dilutions=auto_convert(os.environ.get("PARAM_NUM_DILUTIONS", "8")),
        spots_per_dilution=auto_convert(os.environ.get("PARAM_SPOTS_PER_DILUTION", "3")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "cfu_enumeration_results.csv")),
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
    "function": "enumerate_bacterial_cfu_by_serial_dilution",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("enumerate_bacterial_cfu_by_serial_dilution_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("enumerate_bacterial_cfu_by_serial_dilution_output.txt", "w") as f:
    f.write("Biomni: Enumerate Bacterial Cfu By Serial Dilution" + NL)
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
        biomni_function: "enumerate_bacterial_cfu_by_serial_dilution"
    END_VERSIONS
    """
}

workflow ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION(ch_input)

    emit:
    results = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.results
    output = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.output
    versions = ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION_WORKFLOW(ch_input)

    ENUMERATE_BACTERIAL_CFU_BY_SERIAL_DILUTION_WORKFLOW.out.output.view { "Output: $it" }
}
