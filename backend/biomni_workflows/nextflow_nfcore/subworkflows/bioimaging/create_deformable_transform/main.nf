#!/usr/bin/env nextflow
/*
 * bioimaging/create_deformable_transform
 * Create a deformable (B-spline) transform for image registration.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Mock NIFTI images for registration test
params.fixed_image = "${projectDir}/../../../test_data/mock_fixed_image.nii.gz"
params.moving_image = "${projectDir}/../../../test_data/mock_moving_image.nii.gz"
params.number_of_control_points = 4

process CREATE_DEFORMABLE_TRANSFORM {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("create_deformable_transform_results.json"), emit: results
    tuple val(meta), path("create_deformable_transform_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FIXED_IMAGE="${params.fixed_image?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MOVING_IMAGE="${params.moving_image?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUMBER_OF_CONTROL_POINTS="${params.number_of_control_points?.toString()?.replace('"', '\\"') ?: 'null'}"

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



def create_deformable_transform(fixed_image=None, moving_image=None, number_of_control_points=4):
    '''Create a deformable (B-spline) transform for image registration using SimpleITK.

    B-spline transforms allow for local, non-rigid deformations controlled by
    a grid of control points. Higher control point density allows finer deformations.

    Args:
        fixed_image: Path to the fixed/reference image
        moving_image: Path to the moving image to be registered
        number_of_control_points: Number of control points per dimension (default: 4)

    Returns:
        Dictionary with B-spline transform parameters
    '''
    import SimpleITK as sitk
    import numpy as np

    # Load images
    if fixed_image and fixed_image != 'null':
        fixed = sitk.ReadImage(str(fixed_image))
    else:
        return {"function": "create_deformable_transform", "status": "error",
                "message": "Fixed image path required"}

    if moving_image and moving_image != 'null':
        moving = sitk.ReadImage(str(moving_image))
    else:
        return {"function": "create_deformable_transform", "status": "error",
                "message": "Moving image path required"}

    # Get image properties
    dimension = fixed.GetDimension()

    # Ensure number_of_control_points is valid
    if number_of_control_points is None:
        number_of_control_points = 4
    num_ctrl_pts = int(number_of_control_points)

    # Create B-spline transform
    # The transform domain is defined by the fixed image
    transform_domain_mesh_size = [num_ctrl_pts - 3] * dimension  # B-spline order 3

    bspline_transform = sitk.BSplineTransformInitializer(
        image1=fixed,
        transformDomainMeshSize=transform_domain_mesh_size,
        order=3
    )

    # Get transform properties
    num_parameters = bspline_transform.GetNumberOfParameters()
    grid_size = list(bspline_transform.GetTransformDomainMeshSize())

    # Initialize with zero displacement
    params = [0.0] * num_parameters
    bspline_transform.SetParameters(params)

    # Save transform to file
    output_transform_path = "bspline_transform.tfm"
    sitk.WriteTransform(bspline_transform, output_transform_path)

    return {
        "function": "create_deformable_transform",
        "status": "success",
        "transform_type": "BSplineTransform",
        "dimension": dimension,
        "bspline_order": 3,
        "control_points_per_dimension": num_ctrl_pts,
        "grid_size": grid_size,
        "num_parameters": num_parameters,
        "fixed_image": str(fixed_image),
        "moving_image": str(moving_image),
        "transform_file": output_transform_path,
        "transform_domain_origin": list(bspline_transform.GetTransformDomainOrigin()),
        "transform_domain_spacing": list(bspline_transform.GetTransformDomainPhysicalDimensions()),
        "message": f"Created {dimension}D B-spline transform with {num_parameters} parameters"
    }

# Execute the function
try:
    result = create_deformable_transform(
        fixed_image=auto_convert(os.environ.get("PARAM_FIXED_IMAGE", "")),
        moving_image=auto_convert(os.environ.get("PARAM_MOVING_IMAGE", "")),
        number_of_control_points=auto_convert(os.environ.get("PARAM_NUMBER_OF_CONTROL_POINTS", "4")),
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
    "function": "create_deformable_transform",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("create_deformable_transform_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("create_deformable_transform_output.txt", "w") as f:
    f.write("Biomni: Create Deformable Transform" + NL)
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
        biomni_function: "create_deformable_transform"
    END_VERSIONS
    """
}

workflow CREATE_DEFORMABLE_TRANSFORM_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CREATE_DEFORMABLE_TRANSFORM(ch_input)

    emit:
    results = CREATE_DEFORMABLE_TRANSFORM.out.results
    output = CREATE_DEFORMABLE_TRANSFORM.out.output
    versions = CREATE_DEFORMABLE_TRANSFORM.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CREATE_DEFORMABLE_TRANSFORM_WORKFLOW(ch_input)

    CREATE_DEFORMABLE_TRANSFORM_WORKFLOW.out.output.view { "Output: $it" }
}
