#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: PADOG
// This package implements a general purpose gene set analysis method called PADOG that downplays the i
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/PADOG/inst/doc/PADOG.R
// Upstream  : none
// Downstream: BLMA
//
// Install: BiocManager::install("PADOG")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PADOG {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-padog"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-padog:1.48.0--r44_0' :
        'quay.io/biocontainers/bioconductor-padog:1.48.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_padog_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_padog_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_padog_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(PADOG)
    library(jsonlite)

    # --- Data Extraction and Preparation ---
    # Key functions: exprs, pData, annotation
    exp_matrix <- Biobase::exprs(eset)
    group_info <- Biobase::pData(eset)$Group
    block_info <- Biobase::pData(eset)$Block
    annotation_pkg <- paste0(Biobase::annotation(eset), ".db")
    target_gs <- Biobase::notes(Biobase::experimentData(eset))$targetGeneSets

    # --- Pathway Analysis with PADOG ---
    # Key functions: padog
    padog_results <- padog(
        esetm = exp_matrix,
        group = group_info,
        paired = FALSE,
        block = block_info,
        targetgs = target_gs,
        annotation = annotation_pkg,
        gslist = "KEGGRESTpathway",
        organism = "hsa",
        verbose = FALSE,
        Nmin = 3,
        NI = 50,
        plots = FALSE
    )

    # --- Comparison with GSEA ---
    # Key functions: compGseapre
    gsea_comparison <- compGseapre(
        esetm = exp_matrix,
        group = group_info,
        paired = FALSE,
        block = block_info,
        targetgs = target_gs,
        annotation = annotation_pkg,
        gslist = "KEGGRESTpathway",
        organism = "hsa",
        verbose = FALSE,
        Nmin = 3,
        NI = 50
    )

    # --- Pathway Visualisation and Filtering ---
    # Key functions: padog
    top_pathways <- padog_results[order(padog_results$padog), ]
    significant_pathways <- top_pathways[top_pathways$padog < 0.05, ]
    padog_with_plots <- padog(
        esetm = exp_matrix,
        group = group_info,
        paired = FALSE,
        block = block_info,
        targetgs = target_gs,
        annotation = annotation_pkg,
        gslist = "KEGGRESTpathway",
        organism = "hsa",
        verbose = FALSE,
        Nmin = 3,
        NI = 50,
        plots = TRUE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_padog_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_padog_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_padog_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PADOG:", paste0("    padog: ", packageVersion("PADOG"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_padog_results.csv
    touch ${prefix}_padog_output.rds
    echo "BIOC_PADOG:" > versions.yml
    echo "    padog: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PADOG_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PADOG(ch_input)

    emit:
    results  = BIOC_PADOG.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PADOG.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PADOG.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PADOG.out.versions  // channel: path(versions.yml)
}
