#!/usr/bin/env nextflow
/*
 * microbiology/optimize_anaerobic_digestion_process
 * Optimize anaerobic digestion process conditions to maximize VFA production or methane yield.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Food waste anaerobic digestion optimization
// waste_characteristics keys: volatile_solids (%), cod (mg/L)
params.waste_characteristics = '{"volatile_solids": 85.2, "cod": 45000}'
// operational_parameters keys: hrt, olr, if_ratio, temperature, ph - all as (min, max) bounds
params.operational_parameters = '{"hrt": [5, 30], "olr": [1, 6], "if_ratio": [0.1, 0.5], "temperature": [30, 55], "ph": [5.5, 7.5]}'
params.target_output = 'methane_yield'
params.optimization_method = 'rsm'

process OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("optimize_anaerobic_digestion_process_results.json"), emit: results
    tuple val(meta), path("optimize_anaerobic_digestion_process_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_WASTE_CHARACTERISTICS="${params.waste_characteristics?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OPERATIONAL_PARAMETERS="${params.operational_parameters?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_OUTPUT="${params.target_output?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OPTIMIZATION_METHOD="${params.optimization_method?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def optimize_anaerobic_digestion_process(
    waste_characteristics,
    operational_parameters,
    target_output="methane_yield",
    optimization_method="rsm",
):
    '''Optimize anaerobic digestion process conditions to maximize VFA production or methane yield.

    Parameters
    ----------
    waste_characteristics : dict
        Dictionary containing waste characteristics such as:
        - total_solids (float): Total solids content (%)
        - volatile_solids (float): Volatile solids content (%)
        - cod (float): Chemical oxygen demand (mg/L)

    operational_parameters : dict
        Dictionary containing operational parameters and their ranges:
        - hrt (tuple): Hydraulic retention time range in days (min, max)
        - olr (tuple): Organic loading rate range in kg VS/(m³·d) (min, max)
        - if_ratio (tuple): Inoculum-to-feedstock ratio range (min, max)
        - temperature (tuple): Temperature range in °C (min, max)
        - ph (tuple): pH range (min, max)

    target_output : str, optional
        Target output to maximize, either 'vfa_production' or 'methane_yield'.
        Default is 'methane_yield'.

    optimization_method : str, optional
        Method used for optimization, either 'rsm' (Response Surface Methodology) or
        'genetic' (Genetic Algorithm). Default is 'rsm'.

    Returns
    -------
    str
        Research log summarizing the optimization process and results.

    '''
    import matplotlib.pyplot as plt
    import numpy as np
    from matplotlib import cm
    from scipy.optimize import differential_evolution, minimize

    # Research log initialization
    log = "# Anaerobic Digestion Process Optimization Research Log\\n\\n"
    log += "## Input Parameters\\n\\n"
    log += "### Waste Characteristics\\n"
    for key, value in waste_characteristics.items():
        log += f"- {key}: {value}\\n"

    log += "\\n### Operational Parameters Ranges\\n"
    for key, value in operational_parameters.items():
        log += f"- {key}: {value}\\n"

    log += "\\n## Optimization Setup\\n"
    log += f"- Target output: {target_output}\\n"
    log += f"- Optimization method: {optimization_method}\\n\\n"

    # Define simplified models for VFA production and methane yield
    # These are simplified models based on literature that relate operational parameters to outputs
    def vfa_production_model(params):
        hrt, olr, if_ratio, temp, ph = params

        # Basic model: Higher VFA at moderate HRT, high OLR, low I/F ratio, mesophilic temp, slightly acidic pH
        # This is a simplified model for demonstration purposes
        vfa = (
            -0.1 * (hrt - 10) ** 2  # Optimal HRT around 10 days
            + 2 * olr  # Higher OLR generally increases VFA
            + -5 * if_ratio  # Lower I/F ratio favors VFA accumulation
            + -0.05 * (temp - 35) ** 2  # Optimal around 35°C (mesophilic)
            + -10 * (ph - 5.5) ** 2  # Optimal pH around 5.5 for VFA
        )

        # Incorporate waste characteristics effects
        vfa *= 0.8 + 0.2 * waste_characteristics["volatile_solids"] / 100
        vfa *= 0.9 + 0.1 * waste_characteristics["cod"] / 10000

        return -vfa  # Negative because we're minimizing

    def methane_yield_model(params):
        hrt, olr, if_ratio, temp, ph = params

        # Basic model: Higher methane at longer HRT, moderate OLR, high I/F ratio, mesophilic/thermophilic temp, neutral pH
        # This is a simplified model for demonstration purposes
        methane = (
            0.05 * hrt  # Longer HRT generally increases methane
            + -0.5 * (olr - 3) ** 2  # Optimal OLR around 3
            + 2 * if_ratio  # Higher I/F ratio favors methanogenesis
            + -0.05 * (temp - 37) ** 2  # Optimal around 37°C (mesophilic)
            + -15 * (ph - 7.2) ** 2  # Optimal pH around 7.2 for methane
        )

        # Incorporate waste characteristics effects
        methane *= 0.7 + 0.3 * waste_characteristics["volatile_solids"] / 100
        methane *= 0.8 + 0.2 * waste_characteristics["cod"] / 10000

        return -methane  # Negative because we're minimizing

    # Select the appropriate model based on target output
    if target_output == "vfa_production":
        model = vfa_production_model
    else:  # methane_yield
        model = methane_yield_model

    # Define parameter bounds
    bounds = [
        operational_parameters["hrt"],
        operational_parameters["olr"],
        operational_parameters["if_ratio"],
        operational_parameters["temperature"],
        operational_parameters["ph"],
    ]

    # Perform optimization
    log += "## Optimization Process\\n\\n"
    log += "Performing parameter optimization to find optimal operating conditions...\\n\\n"

    if optimization_method == "rsm":
        # Initial guess (middle of each range)
        x0 = [(b[0] + b[1]) / 2 for b in bounds]

        # Run optimization
        result = minimize(model, x0, bounds=bounds, method="L-BFGS-B")

        optimal_params = result.x
        optimal_value = -result.fun  # Convert back to positive

        log += f"Optimization converged after {result.nfev} function evaluations.\\n"
        log += f"Optimization success: {result.success}\\n"
        log += f"Final optimization message: {result.message}\\n\\n"

    else:  # genetic algorithm
        result = differential_evolution(model, bounds)

        optimal_params = result.x
        optimal_value = -result.fun  # Convert back to positive

        log += f"Genetic algorithm completed after {result.nfev} function evaluations.\\n"
        log += f"Optimization success: {result.success}\\n"
        log += f"Final optimization message: {result.message}\\n\\n"

    # Log optimal parameters
    log += "## Optimization Results\\n\\n"
    log += "### Optimal Operating Conditions\\n"
    param_names = [
        "Hydraulic Retention Time (days)",
        "Organic Loading Rate (kg VS/(m³·d))",
        "Inoculum-to-Feedstock Ratio",
        "Temperature (°C)",
        "pH",
    ]

    for name, value in zip(param_names, optimal_params, strict=False):
        log += f"- {name}: {value:.2f}\\n"

    log += "\\n### Predicted Performance\\n"
    log += f"- Predicted {target_output.replace('_', ' ')}: {optimal_value:.2f}\\n\\n"

    # Generate response surface visualization for the two most important parameters
    # For VFA, we'll use HRT and OLR; for methane, we'll use HRT and I/F ratio
    log += "## Response Surface Visualization\\n\\n"

    if target_output == "vfa_production":
        param1_idx, param2_idx = 0, 1  # HRT and OLR
        param1_name, param2_name = "HRT (days)", "OLR (kg VS/(m³·d))"
    else:  # methane_yield
        param1_idx, param2_idx = 0, 2  # HRT and I/F ratio
        param1_name, param2_name = "HRT (days)", "I/F ratio"

    # Create mesh grid for the two selected parameters
    param1_range = np.linspace(bounds[param1_idx][0], bounds[param1_idx][1], 20)
    param2_range = np.linspace(bounds[param2_idx][0], bounds[param2_idx][1], 20)
    P1, P2 = np.meshgrid(param1_range, param2_range)

    # Calculate output values
    Z = np.zeros_like(P1)
    for i in range(len(param1_range)):
        for j in range(len(param2_range)):
            params = list(optimal_params)  # Start with optimal values for other parameters
            params[param1_idx] = param1_range[i]
            params[param2_idx] = param2_range[j]
            Z[j, i] = -model(params)  # Convert back to positive

    # Create 3D plot
    fig = plt.figure(figsize=(10, 8))
    ax = fig.add_subplot(111, projection="3d")
    surf = ax.plot_surface(P1, P2, Z, cmap=cm.coolwarm, alpha=0.8)

    # Add optimal point
    ax.scatter(
        optimal_params[param1_idx],
        optimal_params[param2_idx],
        optimal_value,
        color="black",
        s=100,
        marker="*",
    )

    # Labels
    ax.set_xlabel(param1_name)
    ax.set_ylabel(param2_name)
    ax.set_zlabel(f"{target_output.replace('_', ' ')}")
    ax.set_title(f"Response Surface for {target_output.replace('_', ' ')}")

    # Add colorbar
    fig.colorbar(surf, ax=ax, shrink=0.5, aspect=5)

    # Save figure
    plot_filename = f"ad_optimization_{target_output}_response_surface.png"
    plt.savefig(plot_filename)
    plt.close()

    log += f"Response surface plot saved as: {plot_filename}\\n\\n"

    # Sensitivity analysis
    log += "## Parameter Sensitivity Analysis\\n\\n"

    # Calculate sensitivity by varying each parameter slightly
    sensitivities = []
    for i, (name, param) in enumerate(zip(param_names, optimal_params, strict=False)):
        delta = (bounds[i][1] - bounds[i][0]) * 0.05  # 5% of range

        # Create parameter sets with small changes
        params_plus = list(optimal_params)
        params_plus[i] += delta

        params_minus = list(optimal_params)
        params_minus[i] -= delta

        # Calculate output change
        output_plus = -model(params_plus)
        output_minus = -model(params_minus)

        # Calculate sensitivity (normalized)
        sensitivity = abs(output_plus - output_minus) / (2 * delta) * (param / optimal_value)
        sensitivities.append((name, sensitivity))

    # Sort sensitivities
    sensitivities.sort(key=lambda x: x[1], reverse=True)

    # Log sensitivities
    log += "Parameters ranked by sensitivity (most to least sensitive):\\n"
    for name, sensitivity in sensitivities:
        log += f"- {name}: {sensitivity:.4f}\\n"

    log += "\\n## Conclusion\\n\\n"
    log += f"The optimization process identified optimal operating conditions for maximizing {target_output.replace('_', ' ')} "
    log += "in anaerobic digestion of the given organic waste. The most sensitive parameters were "
    log += f"{sensitivities[0][0]} and {sensitivities[1][0]}.\\n\\n"

    log += "These results can be used to guide experimental design and process control in anaerobic digestion systems."

    return log

# Execute the function
try:
    result = optimize_anaerobic_digestion_process(
        waste_characteristics=auto_convert(os.environ.get("PARAM_WASTE_CHARACTERISTICS", "")),
        operational_parameters=auto_convert(os.environ.get("PARAM_OPERATIONAL_PARAMETERS", "")),
        target_output=auto_convert(os.environ.get("PARAM_TARGET_OUTPUT", "methane_yield")),
        optimization_method=auto_convert(os.environ.get("PARAM_OPTIMIZATION_METHOD", "rsm")),
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
    "function": "optimize_anaerobic_digestion_process",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("optimize_anaerobic_digestion_process_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("optimize_anaerobic_digestion_process_output.txt", "w") as f:
    f.write("Biomni: Optimize Anaerobic Digestion Process" + NL)
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
        biomni_function: "optimize_anaerobic_digestion_process"
    END_VERSIONS
    """
}

workflow OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS(ch_input)

    emit:
    results = OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS.out.results
    output = OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS.out.output
    versions = OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS_WORKFLOW(ch_input)

    OPTIMIZE_ANAEROBIC_DIGESTION_PROCESS_WORKFLOW.out.output.view { "Output: $it" }
}
