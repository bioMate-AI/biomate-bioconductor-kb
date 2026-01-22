// ProTrek - Trimodal protein search (sequence, structure, text)
// 100x faster than Foldseek, can search by text description
// FREE API available at search-protrek.com

process PROTREK_SEARCH {
    tag "$meta.id"
    label 'process_medium'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest'

    input:
    tuple val(meta), val(query)  // Can be: sequence, PDB path, or text description
    val query_type              // "sequence", "structure", or "text"

    output:
    tuple val(meta), path("*_protrek_results.json"), emit: results
    tuple val(meta), path("*_top_hits.tsv"), emit: top_hits
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    def top_k = task.ext.top_k ?: 100
    """
    python /opt/protrek/demo/search.py \\
        --query "${query}" \\
        --type ${query_type} \\
        --top_k ${top_k} \\
        --output ${prefix}_protrek_results.json

    # Convert to TSV for easier processing
    python -c "
import json
with open('${prefix}_protrek_results.json') as f:
    data = json.load(f)
with open('${prefix}_top_hits.tsv', 'w') as f:
    f.write('rank\\tuniprot_id\\tscore\\tfunction\\n')
    for i, hit in enumerate(data.get('hits', [])[:${top_k}]):
        f.write(f'{i+1}\\t{hit.get(\"id\",\"\")}\\t{hit.get(\"score\",\"\")}\\t{hit.get(\"function\",\"\")}\\n')
"

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        protrek: "latest"
    END_VERSIONS
    """
}

// Embedding generation for custom databases
process PROTREK_EMBED {
    tag "$meta.id"
    label 'process_gpu'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/protrek:latest'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*_embeddings.pt"), emit: embeddings
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    python /opt/protrek/demo/embed.py \\
        --input ${fasta} \\
        --output ${prefix}_embeddings.pt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        protrek: "latest"
    END_VERSIONS
    """
}
