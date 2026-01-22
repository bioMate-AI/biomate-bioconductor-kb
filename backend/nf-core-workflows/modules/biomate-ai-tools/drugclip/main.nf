// DrugCLIP - Ultra-fast virtual drug screening
// 10 million times faster than traditional docking
// Can also use FREE API at drugclip.com

process DRUGCLIP {
    tag "$meta.id"
    label 'process_medium'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/drugclip:latest'

    input:
    tuple val(meta), path(protein_fasta)
    path compounds  // SDF or SMILES file

    output:
    tuple val(meta), path("*_scores.csv"), emit: scores
    tuple val(meta), path("*_top_hits.csv"), emit: top_hits
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def top_k = task.ext.top_k ?: 100
    """
    python /opt/drugclip/screen.py \\
        --protein ${protein_fasta} \\
        --compounds ${compounds} \\
        --output ${prefix}_scores.csv \\
        --top_k ${top_k}

    # Extract top hits
    head -n ${top_k} ${prefix}_scores.csv > ${prefix}_top_hits.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        drugclip: "latest"
    END_VERSIONS
    """
}

// API-based screening (uses pre-computed database)
process DRUGCLIP_API {
    tag "$meta.id"
    label 'process_low'

    input:
    tuple val(meta), val(uniprot_id)

    output:
    tuple val(meta), path("*_drugclip_results.json"), emit: results
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    curl -s "https://drugclip.com/api/search/${uniprot_id}" \\
        -o ${prefix}_drugclip_results.json

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        drugclip_api: "v1"
    END_VERSIONS
    """
}
