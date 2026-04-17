#!/usr/bin/env nextflow
/*
 * physiology/calculate_brain_adc_map
 * Calculate Apparent Diffusion Coefficient (ADC) map from diffusion-weighted MRI data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Uses inline-generated mock DWI data
params.dwi_file_path = 'mock_dwi.nii.gz'
params.b_values = '[0, 500, 1000]'
params.output_path = 'adc_map.nii.gz'
params.mask_file_path = null

process CALCULATE_BRAIN_ADC_MAP {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("calculate_brain_adc_map_results.json"), emit: results
    tuple val(meta), path("calculate_brain_adc_map_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_DWI_FILE_PATH="${params.dwi_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_B_VALUES="${params.b_values?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PATH="${params.output_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MASK_FILE_PATH="${params.mask_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Generate mock DWI data for testing

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



def calculate_brain_adc_map(dwi_file_path, b_values, output_path="adc_map.nii.gz", mask_file_path=None):
    '''Calculate Apparent Diffusion Coefficient (ADC) map from diffusion-weighted MRI data.

    This function fits the DW-MRI data to the monoexponential diffusion model:
    S = S0 * exp(-b * ADC), where S is the signal intensity, S0 is the signal without
    diffusion weighting, b is the b-value, and ADC is the apparent diffusion coefficient.

    Parameters
    ----------
    dwi_file_path : str
        Path to the 4D NIfTI file containing diffusion-weighted MRI data,
        where the 4th dimension corresponds to different b-values.
    b_values : list or numpy.ndarray
        List of b-values corresponding to each volume in the 4D DWI data.
    output_path : str, optional
        Path where the output ADC map will be saved (default: "adc_map.nii.gz").
    mask_file_path : str, optional
        Path to a binary mask file to limit ADC calculation to brain regions (default: None).

    Returns
    -------
    str
        Research log summarizing the ADC mapping process and results.

    '''
    import os

    import nibabel as nib
    import numpy as np
    from scipy.optimize import curve_fit

    # Start research log
    research_log = "Brain Water Diffusion Mapping Research Log\\n"
    research_log += "=" * 50 + "\\n\\n"

    # Step 1: Load DWI data
    research_log += "Step 1: Loading diffusion-weighted MRI data\\n"
    dwi_img = nib.load(dwi_file_path)
    dwi_data = dwi_img.get_fdata()
    research_log += f"- Loaded DWI data with shape: {dwi_data.shape}\\n"
    research_log += f"- B-values: {b_values}\\n\\n"

    # Step 2: Load mask if provided
    if mask_file_path:
        research_log += "Step 2: Loading brain mask\\n"
        mask_img = nib.load(mask_file_path)
        mask_data = mask_img.get_fdata() > 0  # Convert to boolean
        research_log += f"- Loaded mask with {np.sum(mask_data)} voxels to process\\n\\n"
    else:
        research_log += "Step 2: No mask provided, processing all voxels\\n"
        # Create a mask where signal in the baseline image is above a threshold
        baseline_idx = np.argmin(b_values)  # Typically b=0 image
        mask_data = dwi_data[:, :, :, baseline_idx] > np.mean(dwi_data[:, :, :, baseline_idx]) * 0.1
        research_log += f"- Created automatic mask with {np.sum(mask_data)} voxels to process\\n\\n"

    # Step 3: Define the monoexponential diffusion model
    research_log += "Step 3: Fitting data to monoexponential diffusion model\\n"
    research_log += "- Using model: S = S0 * exp(-b * ADC)\\n"

    def mono_exp_model(b, S0, ADC):
        return S0 * np.exp(-b * ADC)

    # Step 4: Calculate ADC map
    shape = dwi_data.shape[:3]
    adc_map = np.zeros(shape)
    S0_map = np.zeros(shape)

    # Convert b_values to numpy array if it's not already
    b_values = np.array(b_values)

    # Process only voxels within the mask
    total_voxels = np.sum(mask_data)
    processed_voxels = 0

    for x in range(shape[0]):
        for y in range(shape[1]):
            for z in range(shape[2]):
                if mask_data[x, y, z]:
                    signal = dwi_data[x, y, z, :]

                    # Skip voxels with zero or negative values
                    if np.any(signal <= 0):
                        continue

                    try:
                        # Fit the monoexponential model
                        params, _ = curve_fit(
                            mono_exp_model,
                            b_values,
                            signal,
                            p0=[signal[0], 0.001],  # Initial guess
                            bounds=([0, 0], [np.inf, 0.01]),
                        )
                        S0_map[x, y, z] = params[0]
                        adc_map[x, y, z] = params[1]
                        processed_voxels += 1
                    except Exception:
                        # If fitting fails, set ADC to 0
                        adc_map[x, y, z] = 0

    research_log += f"- Successfully processed {processed_voxels} out of {total_voxels} voxels\\n\\n"

    # Step 5: Save ADC map
    research_log += "Step 5: Saving ADC map\\n"
    # Convert ADC from mm²/s to µm²/ms for conventional display
    adc_map_save = adc_map * 1000  # Convert to µm²/ms
    adc_img = nib.Nifti1Image(adc_map_save, dwi_img.affine, dwi_img.header)
    nib.save(adc_img, output_path)
    research_log += f"- ADC map saved to: {os.path.abspath(output_path)}\\n"

    # Step 6: Calculate summary statistics
    valid_adcs = adc_map[mask_data & (adc_map > 0)]
    if len(valid_adcs) > 0:
        research_log += "\\nStep 6: ADC Statistics (in µm²/ms):\\n"
        research_log += f"- Mean ADC: {np.mean(valid_adcs) * 1000:.4f}\\n"
        research_log += f"- Median ADC: {np.median(valid_adcs) * 1000:.4f}\\n"
        research_log += f"- Min ADC: {np.min(valid_adcs) * 1000:.4f}\\n"
        research_log += f"- Max ADC: {np.max(valid_adcs) * 1000:.4f}\\n"
        research_log += f"- Std Dev ADC: {np.std(valid_adcs) * 1000:.4f}\\n"

    research_log += "\\nBrain water diffusion mapping completed successfully.\\n"

    return research_log

# Execute the function
try:
    result = calculate_brain_adc_map(
        dwi_file_path=auto_convert(os.environ.get("PARAM_DWI_FILE_PATH", "")),
        b_values=auto_convert(os.environ.get("PARAM_B_VALUES", "")),
        output_path=auto_convert(os.environ.get("PARAM_OUTPUT_PATH", "adc_map.nii.gz")),
        mask_file_path=auto_convert(os.environ.get("PARAM_MASK_FILE_PATH", "")),
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
    "function": "calculate_brain_adc_map",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("calculate_brain_adc_map_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("calculate_brain_adc_map_output.txt", "w") as f:
    f.write("Biomni: Calculate Brain Adc Map" + NL)
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
        biomni_function: "calculate_brain_adc_map"
    END_VERSIONS
    """
}

workflow CALCULATE_BRAIN_ADC_MAP_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CALCULATE_BRAIN_ADC_MAP(ch_input)

    emit:
    results = CALCULATE_BRAIN_ADC_MAP.out.results
    output = CALCULATE_BRAIN_ADC_MAP.out.output
    versions = CALCULATE_BRAIN_ADC_MAP.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CALCULATE_BRAIN_ADC_MAP_WORKFLOW(ch_input)

    CALCULATE_BRAIN_ADC_MAP_WORKFLOW.out.output.view { "Output: $it" }
}
