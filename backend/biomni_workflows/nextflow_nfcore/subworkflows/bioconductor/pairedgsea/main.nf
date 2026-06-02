#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: pairedGSEA
// pairedGSEA makes it simple to run a paired Differential Gene Expression (DGE) and Differencital Gene
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/pairedGSEA/inst/doc/User-Guide.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("pairedGSEA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PAIREDGSEA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-pairedgsea"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-pairedgsea:1.6.0--r44_0' :
        'quay.io/biocontainers/bioconductor-pairedgsea:1.6.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_pairedgsea_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_pairedgsea_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_pairedgsea_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(pairedGSEA)
    library(jsonlite)

    # --- Differential Expression and Splicing Analysis [paired_diff] ---
    # Key functions: paired_diff
    data("example_se")
    diff_results <- paired_diff(
        object = example_se,
        metadata = NULL,
        group_col = "group_nr",
        sample_col = "id",
        baseline = 1,
        case = 2,
        experiment_title = "TGFb treatment for 12h",
        store_results = FALSE
    )

    # --- Gene Set Preparation [prepare_msigdb] ---
    # Key functions: prepare_msigdb
    gene_sets <- prepare_msigdb(
        species = "Homo sapiens",
        category = "C5",
        gene_id_type = "ensembl_gene"
    )

    # --- Over-representation Analysis [paired_ora] ---
    # Key functions: paired_ora
    ora_results <- paired_ora(
        paired_diff_result = diff_results,
        gene_sets = gene_sets,
        experiment_title = NULL
    )

    # --- Visualization of GSEA Results [plot_ora] ---
    # Key functions: plot_ora
    plot_ora(
        ora_results,
        plotly = FALSE,
        pattern = "Telomer",
        cutoff = 0.05,
        lines = TRUE
    )


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_pairedgsea_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_pairedgsea_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_pairedgsea_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PAIREDGSEA:", paste0("    pairedgsea: ", packageVersion("pairedGSEA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_pairedgsea_results.csv
    touch ${prefix}_pairedgsea_output.rds
    echo "BIOC_PAIREDGSEA:" > versions.yml
    echo "    pairedgsea: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PAIREDGSEA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PAIREDGSEA(ch_input)

    emit:
    results  = BIOC_PAIREDGSEA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PAIREDGSEA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PAIREDGSEA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PAIREDGSEA.out.versions  // channel: path(versions.yml)
}
