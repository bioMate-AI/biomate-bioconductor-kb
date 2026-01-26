#!/usr/bin/env nextflow
/*
 * bioengineering/analyze_myofiber_morphology
 * Quantifies morphological properties of myofibers in microscopy images of tissue sections.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_path = null
params.nuclei_channel = '2'
params.myofiber_channel = '1'
params.threshold_method = 'otsu'
params.output_dir = './'

process ANALYZE_MYOFIBER_MORPHOLOGY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_myofiber_morphology_results.json"), emit: results
    tuple val(meta), path("analyze_myofiber_morphology_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUCLEI_CHANNEL="${params.nuclei_channel?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MYOFIBER_CHANNEL="${params.myofiber_channel?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD_METHOD="${params.threshold_method?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def analyze_myofiber_morphology(
    image_path,
    nuclei_channel=2,
    myofiber_channel=1,
    threshold_method="otsu",
    output_dir="./",
):
    '''Quantifies morphological properties of myofibers in microscopy images of tissue sections.

    Parameters
    ----------
    image_path : str
        Path to the microscopy image file (typically a multichannel image with nuclei and myofiber staining)
    nuclei_channel : int, default=2
        Channel index containing nuclei staining (DAPI, Hoechst, etc.)
    myofiber_channel : int, default=1
        Channel index containing myofiber staining (α-Actinin, etc.)
    threshold_method : str, default='otsu'
        Method for thresholding ('otsu', 'adaptive', or 'manual')
    output_dir : str, default='./'
        Directory to save output files

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import os
    from datetime import datetime

    import numpy as np
    import pandas as pd
    from skimage import exposure, filters, io, measure, morphology
    from skimage.color import label2rgb

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Load the image
    image = io.imread(image_path)

    # Extract channels (assuming multichannel image)
    if len(image.shape) > 2:
        if len(image.shape) == 3:
            # RGB image
            nuclei_img = image[:, :, nuclei_channel] if nuclei_channel < image.shape[2] else image[:, :, 0]
            myofiber_img = image[:, :, myofiber_channel] if myofiber_channel < image.shape[2] else image[:, :, 1]
        else:
            # Multichannel image (e.g., from confocal)
            nuclei_img = image[nuclei_channel, :, :] if nuclei_channel < image.shape[0] else image[0, :, :]
            myofiber_img = image[myofiber_channel, :, :] if myofiber_channel < image.shape[0] else image[1, :, :]
    else:
        # Single channel image - can't separate nuclei and myofibers
        return "Error: Input image must be multichannel to separate nuclei and myofibers"

    # Enhance contrast
    nuclei_img = exposure.equalize_adapthist(nuclei_img)
    myofiber_img = exposure.equalize_adapthist(myofiber_img)

    # Segment nuclei
    if threshold_method == "otsu":
        nuclei_thresh = filters.threshold_otsu(nuclei_img)
    elif threshold_method == "adaptive":
        nuclei_thresh = filters.threshold_local(nuclei_img, block_size=35)
    else:  # manual
        nuclei_thresh = np.mean(nuclei_img) * 1.5

    nuclei_binary = nuclei_img > nuclei_thresh
    nuclei_binary = morphology.remove_small_objects(nuclei_binary, min_size=30)
    nuclei_binary = morphology.binary_closing(nuclei_binary)

    # Label nuclei
    nuclei_labels = measure.label(nuclei_binary)
    nuclei_props = measure.regionprops(nuclei_labels)

    # Segment myofibers
    if threshold_method == "otsu":
        myofiber_thresh = filters.threshold_otsu(myofiber_img)
    elif threshold_method == "adaptive":
        myofiber_thresh = filters.threshold_local(myofiber_img, block_size=101)
    else:  # manual
        myofiber_thresh = np.mean(myofiber_img) * 1.2

    myofiber_binary = myofiber_img > myofiber_thresh
    myofiber_binary = morphology.remove_small_objects(myofiber_binary, min_size=500)
    myofiber_binary = morphology.binary_closing(myofiber_binary, morphology.disk(3))

    # Label myofibers
    myofiber_labels = measure.label(myofiber_binary)
    myofiber_props = measure.regionprops(myofiber_labels)

    # Count nuclei inside myofibers
    nuclei_inside = 0
    nuclei_total = len(nuclei_props)

    for nucleus in nuclei_props:
        y, x = nucleus.centroid
        y, x = int(y), int(x)
        if myofiber_binary[y, x]:
            nuclei_inside += 1

    percent_inside = nuclei_inside / nuclei_total * 100 if nuclei_total > 0 else 0

    # Calculate myofiber morphological properties
    myofiber_data = []
    for fiber in myofiber_props:
        myofiber_data.append(
            {
                "Area": fiber.area,
                "Perimeter": fiber.perimeter,
                "Eccentricity": fiber.eccentricity,
                "Solidity": fiber.solidity,
                "Orientation": fiber.orientation,
            }
        )

    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    results_file = f"{output_dir}/myofiber_analysis_{timestamp}.csv"

    if myofiber_data:
        df = pd.DataFrame(myofiber_data)
        df.to_csv(results_file, index=False)

        # Calculate summary statistics
        mean_area = df["Area"].mean()
        mean_perimeter = df["Perimeter"].mean()
        mean_eccentricity = df["Eccentricity"].mean()
    else:
        mean_area = mean_perimeter = mean_eccentricity = 0

    # Save labeled image
    labeled_image = label2rgb(myofiber_labels, image=myofiber_img)
    labeled_image_path = f"{output_dir}/labeled_myofibers_{timestamp}.png"
    io.imsave(labeled_image_path, (labeled_image * 255).astype(np.uint8))

    # Create research log
    log = f'''
MYOFIBER MORPHOLOGICAL ANALYSIS REPORT
======================================
Date: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
Image: {image_path}

ANALYSIS STEPS:
1. Loaded multichannel microscopy image
2. Extracted nuclei (channel {nuclei_channel}) and myofiber (channel {myofiber_channel}) signals
3. Enhanced contrast using adaptive histogram equalization
4. Segmented nuclei using {threshold_method} thresholding
5. Segmented myofibers using {threshold_method} thresholding
6. Performed morphological operations to refine segmentation
7. Identified and measured individual myofibers and nuclei

RESULTS:
- Total myofibers detected: {len(myofiber_props)}
- Total nuclei detected: {nuclei_total}
- Nuclei inside myofibers: {nuclei_inside} ({percent_inside:.2f}%)
- Mean myofiber area: {mean_area:.2f} pixels
- Mean myofiber perimeter: {mean_perimeter:.2f} pixels
- Mean myofiber eccentricity: {mean_eccentricity:.2f}

FILES GENERATED:
- Morphological measurements: {results_file}
- Labeled myofiber image: {labeled_image_path}
'''

    return log

# Execute the function
try:
    result = analyze_myofiber_morphology(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        nuclei_channel=auto_convert(os.environ.get("PARAM_NUCLEI_CHANNEL", "2")),
        myofiber_channel=auto_convert(os.environ.get("PARAM_MYOFIBER_CHANNEL", "1")),
        threshold_method=auto_convert(os.environ.get("PARAM_THRESHOLD_METHOD", "otsu")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./")),
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
    "function": "analyze_myofiber_morphology",
    "domain": "bioengineering",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_myofiber_morphology_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_myofiber_morphology_output.txt", "w") as f:
    f.write("Biomni: Analyze Myofiber Morphology" + NL)
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
        biomni_function: "analyze_myofiber_morphology"
    END_VERSIONS
    """
}

workflow ANALYZE_MYOFIBER_MORPHOLOGY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_MYOFIBER_MORPHOLOGY(ch_input)

    emit:
    results = ANALYZE_MYOFIBER_MORPHOLOGY.out.results
    output = ANALYZE_MYOFIBER_MORPHOLOGY.out.output
    versions = ANALYZE_MYOFIBER_MORPHOLOGY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_MYOFIBER_MORPHOLOGY_WORKFLOW(ch_input)

    ANALYZE_MYOFIBER_MORPHOLOGY_WORKFLOW.out.output.view { "Output: $it" }
}
