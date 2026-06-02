#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GSEAmining
// Gene Set Enrichment Analysis is a very powerful and interesting computational method that allows an 
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GSEAmining/inst/doc/GSEAmining.R
// Upstream  : none
// Downstream: none
//
// Install: BiocManager::install("GSEAmining")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GSEAMINING {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gseamining"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gseamining:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gseamining:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gseamining_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gseamining_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gseamining_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GSEAmining)
    library(jsonlite)

    # --- Gene Set Clustering [] ---
    # Key functions: gm_clust
    gs.cl <- gm_clust(gs.filt)


    # --- Dendrogram Visualization [] ---
    # Key functions: gm_dendplot
    gm_dendplot(
        gs.filt,
        gs.cl,
        col_pos = "orange",
        col_neg = "black",
        rect = TRUE,
        dend_len = 20,
        rect_len = 2
    )


    # --- Enriched Terms Identification [] ---
    # Key functions: gm_enrichterms
    terms_clustered <- gm_enrichterms(
        gs.filt,
        gs.cl,
        clust = TRUE
    )
    terms_unclustered <- gm_enrichterms(
        gs.filt,
        gs.cl,
        clust = FALSE,
        col_pos = "chocolate3",
        col_neg = "skyblue3"
    )


    # --- Core Genes Enrichment [] ---
    # Key functions: gm_enrichcores
    cores_enriched <- gm_enrichcores(
        gs.filt,
        gs.cl
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gseamining_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gseamining_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gseamining_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GSEAMINING:", paste0("    gseamining: ", packageVersion("GSEAmining"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gseamining_results.csv
    touch ${prefix}_gseamining_output.rds
    echo "BIOC_GSEAMINING:" > versions.yml
    echo "    gseamining: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GSEAMINING_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GSEAMINING(ch_input)

    emit:
    results  = BIOC_GSEAMINING.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GSEAMINING.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GSEAMINING.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GSEAMINING.out.versions  // channel: path(versions.yml)
}
