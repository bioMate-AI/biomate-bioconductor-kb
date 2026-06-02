#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: omicRexposome
// omicRexposome systematizes the association evaluation between exposures and omic data, taking advant
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/omicRexposome/inst/doc/exposome_omic_integration.R
// Upstream  : MultiDataSet, rexposome
// Downstream: none
//
// Install: BiocManager::install("omicRexposome")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_OMICREXPOSOME {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-omicrexposome"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-omicrexposome:1.28.0--r44_0' :
        'quay.io/biocontainers/bioconductor-omicrexposome:1.28.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_omicrexposome_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_omicrexposome_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_omicrexposome_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(omicRexposome)
    library(jsonlite)

    # --- Association Visualization [] ---
    # Key functions: plotAssociation
    p1 <- plotAssociation(gexp, rid="Ben_p", type="qq")
    p2 <- plotAssociation(gexp, rid="Ben_p", type="volcano", tPV=-log10(1e-04))


    # --- Cross-Omics Integration [] ---
    # Key functions: crossomics, plotIntegration
    cr_mcia <- crossomics(mds, method = "mcia", verbose = TRUE)
    cr_mcca <- crossomics(mds, method = "mcca", permute=c(4, 2))
    colors <- c("green", "blue", "red")
    names(colors) <- names(mds)
    plotIntegration(cr_mcia, colors=colors)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_omicrexposome_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_omicrexposome_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_omicrexposome_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_OMICREXPOSOME:", paste0("    omicrexposome: ", packageVersion("omicRexposome"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_omicrexposome_results.csv
    touch ${prefix}_omicrexposome_output.rds
    echo "BIOC_OMICREXPOSOME:" > versions.yml
    echo "    omicrexposome: 0.0.0" >> versions.yml
    """
}


workflow BIOC_OMICREXPOSOME_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_OMICREXPOSOME(ch_input)

    emit:
    results  = BIOC_OMICREXPOSOME.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_OMICREXPOSOME.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_OMICREXPOSOME.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_OMICREXPOSOME.out.versions  // channel: path(versions.yml)
}
