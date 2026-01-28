#!/usr/bin/env python3
"""
Fix bioimaging stub classes with full self-contained implementations.
Uses single-quoted docstrings to avoid closing Nextflow's script block.
"""

import re
from pathlib import Path

# Full SegmentationTool implementation (using single-quote docstrings)
SEGMENTATION_TOOL_CODE = '''
import logging
import os
import zipfile
import shutil

import nibabel as nib
import numpy as np
import requests

# Optional nnunet import
try:
    from nnunet.inference.predict import predict_from_folder
    NNUNET_AVAILABLE = True
except ImportError:
    predict_from_folder = None
    NNUNET_AVAILABLE = False

# Optional torch import
try:
    import torch
    import torch.serialization
    torch.serialization.add_safe_globals([tuple, list, dict, set, int, float, str, bytes, bytearray])
    torch.serialization.add_safe_globals([complex, slice, range])
    torch.serialization.add_safe_globals([np.core.multiarray.scalar])
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False

logger = logging.getLogger(__name__)


class SegmentationTool:
    \'\'\'Medical image segmentation using nnUNet.\'\'\'

    def __init__(self):
        \'\'\'Initialize the SegmentationTool.\'\'\'
        self.supported_formats = [".nii", ".nii.gz"]
        logger.info("SegmentationTool initialized")

    def split_modalities(self, input_file, output_dir, case_name="BRAT"):
        \'\'\'Split a 4D NIfTI file into separate modality files for nnUNet.\'\'\'
        os.makedirs(output_dir, exist_ok=True)

        print(f"Loading {input_file}...")
        img = nib.load(input_file)
        data = img.get_fdata()

        print(f"Image shape: {data.shape}")
        if len(data.shape) != 4:
            raise ValueError(f"Expected 4D image, got {len(data.shape)}D")
        if data.shape[3] != 4:
            raise ValueError(f"Expected 4 modalities, got {data.shape[3]}")

        modalities = ["FLAIR", "T1w", "t1gd", "T2w"]
        for i, modality in enumerate(modalities):
            modality_data = data[:, :, :, i]
            modality_img = nib.Nifti1Image(modality_data, img.affine, img.header)
            output_file = os.path.join(output_dir, f"{case_name}_{i:04d}.nii.gz")
            nib.save(modality_img, output_file)
            print(f"Saved {modality} to {output_file}")

        return output_dir

    def prepare_input_for_nnunet(self, input_path, output_dir, case_name="BRAT"):
        \'\'\'Prepare input data for nnUNet.\'\'\'
        os.makedirs(output_dir, exist_ok=True)

        if os.path.isfile(input_path):
            if input_path.endswith((".nii", ".nii.gz")):
                try:
                    img = nib.load(input_path)
                    if len(img.shape) == 4 and img.shape[3] == 4:
                        return self.split_modalities(input_path, output_dir, case_name)
                    else:
                        output_file = os.path.join(output_dir, f"{case_name}_0000.nii.gz")
                        shutil.copy2(input_path, output_file)
                        return output_dir
                except Exception as e:
                    raise ValueError(f"Error reading file {input_path}: {e}")
        elif os.path.isdir(input_path):
            files = [f for f in os.listdir(input_path) if f.endswith((".nii", ".nii.gz"))]
            if any(f.endswith("_0000.nii.gz") for f in files):
                for f in files:
                    if f.endswith((".nii", ".nii.gz")):
                        shutil.copy2(os.path.join(input_path, f), os.path.join(output_dir, f))
                return output_dir
            for f in files:
                try:
                    img = nib.load(os.path.join(input_path, f))
                    if len(img.shape) == 4 and img.shape[3] == 4:
                        return self.split_modalities(os.path.join(input_path, f), output_dir, case_name)
                except Exception:
                    continue
            for f in files:
                shutil.copy2(os.path.join(input_path, f), os.path.join(output_dir, f))
            return output_dir

        raise ValueError(f"Input path {input_path} is neither valid file nor directory")

    def setup_nnunet_environment(self, results_folder=None, raw_data_base=None, preprocessed=None):
        \'\'\'Setup nnU-Net environment variables.\'\'\'
        if results_folder:
            os.environ["nnUNet_RESULTS_FOLDER"] = os.path.expanduser(results_folder)
        elif "nnUNet_RESULTS_FOLDER" not in os.environ:
            os.environ["nnUNet_RESULTS_FOLDER"] = os.path.expanduser("~/nnUNet_results")

        if raw_data_base:
            os.environ["nnUNet_raw_data_base"] = os.path.expanduser(raw_data_base)
        elif "nnUNet_raw_data_base" not in os.environ:
            os.environ["nnUNet_raw_data_base"] = os.path.expanduser("~/nnUNet_raw_data_base")

        if preprocessed:
            os.environ["nnUNet_preprocessed"] = os.path.expanduser(preprocessed)
        elif "nnUNet_preprocessed" not in os.environ:
            os.environ["nnUNet_preprocessed"] = os.path.expanduser("~/nnUNet_preprocessed")

        for path in [os.environ["nnUNet_RESULTS_FOLDER"], os.environ["nnUNet_raw_data_base"], os.environ["nnUNet_preprocessed"]]:
            os.makedirs(path, exist_ok=True)

    def _download_model_with_browser_headers(self, url, output_path):
        \'\'\'Download model with browser-like headers.\'\'\'
        headers = {"User-Agent": "Mozilla/5.0", "Accept": "*/*"}
        try:
            response = requests.get(url, headers=headers, stream=True, timeout=300)
            response.raise_for_status()
            with open(output_path, "wb") as f:
                for chunk in response.iter_content(chunk_size=8192):
                    if chunk:
                        f.write(chunk)
            return True
        except Exception as e:
            logger.error(f"Download failed: {e}")
            if os.path.exists(output_path):
                os.remove(output_path)
            return False

    def _download_and_extract_model(self, task_id, model_type="3d_fullres"):
        \'\'\'Download and extract nnUNet model.\'\'\'
        results_folder = os.path.expanduser(os.environ.get("nnUNet_RESULTS_FOLDER", "~/nnUNet_results"))
        nnunet_dir = os.path.join(results_folder, "nnUNet")
        os.makedirs(nnunet_dir, exist_ok=True)

        task_dir = os.path.join(nnunet_dir, model_type, task_id)
        if os.path.exists(task_dir) and os.path.exists(os.path.join(task_dir, "nnUNetTrainerV2__nnUNetPlansv2.1")):
            return True

        download_url = f"https://zenodo.org/record/4003545/files/{task_id}.zip?download=1"
        temp_zip = os.path.join(nnunet_dir, f"{task_id}_temp.zip")

        if self._download_model_with_browser_headers(download_url, temp_zip):
            try:
                with zipfile.ZipFile(temp_zip, "r") as zip_ref:
                    zip_ref.extractall(nnunet_dir)
                os.remove(temp_zip)
                return os.path.exists(task_dir)
            except Exception as e:
                logger.error(f"Extraction failed: {e}")
                if os.path.exists(temp_zip):
                    os.remove(temp_zip)
        return False

    def segment_with_nn_unet(self, image_path, output_dir, task_id, model_type="3d_fullres",
                             folds=None, use_tta=False, num_threads=1, mixed_precision=True,
                             verbose=True, auto_prepare_input=True, results_folder=None, auto_download=True):
        \'\'\'Segment images using nnUNet.\'\'\'
        if not NNUNET_AVAILABLE:
            raise ImportError("nnunet is not installed. Install with: pip install nnunet")
        if folds is None:
            folds = [0, 1, 2, 3, 4]
        os.makedirs(output_dir, exist_ok=True)

        self.setup_nnunet_environment(results_folder=results_folder)

        if auto_prepare_input:
            temp_input_dir = os.path.join(output_dir, "temp_input")
            image_path = self.prepare_input_for_nnunet(image_path, temp_input_dir)

        results_folder = os.environ.get("nnUNet_RESULTS_FOLDER", os.path.expanduser("~/nnUNet_results"))
        model_folder = os.path.join(results_folder, "nnUNet", model_type, task_id, "nnUNetTrainerV2__nnUNetPlansv2.1")

        def check_model_files_exist(mf, fs):
            if not os.path.exists(mf) or not os.path.exists(os.path.join(mf, "plans.pkl")):
                return False
            for fold in fs:
                fold_dir = os.path.join(mf, f"fold_{fold}")
                if os.path.exists(fold_dir) and any(f.endswith((".model", ".model.pkl")) for f in os.listdir(fold_dir)):
                    return True
            return False

        if not check_model_files_exist(model_folder, folds):
            if auto_download:
                if not self._download_and_extract_model(task_id, model_type):
                    raise RuntimeError(f"Failed to download model for {task_id}")
            else:
                raise RuntimeError("Model not found and auto_download disabled")

        if TORCH_AVAILABLE:
            original_torch_load = torch.load
            def patched_torch_load(*args, **kwargs):
                kwargs["weights_only"] = False
                return original_torch_load(*args, **kwargs)
            torch.load = patched_torch_load

        try:
            predict_from_folder(model=model_folder, input_folder=image_path, output_folder=output_dir,
                              folds=folds, save_npz=False, num_threads_preprocessing=num_threads,
                              num_threads_nifti_save=num_threads, mixed_precision=mixed_precision,
                              lowres_segmentations=None, part_id=0, num_parts=1, tta=use_tta)
        finally:
            if TORCH_AVAILABLE:
                torch.load = original_torch_load

        if auto_prepare_input and os.path.exists(os.path.join(output_dir, "temp_input")):
            shutil.rmtree(os.path.join(output_dir, "temp_input"))
        return output_dir

    def create_segmentation_visualization(self, original_mri, segmentation, output_dir="./visualization_output"):
        \'\'\'Create visualization of segmentation results.\'\'\'
        try:
            from nilearn import plotting
            os.makedirs(output_dir, exist_ok=True)
            if not os.path.exists(original_mri) or not os.path.exists(segmentation):
                raise FileNotFoundError("Input files not found")

            saved_files = []
            display = plotting.plot_roi(segmentation, bg_img=original_mri, cmap="Set1", alpha=0.6, title="Segmentation Overlay")
            output_file = os.path.join(output_dir, "segmentation_overlay.png")
            display.savefig(output_file, dpi=150, bbox_inches="tight")
            saved_files.append(output_file)
            display.close()

            for view, mode, name in [("Axial", "z", "axial"), ("Sagittal", "x", "sagittal"), ("Coronal", "y", "coronal")]:
                disp = plotting.plot_roi(segmentation, bg_img=original_mri, cmap="Set1", alpha=0.6,
                                        title=f"Segmentation - {view}", display_mode=mode)
                fp = os.path.join(output_dir, f"segmentation_{name}.png")
                disp.savefig(fp, dpi=150, bbox_inches="tight")
                saved_files.append(fp)
                disp.close()

            return saved_files
        except ImportError:
            return []
        except Exception as e:
            print(f"Visualization failed: {e}")
            return []
'''

