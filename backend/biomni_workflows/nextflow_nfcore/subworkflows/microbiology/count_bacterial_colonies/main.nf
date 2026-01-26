#!/usr/bin/env nextflow
/*
 * microbiology/count_bacterial_colonies
 * Count bacterial colonies from an image of agar plate using computer vision techniques.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.dilution_factor = '1'
params.plate_area_cm2 = '65.0'
params.output_dir = './output'

process COUNT_BACTERIAL_COLONIES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("count_bacterial_colonies_results.json"), emit: results
    tuple val(meta), path("count_bacterial_colonies_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DILUTION_FACTOR="${params.dilution_factor?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PLATE_AREA_CM2="${params.plate_area_cm2?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def count_bacterial_colonies(image_path, dilution_factor=1, plate_area_cm2=65.0, output_dir="./output"):
    '''Count bacterial colonies from an image of agar plate using computer vision techniques.

    Parameters
    ----------
    image_path : str
        Path to the image file containing bacterial colonies on agar plate
    dilution_factor : float
        Dilution factor of the plated sample (default=1)
    plate_area_cm2 : float
        Area of the agar plate in square centimeters (default=65.0, standard Petri dish)
    output_dir : str
        Directory to save output images and results (default="./output")

    Returns
    -------
    str
        Research log summarizing the colony counting process and results

    '''
    import os
    from datetime import datetime

    import cv2
    import numpy as np
    from scipy import ndimage

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Load the image
    original_image = cv2.imread(image_path)
    if original_image is None:
        error_message = f"Error: Could not load image from {image_path}. Please check if the file exists and is a valid image format."
        return error_message

    # Convert to grayscale
    gray = cv2.cvtColor(original_image, cv2.COLOR_BGR2GRAY)

    # Apply Gaussian blur to reduce noise
    blurred = cv2.GaussianBlur(gray, (7, 7), 0)

    # Apply threshold to get binary image
    _, thresh = cv2.threshold(blurred, 0, 255, cv2.THRESH_BINARY_INV + cv2.THRESH_OTSU)

    # Perform morphological operations to remove small noise
    kernel = np.ones((3, 3), np.uint8)
    opening = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, kernel, iterations=2)

    # Sure background area
    sure_bg = cv2.dilate(opening, kernel, iterations=3)

    # Finding sure foreground area
    dist_transform = cv2.distanceTransform(opening, cv2.DIST_L2, 5)
    _, sure_fg = cv2.threshold(dist_transform, 0.5 * dist_transform.max(), 255, 0)
    sure_fg = np.uint8(sure_fg)

    # Finding unknown region
    unknown = cv2.subtract(sure_bg, sure_fg)

    # Marker labelling
    _, markers = cv2.connectedComponents(sure_fg)

    # Add one to all labels so that background is 1 instead of 0
    markers = markers + 1

    # Mark the region of unknown with zero
    markers[unknown == 255] = 0

    # Apply watershed
    markers = cv2.watershed(original_image, markers)

    # Count colonies (exclude background marker 1)
    unique_markers = np.unique(markers)
    colony_count = len(unique_markers) - 2  # Subtract background (1) and boundary (-1)

    # Calculate CFU concentration
    cfu_per_ml = colony_count * dilution_factor
    cfu_per_cm2 = cfu_per_ml / plate_area_cm2

    # Create output image showing detected colonies
    output_image = original_image.copy()
    output_image[markers == -1] = [0, 0, 255]  # Mark boundaries in red

    # Draw centroids and numbers on colonies
    labeled_array = ndimage.label(markers > 1)[0]
    for i, region in enumerate(ndimage.find_objects(labeled_array)):
        if region is not None:
            y_slice, x_slice = region
            y = (y_slice.start + y_slice.stop) // 2
            x = (x_slice.start + x_slice.stop) // 2
            cv2.circle(output_image, (x, y), 5, (0, 255, 0), -1)
            cv2.putText(
                output_image,
                str(i + 1),
                (x - 10, y - 10),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.5,
                (0, 255, 0),
                2,
            )

    # Save output image
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_filename = f"colony_count_{timestamp}.jpg"
    output_path = os.path.join(output_dir, output_filename)
    cv2.imwrite(output_path, output_image)

    # Generate research log
    log = f'''
Automated Bacterial Colony Counting - Research Log
=================================================
Date and Time: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
Input Image: {image_path}
Dilution Factor: {dilution_factor}
Plate Area: {plate_area_cm2} cm²

Methodology:
1. Loaded and converted image to grayscale
2. Applied Gaussian blur to reduce noise
3. Used Otsu's thresholding to separate colonies from background
4. Performed morphological operations to clean the image
5. Applied watershed algorithm to separate touching colonies
6. Counted unique colony markers

Results:
- Total Colony Count: {colony_count} CFUs
- Concentration: {cfu_per_ml:.2f} CFU/ml
- Area Density: {cfu_per_cm2:.2f} CFU/cm²

Output visualization saved as: {output_filename}
'''

    return log

# Execute the function
try:
    result = count_bacterial_colonies(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        dilution_factor=auto_convert(os.environ.get("PARAM_DILUTION_FACTOR", "1")),
        plate_area_cm2=auto_convert(os.environ.get("PARAM_PLATE_AREA_CM2", "65.0")),
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
    "function": "count_bacterial_colonies",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("count_bacterial_colonies_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("count_bacterial_colonies_output.txt", "w") as f:
    f.write("Biomni: Count Bacterial Colonies" + NL)
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
        biomni_function: "count_bacterial_colonies"
    END_VERSIONS
    """
}

workflow COUNT_BACTERIAL_COLONIES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    COUNT_BACTERIAL_COLONIES(ch_input)

    emit:
    results = COUNT_BACTERIAL_COLONIES.out.results
    output = COUNT_BACTERIAL_COLONIES.out.output
    versions = COUNT_BACTERIAL_COLONIES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    COUNT_BACTERIAL_COLONIES_WORKFLOW(ch_input)

    COUNT_BACTERIAL_COLONIES_WORKFLOW.out.output.view { "Output: $it" }
}
