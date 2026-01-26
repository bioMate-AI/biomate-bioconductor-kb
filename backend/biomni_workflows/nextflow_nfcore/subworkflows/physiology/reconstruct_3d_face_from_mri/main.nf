#!/usr/bin/env nextflow
/*
 * physiology/reconstruct_3d_face_from_mri
 * Generate a 3D model of facial anatomy from MRI scans of the head and neck.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.mri_file_path = null
params.output_dir = './output'
params.subject_id = 'subject'
params.threshold_value = '300'

process RECONSTRUCT_3D_FACE_FROM_MRI {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("reconstruct_3d_face_from_mri_results.json"), emit: results
    tuple val(meta), path("reconstruct_3d_face_from_mri_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_MRI_FILE_PATH="${params.mri_file_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SUBJECT_ID="${params.subject_id?.toString()?.replace('"', '\\"') ?: 'null'}"
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



def reconstruct_3d_face_from_mri(mri_file_path, output_dir="./output", subject_id="subject", threshold_value=300):
    '''Generate a 3D model of facial anatomy from MRI scans of the head and neck.

    Parameters
    ----------
    mri_file_path : str
        Path to the MRI scan file (NIfTI format: .nii or .nii.gz)
    output_dir : str
        Directory where output files will be saved
    subject_id : str
        Identifier for the subject, used in output filenames
    threshold_value : int
        Threshold value for initial segmentation of facial tissues

    Returns
    -------
    str
        Research log detailing the reconstruction process and output file locations

    '''
    import os
    import time
    from datetime import datetime

    import nibabel as nib
    import numpy as np
    import SimpleITK as sitk
    from skimage import measure

    # Create output directory if it doesn't exist
    os.makedirs(output_dir, exist_ok=True)

    log = []
    log.append(f"3D Facial Reconstruction Log - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    log.append(f"Subject ID: {subject_id}")
    log.append(f"MRI Source: {mri_file_path}")
    log.append("-" * 50)

    # Step 1: Load MRI data
    start_time = time.time()
    log.append("Step 1: Loading MRI data")

    try:
        # Try loading with nibabel first
        mri_data = nib.load(mri_file_path)
        volume_data = mri_data.get_fdata()
        log.append(f"  Loaded MRI data with dimensions: {volume_data.shape}")
        log.append(f"  Data type: {volume_data.dtype}")
    except Exception as e:
        log.append(f"  Error loading with nibabel: {str(e)}")
        log.append("  Attempting to load with SimpleITK...")

        try:
            # Fallback to SimpleITK
            mri_image = sitk.ReadImage(mri_file_path)
            volume_data = sitk.GetArrayFromImage(mri_image)
            log.append(f"  Loaded MRI data with dimensions: {volume_data.shape}")
        except Exception as e2:
            log.append(f"  Failed to load MRI data: {str(e2)}")
            return "\\n".join(log)

    elapsed = time.time() - start_time
    log.append(f"  Completed in {elapsed:.2f} seconds")

    # Step 2: Preprocess MRI data
    start_time = time.time()
    log.append("Step 2: Preprocessing MRI data")

    # Normalize data to 0-1 range for processing
    data_min = np.min(volume_data)
    data_max = np.max(volume_data)
    normalized_data = (volume_data - data_min) / (data_max - data_min)

    # Apply noise reduction filter using SimpleITK
    sitk_image = sitk.GetImageFromArray(normalized_data)
    smoothed_image = sitk.CurvatureFlow(image1=sitk_image, timeStep=0.125, numberOfIterations=5)
    smoothed_data = sitk.GetArrayFromImage(smoothed_image)

    log.append("  Applied noise reduction filter")
    elapsed = time.time() - start_time
    log.append(f"  Completed in {elapsed:.2f} seconds")

    # Step 3: Segment facial tissues
    start_time = time.time()
    log.append("Step 3: Segmenting facial tissues")

    # Apply threshold to segment facial tissues
    normalized_threshold = threshold_value / (data_max - data_min)
    binary_mask = smoothed_data > normalized_threshold

    # Remove small isolated regions
    sitk_mask = sitk.GetImageFromArray(binary_mask.astype(np.uint8))
    cleaned_mask = sitk.BinaryOpeningByReconstruction(sitk_mask, [3, 3, 3])
    segmentation = sitk.GetArrayFromImage(cleaned_mask)

    log.append(f"  Applied threshold value: {threshold_value}")
    log.append("  Removed small isolated regions")

    # Save segmentation mask
    segmentation_file = os.path.join(output_dir, f"{subject_id}_face_segmentation.nii.gz")
    sitk.WriteImage(sitk.GetImageFromArray(segmentation.astype(np.uint8)), segmentation_file)
    log.append(f"  Saved segmentation mask to: {segmentation_file}")

    elapsed = time.time() - start_time
    log.append(f"  Completed in {elapsed:.2f} seconds")

    # Step 4: Generate 3D surface mesh
    start_time = time.time()
    log.append("Step 4: Generating 3D surface mesh")

    # Create mesh using marching cubes algorithm
    try:
        verts, faces, normals, values = measure.marching_cubes(segmentation, level=0.5)
        log.append(f"  Generated mesh with {len(verts)} vertices and {len(faces)} faces")

        # Save mesh as OBJ file
        mesh_file = os.path.join(output_dir, f"{subject_id}_face_3d_model.obj")

        with open(mesh_file, "w") as f:
            # Write vertices
            for v in verts:
                f.write(f"v {v[0]} {v[1]} {v[2]}\\n")

            # Write vertex normals
            for n in normals:
                f.write(f"vn {n[0]} {n[1]} {n[2]}\\n")

            # Write faces (OBJ uses 1-indexed vertices)
            for face in faces:
                f.write(f"f {face[0] + 1} {face[1] + 1} {face[2] + 1}\\n")

        log.append(f"  Saved 3D model to: {mesh_file}")
    except Exception as e:
        log.append(f"  Error generating mesh: {str(e)}")

    elapsed = time.time() - start_time
    log.append(f"  Completed in {elapsed:.2f} seconds")

    # Final summary
    log.append("-" * 50)
    log.append("Reconstruction Summary:")
    log.append(f"  Subject ID: {subject_id}")
    log.append(f"  Segmentation file: {os.path.basename(segmentation_file)}")
    log.append(f"  3D Model file: {os.path.basename(mesh_file)}")
    log.append("-" * 50)

    return "\\n".join(log)

# Execute the function
try:
    result = reconstruct_3d_face_from_mri(
        mri_file_path=auto_convert(os.environ.get("PARAM_MRI_FILE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "./output")),
        subject_id=auto_convert(os.environ.get("PARAM_SUBJECT_ID", "subject")),
        threshold_value=auto_convert(os.environ.get("PARAM_THRESHOLD_VALUE", "300")),
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
    "function": "reconstruct_3d_face_from_mri",
    "domain": "physiology",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("reconstruct_3d_face_from_mri_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("reconstruct_3d_face_from_mri_output.txt", "w") as f:
    f.write("Biomni: Reconstruct 3D Face From Mri" + NL)
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
        biomni_function: "reconstruct_3d_face_from_mri"
    END_VERSIONS
    """
}

workflow RECONSTRUCT_3D_FACE_FROM_MRI_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    RECONSTRUCT_3D_FACE_FROM_MRI(ch_input)

    emit:
    results = RECONSTRUCT_3D_FACE_FROM_MRI.out.results
    output = RECONSTRUCT_3D_FACE_FROM_MRI.out.output
    versions = RECONSTRUCT_3D_FACE_FROM_MRI.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    RECONSTRUCT_3D_FACE_FROM_MRI_WORKFLOW(ch_input)

    RECONSTRUCT_3D_FACE_FROM_MRI_WORKFLOW.out.output.view { "Output: $it" }
}
