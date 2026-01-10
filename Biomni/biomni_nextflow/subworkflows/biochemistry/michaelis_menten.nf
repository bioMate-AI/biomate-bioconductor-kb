#!/usr/bin/env nextflow
/*
 * biomni_biochemistry_michaelis_menten
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process MICHAELIS_MENTEN {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("michaelis_menten_output.txt"), emit: output

    script:
    """
    # Tool: biomni_biochemistry_michaelis_menten
    # Runs in unified Docker container
    echo 'Running MICHAELIS_MENTEN'
        touch michaelis_menten_output.txt
    """
}

process OUTPUT {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("output_output.txt"), emit: output

    script:
    """
    # Tool: cat1
    # Runs in unified Docker container
    echo 'Running OUTPUT'
        touch output_output.txt
    """
}

workflow BIOMNI_BIOCHEMISTRY_MICHAELIS_MENTEN {
    main:

    MICHAELIS_MENTEN()
    OUTPUT()

    emit:
    output = OUTPUT.out.output
}

workflow {
    BIOMNI_BIOCHEMISTRY_MICHAELIS_MENTEN()
}