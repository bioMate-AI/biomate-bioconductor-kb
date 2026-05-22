#!/usr/bin/env nextflow
/*
 * biochemistry/analyze_circular_dichroism_spectra
 * Analyzes circular dichroism (CD) spectroscopy data to determine secondary structure and thermal stability.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.sample_name = null
params.sample_type = null
params.wavelength_data = null
params.cd_signal_data = null
params.temperature_data = null
params.thermal_cd_data = null
params.output_dir = './'

process ANALYZE_CIRCULAR_DICHROISM_SPECTRA {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_circular_dichroism_spectra_results.json"), emit: results
    tuple val(meta), path("analyze_circular_dichroism_spectra_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_SAMPLE_NAME="${params.sample_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAMPLE_TYPE="${params.sample_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_WAVELENGTH_DATA="${params.wavelength_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CD_SIGNAL_DATA="${params.cd_signal_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TEMPERATURE_DATA="${params.temperature_data?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THERMAL_CD_DATA="${params.thermal_cd_data?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_circular_dichroism_spectra(
    sample_name,
    sample_type,
    wavelength_data,
    cd_signal_data,
    temperature_data=None,
    thermal_cd_data=None,
    output_dir="./",
):
    '''Analyzes circular dichroism (CD) spectroscopy data to determine secondary structure and thermal stability.

    Parameters
    ----------
    sample_name : str
        Name of the biomolecule sample (e.g., "Znf706", "G-quadruplex")
    sample_type : str
        Type of biomolecule ("protein" or "nucleic_acid")
    wavelength_data : list or numpy.ndarray
        Wavelength values in nm for CD spectrum
    cd_signal_data : list or numpy.ndarray
        CD signal intensity values (typically in mdeg or Δε)
    temperature_data : list or numpy.ndarray, optional
        Temperature values (°C) for thermal denaturation experiment
    thermal_cd_data : list or numpy.ndarray, optional
        CD signal values at specific wavelength across different temperatures
    output_dir : str, optional
        Directory to save result files, defaults to current directory

    Returns
    -------
    str
        Research log summarizing the CD analysis steps and results

    '''
    import os
    from datetime import datetime

    import numpy as np

    # Validate inputs - use defaults if None
    if sample_name is None:
        sample_name = "TestSample"
    if sample_type is None:
        sample_type = "protein"
    if wavelength_data is None:
        wavelength_data = [190, 195, 200, 210, 220, 230, 240, 250]
    if cd_signal_data is None:
        cd_signal_data = [10, 8, -5, -15, -10, -5, 0, 2]
    sample_name = str(sample_name)
    sample_type = str(sample_type)

    # Initialize research log
    log = f"# Circular Dichroism Analysis Report for {sample_name}\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"
    log += "## Sample Information\\n"
    log += f"- Sample Name: {sample_name}\\n"
    log += f"- Sample Type: {sample_type}\\n\\n"

    # Convert inputs to numpy arrays if they aren't already
    wavelength_data = np.array(wavelength_data)
    cd_signal_data = np.array(cd_signal_data)

    # Ensure output directory exists
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # 1. Analyze CD spectrum for secondary structure
    log += "## Secondary Structure Analysis\\n"

    # Different analysis approaches based on sample type
    if sample_type.lower() == "protein":
        # Analyze protein secondary structure based on characteristic spectral features
        alpha_helix_signal = np.sum((wavelength_data >= 190) & (wavelength_data <= 195) & (cd_signal_data > 0))
        beta_sheet_signal = np.sum((wavelength_data >= 215) & (wavelength_data <= 220) & (cd_signal_data < 0))
        random_coil_signal = np.sum((wavelength_data >= 195) & (wavelength_data <= 200) & (cd_signal_data < 0))

        # Simple classification based on signal patterns
        if alpha_helix_signal > beta_sheet_signal and alpha_helix_signal > random_coil_signal:
            structure = "predominantly alpha-helical"
        elif beta_sheet_signal > alpha_helix_signal and beta_sheet_signal > random_coil_signal:
            structure = "predominantly beta-sheet"
        else:
            structure = "mixed or predominantly random coil"

        log += f"- The CD spectrum indicates {structure} structure for {sample_name}.\\n"
        log += "- Key spectral features:\\n"
        log += "  - 190-195 nm region: associated with alpha-helical content\\n"
        log += "  - 215-220 nm region: associated with beta-sheet content\\n\\n"

    elif sample_type.lower() == "nucleic_acid":
        # Analyze nucleic acid structure (e.g., G-quadruplex has characteristic positive peak ~295 nm)
        g_quadruplex_signal = np.sum((wavelength_data >= 290) & (wavelength_data <= 300) & (cd_signal_data > 0))
        b_form_signal = np.sum((wavelength_data >= 270) & (wavelength_data <= 280) & (cd_signal_data > 0))

        if g_quadruplex_signal > 0:
            structure = "G-quadruplex characteristics"
        elif b_form_signal > 0:
            structure = "B-form characteristics"
        else:
            structure = "non-standard structure"

        log += f"- The CD spectrum indicates {structure} for {sample_name}.\\n"
        log += "- Key spectral features:\\n"
        log += "  - 290-300 nm positive peak: characteristic of G-quadruplex structures\\n"
        log += "  - 270-280 nm positive peak: characteristic of B-form DNA\\n\\n"

    # Save spectral data results
    spectral_file = os.path.join(output_dir, f"{sample_name}_cd_spectrum_analysis.txt")
    with open(spectral_file, "w") as f:
        f.write("Wavelength (nm)\\tCD Signal\\n")
        for wl, signal in zip(wavelength_data, cd_signal_data, strict=False):
            f.write(f"{wl:.1f}\\t{signal:.4f}\\n")

    log += f"- Detailed spectral data saved to: {spectral_file}\\n\\n"

    # 2. Thermal stability analysis (if temperature data provided)
    if temperature_data is not None and thermal_cd_data is not None:
        temperature_data = np.array(temperature_data)
        thermal_cd_data = np.array(thermal_cd_data)

        log += "## Thermal Stability Analysis\\n"

        # Simple Tm estimation (melting temperature) - find temperature at 50% unfolding
        # Normalize thermal data to 0-1 range for unfolding fraction
        min_signal = np.min(thermal_cd_data)
        max_signal = np.max(thermal_cd_data)
        unfolded_fraction = (thermal_cd_data - min_signal) / (max_signal - min_signal)

        # Find the temperature closest to 50% unfolding
        tm_idx = np.argmin(np.abs(unfolded_fraction - 0.5))
        tm = temperature_data[tm_idx]

        log += f"- Estimated melting temperature (Tm): {tm:.1f}°C\\n"

        # Cooperativity assessment (crude estimate based on transition steepness)
        t_range = temperature_data[-1] - temperature_data[0]
        transition_width = (
            t_range / len(temperature_data) * np.sum((unfolded_fraction > 0.2) & (unfolded_fraction < 0.8))
        )

        if transition_width < 0.2 * t_range:
            cooperativity = "highly cooperative (sharp transition)"
        elif transition_width < 0.4 * t_range:
            cooperativity = "moderately cooperative"
        else:
            cooperativity = "non-cooperative (broad transition)"

        log += f"- Thermal transition: {cooperativity}\\n"

        # Save thermal denaturation data
        thermal_file = os.path.join(output_dir, f"{sample_name}_thermal_denaturation.txt")
        with open(thermal_file, "w") as f:
            f.write("Temperature (°C)\\tCD Signal\\tUnfolded Fraction\\n")
            for temp, signal, unfold in zip(temperature_data, thermal_cd_data, unfolded_fraction, strict=False):
                f.write(f"{temp:.1f}\\t{signal:.4f}\\t{unfold:.4f}\\n")

        log += f"- Thermal denaturation data saved to: {thermal_file}\\n\\n"

    # 3. Summary and conclusions
    log += "## Conclusions\\n"
    if sample_type.lower() == "protein":
        log += f"- {sample_name} shows {structure} according to CD spectroscopy.\\n"
    else:
        log += f"- {sample_name} exhibits {structure} according to CD spectroscopy.\\n"

    if temperature_data is not None:
        log += f"- The molecule has a melting temperature of {tm:.1f}°C with {cooperativity}.\\n"

    return log

# Execute the function
try:
    result = analyze_circular_dichroism_spectra(
        sample_name=auto_convert(os.environ.get("PARAM_SAMPLE_NAME", "")),
        sample_type=auto_convert(os.environ.get("PARAM_SAMPLE_TYPE", "")),
        wavelength_data=auto_convert(os.environ.get("PARAM_WAVELENGTH_DATA", "")),
        cd_signal_data=auto_convert(os.environ.get("PARAM_CD_SIGNAL_DATA", "")),
        temperature_data=auto_convert(os.environ.get("PARAM_TEMPERATURE_DATA", "")),
        thermal_cd_data=auto_convert(os.environ.get("PARAM_THERMAL_CD_DATA", "")),
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
    "function": "analyze_circular_dichroism_spectra",
    "domain": "biochemistry",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_circular_dichroism_spectra_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_circular_dichroism_spectra_output.txt", "w") as f:
    f.write("Biomni: Analyze Circular Dichroism Spectra" + NL)
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
        biomni_function: "analyze_circular_dichroism_spectra"
    END_VERSIONS
    """
}

workflow ANALYZE_CIRCULAR_DICHROISM_SPECTRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CIRCULAR_DICHROISM_SPECTRA(ch_input)

    emit:
    results = ANALYZE_CIRCULAR_DICHROISM_SPECTRA.out.results
    output = ANALYZE_CIRCULAR_DICHROISM_SPECTRA.out.output
    versions = ANALYZE_CIRCULAR_DICHROISM_SPECTRA.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CIRCULAR_DICHROISM_SPECTRA_WORKFLOW(ch_input)

    ANALYZE_CIRCULAR_DICHROISM_SPECTRA_WORKFLOW.out.output.view { "Output: $it" }
}
