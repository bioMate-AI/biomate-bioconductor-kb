#!/usr/bin/env nextflow
/*
 * microbiology/segment_cells_with_deep_learning
 * Perform cell segmentation on fluorescence microscopy images using deep learning.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.model_type = 'bact_fluor_omni'
params.diameter = null
params.save_dir = 'segmentation_results'

process SEGMENT_CELLS_WITH_DEEP_LEARNING {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("segment_cells_with_deep_learning_results.json"), emit: results
    tuple val(meta), path("segment_cells_with_deep_learning_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DIAMETER="${params.diameter?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAVE_DIR="${params.save_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def segment_cells_with_deep_learning(
    image_path,
    model_type="bact_fluor_omni",
    diameter=None,
    save_dir="segmentation_results",
):
    '''Perform cell segmentation on fluorescence microscopy images using deep learning.

    Uses pre-trained models from the Cellpose/Omnipose library to identify and segment
    individual cells in fluorescence microscopy images.

    Parameters
    ----------
    image_path : str
        Path to the fluorescence microscopy image file
    model_type : str, optional
        Name of the pre-trained model to use (default: 'bact_fluor_omni')
        Options include: 'bact_fluor_omni', 'cyto', 'nuclei', etc.
    diameter : float, optional
        Expected diameter of cells in pixels. If None, diameter is automatically estimated.
    save_dir : str, optional
        Directory to save segmentation results (default: 'segmentation_results')

    Returns
    -------
    str
        Research log detailing the segmentation process and results

    '''
    import os
    from datetime import datetime

    import matplotlib.pyplot as plt
    import numpy as np
    from cellpose import models
    from skimage import io

    # Create output directory if it doesn't exist
    os.makedirs(save_dir, exist_ok=True)

    # Start research log
    log = "# Cell Segmentation Research Log\\n"
    log += f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\\n\\n"

    # Load the image
    log += "## Loading Image\\n"
    log += f"Image path: {image_path}\\n"

    try:
        img = io.imread(image_path)
        log += f"Image loaded successfully. Shape: {img.shape}\\n\\n"
    except Exception as e:
        log += f"Error loading image: {str(e)}\\n"
        return log

    # Prepare image for model
    if len(img.shape) > 2 and img.shape[2] > 1:
        # If RGB, convert to grayscale for single channel
        img_model = img[:, :, 0] if img.shape[2] >= 3 else img
        log += "Using first channel of multi-channel image for segmentation.\\n\\n"
    else:
        img_model = img

    # Initialize model
    log += "## Initializing Model\\n"
    log += f"Model type: {model_type}\\n"

    try:
        model = models.CellposeModel(model_type=model_type, gpu=False)
        log += "Model initialized successfully.\\n\\n"
    except Exception as e:
        log += f"Error initializing model: {str(e)}\\n"
        return log

    # Run segmentation
    log += "## Performing Segmentation\\n"

    try:
        channels = [0, 0]  # First channel for cell detection, no second channel

        log += "Estimated cell diameter: "
        if diameter is None:
            log += "Auto-estimating\\n"
        else:
            log += f"{diameter} pixels\\n"

        # Adjust the unpacking based on the expected return values
        results = model.eval(
            img_model,
            diameter=diameter,
            channels=channels,
            flow_threshold=0.4,
            do_3D=False,
        )

        # Check the number of returned values
        if len(results) == 3:
            masks, flows, diams = results  # Adjusted for 3 return values
            styles = None  # If styles are not returned, set to None
        elif len(results) == 4:
            masks, flows, styles, diams = results  # Original unpacking
        else:
            raise ValueError(f"Unexpected number of return values from model.eval(): {len(results)}")

        if diameter is None:
            log += f"Auto-estimated cell diameter: {diams[0]:.2f} pixels\\n"

        cell_count = len(np.unique(masks)) - 1  # Subtract 1 for background
        log += f"Segmentation complete. Detected {cell_count} cells.\\n\\n"
    except Exception as e:
        log += f"Error during segmentation: {str(e)}\\n"
        return log

    # Save results
    log += "## Saving Results\\n"

    # Save mask image
    mask_file = os.path.join(save_dir, f"masks_{os.path.basename(image_path)}")
    io.imsave(mask_file, masks.astype(np.uint16))
    log += f"Cell masks saved to: {mask_file}\\n"

    # Create and save outlines image
    plt.figure(figsize=(10, 8))
    plt.imshow(img_model, cmap="gray")

    # Generate outlines from masks
    from skimage.segmentation import find_boundaries

    find_boundaries(masks, mode="outer")
    plt.contour(masks, levels=np.unique(masks), colors="r", linewidths=0.5)

    outline_file = os.path.join(save_dir, f"outlines_{os.path.basename(image_path)}")
    plt.axis("off")
    plt.savefig(outline_file, bbox_inches="tight", pad_inches=0)
    plt.close()
    log += f"Cell outlines overlaid on original image saved to: {outline_file}\\n\\n"

    # Final statistics
    log += "## Segmentation Statistics\\n"
    log += f"Total cells detected: {cell_count}\\n"

    # Calculate additional metrics
    if cell_count > 0:
        cell_areas = [np.sum(masks == i) for i in range(1, cell_count + 1)]
        avg_cell_area = np.mean(cell_areas)
        std_cell_area = np.std(cell_areas)
        log += f"Average cell area: {avg_cell_area:.2f} pixels\\n"
        log += f"Standard deviation of cell area: {std_cell_area:.2f} pixels\\n"

    return log

# Execute the function
try:
    result = segment_cells_with_deep_learning(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        model_type=auto_convert(os.environ.get("PARAM_MODEL_TYPE", "bact_fluor_omni")),
        diameter=auto_convert(os.environ.get("PARAM_DIAMETER", "")),
        save_dir=auto_convert(os.environ.get("PARAM_SAVE_DIR", "segmentation_results")),
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
    "function": "segment_cells_with_deep_learning",
    "domain": "microbiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("segment_cells_with_deep_learning_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("segment_cells_with_deep_learning_output.txt", "w") as f:
    f.write("Biomni: Segment Cells With Deep Learning" + NL)
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
        biomni_function: "segment_cells_with_deep_learning"
    END_VERSIONS
    """
}

workflow SEGMENT_CELLS_WITH_DEEP_LEARNING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SEGMENT_CELLS_WITH_DEEP_LEARNING(ch_input)

    emit:
    results = SEGMENT_CELLS_WITH_DEEP_LEARNING.out.results
    output = SEGMENT_CELLS_WITH_DEEP_LEARNING.out.output
    versions = SEGMENT_CELLS_WITH_DEEP_LEARNING.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SEGMENT_CELLS_WITH_DEEP_LEARNING_WORKFLOW(ch_input)

    SEGMENT_CELLS_WITH_DEEP_LEARNING_WORKFLOW.out.output.view { "Output: $it" }
}
