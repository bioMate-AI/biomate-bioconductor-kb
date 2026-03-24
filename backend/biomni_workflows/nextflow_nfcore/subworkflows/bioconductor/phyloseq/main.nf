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

    # --- Prune rare taxa from phyloseq object [] ---
    # Key functions: theme_set, prune_taxa, get_variable, sample_data, subset_taxa
    data(GlobalPatterns)
    topsp <- names(sort(taxa_sums(GlobalPatterns), TRUE)[1:200])
    GP    <- prune_taxa(topsp, GlobalPatterns)
    # --- Get taxonomic rank names [] ---
    # Key functions: rank_names, prune_taxa, sample_variables
    par(mar = c(10, 4, 4, 2) + 0.1) # make more room on bottom margin
    barplot(sort(taxa_sums(enterotype), TRUE)[1:N]/nsamples(enterotype), las=2)
    rank_names(enterotype)
    # --- Subset taxa by criteria [] ---
    # Key functions: subset_taxa, ordinate, plot_scree
    data("GlobalPatterns")
    gpac <- subset_taxa(GlobalPatterns, Phylum=="Crenarchaeota")
    (p <- plot_heatmap(gpac, "NMDS", "bray", "SampleType", "Family"))
    # --- Visualize phylogenetic tree [] ---
    # Key functions: plot_tree, plot_bar, plot_net, plot_scree, plot_ordination, facet_wrap, melt, ggplot
    p1  <- plot_ordination(GP, gpca, "species", color="Phylum")
    (p1 <- ggplot(p1$data, p1$mapping) + geom_point(size=5, alpha=0.5) +
    facet_wrap(~Phylum) +  scale_colour_hue(guide = FALSE) )
    # --- Scatter plot visualization [] ---
    # Key functions: geom_point, geom_line, facet_wrap, distance
    (p12 <- plot_ordination(GlobalPatterns, GloPa.pcoa, "samples", color="SampleType") +
    geom_point(size=5) + geom_path() + scale_colour_hue(guide = FALSE) )
    (p13 <- plot_ordination(GlobalPatterns, GloPa.pcoa, "samples", axes=c(1, 3),

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
