#!/usr/bin/env nextflow
/*
 * bioimaging/create_affine_transform
 * Create an affine transform for image registration.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Mock NIFTI images for registration test
params.fixed_image = "${projectDir}/../../../test_data/mock_fixed_image.nii.gz"
params.moving_image = "${projectDir}/../../../test_data/mock_moving_image.nii.gz"
params.initial_transform = null

process CREATE_AFFINE_TRANSFORM {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("create_affine_transform_results.json"), emit: results
    tuple val(meta), path("create_affine_transform_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FIXED_IMAGE="${params.fixed_image?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MOVING_IMAGE="${params.moving_image?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_INITIAL_TRANSFORM="${params.initial_transform?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def create_affine_transform(fixed_image=None, moving_image=None, initial_transform=None):
    '''Create an affine transform for image registration using SimpleITK.

    An affine transform includes translation, rotation, scaling, and shearing.
    It preserves parallel lines but not necessarily distances or angles.

    Args:
        fixed_image: Path to the fixed/reference image
        moving_image: Path to the moving image to be registered
        initial_transform: Optional path to initial transform file

    Returns:
        Dictionary with affine transform parameters
    '''
    import SimpleITK as sitk
    import numpy as np

    # Load images
    if fixed_image and fixed_image != 'null':
        fixed = sitk.ReadImage(str(fixed_image))
    else:
        return {"function": "create_affine_transform", "status": "error",
                "message": "Fixed image path required"}

    if moving_image and moving_image != 'null':
        moving = sitk.ReadImage(str(moving_image))
    else:
        return {"function": "create_affine_transform", "status": "error",
                "message": "Moving image path required"}

    # Get image dimension
    dimension = fixed.GetDimension()

    # Create affine transform centered on the fixed image
    affine_transform = sitk.AffineTransform(dimension)

    # Set center of rotation to center of fixed image
    center = [fixed.GetOrigin()[i] + fixed.GetSize()[i] * fixed.GetSpacing()[i] / 2.0
              for i in range(dimension)]
    affine_transform.SetCenter(center)

    # Initialize with identity matrix (no initial transformation)
    identity_matrix = list(np.eye(dimension).flatten())
    affine_transform.SetMatrix(identity_matrix)
    affine_transform.SetTranslation([0.0] * dimension)

    # If initial transform provided, compose with it
    if initial_transform and initial_transform != 'null':
        try:
            init_tx = sitk.ReadTransform(str(initial_transform))
            # Compose transforms
            composite = sitk.CompositeTransform(dimension)
            composite.AddTransform(init_tx)
            composite.AddTransform(affine_transform)
            transform_params = list(composite.GetParameters())
        except Exception as e:
            transform_params = list(affine_transform.GetParameters())
    else:
        transform_params = list(affine_transform.GetParameters())

    # Save transform to file
    output_transform_path = "affine_transform.tfm"
    sitk.WriteTransform(affine_transform, output_transform_path)

    return {
        "function": "create_affine_transform",
        "status": "success",
        "transform_type": "AffineTransform",
        "dimension": dimension,
        "center": center,
        "matrix": identity_matrix,
        "translation": [0.0] * dimension,
        "parameters": transform_params,
        "num_parameters": len(transform_params),
        "fixed_image": str(fixed_image),
        "moving_image": str(moving_image),
        "transform_file": output_transform_path,
        "degrees_of_freedom": dimension * dimension + dimension,
        "message": f"Created {dimension}D affine transform with {len(transform_params)} parameters"
    }

# Execute the function
try:
    result = create_affine_transform(
        fixed_image=auto_convert(os.environ.get("PARAM_FIXED_IMAGE", "")),
        moving_image=auto_convert(os.environ.get("PARAM_MOVING_IMAGE", "")),
        initial_transform=auto_convert(os.environ.get("PARAM_INITIAL_TRANSFORM", "")),
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
    "function": "create_affine_transform",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("create_affine_transform_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("create_affine_transform_output.txt", "w") as f:
    f.write("Biomni: Create Affine Transform" + NL)
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
        biomni_function: "create_affine_transform"
    END_VERSIONS
    """
}

workflow CREATE_AFFINE_TRANSFORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CREATE_AFFINE_TRANSFORM(ch_input)

    emit:
    results = CREATE_AFFINE_TRANSFORM.out.results
    output = CREATE_AFFINE_TRANSFORM.out.output
    versions = CREATE_AFFINE_TRANSFORM.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CREATE_AFFINE_TRANSFORM_WORKFLOW(ch_input)

    CREATE_AFFINE_TRANSFORM_WORKFLOW.out.output.view { "Output: $it" }
}
