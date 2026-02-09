// ESMFold - Fast protein structure prediction via API
// FREE API, no key needed, max 400 residues

process ESMFOLD {
    tag "$meta.id"
    label 'process_low'

    // API-based, use biomni-lite which has curl and bash
    container '399683337364.dkr.ecr.us-west-2.amazonaws.com/biomni-lite:latest'

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.pdb"), emit: pdb
    tuple val(meta), path("*.json"), emit: json, optional: true
    path "versions.yml", emit: versions

    script:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    # Read sequence from FASTA
    SEQUENCE=\$(grep -v "^>" ${fasta} | tr -d '\\n')

    # Call ESMFold API
    curl -s -X POST \\
        --data "\$SEQUENCE" \\
        https://api.esmatlas.com/foldSequence/v1/pdb/ \\
        -o ${prefix}.pdb

    # Check if result is valid PDB
    if ! grep -q "^ATOM" ${prefix}.pdb; then
        echo "ERROR: ESMFold API returned invalid result"
        cat ${prefix}.pdb
        exit 1
    fi

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        esmfold: "API v1"
        curl: \$(curl --version | head -n1 | cut -d' ' -f2)
    END_VERSIONS
    """
}
