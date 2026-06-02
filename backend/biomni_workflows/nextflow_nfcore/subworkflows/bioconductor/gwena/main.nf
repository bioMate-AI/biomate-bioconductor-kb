#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: GWENA
// The development of high-throughput sequencing led to increased use of co-expression analysis to go b
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/GWENA/inst/doc/GWENA_guide.R
// Upstream  : magrittr
// Downstream: none
//
// Install: BiocManager::install("GWENA")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GWENA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-gwena"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-gwena:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-gwena:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_gwena_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_gwena_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_gwena_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(GWENA)
    library(SummarizedExperiment)
    library(jsonlite)

    # --- Co-expression Network Construction [] ---
    # Key functions: build_net
    net <- build_net(kuehne_expr_filtered,
                     cor_func = "spearman",
                     n_threads = 2)
    power_selected <- net$metadata$power


    # --- Module Detection and Functional Enrichment [] ---
    # Key functions: detect_modules, bio_enrich, plot_enrichment
    modules <- detect_modules(kuehne_expr_filtered,
                              net$network,
                              detailled_result = TRUE,
                              merge_threshold = 0.25)
    enrichment <- bio_enrich(modules$modules)
    plot_enrichment(enrichment)


    # --- Phenotype Association Analysis [] ---
    # Key functions: associate_phenotype, plot_modules_phenotype
    phenotype_association <- associate_phenotype(
        modules$modules_eigengenes,
        kuehne_traits)
    plot_modules_phenotype(phenotype_association)


    # --- Module Network Visualization [] ---
    # Key functions: build_graph_from_sq_mat, plot_module, get_sub_clusters
    net_mod <- net$network[modules$modules$`2`, modules$modules$`2`]
    graph <- build_graph_from_sq_mat(net_mod)
    sub_clusters <- get_sub_clusters(net_mod)
    layout_mod <- plot_module(graph,
                              upper_weight_th = 0.99,
                              groups = sub_clusters)

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_gwena_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_gwena_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_gwena_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GWENA:", paste0("    gwena: ", packageVersion("GWENA"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_gwena_results.csv
    touch ${prefix}_gwena_output.rds
    echo "BIOC_GWENA:" > versions.yml
    echo "    gwena: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GWENA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_GWENA(ch_input)

    emit:
    results  = BIOC_GWENA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GWENA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GWENA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GWENA.out.versions  // channel: path(versions.yml)
}
