#!/usr/bin/env nextflow
/*
 * pathology/segment_and_quantify_cells_in_multiplexed_images
 * Segment cells and quantify protein expression levels from multichannel tissue images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.markers_list = null
params.nuclear_channel_index = '0'
params.output_dir = './output'

process SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("segment_and_quantify_cells_in_multiplexed_images_results.json"), emit: results
    tuple val(meta), path("segment_and_quantify_cells_in_multiplexed_images_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MARKERS_LIST="${params.markers_list?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUCLEAR_CHANNEL_INDEX="${params.nuclear_channel_index?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def segment_and_quantify_cells_in_multiplexed_images(
    image_path, markers_list, nuclear_channel_index=0, output_dir="./output"
):
    '''Segment cells and quantify protein expression levels from multichannel tissue images.

    Parameters
    ----------
    image_path : str
        Path to the multichannel image file (tiff stack or similar format)
    markers_list : list of str
        List of marker names corresponding to each channel in the image
    nuclear_channel_index : int, optional
        Index of the nuclear marker channel (default: 0, typically DAPI)
    output_dir : str, optional
        Directory to save output files (default: "./output")

    Returns
    -------
    str
        Research log summarizing the steps performed and output file locations

    '''
    import os
    from datetime import datetime

    import numpy as np
    import pandas as pd
    from scipy import ndimage  # Import ndimage for distance transform
    from skimage import filters, io, measure, morphology, segmentation

    # Initialize research log
    log = []
    log.append(
        f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Starting cell segmentation and protein quantification"
    )

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)
        log.append(f"Created output directory: {output_dir}")

    # Load the multichannel image
    try:
        log.append(f"Loading multichannel image from {image_path}")
        image = io.imread(image_path)
        log.append(f"Image loaded successfully. Shape: {image.shape}")

        # Validate image dimensions
        if len(image.shape) < 3:
            return (
                "Error: Image should be multichannel with shape (channels, height, width) or (height, width, channels)"
            )

        # Determine image format
        if image.shape[0] == len(markers_list):
            # Format is (channels, height, width)
            num_channels, height, width = image.shape
            # Extract nuclear channel
            nuclear_channel = image[nuclear_channel_index]
        elif image.shape[-1] == len(markers_list):
            # Format is (height, width, channels)
            height, width, num_channels = image.shape
            # Extract nuclear channel
            nuclear_channel = image[:, :, nuclear_channel_index]
        else:
            return f"Error: Number of channels in image ({image.shape}) doesn't match markers list length ({len(markers_list)})"

        log.append(f"Processing image with {num_channels} channels, dimensions: {height}x{width}")

    except Exception as e:
        return f"Error loading image: {str(e)}"

    # Segment nuclei
    log.append("Performing nuclear segmentation")
    # Apply threshold to nuclear channel
    threshold = filters.threshold_otsu(nuclear_channel)
    binary_nuclei = nuclear_channel > threshold

    # Clean up binary image
    binary_nuclei = morphology.remove_small_objects(binary_nuclei, min_size=50)
    binary_nuclei = morphology.binary_closing(binary_nuclei, morphology.disk(2))

    # Label nuclei
    labeled_nuclei = measure.label(binary_nuclei)
    log.append(f"Identified {np.max(labeled_nuclei)} potential nuclei")

    # Create cell masks by expanding nuclei
    log.append("Expanding nuclear masks to approximate cell boundaries")
    cell_masks = segmentation.watershed(
        -ndimage.distance_transform_edt(~binary_nuclei),  # Use ndimage for distance transform
        labeled_nuclei,
        mask=morphology.binary_dilation(binary_nuclei, morphology.disk(10)),
    )

    # Get region properties for nuclei
    regions = measure.regionprops(cell_masks)
    log.append(f"Segmented {len(regions)} cells")

    # Create a dataframe to store cell features
    log.append("Extracting features and quantifying marker intensities")
    cell_data = []

    for i, region in enumerate(regions):
        cell_features = {
            "cell_id": i + 1,
            "centroid_y": region.centroid[0],
            "centroid_x": region.centroid[1],
            "area": region.area,
        }

        # Extract intensity for each marker
        for channel_idx, marker_name in enumerate(markers_list):
            if image.shape[0] == len(markers_list):
                # Format is (channels, height, width)
                marker_image = image[channel_idx]
            else:
                # Format is (height, width, channels)
                marker_image = image[:, :, channel_idx]

            # Create mask for current cell
            cell_mask = cell_masks == region.label

            # Calculate mean intensity within the cell mask
            mean_intensity = np.mean(marker_image[cell_mask])
            cell_features[f"{marker_name}_mean_intensity"] = mean_intensity

        cell_data.append(cell_features)

    # Create dataframe
    cell_df = pd.DataFrame(cell_data)

    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = os.path.join(output_dir, f"cell_features_{timestamp}.csv")
    cell_df.to_csv(results_file, index=False)
    log.append(f"Saved spatial feature table to {results_file}")

    # Save segmentation mask for visualization
    mask_file = os.path.join(output_dir, f"cell_segmentation_mask_{timestamp}.tiff")
    io.imsave(mask_file, cell_masks.astype(np.uint16))
    log.append(f"Saved cell segmentation mask to {mask_file}")

    # Summarize results
    log.append(f"Analysis complete. Processed {num_channels} markers across {len(regions)} cells.")
    log.append("Output files:")
    log.append(f"  - Spatial feature table: {results_file}")
    log.append(f"  - Cell segmentation mask: {mask_file}")

    return "\\n".join(log)

# Execute the function
try:
    result = segment_and_quantify_cells_in_multiplexed_images(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        markers_list=auto_convert(os.environ.get("PARAM_MARKERS_LIST", "")),
        nuclear_channel_index=auto_convert(os.environ.get("PARAM_NUCLEAR_CHANNEL_INDEX", "0")),
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
    "function": "segment_and_quantify_cells_in_multiplexed_images",
    "domain": "pathology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("segment_and_quantify_cells_in_multiplexed_images_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("segment_and_quantify_cells_in_multiplexed_images_output.txt", "w") as f:
    f.write("Biomni: Segment And Quantify Cells In Multiplexed Images" + NL)
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
        biomni_function: "segment_and_quantify_cells_in_multiplexed_images"
    END_VERSIONS
    """
}

workflow SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES(ch_input)

    emit:
    results = SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES.out.results
    output = SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES.out.output
    versions = SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES_WORKFLOW(ch_input)

    SEGMENT_AND_QUANTIFY_CELLS_IN_MULTIPLEXED_IMAGES_WORKFLOW.out.output.view { "Output: $it" }
}
