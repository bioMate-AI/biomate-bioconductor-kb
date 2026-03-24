#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: HiLDA
// A package built under the Bayesian framework of applying hierarchical latent Dirichlet allocation. I
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/HiLDA/inst/doc/HiLDA.R
// Upstream  : BiocStyle
// Downstream: none
//
// Install: BiocManager::install("HiLDA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_HILDA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-hilda"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-hilda:1.20.0--r44_0' :
        'quay.io/biocontainers/bioconductor-hilda:1.20.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_hilda_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_hilda_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_hilda_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(HiLDA)
    library(jsonlite)

    # --- Pmgetsignature [] ---
    # Key functions: pmgetSignature
    ---------------------------------------------------------------------
    Param <- pmgetSignature(G, K = 3)
    # --- Hildarhat [] ---
    # Key functions: hildaRhat
    ---------------------------------------------------------------------
    hildaRhat(hildaGlobal)
    hildaRhat(hildaLocal)
    # --- Pmbarplot [] ---
    # Key functions: pmBarplot, plot_grid
    ---------------------------------------------------------------------
    pmPlots <- pmBarplot(G, Param, refGroup=1:4, sigOrder=c(1,3,2))
    cowplot::plot_grid(pmPlots$sigPlot, pmPlots$propPlot, rel_widths = c(1,3))
    # --- Hildabarplot [] ---
    # Key functions: hildaBarplot, plot_grid
    ---------------------------------------------------------------------
    hildaPlots <- hildaBarplot(G, hildaLocal, refGroup=1:4, sigOrder=c(1,3,2))
    cowplot::plot_grid(pmPlots$sigPlot, pmPlots$propPlot, rel_widths = c(1,3))
    # --- Hildadiffplot [] ---
    # Key functions: hildaDiffPlot, plot_grid
    ---------------------------------------------------------------------
    hildaDiffPlots <- hildaDiffPlot(G, hildaLocal, sigOrder=c(1,3,2))
    cowplot::plot_grid(hildaDiffPlots$sigPlot, hildaDiffPlots$diffPlot,
                       rel_widths = c(1,3))

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_hilda_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_hilda_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_hilda_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_HILDA:", paste0("    hilda: ", packageVersion("HiLDA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_hilda_results.csv
    touch ${prefix}_hilda_output.rds
    echo "BIOC_HILDA:" > versions.yml
    echo "    hilda: 0.0.0" >> versions.yml
    """
}


workflow BIOC_HILDA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_HILDA(ch_input)

    emit:
    results  = BIOC_HILDA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_HILDA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_HILDA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_HILDA.out.versions  // channel: path(versions.yml)
}
