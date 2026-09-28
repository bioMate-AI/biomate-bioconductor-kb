process OPENMS_DECOYDATABASE {
    tag "$meta.id"
    label 'process_single'

    conda "${moduleDir}/environment.yml"
    // Pinned to match the proteomics_dda_search capability container
    // (OpenMS BSD + Comet Apache bundled in openms-thirdparty).
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/openms-thirdparty:3.4.1--h9ee0642_1' :
        'biocontainers/openms-thirdparty:3.4.1--h9ee0642_1' }"

    input:
    tuple val(meta), path(fasta)

    output:
    tuple val(meta), path("*.fasta"), emit: decoy_fasta
    path "versions.yml"             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${fasta.baseName}_decoy"

    """
    DecoyDatabase \\
        -in $fasta \\
        -out ${prefix}.fasta \\
        -threads $task.cpus \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        openms: \$(FileInfo --help 2>&1 | sed -nE 's/^Version: ([0-9.]+).*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${fasta.baseName}_decoy"

    """
    touch ${prefix}.fasta

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        openms: 3.4.1
    END_VERSIONS
    """
}
