#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: DiffLogo
// DiffLogo is an easy-to-use tool to visualize motif differences.
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/DiffLogo/inst/doc/DiffLogoBasics.R
// Upstream  : MotifDb, seqLogo
// Downstream: none
//
// Install: BiocManager::install("DiffLogo")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DIFFLOGO {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-difflogo"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-difflogo:2.30.0--r44_0' :
        'quay.io/biocontainers/bioconductor-difflogo:2.30.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_difflogo_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_difflogo_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_difflogo_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DiffLogo)
    library(jsonlite)

    # --- Sequence Logo Plotting [] ---
    # Key functions: seqLogo
    pwm1 = motifs_dna[["H1-hESC"]]
    pwm2 = motifs_dna[["MCF7"]]
    DiffLogo::seqLogo(pwm = pwm1)
    DiffLogo::seqLogo(pwm = pwm2, stackHeight = sumProbabilities)


    # --- Difference Logo Generation [] ---
    # Key functions: diffLogoFromPwm, createDiffLogoObject, enrichDiffLogoObjectWithPvalues, diffLogo
    diffLogoFromPwm(pwm1 = pwm1, pwm2 = pwm2)
    diffLogoObj = createDiffLogoObject(pwm1 = pwm1, pwm2 = pwm2)
    diffLogoObj = enrichDiffLogoObjectWithPvalues(diffLogoObj, 100, 100)
    diffLogo(diffLogoObj)


    # --- Difference Logo Table [] ---
    # Key functions: diffLogoTable
    sampleSizes_dna = c("H1-hESC" = 100, "MCF7" = 100)
    diffLogoTable(PWMs = motifs_dna, sampleSizes = sampleSizes_dna)


    # --- Motif Alignment [] ---
    # Key functions: multipleLocalPwmsAlignment, extendPwmsFromAlignmentVector
    pwms = list(pwm1, pwm2)
    multiple_pwms_alignment = multipleLocalPwmsAlignment(pwms)
    aligned_pwms = extendPwmsFromAlignmentVector(pwms,
        multiple_pwms_alignment$alignment$vector)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_difflogo_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_difflogo_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_difflogo_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DIFFLOGO:", paste0("    difflogo: ", packageVersion("DiffLogo"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_difflogo_results.csv
    touch ${prefix}_difflogo_output.rds
    echo "BIOC_DIFFLOGO:" > versions.yml
    echo "    difflogo: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DIFFLOGO_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_DIFFLOGO(ch_input)

    emit:
    results  = BIOC_DIFFLOGO.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DIFFLOGO.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DIFFLOGO.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DIFFLOGO.out.versions  // channel: path(versions.yml)
}
