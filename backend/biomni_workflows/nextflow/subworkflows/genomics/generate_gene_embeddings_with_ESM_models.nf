#!/usr/bin/env nextflow
/*
 * biomni_genomics_generate_gene_embeddings_with_ESM_models
 * Generate average protein embeddings for a list of Ensembl gene IDs.
 * Generated from Galaxy tool definition
 * Docker: biomate/biomni-tools:latest
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

// Main process
process GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS {
    tag "${task.process}"
    label 'process_medium'
    publishDir "${params.outdir}", mode: 'copy'

    container System.getenv('NEXTFLOW_USE_AWS') in ['true','1','yes'] ? '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/biomni-tools:x86' : 'biomate/biomni-tools:latest'

    input:
    // No file inputs

    output:
    path("generate_gene_embeddings_with_ESM_models_results.json"), emit: results
    path("generate_gene_embeddings_with_ESM_models_output.txt"), emit: output

    script:
    """
    python3 << 'PYEOF'
import json
from biomni.tool.genomics import generate_gene_embeddings_with_ESM_models

# Run the tool
try:
    result = generate_gene_embeddings_with_ESM_models(
    ensembl_gene_ids="${params.ensembl_gene_ids}",
    model_name="${params.model_name}",
    layer=${params.layer},
    save_path="${params.save_path}",
    batch_size=${params.batch_size},
    max_sequence_length=${params.max_sequence_length}
    )
except Exception as e:
    result = {"error": str(e)}

# Save results as JSON
with open("generate_gene_embeddings_with_ESM_models_results.json", "w") as f:
    json.dump(result, f, indent=2, default=str)

# Create human-readable output
NL = chr(10)
with open("generate_gene_embeddings_with_ESM_models_output.txt", "w") as f:
    f.write("Biomni: Generate Gene Embeddings With Esm Models Results" + NL)
    f.write("=" * 60 + NL + NL)
    if isinstance(result, dict):
        for key, value in result.items():
            f.write(str(key) + ": " + str(value) + NL)
    else:
        f.write(str(result))

print("generate_gene_embeddings_with_ESM_models completed successfully")
PYEOF
    """
}

// Workflow definition
workflow BIOMNI_GENOMICS_GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS {
    take:
    // No file inputs

    main:
    GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS()

    emit:
    results = GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS.out.results
    output = GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS.out.output
}

// Entry workflow
workflow {
    if (!params.ensembl_gene_ids) {
        error "Please provide --ensembl_gene_ids parameter"
    }


    BIOMNI_GENOMICS_GENERATE_GENE_EMBEDDINGS_WITH_ESM_MODELS()
}
