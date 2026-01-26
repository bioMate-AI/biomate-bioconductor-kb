#!/usr/bin/env nextflow
/*
 * pathology/quantify_corneal_nerve_fibers
 * Quantify the volume/density of immunofluorescence-labeled corneal nerve fibers.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.marker_type = null
params.output_dir = './output'
params.threshold_method = 'otsu'

process QUANTIFY_CORNEAL_NERVE_FIBERS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("quantify_corneal_nerve_fibers_results.json"), emit: results
    tuple val(meta), path("quantify_corneal_nerve_fibers_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MARKER_TYPE="${params.marker_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD_METHOD="${params.threshold_method?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def quantify_corneal_nerve_fibers(image_path, marker_type, output_dir="./output", threshold_method="otsu"):
    '''Quantify the volume/density of immunofluorescence-labeled corneal nerve fibers.

    Parameters
    ----------
    image_path : str
        Path to the immunofluorescence microscopy image file
    marker_type : str
        Type of nerve fiber marker (e.g., 'βIII-tubulin', 'SP', 'L1CAM')
    output_dir : str, optional
        Directory to save output files (default: './output')
    threshold_method : str, optional
        Method for thresholding ('otsu', 'adaptive', 'manual'), default is 'otsu'

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    from datetime import datetime

    import numpy as np
    from skimage import filters, io, measure, morphology, util
    from skimage.color import rgb2gray

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Generate timestamp for unique filenames
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_filename = f"{marker_type.replace(' ', '_')}_{timestamp}"

    # Step 1: Load the image
    try:
        image = io.imread(image_path)
        # Convert to grayscale if RGB
        if len(image.shape) > 2:
            image = rgb2gray(image)
    except Exception as e:
        return f"Error loading image: {str(e)}"

    # Step 2: Preprocess the image
    # Normalize to 0-1 range
    image_normalized = image.astype(float)
    image_normalized = (image_normalized - image_normalized.min()) / (image_normalized.max() - image_normalized.min())

    # Step 3: Segment the nerve fibers
    if threshold_method == "otsu":
        threshold_value = filters.threshold_otsu(image_normalized)
    elif threshold_method == "adaptive":
        threshold_value = filters.threshold_local(image_normalized, block_size=35)
    else:  # manual
        threshold_value = 0.5  # Default manual threshold

    # Create binary mask
    binary_mask = image_normalized > threshold_value

    # Step 4: Clean up with morphological operations
    # Remove small objects
    cleaned_mask = morphology.remove_small_objects(binary_mask, min_size=50)
    # Fill holes
    cleaned_mask = morphology.closing(cleaned_mask, morphology.disk(2))

    # Step 5: Quantify the nerve fibers
    # Calculate total area of nerve fibers (in pixels)
    fiber_area = np.sum(cleaned_mask)
    # Calculate total image area
    total_area = cleaned_mask.size
    # Calculate fiber density (percentage of area covered by fibers)
    fiber_density = (fiber_area / total_area) * 100

    # Calculate properties of individual fiber segments
    labeled_fibers = measure.label(cleaned_mask)
    fiber_props = measure.regionprops(labeled_fibers)

    # Calculate average fiber length and width
    total_length = 0
    total_width = 0
    fiber_count = len(fiber_props)

    if fiber_count > 0:
        for prop in fiber_props:
            # Approximating length as major axis length
            total_length += prop.major_axis_length
            # Approximating width as minor axis length
            total_width += prop.minor_axis_length

        avg_length = total_length / fiber_count
        avg_width = total_width / fiber_count
    else:
        avg_length = 0
        avg_width = 0

    # Step 6: Save results
    # Save segmented image
    segmented_image_path = os.path.join(output_dir, f"{base_filename}_segmented.png")
    io.imsave(segmented_image_path, util.img_as_ubyte(cleaned_mask))

    # Save measurements to CSV
    measurements_path = os.path.join(output_dir, f"{base_filename}_measurements.csv")
    with open(measurements_path, "w") as f:
        f.write("Metric,Value\\n")
        f.write(f"Marker Type,{marker_type}\\n")
        f.write(f"Fiber Area (pixels),{fiber_area}\\n")
        f.write(f"Total Image Area (pixels),{total_area}\\n")
        f.write(f"Fiber Density (%),{fiber_density:.2f}\\n")
        f.write(f"Fiber Count,{fiber_count}\\n")
        f.write(f"Average Fiber Length (pixels),{avg_length:.2f}\\n")
        f.write(f"Average Fiber Width (pixels),{avg_width:.2f}\\n")

    # Step 7: Generate research log
    log = f'''
Research Log: Quantification of {marker_type} Labeled Corneal Nerve Fibers
Date: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
Image: {os.path.basename(image_path)}

Analysis Steps:
1. Loaded and preprocessed the immunofluorescence microscopy image
2. Applied {threshold_method} thresholding for nerve fiber segmentation
3. Performed morphological operations to clean the segmentation
4. Quantified nerve fiber metrics

Results:
- Fiber Area: {fiber_area} pixels
- Total Image Area: {total_area} pixels
- Fiber Density: {fiber_density:.2f}%
- Number of Fiber Segments: {fiber_count}
- Average Fiber Length: {avg_length:.2f} pixels
- Average Fiber Width: {avg_width:.2f} pixels

Output Files:
- Segmented Image: {os.path.basename(segmented_image_path)}
- Measurements: {os.path.basename(measurements_path)}
'''

    return log

# Execute the function
try:
    result = quantify_corneal_nerve_fibers(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        marker_type=auto_convert(os.environ.get("PARAM_MARKER_TYPE", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./output")),
        threshold_method=auto_convert(os.environ.get("PARAM_THRESHOLD_METHOD", "otsu")),
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
    "function": "quantify_corneal_nerve_fibers",
    "domain": "pathology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("quantify_corneal_nerve_fibers_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("quantify_corneal_nerve_fibers_output.txt", "w") as f:
    f.write("Biomni: Quantify Corneal Nerve Fibers" + NL)
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
        biomni_function: "quantify_corneal_nerve_fibers"
    END_VERSIONS
    """
}

workflow QUANTIFY_CORNEAL_NERVE_FIBERS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    QUANTIFY_CORNEAL_NERVE_FIBERS(ch_input)

    emit:
    results = QUANTIFY_CORNEAL_NERVE_FIBERS.out.results
    output = QUANTIFY_CORNEAL_NERVE_FIBERS.out.output
    versions = QUANTIFY_CORNEAL_NERVE_FIBERS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    QUANTIFY_CORNEAL_NERVE_FIBERS_WORKFLOW(ch_input)

    QUANTIFY_CORNEAL_NERVE_FIBERS_WORKFLOW.out.output.view { "Output: $it" }
}
