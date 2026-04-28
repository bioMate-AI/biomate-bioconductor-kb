#!/bin/bash -ue
# Export parameters as environment variables
    export PARAM_TIME_POINTS="[0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24]"
    export PARAM_OD_VALUES="[0.05, 0.07, 0.12, 0.28, 0.55, 0.85, 1.1, 1.3, 1.45, 1.52, 1.55, 1.57, 1.58]"
    export PARAM_STRAIN_NAME="Test_Strain_001"
    export PARAM_OUTPUT_DIR="."

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



def analyze_bacterial_growth_curve(time_points, od_values, strain_name, output_dir="."):
    '''Analyzes bacterial growth curve data to determine growth parameters.

    Parameters
    ----------
    time_points : list or numpy.ndarray
        Time points of measurements in hours
    od_values : list or numpy.ndarray
        Optical density measurements corresponding to each time point
    strain_name : str
        Name of the bacterial strain being analyzed
    output_dir : str, optional
        Directory where output files will be saved (default: current directory)

    Returns
    -------
    str
        A research log summarizing the analysis steps and results

    '''
    import os
    from math import log

    import matplotlib.pyplot as plt
    import numpy as np
    import pandas as pd
    from scipy.optimize import curve_fit

    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    # Convert inputs to numpy arrays if they aren't already
    time_points = np.array(time_points)
    od_values = np.array(od_values)

    # Create a DataFrame for easier data handling
    pd.DataFrame({"Time (h)": time_points, "OD": od_values})

    # Define the logistic growth model function
    def logistic_growth(t, k, n0, r):
        '''Logistic growth model: N(t) = K / (1 + ((K - N0) / N0) * exp(-r*t)).

        Parameters
        ----------
        t: time
        k: carrying capacity (maximum population size)
        n0: initial population
        r: growth rate

        '''
        return k / (1 + ((k - n0) / n0) * np.exp(-r * t))

    # Initial parameter estimates
    p0 = [max(od_values), od_values[0], 0.5]

    # Fit the model to the data
    try:
        popt, pcov = curve_fit(logistic_growth, time_points, od_values, p0=p0)
        k_fit, n0_fit, r_fit = popt

        # Calculate doubling time (in hours)
        doubling_time = log(2) / r_fit

        # Calculate lag phase (approximation)
        lag_phase = (np.log((k_fit / n0_fit) - 1) - np.log((k_fit / (0.05 * k_fit)) - 1)) / r_fit
        lag_phase = max(0, lag_phase)  # Ensure non-negative

        # Generate fitted curve for plotting
        time_fine = np.linspace(min(time_points), max(time_points), 100)
        od_fitted = logistic_growth(time_fine, *popt)

        # Create the growth curve plot
        plt.figure(figsize=(10, 6))
        plt.scatter(time_points, od_values, label="Observed OD")
        plt.plot(time_fine, od_fitted, "r-", label="Fitted curve")
        plt.xlabel("Time (hours)")
        plt.ylabel("Optical Density (OD)")
        plt.title(f"Growth Curve for {strain_name}")
        plt.grid(True, alpha=0.3)
        plt.legend()

        # Save the plot
        plot_filename = os.path.join(output_dir, f"{strain_name.replace(' ', '_')}_growth_curve.png")
        plt.savefig(plot_filename)
        plt.close()

        # Create a research log
        log_text = f'''
Bacterial Growth Curve Analysis Log
==================================
Strain: {strain_name}

Data Summary:
------------
- Number of time points: {len(time_points)}
- Time range: {min(time_points):.1f} to {max(time_points):.1f} hours
- Initial OD: {od_values[0]:.4f}
- Final OD: {od_values[-1]:.4f}

Growth Model:
------------
- Model type: Logistic growth
- Fitted parameters:
  * Maximum population (carrying capacity, K): {k_fit:.4f} OD units
  * Initial population (N0): {n0_fit:.4f} OD units
  * Growth rate (r): {r_fit:.4f} per hour

Growth Metrics:
--------------
- Doubling time: {doubling_time:.2f} hours
- Maximum growth rate: {r_fit:.4f} per hour
- Lag phase duration: {lag_phase:.2f} hours
- Maximum OD (carrying capacity): {k_fit:.4f}

Output Files:
-----------
- Growth curve plot: {plot_filename}

Analysis completed successfully.
'''
        return log_text

    except RuntimeError:
        return f"Error: Could not fit growth model to data for {strain_name}. Please check your input data."

# Execute the function
try:
    result = analyze_bacterial_growth_curve(
        time_points=auto_convert(os.environ.get("PARAM_TIME_POINTS", "")),
        od_values=auto_convert(os.environ.get("PARAM_OD_VALUES", "")),
        strain_name=auto_convert(os.environ.get("PARAM_STRAIN_NAME", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", ".")),
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
    "function": "analyze_bacterial_growth_curve",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_bacterial_growth_curve_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_bacterial_growth_curve_output.txt", "w") as f:
    f.write("Biomni: Analyze Bacterial Growth Curve" + NL)
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
    "ANALYZE_BACTERIAL_GROWTH_CURVE_WORKFLOW:ANALYZE_BACTERIAL_GROWTH_CURVE":
        python: $(python3 --version | cut -d' ' -f2)
        biomni_function: "analyze_bacterial_growth_curve"
    END_VERSIONS
