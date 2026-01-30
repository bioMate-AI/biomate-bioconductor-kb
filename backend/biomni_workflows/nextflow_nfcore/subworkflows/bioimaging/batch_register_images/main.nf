#!/usr/bin/env nextflow
/*
 * bioimaging/batch_register_images
 * Batch registration of multiple images to a single reference.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Test data paths for registration
params.fixed_image_path = "${projectDir}/../../../test_data/mock_fixed_image.nii.gz"
params.moving_images_dir = "${projectDir}/../../../test_data"
params.output_dir = './results'
params.transform_type = 'rigid'
params.metric = 'mutual_information'
params.optimizer = 'gradient_descent'
params.preprocess = true
params.create_visualizations = true
params.learning_rate = 0.01
params.number_of_iterations = 100
params.gradient_convergence_tolerance = 1e-06

process BATCH_REGISTER_IMAGES {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("batch_register_images_results.json"), emit: results
    tuple val(meta), path("batch_register_images_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_FIXED_IMAGE_PATH="${params.fixed_image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MOVING_IMAGES_DIR="${params.moving_images_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TRANSFORM_TYPE="${params.transform_type?.toString()?.replace('"', '\\"') ?: 'rigid'}"
    export PARAM_METRIC="${params.metric?.toString()?.replace('"', '\\"') ?: 'mutual_information'}"
    export PARAM_OPTIMIZER="${params.optimizer?.toString()?.replace('"', '\\"') ?: 'gradient_descent'}"
    export PARAM_PREPROCESS="${params.preprocess?.toString()?.replace('"', '\\"') ?: 'true'}"
    export PARAM_CREATE_VISUALIZATIONS="${params.create_visualizations?.toString()?.replace('"', '\\"') ?: 'true'}"
    export PARAM_LEARNING_RATE="${params.learning_rate?.toString()?.replace('"', '\\"') ?: '0.01'}"
    export PARAM_NUMBER_OF_ITERATIONS="${params.number_of_iterations?.toString()?.replace('"', '\\"') ?: '100'}"
    export PARAM_GRADIENT_CONVERGENCE_TOLERANCE="${params.gradient_convergence_tolerance?.toString()?.replace('"', '\\"') ?: '1e-06'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import os
import SimpleITK as sitk
import json
import os

import logging
logger = logging.getLogger(__name__)


import logging
import os
import numpy as np
import SimpleITK as sitk

logger = logging.getLogger(__name__)


class ImageRegistrationTool:
    '''Medical image registration using SimpleITK.'''

    def __init__(self):
        '''Initialize the ImageRegistrationTool.'''
        self.supported_formats = [".nii", ".nii.gz", ".nrrd", ".mha", ".mhd"]

    def load_image(self, image_path):
        '''Load a medical image using SimpleITK.'''
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image file not found: {image_path}")
        return sitk.ReadImage(image_path)

    def save_image(self, image, output_path):
        '''Save a SimpleITK image to file.'''
        if os.path.isdir(output_path):
            raise ValueError(f"Output path is a directory: {output_path}")
        if not os.path.splitext(output_path)[1]:
            raise ValueError(f"Output path has no extension: {output_path}")
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        sitk.WriteImage(image, output_path)

    def preprocess_image(self, image, denoise=True, normalize=True):
        '''Preprocess an image with denoising and normalization.'''
        processed = sitk.Image(image)
        if denoise:
            processed = sitk.SmoothingRecursiveGaussian(processed, sigma=1.0)
        if normalize:
            mm = sitk.MinimumMaximumImageFilter()
            mm.Execute(processed)
            if mm.GetMaximum() > mm.GetMinimum():
                processed = sitk.IntensityWindowing(processed, windowMinimum=mm.GetMinimum(),
                                                   windowMaximum=mm.GetMaximum(), outputMinimum=0.0, outputMaximum=1.0)
        return processed

    def create_rigid_transform(self, fixed_image, moving_image, initial_transform=None):
        '''Create a rigid transform for registration.'''
        return initial_transform if initial_transform else sitk.Euler3DTransform()

    def create_affine_transform(self, fixed_image, moving_image, initial_transform=None):
        '''Create an affine transform for registration.'''
        return initial_transform if initial_transform else sitk.AffineTransform(3)

    def create_deformable_transform(self, fixed_image, moving_image, number_of_control_points=4):
        '''Create a B-spline deformable transform.'''
        return sitk.BSplineTransformInitializer(fixed_image, [number_of_control_points] * 3, order=3)

    def setup_registration_method(self, transform, metric="mutual_information", optimizer="gradient_descent",
                                   learning_rate=0.01, number_of_iterations=100, gradient_convergence_tolerance=1e-6):
        '''Setup the registration method.'''
        reg = sitk.ImageRegistrationMethod()
        if metric == "mutual_information":
            reg.SetMetricAsMattesMutualInformation(numberOfHistogramBins=50)
        elif metric == "mean_squares":
            reg.SetMetricAsMeanSquares()
        elif metric == "correlation":
            reg.SetMetricAsCorrelation()
        else:
            reg.SetMetricAsMattesMutualInformation(numberOfHistogramBins=50)

        if optimizer == "gradient_descent":
            reg.SetOptimizerAsGradientDescent(learningRate=learning_rate, numberOfIterations=number_of_iterations,
                                              convergenceMinimumValue=gradient_convergence_tolerance)
        elif optimizer == "lbfgsb":
            reg.SetOptimizerAsLBFGSB(gradientConvergenceTolerance=gradient_convergence_tolerance,
                                     numberOfIterations=number_of_iterations)
        elif optimizer == "powell":
            reg.SetOptimizerAsPowell(numberOfIterations=number_of_iterations, maximumLineIterations=20)
        else:
            reg.SetOptimizerAsGradientDescent(learningRate=learning_rate, numberOfIterations=number_of_iterations,
                                              convergenceMinimumValue=gradient_convergence_tolerance)

        reg.SetInterpolator(sitk.sitkLinear)
        reg.SetInitialTransform(transform, inPlace=False)
        return reg

    def register_images(self, fixed_image, moving_image, transform, registration_method):
        '''Perform image registration.'''
        final_transform = registration_method.Execute(fixed_image, moving_image)
        resampler = sitk.ResampleImageFilter()
        resampler.SetReferenceImage(fixed_image)
        resampler.SetInterpolator(sitk.sitkLinear)
        resampler.SetDefaultPixelValue(0)
        resampler.SetTransform(final_transform)
        return final_transform, resampler.Execute(moving_image)

    def calculate_similarity_metrics(self, image1, image2):
        '''Calculate similarity metrics between two images.'''
        metrics = {"mutual_information": 0.0, "mean_squares": 0.0, "correlation": 0.0, "normalized_correlation": 0.0}
        try:
            a1 = sitk.GetArrayFromImage(image1).flatten()
            a2 = sitk.GetArrayFromImage(image2).flatten()
            valid = np.isfinite(a1) & np.isfinite(a2)
            a1, a2 = a1[valid], a2[valid]
            if len(a1) == 0:
                return metrics

            metrics["mean_squares"] = -np.mean((a1 - a2) ** 2)
            if np.std(a1) > 0 and np.std(a2) > 0:
                c = np.corrcoef(a1, a2)[0, 1]
                metrics["correlation"] = c if not np.isnan(c) else 0.0
                metrics["normalized_correlation"] = metrics["correlation"]

            try:
                hist, _, _ = np.histogram2d(a1, a2, bins=50)
                hist = hist + 1e-10
                pxy = hist / np.sum(hist)
                px, py = np.sum(pxy, axis=1), np.sum(pxy, axis=0)
                mi = sum(pxy[i, j] * np.log2(pxy[i, j] / (px[i] * py[j]))
                        for i in range(len(px)) for j in range(len(py))
                        if pxy[i, j] > 0 and px[i] > 0 and py[j] > 0)
                metrics["mutual_information"] = mi
            except Exception:
                pass
        except Exception:
            pass
        return metrics


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

def quick_affine_registration(
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
    Quick affine registration function for Biomni integration.

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
    transform = tool.create_affine_transform(fixed_image, moving_image)
    registration_method = tool.setup_registration_method(
        transform, metric, optimizer, learning_rate, number_of_iterations, gradient_convergence_tolerance
    )

    # Perform registration
    final_transform, registered_image = tool.register_images(fixed_image, moving_image, transform, registration_method)

    # Save results
    os.makedirs(output_dir, exist_ok=True)

    # Save registered image
    registered_path = os.path.join(output_dir, "affine_registered.nii.gz")
    tool.save_image(registered_image, registered_path)

    # Save transform
    transform_path = os.path.join(output_dir, "affine_transform.tfm")
    sitk.WriteTransform(final_transform, transform_path)

    # Calculate metrics
    metrics_before = tool.calculate_similarity_metrics(fixed_image, moving_image)
    metrics_after = tool.calculate_similarity_metrics(fixed_image, registered_image)

    results = {
        "registered_image_path": registered_path,
        "transform_path": transform_path,
        "metrics_before": metrics_before,
        "metrics_after": metrics_after,
        "registration_type": "affine",
    }

    return results

def quick_deformable_registration(
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
    number_of_control_points: int = 4,
) -> dict:
    '''
    Quick deformable registration function for Biomni integration.

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
        number_of_control_points: Number of B-spline control points

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
    transform = tool.create_deformable_transform(fixed_image, moving_image, number_of_control_points)
    registration_method = tool.setup_registration_method(
        transform, metric, optimizer, learning_rate, number_of_iterations, gradient_convergence_tolerance
    )

    # Perform registration
    final_transform, registered_image = tool.register_images(fixed_image, moving_image, transform, registration_method)

    # Save results
    os.makedirs(output_dir, exist_ok=True)

    # Save registered image
    registered_path = os.path.join(output_dir, "deformable_registered.nii.gz")
    tool.save_image(registered_image, registered_path)

    # Save transform
    transform_path = os.path.join(output_dir, "deformable_transform.tfm")
    sitk.WriteTransform(final_transform, transform_path)

    # Calculate metrics
    metrics_before = tool.calculate_similarity_metrics(fixed_image, moving_image)
    metrics_after = tool.calculate_similarity_metrics(fixed_image, registered_image)

    results = {
        "registered_image_path": registered_path,
        "transform_path": transform_path,
        "metrics_before": metrics_before,
        "metrics_after": metrics_after,
        "registration_type": "deformable",
    }

    return results

def batch_register_images(
    fixed_image_path: str,
    moving_images_dir: str,
    output_dir: str,
    transform_type: str = "rigid",
    metric: str = "mutual_information",
    optimizer: str = "gradient_descent",
    preprocess: bool = True,
    create_visualizations: bool = True,
    learning_rate: float = 0.01,
    number_of_iterations: int = 100,
    gradient_convergence_tolerance: float = 1e-6,
) -> dict:
    '''
    Batch registration of multiple images to a single reference.

    Args:
        fixed_image_path: Path to reference image
        moving_images_dir: Directory containing images to register
        output_dir: Directory to save results
        transform_type: Type of registration ('rigid', 'affine', 'deformable')
        metric: Similarity metric
        optimizer: Optimization method
        preprocess: Whether to preprocess images
        create_visualizations: Whether to create visualizations
        learning_rate: Learning rate for optimizer
        number_of_iterations: Maximum iterations
        gradient_convergence_tolerance: Convergence tolerance

    Returns:
        Dictionary with batch registration results
    '''
    logger.info(f"Starting batch {transform_type} registration...")

    # Find all image files in the directory
    image_files = []
    for file in os.listdir(moving_images_dir):
        if any(file.endswith(ext) for ext in [".nii", ".nii.gz", ".nrrd", ".mha", ".mhd"]):
            image_files.append(os.path.join(moving_images_dir, file))

    if not image_files:
        raise ValueError(f"No image files found in {moving_images_dir}")

    logger.info(f"Found {len(image_files)} images to register")

    # Create output directory
    os.makedirs(output_dir, exist_ok=True)

    # Process each image
    results = {}
    ImageRegistrationTool()

    for i, moving_image_path in enumerate(image_files):
        logger.info(f"Processing {i + 1}/{len(image_files)}: {os.path.basename(moving_image_path)}")

        # Create individual output directory
        image_name = os.path.splitext(os.path.basename(moving_image_path))[0]
        if image_name.endswith(".nii"):
            image_name = os.path.splitext(image_name)[0]

        individual_output_dir = os.path.join(output_dir, f"registration_{image_name}")

        try:
            if transform_type == "rigid":
                result = quick_rigid_registration(
                    fixed_image_path,
                    moving_image_path,
                    individual_output_dir,
                    metric,
                    optimizer,
                    preprocess,
                    create_visualizations,
                    learning_rate,
                    number_of_iterations,
                    gradient_convergence_tolerance,
                )
            elif transform_type == "affine":
                result = quick_affine_registration(
                    fixed_image_path,
                    moving_image_path,
                    individual_output_dir,
                    metric,
                    optimizer,
                    preprocess,
                    create_visualizations,
                    learning_rate,
                    number_of_iterations,
                    gradient_convergence_tolerance,
                )
            elif transform_type == "deformable":
                result = quick_deformable_registration(
                    fixed_image_path,
                    moving_image_path,
                    individual_output_dir,
                    metric,
                    optimizer,
                    preprocess,
                    create_visualizations,
                    learning_rate,
                    number_of_iterations,
                    gradient_convergence_tolerance,
                )
            else:
                raise ValueError(f"Unknown transform type: {transform_type}")

            results[image_name] = result
            logger.info(f"Successfully registered {image_name}")

        except Exception as e:
            logger.error(f"Failed to register {image_name}: {e}")
            results[image_name] = {"error": str(e)}

    logger.info(f"Batch registration completed. Processed {len(image_files)} images.")
    return results

# Execute the function
try:
    result = batch_register_images(
        fixed_image_path=auto_convert(os.environ.get("PARAM_FIXED_IMAGE_PATH", "")),
        moving_images_dir=auto_convert(os.environ.get("PARAM_MOVING_IMAGES_DIR", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        transform_type=auto_convert(os.environ.get("PARAM_TRANSFORM_TYPE", "rigid")),
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
    "function": "batch_register_images",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("batch_register_images_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("batch_register_images_output.txt", "w") as f:
    f.write("Biomni: Batch Register Images" + NL)
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
        biomni_function: "batch_register_images"
    END_VERSIONS
    """
}

workflow BATCH_REGISTER_IMAGES_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    BATCH_REGISTER_IMAGES(ch_input)

    emit:
    results = BATCH_REGISTER_IMAGES.out.results
    output = BATCH_REGISTER_IMAGES.out.output
    versions = BATCH_REGISTER_IMAGES.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    BATCH_REGISTER_IMAGES_WORKFLOW(ch_input)

    BATCH_REGISTER_IMAGES_WORKFLOW.out.output.view { "Output: $it" }
}
