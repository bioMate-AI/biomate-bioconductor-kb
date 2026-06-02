#!/usr/bin/env nextflow
// ============================================================
// Bioconductor module: phyloseq
// phyloseq provides a set of classes and tools to facilitate the import, storage, analysis, and graphi
//
// Source : https://bioconductor.org/packages/3.20/bioc/vignettes/phyloseq/inst/doc/phyloseq-analysis.R
// Upstream  : genefilter, ggplot2, reshape2
// Downstream: microbiome, SIAMCAT, MiscMetabar, phyloseqGraphTest
//
// Install: BiocManager::install("phyloseq")
// ============================================================

nextflow.enable.dsl = 2

process BIOC_PHYLOSEQ {
    tag "${meta.id}"
    label 'process_medium'

    conda "bioconductor-phyloseq"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container ?
        'https://depot.galaxyproject.org/singularity/bioconductor-phyloseq:1.50.0--r44_0' :
        'quay.io/biocontainers/bioconductor-phyloseq:1.50.0--r44_0'}"

    input:
    tuple val(meta), path(count_data)

    output:
    tuple val(meta), path("${meta.id}_phyloseq_results.csv"),  emit: results
    tuple val(meta), path("${meta.id}_phyloseq_output.rds"),   emit: rds
    tuple val(meta), path("${meta.id}_phyloseq_plots.pdf"),    emit: plots, optional: true
    path "versions.yml",                                            emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args   = task.ext.args   ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    #!/usr/bin/env Rscript
    library(phyloseq)
    library(jsonlite)

    # --- Taxonomic and Sample Filtering ---
    # Key functions: subset_taxa, prune_taxa, taxa_sums, tax_table
    data("GlobalPatterns")
    top_otus <- names(sort(taxa_sums(GlobalPatterns), TRUE)[1:200])
    gp_subset <- prune_taxa(top_otus, GlobalPatterns)
    top_phyla <- sort(tapply(taxa_sums(gp_subset),
        tax_table(gp_subset)[, "Phylum"], sum), decreasing = TRUE)[1:5]
    gp_filtered <- subset_taxa(gp_subset,
        Phylum %in% names(top_phyla))

    # --- Alpha Diversity Analysis ---
    # Key functions: plot_richness
    data("GlobalPatterns")
    alpha_meas <- c("Observed", "Chao1", "Shannon", "Simpson")
    richness_plot <- plot_richness(GlobalPatterns,
        x = "SampleType",
        measures = alpha_meas)

    # --- Ordination and Dimension Reduction ---
    # Key functions: ordinate, plot_scree, plot_ordination
    data("GlobalPatterns")
    gp_pcoa <- ordinate(GlobalPatterns,
        method = "PCoA",
        distance = "bray")
    scree_p <- plot_scree(gp_pcoa,
        title = "Scree Plot")
    ord_p <- plot_ordination(GlobalPatterns,
        gp_pcoa,
        type = "samples",
        color = "SampleType")

    # --- Taxonomic Abundance Visualization ---
    # Key functions: plot_bar, plot_heatmap, subset_taxa
    data("GlobalPatterns")
    gp_cren <- subset_taxa(GlobalPatterns, Phylum == "Crenarchaeota")
    bar_p <- plot_bar(gp_cren,
        x = "SampleType",
        fill = "Family")
    heat_p <- plot_heatmap(gp_cren,
        method = "NMDS",
        distance = "bray",
        sample.label = "SampleType",
        taxa.label = "Family")

    # --- Phylogenetic Tree and Network Visualization ---
    # Key functions: subset_taxa, plot_tree, plot_net
    data("GlobalPatterns")
    gp_chlam <- subset_taxa(GlobalPatterns, Phylum == "Chlamydiae")
    tree_p <- plot_tree(gp_chlam,
        color = "SampleType",
        shape = "Family",
        label.tips = "Genus",
        size = "Abundance")
    net_p <- plot_net(gp_chlam,
        maxdist = 0.4,
        color = "SampleType")


    # --- Save outputs ---
    if (exists("results_df") && is.data.frame(results_df)) {
        write.csv(results_df, "${prefix}_phyloseq_results.csv", row.names = TRUE)
    } else {
        write.csv(data.frame(status = "completed"), "${prefix}_phyloseq_results.csv")
    }
    if (exists("result_obj")) {
        saveRDS(result_obj, "${prefix}_phyloseq_output.rds")
    }

    # --- versions.yml ---
    writeLines(
        c("BIOC_PHYLOSEQ:", paste0("    phyloseq: ", packageVersion("phyloseq"))),
        "versions.yml"
    )
    """

    stub:
    def prefix = task.ext.prefix ?: "${meta.id}"
    """
    touch ${prefix}_phyloseq_results.csv
    touch ${prefix}_phyloseq_output.rds
    echo "BIOC_PHYLOSEQ:" > versions.yml
    echo "    phyloseq: 0.0.0" >> versions.yml
    """
}


workflow BIOC_PHYLOSEQ_WORKFLOW {
    take:
    ch_input  // channel: [ val(meta), path(count_data) ]

    main:
    BIOC_PHYLOSEQ(ch_input)

    emit:
    results  = BIOC_PHYLOSEQ.out.results   // channel: [ val(meta), path(csv) ]
    rds      = BIOC_PHYLOSEQ.out.rds       // channel: [ val(meta), path(rds) ]
    plots    = BIOC_PHYLOSEQ.out.plots     // channel: [ val(meta), path(pdf) ] (optional)
    versions = BIOC_PHYLOSEQ.out.versions  // channel: path(versions.yml)
}