# Full ImageRegistrationTool implementation (using single-quote docstrings)
REGISTRATION_TOOL_CODE = '''
import logging
import os
import numpy as np
import SimpleITK as sitk

logger = logging.getLogger(__name__)


class ImageRegistrationTool:
    \'\'\'Medical image registration using SimpleITK.\'\'\'

    def __init__(self):
        \'\'\'Initialize the ImageRegistrationTool.\'\'\'
        self.supported_formats = [".nii", ".nii.gz", ".nrrd", ".mha", ".mhd"]

    def load_image(self, image_path):
        \'\'\'Load a medical image using SimpleITK.\'\'\'
        if not os.path.exists(image_path):
            raise FileNotFoundError(f"Image file not found: {image_path}")
        return sitk.ReadImage(image_path)

    def save_image(self, image, output_path):
        \'\'\'Save a SimpleITK image to file.\'\'\'
        if os.path.isdir(output_path):
            raise ValueError(f"Output path is a directory: {output_path}")
        if not os.path.splitext(output_path)[1]:
            raise ValueError(f"Output path has no extension: {output_path}")
        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        sitk.WriteImage(image, output_path)

    def preprocess_image(self, image, denoise=True, normalize=True):
        \'\'\'Preprocess an image with denoising and normalization.\'\'\'
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
        \'\'\'Create a rigid transform for registration.\'\'\'
        return initial_transform if initial_transform else sitk.Euler3DTransform()

    def create_affine_transform(self, fixed_image, moving_image, initial_transform=None):
        \'\'\'Create an affine transform for registration.\'\'\'
        return initial_transform if initial_transform else sitk.AffineTransform(3)

    def create_deformable_transform(self, fixed_image, moving_image, number_of_control_points=4):
        \'\'\'Create a B-spline deformable transform.\'\'\'
        return sitk.BSplineTransformInitializer(fixed_image, [number_of_control_points] * 3, order=3)

    def setup_registration_method(self, transform, metric="mutual_information", optimizer="gradient_descent",
                                   learning_rate=0.01, number_of_iterations=100, gradient_convergence_tolerance=1e-6):
        \'\'\'Setup the registration method.\'\'\'
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
        \'\'\'Perform image registration.\'\'\'
        final_transform = registration_method.Execute(fixed_image, moving_image)
        resampler = sitk.ResampleImageFilter()
        resampler.SetReferenceImage(fixed_image)
        resampler.SetInterpolator(sitk.sitkLinear)
        resampler.SetDefaultPixelValue(0)
        resampler.SetTransform(final_transform)
        return final_transform, resampler.Execute(moving_image)

    def calculate_similarity_metrics(self, image1, image2):
        \'\'\'Calculate similarity metrics between two images.\'\'\'
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
'''


