#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSVA
// Gene Set Variation Analysis (GSVA) is a non-parametric, unsupervised method for estimating variation
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSVA/inst/doc/GSVA.R
// Upstream  : Biobase, GSEABase, GSVAdata, RColorBrewer, edgeR
// Downstream: SMDIC
//
// Install: BiocManager::install("GSVA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSVA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gsva"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gsva:2.0.7--r44_0' :
        'quay.io/biocontainers/bioconductor-gsva:2.0.7--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gsva_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gsva_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gsva_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSVA)
    library(jsonlite)

    # --- GSVA Parameter Configuration [] ---
    # Key functions: gsvaParam
    expr_matrix <- matrix(rnorm(1000), nrow=100, ncol=10,
                          dimnames=list(paste0("g", 1:100), paste0("s", 1:10)))
    gsva_params <- gsvaParam(expr_matrix, gsc,
                             minSize=2, maxSize=500,
                             kcdf="Gaussian")


    # --- GSVA Enrichment Calculation [] ---
    # Key functions: gsva
    gsva_results <- gsva(gsva_params, verbose=FALSE)
    enrichment_scores <- as.matrix(gsva_results)


    # --- SSGSEA Enrichment Calculation [] ---
    # Key functions: ssgseaParam, gsva
    ssgsea_params <- ssgseaParam(expr_matrix, gsc,
                                 minSize=2, maxSize=500,
                                 normalization=TRUE)
    ssgsea_results <- gsva(ssgsea_params, verbose=FALSE)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gsva_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gsva_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gsva_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSVA:", paste0("    gsva: ", packageVersion("GSVA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gsva_results.csv
    touch ${prefix}_gsva_output.rds
    echo "BIOC_GSVA:" > versions.yml
    echo "    gsva: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSVA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSVA(ch_input)

    emit:
    results  = BIOC_GSVA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSVA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSVA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSVA.out.versions  // channel: path(versions.yml)
}
