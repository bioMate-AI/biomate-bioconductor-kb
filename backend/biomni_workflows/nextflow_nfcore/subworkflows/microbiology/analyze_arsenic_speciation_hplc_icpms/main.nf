#!/usr/bin/env nextflow
/*
 * microbiology/analyze_arsenic_speciation_hplc_icpms
 * Analyzes arsenic speciation in liquid samples using HPLC-ICP-MS technique.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: HPLC-ICP-MS arsenic speciation chromatogram (sample_id -> {retention_time: intensity})
params.sample_data = '{"Sample_A": {"2.8": 1250, "7.5": 3400, "5.3": 890}, "Sample_B": {"2.8": 980, "7.5": 2100, "5.3": 1450}}'
params.sample_name = 'Environmental_Water_Sample'
params.calibration_data = null

process ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_arsenic_speciation_hplc_icpms_results.json"), emit: results
    tuple val(meta), path("analyze_arsenic_speciation_hplc_icpms_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SAMPLE_DATA="${params.sample_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAMPLE_NAME="${params.sample_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CALIBRATION_DATA="${params.calibration_data?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_arsenic_speciation_hplc_icpms(sample_data, sample_name="Unknown Sample", calibration_data=None):
    '''Analyzes arsenic speciation in liquid samples using HPLC-ICP-MS technique.

    Parameters
    ----------
    sample_data : dict
        Dictionary containing sample data with keys as sample IDs and values as dictionaries
        with retention times (in minutes) as keys and signal intensities as values.
    sample_name : str, optional
        Name of the sample being analyzed (default: "Unknown Sample")
    calibration_data : dict, optional
        Dictionary containing calibration standards data with known concentrations for each arsenic species.
        If None, default calibration values will be used.

    Returns
    -------
    str
        A research log summarizing the steps of the analysis and results.

    '''
    from datetime import datetime

    import pandas as pd

    # Start research log
    log = "# Arsenic Speciation Analysis by HPLC-ICP-MS\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += f"Sample: {sample_name}\\n\\n"

    # Step 1: Sample preparation
    log += "## 1. Sample Preparation\\n"
    log += "- Filtered sample through 0.45 μm filter\\n"
    log += "- Diluted sample with mobile phase (if necessary)\\n"
    log += "- Prepared for injection into HPLC system\\n\\n"

    # Step 2: HPLC-ICP-MS Analysis
    log += "## 2. HPLC-ICP-MS Analysis\\n"
    log += "- Column: Anion exchange column\\n"
    log += "- Mobile phase: 20 mM NH4H2PO4 (pH 6.0)\\n"
    log += "- Flow rate: 1.0 mL/min\\n"
    log += "- Injection volume: 50 μL\\n"
    log += "- ICP-MS detection: m/z 75 for arsenic\\n\\n"

    # Step 3: Chromatographic separation and detection
    log += "## 3. Chromatographic Separation and Detection\\n"
    log += "- Running chromatographic separation\\n"
    log += "- Monitoring arsenic signal (m/z 75)\\n"
    log += "- Collecting retention time data for species identification\\n\\n"

    # Define retention times for arsenic species (in minutes)
    arsenic_species = {
        "As(III)": 2.8,
        "As(V)": 7.5,
        "MMAs(III)": 3.9,
        "MMAs(V)": 6.2,
        "DMAs(III)": 4.7,
        "DMAs(V)": 5.3,
    }

    # Default calibration factors if not provided
    if calibration_data is None:
        calibration_data = {
            "As(III)": {"factor": 0.85, "limit": 0.1},
            "As(V)": {"factor": 0.92, "limit": 0.1},
            "MMAs(III)": {"factor": 0.78, "limit": 0.2},
            "MMAs(V)": {"factor": 0.88, "limit": 0.15},
            "DMAs(III)": {"factor": 0.81, "limit": 0.2},
            "DMAs(V)": {"factor": 0.90, "limit": 0.15},
        }

    # Step 4: Data analysis and quantification
    log += "## 4. Data Analysis and Quantification\\n"

    # Process sample data to identify and quantify arsenic species
    results = {}

    for sample_id, sample in sample_data.items():
        species_concentrations = {}

        for species_name, expected_rt in arsenic_species.items():
            # Find the closest retention time in the sample data
            closest_rt = min(sample.keys(), key=lambda rt: abs(rt - expected_rt))

            # Check if the retention time is within an acceptable range (±0.3 min)
            if abs(closest_rt - expected_rt) <= 0.3:
                # Calculate concentration using calibration factor
                intensity = sample[closest_rt]
                concentration = intensity * calibration_data[species_name]["factor"]

                # Check if concentration is above detection limit
                if concentration >= calibration_data[species_name]["limit"]:
                    species_concentrations[species_name] = concentration
                else:
                    species_concentrations[species_name] = (
                        f"<{calibration_data[species_name]['limit']} (Below detection limit)"
                    )
            else:
                species_concentrations[species_name] = "Not detected"

        results[sample_id] = species_concentrations

    # Convert results to DataFrame for easier handling
    results_df = pd.DataFrame.from_dict(results, orient="index")

    # Log the detection and quantification process
    log += "- Identified arsenic species based on retention times\\n"
    log += "- Quantified concentrations using calibration standards\\n"
    log += "- Applied detection limits for each species\\n\\n"

    # Step 5: Results
    log += "## 5. Results\\n"
    log += "Detected arsenic species and their concentrations (μg/L):\\n\\n"

    # Create a results file
    results_filename = (
        f"arsenic_speciation_results_{sample_name.replace(' ', '_')}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.csv"
    )
    results_df.to_csv(results_filename)

    log += f"Results have been saved to: {results_filename}\\n\\n"

    # Summary of findings
    log += "## 6. Summary\\n"

    # Identify predominant species
    for sample_id, species_data in results.items():
        numeric_concs = {k: v for k, v in species_data.items() if isinstance(v, int | float)}
        if numeric_concs:
            predominant_species = max(numeric_concs.items(), key=lambda x: x[1])
            log += f"Sample {sample_id}: Predominant arsenic species is {predominant_species[0]} "
            log += f"at {predominant_species[1]:.2f} μg/L\\n"
        else:
            log += f"Sample {sample_id}: No arsenic species detected above quantification limits\\n"

    return log

# Execute the function
try:
    # Convert sample_data keys from strings to floats (JSON doesn't support non-string keys)
    sample_data_raw = auto_convert(os.environ.get("PARAM_SAMPLE_DATA", ""))
    if isinstance(sample_data_raw, dict):
        sample_data = {
            sample_id: {float(rt): intensity for rt, intensity in sample.items()}
            for sample_id, sample in sample_data_raw.items()
        }
    else:
        sample_data = sample_data_raw

    result = analyze_arsenic_speciation_hplc_icpms(
        sample_data=sample_data,
        sample_name=auto_convert(os.environ.get("PARAM_SAMPLE_NAME", "Unknown Sample")),
        calibration_data=auto_convert(os.environ.get("PARAM_CALIBRATION_DATA", "")),
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
    "function": "analyze_arsenic_speciation_hplc_icpms",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_arsenic_speciation_hplc_icpms_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_arsenic_speciation_hplc_icpms_output.txt", "w") as f:
    f.write("Biomni: Analyze Arsenic Speciation Hplc Icpms" + NL)
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
        biomni_function: "analyze_arsenic_speciation_hplc_icpms"
    END_VERSIONS
    """
}

workflow ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS(ch_input)

    emit:
    results = ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS.out.results
    output = ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS.out.output
    versions = ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS_WORKFLOW(ch_input)

    ANALYZE_ARSENIC_SPECIATION_HPLC_ICPMS_WORKFLOW.out.output.view { "Output: $it" }
}
