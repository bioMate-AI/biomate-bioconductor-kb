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
    library(SummarizedExperiment)
    library(jsonlite)

    # --- data input expr [] ---
    # Key functions: is_data_expr
    data("kuehne_expr")
    kuehne_expr = read.table(<path_to_file>, header=TRUE, row.names=1)
    ncol(kuehne_expr)
    # --- data input SummarizedExperiment [] ---
    # Key functions: SummarizedExperiment, metadata

    # --- filter_low_var [] ---
    # Key functions: filter_low_var
    kuehne_expr_filtered <- filter_low_var(kuehne_expr, pct = 0.7, type = "median")
    ncol(kuehne_expr_filtered)
    # --- build_net [] ---
    # Key functions: build_net

    # --- modules detection [] ---
    # Key functions: detect_modules

    # --- bipartite graph merge [] ---
    # Key functions: plot_modules_merge
    length(unique(modules$modules_premerge))
    length(unique(modules$modules))
    # --- plot modules gene distribution [] ---
    # Key functions: ggplot, aes, ylab, xlab
    ggplot2::ggplot(data.frame(modules$modules %>% stack),
    ggplot2::aes(x = ind)) + ggplot2::stat_count() +
    ggplot2::ylab("Number of genes") +
    # --- plot module profile [] ---
    # Key functions: plot_expression_profiles
    plot_expression_profiles(kuehne_expr_filtered, modules$modules)
    # --- modules enrichment [] ---
    # Key functions: bio_enrich, plot_enrichment
    enrichment <- bio_enrich(modules$modules)
    plot_enrichment(enrichment)
    # --- modules phenotype [] ---
    # Key functions: associate_phenotype, colData, plot_modules_phenotype
    phenotype_association <- associate_phenotype(
    kuehne_traits %>% dplyr::select(Condition, Age, Slide))
    # --- build_graph_from_sq_mat [] ---
    # Key functions: build_graph_from_sq_mat, plot_module
    graph <- build_graph_from_sq_mat(net$network[module_example, module_example])
    # --- get_sub_clusters [] ---
    # Key functions: get_sub_clusters, plot_module
    sub_clusters <- get_sub_clusters(net_mod_2)
    # --- condition comparison [] ---
    # Key functions: compare_conditions

    # --- plot comparison stats [] ---
    # Key functions: plot_comparison_stats
    plot_comparison_stats(comparison$result$young$old$p.values)

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
