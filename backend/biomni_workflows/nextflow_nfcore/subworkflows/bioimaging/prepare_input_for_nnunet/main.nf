#!/usr/bin/env nextflow
/*
 * bioimaging/prepare_input_for_nnunet
 * Prepare input data for nnUNet by handling both 4D and pre-split modality files
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Test with mock 4D brain image
params.input_path = "${projectDir}/../../../test_data/mock_4d_brain.nii.gz"
params.output_dir = './results'
params.case_name = 'BRAT'

process PREPARE_INPUT_FOR_NNUNET {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("prepare_input_for_nnunet_results.json"), emit: results
    tuple val(meta), path("prepare_input_for_nnunet_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_INPUT_PATH="${params.input_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_DIR="${params.output_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CASE_NAME="${params.case_name?.toString()?.replace('"', '\\"') ?: 'null'}"

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
        '''Setup nnU-Net environment variables.'''
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
        '''Segment images using nnUNet.'''
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



def prepare_input_for_nnunet(input_path, output_dir, case_name="BRAT"):
    '''Convenience function for preparing nnUNet input'''
    tool = SegmentationTool()
    return tool.prepare_input_for_nnunet(input_path, output_dir, case_name)

# Execute the function
try:
    result = prepare_input_for_nnunet(
        input_path=auto_convert(os.environ.get("PARAM_INPUT_PATH", "")),
        output_dir=auto_convert(os.environ.get("PARAM_OUTPUT_DIR", "")),
        case_name=auto_convert(os.environ.get("PARAM_CASE_NAME", "BRAT")),
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
    "function": "prepare_input_for_nnunet",
    "domain": "bioimaging",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("prepare_input_for_nnunet_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("prepare_input_for_nnunet_output.txt", "w") as f:
    f.write("Biomni: Prepare Input For Nnunet" + NL)
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
        biomni_function: "prepare_input_for_nnunet"
    END_VERSIONS
    """
}

workflow PREPARE_INPUT_FOR_NNUNET_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    PREPARE_INPUT_FOR_NNUNET(ch_input)

    emit:
    results = PREPARE_INPUT_FOR_NNUNET.out.results
    output = PREPARE_INPUT_FOR_NNUNET.out.output
    versions = PREPARE_INPUT_FOR_NNUNET.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    PREPARE_INPUT_FOR_NNUNET_WORKFLOW(ch_input)

    PREPARE_INPUT_FOR_NNUNET_WORKFLOW.out.output.view { "Output: $it" }
}
