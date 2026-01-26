#!/usr/bin/env nextflow
/*
 * pharmacology/analyze_radiolabeled_antibody_biodistribution
 * Analyze biodistribution and pharmacokinetic profile of radiolabeled antibodies.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.tissue_data = null

process ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_radiolabeled_antibody_biodistribution_results.json"), emit: results
    tuple val(meta), path("analyze_radiolabeled_antibody_biodistribution_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TISSUE_DATA="${params.tissue_data?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
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



def analyze_radiolabeled_antibody_biodistribution(time_points, tissue_data):
    '''Analyze biodistribution and pharmacokinetic profile of radiolabeled antibodies.

    Parameters
    ----------
    time_points : list or numpy.ndarray
        Time points (hours) at which measurements were taken
    tissue_data : dict
        Dictionary where keys are tissue names and values are lists/arrays of %IA/g
        measurements corresponding to time_points. Must include 'tumor' as one of the keys.

    Returns
    -------
    str
        Research log summarizing the biodistribution analysis, pharmacokinetic parameters,
        and tumor-to-normal tissue ratios

    '''
    import json
    import os

    import numpy as np
    from scipy.optimize import curve_fit

    # Validate inputs
    if "tumor" not in tissue_data:
        return "Error: Tumor data must be provided in tissue_data dictionary"

    # Define bi-exponential model for pharmacokinetic analysis
    # C(t) = A*exp(-alpha*t) + B*exp(-beta*t)
    def bi_exp_model(t, A, alpha, B, beta):
        return A * np.exp(-alpha * t) + B * np.exp(-beta * t)

    # Initialize results dictionary
    results = {
        "tissues_analyzed": list(tissue_data.keys()),
        "pk_parameters": {},
        "tumor_to_normal_ratios": {},
        "auc_values": {},
    }

    # Analyze each tissue
    for tissue, measurements in tissue_data.items():
        try:
            # Fit bi-exponential model
            params, _ = curve_fit(
                bi_exp_model,
                time_points,
                measurements,
                p0=[50, 0.1, 50, 0.01],  # Initial parameter guess
                bounds=([0, 0, 0, 0], [100, 5, 100, 1]),  # Parameter bounds
            )

            A, alpha, B, beta = params

            # Calculate pharmacokinetic parameters
            # Distribution half-life (fast component)
            t_half_dist = np.log(2) / alpha

            # Elimination half-life (slow component)
            t_half_elim = np.log(2) / beta

            # Area under the curve (AUC)
            auc = A / alpha + B / beta

            # Mean residence time (MRT)
            mrt = (A / (alpha**2) + B / (beta**2)) / auc

            # Clearance (for blood/plasma only - conceptual)
            clearance = 1 / auc if tissue.lower() in ["blood", "plasma"] else None

            # Store results
            results["pk_parameters"][tissue] = {
                "A": float(A),
                "alpha": float(alpha),
                "B": float(B),
                "beta": float(beta),
                "distribution_half_life_h": float(t_half_dist),
                "elimination_half_life_h": float(t_half_elim),
                "mean_residence_time_h": float(mrt),
            }

            if clearance:
                results["pk_parameters"][tissue]["clearance"] = float(clearance)

            # Calculate AUC
            results["auc_values"][tissue] = float(auc)

        except Exception as e:
            results["pk_parameters"][tissue] = f"Fitting failed: {str(e)}"

    # Calculate tumor-to-normal tissue ratios at each time point
    for tissue in tissue_data:
        if tissue != "tumor":
            ratios = [
                t / n if n > 0 else float("inf")
                for t, n in zip(tissue_data["tumor"], tissue_data[tissue], strict=False)
            ]
            results["tumor_to_normal_ratios"][tissue] = {
                "values": [float(r) for r in ratios],
                "max_ratio": float(max(ratios)),
                "max_ratio_time_point": float(time_points[np.argmax(ratios)]),
            }

    # Save results to JSON file
    filename = "biodistribution_pk_results.json"
    with open(filename, "w") as f:
        json.dump(results, f, indent=2)

    # Generate research log
    log = "# Biodistribution and Pharmacokinetic Analysis of Radiolabeled Antibody\\n\\n"
    log += "## Analysis Summary\\n"
    log += f"- Analyzed biodistribution data across {len(tissue_data)} tissues\\n"
    log += f"- Time points analyzed: {time_points} hours\\n"
    log += "- Performed bi-exponential pharmacokinetic modeling\\n\\n"

    log += "## Key Pharmacokinetic Parameters\\n"
    for tissue, params in results["pk_parameters"].items():
        if isinstance(params, dict):
            log += f"\\n### {tissue.capitalize()}\\n"
            log += f"- Distribution half-life: {params['distribution_half_life_h']:.2f} hours\\n"
            log += f"- Elimination half-life: {params['elimination_half_life_h']:.2f} hours\\n"
            log += f"- Mean residence time: {params['mean_residence_time_h']:.2f} hours\\n"
            if "clearance" in params:
                log += f"- Clearance: {params['clearance']:.4f} units\\n"

    log += "\\n## Tumor-to-Normal Tissue Ratios\\n"
    for tissue, ratio_data in results["tumor_to_normal_ratios"].items():
        log += f"- {tissue.capitalize()}: Max ratio {ratio_data['max_ratio']:.2f} at {ratio_data['max_ratio_time_point']:.1f} hours\\n"

    log += "\\n## Detailed Results\\n"
    log += f"Complete analysis results saved to: {os.path.abspath(filename)}\\n"

    return log

# Execute the function
try:
    result = analyze_radiolabeled_antibody_biodistribution(
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
        tissue_data=auto_convert(os.environ.get("PARAM_TISSUE_DATA", "")),
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
    "function": "analyze_radiolabeled_antibody_biodistribution",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_radiolabeled_antibody_biodistribution_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_radiolabeled_antibody_biodistribution_output.txt", "w") as f:
    f.write("Biomni: Analyze Radiolabeled Antibody Biodistribution" + NL)
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
        biomni_function: "analyze_radiolabeled_antibody_biodistribution"
    END_VERSIONS
    """
}

workflow ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION(ch_input)

    emit:
    results = ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION.out.results
    output = ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION.out.output
    versions = ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION_WORKFLOW(ch_input)

    ANALYZE_RADIOLABELED_ANTIBODY_BIODISTRIBUTION_WORKFLOW.out.output.view { "Output: $it" }
}
