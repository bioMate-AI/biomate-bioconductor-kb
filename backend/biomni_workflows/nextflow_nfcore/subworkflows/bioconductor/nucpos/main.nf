#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: nuCpos
// nuCpos, a derivative of NuPoP, is an R package for prediction of nucleosome positions. nuCpos calcul
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/nuCpos/inst/doc/nuCpos-intro.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("nuCpos")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_NUCPOS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-nucpos"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-nucpos:1.24.0--r44_0' :
        'quay.io/biocontainers/bioconductor-nucpos:1.24.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_nucpos_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_nucpos_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_nucpos_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HBA)
    library(jsonlite)

    # --- Nucpos Intro.Rnw:99 107 [] ---
    # Key functions: HBA
    load(system.file("extdata", "inseq.RData", package = "nuCpos"))
    HBA(inseq = inseq, species = "sc")
    for(i in 1:3) cat(substr(inseq, start = (i-1)*60+1,
        stop = (i-1)*60+60), "\n")
    load(system.file("extdata", "INSEQ_DNAString.RData",
    # --- Nucpos Intro.Rnw:135 139 [] ---
    # Key functions: localHBA
    localHBA(inseq = inseq, species = "sc")
    barplot(localHBA(inseq = inseq, species = "sc"),
        names.arg = LETTERS[1:13], xlab = "Nucleosomal subsegments",
        ylab = "local HBA", main = "Local HBA scores for inseq")

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_nucpos_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_nucpos_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_nucpos_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_NUCPOS:", paste0("    nucpos: ", packageVersion("nuCpos"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_nucpos_results.csv
    touch ${prefix}_nucpos_output.rds
    echo "BIOC_NUCPOS:" > versions.yml
    echo "    nucpos: 0.0.0" >> versions.yml
    """
}


workflow BIOC_NUCPOS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_NUCPOS(ch_input)

    emit:
    results  = BIOC_NUCPOS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_NUCPOS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_NUCPOS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_NUCPOS.out.versions  // channel: path(versions.yml)
}
