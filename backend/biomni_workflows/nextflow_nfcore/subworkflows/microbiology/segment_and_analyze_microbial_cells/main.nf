#!/usr/bin/env nextflow
/*
 * microbiology/segment_and_analyze_microbial_cells
 * Perform automated cell segmentation and quantify morphological metrics from fluorescence microscopy images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Uses inline-generated mock fluorescence microscopy image
params.image_path = 'mock_microbial_cells.png'
params.output_dir = './output'
params.min_cell_size = '50'

process SEGMENT_AND_ANALYZE_MICROBIAL_CELLS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("segment_and_analyze_microbial_cells_results.json"), emit: results
    tuple val(meta), path("segment_and_analyze_microbial_cells_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIN_CELL_SIZE="${params.min_cell_size?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Generate mock fluorescence microscopy image with microbial cells

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



def segment_and_analyze_microbial_cells(image_path, output_dir="./output", min_cell_size=50):
    '''Perform automated cell segmentation and quantify morphological metrics from fluorescence microscopy images.

    Parameters
    ----------
    image_path : str
        Path to the fluorescence microscopy image file
    output_dir : str, optional
        Directory to save output files (default: './output')
    min_cell_size : int, optional
        Minimum cell size in pixels to filter noise (default: 50)

    Returns
    -------
    str
        Research log summarizing the segmentation process, metrics calculated, and output file paths

    '''
    import os

    import numpy as np
    import pandas as pd
    from scipy import ndimage
    from skimage import color, filters, io, measure, morphology, segmentation

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Step 1: Load and preprocess the image
    image = io.imread(image_path)
    if len(image.shape) > 2:  # Convert to grayscale if RGB
        image = color.rgb2gray(image)

    # Step 2: Enhance contrast and denoise
    image_smooth = filters.gaussian(image, sigma=1)

    # Step 3: Thresholding to separate cells from background
    threshold_value = filters.threshold_otsu(image_smooth)
    binary_mask = image_smooth > threshold_value

    # Step 4: Clean binary mask (remove small objects and fill holes)
    binary_mask = morphology.remove_small_objects(binary_mask, min_size=min_cell_size)
    binary_mask = morphology.binary_closing(binary_mask, morphology.disk(2))
    binary_mask = ndimage.binary_fill_holes(binary_mask)

    # Step 5: Watershed segmentation for separating touching cells
    distance = ndimage.distance_transform_edt(binary_mask)
    local_max = morphology.local_maxima(distance)
    markers = measure.label(local_max)
    segmented_cells = segmentation.watershed(-distance, markers, mask=binary_mask)

    # Step 6: Measure cell properties
    props = measure.regionprops_table(
        segmented_cells,
        intensity_image=image,
        properties=[
            "label",
            "area",
            "perimeter",
            "eccentricity",
            "major_axis_length",
            "minor_axis_length",
            "mean_intensity",
            "max_intensity",
        ],
    )

    # Calculate circularity (4π × area / perimeter²)
    props["circularity"] = 4 * np.pi * props["area"] / (props["perimeter"] ** 2)

    # Step 7: Save results
    # Save segmentation image
    segmentation_filename = os.path.join(output_dir, "segmented_cells.png")
    segmentation_image = color.label2rgb(segmented_cells, image, alpha=0.3, bg_label=0)
    io.imsave(segmentation_filename, (segmentation_image * 255).astype(np.uint8))

    # Save metrics to CSV
    metrics_filename = os.path.join(output_dir, "cell_metrics.csv")
    metrics_df = pd.DataFrame(props)
    metrics_df.to_csv(metrics_filename, index=False)

    # Step 8: Generate summary statistics
    cell_count = len(np.unique(segmented_cells)) - 1  # Subtract background
    avg_cell_area = np.mean(props["area"])
    avg_circularity = np.mean(props["circularity"])

    # Create research log
    log = f'''
Cell Segmentation and Morphology Analysis Research Log:
------------------------------------------------------
Image processed: {image_path}
Segmentation method: Otsu thresholding + Watershed

Results Summary:
- Number of cells detected: {cell_count}
- Average cell area: {avg_cell_area:.2f} pixels²
- Average cell circularity: {avg_circularity:.4f}
- Size range: {np.min(props["area"]):.2f} to {np.max(props["area"]):.2f} pixels²

Cell morphology metrics have been calculated including:
- Area
- Perimeter
- Eccentricity
- Major/minor axis lengths
- Circularity

Output files:
- Segmentation image: {segmentation_filename}
- Detailed metrics: {metrics_filename}
'''

    return log

# Execute the function
try:
    result = segment_and_analyze_microbial_cells(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./output")),
        min_cell_size=auto_convert(os.environ.get("PARAM_MIN_CELL_SIZE", "50")),
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
    "function": "segment_and_analyze_microbial_cells",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("segment_and_analyze_microbial_cells_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("segment_and_analyze_microbial_cells_output.txt", "w") as f:
    f.write("Biomni: Segment And Analyze Microbial Cells" + NL)
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
        biomni_function: "segment_and_analyze_microbial_cells"
    END_VERSIONS
    """
}

workflow SEGMENT_AND_ANALYZE_MICROBIAL_CELLS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SEGMENT_AND_ANALYZE_MICROBIAL_CELLS(ch_input)

    emit:
    results = SEGMENT_AND_ANALYZE_MICROBIAL_CELLS.out.results
    output = SEGMENT_AND_ANALYZE_MICROBIAL_CELLS.out.output
    versions = SEGMENT_AND_ANALYZE_MICROBIAL_CELLS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SEGMENT_AND_ANALYZE_MICROBIAL_CELLS_WORKFLOW(ch_input)

    SEGMENT_AND_ANALYZE_MICROBIAL_CELLS_WORKFLOW.out.output.view { "Output: $it" }
}
