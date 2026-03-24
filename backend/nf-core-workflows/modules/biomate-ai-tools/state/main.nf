// STATE - Virtual cell model for perturbation response prediction
// Predicts cellular responses to gene knockdown, drug treatment, CRISPR

process STATE_PERTURB {
    tag "$meta.id"
    label 'process_gpu'
    label 'process_high_memory'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:nextflow'

    input:
    tuple val(meta), path(adata)  // AnnData h5ad file with scRNA-seq data

    output:
    tuple val(meta), path("*_simulated.h5ad"), emit: simulated
    tuple val(meta), path("*_predictions.csv"), emit: predictions, optional: true
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def pert_col = task.ext.pert_col ?: "perturbation"
    def celltype_col = task.ext.celltype_col ?: "cell_type"
    """
    state tx infer \\
        --adata ${adata} \\
        --model-dir /models/state \\
        --pert-col ${pert_col} \\
        --celltype-col ${celltype_col} \\
        --output ${prefix}_simulated.h5ad

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        state: \$(pip show arc-state 2>/dev/null | grep Version | cut -d' ' -f2 || echo "0.10.1")
    END_VERSIONS
    """
}

process STATE_EMBED {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/state:nextflow'

    input:
    tuple val(meta), path(adata)  // AnnData h5ad file

    output:
    tuple val(meta), path("*_embedded.h5ad"), emit: embedded
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    state emb transform \\
        --input ${adata} \\
        --model-folder /models/state \\
        --output ${prefix}_embedded.h5ad

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        state: \$(pip show arc-state 2>/dev/null | grep Version | cut -d' ' -f2 || echo "0.10.1")
    END_VERSIONS
    """
}
