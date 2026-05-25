#!/usr/bin/env nextflow
/*
 * pathology/analyze_bone_microct_morphometry
 * Analyze bone microarchitecture parameters from 3D micro-CT images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.input_file_path = null
params.output_dir = './results'
params.threshold_value = null

process ANALYZE_BONE_MICROCT_MORPHOMETRY {
    tag "$meta.id"
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("analyze_bone_microct_morphometry_results.json"), emit: results
    tuple val(meta), path("analyze_bone_microct_morphometry_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INPUT_FILE_PATH="${params.input_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_THRESHOLD_VALUE="${params.threshold_value?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def analyze_bone_microct_morphometry(input_file_path, output_dir="./results", threshold_value=None):
    '''Analyze bone microarchitecture parameters from 3D micro-CT images.

    Performs quantitative analysis of bone microstructure to calculate bone mineral density (BMD),
    bone volume (BV), trabecular number (Tb.N), trabecular thickness (Tb.Th), and
    trabecular separation (Tb.S) from micro-CT data.

    Parameters
    ----------
    input_file_path : str
        Path to the micro-CT scan data file (TIFF stack or similar 3D format)
    output_dir : str, optional
        Directory to save output files, default is "./results"
    threshold_value : float, optional
        Threshold value for bone segmentation. If None, Otsu's method will be used

    Returns
    -------
    str
        Research log summarizing the analysis steps and results

    '''
    import json
    import os
    from datetime import datetime

    import numpy as np
    from scipy import ndimage
    from skimage import filters, io

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    # Start research log
    log = [
        "# Micro-CT Bone Morphometry Analysis",
        f"Date: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        f"Input file: {input_file_path}",
    ]

    # Step 1: Load the micro-CT data
    log.append("\\n## 1. Data Loading")
    try:
        log.append(f"Loading 3D micro-CT data from {input_file_path}")
        # Load the 3D image data
        image_data = io.imread(input_file_path)
        if image_data.ndim < 3:
            log.append("Warning: Input appears to be 2D. Converting to 3D.")
            image_data = np.expand_dims(image_data, axis=0)

        log.append(f"Data loaded successfully. Dimensions: {image_data.shape}")
        voxel_count = image_data.size
        log.append(f"Total voxels: {voxel_count}")
    except Exception as e:
        error_msg = f"Error loading data: {str(e)}"
        log.append(error_msg)
        return "\\n".join(log)

    # Step 2: Preprocess the data
    log.append("\\n## 2. Preprocessing")
    log.append("Applying median filter to reduce noise")
    filtered_data = ndimage.median_filter(image_data, size=2)

    # Step 3: Segmentation of bone tissue
    log.append("\\n## 3. Bone Segmentation")
    if threshold_value is None:
        log.append("Calculating optimal threshold using Otsu's method")
        threshold_value = filters.threshold_otsu(filtered_data)

    log.append(f"Segmenting bone using threshold value: {threshold_value}")
    binary_image = filtered_data > threshold_value

    # Step 4: Calculate bone morphometry parameters
    log.append("\\n## 4. Morphometry Analysis")

    # 4.1 Calculate BMD (simplified as mean intensity in bone regions)
    bmd = np.mean(image_data[binary_image])
    log.append(f"Bone Mineral Density (BMD): {bmd:.2f} arbitrary units")

    # 4.2 Calculate BV (bone volume)
    bone_volume = np.sum(binary_image)
    total_volume = binary_image.size
    bv_tv_ratio = bone_volume / total_volume
    log.append(f"Bone Volume (BV): {bone_volume} voxels")
    log.append(f"BV/TV Ratio: {bv_tv_ratio:.4f}")

    # 4.3 Calculate trabecular thickness (Tb.Th)
    # Using distance transform method
    log.append("Calculating trabecular thickness (Tb.Th)")
    distance_map = ndimage.distance_transform_edt(binary_image)
    tb_th_mean = np.mean(distance_map[binary_image]) * 2  # Multiply by 2 for diameter
    log.append(f"Trabecular Thickness (Tb.Th): {tb_th_mean:.2f} voxels")

    # 4.4 Calculate trabecular separation (Tb.S)
    log.append("Calculating trabecular separation (Tb.S)")
    distance_map_inv = ndimage.distance_transform_edt(~binary_image)
    tb_s_mean = np.mean(distance_map_inv[~binary_image])
    log.append(f"Trabecular Separation (Tb.S): {tb_s_mean:.2f} voxels")

    # 4.5 Calculate trabecular number (Tb.N)
    # Simplified calculation: Tb.N = (BV/TV) / Tb.Th
    log.append("Calculating trabecular number (Tb.N)")
    tb_n = bv_tv_ratio / tb_th_mean if tb_th_mean > 0 else 0
    log.append(f"Trabecular Number (Tb.N): {tb_n:.4f} 1/voxel")

    # Step 5: Save results
    log.append("\\n## 5. Saving Results")

    # Save binary segmentation as a sample slice
    middle_slice = binary_image.shape[0] // 2
    segmentation_file = os.path.join(output_dir, "bone_segmentation_slice.tif")
    io.imsave(segmentation_file, binary_image[middle_slice].astype(np.uint8) * 255)
    log.append(f"Sample segmentation slice saved to: {segmentation_file}")

    # Save numerical results as JSON
    results = {
        "BMD": float(bmd),
        "BV": int(bone_volume),
        "BV/TV": float(bv_tv_ratio),
        "Tb.Th": float(tb_th_mean),
        "Tb.S": float(tb_s_mean),
        "Tb.N": float(tb_n),
    }

    results_file = os.path.join(output_dir, "bone_morphometry_results.json")
    with open(results_file, "w") as f:
        json.dump(results, f, indent=4)
    log.append(f"Numerical results saved to: {results_file}")

    # Summary of results
    log.append("\\n## 6. Summary of Bone Morphometry Results")
    log.append(f"- Bone Mineral Density (BMD): {bmd:.2f} arbitrary units")
    log.append(f"- Bone Volume (BV): {bone_volume} voxels")
    log.append(f"- BV/TV Ratio: {bv_tv_ratio:.4f}")
    log.append(f"- Trabecular Thickness (Tb.Th): {tb_th_mean:.2f} voxels")
    log.append(f"- Trabecular Separation (Tb.S): {tb_s_mean:.2f} voxels")
    log.append(f"- Trabecular Number (Tb.N): {tb_n:.4f} 1/voxel")

    return "\\n".join(log)

# Execute the function
try:
    result = analyze_bone_microct_morphometry(
        input_file_path=auto_convert(os.environ.get("PARAM_INPUT_FILE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./results")),
        threshold_value=auto_convert(os.environ.get("PARAM_THRESHOLD_VALUE", "")),
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
    "function": "analyze_bone_microct_morphometry",
    "domain": "pathology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("analyze_bone_microct_morphometry_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("analyze_bone_microct_morphometry_output.txt", "w") as f:
    f.write("Biomni: Analyze Bone Microct Morphometry" + NL)
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
        biomni_function: "analyze_bone_microct_morphometry"
    END_VERSIONS
    """
}

workflow ANALYZE_BONE_MICROCT_MORPHOMETRY_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    ANALYZE_BONE_MICROCT_MORPHOMETRY(ch_input)

    emit:
    results = ANALYZE_BONE_MICROCT_MORPHOMETRY.out.results
    output = ANALYZE_BONE_MICROCT_MORPHOMETRY.out.output
    versions = ANALYZE_BONE_MICROCT_MORPHOMETRY.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    ANALYZE_BONE_MICROCT_MORPHOMETRY_WORKFLOW(ch_input)

    ANALYZE_BONE_MICROCT_MORPHOMETRY_WORKFLOW.out.output.view { "Output: $it" }
}
