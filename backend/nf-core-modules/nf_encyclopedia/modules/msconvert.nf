process MSCONVERT {
    publishDir "${params.mzml_dir}/${outputDir}", failOnError: true
    label 'process_low_constant'
    label 'error_retry'

    input:
        tuple val(file_id), path(raw_input), val(outputDir)

    output:
        tuple val(file_id), path("${raw_input.baseName}.mzML.gz")

    script:
    """
    wine msconvert \\
        -v \\
        --gzip \\
        --mzML \\
        --64 \\
        --zlib \\
        --filter "peakPicking true 1-" \\
        ${params.msconvert.demultiplex ? '--filter "demultiplex optimization=overlap_only"' : ''} \\
        ${raw_input}
    """

    stub:
    """
    touch ${raw_input.baseName}.mzML.gz
    """
}
