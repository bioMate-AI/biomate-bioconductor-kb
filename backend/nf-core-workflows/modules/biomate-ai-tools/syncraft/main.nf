// SynCraft - AI-powered retrosynthesis planning
// Uses LLM (Gemini) to plan synthesis routes for drug molecules
// Requires: GEMINI_API_KEY environment variable

process SYNCRAFT {
    tag "$meta.id"
    label 'process_low'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:latest'

    input:
    tuple val(meta), val(smiles)  // Target molecule SMILES

    output:
    tuple val(meta), path("*_synthesis_route.json"), emit: route
    tuple val(meta), path("*_synthesis_route.txt"), emit: route_text
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Check for API key
    if [ -z "\${GEMINI_API_KEY}" ]; then
        echo "ERROR: GEMINI_API_KEY environment variable not set"
        exit 1
    fi

    python /opt/syncraft/plan_synthesis.py \\
        --smiles "${smiles}" \\
        --output ${prefix}_synthesis_route.json \\
        --output_text ${prefix}_synthesis_route.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        syncraft: "latest"
        gemini: "api"
    END_VERSIONS
    """
}

// Batch processing for multiple molecules
process SYNCRAFT_BATCH {
    tag "$meta.id"
    label 'process_low'

    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomate/ai-tools/syncraft:latest'

    input:
    tuple val(meta), path(smiles_file)  // File with SMILES, one per line

    output:
    tuple val(meta), path("*_batch_routes.json"), emit: routes
    tuple val(meta), path("*_summary.csv"), emit: summary
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    if [ -z "\${GEMINI_API_KEY}" ]; then
        echo "ERROR: GEMINI_API_KEY environment variable not set"
        exit 1
    fi

    python /opt/syncraft/batch_synthesis.py \\
        --input ${smiles_file} \\
        --output ${prefix}_batch_routes.json \\
        --summary ${prefix}_summary.csv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        syncraft: "latest"
        gemini: "api"
    END_VERSIONS
    """
}
