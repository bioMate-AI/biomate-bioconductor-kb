#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: ggtreeExtra
// 'ggtreeExtra' extends the method for mapping and visualizing associated data on phylogenetic tree us
//
// Source : https://yulab-smu.top/treedata-book/chapter10.html
// Upstream  : ggnewscale, ggplot2, ggstar, ggtree, treeio
// Downstream: none
//
// Install: BiocManager::install("ggtreeExtra")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_GGTREEEXTRA {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-ggtreeextra"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-ggtreeextra:1.16.0--r44_0' :
        'quay.io/biocontainers/bioconductor-ggtreeextra:1.16.0--r44_0'}"

    input:
    tuple val(meta), path(phyloseq)

    output:
    tuple val(meta), path("${meta.id}_ggtreeextra_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_ggtreeextra_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_ggtreeextra_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(Cheek)
    library(Nose)
    library(Plaque)
    library(Stool)
    library(Tongue)
    library(jsonlite)

    # --- Aligning Graphs to the Tree Based on a Tree Structure [] ---
    # Key functions: data, prune_taxa, taxa_sums, sample_data, get_variable, merge_samples, rarefy_even_depth, tax_glom
    library(ggtreeExtra)
    library(ggtree)
    library(phyloseq)
    library(dplyr)
    
    data("GlobalPatterns")
    GP <- GlobalPatterns
    GP <- prune_taxa(taxa_sums(GP) > 600, GP)
    sample_data(GP)$human <- get_variable(GP, "SampleType") %in%
                                  c("Feces", "Skin")
    mergedGP <- merge_samples(GP, "SampleType")
    mergedGP <- rarefy_even_depth(mergedGP,rngseed=394582)
    # --- Aligning Multiple Graphs to the Tree for Multi-dimensional Data [] ---
    # Key functions: df_tippoint, df_ring_heatmap, df_barplot_attr, factor, Stool, Cheek, Plaque, Tongue
    library(ggtreeExtra)
    library(ggtree)
    library(treeio)
    library(tidytree)
    library(ggstar)
    library(ggplot2)
    library(ggnewscale)
    library(TDbook)
    
    # load data from TDbook, including tree_hmptree,
    # df_tippoint (the abundance and types of microbes),
    # df_ring_heatmap (the abundance of microbes at different body sites),
    # --- Examples for Population Genetics [] ---
    # Key functions: select, factor, melt, aggregate
    library(ggtree)
    library(ggtreeExtra)
    library(ggplot2)
    library(ggnewscale)
    library(reshape2)
    library(dplyr)
    library(tidytree)
    library(ggstar)
    library(TDbook)
    
    # load tr and dat from the TDbook package
    dat <- df_Candidaauris_data

    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_ggtreeextra_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_ggtreeextra_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_ggtreeextra_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_GGTREEEXTRA:", paste0("    ggtreeextra: ", packageVersion("ggtreeExtra"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_ggtreeextra_results.csv
    touch ${prefix}_ggtreeextra_output.rds
    echo "BIOC_GGTREEEXTRA:" > versions.yml
    echo "    ggtreeextra: 0.0.0" >> versions.yml
    """
}


workflow BIOC_GGTREEEXTRA_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(phyloseq) ]

    main:
    BIOC_GGTREEEXTRA(ch_input)

    emit:
    results  = BIOC_GGTREEEXTRA.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_GGTREEEXTRA.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_GGTREEEXTRA.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_GGTREEEXTRA.out.versions  // channel: path(versions.yml)
}
