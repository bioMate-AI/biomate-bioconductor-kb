process OPENMSTHIRDPARTY_COMETADAPTER {
    tag "$meta.id"
    label 'process_high'

    conda "${moduleDir}/environment.yml"
    // Pinned to match the proteomics_dda_search capability container
    // (openms-thirdparty bundles Comet; OpenMS BSD + Comet Apache).
    container "${ workflow.containerEngine in ['singularity', 'apptainer'] && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/openms-thirdparty:3.4.1--h9ee0642_1' :
        'biocontainers/openms-thirdparty:3.4.1--h9ee0642_1' }"

    input:
    tuple val(meta), path(mzml), path(fasta)

    output:
    tuple val(meta), path("*.idXML"), emit: idxml
    tuple val(meta), path("*.tsv")  , emit: pin, optional: true
    path "versions.yml"             , emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    CometAdapter \\
        -in $mzml \\
        -database $fasta \\
        -out ${prefix}.idXML \\
        -threads $task.cpus \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        CometAdapter: \$(CometAdapter --help 2>&1 | sed -nE 's/^Version: ([0-9.]+).*/\\1/p')
        Comet: \$(comet 2>&1 | sed -n 's/.*Comet version " *\\(.*\\)".*/\\1/p')
    END_VERSIONS
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"

    """
    touch ${prefix}.idXML
    touch ${prefix}_pin.tsv

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        CometAdapter: 3.4.1
        Comet: 2024.01.0
    END_VERSIONS
    """
}
