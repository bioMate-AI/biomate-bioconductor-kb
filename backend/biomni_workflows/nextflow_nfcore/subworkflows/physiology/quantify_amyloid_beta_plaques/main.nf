#!/usr/bin/env nextflow
/*
 * physiology/quantify_amyloid_beta_plaques
 * 
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Uses inline-generated mock amyloid plaque image
params.image_path = 'mock_amyloid_plaques.png'
params.output_dir = './results'
params.threshold_method = 'otsu'
params.min_plaque_size = '50'
params.manual_threshold = '127'

process QUANTIFY_AMYLOID_BETA_PLAQUES {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("quantify_amyloid_beta_plaques_results.json"), emit: results
    tuple val(meta), path("quantify_amyloid_beta_plaques_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD_METHOD="${params.threshold_method?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_PLAQUE_SIZE="${params.min_plaque_size?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MANUAL_THRESHOLD="${params.manual_threshold?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Generate mock amyloid plaque image for testing

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



def quantify_amyloid_beta_plaques(
    image_path,
    output_dir="./results",
    threshold_method="otsu",
    min_plaque_size=50,
    manual_threshold=127,
):
    import os
    from datetime import datetime

    import pandas as pd
    from skimage import color, filters, io, measure, morphology
    from skimage.segmentation import clear_border
    from skimage.util import img_as_ubyte

    os.makedirs(output_dir, exist_ok=True)
    original_image = io.imread(image_path)

    if len(original_image.shape) > 2 and original_image.shape[2] > 1:
        gray_image = color.rgb2gray(original_image)
    else:
        gray_image = original_image

    gray_image = img_as_ubyte(gray_image)
    smoothed_image = filters.gaussian(gray_image, sigma=1)

    if smoothed_image.shape[0] < 10 or smoothed_image.shape[1] < 10:
        raise ValueError("Image too small for reliable plaque detection.")

    if threshold_method == "otsu":
        threshold_value = filters.threshold_otsu(smoothed_image)
        binary_image = smoothed_image > threshold_value
    elif threshold_method == "adaptive":
        block_size = 35 if min(smoothed_image.shape) > 35 else min(smoothed_image.shape) // 2 * 2 + 1
        adaptive_thresh = filters.threshold_local(smoothed_image, block_size=block_size)
        binary_image = smoothed_image > adaptive_thresh
    else:
        threshold_value = manual_threshold
        binary_image = smoothed_image > threshold_value

    cleaned_binary = morphology.remove_small_objects(binary_image, min_size=min_plaque_size)
    labeled_image = measure.label(cleaned_binary)
    labeled_image = clear_border(labeled_image)

    regions = measure.regionprops(labeled_image, intensity_image=gray_image)
    plaque_data = []

    for region in regions:
        plaque_data.append(
            {
                "Area": region.area,
                "Perimeter": region.perimeter,
                "Mean_Intensity": region.mean_intensity,
                "Eccentricity": region.eccentricity,
            }
        )

    total_plaque_area = sum(r["Area"] for r in plaque_data)
    total_image_area = gray_image.size
    area_fraction = (total_plaque_area / total_image_area) * 100

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    csv_filename = f"{output_dir}/plaque_analysis_{timestamp}.csv"
    segmented_image_filename = f"{output_dir}/segmented_plaques_{timestamp}.png"

    if plaque_data:
        df = pd.DataFrame(plaque_data)
        df.to_csv(csv_filename, index=False)

        colored_labels = color.label2rgb(labeled_image, image=gray_image, bg_label=0, kind="overlay")
        io.imsave(segmented_image_filename, img_as_ubyte(colored_labels))

        log = f'''
Amyloid-β Plaque Analysis Research Log
======================================
Date: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
Image: {image_path}

Parameters:
- Threshold method: {threshold_method}
- Threshold value: {threshold_value if threshold_method != "adaptive" else "Adaptive local thresholding"}
- Minimum plaque size: {min_plaque_size} pixels²

Results:
- Total plaques detected: {len(plaque_data)}
- Avg plaque size: {df["Area"].mean():.2f} ± {df["Area"].std():.2f} pixels²
- Total plaque area: {total_plaque_area} pixels² ({area_fraction:.2f}% of tissue)
- Avg plaque intensity: {df["Mean_Intensity"].mean():.2f}

Outputs:
- Detailed CSV: {csv_filename}
- Segmented Image: {segmented_image_filename}
'''
    else:
        log = f'''
Amyloid-β Plaque Analysis Research Log
======================================
Date: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
Image: {image_path}

Parameters:
- Threshold method: {threshold_method}
- Threshold value: {threshold_value if threshold_method != "adaptive" else "Adaptive local thresholding"}
- Minimum plaque size: {min_plaque_size} pixels²

Results:
No plaques detected. Adjust threshold or minimum plaque size.
'''
    return log

# Execute the function
try:
    result = quantify_amyloid_beta_plaques(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
        threshold_method=auto_convert(os.environ.get("PARAM_THRESHOLD_METHOD", "otsu")),
        min_plaque_size=auto_convert(os.environ.get("PARAM_MIN_PLAQUE_SIZE", "50")),
        manual_threshold=auto_convert(os.environ.get("PARAM_MANUAL_THRESHOLD", "127")),
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
    "function": "quantify_amyloid_beta_plaques",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("quantify_amyloid_beta_plaques_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("quantify_amyloid_beta_plaques_output.txt", "w") as f:
    f.write("Biomni: Quantify Amyloid Beta Plaques" + NL)
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
        biomni_function: "quantify_amyloid_beta_plaques"
    END_VERSIONS
    """
}

workflow QUANTIFY_AMYLOID_BETA_PLAQUES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    QUANTIFY_AMYLOID_BETA_PLAQUES(ch_input)

    emit:
    results = QUANTIFY_AMYLOID_BETA_PLAQUES.out.results
    output = QUANTIFY_AMYLOID_BETA_PLAQUES.out.output
    versions = QUANTIFY_AMYLOID_BETA_PLAQUES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    QUANTIFY_AMYLOID_BETA_PLAQUES_WORKFLOW(ch_input)

    QUANTIFY_AMYLOID_BETA_PLAQUES_WORKFLOW.out.output.view { "Output: $it" }
}