def fix_segmentation_workflow(file_path: Path):
    """Replace stub SegmentationTool with full implementation."""
    content = file_path.read_text()

    # Find the stub class pattern
    stub_pattern = r'''class SegmentationTool:
    """Stub for SegmentationTool - requires nnU-Net."""
    def __init__\(self\):
        raise NotImplementedError\("SegmentationTool requires nnU-Net and full biomni installation"\)'''

    if re.search(stub_pattern, content):
        # Replace the stub with full implementation
        content = re.sub(stub_pattern, SEGMENTATION_TOOL_CODE.strip(), content)
        file_path.write_text(content)
        print(f"  Fixed: {file_path}")
        return True
    else:
        print(f"  No stub found in: {file_path}")
        return False


def fix_registration_workflow(file_path: Path):
    """Replace stub ImageRegistrationTool with full implementation."""
    content = file_path.read_text()

    # Find the stub class pattern (multiple variations)
    stub_patterns = [
        r'''class ImageRegistrationTool:
    """Stub for ImageRegistrationTool - requires SimpleITK."""
    def __init__\(self\):
        raise NotImplementedError\("ImageRegistrationTool requires SimpleITK and full biomni installation"\)
    def load_image\(self, path\):
        pass
    def calculate_similarity_metrics\(self, img1, img2\):
        return \{"error": "ImageRegistrationTool not available"\}''',
        r'''class ImageRegistrationTool:
    """Stub for ImageRegistrationTool - requires SimpleITK."""
    def __init__\(self\):
        raise NotImplementedError\("ImageRegistrationTool requires SimpleITK and full biomni installation"\)'''
    ]

    for stub_pattern in stub_patterns:
        if re.search(stub_pattern, content):
            content = re.sub(stub_pattern, REGISTRATION_TOOL_CODE.strip(), content)
            file_path.write_text(content)
            print(f"  Fixed: {file_path}")
            return True

    print(f"  No stub found in: {file_path}")
    return False


