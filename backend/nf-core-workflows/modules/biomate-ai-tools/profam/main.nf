// ProFam - Protein family language model for fitness prediction
// Score variants or generate new sequences

process PROFAM_SCORE {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest'

    input:
    tuple val(meta), path(conditioning_fasta)  // Family MSA or reference sequences
    tuple val(meta), path(candidates)          // Variants to score (FASTA or CSV)

    output:
    tuple val(meta), path("*_scores.csv"), emit: scores
    tuple val(meta), path("*_ranked.csv"), emit: ranked
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    python /opt/profam/scripts/score_sequences.py \\
        --checkpoint_dir /models/profam \\
        --conditioning_fasta ${conditioning_fasta} \\
        --candidates_file ${candidates} \\
        --save_dir ./

    # Rename output
    mv scores.csv ${prefix}_scores.csv || true

    # Create ranked list
    sort -t',' -k2 -nr ${prefix}_scores.csv > ${prefix}_ranked.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        profam: "1.0"
    END_VERSIONS
    """
}

process PROFAM_GENERATE {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/profam:latest'

    input:
    tuple val(meta), path(conditioning_fasta)  // Family MSA or reference sequences

    output:
    tuple val(meta), path("*_generated.fasta"), emit: sequences
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def num_sequences = task.ext.num_sequences ?: 100
    def temperature = task.ext.temperature ?: 1.0
    """
    python /opt/profam/scripts/generate_sequences.py \\
        --checkpoint_dir /models/profam \\
        --conditioning_fasta ${conditioning_fasta} \\
        --num_sequences ${num_sequences} \\
        --temperature ${temperature} \\
        --save_dir ./

    mv generated.fasta ${prefix}_generated.fasta || true

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        profam: "1.0"
    END_VERSIONS
    """
}
