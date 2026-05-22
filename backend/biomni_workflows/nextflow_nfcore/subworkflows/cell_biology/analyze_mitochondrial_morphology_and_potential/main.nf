#!/usr/bin/env nextflow
/*
 * cell_biology/analyze_mitochondrial_morphology_and_potential
 * Quantifies metrics of mitochondrial morphology and membrane potential from fluorescence microscopy images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo mode: use 'demo' to generate synthetic test images
params.morphology_image_path = 'demo'
params.potential_image_path = 'demo'
params.output_dir = './output'

process ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_mitochondrial_morphology_and_potential_results.json"), emit: results
    tuple val(meta), path("analyze_mitochondrial_morphology_and_potential_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_MORPHOLOGY_IMAGE_PATH="${params.morphology_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_POTENTIAL_IMAGE_PATH="${params.potential_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_mitochondrial_morphology_and_potential(morphology_image_path, potential_image_path, output_dir="./output"):
    '''Quantifies metrics of mitochondrial morphology and membrane potential from fluorescence microscopy images.

    Parameters
    ----------
    morphology_image_path : str
        Path to the fluorescence microscopy image showing mitochondrial morphology (e.g., MTS-GFP)
        Use 'demo' for synthetic test data.
    potential_image_path : str
        Path to the fluorescence microscopy image showing mitochondrial membrane potential (e.g., TMRE staining)
        Use 'demo' for synthetic test data.
    output_dir : str, optional
        Directory to save output files, default is "./output"

    Returns
    -------
    str
        A research log summarizing the analysis steps and results

    '''
    import datetime
    import os

    import cv2
    import numpy as np
    from scipy import ndimage
    from skimage import filters, io, morphology, util

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    log = []
    log.append(f"Mitochondrial Analysis - {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append("=" * 50)

    # Generate synthetic test images if demo mode
    if morphology_image_path == 'demo' or potential_image_path == 'demo':
        log.append("DEMO MODE: Generating synthetic mitochondrial images for testing")
        np.random.seed(42)

        # Create synthetic morphology image with mitochondrial-like structures
        morph_img = np.zeros((256, 256), dtype=np.float32)
        # Add some tubular structures (simplified mitochondria)
        for _ in range(15):
            x_start, y_start = np.random.randint(20, 200, 2)
            length = np.random.randint(20, 60)
            angle = np.random.uniform(0, 2*np.pi)
            for t in range(length):
                x = int(x_start + t * np.cos(angle))
                y = int(y_start + t * np.sin(angle))
                if 0 <= x < 256 and 0 <= y < 256:
                    morph_img[max(0,y-2):min(256,y+3), max(0,x-2):min(256,x+3)] = np.random.uniform(0.6, 1.0)

        # Add noise
        morph_img += np.random.normal(0, 0.05, morph_img.shape)
        morph_img = np.clip(morph_img, 0, 1)

        # Create synthetic potential image (similar pattern but with intensity variation)
        pot_img = morph_img * np.random.uniform(0.5, 1.0, morph_img.shape)
        pot_img = np.clip(pot_img, 0, 1)

        log.append(f"Generated synthetic morphology image: shape {morph_img.shape}")
        log.append(f"Generated synthetic potential image: shape {pot_img.shape}")
    else:
        # Load images
        try:
            morph_img = io.imread(morphology_image_path)
            pot_img = io.imread(potential_image_path)

            log.append(f"Successfully loaded morphology image: {morphology_image_path}")
            log.append(f"Successfully loaded potential image: {potential_image_path}")
            log.append(f"Morphology image shape: {morph_img.shape}")
            log.append(f"Potential image shape: {pot_img.shape}")
        except Exception as e:
            return f"Error loading images: {str(e)}"

    # Convert to grayscale if needed
    if len(morph_img.shape) > 2:
        morph_img = cv2.cvtColor(morph_img, cv2.COLOR_RGB2GRAY)
        log.append("Converted morphology image to grayscale")
    if len(pot_img.shape) > 2:
        pot_img = cv2.cvtColor(pot_img, cv2.COLOR_RGB2GRAY)
        log.append("Converted potential image to grayscale")

    # Normalize images
    morph_img = util.img_as_float(morph_img)
    pot_img = util.img_as_float(pot_img)

    log.append("\\nMorphology Analysis:")
    log.append("-" * 30)

    # Denoise morphology image
    morph_img_denoised = filters.gaussian(morph_img, sigma=1.0)

    # Threshold to segment mitochondria
    threshold_value = filters.threshold_otsu(morph_img_denoised)
    binary_img = morph_img_denoised > threshold_value

    # Remove small objects
    binary_img = morphology.remove_small_objects(binary_img, min_size=20)

    # Save binary image
    binary_path = os.path.join(output_dir, "binary_mitochondria.png")
    io.imsave(binary_path, util.img_as_ubyte(binary_img))
    log.append(f"Binary segmentation saved to: {binary_path}")

    # Skeletonize for network analysis
    skeleton = morphology.skeletonize(binary_img)
    skeleton_path = os.path.join(output_dir, "skeleton.png")
    io.imsave(skeleton_path, util.img_as_ubyte(skeleton))
    log.append(f"Skeleton image saved to: {skeleton_path}")

    # Calculate morphology metrics
    # 1. Count branches and junctions
    # Label the skeleton
    labeled_skeleton, num_branches = ndimage.label(skeleton)

    # Find branch points (pixels with more than 2 neighbors)
    kernel = np.ones((3, 3), dtype=np.uint8)
    kernel[1, 1] = 0  # Don't count the center pixel
    neighbor_count = ndimage.convolve(skeleton.astype(np.uint8), kernel)
    junction_points = (neighbor_count > 2) & skeleton
    num_junctions = np.sum(junction_points)

    # 2. Calculate fragmentation metrics
    labeled_objects, num_objects = ndimage.label(binary_img)
    object_sizes = ndimage.sum(binary_img, labeled_objects, range(1, num_objects + 1))
    mean_size = np.mean(object_sizes) if len(object_sizes) > 0 else 0

    # Calculate network connectivity (ratio of junctions to branches)
    connectivity = num_junctions / num_branches if num_branches > 0 else 0

    # Calculate fragmentation index (inverse of mean object size, normalized)
    fragmentation = 1 / (mean_size / np.max(object_sizes)) if mean_size > 0 and np.max(object_sizes) > 0 else 0

    log.append(f"Number of mitochondrial fragments: {num_objects}")
    log.append(f"Number of branches: {num_branches}")
    log.append(f"Number of junction points: {num_junctions}")
    log.append(f"Network connectivity index: {connectivity:.4f}")
    log.append(f"Fragmentation index: {fragmentation:.4f}")
    log.append(f"Mean fragment size: {mean_size:.2f} pixels")

    # Membrane potential analysis
    log.append("\\nMembrane Potential Analysis:")
    log.append("-" * 30)

    # Create mask from morphology image to analyze only mitochondrial regions
    mito_mask = binary_img

    # Calculate potential metrics within mitochondrial regions
    pot_intensity_raw = np.mean(pot_img)
    pot_intensity_in_mito = np.mean(pot_img[mito_mask]) if np.sum(mito_mask) > 0 else 0

    # Calculate potential heterogeneity (standard deviation of intensity)
    pot_heterogeneity = np.std(pot_img[mito_mask]) if np.sum(mito_mask) > 0 else 0

    # Calculate potential distribution
    if np.sum(mito_mask) > 0:
        percentiles = [10, 25, 50, 75, 90]
        pot_percentiles = np.percentile(pot_img[mito_mask], percentiles)
        percentile_str = ", ".join([f"{p}th: {v:.4f}" for p, v in zip(percentiles, pot_percentiles, strict=False)])
    else:
        percentile_str = "No mitochondrial regions detected"

    log.append(f"Overall mean TMRE intensity: {pot_intensity_raw:.4f}")
    log.append(f"Mean TMRE intensity in mitochondria: {pot_intensity_in_mito:.4f}")
    log.append(f"TMRE intensity heterogeneity (std): {pot_heterogeneity:.4f}")
    log.append(f"TMRE intensity percentiles: {percentile_str}")

    # Create a combined results image
    # Overlay potential intensity on morphology
    overlay = np.zeros((morph_img.shape[0], morph_img.shape[1], 3), dtype=np.float32)
    overlay[..., 0] = morph_img  # Red channel - morphology
    overlay[..., 2] = pot_img  # Blue channel - potential
    overlay = np.clip(overlay, 0, 1)

    overlay_path = os.path.join(output_dir, "morphology_potential_overlay.png")
    io.imsave(overlay_path, util.img_as_ubyte(overlay))
    log.append(f"Overlay image saved to: {overlay_path}")

    # Save quantitative results to CSV
    import csv

    results_path = os.path.join(output_dir, "mitochondrial_analysis_results.csv")
    with open(results_path, "w", newline="") as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["Metric", "Value"])
        writer.writerow(["Number of fragments", num_objects])
        writer.writerow(["Number of branches", num_branches])
        writer.writerow(["Number of junctions", num_junctions])
        writer.writerow(["Network connectivity", connectivity])
        writer.writerow(["Fragmentation index", fragmentation])
        writer.writerow(["Mean fragment size", mean_size])
        writer.writerow(["Mean TMRE intensity", pot_intensity_in_mito])
        writer.writerow(["TMRE heterogeneity", pot_heterogeneity])

    log.append(f"Quantitative results saved to: {results_path}")
    log.append("\\nAnalysis complete.")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_mitochondrial_morphology_and_potential(
        morphology_image_path=auto_convert(os.environ.get("PARAM_MORPHOLOGY_IMAGE_PATH", "")),
        potential_image_path=auto_convert(os.environ.get("PARAM_POTENTIAL_IMAGE_PATH", "")),
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
    "function": "analyze_mitochondrial_morphology_and_potential",
    "domain": "cell_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_mitochondrial_morphology_and_potential_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_mitochondrial_morphology_and_potential_output.txt", "w") as f:
    f.write("Biomni: Analyze Mitochondrial Morphology And Potential" + NL)
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
        biomni_function: "analyze_mitochondrial_morphology_and_potential"
    END_VERSIONS
    """
}

workflow ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL(ch_input)

    emit:
    results = ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL.out.results
    output = ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL.out.output
    versions = ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL_WORKFLOW(ch_input)

    ANALYZE_MITOCHONDRIAL_MORPHOLOGY_AND_POTENTIAL_WORKFLOW.out.output.view { "Output: $it" }
}
