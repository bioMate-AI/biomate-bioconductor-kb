#!/usr/bin/env nextflow
/*
 * pharmacology/analyze_accelerated_stability_of_pharmaceutical_formulations
 * Analyzes the stability of pharmaceutical formulations under accelerated storage conditions.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Default test data: Pharmaceutical stability testing experiment
params.formulations = '[{"name": "FormulationA", "active_ingredient": "Ibuprofen", "concentration": 20.0, "excipients": ["microcrystalline cellulose", "magnesium stearate"]}, {"name": "FormulationB", "active_ingredient": "Ibuprofen", "concentration": 40.0, "excipients": ["lactose", "povidone", "magnesium stearate"]}]'
params.storage_conditions = '[{"temperature": 25, "humidity": 60, "description": "Room Temperature"}, {"temperature": 40, "humidity": 75, "description": "Accelerated"}, {"temperature": 50, "humidity": 90, "description": "Stress"}]'
params.time_points = '[0, 30, 60, 90, 180, 365]'

process ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_accelerated_stability_of_pharmaceutical_formulations_results.json"), emit: results
    tuple val(meta), path("analyze_accelerated_stability_of_pharmaceutical_formulations_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FORMULATIONS="${params.formulations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_STORAGE_CONDITIONS="${params.storage_conditions?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import pandas as pd
import os
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



def analyze_accelerated_stability_of_pharmaceutical_formulations(formulations, storage_conditions, time_points):
    '''Analyzes the stability of pharmaceutical formulations under accelerated storage conditions.

    Parameters
    ----------
    formulations : list of dict
        List of formulation dictionaries, each containing:
        - 'name': str, name of the formulation
        - 'active_ingredient': str, name of the active pharmaceutical ingredient
        - 'concentration': float, concentration in mg/mL
        - 'excipients': list, list of excipients

    storage_conditions : list of dict
        List of storage condition dictionaries, each containing:
        - 'temperature': float, temperature in °C
        - 'humidity': float, relative humidity in percentage (optional for solid dosage forms)
        - 'description': str, description of storage condition (e.g., "Room Temperature", "Accelerated")

    time_points : list of int
        List of time points in days to evaluate stability

    Returns
    -------
    str
        Research log summarizing the stability testing process and results

    '''
    # Create output directory if it doesn't exist
    output_dir = "stability_test_results"
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Initialize results storage
    all_results = []

    # Process each formulation under each storage condition
    for formulation in formulations:
        for condition in storage_conditions:
            # Initialize stability parameters
            results = []

            # Get acceleration factor based on temperature (simplified Arrhenius equation)
            temp_c = condition["temperature"]
            accel_factor = 2 ** ((temp_c - 25) / 10)  # Rule of thumb: reaction rate doubles every 10°C

            # Add humidity effect for degradation if provided
            humidity_factor = 1.0
            if "humidity" in condition:
                humidity = condition["humidity"]
                # Simple model: higher humidity increases degradation rate
                humidity_factor = 1.0 + (humidity - 60) / 100 if humidity > 60 else 1.0

            # Calculate stability parameters at each time point
            initial_content = 100.0  # Starting at 100%

            for time in time_points:
                # Chemical stability (% of initial content)
                # Simple first-order degradation model
                effective_time = time * accel_factor * humidity_factor
                chemical_stability = initial_content * np.exp(-0.001 * effective_time)

                # Physical stability (score from 1-10, 10 being perfect)
                # Decreases over time, affected by temperature and humidity
                physical_stability = 10 - (0.05 * effective_time)
                physical_stability = max(1, physical_stability)  # Minimum score of 1

                # Particle size change (% increase from initial)
                # Some formulations show particle growth over time
                particle_size_change = (
                    0.2 * effective_time if "solid" in formulation.get("dosage_form", "").lower() else 0
                )

                results.append(
                    {
                        "Formulation": formulation["name"],
                        "Storage_Condition": condition["description"],
                        "Temperature_C": temp_c,
                        "Humidity_RH": condition.get("humidity", "N/A"),
                        "Time_Days": time,
                        "Chemical_Stability_Percent": round(chemical_stability, 2),
                        "Physical_Stability_Score": round(physical_stability, 1),
                        "Particle_Size_Change_Percent": round(particle_size_change, 2),
                    }
                )

            all_results.extend(results)

    # Convert results to DataFrame
    results_df = pd.DataFrame(all_results)

    # Save results to CSV
    csv_filename = f"{output_dir}/stability_results_{timestamp}.csv"
    results_df.to_csv(csv_filename, index=False)

    # Generate research log
    log = "Accelerated Stability Testing of Pharmaceutical Formulations\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    log += "1. STUDY PARAMETERS\\n"
    log += f"   - Number of formulations tested: {len(formulations)}\\n"
    log += f"   - Formulations: {', '.join([f['name'] for f in formulations])}\\n"
    log += (
        "   - Storage conditions: "
        + ", ".join(
            [
                f"{c['description']} ({c['temperature']}°C" + (f"/{c['humidity']}% RH" if "humidity" in c else "") + ")"
                for c in storage_conditions
            ]
        )
        + "\\n"
    )
    log += f"   - Time points evaluated (days): {', '.join(map(str, time_points))}\\n\\n"

    log += "2. METHODOLOGY\\n"
    log += "   - Chemical stability assessed by active ingredient content\\n"
    log += "   - Physical stability evaluated on a 10-point scale\\n"
    log += "   - Particle size changes measured where applicable\\n\\n"

    log += "3. KEY FINDINGS\\n"

    # Summarize stability at final time point for each formulation/condition
    final_time = max(time_points)
    final_results = results_df[results_df["Time_Days"] == final_time]

    for formulation in formulations:
        form_results = final_results[final_results["Formulation"] == formulation["name"]]
        log += f"   {formulation['name']}:\\n"

        for _, row in form_results.iterrows():
            condition = row["Storage_Condition"]
            chem_stab = row["Chemical_Stability_Percent"]
            phys_stab = row["Physical_Stability_Score"]

            stability_assessment = "Stable"
            if chem_stab < 90 or phys_stab < 7:
                stability_assessment = "Potentially unstable"
            if chem_stab < 85 or phys_stab < 5:
                stability_assessment = "Unstable"

            log += f"     - {condition}: Chemical stability {chem_stab}%, Physical stability score {phys_stab}/10 - {stability_assessment}\\n"
        log += "\\n"

    log += "4. CONCLUSION\\n"

    # Identify most stable formulation
    best_formulation = ""
    best_stability = 0

    for formulation in formulations:
        form_data = final_results[final_results["Formulation"] == formulation["name"]]
        avg_chem_stability = form_data["Chemical_Stability_Percent"].mean()
        if avg_chem_stability > best_stability:
            best_stability = avg_chem_stability
            best_formulation = formulation["name"]

    log += f"   - Most stable formulation: {best_formulation} (avg. chemical stability: {best_stability:.2f}%)\\n"
    log += f"   - Detailed results saved to: {csv_filename}\\n"

    return log

# Execute the function
try:
    result = analyze_accelerated_stability_of_pharmaceutical_formulations(
        formulations=auto_convert(os.environ.get("PARAM_FORMULATIONS", "")),
        storage_conditions=auto_convert(os.environ.get("PARAM_STORAGE_CONDITIONS", "")),
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
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
    "function": "analyze_accelerated_stability_of_pharmaceutical_formulations",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_accelerated_stability_of_pharmaceutical_formulations_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_accelerated_stability_of_pharmaceutical_formulations_output.txt", "w") as f:
    f.write("Biomni: Analyze Accelerated Stability Of Pharmaceutical Formulations" + NL)
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
        biomni_function: "analyze_accelerated_stability_of_pharmaceutical_formulations"
    END_VERSIONS
    """
}

workflow ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS(ch_input)

    emit:
    results = ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS.out.results
    output = ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS.out.output
    versions = ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS_WORKFLOW(ch_input)

    ANALYZE_ACCELERATED_STABILITY_OF_PHARMACEUTICAL_FORMULATIONS_WORKFLOW.out.output.view { "Output: $it" }
}
