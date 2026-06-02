#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PWMEnrich
// A toolkit of high-level functions for DNA motif scanning and enrichment analysis built upon Biostrin
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PWMEnrich/inst/doc/PWMEnrich.R
// Upstream  : none
// Downstream: PWMEnrich.Dmelanogaster.background, PWMEnrich.Hsapiens.background, PWMEnrich.Mmusculus.background
//
// Install: BiocManager::install("PWMEnrich")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PWMENRICH {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pwmenrich"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pwmenrich:4.42.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pwmenrich:4.42.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pwmenrich_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pwmenrich_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pwmenrich_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PWMEnrich)
    library(jsonlite)

    # --- Motif Scanning and Scoring [] ---
    # Key functions: motifScores, plotMotifScores
    sel.pwms <- PWMLogn.dm3.MotifDb.Dmel$pwms[c("Kr", "gt")]
    scores <- motifScores(sequence, sel.pwms, raw.scores = TRUE)
    plotMotifScores(scores, cols = c("green", "red"))


    # --- Custom Background Generation [] ---
    # Key functions: readMotifs, toPWM, makeBackground
    motifs.denovo <- readMotifs(transfac_file, remove.acc = TRUE)
    genomic.acgt <- getBackgroundFrequencies("dm3")
    pwms.denovo <- toPWM(motifs.denovo, prior = genomic.acgt)
    bg.denovo <- makeBackground(
        pwms.denovo,
        organism = "dm3",
        type = "logn",
        quick = TRUE
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pwmenrich_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pwmenrich_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pwmenrich_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PWMENRICH:", paste0("    pwmenrich: ", packageVersion("PWMEnrich"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pwmenrich_results.csv
    touch ${prefix}_pwmenrich_output.rds
    echo "BIOC_PWMENRICH:" > versions.yml
    echo "    pwmenrich: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PWMENRICH_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PWMENRICH(ch_input)

    emit:
    results  = BIOC_PWMENRICH.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PWMENRICH.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PWMENRICH.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PWMENRICH.out.versions  // channel: path(versions.yml)
}
