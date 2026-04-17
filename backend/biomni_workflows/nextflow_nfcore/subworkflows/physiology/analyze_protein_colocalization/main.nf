#!/usr/bin/env nextflow
/*
 * physiology/analyze_protein_colocalization
 * Analyze colocalization between two fluorescently labeled proteins in microscopy images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Uses inline-generated mock fluorescence channel images
params.channel1_path = 'mock_channel1_green.png'
params.channel2_path = 'mock_channel2_red.png'
params.output_dir = './output'
params.threshold_method = 'otsu'

process ANALYZE_PROTEIN_COLOCALIZATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_protein_colocalization_results.json"), emit: results
    tuple val(meta), path("analyze_protein_colocalization_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_CHANNEL1_PATH="${params.channel1_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CHANNEL2_PATH="${params.channel2_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD_METHOD="${params.threshold_method?.toString()?.replace('"', '\\"') ?: 'null'}"

    # Generate mock fluorescence channel images for testing

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



def analyze_protein_colocalization(channel1_path, channel2_path, output_dir="./output", threshold_method="otsu"):
    '''Analyze colocalization between two fluorescently labeled proteins in microscopy images.

    Parameters
    ----------
    channel1_path : str
        Path to the first channel image file (fluorescent protein 1)
    channel2_path : str
        Path to the second channel image file (fluorescent protein 2)
    output_dir : str
        Directory to save output files (default: "./output")
    threshold_method : str
        Method for thresholding images ('otsu', 'li', or 'yen') (default: "otsu")

    Returns
    -------
    str
        Research log summarizing the colocalization analysis results and saved files

    '''
    import os

    import matplotlib.pyplot as plt
    import numpy as np
    from scipy import stats
    from skimage import exposure, filters, io

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Load images
    img1 = io.imread(channel1_path)
    img2 = io.imread(channel2_path)

    # Ensure images are same size
    if img1.shape != img2.shape:
        return "Error: Images must have the same dimensions"

    # Convert to grayscale if RGB
    if len(img1.shape) > 2:
        img1 = img1.mean(axis=2)
    if len(img2.shape) > 2:
        img2 = img2.mean(axis=2)

    # Normalize images to 0-1 range
    img1_norm = exposure.rescale_intensity(img1.astype(float), out_range=(0, 1))
    img2_norm = exposure.rescale_intensity(img2.astype(float), out_range=(0, 1))

    # Apply threshold to segment foreground from background
    if threshold_method == "otsu":
        thresh1 = filters.threshold_otsu(img1_norm)
        thresh2 = filters.threshold_otsu(img2_norm)
    elif threshold_method == "li":
        thresh1 = filters.threshold_li(img1_norm)
        thresh2 = filters.threshold_li(img2_norm)
    elif threshold_method == "yen":
        thresh1 = filters.threshold_yen(img1_norm)
        thresh2 = filters.threshold_yen(img2_norm)
    else:
        thresh1 = filters.threshold_otsu(img1_norm)
        thresh2 = filters.threshold_otsu(img2_norm)

    mask1 = img1_norm > thresh1
    mask2 = img2_norm > thresh2

    # Calculate Pearson's correlation coefficient (whole image)
    pearson_whole = stats.pearsonr(img1_norm.flatten(), img2_norm.flatten())[0]

    # Calculate Pearson's correlation coefficient (above threshold)
    combined_mask = np.logical_or(mask1, mask2)
    if np.sum(combined_mask) > 0:
        pearson_masked = stats.pearsonr(img1_norm[combined_mask].flatten(), img2_norm[combined_mask].flatten())[0]
    else:
        pearson_masked = 0

    # Calculate Mander's Overlap Coefficient (MOC)
    numerator = np.sum(img1_norm * img2_norm)
    denominator = np.sqrt(np.sum(img1_norm**2) * np.sum(img2_norm**2))
    moc = numerator / denominator if denominator > 0 else 0

    # Calculate Mander's Colocalization Coefficients (MCC)
    # M1: Fraction of channel1 overlapping with channel2
    # M2: Fraction of channel2 overlapping with channel1
    m1 = np.sum(img1_norm * mask2) / np.sum(img1_norm) if np.sum(img1_norm) > 0 else 0
    m2 = np.sum(img2_norm * mask1) / np.sum(img2_norm) if np.sum(img2_norm) > 0 else 0

    # Create visualization
    plt.figure(figsize=(10, 8))

    # Plot original images and overlay
    plt.subplot(2, 2, 1)
    plt.imshow(img1_norm, cmap="Greens")
    plt.title("Channel 1")
    plt.axis("off")

    plt.subplot(2, 2, 2)
    plt.imshow(img2_norm, cmap="Reds")
    plt.title("Channel 2")
    plt.axis("off")

    plt.subplot(2, 2, 3)
    overlay = np.zeros((img1_norm.shape[0], img1_norm.shape[1], 3))
    overlay[:, :, 1] = img1_norm  # Green channel
    overlay[:, :, 0] = img2_norm  # Red channel
    plt.imshow(overlay)
    plt.title("Overlay")
    plt.axis("off")

    # Plot scatter plot of pixel intensities
    plt.subplot(2, 2, 4)
    plt.hexbin(img1_norm.flatten(), img2_norm.flatten(), gridsize=50, cmap="viridis", mincnt=1)
    plt.xlabel("Channel 1 Intensity")
    plt.ylabel("Channel 2 Intensity")
    plt.title("Intensity Correlation")

    # Save visualization
    viz_filename = os.path.join(output_dir, "colocalization_visualization.png")
    plt.tight_layout()
    plt.savefig(viz_filename)
    plt.close()

    # Create research log
    log = f'''Colocalization Analysis Research Log:

1. Analyzed images:
   - Channel 1: {channel1_path}
   - Channel 2: {channel2_path}

2. Thresholding method: {threshold_method}
   - Channel 1 threshold: {thresh1:.4f}
   - Channel 2 threshold: {thresh2:.4f}

3. Colocalization metrics:
   - Pearson's correlation coefficient (whole image): {pearson_whole:.4f}
   - Pearson's correlation coefficient (above threshold): {pearson_masked:.4f}
   - Mander's Overlap Coefficient (MOC): {moc:.4f}
   - Mander's Colocalization Coefficient M1: {m1:.4f}
   - Mander's Colocalization Coefficient M2: {m2:.4f}

4. Visualization saved to: {viz_filename}

Interpretation:
- Pearson's coefficient ranges from -1 to 1, with values closer to 1 indicating stronger colocalization
- Mander's coefficients range from 0 to 1, with values closer to 1 indicating higher overlap
- M1 represents the fraction of channel 1 overlapping with channel 2
- M2 represents the fraction of channel 2 overlapping with channel 1
'''

    return log

# Execute the function
try:
    result = analyze_protein_colocalization(
        channel1_path=auto_convert(os.environ.get("PARAM_CHANNEL1_PATH", "")),
        channel2_path=auto_convert(os.environ.get("PARAM_CHANNEL2_PATH", "")),
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
    "function": "analyze_protein_colocalization",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_protein_colocalization_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_protein_colocalization_output.txt", "w") as f:
    f.write("Biomni: Analyze Protein Colocalization" + NL)
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
        biomni_function: "analyze_protein_colocalization"
    END_VERSIONS
    """
}

workflow ANALYZE_PROTEIN_COLOCALIZATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_PROTEIN_COLOCALIZATION(ch_input)

    emit:
    results = ANALYZE_PROTEIN_COLOCALIZATION.out.results
    output = ANALYZE_PROTEIN_COLOCALIZATION.out.output
    versions = ANALYZE_PROTEIN_COLOCALIZATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_PROTEIN_COLOCALIZATION_WORKFLOW(ch_input)

    ANALYZE_PROTEIN_COLOCALIZATION_WORKFLOW.out.output.view { "Output: $it" }
}
