#!/usr/bin/env nextflow
/*
 * genomics/generate_embeddings_with_state
 * Generate State embeddings for single-cell RNA-seq data using the SE-600M model.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PBMC 3k single-cell dataset from Galaxy test data
params.adata_filename = '/home/yzhang/biomate/backend/lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad'
params.data_dir = null
params.model_folder = null
params.output_filename = null
params.checkpoint = null
params.embed_key = 'X_state'
params.protein_embeddings = null
params.batch_size = '500'

process GENERATE_EMBEDDINGS_WITH_STATE {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("generate_embeddings_with_state_results.json"), emit: results
    tuple val(meta), path("generate_embeddings_with_state_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ADATA_FILENAME="${params.adata_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_DIR="${params.data_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_FOLDER="${params.model_folder?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILENAME="${params.output_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CHECKPOINT="${params.checkpoint?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EMBED_KEY="${params.embed_key?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PROTEIN_EMBEDDINGS="${params.protein_embeddings?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BATCH_SIZE="${params.batch_size?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import scanpy as sc
import os
import torch
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



def generate_embeddings_with_state(
    adata_filename,
    data_dir,
    model_folder,
    output_filename=None,
    checkpoint=None,
    embed_key="X_state",
    protein_embeddings=None,
    batch_size=500,
):
    '''
    Generate State embeddings for single-cell RNA-seq data using the SE-600M model.

    This function downloads the SE-600M model from Hugging Face, installs required dependencies,
    and generates embeddings for the input AnnData object.

    Parameters:
    -----------
    adata_filename : str
        Name of the input AnnData file (.h5ad format)
    data_dir : str
        Directory containing the input data file
    model_folder : str
        Directory where the SE-600M model will be downloaded and stored
    output_filename : str, optional
        Name of the output file. If None, will use input filename with '_state_embeddings' suffix
    checkpoint : str, optional
        Path to the specific model checkpoint. If None, uses the latest checkpoint in model_folder
    embed_key : str, default="X_state"
        Name of key to store embeddings in the output AnnData object
    protein_embeddings : str, optional
        Path to protein embeddings override (.pt). If omitted, auto-detects in model folder
    batch_size : int, default=500
        Batch size for embedding forward pass. Increase to use more VRAM and speed up embedding

    Returns:
    --------
    str
        Research log summarizing the steps performed and results

    Notes:
    ------
    - Requires 10GB+ GPU memory for model loading
    - Downloads ~25GB model files from Hugging Face
    - Installs git-lfs, uv, and arc-state if not already available
    - Validates input h5ad file format (CSR matrix and gene_name column)
    - Provides real-time streaming output for git clone and embedding generation
    - Includes automatic retry with reduced batch size on failure
    '''
    import os
    import subprocess

    # Initialize steps list for logging
    steps = []

    # Set up paths
    input_path = os.path.join(data_dir, adata_filename)
    if output_filename is None:
        base_name = os.path.splitext(adata_filename)[0]
        output_filename = f"{base_name}_state_embeddings.h5ad"

    output_path = os.path.join(data_dir, "output", output_filename)

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    steps.append(f"Created output directory: {os.path.dirname(output_path)}")

    # Validate h5ad file format
    steps.append("Validating h5ad file format...")
    try:
        import scanpy as sc

        adata = sc.read_h5ad(input_path)

        import warnings

        if not hasattr(adata.X, "indices"):
            warning_msg = (
                "Input data is not in CSR (Compressed Sparse Row) matrix format. Proceeding, but this may cause issues."
            )
            warnings.warn(warning_msg, stacklevel=2)
            steps.append(f"Warning: {warning_msg}")

        if "gene_name" not in adata.var.columns:
            warning_msg = (
                "'gene_name' column is not present in the var dataframe. Proceeding, but this may cause issues."
            )
            warnings.warn(warning_msg, stacklevel=2)
            steps.append(f"Warning: {warning_msg}")

        steps.append(f"  - Matrix format: {type(adata.X).__name__}")
        steps.append(f"  - Number of cells: {adata.n_obs}")
        steps.append(f"  - Number of genes: {adata.n_vars}")
        steps.append(f"  - Gene names available: {'gene_name' in adata.var.columns}")

    except Exception as e:
        error_msg = f"h5ad file validation failed: {e}"
        steps.append(error_msg)
        raise ValueError(error_msg) from e

    # Check if git-lfs is installed
    steps.append("Checking if git-lfs is installed...")
    try:
        subprocess.run(["git", "lfs", "version"], check=True, capture_output=True)
        steps.append("git-lfs is available")
    except (subprocess.CalledProcessError, FileNotFoundError) as e:
        error_msg = (
            "git-lfs is not installed or not found in PATH. "
            "Please install git-lfs before running this function.\\n"
            "Run the following command with root privileges:\\n"
            "sudo apt-get install git-lfs\\n"
            "git lfs install"
        )
        steps.append(error_msg)
        raise RuntimeError(error_msg) from e

    steps.append("Downloading SE-600M model...")

    # Check if model weights actually exist (not just the directory)
    model_exists = False
    if os.path.exists(model_folder):
        # Check for SE-600M specific checkpoint files
        checkpoint_indicators = ["se600m_epoch16.ckpt", "se600m_epoch4.ckpt", "model.safetensors", "config.yaml"]
        model_exists = any(os.path.exists(os.path.join(model_folder, indicator)) for indicator in checkpoint_indicators)

    if not model_exists:
        os.makedirs(model_folder, exist_ok=True)
        steps.append(f"Created model directory: {model_folder}")
        try:
            steps.append(f"Cloning SE-600M model to {model_folder}")
            steps.append("This may take a while and final model weights are approx 25GB!...")
            process = subprocess.Popen(
                ["git", "clone", "https://huggingface.co/arcinstitute/SE-600M", model_folder],
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                universal_newlines=True,
            )

            for line in iter(process.stdout.readline, ""):
                line = line.rstrip()
                print(line)
                steps.append(line)

            process.wait()

            if process.returncode != 0:
                raise subprocess.CalledProcessError(
                    process.returncode, ["git", "clone", "https://huggingface.co/arcinstitute/SE-600M", model_folder]
                )
            steps.append("SE-600M model downloaded successfully")
        except subprocess.CalledProcessError as e:
            error_msg = f"Error downloading model: {e}"
            steps.append(error_msg)
            raise
    else:
        steps.append(f"Model already downloaded: {model_folder}")

    steps.append("Generating embeddings...")

    if torch.cuda.is_available():
        device_name = torch.cuda.get_device_name(0)
        gpu_memory = torch.cuda.get_device_properties(0).total_memory / (1024**3)
        current_device = torch.cuda.current_device()
        steps.append(f"✓ GPU detected: {device_name}")
        steps.append(f"✓ GPU memory: {gpu_memory:.1f} GB")
        steps.append(f"✓ Current CUDA device: {current_device}")
        if gpu_memory < 10:
            warning_msg = f"⚠️  WARNING: GPU has only {gpu_memory:.1f} GB memory. SE600 model requires 10GB+ GPU memory."
            steps.append(warning_msg)
    else:
        steps.append("⚠️  WARNING: No GPU detected! This will run on CPU and be very slow.")
        steps.append("⚠️  SE600 model requires 10GB+ GPU memory for optimal performance.")

    cuda_visible = os.environ.get("CUDA_VISIBLE_DEVICES", "Not set")
    steps.append(f"CUDA_VISIBLE_DEVICES: {cuda_visible}")

    steps.append(f"PyTorch CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        steps.append(f"PyTorch CUDA device count: {torch.cuda.device_count()}")
        steps.append(f"PyTorch current device: {torch.cuda.current_device()}")

    steps.append("embedding data can take a while...")
    max_retries = 3
    retries = 0
    last_exception = None

    while retries <= max_retries:
        try:
            cmd = [
                "uv",
                "run",
                "state",
                "emb",
                "transform",
                "--model-folder",
                model_folder,
                "--input",
                input_path,
                "--output",
                output_path,
            ]

            if checkpoint:
                cmd.extend(["--checkpoint", checkpoint])
            if embed_key != "X_state":
                cmd.extend(["--embed-key", embed_key])
            if protein_embeddings:
                cmd.extend(["--protein-embeddings", protein_embeddings])
            if batch_size:
                cmd.extend(["--batch-size", str(batch_size)])

            steps.append(f"Running command: {' '.join(cmd)}")
            process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, universal_newlines=True
            )

            for line in iter(process.stdout.readline, ""):
                line = line.rstrip()
                print(line)  # Print to console first
                steps.append(line)  # Then add to steps list

            process.wait()

            if process.returncode != 0:
                raise subprocess.CalledProcessError(process.returncode, cmd)

            steps.append("Embeddings generated successfully!")
            steps.append("Output Format and Location:")
            steps.append("  Output format: .h5ad (AnnData format)")
            steps.append("  Embeddings stored in: X_state layer (by default)")
            steps.append("  Location: Specified by --output parameter")
            steps.append(f"  In your code: Saved to {output_path}")
            steps.append("")
            return "\\n".join(steps)

        except subprocess.CalledProcessError as e:
            error_msg = f"Error generating embeddings (attempt {retries + 1}): {e}"
            steps.append(error_msg)
            last_exception = e
            if batch_size and retries < max_retries:
                batch_size = max(1, batch_size // 2)
                steps.append(f"Retrying with reduced batch size: {batch_size}")
                retries += 1
            else:
                break

    steps.append("Failed to generate embeddings after multiple attempts.")
    if last_exception:
        steps.append(f"Last exception: {last_exception}")
        raise last_exception

    return "\\n".join(steps)

# Execute the function
try:
    result = generate_embeddings_with_state(
        adata_filename=auto_convert(os.environ.get("PARAM_ADATA_FILENAME", "")),
        data_dir=auto_convert(os.environ.get("PARAM_DATA_DIR", "")),
        model_folder=auto_convert(os.environ.get("PARAM_MODEL_FOLDER", "")),
        output_filename=auto_convert(os.environ.get("PARAM_OUTPUT_FILENAME", "")),
        checkpoint=auto_convert(os.environ.get("PARAM_CHECKPOINT", "")),
        embed_key=auto_convert(os.environ.get("PARAM_EMBED_KEY", "X_state")),
        protein_embeddings=auto_convert(os.environ.get("PARAM_PROTEIN_EMBEDDINGS", "")),
        batch_size=auto_convert(os.environ.get("PARAM_BATCH_SIZE", "500")),
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
    "function": "generate_embeddings_with_state",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("generate_embeddings_with_state_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("generate_embeddings_with_state_output.txt", "w") as f:
    f.write("Biomni: Generate Embeddings With State" + NL)
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
        biomni_function: "generate_embeddings_with_state"
    END_VERSIONS
    """
}

workflow GENERATE_EMBEDDINGS_WITH_STATE_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GENERATE_EMBEDDINGS_WITH_STATE(ch_input)

    emit:
    results = GENERATE_EMBEDDINGS_WITH_STATE.out.results
    output = GENERATE_EMBEDDINGS_WITH_STATE.out.output
    versions = GENERATE_EMBEDDINGS_WITH_STATE.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GENERATE_EMBEDDINGS_WITH_STATE_WORKFLOW(ch_input)

    GENERATE_EMBEDDINGS_WITH_STATE_WORKFLOW.out.output.view { "Output: $it" }
}
