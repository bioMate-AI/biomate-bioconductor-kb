#!/usr/bin/env nextflow
/*
 * genomics/generate_transcriptformer_embeddings
 * Generate Transcriptformer embeddings for single-cell RNA-seq data.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
// Demo: PBMC 3k single-cell dataset from Galaxy test data
params.adata_filename = "${projectDir}/../../../../lib/galaxy/datatypes/test/pbmc3k_tiny.h5ad"
params.data_dir = null
params.output_filename = null
params.model_type = 'tf-sapiens'
params.checkpoint_path = null
params.batch_size = 8
params.precision = '16-mixed'
params.clip_counts = 30
params.embedding_layer_index = null
params.num_gpus = 1
params.n_data_workers = 0
params.gene_col_name = 'ensembl_id'
params.pretrained_embedding = null
params.filter_to_vocabs = null
params.use_raw = 'None'
params.emb_type = 'cell'
params.remove_duplicate_genes = null
params.oom_dataloader = null

process GENERATE_TRANSCRIPTFORMER_EMBEDDINGS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("generate_transcriptformer_embeddings_results.json"), emit: results
    tuple val(meta), path("generate_transcriptformer_embeddings_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ADATA_FILENAME="${params.adata_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_DATA_DIR="${params.data_dir?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OUTPUT_FILENAME="${params.output_filename?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_TYPE="${params.model_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CHECKPOINT_PATH="${params.checkpoint_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BATCH_SIZE="${params.batch_size?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PRECISION="${params.precision?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_CLIP_COUNTS="${params.clip_counts?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EMBEDDING_LAYER_INDEX="${params.embedding_layer_index?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_NUM_GPUS="${params.num_gpus?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_N_DATA_WORKERS="${params.n_data_workers?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_GENE_COL_NAME="${params.gene_col_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_PRETRAINED_EMBEDDING="${params.pretrained_embedding?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_FILTER_TO_VOCABS="${params.filter_to_vocabs?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_USE_RAW="${params.use_raw?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_EMB_TYPE="${params.emb_type?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_REMOVE_DUPLICATE_GENES="${params.remove_duplicate_genes?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_OOM_DATALOADER="${params.oom_dataloader?.toString()?.replace('"', '\\"') ?: 'null'}"

    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import scanpy as sc
import pandas as pd
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



def generate_transcriptformer_embeddings(
    adata_filename: str,
    data_dir: str,
    output_filename: str = None,
    model_type: str = "tf-sapiens",
    checkpoint_path: str = None,
    batch_size: int = 8,
    precision: str = "16-mixed",
    clip_counts: int = 30,
    embedding_layer_index: int = -1,
    num_gpus: int = 1,
    n_data_workers: int = 0,
    gene_col_name: str = "ensembl_id",
    pretrained_embedding: str = None,
    filter_to_vocabs: bool = True,
    use_raw: str = "None",
    emb_type: str = "cell",
    remove_duplicate_genes: bool = False,
    oom_dataloader: bool = False,
) -> str:
    '''
    Generate Transcriptformer embeddings for single-cell RNA-seq data.

    Parameters:
    -----------
    adata_filename : str
        Name of the input AnnData file (.h5ad format)
    data_dir : str
        Directory containing the input data file
    output_filename : str, optional
        Name of the output embeddings file. If None, will use input filename with '_transcriptformer_embeddings' suffix
    model_type : str, optional
        Type of transcriptformer model to download and use. Options: "tf-sapiens", "tf-exemplar", "tf-metazoa" (default: "tf-sapiens")
    checkpoint_path : str, optional
        Path to the transcriptformer checkpoint directory. If None, will use "./checkpoints/{model_type}" (default: None)
    batch_size : int, optional
        Batch size for inference (default: 8)
    precision : str, optional
        Precision for inference. Options: "16-mixed", "32" (default: "16-mixed")
    clip_counts : int, optional
        Maximum count value to clip to (default: 30)
    embedding_layer_index : int, optional
        Which layer to extract embeddings from (default: -1, last layer)
    num_gpus : int, optional
        Number of GPUs to use (default: 1)
    n_data_workers : int, optional
        Number of data loading workers (default: 0)
    gene_col_name : str, optional
        Column name in AnnData.var containing gene identifiers (default: "ensembl_id")
    pretrained_embedding : str, optional
        Path to pretrained embeddings for out-of-distribution species (default: None)
    filter_to_vocabs : bool, optional
        Whether to filter genes to only those in the vocabulary (default: True)
    use_raw : str, optional
        Whether to use raw counts from AnnData.raw.X (True), adata.X (False), or auto-detect (None/auto) (default: "None")
    emb_type : str, optional
        Type of embeddings to extract: 'cell' for mean-pooled cell embeddings or 'cge' for contextual gene embeddings (default: "cell")
    remove_duplicate_genes : bool, optional
        Remove duplicate genes if found instead of raising an error (default: False)
    oom_dataloader : bool, optional
        Use map-style out-of-memory DataLoader (DistributedSampler-friendly) (default: False)
    Returns:
    --------
    str
        Path to the generated embeddings file
    '''
    import os
    import subprocess

    import pandas as pd
    import scanpy as sc
    import torch

    if checkpoint_path is None:
        checkpoint_path = f"./checkpoints/{model_type}"

    input_path = os.path.join(data_dir, adata_filename)
    if output_filename is None:
        base_name = os.path.splitext(adata_filename)[0]
        output_filename = f"{base_name}_transcriptformer_embeddings.h5ad"

    output_path = os.path.join(data_dir, "output", output_filename)
    temp_data_path = os.path.join(data_dir, "temp_transcriptformer_input.h5ad")

    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    print("Checking GPU availability...")
    if torch.cuda.is_available():
        device_name = torch.cuda.get_device_name(0)
        gpu_memory = torch.cuda.get_device_properties(0).total_memory / (1024**3)
        current_device = torch.cuda.current_device()
        print(f"✓ GPU detected: {device_name}")
        print(f"✓ GPU memory: {gpu_memory:.1f} GB")
        print(f"✓ Current CUDA device: {current_device}")
    else:
        print("⚠️  WARNING: No GPU detected! This will run on CPU and be very slow.")
        print("⚠️  Transcriptformer requires GPU for optimal performance.")

    import os

    cuda_visible = os.environ.get("CUDA_VISIBLE_DEVICES", "Not set")
    print(f"CUDA_VISIBLE_DEVICES: {cuda_visible}")

    print(f"PyTorch CUDA available: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"PyTorch CUDA device count: {torch.cuda.device_count()}")
        print(f"PyTorch current device: {torch.cuda.current_device()}")

    try:
        os.makedirs(checkpoint_path, exist_ok=True)

        def is_model_downloaded(checkpoint_path, model_type):
            '''Check if model is already downloaded by looking for key files'''
            required_files = [
                "config.yaml",
                "pytorch_model.bin",
            ]

            for file_name in required_files:
                file_path = os.path.join(checkpoint_path, file_name)
                if not os.path.exists(file_path):
                    return False

            return True

        if is_model_downloaded(checkpoint_path, model_type):
            print(f"✓ Model checkpoints for {model_type} already exist at: {checkpoint_path}")
            print("✓ Skipping download...")
        else:
            print(f"Downloading transcriptformer model checkpoints for {model_type}...")
            print("This may take a while and model checkpoints are several GB!...")
            print(f"Model will be saved to: {checkpoint_path}")

            try:
                process = subprocess.Popen(
                    ["transcriptformer", "download", model_type],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    universal_newlines=True,
                )

                for line in iter(process.stdout.readline, ""):
                    print(line.rstrip())

                process.wait()

                if process.returncode != 0:
                    raise subprocess.CalledProcessError(
                        process.returncode, ["transcriptformer", "download", model_type]
                    )
                print(f"✓ Model checkpoints for {model_type} downloaded successfully")
            except subprocess.CalledProcessError as e:
                print(f"Error downloading model checkpoints: {e}")
                raise

        print("Loading and preparing AnnData object...")
        try:
            adata = sc.read_h5ad(input_path)
            print(f"✓ Loaded AnnData with {adata.n_obs} cells and {adata.n_vars} genes")

            def check_ensembl_patterns(gene_index):
                patterns = {
                    "human_ensembl": r"^ENSG\d{11}(\.\d+)?$",
                    "mouse_ensembl": r"^ENSMUSG\d{11}(\.\d+)?$",
                    "zebrafish_ensembl": r"^ENSDARG\d{11}(\.\d+)?$",
                    "fly_ensembl": r"^FBgn\d{7}$",
                    "worm_ensembl": r"^WBGene\d{8}$",
                    "yeast_ensembl": r"^Y[A-P][LR]\d{3}[WC]?$",
                    "generic_ensembl": r"^ENS[A-Z]{3}G\d{11}(\.\d+)?$",
                }

                results = {}
                for pattern_name, pattern in patterns.items():
                    matches = gene_index.str.match(pattern, na=False)
                    count = matches.sum()
                    results[pattern_name] = {
                        "count": count,
                        "percentage": (count / len(gene_index)) * 100,
                        "matches": gene_index[matches].tolist()[:5] if count > 0 else [],
                    }

                return results

            print("Analyzing gene index for Ensembl ID patterns...")
            ensembl_analysis = check_ensembl_patterns(adata.var.index)

            for pattern_name, data in ensembl_analysis.items():
                if data["count"] > 0:
                    print(f"✓ {pattern_name}: {data['count']} genes ({data['percentage']:.1f}%)")
                    if data["matches"]:
                        print(f"  Examples: {data['matches']}")

            best_pattern = max(ensembl_analysis.items(), key=lambda x: x[1]["count"])
            if best_pattern[1]["count"] > 0:
                print(f"✓ Best match: {best_pattern[0]} with {best_pattern[1]['count']} genes")
            else:
                print("❌ ERROR: No clear Ensembl ID patterns detected in gene index")
                print(f"  Gene index examples: {adata.var.index[:5].tolist()}")
                print("  This dataset cannot be processed by transcriptformer.")
                print("  Please ensure your data contains valid Ensembl gene IDs.")
                raise ValueError(
                    "No Ensembl ID patterns found in gene index. Cannot proceed with transcriptformer inference."
                )

            if "ensembl_id" not in adata.var.columns:
                if "gene_ids" in adata.var.columns:
                    print("✓ Found 'gene_ids' column, renaming to 'ensembl_id'")
                    adata.var["ensembl_id"] = adata.var["gene_ids"]
                elif best_pattern[1]["count"] > 0:
                    adata.var["ensembl_id"] = adata.var.index
                    print(f"✓ Using gene index as ensembl_id (detected {best_pattern[0]} pattern)")
                else:
                    print("❌ ERROR: No 'ensembl_id' column found and gene index doesn't match Ensembl patterns")
                    print("  This dataset cannot be processed by transcriptformer.")
                    print("  Please ensure your data contains valid Ensembl gene IDs.")
                    raise ValueError("No valid Ensembl gene IDs found. Cannot proceed with transcriptformer inference.")

            if adata.raw is None:
                print("⚠️  Warning: Transcriptformer expects raw (unnormalized) count data in adata.X.")
                if not pd.api.types.is_integer_dtype(adata.X.dtype):
                    print("⚠️  Warning: adata.X does not appear to be unnormalized counts (integer type not detected).")
                adata.raw = adata
                print("✓ Set adata.raw to current adata")

            if remove_duplicate_genes:
                print("Pre-processing: Removing duplicate genes to prevent dimension mismatch...")
                adata.var["ensembl_id_clean"] = adata.var["ensembl_id"].str.split(".").str[0]

                duplicate_mask = adata.var["ensembl_id_clean"].duplicated(keep="first")
                n_duplicates = duplicate_mask.sum()

                if n_duplicates > 0:
                    print(f"Found {n_duplicates} duplicate genes, removing them...")
                    adata = adata[:, ~duplicate_mask].copy()
                    print(f"✓ Removed {n_duplicates} duplicate genes. Remaining: {adata.n_vars} genes")
                else:
                    print("✓ No duplicate genes found")

                adata.var["ensembl_id"] = adata.var["ensembl_id_clean"]
                adata.var.drop("ensembl_id_clean", axis=1, inplace=True)

            adata.write(temp_data_path)
            print(f"✓ Saved prepared AnnData to {temp_data_path}")

        except Exception as e:
            print(f"Error preparing AnnData object: {e}")
            raise

        print("Running transcriptformer inference...")
        print("This may take a while depending on data size and GPU...")
        try:
            cmd = [
                "transcriptformer",
                "inference",
                "--checkpoint-path",
                checkpoint_path,
                "--data-file",
                temp_data_path,
                "--output-path",
                os.path.dirname(output_path),
                "--output-filename",
                os.path.basename(output_path),
                "--batch-size",
                str(batch_size),
                "--gene-col-name",
                gene_col_name,
                "--precision",
                precision,
                "--clip-counts",
                str(clip_counts),
                "--model-type",
                "transcriptformer",
                "--use-raw",
                use_raw,
                "--emb-type",
                emb_type,
                "--num-gpus",
                str(num_gpus),
                "--n-data-workers",
                str(n_data_workers),
            ]

            # Check if assay column exists in obs, if not create it
            if "assay" not in adata.obs.columns:
                print("✓ Creating 'assay' column in obs metadata with 'unknown' values")
                adata.obs["assay"] = "unknown"
                # Save the updated adata with assay column
                adata.write(temp_data_path)
                print(f"✓ Updated AnnData saved to {temp_data_path}")

            if pretrained_embedding is not None:
                cmd.extend(["--pretrained-embedding", pretrained_embedding])

            if filter_to_vocabs:
                cmd.append("--filter-to-vocabs")

            if remove_duplicate_genes:
                cmd.append("--remove-duplicate-genes")

            if oom_dataloader:
                cmd.append("--oom-dataloader")

            process = subprocess.Popen(
                cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1, universal_newlines=True
            )

            for line in iter(process.stdout.readline, ""):
                print(line.rstrip())

            process.wait()

            if process.returncode != 0:
                raise subprocess.CalledProcessError(process.returncode, cmd)

            print("✓ Transcriptformer inference completed successfully")
            print(f"✓ Output saved to: {output_path}")

        except subprocess.CalledProcessError as e:
            print(f"Error running transcriptformer inference: {e}")
            raise

        try:
            if os.path.exists(temp_data_path):
                os.remove(temp_data_path)
                print("✓ Cleaned up temporary files")
        except Exception as e:
            print(f"⚠️  Warning: Could not clean up temporary files: {e}")

        print("✓ Transcriptformer embeddings generated successfully!")
        print("\\nOutput Format and Location:")
        print("  Output format: .h5ad (AnnData format)")

        return output_path

    except Exception as e:
        print(f"Fatal error in transcriptformer embedding generation: {e}")
        raise

# Execute the function
try:
    result = generate_transcriptformer_embeddings(
        adata_filename=auto_convert(os.environ.get("PARAM_ADATA_FILENAME", "")),
        data_dir=auto_convert(os.environ.get("PARAM_DATA_DIR", "")),
        output_filename=auto_convert(os.environ.get("PARAM_OUTPUT_FILENAME", "")),
        model_type=auto_convert(os.environ.get("PARAM_MODEL_TYPE", "tf-sapiens")),
        checkpoint_path=auto_convert(os.environ.get("PARAM_CHECKPOINT_PATH", "")),
        batch_size=auto_convert(os.environ.get("PARAM_BATCH_SIZE", "8")),
        precision=auto_convert(os.environ.get("PARAM_PRECISION", "16-mixed")),
        clip_counts=auto_convert(os.environ.get("PARAM_CLIP_COUNTS", "30")),
        embedding_layer_index=auto_convert(os.environ.get("PARAM_EMBEDDING_LAYER_INDEX", "")),
        num_gpus=auto_convert(os.environ.get("PARAM_NUM_GPUS", "1")),
        n_data_workers=auto_convert(os.environ.get("PARAM_N_DATA_WORKERS", "0")),
        gene_col_name=auto_convert(os.environ.get("PARAM_GENE_COL_NAME", "ensembl_id")),
        pretrained_embedding=auto_convert(os.environ.get("PARAM_PRETRAINED_EMBEDDING", "")),
        filter_to_vocabs=auto_convert(os.environ.get("PARAM_FILTER_TO_VOCABS", "")),
        use_raw=auto_convert(os.environ.get("PARAM_USE_RAW", "None")),
        emb_type=auto_convert(os.environ.get("PARAM_EMB_TYPE", "cell")),
        remove_duplicate_genes=auto_convert(os.environ.get("PARAM_REMOVE_DUPLICATE_GENES", "")),
        oom_dataloader=auto_convert(os.environ.get("PARAM_OOM_DATALOADER", "")),
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
    "function": "generate_transcriptformer_embeddings",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("generate_transcriptformer_embeddings_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("generate_transcriptformer_embeddings_output.txt", "w") as f:
    f.write("Biomni: Generate Transcriptformer Embeddings" + NL)
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
        biomni_function: "generate_transcriptformer_embeddings"
    END_VERSIONS
    """
}

workflow GENERATE_TRANSCRIPTFORMER_EMBEDDINGS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GENERATE_TRANSCRIPTFORMER_EMBEDDINGS(ch_input)

    emit:
    results = GENERATE_TRANSCRIPTFORMER_EMBEDDINGS.out.results
    output = GENERATE_TRANSCRIPTFORMER_EMBEDDINGS.out.output
    versions = GENERATE_TRANSCRIPTFORMER_EMBEDDINGS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GENERATE_TRANSCRIPTFORMER_EMBEDDINGS_WORKFLOW(ch_input)

    GENERATE_TRANSCRIPTFORMER_EMBEDDINGS_WORKFLOW.out.output.view { "Output: $it" }
}
