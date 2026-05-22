#!/usr/bin/env nextflow
/*
 * bioimaging/save_image
 * Save a SimpleITK image to file.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: null values create a demo synthetic image
params.image = null
params.output_path = 'saved_demo_image.nii.gz'

process SAVE_IMAGE {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("save_image_results.json"), emit: results
    tuple val(meta), path("save_image_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_IMAGE="${params.image?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_PATH="${params.output_path?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def save_image(image=None, output_path=None):
    '''Save a SimpleITK image to file.

    This function demonstrates image saving. In actual use, it receives
    a SimpleITK image object. For this workflow test, it creates a demo image.

    Args:
        image: SimpleITK image object or path to source image
        output_path: Path where to save the image

    Returns:
        Dictionary with save operation results
    '''
    import SimpleITK as sitk
    import numpy as np
    import os

    # Determine output path
    if output_path is None or output_path == 'null':
        output_path = "output_image.nii.gz"

    try:
        # If image is a path string, load it first
        if isinstance(image, str) and image != 'null' and os.path.exists(image):
            img = sitk.ReadImage(image)
            source_type = "loaded_from_file"
        elif image is None or image == 'null':
            # Create a demo 3D image for testing
            demo_array = np.random.randn(32, 64, 64).astype(np.float32) * 100
            demo_array[8:24, 16:48, 16:48] = 500  # Add a bright region
            img = sitk.GetImageFromArray(demo_array)
            img.SetSpacing([1.0, 1.0, 1.0])
            img.SetOrigin([0.0, 0.0, 0.0])
            source_type = "demo_generated"
        else:
            # Assume it's already a SimpleITK image (in production use)
            img = image
            source_type = "sitk_image"

        # Get image properties before saving
        dimension = img.GetDimension()
        size = list(img.GetSize())
        spacing = list(img.GetSpacing())
        pixel_type = img.GetPixelIDTypeAsString()

        # Save the image
        sitk.WriteImage(img, str(output_path))

        # Verify the file was created
        file_exists = os.path.exists(str(output_path))
        file_size = os.path.getsize(str(output_path)) if file_exists else 0

        return {
            "function": "save_image",
            "status": "success",
            "output_path": str(output_path),
            "source_type": source_type,
            "dimension": dimension,
            "size": size,
            "spacing": spacing,
            "pixel_type": pixel_type,
            "file_exists": file_exists,
            "file_size_bytes": file_size,
            "message": f"Successfully saved {dimension}D image to {output_path}"
        }

    except Exception as e:
        return {
            "function": "save_image",
            "status": "error",
            "output_path": str(output_path),
            "message": f"Failed to save image: {str(e)}"
        }

# Execute the function
try:
    result = save_image(
        image=auto_convert(os.environ.get("PARAM_IMAGE", "")),
        output_path=auto_convert(os.environ.get("PARAM_OUTPUT_PATH", "")),
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
    "function": "save_image",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("save_image_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("save_image_output.txt", "w") as f:
    f.write("Biomni: Save Image" + NL)
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
        biomni_function: "save_image"
    END_VERSIONS
    """
}

workflow SAVE_IMAGE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SAVE_IMAGE(ch_input)

    emit:
    results = SAVE_IMAGE.out.results
    output = SAVE_IMAGE.out.output
    versions = SAVE_IMAGE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SAVE_IMAGE_WORKFLOW(ch_input)

    SAVE_IMAGE_WORKFLOW.out.output.view { "Output: $it" }
}
