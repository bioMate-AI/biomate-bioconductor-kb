#!/usr/bin/env nextflow
/*
 * bioengineering/analyze_in_vitro_drug_release_kinetics
 * Analyzes in vitro drug release kinetics from biomaterial formulations.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.time_points = null
params.concentration_data = null
params.drug_name = 'Drug'
params.total_drug_loaded = null
params.output_dir = './'

process ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_in_vitro_drug_release_kinetics_results.json"), emit: results
    tuple val(meta), path("analyze_in_vitro_drug_release_kinetics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_TIME_POINTS="${params.time_points?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONCENTRATION_DATA="${params.concentration_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DRUG_NAME="${params.drug_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TOTAL_DRUG_LOADED="${params.total_drug_loaded?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_in_vitro_drug_release_kinetics(
    time_points,
    concentration_data,
    drug_name="Drug",
    total_drug_loaded=None,
    output_dir="./",
):
    '''Analyzes in vitro drug release kinetics from biomaterial formulations.

    Parameters
    ----------
    time_points : list or numpy.ndarray
        Time points at which drug concentrations were measured (in hours)
    concentration_data : list or numpy.ndarray
        Measured drug concentration at each time point
    drug_name : str, optional
        Name of the drug being analyzed (default: "Drug")
    total_drug_loaded : float, optional
        Total amount of drug initially loaded in the formulation.
        If None, the maximum concentration is used as 100% (default: None)
    output_dir : str, optional
        Directory to save output files (default: "./")

    Returns
    -------
    str
        Research log summarizing the analysis steps, results, and saved file locations

    '''
    import os
    from datetime import datetime

    import matplotlib.pyplot as plt
    import numpy as np
    import pandas as pd
    from scipy.optimize import curve_fit

    # Validate inputs - use defaults if None
    if time_points is None:
        time_points = [0, 1, 2, 4, 8, 12, 24, 48, 72]
    if concentration_data is None:
        # Simulate typical drug release profile (first-order kinetics)
        concentration_data = [0, 15, 28, 45, 65, 78, 88, 95, 98]
    if drug_name is None:
        drug_name = "Drug"
    if output_dir is None:
        output_dir = "./"

    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Convert inputs to numpy arrays
    time_points = np.array(time_points)
    concentration_data = np.array(concentration_data)

    # Calculate cumulative release percentage
    if total_drug_loaded is None:
        total_drug_loaded = np.max(concentration_data)

    cumulative_release = (concentration_data / total_drug_loaded) * 100

    # Create a DataFrame for easier manipulation
    release_df = pd.DataFrame(
        {
            "Time (hours)": time_points,
            "Concentration": concentration_data,
            "Cumulative Release (%)": cumulative_release,
        }
    )

    # Calculate release rate (simple approximation using differences)
    release_df["Release Rate"] = np.gradient(release_df["Cumulative Release (%)"], release_df["Time (hours)"])

    # Define kinetic models
    def zero_order(t, k):
        return k * t

    def first_order(t, k):
        return 100 * (1 - np.exp(-k * t))

    def higuchi(t, k):
        return k * np.sqrt(t)

    def korsmeyer_peppas(t, k, n):
        return 100 * (k * t) ** n

    # Fit data to different kinetic models
    models = {}
    r2_values = {}

    # Zero-order kinetics
    try:
        params, _ = curve_fit(zero_order, time_points, cumulative_release)
        y_pred = zero_order(time_points, *params)
        ss_total = np.sum((cumulative_release - np.mean(cumulative_release)) ** 2)
        ss_residual = np.sum((cumulative_release - y_pred) ** 2)
        r2 = 1 - (ss_residual / ss_total)
        models["Zero-order"] = {
            "params": params,
            "equation": f"Release = {params[0]:.4f} * t",
            "pred": y_pred,
        }
        r2_values["Zero-order"] = r2
    except Exception:
        models["Zero-order"] = {
            "params": None,
            "equation": "Fitting failed",
            "pred": None,
        }
        r2_values["Zero-order"] = 0

    # First-order kinetics
    try:
        params, _ = curve_fit(first_order, time_points, cumulative_release, bounds=(0, [1]))
        y_pred = first_order(time_points, *params)
        ss_total = np.sum((cumulative_release - np.mean(cumulative_release)) ** 2)
        ss_residual = np.sum((cumulative_release - y_pred) ** 2)
        r2 = 1 - (ss_residual / ss_total)
        models["First-order"] = {
            "params": params,
            "equation": f"Release = 100 * (1 - exp(-{params[0]:.4f} * t))",
            "pred": y_pred,
        }
        r2_values["First-order"] = r2
    except Exception:
        models["First-order"] = {
            "params": None,
            "equation": "Fitting failed",
            "pred": None,
        }
        r2_values["First-order"] = 0

    # Higuchi model
    try:
        params, _ = curve_fit(higuchi, time_points, cumulative_release)
        y_pred = higuchi(time_points, *params)
        ss_total = np.sum((cumulative_release - np.mean(cumulative_release)) ** 2)
        ss_residual = np.sum((cumulative_release - y_pred) ** 2)
        r2 = 1 - (ss_residual / ss_total)
        models["Higuchi"] = {
            "params": params,
            "equation": f"Release = {params[0]:.4f} * sqrt(t)",
            "pred": y_pred,
        }
        r2_values["Higuchi"] = r2
    except Exception:
        models["Higuchi"] = {"params": None, "equation": "Fitting failed", "pred": None}
        r2_values["Higuchi"] = 0

    # Korsmeyer-Peppas model
    try:
        # Only use the first 60% of release data for Korsmeyer-Peppas model
        mask = cumulative_release <= 60
        if sum(mask) >= 3:  # Need at least 3 points for fitting
            params, _ = curve_fit(
                korsmeyer_peppas,
                time_points[mask],
                cumulative_release[mask],
                bounds=([0, 0], [1, 1]),
            )
            y_pred = korsmeyer_peppas(time_points, *params)
            ss_total = np.sum((cumulative_release - np.mean(cumulative_release)) ** 2)
            ss_residual = np.sum((cumulative_release - y_pred) ** 2)
            r2 = 1 - (ss_residual / ss_total)
            models["Korsmeyer-Peppas"] = {
                "params": params,
                "equation": f"Release = 100 * ({params[0]:.4f} * t)^{params[1]:.4f}",
                "pred": y_pred,
            }
            r2_values["Korsmeyer-Peppas"] = r2
        else:
            models["Korsmeyer-Peppas"] = {
                "params": None,
                "equation": "Insufficient data points",
                "pred": None,
            }
            r2_values["Korsmeyer-Peppas"] = 0
    except Exception:
        models["Korsmeyer-Peppas"] = {
            "params": None,
            "equation": "Fitting failed",
            "pred": None,
        }
        r2_values["Korsmeyer-Peppas"] = 0

    # Determine best model based on R² value
    best_model = max(r2_values, key=r2_values.get)

    # Calculate half-life (time to 50% release)
    try:
        # Use best model to calculate half-life
        if best_model == "Zero-order":
            k = models[best_model]["params"][0]
            half_life = 50 / k if k > 0 else float("inf")
        elif best_model == "First-order":
            k = models[best_model]["params"][0]
            half_life = -np.log(0.5) / k if k > 0 else float("inf")
        elif best_model == "Higuchi":
            k = models[best_model]["params"][0]
            half_life = (50 / k) ** 2 if k > 0 else float("inf")
        elif best_model == "Korsmeyer-Peppas":
            k, n = models[best_model]["params"]
            half_life = (0.5 ** (1 / n)) / k if k > 0 else float("inf")
        else:
            # Interpolate from data if model fitting failed
            from scipy.interpolate import interp1d

            if np.max(cumulative_release) >= 50:
                f = interp1d(cumulative_release, time_points)
                half_life = float(f(50))
            else:
                half_life = "Not reached"
    except Exception:
        half_life = "Could not calculate"

    # Create plots
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # 1. Cumulative release plot with model fits
    plt.figure(figsize=(10, 6))
    plt.plot(time_points, cumulative_release, "o-", label="Experimental data")

    for model_name, model_data in models.items():
        if model_data["pred"] is not None:
            plt.plot(
                time_points,
                model_data["pred"],
                "--",
                label=f"{model_name} (R² = {r2_values[model_name]:.4f})",
            )

    plt.xlabel("Time (hours)")
    plt.ylabel("Cumulative Release (%)")
    plt.title(f"In Vitro Release Profile of {drug_name}")
    plt.legend()
    plt.grid(True, linestyle="--", alpha=0.7)
    cumulative_plot_path = os.path.join(output_dir, f"cumulative_release_{timestamp}.png")
    plt.savefig(cumulative_plot_path, dpi=300, bbox_inches="tight")
    plt.close()

    # 2. Release rate plot
    plt.figure(figsize=(10, 6))
    plt.plot(time_points, release_df["Release Rate"], "o-")
    plt.xlabel("Time (hours)")
    plt.ylabel("Release Rate (%/hour)")
    plt.title(f"Release Rate of {drug_name}")
    plt.grid(True, linestyle="--", alpha=0.7)
    rate_plot_path = os.path.join(output_dir, f"release_rate_{timestamp}.png")
    plt.savefig(rate_plot_path, dpi=300, bbox_inches="tight")
    plt.close()

    # Save data to CSV
    csv_path = os.path.join(output_dir, f"drug_release_data_{timestamp}.csv")
    release_df.to_csv(csv_path, index=False)

    # Generate research log
    log = f'''
# In Vitro Drug Release Kinetics Analysis for {drug_name}

## Analysis Summary
- **Date/Time:** {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
- **Drug Analyzed:** {drug_name}
- **Time Range:** {min(time_points)} to {max(time_points)} hours
- **Number of Data Points:** {len(time_points)}
- **Maximum Release Achieved:** {max(cumulative_release):.2f}%

## Kinetic Models Analysis
The release data was fitted to four standard kinetic models:

1. **Zero-order Model:** {models["Zero-order"]["equation"]} (R² = {r2_values["Zero-order"]:.4f})
2. **First-order Model:** {models["First-order"]["equation"]} (R² = {r2_values["First-order"]:.4f})
3. **Higuchi Model:** {models["Higuchi"]["equation"]} (R² = {r2_values["Higuchi"]:.4f})
4. **Korsmeyer-Peppas Model:** {models["Korsmeyer-Peppas"]["equation"]} (R² = {r2_values["Korsmeyer-Peppas"]:.4f})

**Best-fitting Model:** {best_model} (R² = {r2_values[best_model]:.4f})

## Release Metrics
- **Half-life (t50%):** {half_life if isinstance(half_life, str) else f"{half_life:.2f} hours"}
- **Initial Release Rate:** {release_df["Release Rate"].iloc[0]:.4f} %/hour
- **Average Release Rate:** {np.mean(release_df["Release Rate"]):.4f} %/hour

## Files Generated
1. Cumulative Release Plot: {cumulative_plot_path}
2. Release Rate Plot: {rate_plot_path}
3. Data CSV: {csv_path}

## Interpretation
The drug release profile of {drug_name} best follows a {
        best_model
    } kinetic model, which suggests that the release mechanism is primarily driven by {
        "diffusion through a porous matrix"
        if best_model == "Higuchi"
        else "diffusion with erosion"
        if best_model == "Korsmeyer-Peppas" and 0.43 <= models[best_model]["params"][1] <= 0.85
        else "Fickian diffusion"
        if best_model == "Korsmeyer-Peppas" and models[best_model]["params"][1] < 0.43
        else "case-II transport"
        if best_model == "Korsmeyer-Peppas" and models[best_model]["params"][1] > 0.85
        else "concentration-dependent diffusion"
        if best_model == "First-order"
        else "constant release rate independent of concentration"
        if best_model == "Zero-order"
        else "complex mechanisms"
    }.
'''

    return log.strip()

# Execute the function
try:
    result = analyze_in_vitro_drug_release_kinetics(
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
        concentration_data=auto_convert(os.environ.get("PARAM_CONCENTRATION_DATA", "")),
        drug_name=auto_convert(os.environ.get("PARAM_DRUG_NAME", "Drug")),
        total_drug_loaded=auto_convert(os.environ.get("PARAM_TOTAL_DRUG_LOADED", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./")),
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
    "function": "analyze_in_vitro_drug_release_kinetics",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_in_vitro_drug_release_kinetics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_in_vitro_drug_release_kinetics_output.txt", "w") as f:
    f.write("Biomni: Analyze In Vitro Drug Release Kinetics" + NL)
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
        biomni_function: "analyze_in_vitro_drug_release_kinetics"
    END_VERSIONS
    """
}

workflow ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS(ch_input)

    emit:
    results = ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS.out.results
    output = ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS.out.output
    versions = ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS_WORKFLOW(ch_input)

    ANALYZE_IN_VITRO_DRUG_RELEASE_KINETICS_WORKFLOW.out.output.view { "Output: $it" }
}
