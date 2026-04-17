#!/usr/bin/env nextflow
/*
 * pathology/analyze_thrombus_histology
 * Analyze histological images of thrombus samples stained with H&E to identify and quantify
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.output_dir = './output'

process ANALYZE_THROMBUS_HISTOLOGY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_thrombus_histology_results.json"), emit: results
    tuple val(meta), path("analyze_thrombus_histology_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_thrombus_histology(image_path, output_dir="./output"):
    '''Analyze histological images of thrombus samples stained with H&E to identify and quantify
    different thrombus components (fresh, cellular lysis, endothelialization, fibroblastic reaction).

    Parameters
    ----------
    image_path : str
        Path to the histological image of thrombus sample stained with H&E
    output_dir : str, optional
        Directory to save output files (default: "./output")

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    from datetime import datetime

    import cv2
    import numpy as np
    from skimage import color

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Initialize research log
    log = f"# Thrombus Component Analysis - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"
    log += f"Analyzing image: {image_path}\\n\\n"

    # Step 1: Load and preprocess the image
    log += "## Step 1: Image Loading and Preprocessing\\n"
    original_image = cv2.imread(image_path)
    if original_image is None:
        return f"Error: Could not load image from {image_path}"

    # Convert to RGB (from BGR)
    rgb_image = cv2.cvtColor(original_image, cv2.COLOR_BGR2RGB)
    log += f"- Loaded image with dimensions: {rgb_image.shape[1]}x{rgb_image.shape[0]} pixels\\n"

    # Convert to LAB color space for better color segmentation
    lab_image = color.rgb2lab(rgb_image)
    log += "- Converted image to LAB color space for improved color-based segmentation\\n\\n"

    # Step 2: Segment thrombus components based on color characteristics
    log += "## Step 2: Thrombus Component Segmentation\\n"

    # Create masks for different components based on color thresholds
    # These thresholds are approximate and may need adjustment for specific staining protocols

    # Fresh thrombus: typically red (erythrocytes) with blue nuclei (leukocytes)
    # Usually appears as bright red/pink areas with scattered dark blue/purple nuclei
    fresh_mask = (
        (lab_image[:, :, 0] > 50)  # Lightness
        & (lab_image[:, :, 1] > 15)  # a* channel (red component)
    )

    # Cellular lysis: degraded cellular components, less intense staining
    lysis_mask = (
        (lab_image[:, :, 0] > 60)  # Lightness
        & (lab_image[:, :, 1] < 15)  # Less red
        & (lab_image[:, :, 1] > -5)
        & (lab_image[:, :, 2] < 10)  # Less blue
    )

    # Endothelialization: endothelial cells lining the thrombus
    # Typically appears as thin, organized cellular layers
    endothel_mask = (
        (lab_image[:, :, 0] > 40) & (lab_image[:, :, 0] < 70) & (lab_image[:, :, 2] < -5)  # More blue component
    )

    # Fibroblastic reaction: fibroblasts and collagen deposition
    # Usually appears as pale pink/purple fibrous structures
    fibro_mask = (
        (lab_image[:, :, 0] > 70)  # Lighter areas
        & (lab_image[:, :, 1] < 5)  # Less red
        & (lab_image[:, :, 1] > -10)
        & (lab_image[:, :, 2] > 0)  # Less blue
    )

    log += "- Created masks for each thrombus component based on color characteristics\\n"

    # Step 3: Quantify the components
    log += "\\n## Step 3: Component Quantification\\n"

    # Calculate total pixel count (excluding background)
    total_pixels = fresh_mask.sum() + lysis_mask.sum() + endothel_mask.sum() + fibro_mask.sum()

    # Calculate percentages
    if total_pixels > 0:
        fresh_percent = (fresh_mask.sum() / total_pixels) * 100
        lysis_percent = (lysis_mask.sum() / total_pixels) * 100
        endothel_percent = (endothel_mask.sum() / total_pixels) * 100
        fibro_percent = (fibro_mask.sum() / total_pixels) * 100
    else:
        fresh_percent = lysis_percent = endothel_percent = fibro_percent = 0

    log += f"- Fresh thrombus: {fresh_percent:.2f}%\\n"
    log += f"- Cellular lysis: {lysis_percent:.2f}%\\n"
    log += f"- Endothelialization: {endothel_percent:.2f}%\\n"
    log += f"- Fibroblastic reaction: {fibro_percent:.2f}%\\n\\n"

    # Step 4: Visualize the results
    log += "## Step 4: Visualization\\n"

    # Create a visualization image
    visualization = np.zeros_like(rgb_image)

    # Assign colors to different components
    visualization[fresh_mask] = [255, 0, 0]  # Red for fresh thrombus
    visualization[lysis_mask] = [0, 255, 0]  # Green for cellular lysis
    visualization[endothel_mask] = [0, 0, 255]  # Blue for endothelialization
    visualization[fibro_mask] = [255, 255, 0]  # Yellow for fibroblastic reaction

    # Save the visualization
    output_filename = os.path.join(output_dir, f"thrombus_components_{os.path.basename(image_path)}")
    cv2.imwrite(output_filename, cv2.cvtColor(visualization, cv2.COLOR_RGB2BGR))

    log += f"- Visualization saved as: {output_filename}\\n"
    log += "- Color legend:\\n"
    log += "  - Red: Fresh thrombus\\n"
    log += "  - Green: Cellular lysis\\n"
    log += "  - Blue: Endothelialization\\n"
    log += "  - Yellow: Fibroblastic reaction\\n\\n"

    # Step 5: Summary
    log += "## Summary\\n"
    log += "The histological analysis of the thrombus sample revealed the following composition:\\n\\n"
    log += f"1. Fresh thrombus: {fresh_percent:.2f}%\\n"
    log += f"2. Cellular lysis: {lysis_percent:.2f}%\\n"
    log += f"3. Endothelialization: {endothel_percent:.2f}%\\n"
    log += f"4. Fibroblastic reaction: {fibro_percent:.2f}%\\n\\n"

    # Save results to CSV
    import csv

    csv_filename = os.path.join(
        output_dir,
        f"thrombus_analysis_{os.path.basename(image_path).split('.')[0]}.csv",
    )
    with open(csv_filename, "w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Component", "Percentage"])
        writer.writerow(["Fresh thrombus", f"{fresh_percent:.2f}"])
        writer.writerow(["Cellular lysis", f"{lysis_percent:.2f}"])
        writer.writerow(["Endothelialization", f"{endothel_percent:.2f}"])
        writer.writerow(["Fibroblastic reaction", f"{fibro_percent:.2f}"])

    log += f"Quantitative results saved to: {csv_filename}\\n"

    return log

# Execute the function
try:
    result = analyze_thrombus_histology(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
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
    "function": "analyze_thrombus_histology",
    "domain": "pathology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_thrombus_histology_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_thrombus_histology_output.txt", "w") as f:
    f.write("Biomni: Analyze Thrombus Histology" + NL)
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
        biomni_function: "analyze_thrombus_histology"
    END_VERSIONS
    """
}

workflow ANALYZE_THROMBUS_HISTOLOGY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_THROMBUS_HISTOLOGY(ch_input)

    emit:
    results = ANALYZE_THROMBUS_HISTOLOGY.out.results
    output = ANALYZE_THROMBUS_HISTOLOGY.out.output
    versions = ANALYZE_THROMBUS_HISTOLOGY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_THROMBUS_HISTOLOGY_WORKFLOW(ch_input)

    ANALYZE_THROMBUS_HISTOLOGY_WORKFLOW.out.output.view { "Output: $it" }
}
