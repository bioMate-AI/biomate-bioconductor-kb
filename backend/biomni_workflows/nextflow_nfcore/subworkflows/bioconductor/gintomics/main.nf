#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: gINTomics
// gINTomics is an R package for Multi-Omics data integration and visualization. gINTomics is designed 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/gINTomics/inst/doc/gINTomics.R
// Upstream  : MultiAssayExperiment, shiny
// Downstream: none
//
// Install: BiocManager::install("gINTomics")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GINTOMICS {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gintomics"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gintomics:1.2.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gintomics:1.2.0--r44_0'}"

    input:
    tuple val(meta), path(input_file)

    output:
    tuple val(meta), path("${meta.id}_gintomics_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gintomics_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gintomics_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(gINTomics)
    library(jsonlite)

    # --- Extract Model Res [] ---
    # Key functions: extract_model_res, plot_network
    ---------------------------------------------------------------------
    data_table <- extract_model_res(multiomics_integration)
    data_table <- data_table[data_table$cov!="(Intercept)",]
    # plot_network(data_table, num_interactions = 200)
    # --- Plot Venn [] ---
    # Key functions: plot_venn
    ---------------------------------------------------------------------
    # plot_venn(data_table)
    # --- Plot Volcano [] ---
    # Key functions: plot_volcano
    ---------------------------------------------------------------------
    # plot_volcano(data_table, omics = "gene_genomic_res", cnv_met = "cnv")
    # plot_volcano(data_table, omics = "gene_genomic_res", cnv_met = "met")
    # --- Plot Ridge [] ---
    # Key functions: plot_ridge
    ---------------------------------------------------------------------
    # plot_ridge(data_table, omics = "gene_genomic_res", cnv_met = "cnv")
    # plot_ridge(data_table, omics = "gene_genomic_res", cnv_met = "met")
    # --- Run Genomic Enrich [] ---
    # Key functions: run_genomic_enrich, dot_plotly
    ---------------------------------------------------------------------
    #gen_enr <- run_genomic_enrich(multiomics_integration, qvalueCutoff = 1, pvalueCutoff = 0.05, pAdjustMethod = "none")
    #dot_plotly(gen_enr$cnv[[1]]$go)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gintomics_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gintomics_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gintomics_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GINTOMICS:", paste0("    gintomics: ", packageVersion("gINTomics"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gintomics_results.csv
    touch ${prefix}_gintomics_output.rds
    echo "BIOC_GINTOMICS:" > versions.yml
    echo "    gintomics: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GINTOMICS_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(input_file) ]

    main:
    BIOC_GINTOMICS(ch_input)

    emit:
    results  = BIOC_GINTOMICS.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GINTOMICS.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GINTOMICS.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GINTOMICS.out.versions  // channel: path(versions.yml)
}
