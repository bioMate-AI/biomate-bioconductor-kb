#!/usr/bin/env nextflow
/*
 * pathology/analyze_intracellular_calcium_with_rhod2
 * Analyzes intracellular calcium concentration using Rhod-2 fluorescent indicator from microscopy images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Use inline-generated mock images (created in script)
params.background_image_path = 'mock_background.png'
params.control_image_path = 'mock_control.png'
params.sample_image_path = 'mock_sample.png'
params.output_dir = './output'

process ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2 {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_intracellular_calcium_with_rhod2_results.json"), emit: results
    tuple val(meta), path("analyze_intracellular_calcium_with_rhod2_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_BACKGROUND_IMAGE_PATH="${params.background_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CONTROL_IMAGE_PATH="${params.control_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAMPLE_IMAGE_PATH="${params.sample_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Create mock images for testing (Rhod-2 calcium imaging simulation)
    python3 << 'MOCKEOF'
import numpy as np
import cv2
# Background: low uniform noise (autofluorescence)
bg = np.random.normal(10, 2, (100, 100)).astype(np.uint8)
cv2.imwrite('mock_background.png', bg)
# Control: baseline cellular fluorescence (low calcium)
ctrl = np.random.normal(30, 5, (100, 100)).astype(np.uint8)
cv2.imwrite('mock_control.png', ctrl)
# Sample: elevated calcium (brighter signal after stimulation)
sample = np.random.normal(120, 15, (100, 100)).astype(np.uint8)
cv2.imwrite('mock_sample.png', sample)
MOCKEOF

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



def analyze_intracellular_calcium_with_rhod2(
    background_image_path, control_image_path, sample_image_path, output_dir="./output"
):
    '''Analyzes intracellular calcium concentration using Rhod-2 fluorescent indicator from microscopy images.

    Parameters
    ----------
    background_image_path : str
        Path to the background image (no cells, just media)
    control_image_path : str
        Path to the control image (cells without calcium stimulus)
    sample_image_path : str
        Path to the sample image (cells with calcium stimulus)
    output_dir : str, optional
        Directory to save output files, default is "./output"

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    from datetime import datetime

    import cv2
    import matplotlib.pyplot as plt
    import numpy as np

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Step 1: Load images
    background = cv2.imread(background_image_path, cv2.IMREAD_GRAYSCALE).astype(float)
    control = cv2.imread(control_image_path, cv2.IMREAD_GRAYSCALE).astype(float)
    sample = cv2.imread(sample_image_path, cv2.IMREAD_GRAYSCALE).astype(float)

    # Step 2: Background subtraction
    control_corrected = np.maximum(control - background, 0)
    sample_corrected = np.maximum(sample - background, 0)

    # Step 3: Calculate fluorescence intensity (mean values)
    control_intensity = np.mean(control_corrected)
    sample_intensity = np.mean(sample_corrected)

    # Step 4: Convert to calcium concentration using a standard calibration equation
    # [Ca2+] = Kd * (F - Fmin) / (Fmax - F)
    # For Rhod-2, Kd is approximately 570 nM
    # We'll use control as Fmin and estimate Fmax as 2.5x the sample value (typical for max calcium response)
    kd = 570  # nM
    f_min = control_intensity
    f_max = 2.5 * sample_intensity  # Estimated maximum
    f = sample_intensity

    # Guard against division by zero
    calcium_concentration = float("inf") if f_max == f else kd * (f - f_min) / (f_max - f)

    # Step 5: Generate heatmap visualization of calcium concentration
    plt.figure(figsize=(10, 8))
    calcium_map = (sample_corrected - control_corrected) / (f_max - control_corrected + 1e-10) * kd
    plt.imshow(calcium_map, cmap="hot")
    plt.colorbar(label="[Ca²⁺] (nM)")
    plt.title("Intracellular Calcium Concentration Map")

    # Save the visualization
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    result_filename = f"{output_dir}/calcium_map_{timestamp}.png"
    plt.savefig(result_filename)
    plt.close()

    # Generate research log
    log = f'''
Intracellular Calcium Imaging Analysis Log - {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
------------------------------------------------------------
1. Loaded microscopy images:
   - Background image: {background_image_path}
   - Control image: {control_image_path}
   - Sample image: {sample_image_path}

2. Performed background subtraction to correct for autofluorescence

3. Calculated fluorescence intensity:
   - Control intensity: {control_intensity:.2f} a.u.
   - Sample intensity: {sample_intensity:.2f} a.u.

4. Converted fluorescence to calcium concentration using Rhod-2 calibration:
   - Kd value: {kd} nM
   - Mean intracellular [Ca²⁺]: {calcium_concentration:.2f} nM

5. Generated calcium concentration heatmap saved to:
   - {result_filename}

Analysis complete. The sample shows {calcium_concentration:.2f} nM intracellular calcium concentration.
'''

    return log

# Execute the function
try:
    result = analyze_intracellular_calcium_with_rhod2(
        background_image_path=auto_convert(os.environ.get("PARAM_BACKGROUND_IMAGE_PATH", "")),
        control_image_path=auto_convert(os.environ.get("PARAM_CONTROL_IMAGE_PATH", "")),
        sample_image_path=auto_convert(os.environ.get("PARAM_SAMPLE_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./output")),
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
    "function": "analyze_intracellular_calcium_with_rhod2",
    "domain": "pathology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_intracellular_calcium_with_rhod2_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_intracellular_calcium_with_rhod2_output.txt", "w") as f:
    f.write("Biomni: Analyze Intracellular Calcium With Rhod2" + NL)
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
        biomni_function: "analyze_intracellular_calcium_with_rhod2"
    END_VERSIONS
    """
}

workflow ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2(ch_input)

    emit:
    results = ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2.out.results
    output = ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2.out.output
    versions = ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2_WORKFLOW(ch_input)

    ANALYZE_INTRACELLULAR_CALCIUM_WITH_RHOD2_WORKFLOW.out.output.view { "Output: $it" }
}
