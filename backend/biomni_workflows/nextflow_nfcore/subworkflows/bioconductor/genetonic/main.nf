#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GeneTonic
// This package provides functionality to combine the existing pieces of the transcriptome data and res
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GeneTonic/inst/doc/GeneTonic_manual.R
// Upstream  : AnnotationDbi, DESeq2, igraph, macrophage, magrittr
// Downstream: none
//
// Install: BiocManager::install("GeneTonic")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GENETONIC {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-genetonic"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-genetonic:3.0.0--r44_0' :
        'quay.io/biocontainers/bioconductor-genetonic:3.0.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_genetonic_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_genetonic_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_genetonic_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(DESeq)
    library(DESeqDataSet)
    library(GeneTonic)
    library(GeneTonicList)
    library(jsonlite)

    # --- Enrichment Table Enhancement [] ---
    # Key functions: enhance_table
    p <- enhance_table(
        res_enrich = res_enrich_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        n_gs = 30,
        annotation_obj = anno_df,
        chars_limit = 60
    )


    # --- Gene-Geneset Visualisation [] ---
    # Key functions: gs_alluvial, ggs_graph
    alluvial_plot <- gs_alluvial(
        res_enrich = res_enrich_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        annotation_obj = anno_df,
        n_gs = 4
    )
    ggs <- ggs_graph(
        res_enrich = res_enrich_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        annotation_obj = anno_df,
        n_gs = 20
    )


    # --- Enrichment Map Analysis [] ---
    # Key functions: enrichment_map
    em <- enrichment_map(
        res_enrich = res_enrich_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        n_gs = 30,
        color_by = "z_score",
        annotation_obj = anno_df
    )


    # --- Enrichment Distillation [] ---
    # Key functions: distill_enrichment
    distilled <- distill_enrichment(
        res_enrich = res_enrich_macrophage,
        res_de = res_macrophage_IFNg_vs_naive,
        annotation_obj = anno_df,
        n_gs = 60,
        cluster_fun = "cluster_markov"
    )


    # --- Fuzzy Clustering of Gene Sets [] ---
    # Key functions: gs_fuzzyclustering
    fuzzy_subset <- gs_fuzzyclustering(
        res_enrich = res_enrich_macrophage[1:100, ],
        n_gs = 100,
        gs_ids = NULL,
        similarity_matrix = NULL,
        similarity_threshold = 0.35,
        fuzzy_seeding_initial_neighbors = 3,
        fuzzy_multilinkage_rule = 0.5
    )

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_genetonic_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_genetonic_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_genetonic_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GENETONIC:", paste0("    genetonic: ", packageVersion("GeneTonic"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_genetonic_results.csv
    touch ${prefix}_genetonic_output.rds
    echo "BIOC_GENETONIC:" > versions.yml
    echo "    genetonic: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GENETONIC_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GENETONIC(ch_input)

    emit:
    results  = BIOC_GENETONIC.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GENETONIC.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GENETONIC.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GENETONIC.out.versions  // channel: path(versions.yml)
}
