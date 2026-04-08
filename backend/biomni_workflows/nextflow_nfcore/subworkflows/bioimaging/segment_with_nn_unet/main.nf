#!/usr/bin/env nextflow
/*
 * bioimaging/segment_with_nn_unet
 * Segment images using nnUNet with proper environment setup and automatic model downloading
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: Mock brain NIFTI from test data
params.image_path = "${projectDir}/../../../test_data/mock_fixed_image.nii.gz"
params.output_dir = null
params.task_id = null
params.model_type = null
params.folds = null
params.use_tta = null
params.num_threads = null
params.mixed_precision = null
params.verbose = null
params.auto_prepare_input = null
params.results_folder = null

process SEGMENT_WITH_NN_UNET {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("segment_with_nn_unet_results.json"), emit: results
    tuple val(meta), path("segment_with_nn_unet_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
        # Export parameters as environment variables
    export PARAM_IMAGE_PATH="${params.image_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_TASK_ID="${params.task_id?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FOLDS="${params.folds?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_USE_TTA="${params.use_tta?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_THREADS="${params.num_threads?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MIXED_PRECISION="${params.mixed_precision?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_VERBOSE="${params.verbose?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_AUTO_PREPARE_INPUT="${params.auto_prepare_input?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_RESULTS_FOLDER="${params.results_folder?.toString()?.replace('"', '\\"') ?: 'null'}"


    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation

import json
import os


import logging
import os
import zipfile
import shutil

import nibabel as nib
import numpy as np
import requests

# Optional nnunetv2 import (nnunetv2 is installed, not the old nnunet)
try:
    from nnunetv2.inference.predict_from_raw_data import nnUNetPredictor
    NNUNET_AVAILABLE = True
except ImportError:
    nnUNetPredictor = None
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
    '''Medical image segmentation using nnUNet.'''

    def __init__(self):
        '''Initialize the SegmentationTool.'''
        self.supported_formats = [".nii", ".nii.gz"]
        logger.info("SegmentationTool initialized")

    def split_modalities(self, input_file, output_dir, case_name="BRAT"):
        '''Split a 4D NIfTI file into separate modality files for nnUNet.'''
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
        '''Prepare input data for nnUNet.'''
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
        '''Setup nnU-Net v2 environment variables.'''
        # nnunetv2 uses different env var names
        if results_folder:
            os.environ["nnUNet_results"] = os.path.expanduser(results_folder)
        elif "nnUNet_results" not in os.environ:
            os.environ["nnUNet_results"] = os.path.expanduser("~/nnUNet_results")

        if raw_data_base:
            os.environ["nnUNet_raw"] = os.path.expanduser(raw_data_base)
        elif "nnUNet_raw" not in os.environ:
            os.environ["nnUNet_raw"] = os.path.expanduser("~/nnUNet_raw")

        if preprocessed:
            os.environ["nnUNet_preprocessed"] = os.path.expanduser(preprocessed)
        elif "nnUNet_preprocessed" not in os.environ:
            os.environ["nnUNet_preprocessed"] = os.path.expanduser("~/nnUNet_preprocessed")

        for path in [os.environ["nnUNet_results"], os.environ["nnUNet_raw"], os.environ["nnUNet_preprocessed"]]:
            os.makedirs(path, exist_ok=True)

    def _download_model_with_browser_headers(self, url, output_path):
        '''Download model with browser-like headers.'''
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
        '''Download and extract nnUNet model.'''
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
        '''Segment images using nnUNet (nnunetv2 API).'''
        if not NNUNET_AVAILABLE:
            raise ImportError("nnunetv2 is not installed. Install with: pip install nnunetv2")
        if folds is None:
            folds = (0, 1, 2, 3, 4)  # nnunetv2 expects tuple
        os.makedirs(output_dir, exist_ok=True)

        self.setup_nnunet_environment(results_folder=results_folder)

        if auto_prepare_input:
            temp_input_dir = os.path.join(output_dir, "temp_input")
            image_path = self.prepare_input_for_nnunet(image_path, temp_input_dir)

        results_folder = os.environ.get("nnUNet_results", os.path.expanduser("~/nnUNet_results"))
        # nnunetv2 uses different folder structure: Dataset{XXX}_{name}/nnUNetTrainer__nnUNetPlans__{config}
        model_folder = os.path.join(results_folder, task_id, f"nnUNetTrainer__nnUNetPlans__{model_type}")

        def check_model_files_exist(mf, fs):
            # nnunetv2 model structure check
            if not os.path.exists(mf):
                return False
            # Check for checkpoint files
            for fold in fs:
                fold_dir = os.path.join(mf, f"fold_{fold}")
                if os.path.exists(fold_dir):
                    if any(f.endswith((".pth", "checkpoint_final.pth")) for f in os.listdir(fold_dir)):
                        return True
            return False

        if not check_model_files_exist(model_folder, folds):
            if auto_download:
                if not self._download_and_extract_model(task_id, model_type):
                    raise RuntimeError(f"Failed to download model for {task_id}. "
                                     f"Model folder not found at: {model_folder}")
            else:
                raise RuntimeError(f"Model not found at {model_folder} and auto_download disabled")

        if TORCH_AVAILABLE:
            original_torch_load = torch.load
            def patched_torch_load(*args, **kwargs):
                kwargs["weights_only"] = False
                return original_torch_load(*args, **kwargs)
            torch.load = patched_torch_load

        try:
            # Use nnunetv2 API
            predictor = nnUNetPredictor(
                tile_step_size=0.5,
                use_gaussian=True,
                use_mirroring=use_tta,
                perform_everything_on_device=True,
                device=torch.device('cuda' if torch.cuda.is_available() else 'cpu') if TORCH_AVAILABLE else None,
                verbose=verbose,
                verbose_preprocessing=verbose,
                allow_tqdm=verbose
            )

            # Initialize from trained model folder
            predictor.initialize_from_trained_model_folder(
                model_training_output_dir=model_folder,
                use_folds=folds,
                checkpoint_name='checkpoint_final.pth'
            )

            # Run prediction
            predictor.predict_from_files(
                list_of_lists_or_source_folder=image_path,
                output_folder_or_list_of_truncated_output_files=output_dir,
                save_probabilities=False,
                overwrite=True,
                num_processes_preprocessing=num_threads,
                num_processes_segmentation_export=num_threads,
                folder_with_segs_from_prev_stage=None,
                num_parts=1,
                part_id=0
            )
        finally:
            if TORCH_AVAILABLE:
                torch.load = original_torch_load

        if auto_prepare_input and os.path.exists(os.path.join(output_dir, "temp_input")):
            shutil.rmtree(os.path.join(output_dir, "temp_input"))
        return output_dir

    def create_segmentation_visualization(self, original_mri, segmentation, output_dir="./visualization_output"):
        '''Create visualization of segmentation results.'''
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



def segment_with_nn_unet(
    image_path,
    output_dir,
    task_id,
    model_type="3d_fullres",
    folds=None,
    use_tta=False,
    num_threads=1,
    mixed_precision=True,
    verbose=True,
    auto_prepare_input=True,
    results_folder=None,
):
    '''Convenience function for nnUNet segmentation.

    If task_id is None, runs in demo mode to verify nnunetv2 is installed
    and input preparation works.
    '''
    tool = SegmentationTool()

    # Demo mode: verify setup without requiring a trained model
    if task_id is None:
        result = {
            "status": "demo_mode",
            "nnunetv2_available": NNUNET_AVAILABLE,
            "torch_available": TORCH_AVAILABLE,
            "image_path": image_path,
        }

        # Verify input image can be loaded
        if image_path and os.path.exists(image_path):
            try:
                img = nib.load(image_path)
                result["input_shape"] = list(img.shape)
                result["input_affine"] = img.affine.tolist()
                result["input_loaded"] = True

                # Test input preparation
                if output_dir:
                    os.makedirs(output_dir, exist_ok=True)
                    temp_input_dir = os.path.join(output_dir, "demo_prepared_input")
                    prepared_dir = tool.prepare_input_for_nnunet(image_path, temp_input_dir, case_name="DEMO")
                    result["prepared_input_dir"] = prepared_dir
                    prepared_files = os.listdir(prepared_dir)
                    result["prepared_files"] = prepared_files
            except Exception as e:
                result["input_error"] = str(e)
                result["input_loaded"] = False
        else:
            result["input_loaded"] = False
            result["input_error"] = f"Image not found: {image_path}"

        return result

    # Real segmentation mode
    return tool.segment_with_nn_unet(
        image_path,
        output_dir,
        task_id,
        model_type,
        folds,
        use_tta,
        num_threads,
        mixed_precision,
        verbose,
        auto_prepare_input,
        results_folder,
    )

# Execute the function
try:
    result = segment_with_nn_unet(
        image_path=auto_convert(os.environ.get("PARAM_IMAGE_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        task_id=auto_convert(os.environ.get("PARAM_TASK_ID", "")),
        model_type=auto_convert(os.environ.get("PARAM_MODEL_TYPE", "")),
        folds=auto_convert(os.environ.get("PARAM_FOLDS", "")),
        use_tta=auto_convert(os.environ.get("PARAM_USE_TTA", "")),
        num_threads=auto_convert(os.environ.get("PARAM_NUM_THREADS", "")),
        mixed_precision=auto_convert(os.environ.get("PARAM_MIXED_PRECISION", "")),
        verbose=auto_convert(os.environ.get("PARAM_VERBOSE", "")),
        auto_prepare_input=auto_convert(os.environ.get("PARAM_AUTO_PREPARE_INPUT", "")),
        results_folder=auto_convert(os.environ.get("PARAM_RESULTS_FOLDER", "")),
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
    "function": "segment_with_nn_unet",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("segment_with_nn_unet_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("segment_with_nn_unet_output.txt", "w") as f:
    f.write("Biomni: Segment With Nn Unet" + NL)
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
        biomni_function: "segment_with_nn_unet"
    END_VERSIONS
    """
}

workflow SEGMENT_WITH_NN_UNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    SEGMENT_WITH_NN_UNET(ch_input)

    emit:
    results = SEGMENT_WITH_NN_UNET.out.results
    output = SEGMENT_WITH_NN_UNET.out.output
    versions = SEGMENT_WITH_NN_UNET.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    SEGMENT_WITH_NN_UNET_WORKFLOW(ch_input)

    SEGMENT_WITH_NN_UNET_WORKFLOW.out.output.view { "Output: $it" }
}
