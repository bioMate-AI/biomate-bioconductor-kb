#!/usr/bin/env nextflow
/*
 * biomni_genetics_elbo_loss
 * 
 * Converted from Galaxy format
 * Docker: biomate/biotools:latest
 */

nextflow.enable.dsl = 2

// Parameters

// Processes
process STEP_1__TORCH_MATMUL {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input_file)

    output:
    path("step_1__torch_matmul_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_matmul
    # Runs in unified Docker container
    echo 'Running STEP_1__TORCH_MATMUL'
        touch step_1__torch_matmul_output.txt
    """
}

process STEP_2__TORCH_SUM {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_2__torch_sum_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_sum
    # Runs in unified Docker container
    echo 'Running STEP_2__TORCH_SUM'
        touch step_2__torch_sum_output.txt
    """
}

process STEP_3__TORCH_BERNOULLI {
    tag "${task.process}"
    label 'process_medium'

    container 'biomate/biotools:latest'

    input:
    path(input)

    output:
    path("step_3__torch_bernoulli_output.txt"), emit: output

    script:
    """
    # Tool: python_torch_torch_bernoulli
    # Runs in unified Docker container
    echo 'Running STEP_3__TORCH_BERNOULLI'
        touch step_3__torch_bernoulli_output.txt
    """
}

workflow BIOMNI_GENETICS_ELBO_LOSS {
    main:

    STEP_1__TORCH_MATMUL()
    STEP_2__TORCH_SUM(STEP_1__TORCH_MATMUL.out.output)
    STEP_3__TORCH_BERNOULLI(STEP_2__TORCH_SUM.out.output)

    emit:
    output = STEP_3__TORCH_BERNOULLI.out.output
}

workflow {
    BIOMNI_GENETICS_ELBO_LOSS()
}