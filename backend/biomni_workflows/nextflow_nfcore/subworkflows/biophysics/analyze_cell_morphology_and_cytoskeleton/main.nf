#!/usr/bin/env nextflow
/*
 * biophysics/analyze_cell_morphology_and_cytoskeleton
 * Quantifies cell morphology and cytoskeletal organization from fluorescence microscopy images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = './results'
params.threshold_method = 'otsu'

process ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_cell_morphology_and_cytoskeleton_results.json"), emit: results
    tuple val(meta), path("analyze_cell_morphology_and_cytoskeleton_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_cell_morphology_and_cytoskeleton(image_path, output_dir="./results", threshold_method="otsu"):
    '''Quantifies cell morphology and cytoskeletal organization from fluorescence microscopy images.

    Parameters
    ----------
    image_path : str
        Path to the fluorescence microscopy image file
    output_dir : str, optional
        Directory to save output files (default: './results')
    threshold_method : str, optional
        Method for cell segmentation ('otsu', 'adaptive', or 'manual') (default: 'otsu')

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    from datetime import datetime

    import cv2
    import numpy as np
    import pandas as pd
    from skimage import exposure, feature, filters, io, measure, morphology
    from skimage.color import rgb2gray

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Start log
    log = f"Cell Morphology and Cytoskeleton Analysis Log - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n"
    log += f"Analyzing image: {image_path}\\n\\n"

    # Load image
    log += "Step 1: Loading and preprocessing image\\n"
    try:
        image = io.imread(image_path)
        # Convert to grayscale if RGB
        if len(image.shape) > 2:
            gray_image = rgb2gray(image)
            log += "- Converted RGB image to grayscale\\n"
        else:
            gray_image = image

        # Enhance contrast
        gray_image = exposure.equalize_hist(gray_image)
        log += "- Enhanced image contrast\\n"
    except Exception as e:
        return f"Error loading image: {str(e)}"

    # Segment cells
    log += "\\nStep 2: Segmenting cells from background\\n"
    if threshold_method == "otsu":
        thresh = filters.threshold_otsu(gray_image)
        binary = gray_image > thresh
        log += f"- Applied Otsu thresholding (threshold value: {thresh:.4f})\\n"
    elif threshold_method == "adaptive":
        binary = filters.threshold_local(gray_image, block_size=35, offset=0.05)
        binary = gray_image > binary
        log += "- Applied adaptive thresholding\\n"
    else:  # manual
        thresh = 0.5  # Default value, can be parameterized
        binary = gray_image > thresh
        log += f"- Applied manual thresholding (threshold value: {thresh:.4f})\\n"

    # Clean up binary image
    binary = morphology.remove_small_objects(binary, min_size=100)
    binary = morphology.remove_small_holes(binary, area_threshold=100)
    binary = morphology.binary_closing(binary, morphology.disk(3))
    log += "- Applied morphological operations to clean segmentation\\n"

    # Label cells
    labeled_cells, num_cells = measure.label(binary, return_num=True)
    log += f"- Identified {num_cells} cell regions\\n"

    # Analyze cell properties
    log += "\\nStep 3: Analyzing cell morphology\\n"
    cell_props = measure.regionprops_table(
        labeled_cells,
        gray_image,
        properties=(
            "area",
            "perimeter",
            "major_axis_length",
            "minor_axis_length",
            "eccentricity",
            "orientation",
            "solidity",
        ),
    )

    # Convert to DataFrame for easier manipulation
    cell_df = pd.DataFrame(cell_props)

    # Calculate additional metrics
    if len(cell_df) > 0:
        cell_df["aspect_ratio"] = cell_df["major_axis_length"] / cell_df["minor_axis_length"]
        cell_df["circularity"] = (4 * np.pi * cell_df["area"]) / (cell_df["perimeter"] ** 2)

        # Summary statistics
        log += f"- Average cell area: {cell_df['area'].mean():.2f} pixels\\n"
        log += f"- Average aspect ratio: {cell_df['aspect_ratio'].mean():.2f}\\n"
        log += f"- Average circularity: {cell_df['circularity'].mean():.2f}\\n"
        log += f"- Average eccentricity: {cell_df['eccentricity'].mean():.2f}\\n"
    else:
        log += "- No cells detected for morphological analysis\\n"

    # Analyze cytoskeletal organization
    log += "\\nStep 4: Analyzing cytoskeletal organization\\n"

    # Edge detection to highlight cytoskeletal fibers
    edges = feature.canny(gray_image, sigma=2)

    # Use Hough transform to detect lines (cytoskeletal fibers)
    if np.any(edges):
        lines = cv2.HoughLinesP(
            edges.astype(np.uint8),
            1,
            np.pi / 180,
            threshold=10,
            minLineLength=10,
            maxLineGap=5,
        )

        if lines is not None:
            # Calculate line orientations
            orientations = []
            for line in lines:
                x1, y1, x2, y2 = line[0]
                if x2 - x1 != 0:  # Avoid division by zero
                    angle = np.arctan2(y2 - y1, x2 - x1) * 180 / np.pi
                    orientations.append(angle)

            if orientations:
                # Convert to numpy array for calculations
                orientations = np.array(orientations)

                # Calculate alignment metrics
                mean_orientation = np.mean(orientations)
                # Normalize angles to -90 to 90 degrees
                norm_angles = np.mod(orientations + 90, 180) - 90
                std_orientation = np.std(norm_angles)

                # Order parameter (measure of alignment, 1 = perfectly aligned, 0 = random)
                # Convert angles to radians for calculation
                rad_angles = np.radians(norm_angles)
                order_parameter = np.sqrt(np.mean(np.cos(2 * rad_angles)) ** 2 + np.mean(np.sin(2 * rad_angles)) ** 2)

                log += f"- Detected {len(orientations)} cytoskeletal fibers\\n"
                log += f"- Mean fiber orientation: {mean_orientation:.2f} degrees\\n"
                log += f"- Standard deviation of orientation: {std_orientation:.2f} degrees\\n"
                log += f"- Order parameter (alignment): {order_parameter:.4f} (0=random, 1=aligned)\\n"

                # Add fiber data to dataframe
                fiber_df = pd.DataFrame({"fiber_orientation": orientations})
            else:
                log += "- No fiber orientations could be calculated\\n"
                fiber_df = pd.DataFrame()
        else:
            log += "- No cytoskeletal fibers detected\\n"
            fiber_df = pd.DataFrame()
    else:
        log += "- No edges detected for cytoskeletal analysis\\n"
        fiber_df = pd.DataFrame()

    # Save results
    log += "\\nStep 5: Saving results\\n"

    # Save cell morphology data
    if len(cell_df) > 0:
        cell_csv_path = os.path.join(output_dir, "cell_morphology_data.csv")
        cell_df.to_csv(cell_csv_path, index=False)
        log += f"- Cell morphology data saved to: {cell_csv_path}\\n"

    # Save fiber orientation data
    if len(fiber_df) > 0:
        fiber_csv_path = os.path.join(output_dir, "fiber_orientation_data.csv")
        fiber_df.to_csv(fiber_csv_path, index=False)
        log += f"- Fiber orientation data saved to: {fiber_csv_path}\\n"

    # Save segmentation image
    if num_cells > 0:
        segmentation_path = os.path.join(output_dir, "cell_segmentation.png")
        io.imsave(segmentation_path, labeled_cells.astype(np.uint8) * 50)
        log += f"- Cell segmentation image saved to: {segmentation_path}\\n"

    # Summary
    log += "\\nAnalysis Summary:\\n"
    log += f"- Processed image: {image_path}\\n"
    log += f"- Detected {num_cells} cells\\n"
    if len(cell_df) > 0:
        log += f"- Cell size range: {cell_df['area'].min():.1f} to {cell_df['area'].max():.1f} pixels\\n"
        log += f"- Cell shape: average aspect ratio = {cell_df['aspect_ratio'].mean():.2f}\\n"
    if "order_parameter" in locals():
        log += f"- Cytoskeletal organization: alignment parameter = {order_parameter:.4f}\\n"

    return log

# Execute the function
try:
    result = analyze_cell_morphology_and_cytoskeleton(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
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
    "function": "analyze_cell_morphology_and_cytoskeleton",
    "domain": "biophysics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_cell_morphology_and_cytoskeleton_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_cell_morphology_and_cytoskeleton_output.txt", "w") as f:
    f.write("Biomni: Analyze Cell Morphology And Cytoskeleton" + NL)
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
        biomni_function: "analyze_cell_morphology_and_cytoskeleton"
    END_VERSIONS
    """
}

workflow ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON(ch_input)

    emit:
    results = ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON.out.results
    output = ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON.out.output
    versions = ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON_WORKFLOW(ch_input)

    ANALYZE_CELL_MORPHOLOGY_AND_CYTOSKELETON_WORKFLOW.out.output.view { "Output: $it" }
}