def main():
    # First restore original files from git
    import subprocess
    print("Restoring original files from git...")
    for wf in ['segment_with_nn_unet', 'split_modalities', 'prepare_input_for_nnunet',
               'create_segmentation_visualization', 'batch_register_images',
               'calculate_similarity_metrics', 'preprocess_image',
               'quick_affine_registration', 'quick_deformable_registration',
               'quick_rigid_registration']:
        path = f'subworkflows/bioimaging/{wf}/main.nf'
        subprocess.run(['git', 'checkout', path], capture_output=True)

    base_dir = Path('subworkflows/bioimaging')

    # Segmentation workflows
    segmentation_workflows = [
        'segment_with_nn_unet',
        'split_modalities',
        'prepare_input_for_nnunet',
        'create_segmentation_visualization',
    ]

    # Registration workflows
    registration_workflows = [
        'batch_register_images',
        'calculate_similarity_metrics',
        'preprocess_image',
        'quick_affine_registration',
        'quick_deformable_registration',
        'quick_rigid_registration',
    ]

    print("\nFixing Segmentation Tool workflows:")
    for wf_name in segmentation_workflows:
        wf_path = base_dir / wf_name / 'main.nf'
        if wf_path.exists():
            fix_segmentation_workflow(wf_path)
        else:
            print(f"  Not found: {wf_path}")

    print("\nFixing Image Registration Tool workflows:")
    for wf_name in registration_workflows:
        wf_path = base_dir / wf_name / 'main.nf'
        if wf_path.exists():
            fix_registration_workflow(wf_path)
        else:
            print(f"  Not found: {wf_path}")


if __name__ == '__main__':
    main()
