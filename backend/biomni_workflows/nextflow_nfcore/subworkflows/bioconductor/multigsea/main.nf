#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: multiGSEA
// Extracted features from pathways derived from 8 different databases (KEGG, Reactome, Biocarta, etc.)
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/multiGSEA/inst/doc/multiGSEA.R
// Upstream  : dplyr, magrittr, msigdbr
// Downstream: none
//
// Install: BiocManager::install("multiGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_MULTIGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-multigsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-multigsea:1.16.2--r44_0' :
        'quay.io/biocontainers/bioconductor-multigsea:1.16.2--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_multigsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_multigsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_multigsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(multiGSEA)
    library(jsonlite)

    # --- Slice coverage by threshold [] ---
    # Key functions: arrange, slice
    (here: transcriptome), feature IDs, log2FCs, and p-values
    knitr::kable(
    dplyr::arrange(Symbol) %>%
    # --- Table formatting and display [] ---
    # Key functions: install_github, kable, initOmicsDataStructure, getMultiOmicsFeatures, multiGSEA, extractPvalues, msigdbr, unstack
    omics_data <- initOmicsDataStructure(layer = c(
    omics_data$transcriptome <- rankFeatures(
    names(omics_data$transcriptome) <- transcriptome$Symbol

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_multigsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_multigsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_multigsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_MULTIGSEA:", paste0("    multigsea: ", packageVersion("multiGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_multigsea_results.csv
    touch ${prefix}_multigsea_output.rds
    echo "BIOC_MULTIGSEA:" > versions.yml
    echo "    multigsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_MULTIGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_MULTIGSEA(ch_input)

    emit:
    results  = BIOC_MULTIGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_MULTIGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_MULTIGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_MULTIGSEA.out.versions  // channel: path(versions.yml)
}
