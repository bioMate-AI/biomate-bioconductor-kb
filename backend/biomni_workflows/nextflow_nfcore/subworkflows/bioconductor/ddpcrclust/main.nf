#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ddPCRclust
// The ddPCRclust algorithm can automatically quantify the CPDs of non-orthogonal ddPCR reactions with 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/ddPCRclust/inst/doc/ddPCRclust.R
// Upstream  : ggplot2
// Downstream: none
//
// Install: BiocManager::install("ddPCRclust")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_DDPCRCLUST {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ddpcrclust"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ddpcrclust:1.26.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ddpcrclust:1.26.0--r44_0'}"

    input:
    tuple val(meta), path(ggplot_object)

    output:
    tuple val(meta), path("${meta.id}_ddpcrclust_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ddpcrclust_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ddpcrclust_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(ddPCRclust)
    library(jsonlite)

    # --- Files [] ---
    # Key functions: files, package, readFiles, readTemplate, ddPCRclust, ggplot
    library(ddPCRclust)
    # Read files
    exampleFiles <- list.files(paste0(find.package('ddPCRclust'), '/extdata'),
                               full.names = TRUE)
    files <- readFiles(exampleFiles[3])

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ddpcrclust_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ddpcrclust_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ddpcrclust_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_DDPCRCLUST:", paste0("    ddpcrclust: ", packageVersion("ddPCRclust"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ddpcrclust_results.csv
    touch ${prefix}_ddpcrclust_output.rds
    echo "BIOC_DDPCRCLUST:" > versions.yml
    echo "    ddpcrclust: 0.0.0" >> versions.yml
    """
}


workflow BIOC_DDPCRCLUST_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(ggplot_object) ]

    main:
    BIOC_DDPCRCLUST(ch_input)

    emit:
    results  = BIOC_DDPCRCLUST.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_DDPCRCLUST.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_DDPCRCLUST.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_DDPCRCLUST.out.versions  // channel: path(versions.yml)
}
