#!/usr/bin/env nextflow
/*
 * biochemistry/analyze_itc_binding_thermodynamics
 * Analyzes isothermal titration calorimetry (ITC) data to determine binding affinity and thermodynamic parameters.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.itc_data_path = null
params.itc_data = null
params.temperature = '298.15'
params.protein_concentration = null
params.ligand_concentration = null

process ANALYZE_ITC_BINDING_THERMODYNAMICS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_itc_binding_thermodynamics_results.json"), emit: results
    tuple val(meta), path("analyze_itc_binding_thermodynamics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ITC_DATA_PATH="${params.itc_data_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ITC_DATA="${params.itc_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TEMPERATURE="${params.temperature?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PROTEIN_CONCENTRATION="${params.protein_concentration?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LIGAND_CONCENTRATION="${params.ligand_concentration?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_itc_binding_thermodynamics(
    itc_data_path=None,
    itc_data=None,
    temperature=298.15,
    protein_concentration=None,
    ligand_concentration=None,
):
    '''Analyzes isothermal titration calorimetry (ITC) data to determine binding affinity and thermodynamic parameters.

    Parameters
    ----------
    itc_data_path : str, optional
        Path to CSV or TSV file containing ITC thermogram data with columns for injection number,
        injection volume, and heat released/absorbed. Expected columns: 'injection', 'volume', 'heat'
    itc_data : numpy.ndarray, optional
        Raw ITC thermogram data as a numpy array.
        Expected shape: (n_injections, 3) with columns for injection number, injection volume, and heat
        This parameter is provided for backward compatibility and will be deprecated.
    temperature : float, optional
        Temperature in Kelvin at which the experiment was conducted. Default is 298.15 K (25°C).
    protein_concentration : float, optional
        Initial concentration of protein in the cell in molar (M). Required for accurate fitting.
    ligand_concentration : float, optional
        Concentration of ligand in the syringe in molar (M). Required for accurate fitting.

    Returns
    -------
    str
        A research log summarizing the analysis steps and results, including binding affinity (Kd),
        binding enthalpy (ΔH), binding entropy (ΔS), and Gibbs free energy (ΔG).

    '''
    import datetime

    import numpy as np
    import pandas as pd
    from scipy.optimize import curve_fit

    log = []
    log.append(f"# ITC Binding Affinity Analysis - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M')}")
    log.append("\\n## Data Preprocessing")

    # Check if we have data to process
    if itc_data_path is None and itc_data is None:
        log.append("Error: No data provided. Please provide either itc_data_path or itc_data.")
        return "\\n".join(log)

    # Load data from file if path is provided
    if itc_data_path is not None:
        try:
            if itc_data_path.endswith(".csv"):
                loaded_data = pd.read_csv(itc_data_path)
            elif itc_data_path.endswith((".tsv", ".txt")):
                loaded_data = pd.read_csv(itc_data_path, sep="\\t")
            else:
                log.append("Error: Unsupported file format. Please provide a CSV or TSV file.")
                return "\\n".join(log)

            log.append(f"- Loaded data from file: {itc_data_path}")
            log.append(f"- Input data: DataFrame with {len(loaded_data)} injections")

            if all(col in loaded_data.columns for col in ["injection", "volume", "heat"]):
                data = loaded_data[["injection", "volume", "heat"]].values
            else:
                log.append("- Error: DataFrame must contain 'injection', 'volume', and 'heat' columns")
                return "\\n".join(log)
        except Exception as e:
            log.append(f"- Error loading data from file: {str(e)}")
            return "\\n".join(log)
    # Use provided numpy array data
    elif itc_data is not None:
        if isinstance(itc_data, pd.DataFrame):
            log.append("Warning: Passing DataFrame directly is deprecated. Please use itc_data_path instead.")
            log.append(f"- Input data: DataFrame with {len(itc_data)} injections")
            if all(col in itc_data.columns for col in ["injection", "volume", "heat"]):
                data = itc_data[["injection", "volume", "heat"]].values
            else:
                log.append("- Error: DataFrame must contain 'injection', 'volume', and 'heat' columns")
                return "\\n".join(log)
        else:
            log.append(f"- Input data: Array with {len(itc_data)} injections")
            data = np.array(itc_data)

    # Check if concentration data is provided
    if protein_concentration is None or ligand_concentration is None:
        log.append("- Warning: Protein or ligand concentration not provided. Using normalized data for fitting.")
        protein_concentration = 1.0
        ligand_concentration = 10.0

    # Extract data
    injections = data[:, 0]
    volumes = data[:, 1]
    heats = data[:, 2]

    log.append(f"- Processed {len(injections)} injections")

    # Calculate molar ratio for each injection
    cell_volume = 1.4  # Default cell volume in mL (typical for ITC)

    # Calculate cumulative ligand added
    cumulative_volume = np.cumsum(volumes)
    dilution_factor = 1 - (cumulative_volume / cell_volume)
    protein_conc_corrected = protein_concentration * dilution_factor

    # Calculate molar ratio [ligand]/[protein] for each injection
    molar_ratios = np.zeros_like(injections, dtype=float)
    for i in range(len(injections)):
        ligand_added = volumes[i] * ligand_concentration / 1000  # Convert to mmol
        if i == 0:
            molar_ratios[i] = ligand_added / (protein_concentration * cell_volume / 1000)  # Convert to mmol
        else:
            # Account for dilution and previous injections
            molar_ratios[i] = molar_ratios[i - 1] + ligand_added / (
                protein_conc_corrected[i] * (cell_volume - cumulative_volume[i]) / 1000
            )

    log.append("\\n## Model Fitting")
    log.append("- Applying one-site binding model to the ITC data")

    # Define one-site binding model function
    def one_site_model(x, Kd, dH, n):
        '''One-site binding model for ITC data.

        Parameters
        ----------
        x: Molar ratio [ligand]/[protein]
        Kd: Dissociation constant (M)
        dH: Enthalpy change (cal/mol)
        n: Stoichiometry

        Returns: Heat per injection

        '''
        # Convert x to fraction bound using the binding equation
        Ka = 1 / Kd  # Association constant
        protein = protein_conc_corrected

        # Calculate heat for each injection
        q = np.zeros_like(x)
        for i in range(len(x)):
            if i == 0:
                # First injection
                bound = (n * protein[i] * Ka * (x[i] * protein[i])) / (1 + Ka * (x[i] * protein[i]))
                q[i] = bound * dH * cell_volume
            else:
                # Subsequent injections (differential heat)
                bound_prev = (n * protein[i - 1] * Ka * (x[i - 1] * protein[i - 1])) / (
                    1 + Ka * (x[i - 1] * protein[i - 1])
                )
                bound_curr = (n * protein[i] * Ka * (x[i] * protein[i])) / (1 + Ka * (x[i] * protein[i]))
                q[i] = bound_curr * dH * (cell_volume - cumulative_volume[i]) - bound_prev * dH * (
                    cell_volume - cumulative_volume[i - 1]
                )

        return q

    # Initial parameter guesses
    p0 = [1e-6, -5000, 1.0]  # Kd (M), dH (cal/mol), n (stoichiometry)

    try:
        # Fit the model to the data
        popt, pcov = curve_fit(one_site_model, molar_ratios, heats, p0=p0, maxfev=10000)
        Kd, dH, n = popt

        # Calculate standard errors
        perr = np.sqrt(np.diag(pcov))
        Kd_err, dH_err, n_err = perr

        # Calculate other thermodynamic parameters
        R = 1.9872  # Gas constant in cal/(mol·K)
        dG = R * temperature * np.log(Kd)  # Gibbs free energy
        dS = (dH - dG) / temperature  # Entropy

        log.append("- Model fitting successful")
        log.append("\\n## Results")
        log.append(f"- Binding Stoichiometry (n): {n:.2f} ± {n_err:.2f}")
        log.append(f"- Dissociation Constant (Kd): {Kd * 1e6:.2f} ± {Kd_err * 1e6:.2f} μM")
        log.append(f"- Association Constant (Ka): {1 / Kd / 1e6:.2f} × 10^6 M^-1")
        log.append(f"- Binding Enthalpy (ΔH): {dH:.2f} ± {dH_err:.2f} cal/mol")
        log.append(f"- Binding Entropy (ΔS): {dS:.2f} cal/(mol·K)")
        log.append(f"- Gibbs Free Energy (ΔG): {dG:.2f} cal/mol")

        # Calculate goodness of fit
        residuals = heats - one_site_model(molar_ratios, *popt)
        ss_res = np.sum(residuals**2)
        ss_tot = np.sum((heats - np.mean(heats)) ** 2)
        r_squared = 1 - (ss_res / ss_tot)
        log.append(f"- R-squared: {r_squared:.4f}")

    except Exception as e:
        log.append(f"- Error during model fitting: {str(e)}")
        log.append("- Consider trying different initial parameter guesses or a different binding model")

    log.append("\\n## Conclusion")
    log.append("- Analysis complete. The thermodynamic parameters have been estimated using a one-site binding model.")
    log.append(
        "- For more complex binding scenarios, consider using multi-site binding models or specialized ITC analysis software."
    )

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_itc_binding_thermodynamics(
        itc_data_path=auto_convert(os.environ.get("PARAM_ITC_DATA_PATH", "")),
        itc_data=auto_convert(os.environ.get("PARAM_ITC_DATA", "")),
        temperature=auto_convert(os.environ.get("PARAM_TEMPERATURE", "298.15")),
        protein_concentration=auto_convert(os.environ.get("PARAM_PROTEIN_CONCENTRATION", "")),
        ligand_concentration=auto_convert(os.environ.get("PARAM_LIGAND_CONCENTRATION", "")),
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
    "function": "analyze_itc_binding_thermodynamics",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_itc_binding_thermodynamics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_itc_binding_thermodynamics_output.txt", "w") as f:
    f.write("Biomni: Analyze Itc Binding Thermodynamics" + NL)
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
        biomni_function: "analyze_itc_binding_thermodynamics"
    END_VERSIONS
    """
}

workflow ANALYZE_ITC_BINDING_THERMODYNAMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_ITC_BINDING_THERMODYNAMICS(ch_input)

    emit:
    results = ANALYZE_ITC_BINDING_THERMODYNAMICS.out.results
    output = ANALYZE_ITC_BINDING_THERMODYNAMICS.out.output
    versions = ANALYZE_ITC_BINDING_THERMODYNAMICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_ITC_BINDING_THERMODYNAMICS_WORKFLOW(ch_input)

    ANALYZE_ITC_BINDING_THERMODYNAMICS_WORKFLOW.out.output.view { "Output: $it" }
}
