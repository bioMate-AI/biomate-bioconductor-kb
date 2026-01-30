#!/usr/bin/env nextflow
/*
 * bioimaging/load_image
 * Load a medical image using SimpleITK.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Mock brain NIFTI from test data
params.image_path = "${projectDir}/../../../test_data/mock_fixed_image.nii.gz"

process LOAD_IMAGE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("load_image_results.json"), emit: results
    tuple val(meta), path("load_image_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def load_image(image_path=None):
    '''Load a medical image using SimpleITK.

    Supports various formats: NIfTI (.nii, .nii.gz), DICOM, MetaImage (.mha, .mhd),
    NRRD, and other ITK-supported formats.

    Args:
        image_path: Path to the image file to load

    Returns:
        Dictionary with image metadata and properties
    '''
    import SimpleITK as sitk
    import numpy as np

    if not image_path or image_path == 'null':
        return {"function": "load_image", "status": "error",
                "message": "Image path required"}

    try:
        # Read the image
        image = sitk.ReadImage(str(image_path))

        # Get image properties
        dimension = image.GetDimension()
        size = list(image.GetSize())
        spacing = list(image.GetSpacing())
        origin = list(image.GetOrigin())
        direction = list(image.GetDirection())
        pixel_type = image.GetPixelIDTypeAsString()
        num_components = image.GetNumberOfComponentsPerPixel()

        # Get array for statistics
        array = sitk.GetArrayFromImage(image)

        # Calculate statistics
        stats = {
            "min": float(np.min(array)),
            "max": float(np.max(array)),
            "mean": float(np.mean(array)),
            "std": float(np.std(array)),
            "dtype": str(array.dtype)
        }

        # Calculate physical dimensions
        physical_size = [size[i] * spacing[i] for i in range(dimension)]

        # Determine file format from extension
        import os
        ext = os.path.splitext(str(image_path))[-1].lower()
        if ext == '.gz':
            ext = os.path.splitext(os.path.splitext(str(image_path))[0])[-1].lower() + '.gz'

        return {
            "function": "load_image",
            "status": "success",
            "image_path": str(image_path),
            "file_format": ext,
            "dimension": dimension,
            "size": size,
            "spacing": spacing,
            "origin": origin,
            "direction_matrix": direction,
            "pixel_type": pixel_type,
            "num_components": num_components,
            "physical_size_mm": physical_size,
            "total_voxels": int(np.prod(size)),
            "statistics": stats,
            "message": f"Successfully loaded {dimension}D image with size {size}"
        }

    except Exception as e:
        return {
            "function": "load_image",
            "status": "error",
            "image_path": str(image_path),
            "message": f"Failed to load image: {str(e)}"
        }

# Execute the function
try:
    result = load_image(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
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
    "function": "load_image",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("load_image_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("load_image_output.txt", "w") as f:
    f.write("Biomni: Load Image" + NL)
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
        biomni_function: "load_image"
    END_VERSIONS
    """
}

workflow LOAD_IMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    LOAD_IMAGE(ch_input)

    emit:
    results = LOAD_IMAGE.out.results
    output = LOAD_IMAGE.out.output
    versions = LOAD_IMAGE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    LOAD_IMAGE_WORKFLOW(ch_input)

    LOAD_IMAGE_WORKFLOW.out.output.view { "Output: $it" }
}
