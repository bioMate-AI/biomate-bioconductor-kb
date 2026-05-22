#!/usr/bin/env nextflow
/*
 * pharmacology/estimate_alpha_particle_radiotherapy_dosimetry
 * Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Biodistribution data (organ: [(time_hours, %injected_activity), ...])
params.biodistribution_data = '{"tumor": [[1, 5.2], [4, 8.5], [24, 12.3], [48, 10.1], [72, 7.8]], "liver": [[1, 25.1], [4, 22.3], [24, 15.2], [48, 10.5], [72, 6.8]], "kidney": [[1, 18.2], [4, 15.5], [24, 8.3], [48, 5.1], [72, 3.2]], "bone": [[1, 3.5], [4, 4.2], [24, 5.1], [48, 4.8], [72, 4.5]]}'
// Radiation parameters for Ac-225
params.radiation_parameters = '{"radionuclide": "Ac-225", "half_life_hours": 240, "energy_per_decay_MeV": 28.0, "radiation_weighting_factor": 20, "S_factors": {"tumor": 2.5e-12, "liver": 1.8e-12, "kidney": 3.2e-12, "bone": 1.5e-12}}'
params.output_file = 'dosimetry_results.csv'

process ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("estimate_alpha_particle_radiotherapy_dosimetry_results.json"), emit: results
    tuple val(meta), path("estimate_alpha_particle_radiotherapy_dosimetry_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_BIODISTRIBUTION_DATA="${params.biodistribution_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RADIATION_PARAMETERS="${params.radiation_parameters?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILE="${params.output_file?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
from datetime import datetime
import numpy as np
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



def estimate_alpha_particle_radiotherapy_dosimetry(
    biodistribution_data, radiation_parameters, output_file="dosimetry_results.csv"
):
    '''Estimate radiation absorbed doses to tumor and normal organs for alpha-particle radiotherapeutics.

    This function implements the Medical Internal Radiation Dose (MIRD) schema to calculate
    absorbed doses based on biodistribution data from healthy mice and radiation transport parameters.

    Parameters
    ----------
    biodistribution_data : dict
        Dictionary containing organ/tissue names as keys and a list of time-activity measurements as values.
        Each measurement should be a tuple of (time_hours, percent_injected_activity).
        Must include entries for all relevant organs including 'tumor'.

    radiation_parameters : dict
        Dictionary containing radiation parameters for the alpha-emitting radionuclide:
        - 'radionuclide': str - Name of the radionuclide (e.g., 'Ac-225')
        - 'half_life_hours': float - Physical half-life in hours
        - 'energy_per_decay_MeV': float - Energy released per decay in MeV
        - 'radiation_weighting_factor': float - Radiation weighting factor for alpha particles
        - 'S_factors': dict - S-factors (Gy/Bq-s) for each source-target organ pair

    output_file : str, optional
        Filename to save the dosimetry results (default: "dosimetry_results.csv")

    Returns
    -------
    str
        Research log summarizing the dosimetry estimation process and results

    '''
    import csv
    from datetime import datetime

    import numpy as np
    from scipy.integrate import trapezoid

    # Initialize research log
    log = f"Alpha-Particle Radiotherapy Dosimetry Estimation - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += f"Radionuclide: {radiation_parameters['radionuclide']}\\n"
    log += f"Half-life: {radiation_parameters['half_life_hours']} hours\\n\\n"

    # Step 1: Calculate time-integrated activity for each organ
    log += "Step 1: Calculating time-integrated activity for each organ\\n"
    time_integrated_activity = {}

    for organ, measurements in biodistribution_data.items():
        times = [m[0] for m in measurements]
        activities = [m[1] for m in measurements]

        # Apply physical decay correction
        decay_constant = np.log(2) / radiation_parameters["half_life_hours"]
        decay_corrected_activities = [a * np.exp(-decay_constant * t) for a, t in zip(activities, times, strict=False)]

        # Calculate time-integrated activity using trapezoidal integration
        cumulated_activity = trapezoid(decay_corrected_activities, times)
        time_integrated_activity[organ] = cumulated_activity

        log += f"  - {organ}: {cumulated_activity:.4f} %IA-h\\n"

    # Step 2: Calculate absorbed dose using MIRD schema
    log += "\\nStep 2: Calculating absorbed doses using MIRD schema\\n"

    # Convert %IA-h to MBq-h for a standard injection of 1 MBq
    conversion_factor = 0.01  # Convert %IA to fraction of IA

    # Energy conversion factor: MeV to J

    # Calculate absorbed dose for each target organ
    absorbed_doses = {}
    s_factors = radiation_parameters["S_factors"]

    for target_organ in biodistribution_data:
        absorbed_dose = 0

        # Sum contributions from all source organs
        for source_organ, cumulated_activity in time_integrated_activity.items():
            if (source_organ, target_organ) in s_factors:
                s_value = s_factors[(source_organ, target_organ)]
                organ_contribution = cumulated_activity * conversion_factor * s_value
                absorbed_dose += organ_contribution

        # Apply radiation weighting factor for alpha particles
        absorbed_dose *= radiation_parameters["radiation_weighting_factor"]

        # Store as Gy/MBq
        absorbed_doses[target_organ] = absorbed_dose
        log += f"  - {target_organ}: {absorbed_dose:.4f} Gy/MBq\\n"

    # Step 3: Calculate therapeutic index (tumor-to-normal tissue dose ratios)
    log += "\\nStep 3: Calculating therapeutic indices (tumor-to-normal tissue ratios)\\n"

    tumor_dose = absorbed_doses.get("tumor", 0)
    if tumor_dose > 0:
        for organ, dose in absorbed_doses.items():
            if organ != "tumor" and dose > 0:
                therapeutic_index = tumor_dose / dose
                log += f"  - Tumor-to-{organ} ratio: {therapeutic_index:.2f}\\n"

    # Save results to CSV file
    with open(output_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Organ", "Absorbed Dose (Gy/MBq)"])
        for organ, dose in absorbed_doses.items():
            writer.writerow([organ, f"{dose:.4f}"])

    log += f"\\nDosimetry results saved to {output_file}\\n"

    return log

# Execute the function
try:
    result = estimate_alpha_particle_radiotherapy_dosimetry(
        biodistribution_data=auto_convert(os.environ.get("PARAM_BIODISTRIBUTION_DATA", "")),
        radiation_parameters=auto_convert(os.environ.get("PARAM_RADIATION_PARAMETERS", "")),
        output_file=auto_convert(os.environ.get("PARAM_OUTPUT_FILE", "dosimetry_results.csv")),
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
    "function": "estimate_alpha_particle_radiotherapy_dosimetry",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("estimate_alpha_particle_radiotherapy_dosimetry_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("estimate_alpha_particle_radiotherapy_dosimetry_output.txt", "w") as f:
    f.write("Biomni: Estimate Alpha Particle Radiotherapy Dosimetry" + NL)
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
        biomni_function: "estimate_alpha_particle_radiotherapy_dosimetry"
    END_VERSIONS
    """
}

workflow ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY(ch_input)

    emit:
    results = ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY.out.results
    output = ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY.out.output
    versions = ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY_WORKFLOW(ch_input)

    ESTIMATE_ALPHA_PARTICLE_RADIOTHERAPY_DOSIMETRY_WORKFLOW.out.output.view { "Output: $it" }
}
