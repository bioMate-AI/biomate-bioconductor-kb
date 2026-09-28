process OPENMS_PEPTIDEINDEXER {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    // Pinned to match the proteomics_dda_search capability container.
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/openms-thirdparty:3.4.1--h9ee0642_1' :
        'biocontainers/openms-thirdparty:3.4.1--h9ee0642_1' }"

    input:
    tuple val(meta), path(idxml), path(fasta)

    output:
    tuple val(meta), path("*.idXML"), emit: indexed_idxml
    path "versions.yml"             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}_indexed"
    def fasta_file = fasta ? "-fasta ${fasta}" : ""

    """
    PeptideIndexer \\
        -in $idxml \\
        $fasta_file \\
        -out ${prefix}.idXML \\
        -threads $task.cpus \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        openms: \$(FileInfo --help 2>&1 | sed -nE 's/^Version: ([0-9.]+).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}_indexed"

    """
    touch ${prefix}.idXML

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        openms: 3.4.1
    END_VERSIONS
    """
}
