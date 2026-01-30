#!/usr/bin/env nextflow
/*
 * bioimaging/create_rigid_transform
 * Create a rigid transform for image registration.
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

process CREATE_RIGID_TRANSFORM {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("create_rigid_transform_results.json"), emit: results
    tuple val(meta), path("create_rigid_transform_output.txt"), emit: output
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



def create_rigid_transform(fixed_image=None, moving_image=None, initial_transform=None):
    '''Create a rigid transform for image registration using SimpleITK.

    A rigid transform only allows rotation and translation, preserving
    distances and angles. It has 6 degrees of freedom in 3D (3 rotations + 3 translations).

    Args:
        fixed_image: Path to the fixed/reference image
        moving_image: Path to the moving image to be registered
        initial_transform: Optional path to initial transform file

    Returns:
        Dictionary with rigid transform parameters
    '''
    import SimpleITK as sitk
    import numpy as np

    # Load images
    if fixed_image and fixed_image != 'null':
        fixed = sitk.ReadImage(str(fixed_image))
    else:
        return {"function": "create_rigid_transform", "status": "error",
                "message": "Fixed image path required"}

    if moving_image and moving_image != 'null':
        moving = sitk.ReadImage(str(moving_image))
    else:
        return {"function": "create_rigid_transform", "status": "error",
                "message": "Moving image path required"}

    # Get image dimension
    dimension = fixed.GetDimension()

    # Create appropriate rigid transform based on dimension
    if dimension == 2:
        rigid_transform = sitk.Euler2DTransform()
        dof = 3  # 1 rotation + 2 translations
    elif dimension == 3:
        rigid_transform = sitk.Euler3DTransform()
        dof = 6  # 3 rotations + 3 translations
    else:
        return {"function": "create_rigid_transform", "status": "error",
                "message": f"Unsupported dimension: {dimension}"}

    # Set center of rotation to center of fixed image
    center = [fixed.GetOrigin()[i] + fixed.GetSize()[i] * fixed.GetSpacing()[i] / 2.0
              for i in range(dimension)]
    rigid_transform.SetCenter(center)

    # Initialize with identity (no rotation, no translation)
    if dimension == 2:
        rigid_transform.SetAngle(0.0)
        rigid_transform.SetTranslation([0.0, 0.0])
    else:
        rigid_transform.SetRotation(0.0, 0.0, 0.0)  # Euler angles
        rigid_transform.SetTranslation([0.0, 0.0, 0.0])

    # Get initial parameters
    transform_params = list(rigid_transform.GetParameters())

    # If initial transform provided, use CenteredTransformInitializer
    if initial_transform and initial_transform != 'null':
        try:
            init_tx = sitk.ReadTransform(str(initial_transform))
            # Apply initial transform parameters
            rigid_transform = sitk.Euler3DTransform(init_tx) if dimension == 3 else sitk.Euler2DTransform(init_tx)
            transform_params = list(rigid_transform.GetParameters())
        except Exception as e:
            pass  # Keep identity transform

    # Use CenteredTransformInitializer for better initial alignment
    initial_transform_sitk = sitk.CenteredTransformInitializer(
        fixed,
        moving,
        rigid_transform,
        sitk.CenteredTransformInitializerFilter.GEOMETRY
    )

    # Save transform to file
    output_transform_path = "rigid_transform.tfm"
    sitk.WriteTransform(initial_transform_sitk, output_transform_path)

    return {
        "function": "create_rigid_transform",
        "status": "success",
        "transform_type": f"Euler{dimension}DTransform",
        "dimension": dimension,
        "center": center,
        "rotation_angles": [0.0] * (1 if dimension == 2 else 3),
        "translation": [0.0] * dimension,
        "parameters": list(initial_transform_sitk.GetParameters()),
        "num_parameters": len(list(initial_transform_sitk.GetParameters())),
        "degrees_of_freedom": dof,
        "fixed_image": str(fixed_image),
        "moving_image": str(moving_image),
        "transform_file": output_transform_path,
        "message": f"Created {dimension}D rigid transform with {dof} degrees of freedom"
    }

# Execute the function
try:
    result = create_rigid_transform(
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
    "function": "create_rigid_transform",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("create_rigid_transform_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("create_rigid_transform_output.txt", "w") as f:
    f.write("Biomni: Create Rigid Transform" + NL)
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
        biomni_function: "create_rigid_transform"
    END_VERSIONS
    """
}

workflow CREATE_RIGID_TRANSFORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CREATE_RIGID_TRANSFORM(ch_input)

    emit:
    results = CREATE_RIGID_TRANSFORM.out.results
    output = CREATE_RIGID_TRANSFORM.out.output
    versions = CREATE_RIGID_TRANSFORM.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CREATE_RIGID_TRANSFORM_WORKFLOW(ch_input)

    CREATE_RIGID_TRANSFORM_WORKFLOW.out.output.view { "Output: $it" }
}
