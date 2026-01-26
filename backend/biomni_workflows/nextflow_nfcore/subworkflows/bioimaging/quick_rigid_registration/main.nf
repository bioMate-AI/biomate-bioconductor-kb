#!/usr/bin/env nextflow
/*
 * bioimaging/quick_rigid_registration
 * Quick rigid registration function for Biomni integration.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.fixed_image_path = null
params.moving_image_path = null
params.output_dir = null
params.metric = 'mutual_information'
params.optimizer = 'gradient_descent'
params.preprocess = null
params.create_visualizations = null
params.learning_rate = 0.01
params.number_of_iterations = 100
params.gradient_convergence_tolerance = 1e-06

process QUICK_RIGID_REGISTRATION {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("quick_rigid_registration_results.json"), emit: results
    tuple val(meta), path("quick_rigid_registration_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FIXED_IMAGE_PATH="${params.fixed_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MOVING_IMAGE_PATH="${params.moving_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_METRIC="${params.metric?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OPTIMIZER="${params.optimizer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PREPROCESS="${params.preprocess?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CREATE_VISUALIZATIONS="${params.create_visualizations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LEARNING_RATE="${params.learning_rate?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUMBER_OF_ITERATIONS="${params.number_of_iterations?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GRADIENT_CONVERGENCE_TOLERANCE="${params.gradient_convergence_tolerance?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
import SimpleITK as sitk
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



def quick_rigid_registration(
    fixed_image_path: str,
    moving_image_path: str,
    output_dir: str,
    metric: str = "mutual_information",
    optimizer: str = "gradient_descent",
    preprocess: bool = True,
    create_visualizations: bool = True,
    learning_rate: float = 0.01,
    number_of_iterations: int = 100,
    gradient_convergence_tolerance: float = 1e-6,
) -> dict:
    '''
    Quick rigid registration function for Biomni integration.

    Args:
        fixed_image_path: Path to reference image
        moving_image_path: Path to image to register
        output_dir: Directory to save results
        metric: Similarity metric
        optimizer: Optimization method
        preprocess: Whether to preprocess images
        create_visualizations: Whether to create visualizations
        learning_rate: Learning rate for optimizer
        number_of_iterations: Maximum iterations
        gradient_convergence_tolerance: Convergence tolerance

    Returns:
        Dictionary with registration results
    '''
    tool = ImageRegistrationTool()

    # Load images
    fixed_image = tool.load_image(fixed_image_path)
    moving_image = tool.load_image(moving_image_path)

    # Preprocess if requested
    if preprocess:
        fixed_image = tool.preprocess_image(fixed_image)
        moving_image = tool.preprocess_image(moving_image)

    # Create transform and registration method
    transform = tool.create_rigid_transform(fixed_image, moving_image)
    registration_method = tool.setup_registration_method(
        transform, metric, optimizer, learning_rate, number_of_iterations, gradient_convergence_tolerance
    )

    # Perform registration
    final_transform, registered_image = tool.register_images(fixed_image, moving_image, transform, registration_method)

    # Save results
    os.makedirs(output_dir, exist_ok=True)

    # Save registered image
    registered_path = os.path.join(output_dir, "rigid_registered.nii.gz")
    tool.save_image(registered_image, registered_path)

    # Save transform
    transform_path = os.path.join(output_dir, "rigid_transform.tfm")
    sitk.WriteTransform(final_transform, transform_path)

    # Calculate metrics
    metrics_before = tool.calculate_similarity_metrics(fixed_image, moving_image)
    metrics_after = tool.calculate_similarity_metrics(fixed_image, registered_image)

    results = {
        "registered_image_path": registered_path,
        "transform_path": transform_path,
        "metrics_before": metrics_before,
        "metrics_after": metrics_after,
        "registration_type": "rigid",
    }

    return results

# Execute the function
try:
    result = quick_rigid_registration(
        fixed_image_path=auto_convert(os.environ.get("PARAM_FIXED_IMAGE_PATH", "")),
        moving_image_path=auto_convert(os.environ.get("PARAM_MOVING_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        metric=auto_convert(os.environ.get("PARAM_METRIC", "mutual_information")),
        optimizer=auto_convert(os.environ.get("PARAM_OPTIMIZER", "gradient_descent")),
        preprocess=auto_convert(os.environ.get("PARAM_PREPROCESS", "")),
        create_visualizations=auto_convert(os.environ.get("PARAM_CREATE_VISUALIZATIONS", "")),
        learning_rate=auto_convert(os.environ.get("PARAM_LEARNING_RATE", "0.01")),
        number_of_iterations=auto_convert(os.environ.get("PARAM_NUMBER_OF_ITERATIONS", "100")),
        gradient_convergence_tolerance=auto_convert(os.environ.get("PARAM_GRADIENT_CONVERGENCE_TOLERANCE", "1e-06")),
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
    "function": "quick_rigid_registration",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("quick_rigid_registration_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("quick_rigid_registration_output.txt", "w") as f:
    f.write("Biomni: Quick Rigid Registration" + NL)
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
        biomni_function: "quick_rigid_registration"
    END_VERSIONS
    """
}

workflow QUICK_RIGID_REGISTRATION_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    QUICK_RIGID_REGISTRATION(ch_input)

    emit:
    results = QUICK_RIGID_REGISTRATION.out.results
    output = QUICK_RIGID_REGISTRATION.out.output
    versions = QUICK_RIGID_REGISTRATION.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    QUICK_RIGID_REGISTRATION_WORKFLOW(ch_input)

    QUICK_RIGID_REGISTRATION_WORKFLOW.out.output.view { "Output: $it" }
}
