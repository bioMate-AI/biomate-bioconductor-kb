#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: projectR
// Functions for the projection of data into the spaces defined by PCA, CoGAPS, NMF, correlation, and c
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/projectR/inst/doc/projectR.R
// Upstream  : cowplot, fgsea, ggplot2, gplots, gridExtra
// Downstream: none
//
// Install: BiocManager::install("projectR")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PROJECTR {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-projectr"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-projectr:1.22.0--r44_0' :
        'quay.io/biocontainers/bioconductor-projectr:1.22.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_projectr_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_projectr_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_projectr_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(projectR)
    library(jsonlite)

    # --- PCA Projection [PCA Projection] ---
    # Key functions: projectR
    data(p.RNAseq6l3c3t)
    data(p.ESepiGen4c1l)
    pc_source <- prcomp(t(p.RNAseq6l3c3t))
    PCA2ESepi <- projectR(
        data = p.ESepiGen4c1l$mRNA.Seq,
        loadings = pc_source,
        full = TRUE,
        dataNames = map.ESepiGen4c1l[["GeneSymbols"]]
    )

    # --- CoGAPS Pattern Projection [CoGAPS Pattern Projection] ---
    # Key functions: projectR
    data(p.ESepiGen4c1l)
    AP_data <- get(data("AP.RNAseq6l3c3t"))
    AP_matrix <- AP_data$Amean
    NMF2ESepi <- projectR(
        data = p.ESepiGen4c1l$mRNA.Seq,
        loadings = AP_matrix,
        full = TRUE,
        dataNames = map.ESepiGen4c1l[["GeneSymbols"]]
    )

    # --- Gene Correlation Analysis [Gene Correlation Analysis] ---
    # Key functions: correlateR
    data(p.RNAseq6l3c3t)
    cor2T <- correlateR(
        genes = "T",
        dat = p.RNAseq6l3c3t,
        threshtype = "N",
        threshold = 10,
        absR = TRUE
    )
    cor_matrix <- cor2T@corM

    # --- Correlation Space Projection [Correlation Space Projection] ---
    # Key functions: projectR, correlateR
    data(p.RNAseq6l3c3t)
    data(p.ESepiGen4c1l)
    cor2T <- correlateR(
        genes = "T",
        dat = p.RNAseq6l3c3t,
        threshtype = "N",
        threshold = 10,
        absR = TRUE
    )
    cor2ESepi <- projectR(
        data = p.ESepiGen4c1l$mRNA.Seq,
        loadings = cor2T[[1]],
        full = FALSE,
        dataNames = map.ESepiGen4c1l$GeneSymbols
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_projectr_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_projectr_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_projectr_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PROJECTR:", paste0("    projectr: ", packageVersion("projectR"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_projectr_results.csv
    touch ${prefix}_projectr_output.rds
    echo "BIOC_PROJECTR:" > versions.yml
    echo "    projectr: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PROJECTR_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PROJECTR(ch_input)

    emit:
    results  = BIOC_PROJECTR.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PROJECTR.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PROJECTR.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PROJECTR.out.versions  // channel: path(versions.yml)
}
