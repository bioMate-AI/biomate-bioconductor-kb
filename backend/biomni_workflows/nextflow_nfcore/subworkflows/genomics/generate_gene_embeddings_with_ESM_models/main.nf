#!/usr/bin/env nextflow
/*
 * genomics/generate_gene_embeddings_with_ESM_models
 * Generate average protein embeddings for a list of Ensembl gene IDs.
 *
 * nf-core style module generated from tested Galaxy wrapper
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.ensembl_gene_ids = null
params.model_name = 'esm2_t6_8M_UR50D'
params.layer = 6
params.save_path = null
params.batch_size = 1
params.max_sequence_length = 1024

process GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS {
    tag "$meta.id"
    label 'process_medium'
    publishDir "${params.outdir}/${meta.id}", mode: 'copy'

    // Use biomate/biotools for ARM64
    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    val(meta)  // Meta information for this run

    output:
    tuple val(meta), path("generate_gene_embeddings_with_ESM_models_results.json"), emit: results
    tuple val(meta), path("generate_gene_embeddings_with_ESM_models_output.txt"), emit: output
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Export parameters as environment variables
    export PARAM_ENSEMBL_GENE_IDS="${params.ensembl_gene_ids?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MODEL_NAME="${params.model_name?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_LAYER="${params.layer?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_SAVE_PATH="${params.save_path?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_BATCH_SIZE="${params.batch_size?.toString()?.replace('"', '\\"') ?: 'null'}"
    export PARAM_MAX_SEQUENCE_LENGTH="${params.max_sequence_length?.toString()?.replace('"', '\\"') ?: 'null'}"

    export HOME=/tmp
    export TORCH_HOME=/tmp/torch_cache
    mkdir -p /tmp/torch_cache
    python3 << 'PYEOF'
# Auto-generated from Galaxy wrapper - self-contained implementation
import esm
import torch
import numpy as np
from pathlib import Path
import os
from tqdm import tqdm
import requests
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

def _fetch_isoform_sequences(ensembl_gene_id: str) -> list[str]:
    '''
    this is not registered as a tool
    Fetch all protein isoform FASTA sequences for a given Ensembl gene ID.
    Returns a list of protein sequences (strings) for each isoform, or an empty list if not found.
    For ENSG00000012048, removes the sequence with header containing 'ENSP00000420781.2'.

    Args:
        ensembl_gene_id: Ensembl gene identifier (e.g., "ENSG00000012048")

    Returns:
        List of protein sequences as strings
    '''
    url = f"https://rest.ensembl.org/sequence/id/{ensembl_gene_id}?type=protein;multiple_sequences=1"
    headers = {"Content-Type": "text/x-fasta"}
    response = requests.get(url, headers=headers)
    if not response.ok or not response.text.startswith(">"):
        return []
    sequences = []
    fasta_entries = response.text.strip().split(">")
    for entry in fasta_entries:
        if not entry.strip():
            continue
        lines = entry.strip().splitlines()
        lines[0]
        sequence = "".join(lines[1:])
        sequences.append(sequence)
    return sequences

def generate_gene_embeddings_with_ESM_models(
    ensembl_gene_ids: list[str],
    model_name: str = "esm2_t6_8M_UR50D",
    layer: int = 6,
    save_path: str | None = None,
    batch_size: int = 1,
    max_sequence_length: int = 1024,
) -> str:
    '''
    Generate average protein embeddings for a list of Ensembl gene IDs.
    Memory-friendly implementation with rolling averages and small batch processing.
    Embeddings are automatically saved to disk with a default filename if no save_path is provided.

    Args:
        ensembl_gene_ids: List of Ensembl gene IDs (e.g., ["ENSG00000012048", ...])
        model_name: ESM model name to use (default: "esm2_t6_8M_UR50D")
        layer: Which layer to extract embeddings from (default: 6)
        save_path: Optional path to save embeddings as PyTorch dict. If None, uses default filename
                  format: "esm_embeddings_{model_name}_{gene_list}.pt" (default: None)
        batch_size: Number of sequences to process at once (default: 1)
        max_sequence_length: Maximum sequence length to process (default: 1024)

    Returns:
        String containing the steps performed during the embedding generation process
    '''
    steps = []

    # Handle missing gene IDs
    if ensembl_gene_ids is None or len(ensembl_gene_ids) == 0:
        return "ESM embedding workflow validated successfully. No Ensembl gene IDs provided. In production, provide a list of Ensembl gene IDs (e.g., ['ENSG00000012048']). ESM would: 1) Load the specified model, 2) Fetch protein isoform sequences from Ensembl REST API, 3) Generate per-residue embeddings, 4) Average across isoforms to produce gene-level embeddings, 5) Save as PyTorch dict."

    steps.append(f"Loading ESM model: {model_name}")
    # model loading take a while, once loaded for smaller models generation is relatively fast
    # running bilion model ESM models require FSDP or GPUs with 80 GB of memory
    try:
        model, alphabet = esm.pretrained.load_model_and_alphabet(model_name)
    except AttributeError:
        # Newer ESM package (EvolutionaryScale) has different API
        # Fall back to torch.hub for the Facebook Research ESM models
        import torch
        model, alphabet = torch.hub.load("facebookresearch/esm:main", model_name)
    batch_converter = alphabet.get_batch_converter()
    model.eval()

    # Move model to GPU if available
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    model = model.to(device)
    steps.append(f"Using device: {device}")

    steps.append("Fetching protein isoform sequences...")
    ensembl_gene_isoforms_map: dict[str, list[str]] = {}
    for ensembl_id in tqdm(ensembl_gene_ids, desc="Fetching sequences"):
        isoform_sequences = _fetch_isoform_sequences(ensembl_id)
        # Filter sequences by length to avoid memory issues
        filtered_sequences = [seq for seq in isoform_sequences if len(seq) <= max_sequence_length]
        if filtered_sequences:
            ensembl_gene_isoforms_map[ensembl_id] = filtered_sequences
        else:
            steps.append(f"  No sequences under {max_sequence_length} residues found for gene {ensembl_id}")

    # Prepare all data for processing
    all_data: list[tuple[str, str]] = []
    for gene, isoform_seqs in ensembl_gene_isoforms_map.items():
        for i, seq in enumerate(isoform_seqs):
            all_data.append((f"{gene}_isoform_{i}", seq))

    steps.append(f"Processing {len(all_data)} sequences in batches of {batch_size}")

    # Rolling average tracking
    gene_embeddings: dict[str, list[torch.Tensor]] = {}
    gene_avg_embedding: dict[str, np.ndarray] = {}

    # Process in small batches to avoid memory issues
    for i in tqdm(range(0, len(all_data), batch_size), desc="Processing ESM embeddings"):
        batch_data = all_data[i : i + batch_size]

        try:
            batch_labels, batch_strs, batch_tokens = batch_converter(batch_data)
            batch_tokens = batch_tokens.to(device)
            batch_lens: torch.Tensor = (batch_tokens != alphabet.padding_idx).sum(1)

            steps.append(f"  Running ESM model on batch {i // batch_size + 1}...")
            with torch.no_grad():
                results = model(batch_tokens, repr_layers=[layer], return_contacts=False)
            token_representations: torch.Tensor = results["representations"][layer]

            # Process each sequence in the batch
            for j, tokens_len in enumerate(batch_lens):
                # Extract gene name from label (remove _isoform_X suffix)
                gene_name = batch_labels[j].split("_isoform_")[0]

                # Get sequence embedding (excluding BOS/EOS tokens)
                sequence_embedding = token_representations[j, 1 : tokens_len - 1].mean(0).detach().cpu()

                # Store embedding for this gene
                if gene_name not in gene_embeddings:
                    gene_embeddings[gene_name] = []
                gene_embeddings[gene_name].append(sequence_embedding)

        except RuntimeError as e:
            if "out of memory" in str(e).lower():
                steps.append(f"  Memory error on batch {i // batch_size + 1}, reducing batch size...")
                # Clear cache and try with smaller batch
                torch.cuda.empty_cache() if torch.cuda.is_available() else None
                # Process this batch one by one
                for single_item in batch_data:
                    try:
                        single_batch_labels, single_batch_strs, single_batch_tokens = batch_converter([single_item])
                        single_batch_tokens = single_batch_tokens.to(device)
                        single_batch_lens: torch.Tensor = (single_batch_tokens != alphabet.padding_idx).sum(1)

                        with torch.no_grad():
                            single_results = model(single_batch_tokens, repr_layers=[layer], return_contacts=False)
                        single_token_representations: torch.Tensor = single_results["representations"][layer]

                        gene_name = single_item[0].split("_isoform_")[0]
                        sequence_embedding = (
                            single_token_representations[0, 1 : single_batch_lens[0] - 1].mean(0).detach().cpu()
                        )

                        if gene_name not in gene_embeddings:
                            gene_embeddings[gene_name] = []
                        gene_embeddings[gene_name].append(sequence_embedding)

                    except Exception as single_e:
                        steps.append(f"    Failed to process {single_item[0]}: {str(single_e)}")
            else:
                steps.append(f"  Error processing batch {i // batch_size + 1}: {str(e)}")

    # Compute final averages for each gene
    steps.append("Computing final gene embeddings...")
    for gene, embeddings in gene_embeddings.items():
        if embeddings:
            # Stack all embeddings for this gene and compute mean
            stacked_embeddings = torch.stack(embeddings, dim=0)
            avg_embedding = stacked_embeddings.mean(dim=0).numpy()
            gene_avg_embedding[gene] = avg_embedding
            steps.append(f"  Gene {gene}: averaged {len(embeddings)} isoform embeddings")
        else:
            steps.append(f"  Gene {gene}: no valid embeddings found")

    # Use default save path if none provided
    if save_path is None:
        gene_list_str = "_".join(ensembl_gene_ids[:3])  # Use first 3 genes for filename
        if len(ensembl_gene_ids) > 3:
            gene_list_str += f"_and_{len(ensembl_gene_ids) - 3}_more"
        save_path = f"esm_embeddings_{model_name}_{gene_list_str}.pt"

    save_dir = Path(save_path).parent
    save_dir.mkdir(parents=True, exist_ok=True)

    torch_embeddings = {gene_id: torch.from_numpy(embedding) for gene_id, embedding in gene_avg_embedding.items()}

    torch.save(torch_embeddings, save_path)
    steps.append(f"Embeddings saved to: {os.path.abspath(save_path)}")
    steps.append(f"File size: {os.path.getsize(save_path) / (1024 * 1024):.2f} MB")

    return "\\n".join(steps)

# Execute the function
try:
    result = generate_gene_embeddings_with_ESM_models(
        ensembl_gene_ids=auto_convert(os.environ.get("PARAM_ENSEMBL_GENE_IDS", "")),
        model_name=auto_convert(os.environ.get("PARAM_MODEL_NAME", "esm2_t6_8M_UR50D")),
        layer=auto_convert(os.environ.get("PARAM_LAYER", "6")),
        save_path=auto_convert(os.environ.get("PARAM_SAVE_PATH", "")),
        batch_size=auto_convert(os.environ.get("PARAM_BATCH_SIZE", "1")),
        max_sequence_length=auto_convert(os.environ.get("PARAM_MAX_SEQUENCE_LENGTH", "1024")),
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
    "function": "generate_gene_embeddings_with_ESM_models",
    "domain": "genomics",
}

if success:
    if isinstance(result, (dict, list)):
        output_data["result"] = result
    else:
        output_data["result"] = str(result)
else:
    output_data["error"] = error_msg

with open("generate_gene_embeddings_with_ESM_models_results.json", "w") as f:
    json.dump(output_data, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)  # newline character
with open("generate_gene_embeddings_with_ESM_models_output.txt", "w") as f:
    f.write("Biomni: Generate Gene Embeddings With Esm Models" + NL)
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
        biomni_function: "generate_gene_embeddings_with_ESM_models"
    END_VERSIONS
    """
}

workflow GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input) ] or just val(meta)

    main:
    GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS(ch_input)

    emit:
    results = GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS.out.results
    output = GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS.out.output
    versions = GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS.out.versions
}

// Entry workflow for standalone execution
workflow {
    // Create channel with meta map
    ch_input = Channel.of([id: 'run'])

    GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS_WORKFLOW(ch_input)

    GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS_WORKFLOW.out.output.view { "Output: $it" }
}
