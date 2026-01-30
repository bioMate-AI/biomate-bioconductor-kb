#!/usr/bin/env nextflow
/*
 * immunology/analyze_immunohistochemistry_image
 * Analyzes immunohistochemistry images to quantify protein expression and spatial distribution.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Uses inline-generated mock IHC stained tissue image
params.image_path = 'mock_ihc_image.png'
params.protein_name = 'CD68'
params.output_dir = './ihc_results/'

process ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_immunohistochemistry_image_results.json"), emit: results
    tuple val(meta), path("analyze_immunohistochemistry_image_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PROTEIN_NAME="${params.protein_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Generate mock IHC stained tissue image for testing
    python3 << 'MOCKEOF'
import numpy as np
import cv2

# Create mock IHC stained tissue image (DAB chromogen - brown positive staining)
np.random.seed(42)
# Light pink/purple counterstain background (hematoxylin)
img = np.zeros((512, 512, 3), dtype=np.uint8)
img[:, :] = [220, 200, 230]  # Light purple (BGR)

# Add tissue texture
noise = np.random.normal(0, 8, (512, 512)).astype(np.int16)
for c in range(3):
    img[:, :, c] = np.clip(img[:, :, c].astype(np.int16) + noise, 0, 255).astype(np.uint8)

# Add DAB-positive cells (brown spots - CD68+ macrophages)
for _ in range(80):
    x = np.random.randint(20, 492)
    y = np.random.randint(20, 492)
    radius = np.random.randint(5, 12)
    # Brown color for DAB (BGR)
    color = (30 + np.random.randint(0, 30), 80 + np.random.randint(0, 40), 150 + np.random.randint(0, 50))
    cv2.circle(img, (x, y), radius, color, -1)

# Add some blue nuclei (hematoxylin counterstain)
for _ in range(50):
    x = np.random.randint(20, 492)
    y = np.random.randint(20, 492)
    radius = np.random.randint(3, 6)
    color = (120 + np.random.randint(0, 30), 80 + np.random.randint(0, 30), 100 + np.random.randint(0, 30))
    cv2.circle(img, (x, y), radius, color, -1)

img = cv2.GaussianBlur(img, (3, 3), 1)
cv2.imwrite('mock_ihc_image.png', img)
print("Mock IHC stained tissue image created")
MOCKEOF

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



def analyze_immunohistochemistry_image(image_path, protein_name="Unknown", output_dir="./ihc_results/"):
    '''Analyzes immunohistochemistry images to quantify protein expression and spatial distribution.

    Parameters
    ----------
    image_path : str
        Path to the microscopy image of tissue section stained with antibodies
    protein_name : str, optional
        Name of the protein being analyzed (default: "Unknown")
    output_dir : str, optional
        Directory to save output files (default: "./ihc_results/")

    Returns
    -------
    str
        Research log summarizing the analysis steps, results, and saved file locations

    '''
    import os
    from datetime import datetime

    import numpy as np
    from skimage import exposure, filters, io, measure, morphology
    from skimage.color import rgb2gray

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_filename = f"{protein_name}_{timestamp}"

    # Load the image
    try:
        img = io.imread(image_path)
        log = f"Loaded image from {image_path}\\n"
    except Exception as e:
        return f"Error loading image: {str(e)}"

    # Convert to grayscale if RGB
    if len(img.shape) == 3 and img.shape[2] >= 3:
        gray_img = rgb2gray(img)
        log += "Converted RGB image to grayscale for analysis\\n"
    else:
        gray_img = img
        log += "Image already in grayscale format\\n"

    # Enhance contrast for better visualization
    p2, p98 = np.percentile(gray_img, (2, 98))
    enhanced_img = exposure.rescale_intensity(gray_img, in_range=(p2, p98))
    log += "Enhanced image contrast for better visualization\\n"

    # Segment cells/tissue using thresholding
    threshold_value = filters.threshold_otsu(enhanced_img)
    binary_mask = enhanced_img > threshold_value

    # Clean up the mask with morphological operations
    binary_mask = morphology.remove_small_objects(binary_mask, min_size=50)
    binary_mask = morphology.remove_small_holes(binary_mask, area_threshold=50)
    log += "Segmented tissue regions using Otsu thresholding and morphological cleanup\\n"

    # Label connected regions
    labeled_mask, num_features = measure.label(binary_mask, return_num=True)
    log += f"Identified {num_features} distinct tissue regions\\n"

    # Quantify protein expression by measuring intensity in segmented regions
    region_props = measure.regionprops(labeled_mask, intensity_image=gray_img)

    # Calculate intensity metrics
    mean_intensities = [prop.mean_intensity for prop in region_props]
    total_intensity = sum(prop.mean_intensity * prop.area for prop in region_props)
    avg_intensity = np.mean(mean_intensities) if mean_intensities else 0

    log += "Protein expression quantification:\\n"
    log += f"- Total intensity: {total_intensity:.2f}\\n"
    log += f"- Average intensity: {avg_intensity:.2f}\\n"
    log += f"- Number of regions analyzed: {len(region_props)}\\n"

    # Analyze spatial distribution
    if region_props:
        # Calculate centroid coordinates for each region
        centroids = [prop.centroid for prop in region_props]

        # Calculate distances between centroids to assess clustering
        from scipy.spatial import distance

        if len(centroids) > 1:
            distances = []
            for i in range(len(centroids)):
                for j in range(i + 1, len(centroids)):
                    distances.append(distance.euclidean(centroids[i], centroids[j]))

            avg_distance = np.mean(distances)
            log += "Spatial distribution analysis:\\n"
            log += f"- Average distance between regions: {avg_distance:.2f} pixels\\n"
            log += f"- Minimum distance between regions: {min(distances):.2f} pixels\\n"
            log += f"- Maximum distance between regions: {max(distances):.2f} pixels\\n"
        else:
            log += "Spatial distribution analysis: Only one region detected\\n"

    # Save results
    segmentation_file = os.path.join(output_dir, f"{base_filename}_segmentation.png")
    io.imsave(segmentation_file, labeled_mask)

    # Create a CSV with region properties
    import csv

    csv_file = os.path.join(output_dir, f"{base_filename}_region_data.csv")
    with open(csv_file, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["Region ID", "Area", "Mean Intensity", "Centroid Y", "Centroid X"])
        for i, prop in enumerate(region_props):
            writer.writerow(
                [
                    i + 1,
                    prop.area,
                    prop.mean_intensity,
                    prop.centroid[0],
                    prop.centroid[1],
                ]
            )

    log += "\\nResults saved:\\n"
    log += f"- Segmentation image: {segmentation_file}\\n"
    log += f"- Region data: {csv_file}\\n"

    return log

# Execute the function
try:
    result = analyze_immunohistochemistry_image(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        protein_name=auto_convert(os.environ.get("PARAM_PROTEIN_NAME", "Unknown")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./ihc_results/")),
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
    "function": "analyze_immunohistochemistry_image",
    "domain": "immunology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_immunohistochemistry_image_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_immunohistochemistry_image_output.txt", "w") as f:
    f.write("Biomni: Analyze Immunohistochemistry Image" + NL)
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
        biomni_function: "analyze_immunohistochemistry_image"
    END_VERSIONS
    """
}

workflow ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE(ch_input)

    emit:
    results = ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE.out.results
    output = ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE.out.output
    versions = ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE_WORKFLOW(ch_input)

    ANALYZE_IMMUNOHISTOCHEMISTRY_IMAGE_WORKFLOW.out.output.view { "Output: $it" }
}
