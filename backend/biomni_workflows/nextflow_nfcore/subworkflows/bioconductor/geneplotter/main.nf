#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: geneplotter
// Functions for plotting genomic data
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/geneplotter/inst/doc/byChroms.R
// Upstream  : annotate
// Downstream: HD2013SGI, Hiiragi2013, maEndToEnd
//
// Install: BiocManager::install("geneplotter")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENEPLOTTER {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-geneplotter"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-geneplotter:1.84.0--r44_0' :
        'quay.io/biocontainers/bioconductor-geneplotter:1.84.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_geneplotter_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_geneplotter_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_geneplotter_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(geneplotter)
    library(jsonlite)

    # --- unlist [] ---
    # Key functions: unlist
    library("annotate")
    library("hu6800.db")
    lens <- unlist(eapply(hu6800CHR, length))
    # --- split [] ---
    # Key functions: split
    strand <- as.list(hu6800CHRLOC)
    splits <- split(strand, chrs2)
    length(splits)
    # --- build Chrom Location [] ---
    # Key functions: buildChromLocation
    newChrClass <- buildChromLocation("hu6800")
    # --- c Plot [] ---
    # Key functions: cPlot
    library(geneplotter)
    newChrClass@chromLocs <- newChrClass@chromLocs[order(as.numeric(names(newChrClass@chromLocs)))]
    newChrClass@chromInfo <- newChrClass@chromInfo[order(as.numeric(names(newChrClass@chromInfo)))]

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_geneplotter_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_geneplotter_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_geneplotter_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENEPLOTTER:", paste0("    geneplotter: ", packageVersion("geneplotter"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_geneplotter_results.csv
    touch ${prefix}_geneplotter_output.rds
    echo "BIOC_GENEPLOTTER:" > versions.yml
    echo "    geneplotter: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENEPLOTTER_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENEPLOTTER(ch_input)

    emit:
    results  = BIOC_GENEPLOTTER.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENEPLOTTER.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENEPLOTTER.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENEPLOTTER.out.versions  // channel: path(versions.yml)
}
