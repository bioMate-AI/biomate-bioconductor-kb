#!/usr/bin/env nextflow
/*
 * bioimaging/calculate_similarity_metrics
 * Calculate similarity metrics between two images.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Compare fixed and moving images from test data
params.image1_path = "${projectDir}/../../../test_data/mock_fixed_image.nii.gz"
params.image2_path = "${projectDir}/../../../test_data/mock_moving_image.nii.gz"

process CALCULATE_SIMILARITY_METRICS {
    tag { meta.id }
    label 'process_medium'
    publishDir { "${params.outdir}/${meta.id}" }, mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') == 'true' ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("calculate_similarity_metrics_results.json"), emit: results
    tuple val(meta), path("calculate_similarity_metrics_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_IMAGE1_PATH="${params.image1_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_IMAGE2_PATH="${params.image2_path?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os


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



def calculate_similarity_metrics(image1_path: str, image2_path: str) -> dict[str, float]:
    '''
    Calculate similarity metrics between two images.

    Args:
        image1_path: Path to first image
        image2_path: Path to second image

    Returns:
        Dictionary of similarity metrics
    '''
    tool = ImageRegistrationTool()
    image1 = tool.load_image(image1_path)
    image2 = tool.load_image(image2_path)
    return tool.calculate_similarity_metrics(image1, image2)

# Execute the function
try:
    result = calculate_similarity_metrics(
        image1_path=auto_convert(os.environ.get("PARAM_IMAGE1_PATH", "")),
        image2_path=auto_convert(os.environ.get("PARAM_IMAGE2_PATH", "")),
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
    "function": "calculate_similarity_metrics",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("calculate_similarity_metrics_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("calculate_similarity_metrics_output.txt", "w") as f:
    f.write("Biomni: Calculate Similarity Metrics" + NL)
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
        biomni_function: "calculate_similarity_metrics"
    END_VERSIONS
    """
}

workflow CALCULATE_SIMILARITY_METRICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    CALCULATE_SIMILARITY_METRICS(ch_input)

    emit:
    results = CALCULATE_SIMILARITY_METRICS.out.results
    output = CALCULATE_SIMILARITY_METRICS.out.output
    versions = CALCULATE_SIMILARITY_METRICS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    CALCULATE_SIMILARITY_METRICS_WORKFLOW(ch_input)

    CALCULATE_SIMILARITY_METRICS_WORKFLOW.out.output.view { "Output: $it" }
}
