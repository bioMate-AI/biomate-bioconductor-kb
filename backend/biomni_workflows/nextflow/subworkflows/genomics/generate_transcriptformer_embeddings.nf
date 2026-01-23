#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_transcriptformer_embeddings
 * Generate Transcriptformer embeddings for single-cell RNA-seq data.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
 */

nextflow.enable.dsl = 2

// Parameters
params.outdir = './results'
params.adata_filename = null
params.data_dir = null
params.output_filename = null
params.model_type = 'tf-sapiens'
params.checkpoint_path = null
params.batch_size = 8
params.precision = '16-mixed'
params.clip_counts = 30
params.embedding_layer_index = 0
params.num_gpus = 1
params.n_data_workers = 0
params.gene_col_name = 'ensembl_id'
params.pretrained_embedding = null
params.filter_to_vocabs = false
params.use_raw = 'None'
params.emb_type = 'cell'
params.remove_duplicate_genes = false
params.oom_dataloader = false

// Main process
process GENERATE_TRANSCRIPTFORMER_EMBEDDINGS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("generate_transcriptformer_embeddings_results.json"), emit: results
    path("generate_transcriptformer_embeddings_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import generate_transcriptformer_embeddings

# Run the tool
try:
    result = generate_transcriptformer_embeddings(
    adata_filename="${params.adata_filename}",
    data_dir="${params.data_dir}",
    output_filename="${params.output_filename}",
    model_type="${params.model_type}",
    checkpoint_path="${params.checkpoint_path}",
    batch_size=${params.batch_size},
    precision="${params.precision}",
    clip_counts=${params.clip_counts},
    embedding_layer_index=${params.embedding_layer_index},
    num_gpus=${params.num_gpus},
    n_data_workers=${params.n_data_workers},
    gene_col_name="${params.gene_col_name}",
    pretrained_embedding="${params.pretrained_embedding}",
    filter_to_vocabs=${params.filter_to_vocabs ? "True" : "False"},
    use_raw="${params.use_raw}",
    emb_type="${params.emb_type}",
    remove_duplicate_genes=${params.remove_duplicate_genes ? "True" : "False"},
    oom_dataloader=${params.oom_dataloader ? "True" : "False"}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("generate_transcriptformer_embeddings_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("generate_transcriptformer_embeddings_output.txt", "w") as f:
    f.write("Biomni: Generate Transcriptformer Embeddings Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("generate_transcriptformer_embeddings completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_GENERATE_TRANSCRIPTFORMER_EMBEDDINGS {
    take:
    // No file inputs

    main:
    GENERATE_TRANSCRIPTFORMER_EMBEDDINGS()

    emit:
    results = GENERATE_TRANSCRIPTFORMER_EMBEDDINGS.out.results
    output = GENERATE_TRANSCRIPTFORMER_EMBEDDINGS.out.output
}

// Entry workflow
workflow {
    if (!params.adata_filename) {
        error "Please provide --adata_filename parameter"
    }
    if (!params.data_dir) {
        error "Please provide --data_dir parameter"
    }


    BIOMNI_GENOMICS_GENERATE_TRANSCRIPTFORMER_EMBEDDINGS()
}
