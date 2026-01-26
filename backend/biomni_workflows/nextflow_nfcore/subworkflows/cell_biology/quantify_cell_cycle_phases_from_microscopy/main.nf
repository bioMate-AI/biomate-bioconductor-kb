#!/usr/bin/env nextflow
/*
 * cell_biology/quantify_cell_cycle_phases_from_microscopy
 * Quantify the percentage of cells in each cell cycle phase using Calcofluor white stained microscopy images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.image_paths = null
params.output_dir = './results'

process QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("quantify_cell_cycle_phases_from_microscopy_results.json"), emit: results
    tuple val(meta), path("quantify_cell_cycle_phases_from_microscopy_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATHS="${params.image_paths?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def quantify_cell_cycle_phases_from_microscopy(image_paths, output_dir="./results"):
    '''Quantify the percentage of cells in each cell cycle phase using Calcofluor white stained microscopy images.

    This function processes microscopy images where cell walls/septa are stained with Calcofluor white,
    segments individual cells, extracts features, and classifies each cell into G1, S, or G2/M phase.

    Parameters
    ----------
    image_paths : list of str
        List of file paths to microscopy images of cells stained with Calcofluor white
    output_dir : str, optional
        Directory to save results (default: './results')

    Returns
    -------
    str
        Research log summarizing the analysis process and results

    '''
    import os

    import numpy as np
    import pandas as pd
    from skimage import filters, io, measure, morphology

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Initialize log
    log = "# Cell Cycle Phase Quantification Analysis Log\\n\\n"
    log += f"Processing {len(image_paths)} microscopy images with Calcofluor white staining.\\n\\n"

    # Initialize data structures to store results
    all_cells = []
    cell_features = []

    # Step 1: Process images and segment cells
    log += "## Image Processing and Cell Segmentation\\n\\n"

    for i, img_path in enumerate(image_paths):
        log += f"Processing image {i + 1}/{len(image_paths)}: {os.path.basename(img_path)}\\n"

        # Load image
        img = io.imread(img_path)

        # Convert to grayscale if needed
        if len(img.shape) > 2:
            img = np.mean(img, axis=2).astype(np.uint8)

        # Preprocessing
        filtered_img = filters.gaussian(img, sigma=1.0)

        # Thresholding to identify cell walls
        threshold = filters.threshold_otsu(filtered_img)
        binary = filtered_img > threshold

        # Clean up binary image
        binary = morphology.remove_small_objects(binary, min_size=30)
        binary = morphology.binary_closing(binary)

        # Segment cells
        labeled_cells = measure.label(binary)
        cell_props = measure.regionprops(labeled_cells, intensity_image=img)

        log += f"  - Found {len(cell_props)} cells\\n"
        all_cells.extend(cell_props)

        # Extract features for each cell
        for cell in cell_props:
            # Basic morphological features
            area = cell.area
            perimeter = cell.perimeter
            eccentricity = cell.eccentricity
            mean_intensity = cell.mean_intensity

            # Cell shape features
            circularity = (4 * np.pi * area) / (perimeter**2) if perimeter > 0 else 0

            # Check for septation (indicative of S or G2/M phase)
            # Calcofluor white stains the septum more intensely
            has_septum = False
            if area > 50:  # Only check larger cells
                intensity_profile = cell.intensity_image[cell.intensity_image > 0]
                if intensity_profile.size > 0:
                    intensity_std = np.std(intensity_profile)
                    intensity_max = np.max(intensity_profile)
                    # High standard deviation and max intensity suggests septum presence
                    has_septum = intensity_std > 0.2 * np.mean(intensity_profile) and intensity_max > 1.5 * np.mean(
                        intensity_profile
                    )

            # Store features
            cell_features.append(
                [
                    area,
                    perimeter,
                    eccentricity,
                    mean_intensity,
                    circularity,
                    has_septum,
                    i,  # include image index
                ]
            )

    log += f"\\nTotal cells detected across all images: {len(all_cells)}\\n\\n"

    # Step 2: Feature engineering and classification
    log += "## Cell Cycle Phase Classification\\n\\n"

    # Convert to numpy array for easier processing
    X = np.array(cell_features)

    # Simple rule-based classification
    # This is a simplified approach - in practice, you would train a classifier on labeled data
    # G1: Smaller cells, no septum
    # S: Medium-sized cells, early septum formation
    # G2/M: Larger cells, clear septum, often elongated

    # Define classification rules based on features
    phases = []
    for i in range(X.shape[0]):
        area = X[i, 0]
        perimeter = X[i, 1]
        eccentricity = X[i, 2]
        has_septum = X[i, 5]

        if has_septum and area > np.median(X[:, 0]) * 1.2:
            # Larger cells with septum are likely in G2/M
            phases.append("G2/M")
        elif has_septum or (area > np.median(X[:, 0]) and eccentricity > 0.5):
            # Cells with septum or larger elongated cells are likely in S
            phases.append("S")
        else:
            # Smaller cells without septum are likely in G1
            phases.append("G1")

    # Calculate percentages
    unique_phases, counts = np.unique(phases, return_counts=True)
    percentages = (counts / len(phases)) * 100

    # Create results table
    results_df = pd.DataFrame({"Phase": unique_phases, "Count": counts, "Percentage": percentages})

    # Save results
    results_path = os.path.join(output_dir, "cell_cycle_phases.csv")
    results_df.to_csv(results_path, index=False)

    # Log results
    log += "### Cell Cycle Phase Distribution\\n\\n"
    for phase, count, percentage in zip(unique_phases, counts, percentages, strict=False):
        log += f"- {phase}: {count} cells ({percentage:.2f}%)\\n"

    log += f"\\nResults saved to: {results_path}\\n"
    log += "\\nNote: This analysis uses simplified morphological features for classification. "
    log += (
        "For more accurate results, a supervised machine learning approach with labeled training data is recommended.\\n"
    )

    return log

# Execute the function
try:
    result = quantify_cell_cycle_phases_from_microscopy(
        image_paths=auto_convert(os.environ.get("PARAM_IMAGE_PATHS", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
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
    "function": "quantify_cell_cycle_phases_from_microscopy",
    "domain": "cell_biology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("quantify_cell_cycle_phases_from_microscopy_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("quantify_cell_cycle_phases_from_microscopy_output.txt", "w") as f:
    f.write("Biomni: Quantify Cell Cycle Phases From Microscopy" + NL)
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
        biomni_function: "quantify_cell_cycle_phases_from_microscopy"
    END_VERSIONS
    """
}

workflow QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY(ch_input)

    emit:
    results = QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY.out.results
    output = QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY.out.output
    versions = QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY_WORKFLOW(ch_input)

    QUANTIFY_CELL_CYCLE_PHASES_FROM_MICROSCOPY_WORKFLOW.out.output.view { "Output: $it" }
}
