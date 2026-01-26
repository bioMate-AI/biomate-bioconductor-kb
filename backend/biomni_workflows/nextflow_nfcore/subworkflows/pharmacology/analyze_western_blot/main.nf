#!/usr/bin/env nextflow
/*
 * pharmacology/analyze_western_blot
 * Performs densitometric analysis of Western blot images to quantify relative protein expression.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.blot_image_path = null
params.target_bands = null
params.loading_control_band = null
params.antibody_info = null
params.output_dir = './results'

process ANALYZE_WESTERN_BLOT {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_western_blot_results.json"), emit: results
    tuple val(meta), path("analyze_western_blot_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_BLOT_IMAGE_PATH="${params.blot_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TARGET_BANDS="${params.target_bands?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LOADING_CONTROL_BAND="${params.loading_control_band?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_ANTIBODY_INFO="${params.antibody_info?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_western_blot(
    blot_image_path,
    target_bands,
    loading_control_band,
    antibody_info,
    output_dir="./results",
):
    '''Performs densitometric analysis of Western blot images to quantify relative protein expression.

    Parameters
    ----------
    blot_image_path : str
        Path to the Western blot image file
    target_bands : list of dict
        List of dictionaries containing information about target protein bands
        Each dict should have 'name', 'roi' (region of interest as [x, y, width, height])
    loading_control_band : dict
        Dictionary with 'name' and 'roi' for the loading control protein (e.g., β-actin, GAPDH)
    antibody_info : dict
        Dictionary containing information about antibodies used
        Should have 'primary' and 'secondary' keys with antibody details
    output_dir : str, optional
        Directory to save output files, defaults to './results'

    Returns
    -------
    str
        Research log summarizing the Western blot analysis process and results

    '''
    import os

    import numpy as np
    from skimage import io

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Load the Western blot image
    image = io.imread(blot_image_path)
    if len(image.shape) > 2:  # Convert to grayscale if color image
        image = np.mean(image, axis=2).astype(np.uint8)

    # Initialize results dictionary
    results = {
        "loading_control": {"name": loading_control_band["name"], "intensity": 0},
        "targets": [],
    }

    # Analyze loading control band
    lc_roi = loading_control_band["roi"]
    lc_band = image[lc_roi[1] : lc_roi[1] + lc_roi[3], lc_roi[0] : lc_roi[0] + lc_roi[2]]
    lc_intensity = np.sum(lc_band)
    results["loading_control"]["intensity"] = lc_intensity

    # Analyze target protein bands
    for band in target_bands:
        roi = band["roi"]
        band_img = image[roi[1] : roi[1] + roi[3], roi[0] : roi[0] + roi[2]]
        band_intensity = np.sum(band_img)

        # Calculate relative expression (normalized to loading control)
        relative_expression = band_intensity / lc_intensity

        results["targets"].append(
            {
                "name": band["name"],
                "intensity": band_intensity,
                "relative_expression": relative_expression,
            }
        )

    # Generate results table and save to CSV
    results_file = os.path.join(output_dir, "western_blot_results.csv")
    with open(results_file, "w") as f:
        f.write("Protein,Raw Intensity,Relative Expression\\n")
        f.write(f"{results['loading_control']['name']},{results['loading_control']['intensity']},1.0\\n")
        for target in results["targets"]:
            f.write(f"{target['name']},{target['intensity']},{target['relative_expression']:.4f}\\n")

    # Generate research log
    log = "## Western Blot Analysis\\n\\n"
    log += f"Analyzed Western blot image: {os.path.basename(blot_image_path)}\\n\\n"
    log += "### Antibodies Used\\n"
    log += f"Primary antibody: {antibody_info['primary']}\\n"
    log += f"Secondary antibody: {antibody_info['secondary']}\\n\\n"
    log += "### Analysis Steps\\n"
    log += "1. Loaded Western blot image and converted to grayscale\\n"
    log += f"2. Quantified loading control ({loading_control_band['name']}) band intensity\\n"
    log += "3. Measured target protein band intensities\\n"
    log += "4. Calculated relative expression by normalizing to loading control\\n\\n"
    log += "### Results\\n"
    log += f"Loading control ({loading_control_band['name']}): {results['loading_control']['intensity']} intensity units\\n\\n"
    log += "Target proteins:\\n"
    for target in results["targets"]:
        log += f"- {target['name']}: {target['intensity']} intensity units, "
        log += f"{target['relative_expression']:.4f} relative expression\\n"
    log += f"\\nDetailed results saved to: {results_file}\\n"

    return log

# Execute the function
try:
    result = analyze_western_blot(
        blot_image_path=auto_convert(os.environ.get("PARAM_BLOT_IMAGE_PATH", "")),
        target_bands=auto_convert(os.environ.get("PARAM_TARGET_BANDS", "")),
        loading_control_band=auto_convert(os.environ.get("PARAM_LOADING_CONTROL_BAND", "")),
        antibody_info=auto_convert(os.environ.get("PARAM_ANTIBODY_INFO", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
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
    "function": "analyze_western_blot",
    "domain": "pharmacology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_western_blot_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_western_blot_output.txt", "w") as f:
    f.write("Biomni: Analyze Western Blot" + NL)
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
        biomni_function: "analyze_western_blot"
    END_VERSIONS
    """
}

workflow ANALYZE_WESTERN_BLOT_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_WESTERN_BLOT(ch_input)

    emit:
    results = ANALYZE_WESTERN_BLOT.out.results
    output = ANALYZE_WESTERN_BLOT.out.output
    versions = ANALYZE_WESTERN_BLOT.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_WESTERN_BLOT_WORKFLOW(ch_input)

    ANALYZE_WESTERN_BLOT_WORKFLOW.out.output.view { "Output: $it" }
}
